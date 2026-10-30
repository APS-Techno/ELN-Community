unit test_ZRWPlateau;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Math, System.JSON, unit_ZRWData,
  unit_ZRWPlateau;

type
  [TestFixture]
  TZRWPlateauTests = class
  public
    [Test] procedure ShortRunningInIsExcluded;
    [Test] procedure FinalRiseEndsPlateau;
    [Test] procedure LongerLaterPlateauIsNotChosen;
    [Test] procedure TrimmedPlateauShorterThanMinimumIsNoPlateau;
    [Test] procedure OutliersAreKept;
    [Test] procedure ShortSpikesDoNotEndPlateau;
    [Test] procedure GradualRunningInIsExcluded;
    [Test] procedure RisingRunningInIsExcluded;
    [Test] procedure OscillatingRunningInBeforeDriftIsExcluded;
    [Test] procedure DriftDoesNotDelayStart;
    [Test] procedure WavyPlateauKeepsItsFirstHalf;
    [Test] procedure RepeatedCoordinatesDoubleCount;
    [Test] procedure SparseCurveIsNoPlateau;
    [Test] procedure AllZerosNoPlateauAndManualWarns;
    [Test] procedure ManualIntervalCounts;
    [Test] procedure ManualShortIntervalWarns;
    [Test] procedure ManualUnstableIntervalWarns;
    [Test] procedure ManualStableIntervalHasNoWarnings;
    [Test] procedure DegenerateIntervalsRaise;
    [Test] procedure JsonRoundTrips;
    [Test] procedure JsonNumbersAreInvariant;
    [Test] procedure JsonIsShort;
    [Test] procedure JsonRejectsMalformed;
    [Test] procedure JsonCarriesSchemaAndDetectorParameters;
    [Test] procedure JsonRejectsUnknownSchemaOrReader;
    [Test] procedure LargeBurstCurveIntegerCoordinates;
    [Test] procedure LargeBurstCurveNonIntegerRepeatedCoordinates;
  end;

implementation

type
  TCofFunc = reference to function(Cycle: Integer): Double;

function MakeCurve(const Cof: TCofFunc; Repeats: Integer = 1): TZRWCurve;
var
  C, R, N: Integer;
begin
  SetLength(Result.Samples, 1001 * Repeats);
  N := 0;
  for C := 0 to 1000 do
    for R := 1 to Repeats do
    begin
      Result.Samples[N].Cycle := C;
      Result.Samples[N].COF := Cof(C);
      Inc(N);
    end;
end;

function RunningIn(Cycle: Integer): Double;
begin
  if Cycle <= 9 then
    Result := 0.40
  else
    Result := 0.10;
end;

function Noise(Cycle: Integer): Double;
begin
  Result := (((Cycle * 7919) mod 11) - 5) * 0.0004;
end;

function Iv(Start, Finish: Double; ThroughEnd: Boolean = False): TZRWInterval;
begin
  Result.StartCycle := Start;
  Result.EndCycle := Finish;
  Result.ThroughEnd := ThroughEnd;
end;

procedure ExpectFound(const Curve: TZRWCurve; Start, Finish: Double;
  ThroughEnd: Boolean);
var
  I: TZRWInterval;
begin
  Assert.AreEqual(Ord(zdrFound), Ord(DetectPlateau(Curve, I)));
  Assert.AreEqual(Start, I.StartCycle, 0.0);
  Assert.AreEqual(Finish, I.EndCycle, 0.0);
  Assert.AreEqual(ThroughEnd, I.ThroughEnd);
end;

procedure ExpectStartWithin(const Curve: TZRWCurve; Earliest, Latest: Double);
var
  I: TZRWInterval;
begin
  Assert.AreEqual(Ord(zdrFound), Ord(DetectPlateau(Curve, I)));
  Assert.IsTrue((I.StartCycle >= Earliest) and (I.StartCycle <= Latest),
    Format('Start %g is outside %g..%g', [I.StartCycle, Earliest, Latest]));
  Assert.AreEqual(1000.0, I.EndCycle, 0.0);
  Assert.IsTrue(I.ThroughEnd);
end;

procedure TZRWPlateauTests.ShortRunningInIsExcluded;
var
  Curve: TZRWCurve;
  I: TZRWInterval;
  St: TZRWStats;
begin
  Curve := MakeCurve(RunningIn);
  ExpectFound(Curve, 10, 1000, True);
  DetectPlateau(Curve, I);
  St := IntervalStats(Curve, I);
  Assert.AreEqual<NativeInt>(991, St.Count);
  Assert.AreEqual(0.1, St.Mean, 1e-12);
  Assert.AreEqual(0.0, St.PopulationStd, 1e-12);
end;

procedure TZRWPlateauTests.FinalRiseEndsPlateau;
begin
  ExpectFound(MakeCurve(
    function(C: Integer): Double
    begin
      if C >= 700 then Result := 0.50 else if C <= 9 then Result := 0.40 else Result := 0.10;
    end), 10, 700, False);
end;

procedure TZRWPlateauTests.LongerLaterPlateauIsNotChosen;
begin
  ExpectFound(MakeCurve(
    function(C: Integer): Double
    begin
      if C <= 249 then Result := 0.10 else if C <= 299 then Result := 0.60 else Result := 0.20;
    end), 0, 250, False);
end;

procedure TZRWPlateauTests.TrimmedPlateauShorterThanMinimumIsNoPlateau;
var
  I: TZRWInterval;
begin
  Assert.AreEqual(Ord(zdrNoPlateau), Ord(DetectPlateau(MakeCurve(
    function(C: Integer): Double
    begin
      if C >= 220 then Result := 0.50
      else if C < 150 then Result := 0.13 - 0.03 * C / 150
      else Result := 0.10;
    end), I)));
end;

procedure TZRWPlateauTests.OutliersAreKept;
var
  Curve: TZRWCurve;
  I: TZRWInterval;
  St: TZRWStats;
  P: Double;
begin
  Curve := MakeCurve(
    function(C: Integer): Double
    begin
      if C mod 25 = 12 then Result := 0.20 else Result := 0.10;
    end);
  ExpectFound(Curve, 0, 1000, True);
  DetectPlateau(Curve, I);
  St := IntervalStats(Curve, I);
  P := 40 / 1001;
  Assert.AreEqual<NativeInt>(1001, St.Count);
  Assert.AreEqual(104.1 / 1001, St.Mean, 1e-12);
  Assert.AreEqual(0.1 * Sqrt(P * (1 - P)), St.PopulationStd, 1e-12);
end;

procedure TZRWPlateauTests.ShortSpikesDoNotEndPlateau;
begin
  ExpectFound(MakeCurve(
    function(C: Integer): Double
    begin
      if ((C >= 500) and (C <= 502)) or (C >= 998) then Result := 0.50 else Result := 0.10;
    end), 0, 1000, True);
end;

procedure TZRWPlateauTests.GradualRunningInIsExcluded;
begin
  ExpectStartWithin(MakeCurve(
    function(C: Integer): Double
    begin
      Result := 0.10 + 0.05 * Exp(-C / 100) + Noise(C) / 2;
    end), 300, 450);
end;

procedure TZRWPlateauTests.RisingRunningInIsExcluded;
begin
  ExpectStartWithin(MakeCurve(
    function(C: Integer): Double
    begin
      Result := 0.10 - 0.02 * Exp(-C / 100) + Noise(C) / 2;
    end), 220, 350);
end;

procedure TZRWPlateauTests.OscillatingRunningInBeforeDriftIsExcluded;
begin
  ExpectStartWithin(MakeCurve(
    function(C: Integer): Double
    begin
      if C < 60 then
        Result := 0.30 + 0.1 * ((C * 37) mod 9)
      else if C < 120 then
        Result := 0.75
      else
        Result := 0.66 + 0.00015 * (C - 120);
      Result := Result + 5 * Noise(C);
    end), 120, 160);
end;

procedure TZRWPlateauTests.DriftDoesNotDelayStart;
begin
  ExpectStartWithin(MakeCurve(
    function(C: Integer): Double
    begin
      if C < 60 then
        Result := 0.30 + 0.006 * C
      else if C < 150 then
        Result := 0.66
      else
        Result := 0.66 + 0.0002 * (C - 150);
      Result := Result + 5 * Noise(C);
    end), 60, 160);
end;

procedure TZRWPlateauTests.WavyPlateauKeepsItsFirstHalf;
begin
  ExpectStartWithin(MakeCurve(
    function(C: Integer): Double
    begin
      if C < 100 then
        Result := 0.60
      else
        Result := 0.50 + 0.01 * (Abs((C mod 300) - 150) / 150 * 2 - 1);
      Result := Result + 5 * Noise(C);
    end), 100, 150);
end;

procedure TZRWPlateauTests.RepeatedCoordinatesDoubleCount;
var
  Curve: TZRWCurve;
  I: TZRWInterval;
begin
  Curve := MakeCurve(RunningIn, 2);
  ExpectFound(Curve, 10, 1000, True);
  DetectPlateau(Curve, I);
  Assert.AreEqual(1982, IntervalStats(Curve, I).Count);
end;

procedure TZRWPlateauTests.SparseCurveIsNoPlateau;
var
  Curve: TZRWCurve;
  I: TZRWInterval;
begin
  SetLength(Curve.Samples, 3);
  Curve.Samples[0].Cycle := 0;
  Curve.Samples[1].Cycle := 500;
  Curve.Samples[2].Cycle := 1000;
  Curve.Samples[0].COF := 0.1;
  Curve.Samples[1].COF := 0.1;
  Curve.Samples[2].COF := 0.1;
  Assert.AreEqual(Ord(zdrNoPlateau), Ord(DetectPlateau(Curve, I)));
end;

procedure TZRWPlateauTests.AllZerosNoPlateauAndManualWarns;
var
  Curve: TZRWCurve;
  I: TZRWInterval;
begin
  Curve := MakeCurve(
    function(C: Integer): Double
    begin
      Result := 0;
    end);
  Assert.AreEqual(Ord(zdrNoPlateau), Ord(DetectPlateau(Curve, I)));
  Assert.AreEqual(100, IntervalStats(Curve, Iv(0, 100)).Count);
  Assert.IsTrue(zwNonPositiveValues in ManualWarnings(Curve, Iv(0, 100)));
end;

procedure TZRWPlateauTests.ManualIntervalCounts;
var
  Curve: TZRWCurve;
begin
  Curve := MakeCurve(RunningIn);
  Assert.AreEqual(10, IntervalStats(Curve, Iv(10, 20)).Count);
  Assert.AreEqual(11, IntervalStats(Curve, Iv(990, 1000, True)).Count);
  Assert.AreEqual(10, IntervalStats(Curve, Iv(990, 1000)).Count);
end;

procedure TZRWPlateauTests.ManualShortIntervalWarns;
var
  Curve: TZRWCurve;
begin
  Curve := MakeCurve(RunningIn);
  Assert.IsTrue(zwBelowMinimumDuration in ManualWarnings(Curve, Iv(0, 100)));
  Assert.IsFalse(zwBelowMinimumDuration in ManualWarnings(Curve, Iv(100, 300)));
end;

procedure TZRWPlateauTests.ManualUnstableIntervalWarns;
var
  Curve: TZRWCurve;
begin
  Curve := MakeCurve(RunningIn);
  Assert.IsTrue(zwUnstable in ManualWarnings(Curve, Iv(0, 400)));
  Curve := MakeCurve(
    function(C: Integer): Double
    begin
      if C < 500 then Result := 0.10 else Result := 0.30;
    end);
  Assert.IsTrue(zwUnstable in ManualWarnings(Curve, Iv(0, 1000, True)));
end;

procedure TZRWPlateauTests.ManualStableIntervalHasNoWarnings;
begin
  Assert.IsTrue(ManualWarnings(MakeCurve(RunningIn), Iv(100, 900)) = []);
end;

procedure TZRWPlateauTests.DegenerateIntervalsRaise;
var
  Curve: TZRWCurve;
begin
  Curve := MakeCurve(RunningIn);
  Assert.WillRaise(procedure begin IntervalStats(Curve, Iv(5, 5)); end, EZRWFormatError);
  Assert.WillRaise(procedure begin IntervalStats(Curve, Iv(5, 5.5)); end, EZRWFormatError);
  Assert.WillRaise(procedure begin IntervalStats(Curve, Iv(6, 5)); end, EZRWFormatError);
  Assert.WillRaise(procedure begin ManualWarnings(Curve, Iv(5, 5)); end, EZRWFormatError);
end;

function SampleSelection: TZRWSelection;
begin
  Result.Mode := zsmManual;
  Result.Interval := Iv(0.3, 1 / 3, True);
  Result.ReaderVersion := '2';
  Result.AlgorithmVersion := '1';
  Result.FileHash := 'ABCDEF0123456789ABCDEF0123456789';
  Result.ApplyId := '{5E1B9C34-0B6E-4F43-9C0A-3C3E9D0E5A11}';
  Result.AppliedAt := '2026-10-14T08:30:00Z';
  Result.Revision := 3;
  Result.AppliedBy := 42;
end;

procedure TZRWPlateauTests.JsonRoundTrips;
var
  A, B: TZRWSelection;
begin
  A := SampleSelection;
  Assert.IsTrue(TryParseSelection(SelectionToJson(A), B));
  Assert.AreEqual(Ord(A.Mode), Ord(B.Mode));
  Assert.AreEqual(A.Interval.StartCycle, B.Interval.StartCycle, 0.0);
  Assert.AreEqual(A.Interval.EndCycle, B.Interval.EndCycle, 0.0);
  Assert.AreEqual(A.Interval.ThroughEnd, B.Interval.ThroughEnd);
  Assert.AreEqual(A.ReaderVersion, B.ReaderVersion);
  Assert.AreEqual(A.AlgorithmVersion, B.AlgorithmVersion);
  Assert.AreEqual(A.FileHash, B.FileHash);
  Assert.AreEqual(A.ApplyId, B.ApplyId);
  Assert.AreEqual(A.AppliedAt, B.AppliedAt);
  Assert.AreEqual(A.Revision, B.Revision);
  Assert.AreEqual(A.AppliedBy, B.AppliedBy);
  A.Mode := zsmAutomatic;
  A.Interval.ThroughEnd := False;
  Assert.IsTrue(TryParseSelection(SelectionToJson(A), B));
  Assert.AreEqual(Ord(zsmAutomatic), Ord(B.Mode));
  Assert.IsFalse(B.Interval.ThroughEnd);
end;

procedure TZRWPlateauTests.JsonNumbersAreInvariant;
var
  Saved: Char;
  Json: string;
  B: TZRWSelection;
begin
  Saved := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := ',';
  try
    Json := SelectionToJson(SampleSelection);
    Assert.IsTrue(TryParseSelection(Json, B));
    Assert.AreEqual(SampleSelection.Interval.StartCycle, B.Interval.StartCycle, 0.0);
  finally
    FormatSettings.DecimalSeparator := Saved;
  end;
  Assert.IsTrue(Json.Contains('"start":0.3,'), Json);
  Assert.IsFalse(Json.Contains('0,3'), Json);
end;

procedure TZRWPlateauTests.JsonIsShort;
begin
  Assert.IsTrue(Length(SelectionToJson(SampleSelection)) < 2000);
end;

function BurstCurve(Offset: Integer; Origin, Step: Double): TZRWCurve;
var
  K, R, N: Integer;
begin
  SetLength(Result.Samples, 13000);
  N := 0;
  for K := 0 to 6499 do
    for R := 1 to 2 do
    begin
      Result.Samples[N].Cycle := Origin + K * Step;
      if (K mod 1950 >= Offset) and (K mod 1950 < Offset + 200) then
        Result.Samples[N].COF := 0.50
      else
        Result.Samples[N].COF := 0.10;
      Inc(N);
    end;
end;

procedure TZRWPlateauTests.LargeBurstCurveIntegerCoordinates;
begin
  ExpectFound(BurstCurve(1000, 0, 1), 1200, 2950, False);
end;

procedure TZRWPlateauTests.LargeBurstCurveNonIntegerRepeatedCoordinates;
begin
  ExpectFound(BurstCurve(700, 0.89, 0.38), 0.89 + 900 * 0.38, 0.89 + 2650 * 0.38, False);
end;

procedure TZRWPlateauTests.JsonRejectsMalformed;
var
  S: TZRWSelection;
begin
  Assert.IsFalse(TryParseSelection('', S));
  Assert.IsFalse(TryParseSelection('not json', S));
  Assert.IsFalse(TryParseSelection('[]', S));
  Assert.IsFalse(TryParseSelection('{"mode":"manual"}', S));
  Assert.IsFalse(TryParseSelection(
    StringReplace(SelectionToJson(SampleSelection), '"manual"', '"other"', []), S));
end;

procedure TZRWPlateauTests.JsonCarriesSchemaAndDetectorParameters;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.ParseJSONValue(SelectionToJson(SampleSelection)) as TJSONObject;
  try
    Assert.AreEqual(1, Obj.GetValue<Integer>('schema_version'));
    Assert.AreEqual('aps.zrw', Obj.GetValue<string>('reader_id'));
    Assert.AreEqual<Double>(0.2, Obj.GetValue<Double>('min_duration'));
    Assert.AreEqual<Double>(0.3, Obj.GetValue<Double>('band'));
    Assert.AreEqual<Double>(0.95, Obj.GetValue<Double>('coverage'));
    Assert.AreEqual<Double>(0.05, Obj.GetValue<Double>('window'));
    Assert.AreEqual<Double>(0.5, Obj.GetValue<Double>('truncation'));
    Assert.AreEqual<Double>(0.1, Obj.GetValue<Double>('local_window'));
    Assert.AreEqual<NativeInt>(19, Obj.Count, 'Selection key list');
  finally
    Obj.Free;
  end;
end;

procedure TZRWPlateauTests.JsonRejectsUnknownSchemaOrReader;
var
  S: TZRWSelection;
  Json: string;
begin
  Json := SelectionToJson(SampleSelection);
  Assert.IsTrue(TryParseSelection(Json, S));
  Assert.IsFalse(TryParseSelection(
    StringReplace(Json, '"schema_version":1', '"schema_version":2', []), S));
  Assert.IsFalse(TryParseSelection(
    StringReplace(Json, '"schema_version":1,', '', []), S));
  Assert.IsFalse(TryParseSelection(
    StringReplace(Json, '"aps.zrw"', '"aps.other"', []), S));
end;

initialization
  TDUnitX.RegisterTestFixture(TZRWPlateauTests);

end.
