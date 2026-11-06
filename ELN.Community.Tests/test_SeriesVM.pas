unit test_SeriesVM;

interface

uses
  System.SysUtils, DUnitX.TestFramework, unit_LocalNotebook, unit_ValueType,
  unit_SeriesTable, unit_SeriesModel, unit_SeriesVM;

type
  [TestFixture]
  TSeriesPlanInputTests = class
  private
    function German: TFormatSettings;
    function English: TFormatSettings;
  public
    [Test] procedure NumbersAcceptInvariantAndUserSeparator;
    [Test] procedure NumbersRefuseAmbiguousOrMalformedText;
    [Test] procedure LevelsSplitOnSemicolonsAndLineBreaks;
    [Test] procedure LevelsNameTheBadTokenAndTheRepeat;
    [Test] procedure QuantitiesConvertKnownUnitsToTheTypeUnit;
    [Test] procedure QuantitiesRefuseUnknownOrIncompatibleUnits;
    [Test] procedure LevelsConvertUnitsBeforeTheRepeatCheck;
    [Test] procedure OneFactorMakesOnePointPerLevel;
    [Test] procedure TwoFactorsMakeAGridWithFirstFactorSlowest;
    [Test] procedure ExistingPointsAreSkipped;
    [Test] procedure GridNeedsBothListsOrNeither;
    [Test] procedure PointTextAppendsUnits;
  end;

  [TestFixture]
  TSeriesVMTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FVM: TSeriesVM;
    FProjectId: Integer;
    FPower, FThickness, FArFlow, FPressure: TValueType;
    function NewType(const ASymbol, ATitle, AUnits: string): TValueType;
    function PlanWith(const AFactors: array of TValueType): TSeriesPlan;
    function RowOfSlot(ASlotId: Integer): Integer;
    function RowAtPower(ALevel: Double): Integer;
    function SlotAtPower(ALevel: Double): Integer;
    function PowerColumn: Integer;
    function MakeAt(ALevel: Double): Integer;
    procedure SetStoredValue(AItemId: Integer; AType: TValueType; AValue: Double);
    procedure ExpectSeriesError(const AProc: TProc);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ProgressTextShowsMeasuredOverPoints;
    [Test] procedure EmptyTextFollowsSeriesAndPoints;
    [Test] procedure NewSeriesBuildsSortedPlannedRowsFromLevels;
    [Test] procedure NewSeriesWithTwoFactorsMakesGrid;
    [Test] procedure NewSeriesRefusedCreatesNothing;
    [Test] procedure SavePlanRefusalKeepsTitlePurposeAndPoints;
    [Test] procedure SavePlanRenamesAndAddsLevelsAsAdded;
    [Test] procedure SavePlanGridSkipsExistingCombinations;
    [Test] procedure AddPointMarksTheRowAdded;
    [Test] procedure RowActionsFollowRowStateAndSeriesStatus;
    [Test] procedure PlannedValuesAreNotPlottedUntilConfirmed;
    [Test] procedure DeviationHintNamesThePlannedValue;
    [Test] procedure ConfirmPlannedRefusesSignedDeposition;
    [Test] procedure PlotUsesTheDataHitOfAMixedCell;
    [Test] procedure FailedRowsAreNotPlotted;
  end;

implementation

uses
  System.IOUtils, System.Generics.Collections,
  Aurelius.Types.Nullable,
  unit_Project, unit_ProjectModel, unit_Item, unit_ItemTypes, unit_Series,
  unit_SeriesColumn, unit_SeriesSlot, unit_SignatureModel,
  unit_SeriesPlanInput;

const
  Password = 'Synthetic-Series-VM-Only!';

function TSeriesPlanInputTests.German: TFormatSettings;
begin
  Result := TFormatSettings.Create('de-DE');
end;

function TSeriesPlanInputTests.English: TFormatSettings;
begin
  Result := TFormatSettings.Create('en-US');
end;

procedure TSeriesPlanInputTests.NumbersAcceptInvariantAndUserSeparator;
var
  V: Double;
begin
  Assert.IsTrue(TryParsePlanNumber('1,5', German, V));
  Assert.AreEqual(1.5, V, 1e-12);
  Assert.IsTrue(TryParsePlanNumber('1.5', German, V));
  Assert.AreEqual(1.5, V, 1e-12);
  Assert.IsTrue(TryParsePlanNumber(' -2.25 ', English, V));
  Assert.AreEqual(-2.25, V, 1e-12);
  Assert.IsTrue(TryParsePlanNumber('1,5e2', German, V));
  Assert.AreEqual(150.0, V, 1e-9);
  Assert.IsTrue(TryParsePlanNumber('1e3', English, V));
  Assert.AreEqual(1000.0, V, 1e-9);
end;

procedure TSeriesPlanInputTests.NumbersRefuseAmbiguousOrMalformedText;
var
  V: Double;
begin
  Assert.IsFalse(TryParsePlanNumber('1,5', English, V), 'comma is not the English separator');
  Assert.IsFalse(TryParsePlanNumber('1.234,5', German, V), 'two separators');
  Assert.IsFalse(TryParsePlanNumber('1 000', English, V), 'thousands space');
  Assert.IsFalse(TryParsePlanNumber('1.2.3', English, V));
  Assert.IsFalse(TryParsePlanNumber('', English, V));
  Assert.IsFalse(TryParsePlanNumber('  ', English, V));
  Assert.IsFalse(TryParsePlanNumber('abc', English, V));
  Assert.IsFalse(TryParsePlanNumber('1-2', English, V));
  Assert.IsFalse(TryParsePlanNumber('e5', English, V));
  Assert.IsFalse(TryParsePlanNumber('1e999', English, V), 'overflow');
  Assert.AreEqual(0.0, V, 0.0, 'a refused text leaves zero');
end;

procedure TSeriesPlanInputTests.LevelsSplitOnSemicolonsAndLineBreaks;
var
  L: TArray<Double>;
  E: string;
begin
  Assert.IsTrue(TryParseLevels('100; 200 ;300;', '', English, L, E));
  Assert.AreEqual<NativeInt>(3, Length(L));
  Assert.AreEqual(300.0, L[2], 0.0);
  Assert.IsTrue(TryParseLevels('1.5'#13#10'2.5', '', English, L, E));
  Assert.AreEqual<NativeInt>(2, Length(L));
  Assert.IsTrue(TryParseLevels('  ', '', English, L, E));
  Assert.AreEqual<NativeInt>(0, Length(L));
end;

procedure TSeriesPlanInputTests.LevelsNameTheBadTokenAndTheRepeat;
var
  L: TArray<Double>;
  E: string;
begin
  Assert.IsFalse(TryParseLevels('100; abc', '', English, L, E));
  Assert.AreEqual('"abc" is not a number.', E);
  Assert.AreEqual<NativeInt>(0, Length(L));
  Assert.IsFalse(TryParseLevels('100; 100.0', '', English, L, E));
  Assert.AreEqual('The level 100.0 is listed twice.', E);
end;

procedure TSeriesPlanInputTests.QuantitiesConvertKnownUnitsToTheTypeUnit;
var
  V: Double;
  E: string;
begin
  Assert.IsTrue(TryParsePlanQuantity('2 mTorr', 'Pa', False, English, V, E), E);
  Assert.AreEqual(0.266644736, V, 1e-9);
  Assert.IsTrue(TryParsePlanQuantity('2mTorr', 'Pa', False, English, V, E), E);
  Assert.AreEqual(0.266644736, V, 1e-9);
  Assert.IsTrue(TryParsePlanQuantity('1,5 kPa', 'Pa', False, German, V, E), E);
  Assert.AreEqual(1500.0, V, 1e-9);
  Assert.IsTrue(TryParsePlanQuantity('1e-3 Torr', 'mTorr', False, English, V, E), E);
  Assert.AreEqual(1.0, V, 1e-9);
  Assert.IsTrue(TryParsePlanQuantity('25 '#$00B0'C', 'K', False, English, V, E), E);
  Assert.AreEqual(298.15, V, 1e-9, 'a value converts with the offset');
  Assert.IsTrue(TryParsePlanQuantity('3 Pa', 'Pa', True, English, V, E), E);
  Assert.AreEqual(3.0, V, 0.0);
  Assert.IsTrue(TryParsePlanQuantity('0.5 mTorr', 'Pa', True, English, V, E), E);
  Assert.AreEqual(0.066661184, V, 1e-9, 'a tolerance converts by the factor');
  Assert.IsTrue(TryParsePlanQuantity(' 7 ', 'Pa', False, English, V, E), E);
  Assert.AreEqual(7.0, V, 0.0, 'a bare number is in the type unit');
end;

procedure TSeriesPlanInputTests.QuantitiesRefuseUnknownOrIncompatibleUnits;
var
  V: Double;
  E: string;
begin
  Assert.IsFalse(TryParsePlanQuantity('2 bogus', 'Pa', False, English, V, E));
  Assert.AreEqual('"bogus" is not a unit that the ELN knows.', E);
  Assert.IsFalse(TryParsePlanQuantity('5 W', 'Pa', False, English, V, E));
  Assert.AreEqual('A value in W cannot be converted to Pa.', E);
  Assert.IsFalse(TryParsePlanQuantity('2 Pa', '', False, English, V, E));
  Assert.AreEqual('This value type has no unit, so "Pa" cannot be used.', E);
  Assert.IsFalse(TryParsePlanQuantity('1 '#$00B0'C', 'K', True, English, V, E),
    'an offset unit is not a tolerance');
  Assert.IsFalse(TryParsePlanQuantity('mTorr', 'Pa', False, English, V, E));
  Assert.AreEqual('"mTorr" is not a number.', E);
  Assert.AreEqual(0.0, V, 0.0, 'a refused text leaves zero');
end;

procedure TSeriesPlanInputTests.LevelsConvertUnitsBeforeTheRepeatCheck;
var
  L: TArray<Double>;
  P: TArray<TSeriesPoint>;
  E: string;
begin
  Assert.IsTrue(TryParseLevels('100 mTorr; 0.2 Torr', 'mTorr', English, L, E), E);
  Assert.AreEqual(200.0, L[1], 1e-9);
  Assert.IsFalse(TryParseLevels('100 mTorr; 0.1 Torr', 'mTorr', English, L, E));
  Assert.AreEqual('The level 0.1 Torr is listed twice.', E);
  Assert.IsTrue(BuildPlanPoints('1 kW; 2 kW|10', ['W', 'sccm'], nil, English, P, E), E);
  Assert.AreEqual(2000.0, P[1][0], 1e-9);
end;

procedure TSeriesPlanInputTests.OneFactorMakesOnePointPerLevel;
var
  P: TArray<TSeriesPoint>;
  E: string;
begin
  Assert.IsTrue(BuildPlanPoints('300; 100', ['W'], nil, English, P, E));
  Assert.AreEqual<NativeInt>(2, Length(P));
  Assert.AreEqual(300.0, P[0][0], 0.0);
  Assert.AreEqual(100.0, P[1][0], 0.0);
  Assert.IsTrue(BuildPlanPoints('300; 100', [], nil, English, P, E));
  Assert.AreEqual<NativeInt>(0, Length(P), 'no factor, no points');
  Assert.IsFalse(BuildPlanPoints('1|2', ['W'], nil, English, P, E));
  Assert.AreEqual('Enter the levels of each factor.', E);
end;

procedure TSeriesPlanInputTests.TwoFactorsMakeAGridWithFirstFactorSlowest;
var
  P: TArray<TSeriesPoint>;
  E: string;
begin
  Assert.IsTrue(BuildPlanPoints('1; 2|10; 20', ['W', 'sccm'], nil, English, P, E));
  Assert.AreEqual<NativeInt>(4, Length(P));
  Assert.AreEqual(1.0, P[0][0], 0.0);
  Assert.AreEqual(10.0, P[0][1], 0.0);
  Assert.AreEqual(1.0, P[1][0], 0.0);
  Assert.AreEqual(20.0, P[1][1], 0.0);
  Assert.AreEqual(2.0, P[2][0], 0.0);
  Assert.AreEqual(20.0, P[3][1], 0.0);
end;

procedure TSeriesPlanInputTests.ExistingPointsAreSkipped;
var
  P: TArray<TSeriesPoint>;
  Known: TArray<TSeriesPoint>;
  E: string;
begin
  SetLength(Known, 1);
  Known[0] := [1.0, 10.0];
  Assert.IsTrue(BuildPlanPoints('1; 2|10; 20', ['W', 'sccm'], Known, English, P, E));
  Assert.AreEqual<NativeInt>(3, Length(P));
  Assert.AreEqual(1.0, P[0][0], 0.0);
  Assert.AreEqual(20.0, P[0][1], 0.0);
end;

procedure TSeriesPlanInputTests.GridNeedsBothListsOrNeither;
var
  P: TArray<TSeriesPoint>;
  E: string;
begin
  Assert.IsFalse(BuildPlanPoints('1; 2|', ['W', 'sccm'], nil, English, P, E));
  Assert.AreEqual('Enter levels for both factors, or leave both empty.', E);
  Assert.IsTrue(BuildPlanPoints('', ['W', 'sccm'], nil, English, P, E));
  Assert.AreEqual<NativeInt>(0, Length(P));
  Assert.IsTrue(BuildPlanPoints('|', ['W', 'sccm'], nil, English, P, E));
  Assert.AreEqual<NativeInt>(0, Length(P));
  Assert.AreEqual('1|2', JoinLevelLists(['1', '2']));
end;

procedure TSeriesPlanInputTests.PointTextAppendsUnits;
var
  Text: string;
begin
  Text := FormatPointText([200.0, 1.5], ['W', 'sccm']);
  Assert.AreEqual('200 W, 1' + FormatSettings.DecimalSeparator + '5 sccm', Text);
  Assert.AreEqual('200, 7', FormatPointText([200.0, 7.0], ['', '']));
  Assert.AreEqual('200 W', FormatPointText([200.0], ['W']));
end;

function TSeriesVMTests.NewType(const ASymbol, ATitle, AUnits: string): TValueType;
begin
  Result := TValueType.Create;
  Result.Symbol := ASymbol;
  Result.Title := ATitle;
  Result.Units := AUnits;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
end;

procedure TSeriesVMTests.Setup;
var
  Projects: TProjectsModel;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SeriesVM-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    FProjectId := Projects.AddProject('Series VM project', '', FNotebook.Principal).Id;
  finally
    Projects.Free;
  end;
  FPower := NewType('PW', 'Power', 'W');
  FThickness := NewType('TH', 'Thickness', 'nm');
  FArFlow := NewType('AF', 'Ar flow', 'sccm');
  FPressure := NewType('PR', 'Pressure', 'mTorr');
  FNotebook.Manager.Flush;
  FVM := TSeriesVM.Create(FNotebook.Manager, FNotebook.Principal, FNotebook.AccessPolicy);
  FVM.OpenProject(FProjectId, 0);
end;

procedure TSeriesVMTests.TearDown;
begin
  FreeAndNil(FVM);
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TSeriesVMTests.PlanWith(const AFactors: array of TValueType): TSeriesPlan;
var
  I: Integer;
begin
  Result := Default(TSeriesPlan);
  SetLength(Result.Factors, Length(AFactors));
  for I := 0 to High(AFactors) do
    Result.Factors[I].ValueTypeId := AFactors[I].Id;
  SetLength(Result.Fixed, 1);
  Result.Fixed[0].ValueTypeId := FArFlow.Id;
  Result.Fixed[0].Value := 20;
  Result.Fixed[0].Tol := 1;
  SetLength(Result.Responses, 1);
  Result.Responses[0].ValueTypeId := FThickness.Id;
end;

function TSeriesVMTests.RowOfSlot(ASlotId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FVM.Table.Rows) do
    if FVM.Table.Rows[I].SlotId = ASlotId then
      Exit(I);
  Result := -1;
  Assert.Fail('no row for slot');
end;

function TSeriesVMTests.SlotAtPower(ALevel: Double): Integer;
var
  S: TSeriesSlotInfo;
begin
  for S in FVM.Plan.Slots do
    if Abs(S.Levels[0] - ALevel) < 1e-9 then
      Exit(S.SlotId);
  Result := 0;
  Assert.Fail('no slot at ' + FloatToStr(ALevel));
end;

function TSeriesVMTests.RowAtPower(ALevel: Double): Integer;
begin
  Result := RowOfSlot(SlotAtPower(ALevel));
end;

function TSeriesVMTests.PowerColumn: Integer;
begin
  Result := FVM.Table.ColumnIndex(TRecType.EXP_CONDITION, FPower.Id, '');
  Assert.IsTrue(Result >= 0, 'power column');
end;

function TSeriesVMTests.MakeAt(ALevel: Double): Integer;
var
  Draft: TSeriesDepositionDraft;
begin
  Draft := Default(TSeriesDepositionDraft);
  Draft.Title := 'Ti ' + FloatToStr(ALevel);
  Result := FVM.MakeDeposition(SlotAtPower(ALevel), Draft);
end;

procedure TSeriesVMTests.SetStoredValue(AItemId: Integer; AType: TValueType;
  AValue: Double);
var
  Item: TItem;
  V: unit_Item.TValue;
begin
  Item := FNotebook.Manager.Find<TItem>(AItemId);
  for V in Item.Values do
    if V.ValueType.Id = AType.Id then
      V.Value := AValue;
  FNotebook.Manager.Flush;
end;

procedure TSeriesVMTests.ExpectSeriesError(const AProc: TProc);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    AProc();
  except
    on ESeriesError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'ESeriesError expected');
end;

procedure TSeriesVMTests.ProgressTextShowsMeasuredOverPoints;
var
  S: TSeriesSummary;
begin
  S := Default(TSeriesSummary);
  S.PointCount := 5;
  S.MeasuredCount := 2;
  Assert.AreEqual('2/5 measured', TSeriesVM.ProgressText(S));
  S.PointCount := 0;
  S.MeasuredCount := 0;
  Assert.AreEqual('0/0 measured', TSeriesVM.ProgressText(S));
end;

procedure TSeriesVMTests.EmptyTextFollowsSeriesAndPoints;
begin
  Assert.AreEqual('No series yet. Click New series... to make one.', FVM.EmptyText);
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '');
  Assert.AreEqual('This series has no points. Click Edit plan... to add factors and levels.',
    FVM.EmptyText);
  FVM.SavePlan('Ti rate', '', FVM.Plan.Plan, '100; 200');
  Assert.AreEqual('', FVM.EmptyText);
end;

procedure TSeriesVMTests.NewSeriesBuildsSortedPlannedRowsFromLevels;
var
  I: Integer;
begin
  FVM.NewSeries('Ti rate', 'Calibrate', PlanWith([FPower]), '300; 100; 200');
  Assert.AreEqual<NativeInt>(1, Length(FVM.Series));
  Assert.AreEqual(3, FVM.Series[0].PointCount);
  Assert.AreEqual<NativeInt>(3, Length(FVM.Table.Rows));
  Assert.AreEqual('100 W', FVM.PointText(0));
  Assert.AreEqual('200 W', FVM.PointText(1));
  Assert.AreEqual('300 W', FVM.PointText(2));
  for I := 0 to 2 do
    Assert.AreEqual('planned', TSeriesVM.StateText(FVM.Table.Rows[I].State));
end;

procedure TSeriesVMTests.NewSeriesWithTwoFactorsMakesGrid;
begin
  FVM.NewSeries('Grid', '', PlanWith([FPower, FPressure]), '100; 200|1; 2');
  Assert.AreEqual<NativeInt>(4, Length(FVM.Table.Rows));
  Assert.AreEqual('100 W, 1 mTorr', FVM.PointText(0));
  Assert.AreEqual('100 W, 2 mTorr', FVM.PointText(1));
  Assert.AreEqual('200 W, 2 mTorr', FVM.PointText(3));
end;

procedure TSeriesVMTests.NewSeriesRefusedCreatesNothing;
var
  Plan: TSeriesPlan;
begin
  ExpectSeriesError(
    procedure
    begin
      FVM.NewSeries('Bad levels', '', PlanWith([FPower]), '100; abc');
    end);
  Plan := PlanWith([FPower]);
  Plan.Factors[0].RangeMax := 150.0;
  ExpectSeriesError(
    procedure
    begin
      FVM.NewSeries('Out of range', '', Plan, '100; 200');
    end);
  FVM.Reload;
  Assert.AreEqual<NativeInt>(0, Length(FVM.Series));
end;

procedure TSeriesVMTests.SavePlanRefusalKeepsTitlePurposeAndPoints;
var
  Changed: TSeriesPlan;
begin
  FVM.NewSeries('Ti rate', 'Old purpose', PlanWith([FPower]), '100; 200');
  Changed := PlanWith([FPressure]);
  ExpectSeriesError(
    procedure
    begin
      FVM.SavePlan('New title', 'New purpose', Changed, '');
    end);
  FVM.Reload;
  Assert.AreEqual('Ti rate', FVM.Series[0].Title);
  Assert.AreEqual('Old purpose', FVM.Series[0].Purpose);
  Assert.AreEqual(FPower.Id, FVM.Plan.Plan.Factors[0].ValueTypeId);
  Assert.AreEqual<NativeInt>(2, Length(FVM.Plan.Slots));
end;

procedure TSeriesVMTests.SavePlanRenamesAndAddsLevelsAsAdded;
begin
  FVM.NewSeries('Ti rate', 'Old purpose', PlanWith([FPower]), '');
  FVM.SavePlan('Ti rate v2', 'New purpose', FVM.Plan.Plan, '100; 200');
  Assert.AreEqual('Ti rate v2', FVM.Series[0].Title);
  Assert.AreEqual('New purpose', FVM.Series[0].Purpose);
  Assert.AreEqual<NativeInt>(2, Length(FVM.Table.Rows));
  Assert.AreEqual('100 W (added)', FVM.PointText(0));
  Assert.AreEqual(Ord(ssoAdded), Ord(FVM.Table.Rows[1].Origin));
end;

procedure TSeriesVMTests.SavePlanGridSkipsExistingCombinations;
begin
  FVM.NewSeries('Grid', '', PlanWith([FPower, FPressure]), '100|1');
  Assert.AreEqual<NativeInt>(1, Length(FVM.Table.Rows));
  FVM.SavePlan('Grid', '', FVM.Plan.Plan, '100; 200|1; 2');
  Assert.AreEqual<NativeInt>(4, Length(FVM.Table.Rows));
end;

procedure TSeriesVMTests.AddPointMarksTheRowAdded;
var
  Levels: TSeriesPoint;
  Slot: Integer;
begin
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '100; 200; 300');
  SetLength(Levels, 1);
  Levels[0] := 250;
  Slot := FVM.AddPoint(Levels, 'Check the knee');
  Assert.AreEqual(SlotAtPower(250), Slot, 'AddPoint returns the new point, so the view can make its deposition');
  Assert.AreEqual<NativeInt>(4, Length(FVM.Table.Rows));
  Assert.AreEqual('250 W (added)', FVM.PointText(RowAtPower(250)));
  Assert.AreEqual('200 W', FVM.PointText(RowAtPower(200)));
end;

procedure TSeriesVMTests.RowActionsFollowRowStateAndSeriesStatus;
var
  Row, Item: Integer;
begin
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '100; 200; 300');
  Row := RowAtPower(200);
  Assert.IsTrue(FVM.RowActions(Row) = [raMake, raLink, raRemove], 'planned row');
  Item := MakeAt(200);
  Row := RowAtPower(200);
  Assert.IsTrue(FVM.RowActions(Row) = [raOpen, raUnlink, raFail, raConfirm],
    'deposited row with planned values');
  Assert.AreEqual(Item, FVM.Table.Rows[Row].ItemId);
  FVM.ConfirmPlanned(Item);
  Assert.IsTrue(FVM.RowActions(RowAtPower(200)) = [raOpen, raUnlink, raFail],
    'confirmed row');
  FVM.ChangeStatus(ssClosed);
  Assert.IsTrue(FVM.RowActions(RowAtPower(200)) = [raOpen], 'closed series, member');
  Assert.IsTrue(FVM.RowActions(RowAtPower(100)) = [], 'closed series, planned');
  Assert.IsTrue(FVM.RowActions(-1) = [], 'no row');
end;

procedure TSeriesVMTests.PlannedValuesAreNotPlottedUntilConfirmed;
var
  Item, Col, Row: Integer;
  V, Tol: Double;
begin
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '100; 200; 300');
  Item := MakeAt(200);
  Col := PowerColumn;
  Row := RowAtPower(200);
  Assert.AreEqual('deposited', TSeriesVM.StateText(FVM.Table.Rows[Row].State));
  Assert.IsFalse(FVM.PlotValue(Row, Col, V, Tol), 'planned hit is not plotted');
  Assert.IsFalse(FVM.PlotValue(RowAtPower(100), Col, V, Tol), 'planned row is not plotted');
  Assert.AreEqual(1, FVM.PointsWaiting([Col]));
  Assert.AreEqual(0, FVM.PointsWaiting([]));
  Assert.AreEqual(2, FVM.ConfirmPlanned(Item), 'power and the fixed Ar flow');
  Row := RowAtPower(200);
  Assert.IsTrue(FVM.PlotValue(Row, PowerColumn, V, Tol));
  Assert.AreEqual(200.0, V, 1e-9);
  Assert.AreEqual(0, FVM.PointsWaiting([PowerColumn]));
  Assert.IsFalse(FVM.PlotValue(RowAtPower(300), PowerColumn, V, Tol));
end;

procedure TSeriesVMTests.PlotUsesTheDataHitOfAMixedCell;
var
  Item, Row: Integer;
  V, Tol: Double;
  Manual: unit_Item.TValue;
begin
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '100; 200');
  Item := MakeAt(200);
  Manual := unit_Item.TValue.Create;
  Manual.Item := FNotebook.Manager.Find<TItem>(Item);
  Manual.ValueType := FPower;
  Manual.RecType := TRecType.EXP_CONDITION;
  Manual.Value := 205;
  Manual.Tol := 0.5;
  Manual.CreatedDate := Now;
  FNotebook.Manager.Save(Manual);
  FNotebook.Manager.Flush;
  FVM.Reload;
  Row := RowAtPower(200);
  Assert.AreEqual<NativeInt>(2, Length(FVM.Table.Rows[Row].Cells[PowerColumn].Hits),
    'one planned and one manual hit');
  Assert.IsTrue(FVM.PlotValue(Row, PowerColumn, V, Tol), 'the manual hit is plotted');
  Assert.AreEqual(205.0, V, 1e-9);
  Assert.AreEqual(0.5, Tol, 1e-9);
end;

procedure TSeriesVMTests.FailedRowsAreNotPlotted;
var
  Item, I, Failed, Row: Integer;
  V, Tol: Double;
begin
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '100; 200');
  Item := MakeAt(200);
  FVM.ConfirmPlanned(Item);
  Row := RowAtPower(200);
  Assert.IsTrue(FVM.PlotValue(Row, PowerColumn, V, Tol), 'confirmed value is plotted');
  FVM.ShowFailed := True;
  FVM.MarkFailed(Item, 'Target arced');
  Failed := -1;
  for I := 0 to High(FVM.Table.Rows) do
    if FVM.Table.Rows[I].State = srsFailed then
      Failed := I;
  Assert.IsTrue(Failed >= 0, 'the failed attempt is listed');
  Assert.IsFalse(FVM.PlotValue(Failed, PowerColumn, V, Tol), 'a failed attempt is not plotted');
end;

procedure TSeriesVMTests.DeviationHintNamesThePlannedValue;
var
  Item, Row: Integer;
  FlowCol: Integer;
begin
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '100; 200');
  Item := MakeAt(200);
  FVM.ConfirmPlanned(Item);
  Row := RowAtPower(200);
  Assert.AreEqual('', FVM.DeviationHint(Row, PowerColumn), 'no deviation yet');
  SetStoredValue(Item, FPower, 230);
  SetStoredValue(Item, FArFlow, 25);
  FVM.Reload;
  Row := RowAtPower(200);
  Assert.IsTrue(FVM.Table.Rows[Row].Cells[PowerColumn].Deviation);
  Assert.AreEqual('Differs from the plan (200 W)', FVM.DeviationHint(Row, PowerColumn));
  FlowCol := FVM.Table.ColumnIndex(TRecType.EXP_CONDITION, FArFlow.Id, '');
  Assert.AreEqual('Differs from the plan (20 sccm)', FVM.DeviationHint(Row, FlowCol));
  Assert.AreEqual('', FVM.DeviationHint(RowAtPower(100), PowerColumn));
end;

procedure TSeriesVMTests.ConfirmPlannedRefusesSignedDeposition;
var
  Item, Row: Integer;
  Signatures: TSignatureModel;
  Msg: string;
begin
  FVM.NewSeries('Ti rate', '', PlanWith([FPower]), '100; 200');
  Item := MakeAt(200);
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Signatures.SignItem(FNotebook.Manager.Find<TItem>(Item),
      FNotebook.Principal, Password, 'Synthetic signature', ''));
  finally
    Signatures.Free;
  end;
  Msg := '';
  try
    FVM.ConfirmPlanned(Item);
  except
    on E: ESeriesError do
      Msg := E.Message;
  end;
  Assert.AreEqual('This deposition is signed. Its planned values cannot be confirmed.', Msg);
  FVM.Reload;
  Row := RowAtPower(200);
  Assert.AreEqual(1, FVM.PointsWaiting([PowerColumn]));
  Assert.IsTrue(raConfirm in FVM.RowActions(Row));
end;

initialization
  TDUnitX.RegisterTestFixture(TSeriesPlanInputTests);
  TDUnitX.RegisterTestFixture(TSeriesVMTests);

end.
