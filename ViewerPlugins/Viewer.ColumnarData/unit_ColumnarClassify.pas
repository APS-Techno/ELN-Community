{ Decides whether a delimited-text file actually holds chartable columns.

  The ColumnarData viewer is bound to '.dat;.csv;.txt;.ascii' — extensions that
  carry instrument data most of the time and free prose the rest of it. Feeding
  prose to the chart builder yields an empty chart and no error, so the viewer
  needs to know which kind of file it has BEFORE it decides what to show.

  The classification deliberately runs the same delimiter/comment/header/parse
  rules the chart builder runs, so the two can never disagree about a file. }
unit unit_ColumnarClassify;

interface

uses
  System.SysUtils, System.Classes;

type
  { What a pass over the document found. When IsTabular is False the caller
    should show the raw text; the remaining fields are still filled in as far
    as parsing got, which is what the status bar reports. }
  TColumnarClassification = record
    IsTabular: Boolean;
    Delimiter: Char;
    DelimiterName: string;
    HasHeader: Boolean;
    ColumnNames: TArray<string>;
    ColCount: Integer;
    RowCount: Integer;
    { Points accumulated by the richest Y column — the real test of whether a
      chart would draw anything. RowCount alone is not: a row counts even when
      none of its Y cells parsed as numbers. }
    MaxSeriesPoints: Integer;
  end;

const
  { A line needs two ends. One point draws nothing a user can read. }
  MinPlottablePoints = 2;

function DetectDelimiter(const ALine: string; out ADelimiterName: string): Char;
function IsCommentLine(const ALine: string): Boolean;
function SplitLine(const ALine: string; ADelimiter: Char): TArray<string>;
function IsHeaderLine(const ALine: string; ADelimiter: Char): Boolean;
function ClassifyColumnarText(ALines: TStrings): TColumnarClassification;

implementation

function DetectDelimiter(const ALine: string; out ADelimiterName: string): Char;
begin
  if Pos(#9, ALine) > 0 then
  begin
    Result := #9;
    ADelimiterName := 'Tab';
  end
  else if Pos(',', ALine) > 0 then
  begin
    Result := ',';
    ADelimiterName := 'Comma';
  end
  else if Pos(';', ALine) > 0 then
  begin
    Result := ';';
    ADelimiterName := 'Semicolon';
  end
  else
  begin
    Result := ' ';
    ADelimiterName := 'Space';
  end;
end;

function IsCommentLine(const ALine: string): Boolean;
var
  Trimmed: string;
begin
  Trimmed := TrimLeft(ALine);
  Result := (Trim(Trimmed) = '') or
            Trimmed.StartsWith('#') or
            Trimmed.StartsWith('%') or
            Trimmed.StartsWith('//') or
            Trimmed.StartsWith('!');
end;

function SplitLine(const ALine: string; ADelimiter: Char): TArray<string>;
var
  I: Integer;
  Raw: TArray<string>;
begin
  if ADelimiter = ' ' then
    // Space delimiter: split on any run of whitespace, skip empties
    Result := ALine.Split([' ', #9], TStringSplitOptions.ExcludeEmpty)
  else
  begin
    Raw := ALine.Split([ADelimiter]);
    SetLength(Result, Length(Raw));
    for I := 0 to Length(Raw) - 1 do
      Result[I] := Trim(Raw[I]);
  end;
end;

function IsHeaderLine(const ALine: string; ADelimiter: Char): Boolean;
var
  Parts: TArray<string>;
  I: Integer;
  Val: Double;
begin
  Parts := SplitLine(ALine, ADelimiter);
  if Length(Parts) = 0 then
    Exit(False);

  for I := 0 to Length(Parts) - 1 do
    if (Parts[I] <> '') and not TryStrToFloat(Parts[I], Val) then
      Exit(True);

  Result := False;
end;

function ClassifyColumnarText(ALines: TStrings): TColumnarClassification;
var
  I, J: Integer;
  Line, FirstDataLine: string;
  Parts: TArray<string>;
  XVal, YVal: Double;
  HeaderFound, DataStarted, FirstDataLineFound: Boolean;
  PointCounts: TArray<Integer>;
begin
  Result := Default(TColumnarClassification);
  Result.Delimiter := ' ';

  if not Assigned(ALines) then
    Exit;

  // The first line with content decides the delimiter for the whole document
  FirstDataLine := '';
  FirstDataLineFound := False;
  for I := 0 to ALines.Count - 1 do
    if not IsCommentLine(ALines[I]) then
    begin
      FirstDataLine := ALines[I];
      FirstDataLineFound := True;
      Break;
    end;

  if not FirstDataLineFound then
    Exit;

  Result.Delimiter := DetectDelimiter(FirstDataLine, Result.DelimiterName);

  HeaderFound := False;
  DataStarted := False;

  for I := 0 to ALines.Count - 1 do
  begin
    Line := ALines[I];
    if IsCommentLine(Line) then
      Continue;

    if not DataStarted then
    begin
      // First non-comment line: a row of labels names the columns
      if not HeaderFound and IsHeaderLine(Line, Result.Delimiter) then
      begin
        Result.ColumnNames := SplitLine(Line, Result.Delimiter);
        Result.HasHeader := True;
        HeaderFound := True;
        Continue;
      end;
      DataStarted := True;
    end;

    Parts := SplitLine(Line, Result.Delimiter);
    if Length(Parts) < 2 then
      Continue;

    // The first data row fixes the column count for every series
    if Result.ColCount = 0 then
    begin
      Result.ColCount := Length(Parts);
      SetLength(PointCounts, Result.ColCount);
    end;

    if not TryStrToFloat(Parts[0], XVal) then
      Continue;

    for J := 1 to Result.ColCount - 1 do
      if (J < Length(Parts)) and TryStrToFloat(Parts[J], YVal) then
        Inc(PointCounts[J]);

    Inc(Result.RowCount);
  end;

  for J := 0 to High(PointCounts) do
    if PointCounts[J] > Result.MaxSeriesPoints then
      Result.MaxSeriesPoints := PointCounts[J];

  Result.IsTabular := Result.MaxSeriesPoints >= MinPlottablePoints;
end;

end.
