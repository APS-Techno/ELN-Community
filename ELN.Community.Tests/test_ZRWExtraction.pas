unit test_ZRWExtraction;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils,
  System.JSON, System.Zip, System.Hash, unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ZRWPlateau, unit_ZRWViewerPlugin, unit_ValueDrift;

procedure WriteSyntheticZrw(const FileName: string; Plateau: Boolean = True);
procedure WriteMalformedZrw(const FileName: string);
procedure WriteCommaDecimalZrw(const FileName: string);
function SyntheticZrwBytes(Plateau: Boolean = True): TBytes;
function ShortZrwBytes(Count: Integer): TBytes;
function MalformedZrwBytes: TBytes;

type
  [TestFixture]
  TZRWExtractionTests = class
  private
    FDir: string;
    FPath: string;
    FPlugin: TELNZRWViewerPlugin;
    FHash: string;
    function Context(const SharedSelection: string): TAnalysisContext;
    function Selection(Mode: TZRWSelectionMode; Start, Stop: Double;
      ThroughEnd: Boolean; const FileHash: string): string;
    function Keys: TArray<TPluginKeyValue>;
    function Find(const Keys: TArray<TPluginKeyValue>; const Name: string;
      out Value: TPluginKeyValue): Boolean;
    function Provider: IAnalysisKeyValueProvider;
    procedure Load(const Path: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure NoSharedSelectionUsesDetectorWithAutomaticSnapshot;
    [Test] procedure AppliedManualSelectionUsesItsBoundsAndSharedRevision;
    [Test] procedure AppliedAutomaticSelectionKeepsItsStoredInterval;
    [Test] procedure StaleSelectionOmitsCofKeysWithStatus;
    [Test] procedure NoPlateauOmitsCofKeysWithStatus;
    [Test] procedure UnusableIntervalOmitsCofKeysWithStatus;
    [Test] procedure StoredSnapshotContextReproducesTheStoredInterval;
    [Test] procedure ReloadingTheFileResetsTheContext;
    [Test] procedure HeaderKeysAreUnchanged;
    [Test] procedure FailedLoadExposesLineNumberedMessageAndNextLoadClearsIt;
    [Test] procedure NewFormatFileLoadsAndExposesHeaderKeys;
    [Test] procedure DriftIntervalStatusMatchesPluginCoreStatus;
  end;

implementation

const
  HeaderText =
    'Stroke:'#9'12.5'#9'Speed:'#9'3.2'#9'Duration:'#9'100'#13#10 +
    'Load:'#9'1.5 kgf'#9'Cycles:'#9'1000'#9'Pause:'#9'2'#9'Sampling rate:'#9'50'#13#10 +
    'Cycles'#9'COF'#13#10;
  OtherHash = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';

function ZipDataBytes(const Text: string): TBytes;
var
  Zip: TZipFile;
  Data: TBytesStream;
  Path: string;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'ELN_ZRWBytes_' + TGUID.NewGuid.ToString);
  Zip := TZipFile.Create;
  Data := TBytesStream.Create(TEncoding.UTF8.GetBytes(Text));
  try
    Zip.Open(Path, zmWrite);
    Zip.Add(Data, 'Data.dat');
    Zip.Close;
    Result := TFile.ReadAllBytes(Path);
  finally
    Data.Free;
    Zip.Free;
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

function SyntheticZrwBytes(Plateau: Boolean): TBytes;
var
  Text: string;
  I: Integer;
  Cof: Double;
begin
  Text := HeaderText;
  for I := 0 to 99 do
  begin
    if Plateau then
      Cof := 0.4 + 0.0002 * I
    else if Odd(I) then
      Cof := 0.9
    else
      Cof := 0.1;
    Text := Text + IntToStr(I) + #9 +
      FloatToStr(Cof, TFormatSettings.Invariant) + #13#10;
  end;
  Result := ZipDataBytes(Text);
end;

function ShortZrwBytes(Count: Integer): TBytes;
var
  Text: string;
  I: Integer;
begin
  Text := HeaderText;
  for I := 0 to Count - 1 do
    Text := Text + IntToStr(I) + #9 +
      FloatToStr(0.4 + 0.0002 * I, TFormatSettings.Invariant) + #13#10;
  Result := ZipDataBytes(Text);
end;

function MalformedZrwBytes: TBytes;
begin
  Result := ZipDataBytes(HeaderText + '0'#9'0.4'#13#10 + '1'#9'abc'#13#10);
end;

procedure WriteSyntheticZrw(const FileName: string; Plateau: Boolean);
begin
  TFile.WriteAllBytes(FileName, SyntheticZrwBytes(Plateau));
end;

procedure WriteMalformedZrw(const FileName: string);
begin
  TFile.WriteAllBytes(FileName, MalformedZrwBytes);
end;

procedure WriteCommaDecimalZrw(const FileName: string);
begin
  TFile.WriteAllBytes(FileName, ZipDataBytes(HeaderText + '0'#9'0,4'#13#10 +
    '1'#9'0,5'#13#10));
end;

procedure TZRWExtractionTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_ZRWExtraction_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FPlugin := TELNZRWViewerPlugin.Create(nil);
  FPath := TPath.Combine(FDir, 'plateau.zrw');
  WriteSyntheticZrw(FPath);
  Load(FPath);
end;

procedure TZRWExtractionTests.TearDown;
begin
  FPlugin.Free;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TZRWExtractionTests.Load(const Path: string);
begin
  Assert.IsTrue(FPlugin.LoadFromFile(Path));
  FHash := UpperCase(THashMD5.GetHashStringFromFile(Path));
end;

function TZRWExtractionTests.Provider: IAnalysisKeyValueProvider;
begin
  Assert.IsTrue(Supports(FPlugin, IAnalysisKeyValueProvider, Result),
    'The ZRW reader must implement IAnalysisKeyValueProvider');
end;

function TZRWExtractionTests.Context(const SharedSelection: string): TAnalysisContext;
begin
  Result := Default(TAnalysisContext);
  Result.Kind := ackCurrent;
  Result.FileId := 17;
  Result.FileHash := FHash;
  Result.SharedSelection := SharedSelection;
end;

function TZRWExtractionTests.Selection(Mode: TZRWSelectionMode; Start,
  Stop: Double; ThroughEnd: Boolean; const FileHash: string): string;
var
  S: TZRWSelection;
begin
  S := Default(TZRWSelection);
  S.Mode := Mode;
  S.Interval.StartCycle := Start;
  S.Interval.EndCycle := Stop;
  S.Interval.ThroughEnd := ThroughEnd;
  S.ReaderVersion := '2';
  S.AlgorithmVersion := '1';
  S.FileHash := FileHash;
  S.ApplyId := 'apply-7';
  S.AppliedAt := '2026-01-02T03:04:05Z';
  S.AppliedBy := 1;
  S.Revision := 3;
  Result := SelectionToJson(S);
end;

function TZRWExtractionTests.Keys: TArray<TPluginKeyValue>;
begin
  Result := (FPlugin as IKeyValueProvider).GetKeyValues;
end;

function TZRWExtractionTests.Find(const Keys: TArray<TPluginKeyValue>;
  const Name: string; out Value: TPluginKeyValue): Boolean;
var
  Key: TPluginKeyValue;
begin
  for Key in Keys do
    if Key.Name = Name then
    begin
      Value := Key;
      Exit(True);
    end;
  Result := False;
end;

procedure TZRWExtractionTests.NoSharedSelectionUsesDetectorWithAutomaticSnapshot;
var
  Values: TArray<TPluginKeyValue>;
  Cof, Std: TPluginKeyValue;
  Snapshot: TJSONObject;
  Stored: string;
begin
  Provider.SetAnalysisContext(Context(''));
  Values := Keys;
  Assert.IsTrue(Find(Values, 'COF', Cof), 'COF is emitted');
  Assert.IsTrue(Find(Values, 'COF STD', Std), 'COF STD is emitted');
  Assert.IsTrue(Cof.IsKey);
  Assert.IsFalse(Std.IsKey);
  Assert.IsTrue(Cof.RecType = prResult);
  Assert.IsTrue(Std.RecType = prResult);
  Assert.AreEqual('', Cof.Units);
  Assert.AreEqual('', Std.Units);
  Assert.AreEqual('Mean friction coefficient, cycles 0' + #$2013 +
    '99 (automatic plateau)', Cof.Description);
  Assert.AreEqual(0.4 + 0.0002 * 49.5, Cof.Value, 1e-9);
  Assert.IsTrue(Std.Value > 0);
  Assert.AreEqual('', Provider.GetAnalysisStatus);
  Stored := Provider.GetAnalysisSnapshot('COF');
  Assert.AreEqual(Stored, Provider.GetAnalysisSnapshot('COF STD'));
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('Fn'));
  Assert.IsTrue(Length(Stored) <= 2000);
  Snapshot := TJSONObject.ParseJSONValue(Stored) as TJSONObject;
  try
    Assert.AreEqual('aps.zrw', Snapshot.GetValue<string>('reader_id'));
    Assert.AreEqual('2', Snapshot.GetValue<string>('reader_version'));
    Assert.AreEqual('3', Snapshot.GetValue<string>('algorithm_version'));
    Assert.AreEqual(1, Snapshot.GetValue<Integer>('schema_version'));
    Assert.AreEqual<Double>(0.2, Snapshot.GetValue<Double>('min_duration'));
    Assert.AreEqual<Double>(0.3, Snapshot.GetValue<Double>('band'));
    Assert.AreEqual<Double>(0.95, Snapshot.GetValue<Double>('coverage'));
    Assert.AreEqual<Double>(0.05, Snapshot.GetValue<Double>('window'));
    Assert.AreEqual<Double>(0.5, Snapshot.GetValue<Double>('truncation'));
    Assert.AreEqual<Double>(0.1, Snapshot.GetValue<Double>('local_window'));
    Assert.AreEqual<NativeInt>(18, Snapshot.Count, 'Automatic snapshot key list');
    Assert.AreEqual('COF', Snapshot.GetValue<string>('key_name'));
    Assert.AreEqual<Int64>(17, Snapshot.GetValue<Int64>('file_id'));
    Assert.AreEqual(FHash, Snapshot.GetValue<string>('file_hash'));
    Assert.AreEqual('automatic', Snapshot.GetValue<string>('mode'));
    Assert.AreEqual<Double>(0, Snapshot.GetValue<Double>('start'));
    Assert.AreEqual<Double>(99, Snapshot.GetValue<Double>('end'));
    Assert.IsTrue(Snapshot.GetValue<Boolean>('through_end'));
    Assert.AreEqual(100, Snapshot.GetValue<Integer>('count'));
    Assert.IsNull(Snapshot.FindValue('shared_revision'));
    Assert.IsNull(Snapshot.FindValue('shared_apply_id'));
    Assert.IsNull(Snapshot.FindValue('value_id'));
  finally
    Snapshot.Free;
  end;
end;

procedure TZRWExtractionTests.AppliedManualSelectionUsesItsBoundsAndSharedRevision;
var
  Cof: TPluginKeyValue;
  Snapshot: TJSONObject;
begin
  Provider.SetAnalysisContext(Context(Selection(zsmManual, 20, 60, False, FHash)));
  Assert.IsTrue(Find(Keys, 'COF', Cof));
  Assert.AreEqual(0.4 + 0.0002 * 39.5, Cof.Value, 1e-9);
  Assert.AreEqual('Mean friction coefficient, cycles 20' + #$2013 +
    '60 (manual selection)', Cof.Description);
  Snapshot := TJSONObject.ParseJSONValue(Provider.GetAnalysisSnapshot('COF')) as TJSONObject;
  try
    Assert.AreEqual('manual', Snapshot.GetValue<string>('mode'));
    Assert.AreEqual(1, Snapshot.GetValue<Integer>('schema_version'));
    Assert.IsNull(Snapshot.FindValue('band'));
    Assert.AreEqual<NativeInt>(14, Snapshot.Count, 'Manual snapshot key list');
    Assert.AreEqual<Double>(20, Snapshot.GetValue<Double>('start'));
    Assert.AreEqual<Double>(60, Snapshot.GetValue<Double>('end'));
    Assert.IsFalse(Snapshot.GetValue<Boolean>('through_end'));
    Assert.AreEqual(40, Snapshot.GetValue<Integer>('count'));
    Assert.AreEqual(3, Snapshot.GetValue<Integer>('shared_revision'));
    Assert.AreEqual('apply-7', Snapshot.GetValue<string>('shared_apply_id'));
  finally
    Snapshot.Free;
  end;
end;

procedure TZRWExtractionTests.AppliedAutomaticSelectionKeepsItsStoredInterval;
var
  Cof: TPluginKeyValue;
  Snapshot: TJSONObject;
begin
  Provider.SetAnalysisContext(Context(Selection(zsmAutomatic, 10, 50, False, FHash)));
  Assert.IsTrue(Find(Keys, 'COF', Cof));
  Assert.AreEqual(0.4 + 0.0002 * 29.5, Cof.Value, 1e-9);
  Assert.IsTrue(Pos('(automatic plateau)', Cof.Description) > 0);
  Snapshot := TJSONObject.ParseJSONValue(Provider.GetAnalysisSnapshot('COF')) as TJSONObject;
  try
    Assert.AreEqual('automatic', Snapshot.GetValue<string>('mode'));
    Assert.AreEqual<Double>(10, Snapshot.GetValue<Double>('start'));
    Assert.AreEqual(3, Snapshot.GetValue<Integer>('shared_revision'));
  finally
    Snapshot.Free;
  end;
end;

procedure TZRWExtractionTests.StaleSelectionOmitsCofKeysWithStatus;
var
  Values: TArray<TPluginKeyValue>;
  Unused: TPluginKeyValue;
begin
  Provider.SetAnalysisContext(Context(Selection(zsmManual, 20, 60, False, OtherHash)));
  Values := Keys;
  Assert.IsFalse(Find(Values, 'COF', Unused));
  Assert.IsFalse(Find(Values, 'COF STD', Unused));
  Assert.IsTrue(Find(Values, 'Fn', Unused), 'Header keys remain');
  Assert.AreEqual('stale_selection', Provider.GetAnalysisStatus);
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('COF'));
end;

procedure TZRWExtractionTests.NoPlateauOmitsCofKeysWithStatus;
var
  Values: TArray<TPluginKeyValue>;
  Unused: TPluginKeyValue;
begin
  FPath := TPath.Combine(FDir, 'noisy.zrw');
  WriteSyntheticZrw(FPath, False);
  Load(FPath);
  Provider.SetAnalysisContext(Context(''));
  Values := Keys;
  Assert.IsFalse(Find(Values, 'COF', Unused));
  Assert.IsFalse(Find(Values, 'COF STD', Unused));
  Assert.AreEqual('no_plateau', Provider.GetAnalysisStatus);
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('COF'));
end;

procedure TZRWExtractionTests.UnusableIntervalOmitsCofKeysWithStatus;
var
  Unused: TPluginKeyValue;
begin
  Provider.SetAnalysisContext(Context(Selection(zsmManual, 500, 600, False, FHash)));
  Assert.IsFalse(Find(Keys, 'COF', Unused));
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
  Provider.SetAnalysisContext(Context('{"mode":'));
  Assert.IsFalse(Find(Keys, 'COF', Unused));
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
  Provider.SetAnalysisContext(Context(StringReplace(
    Selection(zsmManual, 20, 60, False, FHash), '"schema_version":1',
    '"schema_version":2', [])));
  Assert.IsFalse(Find(Keys, 'COF', Unused));
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
end;

procedure TZRWExtractionTests.StoredSnapshotContextReproducesTheStoredInterval;
var
  Original, Replayed: TPluginKeyValue;
  Stored: string;
  Replay: TAnalysisContext;
  Snapshot: TJSONObject;
begin
  Provider.SetAnalysisContext(Context(Selection(zsmManual, 20, 60, False, FHash)));
  Assert.IsTrue(Find(Keys, 'COF', Original));
  Stored := Provider.GetAnalysisSnapshot('COF');
  Replay := Default(TAnalysisContext);
  Replay.Kind := ackStoredSnapshot;
  Replay.FileId := 17;
  Replay.FileHash := FHash;
  Replay.StoredSnapshot := Stored;
  Provider.SetAnalysisContext(Replay);
  Assert.IsTrue(Find(Keys, 'COF', Replayed));
  Assert.AreEqual(Original.Value, Replayed.Value, 0.0);
  Assert.AreEqual('', Provider.GetAnalysisStatus);
  Snapshot := TJSONObject.ParseJSONValue(Provider.GetAnalysisSnapshot('COF')) as TJSONObject;
  try
    Assert.AreEqual('manual', Snapshot.GetValue<string>('mode'));
    Assert.AreEqual(3, Snapshot.GetValue<Integer>('shared_revision'));
  finally
    Snapshot.Free;
  end;
  Replay.StoredSnapshot := 'not json';
  Provider.SetAnalysisContext(Replay);
  Assert.IsFalse(Find(Keys, 'COF', Replayed));
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
end;

procedure TZRWExtractionTests.ReloadingTheFileResetsTheContext;
var
  Cof: TPluginKeyValue;
begin
  Provider.SetAnalysisContext(Context(Selection(zsmManual, 20, 60, False, OtherHash)));
  Assert.IsFalse(Find(Keys, 'COF', Cof));
  Load(FPath);
  Assert.IsTrue(Find(Keys, 'COF', Cof), 'A reload must not keep the previous file context');
  Assert.AreEqual('', Provider.GetAnalysisStatus);
end;

procedure TZRWExtractionTests.HeaderKeysAreUnchanged;
var
  Values: TArray<TPluginKeyValue>;
  Names: string;
  I: Integer;
begin
  Provider.SetAnalysisContext(Context(''));
  Values := Keys;
  Names := '';
  for I := 0 to High(Values) do
    Names := Names + Values[I].Name + '|';
  Assert.AreEqual('Fn|Cycles|Stroke|Speed|Sampling Rate|COF|COF STD|', Names);
end;

procedure TZRWExtractionTests.NewFormatFileLoadsAndExposesHeaderKeys;
var
  Text, Names: string;
  I: Integer;
  Values: TArray<TPluginKeyValue>;
  Fn, Stroke, Speed, Cycles, Interval, Cof: TPluginKeyValue;
begin
  Text := 'Cycles'#9'COF'#13#10' '#9' '#13#10'#'#9'kgF'#9'kgF'#13#10 +
    'Created:  2026-06-01T18:46:26'#13#10 +
    'Stroke: 10 [mm]     Speed: 30 [mm/sec]     Load: 0.5 [kgF]'#13#10 +
    'Cycles: 1000     Sampling interval: 20    Duration:  00:11:35'#13#10 +
    #13#10'Comment: '#13#10;
  for I := 1 to 100 do
    Text := Text + IntToStr(I) + '.0000'#9 +
      FloatToStr(0.4 + 0.0002 * I, TFormatSettings.Invariant) + #13#10;
  FPath := TPath.Combine(FDir, 'newformat.zrw');
  TFile.WriteAllBytes(FPath, ZipDataBytes(Text));
  Load(FPath);
  Provider.SetAnalysisContext(Context(''));
  Values := Keys;
  Names := '';
  for I := 0 to High(Values) do
    Names := Names + Values[I].Name + '|';
  Assert.AreEqual('Fn|Cycles|Stroke|Speed|Sampling Interval|COF|COF STD|', Names);
  Assert.IsTrue(Find(Values, 'Fn', Fn));
  Assert.AreEqual(4.903325, Fn.Value, 1e-9);
  Assert.AreEqual('N', Fn.Units);
  Assert.IsTrue(Find(Values, 'Stroke', Stroke));
  Assert.AreEqual(10.0, Stroke.Value, 0.0);
  Assert.IsTrue(Find(Values, 'Speed', Speed));
  Assert.AreEqual(30.0, Speed.Value, 0.0);
  Assert.AreEqual('mm/s', Speed.Units);
  Assert.IsTrue(Find(Values, 'Cycles', Cycles));
  Assert.AreEqual(1000.0, Cycles.Value, 0.0);
  Assert.IsTrue(Find(Values, 'Sampling Interval', Interval));
  Assert.AreEqual(20.0, Interval.Value, 0.0);
  Assert.AreEqual('', Interval.Units);
  Assert.IsTrue(Find(Values, 'COF', Cof));
end;

procedure TZRWExtractionTests.FailedLoadExposesLineNumberedMessageAndNextLoadClearsIt;
var
  Bad: string;
begin
  Bad := TPath.Combine(FDir, 'bad.zrw');
  WriteMalformedZrw(Bad);
  Assert.IsFalse(FPlugin.LoadFromFile(Bad));
  Assert.IsTrue(Pos('line 5', Provider.GetLoadError) > 0,
    'The message must name the line: ' + Provider.GetLoadError);
  Assert.IsFalse(FPlugin.LoadFromFile(TPath.Combine(FDir, 'missing.zrw')));
  Assert.IsTrue(Provider.GetLoadError <> '');
  Assert.IsTrue(FPlugin.LoadFromFile(FPath));
  Assert.AreEqual('', Provider.GetLoadError);
end;

procedure TZRWExtractionTests.DriftIntervalStatusMatchesPluginCoreStatus;
begin
  Assert.AreEqual(ANALYSIS_STATUS_INTERVAL_UNUSABLE, DRIFT_STATUS_INTERVAL_UNUSABLE);
end;

initialization
  TDUnitX.RegisterTestFixture(TZRWExtractionTests);

end.
