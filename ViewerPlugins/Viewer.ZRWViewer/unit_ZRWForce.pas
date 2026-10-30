unit unit_ZRWForce;

interface

uses
  System.SysUtils, unit_ZRWData;

const
  ZRWForceTrim = 0.15;

type
  TZRWForce = record
    Header: TZRWHeader;
    ForceUnit: string;
    Cycles: Integer;
    Incomplete: Boolean;
    SkippedRows: Integer;
    Fn, Fl: TArray<Double>;
  end;

  TZRWStroke = record
    StartIdx, EndIdx, Direction: Integer;
  end;

function ParseForceRaw(const Bytes: TBytes): TZRWForce;
function DetectStrokes(const Force: TZRWForce): TArray<TZRWStroke>;
function PerStrokeCurve(const Force: TZRWForce;
  const Strokes: TArray<TZRWStroke>): TZRWCurve;

implementation

uses
  System.Classes, System.Math, System.JSON;

const
  MinRows = 10;
  DefaultCycles = 100;
  MaxStrokeDeviation = 0.5;
  FnFloorFraction = 0.1;
  DataMarker = '[DATA]';
  BannerV3 = '[APS Tribo V3.';
  DurationPrefixLength = 11;

function JsonObjectOf(Parent: TJSONObject; const Name: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := Parent.GetValue(Name);
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    Result := nil;
end;

function JsonDouble(Obj: TJSONObject; const Name: string; Default: Double): Double;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  V := Obj.GetValue(Name);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsDouble;
end;

function NumText(Value: Double): string;
begin
  Result := FloatToStr(Value, TFormatSettings.Invariant);
end;

function SingleField(const Text: string; out Value: Double): Boolean;
var
  D: Double;
begin
  Result := TryStrToFloat(Trim(Text), D, TFormatSettings.Invariant) and
    not IsNan(D) and not IsInfinite(D);
  if Result then
    Value := Single(D);
end;

procedure ReadHeader(Lines: TStringList; DataIdx: Integer; var Force: TZRWForce);
var
  I: Integer;
  JsonText: string;
  Root: TJSONValue;
  TestObj, Sampling: TJSONObject;
  Channels: TJSONValue;
  Chan: TJSONValue;
  Unit_: TJSONValue;
  Cycles: Double;
begin
  JsonText := '';
  for I := 1 to DataIdx - 1 do
    JsonText := JsonText + Lines[I] + sLineBreak;
  Root := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (Root is TJSONObject) then
      raise EZRWFormatError.Create('force.raw: header JSON is invalid');
    TestObj := JsonObjectOf(TJSONObject(Root), 'test');
    Sampling := JsonObjectOf(TJSONObject(Root), 'sampling');
    Force.ForceUnit := 'g';
    Channels := TJSONObject(Root).GetValue('channels');
    if (Channels is TJSONArray) and (TJSONArray(Channels).Count > 0) then
    begin
      Chan := TJSONArray(Channels).Items[0];
      if Chan is TJSONObject then
      begin
        Unit_ := TJSONObject(Chan).GetValue('unit');
        if Unit_ is TJSONString then
          Force.ForceUnit := TJSONString(Unit_).Value;
      end;
    end;
    Cycles := JsonDouble(TestObj, 'cycles', 0);
    Force.Cycles := Round(Cycles);
    if Force.Cycles <= 0 then
      Force.Cycles := DefaultCycles;
    Force.Header.Stroke := NumText(JsonDouble(TestObj, 'stroke_mm', 0));
    Force.Header.Speed := NumText(JsonDouble(TestObj, 'speed_mm_per_s', 0));
    Force.Header.Load := NumText(JsonDouble(TestObj, 'load', 0)) + ' ' + Force.ForceUnit;
    Force.Header.Cycles := IntToStr(Force.Cycles);
    Force.Header.SamplingInterval := IntToStr(Round(JsonDouble(Sampling, 'rate_hz', 0)));
  finally
    Root.Free;
  end;
end;

procedure RemoveBaseline(var Force: TZRWForce);
var
  I, Last, Upto: Integer;
  Avg: Double;
begin
  Last := High(Force.Fl);
  Upto := Round(0.9 * Last);
  Avg := 0;
  for I := 3 to Upto do
    Avg := Avg + Force.Fl[I];
  if Upto >= 3 then
    Avg := Avg / (Upto - 3 + 1);
  for I := 0 to Last do
    Force.Fl[I] := Force.Fl[I] - Avg;
end;

procedure RecountCycles(var Force: TZRWForce);
const
  Window = 5;
var
  I, K, Neg, Pos_, Count: Integer;
begin
  Count := 0;
  for I := Window to High(Force.Fl) - Window do
  begin
    Neg := 0;
    Pos_ := 0;
    for K := I - Window to I - 1 do
      if Force.Fl[K] < 0 then
        Inc(Neg);
    for K := I to I + Window do
      if Force.Fl[K] > 0 then
        Inc(Pos_);
    if (Neg = Window) and (Pos_ = Window) then
      Inc(Count);
  end;
  Force.Cycles := Count;
  Force.Header.Cycles := IntToStr(Count);
end;

function ParseForceRaw(const Bytes: TBytes): TZRWForce;
var
  Lines: TStringList;
  Stream: TBytesStream;
  DataIdx, I, Count, P1, P2: Integer;
  Line, Duration: string;
  X, FnV, FlV: Double;
  HasTab: Boolean;
begin
  Result := Default(TZRWForce);
  Lines := TStringList.Create;
  try
    Stream := TBytesStream.Create(Bytes);
    try
      Lines.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
    if (Lines.Count < MinRows) or (Pos(BannerV3, Lines[0]) <> 1) then
      raise EZRWFormatError.Create('force.raw: not an APS Tribo V3 file');
    DataIdx := Lines.IndexOf(DataMarker);
    if DataIdx < 1 then
      raise EZRWFormatError.Create('force.raw: missing ' + DataMarker);
    ReadHeader(Lines, DataIdx, Result);

    Duration := Lines[Lines.Count - 1];
    Delete(Duration, 1, DurationPrefixLength);
    Result.Incomplete := Pos(':', Duration) <= 0;

    SetLength(Result.Fn, Lines.Count);
    SetLength(Result.Fl, Lines.Count);
    Count := 0;
    for I := DataIdx + 3 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      P1 := Pos(#9, Line);
      HasTab := P1 > 0;
      P2 := 0;
      if HasTab then
        P2 := Pos(#9, Line, P1 + 1);
      if (P2 > 0) and SingleField(Copy(Line, 1, P1 - 1), X) and
        SingleField(Copy(Line, P1 + 1, P2 - P1 - 1), FnV) and
        SingleField(Copy(Line, P2 + 1, MaxInt), FlV) then
      begin
        Result.Fn[Count] := FnV;
        Result.Fl[Count] := FlV;
        Inc(Count);
      end
      else if HasTab then
        Inc(Result.SkippedRows);
    end;
    SetLength(Result.Fn, Count);
    SetLength(Result.Fl, Count);
  finally
    Lines.Free;
  end;
  if Count < MinRows then
    raise EZRWFormatError.CreateFmt('force.raw: %d data rows, at least %d needed',
      [Count, MinRows]);
  RemoveBaseline(Result);
  if Result.Incomplete then
    RecountCycles(Result);
end;

procedure MovingAverage(Window: Integer; var Y: TArray<Double>);
var
  I, J: Integer;
  S: Double;
begin
  for I := 0 to High(Y) - Window do
  begin
    S := 0;
    for J := 0 to Window do
      S := S + Y[I + J];
    Y[I + Window div 2] := S / (Window + 1);
  end;
end;

function DetectStrokes(const Force: TZRWForce): TArray<TZRWStroke>;
var
  Samples, I, K, Len, MinGap, LPWindow, PrevSgn, Sgn, Dir, Kept: Integer;
  Expected: Double;
  LP: TArray<Double>;
  Crossings: TArray<Integer>;
  CrossingCount: Integer;
begin
  Result := nil;
  Samples := Length(Force.Fl);
  if (Samples < MinRows) or (Force.Cycles <= 0) then
    Exit;
  Expected := Samples / (2.0 * Force.Cycles);
  if Expected < 5 then
    Exit;
  MinGap := Max(1, Round(Expected * 0.25));
  LPWindow := Max(1, Round(Expected / 8));
  LP := Copy(Force.Fl);
  MovingAverage(LPWindow, LP);

  SetLength(Crossings, Samples div MinGap + 2);
  CrossingCount := 0;
  PrevSgn := Sign(LP[0]);
  for I := 1 to Samples - 1 do
  begin
    Sgn := Sign(LP[I]);
    if (Sgn <> 0) and (PrevSgn <> 0) and (Sgn <> PrevSgn) then
    begin
      PrevSgn := Sgn;
      if (CrossingCount = 0) or (I - Crossings[CrossingCount - 1] >= MinGap) then
      begin
        Crossings[CrossingCount] := I;
        Inc(CrossingCount);
      end;
    end
    else if Sgn <> 0 then
      PrevSgn := Sgn;
  end;
  if CrossingCount < 2 then
    Exit;

  SetLength(Result, CrossingCount - 1);
  Kept := 0;
  for K := 0 to CrossingCount - 2 do
  begin
    Len := Crossings[K + 1] - Crossings[K];
    if (Abs(Len - Expected) / Expected > MaxStrokeDeviation) and
      ((K = 0) or (K = CrossingCount - 2)) then
      Continue;
    Dir := Sign(LP[Crossings[K] + 1]);
    if Dir = 0 then
      Dir := 1;
    Result[Kept].StartIdx := Crossings[K];
    Result[Kept].EndIdx := Crossings[K + 1];
    Result[Kept].Direction := Dir;
    Inc(Kept);
  end;
  SetLength(Result, Kept);
end;

function PerStrokeCurve(const Force: TZRWForce;
  const Strokes: TArray<TZRWStroke>): TZRWCurve;
var
  CycleCount, J, K, I, Pass, Len, Trimmed, From, Upto, Samples: Integer;
  SumFl, SumFn, FnAcc, FnFloor: Double;
  Stroke: TZRWStroke;
  Out_: TArray<TZRWSample>;
begin
  Result := Default(TZRWCurve);
  Result.Header := Force.Header;
  CycleCount := Length(Strokes) div 2;
  if (CycleCount < 1) or (Length(Force.Fn) < 1) then
    Exit;

  FnAcc := 0;
  for I := 0 to High(Force.Fn) do
    FnAcc := FnAcc + Abs(Force.Fn[I]);
  FnFloor := FnFloorFraction * (FnAcc / Length(Force.Fn));

  SetLength(Out_, CycleCount);
  K := 0;
  for J := 0 to CycleCount - 1 do
  begin
    SumFl := 0;
    SumFn := 0;
    Samples := 0;
    for Pass := 0 to 1 do
    begin
      Stroke := Strokes[2 * J + Pass];
      Len := Stroke.EndIdx - Stroke.StartIdx;
      Trimmed := Round(Len * ZRWForceTrim);
      From := Stroke.StartIdx + Trimmed;
      Upto := Stroke.EndIdx - Trimmed;
      for I := From to Upto - 1 do
      begin
        SumFl := SumFl + Abs(Force.Fl[I]);
        SumFn := SumFn + Abs(Force.Fn[I]);
        Inc(Samples);
      end;
    end;
    if (Samples <= 0) or (SumFn <= 0) or (SumFn / Samples < FnFloor) then
      Continue;
    Out_[K].Cycle := J + 1;
    Out_[K].COF := SumFl / SumFn;
    Inc(K);
  end;
  SetLength(Out_, K);
  Result.Samples := Out_;
end;

end.
