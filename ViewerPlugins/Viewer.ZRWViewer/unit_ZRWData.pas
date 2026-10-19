unit unit_ZRWData;

interface

uses
  System.SysUtils;

type
  TZRWSample = record
    Cycle, COF: Double;
  end;

  TZRWHeader = record
    Stroke, Speed, Load, Cycles, Pause, SamplingRate, SamplingInterval: string;
  end;

  TZRWCurve = record
    Header: TZRWHeader;
    Samples: TArray<TZRWSample>;
  end;

  EZRWFormatError = class(Exception);

function ParseZRWData(const Bytes: TBytes): TZRWCurve;
function LoadZRWFile(const FileName: string): TZRWCurve;

implementation

uses
  System.Classes, System.Math, System.Zip, System.Generics.Collections,
  System.RegularExpressions;

const
  DataEntryName = 'Data.dat';

function TryParseNumber(const Text: string; out Value: Double): Boolean;
var
  Trimmed: string;
begin
  Trimmed := Trim(Text);
  Result := (Trimmed <> '') and (Pos(',', Trimmed) = 0) and
    TryStrToFloat(Trimmed, Value, TFormatSettings.Invariant) and
    not IsNan(Value) and not IsInfinite(Value);
end;

function ParseNumber(const Text, ColumnName: string; LineNo: Integer): Double;
begin
  if not TryParseNumber(Text, Result) then
    raise EZRWFormatError.CreateFmt('Invalid %s value "%s" on line %d',
      [ColumnName, Trim(Text), LineNo]);
end;

function EndsHeader(const Line: string): Boolean;
var
  Fields: TArray<string>;
  Dummy: Double;
  Text: string;
begin
  Text := Trim(Line);
  Fields := Line.Split([#9]);
  Result := ((Length(Fields) = 2) and TryParseNumber(Fields[0], Dummy) and
    TryParseNumber(Fields[1], Dummy)) or
    ((Text <> '') and CharInSet(Text[1], ['0'..'9', '+', '-', '.']));
end;

procedure AssignHeaderField(const Key, Value, Units: string; var Header: TZRWHeader);
begin
  if SameText(Key, 'Stroke') then
    Header.Stroke := Value
  else if SameText(Key, 'Speed') then
    Header.Speed := Value
  else if SameText(Key, 'Load') then
  begin
    if Units <> '' then
      Header.Load := Value + ' ' + Units
    else
      Header.Load := Value;
  end
  else if SameText(Key, 'Cycles') then
    Header.Cycles := Value
  else if SameText(Key, 'Pause') then
    Header.Pause := Value
  else if SameText(Key, 'Sampling rate') then
    Header.SamplingRate := Value
  else if SameText(Key, 'Sampling interval') then
    Header.SamplingInterval := Value;
end;

procedure ParseTabHeaderLine(const Line: string; var Header: TZRWHeader);
var
  Parts: TArray<string>;
  I, Colon: Integer;
begin
  Parts := Line.Split([#9]);
  for I := 0 to High(Parts) - 1 do
  begin
    Colon := Pos(':', Parts[I]);
    if (Colon > 0) and (Colon = Length(Trim(Parts[I]))) then
      AssignHeaderField(Trim(Copy(Parts[I], 1, Colon - 1)), Trim(Parts[I + 1]), '', Header);
  end;
end;

procedure ParseSpacedHeaderLine(const Line: string; var Header: TZRWHeader);
var
  Segments: TArray<string>;
  Segment, Key, Rest, Value, Units: string;
  Colon, OpenAt, CloseAt: Integer;
begin
  Segments := TRegEx.Split(Trim(Line), ' {2,}');
  for Segment in Segments do
  begin
    Colon := Pos(':', Segment);
    if Colon < 2 then
      Continue;
    Key := Trim(Copy(Segment, 1, Colon - 1));
    Rest := Trim(Copy(Segment, Colon + 1, MaxInt));
    Units := '';
    OpenAt := Pos('[', Rest);
    CloseAt := Pos(']', Rest);
    if (OpenAt > 0) and (CloseAt > OpenAt) then
    begin
      Units := Trim(Copy(Rest, OpenAt + 1, CloseAt - OpenAt - 1));
      Value := Trim(Copy(Rest, 1, OpenAt - 1));
    end
    else
      Value := Rest;
    AssignHeaderField(Key, Value, Units, Header);
  end;
end;

procedure ParseHeaderLine(const Line: string; var Header: TZRWHeader);
begin
  if Pos(#9, Line) > 0 then
    ParseTabHeaderLine(Line, Header)
  else
    ParseSpacedHeaderLine(Line, Header);
end;

function ParseZRWData(const Bytes: TBytes): TZRWCurve;
var
  Lines: TStringList;
  Stream: TBytesStream;
  Samples: TList<TZRWSample>;
  I: Integer;
  Line: string;
  Fields: TArray<string>;
  HeaderDone: Boolean;
  Sample: TZRWSample;
begin
  Result := Default(TZRWCurve);
  Lines := TStringList.Create;
  Samples := TList<TZRWSample>.Create;
  try
    Stream := TBytesStream.Create(Bytes);
    try
      Lines.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;

    HeaderDone := False;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then
        Continue;

      if not HeaderDone then
      begin
        if not EndsHeader(Lines[I]) then
        begin
          ParseHeaderLine(Lines[I], Result.Header);
          Continue;
        end;
        HeaderDone := True;
      end;

      Fields := Lines[I].Split([#9]);
      if Length(Fields) <> 2 then
        raise EZRWFormatError.CreateFmt(
          'Expected two tab-separated columns on line %d, found %d', [I + 1, Length(Fields)]);
      Sample.Cycle := ParseNumber(Fields[0], 'cycle', I + 1);
      Sample.COF := ParseNumber(Fields[1], 'COF', I + 1);
      if (Samples.Count > 0) and (Sample.Cycle < Samples.Last.Cycle) then
        raise EZRWFormatError.CreateFmt(
          'Cycle %s on line %d is lower than the previous cycle %s',
          [FloatToStr(Sample.Cycle, TFormatSettings.Invariant), I + 1,
           FloatToStr(Samples.Last.Cycle, TFormatSettings.Invariant)]);
      Samples.Add(Sample);
    end;
    if not HeaderDone then
      raise EZRWFormatError.Create('No data rows found');
    Result.Samples := Samples.ToArray;
  finally
    Samples.Free;
    Lines.Free;
  end;
end;

function LoadZRWFile(const FileName: string): TZRWCurve;
var
  Zip: TZipFile;
  DatBytes: TBytes;
begin
  Zip := TZipFile.Create;
  try
    Zip.Open(FileName, zmRead);
    try
      if Zip.IndexOf(DataEntryName) < 0 then
        raise EZRWFormatError.CreateFmt('%s is missing from %s', [DataEntryName, FileName]);
      Zip.Read(DataEntryName, DatBytes);
    finally
      Zip.Close;
    end;
  finally
    Zip.Free;
  end;
  Result := ParseZRWData(DatBytes);
end;

end.
