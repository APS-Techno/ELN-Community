{ Prose shares the supported extensions with numeric data and can yield an empty
  chart without an error. Classification and chart building must use the same
  delimiter, comment, header and numeric parsing rules. }
unit unit_ColumnarClassify;

interface

uses
  System.SysUtils, System.Classes;

type
  { Fields remain partially populated for status reporting when IsTabular=False. }
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
function ColumnarTableToText(ALines: TStrings;
  const AClassification: TColumnarClassification): string;

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

function ColumnarTableToText(ALines: TStrings;
  const AClassification: TColumnarClassification): string;
var
  Output: TStringBuilder;
  Parts: TArray<string>;
  I, J: Integer;
  X: Double;
  SkipHeader: Boolean;
begin
  Output := TStringBuilder.Create;
  try
    for J := 0 to AClassification.ColCount - 1 do
    begin
      if J > 0 then Output.Append(#9);
      if J < Length(AClassification.ColumnNames) then
        Output.Append(AClassification.ColumnNames[J])
      else if J = 0 then
        Output.Append('X')
      else
        Output.Append('Column ' + IntToStr(J));
    end;
    Output.AppendLine;
    SkipHeader := AClassification.HasHeader;
    for I := 0 to ALines.Count - 1 do
    begin
      if IsCommentLine(ALines[I]) then Continue;
      if SkipHeader then
      begin
        SkipHeader := False;
        Continue;
      end;
      Parts := SplitLine(ALines[I], AClassification.Delimiter);
      if (Length(Parts) = 0) or not TryStrToFloat(Parts[0], X) then Continue;
      // Export source rows, not independently compacted chart series. Keep
      // repeated X values, missing cells and nonnumeric measurement markers.
      for J := 0 to AClassification.ColCount - 1 do
      begin
        if J > 0 then Output.Append(#9);
        if J < Length(Parts) then Output.Append(Parts[J]);
      end;
      Output.AppendLine;
    end;
    Result := Output.ToString;
  finally
    Output.Free;
  end;
end;

end.
