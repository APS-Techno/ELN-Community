unit unit_PackageImport;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.IOUtils,
  Aurelius.Engine.ObjectManager,
  Aurelius.Types.Nullable,
  unit_Item,
  unit_LabEntry,
  unit_Protocol,
  unit_Template,
  unit_ProtocolStatusChange,
  unit_ItemTypes,
  unit_ELNDB_Dictionary;

type
  TELNPackageImportResult = record
    Success: Boolean;
    ItemCount: Integer;
    TemplateCount: Integer;
    ErrorMessage: string;
  end;

  TELNPackageImporter = class
  protected
    FManager: TObjectManager;
    FTemplateDic: TTemplateDictionary;
    FTemplateMap: TDictionary<Integer, Integer>; // originalId -> newId

    function ParsePackage(const PackagePath: string; out Root: TJSONObject): Boolean;
    procedure ImportTemplates(JTemplates: TJSONArray; out Count: Integer);
    procedure ImportItems(JItems: TJSONArray; ProjectId, FolderId, UserId: Integer;
      out Count: Integer);
    function FindOrCreateTemplate(OriginalId: Integer; const Name, Schema: string;
      Version: Integer): Integer;
    function ImportProtocol(JEntry: TJSONObject; UserId: Integer): TProtocol;
    procedure ImportStatusHistory(JHistory: TJSONArray; ProtocolId, UserId: Integer);

  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;
    function ImportPackage(const PackagePath: string;
      ProjectId, FolderId, UserId: Integer): TELNPackageImportResult;
    function PreviewPackage(const PackagePath: string): string;
  end;

implementation

uses
  Aurelius.Criteria.Linq,
  Aurelius.Drivers.Interfaces,
  unit_ProtocolTemplateModel,
  unit_ProtocolTemplateHtmlGenerator,
  unit_ActionType,
  unit_FileType,
  unit_ValueType,
  unit_TimeHelper;

{ TELNPackageImporter }

constructor TELNPackageImporter.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FTemplateDic := TTemplateDictionary.Create;
  FTemplateMap := TDictionary<Integer, Integer>.Create;
end;

destructor TELNPackageImporter.Destroy;
begin
  FTemplateMap.Free;
  FTemplateDic.Free;
  inherited;
end;


function TELNPackageImporter.ParsePackage(const PackagePath: string;
  out Root: TJSONObject): Boolean;
var
  Content: string;
  JsonVal: TJSONValue;
begin
  Result := False;
  Root := nil;

  if not FileExists(PackagePath) then Exit;

  Content := System.IOUtils.TFile.ReadAllText(PackagePath, TEncoding.UTF8);
  JsonVal := TJSONObject.ParseJSONValue(Content);

  if Assigned(JsonVal) and (JsonVal is TJSONObject) then
  begin
    Root := TJSONObject(JsonVal);
    Result := True;
  end
  else
  begin
    JsonVal.Free;
  end;
end;

function TELNPackageImporter.PreviewPackage(const PackagePath: string): string;
var
  Root: TJSONObject;
  JItems, JTemplates: TJSONArray;
  SB: TStringBuilder;
  I: Integer;
  JItem: TJSONObject;
begin
  Result := '';
  if not ParsePackage(PackagePath, Root) then
  begin
    Result := 'Invalid package file.';
    Exit;
  end;

  SB := TStringBuilder.Create;
  try
    if Root.GetValue('exportedBy') <> nil then
      SB.AppendLine('Exported by: ' + Root.GetValue('exportedBy').Value);
    if Root.GetValue('exportDate') <> nil then
      SB.AppendLine('Export date: ' + Root.GetValue('exportDate').Value);
    SB.AppendLine('');

    JTemplates := Root.GetValue('templates') as TJSONArray;
    if Assigned(JTemplates) then
      SB.AppendFormat('Templates: %d', [JTemplates.Count]).AppendLine;

    JItems := Root.GetValue('items') as TJSONArray;
    if Assigned(JItems) then
    begin
      SB.AppendFormat('Items: %d', [JItems.Count]).AppendLine;
      SB.AppendLine('');
      for I := 0 to JItems.Count - 1 do
      begin
        if not (JItems.Items[I] is TJSONObject) then Continue;
        JItem := JItems.Items[I] as TJSONObject;
        if JItem.GetValue('title') <> nil then
          SB.AppendFormat('  - %s', [JItem.GetValue('title').Value]).AppendLine;
      end;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
    Root.Free;
  end;
end;

function TELNPackageImporter.FindOrCreateTemplate(OriginalId: Integer;
  const Name, Schema: string; Version: Integer): Integer;
var
  Existing: TTemplates;
  T, Match: TTemplate;
begin
  // Check if we already mapped this original ID
  if FTemplateMap.ContainsKey(OriginalId) then
    Exit(FTemplateMap[OriginalId]);

  // Search for existing template with same name and schema
  Existing := FManager.Find<TTemplate>
    .Where(FTemplateDic.Name = Name)
    .Where(FTemplateDic.IsActive = True)
    .List;
  try
    Match := nil;
    for T in Existing do
    begin
      if T.FormSchema = Schema then
      begin
        Match := T;
        Break;
      end;
    end;

    if Assigned(Match) then
    begin
      // Exact match — reuse existing template
      Result := Match.Id;
    end
    else
    begin
      // Same name but different schema → create new version
      // Or no matching name → create new template
      T := TTemplate.Create;
      T.Name := Name;
      T.FormSchema := Schema;
      T.IsActive := True;
      T.Version := Version;
      T.CreatedDate := UTCNow;
      FManager.Save(T);
      FManager.Flush;
      Result := T.Id;
    end;
  finally
    Existing.Free;
  end;

  FTemplateMap.Add(OriginalId, Result);
end;

procedure TELNPackageImporter.ImportTemplates(JTemplates: TJSONArray;
  out Count: Integer);
var
  I: Integer;
  JTpl: TJSONObject;
  OriginalId, Version: Integer;
  Name, Schema, ValidationError: string;
begin
  Count := 0;
  for I := 0 to JTemplates.Count - 1 do
  begin
    JTpl := JTemplates.Items[I] as TJSONObject;
    OriginalId := (JTpl.GetValue('originalId') as TJSONNumber).AsInt;
    Name := JTpl.GetValue('name').Value;
    Schema := JTpl.GetValue('formSchema').Value;

    // Reject a template whose form schema is malformed before persisting it —
    // an unvalidated schema would crash TTemplateHtmlGenerator at render time.
    // Raising here aborts and rolls back the whole import (surfaced via
    // ImportPackage's ErrorMessage), matching how import failures are reported.
    ValidationError := TTemplateHtmlGenerator.ValidateSchema(Schema);
    if ValidationError <> '' then
      raise Exception.CreateFmt('Template "%s" has an invalid form schema: %s',
        [Name, ValidationError]);

    Version := 1;
    if JTpl.GetValue('version') <> nil then
      Version := (JTpl.GetValue('version') as TJSONNumber).AsInt;

    FindOrCreateTemplate(OriginalId, Name, Schema, Version);
    Inc(Count);
  end;
end;

function TELNPackageImporter.ImportProtocol(JEntry: TJSONObject;
  UserId: Integer): TProtocol;
var
  JTemplateId: TJSONValue;
  OriginalTemplateId, NewTemplateId: Integer;
begin
  Result := TProtocol.Create;
  Result.Title := JEntry.GetValue('title').Value;
  Result.FormData := JEntry.GetValue('formData').Value;
  Result.CreatedDate := UTCNow;
  Result.CreatedBy := UserId;

  if (JEntry.GetValue('protocolType') <> nil) and
     not (JEntry.GetValue('protocolType') is TJSONNull) then
    Result.ProtocolType := TProtocolType((JEntry.GetValue('protocolType') as TJSONNumber).AsInt);

  // Always import protocols as Draft regardless of the packaged status.
  // Accepting vsApproved/vsInReview from the package would let an import
  // package forge an approval record; the operator must re-run the
  // TProtocolStatusModel workflow post-import to reach any non-draft state.
  Result.ValidationStatus := vsDraft;

  // Map template ID
  JTemplateId := JEntry.GetValue('templateOriginalId');
  if Assigned(JTemplateId) and not (JTemplateId is TJSONNull) then
  begin
    OriginalTemplateId := (JTemplateId as TJSONNumber).AsInt;
    if FTemplateMap.TryGetValue(OriginalTemplateId, NewTemplateId) then
      Result.TemplateId := NewTemplateId
    else
      Result.TemplateId := OriginalTemplateId; // fallback — use original ID
  end;
end;

procedure TELNPackageImporter.ImportStatusHistory(JHistory: TJSONArray;
  ProtocolId, UserId: Integer);
var
  I: Integer;
  JChange: TJSONObject;
  Change: TProtocolStatusChange;
begin
  for I := 0 to JHistory.Count - 1 do
  begin
    JChange := JHistory.Items[I] as TJSONObject;
    Change := TProtocolStatusChange.Create;
    Change.ProtocolId := ProtocolId;
    Change.OldStatus := TValidationStatus((JChange.GetValue('oldStatus') as TJSONNumber).AsInt);
    Change.NewStatus := TValidationStatus((JChange.GetValue('newStatus') as TJSONNumber).AsInt);
    Change.ChangedBy := UserId;
    Change.ChangedDate := UTCNow;
    if JChange.GetValue('comment') <> nil then
      Change.Comment := JChange.GetValue('comment').Value;
    FManager.Save(Change);
  end;
end;

procedure TELNPackageImporter.ImportItems(JItems: TJSONArray;
  ProjectId, FolderId, UserId: Integer; out Count: Integer);
var
  I, J: Integer;
  JItem, JEntry: TJSONObject;
  JEntries, JStatusHistory: TJSONArray;
  Item: TItem;
  Protocol: TProtocol;
begin
  Count := 0;
  for I := 0 to JItems.Count - 1 do
  begin
    JItem := JItems.Items[I] as TJSONObject;

    Item := TItem.Create;
    Item.Title := JItem.GetValue('title').Value;
    if JItem.GetValue('description') <> nil then
      Item.Description := JItem.GetValue('description').Value;
    Item.Level := TItemLevel((JItem.GetValue('level') as TJSONNumber).AsInt);
    Item.Type_ := TItemType((JItem.GetValue('type') as TJSONNumber).AsInt);
    Item.ProjectID := ProjectId;
    Item.FolderID := FolderId;
    Item.Parent := 0;
    Item.Expanded := True;
    Item.CreatedDate := UTCNow;
    Item.CreatedBy := UserId;

    if JItem.GetValue('sortOrder') <> nil then
      Item.SortOrder := (JItem.GetValue('sortOrder') as TJSONNumber).AsInt;

    FManager.Save(Item);

    // Import entries (protocols/notes)
    if JItem.GetValue('entries') <> nil then
    begin
      JEntries := JItem.GetValue('entries') as TJSONArray;
      for J := 0 to JEntries.Count - 1 do
      begin
        JEntry := JEntries.Items[J] as TJSONObject;
        Protocol := ImportProtocol(JEntry, UserId);
        Item.Entries.Add(Protocol);
      end;
    end;

    FManager.Update(Item);
    FManager.Flush;

    // Import status history for protocols that have been saved
    if JItem.GetValue('entries') <> nil then
    begin
      JEntries := JItem.GetValue('entries') as TJSONArray;
      for J := 0 to JEntries.Count - 1 do
      begin
        JEntry := JEntries.Items[J] as TJSONObject;
        JStatusHistory := nil;
        if JEntry.GetValue('statusHistory') <> nil then
          JStatusHistory := JEntry.GetValue('statusHistory') as TJSONArray;

        if Assigned(JStatusHistory) and (JStatusHistory.Count > 0) then
        begin
          // Get the protocol that was just saved (entry index matches)
          if J < Item.Entries.Count then
          begin
            Protocol := Item.Entries[J] as TProtocol;
            ImportStatusHistory(JStatusHistory, Protocol.Id, UserId);
          end;
        end;
      end;
    end;

    FManager.Flush;
    Inc(Count);
  end;
end;

function TELNPackageImporter.ImportPackage(const PackagePath: string;
  ProjectId, FolderId, UserId: Integer): TELNPackageImportResult;
var
  Root: TJSONObject;
  JTemplates, JItems: TJSONArray;
  Trans: IDBTransaction;
begin
  Result.Success := False;
  Result.ItemCount := 0;
  Result.TemplateCount := 0;
  Result.ErrorMessage := '';
  FTemplateMap.Clear;

  if not ParsePackage(PackagePath, Root) then
  begin
    Result.ErrorMessage := 'Failed to parse package file.';
    Exit;
  end;

  try
    // Wrap the entire import in a single transaction so any exception rolls
    // the partial state back. Previously ImportTemplates/ImportItems each
    // called Flush inline and a failure mid-way left orphan templates,
    // half-linked items, or dangling ref IDs in the database.
    Trans := FManager.Connection.BeginTransaction;
    try
      // Import templates first
      JTemplates := Root.GetValue('templates') as TJSONArray;
      if Assigned(JTemplates) then
        ImportTemplates(JTemplates, Result.TemplateCount);

      // Import items
      JItems := Root.GetValue('items') as TJSONArray;
      if Assigned(JItems) then
        ImportItems(JItems, ProjectId, FolderId, UserId, Result.ItemCount);

      FManager.Flush;
      Trans.Commit;
      Result.Success := True;
    except
      on E: Exception do
      begin
        Trans.Rollback;
        Result.ItemCount := 0;
        Result.TemplateCount := 0;
        Result.ErrorMessage := E.Message;
      end;
    end;
  finally
    Root.Free;
  end;
end;


end.
