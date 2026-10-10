unit unit_PackageExport;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.IOUtils, System.TypInfo,
  Aurelius.Engine.ObjectManager,
  unit_Item,
  unit_LabEntry,
  unit_Protocol,
  unit_Template,
  unit_ProtocolStatusChange,
  unit_ELNDB_Dictionary;

type
  TELNPackageExportOptions = record
    IncludeFiles: Boolean;
    IncludeStatusHistory: Boolean;
  end;

  TELNPackageExporter = class
  private
    FManager: TObjectManager;
    FOptions: TELNPackageExportOptions;
    FTemplateIds: TList<Integer>;
    FStatusDic: TProtocolStatusChangeDictionary;
    FItemDic: TItemDictionary;

    function ItemToJson(Item: TItem): TJSONObject;
    function ProtocolToJson(Protocol: TProtocol): TJSONObject;
    function FileToJson(AFile: TFile): TJSONObject;
    function TemplateToJson(Template: TTemplate): TJSONObject;
    function GetStatusHistory(ProtocolId: Integer): TJSONArray;
    procedure CollectTemplateId(TemplateId: Integer);
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;
    function ExportItems(Items: TItems; const OutputPath: string;
      const ExportedBy: string; Options: TELNPackageExportOptions): Boolean;
  end;

implementation

uses
  unit_ProtocolTemplateModel;


constructor TELNPackageExporter.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FTemplateIds := TList<Integer>.Create;
  FStatusDic := TProtocolStatusChangeDictionary.Create;
  FItemDic := TItemDictionary.Create;
end;

destructor TELNPackageExporter.Destroy;
begin
  FItemDic.Free;
  FStatusDic.Free;
  FTemplateIds.Free;
  inherited;
end;

procedure TELNPackageExporter.CollectTemplateId(TemplateId: Integer);
begin
  if (TemplateId > 0) and not FTemplateIds.Contains(TemplateId) then
    FTemplateIds.Add(TemplateId);
end;

function TELNPackageExporter.GetStatusHistory(ProtocolId: Integer): TJSONArray;
var
  Changes: TProtocolStatusChanges;
  Change: TProtocolStatusChange;
  JChange: TJSONObject;
begin
  Result := TJSONArray.Create;
  Changes := FManager.Find<TProtocolStatusChange>
    .Where(FStatusDic.ProtocolId = ProtocolId)
    .OrderBy(FStatusDic.ChangedDate)
    .List;
  try
    for Change in Changes do
    begin
      JChange := TJSONObject.Create;
      JChange.AddPair('oldStatus', TJSONNumber.Create(Ord(Change.OldStatus)));
      JChange.AddPair('newStatus', TJSONNumber.Create(Ord(Change.NewStatus)));
      JChange.AddPair('changedBy', TJSONNumber.Create(Change.ChangedBy));
      JChange.AddPair('changedDate', DateTimeToStr(Change.ChangedDate));
      JChange.AddPair('comment', Change.Comment);
      Result.AddElement(JChange);
    end;
  finally
    Changes.Free;
  end;
end;

function TELNPackageExporter.FileToJson(AFile: TFile): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', AFile.Title);
  Result.AddPair('hash', AFile.Hash);
  if Assigned(AFile.FileType) then
    Result.AddPair('fileTypeExt', AFile.FileType.Ext)
  else
    Result.AddPair('fileTypeExt', '');
  Result.AddPair('description', AFile.Description);
end;

function TELNPackageExporter.ProtocolToJson(Protocol: TProtocol): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', Protocol.Title);
  Result.AddPair('formData', Protocol.FormData);

  if Protocol.ProtocolType.HasValue then
    Result.AddPair('protocolType', TJSONNumber.Create(Ord(Protocol.ProtocolType.Value)))
  else
    Result.AddPair('protocolType', TJSONNull.Create);

  Result.AddPair('validationStatus', TJSONNumber.Create(Ord(Protocol.ValidationStatus)));

  if Protocol.TemplateId.HasValue then
  begin
    Result.AddPair('templateOriginalId', TJSONNumber.Create(Protocol.TemplateId.Value));
    CollectTemplateId(Protocol.TemplateId.Value);
  end
  else
    Result.AddPair('templateOriginalId', TJSONNull.Create);

  Result.AddPair('createdDate', DateTimeToStr(Protocol.CreatedDate));

  if FOptions.IncludeStatusHistory and (Protocol.Id > 0) then
    Result.AddPair('statusHistory', GetStatusHistory(Protocol.Id))
  else
    Result.AddPair('statusHistory', TJSONArray.Create);
end;

function TELNPackageExporter.ItemToJson(Item: TItem): TJSONObject;
var
  JEntries, JFiles, JValues, JChildren: TJSONArray;
  Entry: TLabEntry;
  AFile: TFile;
  Val: TValue;
  JVal: TJSONObject;
  ActionTypeTitle: string;
  Children: TItems;
  Child: TItem;
begin
  Result := TJSONObject.Create;
  Result.AddPair('originalId', TJSONNumber.Create(Item.Id));
  Result.AddPair('title', Item.Title);
  Result.AddPair('description', Item.Description);
  Result.AddPair('level', TJSONNumber.Create(Ord(Item.Level)));
  Result.AddPair('type', TJSONNumber.Create(Ord(Item.Type_)));
  Result.AddPair('sortOrder', TJSONNumber.Create(Item.SortOrder));

  ActionTypeTitle := '';
  if Assigned(Item.ActionType) then
    ActionTypeTitle := Item.ActionType.Title;
  Result.AddPair('actionTypeTitle', ActionTypeTitle);

  JEntries := TJSONArray.Create;
  for Entry in Item.Entries do
  begin
    if Entry is TProtocol then
      JEntries.AddElement(ProtocolToJson(TProtocol(Entry)));
  end;
  Result.AddPair('entries', JEntries);

  JFiles := TJSONArray.Create;
  if FOptions.IncludeFiles then
  begin
    for AFile in Item.Files do
      JFiles.AddElement(FileToJson(AFile));
  end;
  Result.AddPair('files', JFiles);

  JValues := TJSONArray.Create;
  for Val in Item.Values do
  begin
    JVal := TJSONObject.Create;
    if Assigned(Val.ValueType) then
      JVal.AddPair('valueTypeId', TJSONNumber.Create(Val.ValueType.Id))
    else
      JVal.AddPair('valueTypeId', TJSONNumber.Create(0));
    JVal.AddPair('category', TJSONNumber.Create(Ord(Val.RecType)));
    JVal.AddPair('value', TJSONNumber.Create(Val.Value));
    JVal.AddPair('uncertainty', TJSONNumber.Create(Val.Tol));
    JVal.AddPair('label', Val.Description);
    JValues.AddElement(JVal);
  end;
  Result.AddPair('values', JValues);

  JChildren := TJSONArray.Create;
  // Exclude soft-deleted (recycle-bin) descendants — otherwise they are
  // serialized as live items and resurrected on import.
  Children := FManager.Find<TItem>
    .Where((FItemDic.ParentID = Item.Id) and (FItemDic.IsDeleted = False))
    .OrderBy('SortOrder')
    .OrderBy('Id')
    .List;
  try
    for Child in Children do
      JChildren.AddElement(ItemToJson(Child));
  finally
    Children.Free;
  end;
  Result.AddPair('children', JChildren);
end;

function TELNPackageExporter.TemplateToJson(Template: TTemplate): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('originalId', TJSONNumber.Create(Template.Id));
  Result.AddPair('name', Template.Name);
  Result.AddPair('description', Template.Description);
  Result.AddPair('formSchema', Template.FormSchema);
  Result.AddPair('version', TJSONNumber.Create(Template.Version));
  Result.AddPair('isActive', TJSONBool.Create(Template.IsActive));
end;

function TELNPackageExporter.ExportItems(Items: TItems; const OutputPath: string;
  const ExportedBy: string; Options: TELNPackageExportOptions): Boolean;
var
  Root: TJSONObject;
  JItems, JTemplates: TJSONArray;
  Item: TItem;
  TemplateId: Integer;
  Template: TTemplate;
  JsonStr: string;
  FileStream: TStreamWriter;
begin
  FOptions := Options;
  FTemplateIds.Clear;

  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Root.AddPair('exportDate', DateTimeToStr(Now));
    Root.AddPair('exportedBy', ExportedBy);

    JItems := TJSONArray.Create;
    for Item in Items do
      // Skip a soft-deleted root; its live children (if any) are unreachable
      // through the recycle bin and must not be resurrected via export/import.
      if not Item.IsDeleted then
        JItems.AddElement(ItemToJson(Item));
    Root.AddPair('items', JItems);

    JTemplates := TJSONArray.Create;
    for TemplateId in FTemplateIds do
    begin
      Template := FManager.Find<TTemplate>(TemplateId);
      if Assigned(Template) then
        JTemplates.AddElement(TemplateToJson(Template));
    end;
    Root.AddPair('templates', JTemplates);

    ForceDirectories(ExtractFilePath(OutputPath));
    FileStream := TStreamWriter.Create(OutputPath, False, TEncoding.UTF8);
    try
      JsonStr := Root.Format(2);
      FileStream.Write(JsonStr);
    finally
      FileStream.Free;
    end;
  finally
    Root.Free;
  end;

  Result := True;
end;

end.
