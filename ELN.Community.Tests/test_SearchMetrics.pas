unit test_SearchMetrics;

interface

uses
  System.SysUtils, System.Math, DUnitX.TestFramework, unit_SearchMetrics;

type
  [TestFixture]
  TSearchMetricsTests = class
  private
    function Graded(const Pairs: array of Integer): TArray<TGradedItem>;
  public
    [Test] procedure RecallCountsRelevantItemsInTopK;
    [Test] procedure RecallWithKBeyondTheListUsesTheWholeList;
    [Test] procedure ReciprocalRankUsesFirstRelevantItem;
    [Test] procedure ReciprocalRankIsZeroWhenNothingRelevantIsRanked;
    [Test] procedure NdcgMatchesHandComputedValue;
    [Test] procedure NdcgIsOneForIdealOrder;
    [Test] procedure NdcgPenalisesGradeOneAheadOfGradeTwo;
    [Test] procedure NdcgWithKBeyondTheListUsesTheWholeList;
    [Test] procedure QueryWithoutRelevantItemIsUndefined;
    [Test] procedure MeanSkipsUndefinedValuesAndCountsThem;
    [Test] procedure MeanOfNothingIsUndefined;
    [Test] procedure CountAtKCountsListedItemsInTopK;
    [Test] procedure PercentileUsesNearestRank;
  end;

implementation

const
  Tolerance = 1e-6;

function TSearchMetricsTests.Graded(const Pairs: array of Integer): TArray<TGradedItem>;
var
  I: Integer;
begin
  SetLength(Result, Length(Pairs) div 2);
  for I := 0 to High(Result) do
  begin
    Result[I].ItemId := Pairs[2 * I];
    Result[I].Grade := Pairs[2 * I + 1];
  end;
end;

procedure TSearchMetricsTests.RecallCountsRelevantItemsInTopK;
var
  Relevant: TArray<TGradedItem>;
begin
  Relevant := Graded([20, 2, 50, 1, 99, 2]);
  Assert.AreEqual(1 / 3, RecallAtK([10, 20, 30, 40, 50], Relevant, 3), Tolerance);
  Assert.AreEqual(2 / 3, RecallAtK([10, 20, 30, 40, 50], Relevant, 5), Tolerance);
  Assert.AreEqual(0.0, RecallAtK([10, 20, 30, 40, 50], Relevant, 1), Tolerance);
end;

procedure TSearchMetricsTests.RecallWithKBeyondTheListUsesTheWholeList;
begin
  Assert.AreEqual(2 / 3, RecallAtK([10, 20, 30, 40, 50], Graded([20, 2, 50, 1, 99, 2]), 100), Tolerance);
end;

procedure TSearchMetricsTests.ReciprocalRankUsesFirstRelevantItem;
begin
  Assert.AreEqual(0.5, ReciprocalRank([10, 20, 30, 40, 50], Graded([20, 2, 50, 1])), Tolerance);
  Assert.AreEqual(1 / 5, ReciprocalRank([10, 20, 30, 40, 50], Graded([50, 1])), Tolerance);
end;

procedure TSearchMetricsTests.ReciprocalRankIsZeroWhenNothingRelevantIsRanked;
begin
  Assert.AreEqual(0.0, ReciprocalRank([10, 20], Graded([99, 2])), Tolerance);
  Assert.AreEqual(0.0, ReciprocalRank(nil, Graded([99, 2])), Tolerance);
end;

procedure TSearchMetricsTests.NdcgMatchesHandComputedValue;
begin
  Assert.AreEqual(0.422720, NdcgAtK([10, 20, 30, 40, 50], Graded([20, 2, 50, 1, 99, 2]), 5), Tolerance);
  Assert.AreEqual(0.0, NdcgAtK([10, 20, 30, 40, 50], Graded([20, 2, 50, 1, 99, 2]), 1), Tolerance);
end;

procedure TSearchMetricsTests.NdcgIsOneForIdealOrder;
begin
  Assert.AreEqual(1.0, NdcgAtK([20, 99, 50, 7], Graded([20, 2, 50, 1, 99, 2]), 10), Tolerance);
end;

procedure TSearchMetricsTests.NdcgPenalisesGradeOneAheadOfGradeTwo;
begin
  Assert.AreEqual(0.796708, NdcgAtK([50, 20], Graded([20, 2, 50, 1]), 10), Tolerance);
  Assert.AreEqual(1.0, NdcgAtK([20, 50], Graded([20, 2, 50, 1]), 10), Tolerance);
end;

procedure TSearchMetricsTests.NdcgWithKBeyondTheListUsesTheWholeList;
begin
  Assert.AreEqual(0.422720, NdcgAtK([10, 20, 30, 40, 50], Graded([20, 2, 50, 1, 99, 2]), 50), Tolerance);
end;

procedure TSearchMetricsTests.QueryWithoutRelevantItemIsUndefined;
begin
  Assert.IsTrue(IsNan(RecallAtK([10, 20], nil, 5)), 'recall');
  Assert.IsTrue(IsNan(ReciprocalRank([10, 20], nil)), 'rr');
  Assert.IsTrue(IsNan(NdcgAtK([10, 20], nil, 5)), 'ndcg');
  Assert.IsTrue(IsNan(RecallAtK([10, 20], Graded([10, 0]), 5)), 'grade 0 is not relevant');
end;

procedure TSearchMetricsTests.MeanSkipsUndefinedValuesAndCountsThem;
var
  Mean: TMetricMean;
begin
  Mean := Default(TMetricMean);
  Mean.Add(0.5);
  Mean.Add(NaN);
  Mean.Add(1.0);
  Assert.AreEqual(0.75, Mean.Mean, Tolerance);
  Assert.AreEqual(2, Mean.Count);
  Assert.AreEqual(1, Mean.Skipped);
end;

procedure TSearchMetricsTests.MeanOfNothingIsUndefined;
var
  Mean: TMetricMean;
begin
  Mean := Default(TMetricMean);
  Mean.Add(NaN);
  Assert.IsTrue(IsNan(Mean.Mean));
end;

procedure TSearchMetricsTests.CountAtKCountsListedItemsInTopK;
begin
  Assert.AreEqual(1, CountAtK([10, 20, 30, 40, 50], [20, 40, 99], 3));
  Assert.AreEqual(2, CountAtK([10, 20, 30, 40, 50], [20, 40, 99], 5));
  Assert.AreEqual(2, CountAtK([10, 20, 30, 40, 50], [20, 40, 99], 100));
end;

procedure TSearchMetricsTests.PercentileUsesNearestRank;
var
  Values: TArray<Double>;
  I: Integer;
begin
  SetLength(Values, 20);
  for I := 0 to 19 do
    Values[I] := 20 - I;
  Assert.AreEqual(19.0, Percentile(Values, 0.95), Tolerance);
  Assert.AreEqual(2.0, Percentile([4, 1, 3, 2], 0.5), Tolerance);
  Assert.AreEqual(7.0, Percentile([7], 0.95), Tolerance);
end;

initialization
  TDUnitX.RegisterTestFixture(TSearchMetricsTests);

end.
