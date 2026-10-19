unit unit_ToolsValueChecks;

interface

uses
  unit_MCPTools;

procedure RegisterValueCheckTools(Registry: TToolRegistry);

implementation

uses
  System.SysUtils, System.JSON, System.Math,
  System.Generics.Collections, System.Generics.Defaults,
  unit_Item, unit_Project, unit_ELNPluginTypes,
  unit_ValueChecks, unit_ValueDrift, unit_StorageCheck, unit_FilePaths,
  unit_JSONCompact, unit_ToolScope, unit_ToolDownloads, unit_ToolsWrite,
  unit_ToolHelpers, unit_ItemTypes, unit_ValueSource;

const
  MAX_ROWS = 5000;
  DEFAULT_ISSUE_LIMIT = 1000;
  DEFAULT_STORAGE_LIMIT = 500;
  STATUS_NOT_FOUND = 'not_found';

resourcestring
  SSourceUnavailable = 'The source file is outside this session''s project ' +
    'scope, or does not exist.';

type
  TToolReaderRunner = class(TInterfacedObject, IValueReaderRunner)
  private
    FContext: TToolContext;
  public
    constructor Create(const AContext: TToolContext);
    function Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
  end;

constructor TToolReaderRunner.Create(const AContext: TToolContext);
begin
  inherited Create;
  FContext := AContext;
end;

function TToolReaderRunner.Run(FileId: Int64;
  const AnalysisSnapshot: string): TReaderRun;
var
  F: unit_Item.TFile;
  Project: TProject;
  Ext, LocalPath: string;
  KeyValues: TArray<TPluginKeyValue>;
  I: Integer;
begin
  Result := Default(TReaderRun);
  F := FContext.Manager.Find<unit_Item.TFile>(FileId);
  if (F = nil) or (F.Item = nil) or
    not IsProjectVisible(FContext, F.Item.ProjectID) then
  begin
    Result.Error := SSourceUnavailable;
    Exit;
  end;
  Project := FContext.Manager.Find<TProject>(F.Item.ProjectID);
  if (Project = nil) or (F.FileType = nil) then
  begin
    Result.Error := Format('The storage path of file %d cannot be resolved.',
      [FileId]);
    Exit;
  end;
  if (FContext.Storage = nil) or (FContext.PluginHost = nil) then
  begin
    Result.Error := 'This server has no notebook storage or viewer plugins.';
    Exit;
  end;
  Ext := FileFormatExtension(F.Title + F.FileType.Ext, F.FileType.Ext);
  try
    if not FContext.Storage.Exists(AttachmentRelativePath(Project.FileFolder,
      F.Item.FolderName, F.FullName)) then
    begin
      Result.FileMissing := True;
      Result.Error := Format('File %d is not in notebook storage.', [FileId]);
      Exit;
    end;
    LocalPath := DownloadFileToLocal(FContext, FileId);
    try
      KeyValues := FContext.PluginHost.ExtractReaderSnapshotReplay(LocalPath,
        Ext, FileId, AnalysisSnapshot, Result.ReaderId, Result.ReaderVersion,
        Result.CurrentFileHash, Result.AnalysisStatus, Result.SnapshotKeys);
    finally
      DeleteLocalDownload(LocalPath);
    end;
  except
    on E: Exception do
    begin
      Result.Error := E.Message;
      Exit;
    end;
  end;
  SetLength(Result.Values, Length(KeyValues));
  for I := 0 to High(KeyValues) do
  begin
    Result.Values[I].Name := KeyValues[I].Name;
    Result.Values[I].Value := KeyValues[I].Value;
    Result.Values[I].Units := KeyValues[I].Units;
  end;
  Result.Succeeded := True;
end;

function OptBool(const Params: TJSONObject; const Key: string;
  ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  Result := ADefault;
  if Params = nil then
    Exit;
  V := Params.FindValue(Key);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else if (V <> nil) and not (V is TJSONNull) then
    raise Exception.CreateFmt('%s must be true or false.', [Key]);
end;

function OptArray(const Params: TJSONObject; const Key: string): TJSONArray;
var
  V: TJSONValue;
begin
  Result := nil;
  if Params = nil then
    Exit;
  V := Params.FindValue(Key);
  if (V = nil) or (V is TJSONNull) then
    Exit;
  if not (V is TJSONArray) then
    raise Exception.CreateFmt('%s must be an array.', [Key]);
  Result := TJSONArray(V);
end;

function RowLimit(const Params: TJSONObject; ADefault: Integer): Integer;
begin
  if not GetOptInt(Params, 'limit', Result) then
    Result := ADefault;
  Result := EnsureRange(Result, 1, MAX_ROWS);
end;

function DriftRowJSON(const Row: TValueDriftRow): TJSONObject;
var
  Flags, Inputs: TJSONArray;
  Flag: TValueDriftFlag;
  Input: TValueDriftInput;
  Entry: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('value_id', TJSONNumber.Create(Row.ValueId));
    Result.AddPair('item_id', TJSONNumber.Create(Row.ItemId));
    Result.AddPair('file_id', TJSONNumber.Create(Row.FileId));
    Result.AddPair('key_name', Row.KeyName);
    Result.AddPair('source_kind', SourceKindName(Row.SourceKind));
    Flags := TJSONArray.Create;
    Result.AddPair('flags', Flags);
    for Flag := Low(TValueDriftFlag) to High(TValueDriftFlag) do
      if Flag in Row.Flags then
        Flags.Add(DriftFlagCode(Flag));
    Result.AddPair('stored_value', TJSONNumber.Create(Row.StoredValue));
    if Row.HasCurrentValue then
      Result.AddPair('current_value', TJSONNumber.Create(Row.CurrentValue))
    else
      Result.AddPair('current_value', TJSONNull.Create);
    Result.AddPair('stored_reader_id', Row.StoredReaderId);
    Result.AddPair('stored_reader_version', Row.StoredReaderVersion);
    Result.AddPair('current_reader_id', Row.CurrentReaderId);
    Result.AddPair('current_reader_version', Row.CurrentReaderVersion);
    Result.AddPair('message', Row.Message);
    if Row.SourceKind = vskDerived then
    begin
      Result.AddPair('formula_id', Row.FormulaId);
      Result.AddPair('stored_formula_version', TJSONNumber.Create(Row.StoredFormulaVersion));
      if Row.CurrentFormulaVersion > 0 then
        Result.AddPair('current_formula_version', TJSONNumber.Create(Row.CurrentFormulaVersion))
      else
        Result.AddPair('current_formula_version', TJSONNull.Create);
      Inputs := TJSONArray.Create;
      Result.AddPair('inputs', Inputs);
      for Input in Row.Inputs do
      begin
        Entry := TJSONObject.Create;
        Inputs.AddElement(Entry);
        Entry.AddPair('role', Input.Role);
        Entry.AddPair('value_id', TJSONNumber.Create(Input.ValueId));
        Entry.AddPair('source_kind', SourceKindName(Input.SourceKind));
        Entry.AddPair('used_value', TJSONNumber.Create(Input.UsedValue));
        if Input.HasCurrentValue then
          Entry.AddPair('current_value', TJSONNumber.Create(Input.CurrentValue))
        else
          Entry.AddPair('current_value', TJSONNull.Create);
        Entry.AddPair('status', Input.Status);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function HandleCheckValueDrift(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId, ProjectId: Integer;
  HasItem, HasProject: Boolean;
  ItemIds: TArray<Integer>;
  Runner: IValueReaderRunner;
  Report: TValueDriftReport;
  Row: TValueDriftRow;
  Rows: TJSONArray;
begin
  HasItem := GetOptInt(Params, 'item_id', ItemId);
  HasProject := GetOptInt(Params, 'project_id', ProjectId);
  if HasItem = HasProject then
    raise Exception.Create('Provide exactly one of item_id or project_id.');
  if HasItem then
  begin
    RequireItemRead(Context, ItemId);
    ItemIds := CollectItemTreeIds(Context, ItemId);
  end
  else
  begin
    RequireProjectRead(Context, ProjectId);
    ItemIds := CollectProjectItemIds(Context, ProjectId);
  end;

  Runner := TToolReaderRunner.Create(Context);
  Report := CheckValueDrift(Context.Manager, ItemIds, Runner);

  Rows := TJSONArray.Create;
  try
    for Row in Report.Rows do
      Rows.AddElement(DriftRowJSON(Row));
  except
    Rows.Free;
    raise;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('checked', TJSONNumber.Create(Report.Checked));
  Result.AddPair('unchanged', TJSONNumber.Create(Report.Unchanged));
  Result.AddPair('drifted', Rows);
end;

function IssueRowJSON(const Row: TValueIssueRow): TJSONObject;
var
  Codes: TJSONArray;
  Issue: TValueIssue;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('value_id', TJSONNumber.Create(Row.ValueId));
    Result.AddPair('item_id', TJSONNumber.Create(Row.ItemId));
    Result.AddPair('item_title', Row.ItemTitle);
    Result.AddPair('project_id', TJSONNumber.Create(Row.ProjectId));
    Result.AddPair('type_id', TJSONNumber.Create(Row.TypeId));
    Result.AddPair('type_title', Row.TypeTitle);
    Result.AddPair('units', Row.Units);
    Result.AddPair('value', SmartNum(Row.Value));
    Result.AddPair('tolerance', SmartNum(Row.Tolerance));
    Result.AddPair('range_min', NullableNumJSON(Row.RangeMin));
    Result.AddPair('range_max', NullableNumJSON(Row.RangeMax));
    Codes := TJSONArray.Create;
    Result.AddPair('issues', Codes);
    for Issue := Low(TValueIssue) to High(TValueIssue) do
      if Issue in Row.Issues then
        Codes.Add(IssueCode(Issue));
  except
    Result.Free;
    raise;
  end;
end;

function HandleReportValueIssues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId, Limit, I: Integer;
  Factor: Double;
  Scope: TToolContext;
  Issues: TArray<TValueIssueRow>;
  Rows: TJSONArray;
begin
  if GetOptInt(Params, 'project_id', ProjectId) then
    RequireProjectRead(Context, ProjectId)
  else
    ProjectId := 0;
  Limit := RowLimit(Params, DEFAULT_ISSUE_LIMIT);
  Factor := LoadToleranceFactor(Context.Manager);
  Scope := Context;
  Issues := FindValueIssues(Context.Manager, ProjectId,
    function(Id: Integer): Boolean
    begin
      Result := IsProjectVisible(Scope, Id);
    end, Factor);

  Rows := TJSONArray.Create;
  try
    for I := 0 to Min(Limit, Length(Issues)) - 1 do
      Rows.AddElement(IssueRowJSON(Issues[I]));
  except
    Rows.Free;
    raise;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('tolerance_factor', TJSONNumber.Create(Factor));
  Result.AddPair('count', TJSONNumber.Create(Rows.Count));
  Result.AddPair('total', TJSONNumber.Create(Length(Issues)));
  Result.AddPair('values', Rows);
end;

function StorageRowJSON(const Row: TStorageCheckRow): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('file_id', TJSONNumber.Create(Row.FileId));
    Result.AddPair('item_id', TJSONNumber.Create(Row.ItemId));
    Result.AddPair('project_id', TJSONNumber.Create(Row.ProjectId));
    Result.AddPair('file_name', Row.FileName);
    Result.AddPair('relative_path', Row.RelativePath);
    Result.AddPair('stored_hash', Row.StoredHash);
    Result.AddPair('actual_hash', Row.ActualHash);
    Result.AddPair('status', StorageCheckStatusCode(Row.Status));
    if Row.Message <> '' then
      Result.AddPair('message', Row.Message);
  except
    Result.Free;
    raise;
  end;
end;

procedure AddItemFiles(const Context: TToolContext; ItemId: Integer;
  Files: TList<unit_Item.TFile>; Seen: TDictionary<Int64, Boolean>);
var
  Item: TItem;
  F: unit_Item.TFile;
begin
  Item := Context.Manager.Find<TItem>(ItemId);
  if (Item = nil) or Item.IsDeleted then
    Exit;
  for F in Item.Files do
    if not Seen.ContainsKey(F.Id) then
    begin
      Seen.Add(F.Id, True);
      Files.Add(F);
    end;
end;

procedure AddRequestedFiles(const Context: TToolContext; FileIds: TJSONArray;
  Files: TList<unit_Item.TFile>; Seen: TDictionary<Int64, Boolean>);
var
  Element: TJSONValue;
  FileId: Int64;
  F: unit_Item.TFile;
begin
  if FileIds.Count > MAX_ROWS then
    raise Exception.CreateFmt('file_ids has %d entries; the maximum is %d.',
      [FileIds.Count, MAX_ROWS]);
  for Element in FileIds do
  begin
    if not (Element is TJSONNumber) then
      raise Exception.Create('file_ids must contain only file IDs.');
    FileId := TJSONNumber(Element).AsInt64;
    RequireFileRead(Context, FileId);
    F := Context.Manager.Find<unit_Item.TFile>(FileId);
    if F.Item.IsDeleted then
      raise Exception.CreateFmt('File %d belongs to deleted item %d.',
        [FileId, F.Item.Id]);
    if not Seen.ContainsKey(F.Id) then
    begin
      Seen.Add(F.Id, True);
      Files.Add(F);
    end;
  end;
end;

function BaselineJSON(const Context: TToolContext;
  Baseline: TJSONArray): TJSONArray;
var
  Element: TJSONValue;
  Entry, Obj: TJSONObject;
  FileId: Int64;
  Previous, Current, Note, Message: string;
  F: unit_Item.TFile;
  Row: TStorageCheckRow;
begin
  if Baseline.Count > MAX_ROWS then
    raise Exception.CreateFmt('baseline has %d entries; the maximum is %d.',
      [Baseline.Count, MAX_ROWS]);
  Result := TJSONArray.Create;
  try
    for Element in Baseline do
    begin
      if not (Element is TJSONObject) then
        raise Exception.Create(
          'baseline entries must be objects {file_id, status, note}.');
      Entry := TJSONObject(Element);
      FileId := GetReqInt64(Entry, 'file_id');
      if not GetOptStr(Entry, 'status', Previous) then
        Previous := '';
      if not GetOptStr(Entry, 'note', Note) then
        Note := '';
      Message := '';
      F := Context.Manager.Find<unit_Item.TFile>(FileId);
      // Missing and out-of-scope files share one status, as the scope
      // guards share one refusal, so a baseline cannot probe other projects.
      if (F = nil) or (F.Item = nil) or F.Item.IsDeleted or
        not IsProjectVisible(Context, F.Item.ProjectID) then
        Current := STATUS_NOT_FOUND
      else
      begin
        Row := CheckStoredFile(Context.Manager, Context.Storage, F);
        Message := Row.Message;
        Current := StorageCheckStatusCode(Row.Status);
      end;
      Obj := TJSONObject.Create;
      Result.AddElement(Obj);
      Obj.AddPair('file_id', TJSONNumber.Create(FileId));
      Obj.AddPair('previous_status', Previous);
      Obj.AddPair('note', Note);
      Obj.AddPair('current_status', Current);
      if Message <> '' then
        Obj.AddPair('message', Message);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function HandleCheckStorage(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId, ItemId, Limit, Offset, I, Id: Integer;
  HasProject, HasItem, IncludeOk: Boolean;
  FileIds, Baseline: TJSONArray;
  Files: TList<unit_Item.TFile>;
  Seen: TDictionary<Int64, Boolean>;
  Counts: array[TStorageCheckStatus] of Integer;
  Status: TStorageCheckStatus;
  Row: TStorageCheckRow;
  Rows, Previous: TJSONArray;
  CountsObj: TJSONObject;
  Checked: Integer;
begin
  HasProject := GetOptInt(Params, 'project_id', ProjectId);
  HasItem := GetOptInt(Params, 'item_id', ItemId);
  FileIds := OptArray(Params, 'file_ids');
  if Ord(HasProject) + Ord(HasItem) + Ord(Assigned(FileIds)) <> 1 then
    raise Exception.Create(
      'Provide exactly one of project_id, item_id or file_ids.');
  Baseline := OptArray(Params, 'baseline');
  IncludeOk := OptBool(Params, 'include_ok', False);
  Limit := RowLimit(Params, DEFAULT_STORAGE_LIMIT);
  if not GetOptInt(Params, 'offset', Offset) or (Offset < 0) then
    Offset := 0;
  if Context.Storage = nil then
    raise Exception.Create('check_storage needs notebook storage.');

  Rows := nil;
  Previous := nil;
  Files := TList<unit_Item.TFile>.Create;
  Seen := TDictionary<Int64, Boolean>.Create;
  try
    if HasProject then
    begin
      RequireProjectRead(Context, ProjectId);
      for Id in CollectProjectItemIds(Context, ProjectId) do
        AddItemFiles(Context, Id, Files, Seen);
    end
    else if HasItem then
    begin
      RequireItemRead(Context, ItemId);
      for Id in CollectItemTreeIds(Context, ItemId) do
        AddItemFiles(Context, Id, Files, Seen);
    end
    else
      AddRequestedFiles(Context, FileIds, Files, Seen);

    Files.Sort(TComparer<unit_Item.TFile>.Construct(
      function(const A, B: unit_Item.TFile): Integer
      begin
        Result := CompareValue(A.Id, B.Id);
      end));

    for Status := Low(TStorageCheckStatus) to High(TStorageCheckStatus) do
      Counts[Status] := 0;
    Checked := 0;
    Offset := Min(Offset, Files.Count);
    Rows := TJSONArray.Create;
    for I := Offset to Min(Offset + Limit, Files.Count) - 1 do
    begin
      Row := CheckStoredFile(Context.Manager, Context.Storage, Files[I]);
      Inc(Checked);
      Inc(Counts[Row.Status]);
      if IncludeOk or (Row.Status <> scsOk) then
        Rows.AddElement(StorageRowJSON(Row));
    end;

    if Assigned(Baseline) then
      Previous := BaselineJSON(Context, Baseline)
    else
      Previous := TJSONArray.Create;

    CountsObj := TJSONObject.Create;
    for Status := Low(TStorageCheckStatus) to High(TStorageCheckStatus) do
      CountsObj.AddPair(StorageCheckStatusCode(Status),
        TJSONNumber.Create(Counts[Status]));

    Result := TJSONObject.Create;
    Result.AddPair('checked', TJSONNumber.Create(Checked));
    Result.AddPair('total', TJSONNumber.Create(Files.Count));
    Result.AddPair('offset', TJSONNumber.Create(Offset));
    Result.AddPair('limit', TJSONNumber.Create(Limit));
    if Offset + Checked < Files.Count then
      Result.AddPair('next_offset', TJSONNumber.Create(Offset + Checked));
    Result.AddPair('counts', CountsObj);
    Result.AddPair('files', Rows);
    Rows := nil;
    Result.AddPair('previously_reported', Previous);
    Previous := nil;
  finally
    Previous.Free;
    Rows.Free;
    Seen.Free;
    Files.Free;
  end;
end;

function MakeDriftSchema: TJSONObject;
var
  Props, P: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Check this item and all its non-deleted descendants');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Check all non-deleted items of this project');
  Props.AddPair('project_id', P);

  Result.AddPair('properties', Props);
end;

function MakeIssuesSchema: TJSONObject;
var
  Props, P: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Report only this project (default: all visible projects)');
  Props.AddPair('project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Maximum number of rows (default: 1000, max: 5000)');
  Props.AddPair('limit', P);

  Result.AddPair('properties', Props);
end;

function MakeStorageSchema: TJSONObject;
var
  Props, P, Items, BaseProps, BaseItem: TJSONObject;
  BaseReq: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Check the files of all non-deleted items of this project');
  Props.AddPair('project_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Check the files of this item and its non-deleted descendants');
  Props.AddPair('item_id', P);

  Items := TJSONObject.Create;
  Items.AddPair('type', 'integer');
  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  P.AddPair('items', Items);
  P.AddPair('description', 'Check exactly these files');
  Props.AddPair('file_ids', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'boolean');
  P.AddPair('description', 'Also list files with status ok (default: false)');
  Props.AddPair('include_ok', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Maximum number of files checked in this call (default: 500, max: 5000)');
  Props.AddPair('limit', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Number of files (ordered by file id) to skip; use next_offset from the previous call');
  Props.AddPair('offset', P);

  BaseProps := TJSONObject.Create;
  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  BaseProps.AddPair('file_id', P);
  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Status from the earlier report (free text)');
  BaseProps.AddPair('status', P);
  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  BaseProps.AddPair('note', P);
  BaseReq := TJSONArray.Create;
  BaseReq.Add('file_id');
  BaseItem := TJSONObject.Create;
  BaseItem.AddPair('type', 'object');
  BaseItem.AddPair('properties', BaseProps);
  BaseItem.AddPair('required', BaseReq);
  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  P.AddPair('items', BaseItem);
  P.AddPair('description', 'Files reported earlier; each is checked again ' +
    'and echoed in previously_reported with its current status');
  Props.AddPair('baseline', P);

  Result.AddPair('properties', Props);
end;

procedure RegisterValueCheckTools(Registry: TToolRegistry);
begin
  Registry.Register('check_value_drift',
    'Read-only. For values with source kind Reader, runs the reader that ' +
    'extension routing selects today on the stored source file and ' +
    'compares its output after the saved conversion with the stored value. ' +
    'Legacy sources without conversion metadata compare raw output. Give exactly one of ' +
    'item_id (the item and its non-deleted descendants) or project_id. ' +
    'Returns checked and unchanged counts and lists only drifted values ' +
    'with flags: value_changed, reader_version_changed, reader_changed, ' +
    'key_missing, file_missing, read_failed, reader_units_changed, ' +
    'source_changed, selection_changed, interval_unusable. A value saved ' +
    'with an analysis snapshot is recalculated over the stored interval, ' +
    'also when the file hash changed: source_changed means the file hash ' +
    'differs from the snapshot, selection_changed means the current shared ' +
    'interval differs from the snapshot (a missing shared interval is a ' +
    'change only for a manual snapshot), interval_unusable means the stored ' +
    'interval holds fewer than two samples in the current file and the value ' +
    'is not compared. current_value ' +
    'uses the saved factor and is null when the key is missing, the interval ' +
    'is unusable or the emitted unit changed. Mapping edits do not ' +
    'reinterpret stored values. For values with source kind Derived, the ' +
    'readers of the Reader inputs are re-run, Derived inputs are recomputed ' +
    'recursively, and the result is recomputed with the saved formula ' +
    'version; the row has source_kind Derived, formula_id, ' +
    'stored_formula_version, current_formula_version and inputs (role, ' +
    'value_id, used_value, current_value, status) and the flags ' +
    'value_changed, input_changed (an input differs from the number used), ' +
    'input_missing, formula_version_changed (a newer version exists; the ' +
    'saved version was used), formula_version_mismatch (the saved version ' +
    'is not available; the value is not recomputed), dependency_cycle, ' +
    'read_failed and not_fully_rerunnable (an input in the tree is Manual ' +
    'or Unknown).',
    MakeDriftSchema, HandleCheckValueDrift, tscProjectScoped);

  Registry.Register('report_value_issues',
    'Read-only. Lists stored values outside their value type range ' +
    '(below_range, above_range) or with an inconsistent tolerance: ' +
    'tolerance_exceeds_value when tolerance > |value|, ' +
    'tolerance_scale_mismatch when tolerance < |value| / tolerance_factor. ' +
    'Covers one project_id or all visible projects. Changes nothing; ' +
    'correct a value only after checking its source.',
    MakeIssuesSchema, HandleReportValueIssues, tscProjectScoped);

  Registry.Register('check_storage',
    'Read-only. Checks that attachment bytes are in notebook storage and ' +
    'that their MD5 matches the hash recorded at upload. Give exactly one ' +
    'of project_id, item_id (with descendants) or file_ids. Files of ' +
    'deleted items are not checked. Status per file: ok, missing, ' +
    'content_mismatch, no_hash or error; ok rows are listed only with ' +
    'include_ok. Files are checked in file id order, limit at a time; ' +
    'continue with next_offset. baseline echoes files from an earlier ' +
    'report in previously_reported with their current status (not_found ' +
    'when the file does not exist or is outside this session''s scope). ' +
    'Never repairs or writes; use repair_files for missing bytes.',
    MakeStorageSchema, HandleCheckStorage, tscProjectScoped);
end;

end.
