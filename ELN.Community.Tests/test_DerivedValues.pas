unit test_DerivedValues;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  unit_LocalNotebook, unit_Item, unit_ValueSource, unit_DerivedValueModel;

type
  [TestFixture]
  TDerivedValueTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProjectId: Integer;
    function NewProject(const Title: string): Integer;
    function NewItem(ProjectId, ParentId: Integer; const Title: string): TItem;
    function AddValue(Item: TItem; const Title, Units: string; Number: Double;
      const Source: TValueSourceInfo): Integer;
    function Manual(Item: TItem; const Title, Units: string; Number: Double): Integer;
    function Ref(const Role: string; ValueId: Integer): TDerivedInputRef;
    function Derive(Item: TItem; const FormulaId: string;
      const Inputs: TArray<TDerivedInputRef>): TValue;
    procedure ExpectRefusal(Item: TItem; const FormulaId: string;
      const Inputs: TArray<TDerivedInputRef>; const Fragment: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure WearRateUsesKnownNumbersAndAllowsZeroArea;
    [Test] procedure EvaluateRefusesInvalidNumbers;
    [Test] procedure ComputeRefusesWrongInputs;
    [Test] procedure SeveralWearAreasAreAveragedAndChecked;
    [Test] procedure StoredValueHasSourceLinksAndNoTolerance;
    [Test] procedure DerivedInputChainIsCheckedRecursively;
    [Test] procedure DependencyCycleIsRefusedAndReported;
    [Test] procedure DriftReRunsReaderInputsAndReportsMissingInput;
    [Test] procedure DriftReportsFormulaVersions;
    [Test] procedure SeedProvidesEveryBuiltInFormulaType;
  end;

implementation

uses
  System.IOUtils, System.Math, System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_Project, unit_ItemTypes, unit_ValueType, unit_ItemModel,
  unit_DerivedFormulas, unit_ValueDrift;

const
  Password = 'Synthetic-Derived-Only!';
  COPY_FORMULA_ID = 'synthetic_area_double';

type
  TWearRunner = class(TInterfacedObject, IValueReaderRunner)
    Area, Force, Cycles: Double;
    function Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
  end;

function TWearRunner.Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
begin
  Result := Default(TReaderRun);
  Result.Succeeded := True;
  Result.ReaderId := 'synthetic.wear';
  Result.ReaderVersion := '1';
  SetLength(Result.Values, 3);
  Result.Values[0].Name := 'Wear Area';
  Result.Values[0].Value := Area;
  Result.Values[0].Units := 'um2';
  Result.Values[1].Name := 'Fn';
  Result.Values[1].Value := Force;
  Result.Values[1].Units := 'N';
  Result.Values[2].Name := 'Cycles';
  Result.Values[2].Value := Cycles;
end;

function AreaUnits: string;
begin
  Result := 'mm' + WideChar($00B2);
end;

function CopyFormula: TDerivedFormula;
begin
  Result := Default(TDerivedFormula);
  Result.Id := COPY_FORMULA_ID;
  Result.Version := 1;
  Result.Title := 'Synthetic doubled area';
  Result.Expression := 'A2 = 2 A';
  SetLength(Result.Roles, 1);
  Result.Roles[0].Name := 'area';
  Result.Roles[0].TypeTitle := 'Wear area';
  Result.Roles[0].Units := AreaUnits;
  Result.Roles[0].AllowZero := True;
  Result.ResultTitle := 'Wear area';
  Result.ResultUnits := AreaUnits;
  Result.Compute :=
    function(const Inputs: TArray<Double>): Double
    begin
      Result := 2 * Inputs[0];
    end;
end;

procedure TDerivedValueTests.Setup;
var
  Id: TGUID;
begin
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-Derived-' + GUIDToString(Id));
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  FProjectId := NewProject('Derived project');
  RegisterDerivedFormula(CopyFormula);
end;

procedure TDerivedValueTests.TearDown;
begin
  UnregisterDerivedFormula(COPY_FORMULA_ID, 1);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TDerivedValueTests.NewProject(const Title: string): Integer;
var
  Project: TProject;
begin
  Project := TProject.Create;
  Project.Title := Title;
  Project.FileFolder := Title;
  Project.Owner := FNotebook.Principal;
  Project.CreatedBy := FNotebook.Principal.Id;
  Project.CreatedDate := Now;
  FNotebook.Manager.Save(Project);
  FNotebook.Manager.Flush;
  Result := Project.Id;
end;

function TDerivedValueTests.NewItem(ProjectId, ParentId: Integer;
  const Title: string): TItem;
var
  Id: Integer;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.ProjectID := ProjectId;
  Result.Parent := ParentId;
  Result.Level := TItemLevel.Proc;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
  Id := Result.Id;
  FNotebook.Manager.Evict(Result);
  Result.Free;
  Result := FNotebook.Manager.Find<TItem>(Id);
end;

function TDerivedValueTests.AddValue(Item: TItem; const Title, Units: string;
  Number: Double; const Source: TValueSourceInfo): Integer;
var
  Types: TList<TValueType>;
  VT, Found: TValueType;
  Items: TItemModel;
begin
  Found := nil;
  Types := FNotebook.Manager.Find<TValueType>.List;
  try
    for VT in Types do
      if (VT.Title = Title) and (VT.Units = Units) then
        Found := VT;
  finally
    Types.Free;
  end;
  if Found = nil then
  begin
    Found := TValueType.Create;
    Found.Symbol := Title;
    Found.Title := Title;
    Found.Units := Units;
    Found.CreatedDate := Now;
    FNotebook.Manager.Save(Found);
    FNotebook.Manager.Flush;
  end;
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Items.AddValue(Found, EXP_CONDITION, Number, FNotebook.Principal.Id, Item, 0,
      '', Source);
  finally
    Items.Free;
  end;
  Result := Item.Values[Item.Values.Count - 1].Id;
end;

function TDerivedValueTests.Manual(Item: TItem; const Title, Units: string;
  Number: Double): Integer;
begin
  Result := AddValue(Item, Title, Units, Number, TValueSourceInfo.Manual('lab book'));
end;

function TDerivedValueTests.Ref(const Role: string; ValueId: Integer): TDerivedInputRef;
begin
  Result.Role := Role;
  Result.ValueId := ValueId;
end;

function TDerivedValueTests.Derive(Item: TItem; const FormulaId: string;
  const Inputs: TArray<TDerivedInputRef>): TValue;
var
  Model: TDerivedValueModel;
begin
  Model := TDerivedValueModel.Create(FNotebook.Manager);
  try
    Result := Model.Store(Item, Model.Compute(Item, FormulaId, Inputs), '',
      FNotebook.Principal.Id, 'Added derived value');
  finally
    Model.Free;
  end;
end;

procedure TDerivedValueTests.ExpectRefusal(Item: TItem; const FormulaId: string;
  const Inputs: TArray<TDerivedInputRef>; const Fragment: string);
var
  Model: TDerivedValueModel;
  Message: string;
begin
  Message := '';
  Model := TDerivedValueModel.Create(FNotebook.Manager);
  try
    try
      Model.Compute(Item, FormulaId, Inputs);
    except
      on E: EDerivedValueError do
        Message := E.Message;
    end;
  finally
    Model.Free;
  end;
  Assert.IsTrue(Message <> '', 'The Derived value must be refused: ' + Fragment);
  Assert.Contains(Message, Fragment);
end;

procedure TDerivedValueTests.SeedProvidesEveryBuiltInFormulaType;
var
  Formula: TDerivedFormula;
  Role: TDerivedFormulaRole;
  Types: TList<TValueType>;

  function Seeded(const Title, Units: string): Boolean;
  var
    VT: TValueType;
  begin
    for VT in Types do
      if (VT.Title = Title) and (VT.Units = Units) then
        Exit(True);
    Result := False;
  end;

begin
  UnregisterDerivedFormula(COPY_FORMULA_ID, 1);
  Types := FNotebook.Manager.Find<TValueType>.List;
  try
    for Formula in CurrentDerivedFormulas do
    begin
      for Role in Formula.Roles do
        Assert.IsTrue(Seeded(Role.TypeTitle, Role.Units),
          Formula.Id + ' role ' + Role.Name + ' type must be seeded');
      Assert.IsTrue(Seeded(Formula.ResultTitle, Formula.ResultUnits),
        Formula.Id + ' result type must be seeded');
    end;
  finally
    Types.Free;
    RegisterDerivedFormula(CopyFormula);
  end;
end;

procedure TDerivedValueTests.WearRateUsesKnownNumbersAndAllowsZeroArea;
var
  Item: TItem;
  Force, Cycles: Integer;
begin
  Assert.AreEqual(4e-7, WearRateFormula.Evaluate([0.004, 5, 1000]), 1e-20);
  Assert.AreEqual(1.25e-6, WearRateFormula.Evaluate([0.01, 4, 1000]), 1e-20);
  Assert.AreEqual<Double>(0, WearRateFormula.Evaluate([0, 5, 1000]));
  Item := NewItem(FProjectId, 0, 'Wear test');
  Force := Manual(Item, 'Normal force', 'N', 5);
  Cycles := Manual(Item, 'Cycles', '', 1000);
  Assert.AreEqual(4e-7, Derive(Item, WEAR_RATE_FORMULA_ID, [Ref('area',
    Manual(Item, 'Wear area', AreaUnits, 0.004)), Ref('normal_force', Force),
    Ref('cycles', Cycles)]).Value, 1e-20);
  Assert.AreEqual<Double>(0, Derive(Item, WEAR_RATE_FORMULA_ID, [Ref('area',
    Manual(Item, 'Wear area', AreaUnits, 0)), Ref('normal_force', Force),
    Ref('cycles', Cycles)]).Value);
end;

procedure TDerivedValueTests.EvaluateRefusesInvalidNumbers;
begin
  Assert.WillRaise(procedure begin WearRateFormula.Evaluate([0.004, 0, 1000]) end,
    EDerivedValueError);
  Assert.WillRaise(procedure begin WearRateFormula.Evaluate([0.004, -5, 1000]) end,
    EDerivedValueError);
  Assert.WillRaise(procedure begin WearRateFormula.Evaluate([0.004, 5, 0]) end,
    EDerivedValueError);
  Assert.WillRaise(procedure begin WearRateFormula.Evaluate([-0.004, 5, 1000]) end,
    EDerivedValueError);
  Assert.WillRaise(procedure begin WearRateFormula.Evaluate([NaN, 5, 1000]) end,
    EDerivedValueError);
  Assert.WillRaise(procedure begin WearRateFormula.Evaluate([0.004, Infinity, 1000]) end,
    EDerivedValueError);
  Assert.WillRaise(procedure begin WearRateFormula.Evaluate([0.004, 5]) end,
    EDerivedValueError);
end;

procedure TDerivedValueTests.ComputeRefusesWrongInputs;
var
  Item, Child, Sibling, Foreign: TItem;
  Area, Force, Cycles, WrongUnit, WrongType, ChildArea, SiblingArea, ForeignArea,
  ZeroForce: Integer;
  Model: TDerivedValueModel;
begin
  Item := NewItem(FProjectId, 0, 'Wear test');
  Child := NewItem(FProjectId, Item.Id, 'Wear track');
  Sibling := NewItem(FProjectId, 0, 'Unrelated');
  Foreign := NewItem(NewProject('Other project'), 0, 'Other');
  Area := Manual(Item, 'Wear area', AreaUnits, 0.004);
  Force := Manual(Item, 'Normal force', 'N', 5);
  Cycles := Manual(Item, 'Cycles', '', 1000);
  ZeroForce := Manual(Item, 'Normal force', 'N', 0);
  WrongUnit := Manual(Item, 'Wear area', 'um2', 4000);
  WrongType := Manual(Item, 'Thickness', 'm', 1e-6);
  ChildArea := Manual(Child, 'Wear area', AreaUnits, 0.004);
  SiblingArea := Manual(Sibling, 'Wear area', AreaUnits, 0.004);
  ForeignArea := Manual(Foreign, 'Wear area', AreaUnits, 0.004);
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', WrongUnit),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'the role requires Wear area');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Area),
    Ref('normal_force', WrongType), Ref('cycles', Cycles)], 'the role requires Normal force');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Area),
    Ref('normal_force', Force)], 'Missing input for role cycles');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', SiblingArea),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'is not stored on item');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', ForeignArea),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'another project');
  ExpectRefusal(Child, WEAR_RATE_FORMULA_ID, [Ref('area', ChildArea),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'is not stored on item');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Area), Ref('area', Area),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'given twice');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('volume', Area),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'has no role volume');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Area),
    Ref('normal_force', ZeroForce), Ref('cycles', Cycles)], 'normal_force must be positive');
  ExpectRefusal(Item, 'no_such_formula', [], 'Unknown formula');
  Model := TDerivedValueModel.Create(FNotebook.Manager);
  try
    Assert.AreEqual(4e-7, Model.Compute(Item, WEAR_RATE_FORMULA_ID, [Ref('area', ChildArea),
      Ref('normal_force', Force), Ref('cycles', Cycles)]).Number, 1e-20,
      'An input of a descendant item is accepted');
    Assert.AreEqual(2, Length(Model.Candidates(Item, WearRateFormula.Roles[0])),
      'Only values of the role type and unit in the subtree are offered');
  finally
    Model.Free;
  end;
end;

procedure TDerivedValueTests.StoredValueHasSourceLinksAndNoTolerance;
var
  Item: TItem;
  Area, Force, Cycles, Id: Integer;
  Fresh: TObjectManager;
  Stored: TValue;
  Source: TValueSourceInfo;
begin
  Item := NewItem(FProjectId, 0, 'Wear test');
  Area := Manual(Item, 'Wear area', AreaUnits, 0.004);
  Force := Manual(Item, 'Normal force', 'N', 5);
  Cycles := Manual(Item, 'Cycles', '', 1000);
  Id := Derive(Item, WEAR_RATE_FORMULA_ID, [Ref('cycles', Cycles), Ref('area', Area),
    Ref('normal_force', Force)]).Id;
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Stored := Fresh.Find<TValue>(Id);
    Source := ReadSource(Stored);
    Assert.IsTrue(Source.Kind = vskDerived);
    Assert.AreEqual(WEAR_RATE_FORMULA_ID, Source.FormulaId);
    Assert.AreEqual(1, Source.FormulaVersion);
    Assert.AreEqual<Double>(0, Stored.Tol, 'A Derived value has no tolerance');
    Assert.AreEqual('Wear rate', Stored.ValueType.Title);
    Assert.AreEqual(3, Stored.DerivedInputs.Count);
    Assert.AreEqual('area', Stored.DerivedInputs[0].Role);
    Assert.AreEqual(Area, Stored.DerivedInputs[0].InputValueId);
    Assert.AreEqual(0.004, Stored.DerivedInputs[0].InputValue, 1e-15);
    MarkManualEdit(Stored);
    Assert.IsTrue(Stored.EffectiveSourceKind = vskManual,
      'Editing a Derived number by hand makes it Manual');
    Assert.Contains(Stored.SourceNote, 'was derived by ' + WEAR_RATE_FORMULA_ID + ' version 1');
    Assert.IsFalse(Stored.FormulaId.HasValue);
  finally
    Fresh.Free;
  end;
end;

procedure TDerivedValueTests.DerivedInputChainIsCheckedRecursively;
var
  Item: TItem;
  Base, Force, Cycles: Integer;
  Doubled: TValue;
  Report: TValueDriftReport;
  Runner: IValueReaderRunner;
  Row: TValueDriftRow;
  Items: TItemModel;
begin
  Item := NewItem(FProjectId, 0, 'Wear test');
  Base := Manual(Item, 'Wear area', AreaUnits, 0.004);
  Force := Manual(Item, 'Normal force', 'N', 5);
  Cycles := Manual(Item, 'Cycles', '', 1000);
  Doubled := Derive(Item, COPY_FORMULA_ID, [Ref('area', Base)]);
  Assert.AreEqual(0.008, Doubled.Value, 1e-15);
  Assert.AreEqual(8e-7, Derive(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Doubled.Id),
    Ref('normal_force', Force), Ref('cycles', Cycles)]).Value, 1e-20,
    'A Derived input is accepted');
  Runner := TWearRunner.Create;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
  Assert.AreEqual(2, Report.Checked);
  for Row in Report.Rows do
    Assert.IsTrue(vdfNotFullyRerunnable in Row.Flags,
      'A Manual value anywhere in the tree is reported');
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Items.RemoveValue(FNotebook.Manager.Find<TValue>(Base), Item, FNotebook.Principal.Id);
  finally
    Items.Free;
  end;
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Doubled.Id),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'no longer exists');
end;

procedure TDerivedValueTests.SeveralWearAreasAreAveragedAndChecked;
var
  Item: TItem;
  A1, A2, A3, Force, Cycles: Integer;
  Derived: TValue;
  Report: TValueDriftReport;
  Row: TValueDriftRow;
  Runner: IValueReaderRunner;
  Count: Integer;
  Link: TDerivedValueInput;
begin
  Item := NewItem(FProjectId, 0, 'Wear test');
  A1 := Manual(Item, 'Wear area', AreaUnits, 0.002);
  A2 := Manual(Item, 'Wear area', AreaUnits, 0.004);
  A3 := Manual(Item, 'Wear area', AreaUnits, 0.006);
  Force := Manual(Item, 'Normal force', 'N', 5);
  Cycles := Manual(Item, 'Cycles', '', 1000);
  Derived := Derive(Item, WEAR_RATE_FORMULA_ID, [Ref('area', A1), Ref('area', A2),
    Ref('area', A3), Ref('normal_force', Force), Ref('cycles', Cycles)]);
  Assert.AreEqual(4e-7, Derived.Value, 1e-20, 'The mean area 0.004 is used');
  Assert.AreEqual(5, Derived.DerivedInputs.Count, 'Every input is stored');
  Count := 0;
  for Link in Derived.DerivedInputs do
    if Link.Role = 'area' then
      Inc(Count);
  Assert.AreEqual(3, Count, 'All three areas are stored under the area role');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', A1), Ref('area', A1),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'given twice');
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', A1),
    Ref('normal_force', Force), Ref('normal_force', Force), Ref('cycles', Cycles)],
    'given twice');
  FNotebook.Manager.Find<TValue>(A3).Value := 0.012;
  FNotebook.Manager.Flush;
  Runner := TWearRunner.Create;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
  for Row in Report.Rows do
    if Row.ValueId = Derived.Id then
    begin
      Assert.IsTrue(vdfInputChanged in Row.Flags, 'A changed area input is reported');
      Assert.IsTrue(vdfValueChanged in Row.Flags);
      Assert.AreEqual(6e-7, Row.CurrentValue, 1e-20,
        'The mean of the current areas (0.006) is used');
      Assert.AreEqual(5, Length(Row.Inputs), 'Every input has a drift entry');
      Exit;
    end;
  Assert.Fail('The Derived value must be reported');
end;

procedure TDerivedValueTests.DependencyCycleIsRefusedAndReported;
var
  Item: TItem;
  Base, Force, Cycles: Integer;
  A, B: TValue;
  Runner: IValueReaderRunner;
  Report: TValueDriftReport;
  Row: TValueDriftRow;
begin
  Item := NewItem(FProjectId, 0, 'Wear test');
  Base := Manual(Item, 'Wear area', AreaUnits, 0.004);
  Force := Manual(Item, 'Normal force', 'N', 5);
  Cycles := Manual(Item, 'Cycles', '', 1000);
  A := Derive(Item, COPY_FORMULA_ID, [Ref('area', Base)]);
  B := Derive(Item, COPY_FORMULA_ID, [Ref('area', A.Id)]);
  A.DerivedInputs[0].InputValueId := B.Id;
  FNotebook.Manager.Flush;
  ExpectRefusal(Item, WEAR_RATE_FORMULA_ID, [Ref('area', A.Id),
    Ref('normal_force', Force), Ref('cycles', Cycles)], 'cycle');
  Runner := TWearRunner.Create;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
  for Row in Report.Rows do
    if Row.ValueId = A.Id then
    begin
      Assert.IsTrue(vdfDependencyCycle in Row.Flags, 'The drift check reports the cycle');
      Assert.IsFalse(Row.HasCurrentValue, 'A cyclic value is not recomputed');
      Exit;
    end;
  Assert.Fail('The cyclic value must be reported');
end;

procedure TDerivedValueTests.DriftReRunsReaderInputsAndReportsMissingInput;
var
  Item: TItem;
  Area, Force, Cycles: Integer;
  Derived: TValue;
  Wear: TWearRunner;
  Runner: IValueReaderRunner;
  Report: TValueDriftReport;
  Row: TValueDriftRow;
  Items: TItemModel;
  SawArea, SawDerived: Boolean;
begin
  Item := NewItem(FProjectId, 0, 'Wear test');
  Area := AddValue(Item, 'Wear area', AreaUnits, 0.004,
    TValueSourceInfo.Reader(1, 'synthetic.wear', '1', 'Wear Area', 'um2', 1e-6));
  Force := AddValue(Item, 'Normal force', 'N', 5,
    TValueSourceInfo.Reader(1, 'synthetic.wear', '1', 'Fn', 'N', 1));
  Cycles := AddValue(Item, 'Cycles', '', 1000,
    TValueSourceInfo.Reader(1, 'synthetic.wear', '1', 'Cycles', '', 1));
  Derived := Derive(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Area),
    Ref('normal_force', Force), Ref('cycles', Cycles)]);
  Wear := TWearRunner.Create;
  Wear.Area := 4000;
  Wear.Force := 5;
  Wear.Cycles := 1000;
  Runner := Wear;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
  Assert.AreEqual(4, Report.Checked);
  Assert.AreEqual(4, Report.Unchanged, 'Unchanged reader output gives no drift');

  Wear.Area := 8000;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
  Assert.AreEqual(2, Integer(Length(Report.Rows)));
  SawArea := False;
  SawDerived := False;
  for Row in Report.Rows do
    if Row.ValueId = Area then
    begin
      SawArea := Row.Flags = [vdfValueChanged];
    end
    else if Row.ValueId = Derived.Id then
    begin
      SawDerived := (Row.Flags = [vdfValueChanged, vdfInputChanged]) and
        SameValue(Row.CurrentValue, 8e-7, 1e-20) and (Row.SourceKind = vskDerived);
    end;
  Assert.IsTrue(SawArea, 'The changed reader input is reported');
  Assert.IsTrue(SawDerived, 'The Derived value is recomputed from the re-run reader');

  Wear.Area := 4000;
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Items.RemoveValue(FNotebook.Manager.Find<TValue>(Cycles), Item, FNotebook.Principal.Id);
  finally
    Items.Free;
  end;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
  Assert.AreEqual(1, Integer(Length(Report.Rows)));
  Assert.IsTrue(Report.Rows[0].Flags = [vdfInputMissing], 'A deleted input is missing');
  Assert.IsFalse(Report.Rows[0].HasCurrentValue);
end;

procedure TDerivedValueTests.DriftReportsFormulaVersions;
var
  Item: TItem;
  Area, Force, Cycles: Integer;
  Derived: TValue;
  Wear: TWearRunner;
  Runner: IValueReaderRunner;
  Report: TValueDriftReport;
  Newer: TDerivedFormula;
begin
  Item := NewItem(FProjectId, 0, 'Wear test');
  Area := AddValue(Item, 'Wear area', AreaUnits, 0.004,
    TValueSourceInfo.Reader(1, 'synthetic.wear', '1', 'Wear Area', 'um2', 1e-6));
  Force := AddValue(Item, 'Normal force', 'N', 5,
    TValueSourceInfo.Reader(1, 'synthetic.wear', '1', 'Fn', 'N', 1));
  Cycles := AddValue(Item, 'Cycles', '', 1000,
    TValueSourceInfo.Reader(1, 'synthetic.wear', '1', 'Cycles', '', 1));
  Derived := Derive(Item, WEAR_RATE_FORMULA_ID, [Ref('area', Area),
    Ref('normal_force', Force), Ref('cycles', Cycles)]);
  Wear := TWearRunner.Create;
  Wear.Area := 4000;
  Wear.Force := 5;
  Wear.Cycles := 1000;
  Runner := Wear;

  Newer := WearRateFormula;
  Newer.Version := 2;
  Newer.Compute :=
    function(const Inputs: TArray<Double>): Double
    begin
      Result := Inputs[0] / (Inputs[1] * Inputs[2]);
    end;
  RegisterDerivedFormula(Newer);
  try
    Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
    Assert.AreEqual(1, Integer(Length(Report.Rows)));
    Assert.IsTrue(Report.Rows[0].Flags = [vdfFormulaVersionChanged],
      'A newer formula version is reported');
    Assert.AreEqual(4e-7, Report.Rows[0].CurrentValue, 1e-20,
      'The saved formula version is used');
    Assert.AreEqual(2, Report.Rows[0].CurrentFormulaVersion);
  finally
    UnregisterDerivedFormula(WEAR_RATE_FORMULA_ID, 2);
  end;

  Derived.FormulaVersion := 99;
  FNotebook.Manager.Flush;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], Runner);
  Assert.AreEqual(1, Integer(Length(Report.Rows)));
  Assert.IsTrue(Report.Rows[0].Flags = [vdfFormulaVersionMismatch],
    'An unavailable formula version is a version mismatch');
  Assert.IsFalse(Report.Rows[0].HasCurrentValue, 'The value is not recomputed');
  Assert.AreEqual(99, Report.Rows[0].StoredFormulaVersion);
  Assert.Contains(Report.Rows[0].Message, 'not recomputed');
end;

initialization
  TDUnitX.RegisterTestFixture(TDerivedValueTests);

end.
