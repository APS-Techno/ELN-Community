unit test_SeriesTable;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSeriesTableTests = class
  public
    [Test] procedure UnsplitWhenOneSourcePerColumn;
    [Test] procedure SplitsWhenSourcesDifferAcrossRows;
    [Test] procedure LargeTableBuildsCorrectly;
    [Test] procedure SplitsWhenTwoSourcesInAnyRow;
    [Test] procedure SameSourceTwoValuesIsAmbiguous;
    [Test] procedure ConditionAndResultOfSameTypeAreSeparate;
    [Test] procedure RootKeyCaptionIsDeposition;
    [Test] procedure FailedRowsExcludedUnlessRequested;
    [Test] procedure PrefsApplyRoleAndOrder;
    [Test] procedure UnknownValueTypeSkipped;
    [Test] procedure PlannedRowShowsLevels;
    [Test] procedure PlanColumnsExistWithoutHits;
    [Test] procedure StateDepositedVsMeasured;
    [Test] procedure NoResponsesMakesDepositionMeasured;
    [Test] procedure PlannedHitIsNotPresentForMeasured;
    [Test] procedure DeviationUsesValueTolerance;
    [Test] procedure FixedDeviationUsesPlanTolerance;
    [Test] procedure RowsSortByLevels;
    [Test] procedure FailedAttemptFollowsItsPoint;
  end;

implementation

uses
  System.SysUtils, unit_ItemTypes, unit_SeriesColumn, unit_SeriesTable;

function Row(AMember, AItem: Integer; AFailed: Boolean = False): TSeriesRowInput;
begin
  Result := Default(TSeriesRowInput);
  Result.MemberId := AMember;
  Result.ItemId := AItem;
  Result.SlotId := AMember;
  Result.HasMember := True;
  Result.Title := 'Item' + IntToStr(AItem);
  Result.Failed := AFailed;
end;

function Point(ASlot, AItem: Integer; const ALevels: array of Double;
  AFailed: Boolean = False): TSeriesRowInput;
var
  I: Integer;
begin
  Result := Row(ASlot, AItem, AFailed);
  Result.HasMember := AItem <> 0;
  SetLength(Result.Levels, Length(ALevels));
  for I := 0 to High(ALevels) do
  begin
    Result.Levels[I].ValueTypeId := I + 1;
    Result.Levels[I].Value := ALevels[I];
  end;
end;

function Hit(ARoot, AVt: Integer; ARec: TRecType; const ASrc: string;
  AValue: Double): TSeriesHit;
begin
  Result := Default(TSeriesHit);
  Result.RootItemId := ARoot;
  Result.ItemId := ARoot;
  Result.ValueTypeId := AVt;
  Result.RecType := ARec;
  Result.SourceKey := ASrc;
  Result.Value := AValue;
end;

function Planned(ARoot, AVt: Integer; ARec: TRecType; AValue: Double): TSeriesHit;
begin
  Result := Hit(ARoot, AVt, ARec, 'root', AValue);
  Result.Planned := True;
end;

function VT(AId: Integer; const ATitle: string): TSeriesValueTypeInfo;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Units := 'nm';
end;

function Src(const AKey, ACaption: string): TSeriesSourceInfo;
begin
  Result.Key := AKey;
  Result.Caption := ACaption;
end;

function Pref(ARec: TRecType; AVt: Integer; ARole: TSeriesColumnRole;
  AOrder: Integer): TSeriesColumnPref;
begin
  Result.RecType := ARec;
  Result.ValueTypeId := AVt;
  Result.SourceKey := '';
  Result.Role := ARole;
  Result.SortOrder := AOrder;
end;

procedure TSeriesTableTests.UnsplitWhenOneSourcePerColumn;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Row(1, 10), Row(2, 11)],
    [Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 50), Hit(11, 1, TRecType.TEST_RESULT, 'at:5', 60)],
    [VT(1, 'Thickness')], [], [], [], False);
  Assert.AreEqual(1, Integer(Length(T.Columns)));
  Assert.AreEqual('Thickness', T.Columns[0].Caption);
  Assert.AreEqual('', T.Columns[0].SourceKey);
  Assert.AreEqual(2, Integer(Length(T.Rows)));
end;

procedure TSeriesTableTests.SplitsWhenTwoSourcesInAnyRow;
var
  T: TSeriesTable;
  C: Integer;
begin
  T := BuildSeriesTable([Row(1, 10), Row(2, 11)],
    [Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 50), Hit(10, 1, TRecType.TEST_RESULT, 'at:7', 51),
     Hit(11, 1, TRecType.TEST_RESULT, 'at:5', 60)],
    [VT(1, 'Thickness')], [Src('at:5', 'XRR'), Src('at:7', 'Profilometry')], [], [], False);
  Assert.AreEqual(2, Integer(Length(T.Columns)));
  Assert.AreEqual('Thickness [Profilometry]', T.Columns[0].Caption);
  Assert.AreEqual('Thickness [XRR]', T.Columns[1].Caption);
  C := T.ColumnIndex(TRecType.TEST_RESULT, 1, 'at:7');
  Assert.AreEqual(0, C);
  Assert.IsTrue(T.Rows[1].Cells[C].IsMissing);
  Assert.IsFalse(T.Rows[0].Cells[C].IsMissing);
end;

procedure TSeriesTableTests.SplitsWhenSourcesDifferAcrossRows;
var
  T: TSeriesTable;
  CP, CX: Integer;
begin
  T := BuildSeriesTable([Row(1, 10), Row(2, 11), Row(3, 12), Row(4, 13)],
    [Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 50), Hit(11, 1, TRecType.TEST_RESULT, 'at:5', 51),
     Hit(12, 1, TRecType.TEST_RESULT, 'at:5', 52), Hit(13, 1, TRecType.TEST_RESULT, 'at:7', 60)],
    [VT(1, 'Thickness')], [Src('at:5', 'XRR'), Src('at:7', 'Profilometry')], [], [], False);
  Assert.AreEqual(2, Integer(Length(T.Columns)));
  Assert.AreEqual('Thickness [Profilometry]', T.Columns[0].Caption);
  Assert.AreEqual('Thickness [XRR]', T.Columns[1].Caption);
  CP := T.ColumnIndex(TRecType.TEST_RESULT, 1, 'at:7');
  CX := T.ColumnIndex(TRecType.TEST_RESULT, 1, 'at:5');
  Assert.IsTrue(T.Rows[3].Cells[CX].IsMissing);
  Assert.IsFalse(T.Rows[3].Cells[CP].IsMissing);
  Assert.IsTrue(T.Rows[0].Cells[CP].IsMissing);
  Assert.IsFalse(T.Rows[0].Cells[CX].IsMissing);
end;

procedure TSeriesTableTests.LargeTableBuildsCorrectly;
var
  Rows: TArray<TSeriesRowInput>;
  Hits: TArray<TSeriesHit>;
  Types: TArray<TSeriesValueTypeInfo>;
  T: TSeriesTable;
  R, V, S, C: Integer;
begin
  SetLength(Rows, 200);
  SetLength(Types, 20);
  for R := 0 to 199 do
    Rows[R] := Row(R + 1, 1000 + R);
  for V := 1 to 20 do
    Types[V - 1] := VT(V, 'Type' + Format('%.2d', [V]));
  for R := 0 to 199 do
    for V := 1 to 20 do
      for S := 0 to 1 do
      begin
        SetLength(Hits, Length(Hits) + 1);
        if V <= 10 then
          Hits[High(Hits)] := Hit(1000 + R, V, TRecType.TEST_RESULT, 'at:' + IntToStr(5 + S * 2), R * 1000 + V * 10 + S)
        else
          Hits[High(Hits)] := Hit(1000 + R, V, TRecType.TEST_RESULT, 'at:5', R * 1000 + V * 10 + S);
      end;
  T := BuildSeriesTable(Rows, Hits, Types, [], [], [], False);
  Assert.AreEqual(30, Integer(Length(T.Columns)));
  Assert.AreEqual(200, Integer(Length(T.Rows)));
  C := T.ColumnIndex(TRecType.TEST_RESULT, 3, 'at:7');
  Assert.AreEqual(1, Integer(Length(T.Rows[150].Cells[C].Hits)));
  Assert.AreEqual(150031.0, T.Rows[150].Cells[C].Hits[0].Value, 0.0001);
  C := T.ColumnIndex(TRecType.TEST_RESULT, 15, '');
  Assert.IsTrue(T.Rows[199].Cells[C].IsAmbiguous);
  Assert.AreEqual(199150.0, T.Rows[199].Cells[C].Hits[0].Value, 0.0001);
  Assert.AreEqual(199151.0, T.Rows[199].Cells[C].Hits[1].Value, 0.0001);
end;

procedure TSeriesTableTests.SameSourceTwoValuesIsAmbiguous;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Row(1, 10)],
    [Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 50), Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 52)],
    [VT(1, 'Thickness')], [], [], [], False);
  Assert.AreEqual(1, Integer(Length(T.Columns)));
  Assert.AreEqual(2, Integer(Length(T.Rows[0].Cells[0].Hits)));
  Assert.IsTrue(T.Rows[0].Cells[0].IsAmbiguous);
end;

procedure TSeriesTableTests.ConditionAndResultOfSameTypeAreSeparate;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Row(1, 10)],
    [Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 50), Hit(10, 1, TRecType.EXP_CONDITION, 'root', 40)],
    [VT(1, 'Thickness')], [], [], [], False);
  Assert.AreEqual(2, Integer(Length(T.Columns)));
  Assert.IsTrue(T.Columns[0].RecType = TRecType.EXP_CONDITION);
  Assert.IsTrue(T.Columns[1].RecType = TRecType.TEST_RESULT);
end;

procedure TSeriesTableTests.RootKeyCaptionIsDeposition;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Row(1, 10)],
    [Hit(10, 1, TRecType.TEST_RESULT, 'root', 40), Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 41)],
    [VT(1, 'Thickness')], [Src('at:5', 'XRR')], [], [], False);
  Assert.AreEqual('Thickness [deposition]', T.Columns[1].Caption);
  Assert.AreEqual('Thickness [XRR]', T.Columns[0].Caption);
end;

procedure TSeriesTableTests.FailedRowsExcludedUnlessRequested;
var
  Rows: TArray<TSeriesRowInput>;
  Hits: TArray<TSeriesHit>;
begin
  Rows := [Row(1, 10), Row(2, 11, True)];
  Hits := [Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 50), Hit(11, 1, TRecType.TEST_RESULT, 'at:7', 60),
    Hit(11, 1, TRecType.TEST_RESULT, 'at:5', 61)];
  Assert.AreEqual(1, Integer(Length(BuildSeriesTable(Rows, Hits, [VT(1, 'T')], [], [], [], False).Rows)));
  Assert.AreEqual(1, Integer(Length(BuildSeriesTable(Rows, Hits, [VT(1, 'T')], [], [], [], False).Columns)));
  Assert.AreEqual(2, Integer(Length(BuildSeriesTable(Rows, Hits, [VT(1, 'T')], [], [], [], True).Rows)));
  Assert.AreEqual(2, Integer(Length(BuildSeriesTable(Rows, Hits, [VT(1, 'T')], [], [], [], True).Columns)));
end;

procedure TSeriesTableTests.PrefsApplyRoleAndOrder;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Row(1, 10)],
    [Hit(10, 1, TRecType.TEST_RESULT, 'at:5', 1), Hit(10, 2, TRecType.TEST_RESULT, 'at:5', 2),
     Hit(10, 3, TRecType.TEST_RESULT, 'at:5', 3)],
    [VT(1, 'Alpha'), VT(2, 'Beta'), VT(3, 'Gamma')], [],
    [Pref(TRecType.TEST_RESULT, 3, scrShown, 0), Pref(TRecType.TEST_RESULT, 1, scrHidden, 1)],
    [], False);
  Assert.AreEqual(3, Integer(Length(T.Columns)));
  Assert.AreEqual('Gamma', T.Columns[0].Caption);
  Assert.AreEqual('Alpha', T.Columns[1].Caption);
  Assert.IsTrue(T.Columns[1].Role = scrHidden);
  Assert.AreEqual('Beta', T.Columns[2].Caption);
  Assert.IsTrue(T.Columns[2].Role = scrShown);
end;

procedure TSeriesTableTests.UnknownValueTypeSkipped;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Row(1, 10)],
    [Hit(10, 99, TRecType.TEST_RESULT, 'at:5', 1)], [VT(1, 'Alpha')], [], [], [], False);
  Assert.AreEqual(0, Integer(Length(T.Columns)));
  Assert.AreEqual(1, Integer(Length(T.Rows)));
end;

function MeasuredHit(ARoot, AVt: Integer; AValue: Double): TSeriesHit;
begin
  Result := Hit(ARoot, AVt, TRecType.TEST_RESULT, 'at:5', AValue);
end;

function CondHit(ARoot, AVt: Integer; AValue, ATol: Double): TSeriesHit;
begin
  Result := Hit(ARoot, AVt, TRecType.EXP_CONDITION, 'root', AValue);
  Result.Tol := ATol;
end;

procedure TSeriesTableTests.PlannedRowShowsLevels;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Point(1, 0, [100])], [], [VT(1, 'Temp')], [],
    [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0)], [], False);
  Assert.AreEqual(1, Integer(Length(T.Rows)));
  Assert.IsTrue(T.Rows[0].State = srsPlanned);
  Assert.AreEqual(0, T.Rows[0].ItemId);
  Assert.IsTrue(T.Rows[0].Cells[0].IsMissing);
  Assert.IsTrue(T.Rows[0].Cells[0].HasPlanned);
  Assert.AreEqual(100.0, T.Rows[0].Cells[0].PlannedValue, 0.0001);
end;

procedure TSeriesTableTests.PlanColumnsExistWithoutHits;
var
  T: TSeriesTable;
  C: Integer;
begin
  T := BuildSeriesTable([Point(1, 0, [100])], [],
    [VT(1, 'Temp'), VT(2, 'Pressure'), VT(3, 'Thickness')], [],
    [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0), Pref(TRecType.EXP_CONDITION, 2, scrFixed, 1),
     Pref(TRecType.TEST_RESULT, 3, scrResponse, 0)], [], False);
  Assert.AreEqual(3, Integer(Length(T.Columns)));
  C := T.ColumnIndex(TRecType.EXP_CONDITION, 1, '');
  Assert.IsTrue(T.Columns[C].Role = scrVaried);
  C := T.ColumnIndex(TRecType.EXP_CONDITION, 2, '');
  Assert.IsTrue(T.Columns[C].Role = scrFixed);
  C := T.ColumnIndex(TRecType.TEST_RESULT, 3, '');
  Assert.IsTrue(T.Columns[C].Role = scrResponse);
  Assert.AreEqual(3, Integer(Length(T.Rows[0].Cells)));
end;

procedure TSeriesTableTests.StateDepositedVsMeasured;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Point(1, 10, [100]), Point(2, 11, [200]), Point(3, 0, [300])],
    [MeasuredHit(10, 3, 50)], [VT(1, 'Temp'), VT(3, 'Thickness')], [],
    [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0), Pref(TRecType.TEST_RESULT, 3, scrResponse, 0)],
    [], False);
  Assert.IsTrue(T.Rows[0].State = srsMeasured);
  Assert.IsTrue(T.Rows[1].State = srsDeposited);
  Assert.IsTrue(T.Rows[2].State = srsPlanned);
end;

procedure TSeriesTableTests.NoResponsesMakesDepositionMeasured;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Point(1, 10, [100]), Point(2, 0, [200])], [],
    [VT(1, 'Temp')], [], [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0)], [], False);
  Assert.IsTrue(T.Rows[0].State = srsMeasured);
  Assert.IsTrue(T.Rows[1].State = srsPlanned);
end;

procedure TSeriesTableTests.PlannedHitIsNotPresentForMeasured;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Point(1, 10, [100])],
    [Planned(10, 3, TRecType.TEST_RESULT, 50)], [VT(3, 'Thickness')], [],
    [Pref(TRecType.TEST_RESULT, 3, scrResponse, 0)], [], False);
  Assert.IsTrue(T.Rows[0].State = srsDeposited);
  T := BuildSeriesTable([Point(1, 10, [100])],
    [Planned(10, 3, TRecType.TEST_RESULT, 50), MeasuredHit(10, 3, 51)],
    [VT(3, 'Thickness')], [], [Pref(TRecType.TEST_RESULT, 3, scrResponse, 0)], [], False);
  Assert.IsTrue(T.Rows[0].State = srsMeasured);
end;

procedure TSeriesTableTests.DeviationUsesValueTolerance;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Point(1, 10, [200]), Point(2, 11, [200]), Point(3, 12, [200])],
    [CondHit(10, 1, 195, 0.1), CondHit(11, 1, 199.97, 0.1),
     Planned(12, 1, TRecType.EXP_CONDITION, 150)],
    [VT(1, 'Temp')], [], [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0)], [], False);
  Assert.IsTrue(T.Rows[0].Cells[0].Deviation);
  Assert.IsFalse(T.Rows[1].Cells[0].Deviation);
  Assert.IsFalse(T.Rows[2].Cells[0].Deviation);
  Assert.IsFalse(T.Rows[0].Cells[0].HasPlanned);
end;

procedure TSeriesTableTests.FixedDeviationUsesPlanTolerance;
var
  T: TSeriesTable;
  X, Y: TSeriesFixedSpec;
begin
  X.ValueTypeId := 2;
  X.Value := 5;
  X.Tol := 0.5;
  T := BuildSeriesTable([Point(1, 10, [100]), Point(2, 11, [200])],
    [CondHit(10, 2, 5.4, 0.01), CondHit(11, 2, 5.6, 5)],
    [VT(1, 'Temp'), VT(2, 'Pressure')], [],
    [Pref(TRecType.EXP_CONDITION, 2, scrFixed, 0)], [X], False);
  Assert.IsFalse(T.Rows[0].Cells[0].Deviation);
  Assert.IsTrue(T.Rows[1].Cells[0].Deviation);
  Y := X;
  Y.Tol := 0;
  T := BuildSeriesTable([Point(1, 10, [100]), Point(2, 11, [200]), Point(3, 12, [300])],
    [CondHit(10, 2, 5.05, 0.1), CondHit(11, 2, 5.7, 0.1), CondHit(12, 2, 5.01, 0)],
    [VT(1, 'Temp'), VT(2, 'Pressure')], [],
    [Pref(TRecType.EXP_CONDITION, 2, scrFixed, 0)], [Y], False);
  Assert.IsFalse(T.Rows[0].Cells[0].Deviation);
  Assert.IsTrue(T.Rows[1].Cells[0].Deviation);
  Assert.IsTrue(T.Rows[2].Cells[0].Deviation);
end;

procedure TSeriesTableTests.RowsSortByLevels;
var
  T: TSeriesTable;
begin
  T := BuildSeriesTable([Point(1, 0, [300]), Point(2, 0, [100]), Point(3, 0, [200])],
    [], [VT(1, 'Temp')], [], [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0)], [], False);
  Assert.AreEqual(100.0, T.Rows[0].Cells[0].PlannedValue, 0.0001);
  Assert.AreEqual(200.0, T.Rows[1].Cells[0].PlannedValue, 0.0001);
  Assert.AreEqual(300.0, T.Rows[2].Cells[0].PlannedValue, 0.0001);
  Assert.AreEqual(2, T.Rows[0].SlotId);
end;

procedure TSeriesTableTests.FailedAttemptFollowsItsPoint;
var
  Rows: TArray<TSeriesRowInput>;
  T: TSeriesTable;
begin
  Rows := [Point(2, 11, [200]), Point(1, 0, [100]), Point(1, 10, [100], True)];
  Rows[2].MemberId := 7;
  T := BuildSeriesTable(Rows, [], [VT(1, 'Temp')], [],
    [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0)], [], True);
  Assert.AreEqual(3, Integer(Length(T.Rows)));
  Assert.AreEqual(1, T.Rows[0].SlotId);
  Assert.IsTrue(T.Rows[0].State = srsPlanned);
  Assert.AreEqual(1, T.Rows[1].SlotId);
  Assert.IsTrue(T.Rows[1].State = srsFailed);
  Assert.AreEqual(2, T.Rows[2].SlotId);
  T := BuildSeriesTable(Rows, [], [VT(1, 'Temp')], [],
    [Pref(TRecType.EXP_CONDITION, 1, scrVaried, 0)], [], False);
  Assert.AreEqual(2, Integer(Length(T.Rows)));
end;

initialization
  TDUnitX.RegisterTestFixture(TSeriesTableTests);

end.
