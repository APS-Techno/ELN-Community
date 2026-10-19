unit unit_ReaderValueStatistics;

interface

type
  TReaderStatisticInput = record
    Name, Units: string;
    Value: Double;
  end;

  TReaderValueStatistics = record
    IsStandardDeviation, HasStandardDeviation: Boolean;
    StandardDeviation: Double;
    Warning: string;
  end;

function AnalyzeReaderStatistics(const Values: TArray<TReaderStatisticInput>): TArray<TReaderValueStatistics>;
function ConvertedReaderTolerance(const Statistics: TReaderValueStatistics;
  Factor: Double; out Warning: string): Double;

implementation

uses System.SysUtils, System.Math, System.Generics.Collections;

function AnalyzeReaderStatistics(const Values: TArray<TReaderStatisticInput>): TArray<TReaderValueStatistics>;
var
  Indices: TDictionary<string, Integer>;
  Counts: TDictionary<string, Integer>;
  I, J, Count: Integer;
  Name: string;
begin
  SetLength(Result, Length(Values));
  Indices := TDictionary<string, Integer>.Create;
  Counts := TDictionary<string, Integer>.Create;
  try
    for I := 0 to High(Values) do
    begin
      Result[I] := Default(TReaderValueStatistics);
      Name := Values[I].Name;
      Indices.AddOrSetValue(Name, I);
      if not Counts.TryGetValue(Name, Count) then Count := 0;
      Counts.AddOrSetValue(Name, Count + 1);
      Result[I].IsStandardDeviation := Name.EndsWith(' STD');
    end;
    for I := 0 to High(Values) do
    begin
      if Result[I].IsStandardDeviation then
      begin
        Name := Copy(Values[I].Name, 1, Length(Values[I].Name) - 4);
        if not Indices.ContainsKey(Name) then
          Result[I].Warning := Values[I].Name + ': no main value in this extraction';
        Continue;
      end;
      Name := Values[I].Name + ' STD';
      if not Indices.TryGetValue(Name, J) then Continue;
      if (Counts[Name] <> 1) or (Counts[Values[I].Name] <> 1) then
        Result[I].Warning := Name + ': ambiguous duplicate key'
      else if Values[J].Units <> Values[I].Units then
        Result[I].Warning := Name + ': reader units differ'
      else if IsNan(Values[J].Value) or IsInfinite(Values[J].Value) or (Values[J].Value < 0) then
        Result[I].Warning := Name + ': STD must be finite and nonnegative'
      else
      begin
        Result[I].HasStandardDeviation := True;
        Result[I].StandardDeviation := Values[J].Value;
      end;
    end;
  finally
    Counts.Free;
    Indices.Free;
  end;
end;

function ConvertedReaderTolerance(const Statistics: TReaderValueStatistics;
  Factor: Double; out Warning: string): Double;
var
  Scale: Double;
begin
  Result := 0;
  Warning := Statistics.Warning;
  if not Statistics.HasStandardDeviation then Exit;
  Scale := Abs(Factor);
  if IsNan(Scale) or IsInfinite(Scale) or
    ((Scale > 1) and (Statistics.StandardDeviation > MaxDouble / Scale)) then
  begin
    Warning := 'Converted STD is not finite';
    Exit;
  end;
  Result := Statistics.StandardDeviation * Scale;
end;

end.
