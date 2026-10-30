unit test_ZRWData;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  unit_ZRWData;

type
  [TestFixture]
  TZRWDataTests = class
  private
    FDir: string;
    function Bytes(const Text: string): TBytes;
    function WriteArchive(const Name, Text: string): string;
    function Body(const Rows: array of string): string;
    procedure ExpectFormatError(const Text: string; const LineMarker: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ZrwAndZrvGiveSameSamples;
    [Test] procedure HeaderFieldsParse;
    [Test] procedure SamplesParse;
    [Test] procedure TextCofRaisesWithLine;
    [Test] procedure NanCofRaisesWithLine;
    [Test] procedure InfCofRaisesWithLine;
    [Test] procedure EmptyCofRaisesWithLine;
    [Test] procedure BadCycleRaisesWithLine;
    [Test] procedure EmptyColumnDoesNotBorrowNextColumn;
    [Test] procedure LineWithoutTabRaisesWithLine;
    [Test] procedure BlankFieldLineAndExponentParse;
    [Test] procedure DecreasingCycleRaises;
    [Test] procedure CycleResetRaises;
    [Test] procedure RepeatedCyclesKeepEverySample;
    [Test] procedure CommaDecimalSeparatorDoesNotChangeSamples;
    [Test] procedure NewFormatHeaderWithThreeFieldUnitsLineLoads;
    [Test] procedure NewFormatHeaderKeysParse;
    [Test] procedure NewFormatKeepsStrictRulesAfterFirstRow;
    [Test] procedure FileWithoutDataRowsRaises;
    [Test] procedure MalformedFirstRowIsNotSkipped;
    [Test] procedure MissingDataEntryRaises;
  end;

implementation

const
  NewHeaderText =
    'Cycles'#9'COF'#13#10' '#9' '#13#10'#'#9'kgF'#9'kgF'#13#10 +
    'Created:  2026-06-01T18:46:26'#13#10 +
    'Stroke: 10 [mm]     Speed: 30 [mm/sec]     Load: 1 [kgF]'#13#10 +
    'Cycles: 1000     Sampling interval: 20    Duration:  00:11:35'#13#10 +
    #13#10'Comment: '#13#10;
  HeaderText =
    'Stroke:'#9'12.5'#9'Speed:'#9'3.2'#9'Duration:'#9'100'#13#10 +
    'Load:'#9'1.5 kgf'#9'Cycles:'#9'1000'#9'Pause:'#9'2'#9'Sampling rate:'#9'50'#13#10 +
    'Cycles'#9'COF'#13#10;

function TZRWDataTests.Bytes(const Text: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(Text);
end;

function TZRWDataTests.Body(const Rows: array of string): string;
var
  Row: string;
begin
  Result := HeaderText;
  for Row in Rows do
    Result := Result + Row + #13#10;
end;

function TZRWDataTests.WriteArchive(const Name, Text: string): string;
var
  Zip: TZipFile;
  Data: TBytesStream;
begin
  Result := TPath.Combine(FDir, Name);
  Zip := TZipFile.Create;
  Data := TBytesStream.Create(Bytes(Text));
  try
    Zip.Open(Result, zmWrite);
    Zip.Add(Data, 'Data.dat');
    Zip.Close;
  finally
    Data.Free;
    Zip.Free;
  end;
end;

procedure TZRWDataTests.ExpectFormatError(const Text, LineMarker: string);
var
  Message: string;
begin
  Message := '';
  try
    ParseZRWData(Bytes(Text));
  except
    on E: EZRWFormatError do
      Message := E.Message;
  end;
  Assert.IsTrue(Message <> '', 'EZRWFormatError expected');
  Assert.IsTrue(Message.Contains(LineMarker), 'Message "' + Message + '" lacks ' + LineMarker);
end;

procedure TZRWDataTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_ZRW_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TZRWDataTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TZRWDataTests.ZrwAndZrvGiveSameSamples;
var
  A, B: TZRWCurve;
  I: Integer;
begin
  A := LoadZRWFile(WriteArchive('a.zrw', Body(['0'#9'0.10', '1'#9'0.20', '2'#9'0.30'])));
  B := LoadZRWFile(WriteArchive('a.zrv', Body(['0'#9'0.10', '1'#9'0.20', '2'#9'0.30'])));
  Assert.AreEqual<NativeInt>(3, Length(A.Samples));
  Assert.AreEqual(Length(A.Samples), Length(B.Samples));
  for I := 0 to High(A.Samples) do
  begin
    Assert.AreEqual(A.Samples[I].Cycle, B.Samples[I].Cycle, 0.0);
    Assert.AreEqual(A.Samples[I].COF, B.Samples[I].COF, 0.0);
  end;
end;

procedure TZRWDataTests.HeaderFieldsParse;
var
  C: TZRWCurve;
begin
  C := ParseZRWData(Bytes(Body(['0'#9'0.1'])));
  Assert.AreEqual('12.5', C.Header.Stroke);
  Assert.AreEqual('3.2', C.Header.Speed);
  Assert.AreEqual('1.5 kgf', C.Header.Load);
  Assert.AreEqual('1000', C.Header.Cycles);
  Assert.AreEqual('2', C.Header.Pause);
  Assert.AreEqual('50', C.Header.SamplingRate);
end;

procedure TZRWDataTests.SamplesParse;
var
  C: TZRWCurve;
begin
  C := ParseZRWData(Bytes(Body(['0.5'#9'0.125', '1.5'#9'-0.25'])));
  Assert.AreEqual<NativeInt>(2, Length(C.Samples));
  Assert.AreEqual(0.5, C.Samples[0].Cycle, 0.0);
  Assert.AreEqual(0.125, C.Samples[0].COF, 0.0);
  Assert.AreEqual(1.5, C.Samples[1].Cycle, 0.0);
  Assert.AreEqual(-0.25, C.Samples[1].COF, 0.0);
end;

procedure TZRWDataTests.TextCofRaisesWithLine;
begin
  ExpectFormatError(Body(['0'#9'0.1', '1'#9'abc']), 'line 5');
end;

procedure TZRWDataTests.NanCofRaisesWithLine;
begin
  ExpectFormatError(Body(['0'#9'0.1', '1'#9'NaN']), 'line 5');
end;

procedure TZRWDataTests.InfCofRaisesWithLine;
begin
  ExpectFormatError(Body(['0'#9'0.1', '1'#9'INF']), 'line 5');
end;

procedure TZRWDataTests.EmptyCofRaisesWithLine;
begin
  ExpectFormatError(Body(['0'#9'0.1', '1'#9]), 'Invalid COF value "" on line 5');
  ExpectFormatError(Body(['0'#9'0.1', '1'#9' ']), 'Invalid COF value "" on line 5');
end;

procedure TZRWDataTests.EmptyColumnDoesNotBorrowNextColumn;
begin
  ExpectFormatError(Body(['0'#9'0.1', '1'#9#9'0.2']), 'line 5');
end;

procedure TZRWDataTests.LineWithoutTabRaisesWithLine;
begin
  ExpectFormatError(Body(['0'#9'0.1', '1 0.2']), 'Expected two tab-separated columns on line 5');
end;

procedure TZRWDataTests.BlankFieldLineAndExponentParse;
var
  C: TZRWCurve;
begin
  C := ParseZRWData(Bytes('Cycles'#9'COF'#13#10' '#9' '#13#10#13#10 +
    'Stroke:'#9'5'#9'Speed:'#9'5'#13#10'Cycles:'#9'50000'#9'Pause:'#9'50'#13#10 +
    'Sampling rate:'#9#13#10'50.8900'#9'0.1190'#13#10'4.988E0004'#9'0.1353'#13#10));
  Assert.AreEqual<NativeInt>(2, Length(C.Samples));
  Assert.AreEqual(49880.0, C.Samples[1].Cycle, 0.0);
  Assert.AreEqual('', C.Header.SamplingRate);
  Assert.AreEqual('50000', C.Header.Cycles);
end;

procedure TZRWDataTests.BadCycleRaisesWithLine;
begin
  ExpectFormatError(Body(['0'#9'0.1', 'x'#9'0.2']), 'line 5');
end;

procedure TZRWDataTests.DecreasingCycleRaises;
begin
  ExpectFormatError(Body(['4'#9'0.1', '6'#9'0.2', '5'#9'0.3']), 'line 6');
end;

procedure TZRWDataTests.CycleResetRaises;
begin
  ExpectFormatError(Body(['9'#9'0.1', '10'#9'0.2', '0'#9'0.3']), 'line 6');
end;

procedure TZRWDataTests.RepeatedCyclesKeepEverySample;
var
  C: TZRWCurve;
begin
  C := ParseZRWData(Bytes(Body(['1'#9'0.1', '1'#9'0.2', '1'#9'0.3', '2'#9'0.4'])));
  Assert.AreEqual<NativeInt>(4, Length(C.Samples));
  Assert.AreEqual(0.2, C.Samples[1].COF, 0.0);
  Assert.AreEqual(0.3, C.Samples[2].COF, 0.0);
end;

procedure TZRWDataTests.CommaDecimalSeparatorDoesNotChangeSamples;
var
  Saved: Char;
  Before, After: TZRWCurve;
begin
  Before := ParseZRWData(Bytes(Body(['0.5'#9'0.125', '1.5'#9'0.25'])));
  Saved := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := ',';
  try
    After := ParseZRWData(Bytes(Body(['0.5'#9'0.125', '1.5'#9'0.25'])));
  finally
    FormatSettings.DecimalSeparator := Saved;
  end;
  Assert.AreEqual(Length(Before.Samples), Length(After.Samples));
  Assert.AreEqual(Before.Samples[0].Cycle, After.Samples[0].Cycle, 0.0);
  Assert.AreEqual(Before.Samples[0].COF, After.Samples[0].COF, 0.0);
  Assert.AreEqual(Before.Samples[1].COF, After.Samples[1].COF, 0.0);
end;

procedure TZRWDataTests.MissingDataEntryRaises;
var
  Zip: TZipFile;
  Data: TBytesStream;
  Path: string;
begin
  Path := TPath.Combine(FDir, 'x.zrw');
  Zip := TZipFile.Create;
  Data := TBytesStream.Create(Bytes('x'));
  try
    Zip.Open(Path, zmWrite);
    Zip.Add(Data, 'Other.dat');
    Zip.Close;
  finally
    Data.Free;
    Zip.Free;
  end;
  Assert.WillRaise(procedure begin LoadZRWFile(Path); end, EZRWFormatError);
end;

procedure TZRWDataTests.NewFormatHeaderWithThreeFieldUnitsLineLoads;
var
  C: TZRWCurve;
begin
  C := ParseZRWData(Bytes(NewHeaderText + '1.0000'#9'0.8475'#13#10 +
    '2.0000'#9'0.7000'#13#10));
  Assert.AreEqual<NativeInt>(2, Length(C.Samples));
  Assert.AreEqual(0.8475, C.Samples[0].COF, 0.0);
end;

procedure TZRWDataTests.NewFormatHeaderKeysParse;
var
  C: TZRWCurve;
begin
  C := ParseZRWData(Bytes(NewHeaderText + '1.0000'#9'0.8475'#13#10));
  Assert.AreEqual('10', C.Header.Stroke);
  Assert.AreEqual('30', C.Header.Speed);
  Assert.AreEqual('1 kgF', C.Header.Load);
  Assert.AreEqual('1000', C.Header.Cycles);
  Assert.AreEqual('20', C.Header.SamplingInterval);
  Assert.AreEqual('', C.Header.SamplingRate);
  Assert.AreEqual('', C.Header.Pause);
end;

procedure TZRWDataTests.NewFormatKeepsStrictRulesAfterFirstRow;
begin
  ExpectFormatError(NewHeaderText + '1'#9'0.5'#13#10 + '2'#9'0.5'#9'0.6'#13#10,
    'Expected two tab-separated columns on line 10');
  ExpectFormatError(NewHeaderText + '2'#9'0.5'#13#10 + '1'#9'0.5'#13#10, 'line 10');
end;

procedure TZRWDataTests.FileWithoutDataRowsRaises;
begin
  ExpectFormatError(NewHeaderText, 'No data rows');
end;

procedure TZRWDataTests.MalformedFirstRowIsNotSkipped;
begin
  ExpectFormatError(HeaderText + '1,5'#9'0.2'#13#10 + '2'#9'0.3'#13#10, 'on line 4');
  ExpectFormatError(NewHeaderText + '1,5'#9'0.2'#13#10 + '2'#9'0.3'#13#10, 'on line 9');
  ExpectFormatError(NewHeaderText + '1'#9'NaN'#13#10 + '2'#9'0.3'#13#10, 'on line 9');
  ExpectFormatError(NewHeaderText + '1'#9'INF'#13#10 + '2'#9'0.3'#13#10, 'on line 9');
  ExpectFormatError(NewHeaderText + '1 0.2'#13#10 + '2'#9'0.3'#13#10,
    'Expected two tab-separated columns on line 9');
  ExpectFormatError(NewHeaderText + '1'#9'0.2'#9#13#10 + '2'#9'0.3'#13#10,
    'Expected two tab-separated columns on line 9');
  ExpectFormatError(NewHeaderText + '1'#9'NaN'#13#10, 'on line 9');
end;

initialization
  TDUnitX.RegisterTestFixture(TZRWDataTests);

end.
