unit unit_SearchMetrics;

interface

type
  TGradedItem = record
    ItemId: Integer;
    Grade: Integer;
  end;

  TMetricMean = record
    Sum: Double;
    Count: Integer;
    Skipped: Integer;
    procedure Add(Value: Double);
    function Mean: Double;
  end;

function RecallAtK(const Ranked: TArray<Integer>; const Relevant: TArray<TGradedItem>;
  K: Integer): Double;
function ReciprocalRank(const Ranked: TArray<Integer>; const Relevant: TArray<TGradedItem>): Double;
function NdcgAtK(const Ranked: TArray<Integer>; const Relevant: TArray<TGradedItem>;
  K: Integer): Double;
function CountAtK(const Ranked, Items: TArray<Integer>; K: Integer): Integer;
function Percentile(const Values: TArray<Double>; P: Double): Double;

implementation

uses
  System.SysUtils, System.Math, System.Generics.Collections, System.Generics.Defaults;

function GradeOf(const Relevant: TArray<TGradedItem>; ItemId: Integer): Integer;
var
  Entry: TGradedItem;
begin
  for Entry in Relevant do
    if Entry.ItemId = ItemId then
      Exit(Entry.Grade);
  Result := 0;
end;

function RelevantCount(const Relevant: TArray<TGradedItem>): Integer;
var
  Entry: TGradedItem;
begin
  Result := 0;
  for Entry in Relevant do
    if Entry.Grade > 0 then
      Inc(Result);
end;

function Gain(Grade: Integer): Double;
begin
  Result := Power(2, Grade) - 1;
end;

function Discount(Rank: Integer): Double;
begin
  Result := 1 / Log2(Rank + 1);
end;

function RecallAtK(const Ranked: TArray<Integer>; const Relevant: TArray<TGradedItem>;
  K: Integer): Double;
var
  Total, Found, I: Integer;
begin
  Total := RelevantCount(Relevant);
  if Total = 0 then
    Exit(NaN);
  Found := 0;
  for I := 0 to Min(K, Length(Ranked)) - 1 do
    if GradeOf(Relevant, Ranked[I]) > 0 then
      Inc(Found);
  Result := Found / Total;
end;

function ReciprocalRank(const Ranked: TArray<Integer>; const Relevant: TArray<TGradedItem>): Double;
var
  I: Integer;
begin
  if RelevantCount(Relevant) = 0 then
    Exit(NaN);
  for I := 0 to High(Ranked) do
    if GradeOf(Relevant, Ranked[I]) > 0 then
      Exit(1 / (I + 1));
  Result := 0;
end;

function NdcgAtK(const Ranked: TArray<Integer>; const Relevant: TArray<TGradedItem>;
  K: Integer): Double;
var
  Grades: TArray<Integer>;
  Entry: TGradedItem;
  Dcg, Ideal: Double;
  I, Count: Integer;
begin
  if RelevantCount(Relevant) = 0 then
    Exit(NaN);
  Dcg := 0;
  for I := 0 to Min(K, Length(Ranked)) - 1 do
    Dcg := Dcg + Gain(GradeOf(Relevant, Ranked[I])) * Discount(I + 1);
  Grades := nil;
  for Entry in Relevant do
    if Entry.Grade > 0 then
      Grades := Grades + [Entry.Grade];
  TArray.Sort<Integer>(Grades, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := B - A;
    end));
  Ideal := 0;
  Count := Min(K, Length(Grades));
  for I := 0 to Count - 1 do
    Ideal := Ideal + Gain(Grades[I]) * Discount(I + 1);
  Result := Dcg / Ideal;
end;

function CountAtK(const Ranked, Items: TArray<Integer>; K: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Min(K, Length(Ranked)) - 1 do
    if TArray.IndexOf<Integer>(Items, Ranked[I]) >= 0 then
      Inc(Result);
end;

function Percentile(const Values: TArray<Double>; P: Double): Double;
var
  Sorted: TArray<Double>;
  Rank: Integer;
begin
  if Length(Values) = 0 then
    Exit(NaN);
  Sorted := Copy(Values);
  TArray.Sort<Double>(Sorted);
  Rank := EnsureRange(Ceil(P * Length(Sorted)), 1, Length(Sorted));
  Result := Sorted[Rank - 1];
end;

procedure TMetricMean.Add(Value: Double);
begin
  if IsNan(Value) then
    Inc(Skipped)
  else
  begin
    Sum := Sum + Value;
    Inc(Count);
  end;
end;

function TMetricMean.Mean: Double;
begin
  if Count = 0 then
    Result := NaN
  else
    Result := Sum / Count;
end;

end.
