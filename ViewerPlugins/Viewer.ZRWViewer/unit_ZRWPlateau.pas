unit unit_ZRWPlateau;

interface

uses
  System.SysUtils, unit_ZRWData;

type
  TZRWInterval = record
    StartCycle, EndCycle: Double;
    ThroughEnd: Boolean;
  end;

  TZRWStats = record
    Count: Integer;
    Mean, PopulationStd: Double;
  end;

  TZRWWarning = (zwBelowMinimumDuration, zwUnstable, zwNonPositiveValues);
  TZRWWarnings = set of TZRWWarning;
  TZRWDetectResult = (zdrFound, zdrNoPlateau);
  TZRWSelectionMode = (zsmAutomatic, zsmManual);

  TZRWSelection = record
    Mode: TZRWSelectionMode;
    Interval: TZRWInterval;
    ReaderVersion, AlgorithmVersion, FileHash, ApplyId, AppliedAt: string;
    Revision, AppliedBy: Integer;
  end;

function DetectPlateau(const Curve: TZRWCurve; out Interval: TZRWInterval): TZRWDetectResult;
function IntervalStats(const Curve: TZRWCurve; const Interval: TZRWInterval): TZRWStats;
function ManualWarnings(const Curve: TZRWCurve; const Interval: TZRWInterval): TZRWWarnings;
function SelectionToJson(const S: TZRWSelection): string;
function TryParseSelection(const Json: string; out S: TZRWSelection): Boolean;
function NumberText(Value: Double): string;
function SelectionModeName(Mode: TZRWSelectionMode): string;
function TryParseSelectionMode(const Text: string;
  out Mode: TZRWSelectionMode): Boolean;

const
  ZRWSelectionSchemaVersion = 1;
  ZRWSelectionReaderId = 'aps.zrw';
  MinDurationFraction = 0.20;
  WindowFraction = 0.05;
  BandFraction = 0.30;
  CoverageFraction = 0.95;
  TruncationFraction = 0.50;
  LocalMinimumFraction = 0.10;

implementation

uses
  System.Math, System.Generics.Collections, System.JSON;

const
  CoverageNumerator = 19;
  CoverageDenominator = 20;
  BoundEpsilonFraction = 1e-9;
  ExactFitFraction = 1e-12;

function LowerBound(const Samples: TArray<TZRWSample>; X: Double): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Length(Samples);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if Samples[Mid].Cycle < X then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

function UpperBound(const Samples: TArray<TZRWSample>; X: Double): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Length(Samples);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if Samples[Mid].Cycle <= X then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

function MedianOf(const Samples: TArray<TZRWSample>; ALo, AHi: Integer): Double;
var
  Values: TArray<Double>;
  I, N: Integer;
begin
  N := AHi - ALo;
  SetLength(Values, N);
  for I := 0 to N - 1 do
    Values[I] := Samples[ALo + I].COF;
  TArray.Sort<Double>(Values);
  if Odd(N) then
    Result := Values[N div 2]
  else
    Result := (Values[N div 2 - 1] + Values[N div 2]) / 2;
end;

function RangeQualifies(const Samples: TArray<TZRWSample>; ALo, AHi: Integer;
  Ref: Double): Boolean;
var
  I, Inside, Total: Integer;
  Lower, Upper: Double;
begin
  Total := AHi - ALo;
  if (Total < 2) or (Ref <= 0) or not (Samples[ALo].Cycle < Samples[AHi - 1].Cycle) then
    Exit(False);
  Lower := (1 - BandFraction) * Ref;
  Upper := (1 + BandFraction) * Ref;
  Inside := 0;
  for I := ALo to AHi - 1 do
    if (Samples[I].COF >= Lower) and (Samples[I].COF <= Upper) then
      Inc(Inside);
  Result := Inside * CoverageDenominator >= Total * CoverageNumerator;
end;

function DistinctCycles(const Samples: TArray<TZRWSample>): TArray<Double>;
var
  I, N: Integer;
begin
  SetLength(Result, Length(Samples));
  N := 0;
  for I := 0 to High(Samples) do
    if (N = 0) or (Samples[I].Cycle <> Result[N - 1]) then
    begin
      Result[N] := Samples[I].Cycle;
      Inc(N);
    end;
  SetLength(Result, N);
end;

function SortedLowerBound(const Buf: TArray<Double>; Count: Integer; X: Double): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Count;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if Buf[Mid] < X then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

function SortedUpperBound(const Buf: TArray<Double>; Count: Integer; X: Double): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Count;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if Buf[Mid] <= X then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

procedure SortedInsert(var Buf: TArray<Double>; var Count: Integer; X: Double);
var
  Pos: Integer;
begin
  Pos := SortedLowerBound(Buf, Count, X);
  Move(Buf[Pos], Buf[Pos + 1], (Count - Pos) * SizeOf(Double));
  Buf[Pos] := X;
  Inc(Count);
end;

procedure SortedDelete(var Buf: TArray<Double>; var Count: Integer; X: Double);
var
  Pos: Integer;
begin
  Pos := SortedLowerBound(Buf, Count, X);
  Move(Buf[Pos + 1], Buf[Pos], (Count - Pos - 1) * SizeOf(Double));
  Dec(Count);
end;

function BufferMedian(const Buf: TArray<Double>; Count: Integer): Double;
begin
  if Odd(Count) then
    Result := Buf[Count div 2]
  else
    Result := (Buf[Count div 2 - 1] + Buf[Count div 2]) / 2;
end;

function RollingMedians(const S: TArray<TZRWSample>; const D: TArray<Double>;
  HalfWidth, Eps: Double): TArray<Double>;
var
  Buf: TArray<Double>;
  J, Lo, Hi, BufCount, CurLo, CurHi: Integer;
begin
  SetLength(Result, Length(D));
  SetLength(Buf, Length(S) + 1);
  BufCount := 0;
  CurLo := 0;
  CurHi := 0;
  for J := 0 to High(D) do
  begin
    Lo := LowerBound(S, D[J] - HalfWidth - Eps);
    Hi := UpperBound(S, D[J] + HalfWidth + Eps);
    while CurHi < Hi do
    begin
      SortedInsert(Buf, BufCount, S[CurHi].COF);
      Inc(CurHi);
    end;
    while CurLo < Lo do
    begin
      SortedDelete(Buf, BufCount, S[CurLo].COF);
      Inc(CurLo);
    end;
    Result[J] := BufferMedian(Buf, BufCount);
  end;
end;

function TruncationStart(const S: TArray<TZRWSample>; const D: TArray<Double>;
  const DLo: TArray<Integer>; K, E, EndHi: Integer; LocalWidth, Eps: Double): Integer;
var
  V: TArray<Double>;
  Last, J, I, A, B, Count: Integer;
  X0, X, Y, Dx, Dy, MeanX, MeanY, Cxx, Cxy, Cyy, Sse: Double;
  Lowest: Boolean;
begin
  Last := K;
  while (Last + 1 < E) and
    (DLo[Last + 1] - DLo[K] <= Trunc(TruncationFraction * (EndHi - DLo[K]))) do
    Inc(Last);
  SetLength(V, Last - K + 1);
  X0 := S[DLo[K]].Cycle;
  Count := 0;
  MeanX := 0;
  MeanY := 0;
  Cxx := 0;
  Cxy := 0;
  Cyy := 0;
  I := EndHi - 1;
  for J := E - 1 downto K do
  begin
    while I >= DLo[J] do
    begin
      X := S[I].Cycle - X0;
      Y := S[I].COF;
      Inc(Count);
      Dx := X - MeanX;
      MeanX := MeanX + Dx / Count;
      Dy := Y - MeanY;
      MeanY := MeanY + Dy / Count;
      Cxx := Cxx + Dx * (X - MeanX);
      Cxy := Cxy + Dx * (Y - MeanY);
      Cyy := Cyy + Dy * (Y - MeanY);
      Dec(I);
    end;
    if J <= Last then
    begin
      Sse := Cyy;
      if Cxx > 0 then
        Sse := Cyy - Cxy * Cxy / Cxx;
      { Rounding residue of an exact line fit counts as zero, so exact ties keep the earliest start. }
      if Sse <= ExactFitFraction * Cyy then
        Sse := 0;
      V[J - K] := Sse / Sqr(Double(Count));
    end;
  end;
  for J := K to Last do
  begin
    A := J;
    while (A > K) and (D[A - 1] >= D[J] - LocalWidth - Eps) do
      Dec(A);
    B := J;
    while (B < Last) and (D[B + 1] <= D[J] + LocalWidth + Eps) do
      Inc(B);
    Lowest := True;
    for I := A to B do
      if V[I - K] < V[J - K] then
      begin
        Lowest := False;
        Break;
      end;
    if Lowest then
      Exit(J);
  end;
  Result := K;
end;

function DetectPlateau(const Curve: TZRWCurve; out Interval: TZRWInterval): TZRWDetectResult;
var
  S: TArray<TZRWSample>;
  D, Buf, Smooth: TArray<Double>;
  DLo: TArray<Integer>;
  CLast, Span, W, w5, Eps, Ref, Lower, Upper, EndValue: Double;
  K, J, E, I, Lo, Hi, N, M, Total, BufCount, CurLo, CurHi, Inside, EndHi: Integer;
  ThroughEnd: Boolean;
begin
  Interval := Default(TZRWInterval);
  S := Curve.Samples;
  N := Length(S);
  if N < 2 then
    Exit(zdrNoPlateau);
  CLast := S[N - 1].Cycle;
  Span := CLast - S[0].Cycle;
  if not (Span > 0) then
    Exit(zdrNoPlateau);
  W := MinDurationFraction * Span;
  w5 := WindowFraction * Span;
  Eps := BoundEpsilonFraction * Span;

  SetLength(D, N);
  SetLength(DLo, N);
  M := 0;
  for I := 0 to N - 1 do
    if (M = 0) or (S[I].Cycle <> D[M - 1]) then
    begin
      D[M] := S[I].Cycle;
      DLo[M] := I;
      Inc(M);
    end;
  SetLength(D, M);
  SetLength(DLo, M);
  Smooth := RollingMedians(S, D, w5 / 2, Eps);

  SetLength(Buf, N + 1);
  BufCount := 0;
  CurLo := 0;
  CurHi := 0;

  for K := 0 to M - 1 do
  begin
    if D[K] + W > CLast + Eps then
      Break;
    Lo := DLo[K];
    if D[K] + W >= CLast - Eps then
      Hi := N
    else
      Hi := LowerBound(S, D[K] + W - Eps);
    while CurHi < Hi do
    begin
      SortedInsert(Buf, BufCount, S[CurHi].COF);
      Inc(CurHi);
    end;
    while CurLo < Lo do
    begin
      SortedDelete(Buf, BufCount, S[CurLo].COF);
      Inc(CurLo);
    end;
    Total := Hi - Lo;
    if (Total < 2) or not (S[Lo].Cycle < S[Hi - 1].Cycle) then
      Continue;
    Ref := BufferMedian(Buf, BufCount);
    if Ref <= 0 then
      Continue;
    Lower := (1 - BandFraction) * Ref;
    Upper := (1 + BandFraction) * Ref;
    Inside := SortedUpperBound(Buf, BufCount, Upper) - SortedLowerBound(Buf, BufCount, Lower);
    if Inside * CoverageDenominator < Total * CoverageNumerator then
      Continue;
    if not RangeQualifies(S, Lo, LowerBound(S, D[K] + w5 - Eps), Ref) then
      Continue;

    E := K;
    while (E < M) and (Smooth[E] >= Lower) and (Smooth[E] <= Upper) do
      Inc(E);
    ThroughEnd := E >= M;
    if ThroughEnd then
    begin
      EndValue := CLast;
      EndHi := N;
    end
    else
    begin
      EndValue := D[E];
      if EndValue < D[K] + W - Eps then
        Continue;
      EndHi := DLo[E];
    end;

    J := TruncationStart(S, D, DLo, K, E, EndHi, LocalMinimumFraction * Span, Eps);

    Interval.StartCycle := D[J];
    Interval.EndCycle := EndValue;
    Interval.ThroughEnd := ThroughEnd;
    if Interval.EndCycle - Interval.StartCycle < W - Eps then
    begin
      Interval := Default(TZRWInterval);
      Exit(zdrNoPlateau);
    end;
    Exit(zdrFound);
  end;
  Result := zdrNoPlateau;
end;

procedure IntervalRange(const Curve: TZRWCurve; const Interval: TZRWInterval;
  out Lo, Hi: Integer);
var
  S: TArray<TZRWSample>;
begin
  S := Curve.Samples;
  Lo := LowerBound(S, Interval.StartCycle);
  Hi := Lo;
  while (Hi < Length(S)) and ((S[Hi].Cycle < Interval.EndCycle) or
    (Interval.ThroughEnd and (S[Hi].Cycle = Interval.EndCycle))) do
    Inc(Hi);
  if not (Interval.EndCycle > Interval.StartCycle) then
    raise EZRWFormatError.Create('Interval has a non-positive span');
  if Hi - Lo < 2 then
    raise EZRWFormatError.Create('Interval holds fewer than two samples');
end;

function IntervalStats(const Curve: TZRWCurve; const Interval: TZRWInterval): TZRWStats;
var
  Lo, Hi, I: Integer;
  Sum, Acc, Delta: Double;
begin
  IntervalRange(Curve, Interval, Lo, Hi);
  Result.Count := Hi - Lo;
  Sum := 0;
  for I := Lo to Hi - 1 do
    Sum := Sum + Curve.Samples[I].COF;
  Result.Mean := Sum / Result.Count;
  Acc := 0;
  for I := Lo to Hi - 1 do
  begin
    Delta := Curve.Samples[I].COF - Result.Mean;
    Acc := Acc + Delta * Delta;
  end;
  Result.PopulationStd := Sqrt(Acc / Result.Count);
end;

function ManualWarnings(const Curve: TZRWCurve; const Interval: TZRWInterval): TZRWWarnings;
var
  S: TArray<TZRWSample>;
  Lo, Hi, I, J, N: Integer;
  Span, Eps, Ref, WinEnd: Double;
  D: TArray<Double>;
  Sub: TArray<TZRWSample>;
begin
  IntervalRange(Curve, Interval, Lo, Hi);
  S := Curve.Samples;
  N := Length(S);
  Span := S[N - 1].Cycle - S[0].Cycle;
  Eps := BoundEpsilonFraction * Span;
  Result := [];
  if Interval.EndCycle - Interval.StartCycle < MinDurationFraction * Span - Eps then
    Include(Result, zwBelowMinimumDuration);
  for I := Lo to Hi - 1 do
    if S[I].COF <= 0 then
    begin
      Include(Result, zwNonPositiveValues);
      Break;
    end;
  Ref := MedianOf(S, Lo, Hi);
  if not RangeQualifies(S, Lo, Hi, Ref) then
    Include(Result, zwUnstable)
  else
  begin
    Sub := Copy(S, Lo, Hi - Lo);
    D := DistinctCycles(Sub);
    for J := 0 to High(D) do
    begin
      WinEnd := D[J] + WindowFraction * Span;
      if WinEnd > Interval.EndCycle + Eps then
        Break;
      if not RangeQualifies(S, LowerBound(S, D[J]), LowerBound(S, WinEnd - Eps), Ref) then
      begin
        Include(Result, zwUnstable);
        Break;
      end;
    end;
  end;
end;

function NumberText(Value: Double): string;
var
  Digits: Integer;
  Parsed: Double;
begin
  for Digits := 15 to 17 do
  begin
    Result := FloatToStrF(Value, ffGeneral, Digits, 0, TFormatSettings.Invariant);
    Parsed := StrToFloat(Result, TFormatSettings.Invariant);
    if Parsed = Value then
      Exit;
  end;
end;

const
  ModeNames: array[TZRWSelectionMode] of string = ('automatic', 'manual');

function SelectionModeName(Mode: TZRWSelectionMode): string;
begin
  Result := ModeNames[Mode];
end;

function TryParseSelectionMode(const Text: string;
  out Mode: TZRWSelectionMode): Boolean;
var
  Candidate: TZRWSelectionMode;
begin
  for Candidate := Low(TZRWSelectionMode) to High(TZRWSelectionMode) do
    if SameText(Text, ModeNames[Candidate]) then
    begin
      Mode := Candidate;
      Exit(True);
    end;
  Mode := zsmAutomatic;
  Result := False;
end;

function SelectionToJson(const S: TZRWSelection): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', TJSONNumber.Create(ZRWSelectionSchemaVersion));
    Obj.AddPair('reader_id', ZRWSelectionReaderId);
    Obj.AddPair('mode', ModeNames[S.Mode]);
    Obj.AddPair('min_duration', TJSONNumber.Create(NumberText(MinDurationFraction)));
    Obj.AddPair('band', TJSONNumber.Create(NumberText(BandFraction)));
    Obj.AddPair('coverage', TJSONNumber.Create(NumberText(CoverageFraction)));
    Obj.AddPair('window', TJSONNumber.Create(NumberText(WindowFraction)));
    Obj.AddPair('truncation', TJSONNumber.Create(NumberText(TruncationFraction)));
    Obj.AddPair('local_window', TJSONNumber.Create(NumberText(LocalMinimumFraction)));
    Obj.AddPair('start', TJSONNumber.Create(NumberText(S.Interval.StartCycle)));
    Obj.AddPair('end', TJSONNumber.Create(NumberText(S.Interval.EndCycle)));
    Obj.AddPair('through_end', TJSONBool.Create(S.Interval.ThroughEnd));
    Obj.AddPair('reader_version', S.ReaderVersion);
    Obj.AddPair('algorithm_version', S.AlgorithmVersion);
    Obj.AddPair('file_hash', S.FileHash);
    Obj.AddPair('apply_id', S.ApplyId);
    Obj.AddPair('applied_at', S.AppliedAt);
    Obj.AddPair('applied_by', TJSONNumber.Create(S.AppliedBy));
    Obj.AddPair('revision', TJSONNumber.Create(S.Revision));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function TryParseSelection(const Json: string; out S: TZRWSelection): Boolean;
var
  Root: TJSONValue;
  Obj: TJSONObject;

  function GetStr(const Name: string; out V: string): Boolean;
  var
    Item: TJSONValue;
  begin
    Item := Obj.GetValue(Name);
    Result := Item is TJSONString;
    if Result then
      V := TJSONString(Item).Value;
  end;

  function GetNum(const Name: string; out V: Double): Boolean;
  var
    Item: TJSONValue;
  begin
    Item := Obj.GetValue(Name);
    Result := (Item is TJSONNumber) and
      TryStrToFloat(Item.ToString, V, TFormatSettings.Invariant) and not IsNan(V) and
      not IsInfinite(V);
  end;

  function GetInt(const Name: string; out V: Integer): Boolean;
  var
    F: Double;
  begin
    Result := GetNum(Name, F) and (Frac(F) = 0) and (Abs(F) < MaxInt);
    if Result then
      V := Trunc(F);
  end;

var
  ModeText, ReaderIdText: string;
  SchemaVersion: Integer;
  Flag: TJSONValue;
begin
  S := Default(TZRWSelection);
  Root := nil;
  try
    try
      Root := TJSONObject.ParseJSONValue(Json);
    except
      Root := nil;
    end;
    if not (Root is TJSONObject) then
      Exit(False);
    Obj := TJSONObject(Root);
    Result := GetInt('schema_version', SchemaVersion) and
      (SchemaVersion = ZRWSelectionSchemaVersion) and
      GetStr('reader_id', ReaderIdText) and
      (ReaderIdText = ZRWSelectionReaderId) and
      GetStr('mode', ModeText) and
      GetNum('start', S.Interval.StartCycle) and
      GetNum('end', S.Interval.EndCycle) and
      GetStr('reader_version', S.ReaderVersion) and
      GetStr('algorithm_version', S.AlgorithmVersion) and
      GetStr('file_hash', S.FileHash) and
      GetStr('apply_id', S.ApplyId) and
      GetStr('applied_at', S.AppliedAt) and
      GetInt('applied_by', S.AppliedBy) and
      GetInt('revision', S.Revision);
    if not Result then
      Exit;
    if not TryParseSelectionMode(ModeText, S.Mode) then
      Exit(False);
    Flag := Obj.GetValue('through_end');
    if not (Flag is TJSONBool) then
      Exit(False);
    S.Interval.ThroughEnd := TJSONBool(Flag).AsBoolean;
  finally
    Root.Free;
  end;
  if not Result then
    S := Default(TZRWSelection);
end;

end.
