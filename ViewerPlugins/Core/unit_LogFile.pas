unit unit_LogFile;

{ Tab-delimited CSMIC sputter log file parser.
  Owns parsed data; one instance per plugin LoadFromFile call.
  Implements the data half of IColumnarDataProvider. }

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  unit_ELNPluginCore;

type
  TLogColumn = record
    Name:  string;
    Units: string;
    DType: TColumnDType;
  end;

  TLogFile = class
  private
    FFileName: string;
    FColumns:  TArray<TLogColumn>;
    FRows:     TArray<TArray<string>>;    // [row][col] raw cells
    FNumeric:  TArray<TArray<Double>>;    // [row][col] parsed; NaN if unparseable or text col
    FTimeColIndex: Integer;
    FTruncated:    Boolean;
    FFmtSettings:  TFormatSettings;
    procedure ParseHeader(const HeaderLine, UnitsLine: string);
    procedure ParseRows(const Lines: TStrings);
    procedure InferDTypes;
    procedure FillNumeric;
    function MakePoint(Row, Col: Integer; UseTime: Boolean): TColumnPoint;
    function GetColumnRaw(ColIdx, RowStart, RowEnd: Integer; UseTime: Boolean): TArray<TColumnPoint>;
    function GetColumnDownsampleNumeric(ColIdx, MaxRows, RangeStart, RangeEnd: Integer; UseTime: Boolean): TArray<TColumnPoint>;
    function GetColumnDownsampleText(ColIdx, MaxRows, RangeStart, RangeEnd: Integer; UseTime: Boolean): TArray<TColumnPoint>;
    function NumericStats(ColIdx: Integer): TColumnStats;
    function TextStats(ColIdx: Integer): TColumnStats;
  public
    constructor Create;
    function LoadFromFile(const AFileName: string): Boolean;
    function LoadTable(const AFileName: string; const AColumns: TArray<TLogColumn>;
      const ARows: TArray<TArray<string>>; const AFormat: TFormatSettings): Boolean;
    function ColumnCount: Integer;
    function RowCount: Integer;
    function ColumnAt(Idx: Integer): TLogColumn;
    function CellText(Row, Col: Integer): string;
    function CellNumeric(Row, Col: Integer): Double;  // NaN sentinel for missing
    // The new deposition software reports unset channels as float denormals
    // (e.g. 2.8026E-45). Call after LoadFromFile to zero them everywhere the
    // numeric matrix is consumed (charts, columnar data, stats).
    procedure ClampDenormals(const Threshold: Double = 1E-30);
    function GetTotalRows: Integer;
    function GetTimeAxisIndex: Integer;
    function GetTimeSpan(out StartTime, EndTime: string): Boolean;
    function GetSchema: TArray<TColumnSchema>;
    function ResolveColumnName(const Name: string;
      out Indices: TArray<Integer>): Boolean;
    function GetData(const Req: TColumnarRequest): TArray<TArray<TColumnPoint>>;
    function GetStats(const Cols: TArray<Integer>): TArray<TColumnStats>;
    property FileName: string read FFileName;
    property Truncated: Boolean read FTruncated;
    property TimeColIndex: Integer read FTimeColIndex;
  end;

implementation

uses
  System.Math, System.StrUtils;

const
  DTYPE_INFER_ROWS = 10;

constructor TLogFile.Create;
begin
  inherited;
  FTimeColIndex := -1;
  FFmtSettings := TFormatSettings.Invariant;
end;

function TLogFile.LoadFromFile(const AFileName: string): Boolean;
var
  Lines: TStringList;
begin
  Result := False;
  FFileName := AFileName;
  FTruncated := False;
  SetLength(FColumns, 0);
  SetLength(FRows, 0);
  SetLength(FNumeric, 0);
  FTimeColIndex := -1;
  FFmtSettings := TFormatSettings.Invariant;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName);
    except
      Exit;
    end;

    if Lines.Count < 2 then Exit;

    if Lines.Count > 2 then
    begin
      var HeaderTabs := 0;
      var LastTabs := 0;
      var I: Integer;
      for I := 1 to Length(Lines[0]) do
        if Lines[0][I] = #9 then Inc(HeaderTabs);
      var Last := Lines[Lines.Count - 1];
      for I := 1 to Length(Last) do
        if Last[I] = #9 then Inc(LastTabs);
      if (LastTabs < HeaderTabs) or (Last = '') then
      begin
        Lines.Delete(Lines.Count - 1);
        FTruncated := True;
      end;
    end;

    ParseHeader(Lines[0], Lines[1]);
    if Length(FColumns) = 0 then Exit;

    ParseRows(Lines);
    InferDTypes;
    FillNumeric;
    Result := True;
  finally
    Lines.Free;
  end;
end;

function TLogFile.LoadTable(const AFileName: string; const AColumns: TArray<TLogColumn>;
  const ARows: TArray<TArray<string>>; const AFormat: TFormatSettings): Boolean;
begin
  FFileName := AFileName;
  FTruncated := False;
  FTimeColIndex := -1;
  FFmtSettings := AFormat;
  FColumns := Copy(AColumns);
  FRows := ARows;
  SetLength(FNumeric, 0);
  Result := Length(FColumns) > 0;
  if not Result then
  begin
    SetLength(FRows, 0);
    Exit;
  end;
  InferDTypes;
  FillNumeric;
end;

procedure TLogFile.ParseHeader(const HeaderLine, UnitsLine: string);
var
  Names, Units: TStringList;
  I: Integer;
begin
  Names := TStringList.Create;
  Units := TStringList.Create;
  try
    Names.StrictDelimiter := True;
    Names.Delimiter := #9;
    Units.StrictDelimiter := True;
    Units.Delimiter := #9;
    Names.DelimitedText := HeaderLine;
    Units.DelimitedText := UnitsLine;

    SetLength(FColumns, Names.Count);
    for I := 0 to Names.Count - 1 do
    begin
      FColumns[I].Name := Names[I];
      if I < Units.Count then
        FColumns[I].Units := Units[I]
      else
        FColumns[I].Units := '';
      FColumns[I].DType := cdNumeric;
    end;

    if (Names.Count > 0) and SameText(Names[0], 'Time') then
      FTimeColIndex := 0;
  finally
    Names.Free;
    Units.Free;
  end;
end;

procedure TLogFile.ParseRows(const Lines: TStrings);
var
  Row: TStringList;
  I, J, NumDataRows: Integer;
begin
  // Data rows start at index 2 (after header + units rows).
  NumDataRows := Lines.Count - 2;
  if NumDataRows <= 0 then
  begin
    SetLength(FRows, 0);
    Exit;
  end;

  SetLength(FRows, NumDataRows);
  Row := TStringList.Create;
  try
    Row.StrictDelimiter := True;
    Row.Delimiter := #9;
    for I := 0 to NumDataRows - 1 do
    begin
      Row.DelimitedText := Lines[I + 2];
      SetLength(FRows[I], Length(FColumns));
      for J := 0 to Length(FColumns) - 1 do
      begin
        if J < Row.Count then
          FRows[I][J] := Row[J]
        else
          FRows[I][J] := '';
      end;
    end;
  finally
    Row.Free;
  end;
end;

procedure TLogFile.InferDTypes;
var
  ColIdx, RowIdx, Sampled, NumericMatches: Integer;
  V: Double;
  Cell: string;
begin
  for ColIdx := 0 to Length(FColumns) - 1 do
  begin
    if ColIdx = FTimeColIndex then
    begin
      FColumns[ColIdx].DType := cdText;
      Continue;
    end;

    Sampled := 0;
    NumericMatches := 0;
    for RowIdx := 0 to Length(FRows) - 1 do
    begin
      if Sampled >= DTYPE_INFER_ROWS then Break;
      Cell := FRows[RowIdx][ColIdx];
      if Cell = '' then Continue;
      Inc(Sampled);
      if TryStrToFloat(Cell, V, FFmtSettings) then
        Inc(NumericMatches);
    end;

    if (Sampled > 0) and (NumericMatches = Sampled) then
      FColumns[ColIdx].DType := cdNumeric
    else
      FColumns[ColIdx].DType := cdText;
  end;
end;

procedure TLogFile.FillNumeric;
var
  R, C: Integer;
  V: Double;
begin
  SetLength(FNumeric, Length(FRows));
  for R := 0 to Length(FRows) - 1 do
  begin
    SetLength(FNumeric[R], Length(FColumns));
    for C := 0 to Length(FColumns) - 1 do
    begin
      if FColumns[C].DType <> cdNumeric then
      begin
        FNumeric[R][C] := NaN;
        Continue;
      end;
      if TryStrToFloat(FRows[R][C], V, FFmtSettings) then
        FNumeric[R][C] := V
      else
        FNumeric[R][C] := NaN;
    end;
  end;
end;

procedure TLogFile.ClampDenormals(const Threshold: Double);
var
  R, C: Integer;
begin
  for R := 0 to High(FNumeric) do
    for C := 0 to High(FNumeric[R]) do
      if (not IsNaN(FNumeric[R][C])) and (Abs(FNumeric[R][C]) < Threshold) then
        FNumeric[R][C] := 0;
end;

function TLogFile.ColumnCount: Integer;
begin
  Result := Length(FColumns);
end;

function TLogFile.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TLogFile.ColumnAt(Idx: Integer): TLogColumn;
begin
  Result := FColumns[Idx];
end;

function TLogFile.CellText(Row, Col: Integer): string;
begin
  if (Row < 0) or (Row >= Length(FRows)) or
     (Col < 0) or (Col >= Length(FColumns)) then
    Exit('');
  Result := FRows[Row][Col];
end;

function TLogFile.CellNumeric(Row, Col: Integer): Double;
begin
  if (Row < 0) or (Row >= Length(FRows)) or
     (Col < 0) or (Col >= Length(FColumns)) then
    Exit(NaN);
  Result := FNumeric[Row][Col];
end;

function TLogFile.GetTotalRows: Integer;
begin
  Result := Length(FRows);
end;

function TLogFile.GetTimeAxisIndex: Integer;
begin
  Result := FTimeColIndex;
end;

function TLogFile.GetTimeSpan(out StartTime, EndTime: string): Boolean;
begin
  StartTime := '';
  EndTime := '';
  if FTimeColIndex < 0 then Exit(False);
  if Length(FRows) = 0 then Exit(False);
  StartTime := FRows[0][FTimeColIndex];
  EndTime := FRows[Length(FRows) - 1][FTimeColIndex];
  Result := True;
end;

function TLogFile.GetSchema: TArray<TColumnSchema>;
var
  I: Integer;
begin
  SetLength(Result, Length(FColumns));
  for I := 0 to Length(FColumns) - 1 do
  begin
    Result[I].Index := I;
    Result[I].Name  := FColumns[I].Name;
    Result[I].Units := FColumns[I].Units;
    Result[I].DType := FColumns[I].DType;
  end;
end;

function TLogFile.ResolveColumnName(const Name: string;
  out Indices: TArray<Integer>): Boolean;
var
  I, Count: Integer;
begin
  SetLength(Indices, 0);
  Count := 0;
  SetLength(Indices, Length(FColumns));
  for I := 0 to Length(FColumns) - 1 do
  begin
    if SameText(FColumns[I].Name, Name) then
    begin
      Indices[Count] := I;
      Inc(Count);
    end;
  end;
  SetLength(Indices, Count);
  Result := Count > 0;
end;

function TLogFile.MakePoint(Row, Col: Integer; UseTime: Boolean): TColumnPoint;
begin
  Result.Row := Row;
  Result.Time := '';
  Result.Value := 0;
  Result.TextValue := '';
  if UseTime and (FTimeColIndex >= 0) and (Row >= 0) and (Row < Length(FRows)) then
    Result.Time := FRows[Row][FTimeColIndex];
  if (Row < 0) or (Row >= Length(FRows)) or
     (Col < 0) or (Col >= Length(FColumns)) then
    Exit;
  if FColumns[Col].DType = cdNumeric then
    Result.Value := FNumeric[Row][Col]
  else
    Result.TextValue := FRows[Row][Col];
end;

function TLogFile.GetColumnRaw(ColIdx, RowStart, RowEnd: Integer;
                               UseTime: Boolean): TArray<TColumnPoint>;
var
  R, OutCount: Integer;
begin
  if RowEnd > Length(FRows) then RowEnd := Length(FRows);
  if RowStart < 0 then RowStart := 0;
  if RowEnd <= RowStart then Exit(nil);

  SetLength(Result, RowEnd - RowStart);
  OutCount := 0;
  for R := RowStart to RowEnd - 1 do
  begin
    if (FColumns[ColIdx].DType = cdNumeric) and IsNaN(FNumeric[R][ColIdx]) then
      Continue;
    Result[OutCount] := MakePoint(R, ColIdx, UseTime);
    Inc(OutCount);
  end;
  SetLength(Result, OutCount);
end;

function TLogFile.GetColumnDownsampleNumeric(ColIdx, MaxRows,
  RangeStart, RangeEnd: Integer; UseTime: Boolean): TArray<TColumnPoint>;
var
  N, BucketCount, B, RowLo, RowHi, R, MinR, MaxR, OutCount: Integer;
  V, MinV, MaxV: Double;
  HasData: Boolean;
begin
  N := RangeEnd - RangeStart;

  if N <= MaxRows then
    Exit(GetColumnRaw(ColIdx, RangeStart, RangeEnd, UseTime));

  BucketCount := MaxRows div 2;
  if BucketCount < 1 then BucketCount := 1;

  SetLength(Result, BucketCount * 2);
  OutCount := 0;

  for B := 0 to BucketCount - 1 do
  begin
    RowLo := RangeStart + Trunc(B * (N / BucketCount));
    if B = BucketCount - 1 then
      RowHi := RangeEnd
    else
      RowHi := RangeStart + Trunc((B + 1) * (N / BucketCount));

    HasData := False;
    MinV := 0; MaxV := 0; MinR := -1; MaxR := -1;
    for R := RowLo to RowHi - 1 do
    begin
      V := FNumeric[R][ColIdx];
      if IsNaN(V) then Continue;
      if not HasData then
      begin
        MinV := V; MaxV := V; MinR := R; MaxR := R; HasData := True;
      end
      else
      begin
        if V < MinV then begin MinV := V; MinR := R; end;
        if V > MaxV then begin MaxV := V; MaxR := R; end;
      end;
    end;

    if not HasData then Continue;

    if MinR = MaxR then
    begin
      Result[OutCount] := MakePoint(MinR, ColIdx, UseTime);
      Inc(OutCount);
    end
    else if MinR < MaxR then
    begin
      Result[OutCount] := MakePoint(MinR, ColIdx, UseTime);
      Inc(OutCount);
      Result[OutCount] := MakePoint(MaxR, ColIdx, UseTime);
      Inc(OutCount);
    end
    else
    begin
      Result[OutCount] := MakePoint(MaxR, ColIdx, UseTime);
      Inc(OutCount);
      Result[OutCount] := MakePoint(MinR, ColIdx, UseTime);
      Inc(OutCount);
    end;
  end;

  SetLength(Result, OutCount);
end;

function TLogFile.GetColumnDownsampleText(ColIdx, MaxRows,
  RangeStart, RangeEnd: Integer; UseTime: Boolean): TArray<TColumnPoint>;
var
  N, BucketCount, B, RowLo, OutCount: Integer;
begin
  N := RangeEnd - RangeStart;
  if N <= MaxRows then
    Exit(GetColumnRaw(ColIdx, RangeStart, RangeEnd, UseTime));

  BucketCount := MaxRows;
  if BucketCount < 1 then BucketCount := 1;

  SetLength(Result, BucketCount);
  OutCount := 0;
  for B := 0 to BucketCount - 1 do
  begin
    RowLo := RangeStart + Trunc(B * (N / BucketCount));
    if RowLo >= RangeEnd then Break;
    Result[OutCount] := MakePoint(RowLo, ColIdx, UseTime);
    Inc(OutCount);
  end;
  SetLength(Result, OutCount);
end;

function TLogFile.GetData(const Req: TColumnarRequest): TArray<TArray<TColumnPoint>>;
var
  I, ColIdx, RangeStart, RangeEnd, MaxRows: Integer;
  UseTime: Boolean;
begin
  RangeStart := Req.RowStart;
  RangeEnd   := Req.RowEnd;
  if RangeStart < 0 then RangeStart := 0;
  if (RangeEnd < 0) or (RangeEnd > Length(FRows)) then RangeEnd := Length(FRows);
  if RangeEnd < RangeStart then RangeEnd := RangeStart;

  MaxRows := Req.MaxRows;
  if MaxRows < 2 then MaxRows := 500;

  UseTime := FTimeColIndex >= 0;

  SetLength(Result, Length(Req.Columns));
  for I := 0 to Length(Req.Columns) - 1 do
  begin
    ColIdx := Req.Columns[I];
    if (ColIdx < 0) or (ColIdx >= Length(FColumns)) then
    begin
      SetLength(Result[I], 0);
      Continue;
    end;
    case Req.Mode of
      cmRaw:
        Result[I] := GetColumnRaw(ColIdx, RangeStart, RangeEnd, UseTime);
      cmDownsample:
        if FColumns[ColIdx].DType = cdNumeric then
          Result[I] := GetColumnDownsampleNumeric(ColIdx, MaxRows, RangeStart, RangeEnd, UseTime)
        else
          Result[I] := GetColumnDownsampleText(ColIdx, MaxRows, RangeStart, RangeEnd, UseTime);
    else
      SetLength(Result[I], 0);
    end;
  end;
end;

function TLogFile.NumericStats(ColIdx: Integer): TColumnStats;
var
  R, Count, NonZero: Integer;
  V, Sum, SumSq, MinV, MaxV: Double;
  MinR, MaxR: Integer;
  HasFirst: Boolean;
begin
  Result := Default(TColumnStats);
  Result.DType := cdNumeric;
  Result.RowCount := Length(FRows);

  Count := 0;
  NonZero := 0;
  Sum := 0;
  SumSq := 0;
  MinV := 0; MaxV := 0; MinR := 0; MaxR := 0;
  HasFirst := False;

  for R := 0 to Length(FRows) - 1 do
  begin
    V := FNumeric[R][ColIdx];
    if IsNaN(V) then Continue;
    if V <> 0 then Inc(NonZero);
    if not HasFirst then
    begin
      Result.FirstV := V;
      MinV := V; MaxV := V; MinR := R; MaxR := R;
      HasFirst := True;
    end
    else
    begin
      if V < MinV then begin MinV := V; MinR := R; end;
      if V > MaxV then begin MaxV := V; MaxR := R; end;
    end;
    Result.LastV := V;
    Sum := Sum + V;
    SumSq := SumSq + V * V;
    Inc(Count);
  end;

  Result.NonZeroCount := NonZero;
  if Count > 0 then
  begin
    Result.MinV := MinV;
    Result.MaxV := MaxV;
    Result.Mean := Sum / Count;
    if Count > 1 then
      Result.StdDev := Sqrt(Max(0, (SumSq / Count) - Result.Mean * Result.Mean))
    else
      Result.StdDev := 0;
    Result.MinRow := MinR;
    Result.MaxRow := MaxR;
    if FTimeColIndex >= 0 then
    begin
      Result.MinTime := FRows[MinR][FTimeColIndex];
      Result.MaxTime := FRows[MaxR][FTimeColIndex];
    end;
  end;
end;

function TLogFile.TextStats(ColIdx: Integer): TColumnStats;
var
  R: Integer;
  Distinct: TDictionary<string, Boolean>;
  Cell: string;
begin
  Result := Default(TColumnStats);
  Result.DType := cdText;
  Result.RowCount := Length(FRows);
  if Length(FRows) = 0 then Exit;

  Result.FirstText := FRows[0][ColIdx];
  Result.LastText  := FRows[Length(FRows) - 1][ColIdx];

  Distinct := TDictionary<string, Boolean>.Create;
  try
    for R := 0 to Length(FRows) - 1 do
    begin
      Cell := FRows[R][ColIdx];
      if not Distinct.ContainsKey(Cell) then
        Distinct.Add(Cell, True);
    end;
    Result.DistinctCount := Distinct.Count;
  finally
    Distinct.Free;
  end;
end;

function TLogFile.GetStats(const Cols: TArray<Integer>): TArray<TColumnStats>;
var
  I, ColIdx: Integer;
begin
  SetLength(Result, Length(Cols));
  for I := 0 to Length(Cols) - 1 do
  begin
    ColIdx := Cols[I];
    if (ColIdx < 0) or (ColIdx >= Length(FColumns)) then
    begin
      Result[I] := Default(TColumnStats);
      Continue;
    end;
    if FColumns[ColIdx].DType = cdNumeric then
      Result[I] := NumericStats(ColIdx)
    else
      Result[I] := TextStats(ColIdx);
  end;
end;

end.
