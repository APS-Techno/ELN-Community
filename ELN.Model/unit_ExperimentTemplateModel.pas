unit unit_ExperimentTemplateModel;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_ExperimentTemplate,
  unit_Item,
  unit_ItemTypes,
  unit_ActionType,
  unit_Project,
  unit_ProjectAccessPolicy,
  unit_ELNDB_Dictionary;

type
  EWikiFolderExists = class(Exception);

  TExperimentTemplateModel = class
  private
    FManager: TObjectManager;
    FAccess: IProjectAccessPolicy;
    FDic: TExperimentTemplateDictionary;
    procedure CreateChildren(ParentId, ProjectId, FolderId, UserId: Integer;
      ChildrenArr: TJSONArray;
      var FirstItemCreated: TItem);
    function CreateItemNode(ParentId, ProjectId, FolderId, UserId: Integer;
      ItemObj: TJSONObject; DefaultLevel: TItemLevel): TItem;
    procedure CreateFolderNode(ProjectId, ParentFolderId, UserId: Integer;
      FolderObj: TJSONObject; var FirstItemCreated: TItem);
    function ApplyFolderRoot(RootObj: TJSONObject;
      ProjectId, ParentFolderId, UserId: Integer;
      const TitleOverride: string): TItem;
    function FindFolderByTitle(ProjectId, ParentFolderId: Integer;
      const Title: string): TFolder;
    procedure ConvertIdsToNames(Node: TJSONObject);
    procedure ConvertNamesToIds(Node: TJSONObject; Warnings: TStringList);
    function FindActionTypeByName(const Name: string): Integer;
  public
    constructor Create(Manager: TObjectManager; const Access: IProjectAccessPolicy);
    destructor Destroy; override;

    // CRUD
    function AddTemplate(const Name, Description, Category, StructureJSON: string;
      CreatedBy: Integer): TExperimentTemplate;
    procedure UpdateTemplate(Template: TExperimentTemplate);
    procedure DeleteTemplate(TemplateId: Integer);
    function GetAllTemplates: TExperimentTemplates;
    function GetTemplate(TemplateId: Integer): TExperimentTemplate;
    function FindTemplateByName(const Name: string): Integer;
    function DuplicateTemplate(TemplateId, CreatedBy: Integer): TExperimentTemplate;

    // Apply template — creates a Proc with children in the given project/folder
    function ApplyTemplate(TemplateId, ProjectId, FolderId, UserId: Integer;
      const TitleOverride: string = ''): TItem;

    // Export template to .elntemplate JSON file
    procedure ExportTemplateToFile(TemplateId: Integer; const FilePath: string);

    // Import template from .elntemplate JSON file
    function ImportTemplateFromFile(const FilePath: string; CreatedBy: Integer;
      out Warnings: string): TExperimentTemplate;
  end;

implementation

uses
  Aurelius.Criteria.Base,
  unit_AuditLog,
  unit_AuditHelper,
  unit_ProjectModel,
  unit_TimeHelper;

{ TExperimentTemplateModel }

constructor TExperimentTemplateModel.Create(Manager: TObjectManager;
  const Access: IProjectAccessPolicy);
begin
  inherited Create;
  if Access = nil then
    raise EArgumentNilException.Create('Access');
  FManager := Manager;
  FAccess := Access;
  FDic := TExperimentTemplateDictionary.Create;
end;

destructor TExperimentTemplateModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TExperimentTemplateModel.AddTemplate(const Name, Description, Category,
  StructureJSON: string; CreatedBy: Integer): TExperimentTemplate;
begin
  Result := TExperimentTemplate.Create;
  Result.Name := Name;
  Result.Description := Description;
  Result.Category := Category;
  Result.StructureJSON := StructureJSON;
  Result.CreatedBy := CreatedBy;
  Result.CreatedDate := UTCNow;
  FManager.Save(Result);
  FManager.Flush;
end;

procedure TExperimentTemplateModel.UpdateTemplate(Template: TExperimentTemplate);
begin
  Template.ModifiedDate := UTCNow;
  FManager.Flush;
end;

procedure TExperimentTemplateModel.DeleteTemplate(TemplateId: Integer);
var
  Template: TExperimentTemplate;
begin
  Template := FManager.Find<TExperimentTemplate>(TemplateId);
  if Assigned(Template) then
  begin
    FManager.Remove(Template);
    FManager.Flush;
  end;
end;

function TExperimentTemplateModel.GetAllTemplates: TExperimentTemplates;
begin
  Result := FManager.Find<TExperimentTemplate>
    .OrderBy(FDic.Name)
    .List;
end;

function TExperimentTemplateModel.GetTemplate(TemplateId: Integer): TExperimentTemplate;
begin
  Result := FManager.Find<TExperimentTemplate>(TemplateId);
end;

function TExperimentTemplateModel.FindTemplateByName(const Name: string): Integer;
var
  List: TExperimentTemplates;
  I: Integer;
begin
  Result := 0;
  List := FManager.Find<TExperimentTemplate>.List;
  try
    for I := 0 to List.Count - 1 do
      if SameText(List[I].Name, Name) then
      begin
        Result := List[I].Id;
        Break;
      end;
  finally
    List.Free;
  end;
end;

function TExperimentTemplateModel.DuplicateTemplate(TemplateId, CreatedBy: Integer): TExperimentTemplate;
var
  Source: TExperimentTemplate;
begin
  Result := nil;
  Source := FManager.Find<TExperimentTemplate>(TemplateId);
  if not Assigned(Source) then Exit;

  Result := TExperimentTemplate.Create;
  Result.Name := Source.Name + ' (Copy)';
  Result.Description := Source.Description;
  Result.Category := Source.Category;
  Result.StructureJSON := Source.StructureJSON;
  Result.CreatedBy := CreatedBy;
  Result.CreatedDate := UTCNow;
  FManager.Save(Result);
  FManager.Flush;
end;

function TExperimentTemplateModel.CreateItemNode(ParentId, ProjectId, FolderId,
  UserId: Integer; ItemObj: TJSONObject; DefaultLevel: TItemLevel): TItem;
var
  ChildLevel: TItemLevel;
  ChildType: TItemType;
  ActionTypeId: Integer;
  ManagedActionType: TActionType;
  SubChildren: TJSONArray;
  ChildFirstItem: TItem;
begin
  ChildLevel := TItemLevel(ItemObj.GetValue<Integer>('level', Ord(DefaultLevel)));
  ChildType  := TItemType(ItemObj.GetValue<Integer>('type', Ord(TItemType.Other)));

  Result := TItem.Create;
  Result.Title       := ItemObj.GetValue<string>('title', 'Untitled');
  Result.Level       := ChildLevel;
  Result.Type_       := ChildType;
  Result.Parent      := ParentId;
  Result.ProjectID   := ProjectId;
  Result.FolderID    := FolderId;
  Result.CreatedDate := UTCNow;
  Result.CreatedBy   := UserId;
  Result.Expanded    := True;

  ActionTypeId := ItemObj.GetValue<Integer>('actionTypeId', 0);
  if ActionTypeId > 0 then
  begin
    ManagedActionType := FManager.Find<TActionType>(ActionTypeId);
    if Assigned(ManagedActionType) then
      Result.ActionType := ManagedActionType;
  end;

  FManager.Save(Result);
  FManager.Flush;
  FManager.Evict(Result);

  if ItemObj.TryGetValue<TJSONArray>('children', SubChildren) then
  begin
    ChildFirstItem := nil;  // discard — item-root templates surface Result directly
    CreateChildren(Result.Id, ProjectId, FolderId, UserId, SubChildren, ChildFirstItem);
  end;
end;

procedure TExperimentTemplateModel.CreateChildren(ParentId, ProjectId, FolderId,
  UserId: Integer; ChildrenArr: TJSONArray; var FirstItemCreated: TItem);
var
  I: Integer;
  ChildObj, Inner: TJSONObject;
  Created: TItem;
begin
  for I := 0 to ChildrenArr.Count - 1 do
  begin
    ChildObj := ChildrenArr.Items[I] as TJSONObject;

    if ChildObj.TryGetValue<TJSONObject>('folder', Inner) then
      CreateFolderNode(ProjectId, FolderId, UserId, Inner, FirstItemCreated)
    else if ChildObj.TryGetValue<TJSONObject>('item', Inner) then
    begin
      Created := CreateItemNode(ParentId, ProjectId, FolderId, UserId, Inner, TItemLevel.Item);
      if not Assigned(FirstItemCreated) then FirstItemCreated := Created;
    end
    else if ChildObj.TryGetValue<TJSONObject>('proc', Inner) then
    begin
      Created := CreateItemNode(ParentId, ProjectId, FolderId, UserId, Inner, TItemLevel.Proc);
      if not Assigned(FirstItemCreated) then FirstItemCreated := Created;
    end
    else
    begin
      // v1 back-compat: bare object = item
      Created := CreateItemNode(ParentId, ProjectId, FolderId, UserId, ChildObj, TItemLevel.Item);
      if not Assigned(FirstItemCreated) then FirstItemCreated := Created;
    end;
  end;
end;

function TExperimentTemplateModel.FindFolderByTitle(ProjectId, ParentFolderId: Integer;
  const Title: string): TFolder;
var
  Project: TProject;
  Folders: TFoldersList;
  I: Integer;
begin
  Result := nil;
  Project := FManager.Find<TProject>(ProjectId);
  if not Assigned(Project) then Exit;

  Folders := Project.Folders;  // proxy-backed list scoped to this project
  if not Assigned(Folders) then Exit;

  for I := 0 to Folders.Count - 1 do
  begin
    if (Folders[I].ParentFolderID = ParentFolderId) and
       SameText(Folders[I].Title, Title) then
    begin
      Result := Folders[I];
      Break;
    end;
  end;
end;

procedure TExperimentTemplateModel.CreateFolderNode(ProjectId, ParentFolderId,
  UserId: Integer; FolderObj: TJSONObject; var FirstItemCreated: TItem);
var
  Title: string;
  NewFolder: TFolder;
  ChildrenArr: TJSONArray;
  Projects: TProjectsModel;
begin
  Title := FolderObj.GetValue<string>('title', 'Untitled');

  // Production folder creation path. TProjectsModel.AddFolder does not return
  // the new folder; instantiate a local model bound to the same manager so the
  // audit/ownership side-effects match the desktop path.
  Projects := TProjectsModel.Create(FManager, FAccess);
  try
    Projects.AddFolder(Title, '', ProjectId, ParentFolderId);
  finally
    Projects.Free;
  end;

  NewFolder := FindFolderByTitle(ProjectId, ParentFolderId, Title);
  if not Assigned(NewFolder) then
    raise Exception.CreateFmt(
      'Failed to locate folder "%s" after creation (project=%d, parent=%d).',
      [Title, ProjectId, ParentFolderId]);

  if FolderObj.TryGetValue<TJSONArray>('children', ChildrenArr) then
    CreateChildren(0, ProjectId, NewFolder.Id, UserId, ChildrenArr, FirstItemCreated);
  // Note: ParentId=0 for items under a folder-root — items in the Wiki/ root
  // are not children of any item, just scoped by folder.
end;

function TExperimentTemplateModel.ApplyFolderRoot(RootObj: TJSONObject;
  ProjectId, ParentFolderId, UserId: Integer;
  const TitleOverride: string): TItem;
var
  EffectiveTitle: string;
  NewFolder: TFolder;
  ChildrenArr: TJSONArray;
  Projects: TProjectsModel;
  FirstItemCreated: TItem;
begin
  FirstItemCreated := nil;

  if TitleOverride <> '' then
    EffectiveTitle := TitleOverride
  else
    EffectiveTitle := RootObj.GetValue<string>('title', 'Wiki');

  if Assigned(FindFolderByTitle(ProjectId, ParentFolderId, EffectiveTitle)) then
    raise EWikiFolderExists.CreateFmt('%s already exists in this folder.', [EffectiveTitle]);

  // Create the root folder
  Projects := TProjectsModel.Create(FManager, FAccess);
  try
    Projects.AddFolder(EffectiveTitle, '', ProjectId, ParentFolderId);
  finally
    Projects.Free;
  end;

  NewFolder := FindFolderByTitle(ProjectId, ParentFolderId, EffectiveTitle);
  if not Assigned(NewFolder) then
    raise Exception.CreateFmt(
      'Failed to locate folder "%s" after creation (project=%d, parent=%d).',
      [EffectiveTitle, ProjectId, ParentFolderId]);

  // Process children into the new root folder
  if RootObj.TryGetValue<TJSONArray>('children', ChildrenArr) then
    CreateChildren(0, ProjectId, NewFolder.Id, UserId, ChildrenArr, FirstItemCreated);

  Result := FirstItemCreated;
end;

function TExperimentTemplateModel.ApplyTemplate(TemplateId, ProjectId, FolderId,
  UserId: Integer; const TitleOverride: string): TItem;
var
  Template: TExperimentTemplate;
  RootJSON: TJSONObject;
  RootObj: TJSONObject;
  RootItem: TItem;
  RootType: TItemType;
  RootLevel: TItemLevel;
  ActionTypeId: Integer;
  ManagedActionType: TActionType;
  ChildrenArr: TJSONArray;
  UnusedFirst: TItem;
begin
  Result := nil;
  Template := FManager.Find<TExperimentTemplate>(TemplateId);
  if not Assigned(Template) then Exit;

  RootJSON := TJSONObject.ParseJSONValue(Template.StructureJSON) as TJSONObject;
  if not Assigned(RootJSON) then Exit;
  try
    // Support 'folder', 'proc', and 'item' root keys
    if RootJSON.TryGetValue<TJSONObject>('folder', RootObj) then
    begin
      Result := ApplyFolderRoot(RootObj, ProjectId, FolderId, UserId, TitleOverride);
      Exit;
    end
    else if RootJSON.TryGetValue<TJSONObject>('proc', RootObj) then
      RootLevel := TItemLevel.Proc
    else if RootJSON.TryGetValue<TJSONObject>('item', RootObj) then
      RootLevel := TItemLevel.Item
    else
      Exit;

    RootType := TItemType(RootObj.GetValue<Integer>('type', Ord(TItemType.Other)));

    RootItem := TItem.Create;
    if TitleOverride <> '' then
      RootItem.Title := TitleOverride
    else
      RootItem.Title := RootObj.GetValue<string>('title', Template.Name);
    RootItem.Level := RootLevel;
    RootItem.Type_ := RootType;
    RootItem.Parent := 0;
    RootItem.ProjectID := ProjectId;
    RootItem.FolderID := FolderId;
    RootItem.CreatedDate := UTCNow;
    RootItem.CreatedBy := UserId;
    RootItem.Expanded := True;

    ActionTypeId := RootObj.GetValue<Integer>('actionTypeId', 0);
    if ActionTypeId > 0 then
    begin
      ManagedActionType := FManager.Find<TActionType>(ActionTypeId);
      if Assigned(ManagedActionType) then
        RootItem.ActionType := ManagedActionType;
    end;

    FManager.Save(RootItem);
    FManager.Flush;
    RecordAudit(FManager, aetItem, RootItem.Id, aoCreate, UserId,
      'Created from template "' + Template.Name + '"');
    FManager.Evict(RootItem);

    Result := RootItem;

    // Create children
    if RootObj.TryGetValue<TJSONArray>('children', ChildrenArr) then
    begin
      UnusedFirst := nil;
      CreateChildren(RootItem.Id, ProjectId, FolderId, UserId, ChildrenArr, UnusedFirst);
    end;
  finally
    RootJSON.Free;
  end;
end;

procedure TExperimentTemplateModel.ConvertIdsToNames(Node: TJSONObject);
var
  ActionTypeId: Integer;
  ActionType: TActionType;
  Pair: TJSONPair;
  ChildrenArr: TJSONArray;
  i: Integer;
  ChildObj: TJSONObject;
begin
  // Replace actionTypeId (integer) with actionTypeName (string)
  ActionTypeId := Node.GetValue<Integer>('actionTypeId', 0);
  if ActionTypeId > 0 then
  begin
    ActionType := FManager.Find<TActionType>(ActionTypeId);
    // Remove the integer ID pair
    Pair := Node.RemovePair('actionTypeId');
    Pair.Free;
    // Add name-based reference
    if Assigned(ActionType) then
      Node.AddPair('actionTypeName', ActionType.Title)
    else
      Node.AddPair('actionTypeName', '');
  end
  else
  begin
    // Remove actionTypeId=0 entries (no action type assigned)
    Pair := Node.RemovePair('actionTypeId');
    if Assigned(Pair) then
      Pair.Free;
  end;

  // Recurse into children array
  if Node.TryGetValue<TJSONArray>('children', ChildrenArr) then
  begin
    for i := 0 to ChildrenArr.Count - 1 do
    begin
      ChildObj := ChildrenArr.Items[i] as TJSONObject;
      ConvertIdsToNames(ChildObj);
    end;
  end;
end;

procedure TExperimentTemplateModel.ExportTemplateToFile(TemplateId: Integer;
  const FilePath: string);
var
  Template: TExperimentTemplate;
  StructJSON: TJSONObject;
  ProcObj: TJSONObject;
  Envelope: TJSONObject;
  ElnTemplate: TJSONObject;
  SL: TStringList;
begin
  Template := FManager.Find<TExperimentTemplate>(TemplateId);
  if not Assigned(Template) then
    raise Exception.Create('Template not found');

  StructJSON := TJSONObject.ParseJSONValue(Template.StructureJSON) as TJSONObject;
  if not Assigned(StructJSON) then
    raise Exception.Create('Invalid template structure JSON');

  Envelope := nil;
  try
    // Convert IDs to names in the root object (proc or item)
    if StructJSON.TryGetValue<TJSONObject>('proc', ProcObj) then
      ConvertIdsToNames(ProcObj)
    else if StructJSON.TryGetValue<TJSONObject>('item', ProcObj) then
      ConvertIdsToNames(ProcObj);

    // Build export envelope
    ElnTemplate := TJSONObject.Create;
    ElnTemplate.AddPair('version', TJSONNumber.Create(1));
    ElnTemplate.AddPair('name', Template.Name);
    ElnTemplate.AddPair('description', Template.Description);
    ElnTemplate.AddPair('category', Template.Category);
    // Transfer ownership of StructJSON to ElnTemplate
    ElnTemplate.AddPair('structure', StructJSON);

    Envelope := TJSONObject.Create;
    Envelope.AddPair('elnTemplate', ElnTemplate);

    // Write formatted JSON to file
    SL := TStringList.Create;
    try
      SL.Text := Envelope.Format(2);
      SL.SaveToFile(FilePath, TEncoding.UTF8);
    finally
      SL.Free;
    end;
  finally
    // StructJSON ownership was transferred to Envelope, so only free Envelope
    Envelope.Free;
  end;
end;

function TExperimentTemplateModel.FindActionTypeByName(const Name: string): Integer;
var
  TrimmedName: string;
  List: TActionTypes;
  AT: TActionType;
begin
  Result := 0;
  TrimmedName := Trim(Name);
  if TrimmedName = '' then
    Exit;

  // Load all action types and find case-insensitive match
  List := FManager.Find<TActionType>.List;
  try
    for AT in List do
    begin
      if SameText(AT.Title, TrimmedName) then
      begin
        Result := AT.Id;
        Break;
      end;
    end;
  finally
    List.Free;
  end;
end;

procedure TExperimentTemplateModel.ConvertNamesToIds(Node: TJSONObject;
  Warnings: TStringList);
var
  ActionTypeName: string;
  ActionTypeId: Integer;
  Pair: TJSONPair;
  ChildrenArr: TJSONArray;
  i: Integer;
  ChildObj: TJSONObject;
begin
  // Replace actionTypeName (string) with actionTypeId (integer)
  ActionTypeName := Node.GetValue<string>('actionTypeName', '');
  if ActionTypeName <> '' then
  begin
    // Remove the name pair
    Pair := Node.RemovePair('actionTypeName');
    Pair.Free;

    // Look up the action type by name
    ActionTypeId := FindActionTypeByName(ActionTypeName);
    if ActionTypeId > 0 then
      Node.AddPair('actionTypeId', TJSONNumber.Create(ActionTypeId))
    else
      Warnings.Add('Action type not found: "' + ActionTypeName + '"');
  end;

  // Recurse into children array
  if Node.TryGetValue<TJSONArray>('children', ChildrenArr) then
  begin
    for i := 0 to ChildrenArr.Count - 1 do
    begin
      ChildObj := ChildrenArr.Items[i] as TJSONObject;
      ConvertNamesToIds(ChildObj, Warnings);
    end;
  end;
end;

function TExperimentTemplateModel.ImportTemplateFromFile(const FilePath: string;
  CreatedBy: Integer; out Warnings: string): TExperimentTemplate;
var
  SL: TStringList;
  WarnList: TStringList;
  RootJSON: TJSONObject;
  ElnTemplate: TJSONObject;
  StructObj: TJSONObject;
  ProcObj: TJSONObject;
  Version: Integer;
  Name, Description, Category: string;
begin
  Warnings := '';

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FilePath, TEncoding.UTF8);
    RootJSON := TJSONObject.ParseJSONValue(SL.Text) as TJSONObject;
  finally
    SL.Free;
  end;

  if not Assigned(RootJSON) then
    raise Exception.Create('Invalid JSON file');

  WarnList := TStringList.Create;
  try
    // Validate envelope structure
    if not RootJSON.TryGetValue<TJSONObject>('elnTemplate', ElnTemplate) then
      raise Exception.Create('Missing "elnTemplate" object in file');

    Version := ElnTemplate.GetValue<Integer>('version', 0);
    if not (Version in [1, 2]) then
      raise Exception.Create('Unsupported template version: ' + IntToStr(Version));

    // Extract metadata
    Name := ElnTemplate.GetValue<string>('name', '');
    Description := ElnTemplate.GetValue<string>('description', '');
    Category := ElnTemplate.GetValue<string>('category', '');

    if Name = '' then
      raise Exception.Create('Template name is required');

    // Get structure sub-object
    if not ElnTemplate.TryGetValue<TJSONObject>('structure', StructObj) then
      raise Exception.Create('Missing "structure" object in template');

    // Convert action type names back to IDs in the root node (proc or item)
    if StructObj.TryGetValue<TJSONObject>('proc', ProcObj) then
      ConvertNamesToIds(ProcObj, WarnList)
    else if StructObj.TryGetValue<TJSONObject>('item', ProcObj) then
      ConvertNamesToIds(ProcObj, WarnList);

    // Create the template using the existing AddTemplate method
    Result := AddTemplate(Name, Description, Category, StructObj.Format(2), CreatedBy);

    // Collect warnings
    if WarnList.Count > 0 then
      Warnings := WarnList.Text;
  finally
    WarnList.Free;
    RootJSON.Free;
  end;
end;

end.
