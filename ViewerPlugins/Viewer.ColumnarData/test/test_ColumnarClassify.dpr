program test_ColumnarClassify;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  unit_ColumnarClassify in '..\unit_ColumnarClassify.pas';

var
  Failures: Integer = 0;

procedure AssertEq(const ATestName, AExpected, AActual: string);
begin
  if AExpected = AActual then
    Writeln('PASS ', ATestName)
  else
  begin
    Inc(Failures);
    Writeln('FAIL ', ATestName);
    Writeln('  expected: ', AExpected);
    Writeln('  actual:   ', AActual);
  end;
end;

procedure AssertEqI(const ATestName: string; AExpected, AActual: Integer);
begin
  AssertEq(ATestName, IntToStr(AExpected), IntToStr(AActual));
end;

procedure AssertEqB(const ATestName: string; AExpected, AActual: Boolean);
begin
  AssertEq(ATestName, BoolToStr(AExpected, True), BoolToStr(AActual, True));
end;

{ Runs the classifier over an in-memory document. }
function Classify(const ALines: array of string): TColumnarClassification;
var
  List: TStringList;
  I: Integer;
begin
  List := TStringList.Create;
  try
    for I := Low(ALines) to High(ALines) do
      List.Add(ALines[I]);
    Result := ClassifyColumnarText(List);
  finally
    List.Free;
  end;
end;

{ Renders a classification as 'tabular|delimiter|cols|rows|points' so a whole
  document is one readable assertion. }
function Flatten(const ALines: array of string): string;
var
  C: TColumnarClassification;
begin
  C := Classify(ALines);
  Result := Format('%s|%s|%d|%d|%d',
    [BoolToStr(C.IsTabular, True), C.DelimiterName, C.ColCount, C.RowCount,
     C.MaxSeriesPoints]);
end;

{ --- The bug this unit exists to prevent -------------------------------- }

procedure TestControlEventLogIsNotTabular;
var
  C: TColumnarClassification;
begin
  { Synthetic control-event records: timestamps, tags and JSON payloads
    must stay text instead of producing an empty chart. No operational data. }
  C := Classify([
    '[2000-01-01 00:00:01] [ControlMode] startup mode Synthetic (test fixture)',
    '[2000-01-01 00:00:02] [Remote] Synthetic pipe server listening (3 slots)',
    '[2000-01-01 00:00:03] [Agent] recipe.start {"name":"synthetic-example"}',
    '[2000-01-01 00:00:04] [Error] Synthetic hardware error: Cannot start example',
    '[2000-01-01 00:00:05] [Agent] device.command {"type":"SyntheticCommand"}'
  ]);
  AssertEqB('event log is not tabular', False, C.IsTabular);
  AssertEqI('event log plots no points', 0, C.MaxSeriesPoints);
end;

procedure TestTimestampedLogIsNotTabular;
begin
  { Bare timestamps, no brackets — still text, because the X column never
    parses as a number. }
  AssertEq('timestamped log', 'False|Space|3|0|0', Flatten([
    '2000-01-01 00:00:01 startup',
    '2000-01-01 00:00:02 listening',
    '2000-01-01 00:00:03 stopped'
  ]));
end;

procedure TestProseIsNotTabular;
begin
  { A numeric first token is not enough — the Y columns must parse too.
    Two rows, not three: the first line is eaten as a header, because it
    carries non-numeric cells. That is the chart builder's own rule. }
  AssertEq('prose with leading numbers', 'False|Space|4|2|0', Flatten([
    '12.5 seconds elapsed now',
    '13.5 seconds elapsed now',
    '14.5 seconds elapsed now'
  ]));
end;

procedure TestSingleColumnIsNotTabular;
begin
  { One number per line has no Y column to plot against. }
  AssertEqB('single column', False, Classify(['1', '2', '3', '4']).IsTabular);
end;

{ --- Real data files must keep charting --------------------------------- }

procedure TestTabSeparatedWithHeader;
var
  C: TColumnarClassification;
begin
  C := Classify([
    'Time'#9'Pressure'#9'Power',
    '0'#9'1.2e-6'#9'150',
    '1'#9'1.3e-6'#9'151',
    '2'#9'1.1e-6'#9'149'
  ]);
  AssertEqB('tsv is tabular', True, C.IsTabular);
  AssertEq('tsv delimiter', 'Tab', C.DelimiterName);
  AssertEqB('tsv has header', True, C.HasHeader);
  AssertEqI('tsv columns', 3, C.ColCount);
  AssertEqI('tsv rows', 3, C.RowCount);
  AssertEq('tsv first column name', 'Time', C.ColumnNames[0]);
  AssertEq('tsv last column name', 'Power', C.ColumnNames[2]);
end;

procedure TestCommaSeparatedWithHeader;
begin
  AssertEq('csv', 'True|Comma|2|3|3', Flatten([
    'Angle, Intensity',
    '0.0, 1000',
    '0.1, 1200',
    '0.2, 900'
  ]));
end;

procedure TestSemicolonSeparated;
begin
  AssertEq('semicolon', 'True|Semicolon|2|3|3', Flatten([
    'X;Y',
    '1;10',
    '2;20',
    '3;30'
  ]));
end;

procedure TestSpaceSeparatedNoHeader;
var
  C: TColumnarClassification;
begin
  C := Classify(['1 10', '2 20', '3 30']);
  AssertEqB('space data is tabular', True, C.IsTabular);
  AssertEq('space delimiter', 'Space', C.DelimiterName);
  AssertEqB('space data has no header', False, C.HasHeader);
  AssertEqI('space data rows', 3, C.RowCount);
end;

procedure TestCommentsAreSkipped;
var
  C: TColumnarClassification;
begin
  { All four comment markers, plus blank lines, ahead of real data. }
  C := Classify([
    '# generated by instrument',
    '% matlab-style comment',
    '// c-style comment',
    '! fortran-style comment',
    '',
    'X'#9'Y',
    '1'#9'10',
    '2'#9'20'
  ]);
  AssertEqB('commented data is tabular', True, C.IsTabular);
  AssertEq('comments do not set the delimiter', 'Tab', C.DelimiterName);
  AssertEqI('commented data rows', 2, C.RowCount);
end;

procedure TestTrailingProseStillCharts;
begin
  { Instrument files often end with a footer. The data still wins. }
  AssertEqB('trailing footer', True, Classify([
    'X'#9'Y',
    '1'#9'10',
    '2'#9'20',
    '3'#9'30',
    'End of scan'
  ]).IsTabular);
end;

{ --- Boundaries --------------------------------------------------------- }

procedure TestOneDataRowIsNotTabular;
begin
  { A single point cannot draw a line, so the chart would come up blank. }
  AssertEq('one data row', 'False|Tab|2|1|1', Flatten([
    'X'#9'Y',
    '1'#9'10'
  ]));
end;

procedure TestTwoDataRowsAreTabular;
begin
  { Two points is the smallest chart that shows something. }
  AssertEq('two data rows', 'True|Tab|2|2|2', Flatten([
    'X'#9'Y',
    '1'#9'10',
    '2'#9'20'
  ]));
end;

procedure TestHeaderOnlyIsNotTabular;
begin
  AssertEqB('header only', False, Classify(['Time'#9'Pressure']).IsTabular);
end;

procedure TestCommentsOnlyIsNotTabular;
begin
  AssertEqB('comments only', False,
    Classify(['# nothing', '# to see', '# here']).IsTabular);
end;

procedure TestEmptyIsNotTabular;
var
  C: TColumnarClassification;
begin
  C := Classify([]);
  AssertEqB('empty document', False, C.IsTabular);
  AssertEqI('empty document rows', 0, C.RowCount);
end;

procedure TestBlankLinesOnlyIsNotTabular;
begin
  AssertEqB('blank lines only', False, Classify(['', '   ', '']).IsTabular);
end;

procedure TestNilIsNotTabular;
begin
  AssertEqB('nil lines', False, ClassifyColumnarText(nil).IsTabular);
end;

procedure TestRaggedRowsDoNotOverrun;
begin
  { Short rows must not index past the parts array. }
  AssertEqB('ragged rows', True, Classify([
    'X'#9'Y'#9'Z',
    '1'#9'10'#9'100',
    '2'#9'20',
    '3'#9'30'#9'300'
  ]).IsTabular);
end;

begin
  try
    TestControlEventLogIsNotTabular;
    TestTimestampedLogIsNotTabular;
    TestProseIsNotTabular;
    TestSingleColumnIsNotTabular;

    TestTabSeparatedWithHeader;
    TestCommaSeparatedWithHeader;
    TestSemicolonSeparated;
    TestSpaceSeparatedNoHeader;
    TestCommentsAreSkipped;
    TestTrailingProseStillCharts;

    TestOneDataRowIsNotTabular;
    TestTwoDataRowsAreTabular;
    TestHeaderOnlyIsNotTabular;
    TestCommentsOnlyIsNotTabular;
    TestEmptyIsNotTabular;
    TestBlankLinesOnlyIsNotTabular;
    TestNilIsNotTabular;
    TestRaggedRowsDoNotOverrun;

    Writeln;
    if Failures = 0 then
      Writeln('All tests passed.')
    else
      Writeln(Failures, ' test(s) FAILED.');
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;

  if Failures > 0 then
    ExitCode := 1;
end.
