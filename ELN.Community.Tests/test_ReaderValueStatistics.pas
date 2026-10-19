unit test_ReaderValueStatistics;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TReaderStatisticsTests = class
  public
    [Test] procedure PairsInEitherOrderAndScalesAbsoluteFactor;
    [Test] procedure RejectsInvalidAndAmbiguousStatistics;
    [Test] procedure KeepsZeroAndMissingDistinctAndRejectsOverflow;
  end;

implementation

uses System.Math, unit_ReaderValueStatistics;

function Input(const Name, Units: string; Value: Double): TReaderStatisticInput;
begin
  Result.Name := Name;
  Result.Units := Units;
  Result.Value := Value;
end;

procedure TReaderStatisticsTests.PairsInEitherOrderAndScalesAbsoluteFactor;
var
  S: TArray<TReaderValueStatistics>;
  Warning: string;
begin
  S := AnalyzeReaderStatistics([Input('Hardness STD', 'GPa', 0.2),
    Input('Hardness', 'GPa', 5), Input('Modulus', 'GPa', 100),
    Input('Modulus STD', 'GPa', 3)]);
  Assert.IsTrue(S[0].IsStandardDeviation);
  Assert.IsTrue(S[1].HasStandardDeviation);
  Assert.AreEqual(0.0002, ConvertedReaderTolerance(S[1], -0.001, Warning), 1e-12);
  Assert.AreEqual('', Warning);
  Assert.AreEqual(3.0, ConvertedReaderTolerance(S[2], 1, Warning), 1e-12);
end;

procedure TReaderStatisticsTests.RejectsInvalidAndAmbiguousStatistics;
var
  S: TArray<TReaderValueStatistics>;
  V: Double;
begin
  for V in [Double(-1), NaN, Infinity] do
  begin
    S := AnalyzeReaderStatistics([Input('COF', '', 0.5), Input('COF STD', '', V)]);
    Assert.IsFalse(S[0].HasStandardDeviation);
    Assert.IsTrue(S[0].Warning <> '');
  end;
  S := AnalyzeReaderStatistics([Input('Thickness', 'um', 5), Input('Thickness STD', 'm', 0.2)]);
  Assert.IsFalse(S[0].HasStandardDeviation);
  Assert.IsTrue(S[0].Warning <> '');
  S := AnalyzeReaderStatistics([Input('COF', '', 0.5), Input('COF STD', '', 0.1), Input('COF STD', '', 0.2)]);
  Assert.IsFalse(S[0].HasStandardDeviation);
  Assert.IsTrue(S[0].Warning <> '');
  S := AnalyzeReaderStatistics([Input('COF', '', 0.5), Input('COF', '', 0.7), Input('COF STD', '', 0.2)]);
  Assert.IsFalse(S[0].HasStandardDeviation);
  Assert.IsFalse(S[1].HasStandardDeviation);
  Assert.IsTrue(S[0].Warning <> '');
  Assert.IsTrue(S[1].Warning <> '');
  S := AnalyzeReaderStatistics([Input('Orphan STD', '', 1)]);
  Assert.IsTrue(S[0].IsStandardDeviation);
  Assert.IsTrue(S[0].Warning <> '');
end;

procedure TReaderStatisticsTests.KeepsZeroAndMissingDistinctAndRejectsOverflow;
var
  S: TArray<TReaderValueStatistics>;
  Warning: string;
begin
  S := AnalyzeReaderStatistics([Input('COF', '', 0.5), Input('COF STD', '', 0)]);
  Assert.IsTrue(S[0].HasStandardDeviation);
  Assert.AreEqual(0.0, ConvertedReaderTolerance(S[0], 1, Warning), 1e-12);
  Assert.AreEqual('', Warning);
  S := AnalyzeReaderStatistics([Input('COF', '', 0.5)]);
  Assert.IsFalse(S[0].HasStandardDeviation);
  Assert.AreEqual('', S[0].Warning);
  S := AnalyzeReaderStatistics([Input('COF', '', 0.5), Input('COF STD', '', 1e300)]);
  Assert.AreEqual(0.0, ConvertedReaderTolerance(S[0], 1e100, Warning), 1e-12);
  Assert.IsTrue(Warning <> '');
end;

initialization
  TDUnitX.RegisterTestFixture(TReaderStatisticsTests);
end.
