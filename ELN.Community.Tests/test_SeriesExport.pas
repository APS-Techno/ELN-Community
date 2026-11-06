unit test_SeriesExport;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSeriesExportTests = class
  public
    [Test] procedure NamesAndUnitsRows;
    [Test] procedure ToleranceColumnOnlyWhenAnyTol;
    [Test] procedure HiddenColumnsSkipped;
    [Test] procedure AmbiguousCellJoinsValues;
    [Test] procedure InvariantDecimalUnderCommaLocale;
    [Test] procedure CsvQuotesTitlesWithCommaAndQuote;
    [Test] procedure PlannedRowsNotExported;
    [Test] procedure PlannedHitsExportEmpty;
    [Test] procedure MixedPlannedAndDataCellExportsDataOnly;
  end;

implementation

uses
  System.SysUtils, System.Classes, unit_ItemTypes, unit_SeriesColumn,
  unit_SeriesTable, unit_SeriesExport;

function Col(const ACaption, AUnits: string;
  ARole: TSeriesColumnRole = scrShown): TSeriesTableColumn;
begin
  Result := Default(TSeriesTableColumn);
  Result.Caption := ACaption;
  Result.Units := AUnits;
  Result.Role := ARole;
end;

function Cell(const AValues: array of Double; ATol: Double = 0): TSeriesCell;
var
  I: Integer;
begin
  SetLength(Result.Hits, Length(AValues));
  for I := 0 to High(AValues) do
  begin
    Result.Hits[I] := Default(TSeriesHit);
    Result.Hits[I].Value := AValues[I];
    Result.Hits[I].Tol := ATol;
  end;
end;

function EmptyCell: TSeriesCell;
begin
  Result.Hits := nil;
end;

function MakeRow(const ATitle: string; const ACells: array of TSeriesCell): TSeriesTableRow;
var
  I: Integer;
begin
  Result := Default(TSeriesTableRow);
  Result.State := srsMeasured;
  Result.Title := ATitle;
  SetLength(Result.Cells, Length(ACells));
  for I := 0 to High(ACells) do
    Result.Cells[I] := ACells[I];
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Split([#13#10]);
end;

procedure TSeriesExportTests.NamesAndUnitsRows;
var
  T: TSeriesTable;
  L: TArray<string>;
begin
  T.Columns := [Col('Power', 'W'), Col('Thickness', 'nm')];
  T.Rows := [MakeRow('D-1', [Cell([50]), Cell([100])])];
  L := Lines(SeriesTableToText(T, #9));
  Assert.AreEqual('Item'#9'Power'#9'Thickness', L[0]);
  Assert.AreEqual(#9'W'#9'nm', L[1]);
  Assert.AreEqual('D-1'#9'50'#9'100', L[2]);
  Assert.AreEqual('', L[3]);
end;

procedure TSeriesExportTests.ToleranceColumnOnlyWhenAnyTol;
var
  T: TSeriesTable;
  L: TArray<string>;
begin
  T.Columns := [Col('Power', 'W'), Col('Thickness', 'nm')];
  T.Rows := [
    MakeRow('A', [Cell([50], 0.5), Cell([100])]),
    MakeRow('B', [EmptyCell, Cell([110])])];
  L := Lines(SeriesTableToText(T, #9));
  Assert.AreEqual('Item'#9'Power'#9#$00B1' Power'#9'Thickness', L[0]);
  Assert.AreEqual(#9'W'#9'W'#9'nm', L[1]);
  Assert.AreEqual('A'#9'50'#9'0.5'#9'100', L[2]);
  Assert.AreEqual('B'#9#9#9'110', L[3]);
end;

procedure TSeriesExportTests.HiddenColumnsSkipped;
var
  T: TSeriesTable;
  L: TArray<string>;
begin
  T.Columns := [Col('Power', 'W', scrHidden), Col('Thickness', 'nm')];
  T.Rows := [MakeRow('A', [Cell([50]), Cell([100])])];
  L := Lines(SeriesTableToText(T, #9));
  Assert.AreEqual('Item'#9'Thickness', L[0]);
  Assert.AreEqual('A'#9'100', L[2]);
end;

procedure TSeriesExportTests.AmbiguousCellJoinsValues;
var
  T: TSeriesTable;
  L: TArray<string>;
begin
  T.Columns := [Col('Power', 'W')];
  T.Rows := [MakeRow('A', [Cell([50, 52], 1)])];
  L := Lines(SeriesTableToText(T, #9));
  Assert.AreEqual('Item'#9'Power', L[0]);
  Assert.AreEqual('A'#9'50; 52', L[2]);
end;

procedure TSeriesExportTests.InvariantDecimalUnderCommaLocale;
var
  T: TSeriesTable;
  Saved: Char;
  L: TArray<string>;
begin
  T.Columns := [Col('Power', 'W')];
  T.Rows := [MakeRow('A', [Cell([51.5])])];
  Saved := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := ',';
  try
    L := Lines(SeriesTableToText(T, #9));
  finally
    FormatSettings.DecimalSeparator := Saved;
  end;
  Assert.AreEqual('A'#9'51.5', L[2]);
end;

procedure TSeriesExportTests.CsvQuotesTitlesWithCommaAndQuote;
var
  T: TSeriesTable;
  L: TArray<string>;
begin
  T.Columns := [Col('Power', 'W')];
  T.Rows := [MakeRow('D-1, "Ti"', [Cell([50])])];
  L := Lines(SeriesTableToText(T, ','));
  Assert.AreEqual('"D-1, ""Ti""",50', L[2]);
end;

function PlannedCell(AValue: Double): TSeriesCell;
begin
  Result := Cell([AValue], 0.5);
  Result.Hits[0].Planned := True;
end;

procedure TSeriesExportTests.PlannedRowsNotExported;
var
  T: TSeriesTable;
  L: TArray<string>;
  Planned: TSeriesTableRow;
begin
  T.Columns := [Col('Power', 'W')];
  Planned := MakeRow('P-1', [Cell([50])]);
  Planned.State := srsPlanned;
  T.Rows := [Planned, MakeRow('D-1', [Cell([60])])];
  L := Lines(SeriesTableToText(T, #9));
  Assert.AreEqual('D-1'#9'60', L[2]);
  Assert.AreEqual('', L[3]);
end;

procedure TSeriesExportTests.PlannedHitsExportEmpty;
var
  T: TSeriesTable;
  L: TArray<string>;
  Only: TSeriesCell;
begin
  T.Columns := [Col('Power', 'W')];
  Only.Hits := nil;
  Only.HasPlanned := True;
  Only.PlannedValue := 40;
  T.Rows := [MakeRow('A', [PlannedCell(50)]), MakeRow('B', [Only]),
    MakeRow('C', [Cell([70])])];
  L := Lines(SeriesTableToText(T, #9));
  Assert.AreEqual('Item'#9'Power', L[0]);
  Assert.AreEqual('A'#9, L[2]);
  Assert.AreEqual('B'#9, L[3]);
  Assert.AreEqual('C'#9'70', L[4]);
end;

procedure TSeriesExportTests.MixedPlannedAndDataCellExportsDataOnly;
var
  T: TSeriesTable;
  L: TArray<string>;
  C: TSeriesCell;
begin
  T.Columns := [Col('Power', 'W')];
  C := Cell([55], 1);
  C.Hits := [PlannedCell(50).Hits[0], C.Hits[0]];
  T.Rows := [MakeRow('A', [C])];
  L := Lines(SeriesTableToText(T, #9));
  Assert.AreEqual('Item'#9'Power'#9#$00B1' Power', L[0]);
  Assert.AreEqual('A'#9'55'#9'1', L[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TSeriesExportTests);

end.
