unit unit_ToolsValueEdit;

interface

uses
  unit_MCPTools;

procedure RegisterValueEditTools(Registry: TToolRegistry);

implementation

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Drivers.Interfaces, Aurelius.Commands.Exceptions,
  unit_Item, unit_ItemTypes, unit_ValueType,
  unit_AuditLog, unit_AuditHelper, unit_ConflictHandler, unit_SignatureModel,
  unit_Hypothesis, unit_HypothesisGuard,
  unit_AnalysisSettingsModel, unit_DerivedValueModel,
  unit_ValueSource, unit_ValueChecks, unit_TimeHelper,
  unit_JSONCompact, unit_ToolScope, unit_ToolHelpers, unit_ToolsWrite;

const
  MAX_REASON_LEN = 255;
  UPDATE_PARAMS: array[0..8] of string = ('value_id', 'value', 'tolerance',
    'description', 'rec_type', 'value_type_id', 'reader_version',
    'analysis_snapshot', 'confirm_out_of_range');
  SOURCE_PARAMS: array[0..8] of string = ('source_kind', 'source_file_id',
    'reader_id', 'key_name', 'reader_units', 'conversion_factor',
    'source_note', 'formula_id', 'inputs');

type
  TRemoval = record
    ValueId: Integer;
    ItemId: Integer;
    ItemTitle: string;
    ReaderId: string;
    OldText: string;
    Description: string;
    Dependents: TArray<Integer>;
  end;

function Num(const V: Double): string;
begin
  Result := FloatToStr(V, TFormatSettings.Invariant);
end;

function IdList(const Ids: TArray<Integer>): string;
var
  Id: Integer;
begin
  Result := '';
  for Id in Ids do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + IntToStr(Id);
  end;
end;

function IdArrayJSON(const Ids: TArray<Integer>): TJSONArray;
var
  Id: Integer;
begin
  Result := TJSONArray.Create;
  for Id in Ids do
    Result.Add(Id);
end;

function ValueTypeIdOf(Val: unit_Item.TValue): Integer;
begin
  if Assigned(Val.ValueType) then
    Result := Val.ValueType.Id
  else
    Result := 0;
end;

function OldNumbersText(Val: unit_Item.TValue): string;
begin
  Result := Format('value %s, tolerance %s, value type %d, %s, source %s',
    [Num(Val.Value), Num(Val.Tol), ValueTypeIdOf(Val), RecTypeName(Val.RecType),
     SourceKindName(Val.EffectiveSourceKind)]);
  if Val.EffectiveSourceKind = vskReader then
    Result := Result + Format(', reader version "%s"', [Val.ReaderVersion]);
end;

function PreviousJSON(Val: unit_Item.TValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('value', SmartNum(Val.Value));
  Result.AddPair('tolerance', SmartNum(Val.Tol));
  Result.AddPair('description', Val.Description);
  Result.AddPair('rec_type', RecTypeName(Val.RecType));
  Result.AddPair('value_type_id', TJSONNumber.Create(ValueTypeIdOf(Val)));
  if Val.EffectiveSourceKind = vskReader then
    Result.AddPair('reader_version', Val.ReaderVersion);
end;

function ResolveEditableValue(const Context: TToolContext;
  Operation: TObjectManager; ValueId: Integer): unit_Item.TValue;
var
  Item: TItem;
  HypId: Integer;
  HypStatus: THypothesisStatus;
begin
  Result := Operation.Find<unit_Item.TValue>(ValueId);
  if (Result = nil) or (Result.Item = nil) then
    RaiseOutOfScope;
  Item := Result.Item;
  RequireProjectRead(Context, Item.ProjectID);
  if Item.IsDeleted then
    raise Exception.CreateFmt('Value %d belongs to deleted item %d.',
      [ValueId, Item.Id]);
  CheckProjectWriteAccess(Context, Item.ProjectID);
  if IsItemSignedCheck(Operation, Item.Id) then
    raise Exception.CreateFmt('Item %d is signed; its values cannot be changed.',
      [Item.Id]);
  if IsItemCitedByLockedHypothesis(Operation, Item.Id, HypId, HypStatus) then
    raise Exception.CreateFmt(
      'Item %d is cited by hypothesis %d (%s); its values cannot be changed.',
      [Item.Id, HypId, HypothesisStatusNames[HypStatus]]);
end;

function DependentDerivedIds(Operation: TObjectManager; ValueId: Integer;
  const Excluded: TArray<Integer>): TArray<Integer>;
var
  Links: TList<TDerivedValueInput>;
  Link: TDerivedValueInput;
  Ids: TList<Integer>;
  ResultId, Skip: Integer;
  Keep: Boolean;
begin
  Result := nil;
  if not TDerivedValueModel.HasStorage(Operation.Connection) then
    Exit;
  Ids := TList<Integer>.Create;
  try
    Links := Operation.Find<TDerivedValueInput>
      .Where(Linq['InputValueId'] = ValueId).List;
    try
      for Link in Links do
      begin
        if Link.ResultValue = nil then
          Continue;
        ResultId := Link.ResultValue.Id;
        Keep := not Ids.Contains(ResultId);
        for Skip in Excluded do
          if Skip = ResultId then
            Keep := False;
        if Keep then
          Ids.Add(ResultId);
      end;
    finally
      Links.Free;
    end;
    Ids.Sort;
    Result := Ids.ToArray;
  finally
    Ids.Free;
  end;
end;

function RemovalJSON(Val: unit_Item.TValue;
  const Dependents: TArray<Integer>): TJSONObject;
begin
  Result := StoredValueJSON(Val, []);
  Result.AddPair('description', Val.Description);
  Result.AddPair('rec_type', RecTypeName(Val.RecType));
  Result.AddPair('dependent_derived_value_ids', IdArrayJSON(Dependents));
end;

function RemovalAuditText(const R: TRemoval; const Reason: string): string;
begin
  Result := Format('MCP: Removed value %d; old %s', [R.ValueId, R.OldText]);
  if Length(R.Dependents) > 0 then
    Result := Result + '; input of Derived values ' + IdList(R.Dependents);
  if Reason <> '' then
    Result := Result + Format('; reason "%s"', [Reason]);
  Result := Result + Format('; description "%s"; item "%s"',
    [R.Description, R.ItemTitle]);
end;

procedure RefreshCachedValue(const Context: TToolContext; ValueId: Integer);
var
  Cached: unit_Item.TValue;
begin
  Cached := Context.Manager.FindCached<unit_Item.TValue>(ValueId);
  if Assigned(Cached) and not Context.Manager.HasChanges(Cached) then
    Context.Manager.Refresh(Cached);
end;

function RemoveValues(const Context: TToolContext;
  const ValueIds: TArray<Integer>; const Reason: string): TJSONArray;
var
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  Committed: Boolean;
  Targets: TArray<unit_Item.TValue>;
  Removals: TArray<TRemoval>;
  Settings: TAnalysisSettingsModel;
  I: Integer;
begin
  SetLength(Targets, Length(ValueIds));
  SetLength(Removals, Length(ValueIds));
  Operation := TObjectManager.Create(Context.Manager.Connection);
  try
    for I := 0 to High(ValueIds) do
      try
        Targets[I] := ResolveEditableValue(Context, Operation, ValueIds[I]);
      except
        on E: Exception do
          if Length(ValueIds) = 1 then
            raise
          else
            raise Exception.CreateFmt(
              'value_ids[%d] refused; nothing was removed: %s', [I, E.Message]);
      end;

    Result := TJSONArray.Create;
    try
      for I := 0 to High(Targets) do
      begin
        Removals[I].ValueId := Targets[I].Id;
        Removals[I].ItemId := Targets[I].Item.Id;
        Removals[I].ItemTitle := Targets[I].Item.Title;
        Removals[I].ReaderId := Targets[I].ReaderId;
        Removals[I].OldText := OldNumbersText(Targets[I]);
        Removals[I].Description := Targets[I].Description;
        Removals[I].Dependents := DependentDerivedIds(Operation, ValueIds[I],
          ValueIds);
        Result.AddElement(RemovalJSON(Targets[I], Removals[I].Dependents));
      end;

      Transaction := TConflictHandler.BeginOperationTransaction(Context.Manager);
      Committed := False;
      try
        try
          for I := 0 to High(Targets) do
          begin
            Targets[I].Item.Values.Remove(Targets[I]);
            Operation.Remove(Targets[I]);
          end;
          Operation.Flush;
        except
          on E: EVersionedConcurrencyControl do
            raise Exception.Create('A value changed elsewhere while it was ' +
              'removed. Nothing was removed; read the values again and retry.');
        end;
        Settings := TAnalysisSettingsModel.Create(Operation);
        try
          for I := 0 to High(Removals) do
            Settings.DeleteForValue(Removals[I].ReaderId, Removals[I].ValueId);
        finally
          Settings.Free;
        end;
        for I := 0 to High(Removals) do
          RecordAudit(Operation, aetItem, Removals[I].ItemId, aoUpdate,
            Context.User.Id, RemovalAuditText(Removals[I], Reason));
        Transaction.Commit;
        Committed := True;
      finally
        if not Committed then
          Transaction.Rollback;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    TConflictHandler.FreeOperationManager(Operation);
  end;

  for I := 0 to High(Removals) do
  begin
    RefreshCachedItem(Context, Removals[I].ItemId);
    ForgetCachedRow(Context,
      Context.Manager.FindCached<unit_Item.TValue>(Removals[I].ValueId));
  end;
end;

function GetReason(const Params: TJSONObject): string;
begin
  Result := '';
  if GetOptStr(Params, 'reason', Result) then
    CheckMaxLen(Result, 'reason', MAX_REASON_LEN);
end;

function HandleRemoveValue(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ValueId: Integer;
  Reason: string;
  Rows: TJSONArray;
begin
  ValueId := GetReqInt(Params, 'value_id');
  Reason := GetReason(Params);
  Rows := RemoveValues(Context, [ValueId], Reason);
  try
    Result := Rows.Remove(0) as TJSONObject;
  finally
    Rows.Free;
  end;
end;

function HandleRemoveValues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Arr: TJSONArray;
  Ids: TArray<Integer>;
  Reason: string;
  Rows: TJSONArray;
  I, J: Integer;
begin
  if (Params = nil) or not (Params.FindValue('value_ids') is TJSONArray) then
    raise Exception.Create(
      'Missing required parameter: value_ids (array of value ids)');
  Arr := TJSONArray(Params.FindValue('value_ids'));
  if Arr.Count = 0 then
    raise Exception.Create('value_ids is empty; nothing was removed.');
  if Arr.Count > MAX_VALUE_BATCH then
    raise Exception.CreateFmt(
      'value_ids has %d entries; the maximum is %d. Split the batch.',
      [Arr.Count, MAX_VALUE_BATCH]);
  SetLength(Ids, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    if not (Arr.Items[I] is TJSONNumber) or
      not TryStrToInt(Arr.Items[I].Value, Ids[I]) then
      raise Exception.CreateFmt(
        'value_ids[%d] is not an integer value id; nothing was removed.', [I]);
    for J := 0 to I - 1 do
      if Ids[J] = Ids[I] then
        raise Exception.CreateFmt('value_ids[%d] repeats value %d; nothing ' +
          'was removed.', [I, Ids[I]]);
  end;
  Reason := GetReason(Params);

  Rows := RemoveValues(Context, Ids, Reason);
  Result := TJSONObject.Create;
  Result.AddPair('count', TJSONNumber.Create(Rows.Count));
  Result.AddPair('values', Rows);
end;

procedure CheckUpdateParams(const Params: TJSONObject);
var
  Pair: TJSONPair;
  Name, Known: string;
  Found: Boolean;
begin
  if Params = nil then
    Exit;
  for Pair in Params do
  begin
    Name := Pair.JsonString.Value;
    Found := False;
    for Known in UPDATE_PARAMS do
      if Known = Name then
        Found := True;
    if Found then
      Continue;
    for Known in SOURCE_PARAMS do
      if Known = Name then
        raise Exception.CreateFmt('update_value does not change the value ' +
          'source (%s). A source change is remove_value plus add_value.',
          [Name]);
    raise Exception.CreateFmt('Unknown parameter %s.', [Name]);
  end;
end;

function HandleUpdateValue(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ValueId, NewTypeId, ItemId: Integer;
  HasValue, HasTol, HasDesc, HasRec, HasType, HasVersion, HasSnapshot: Boolean;
  NewValue, NewTol, Factor: Double;
  NewDesc, RecStr, NewVersion, Snapshot, Completed, OldSnapshot: string;
  OldText, ItemTitle: string;
  NewRec: TRecType;
  Operation: TObjectManager;
  Val: unit_Item.TValue;
  VType: TValueType;
  Source: TValueSourceInfo;
  Issues: TValueIssues;
  Changed: Boolean;
  Transaction: IDBTransaction;
  Committed: Boolean;
  Settings: TAnalysisSettingsModel;
  Previous: TJSONObject;
begin
  CheckUpdateParams(Params);
  ValueId := GetReqInt(Params, 'value_id');
  HasValue := GetOptNum(Params, 'value', NewValue);
  HasTol := GetOptNum(Params, 'tolerance', NewTol);
  HasDesc := GetOptStr(Params, 'description', NewDesc);
  if HasDesc then
    CheckMaxLen(NewDesc, 'description', MAX_DESC_LEN);
  HasRec := GetOptStr(Params, 'rec_type', RecStr);
  NewRec := TEST_RESULT;
  if HasRec then
    NewRec := ParseRecType(RecStr);
  HasType := GetOptInt(Params, 'value_type_id', NewTypeId);
  HasVersion := GetOptStr(Params, 'reader_version', NewVersion);
  HasSnapshot := GetOptAnalysisSnapshot(Params, Snapshot);
  if not (HasValue or HasTol or HasDesc or HasRec or HasType or HasVersion or
    HasSnapshot) then
    raise Exception.Create('Nothing to change: give at least one of value, ' +
      'tolerance, description, rec_type, value_type_id, reader_version or ' +
      'analysis_snapshot.');

  Operation := TObjectManager.Create(Context.Manager.Connection);
  try
    Val := ResolveEditableValue(Context, Operation, ValueId);
    ItemId := Val.Item.Id;
    ItemTitle := Val.Item.Title;
    Source := ReadSource(Val);
    if (HasVersion or HasSnapshot) and (Source.Kind <> vskReader) then
      raise Exception.CreateFmt('reader_version and analysis_snapshot apply ' +
        'only to a Reader value; value %d has source %s.',
        [ValueId, SourceKindName(Source.Kind)]);
    if (HasValue or HasTol or HasType) and (Source.Kind = vskDerived) then
      raise Exception.CreateFmt('Value %d is Derived: the server computed its ' +
        'number. Store a new result with add_derived_value and remove this ' +
        'one with remove_value.', [ValueId]);

    if not HasValue then
      NewValue := Val.Value;
    if not HasTol then
      NewTol := Val.Tol;
    if not HasDesc then
      NewDesc := Val.Description;
    if not HasRec then
      NewRec := Val.RecType;
    if not HasType then
      NewTypeId := ValueTypeIdOf(Val);
    VType := Operation.Find<TValueType>(NewTypeId);
    if not Assigned(VType) then
      raise Exception.CreateFmt('ValueType not found: %d', [NewTypeId]);

    if HasVersion then
    begin
      if Trim(NewVersion) = '' then
        NewVersion := 'unknown';
      Source.ReaderVersion := NewVersion;
      try
        ValidateSource(Source);
      except
        on E: EValueSourceError do
          raise Exception.Create(E.Message);
      end;
    end;
    if HasSnapshot then
      CheckAnalysisSnapshot(Context, Source, Snapshot);

    Issues := [];
    if HasValue or HasTol or HasType then
    begin
      Factor := LoadToleranceFactor(Operation);
      Issues := CheckValue(VType, NewValue, NewTol, Factor);
      if (Issues <> []) and not GetOptBool(Params, 'confirm_out_of_range', False) then
        raise Exception.CreateFmt(
          'Value refused: %s (issues: %s). Check the number, the units of ' +
          'value type %d ("%s") and the tolerance scale. If the value is ' +
          'correct as given, repeat the call with confirm_out_of_range: true.',
          [DescribeValueIssues(Issues, VType, NewValue, NewTol, Factor),
           IssueCodesText(Issues), VType.Id, VType.Units]);
    end;

    Settings := TAnalysisSettingsModel.Create(Operation);
    try
      Settings.LoadSnapshot(Val, OldSnapshot);
      Completed := '';
      if HasSnapshot and (Snapshot <> '') then
        Completed := TAnalysisSettingsModel.CompleteSnapshot(Snapshot,
          Source.ReaderId, Source.KeyName, Source.FileId, ValueId);

      Changed := (NewValue <> Val.Value) or (NewTol <> Val.Tol) or
        (NewDesc <> Val.Description) or (NewRec <> Val.RecType) or
        (VType.Id <> ValueTypeIdOf(Val)) or
        (HasVersion and (NewVersion <> Val.ReaderVersion)) or
        (HasSnapshot and (Completed <> OldSnapshot));

      Previous := PreviousJSON(Val);
      try
        if Changed then
        begin
          OldText := Format('%s; description "%s"',
            [OldNumbersText(Val), Val.Description]);
          Transaction := TConflictHandler.BeginOperationTransaction(Context.Manager);
          Committed := False;
          try
            Val.Value := NewValue;
            Val.Tol := NewTol;
            Val.Description := NewDesc;
            Val.RecType := NewRec;
            Val.ValueType := VType;
            if HasVersion then
              Val.ReaderVersion := NewVersion;
            Val.ModifiedDate := UTCNow;
            Val.ModifiedBy := Context.User.Id;
            try
              Operation.Flush;
            except
              on E: EVersionedConcurrencyControl do
                raise Exception.CreateFmt('Value %d changed elsewhere. Nothing ' +
                  'was changed; read it again and retry.', [ValueId]);
            end;
            if HasSnapshot then
              if Completed = '' then
                Settings.DeleteForValue(Source.ReaderId, ValueId)
              else
                Settings.SaveSnapshot(Source.ReaderId, ValueId, Completed);
            RecordAudit(Operation, aetValue, ValueId, aoUpdate, Context.User.Id,
              Format('MCP: Updated value; old %s; item "%s"', [OldText, ItemTitle]));
            Transaction.Commit;
            Committed := True;
          finally
            if not Committed then
              Transaction.Rollback;
          end;
        end;

        Result := StoredValueJSON(Val, Issues);
        Result.AddPair('description', Val.Description);
        Result.AddPair('rec_type', RecTypeName(Val.RecType));
        Result.AddPair('changed', TJSONBool.Create(Changed));
        Result.AddPair('previous', Previous);
        Previous := nil;
      finally
        Previous.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    TConflictHandler.FreeOperationManager(Operation);
  end;

  if Changed then
  begin
    RefreshCachedItem(Context, ItemId);
    RefreshCachedValue(Context, ValueId);
  end;
end;

function MakeRemoveValueSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'ID of the value to remove (from get_values)');
  Props.AddPair('value_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Why the value is removed, for example "reader ' +
    'fix, replaced by value 812". Written to the audit row (max 255 characters).');
  Props.AddPair('reason', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('value_id');
  Result.AddPair('required', Req);
end;

function MakeRemoveValuesSchema: TJSONObject;
var
  Props, P, Items: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  Items := TJSONObject.Create;
  Items.AddPair('type', 'integer');
  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  P.AddPair('minItems', TJSONNumber.Create(1));
  P.AddPair('maxItems', TJSONNumber.Create(MAX_VALUE_BATCH));
  P.AddPair('items', Items);
  P.AddPair('description', 'IDs of the values to remove, each once');
  Props.AddPair('value_ids', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Why the values are removed. Written to every ' +
    'audit row (max 255 characters).');
  Props.AddPair('reason', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('value_ids');
  Result.AddPair('required', Req);
end;

function MakeUpdateValueSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;

  procedure Add(const Name, JsonType, Description: string);
  begin
    P := TJSONObject.Create;
    P.AddPair('type', JsonType);
    P.AddPair('description', Description);
    Props.AddPair(Name, P);
  end;

begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  Add('value_id', 'integer', 'ID of the value to change (from get_values)');
  Add('value', 'number', 'New number in the units of the value type');
  Add('tolerance', 'number', 'New tolerance in the same units as value');
  Add('description', 'string', 'New description / notes');
  Add('rec_type', 'string', 'New record type: EXP_CONDITION or TEST_RESULT');
  Add('value_type_id', 'integer', 'New value type ID (from list_value_types)');
  Add('reader_version', 'string', 'Reader values only: the reader version ' +
    'that produced the new number (reader_version from extract_file_key_values)');

  P := TJSONObject.Create;
  P.AddPair('type', TJSONArray.Create.Add('object').Add('string'));
  P.AddPair('description', 'Reader values only: the analysis_snapshot of ' +
    'the key from extract_file_key_values, as a JSON object or a string ' +
    'holding it. Its file_id must be the source file of the value and its ' +
    'file_hash the current content hash of that file. It replaces the ' +
    'stored snapshot. An empty string deletes the stored snapshot. Leave it ' +
    'out to keep the stored snapshot.');
  Props.AddPair('analysis_snapshot', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'boolean');
  P.AddPair('description', 'Store a value outside the value type range or ' +
    'with an inconsistent tolerance anyway (default: false). Set it only ' +
    'after checking that the refused number and its units are correct.');
  Props.AddPair('confirm_out_of_range', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('value_id');
  Result.AddPair('required', Req);
end;

procedure RegisterValueEditTools(Registry: TToolRegistry);
begin
  Registry.Register('update_value',
    'Change a stored value in place. Give value_id and any of value, ' +
    'tolerance, description, rec_type and value_type_id. For a Reader value ' +
    'you can also give reader_version and analysis_snapshot, for example ' +
    'after a reader fix: call extract_file_key_values again and pass the new ' +
    'converted_value, reader_version and analysis_snapshot. The source kind ' +
    'and the other source fields do not change; for another source, remove ' +
    'the value and add a new one. The number of a Derived value cannot be ' +
    'changed; store a new result with add_derived_value. A new value, ' +
    'tolerance or value type goes through the range and tolerance checks of ' +
    'add_value (confirm_out_of_range). The change cannot be undone from MCP. ' +
    'The audit row (get_audit_log, entity_type Value, entity_id = value_id) ' +
    'keeps the old value, tolerance, value type and description. The ' +
    'response has the stored value, previous (the old fields) and changed ' +
    '(false when every field already had the given value; then nothing is ' +
    'written). Requires write access. Refused when the item is signed or ' +
    'deleted, or when a hypothesis in review or accepted has the item as a ' +
    'run or cites the item or one of its values.',
    MakeUpdateValueSchema, HandleUpdateValue, tscProjectScoped);

  Registry.Register('remove_value',
    'Remove one stored value from its item. This is a hard delete and cannot ' +
    'be undone from MCP. The audit log keeps the old value, tolerance, value ' +
    'type, source and description in one row on the item (get_audit_log, ' +
    'entity_type Item, entity_id = the item id), with the optional reason. ' +
    'The analysis snapshot of the value is deleted with it. A Derived value ' +
    'that uses this value as an input is kept: the response lists it in ' +
    'dependent_derived_value_ids, and check_value_drift then reports the ' +
    'input as missing. Requires write access. Refused when the item is ' +
    'signed or deleted, or when a hypothesis in review or accepted has the ' +
    'item as a run or cites the item or one of its values. Use remove_values ' +
    'to remove several values in one step.',
    MakeRemoveValueSchema, HandleRemoveValue, tscProjectScoped);

  Registry.Register('remove_values',
    'Remove up to 200 stored values in one all-or-nothing step, for example ' +
    'all old results of a reader before a fix. Same rules as remove_value. ' +
    'Every id is checked before anything is removed; if one is refused, the ' +
    'error names its index (value_ids[i]) and nothing is removed. A Derived ' +
    'value removed in the same call is not listed as a dependent. One audit ' +
    'row is written per value. This cannot be undone from MCP.',
    MakeRemoveValuesSchema, HandleRemoveValues, tscProjectScoped);
end;

end.
