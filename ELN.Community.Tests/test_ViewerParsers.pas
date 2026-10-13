unit test_ViewerParsers;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils,
  System.Zip, unit_LAMMPSDumpParser, unit_DM3Parser, unit_XRFXParser;

type
  [TestFixture]
  TViewerParserTests = class
  private
    FDir: string;
    function TextFile(const Name, Text: string): string;
    procedure CheckDM3(const Info: array of Cardinal; Valid: Boolean);
    procedure CheckXRFXFailure(const Manifest, Curve: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure LAMMPS_DecimalPointIgnoresLocale;
    [Test] procedure LAMMPS_TriclinicScaledCoordinates;
    [Test] procedure LAMMPS_TriclinicUnwrappedScaledCoordinates;
    [Test] procedure LAMMPS_GeneralTriclinicIsExplicitlyRejected;
    [Test] procedure LAMMPS_InvalidCoordinatesAreRejected;
    [Test] procedure DM3_TruncatedStructDescriptorsAreRejected;
    [Test] procedure DM3_ValidAndEmptyStructArraysAreAccepted;
    [Test] procedure XRFX_MissingManifestCleansExtractedPayload;
    [Test] procedure XRFX_InvalidCurveCleansExtractedPayload;
  end;

implementation

const
  DUMP_HEADER = 'ITEM: TIMESTEP'#13#10'0'#13#10 +
    'ITEM: NUMBER OF ATOMS'#13#10'1'#13#10;
  MANIFEST_JSON = '{"version":1,"fom":0,"substrate":"Si",' +
    '"target_lines":[],"element_pool":[],"per_element":[],' +
    '"structure_summary":{"type":"periodic","d":10,"gamma":0.5,"N":1,"sigma":0},' +
    '"optimizer":{"population":1,"iterations":1,"stagnation_limit":1}}';

procedure TViewerParserTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_ViewerRegression_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TViewerParserTests.TearDown;
begin
  TDirectory.Delete(FDir, True);
end;

function TViewerParserTests.TextFile(const Name, Text: string): string;
begin
  Result := TPath.Combine(FDir, Name);
  TFile.WriteAllText(Result, Text, TEncoding.UTF8);
end;

procedure TViewerParserTests.LAMMPS_DecimalPointIgnoresLocale;
var
  Dump: TLAMMPSDumpFile;
  Saved: TFormatSettings;
begin
  Dump := TLAMMPSDumpFile.Create;
  Saved := FormatSettings;
  try
    FormatSettings.DecimalSeparator := ',';
    FormatSettings.ThousandSeparator := '.';
    Dump.ParseFromFile(TextFile('scaled.dump', DUMP_HEADER +
      'ITEM: BOX BOUNDS pp pp pp'#13#10'0.0 10.0'#13#10'0.0 20.0'#13#10'0.0 40.0'#13#10 +
      'ITEM: ATOMS id type xs ys zs'#13#10'1 1 0.5 0.5 0.5'));
    Assert.AreEqual(Double(5), Dump.Atoms[0].X, 1E-9);
    Assert.AreEqual(Double(10), Dump.Atoms[0].Y, 1E-9);
    Assert.AreEqual(Double(20), Dump.Atoms[0].Z, 1E-9);
    Dump.ParseFromFile(TextFile('atomic.data', '# synthetic'#13#10 +
      '1 atoms'#13#10'1 atom types'#13#10'0.5 10.5 xlo xhi'#13#10 +
      '0.0 20.0 ylo yhi'#13#10'0.0 40.0 zlo zhi'#13#10 +
      'Masses'#13#10#13#10'1 12.5'#13#10#13#10 +
      'Atoms # atomic'#13#10#13#10'1 1 1.25 2.5 3.75'));
    Assert.AreEqual(Double(0.5), Dump.Box.XLo, 1E-9);
    Assert.AreEqual(Double(12.5), Dump.Masses[0].Mass, 1E-9);
    Assert.AreEqual(Double(1.25), Dump.Atoms[0].X, 1E-9);
    Assert.AreEqual(Double(2.5), Dump.Atoms[0].Y, 1E-9);
    Assert.AreEqual(Double(3.75), Dump.Atoms[0].Z, 1E-9);
  finally
    FormatSettings := Saved;
    Dump.Free;
  end;
end;

procedure TViewerParserTests.LAMMPS_TriclinicScaledCoordinates;
var
  Dump: TLAMMPSDumpFile;
begin
  Dump := TLAMMPSDumpFile.Create;
  try
    Dump.ParseFromFile(TextFile('tilted.dump', DUMP_HEADER +
      'ITEM: BOX BOUNDS xy xz yz pp pp pp'#13#10'0 12 2'#13#10'0 10 0'#13#10'0 10 0'#13#10 +
      'ITEM: ATOMS id type xs ys zs'#13#10'1 1 0.5 0 0'));
    Assert.AreEqual(Double(10), Dump.Box.XHi - Dump.Box.XLo, 1E-9);
    Assert.AreEqual(Double(5), Dump.Atoms[0].X, 1E-9);
    // Nonzero origin, negative xy/yz, and positive xz exercise all cross terms.
    Dump.ParseFromFile(TextFile('mixed.dump', DUMP_HEADER +
      'ITEM: BOX BOUNDS xy xz yz pp pp pp'#13#10'-2 13 -2'#13#10'-1 12 3'#13#10'3 13 -3'#13#10 +
      'ITEM: ATOMS id type xs ys zs'#13#10'1 1 0.5 0.25 0.75'));
    Assert.AreEqual(Double(0), Dump.Box.XLo, 1E-9);
    Assert.AreEqual(Double(10), Dump.Box.XHi, 1E-9);
    Assert.AreEqual(Double(2), Dump.Box.YLo, 1E-9);
    Assert.AreEqual(Double(6.75), Dump.Atoms[0].X, 1E-9);
    Assert.AreEqual(Double(2.25), Dump.Atoms[0].Y, 1E-9);
    Assert.AreEqual(Double(10.5), Dump.Atoms[0].Z, 1E-9);
  finally
    Dump.Free;
  end;
end;

procedure TViewerParserTests.LAMMPS_TriclinicUnwrappedScaledCoordinates;
var
  Dump: TLAMMPSDumpFile;
begin
  Dump := TLAMMPSDumpFile.Create;
  try
    Dump.ParseFromFile(TextFile('unwrapped.dump', DUMP_HEADER +
      'ITEM: BOX BOUNDS xy xz yz pp pp pp'#13#10'0 12 2'#13#10'0 10 0'#13#10'0 10 0'#13#10 +
      'ITEM: ATOMS id type xsu ysu zsu'#13#10'1 1 1.5 -0.5 0'));
    Assert.AreEqual(Double(14), Dump.Atoms[0].X, 1E-9);
    Assert.AreEqual(Double(-5), Dump.Atoms[0].Y, 1E-9);
  finally
    Dump.Free;
  end;
end;

procedure TViewerParserTests.LAMMPS_GeneralTriclinicIsExplicitlyRejected;
var
  Dump: TLAMMPSDumpFile;
  Name: string;
begin
  Name := TextFile('general.dump', DUMP_HEADER +
    'ITEM: BOX BOUNDS abc origin'#13#10'10 0 0 1'#13#10'2 10 0 2'#13#10'0 0 10 3'#13#10 +
    'ITEM: ATOMS id type xs ys zs'#13#10'1 1 0.5 0.5 0.5');
  Dump := TLAMMPSDumpFile.Create;
  try
    Assert.WillRaise(procedure begin Dump.ParseFromFile(Name); end, EConvertError);
  finally
    Dump.Free;
  end;
end;

procedure TViewerParserTests.LAMMPS_InvalidCoordinatesAreRejected;
var
  Dump: TLAMMPSDumpFile;
  Name: string;
begin
  Name := TextFile('bad.dump', DUMP_HEADER +
    'ITEM: BOX BOUNDS pp pp pp'#13#10'0 10'#13#10'0 10'#13#10'0 10'#13#10 +
    'ITEM: ATOMS id type x y z'#13#10'1 1 not-a-number 2 3');
  Dump := TLAMMPSDumpFile.Create;
  try
    Assert.WillRaise(procedure begin Dump.ParseFromFile(Name); end, EConvertError);
  finally
    Dump.Free;
  end;
end;

procedure TViewerParserTests.CheckDM3(const Info: array of Cardinal; Valid: Boolean);
var
  Stream: TMemoryStream;
  DM3: TDM3File;
  V: Cardinal;
  B: Byte;
  procedure BE32(N: Cardinal);
  var Bytes: array[0..3] of Byte;
  begin
    Bytes[0] := N shr 24; Bytes[1] := (N shr 16) and $FF;
    Bytes[2] := (N shr 8) and $FF; Bytes[3] := N and $FF;
    Stream.WriteBuffer(Bytes, SizeOf(Bytes));
  end;
begin
  Stream := TMemoryStream.Create;
  DM3 := TDM3File.Create;
  try
    BE32(3); BE32(0); BE32(1);
    B := 0; Stream.WriteBuffer(B, 1); Stream.WriteBuffer(B, 1); BE32(1);
    B := 21; Stream.WriteBuffer(B, 1);
    B := 0; Stream.WriteBuffer(B, 1); Stream.WriteBuffer(B, 1);
    BE32($25252525); BE32(Length(Info));
    for V in Info do BE32(V);
    BE32(0); // payload for valid one-field structs
    if Valid then
      Assert.WillNotRaise(procedure begin DM3.ParseFromStream(Stream); end)
    else
      Assert.WillRaise(procedure begin DM3.ParseFromStream(Stream); end, EDM3Error);
  finally
    DM3.Free;
    Stream.Free;
  end;
end;

procedure TViewerParserTests.DM3_TruncatedStructDescriptorsAreRejected;
begin
  CheckDM3([], False);
  CheckDM3([15], False);
  CheckDM3([20], False);
  CheckDM3([20, 15, 0, 100, 0], False);
  CheckDM3([20, 15, 0, $FFFFFFFF, 0], False);
  CheckDM3([15, 0], False);
  CheckDM3([15, 0, 100, 0], False);
  CheckDM3([15, 0, $FFFFFFFF], False);
  CheckDM3([20, 15, 0, 1, 0, 3], False); // missing array length
end;

procedure TViewerParserTests.DM3_ValidAndEmptyStructArraysAreAccepted;
begin
  CheckDM3([15, 0, 1, 0, 3], True);
  CheckDM3([20, 15, 0, 1, 0, 3, 1], True);
  CheckDM3([20, 15, 0, 1, 0, 10, 0], True);
end;

procedure TViewerParserTests.CheckXRFXFailure(const Manifest, Curve: string);
var
  Zip: TZipFile;
  ArchiveName, TempRoot, Dir, MarkerName, MarkerContent: string;
  After: TArray<string>;
  function IsOwned(const Path: string): Boolean;
  var
    MarkerPath: string;
  begin
    MarkerPath := TPath.Combine(Path, MarkerName);
    Result := TFile.Exists(MarkerPath) and
      (TFile.ReadAllText(MarkerPath, TEncoding.UTF8) = MarkerContent);
  end;
var
  Loaded: TXRFXLoadedResult;
begin
  ArchiveName := TPath.Combine(FDir, 'synthetic.xrfx');
  MarkerContent := TGUID.NewGuid.ToString;
  MarkerName := 'fixture-' + MarkerContent + '.txt';
  Zip := TZipFile.Create;
  try
    Zip.Open(ArchiveName, zmWrite);
    Zip.Add(TextFile(MarkerName, MarkerContent), MarkerName);
    if Manifest <> '' then Zip.Add(TextFile('manifest.json', Manifest), 'manifest.json');
    if Curve <> '' then Zip.Add(TextFile('curve.dat', Curve), 'best_curves/test.dat');
    Zip.Close;
  finally
    Zip.Free;
  end;
  TempRoot := TPath.Combine(TPath.GetTempPath, 'ELN_XRFX');
  try
    Assert.WillRaise(procedure begin Loaded := LoadXRFXFile(ArchiveName); end);
    After := TDirectory.GetDirectories(TempRoot);
    for Dir in After do
      Assert.IsFalse(IsOwned(Dir), 'Failed archive load retained extracted fixture data');
  finally
    if TDirectory.Exists(TempRoot) then
      for Dir in TDirectory.GetDirectories(TempRoot) do
        if IsOwned(Dir) then CleanupXRFXTemp(Dir);
  end;
end;

procedure TViewerParserTests.XRFX_MissingManifestCleansExtractedPayload;
begin
  CheckXRFXFailure('', '');
end;

procedure TViewerParserTests.XRFX_InvalidCurveCleansExtractedPayload;
begin
  CheckXRFXFailure(MANIFEST_JSON, 'Theta'#9'R'#13#10'bad'#9'0.5');
end;

initialization
  TDUnitX.RegisterTestFixture(TViewerParserTests);
end.
