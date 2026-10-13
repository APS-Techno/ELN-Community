unit unit_ToolsWrite;

interface

uses
  System.JSON,
  unit_MCPTools;

procedure RegisterWriteTools(Registry: TToolRegistry);

function GetReqInt(const Params: TJSONObject; const Key: string): Integer;
function GetReqInt64(const Params: TJSONObject; const Key: string): Int64;
function GetReqStr(const Params: TJSONObject; const Key: string): string;
function GetOptStr(const Params: TJSONObject; const Key: string;
  out Value: string): Boolean;
function GetOptInt(const Params: TJSONObject; const Key: string;
  out Value: Integer): Boolean;
function GetOptInt64(const Params: TJSONObject; const Key: string;
  out Value: Int64): Boolean;
procedure CheckUploadPathAllowed(const Context: TToolContext;
  const FilePath: string);
procedure CheckProjectWriteAccess(const Context: TToolContext; ProjectId: Integer);
procedure RequireWriteUser(const Context: TToolContext);
function ComputeFileMD5(const FilePath: string): string;

function HandleCreateProject(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleCreateFolder(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleCreateItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleUpdateItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

function HandleRepairFiles(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleReattachFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

// The root (even when deleted) and its non-deleted descendants.
function CollectItemTreeIds(const Context: TToolContext;
  RootId: Integer): TArray<Integer>;
function CollectProjectItemIds(const Context: TToolContext;
  ProjectId: Integer): TArray<Integer>;

function HandleMoveFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleReparentItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

type
  TAttachedFileInfo = record
    Id: Int64;
    Title: string;
    FullName: string;
    Hash: string;
  end;

// Attach a local file to a given item: computes MD5, inserts the DB row,
// copies to storage, records audit. Does NOT perform permission or signed-item
// checks — the caller must do those. Item, FileType, and FilePath must all
// have been validated before calling.
function AttachFileToItem(const Context: TToolContext; ItemId: Integer;
  const FilePath: string; FileTypeId: Integer; const Title: string): TAttachedFileInfo;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.StrUtils, System.DateUtils,
  System.Generics.Collections, System.TypInfo, System.Rtti,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Drivers.Interfaces,
  IdHashMessageDigest,
  unit_User, unit_Project, unit_Item, unit_ItemTypes,
  unit_FileLocator,
  unit_ProjectAccessPolicy, unit_ELNDB_Dictionary,
  unit_FileRelocator,
  unit_NotebookStorage,
  unit_FileType, unit_ValueType,
  unit_ActionType, unit_Equipment,
  unit_AuditLog, unit_AuditHelper,
  unit_ConflictHandler, unit_ItemModel, unit_ProjectModel, unit_SignatureModel,
  unit_ToolScope,
  unit_FilePaths, unit_JSONCompact,
  unit_TimeHelper,
  Winapi.Windows,
  unit_MCPDiag,
  unit_ToolHelpers,
  unit_Hypothesis, unit_HypothesisGuard, unit_HypothesisEvidence,
  unit_ValueSource, unit_ValueChecks;


function GetReqInt(const Params: TJSONObject; const Key: string): Integer;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<Integer>(Key);
end;

function GetReqInt64(const Params: TJSONObject; const Key: string): Int64;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<Int64>(Key);
end;

function GetReqStr(const Params: TJSONObject; const Key: string): string;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<string>(Key);
end;

function GetReqNum(const Params: TJSONObject; const Key: string): Double;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<Double>(Key);
end;

function GetOptStr(const Params: TJSONObject; const Key: string;
  out Value: string): Boolean;
begin
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil) and
            not (Params.FindValue(Key) is TJSONNull);
  if Result then
    Value := Params.GetValue<string>(Key);
end;

function GetOptInt(const Params: TJSONObject; const Key: string;
  out Value: Integer): Boolean;
begin
  // JSON null means absent, not an infrastructure parsing error.
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil) and
            not (Params.FindValue(Key) is TJSONNull);
  if Result then
    Value := Params.GetValue<Integer>(Key);
end;

function GetOptInt64(const Params: TJSONObject; const Key: string;
  out Value: Int64): Boolean;
begin
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil) and
            not (Params.FindValue(Key) is TJSONNull);
  if Result then
    Value := Params.GetValue<Int64>(Key);
end;

function GetOptBool(const Params: TJSONObject; const Key: string;
  ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if Params = nil then
    Exit;
  V := Params.FindValue(Key);
  if (V = nil) or (V is TJSONNull) then
    Exit;
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else
    // Tolerate the string forms some clients send for booleans.
    Result := SameText(V.Value, 'true');
end;

function GetOptNum(const Params: TJSONObject; const Key: string;
  out Value: Double): Boolean;
begin
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil);
  if Result then
    Value := Params.GetValue<Double>(Key);
end;


procedure CheckUploadPathAllowed(const Context: TToolContext;
  const FilePath: string);
var
  NormRoot, NormFile, Current, Parent, Component: string;
  Attributes, ErrorCode: DWORD;
begin
  if Context.UploadRoot = '' then
    raise Exception.Create(
      'upload_file is disabled on this server. Configure an allowed upload ' +
      'directory before using this tool.');

  NormRoot := IncludeTrailingPathDelimiter(
    TPath.GetFullPath(Context.UploadRoot));
  NormFile := TPath.GetFullPath(FilePath);

  if not StartsText(NormRoot, NormFile) then
    raise Exception.Create(
      'file_path is outside the allowed upload root.');
  // Refuse Windows aliases and alternate data streams before opening bytes.
  if (Pos(':', Copy(NormFile, 3, MaxInt)) > 0) or
    StartsText('\\?\', FilePath) or StartsText('\\.\', FilePath) then
    raise Exception.Create('file_path uses an unsupported Windows path alias.');
  for Component in Copy(NormFile, 4, MaxInt).Replace('/', '\').Split(['\']) do
    if (Component <> '') and CharInSet(Component[Length(Component)], [' ', '.']) then
      raise Exception.Create('file_path uses an ambiguous Windows path component.');
  // Prefix checks alone do not confine junctions or symbolic links.
  Current := NormFile;
  while Current <> '' do
  begin
    Attributes := GetFileAttributes(PChar(Current));
    if Attributes <> INVALID_FILE_ATTRIBUTES then
    begin
      if (Attributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
        raise Exception.Create('file_path cannot traverse a reparse point.');
    end
    else
    begin
      ErrorCode := GetLastError;
      if not (ErrorCode in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND]) then
        RaiseLastOSError(ErrorCode);
    end;
    Parent := ExtractFileDir(Current);
    if SameText(Parent, Current) then
      Break;
    Current := Parent;
  end;
end;


// Identity is required here; project write permission is decided by the
// injected access policy in CheckProjectWriteAccess.
procedure RequireWriteUser(const Context: TToolContext);
begin
  if Context.User = nil then
    raise Exception.Create('No notebook principal configured.');
  if Context.User.IsArchived then
    raise Exception.CreateFmt('Access denied: user "%s" is archived.',
      [Context.User.Username]);
end;

procedure CheckProjectWriteAccess(const Context: TToolContext; ProjectId: Integer);
begin
  RequireWriteUser(Context);

  // Writes obey the scope too, through this one chokepoint: every write
  // handler funnels its subject's project (and both ends of a move) through
  // here. The guard is inert without a scope, and its uniform refusal fires
  // BEFORE the existence/archived checks below can say anything specific
  // about an out-of-scope project.
  RequireProjectRead(Context, ProjectId);

  case Context.AccessPolicy.CheckWrite(Context.Manager, Context.User, ProjectId) of
    pwAllowed: ;
    pwProjectNotFound:
      raise Exception.CreateFmt('Project not found: %d', [ProjectId]);
    pwProjectArchived:
      raise Exception.CreateFmt(
        'Project %d is archived and cannot be modified.', [ProjectId]);
    pwNoPermission:
      raise Exception.CreateFmt(
        'Access denied: no write permission on project %d', [ProjectId]);
  else
    // Fail closed for role denials or any future verdict.
    raise Exception.CreateFmt(
      'Access denied: cannot write to project %d', [ProjectId]);
  end;
end;


function BuildItemStoragePath(const ProjectFileFolder, ItemFolderName,
  FileFullName: string): string;
begin
  Result := Format('Projects/%s/%s/%s', [CleanFileName(ProjectFileFolder),
    CleanFileName(ItemFolderName), FileFullName]);
end;

function HandleCreateProject(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Title, Description: string;
  HasDesc: Boolean;
  Project: TProject;
begin
  RequireWriteUser(Context);
  if not Context.AccessPolicy.CanCreateProjects(Context.Manager, Context.User) then
    raise Exception.Create('Access denied: cannot create projects.');
  // A new project is outside a fixed scope; only the host can widen a scope.
  if IsScopeActive(Context) then
    raise Exception.Create('This session is confined to a fixed set of ' +
      'projects and cannot create new ones.');
  Title := GetReqStr(Params, 'title');
  HasDesc := GetOptStr(Params, 'description', Description);

  CheckMaxLen(Title, 'title', MAX_TITLE_LEN);
  if HasDesc then
    CheckMaxLen(Description, 'description', MAX_DESC_LEN);


  Project := TProject.Create;
  Project.Title := Title;
  if HasDesc then
    Project.Description := Description;
  Project.Owner := Context.User;
  Project.CreatedDate := UTCNow;
  Project.CreatedBy := Context.User.Id;
  Project.Expanded := True;
  Project.IsArchived := False;
  Context.Manager.Save(Project);

  Project.FileFolder := Format('[%.*d]%s', [5, Project.Id, Project.Title]);
  TConflictHandler.SafeFlush(Context.Manager);
  RecordAudit(Context.Manager, aetProject, Project.Id, aoCreate,
    Context.User.Id, 'MCP: Created project "' + Title + '"');

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Project.Id));
  Result.AddPair('title', Project.Title);
  Result.AddPair('file_folder', Project.FileFolder);
end;

function MakeCreateProjectSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Project title');
  Props.AddPair('title', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Project description');
  Props.AddPair('description', P);


  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('title');
  Result.AddPair('required', Req);
end;


function HandleCreateFolder(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId, ParentFolderId: Integer;
  Title, Description: string;
  HasParent, HasDesc: Boolean;
  Project: TProject;
  Folder: TFolder;
begin
  ProjectId := GetReqInt(Params, 'project_id');
  Title := GetReqStr(Params, 'title');
  HasParent := GetOptInt(Params, 'parent_folder_id', ParentFolderId);
  HasDesc := GetOptStr(Params, 'description', Description);

  CheckMaxLen(Title, 'title', MAX_TITLE_LEN);
  if HasDesc then
    CheckMaxLen(Description, 'description', MAX_DESC_LEN);

  CheckProjectWriteAccess(Context, ProjectId);

  Project := Context.Manager.Find<TProject>(ProjectId);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project not found: %d', [ProjectId]);

  // Reject a bogus/hallucinated parent id up front — a nonexistent parent would
  // otherwise commit silently and the folder would never appear in the tree.
  if HasParent and (ParentFolderId <> 0) and
     (Project.GetFolder(ParentFolderId) = nil) then
    raise Exception.CreateFmt('Parent folder %d not found in project %d',
      [ParentFolderId, ProjectId]);

  Folder := TFolder.Create;
  Folder.Title := Title;
  if HasDesc then
    Folder.Description := Description;
  if HasParent then
    Folder.ParentFolderID := ParentFolderId
  else
    Folder.ParentFolderID := 0;
  Folder.CreatedDate := UTCNow;
  Folder.CreatedBy := Context.User.Id;
  Folder.Expanded := True;

  Project.Folders.Add(Folder);
  Context.Manager.SaveOrUpdate(Project);
  TConflictHandler.SafeFlush(Context.Manager);
  RecordAudit(Context.Manager, aetFolder, Folder.Id, aoCreate,
    Context.User.Id,
    'MCP: Created folder "' + Title + '" in project "' + Project.Title + '"');

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Folder.Id));
  Result.AddPair('title', Folder.Title);
end;

function MakeCreateFolderSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Project ID');
  Props.AddPair('project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Folder title');
  Props.AddPair('title', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Parent folder ID (default: 0 = root)');
  Props.AddPair('parent_folder_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Folder description');
  Props.AddPair('description', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('project_id');
  Req.Add('title');
  Result.AddPair('required', Req);
end;


function StrToItemType(const S: string; out AType: TItemType): Boolean;
var V: Integer;
begin
  V := GetEnumValue(TypeInfo(TItemType), S);
  Result := V >= 0;
  if Result then AType := TItemType(V);
end;

function StrToItemLevel(const S: string; out ALevel: TItemLevel): Boolean;
var V: Integer;
begin
  V := GetEnumValue(TypeInfo(TItemLevel), S);
  Result := V >= 0;
  if Result then ALevel := TItemLevel(V);
end;

function ItemTypeToStr(AType: TItemType): string;
begin
  Result := TRttiEnumerationType.GetName<TItemType>(AType);
end;

function ItemLevelToStr(ALevel: TItemLevel): string;
begin
  Result := TRttiEnumerationType.GetName<TItemLevel>(ALevel);
end;


function HandleCreateItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId, FolderId, ParentId, ActionTypeId, EquipmentId: Integer;
  Title, Description, Properties, TypeStr, LevelStr: string;
  HasParent, HasDesc, HasProps, HasAT, HasEq: Boolean;
  IType: TItemType;
  ILevel: TItemLevel;
  Item: TItem;
  Project: TProject;
  ParentItem: TItem;
begin
  ProjectId := GetReqInt(Params, 'project_id');
  FolderId := GetReqInt(Params, 'folder_id');
  Title := GetReqStr(Params, 'title');
  TypeStr := GetReqStr(Params, 'item_type');
  LevelStr := GetReqStr(Params, 'level');

  if not StrToItemType(TypeStr, IType) then
    raise Exception.CreateFmt('Invalid item_type: %s', [TypeStr]);
  if not StrToItemLevel(LevelStr, ILevel) then
    raise Exception.CreateFmt('Invalid level: %s', [LevelStr]);

  HasParent := GetOptInt(Params, 'parent_id', ParentId);
  HasDesc := GetOptStr(Params, 'description', Description);
  HasProps := GetOptStr(Params, 'properties', Properties);
  HasAT := GetOptInt(Params, 'action_type_id', ActionTypeId);
  HasEq := GetOptInt(Params, 'equipment_id', EquipmentId);

  // Validate before saving: strict VARCHAR limits can fail after the item row commits.
  CheckMaxLen(Title, 'title', MAX_TITLE_LEN);
  if HasDesc then
    CheckMaxLen(Description, 'description', MAX_DESC_LEN);

  CheckProjectWriteAccess(Context, ProjectId);

  // Referential validation: a typo'd/hallucinated folder_id or parent_id would
  // otherwise commit a "success" with a valid eln:// URL, but the item would be
  // invisible in the desktop tree (looks like data loss).
  Project := Context.Manager.Find<TProject>(ProjectId);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project not found: %d', [ProjectId]);
  if (FolderId <> 0) and (Project.GetFolder(FolderId) = nil) then
    raise Exception.CreateFmt('Folder %d not found in project %d',
      [FolderId, ProjectId]);

  if HasParent and (ParentId > 0) then
  begin
    RequireItemRead(Context, ParentId);
    ParentItem := Context.Manager.Find<TItem>(ParentId);
    if not Assigned(ParentItem) then
      raise Exception.CreateFmt('Parent item not found: %d', [ParentId]);
    if ParentItem.ProjectID <> ProjectId then
      raise Exception.CreateFmt(
        'Parent item %d belongs to project %d, not %d.',
        [ParentId, ParentItem.ProjectID, ProjectId]);
    if IsItemSignedCheck(Context.Manager, ParentId) then
      raise Exception.Create('Parent item is signed and cannot be modified.');
  end;

  Item := TItem.Create;
  Item.Title := Title;
  Item.Type_ := IType;
  Item.Level := ILevel;
  Item.ProjectID := ProjectId;
  Item.FolderID := FolderId;
  if HasParent then
    Item.Parent := ParentId
  else
    Item.Parent := 0;
  if HasDesc then
    Item.Description := Description;
  if HasProps then
    Item.Properties := Properties;
  Item.CreatedDate := UTCNow;
  Item.CreatedBy := Context.User.Id;
  Item.Expanded := True;

  if HasAT then
  begin
    Item.ActionType := Context.Manager.Find<TActionType>(ActionTypeId);
    if not Assigned(Item.ActionType) then
      raise Exception.CreateFmt('ActionType not found: %d', [ActionTypeId]);
  end;
  if HasEq then
  begin
    Item.Equipment := Context.Manager.Find<TEquipment>(EquipmentId);
    if not Assigned(Item.Equipment) then
      raise Exception.CreateFmt('Equipment not found: %d', [EquipmentId]);
  end;

  Context.Manager.Save(Item);
  TConflictHandler.SafeFlush(Context.Manager);
  RecordAudit(Context.Manager, aetItem, Item.Id, aoCreate,
    Context.User.Id, 'MCP: Created item "' + Title + '"');
  Context.Manager.Evict(Item);

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Item.Id));
  Result.AddPair('url', MakeElnItemUrl(Item));
  Result.AddPair('title', Item.Title);
  Result.AddPair('level', ItemLevelToStr(Item.Level));
  Result.AddPair('type', ItemTypeToStr(Item.Type_));
end;

function MakeCreateItemSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Project ID');
  Props.AddPair('project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Folder ID');
  Props.AddPair('folder_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Item title');
  Props.AddPair('title', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Item type: Synthesis, Treatment, Measurement, Testing, ' +
    'Characterization, Computing, Specimen, Model, Other, Wiki');
  Props.AddPair('item_type', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Hierarchy level: Proc, Item, Action, Folder');
  Props.AddPair('level', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Parent item ID (default: 0 = top-level)');
  Props.AddPair('parent_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Item description');
  Props.AddPair('description', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Free-text properties/metadata');
  Props.AddPair('properties', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Action type ID');
  Props.AddPair('action_type_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Equipment ID');
  Props.AddPair('equipment_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('project_id');
  Req.Add('folder_id');
  Req.Add('title');
  Req.Add('item_type');
  Req.Add('level');
  Result.AddPair('required', Req);
end;


function HandleUpdateItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  NewTitle, NewDescription, NewProperties: string;
  HasTitle, HasDesc, HasProps, Changed: Boolean;
  Item: TItem;
  Items: TItemModel;
  Relocator: IFileRelocator;
begin
  ItemId := GetReqInt(Params, 'item_id');
  HasTitle := GetOptStr(Params, 'title', NewTitle);
  HasDesc := GetOptStr(Params, 'description', NewDescription);
  HasProps := GetOptStr(Params, 'properties', NewProperties);

  if (not HasTitle) and (not HasDesc) and (not HasProps) then
    raise Exception.Create(
      'At least one of title, description, or properties is required.');

  if HasTitle then
    CheckMaxLen(NewTitle, 'title', MAX_TITLE_LEN);
  if HasDesc then
    CheckMaxLen(NewDescription, 'description', MAX_DESC_LEN);

  // Scope first, with the uniform refusal: "Item not found" below must not
  // read differently for an existing-but-out-of-scope id.
  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);

  CheckProjectWriteAccess(Context, Item.ProjectID);

  if IsItemSignedCheck(Context.Manager, ItemId) then
    raise Exception.Create('Item is signed and cannot be modified.');

  Changed := False;
  if HasTitle and (Item.Title <> NewTitle) then
  begin
    Changed := True;
    Item.Title := NewTitle;
  end;
  if HasDesc and (Item.Description <> NewDescription) then
  begin
    Changed := True;
    Item.Description := NewDescription;
  end;
  if HasProps and (Item.Properties <> NewProperties) then
  begin
    Changed := True;
    Item.Properties := NewProperties;
  end;

  if not Changed then
  begin
    // No-op: preserve ModifiedDate and do not write an audit row.
    Result := TJSONObject.Create;
    Result.AddPair('id', TJSONNumber.Create(Item.Id));
    Result.AddPair('url', MakeElnItemUrl(Item));
    Result.AddPair('title', Item.Title);
    Result.AddPair('description', Item.Description);
    Result.AddPair('properties', Item.Properties);
    if Item.ModifiedDate.HasValue then
      Result.AddPair('modified_date',
        TJSONString.Create(DateToISO8601(Item.ModifiedDate.Value, False)))
    else
      Result.AddPair('modified_date', TJSONNull.Create);
    Result.AddPair('changed', TJSONBool.Create(False));
    Exit;
  end;

  Relocator := nil;
  if Context.Storage <> nil then
    Relocator := TNotebookFileRelocator.Create(Context.Storage);
  Items := TItemModel.Create(Context.Manager);
  try
    if not Items.UpdateItemDurable(Item, Context.User.Id, Relocator) then
      raise Exception.Create('Item update refused: signed or changed by another user.');
  finally
    Items.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Item.Id));
  Result.AddPair('url', MakeElnItemUrl(Item));
  Result.AddPair('title', Item.Title);
  Result.AddPair('description', Item.Description);
  Result.AddPair('properties', Item.Properties);
  Result.AddPair('modified_date',
    DateToISO8601(Item.ModifiedDate.Value, False));
  Result.AddPair('changed', TJSONBool.Create(True));
end;

function MakeUpdateItemSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Item ID to update');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'New item title');
  Props.AddPair('title', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'New description (overwrites existing). ' +
    'Use empty string to clear.');
  Props.AddPair('description', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'New free-text properties/metadata (overwrites ' +
    'existing). Use empty string to clear.');
  Props.AddPair('properties', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;


function ComputeFileMD5(const FilePath: string): string;
var
  Fs: TFileStream;
  MD5: TIdHashMessageDigest5;
begin
  Fs := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyWrite);
  try
    MD5 := TIdHashMessageDigest5.Create;
    try
      Result := MD5.HashStreamAsHex(Fs);
    finally
      MD5.Free;
    end;
  finally
    Fs.Free;
  end;
end;

// Compensating delete for AttachFileToItem: the Files row must exist before the
// remote path can be built (it embeds F.Id), so when storage then fails the row
// has to be taken back out again. Mirrors TItemModel.RemoveFile — detach from
// Item.Files first so the collection keeps no dangling reference, then Remove.
// Never raises: the caller is already unwinding a failure and needs to report
// the original cause, so a secondary failure is returned as text instead.
function RemoveOrphanFileRow(const Context: TToolContext; FileId: Int64): string;
var
  F: TFile;
begin
  try
    F := Context.Manager.Find<TFile>(FileId);
    if not Assigned(F) then
    begin
      Result := 'rolled back';
      Exit;
    end;
    if Assigned(F.Item) then
      F.Item.Files.Remove(F);
    Context.Manager.Remove(F);
    if not TConflictHandler.SafeFlush(Context.Manager) then
      raise Exception.Create('flush of the compensating delete was rejected');
    Result := 'rolled back';
  except
    on E: Exception do
    begin
      Result := 'COULD NOT be rolled back - orphan row remains';
      MCPLog(Format(
        'RemoveOrphanFileRow failed for file %d: %s: %s — orphan row remains',
        [FileId, E.ClassName, E.Message]));
    end;
  end;
end;

function AttachFileToItem(const Context: TToolContext; ItemId: Integer;
  const FilePath: string; FileTypeId: Integer; const Title: string): TAttachedFileInfo;
var
  Item: TItem;
  Project: TProject;
  FType: TFileType;
  F: TFile;
  FileId: Int64;
  Hash, RemotePath, CleanupMsg: string;
begin
  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);
  FType := Context.Manager.Find<TFileType>(FileTypeId);
  if not Assigned(FType) then
    raise Exception.CreateFmt('FileType not found: %d', [FileTypeId]);

  Hash := ComputeFileMD5(FilePath);

  F := TFile.Create;
  F.FileType := FType;
  F.Title := Title;
  F.Hash := Hash;
  F.CreatedDate := UTCNow;
  F.CreatedBy := Context.User.Id;
  F.Item := Item;
  Item.Files.Add(F);
  Context.Manager.Update(Item);

  // Flush belongs inside compensation: MySQL can commit this INSERT before
  // an unrelated managed entity fails, leaving a file row with no bytes.
  FileId := 0;
  try
    TConflictHandler.SafeFlush(Context.Manager);
    FileId := F.Id;   // capture before any rollback attempt invalidates F

    Project := Context.Manager.Find<TProject>(Item.ProjectID);
    RemotePath := Format('Projects/%s/%s/%s', [
      CleanFileName(Project.FileFolder),
      CleanFileName(Item.FolderName),
      F.FullName]);
    Context.Storage.CopyIn(FilePath, RemotePath);
  except
    on E: Exception do
    begin
      // Storage (or the flush) failed. Remove the row so the database never
      // claims a file that is not in storage.
      //
      // FileId is still 0 when the flush itself raised, but the row may exist
      // anyway: the flush walks every object in the manager, so this INSERT can
      // have gone through and autocommitted before a later statement failed.
      // Re-read F.Id here rather than trusting the pre-flush capture — Aurelius
      // stamps the generated key on the object as soon as its INSERT succeeds.
      // RemoveOrphanFileRow treats an id that resolves to nothing as a no-op.
      if FileId = 0 then
        FileId := F.Id;
      MCPLog(Format('upload_file storage failed for item %d file %d: %s: %s',
        [ItemId, FileId, E.ClassName, E.Message]));
      CleanupMsg := RemoveOrphanFileRow(Context, FileId);
      raise Exception.CreateFmt('%s (file record %d %s)',
        [E.Message, FileId, CleanupMsg]);
    end;
  end;

  RecordAudit(Context.Manager, aetFile, F.Id, aoCreate,
    Context.User.Id,
    'MCP: Added file "' + Title + '" to item "' + Item.Title + '"');

  Result.Id := F.Id;
  Result.Title := F.Title;
  Result.FullName := F.FullName;
  Result.Hash := F.Hash;
end;

procedure CheckFileTitleChars(const Title, ParamName: string);
begin
  if Title.IndexOfAny([':', '/', '\']) >= 0 then
    raise Exception.CreateFmt('%s must not contain ":", "/" or "\".', [ParamName]);
end;

function HandleUploadFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId, FileTypeId: Integer;
  FilePath, Title: string;
  HasTitle: Boolean;
  Item: TItem;
  FType: TFileType;
  Info: TAttachedFileInfo;
begin
  ItemId := GetReqInt(Params, 'item_id');
  FilePath := GetReqStr(Params, 'file_path');
  FileTypeId := GetReqInt(Params, 'file_type_id');
  HasTitle := GetOptStr(Params, 'title', Title);
  if HasTitle then
    CheckFileTitleChars(Title, 'title');

  // Confine the source path before touching the filesystem so a bad path is
  // rejected without leaking FileExists probe-style information about arbitrary
  // locations on the server host.
  CheckUploadPathAllowed(Context, FilePath);

  if not FileExists(FilePath) then
    raise Exception.CreateFmt('File not found: %s', [FilePath]);

  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);

  CheckProjectWriteAccess(Context, Item.ProjectID);

  if IsItemSignedCheck(Context.Manager, ItemId) then
    raise Exception.Create('Item is signed and cannot be modified.');

  FType := Context.Manager.Find<TFileType>(FileTypeId);
  if not Assigned(FType) then
    raise Exception.CreateFmt('FileType not found: %d', [FileTypeId]);

  if not HasTitle then
    Title := TPath.GetFileNameWithoutExtension(FilePath);

  Info := AttachFileToItem(Context, ItemId, FilePath, FileTypeId, Title);

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Info.Id));
  Result.AddPair('title', Info.Title);
  Result.AddPair('full_name', Info.FullName);
  Result.AddPair('hash', Info.Hash);
end;

function MakeUploadFileSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Item ID to attach the file to');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Absolute local file path');
  Props.AddPair('file_path', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'File type ID (from list_file_types)');
  Props.AddPair('file_type_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'File title (default: filename without extension); must not contain ":", "/" or "\"');
  Props.AddPair('title', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Req.Add('file_path');
  Req.Add('file_type_id');
  Result.AddPair('required', Req);
end;


function HandleRenameFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Int64;
  FileTypeId: Integer;
  NewTitle, OldTitle, OldExt, OldPath, NewPath, NewFullName, AuditMsg: string;
  HasTitle, HasType: Boolean;
  F: TFile;
  FType: TFileType;
  Item: TItem;
  Project: TProject;
  UsedTitle, UsedExt: string;
  Transaction: IDBTransaction;
  BytesMoved: Boolean;
begin
  FileId := GetReqInt64(Params, 'file_id');
  HasTitle := GetOptStr(Params, 'new_title', NewTitle);
  HasType := GetOptInt(Params, 'file_type_id', FileTypeId);
  FType := nil;

  if (not HasTitle) and (not HasType) then
    raise Exception.Create('At least one of new_title or file_type_id is required.');

  if HasTitle then
    CheckFileTitleChars(NewTitle, 'new_title');

  RequireFileRead(Context, FileId);

  F := Context.Manager.Find<TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);

  Item := F.Item;
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [Item.Id]);

  CheckProjectWriteAccess(Context, Item.ProjectID);

  if IsItemSignedCheck(Context.Manager, Item.Id) then
    raise Exception.Create('Item is signed and cannot be modified.');

  if HasType then
  begin
    FType := Context.Manager.Find<TFileType>(FileTypeId);
    if not Assigned(FType) then
      raise Exception.CreateFmt('FileType not found: %d', [FileTypeId]);
  end;

  Project := Context.Manager.Find<TProject>(Item.ProjectID);
  OldTitle := F.Title;
  OldExt := F.FileType.Ext;

  OldPath := Format('Projects/%s/%s/%s', [
    CleanFileName(Project.FileFolder),
    CleanFileName(Item.FolderName),
    F.FullName]);

  // Build new storage path (compute without modifying entity yet)
  if HasTitle then UsedTitle := NewTitle else UsedTitle := F.Title;
  if HasType then UsedExt := FType.Ext else UsedExt := F.FileType.Ext;
  NewFullName := Format('[%.*d]%s%s', [4, F.Id, UsedTitle, UsedExt]);
  NewPath := Format('Projects/%s/%s/%s', [
    CleanFileName(Project.FileFolder),
    CleanFileName(Item.FolderName),
    NewFullName]);

  if Context.Storage = nil then
    raise Exception.Create('rename_file needs notebook storage.');
  BytesMoved := False;
  Transaction := Context.Manager.Connection.BeginTransaction;
  try
    if OldPath <> NewPath then
    begin
      Context.Storage.MoveFile(OldPath, NewPath);
      BytesMoved := True;
    end;
    if HasTitle then
      F.Title := NewTitle;
    if HasType then
      F.FileType := FType;
    F.ModifiedDate := UTCNow;
    F.ModifiedBy := Context.User.Id;
    if not TConflictHandler.SafeFlush(Context.Manager) then
      raise Exception.Create('File changed elsewhere; rename refused.');

    AuditMsg := 'MCP: Updated file';
    if HasTitle then
      AuditMsg := AuditMsg + Format(' title "%s" -> "%s"', [OldTitle, F.Title]);
    if HasType then
      AuditMsg := AuditMsg + Format(' type -> %s', [F.FileType.Ext]);
    RecordAudit(Context.Manager, aetFile, F.Id, aoUpdate,
      Context.User.Id, AuditMsg);
    Transaction.Commit;
  except
    on E: Exception do
    begin
      try
        Transaction.Rollback;
      finally
        // Compensation must run even if the DB connection was lost.
        if BytesMoved then
          try
            Context.Storage.MoveFile(NewPath, OldPath);
          except
            on E2: Exception do
            begin
              MCPLog(Format('rename_file %d: %s; compensation failed: %s',
                [FileId, E.Message, E2.Message]));
              raise Exception.Create(
                'File rename failed and its bytes could not be restored; run repair_files.');
            end;
          end;
        Context.Manager.Refresh(F);
      end;
      raise;
    end;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(F.Id));
  Result.AddPair('old_title', OldTitle);
  Result.AddPair('new_title', F.Title);
  Result.AddPair('old_extension', OldExt);
  Result.AddPair('full_name', F.FullName);
  Result.AddPair('extension', F.FileType.Ext);
end;

function MakeRenameFileSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'File ID to rename');
  Props.AddPair('file_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'New file title (without extension); must not contain ":", "/" or "\". Optional if file_type_id is provided.');
  Props.AddPair('new_title', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'New file type ID (from list_file_types). Changes the extension. Optional if new_title is provided.');
  Props.AddPair('file_type_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Result.AddPair('required', Req);
end;


const
  MAX_VALUE_BATCH = 200;
  MAX_ITEM_DEPTH = 1000;

type
  TValueEntry = record
    ItemId: Integer;
    ValueTypeId: Integer;
    Value: Double;
    Tolerance: Double;
    Description: string;
    RecType: TRecType;
    Source: TValueSourceInfo;
    Issues: TValueIssues;
  end;

function IssueCodesText(Issues: TValueIssues): string;
var
  Issue: TValueIssue;
begin
  Result := '';
  for Issue := Low(TValueIssue) to High(TValueIssue) do
    if Issue in Issues then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + IssueCode(Issue);
    end;
end;

function IssueCodesJSON(Issues: TValueIssues): TJSONArray;
var
  Issue: TValueIssue;
begin
  Result := TJSONArray.Create;
  for Issue := Low(TValueIssue) to High(TValueIssue) do
    if Issue in Issues then
      Result.Add(IssueCode(Issue));
end;

function ParseValueSource(const Params: TJSONObject): TValueSourceInfo;
var
  KindStr: string;
  HasFile, HasReader, HasNote: Boolean;
begin
  Result := Default(TValueSourceInfo);
  HasFile := GetOptInt64(Params, 'source_file_id', Result.FileId);
  if HasFile and (Result.FileId <= 0) then
    raise Exception.Create('source_file_id must be a positive file id');
  HasReader := GetOptStr(Params, 'reader_id', Result.ReaderId);
  GetOptStr(Params, 'reader_version', Result.ReaderVersion);
  GetOptStr(Params, 'key_name', Result.KeyName);
  HasNote := GetOptStr(Params, 'source_note', Result.Note);
  if GetOptStr(Params, 'source_kind', KindStr) then
  begin
    if not TryParseSourceKind(KindStr, Result.Kind) then
      raise Exception.CreateFmt(
        'Invalid source_kind: %s (use Reader, Manual or Unknown)', [KindStr]);
  end
  else if HasReader then
    Result.Kind := vskReader
  else if HasFile or HasNote then
    Result.Kind := vskManual
  else
    Result.Kind := vskUnknown;
  try
    ValidateSource(Result);
  except
    on E: EValueSourceError do
      raise Exception.Create(E.Message);
  end;
end;

function ParseValueEntry(const Params: TJSONObject): TValueEntry;
var
  RecTypeStr: string;
begin
  Result := Default(TValueEntry);
  Result.ItemId := GetReqInt(Params, 'item_id');
  Result.Value := GetReqNum(Params, 'value');
  Result.ValueTypeId := GetReqInt(Params, 'value_type_id');
  if not GetOptNum(Params, 'tolerance', Result.Tolerance) then
    Result.Tolerance := 0;
  if GetOptStr(Params, 'description', Result.Description) then
    CheckMaxLen(Result.Description, 'description', MAX_DESC_LEN);
  Result.RecType := TEST_RESULT;
  if GetOptStr(Params, 'rec_type', RecTypeStr) then
  begin
    if SameText(RecTypeStr, 'EXP_CONDITION') then
      Result.RecType := EXP_CONDITION
    else if not SameText(RecTypeStr, 'TEST_RESULT') then
      raise Exception.CreateFmt('Invalid rec_type: %s (use EXP_CONDITION or TEST_RESULT)',
        [RecTypeStr]);
  end;
  Result.Source := ParseValueSource(Params);
end;

function IsSelfOrAncestor(const Context: TToolContext; AncestorId: Integer;
  Item: TItem): Boolean;
var
  Current: TItem;
  Depth: Integer;
begin
  Current := Item;
  Depth := 0;
  while Assigned(Current) and (Depth <= MAX_ITEM_DEPTH) do
  begin
    if Current.Id = AncestorId then
      Exit(True);
    if Current.Parent <= 0 then
      Break;
    Current := Context.Manager.Find<TItem>(Current.Parent);
    Inc(Depth);
  end;
  Result := False;
end;

procedure CheckSourceFile(const Context: TToolContext; Item: TItem;
  FileId: Int64);
var
  F: TFile;
  FileItem: TItem;
begin
  RequireFileRead(Context, FileId);
  F := Context.Manager.Find<TFile>(FileId);
  FileItem := F.Item;
  if FileItem.IsDeleted then
    raise Exception.CreateFmt('Source file %d belongs to deleted item %d.',
      [FileId, FileItem.Id]);
  if FileItem.ProjectID <> Item.ProjectID then
    raise Exception.CreateFmt(
      'Source file %d belongs to another project than item %d. A value ' +
      'source must be a file of the item, its ancestors or its descendants ' +
      'in the same project.', [FileId, Item.Id]);
  if not IsSelfOrAncestor(Context, FileItem.Id, Item) and
    not IsSelfOrAncestor(Context, Item.Id, FileItem) then
    raise Exception.CreateFmt(
      'Source file %d is not attached to item %d, its ancestors or its ' +
      'descendants in the same project.', [FileId, Item.Id]);
end;

procedure ValidateValueEntry(const Context: TToolContext;
  var Entry: TValueEntry; Factor: Double; Confirm: Boolean);
var
  Item: TItem;
  VType: TValueType;
begin
  RequireItemRead(Context, Entry.ItemId);
  Item := Context.Manager.Find<TItem>(Entry.ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [Entry.ItemId]);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [Entry.ItemId]);

  CheckProjectWriteAccess(Context, Item.ProjectID);

  if IsItemSignedCheck(Context.Manager, Entry.ItemId) then
    raise Exception.Create('Item is signed and cannot be modified.');

  VType := Context.Manager.Find<TValueType>(Entry.ValueTypeId);
  if not Assigned(VType) then
    raise Exception.CreateFmt('ValueType not found: %d', [Entry.ValueTypeId]);

  if Entry.Source.FileId > 0 then
    CheckSourceFile(Context, Item, Entry.Source.FileId);

  Entry.Issues := CheckValue(VType, Entry.Value, Entry.Tolerance, Factor);
  if (Entry.Issues <> []) and not Confirm then
    raise Exception.CreateFmt(
      'Value refused: %s (issues: %s). Check the number, the units of ' +
      'value type %d ("%s") and the tolerance scale. If the value is correct ' +
      'as given, repeat the call with confirm_out_of_range: true.',
      [DescribeValueIssues(Entry.Issues, VType, Entry.Value, Entry.Tolerance,
        Factor), IssueCodesText(Entry.Issues), VType.Id, VType.Units]);
end;

function StoredValueJSON(Val: unit_Item.TValue;
  Issues: TValueIssues): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('id', TJSONNumber.Create(Val.Id));
    Result.AddPair('item_id', TJSONNumber.Create(Val.Item.Id));
    Result.AddPair('value', SmartNum(Val.Value));
    Result.AddPair('tolerance', SmartNum(Val.Tol));
    if Assigned(Val.ValueType) then
    begin
      Result.AddPair('value_type', Val.ValueType.Title);
      Result.AddPair('units', Val.ValueType.Units);
    end;
    Result.AddPair('source', ValueSourceJSON(Val));
    if Issues <> [] then
      Result.AddPair('confirmed_issues', IssueCodesJSON(Issues));
  except
    Result.Free;
    raise;
  end;
end;

// Entries must have passed ValidateValueEntry. All rows and their audit
// entries commit together or not at all.
function StoreValueEntries(const Context: TToolContext;
  const Entries: TArray<TValueEntry>): TJSONArray;
var
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  Committed: Boolean;
  Stored: TArray<unit_Item.TValue>;
  Item, Cached: TItem;
  Val: unit_Item.TValue;
  I: Integer;
begin
  SetLength(Stored, Length(Entries));
  Operation := TObjectManager.Create(Context.Manager.Connection);
  try
    Transaction := TConflictHandler.BeginOperationTransaction(Context.Manager);
    Committed := False;
    try
      for I := 0 to High(Entries) do
      begin
        Item := Operation.Find<TItem>(Entries[I].ItemId);
        Val := unit_Item.TValue.Create;
        Item.Values.Add(Val);
        Val.Item := Item;
        Val.ValueType := Operation.Find<TValueType>(Entries[I].ValueTypeId);
        Val.RecType := Entries[I].RecType;
        Val.Value := Entries[I].Value;
        Val.Tol := Entries[I].Tolerance;
        Val.Description := Entries[I].Description;
        Val.CreatedDate := UTCNow;
        Val.CreatedBy := Context.User.Id;
        ApplySource(Val, Entries[I].Source);
        Operation.Update(Item);
        Stored[I] := Val;
      end;
      Operation.Flush;
      for I := 0 to High(Stored) do
        RecordAudit(Operation, aetValue, Stored[I].Id, aoCreate,
          Context.User.Id,
          'MCP: Added value to item "' + Stored[I].Item.Title + '"');
      Transaction.Commit;
      Committed := True;
    finally
      if not Committed then
        Transaction.Rollback;
    end;

    for I := 0 to High(Entries) do
    begin
      Cached := Context.Manager.FindCached<TItem>(Entries[I].ItemId);
      if Assigned(Cached) and not Context.Manager.HasChanges(Cached) then
        Context.Manager.Refresh(Cached);
    end;

    Result := TJSONArray.Create;
    try
      for I := 0 to High(Stored) do
        Result.AddElement(StoredValueJSON(Stored[I], Entries[I].Issues));
    except
      Result.Free;
      raise;
    end;
  finally
    TConflictHandler.FreeOperationManager(Operation);
  end;
end;

function HandleAddValue(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Entry: TValueEntry;
  Rows: TJSONArray;
begin
  Entry := ParseValueEntry(Params);
  ValidateValueEntry(Context, Entry, LoadToleranceFactor(Context.Manager),
    GetOptBool(Params, 'confirm_out_of_range', False));
  Rows := StoreValueEntries(Context, [Entry]);
  try
    Result := Rows.Remove(0) as TJSONObject;
  finally
    Rows.Free;
  end;
end;

function HandleAddValues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Arr: TJSONArray;
  Entries: TArray<TValueEntry>;
  Factor: Double;
  Confirm: Boolean;
  Rows: TJSONArray;
  I: Integer;
begin
  if (Params = nil) or not (Params.FindValue('values') is TJSONArray) then
    raise Exception.Create(
      'Missing required parameter: values (array of value objects)');
  Arr := TJSONArray(Params.FindValue('values'));
  if Arr.Count = 0 then
    raise Exception.Create('values is empty; nothing was stored.');
  if Arr.Count > MAX_VALUE_BATCH then
    raise Exception.CreateFmt(
      'values has %d entries; the maximum is %d. Split the batch.',
      [Arr.Count, MAX_VALUE_BATCH]);
  Confirm := GetOptBool(Params, 'confirm_out_of_range', False);
  Factor := LoadToleranceFactor(Context.Manager);
  SetLength(Entries, Arr.Count);
  for I := 0 to Arr.Count - 1 do
    try
      if not (Arr.Items[I] is TJSONObject) then
        raise Exception.Create('the entry is not a JSON object');
      Entries[I] := ParseValueEntry(TJSONObject(Arr.Items[I]));
      ValidateValueEntry(Context, Entries[I], Factor, Confirm);
    except
      on E: Exception do
        raise Exception.CreateFmt('values[%d] refused; nothing was stored: %s',
          [I, E.Message]);
    end;

  Rows := StoreValueEntries(Context, Entries);
  Result := TJSONObject.Create;
  Result.AddPair('count', TJSONNumber.Create(Rows.Count));
  Result.AddPair('values', Rows);
end;

procedure AddValueSourceProps(Props: TJSONObject);
var
  P: TJSONObject;
  Kinds: TJSONArray;
begin
  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  Kinds := TJSONArray.Create;
  Kinds.Add('Reader');
  Kinds.Add('Manual');
  Kinds.Add('Unknown');
  P.AddPair('enum', Kinds);
  P.AddPair('description', 'Source kind. Default: Reader when reader_id is ' +
    'given, else Manual when source_file_id or source_note is given, else ' +
    'Unknown. Reader needs source_file_id, reader_id and key_name; Manual ' +
    'takes source_file_id and/or source_note; Unknown takes no source fields.');
  Props.AddPair('source_kind', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'File the number was read from or derived from. ' +
    'It must be attached to the item, one of its ancestors or one of its ' +
    'descendants in the same project.');
  Props.AddPair('source_file_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Reader identity (reader_id from extract_file_key_values)');
  Props.AddPair('reader_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Reader version (reader_version from extract_file_key_values)');
  Props.AddPair('reader_version', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Name of the reader key value that produced the number');
  Props.AddPair('key_name', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Free-text source, for example the analysis job, ' +
    'run or script that produced the number (max 1000 characters)');
  Props.AddPair('source_note', P);
end;

function MakeValueEntryProps: TJSONObject;
var
  P: TJSONObject;
begin
  Result := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Item ID to attach the value to');
  Result.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'number');
  P.AddPair('description', 'Numeric value in the units of the value type');
  Result.AddPair('value', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Value type ID (from list_value_types)');
  Result.AddPair('value_type_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'number');
  P.AddPair('description', 'Tolerance in the same units as value (default: 0)');
  Result.AddPair('tolerance', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Description / notes');
  Result.AddPair('description', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Record type: EXP_CONDITION or TEST_RESULT (default: TEST_RESULT)');
  Result.AddPair('rec_type', P);

  AddValueSourceProps(Result);
end;

function MakeValueEntryRequired: TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add('item_id');
  Result.Add('value');
  Result.Add('value_type_id');
end;

function MakeConfirmProp: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'boolean');
  Result.AddPair('description', 'Store values outside the value type range ' +
    'or with an inconsistent tolerance anyway (default: false). Set it only ' +
    'after checking that the refused number and its units are correct.');
end;

function MakeAddValueSchema: TJSONObject;
var
  Props: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := MakeValueEntryProps;
  Props.AddPair('confirm_out_of_range', MakeConfirmProp);
  Result.AddPair('properties', Props);
  Result.AddPair('required', MakeValueEntryRequired);
end;

function MakeAddValuesSchema: TJSONObject;
var
  Props, Values, Entry: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  Entry := TJSONObject.Create;
  Entry.AddPair('type', 'object');
  Entry.AddPair('properties', MakeValueEntryProps);
  Entry.AddPair('required', MakeValueEntryRequired);

  Values := TJSONObject.Create;
  Values.AddPair('type', 'array');
  Values.AddPair('minItems', TJSONNumber.Create(1));
  Values.AddPair('maxItems', TJSONNumber.Create(MAX_VALUE_BATCH));
  Values.AddPair('items', Entry);
  Values.AddPair('description', 'Values to store, each with the add_value fields');
  Props.AddPair('values', Values);

  Props.AddPair('confirm_out_of_range', MakeConfirmProp);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('values');
  Result.AddPair('required', Req);
end;


function HandleMoveItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId, TargetProjectId, TargetFolderId: Integer;
  Item: TItem;
  OldProjectId: Integer;
  NewProject: TProject;
  NewFolder: TFolder;
  Items: TItemModel;
  Relocator: IFileRelocator;
  IsCrossProject: Boolean;
begin
  ItemId := GetReqInt(Params, 'item_id');
  TargetProjectId := GetReqInt(Params, 'target_project_id');
  TargetFolderId := GetReqInt(Params, 'target_folder_id');

  // Scope first, both ends, with the uniform refusal - before any of the
  // friendlier errors below can differentiate out-of-scope subjects.
  RequireItemRead(Context, ItemId);
  RequireProjectRead(Context, TargetProjectId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);
  if Item.Parent <> 0 then
    raise Exception.Create('Item has a parent — only root-level items can be moved. ' +
      'To move sub-items, move the parent item.');
  if IsItemSignedCheck(Context.Manager, ItemId) then
    raise Exception.Create('Item is signed and cannot be moved.');

  OldProjectId := Item.ProjectID;
  IsCrossProject := OldProjectId <> TargetProjectId;

  CheckProjectWriteAccess(Context, OldProjectId);
  if IsCrossProject then
    CheckProjectWriteAccess(Context, TargetProjectId);

  NewProject := Context.Manager.Find<TProject>(TargetProjectId);
  if not Assigned(NewProject) then
    raise Exception.CreateFmt('Target project not found: %d', [TargetProjectId]);
  NewFolder := NewProject.GetFolder(TargetFolderId);
  if not Assigned(NewFolder) then
    raise Exception.CreateFmt('Folder %d not found in project %d',
      [TargetFolderId, TargetProjectId]);

  Relocator := TNotebookFileRelocator.Create(Context.Storage);
  Items := TItemModel.Create(Context.Manager);
  try
    if not Items.MoveProc(Item, TargetProjectId, TargetFolderId,
      Context.User.Id, Relocator) then
      raise Exception.Create('MoveProc failed (signed item or DB conflict).');
  finally
    Items.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Item.Id));
  Result.AddPair('url', MakeElnItemUrl(Item));
  Result.AddPair('title', Item.Title);
  Result.AddPair('target_project_id', TJSONNumber.Create(TargetProjectId));
  Result.AddPair('target_folder_id', TJSONNumber.Create(TargetFolderId));
end;

function MakeMoveItemSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of a root-level item to move (Proc, Specimen, etc.)');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Destination project ID');
  Props.AddPair('target_project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Destination folder ID within the target project');
  Props.AddPair('target_folder_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Req.Add('target_project_id');
  Req.Add('target_folder_id');
  Result.AddPair('required', Req);
end;


function FindFolderProject(Manager: TObjectManager; FolderId: Integer): TProject;
var
  Projects: TList<TProject>;
begin
  Projects := Manager.Find<TProject>
    .CreateAlias('FFolders', 'f')
    .Where(Linq['f.Id'] = FolderId)
    .List;
  try
    if Projects.Count = 0 then
      Exit(nil);
    Result := Projects[0];
  finally
    Projects.Free;
  end;
end;

function HandleMoveFolder(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FolderId, TargetProjectId, TargetParentFolderId: Integer;
  HasParent: Boolean;
  Folder: TFolder;
  SrcProject, DstProject: TProject;
  SrcProjectId: Integer;
  IsCrossProject: Boolean;
  Projects: TProjectsModel;
  Relocator: IFileRelocator;
  WalkId, WalkSteps, MaxSteps: Integer;
  WalkFolder: TFolder;
begin
  FolderId := GetReqInt(Params, 'folder_id');
  TargetProjectId := GetReqInt(Params, 'target_project_id');
  HasParent := GetOptInt(Params, 'target_parent_folder_id', TargetParentFolderId);
  if not HasParent then
    TargetParentFolderId := 0;

  // Under a scope the target project refuses uniformly up front, and a
  // missing folder must be indistinguishable from an out-of-scope one.
  RequireProjectRead(Context, TargetProjectId);

  SrcProject := FindFolderProject(Context.Manager, FolderId);
  if not Assigned(SrcProject) then
  begin
    if IsScopeActive(Context) then
      RaiseOutOfScope;
    raise Exception.CreateFmt('Folder not found: %d', [FolderId]);
  end;

  Folder := SrcProject.GetFolder(FolderId);
  SrcProjectId := SrcProject.Id;
  RequireProjectRead(Context, SrcProjectId);
  IsCrossProject := SrcProjectId <> TargetProjectId;

  CheckProjectWriteAccess(Context, SrcProjectId);
  if IsCrossProject then
    CheckProjectWriteAccess(Context, TargetProjectId);

  if IsCrossProject then
  begin
    DstProject := Context.Manager.Find<TProject>(TargetProjectId);
    if not Assigned(DstProject) then
      raise Exception.CreateFmt('Target project not found: %d', [TargetProjectId]);
  end
  else
    DstProject := SrcProject;

  if TargetParentFolderId <> 0 then
    if DstProject.GetFolder(TargetParentFolderId) = nil then
      raise Exception.CreateFmt('Target parent folder %d not found in project %d',
        [TargetParentFolderId, TargetProjectId]);

  // Cycle guard — reject moving a folder into itself or into one of its own
  // descendants. Either would persist a folder cycle that detaches the whole
  // subtree from the tree. Walk ParentFolderID from the target parent up toward
  // the root; if we meet the moved folder, the target is a descendant. The walk
  // is bounded by the project's folder count so a pre-existing cycle in the data
  // cannot loop forever.
  if TargetParentFolderId <> 0 then
  begin
    if TargetParentFolderId = FolderId then
      raise Exception.CreateFmt('Cannot move folder %d into itself.', [FolderId]);
    WalkId := TargetParentFolderId;
    MaxSteps := DstProject.Folders.Count + 1;
    WalkSteps := 0;
    while (WalkId <> 0) and (WalkSteps < MaxSteps) do
    begin
      if WalkId = FolderId then
        raise Exception.CreateFmt(
          'Cannot move folder %d into its own descendant (target parent %d).',
          [FolderId, TargetParentFolderId]);
      WalkFolder := DstProject.GetFolder(WalkId);
      if WalkFolder = nil then
        Break;
      WalkId := WalkFolder.ParentFolderID;
      Inc(WalkSteps);
    end;
  end;

  Relocator := TNotebookFileRelocator.Create(Context.Storage);
  Projects := TProjectsModel.Create(Context.Manager, Context.AccessPolicy);
  try
    if not Projects.MoveFolder(Folder, SrcProjectId, TargetProjectId,
      TargetParentFolderId, Context.User.Id, Relocator) then
      raise Exception.Create('MoveFolder failed (DB conflict).');
  finally
    Projects.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Folder.Id));
  Result.AddPair('title', Folder.Title);
  Result.AddPair('target_project_id', TJSONNumber.Create(TargetProjectId));
  Result.AddPair('target_parent_folder_id', TJSONNumber.Create(TargetParentFolderId));
end;

function MakeMoveFolderSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of the folder to move');
  Props.AddPair('folder_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Destination project ID');
  Props.AddPair('target_project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Parent folder ID in destination (default: 0 = project root)');
  Props.AddPair('target_parent_folder_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('folder_id');
  Req.Add('target_project_id');
  Result.AddPair('required', Req);
end;


function HandleRelocateItemFiles(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  IdsArr: TJSONValue;
  Arr: TJSONArray;
  SourceProjectId, DstProjectId, i, ItemId: Integer;
  SrcProject, DstProject: TProject;
  Item: TItem;
  Items: TList<TItem>;
  PerItem: TJSONObject;
  ItemArr: TJSONArray;
  TotalFiles, ItemFiles: Integer;
  F: TFile;
begin
  IdsArr := nil;
  if Params <> nil then
    IdsArr := Params.FindValue('item_ids');
  if not (IdsArr is TJSONArray) then
    raise Exception.Create('Missing required parameter: item_ids (array of integers)');
  Arr := TJSONArray(IdsArr);
  if Arr.Count = 0 then
    raise Exception.Create('item_ids must contain at least one id');

  SourceProjectId := GetReqInt(Params, 'source_project_id');
  RequireProjectRead(Context, SourceProjectId);

  SrcProject := Context.Manager.Find<TProject>(SourceProjectId);
  if not Assigned(SrcProject) then
    raise Exception.CreateFmt('Source project not found: %d', [SourceProjectId]);

  Items := TList<TItem>.Create;
  try
    DstProjectId := 0;
    for i := 0 to Arr.Count - 1 do
    begin
      ItemId := (Arr.Items[i] as TJSONNumber).AsInt;
      RequireItemRead(Context, ItemId);
      Item := Context.Manager.Find<TItem>(ItemId);
      if not Assigned(Item) then
        raise Exception.CreateFmt('Item not found: %d', [ItemId]);
      if Item.IsDeleted then
        raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);
      if Item.Parent <> 0 then
        raise Exception.CreateFmt(
          'Item %d has a parent; only root-level items can be relocated. ' +
          'Include the root item instead.', [ItemId]);
      if IsItemSignedCheck(Context.Manager, ItemId) then
        raise Exception.CreateFmt('Item %d is signed and cannot be relocated.', [ItemId]);

      if i = 0 then
        DstProjectId := Item.ProjectID
      else if Item.ProjectID <> DstProjectId then
        raise Exception.CreateFmt(
          'All item_ids must currently live in the same project. ' +
          'Item %d is in project %d, expected %d.',
          [ItemId, Item.ProjectID, DstProjectId]);

      Items.Add(Item);
    end;

    if SourceProjectId = DstProjectId then
      raise Exception.CreateFmt(
        'source_project_id (%d) equals the items'' current project. ' +
        'Nothing to relocate.', [SourceProjectId]);

    DstProject := Context.Manager.Find<TProject>(DstProjectId);
    if not Assigned(DstProject) then
      raise Exception.CreateFmt('Destination project not found: %d', [DstProjectId]);

    CheckProjectWriteAccess(Context, SourceProjectId);
    CheckProjectWriteAccess(Context, DstProjectId);

    // Physical file relocation only — DB is already correct. Each file move is
    // isolated: a failure on one file is recorded and the rest still proceed, so
    // a partial storage outage does not abort the whole batch with no report of
    // what moved. The result carries a machine-readable failure list so the
    // caller can retry just the stragglers.
    var Relocator: IFileRelocator := TNotebookFileRelocator.Create(Context.Storage);
    var FF: unit_Item.TFile;
    var IT: TItem;
    var MovedFileCount := 0;
    // Guard FailedArr (and its per-file objects) until ownership transfers to
    // Result at the failed_files AddPair below — RecordAudit/SafeFlush can raise
    // before then and would otherwise leak it in the long-lived server.
    var FailedArr := TJSONArray.Create;
    try
    for IT in Items do
      for FF in IT.Files do
      begin
        try
          Relocator.MoveFile(
            BuildItemFileRemotePath(SrcProject.FileFolder, IT.FolderName, FF.FullName),
            BuildItemFileRemotePath(DstProject.FileFolder, IT.FolderName, FF.FullName));
          Inc(MovedFileCount);
        except
          on E: Exception do
          begin
            var FailObj := TJSONObject.Create;
            FailObj.AddPair('item_id', TJSONNumber.Create(IT.Id));
            FailObj.AddPair('file', FF.FullName);
            FailObj.AddPair('error', E.Message);
            FailedArr.AddElement(FailObj);
          end;
        end;
      end;

    TotalFiles := 0;
    for Item in Items do
    begin
      ItemFiles := 0;
      for F in Item.Files do
        Inc(ItemFiles);
      Inc(TotalFiles, ItemFiles);
      RecordAudit(Context.Manager, aetItem, Item.Id, aoUpdate,
        Context.User.Id,
        Format('MCP: Relocated %d file(s) in storage from project %d to project %d (repair)',
          [ItemFiles, SourceProjectId, DstProjectId]));
    end;
    TConflictHandler.SafeFlush(Context.Manager);

    Result := TJSONObject.Create;
    Result.AddPair('source_project_id', TJSONNumber.Create(SourceProjectId));
    Result.AddPair('target_project_id', TJSONNumber.Create(DstProjectId));
    Result.AddPair('relocated_item_count', TJSONNumber.Create(Items.Count));
    Result.AddPair('relocated_file_count', TJSONNumber.Create(TotalFiles));
    Result.AddPair('moved_file_count', TJSONNumber.Create(MovedFileCount));
    Result.AddPair('failed_file_count', TJSONNumber.Create(FailedArr.Count));
    Result.AddPair('failed_files', FailedArr);
    except
      FailedArr.Free;
      raise;
    end;

    ItemArr := TJSONArray.Create;
    for Item in Items do
    begin
      ItemFiles := 0;
      for F in Item.Files do
        Inc(ItemFiles);
      PerItem := TJSONObject.Create;
      PerItem.AddPair('id', TJSONNumber.Create(Item.Id));
      PerItem.AddPair('url', MakeElnItemUrl(Item));
      PerItem.AddPair('title', Item.Title);
      PerItem.AddPair('files_moved', TJSONNumber.Create(ItemFiles));
      ItemArr.AddElement(PerItem);
    end;
    Result.AddPair('items', ItemArr);
  finally
    Items.Free;
  end;
end;

function MakeRelocateItemFilesSchema: TJSONObject;
var
  Props, P, IdsItem: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  IdsItem := TJSONObject.Create;
  IdsItem.AddPair('type', 'integer');
  P.AddPair('items', IdsItem);
  P.AddPair('description',
    'Root-level item IDs whose attached files should be relocated in storage. ' +
    'All items must currently live in the same (destination) project.');
  Props.AddPair('item_ids', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Project ID the files currently live under in storage (i.e., the pre-repair ' +
    'project). The destination project is taken from the items'' current ProjectID.');
  Props.AddPair('source_project_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_ids');
  Req.Add('source_project_id');
  Result.AddPair('required', Req);
end;


{ Attachment paths follow project/item/file identities, not the ELN folder tree.
  Cross-project moves and renames can leave bytes under stale names; id tokens
  survive both. Search by those tokens and refuse ambiguous matches. Missing
  bytes cannot be relocated: report lost and use reattach_file. }

type
  TRepairCache = class
  private
    FStorage: INotebookStorageInspection;
    FListings: TDictionary<string, TArray<string>>;
    FProjects: TList<TProject>;
    FContext: TToolContext;
  public
    constructor Create(const Context: TToolContext);
    destructor Destroy; override;
    // One listing per collection per call, however many files need it. An
    // item's files all share a folder, and every file in the run shares the
    // project listing, so an uncached hunt would re-walk the whole tree once
    // per missing file.
    function List(const ACollection: string): TArray<string>;
    function SourceProjectId(const Folder: string): Integer;
  end;

constructor TRepairCache.Create(const Context: TToolContext);
begin
  inherited Create;
  if not Supports(Context.Storage, INotebookStorageInspection, FStorage) then
    raise Exception.Create('Storage provider does not support attachment inspection.');
  FListings := TDictionary<string, TArray<string>>.Create;
  FContext := Context;
  RequireToolPrincipal(Context);
  // UI project lists can omit readable projects owned by other accounts.
  // SourceProjectId applies the access policy and device scope before traversal.
  FProjects := Context.Manager.Find<TProject>.List;
end;

destructor TRepairCache.Destroy;
begin
  FProjects.Free;
  FListings.Free;
  inherited Destroy;
end;

function TRepairCache.List(const ACollection: string): TArray<string>;
begin
  if FListings.TryGetValue(ACollection, Result) then
    Exit;
  if not FStorage.ListCollection(ACollection, Result) then
    raise Exception.Create('Storage collection could not be inspected: ' + ACollection);
  FListings.Add(ACollection, Result);
end;

function TRepairCache.SourceProjectId(const Folder: string): Integer;
var
  Project: TProject;
begin
  Result := 0;
  // Unknown historical folders are not an authority to inspect or move bytes.
  for Project in FProjects do
    if ((Folder = CleanFileName(Project.FileFolder)) or
        StartsStr(ProjectFolderToken(Project.Id), Folder)) and
       IsProjectVisible(FContext, Project.Id) then
      Exit(Project.Id);
end;

const
  PROJECTS_ROOT = 'Projects';

function HuntForStrays(Cache: TRepairCache;
  ItemId: Integer; FileId: Int64): TArray<string>;
var
  ProjectFolders, ItemFolders, FileNames: TArray<string>;
  ProjectFolder, ItemFolder, FileName: string;
  N: Integer;
begin
  Result := nil;
  N := 0;
  ProjectFolders := Cache.List(PROJECTS_ROOT);
  for ProjectFolder in ProjectFolders do
  begin
    if Cache.SourceProjectId(ProjectFolder) = 0 then
      Continue;
    ItemFolders := FindNamesWithToken(
      Cache.List(PROJECTS_ROOT + '/' + ProjectFolder), ItemFolderToken(ItemId));
    for ItemFolder in ItemFolders do
    begin
      FileNames := FindNamesWithToken(
        Cache.List(PROJECTS_ROOT + '/' + ProjectFolder + '/' + ItemFolder),
        FileNameToken(FileId));
      for FileName in FileNames do
      begin
        // Concatenated, NOT built with BuildItemFileRemotePath: these segments
        // were read back from storage and are already in their stored form.
        // Running them through CleanFileName again would rewrite characters
        // the server is actually serving, producing a path that 404s.
        if N = Length(Result) then
          SetLength(Result, N + 4);
        Result[N] := PROJECTS_ROOT + '/' + ProjectFolder + '/' + ItemFolder +
          '/' + FileName;
        Inc(N);
      end;
    end;
  end;
  SetLength(Result, N);
end;

procedure CollectItemTree(const Context: TToolContext; RootId: Integer;
  Recursive: Boolean; Target: TList<TItem>);
var
  Root: TItem;
  Dic: TItemDictionary;
  Candidates: TList<TItem>;

  procedure AddDescendants(ParentId: Integer);
  var
    Child: TItem;
  begin
    for Child in Candidates do
      if Child.Parent = ParentId then
      begin
        Target.Add(Child);
        AddDescendants(Child.Id);
      end;
  end;

begin
  Root := Context.Manager.Find<TItem>(RootId);
  if not Assigned(Root) then
    raise Exception.CreateFmt('Item not found: %d', [RootId]);
  Target.Add(Root);
  if not Recursive then
    Exit;

  Dic := TItemDictionary.Create;
  try
    Candidates := Context.Manager.Find<TItem>
      .Where((Dic.ProjectID = Root.ProjectID) and (Dic.IsDeleted = False))
      .List;
    try
      AddDescendants(Root.Id);
    finally
      Candidates.Free;
    end;
  finally
    Dic.Free;
  end;
end;

procedure CollectProjectItems(const Context: TToolContext; ProjectId: Integer;
  Target: TList<TItem>);
var
  Dic: TItemDictionary;
  Rows: TList<TItem>;
  Item: TItem;
begin
  Dic := TItemDictionary.Create;
  try
    Rows := Context.Manager.Find<TItem>
      .Where((Dic.ProjectID = ProjectId) and (Dic.IsDeleted = False))
      .List;
    try
      for Item in Rows do
        Target.Add(Item);
    finally
      Rows.Free;
    end;
  finally
    Dic.Free;
  end;
end;

function ItemListIds(Items: TList<TItem>): TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, Items.Count);
  for I := 0 to Items.Count - 1 do
    Result[I] := Items[I].Id;
end;

function CollectItemTreeIds(const Context: TToolContext;
  RootId: Integer): TArray<Integer>;
var
  Items: TList<TItem>;
begin
  Items := TList<TItem>.Create;
  try
    CollectItemTree(Context, RootId, True, Items);
    Result := ItemListIds(Items);
  finally
    Items.Free;
  end;
end;

function CollectProjectItemIds(const Context: TToolContext;
  ProjectId: Integer): TArray<Integer>;
var
  Items: TList<TItem>;
begin
  Items := TList<TItem>.Create;
  try
    CollectProjectItems(Context, ProjectId, Items);
    Result := ItemListIds(Items);
  finally
    Items.Free;
  end;
end;

function HandleRepairFiles(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId, ProjectId: Integer;
  HasItem, HasProject, Recursive, DryRun: Boolean;
  Items: TList<TItem>;
  Item: TItem;
  Project: TProject;
  F: unit_Item.TFile;
  Cache: TRepairCache;
  Inspection: INotebookStorageInspection;
  FilesArr, CandArr: TJSONArray;
  Entry, Summary: TJSONObject;
  Expected, Found, Status, Candidate: string;
  Candidates: TArray<string>;
  HttpStatus, Checked: Integer;
  ContentLength: Int64;
  CountOk, CountEmpty, CountRelocated, CountRelocatable: Integer;
  CountAmbiguous, CountLost, CountError: Integer;
begin
  if not Supports(Context.Storage, INotebookStorageInspection, Inspection) then
    raise Exception.Create('Storage provider does not support attachment inspection.');
  ItemId := 0;
  ProjectId := 0;
  HasItem := GetOptInt(Params, 'item_id', ItemId);
  HasProject := GetOptInt(Params, 'project_id', ProjectId);
  if HasItem = HasProject then
    raise Exception.Create('Provide exactly one of item_id or project_id.');

  Recursive := GetOptBool(Params, 'recursive', True);
  DryRun := GetOptBool(Params, 'dry_run', True);

  CountOk := 0; CountEmpty := 0; CountRelocated := 0; CountRelocatable := 0;
  CountAmbiguous := 0; CountLost := 0; CountError := 0;
  Checked := 0;
  HttpStatus := 0;
  ContentLength := 0;

  Items := TList<TItem>.Create;
  try
    if HasItem then
    begin
      RequireItemRead(Context, ItemId);
      CollectItemTree(Context, ItemId, Recursive, Items);
      ProjectId := Items[0].ProjectID;
    end
    else
    begin
      RequireProjectRead(Context, ProjectId);
      CollectProjectItems(Context, ProjectId, Items);
    end;

    // A repair is a write even under dry_run: the same permission governs
    // whether this caller may inspect and rearrange this project's storage.
    CheckProjectWriteAccess(Context, ProjectId);

    FilesArr := TJSONArray.Create;
    Cache := TRepairCache.Create(Context);
    try
      for Item in Items do
      begin
        Project := Context.Manager.Find<TProject>(Item.ProjectID);
        if not Assigned(Project) then
          Continue;

        for F in Item.Files do
        begin
          Inc(Checked);
          Expected := BuildItemStoragePath(
            Project.FileFolder, Item.FolderName, F.FullName);
          Found := '';
          Candidates := nil;
          HttpStatus := 0;
          ContentLength := 0;
          try

          if Inspection.TryGetFileInfo(Expected, HttpStatus, ContentLength) then
          begin
            // ContentLength -1 means the server sent no Content-Length, which
            // is not evidence of an empty file, so it counts as ok.
            if ContentLength = 0 then
            begin
              Status := 'empty';
              Inc(CountEmpty);
            end
            else
            begin
              Status := 'ok';
              Inc(CountOk);
            end;
          end
          else if HttpStatus <> 404 then
          begin
            // Anything that is not a clean 404 means storage could not answer,
            // not that the file is gone. Hunting here would report an entire
            // project as lost during an outage.
            Status := 'error';
            Inc(CountError);
          end
          else
          begin
            Candidates := HuntForStrays(Cache, Item.Id, F.Id);
            case ResolveSingleMatch(Candidates, Found) of
              loNotFound:
                begin
                  Status := 'lost';
                  Inc(CountLost);
                end;
              loAmbiguous:
                begin
                  Status := 'ambiguous';
                  Inc(CountAmbiguous);
                end;
            else
              if DryRun then
              begin
                Status := 'relocatable';
                Inc(CountRelocatable);
              end
              else
              begin
                try
                  CheckProjectWriteAccess(Context, Cache.SourceProjectId(
                    Copy(Found, Length(PROJECTS_ROOT) + 2,
                      PosEx('/', Found, Length(PROJECTS_ROOT) + 2) -
                        Length(PROJECTS_ROOT) - 2)));
                  Context.Storage.MoveFile(Found, Expected);
                  Status := 'relocated';
                  Inc(CountRelocated);
                except
                  on E: Exception do
                  begin
                    Status := 'error';
                    Inc(CountError);
                    MCPLog(Format('repair_files: MOVE failed %s -> %s: %s',
                      [Found, Expected, E.Message]));
                  end;
                end;
              end;
            end;
          end;
          except
            on E: Exception do
            begin
              Status := 'error';
              Inc(CountError);
              MCPLog(Format('repair_files: inspection failed for %s: %s',
                [Expected, E.Message]));
            end;
          end;
          // Database/audit failures must propagate, not masquerade as storage
          // inspection failures after bytes have already been relocated.
          if Status = 'relocated' then
            RecordAudit(Context.Manager, aetFile, F.Id, aoUpdate,
              Context.User.Id,
              Format('MCP: Relocated file "%s" in storage from %s (repair)',
                [F.FullName, Found]));

          Entry := TJSONObject.Create;
          Entry.AddPair('file_id', TJSONNumber.Create(F.Id));
          Entry.AddPair('item_id', TJSONNumber.Create(Item.Id));
          Entry.AddPair('item_title', Item.Title);
          Entry.AddPair('full_name', F.FullName);
          Entry.AddPair('expected_path', Expected);
          Entry.AddPair('status', Status);
          if Status = 'ok' then
            Entry.AddPair('size', TJSONNumber.Create(ContentLength));
          if Found <> '' then
            Entry.AddPair('found_at', Found);
          if Status = 'ambiguous' then
          begin
            CandArr := TJSONArray.Create;
            for Candidate in Candidates do
              CandArr.Add(Candidate);
            Entry.AddPair('candidates', CandArr);
          end;
          if Status = 'error' then
            Entry.AddPair('http_status', TJSONNumber.Create(HttpStatus));
          FilesArr.AddElement(Entry);
        end;
      end;

      if CountRelocated > 0 then
        TConflictHandler.SafeFlush(Context.Manager);
    finally
      Cache.Free;
    end;

    Summary := TJSONObject.Create;
    Summary.AddPair('ok', TJSONNumber.Create(CountOk));
    Summary.AddPair('empty', TJSONNumber.Create(CountEmpty));
    Summary.AddPair('relocated', TJSONNumber.Create(CountRelocated));
    Summary.AddPair('relocatable', TJSONNumber.Create(CountRelocatable));
    Summary.AddPair('ambiguous', TJSONNumber.Create(CountAmbiguous));
    Summary.AddPair('lost', TJSONNumber.Create(CountLost));
    Summary.AddPair('error', TJSONNumber.Create(CountError));

    Result := TJSONObject.Create;
    Result.AddPair('dry_run', TJSONBool.Create(DryRun));
    Result.AddPair('checked_file_count', TJSONNumber.Create(Checked));
    Result.AddPair('summary', Summary);
    Result.AddPair('files', FilesArr);
  finally
    Items.Free;
  end;
end;

function MakeRepairFilesSchema: TJSONObject;
var
  Props, P: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Item to check. Its descendants are included unless recursive is false. ' +
    'Provide exactly one of item_id or project_id.');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Check every file of every item in this project. ' +
    'Provide exactly one of item_id or project_id.');
  Props.AddPair('project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'boolean');
  P.AddPair('description',
    'With item_id, also check the item''s descendants (default true). ' +
    'Ignored with project_id.');
  Props.AddPair('recursive', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'boolean');
  P.AddPair('description',
    'Report what would be moved without moving anything (default TRUE). ' +
    'Re-run with dry_run false to commit the relocations.');
  Props.AddPair('dry_run', P);

  Result.AddPair('properties', Props);
end;


function HandleReattachFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Int64;
  FilePath: string;
  Force, Existed: Boolean;
  F: unit_Item.TFile;
  Item: TItem;
  Project: TProject;
  RemotePath, Hash: string;
  HttpStatus: Integer;
  Inspection: INotebookStorageInspection;
  ContentLength: Int64;
begin
  FileId := GetReqInt64(Params, 'file_id');
  FilePath := GetReqStr(Params, 'file_path');
  Force := GetOptBool(Params, 'force', False);

  CheckUploadPathAllowed(Context, FilePath);
  if not System.SysUtils.FileExists(FilePath) then
    raise Exception.CreateFmt('Local file not found: %s', [FilePath]);

  RequireFileRead(Context, FileId);
  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);
  Item := F.Item;
  if not Assigned(Item) then
    raise Exception.CreateFmt('File %d has no item.', [FileId]);

  CheckProjectWriteAccess(Context, Item.ProjectID);
  if IsItemSignedCheck(Context.Manager, Item.Id) then
    raise Exception.CreateFmt(
      'Item %d is signed; its files cannot be reattached.', [Item.Id]);

  Project := Context.Manager.Find<TProject>(Item.ProjectID);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project not found: %d', [Item.ProjectID]);

  RemotePath := BuildItemStoragePath(
    Project.FileFolder, Item.FolderName, F.FullName);

  // Fill gaps only. Overwriting a healthy file would destroy exactly the data
  // this tool exists to protect, and the caller cannot see what is there.
  HttpStatus := 0;
  ContentLength := 0;
  if not Supports(Context.Storage, INotebookStorageInspection, Inspection) then
    raise Exception.Create('Storage provider does not support attachment inspection.');
  Existed := Inspection.TryGetFileInfo(RemotePath, HttpStatus, ContentLength);
  if not Existed and (HttpStatus <> 404) then
    raise Exception.CreateFmt('Storage could not inspect file %d (status %d).',
      [FileId, HttpStatus]);
  if Existed and not Force then
    raise Exception.CreateFmt(
      'File %d already has %d byte(s) in storage at %s. reattach_file only ' +
      'fills gaps; pass force true to overwrite.',
      [FileId, ContentLength, RemotePath]);

  Hash := ComputeFileMD5(FilePath);

  // Store bytes first: this existing row already supplies the path id. A failed
  // write must preserve the row and its links, values and history.
  Context.Storage.CopyIn(FilePath, RemotePath);

  F.Hash := Hash;
  Context.Manager.Update(F);
  RecordAudit(Context.Manager, aetFile, F.Id, aoUpdate, Context.User.Id,
    Format('MCP: Reattached bytes for file "%s" on item "%s" (repair)',
      [F.FullName, Item.Title]));
  TConflictHandler.SafeFlush(Context.Manager);

  Result := TJSONObject.Create;
  Result.AddPair('file_id', TJSONNumber.Create(F.Id));
  Result.AddPair('title', F.Title);
  Result.AddPair('full_name', F.FullName);
  Result.AddPair('path', RemotePath);
  Result.AddPair('hash', Hash);
  Result.AddPair('overwritten', TJSONBool.Create(Existed));
end;

function MakeReattachFileSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Existing file record to restore bytes for. The record is kept, so its ' +
    'id, links and history survive.');
  Props.AddPair('file_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Local path of the file to upload. Must sit under the server''s ' +
    'configured MCPUploadRoot.');
  Props.AddPair('file_path', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'boolean');
  P.AddPair('description',
    'Overwrite bytes already in storage (default false). Without it the ' +
    'call is refused when the file is already present.');
  Props.AddPair('force', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Req.Add('file_path');
  Result.AddPair('required', Req);
end;


function HandleMoveFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Int64;
  TargetId, SourceId, HypId: Integer;
  HypStatus: THypothesisStatus;
  F: unit_Item.TFile;
  Source, Target: TItem;
  Project: TProject;
  Cites: TList<THypothesisEvidence>;
  OldPath, NewPath, FileTitle, TargetTitle: string;
  Relocator: IFileRelocator;
begin
  FileId := GetReqInt64(Params, 'file_id');
  TargetId := GetReqInt(Params, 'target_item_id');

  RequireFileRead(Context, FileId);
  RequireItemRead(Context, TargetId);

  // The session's manager is long-lived: judge (and build paths from) what is
  // committed now, not what was cached - a title renamed in the desktop since
  // would put the bytes under a stale folder name.
  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);
  Context.Manager.Refresh(F);
  Source := F.Item;
  if not Assigned(Source) then
    raise Exception.CreateFmt('File %d has no item.', [FileId]);
  Context.Manager.Refresh(Source);
  // The scope check above ran on the cached row; re-check on committed state
  // before any message below can name another project.
  RequireProjectRead(Context, Source.ProjectID);
  SourceId := Source.Id;
  Target := Context.Manager.Find<TItem>(TargetId);
  if not Assigned(Target) then
    raise Exception.CreateFmt('Item not found: %d', [TargetId]);
  Context.Manager.Refresh(Target);
  RequireProjectRead(Context, Target.ProjectID);
  if TargetId = SourceId then
    raise Exception.CreateFmt('File %d already belongs to item %d.', [FileId, TargetId]);
  if Source.IsDeleted or Target.IsDeleted then
    raise Exception.Create('Source or target item is deleted.');
  if Target.ProjectID <> Source.ProjectID then
    raise Exception.CreateFmt(
      'Target item %d is in project %d, the file in project %d; move_file ' +
      'only moves within one project.', [TargetId, Target.ProjectID, Source.ProjectID]);

  CheckProjectWriteAccess(Context, Source.ProjectID);

  if IsItemSignedCheck(Context.Manager, SourceId) then
    raise Exception.Create('The file''s item is signed; its files cannot be moved.');
  if IsItemSignedCheck(Context.Manager, TargetId) then
    raise Exception.Create('Target item is signed and cannot be modified.');
  // Moving a file out of an item takes it out of what a locked hypothesis
  // cites, which the delete guard (spec 6.5) forbids for the same reason.
  if IsItemCitedByLockedHypothesis(Context.Manager, SourceId, HypId, HypStatus) then
    raise Exception.CreateFmt(
      'Item %d is cited by hypothesis %d (%s); its files cannot be moved.',
      [SourceId, HypId, HypothesisStatusNames[HypStatus]]);
  // Evidence rows pin the file to its item (ItemId + FileId); a moved file
  // would read as Missing evidence, whatever the hypothesis status.
  Cites := Context.Manager.Find<THypothesisEvidence>
    .Where(Linq['FileId'] = FileId).Take(1).List;
  try
    if Cites.Count > 0 then
      raise Exception.CreateFmt(
        'File %d is cited as evidence by hypothesis %d; remove that evidence ' +
        'first or leave the file where it is.', [FileId, Cites[0].HypothesisId]);
  finally
    Cites.Free;
  end;

  if not Assigned(Context.Storage) then
    raise Exception.Create('move_file needs notebook storage; this server has none.');

  Project := Context.Manager.Find<TProject>(Source.ProjectID);
  OldPath := BuildItemFileRemotePath(Project.FileFolder, Source.FolderName, F.FullName);
  NewPath := BuildItemFileRemotePath(Project.FileFolder, Target.FolderName, F.FullName);
  FileTitle := F.Title;
  TargetTitle := Target.Title;

  Relocator := TNotebookFileRelocator.Create(Context.Storage);
  try
    Relocator.MoveFile(OldPath, NewPath);
  except
    on E: Exception do
      raise Exception.CreateFmt(
        '%s. Nothing was changed; if the bytes are missing, run repair_files ' +
        'on item %d.', [E.Message, SourceId]);
  end;

  // Then the row - changing the FK only, never the proxy collections
  // (CascadeAllRemoveOrphan on TItem.Files would delete it as an orphan).
  // Only a failed save moves the bytes back; anything after it runs on a
  // committed move.
  F.Item := Target;
  F.ModifiedDate := UTCNow;
  F.ModifiedBy := Context.User.Id;
  try
    Context.Manager.Update(F);
    if not TConflictHandler.SafeFlush(Context.Manager) then
      raise Exception.Create('the file changed elsewhere');
  except
    on E: Exception do
    begin
      try
        Relocator.MoveFile(NewPath, OldPath);
      except
        on E2: Exception do
          raise Exception.CreateFmt(
            'Moving file %d failed in the database (%s), and moving its bytes ' +
            'back also failed (%s). They are at %s; run repair_files on item %d.',
            [FileId, E.Message, E2.Message, NewPath, SourceId]);
      end;
      raise Exception.CreateFmt(
        'Moving file %d failed in the database (%s); its bytes were moved back.',
        [FileId, E.Message]);
    end;
  end;

  try
    RecordAudit(Context.Manager, aetFile, FileId, aoUpdate, Context.User.Id,
      Format('MCP: Moved file "%s" from item %d to item %d "%s"',
        [FileTitle, SourceId, TargetId, TargetTitle]));
  except
    on E: Exception do
      raise Exception.CreateFmt(
        'File %d was moved to item %d, but its audit row could not be written: %s',
        [FileId, TargetId, E.Message]);
  end;

  // Evict both cached Files lists so later renames reload the moved file.
  // Evict detaches these objects; it does not free them.
  try
    // Items first: their Files lists may cascade-evict F already.
    Context.Manager.Evict(Source);
    Context.Manager.Evict(Target);
    if Context.Manager.IsAttached(F) then
      Context.Manager.Evict(F);
  except
    on E: Exception do
      MCPLog(Format('move_file: evict after moving file %d failed: %s',
        [FileId, E.Message]));
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file_id', TJSONNumber.Create(FileId));
  Result.AddPair('title', FileTitle);
  Result.AddPair('from_item_id', TJSONNumber.Create(SourceId));
  Result.AddPair('item_id', TJSONNumber.Create(TargetId));
  Result.AddPair('item_title', TargetTitle);
end;

function MakeMoveFileSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of the file to move');
  Props.AddPair('file_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of the item to move it to (same project)');
  Props.AddPair('target_item_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Req.Add('target_item_id');
  Result.AddPair('required', Req);
end;


function HandleReparentItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId, NewParentId, OldParentId, WalkId, Steps: Integer;
  Item, NewParent, Walk: TItem;
  ParentTitle: string;
begin
  ItemId := GetReqInt(Params, 'item_id');
  NewParentId := GetReqInt(Params, 'new_parent_id');

  RequireItemRead(Context, ItemId);
  if NewParentId <> 0 then
    RequireItemRead(Context, NewParentId);

  // Judge committed state, not the long-lived session cache (see move_file).
  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);
  Context.Manager.Refresh(Item);
  RequireProjectRead(Context, Item.ProjectID);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);
  OldParentId := Item.Parent;

  ParentTitle := '(root)';
  if NewParentId <> 0 then
  begin
    if NewParentId = ItemId then
      raise Exception.Create('An item cannot be its own parent.');
    NewParent := Context.Manager.Find<TItem>(NewParentId);
    if not Assigned(NewParent) then
      raise Exception.CreateFmt('Parent item not found: %d', [NewParentId]);
    Context.Manager.Refresh(NewParent);
    RequireProjectRead(Context, NewParent.ProjectID);
    if NewParent.IsDeleted then
      raise Exception.CreateFmt('Parent item %d is deleted.', [NewParentId]);
    if NewParent.ProjectID <> Item.ProjectID then
      raise Exception.CreateFmt(
        'Parent item %d is in project %d, the item in project %d; use move_item ' +
        'to move a root item between projects.',
        [NewParentId, NewParent.ProjectID, Item.ProjectID]);
    if NewParent.FolderID <> Item.FolderID then
      raise Exception.CreateFmt(
        'Parent item %d is in folder %d, the item in folder %d; use move_item ' +
        'to move a root item between folders first.',
        [NewParentId, NewParent.FolderID, Item.FolderID]);
    if NewParent.Level = TItemLevel.Folder then
      raise Exception.Create('A Folder-level item cannot be a parent.');
    // The new parent must not sit inside the item's own subtree, nor under a
    // deleted ancestor (single-item delete leaves children live but hidden).
    WalkId := NewParent.Parent;
    Steps := 0;
    while WalkId <> 0 do
    begin
      if WalkId = ItemId then
        raise Exception.CreateFmt(
          'Item %d is a descendant of item %d; an item cannot move under its own subtree.',
          [NewParentId, ItemId]);
      Inc(Steps);
      if Steps > 1000 then
        raise Exception.CreateFmt(
          'The parent chain above item %d is deeper than 1000 or loops.', [NewParentId]);
      Walk := Context.Manager.Find<TItem>(WalkId);
      if not Assigned(Walk) then
        Break;
      Context.Manager.Refresh(Walk);
      if Walk.IsDeleted then
        raise Exception.CreateFmt(
          'Item %d sits under deleted item %d; it cannot take new children.',
          [NewParentId, WalkId]);
      WalkId := Walk.Parent;
    end;
    ParentTitle := NewParent.Title;
  end;

  CheckProjectWriteAccess(Context, Item.ProjectID);

  if IsItemSignedCheck(Context.Manager, ItemId) then
    raise Exception.Create('Item is signed and cannot be moved.');
  if (OldParentId <> 0) and IsItemSignedCheck(Context.Manager, OldParentId) then
    raise Exception.Create('The item''s current parent is signed; its children cannot be moved.');
  if (NewParentId <> 0) and IsItemSignedCheck(Context.Manager, NewParentId) then
    raise Exception.Create('Parent item is signed and cannot be modified.');

  // An item's storage folder is [id]title under the project, whatever its
  // parent, so no bytes move.
  if NewParentId <> OldParentId then
  begin
    Item.Parent := NewParentId;
    Item.ModifiedDate := UTCNow;
    Item.ModifiedBy := Context.User.Id;
    if not TConflictHandler.SafeFlush(Context.Manager) then
      raise Exception.CreateFmt('Item %d changed elsewhere; nothing was moved.', [ItemId]);
    try
      RecordAudit(Context.Manager, aetItem, ItemId, aoUpdate, Context.User.Id,
        Format('MCP: Reparented item "%s": parent %d -> %d "%s"',
          [Item.Title, OldParentId, NewParentId, ParentTitle]));
    except
      on E: Exception do
        raise Exception.CreateFmt(
          'Item %d was moved under %d, but its audit row could not be written: %s',
          [ItemId, NewParentId, E.Message]);
    end;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(ItemId));
  Result.AddPair('url', MakeElnItemUrl(Item));
  Result.AddPair('title', Item.Title);
  Result.AddPair('old_parent_id', TJSONNumber.Create(OldParentId));
  Result.AddPair('new_parent_id', TJSONNumber.Create(NewParentId));
  Result.AddPair('changed', TJSONBool.Create(NewParentId <> OldParentId));
end;

function MakeReparentItemSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of the item to move');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of the new parent item (same project and folder), ' +
    'or 0 to make it a root item of its folder');
  Props.AddPair('new_parent_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Req.Add('new_parent_id');
  Result.AddPair('required', Req);
end;


procedure RegisterWriteTools(Registry: TToolRegistry);
begin
  Registry.Register('create_project',
    'Create a new project owned by the current principal.',
    MakeCreateProjectSchema, HandleCreateProject, tscProjectScoped);

  Registry.Register('create_folder',
    'Create a folder within a project. Requires write access.',
    MakeCreateFolderSchema, HandleCreateFolder, tscProjectScoped);

  Registry.Register('create_item',
    'Create an item (experiment, specimen, action) in a project/folder. ' +
    'Requires write access. Types: Synthesis, Treatment, Measurement, Testing, ' +
    'Characterization, Computing, Specimen, Model, Other. Levels: Proc, Item, Action, Folder.' +
    ' The response includes a `url` field — an eln://item/N (or ' +
    'eln://specimen/<title>) link that opens the item in the desktop ' +
    'ELN client when clicked in a markdown-rendering chat client.',
    MakeCreateItemSchema, HandleCreateItem, tscProjectScoped);

  Registry.Register('update_item',
    'Update editable fields of an item (title, description, properties). ' +
    'At least one field must be provided. Requires write access. Item must ' +
    'not be signed. Use move_item for parent/folder/project changes.' +
    ' The response includes a `url` field — an eln://item/N (or ' +
    'eln://specimen/<title>) link that opens the item in the desktop ' +
    'ELN client when clicked in a markdown-rendering chat client.',
    MakeUpdateItemSchema, HandleUpdateItem, tscProjectScoped);

  Registry.Register('upload_file',
    'Upload a local file and attach it to an item. Reads from disk, copies to storage, ' +
    'computes MD5 hash. Requires write access. Item must not be signed.',
    MakeUploadFileSchema, HandleUploadFile, tscProjectScoped);

  Registry.Register('rename_file',
    'Rename a file (change title and/or file type). Updates the DB record and ' +
    'renames the physical file in storage. Requires write access. Item must not be signed.',
    MakeRenameFileSchema, HandleRenameFile, tscProjectScoped);

  Registry.Register('add_value',
    'Add a numeric value (measurement, condition, analysis result) to an ' +
    'item. Requires write access. Item must not be signed. Store analysis ' +
    'and fit results as values with a source, not only as item text. For a ' +
    'number from a reader, call extract_file_key_values first and pass ' +
    'source_file_id = its file_id plus its reader_id, reader_version and ' +
    'key_name = the key value name. For a number from an analysis, pass ' +
    'source_file_id (the analysed file) and/or source_note with the job, ' +
    'run or script IDs. A value written without any source field is stored ' +
    'with source kind Unknown. The source file must belong to the item, one ' +
    'of its ancestors or one of its descendants in the same project. A ' +
    'value outside its value type range (list_value_types range_min/' +
    'range_max), or with a tolerance larger than |value| or smaller than ' +
    '|value| / tolerance_factor, is refused with the issue codes; check ' +
    'the number and units, and repeat with confirm_out_of_range: true only ' +
    'if it is correct. The response lists confirmed issues. Use add_values ' +
    'to store several values in one step.',
    MakeAddValueSchema, HandleAddValue, tscProjectScoped);

  Registry.Register('add_values',
    'Add up to 200 values in one all-or-nothing step, for example all ' +
    'results of one fit. Each entry takes the add_value fields (item_id, ' +
    'value, value_type_id, tolerance, description, rec_type and the source ' +
    'fields source_kind, source_file_id, reader_id, reader_version, ' +
    'key_name, source_note) with the same rules: give a source for every ' +
    'result; an entry without source fields is stored as Unknown. Every ' +
    'entry is checked before anything is written; if one entry is refused, ' +
    'the error names its index (values[i]) and nothing is stored. ' +
    'confirm_out_of_range: true applies to all entries. One audit row is ' +
    'written per value.',
    MakeAddValuesSchema, HandleAddValues, tscProjectScoped);

  Registry.Register('move_item',
    'Move a root-level item (Proc, Specimen, etc.) and all its children to a different ' +
    'project/folder. Relocates stored files for cross-project moves. Requires write ' +
    'access on both source and destination. Signed items cannot be moved.' +
    ' The response includes a `url` field — an eln://item/N (or ' +
    'eln://specimen/<title>) link that opens the item in the desktop ' +
    'ELN client when clicked in a markdown-rendering chat client.',
    MakeMoveItemSchema, HandleMoveItem, tscProjectScoped);

  Registry.Register('move_folder',
    'Move a folder and all its items to a different project or parent folder. ' +
    'Relocates stored files for cross-project moves. Requires write access on both ' +
    'source and destination. Folders containing signed items cannot be moved.',
    MakeMoveFolderSchema, HandleMoveFolder, tscProjectScoped);

  Registry.Register('relocate_item_files',
    'Repair tool: relocate attached files in storage for items whose DB record ' +
    'already points to the correct project, but whose physical files still live ' +
    'under a previous project''s directory (e.g. after a partially-completed ' +
    'desktop drag). Does NOT modify DB rows. Provide the item_ids (all must ' +
    'currently share the same ProjectID) and the source_project_id where files ' +
    'physically live now. Requires write access on both source and destination.' +
    ' Each per-item entry in the response includes a `url` field — an ' +
    'eln://item/N (or eln://specimen/<title>) link that opens the item ' +
    'in the desktop ELN client when clicked in a markdown-rendering chat client.',
    MakeRelocateItemFilesSchema, HandleRelocateItemFiles, tscProjectScoped);

  Registry.Register('repair_files',
    'Repair tool: check that every attached file of an item (and its ' +
    'descendants) or of a whole project actually has its bytes in attachment ' +
    'storage, and put back the ones that drifted. Per file the status is ' +
    'ok, empty (present but zero bytes), relocated / relocatable (found ' +
    'elsewhere in storage under a stale project or item folder and moved ' +
    'back, or reported under dry_run), ambiguous (several candidates - ' +
    'nothing is moved, they are listed instead), lost (no bytes anywhere - ' +
    'use reattach_file) or error (storage did not answer; not treated as ' +
    'missing). DRY RUN BY DEFAULT: pass dry_run false to commit the moves. ' +
    'Requires write access.',
    MakeRepairFilesSchema, HandleRepairFiles, tscProjectScoped);

  Registry.Register('reattach_file',
    'Repair tool: upload a local file into an EXISTING file record whose ' +
    'bytes are missing from storage, keeping the record (and therefore its ' +
    'id, links and history) intact. Refuses when bytes are already present ' +
    'unless force is true. Use after repair_files reports a file as lost. ' +
    'Requires write access, a file_path under the server''s MCPUploadRoot, ' +
    'and an unsigned item.',
    MakeReattachFileSchema, HandleReattachFile, tscProjectScoped);

  Registry.Register('move_file',
    'Move a file to another item in the same project, keeping its file id, ' +
    'links and history. Moves the bytes in storage (the path includes the ' +
    'item folder), then the record; a failed record update moves them back. ' +
    'Requires write access. Refused when either item is signed or the ' +
    'file''s item is cited by a hypothesis in review or accepted, or the ' +
    'file itself is cited as hypothesis evidence (any status, closed ones ' +
    'included). A wiki page''s relative ' +
    'image links break if its images move to another item.',
    MakeMoveFileSchema, HandleMoveFile, tscProjectScoped);

  Registry.Register('reparent_item',
    'Move an item (with its subtree) under another item in the same project ' +
    'and folder, or to the folder''s root with new_parent_id 0. Any level ' +
    'can be a parent except Folder, so chains nest to any depth (Action ' +
    'under Action included). No files move. Requires write access; refused ' +
    'when the item, its current parent or the new parent is signed. Use ' +
    'move_item for moves between projects or folders.' +
    ' The response includes a `url` field - an eln://item/N (or ' +
    'eln://specimen/<title>) link that opens the item in the desktop ' +
    'ELN client when clicked in a markdown-rendering chat client.',
    MakeReparentItemSchema, HandleReparentItem, tscProjectScoped);
end;

end.
