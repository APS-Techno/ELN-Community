unit unit_SemanticSearchFilter;

interface

uses
  System.SysUtils,
  Aurelius.Engine.ObjectManager,
  unit_VectorSearch,
  unit_SemanticSearchApi;

function ResolveSemanticFilter(Manager: TObjectManager;
  const VisibleProjectIds: TArray<Integer>;
  const Filter: TSemanticSearchFilter): TItemFilter;

function DescribeValueConstraints(Manager: TObjectManager;
  const Constraints: TArray<TValueConstraint>): TArray<TAppliedLimit>;

function SemanticFilterResolver(Manager: TObjectManager):
  TFunc<TSemanticSearchFilter, TArray<Integer>, TItemFilter>;

function ValueLimitDescriber(Manager: TObjectManager):
  TFunc<TArray<TValueConstraint>, TArray<TAppliedLimit>>;

implementation

uses
  System.Math,
  System.TypInfo,
  System.Variants,
  System.Generics.Collections,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections,
  unit_ItemTypes,
  unit_Item,
  unit_Project,
  unit_ValueType,
  unit_ValueChecks,
  unit_UnitConverter;

resourcestring
  SFolderNotFound = 'The folder does not exist or is not available.';
  SValueTypeNotFound = 'Value type "%s" does not exist.';
  SUnknownUnit = 'Unit "%s" is not known.';
  SUnitMismatch = 'Unit "%s" cannot be converted to "%s", the unit of value type "%s".';
  SBadItemType = 'Unknown item type "%s".';
  SBadLevel = 'Unknown item level "%s".';
  SBadRecType = 'Unknown record type "%s" (use EXP_CONDITION or TEST_RESULT).';
  SBadDates = 'The start date is after the end date.';
  SBadRange = 'The minimum is greater than the maximum for value type "%s".';
  SBadNumber = 'A limit for value type "%s" is not a finite number.';

const
  InChunk = 400;

type
  TTypeBounds = record
    TypeId: Integer;
    HasLower, HasUpper: Boolean;
    Lower, Upper: Double;
  end;

  TCompiledConstraint = record
    Bounds: TArray<TTypeBounds>;
    HasRecType: Boolean;
    RecType: TRecType;
  end;

  TItemCriteria = record
    Types: TArray<Variant>;
    Levels: TArray<Variant>;
    ActionTypeId: Integer;
    DateField: TSemanticDateField;
    DateFrom, DateTo: TDateTime;
  end;

  TLoadedValueType = record
    Id: Integer;
    Title, Symbol, Units: string;
  end;

function RowInt(Row: TCriteriaResult; const Name: string): Integer;
var
  Value: Variant;
begin
  Value := Row.Values[Name];
  if VarIsNull(Value) then
    Result := 0
  else
    Result := Value;
end;

function RowText(Row: TCriteriaResult; const Name: string): string;
begin
  Result := VarToStr(Row.Values[Name]);
end;

function Chunked(const Ids: TArray<Integer>): TArray<TArray<Variant>>;
var
  Chunk: TArray<Variant>;
  I, N, K: Integer;
begin
  Result := nil;
  I := 0;
  while I < Length(Ids) do
  begin
    N := Min(InChunk, Length(Ids) - I);
    Chunk := nil;
    SetLength(Chunk, N);
    for K := 0 to N - 1 do
      Chunk[K] := Ids[I + K];
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Chunk;
    Inc(I, N);
  end;
end;

function ParseOrdinals(const Names: TArray<string>; Info: PTypeInfo;
  const ErrorFormat: string): TArray<Variant>;
var
  I, Ordinal: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Names));
  for I := 0 to High(Names) do
  begin
    Ordinal := GetEnumValue(Info, Trim(Names[I]));
    if Ordinal < 0 then
      raise ESemanticFilterError.CreateFmt(ErrorFormat, [Names[I]]);
    Result[I] := Ordinal;
  end;
end;

function ResolveFolders(Manager: TObjectManager; const VisibleProjectIds: TArray<Integer>;
  FolderId: Integer; out ProjectId: Integer): TArray<Integer>;
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Known: TDictionary<Integer, Integer>;
  Children: TObjectDictionary<Integer, TList<Integer>>;
  Seen: TDictionary<Integer, Boolean>;
  Queue: TList<Integer>;
  Siblings: TList<Integer>;
  Id, Parent, Next: Integer;
  I: Integer;
begin
  Known := TDictionary<Integer, Integer>.Create;
  Children := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  Seen := TDictionary<Integer, Boolean>.Create;
  Queue := TList<Integer>.Create;
  try
    for Chunk in Chunked(VisibleProjectIds) do
    begin
      Rows := Manager.Find<TProject>
        .CreateAlias('Folders', 'f')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('ProjectId'))
          .Add(TProjections.Prop('f.Id').As_('FolderId'))
          .Add(TProjections.Prop('f.ParentFolderID').As_('ParentId')))
        .Where(Linq['Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
        begin
          Id := RowInt(Row, 'FolderId');
          Parent := RowInt(Row, 'ParentId');
          Known.AddOrSetValue(Id, RowInt(Row, 'ProjectId'));
          if not Children.TryGetValue(Parent, Siblings) then
          begin
            Siblings := TList<Integer>.Create;
            Children.Add(Parent, Siblings);
          end;
          Siblings.Add(Id);
        end;
      finally
        Rows.Free;
      end;
    end;
    if not Known.TryGetValue(FolderId, ProjectId) then
      raise ESemanticFilterError.Create(SFolderNotFound);

    Queue.Add(FolderId);
    Seen.Add(FolderId, True);
    I := 0;
    while I < Queue.Count do
    begin
      if Children.TryGetValue(Queue[I], Siblings) then
        for Next in Siblings do
          if not Seen.ContainsKey(Next) and (Known[Next] = ProjectId) then
          begin
            Seen.Add(Next, True);
            Queue.Add(Next);
          end;
      Inc(I);
    end;
    Result := Queue.ToArray;
  finally
    Queue.Free;
    Seen.Free;
    Children.Free;
    Known.Free;
  end;
end;

function LoadValueTypes(Manager: TObjectManager): TArray<TLoadedValueType>;
var
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Loaded: TLoadedValueType;
  List: TList<TLoadedValueType>;
begin
  List := TList<TLoadedValueType>.Create;
  try
    Rows := Manager.Find<TValueType>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('Title').As_('Title'))
        .Add(TProjections.Prop('Symbol').As_('Symbol'))
        .Add(TProjections.Prop('Units').As_('Units')))
      .ListValues;
    try
      for Row in Rows do
      begin
        Loaded.Id := RowInt(Row, 'Id');
        Loaded.Title := RowText(Row, 'Title');
        Loaded.Symbol := RowText(Row, 'Symbol');
        Loaded.Units := RowText(Row, 'Units');
        List.Add(Loaded);
      end;
    finally
      Rows.Free;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ConvertLimit(Value: Double; const UnitSymbol: string;
  const ValueType: TLoadedValueType): Double;
var
  Factor: Double;
begin
  if (UnitSymbol = '') or (UnitSymbol = ValueType.Units) then
    Exit(Value);
  if TUnitConverter.TryFactor(UnitSymbol, ValueType.Units, Factor) then
    Exit(Value * Factor);
  if not TUnitConverter.UnitExists(UnitSymbol) then
    raise ESemanticFilterError.CreateFmt(SUnknownUnit, [UnitSymbol]);
  if TUnitConverter.GetCategoryForUnit(UnitSymbol) <>
    TUnitConverter.GetCategoryForUnit(ValueType.Units) then
    raise ESemanticFilterError.CreateFmt(SUnitMismatch,
      [UnitSymbol, ValueType.Units, ValueType.Title]);
  Result := TUnitConverter.Convert(Value, UnitSymbol, ValueType.Units);
end;

function CompileConstraint(const Types: TArray<TLoadedValueType>;
  const Constraint: TValueConstraint): TCompiledConstraint;
var
  ValueType: TLoadedValueType;
  Bounds: TTypeBounds;
  Ordinal: Integer;
begin
  Result := Default(TCompiledConstraint);
  if Constraint.RecType <> '' then
  begin
    Ordinal := GetEnumValue(TypeInfo(TRecType), Trim(Constraint.RecType));
    if Ordinal < 0 then
      raise ESemanticFilterError.CreateFmt(SBadRecType, [Constraint.RecType]);
    Result.HasRecType := True;
    Result.RecType := TRecType(Ordinal);
  end;
  if Constraint.HasMin and (IsNan(Constraint.Min) or IsInfinite(Constraint.Min)) or
    Constraint.HasMax and (IsNan(Constraint.Max) or IsInfinite(Constraint.Max)) then
    raise ESemanticFilterError.CreateFmt(SBadNumber, [Constraint.ValueType]);

  if Constraint.ValueType <> '' then
    for ValueType in Types do
      if ValueTypeNameMatches(ValueType.Title, ValueType.Symbol, Constraint.ValueType) then
      begin
        Bounds := Default(TTypeBounds);
        Bounds.TypeId := ValueType.Id;
        if Constraint.HasMin then
        begin
          Bounds.HasLower := True;
          Bounds.Lower := ConvertLimit(Constraint.Min, Constraint.UnitSymbol, ValueType);
        end;
        if Constraint.HasMax then
        begin
          Bounds.HasUpper := True;
          Bounds.Upper := ConvertLimit(Constraint.Max, Constraint.UnitSymbol, ValueType);
        end;
        if Bounds.HasLower and Bounds.HasUpper and (Bounds.Lower > Bounds.Upper) then
          raise ESemanticFilterError.CreateFmt(SBadRange, [ValueType.Title]);
        Result.Bounds := Result.Bounds + [Bounds];
      end;
  if Length(Result.Bounds) = 0 then
    raise ESemanticFilterError.CreateFmt(SValueTypeNotFound, [Constraint.ValueType]);
end;

procedure CollectItems(Manager: TObjectManager; const ProjectChunks,
  FolderChunks: TArray<TArray<Variant>>; const Criteria: TItemCriteria;
  Into: TDictionary<Integer, Boolean>);
var
  ProjectChunk, FolderChunk: TArray<Variant>;
  Expr: TLinqExpression;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  DateProperty: string;
begin
  if Criteria.DateField = sdfModified then
    DateProperty := 'ModifiedDate'
  else
    DateProperty := 'CreatedDate';
  for ProjectChunk in ProjectChunks do
    for FolderChunk in FolderChunks do
    begin
      Expr := (Linq['IsDeleted'] = False) and Linq['ProjectID']._In(ProjectChunk);
      if Length(FolderChunk) > 0 then
        Expr := Expr and Linq['FolderID']._In(FolderChunk);
      if Length(Criteria.Types) > 0 then
        Expr := Expr and Linq['Type_']._In(Criteria.Types);
      if Length(Criteria.Levels) > 0 then
        Expr := Expr and Linq['Level']._In(Criteria.Levels);
      if Criteria.DateField = sdfModified then
        Expr := Expr and Linq['ModifiedDate'].IsNotNull;
      if (Criteria.DateField <> sdfNone) and (Criteria.DateFrom > 0) then
        Expr := Expr and (Linq[DateProperty] >= VarFromDateTime(Int(Criteria.DateFrom)));
      if (Criteria.DateField <> sdfNone) and (Criteria.DateTo > 0) then
        Expr := Expr and (Linq[DateProperty] < VarFromDateTime(Int(Criteria.DateTo) + 1));
      if Criteria.ActionTypeId > 0 then
        Rows := Manager.Find<TItem>
          .CreateAlias('ActionType', 'a')
          .Select(TProjections.ProjectionList
            .Add(TProjections.Prop('Id').As_('Id')))
          .Where(Expr and (Linq['a.Id'] = Criteria.ActionTypeId))
          .ListValues
      else
        Rows := Manager.Find<TItem>
          .Select(TProjections.ProjectionList
            .Add(TProjections.Prop('Id').As_('Id')))
          .Where(Expr)
          .ListValues;
      try
        for Row in Rows do
          Into.AddOrSetValue(RowInt(Row, 'Id'), True);
      finally
        Rows.Free;
      end;
    end;
end;

procedure CollectValueItems(Manager: TObjectManager;
  const ProjectChunks: TArray<TArray<Variant>>; const Constraint: TCompiledConstraint;
  Into: TDictionary<Integer, Boolean>);
var
  ProjectChunk: TArray<Variant>;
  Bounds: TTypeBounds;
  Expr: TLinqExpression;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  for Bounds in Constraint.Bounds do
    for ProjectChunk in ProjectChunks do
    begin
      Expr := (Linq['i.IsDeleted'] = False) and Linq['i.ProjectID']._In(ProjectChunk) and
        (Linq['vt.Id'] = Bounds.TypeId);
      if Constraint.HasRecType then
        Expr := Expr and (Linq['RecType'] = Ord(Constraint.RecType));
      if Bounds.HasLower then
        Expr := Expr and (Linq['Value'] >= Bounds.Lower);
      if Bounds.HasUpper then
        Expr := Expr and (Linq['Value'] <= Bounds.Upper);
      Rows := Manager.Find<unit_Item.TValue>
        .CreateAlias('Item', 'i')
        .CreateAlias('ValueType', 'vt')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('i.Id').As_('ItemId')))
        .Where(Expr)
        .ListValues;
      try
        for Row in Rows do
          Into.AddOrSetValue(RowInt(Row, 'ItemId'), True);
      finally
        Rows.Free;
      end;
    end;
end;

procedure Intersect(Target, Other: TDictionary<Integer, Boolean>);
var
  Drop: TList<Integer>;
  Id: Integer;
begin
  Drop := TList<Integer>.Create;
  try
    for Id in Target.Keys do
      if not Other.ContainsKey(Id) then
        Drop.Add(Id);
    for Id in Drop do
      Target.Remove(Id);
  finally
    Drop.Free;
  end;
end;

function ResolveSemanticFilter(Manager: TObjectManager;
  const VisibleProjectIds: TArray<Integer>;
  const Filter: TSemanticSearchFilter): TItemFilter;
var
  Criteria: TItemCriteria;
  Constraints: TArray<TCompiledConstraint>;
  Constraint: TValueConstraint;
  Compiled: TCompiledConstraint;
  Types: TArray<TLoadedValueType>;
  Scope, FolderIds: TArray<Integer>;
  ProjectChunks, FolderChunks: TArray<TArray<Variant>>;
  Allowed, Found: TDictionary<Integer, Boolean>;
  FolderProject: Integer;
  Ids: TArray<Integer>;
begin
  Result := Default(TItemFilter);
  if Filter.IsEmpty then
    Exit;
  if Manager = nil then
    raise EArgumentNilException.Create('Manager is required');

  Criteria := Default(TItemCriteria);
  Criteria.Types := ParseOrdinals(Filter.ItemTypes, TypeInfo(TItemType), SBadItemType);
  Criteria.Levels := ParseOrdinals(Filter.Levels, TypeInfo(TItemLevel), SBadLevel);
  Criteria.ActionTypeId := Filter.ActionTypeId;
  Criteria.DateField := Filter.DateField;
  Criteria.DateFrom := Filter.DateFrom;
  Criteria.DateTo := Filter.DateTo;
  if (Filter.DateField <> sdfNone) and (Filter.DateFrom > 0) and (Filter.DateTo > 0) and
    (Int(Filter.DateFrom) > Int(Filter.DateTo)) then
    raise ESemanticFilterError.Create(SBadDates);

  Constraints := nil;
  if Length(Filter.Values) > 0 then
  begin
    Types := LoadValueTypes(Manager);
    for Constraint in Filter.Values do
      Constraints := Constraints + [CompileConstraint(Types, Constraint)];
  end;

  Scope := VisibleProjectIds;
  FolderIds := nil;
  if Filter.FolderId > 0 then
  begin
    FolderIds := ResolveFolders(Manager, VisibleProjectIds, Filter.FolderId, FolderProject);
    Scope := [FolderProject];
  end;
  ProjectChunks := Chunked(Scope);
  FolderChunks := Chunked(FolderIds);
  if Length(FolderChunks) = 0 then
  begin
    SetLength(FolderChunks, 1);
    FolderChunks[0] := nil;
  end;

  Allowed := nil;
  try
    if (Filter.FolderId > 0) or (Length(Criteria.Types) > 0) or (Length(Criteria.Levels) > 0) or
      (Criteria.ActionTypeId > 0) or (Criteria.DateField <> sdfNone) then
    begin
      Allowed := TDictionary<Integer, Boolean>.Create;
      CollectItems(Manager, ProjectChunks, FolderChunks, Criteria, Allowed);
    end;
    for Compiled in Constraints do
    begin
      if (Allowed <> nil) and (Allowed.Count = 0) then
        Break;
      Found := TDictionary<Integer, Boolean>.Create;
      try
        CollectValueItems(Manager, ProjectChunks, Compiled, Found);
        if Allowed = nil then
        begin
          Allowed := Found;
          Found := nil;
        end
        else
          Intersect(Allowed, Found);
      finally
        Found.Free;
      end;
    end;
    Ids := Allowed.Keys.ToArray;
    TArray.Sort<Integer>(Ids);
    Result := TItemFilter.Only(Ids);
  finally
    Allowed.Free;
  end;
end;

function DescribeValueConstraints(Manager: TObjectManager;
  const Constraints: TArray<TValueConstraint>): TArray<TAppliedLimit>;
var
  Types: TArray<TLoadedValueType>;
  Constraint: TValueConstraint;
  Compiled: TCompiledConstraint;
  Bounds: TTypeBounds;
  Loaded: TLoadedValueType;
  Limit: TAppliedLimit;
begin
  Result := nil;
  if Length(Constraints) = 0 then
    Exit;
  if Manager = nil then
    raise EArgumentNilException.Create('Manager is required');
  Types := LoadValueTypes(Manager);
  for Constraint in Constraints do
  begin
    Compiled := CompileConstraint(Types, Constraint);
    for Bounds in Compiled.Bounds do
      for Loaded in Types do
        if Loaded.Id = Bounds.TypeId then
        begin
          Limit := Default(TAppliedLimit);
          Limit.ValueTypeId := Loaded.Id;
          Limit.ValueType := Loaded.Title;
          Limit.Units := Loaded.Units;
          Limit.RequestedUnit := Trim(Constraint.UnitSymbol);
          if Compiled.HasRecType then
            Limit.RecType := GetEnumName(TypeInfo(TRecType), Ord(Compiled.RecType));
          if Bounds.HasLower then
          begin
            Limit.HasMin := True;
            Limit.Min := Bounds.Lower;
          end;
          if Bounds.HasUpper then
          begin
            Limit.HasMax := True;
            Limit.Max := Bounds.Upper;
          end;
          Result := Result + [Limit];
        end;
  end;
end;

function SemanticFilterResolver(Manager: TObjectManager):
  TFunc<TSemanticSearchFilter, TArray<Integer>, TItemFilter>;
begin
  Result :=
    function(Filter: TSemanticSearchFilter; VisibleProjectIds: TArray<Integer>): TItemFilter
    begin
      Result := ResolveSemanticFilter(Manager, VisibleProjectIds, Filter);
    end;
end;

function ValueLimitDescriber(Manager: TObjectManager):
  TFunc<TArray<TValueConstraint>, TArray<TAppliedLimit>>;
begin
  Result :=
    function(Constraints: TArray<TValueConstraint>): TArray<TAppliedLimit>
    begin
      Result := DescribeValueConstraints(Manager, Constraints);
    end;
end;

end.
