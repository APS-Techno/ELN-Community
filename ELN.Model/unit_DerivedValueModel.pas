unit unit_DerivedValueModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager,
  unit_Item,
  unit_ValueType,
  unit_DerivedFormulas;

const
  MAX_DERIVED_DEPTH = 64;

type
  TDerivedInputRef = record
    Role: string;
    ValueId: Integer;
  end;

  TDerivedResolvedInput = record
    Role: string;
    Value: TValue;
    Number: Double;
  end;

  TDerivedComputation = record
    Formula: TDerivedFormula;
    ResultType: TValueType;
    Inputs: TArray<TDerivedResolvedInput>;
    Number: Double;
  end;

  TDerivedValueModel = class
  private
    FManager: TObjectManager;
    function FindType(const Title, Units: string): TValueType;
    function InSubtree(ResultItem, Candidate: TItem): Boolean;
    procedure CheckInputTree(Value: TValue; Visiting: TList<Integer>;
      Depth: Integer);
    procedure Discard(Item: TItem; Value: TValue);
  public
    constructor Create(Manager: TObjectManager);
    function Compute(ResultItem: TItem; const FormulaId: string;
      const Inputs: TArray<TDerivedInputRef>): TDerivedComputation;
    function Store(ResultItem: TItem; const Computation: TDerivedComputation;
      const Description: string; UserId: Integer;
      const AuditText: string): TValue;
    function SubtreeItems(ResultItem: TItem): TArray<TItem>;
    function Candidates(ResultItem: TItem;
      const Role: TDerivedFormulaRole): TArray<TValue>;
    class function HasStorage(const Connection: IDBConnection): Boolean; static;
  end;

implementation

uses
  Aurelius.Criteria.Linq,
  unit_ItemTypes,
  unit_ValueSource,
  unit_AuditLog,
  unit_AuditHelper,
  unit_SignatureModel,
  unit_TimeHelper;

constructor TDerivedValueModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
end;

function TDerivedValueModel.FindType(const Title, Units: string): TValueType;
var
  Types: TList<TValueType>;
  VT: TValueType;
begin
  Result := nil;
  Types := FManager.Find<TValueType>.List;
  try
    for VT in Types do
      if SameText(VT.Title, Title) and (VT.Units = Units) then
        Exit(VT);
  finally
    Types.Free;
  end;
end;

function TDerivedValueModel.InSubtree(ResultItem, Candidate: TItem): Boolean;
var
  Current: TItem;
  Depth: Integer;
begin
  Result := False;
  if (Candidate = nil) or (Candidate.ProjectID <> ResultItem.ProjectID) or
    Candidate.IsDeleted then
    Exit;
  Current := Candidate;
  Depth := 0;
  while Assigned(Current) and (Depth <= 1000) do
  begin
    if Current.Id = ResultItem.Id then
      Exit(True);
    if Current.Parent <= 0 then
      Exit;
    Current := FManager.Find<TItem>(Current.Parent);
    Inc(Depth);
  end;
end;

procedure TDerivedValueModel.CheckInputTree(Value: TValue;
  Visiting: TList<Integer>; Depth: Integer);
var
  Formula: TDerivedFormula;
  Link: TDerivedValueInput;
  Input: TValue;
begin
  if Value.EffectiveSourceKind <> vskDerived then
    Exit;
  if Visiting.Contains(Value.Id) then
    raise EDerivedValueError.CreateFmt(
      'Derived value %d depends on itself (dependency cycle)', [Value.Id]);
  if Depth > MAX_DERIVED_DEPTH then
    raise EDerivedValueError.CreateFmt(
      'Derived inputs are nested deeper than %d levels', [MAX_DERIVED_DEPTH]);
  if not Value.FormulaId.HasValue or not Value.FormulaVersion.HasValue or
    not TryGetDerivedFormula(Value.FormulaId.Value, Value.FormulaVersion.Value,
    Formula) then
    raise EDerivedValueError.CreateFmt(
      'Derived input value %d uses formula %s version %s, which is not available',
      [Value.Id, Value.FormulaId.ValueOrDefault,
      IntToStr(Value.FormulaVersion.ValueOrDefault)]);
  Visiting.Add(Value.Id);
  try
    for Link in Value.DerivedInputs do
    begin
      Input := FManager.Find<TValue>(Link.InputValueId);
      if Input = nil then
        raise EDerivedValueError.CreateFmt(
          'Input value %d (role %s) of Derived value %d no longer exists',
          [Link.InputValueId, Link.Role, Value.Id]);
      CheckInputTree(Input, Visiting, Depth + 1);
    end;
  finally
    Visiting.Remove(Value.Id);
  end;
end;

function TDerivedValueModel.Compute(ResultItem: TItem; const FormulaId: string;
  const Inputs: TArray<TDerivedInputRef>): TDerivedComputation;
var
  Ref: TDerivedInputRef;
  Index, I, J: Integer;
  Counts: TArray<Integer>;
  Sums: TArray<Double>;
  Input: TValue;
  Numbers: TArray<Double>;
  Visiting: TList<Integer>;
  Resolved: TList<TDerivedResolvedInput>;
  Entry: TDerivedResolvedInput;
begin
  Result := Default(TDerivedComputation);
  if ResultItem = nil then
    raise EDerivedValueError.Create('The result item does not exist');
  if ResultItem.IsDeleted then
    raise EDerivedValueError.CreateFmt('Item %d is deleted', [ResultItem.Id]);
  if not TryGetCurrentDerivedFormula(FormulaId, Result.Formula) then
    raise EDerivedValueError.CreateFmt('Unknown formula: %s', [FormulaId]);
  SetLength(Counts, Length(Result.Formula.Roles));
  SetLength(Sums, Length(Result.Formula.Roles));
  Resolved := TList<TDerivedResolvedInput>.Create;
  try
    for Ref in Inputs do
    begin
      Index := Result.Formula.RoleIndex(Ref.Role);
      if Index < 0 then
        raise EDerivedValueError.CreateFmt('Formula %s has no role %s',
          [FormulaId, Ref.Role]);
      if (Counts[Index] > 0) and not Result.Formula.Roles[Index].Mean then
        raise EDerivedValueError.CreateFmt('Role %s is given twice', [Ref.Role]);
      for Entry in Resolved do
        if (Entry.Role = Ref.Role) and (Entry.Value.Id = Ref.ValueId) then
          raise EDerivedValueError.CreateFmt(
            'Input value %d is given twice for role %s', [Ref.ValueId, Ref.Role]);
      Input := FManager.Find<TValue>(Ref.ValueId);
      if Input = nil then
        raise EDerivedValueError.CreateFmt('Input value %d (role %s) does not exist',
          [Ref.ValueId, Ref.Role]);
      if (Input.Item = nil) or (Input.Item.ProjectID <> ResultItem.ProjectID) then
        raise EDerivedValueError.CreateFmt(
          'Input value %d (role %s) belongs to another project than item %d',
          [Ref.ValueId, Ref.Role, ResultItem.Id]);
      if not InSubtree(ResultItem, Input.Item) then
        raise EDerivedValueError.CreateFmt(
          'Input value %d (role %s) is not stored on item %d or an item below it',
          [Ref.ValueId, Ref.Role, ResultItem.Id]);
      if not RoleMatches(Input, Result.Formula.Roles[Index]) then
        raise EDerivedValueError.CreateFmt(
          'Input value %d for role %s has value type %s (%s); the role requires %s (%s)',
          [Ref.ValueId, Ref.Role, Input.ValueType.Title, Input.ValueType.Units,
          Result.Formula.Roles[Index].TypeTitle, Result.Formula.Roles[Index].Units]);
      Inc(Counts[Index]);
      Sums[Index] := Sums[Index] + Input.Value;
      Entry.Role := Ref.Role;
      Entry.Value := Input;
      Entry.Number := Input.Value;
      Resolved.Add(Entry);
    end;
    for I := 0 to High(Counts) do
      if Counts[I] = 0 then
        raise EDerivedValueError.CreateFmt('Missing input for role %s',
          [Result.Formula.Roles[I].Name]);
    for I := 0 to High(Counts) do
      for J := 0 to Resolved.Count - 1 do
        if Resolved[J].Role = Result.Formula.Roles[I].Name then
        begin
          SetLength(Result.Inputs, Length(Result.Inputs) + 1);
          Result.Inputs[High(Result.Inputs)] := Resolved[J];
        end;
  finally
    Resolved.Free;
  end;
  Visiting := TList<Integer>.Create;
  try
    for I := 0 to High(Result.Inputs) do
      CheckInputTree(Result.Inputs[I].Value, Visiting, 1);
  finally
    Visiting.Free;
  end;
  SetLength(Numbers, Length(Counts));
  for I := 0 to High(Counts) do
    Numbers[I] := Sums[I] / Counts[I];
  Result.Number := Result.Formula.Evaluate(Numbers);
  Result.ResultType := FindType(Result.Formula.ResultTitle, Result.Formula.ResultUnits);
  if Result.ResultType = nil then
    raise EDerivedValueError.CreateFmt('The value type %s (%s) is missing',
      [Result.Formula.ResultTitle, Result.Formula.ResultUnits]);
end;

procedure TDerivedValueModel.Discard(Item: TItem; Value: TValue);
begin
  if Value = nil then
    Exit;
  Item.Values.Remove(Value);
  try
    FManager.Evict(Value);
  except
    Value.Free;
    Exit;
  end;
  FManager.AddOwnership(Value);
end;

function TDerivedValueModel.Store(ResultItem: TItem;
  const Computation: TDerivedComputation; const Description: string;
  UserId: Integer; const AuditText: string): TValue;
var
  Trans: IDBTransaction;
  Link: TDerivedValueInput;
  Input: TDerivedResolvedInput;
begin
  if IsItemSignedCheck(FManager, ResultItem.Id) then
    raise EDerivedValueError.Create('Item is signed and cannot be modified');
  Result := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    Result := TValue.Create;
    Result.Item := ResultItem;
    Result.ValueType := Computation.ResultType;
    Result.RecType := TEST_RESULT;
    Result.Value := Computation.Number;
    Result.Tol := 0;
    Result.Description := Description;
    Result.CreatedDate := UTCNow;
    Result.CreatedBy := UserId;
    ApplySource(Result, TValueSourceInfo.Derived(Computation.Formula.Id,
      Computation.Formula.Version));
    for Input in Computation.Inputs do
    begin
      Link := TDerivedValueInput.Create;
      Link.ResultValue := Result;
      Link.Role := Input.Role;
      Link.InputValueId := Input.Value.Id;
      Link.InputValue := Input.Number;
      Result.DerivedInputs.Add(Link);
    end;
    ResultItem.Values.Add(Result);
    FManager.Update(ResultItem);
    FManager.Flush;
    RecordAudit(FManager, aetValue, Result.Id, aoCreate, UserId, AuditText);
    Trans.Commit;
  except
    try
      Trans.Rollback;
    except
    end;
    Discard(ResultItem, Result);
    raise;
  end;
end;

function TDerivedValueModel.SubtreeItems(ResultItem: TItem): TArray<TItem>;
var
  All: TList<TItem>;
  Found: TList<TItem>;
  Item: TItem;
  Index: Integer;
begin
  All := FManager.Find<TItem>
    .Where(Linq['ProjectID'] = ResultItem.ProjectID).List;
  Found := TList<TItem>.Create;
  try
    Found.Add(ResultItem);
    Index := 0;
    while Index < Found.Count do
    begin
      for Item in All do
        if (Item.Parent = Found[Index].Id) and not Item.IsDeleted and
          not Found.Contains(Item) then
          Found.Add(Item);
      Inc(Index);
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
    All.Free;
  end;
end;

function TDerivedValueModel.Candidates(ResultItem: TItem;
  const Role: TDerivedFormulaRole): TArray<TValue>;
var
  Item: TItem;
  V: TValue;
  Found: TList<TValue>;
begin
  Found := TList<TValue>.Create;
  try
    for Item in SubtreeItems(ResultItem) do
      for V in Item.Values do
        if RoleMatches(V, Role) then
          Found.Add(V);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

class function TDerivedValueModel.HasStorage(const Connection: IDBConnection): Boolean;
var
  Statement: IDBStatement;
begin
  try
    Statement := Connection.CreateStatement;
    Statement.SetSQLCommand('SELECT FormulaId, FormulaVersion FROM DataValues WHERE 1 = 0');
    Statement.ExecuteQuery;
    Statement := Connection.CreateStatement;
    Statement.SetSQLCommand('SELECT ResultValueId, Role, InputValueId, InputValue ' +
      'FROM DerivedValueInputs WHERE 1 = 0');
    Statement.ExecuteQuery;
    Result := True;
  except
    Result := False;
  end;
end;

end.
