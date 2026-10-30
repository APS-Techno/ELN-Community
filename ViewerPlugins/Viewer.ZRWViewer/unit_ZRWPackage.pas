unit unit_ZRWPackage;

interface

uses
  System.SysUtils, unit_ZRWData, unit_ZRWForce;

type
  TZRWContainer = (zcLegacy, zcPackage, zcUnknown);

  TZRWGap = record
    Row, MissingSamples: Int64;
  end;

  TZRWPackageClock = record
    DaqRateHz: Double;
    SamplesPerReadout: Integer;
    FirstSample, ReadoutsWritten: Int64;
    Gaps: TArray<TZRWGap>;
  end;

  TZRWChannel = record
    Name, Units, Idn: string;
    Time, Value: TArray<Double>;
    BadRows: Integer;
  end;

  TZRWPackage = record
    Status, StopReason: string;
    Clock: TZRWPackageClock;
    Channel: TZRWChannel;
    Force: TZRWForce;
    Strokes: TArray<TZRWStroke>;
    Curve: TZRWCurve;
    ChannelCurve: TZRWCurve;
  end;

function DetectZRWContainer(const FileName: string): TZRWContainer;
function ReadingPosition(const Clock: TZRWPackageClock; RowCount: Int64; T: Double;
  out P: Double): Boolean;
function ChannelPerCycle(const Package: TZRWPackage): TZRWCurve;
function MovingMedian(const Curve: TZRWCurve; Window: Integer): TZRWCurve;
function PackageStatusLine(const Package: TZRWPackage): string;

function ParseChannelTsv(const Text: string; const Columns, Units: TArray<string>;
  PlotIndex: Integer): TZRWChannel;
function LoadZRWPackage(const FileName: string): TZRWPackage;

implementation

uses
  System.Classes, System.Math, System.Zip, System.JSON, System.Generics.Collections,
  System.Generics.Defaults;

const
  PackageFormat = 'APS Tribo Package';
  EntryForce = 'force.raw';
  EntryLogger = 'resistance.tsv';
  EntryManifest = 'test.json';
  EntryLegacy = 'Data.dat';
  TextUnit = 'text';

function HasName(Zip: TZipFile; const Wanted: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to Zip.FileCount - 1 do
    if SameText(Zip.FileNames[I], Wanted) then
      Exit(True);
  Result := False;
end;

function DetectZRWContainer(const FileName: string): TZRWContainer;
var
  Zip: TZipFile;
begin
  Zip := TZipFile.Create;
  try
    try
      Zip.Open(FileName, zmRead);
    except
      on E: Exception do
        raise EZRWFormatError.CreateFmt('Cannot open %s: %s', [FileName, E.Message]);
    end;
    if HasName(Zip, EntryForce) and HasName(Zip, EntryLogger) and
      HasName(Zip, EntryManifest) then
      Result := zcPackage
    else if HasName(Zip, EntryLegacy) then
      Result := zcLegacy
    else
      Result := zcUnknown;
  finally
    Zip.Free;
  end;
end;

function ReadEntry(Zip: TZipFile; const Wanted: string): TBytes;
var
  I: Integer;
begin
  for I := 0 to Zip.FileCount - 1 do
    if SameText(Zip.FileNames[I], Wanted) then
    begin
      Zip.Read(I, Result);
      Exit;
    end;
  raise EZRWFormatError.CreateFmt('Package has no %s', [Wanted]);
end;

function DecodeUtf8(const B: TBytes): string;
begin
  Result := TEncoding.UTF8.GetString(B);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function FindPath(Root: TJSONValue; const Path: string): TJSONValue;
var
  Part: string;
begin
  Result := Root;
  for Part in Path.Split(['.']) do
  begin
    if not (Result is TJSONObject) then
      Exit(nil);
    Result := TJSONObject(Result).GetValue(Part);
    if Result = nil then
      Exit(nil);
  end;
  if Result is TJSONNull then
    Result := nil;
end;

function MissingKey(const Path: string): EZRWFormatError;
begin
  Result := EZRWFormatError.CreateFmt('test.json: missing %s', [Path]);
end;

function OptString(Root: TJSONValue; const Path: string): string;
var
  V: TJSONValue;
begin
  V := FindPath(Root, Path);
  if V is TJSONString then
    Result := TJSONString(V).Value
  else
    Result := '';
end;

function RequireString(Root: TJSONValue; const Path: string): string;
var
  V: TJSONValue;
begin
  V := FindPath(Root, Path);
  if not (V is TJSONString) then
    raise MissingKey(Path);
  Result := TJSONString(V).Value;
end;

function RequireDouble(Root: TJSONValue; const Path: string): Double;
var
  V: TJSONValue;
begin
  V := FindPath(Root, Path);
  if not (V is TJSONNumber) then
    raise MissingKey(Path);
  Result := TJSONNumber(V).AsDouble;
end;

function OptInt64(Root: TJSONValue; const Path: string): Int64;
var
  V: TJSONValue;
begin
  V := FindPath(Root, Path);
  if V is TJSONNumber then
    Result := Round(TJSONNumber(V).AsDouble)
  else
    Result := 0;
end;

function RequireStringArray(Root: TJSONValue; const Path: string): TArray<string>;
var
  V: TJSONValue;
  I: Integer;
begin
  V := FindPath(Root, Path);
  if not (V is TJSONArray) then
    raise MissingKey(Path);
  SetLength(Result, TJSONArray(V).Count);
  for I := 0 to High(Result) do
  begin
    if not (TJSONArray(V).Items[I] is TJSONString) then
      raise MissingKey(Path);
    Result[I] := TJSONString(TJSONArray(V).Items[I]).Value;
  end;
end;

function ParseGaps(Root: TJSONValue): TArray<TZRWGap>;
var
  V: TJSONValue;
  I: Integer;
begin
  V := FindPath(Root, 'clock.gaps');
  if not (V is TJSONArray) then
    raise MissingKey('clock.gaps');
  SetLength(Result, TJSONArray(V).Count);
  for I := 0 to High(Result) do
  begin
    Result[I].Row := Round(RequireDouble(TJSONArray(V).Items[I], 'row'));
    Result[I].MissingSamples :=
      Round(RequireDouble(TJSONArray(V).Items[I], 'missing_samples'));
  end;
  TArray.Sort<TZRWGap>(Result, TComparer<TZRWGap>.Construct(
    function(const A, B: TZRWGap): Integer
    begin
      Result := TComparer<Int64>.Default.Compare(A.Row, B.Row);
    end));
end;

function IsReservedKey(const Name: string): Boolean;
const
  Reserved: array[0..7] of string = ('Fn', 'Cycles', 'Stroke', 'Speed',
    'Sampling Rate', 'Sampling Interval', 'COF', 'COF STD');
var
  Key: string;
begin
  for Key in Reserved do
    if SameText(Key, Name) then
      Exit(True);
  Result := Name.EndsWith(' STD', True);
end;

procedure ParseManifest(const JsonText: string; out Package: TZRWPackage;
  out Columns, Units: TArray<string>; out PlotIndex: Integer);
var
  Root: TJSONValue;
  Version, PlotColumn: string;
  Major, I: Integer;
begin
  Root := TJSONObject.ParseJSONValue(JsonText);
  try
    if not (Root is TJSONObject) then
      raise EZRWFormatError.Create('test.json: invalid JSON');
    Version := RequireString(Root, 'format_version');
    Major := StrToIntDef(Copy(Version, 1, Pos('.', Version + '.') - 1), -1);
    if (RequireString(Root, 'format') <> PackageFormat) or (Major <> 1) then
      raise EZRWFormatError.CreateFmt('Unsupported package format %s %s',
        [OptString(Root, 'format'), Version]);
    Package.Status := RequireString(Root, 'status');
    Package.StopReason := OptString(Root, 'stop_reason');
    Package.Clock.DaqRateHz := RequireDouble(Root, 'clock.daq_rate_hz');
    Package.Clock.SamplesPerReadout :=
      Round(RequireDouble(Root, 'clock.samples_per_readout'));
    Package.Clock.FirstSample := Round(RequireDouble(Root, 'clock.first_sample'));
    Package.Clock.ReadoutsWritten := OptInt64(Root, 'clock.readouts_written');
    Package.Clock.Gaps := ParseGaps(Root);
    if Package.Clock.SamplesPerReadout <= 0 then
      raise EZRWFormatError.Create('test.json: invalid clock');
    Columns := RequireStringArray(Root, 'data_logger.columns');
    Units := RequireStringArray(Root, 'data_logger.units');
    if Length(Columns) <> Length(Units) then
      raise EZRWFormatError.Create('test.json: columns and units differ in length');
    PlotColumn := RequireString(Root, 'data_logger.plot_column');
    PlotIndex := -1;
    for I := 0 to High(Columns) do
      if Columns[I] = PlotColumn then
      begin
        PlotIndex := I;
        Break;
      end;
    if PlotIndex < 0 then
      raise EZRWFormatError.CreateFmt('test.json: plot_column %s not in columns',
        [PlotColumn]);
    if SameText(Units[PlotIndex], TextUnit) then
      raise EZRWFormatError.CreateFmt('test.json: plot_column %s is not numeric',
        [PlotColumn]);
    if IsReservedKey(PlotColumn) then
      raise EZRWFormatError.CreateFmt('test.json: plot_column %s collides with a reader key',
        [PlotColumn]);
    Package.Channel.Name := PlotColumn;
    Package.Channel.Units := Units[PlotIndex];
    Package.Channel.Idn := OptString(Root, 'data_logger.idn');
  finally
    Root.Free;
  end;
end;

function TsvLines(const Text: string): TArray<string>;
var
  Raw: TArray<string>;
  I, N: Integer;
begin
  Raw := Text.Split([#10]);
  N := Length(Raw);
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := Raw[I].TrimRight([#13]);
  while (N > 0) and (Result[N - 1] = '') do
    Dec(N);
  SetLength(Result, N);
end;

function ParseChannelTsv(const Text: string; const Columns, Units: TArray<string>;
  PlotIndex: Integer): TZRWChannel;
const
  HeaderError = 'resistance.tsv header does not match test.json';
var
  Lines, F: TArray<string>;
  I, J, N, Cols: Integer;
  T, Dt, V: Double;
  Ok: Boolean;
begin
  Result := Default(TZRWChannel);
  Cols := Length(Columns);
  Lines := TsvLines(Text);
  if Length(Lines) < 2 then
    raise EZRWFormatError.Create(HeaderError);
  F := Lines[0].Split([#9]);
  Ok := (Length(F) = Cols + 2) and (F[0] = 't_s') and (F[1] = 'dt_s');
  for J := 0 to Cols - 1 do
    Ok := Ok and (F[J + 2] = Columns[J]);
  if Ok then
  begin
    F := Lines[1].Split([#9]);
    Ok := (Length(F) = Cols + 2) and (F[0] = 's') and (F[1] = 's');
    for J := 0 to Cols - 1 do
      Ok := Ok and (F[J + 2] = Units[J]);
  end;
  if not Ok then
    raise EZRWFormatError.Create(HeaderError);

  SetLength(Result.Time, Length(Lines) - 2);
  SetLength(Result.Value, Length(Lines) - 2);
  N := 0;
  for I := 2 to High(Lines) do
  begin
    F := Lines[I].Split([#9]);
    Ok := (Length(F) = Cols + 2) and
      TryStrToFloat(F[0], T, TFormatSettings.Invariant) and
      TryStrToFloat(F[1], Dt, TFormatSettings.Invariant);
    for J := 0 to Cols - 1 do
      if Ok and not SameText(Units[J], TextUnit) then
        Ok := TryStrToFloat(F[J + 2], V, TFormatSettings.Invariant) and
          not IsNan(V) and not IsInfinite(V);
    if not Ok then
    begin
      Inc(Result.BadRows);
      Continue;
    end;
    TryStrToFloat(F[PlotIndex + 2], V, TFormatSettings.Invariant);
    Result.Time[N] := T;
    Result.Value[N] := V;
    Inc(N);
  end;
  SetLength(Result.Time, N);
  SetLength(Result.Value, N);
end;

function ReadingPosition(const Clock: TZRWPackageClock; RowCount: Int64; T: Double;
  out P: Double): Boolean;
var
  S, Rel: Double;
  Offset, RowStart, RowEnd, R: Int64;
  K: Integer;
begin
  Result := False;
  P := 0;
  S := T * Clock.DaqRateHz;
  Offset := 0;
  RowStart := 0;
  for K := 0 to Length(Clock.Gaps) do
  begin
    if K < Length(Clock.Gaps) then
      RowEnd := Clock.Gaps[K].Row
    else
      RowEnd := High(Int64);
    Rel := S - Clock.FirstSample - Offset;
    if Rel < 0 then
      Exit;
    R := Floor(Rel / Clock.SamplesPerReadout);
    if R < RowStart then
      Exit;
    if R < RowEnd then
    begin
      P := Rel / Clock.SamplesPerReadout - 0.5;
      Result := (P >= -0.5) and (P <= RowCount - 0.5);
      Exit;
    end;
    if K < Length(Clock.Gaps) then
    begin
      Inc(Offset, Clock.Gaps[K].MissingSamples);
      RowStart := RowEnd;
    end;
  end;
end;

function ChannelPerCycle(const Package: TZRWPackage): TZRWCurve;
var
  Positions, Values: TArray<Double>;
  I, J, N, Count, Kept: Integer;
  P, A, B, Sum: Double;
  Sample: TZRWSample;
  Out_: TArray<TZRWSample>;
begin
  Result := Default(TZRWCurve);
  if Package.Clock.DaqRateHz <= 0 then
    Exit;
  SetLength(Positions, Length(Package.Channel.Time));
  SetLength(Values, Length(Positions));
  N := 0;
  for I := 0 to High(Package.Channel.Time) do
    if ReadingPosition(Package.Clock, Length(Package.Force.Fl),
      Package.Channel.Time[I], P) then
    begin
      Positions[N] := P;
      Values[N] := Package.Channel.Value[I];
      Inc(N);
    end;
  SetLength(Out_, Length(Package.Curve.Samples));
  Kept := 0;
  for Sample in Package.Curve.Samples do
  begin
    J := Round(Sample.Cycle) - 1;
    if (J < 0) or (2 * J + 1 > High(Package.Strokes)) then
      Continue;
    A := Package.Strokes[2 * J].StartIdx - 0.5;
    B := Package.Strokes[2 * J + 1].EndIdx - 0.5;
    Sum := 0;
    Count := 0;
    for I := 0 to N - 1 do
      if (Positions[I] >= A) and (Positions[I] < B) then
      begin
        Sum := Sum + Values[I];
        Inc(Count);
      end;
    if Count > 0 then
    begin
      Out_[Kept].Cycle := Sample.Cycle;
      Out_[Kept].COF := Sum / Count;
      Inc(Kept);
    end;
  end;
  SetLength(Out_, Kept);
  Result.Header := Package.Curve.Header;
  Result.Samples := Out_;
end;

function MovingMedian(const Curve: TZRWCurve; Window: Integer): TZRWCurve;
var
  Half: Double;
  Buffer: TArray<Double>;
  I, J, Lo, Hi, N: Integer;
begin
  Result.Header := Curve.Header;
  Result.Samples := Copy(Curve.Samples);
  if Window <= 1 then
    Exit;
  Half := Window div 2;
  SetLength(Buffer, Length(Curve.Samples));
  Lo := 0;
  Hi := -1;
  for I := 0 to High(Curve.Samples) do
  begin
    while Curve.Samples[Lo].Cycle < Curve.Samples[I].Cycle - Half do
      Inc(Lo);
    while (Hi < High(Curve.Samples)) and
      (Curve.Samples[Hi + 1].Cycle <= Curve.Samples[I].Cycle + Half) do
      Inc(Hi);
    N := Hi - Lo + 1;
    for J := 0 to N - 1 do
      Buffer[J] := Curve.Samples[Lo + J].COF;
    TArray.Sort<Double>(Buffer, TComparer<Double>.Default, 0, N);
    if Odd(N) then
      Result.Samples[I].COF := Buffer[N div 2]
    else
      Result.Samples[I].COF := (Buffer[N div 2 - 1] + Buffer[N div 2]) / 2;
  end;
end;

function PackageStatusLine(const Package: TZRWPackage): string;
var
  Stop: string;
begin
  Stop := Package.StopReason;
  if Stop = '' then
    Stop := '-';
  Result := Format('%s  |  %s  |  %s  |  gaps %d  |  %s rows %d', [Package.Status, Stop,
    Package.Channel.Idn, Length(Package.Clock.Gaps), Package.Channel.Name,
    Length(Package.Channel.Value)]);
  if Package.Channel.BadRows > 0 then
    Result := Result + Format('  |  bad rows %d', [Package.Channel.BadRows]);
  if Length(Package.Force.Fn) <> Package.Clock.ReadoutsWritten then
    Result := Result + Format('  |  force rows %d of %d',
      [Length(Package.Force.Fn), Package.Clock.ReadoutsWritten]);
  if Package.Force.SkippedRows > 0 then
    Result := Result + Format('  |  force rows skipped %d, positions not exact',
      [Package.Force.SkippedRows]);
  if Package.Clock.DaqRateHz <= 0 then
    Result := Result + '  |  no DAQ clock, channel not placed';
end;

function LoadZRWPackage(const FileName: string): TZRWPackage;
var
  Zip: TZipFile;
  Columns, Units: TArray<string>;
  PlotIndex: Integer;
  Channel: TZRWChannel;
  ForceBytes: TBytes;
  Tsv: string;
begin
  Result := Default(TZRWPackage);
  Zip := TZipFile.Create;
  try
    Zip.Open(FileName, zmRead);
    try
      ParseManifest(DecodeUtf8(ReadEntry(Zip, EntryManifest)), Result, Columns,
        Units, PlotIndex);
      Tsv := DecodeUtf8(ReadEntry(Zip, EntryLogger));
      ForceBytes := ReadEntry(Zip, EntryForce);
    finally
      Zip.Close;
    end;
  finally
    Zip.Free;
  end;
  Channel := ParseChannelTsv(Tsv, Columns, Units, PlotIndex);
  Channel.Name := Result.Channel.Name;
  Channel.Units := Result.Channel.Units;
  Channel.Idn := Result.Channel.Idn;
  Result.Channel := Channel;
  Result.Force := ParseForceRaw(ForceBytes);
  Result.Strokes := DetectStrokes(Result.Force);
  Result.Curve := PerStrokeCurve(Result.Force, Result.Strokes);
  Result.ChannelCurve := ChannelPerCycle(Result);
end;

end.
