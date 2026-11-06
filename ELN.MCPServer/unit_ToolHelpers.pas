unit unit_ToolHelpers;


interface

uses
  System.JSON, System.Generics.Collections,
  Aurelius.Types.Nullable, Aurelius.Engine.ObjectManager,
  unit_Item, unit_ItemTypes, unit_ValueChecks, unit_MCPTools;

const
  // Aurelius defaults these columns to VARCHAR(255). Strict MySQL rejects
  // longer strings, while SQLite does not enforce the width.
  MAX_TITLE_LEN = 255;
  MAX_DESC_LEN  = 255;

function MakeElnItemUrl(Item: TItem): string;

function ValueSourceJSON(Value: TValue): TJSONObject;
function NullableNumJSON(const Value: Nullable<Double>): TJSONValue;

function GetOptAnalysisSnapshot(const Params: TJSONObject;
  out Json: string): Boolean;
function AnalysisSnapshotValue(const Json: string): TJSONValue;

function ParseRecType(const S: string): TRecType;
function RecTypeName(RecType: TRecType): string;
function IssueCodesText(Issues: TValueIssues): string;
function IssueCodesJSON(Issues: TValueIssues): TJSONArray;
function StoredValueJSON(Val: TValue; Issues: TValueIssues): TJSONObject;

// Raises if AValue is longer than AMax. The exception is deliberately the base
// Exception class and nothing derived from it: unit_MCPDiag.ClientErrorMessage
// forwards the message verbatim only on an exact class match, so a descendant
// would reach the client as the useless generic "Tool execution failed".
procedure CheckMaxLen(const AValue, AFieldName: string; AMax: Integer);

function ItemInRecycleBin(Manager: TObjectManager; Item: TItem): Boolean;

type
  TAncestorChain = record
    Ids: TArray<Integer>;
    Incomplete: Boolean;
  end;

/// Per item id: its ancestor ids from the root down to the direct parent; the
/// item itself is excluded. Incomplete when a row on the way up is missing or
/// the chain loops. One IN query per tree level. Caller frees.
function AncestorChains(Manager: TObjectManager;
  const ItemIds: TArray<Integer>): TDictionary<Integer, TAncestorChain>;
function AncestorIdsJSON(const Chain: TAncestorChain): TJSONArray;

procedure RefreshCachedItem(const Context: TToolContext; ItemId: Integer);
procedure ForgetCachedRow(const Context: TToolContext; Cached: TObject);

implementation

uses
  System.SysUtils, System.NetEncoding, System.Math, System.Variants,
  Aurelius.Criteria.Base, Aurelius.Criteria.Linq, Aurelius.Criteria.Projections,
  unit_ValueSource,
  unit_JSONCompact;

function MakeElnItemUrl(Item: TItem): string;
begin
  if Item = nil then
  begin
    Result := '';
    Exit;
  end;

  if Item.Type_ = TItemType.Specimen then
    Result := 'eln://specimen/' + TNetEncoding.URL.Encode(Item.Title)
  else
    Result := 'eln://item/' + IntToStr(Item.Id);
end;

function ValueSourceJSON(Value: TValue): TJSONObject;
var
  Source: TValueSourceInfo;
  Inputs: TJSONArray;
  Link: TDerivedValueInput;
  Entry: TJSONObject;
begin
  Source := ReadSource(Value);
  Result := TJSONObject.Create;
  Result.AddPair('kind', SourceKindName(Source.Kind));
  if Source.FileId > 0 then
    Result.AddPair('file_id', TJSONNumber.Create(Source.FileId));
  if Source.ReaderId <> '' then
    Result.AddPair('reader_id', Source.ReaderId);
  if Source.ReaderVersion <> '' then
    Result.AddPair('reader_version', Source.ReaderVersion);
  if Source.KeyName <> '' then
    Result.AddPair('key_name', Source.KeyName);
  if Source.Note <> '' then
    Result.AddPair('note', Source.Note);
  if Source.ReaderUnits.HasValue then
    Result.AddPair('reader_units', Source.ReaderUnits.Value);
  if Source.ConversionFactor.HasValue then
    Result.AddPair('conversion_factor', TJSONNumber.Create(Source.ConversionFactor.Value));
  if Source.Kind = vskDerived then
  begin
    Result.AddPair('formula_id', Source.FormulaId);
    Result.AddPair('formula_version', TJSONNumber.Create(Source.FormulaVersion));
    Inputs := TJSONArray.Create;
    Result.AddPair('inputs', Inputs);
    for Link in Value.DerivedInputs do
    begin
      Entry := TJSONObject.Create;
      Inputs.AddElement(Entry);
      Entry.AddPair('role', Link.Role);
      Entry.AddPair('value_id', TJSONNumber.Create(Link.InputValueId));
      Entry.AddPair('used_value', TJSONNumber.Create(Link.InputValue));
    end;
  end;
end;

function NullableNumJSON(const Value: Nullable<Double>): TJSONValue;
begin
  if Value.HasValue then
    Result := SmartNum(Value.Value)
  else
    Result := TJSONNull.Create;
end;

procedure CheckMaxLen(const AValue, AFieldName: string; AMax: Integer);
begin
  if Length(AValue) > AMax then
    raise Exception.CreateFmt(
      '%s is %d characters; the maximum is %d. Shorten it and retry.',
      [AFieldName, Length(AValue), AMax]);
end;

function ItemInRecycleBin(Manager: TObjectManager; Item: TItem): Boolean;
var
  Current: TItem;
  Seen: TList<Integer>;
begin
  Result := False;
  Seen := TList<Integer>.Create;
  try
    Current := Item;
    while Assigned(Current) do
    begin
      if Current.IsDeleted then
        Exit(True);
      if (Current.Parent <= 0) or (Seen.IndexOf(Current.Parent) >= 0) then
        Exit;
      Seen.Add(Current.Id);
      Current := Manager.Find<TItem>(Current.Parent);
    end;
  finally
    Seen.Free;
  end;
end;

const
  ANCESTOR_CHUNK = 500;

procedure LoadParents(Manager: TObjectManager; const Ids: TArray<Integer>;
  Parents: TDictionary<Integer, Integer>);
var
  Start, I: Integer;
  Keys: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  Start := 0;
  while Start < Length(Ids) do
  begin
    SetLength(Keys, Min(ANCESTOR_CHUNK, Length(Ids) - Start));
    for I := 0 to High(Keys) do
      Keys[I] := Ids[Start + I];
    Rows := Manager.Find<TItem>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('ParentID').As_('Parent')))
      .Where(Linq['Id']._In(Keys))
      .ListValues;
    try
      for Row in Rows do
        if VarIsNull(Row.Values['Parent']) then
          Parents.AddOrSetValue(Row.Values['Id'], 0)
        else
          Parents.AddOrSetValue(Row.Values['Id'], Row.Values['Parent']);
    finally
      Rows.Free;
    end;
    Inc(Start, Length(Keys));
  end;
end;

function AncestorChains(Manager: TObjectManager;
  const ItemIds: TArray<Integer>): TDictionary<Integer, TAncestorChain>;
var
  Parents: TDictionary<Integer, Integer>;
  Queried, Seen: TDictionary<Integer, Boolean>;
  Frontier, Next, Path: TList<Integer>;
  Id, Parent: Integer;
  Chain: TAncestorChain;
begin
  Result := TDictionary<Integer, TAncestorChain>.Create;
  Parents := TDictionary<Integer, Integer>.Create;
  Queried := TDictionary<Integer, Boolean>.Create;
  Seen := TDictionary<Integer, Boolean>.Create;
  Frontier := TList<Integer>.Create;
  Next := TList<Integer>.Create;
  Path := TList<Integer>.Create;
  try
    try
      for Id in ItemIds do
        if not Queried.ContainsKey(Id) then
        begin
          Queried.Add(Id, True);
          Frontier.Add(Id);
        end;
      while Frontier.Count > 0 do
      begin
        LoadParents(Manager, Frontier.ToArray, Parents);
        Next.Clear;
        for Id in Frontier do
          if Parents.TryGetValue(Id, Parent) and (Parent > 0) and
            not Queried.ContainsKey(Parent) then
          begin
            Queried.Add(Parent, True);
            Next.Add(Parent);
          end;
        Frontier.Clear;
        Frontier.AddRange(Next);
      end;

      for Id in ItemIds do
      begin
        if Result.ContainsKey(Id) then
          Continue;
        Chain := Default(TAncestorChain);
        Path.Clear;
        Seen.Clear;
        Seen.Add(Id, True);
        if not Parents.TryGetValue(Id, Parent) then
          Chain.Incomplete := True
        else
          while Parent > 0 do
          begin
            if Seen.ContainsKey(Parent) or not Parents.ContainsKey(Parent) then
            begin
              Chain.Incomplete := True;
              Break;
            end;
            Seen.Add(Parent, True);
            Path.Insert(0, Parent);
            Parent := Parents[Parent];
          end;
        Chain.Ids := Path.ToArray;
        Result.Add(Id, Chain);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Path.Free;
    Next.Free;
    Frontier.Free;
    Seen.Free;
    Queried.Free;
    Parents.Free;
  end;
end;

function AncestorIdsJSON(const Chain: TAncestorChain): TJSONArray;
var
  Id: Integer;
begin
  Result := TJSONArray.Create;
  for Id in Chain.Ids do
    Result.Add(Id);
end;

procedure RefreshCachedItem(const Context: TToolContext; ItemId: Integer);
var
  Cached: TItem;
begin
  Cached := Context.Manager.FindCached<TItem>(ItemId);
  if Assigned(Cached) and not Context.Manager.HasChanges(Cached) then
    Context.Manager.Refresh(Cached);
end;

procedure ForgetCachedRow(const Context: TToolContext; Cached: TObject);
begin
  if Cached = nil then
    Exit;
  // A removed row must not come back from the session cache; Find would
  // return the stale object. The manager keeps ownership and frees it.
  Context.Manager.Evict(Cached);
  Context.Manager.AddOwnership(Cached);
end;

function GetOptAnalysisSnapshot(const Params: TJSONObject;
  out Json: string): Boolean;
var
  Field: TJSONValue;
begin
  Json := '';
  Field := nil;
  if Params <> nil then
    Field := Params.FindValue('analysis_snapshot');
  Result := (Field <> nil) and not (Field is TJSONNull);
  if not Result then
    Exit;
  if Field is TJSONObject then
    Json := Field.ToJSON
  else if Field is TJSONString then
    Json := Field.Value
  else
    raise Exception.Create('analysis_snapshot must be a JSON object or a ' +
      'string holding one JSON object.');
end;

function AnalysisSnapshotValue(const Json: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(Json);
  if not (Result is TJSONObject) then
  begin
    Result.Free;
    Result := TJSONString.Create(Json);
  end;
end;

function ParseRecType(const S: string): TRecType;
begin
  if SameText(S, 'EXP_CONDITION') then
    Result := EXP_CONDITION
  else if SameText(S, 'TEST_RESULT') then
    Result := TEST_RESULT
  else
    raise Exception.CreateFmt(
      'Invalid rec_type: %s (use EXP_CONDITION or TEST_RESULT)', [S]);
end;

function RecTypeName(RecType: TRecType): string;
begin
  if RecType = EXP_CONDITION then
    Result := 'EXP_CONDITION'
  else
    Result := 'TEST_RESULT';
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

function StoredValueJSON(Val: TValue; Issues: TValueIssues): TJSONObject;
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

end.
