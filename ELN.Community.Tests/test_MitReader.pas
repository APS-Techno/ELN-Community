unit test_MitReader;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils,
  System.JSON, System.Hash, System.Math, Vcl.Forms, unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_MitFileParser, unit_MitAnalysis, unit_MitFilePlugin, frame_MitFileViewer,
  test_ZRWViewerSelection;

type
  TMitSpec = record
    Measured: Boolean;
    Fmax: Single;
    Plus28: Double;
    Hmax, Hc, Hr, Hf: Single;
    M: Single;
    H, E, S: Single;
  end;

function MitBytes(const Specs: array of TMitSpec; Version: Byte = 20;
  Contact: Integer = -1; const RecordClass: AnsiString = 'TSimpleIndentation';
  Compliance: Single = 0): TBytes;
function MitFixtureForce(Row, Contact: Integer): Single;
function EvidenceSpecs: TArray<TMitSpec>;
function ComputedSpecs: TArray<TMitSpec>;
function EstimatedSpec: TMitSpec;
function MitHashOf(const Bytes: TBytes): string;
function MitAreaNm2(HcNm: Double): Double;
function MitReducedModulus(SmNnm, HcNm: Double): Double;

type
  [TestFixture]
  TMitReaderTests = class
  private
    FDir: string;
    FPath: string;
    FHash: string;
    FPlugin: TELNMitFileViewerPlugin;
    FForm: TForm;
    function Context(const SharedSelection: string): TAnalysisContext;
    function StoredContext(const Snapshot: string): TAnalysisContext;
    function Selection(Mode: TMitSelectionMode; const Checked: TArray<Integer>;
      const FileHash: string): string;
    function Keys: TArray<TPluginKeyValue>;
    function Find(const Values: TArray<TPluginKeyValue>; const Name: string;
      out Value: TPluginKeyValue): Boolean;
    function Number(const Name: string): Double;
    function Provider: IAnalysisKeyValueProvider;
    procedure Load(const Bytes: TBytes);
    function MeanOf(const Values: array of Double; const Picks: array of Integer): Double;
    function StdOf(const Values: array of Double; const Picks: array of Integer): Double;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ReaderIdentityIsVersionThree;
    [Test] procedure InstrumentFieldsGiveHardnessAndModulusOfTheRecords;
    [Test] procedure MaxForceIsThePeakForceOfTheRecordNotTheReferenceDouble;
    [Test] procedure EvidenceShapedRecordsGiveModulusNear127AndNotTheFallbackValue;
    [Test] procedure ReducedModulusComesFromTheStoredStiffness;
    [Test] procedure MissingInstrumentFieldsComputeFromMeasuredForceAndSkipUnphysicalFits;
    [Test] procedure ComputedModeNeverPublishesModulus;
    [Test] procedure EstimatedRecordsStayExcludedAndCounted;
    [Test] procedure NoSelectionGivesAutomaticSnapshotOverAllUsableIndents;
    [Test] procedure SharedIndentsSelectionGivesMeanOfThoseIndentsAndTaggedSnapshot;
    [Test] procedure StoredSnapshotReplaysInNewPluginAndInViewerFrame;
    [Test] procedure StoredSnapshotOfAnotherFileHashStillReplaysItsIndents;
    [Test] procedure UnknownIndentGivesNoHardnessAndUnusableStatus;
    [Test] procedure ExcludedIndentGivesNoHardnessAndUnusableStatus;
    [Test] procedure MalformedSelectionsAreUnusable;
    [Test] procedure SharedSelectionOfAnotherFileHashIsStale;
    [Test] procedure ReloadingTheFileResetsTheContext;
    [Test] procedure OldFormatFileGivesNoValues;
    [Test] procedure CurveStartsAtTheStoredContactRowWithoutTheTrailerRow;
    [Test] procedure RecordWithoutAContactIndexHasNoCurve;
    [Test] procedure StandardAndSimpleRecordsAreReadInFileOrder;
    [Test] procedure SinusRecordUsesTheDataBlockAfterItsCycleTable;
    [Test] procedure StoredFrameComplianceIsSubtractedFromDepth;
  end;

  [TestFixture]
  TMitViewerTicksTests = class
  private
    FDir: string;
    FPath: string;
    FHash: string;
    FFrame: TframeMitFileViewer;
    FForm: TForm;
    FService: IElnAnalysisSettings;
    FDouble: TApplyDouble;
    FPrevious: IElnAnalysisSettings;
    function Context(const SharedSelection: string): TAnalysisContext;
    function Hardness: Double;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure UntickedIndentsAreTheSelectionAndAreApplied;
    [Test] procedure TickingEverythingAppliesAutomatic;
    [Test] procedure SelectingNoneStoresNothingAndYieldsNoValues;
    [Test] procedure SharedSelectionTicksTheViewer;
    [Test] procedure TicksWithoutServiceStillDriveExtraction;
    [Test] procedure TicksMadeBeforeTheContextAreAppliedWhenItArrives;
    [Test] procedure RefusedApplyKeepsTheTicks;
    [Test] procedure ReloadingTheSameFileKeepsTheTicks;
  end;

implementation

const
  EvFmax: array[0..8] of Double = (0.4996, 0.5002, 0.5003, 0.4993, 0.4995,
    0.4986, 0.4995, 0.4993, 0.4988);
  EvH: array[0..8] of Double = (5.682, 5.992, 5.624, 4.949, 5.844, 6.130,
    6.192, 6.578, 6.268);
  EvE: array[0..8] of Double = (135.04, 146.53, 123.68, 108.89, 129.02,
    116.70, 130.44, 133.08, 121.17);
  EvHf: array[0..8] of Double = (10.80, 16.39, 9.35, 12.61, -3.76, 17.39,
    -8.61, 4.74, 3.95);
  OtherHash = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
  Beta = 1.034;

function MitAreaNm2(HcNm: Double): Double;
begin
  Result := 3000 * HcNm;
end;

function MitReducedModulus(SmNnm, HcNm: Double): Double;
begin
  Result := Sqrt(Pi) / (2 * Beta) * SmNnm / Sqrt(MitAreaNm2(HcNm)) * 1e6;
end;

function MitHashOf(const Bytes: TBytes): string;
var
  Hash: THashMD5;
begin
  Hash := THashMD5.Create;
  Hash.Update(Bytes);
  Result := UpperCase(Hash.HashAsString);
end;

function MitFixtureForce(Row, Contact: Integer): Single;
begin
  if Row <= Contact then
    Result := 1E-5
  else if Row <= 400 then
    Result := 1E-5 + (Row - Contact) * 2E-6
  else
    Result := 1E-5 + (400 - Contact) * 2E-6 - (Row - 400) * 3E-6;
end;

function MitBytes(const Specs: array of TMitSpec; Version: Byte;
  Contact: Integer; const RecordClass: AnsiString; Compliance: Single): TBytes;
var
  Stream: TMemoryStream;
  Header, Post, Padding: TBytes;
  Row: TMitDataRow;
  Spec: TMitSpec;
  I: Integer;
  N: Cardinal;
  S: Single;
  B: Byte;

  procedure U32(V: Cardinal);
  begin
    Stream.WriteBuffer(V, 4);
  end;

  procedure LenString(const V: AnsiString);
  begin
    U32(Length(V));
    if V <> '' then
      Stream.WriteBuffer(V[1], Length(V));
  end;

  procedure PostSingle(Offset: Integer; V: Single);
  begin
    Move(V, Post[Offset], 4);
  end;

begin
  Stream := TMemoryStream.Create;
  try
    SetLength(Header, 93);
    N := MIT_MAGIC;
    Move(N, Header[0], 4);
    Header[45] := Version;
    Stream.WriteBuffer(Header[0], Length(Header));
    for Spec in Specs do
    begin
      LenString(RecordClass);
      U32(0);
      LenString('synthetic');
      if RecordClass = 'TSinusIndentation' then
      begin
        U32(501);
        U32(0);
        Row := Default(TMitDataRow);
        Row[0] := 0.5;
        Row[COL_TIME] := 0.5;
        Stream.WriteBuffer(Row, SizeOf(Row));
        SetLength(Padding, 3000);
        Stream.WriteBuffer(Padding[0], Length(Padding));
      end;
      LenString('TIndentorBerkovich');
      LenString('Diamond');
      LenString('s');
      S := Beta;
      Stream.WriteBuffer(S, 4);
      S := 0.07;
      Stream.WriteBuffer(S, 4);
      S := 1.141E12;
      Stream.WriteBuffer(S, 4);
      U32(0);
      U32(2);
      S := 0;
      Stream.WriteBuffer(S, 4);
      Stream.WriteBuffer(S, 4);
      S := 1E-6;
      Stream.WriteBuffer(S, 4);
      S := 3E-12;
      Stream.WriteBuffer(S, 4);
      U32(501);
      U32(0);
      Row := Default(TMitDataRow);
      Row[0] := 0.1;
      Row[COL_FORCESETPOINT] := 0.0005;
      for I := 0 to 500 do
      begin
        Row[COL_TIME] := (I + 1) * 0.033;
        if Contact >= 0 then
        begin
          Row[COL_DISPLACEMENT] := 2E-6 + I * 1E-9;
          Row[COL_FORCE] := MitFixtureForce(I, Contact);
          if I = 500 then
            Move(Contact, Row[COL_TIME], SizeOf(Contact));
        end;
        Stream.WriteBuffer(Row, SizeOf(Row));
      end;
      SetLength(Post, 0);
      SetLength(Post, 408);
      if Spec.Measured then
      begin
        Move(Spec.Plus28, Post[28], 8);
        PostSingle(352, Spec.H);
        PostSingle(360, Spec.E);
        PostSingle(364, Spec.Fmax);
        PostSingle(368, Spec.Hmax);
        PostSingle(376, Spec.S);
        PostSingle(380, Spec.Hc);
        PostSingle(384, Spec.Hr);
        PostSingle(388, Spec.Hf);
        PostSingle(392, 0.75);
        PostSingle(400, Spec.M);
      end;
      Stream.WriteBuffer(Post[0], Length(Post));
      if Compliance > 0 then
      begin
        LenString('9.0.19');
        B := 0;
        Stream.WriteBuffer(B, 1);
        B := 1;
        Stream.WriteBuffer(B, 1);
        Stream.WriteBuffer(Compliance, 4);
        U32(5);
        U32(0);
        U32(0);
      end;
    end;
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Move(Stream.Memory^, Result[0], Stream.Size);
  finally
    Stream.Free;
  end;
end;

function EvidenceSpecs: TArray<TMitSpec>;
var
  I: Integer;
begin
  SetLength(Result, Length(EvFmax));
  for I := 0 to High(Result) do
  begin
    Result[I] := Default(TMitSpec);
    Result[I].Measured := True;
    Result[I].Fmax := EvFmax[I] * 1e-3;
    Result[I].Plus28 := EvFmax[I] * 1e-3 * 1.0527;
    Result[I].Hmax := 100E-9;
    Result[I].Hc := 80E-9 + I * 1E-9;
    Result[I].Hf := EvHf[I] * 1e-9;
    Result[I].Hr := EvHf[I] * 1e-9;
    Result[I].M := 1.5;
    Result[I].H := EvH[I] * 1e9;
    Result[I].E := EvE[I] * 1e9;
    Result[I].S := 7.1E4 + 300 * I;
  end;
end;

function ComputedSpecs: TArray<TMitSpec>;
var
  I: Integer;
begin
  Result := EvidenceSpecs;
  for I := 0 to High(Result) do
  begin
    Result[I].H := 0;
    Result[I].E := 0;
    Result[I].S := 0;
  end;
end;

function EstimatedSpec: TMitSpec;
begin
  Result := Default(TMitSpec);
end;

procedure TMitReaderTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_MitReader_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FPath := TPath.Combine(FDir, 'sample.mit');
  FForm := TForm.CreateNew(nil);
  FPlugin := TELNMitFileViewerPlugin.Create(nil);
  FPlugin.Frame.Parent := FForm;
  Load(MitBytes(EvidenceSpecs));
end;

procedure TMitReaderTests.TearDown;
begin
  FPlugin.Free;
  FForm.Free;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TMitReaderTests.Load(const Bytes: TBytes);
begin
  TFile.WriteAllBytes(FPath, Bytes);
  Assert.IsTrue(FPlugin.LoadFromFile(FPath), FPlugin.GetLoadError);
  FHash := MitHashOf(Bytes);
end;

function TMitReaderTests.Provider: IAnalysisKeyValueProvider;
begin
  Assert.IsTrue(Supports(FPlugin, IAnalysisKeyValueProvider, Result),
    'The MIT reader must implement IAnalysisKeyValueProvider');
end;

function TMitReaderTests.Context(const SharedSelection: string): TAnalysisContext;
begin
  Result := Default(TAnalysisContext);
  Result.Kind := ackCurrent;
  Result.FileId := 21;
  Result.FileHash := FHash;
  Result.SharedSelection := SharedSelection;
end;

function TMitReaderTests.StoredContext(const Snapshot: string): TAnalysisContext;
begin
  Result := Default(TAnalysisContext);
  Result.Kind := ackStoredSnapshot;
  Result.FileId := 21;
  Result.FileHash := FHash;
  Result.StoredSnapshot := Snapshot;
end;

function TMitReaderTests.Selection(Mode: TMitSelectionMode;
  const Checked: TArray<Integer>; const FileHash: string): string;
var
  S: TMitSelection;
begin
  S := Default(TMitSelection);
  S.Mode := Mode;
  S.Checked := Checked;
  S.FileHash := FileHash;
  Result := MitSelectionToJson(S, 3, 1, 'apply-7', '2026-01-02T03:04:05Z');
end;

function TMitReaderTests.Keys: TArray<TPluginKeyValue>;
begin
  Result := (FPlugin as IKeyValueProvider).GetKeyValues;
end;

function TMitReaderTests.Find(const Values: TArray<TPluginKeyValue>;
  const Name: string; out Value: TPluginKeyValue): Boolean;
var
  Item: TPluginKeyValue;
begin
  for Item in Values do
    if Item.Name = Name then
    begin
      Value := Item;
      Exit(True);
    end;
  Result := False;
end;

function TMitReaderTests.Number(const Name: string): Double;
var
  Item: TPluginKeyValue;
begin
  Assert.IsTrue(Find(Keys, Name, Item), Name + ' must be extracted');
  Result := Item.Value;
end;

function TMitReaderTests.MeanOf(const Values: array of Double;
  const Picks: array of Integer): Double;
var
  I: Integer;
begin
  Result := 0;
  for I in Picks do
    Result := Result + Values[I];
  Result := Result / Length(Picks);
end;

function TMitReaderTests.StdOf(const Values: array of Double;
  const Picks: array of Integer): Double;
var
  I: Integer;
  Mean: Double;
begin
  Mean := MeanOf(Values, Picks);
  Result := 0;
  for I in Picks do
    Result := Result + Sqr(Values[I] - Mean);
  Result := Sqrt(Result / (Length(Picks) - 1));
end;

procedure TMitReaderTests.ReaderIdentityIsVersionThree;
var
  Identity: IReaderIdentity;
begin
  Assert.IsTrue(Supports(FPlugin, IReaderIdentity, Identity));
  Assert.AreEqual('aps.mit', Identity.GetReaderId);
  Assert.AreEqual('3', Identity.GetReaderVersion);
end;

procedure TMitReaderTests.InstrumentFieldsGiveHardnessAndModulusOfTheRecords;
var
  Hardness, Modulus, HStd, EStd: TPluginKeyValue;
  All: array[0..8] of Integer;
  I: Integer;
begin
  for I := 0 to 8 do
    All[I] := I;
  Provider.SetAnalysisContext(Context(''));
  Assert.IsTrue(Find(Keys, 'Hardness', Hardness));
  Assert.IsTrue(Find(Keys, 'Modulus', Modulus));
  Assert.IsTrue(Find(Keys, 'Hardness STD', HStd));
  Assert.IsTrue(Find(Keys, 'Modulus STD', EStd));
  Assert.IsTrue(Hardness.IsKey);
  Assert.IsTrue(Modulus.IsKey);
  Assert.IsTrue(Hardness.RecType = prResult);
  Assert.AreEqual('GPa', Hardness.Units);
  Assert.AreEqual('GPa', Modulus.Units);
  Assert.AreEqual(MeanOf(EvH, All), Hardness.Value, 1e-5);
  Assert.AreEqual(StdOf(EvH, All), HStd.Value, 1e-5);
  Assert.AreEqual(MeanOf(EvE, All), Modulus.Value, 1e-4);
  Assert.AreEqual(StdOf(EvE, All), EStd.Value, 1e-4);
  Assert.AreEqual<Double>(9, Number('Indent Count'));
  Assert.AreEqual<Double>(0, Number('Indents Excluded'));
  Assert.AreEqual('', Provider.GetAnalysisStatus);
end;

procedure TMitReaderTests.MaxForceIsThePeakForceOfTheRecordNotTheReferenceDouble;
var
  MaxForce, MaxForceStd: TPluginKeyValue;
  All: array[0..8] of Integer;
  I: Integer;
begin
  for I := 0 to 8 do
    All[I] := I;
  Assert.IsTrue(Find(Keys, 'Max Force', MaxForce));
  Assert.IsTrue(Find(Keys, 'Max Force STD', MaxForceStd));
  Assert.AreEqual('mN', MaxForce.Units);
  Assert.IsTrue(MaxForce.RecType = prCondition);
  Assert.AreEqual(MeanOf(EvFmax, All), MaxForce.Value, 1e-6);
  Assert.AreEqual(0.4994, MaxForce.Value, 1e-4);
  Assert.IsTrue(Abs(MaxForce.Value - 0.5258) > 0.02, 'The +28 double must not be used');
end;

procedure TMitReaderTests.EvidenceShapedRecordsGiveModulusNear127AndNotTheFallbackValue;
var
  Modulus, Std, Hardness, HStd: TPluginKeyValue;
begin
  Assert.IsTrue(Find(Keys, 'Modulus', Modulus));
  Assert.IsTrue(Find(Keys, 'Modulus STD', Std));
  Assert.IsTrue(Find(Keys, 'Hardness', Hardness));
  Assert.IsTrue(Find(Keys, 'Hardness STD', HStd));
  Assert.AreEqual(127.17, Modulus.Value, 0.01);
  Assert.AreEqual(11.06, Std.Value, 0.01);
  Assert.IsTrue(Abs(Modulus.Value - 213.12) > 50, 'Modulus must not follow the hf fallback');
  Assert.AreEqual(5.918, Hardness.Value, 0.001);
  Assert.AreEqual(0.470, HStd.Value, 0.001);
  Assert.IsTrue(Abs(Hardness.Value - 6.2287) > 0.1, 'Hardness must not follow the +28 force');
end;

procedure TMitReaderTests.ReducedModulusComesFromTheStoredStiffness;
var
  Expected: Double;
  I: Integer;
  Er: TPluginKeyValue;
begin
  Expected := 0;
  for I := 0 to 8 do
    Expected := Expected + MitReducedModulus((7.1E4 + 300 * I) * 1e-6, 80 + I);
  Expected := Expected / 9;
  Assert.IsTrue(Find(Keys, 'Reduced Modulus', Er));
  Assert.IsFalse(Er.IsKey);
  Assert.AreEqual(Expected, Er.Value, Expected * 1e-4);
  Assert.IsTrue(Find(Keys, 'Reduced Modulus STD', Er));
end;

procedure TMitReaderTests.MissingInstrumentFieldsComputeFromMeasuredForceAndSkipUnphysicalFits;
var
  Specs: TArray<TMitSpec>;
  Hardness, Er, Count, Excluded: TPluginKeyValue;
  Pick: array[0..1] of Integer;
  ExpectedH, ExpectedEr: Double;
  J: Integer;
  Info: TJSONObject;
begin
  Specs := Copy(ComputedSpecs, 0, 3);
  Specs[1].Hf := -3.8E-9;
  Specs[2].Hf := 12E-9;
  Load(MitBytes(Specs));
  Provider.SetAnalysisContext(Context(''));
  Pick[0] := 0;
  Pick[1] := 2;
  ExpectedH := 0;
  ExpectedEr := 0;
  for J in Pick do
  begin
    ExpectedH := ExpectedH + Specs[J].Fmax * 1000 / MitAreaNm2(Specs[J].Hc * 1e9) * 1e6;
    ExpectedEr := ExpectedEr + MitReducedModulus(
      Specs[J].Fmax * 1000 * 1.5 / ((Specs[J].Hmax - Specs[J].Hf) * 1e9),
      Specs[J].Hc * 1e9);
  end;
  Assert.IsTrue(Find(Keys, 'Hardness', Hardness));
  Assert.IsTrue(Find(Keys, 'Reduced Modulus', Er));
  Assert.AreEqual(ExpectedH / 2, Hardness.Value, ExpectedH * 1e-4);
  Assert.AreEqual(ExpectedEr / 2, Er.Value, ExpectedEr * 1e-4);
  Assert.IsTrue(Find(Keys, 'Indent Count', Count));
  Assert.IsTrue(Find(Keys, 'Indents Excluded', Excluded));
  Assert.AreEqual<Double>(2, Count.Value);
  Assert.AreEqual<Double>(1, Excluded.Value);
  Info := TJSONObject.ParseJSONValue((FPlugin as IDetailedInfoProvider).GetDetailedInfo) as TJSONObject;
  try
    Assert.AreEqual('computed', Info.GetValue<string>('source'));
    Assert.IsFalse(Info.GetValue<TJSONArray>('records').Items[1].GetValue<Boolean>('usable'));
  finally
    Info.Free;
  end;
end;

procedure TMitReaderTests.ComputedModeNeverPublishesModulus;
var
  Unused: TPluginKeyValue;
  Specs: TArray<TMitSpec>;
begin
  Specs := Copy(EvidenceSpecs, 0, 3);
  Specs[1].E := 0;
  Load(MitBytes(Specs));
  Provider.SetAnalysisContext(Context(''));
  Assert.IsFalse(Find(Keys, 'Modulus', Unused));
  Assert.IsFalse(Find(Keys, 'Modulus STD', Unused));
  Assert.IsTrue(Find(Keys, 'Hardness', Unused));
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('Modulus'));
end;

procedure TMitReaderTests.EstimatedRecordsStayExcludedAndCounted;
var
  Specs: TArray<TMitSpec>;
  Count, Excluded, Hardness: TPluginKeyValue;
begin
  Specs := Copy(EvidenceSpecs, 0, 3);
  Specs := Specs + [EstimatedSpec];
  Load(MitBytes(Specs));
  Provider.SetAnalysisContext(Context(''));
  Assert.IsTrue(Find(Keys, 'Indent Count', Count));
  Assert.IsTrue(Find(Keys, 'Indents Excluded', Excluded));
  Assert.AreEqual<Double>(3, Count.Value);
  Assert.AreEqual<Double>(1, Excluded.Value);
  Assert.IsTrue(Find(Keys, 'Hardness', Hardness));
  Assert.AreEqual((EvH[0] + EvH[1] + EvH[2]) / 3, Hardness.Value, 1e-5);
end;

procedure TMitReaderTests.NoSelectionGivesAutomaticSnapshotOverAllUsableIndents;
var
  Snapshot: TJSONObject;
  Stored: string;
begin
  Provider.SetAnalysisContext(Context(''));
  Stored := Provider.GetAnalysisSnapshot('Hardness');
  Assert.IsTrue(Length(Stored) <= 2000);
  Snapshot := TJSONObject.ParseJSONValue(Stored) as TJSONObject;
  try
    Assert.AreEqual(1, Snapshot.GetValue<Integer>('schema_version'));
    Assert.AreEqual('aps.mit', Snapshot.GetValue<string>('reader_id'));
    Assert.AreEqual('3', Snapshot.GetValue<string>('reader_version'));
    Assert.AreEqual('1', Snapshot.GetValue<string>('algorithm_version'));
    Assert.AreEqual('Hardness', Snapshot.GetValue<string>('key_name'));
    Assert.AreEqual<Int64>(21, Snapshot.GetValue<Int64>('file_id'));
    Assert.AreEqual(FHash, Snapshot.GetValue<string>('file_hash'));
    Assert.AreEqual('automatic', Snapshot.GetValue<string>('mode'));
    Assert.IsNull(Snapshot.FindValue('checked'));
    Assert.IsNull(Snapshot.FindValue('shared_revision'));
  finally
    Snapshot.Free;
  end;
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('Indents Excluded'));
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('Unknown'));
  Assert.AreNotEqual('', Provider.GetAnalysisSnapshot('Hardness STD'));
  Assert.AreNotEqual('', Provider.GetAnalysisSnapshot('Indent Count'));
end;

procedure TMitReaderTests.SharedIndentsSelectionGivesMeanOfThoseIndentsAndTaggedSnapshot;
var
  Picks: array[0..2] of Integer;
  Snapshot: TJSONObject;
  Checked: TJSONArray;
  Std: TPluginKeyValue;
begin
  Picks[0] := 0;
  Picks[1] := 2;
  Picks[2] := 4;
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [1, 3, 5], FHash)));
  Assert.AreEqual(MeanOf(EvH, Picks), Number('Hardness'), 1e-5);
  Assert.AreEqual(MeanOf(EvE, Picks), Number('Modulus'), 1e-4);
  Assert.IsTrue(Find(Keys, 'Hardness STD', Std));
  Assert.AreEqual(StdOf(EvH, Picks), Std.Value, 1e-5);
  Assert.AreEqual<Double>(3, Number('Indent Count'));
  Assert.AreEqual<Double>(0, Number('Indents Excluded'));
  Snapshot := TJSONObject.ParseJSONValue(Provider.GetAnalysisSnapshot('Hardness')) as TJSONObject;
  try
    Assert.AreEqual('indents', Snapshot.GetValue<string>('mode'));
    Checked := Snapshot.GetValue<TJSONArray>('checked');
    Assert.AreEqual<NativeInt>(3, Checked.Count);
    Assert.AreEqual(1, (Checked.Items[0] as TJSONNumber).AsInt);
    Assert.AreEqual(3, (Checked.Items[1] as TJSONNumber).AsInt);
    Assert.AreEqual(5, (Checked.Items[2] as TJSONNumber).AsInt);
    Assert.AreEqual(3, Snapshot.GetValue<Integer>('shared_revision'));
    Assert.AreEqual('apply-7', Snapshot.GetValue<string>('shared_apply_id'));
  finally
    Snapshot.Free;
  end;
end;

procedure TMitReaderTests.StoredSnapshotReplaysInNewPluginAndInViewerFrame;
var
  Stored: string;
  Hardness, Std: TPluginKeyValue;
  Second: TELNMitFileViewerPlugin;
  Frame: TframeMitFileViewer;
  SecondKeys: TArray<TPluginKeyValue>;
  SecondAnalysis: IAnalysisKeyValueProvider;
  SecondValues: IKeyValueProvider;
  First: Double;
begin
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [2, 3, 8], FHash)));
  Stored := Provider.GetAnalysisSnapshot('Hardness');
  Assert.IsTrue(Find(Keys, 'Hardness', Hardness));
  Assert.IsTrue(Find(Keys, 'Hardness STD', Std));

  Second := TELNMitFileViewerPlugin.Create(nil);
  Second.Frame.Parent := FForm;
  try
    Assert.IsTrue(Second.LoadFromFile(FPath));
    Assert.IsTrue(Supports(Second, IAnalysisKeyValueProvider, SecondAnalysis));
    Assert.IsTrue(Supports(Second, IKeyValueProvider, SecondValues));
    SecondAnalysis.SetAnalysisContext(StoredContext(Stored));
    SecondKeys := SecondValues.GetKeyValues;
    First := Hardness.Value;
    Assert.IsTrue(Find(SecondKeys, 'Hardness', Hardness));
    Assert.AreEqual(First, Hardness.Value, 0);
    Assert.IsTrue(Find(SecondKeys, 'Hardness STD', Hardness));
    Assert.AreEqual(Std.Value, Hardness.Value, 0);
    Assert.AreEqual('', SecondAnalysis.GetAnalysisStatus);
  finally
    SecondAnalysis := nil;
    SecondValues := nil;
    Second.Free;
  end;

  Frame := TframeMitFileViewer.Create(nil);
  Frame.Parent := FForm;
  try
    Frame.LoadFromFile(FPath);
    Frame.SetAnalysisContext(StoredContext(Stored));
    Assert.IsTrue(Find(Frame.GetKeyValues, 'Hardness', Hardness));
    Assert.AreEqual(Number('Hardness'), Hardness.Value, 0);
    Assert.IsTrue(Find(Frame.GetKeyValues, 'Hardness STD', Hardness));
    Assert.AreEqual(Std.Value, Hardness.Value, 0);
  finally
    Frame.Free;
  end;
end;

procedure TMitReaderTests.StoredSnapshotOfAnotherFileHashStillReplaysItsIndents;
var
  Stored: string;
  Before: Double;
  Ctx: TAnalysisContext;
begin
  Provider.SetAnalysisContext(Self.Context(Selection(msmIndents, [1, 2], FHash)));
  Stored := Provider.GetAnalysisSnapshot('Hardness');
  Before := Number('Hardness');
  Load(MitBytes(EvidenceSpecs, 18));
  Ctx := StoredContext(Stored);
  Ctx.FileHash := OtherHash;
  Provider.SetAnalysisContext(Ctx);
  Assert.AreEqual(Before, Number('Hardness'), 1e-9);
  Assert.AreEqual('', Provider.GetAnalysisStatus);
end;

procedure TMitReaderTests.UnknownIndentGivesNoHardnessAndUnusableStatus;
var
  Unused: TPluginKeyValue;
  Stored: string;
begin
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [1, 99], FHash)));
  Assert.IsFalse(Find(Keys, 'Hardness', Unused));
  Assert.IsFalse(Find(Keys, 'Indent Count', Unused));
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('Hardness'));
  Stored := '{"schema_version":1,"reader_id":"aps.mit","mode":"indents","checked":[1,99],' +
    '"file_hash":"' + FHash + '"}';
  Provider.SetAnalysisContext(StoredContext(Stored));
  Assert.IsFalse(Find(Keys, 'Hardness', Unused));
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
end;

procedure TMitReaderTests.ExcludedIndentGivesNoHardnessAndUnusableStatus;
var
  Specs: TArray<TMitSpec>;
  Unused: TPluginKeyValue;
begin
  Specs := Copy(EvidenceSpecs, 0, 3);
  Specs := Specs + [EstimatedSpec];
  Load(MitBytes(Specs));
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [1, 4], FHash)));
  Assert.IsFalse(Find(Keys, 'Hardness', Unused));
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [1, 1], FHash)));
  Assert.IsFalse(Find(Keys, 'Hardness', Unused), 'A repeated indent is unusable');
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [], FHash)));
  Assert.IsFalse(Find(Keys, 'Hardness', Unused), 'An empty list is unusable');
  Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus);
end;

procedure TMitReaderTests.MalformedSelectionsAreUnusable;
const
  Bad: array[0..6] of string = ('not json', '[1,2]',
    '{"mode":"indents"}', '{"mode":"indents","checked":"1,2"}',
    '{"mode":"indents","checked":[1.5]}', '{"mode":"manual","checked":[1]}',
    '{"schema_version":2,"mode":"automatic"}');
var
  Text: string;
  Unused: TPluginKeyValue;
begin
  for Text in Bad do
  begin
    Provider.SetAnalysisContext(Context(Text));
    Assert.IsFalse(Find(Keys, 'Hardness', Unused), Text);
    Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus, Text);
    Provider.SetAnalysisContext(StoredContext(Text));
    Assert.IsFalse(Find(Keys, 'Hardness', Unused), Text);
    Assert.AreEqual('interval_unusable', Provider.GetAnalysisStatus, Text);
  end;
end;

procedure TMitReaderTests.SharedSelectionOfAnotherFileHashIsStale;
var
  Unused: TPluginKeyValue;
begin
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [1, 2], OtherHash)));
  Assert.IsFalse(Find(Keys, 'Hardness', Unused));
  Assert.AreEqual('stale_selection', Provider.GetAnalysisStatus);
  Assert.AreEqual('', Provider.GetAnalysisSnapshot('Hardness'));
end;

procedure TMitReaderTests.ReloadingTheFileResetsTheContext;
var
  First, Second: Double;
begin
  Provider.SetAnalysisContext(Context(Selection(msmIndents, [1, 2], FHash)));
  First := Number('Hardness');
  Load(MitBytes(EvidenceSpecs, 18));
  Second := Number('Hardness');
  Assert.AreEqual((EvH[0] + EvH[1] + EvH[2] + EvH[3] + EvH[4] + EvH[5] + EvH[6] +
    EvH[7] + EvH[8]) / 9, Second, 1e-5);
  Assert.IsTrue(Abs(First - Second) > 1e-3);
end;

procedure TMitReaderTests.OldFormatFileGivesNoValues;
var
  Unused: TPluginKeyValue;
begin
  Load(MitBytes(EvidenceSpecs, 0));
  Provider.SetAnalysisContext(Context(''));
  Assert.IsFalse(Find(Keys, 'Hardness', Unused));
  Assert.IsFalse(Find(Keys, 'Modulus', Unused));
end;

procedure TMitReaderTests.CurveStartsAtTheStoredContactRowWithoutTheTrailerRow;
const
  Contact = 120;
var
  Mit: TMitFile;
  Rec: TMitRecord;
  K: Integer;
  Z0, F0: Single;
begin
  TFile.WriteAllBytes(FPath, MitBytes(EvidenceSpecs, 20, Contact));
  Mit := TMitFile.Create;
  try
    Mit.ParseFromFile(FPath);
    Rec := Mit.GetRecord(0);
    Assert.AreEqual(Contact, Rec.ContactRow);
    Assert.AreEqual<NativeInt>(500 - Contact, Length(Rec.Curve), 'Rows from contact up to the trailer');
    Assert.AreEqual(400 - Contact, Rec.PeakIndex);
    Z0 := 2E-6 + Contact * 1E-9;
    F0 := MitFixtureForce(Contact, Contact);
    for K := 0 to High(Rec.Curve) do
    begin
      Assert.AreEqual((Double(Single(2E-6 + (Contact + K) * 1E-9)) - Z0) * 1e9,
        Rec.Curve[K].DepthNm, 1e-6);
      Assert.AreEqual((Double(MitFixtureForce(Contact + K, Contact)) - F0) * 1e3,
        Rec.Curve[K].ForceMN, 1e-9);
    end;
    Assert.AreEqual(0.0, Rec.Curve[0].DepthNm, 0.0);
    Assert.AreEqual(0.0, Rec.Curve[0].ForceMN, 0.0);
  finally
    Mit.Free;
  end;
end;

procedure TMitReaderTests.RecordWithoutAContactIndexHasNoCurve;
var
  Mit: TMitFile;
begin
  TFile.WriteAllBytes(FPath, MitBytes(EvidenceSpecs));
  Mit := TMitFile.Create;
  try
    Mit.ParseFromFile(FPath);
    Assert.AreEqual(-1, Mit.GetRecord(0).ContactRow);
    Assert.IsFalse(Mit.GetRecord(0).HasCurve);
    Assert.AreEqual(9, Mit.RecordCount);
  finally
    Mit.Free;
  end;
end;

procedure TMitReaderTests.SinusRecordUsesTheDataBlockAfterItsCycleTable;
const
  Contact = 120;
var
  Mit: TMitFile;
  I: Integer;
begin
  TFile.WriteAllBytes(FPath, MitBytes(EvidenceSpecs, 20, Contact, 'TSinusIndentation'));
  Mit := TMitFile.Create;
  try
    Mit.ParseFromFile(FPath);
    Assert.AreEqual(9, Mit.RecordCount);
    for I := 0 to 8 do
    begin
      Assert.AreEqual(Contact, Mit.GetRecord(I).ContactRow, Format('Indent %d', [I + 1]));
      Assert.AreEqual(EvH[I], Mit.Indent(I).H_GPa, 1e-4, Format('Indent %d', [I + 1]));
    end;
  finally
    Mit.Free;
  end;
end;

procedure TMitReaderTests.StandardAndSimpleRecordsAreReadInFileOrder;
var
  Specs, Standard: TArray<TMitSpec>;
  Bytes, Tail: TBytes;
  Mit: TMitFile;
  I: Integer;
begin
  Specs := EvidenceSpecs;
  Standard := Copy(Specs, 3, 3);
  Bytes := MitBytes(Copy(Specs, 0, 3), 20);
  Tail := MitBytes(Standard, 20, -1, 'TStandardIndentation');
  Bytes := Bytes + Copy(Tail, 93, Length(Tail) - 93);
  Tail := MitBytes(Copy(Specs, 6, 3), 20);
  Bytes := Bytes + Copy(Tail, 93, Length(Tail) - 93);
  TFile.WriteAllBytes(FPath, Bytes);
  Mit := TMitFile.Create;
  try
    Mit.ParseFromFile(FPath);
    Assert.AreEqual(9, Mit.RecordCount);
    for I := 0 to 8 do
      Assert.AreEqual(EvH[I], Mit.Indent(I).H_GPa, 1e-4, Format('Indent %d', [I + 1]));
  finally
    Mit.Free;
  end;
end;

procedure TMitReaderTests.StoredFrameComplianceIsSubtractedFromDepth;
const
  Contact = 120;
  Compliance: Single = 1E-7;
var
  Mit: TMitFile;
  Rec: TMitRecord;
  K: Integer;
  Z0, F0: Single;
  DF: Double;
begin
  TFile.WriteAllBytes(FPath, MitBytes(EvidenceSpecs, 20, Contact,
    'TSimpleIndentation', Compliance));
  Mit := TMitFile.Create;
  try
    Mit.ParseFromFile(FPath);
    Rec := Mit.GetRecord(0);
    Assert.AreEqual(Double(Compliance), Rec.FrameCompliance, 0.0);
    Z0 := 2E-6 + Contact * 1E-9;
    F0 := MitFixtureForce(Contact, Contact);
    for K := 0 to High(Rec.Curve) do
    begin
      DF := Double(MitFixtureForce(Contact + K, Contact)) - F0;
      Assert.AreEqual((Double(Single(2E-6 + (Contact + K) * 1E-9)) - Z0 -
        Compliance * DF) * 1e9, Rec.Curve[K].DepthNm, 1e-6);
    end;
    Assert.IsTrue(Rec.Curve[Rec.PeakIndex].DepthNm <
      (Double(Single(2E-6 + 400 * 1E-9)) - Z0) * 1e9 - 0.01,
      'The peak depth is reduced by the frame deflection');
  finally
    Mit.Free;
  end;
end;

procedure TMitViewerTicksTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_MitTicks_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  FPath := TPath.Combine(FDir, 'sample.mit');
  TFile.WriteAllBytes(FPath, MitBytes(EvidenceSpecs));
  FHash := UpperCase(THashMD5.GetHashStringFromFile(FPath));
  FPrevious := ElnAnalysisSettings;
  FDouble := TApplyDouble.Create;
  FDouble.Outcome := aarApplied;
  FDouble.UserId := 7;
  FService := FDouble;
  ElnAnalysisSettings := FService;
  FForm := TForm.CreateNew(nil);
  FFrame := TframeMitFileViewer.Create(nil);
  FFrame.Parent := FForm;
  FFrame.LoadFromFile(FPath);
end;

procedure TMitViewerTicksTests.TearDown;
begin
  FreeAndNil(FFrame);
  FreeAndNil(FForm);
  ElnAnalysisSettings := FPrevious;
  FPrevious := nil;
  FService := nil;
  FDouble := nil;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

function TMitViewerTicksTests.Context(const SharedSelection: string): TAnalysisContext;
begin
  Result := Default(TAnalysisContext);
  Result.Kind := ackCurrent;
  Result.FileId := 21;
  Result.FileHash := FHash;
  Result.SharedSelection := SharedSelection;
end;

function TMitViewerTicksTests.Hardness: Double;
var
  Item: TPluginKeyValue;
begin
  Result := -1;
  for Item in FFrame.GetKeyValues do
    if Item.Name = 'Hardness' then
      Result := Item.Value;
end;

procedure TMitViewerTicksTests.UntickedIndentsAreTheSelectionAndAreApplied;
var
  Sent: TJSONObject;
  Checked: TJSONArray;
  Expected: Double;
  I: Integer;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.lstRecords.Checked[1] := False;
  FFrame.lstRecords.Checked[5] := False;
  FFrame.lstRecordsClickCheck(nil);
  Assert.AreEqual(1, FDouble.Calls);
  Assert.AreEqual<Int64>(21, FDouble.LastFileId);
  Assert.AreEqual('aps.mit', FDouble.LastReaderId);
  Assert.AreEqual('', FDouble.LastExpected);
  Sent := TJSONObject.ParseJSONValue(FDouble.LastNew) as TJSONObject;
  try
    Assert.AreEqual('indents', Sent.GetValue<string>('mode'));
    Assert.AreEqual(FHash, Sent.GetValue<string>('file_hash'));
    Assert.AreEqual(1, Sent.GetValue<Integer>('revision'));
    Assert.AreEqual(7, Sent.GetValue<Integer>('applied_by'));
    Checked := Sent.GetValue<TJSONArray>('checked');
    Assert.AreEqual<NativeInt>(7, Checked.Count);
    Assert.AreEqual(1, (Checked.Items[0] as TJSONNumber).AsInt);
    Assert.AreEqual(3, (Checked.Items[1] as TJSONNumber).AsInt);
  finally
    Sent.Free;
  end;
  Expected := 0;
  for I in [0, 2, 3, 4, 6, 7, 8] do
    Expected := Expected + EvH[I];
  Assert.AreEqual(Expected / 7, Hardness, 1e-5);
  Assert.AreNotEqual('', FFrame.GetAnalysisSnapshot('Hardness'));
  Assert.IsTrue(Pos('shared_revision', FFrame.GetAnalysisSnapshot('Hardness')) > 0);
end;

procedure TMitViewerTicksTests.TickingEverythingAppliesAutomatic;
var
  Sent: TJSONObject;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.lstRecords.Checked[1] := False;
  FFrame.lstRecordsClickCheck(nil);
  FFrame.btnSelectAllClick(nil);
  Assert.AreEqual(2, FDouble.Calls);
  Sent := TJSONObject.ParseJSONValue(FDouble.LastNew) as TJSONObject;
  try
    Assert.AreEqual('automatic', Sent.GetValue<string>('mode'));
    Assert.IsNull(Sent.FindValue('checked'));
    Assert.AreEqual(2, Sent.GetValue<Integer>('revision'));
  finally
    Sent.Free;
  end;
  Assert.AreEqual(5.918, Hardness, 0.001);
end;

procedure TMitViewerTicksTests.SelectingNoneStoresNothingAndYieldsNoValues;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.btnSelectNoneClick(nil);
  Assert.AreEqual(0, FDouble.Calls);
  Assert.AreEqual<NativeInt>(0, Length(FFrame.GetKeyValues));
end;

procedure TMitViewerTicksTests.SharedSelectionTicksTheViewer;
var
  S: TMitSelection;
  I: Integer;
  Ticked: Integer;
begin
  S := Default(TMitSelection);
  S.Mode := msmIndents;
  S.Checked := [2, 4, 9];
  S.FileHash := FHash;
  FFrame.SetAnalysisContext(Context(MitSelectionToJson(S, 4, 1, 'apply-4', '2026-01-02T03:04:05Z')));
  Ticked := 0;
  for I := 0 to FFrame.lstRecords.Count - 1 do
    if FFrame.lstRecords.Checked[I] then
      Inc(Ticked);
  Assert.AreEqual(3, Ticked);
  Assert.IsTrue(FFrame.lstRecords.Checked[1] and FFrame.lstRecords.Checked[3] and
    FFrame.lstRecords.Checked[8]);
  Assert.AreEqual((EvH[1] + EvH[3] + EvH[8]) / 3, Hardness, 1e-5);
  Assert.AreEqual(0, FDouble.Calls, 'Adopting a shared selection writes nothing');
  Assert.IsTrue(Pos('"shared_revision":4', FFrame.GetAnalysisSnapshot('Hardness')) > 0);
end;

procedure TMitViewerTicksTests.TicksWithoutServiceStillDriveExtraction;
begin
  ElnAnalysisSettings := nil;
  FFrame.SetAnalysisContext(Context(''));
  FFrame.lstRecords.Checked[0] := False;
  FFrame.lstRecordsClickCheck(nil);
  Assert.AreEqual(0, FDouble.Calls);
  Assert.AreEqual((EvH[1] + EvH[2] + EvH[3] + EvH[4] + EvH[5] + EvH[6] + EvH[7] +
    EvH[8]) / 8, Hardness, 1e-5);
  Assert.IsTrue(Pos('shared_revision', FFrame.GetAnalysisSnapshot('Hardness')) = 0);
end;

procedure TMitViewerTicksTests.TicksMadeBeforeTheContextAreAppliedWhenItArrives;
begin
  FFrame.lstRecords.Checked[0] := False;
  FFrame.lstRecordsClickCheck(nil);
  Assert.AreEqual(0, FDouble.Calls);
  FFrame.SetAnalysisContext(Context(''));
  Assert.AreEqual(1, FDouble.Calls);
  Assert.IsTrue(Pos('"checked":[2,3,4,5,6,7,8,9]', FDouble.LastNew) > 0, FDouble.LastNew);
end;

procedure TMitViewerTicksTests.RefusedApplyKeepsTheTicks;
begin
  FDouble.Outcome := aarDenied;
  FFrame.SetAnalysisContext(Context(''));
  FFrame.lstRecords.Checked[8] := False;
  FFrame.lstRecordsClickCheck(nil);
  Assert.AreEqual(1, FDouble.Calls);
  Assert.AreEqual((EvH[0] + EvH[1] + EvH[2] + EvH[3] + EvH[4] + EvH[5] + EvH[6] +
    EvH[7]) / 8, Hardness, 1e-5);
  Assert.IsTrue(Pos('shared_revision', FFrame.GetAnalysisSnapshot('Hardness')) = 0);
end;

procedure TMitViewerTicksTests.ReloadingTheSameFileKeepsTheTicks;
begin
  FFrame.SetAnalysisContext(Context(''));
  FFrame.lstRecords.Checked[0] := False;
  FFrame.lstRecordsClickCheck(nil);
  FFrame.LoadFromFile(FPath);
  FFrame.SetAnalysisContext(Context(''));
  Assert.IsFalse(FFrame.lstRecords.Checked[0]);
  Assert.AreEqual((EvH[1] + EvH[2] + EvH[3] + EvH[4] + EvH[5] + EvH[6] + EvH[7] +
    EvH[8]) / 8, Hardness, 1e-5);
end;

initialization
  TDUnitX.RegisterTestFixture(TMitReaderTests);
  TDUnitX.RegisterTestFixture(TMitViewerTicksTests);

end.
