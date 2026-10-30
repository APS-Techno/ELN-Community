unit test_ZRWPackage;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  System.Math, System.JSON, System.Hash, unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ZRWData, unit_ZRWForce, unit_ZRWPackage, unit_ZRWPlateau, unit_ZRWViewerPlugin;

type
  [TestFixture]
  TZRWPackageTests = class
  private
    FDir: string;
    function ForceText(Cycles, RowsPerStroke: Integer; Complete: Boolean): string;
    function ManifestText(const Version, PlotColumn: string): string;
    function TsvText(const Header: string): string;
    function WritePackage(const Name: string; const Entries: array of string;
      const Force, Manifest, Tsv: string): string;
    function DefaultPackage(const Manifest: string = ''; const Tsv: string = ''): string;
    procedure ExpectError(const Path, Fragment: string);
    function ConstantTsv(Value: Double): string;
    function Context(Kind: TAnalysisContextKind; const Hash, Shared,
      Stored: string): TAnalysisContext;
    function ManualSelection(const Hash: string): string;
    function FindKey(const Keys: TArray<TPluginKeyValue>; const Name: string;
      out Key: TPluginKeyValue): Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ContainerIsChosenByEntryNames;
    [Test] procedure PackageGivesPerCycleCofFromForce;
    [Test] procedure ChannelIsNamedByPlotColumn;
    [Test] procedure ForceHeaderFeedsCurveHeader;
    [Test] procedure UnfinishedForceFileRecountsCycles;
    [Test] procedure BadLoggerRowsAreCountedNotStored;
    [Test] procedure CommaLocaleDoesNotChangeNumbers;
    [Test] procedure UnsupportedMajorVersionRaises;
    [Test] procedure PlotColumnMissingFromColumnsRaises;
    [Test] procedure TsvHeaderMustMatchManifest;
    [Test] procedure ShortForceFileRaises;
    [Test] procedure ChannelCurveAveragesReadingsInsideEachCycle;
    [Test] procedure ChannelMedianWindowCountsCyclesNotSamples;
    [Test] procedure ReaderKeyNameAsChannelRaises;
    [Test] procedure PluginEmitsChannelKeysOverTheSelectedCycles;
    [Test] procedure ChannelSnapshotNamesItsKeyAndForceAlgorithm;
    [Test] procedure StoredSnapshotReproducesChannelMean;
  end;

implementation

const
  LoggerRows = 40;

function TZRWPackageTests.ForceText(Cycles, RowsPerStroke: Integer;
  Complete: Boolean): string;
var
  I, Total: Integer;
  Fl: Double;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[APS Tribo V3.0]'#13#10 +
      '{'#13#10 +
      '  "test": {"stroke_mm": 5.0, "speed_mm_per_s": 20.0, "load": 1.0,'#13#10 +
      '    "cycles": ').Append(Cycles).Append(', "comment": ""},'#13#10 +
      '  "sampling": {"rate_hz": 20, "interval_ms": 50},'#13#10 +
      '  "channels": [{"role": "normal", "unit": "kgF"}]'#13#10 +
      '}'#13#10 +
      '[DATA]'#13#10 +
      'Readout'#9'F(Norm)'#9'F(Lat)'#13#10 +
      '#'#9'kgF'#9'kgF'#13#10);
    Total := 2 * Cycles * RowsPerStroke;
    for I := 0 to Total - 1 do
    begin
      if (I div RowsPerStroke) mod 2 = 0 then
        Fl := 0.3
      else
        Fl := -0.3;
      SB.Append(I).Append(#9'1.0'#9).Append(FloatToStr(Fl, TFormatSettings.Invariant))
        .Append(#13#10);
    end;
    if Complete then
      SB.Append('Complete in 00:00:10')
    else
      SB.Append('Interrupted');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TZRWPackageTests.ManifestText(const Version, PlotColumn: string): string;
begin
  Result :=
    '{"format":"APS Tribo Package","format_version":"' + Version + '",' +
    '"status":"completed","stop_reason":null,' +
    '"clock":{"daq_rate_hz":1612.9,"samples_per_readout":20,"first_sample":0,' +
    '"readouts_written":2000,"gaps":[{"row":10,"missing_samples":4},{"row":5,"missing_samples":2}]},' +
    '"data_logger":{"idn":"TH2690","columns":["R","state"],"units":["Ohm","text"],' +
    '"plot_column":"' + PlotColumn + '"}}';
end;

function TZRWPackageTests.TsvText(const Header: string): string;
var
  I: Integer;
begin
  Result := Header + #13#10 + 's'#9's'#9'Ohm'#9'text'#13#10;
  for I := 0 to LoggerRows - 1 do
    Result := Result + Format('%d.500000'#9'0.002000'#9'%d.25'#9'ok'#13#10, [I, 20 + I]);
end;

function TZRWPackageTests.WritePackage(const Name: string;
  const Entries: array of string; const Force, Manifest, Tsv: string): string;
var
  Zip: TZipFile;
  Bytes: TBytes;
  I: Integer;
begin
  Result := TPath.Combine(FDir, Name);
  Zip := TZipFile.Create;
  try
    Zip.Open(Result, zmWrite);
    for I := 0 to High(Entries) do
    begin
      if SameText(Entries[I], 'force.raw') then
        Bytes := TEncoding.UTF8.GetBytes(Force)
      else if SameText(Entries[I], 'test.json') then
        Bytes := TEncoding.UTF8.GetBytes(Manifest)
      else if SameText(Entries[I], 'resistance.tsv') then
        Bytes := TEncoding.UTF8.GetBytes(Tsv)
      else
        Bytes := TEncoding.UTF8.GetBytes('x');
      Zip.Add(Bytes, Entries[I]);
    end;
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

function TZRWPackageTests.DefaultPackage(const Manifest, Tsv: string): string;
var
  M, T: string;
begin
  M := Manifest;
  if M = '' then
    M := ManifestText('1.0', 'R');
  T := Tsv;
  if T = '' then
    T := TsvText('t_s'#9'dt_s'#9'R'#9'state');
  Result := WritePackage(TGUID.NewGuid.ToString + '.zrw',
    ['force.raw', 'resistance.tsv', 'test.json'], ForceText(20, 50, True), M, T);
end;

procedure TZRWPackageTests.ExpectError(const Path, Fragment: string);
var
  Message: string;
begin
  Message := '';
  try
    LoadZRWPackage(Path);
  except
    on E: EZRWFormatError do
      Message := E.Message;
  end;
  Assert.IsTrue(Message.Contains(Fragment), 'Message "' + Message + '" lacks ' + Fragment);
end;

procedure TZRWPackageTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_ZRWPkg_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TZRWPackageTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TZRWPackageTests.ContainerIsChosenByEntryNames;
begin
  Assert.AreEqual(Ord(zcPackage), Ord(DetectZRWContainer(DefaultPackage)));
  Assert.AreEqual(Ord(zcPackage), Ord(DetectZRWContainer(WritePackage('up.zrw',
    ['FORCE.RAW', 'Resistance.TSV', 'TEST.JSON'], '', '', ''))));
  Assert.AreEqual(Ord(zcLegacy), Ord(DetectZRWContainer(WritePackage('old.zrw',
    ['Data.raw', 'Data.dat'], '', '', ''))));
  Assert.AreEqual(Ord(zcUnknown), Ord(DetectZRWContainer(WritePackage('part.zrw',
    ['force.raw', 'test.json'], '', '', ''))));
end;

procedure TZRWPackageTests.PackageGivesPerCycleCofFromForce;
var
  P: TZRWPackage;
  S: TZRWSample;
  I: Integer;
begin
  P := LoadZRWPackage(DefaultPackage);
  Assert.AreEqual<NativeInt>(19, Length(P.Curve.Samples));
  for I := 0 to High(P.Curve.Samples) do
  begin
    S := P.Curve.Samples[I];
    Assert.AreEqual(Double(I + 1), S.Cycle, 0.0);
    Assert.AreEqual(0.3, S.COF, 0.01);
  end;
  Assert.AreEqual<NativeInt>(2000, Length(P.Force.Fn));
end;

procedure TZRWPackageTests.ChannelIsNamedByPlotColumn;
var
  P: TZRWPackage;
begin
  P := LoadZRWPackage(DefaultPackage);
  Assert.AreEqual('R', P.Channel.Name);
  Assert.AreEqual('Ohm', P.Channel.Units);
  Assert.AreEqual('TH2690', P.Channel.Idn);
  Assert.AreEqual<NativeInt>(LoggerRows, Length(P.Channel.Value));
  Assert.AreEqual(20.25, P.Channel.Value[0], 1e-9);
  Assert.AreEqual(1.5, P.Channel.Time[1], 1e-9);
  Assert.AreEqual<NativeInt>(2, Length(P.Clock.Gaps));
  Assert.AreEqual<Int64>(5, P.Clock.Gaps[0].Row, 'Gaps are sorted by row');
end;

procedure TZRWPackageTests.ForceHeaderFeedsCurveHeader;
var
  P: TZRWPackage;
begin
  P := LoadZRWPackage(DefaultPackage);
  Assert.AreEqual('5', P.Curve.Header.Stroke);
  Assert.AreEqual('20', P.Curve.Header.Speed);
  Assert.AreEqual('1 kgF', P.Curve.Header.Load);
  Assert.AreEqual('20', P.Curve.Header.Cycles);
end;

procedure TZRWPackageTests.UnfinishedForceFileRecountsCycles;
var
  F: TZRWForce;
begin
  F := ParseForceRaw(TEncoding.UTF8.GetBytes(ForceText(20, 50, False)));
  Assert.IsTrue(F.Incomplete);
  Assert.IsTrue(F.Cycles <> 20, 'Cycle count is taken from the data, not the header');
  Assert.IsTrue(F.Cycles > 0);
end;

procedure TZRWPackageTests.BadLoggerRowsAreCountedNotStored;
var
  Tsv: string;
  P: TZRWPackage;
begin
  Tsv := TsvText('t_s'#9'dt_s'#9'R'#9'state') + 'oops'#9'0.1'#9'1'#9'ok'#13#10 +
    '1.0'#9'0.1'#9'abc'#9'ok'#13#10 + '1.0'#9'0.1'#13#10;
  P := LoadZRWPackage(DefaultPackage('', Tsv));
  Assert.AreEqual(3, P.Channel.BadRows);
  Assert.AreEqual<NativeInt>(LoggerRows, Length(P.Channel.Value));
end;

procedure TZRWPackageTests.CommaLocaleDoesNotChangeNumbers;
var
  Saved: Char;
  P: TZRWPackage;
begin
  Saved := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := ',';
  try
    P := LoadZRWPackage(DefaultPackage);
  finally
    FormatSettings.DecimalSeparator := Saved;
  end;
  Assert.AreEqual(1.5, P.Channel.Time[1], 1e-9);
  Assert.AreEqual(0.3, P.Curve.Samples[0].COF, 0.01);
end;

procedure TZRWPackageTests.UnsupportedMajorVersionRaises;
begin
  ExpectError(DefaultPackage(ManifestText('2.0', 'R')), 'Unsupported package format');
end;

procedure TZRWPackageTests.PlotColumnMissingFromColumnsRaises;
begin
  ExpectError(DefaultPackage(ManifestText('1.0', 'X')), 'plot_column X');
  ExpectError(DefaultPackage(ManifestText('1.0', 'state')), 'not numeric');
end;

procedure TZRWPackageTests.TsvHeaderMustMatchManifest;
begin
  ExpectError(DefaultPackage('', TsvText('t_s'#9'dt_s'#9'Q'#9'state')),
    'header does not match');
end;

procedure TZRWPackageTests.ShortForceFileRaises;
var
  Path: string;
begin
  Path := WritePackage('short.zrw', ['force.raw', 'resistance.tsv', 'test.json'],
    ForceText(1, 2, True), ManifestText('1.0', 'R'), TsvText('t_s'#9'dt_s'#9'R'#9'state'));
  ExpectError(Path, 'data rows');
end;

function TZRWPackageTests.ConstantTsv(Value: Double): string;
var
  I: Integer;
begin
  Result := 't_s'#9'dt_s'#9'R'#9'state'#13#10's'#9's'#9'Ohm'#9'text'#13#10;
  for I := 1 to 300 do
    Result := Result + Format('%.6f'#9'0.002000'#9'%.6f'#9'ok'#13#10,
      [I * 0.1, Value], TFormatSettings.Invariant);
end;

function TZRWPackageTests.Context(Kind: TAnalysisContextKind; const Hash, Shared,
  Stored: string): TAnalysisContext;
begin
  Result := Default(TAnalysisContext);
  Result.Kind := Kind;
  Result.FileId := 17;
  Result.FileHash := Hash;
  Result.SharedSelection := Shared;
  Result.StoredSnapshot := Stored;
end;

function TZRWPackageTests.ManualSelection(const Hash: string): string;
var
  S: TZRWSelection;
begin
  S := Default(TZRWSelection);
  S.Mode := zsmManual;
  S.Interval.StartCycle := 2;
  S.Interval.EndCycle := 10;
  S.Interval.ThroughEnd := True;
  S.ReaderVersion := '2';
  S.AlgorithmVersion := '3';
  S.FileHash := Hash;
  S.ApplyId := 'apply-1';
  S.AppliedAt := '2026-01-02T03:04:05Z';
  S.AppliedBy := 1;
  S.Revision := 1;
  Result := SelectionToJson(S);
end;

function TZRWPackageTests.FindKey(const Keys: TArray<TPluginKeyValue>;
  const Name: string; out Key: TPluginKeyValue): Boolean;
var
  Item: TPluginKeyValue;
begin
  for Item in Keys do
    if Item.Name = Name then
    begin
      Key := Item;
      Exit(True);
    end;
  Result := False;
end;

procedure TZRWPackageTests.ChannelCurveAveragesReadingsInsideEachCycle;
var
  P: TZRWPackage;
begin
  P := LoadZRWPackage(DefaultPackage);
  Assert.AreEqual(1.0, P.ChannelCurve.Samples[0].Cycle, 0.0);
  Assert.AreEqual(21.25, P.ChannelCurve.Samples[0].COF, 1e-9,
    'Cycle 1 spans readouts 50 to 149; only the reading at 1.5 s falls there');
end;

procedure TZRWPackageTests.ChannelMedianWindowCountsCyclesNotSamples;
const
  Cycles: array[0..5] of Double = (1, 2, 3, 4, 10, 11);
  Values: array[0..5] of Double = (1, 100, 2, 3, 40, 50);
var
  Curve, Smooth: TZRWCurve;
  I: Integer;
begin
  SetLength(Curve.Samples, Length(Cycles));
  for I := 0 to High(Cycles) do
  begin
    Curve.Samples[I].Cycle := Cycles[I];
    Curve.Samples[I].COF := Values[I];
  end;
  Smooth := MovingMedian(Curve, 3);
  Assert.AreEqual(50.5, Smooth.Samples[0].COF, 1e-12, 'The first window holds cycles 1 and 2');
  Assert.AreEqual(2.0, Smooth.Samples[1].COF, 1e-12, 'A one-cycle spike is removed');
  Assert.AreEqual(3.0, Smooth.Samples[2].COF, 1e-12);
  Assert.AreEqual(2.5, Smooth.Samples[3].COF, 1e-12, 'Cycle 10 is outside the window of cycle 4');
  Assert.AreEqual(45.0, Smooth.Samples[4].COF, 1e-12);
  Assert.AreEqual(100.0, Curve.Samples[1].COF, 0.0, 'The source curve is unchanged');
  Assert.AreEqual(100.0, MovingMedian(Curve, 1).Samples[1].COF, 0.0);
end;

procedure TZRWPackageTests.ReaderKeyNameAsChannelRaises;
var
  Manifest: string;
begin
  Manifest := ManifestText('1.0', 'R').Replace('"columns":["R","state"]',
    '"columns":["COF","state"]').Replace('"plot_column":"R"', '"plot_column":"COF"');
  ExpectError(DefaultPackage(Manifest,
    TsvText('t_s'#9'dt_s'#9'COF'#9'state')), 'collides with a reader key');
end;

procedure TZRWPackageTests.PluginEmitsChannelKeysOverTheSelectedCycles;
var
  Plugin: TELNZRWViewerPlugin;
  Path, Hash: string;
  Keys: TArray<TPluginKeyValue>;
  Value, Std, Cof: TPluginKeyValue;
begin
  Path := DefaultPackage('', ConstantTsv(5));
  Hash := UpperCase(THashMD5.GetHashStringFromFile(Path));
  Plugin := TELNZRWViewerPlugin.Create(nil);
  try
    Assert.IsTrue(Plugin.LoadFromFile(Path), Plugin.GetLoadError);
    Plugin.SetAnalysisContext(Context(ackCurrent, Hash, ManualSelection(Hash), ''));
    Keys := Plugin.GetKeyValues;
    Assert.IsTrue(FindKey(Keys, 'COF', Cof));
    Assert.IsTrue(FindKey(Keys, 'R', Value), 'Channel key is named after the plot column');
    Assert.IsTrue(FindKey(Keys, 'R STD', Std));
    Assert.AreEqual(5.0, Value.Value, 1e-9);
    Assert.AreEqual(0.0, Std.Value, 1e-9);
    Assert.AreEqual('Ohm', Value.Units);
    Assert.AreEqual('Ohm', Std.Units);
    Assert.IsTrue(Value.IsKey);
    Assert.IsFalse(Std.IsKey);
    Assert.IsTrue(Value.RecType = prResult);
    Assert.AreEqual(0.3, Cof.Value, 0.01);
    Assert.IsTrue(Value.Description.Contains('manual selection'));
  finally
    Plugin.Free;
  end;
end;

procedure TZRWPackageTests.ChannelSnapshotNamesItsKeyAndForceAlgorithm;
var
  Plugin: TELNZRWViewerPlugin;
  Path, Hash, Key: string;
  Snapshot: TJSONObject;
begin
  Path := DefaultPackage('', ConstantTsv(5));
  Hash := UpperCase(THashMD5.GetHashStringFromFile(Path));
  Plugin := TELNZRWViewerPlugin.Create(nil);
  try
    Assert.IsTrue(Plugin.LoadFromFile(Path), Plugin.GetLoadError);
    Plugin.SetAnalysisContext(Context(ackCurrent, Hash, ManualSelection(Hash), ''));
    Assert.AreEqual(Plugin.GetAnalysisSnapshot('R'), Plugin.GetAnalysisSnapshot('R STD'));
    for Key in ['COF', 'R'] do
    begin
      Snapshot := TJSONObject.ParseJSONValue(Plugin.GetAnalysisSnapshot(Key)) as TJSONObject;
      try
        Assert.AreEqual(Key, Snapshot.GetValue<string>('key_name'));
        Assert.AreEqual('1', Snapshot.GetValue<string>('force_algorithm'));
        Assert.AreEqual('manual', Snapshot.GetValue<string>('mode'));
      finally
        Snapshot.Free;
      end;
    end;
    Assert.AreEqual('', Plugin.GetAnalysisSnapshot('Fn'));
  finally
    Plugin.Free;
  end;
end;

procedure TZRWPackageTests.StoredSnapshotReproducesChannelMean;
var
  Plugin: TELNZRWViewerPlugin;
  Path, Hash, Stored: string;
  Value: TPluginKeyValue;
begin
  Path := DefaultPackage('', ConstantTsv(7.5));
  Hash := UpperCase(THashMD5.GetHashStringFromFile(Path));
  Plugin := TELNZRWViewerPlugin.Create(nil);
  try
    Assert.IsTrue(Plugin.LoadFromFile(Path), Plugin.GetLoadError);
    Plugin.SetAnalysisContext(Context(ackCurrent, Hash, ManualSelection(Hash), ''));
    Stored := Plugin.GetAnalysisSnapshot('R');
    Plugin.SetAnalysisContext(Context(ackStoredSnapshot, Hash, '', Stored));
    Assert.IsTrue(FindKey(Plugin.GetKeyValues, 'R', Value));
    Assert.AreEqual(7.5, Value.Value, 1e-9);
  finally
    Plugin.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TZRWPackageTests);

end.
