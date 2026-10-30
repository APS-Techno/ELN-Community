unit test_LAMMPSParser;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils,
  System.Generics.Collections,
  unit_LAMMPSDumpParser;

type
  [TestFixture]
  TLAMMPSParserTests = class
  private
    FDump: TLAMMPSDumpFile;
    FDir: string;
    function DataPath(const AName: string): string;
    function DistinctAtomTypes: Integer;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure FullStyle_ReadsTypeAndCoordsFromRightColumns;
    [Test] procedure FullStyle_DistinctTypesMatchHeaderNotMolecules;
    [Test] procedure AtomicStyle_FiveColumns;
    [Test] procedure AtomicStyle_WithTrailingImageFlags;
    [Test] procedure ChargeStyle_Columns;
    [Test] procedure MolecularStyle_Columns;
    [Test] procedure NoStyleComment_InfersFullLayout;
    [Test] procedure LyingStyleComment_IsCorrectedByInference;
    [Test] procedure HeaderAtomCount_KeptAndWarned;
    [Test] procedure AtomTypeColor_TwentyDistinctThenWraps;
    [Test] procedure MassesAndBoxBounds_StillParse;

    [Test] procedure Dump_ParsesAtomsFromNamedColumns;
    [Test] procedure Dump_ReadsHeaderCountAndBox;
    [Test] procedure Dump_MultiFrameKeepsLastFrame;
    [Test] procedure Dump_ScaledCoordsAreUnscaledToBox;
    [Test] procedure BinaryRestart_IsDetectedAndNotParsedAsText;
    [Test] procedure Clear_DropsPreviousFileState;
  end;

implementation

type
  TLAMMPSFixture = record
    Name: string;
    Text: string;
  end;

const
  FIXTURES: array[0..10] of TLAMMPSFixture = (
    (Name: 'lammps_full.data'; Text:
      'LAMMPS data file - full style fixture'#13#10 +
      ''#13#10 +
      '6 atoms'#13#10 +
      '4 bonds'#13#10 +
      '2 angles'#13#10 +
      ''#13#10 +
      '2 atom types'#13#10 +
      '1 bond types'#13#10 +
      '1 angle types'#13#10 +
      ''#13#10 +
      '0.000000 20.000000 xlo xhi'#13#10 +
      '0.000000 21.000000 ylo yhi'#13#10 +
      '0.000000 22.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 1.0080 # HW'#13#10 +
      '2 15.9994 # OW'#13#10 +
      ''#13#10 +
      'Atoms # full'#13#10 +
      ''#13#10 +
      '1 1 2 -0.847600 1.100000 2.200000 3.300000'#13#10 +
      '2 1 1 0.423800 4.400000 5.500000 6.600000'#13#10 +
      '3 2 1 0.423800 7.700000 8.800000 9.900000'#13#10 +
      '4 2 2 -0.847600 10.100000 11.200000 12.300000'#13#10 +
      '5 3 1 0.423800 13.400000 14.500000 15.600000'#13#10 +
      '6 3 2 -0.847600 16.700000 17.800000 18.900000'#13#10),
    (Name: 'lammps_atomic.data'; Text:
      'LAMMPS data file - atomic style fixture, no image flags'#13#10 +
      ''#13#10 +
      '5 atoms'#13#10 +
      ''#13#10 +
      '4 atom types'#13#10 +
      ''#13#10 +
      '0.000000 30.000000 xlo xhi'#13#10 +
      '0.000000 31.000000 ylo yhi'#13#10 +
      '0.000000 32.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 28.0855'#13#10 +
      '2 15.9994'#13#10 +
      '3 26.9815'#13#10 +
      '4 12.0110'#13#10 +
      ''#13#10 +
      'Atoms # atomic'#13#10 +
      ''#13#10 +
      '1 1 1.500000 2.500000 3.500000'#13#10 +
      '2 2 4.500000 5.500000 6.500000'#13#10 +
      '3 3 7.500000 8.500000 9.500000'#13#10 +
      '4 4 10.500000 11.500000 12.500000'#13#10 +
      '5 1 13.500000 14.500000 15.500000'#13#10),
    (Name: 'lammps_atomic_image.data'; Text:
      'LAMMPS data file - atomic style fixture with trailing image flags'#13#10 +
      ''#13#10 +
      '4 atoms'#13#10 +
      ''#13#10 +
      '2 atom types'#13#10 +
      ''#13#10 +
      '0.000000 40.000000 xlo xhi'#13#10 +
      '0.000000 41.000000 ylo yhi'#13#10 +
      '0.000000 42.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 28.0855'#13#10 +
      '2 15.9994'#13#10 +
      ''#13#10 +
      'Atoms # atomic'#13#10 +
      ''#13#10 +
      '1 1 1.250000 2.250000 3.250000 0 0 0'#13#10 +
      '2 2 4.250000 5.250000 6.250000 1 0 -1'#13#10 +
      '3 1 7.250000 8.250000 9.250000 0 1 0'#13#10 +
      '4 2 10.250000 11.250000 12.250000 -1 -1 1'#13#10),
    (Name: 'lammps_charge.data'; Text:
      'LAMMPS data file - charge style fixture'#13#10 +
      ''#13#10 +
      '4 atoms'#13#10 +
      ''#13#10 +
      '3 atom types'#13#10 +
      ''#13#10 +
      '0.000000 50.000000 xlo xhi'#13#10 +
      '0.000000 51.000000 ylo yhi'#13#10 +
      '0.000000 52.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 28.0855'#13#10 +
      '2 15.9994'#13#10 +
      '3 12.0110'#13#10 +
      ''#13#10 +
      'Atoms # charge'#13#10 +
      ''#13#10 +
      '1 1 1.200000 1.750000 2.750000 3.750000'#13#10 +
      '2 2 -0.600000 4.750000 5.750000 6.750000'#13#10 +
      '3 3 0.000000 7.750000 8.750000 9.750000'#13#10 +
      '4 1 1.200000 10.750000 11.750000 12.750000'#13#10),
    (Name: 'lammps_molecular.data'; Text:
      'LAMMPS data file - molecular style fixture'#13#10 +
      ''#13#10 +
      '4 atoms'#13#10 +
      '2 bonds'#13#10 +
      ''#13#10 +
      '2 atom types'#13#10 +
      '1 bond types'#13#10 +
      ''#13#10 +
      '0.000000 60.000000 xlo xhi'#13#10 +
      '0.000000 61.000000 ylo yhi'#13#10 +
      '0.000000 62.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 12.0110'#13#10 +
      '2 1.0080'#13#10 +
      ''#13#10 +
      'Atoms # molecular'#13#10 +
      ''#13#10 +
      '1 1 1 1.125000 2.125000 3.125000'#13#10 +
      '2 1 2 4.125000 5.125000 6.125000'#13#10 +
      '3 2 2 7.125000 8.125000 9.125000'#13#10 +
      '4 3 1 10.125000 11.125000 12.125000'#13#10),
    (Name: 'lammps_nostyle.data'; Text:
      'LAMMPS data file - full layout with no style comment on the Atoms header'#13#10 +
      ''#13#10 +
      '5 atoms'#13#10 +
      '3 bonds'#13#10 +
      ''#13#10 +
      '2 atom types'#13#10 +
      '1 bond types'#13#10 +
      ''#13#10 +
      '0.000000 70.000000 xlo xhi'#13#10 +
      '0.000000 71.000000 ylo yhi'#13#10 +
      '0.000000 72.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 1.0080'#13#10 +
      '2 15.9994'#13#10 +
      ''#13#10 +
      'Atoms'#13#10 +
      ''#13#10 +
      '1 1 2 -0.847600 1.375000 2.375000 3.375000'#13#10 +
      '2 1 1 0.423800 4.375000 5.375000 6.375000'#13#10 +
      '3 2 1 0.423800 7.375000 8.375000 9.375000'#13#10 +
      '4 3 2 -0.847600 10.375000 11.375000 12.375000'#13#10 +
      '5 4 1 0.423800 13.375000 14.375000 15.375000'#13#10),
    (Name: 'lammps_lyingstyle.data'; Text:
      'LAMMPS data file - full layout mislabelled as atomic'#13#10 +
      ''#13#10 +
      '5 atoms'#13#10 +
      '3 bonds'#13#10 +
      ''#13#10 +
      '2 atom types'#13#10 +
      '1 bond types'#13#10 +
      ''#13#10 +
      '0.000000 80.000000 xlo xhi'#13#10 +
      '0.000000 81.000000 ylo yhi'#13#10 +
      '0.000000 82.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 1.0080'#13#10 +
      '2 15.9994'#13#10 +
      ''#13#10 +
      'Atoms # atomic'#13#10 +
      ''#13#10 +
      '1 1 2 -0.847600 1.625000 2.625000 3.625000'#13#10 +
      '2 1 1 0.423800 4.625000 5.625000 6.625000'#13#10 +
      '3 2 1 0.423800 7.625000 8.625000 9.625000'#13#10 +
      '4 3 2 -0.847600 10.625000 11.625000 12.625000'#13#10 +
      '5 4 1 0.423800 13.625000 14.625000 15.625000'#13#10),
    (Name: 'lammps_countmismatch.data'; Text:
      'LAMMPS data file - header declares more atoms than the body carries'#13#10 +
      ''#13#10 +
      '10 atoms'#13#10 +
      ''#13#10 +
      '2 atom types'#13#10 +
      ''#13#10 +
      '0.000000 90.000000 xlo xhi'#13#10 +
      '0.000000 91.000000 ylo yhi'#13#10 +
      '0.000000 92.000000 zlo zhi'#13#10 +
      ''#13#10 +
      'Masses'#13#10 +
      ''#13#10 +
      '1 28.0855'#13#10 +
      '2 15.9994'#13#10 +
      ''#13#10 +
      'Atoms # atomic'#13#10 +
      ''#13#10 +
      '1 1 1.500000 2.500000 3.500000'#13#10 +
      '2 2 4.500000 5.500000 6.500000'#13#10 +
      '3 1 7.500000 8.500000 9.500000'#13#10 +
      '4 2 10.500000 11.500000 12.500000'#13#10),
    (Name: 'lammps_frame.dump'; Text:
      'ITEM: TIMESTEP'#13#10 +
      '2102813'#13#10 +
      'ITEM: NUMBER OF ATOMS'#13#10 +
      '6'#13#10 +
      'ITEM: BOX BOUNDS pp pp ff'#13#10 +
      '0.0000000000000000e+00 6.8866339999999994e+01'#13#10 +
      '0.0000000000000000e+00 7.2420000000000002e+01'#13#10 +
      '0.0000000000000000e+00 2.2719850900000000e+02'#13#10 +
      'ITEM: ATOMS id type q x y z ix iy iz'#13#10 +
      '1 15 1.1 6.05824 15.6859 6.30761 0 0 0'#13#10 +
      '2 15 1.1 58.6866 9.92129 16.5881 0 0 0'#13#10 +
      '3 2 -0.55 9.89903 35.1769 18.0285 0 0 0'#13#10 +
      '4 3 -0.55 10.1 36.2 19.3 0 0 0'#13#10 +
      '5 1 2.1 11.0 37.0 20.0 0 0 0'#13#10 +
      '6 4 0.4 12.0 38.0 21.0 0 0 0'#13#10),
    (Name: 'lammps_traj.dump'; Text:
      'ITEM: TIMESTEP'#13#10 +
      '100'#13#10 +
      'ITEM: NUMBER OF ATOMS'#13#10 +
      '2'#13#10 +
      'ITEM: BOX BOUNDS pp pp pp'#13#10 +
      '0.0 10.0'#13#10 +
      '0.0 10.0'#13#10 +
      '0.0 10.0'#13#10 +
      'ITEM: ATOMS id type x y z'#13#10 +
      '1 1 1.0 1.0 1.0'#13#10 +
      '2 2 2.0 2.0 2.0'#13#10 +
      'ITEM: TIMESTEP'#13#10 +
      '200'#13#10 +
      'ITEM: NUMBER OF ATOMS'#13#10 +
      '3'#13#10 +
      'ITEM: BOX BOUNDS pp pp pp'#13#10 +
      '0.0 20.0'#13#10 +
      '0.0 20.0'#13#10 +
      '0.0 20.0'#13#10 +
      'ITEM: ATOMS id type x y z'#13#10 +
      '1 1 5.0 5.0 5.0'#13#10 +
      '2 2 6.0 6.0 6.0'#13#10 +
      '3 3 7.0 7.0 7.0'#13#10),
    (Name: 'lammps_scaled.dump'; Text:
      'ITEM: TIMESTEP'#13#10 +
      '0'#13#10 +
      'ITEM: NUMBER OF ATOMS'#13#10 +
      '2'#13#10 +
      'ITEM: BOX BOUNDS pp pp pp'#13#10 +
      '0.0 10.0'#13#10 +
      '0.0 20.0'#13#10 +
      '0.0 40.0'#13#10 +
      'ITEM: ATOMS id type xs ys zs'#13#10 +
      '1 1 0.5 0.5 0.5'#13#10 +
      '2 2 0.25 0.75 0.1'#13#10));
  BINARY_RESTART: array[0..27] of Byte = (
    $4C, $61, $6D, $6D, $70, $53, $20, $52, $65, $73, $74, $61, $72, $74, $54, $00, $01, $00, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00);

function TLAMMPSParserTests.DataPath(const AName: string): string;
var
  Fixture: TLAMMPSFixture;
  Bytes: TBytes;
begin
  Result := TPath.Combine(FDir, AName);
  if AName = 'lammps_binary.restart' then
  begin
    SetLength(Bytes, Length(BINARY_RESTART));
    Move(BINARY_RESTART[0], Bytes[0], Length(BINARY_RESTART));
    TFile.WriteAllBytes(Result, Bytes);
    Exit;
  end;
  for Fixture in FIXTURES do
    if Fixture.Name = AName then
    begin
      TFile.WriteAllBytes(Result, TEncoding.ASCII.GetBytes(Fixture.Text));
      Exit;
    end;
  raise EFileNotFoundException.Create(AName);
end;

function TLAMMPSParserTests.DistinctAtomTypes: Integer;
var
  Seen: TDictionary<Integer, Boolean>;
  I: Integer;
begin
  Seen := TDictionary<Integer, Boolean>.Create;
  try
    for I := 0 to FDump.AtomCount - 1 do
      Seen.AddOrSetValue(FDump.Atoms[I].AtomType, True);
    Result := Seen.Count;
  finally
    Seen.Free;
  end;
end;

procedure TLAMMPSParserTests.Setup;
begin
  FDump := TLAMMPSDumpFile.Create;
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_LAMMPSParser_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TLAMMPSParserTests.TearDown;
begin
  FDump.Free;
  TDirectory.Delete(FDir, True);
end;

procedure TLAMMPSParserTests.FullStyle_ReadsTypeAndCoordsFromRightColumns;
begin
  FDump.ParseFromFile(DataPath('lammps_full.data'));

  Assert.AreEqual('full', FDump.AtomStyle);
  Assert.AreEqual(6, FDump.AtomCount);
  Assert.AreEqual(2, FDump.AtomTypeCount);

  Assert.AreEqual(1, FDump.Atoms[0].ID);
  Assert.AreEqual(2, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(1.1), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(2.2), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(3.3), FDump.Atoms[0].Z, 1E-9);

  Assert.AreEqual(5, FDump.Atoms[4].ID);
  Assert.AreEqual(1, FDump.Atoms[4].AtomType);
  Assert.AreEqual(Double(13.4), FDump.Atoms[4].X, 1E-9);
  Assert.AreEqual(Double(14.5), FDump.Atoms[4].Y, 1E-9);
  Assert.AreEqual(Double(15.6), FDump.Atoms[4].Z, 1E-9);

  Assert.AreEqual(2, FDump.Atoms[5].AtomType);
  Assert.AreEqual(Double(16.7), FDump.Atoms[5].X, 1E-9);
end;

// Regression: the viewer builds one series+colour per distinct AtomType.
// Reading the molecule id as the type yields 3 series here (and thousands
// on a real water box) instead of the 2 the header declares.
procedure TLAMMPSParserTests.FullStyle_DistinctTypesMatchHeaderNotMolecules;
begin
  FDump.ParseFromFile(DataPath('lammps_full.data'));
  Assert.AreEqual(FDump.AtomTypeCount, DistinctAtomTypes,
    'distinct atom types must match the declared "N atom types"');
  Assert.AreEqual(2, DistinctAtomTypes);
end;

procedure TLAMMPSParserTests.AtomicStyle_FiveColumns;
begin
  FDump.ParseFromFile(DataPath('lammps_atomic.data'));

  Assert.AreEqual('atomic', FDump.AtomStyle);
  Assert.AreEqual(5, FDump.AtomCount);
  Assert.AreEqual(4, FDump.AtomTypeCount);
  Assert.AreEqual(4, DistinctAtomTypes);

  Assert.AreEqual(1, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(1.5), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(2.5), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(3.5), FDump.Atoms[0].Z, 1E-9);

  Assert.AreEqual(4, FDump.Atoms[3].AtomType);
  Assert.AreEqual(Double(10.5), FDump.Atoms[3].X, 1E-9);
  Assert.AreEqual(Double(12.5), FDump.Atoms[3].Z, 1E-9);
end;

procedure TLAMMPSParserTests.AtomicStyle_WithTrailingImageFlags;
begin
  FDump.ParseFromFile(DataPath('lammps_atomic_image.data'));

  Assert.AreEqual('atomic', FDump.AtomStyle);
  Assert.AreEqual(4, FDump.AtomCount);
  Assert.AreEqual(2, FDump.AtomTypeCount);
  Assert.AreEqual(2, DistinctAtomTypes);

  Assert.AreEqual(1, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(1.25), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(2.25), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(3.25), FDump.Atoms[0].Z, 1E-9);

  Assert.AreEqual(2, FDump.Atoms[3].AtomType);
  Assert.AreEqual(Double(10.25), FDump.Atoms[3].X, 1E-9);
  Assert.AreEqual(Double(11.25), FDump.Atoms[3].Y, 1E-9);
  Assert.AreEqual(Double(12.25), FDump.Atoms[3].Z, 1E-9);
end;

procedure TLAMMPSParserTests.ChargeStyle_Columns;
begin
  FDump.ParseFromFile(DataPath('lammps_charge.data'));

  Assert.AreEqual('charge', FDump.AtomStyle);
  Assert.AreEqual(4, FDump.AtomCount);
  Assert.AreEqual(3, FDump.AtomTypeCount);

  Assert.AreEqual(1, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(1.75), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(2.75), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(3.75), FDump.Atoms[0].Z, 1E-9);

  Assert.AreEqual(3, FDump.Atoms[2].AtomType);
  Assert.AreEqual(Double(7.75), FDump.Atoms[2].X, 1E-9);
  Assert.AreEqual(Double(9.75), FDump.Atoms[2].Z, 1E-9);
end;

procedure TLAMMPSParserTests.MolecularStyle_Columns;
begin
  FDump.ParseFromFile(DataPath('lammps_molecular.data'));

  Assert.AreEqual('molecular', FDump.AtomStyle);
  Assert.AreEqual(4, FDump.AtomCount);
  Assert.AreEqual(2, FDump.AtomTypeCount);
  Assert.AreEqual(2, DistinctAtomTypes);

  Assert.AreEqual(1, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(1.125), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(2.125), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(3.125), FDump.Atoms[0].Z, 1E-9);

  Assert.AreEqual(1, FDump.Atoms[3].AtomType);
  Assert.AreEqual(Double(10.125), FDump.Atoms[3].X, 1E-9);
end;

procedure TLAMMPSParserTests.NoStyleComment_InfersFullLayout;
begin
  FDump.ParseFromFile(DataPath('lammps_nostyle.data'));

  Assert.AreEqual('inferred', FDump.AtomStyle);
  Assert.AreEqual(5, FDump.AtomCount);
  Assert.AreEqual(2, DistinctAtomTypes);

  Assert.AreEqual(2, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(1.375), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(2.375), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(3.375), FDump.Atoms[0].Z, 1E-9);

  Assert.AreEqual(1, FDump.Atoms[4].AtomType);
  Assert.AreEqual(Double(13.375), FDump.Atoms[4].X, 1E-9);
  Assert.AreEqual(Double(15.375), FDump.Atoms[4].Z, 1E-9);
end;

// "Atoms # atomic" over a full layout: column 1 carries mol ids that run
// past the declared atom-type count, so the comment must be overruled.
procedure TLAMMPSParserTests.LyingStyleComment_IsCorrectedByInference;
begin
  FDump.ParseFromFile(DataPath('lammps_lyingstyle.data'));

  Assert.IsTrue(FDump.AtomStyle.EndsWith('(corrected)'),
    'expected a corrected style, got: ' + FDump.AtomStyle);
  Assert.AreEqual('atomic (corrected)', FDump.AtomStyle);
  Assert.AreEqual(5, FDump.AtomCount);
  Assert.AreEqual(2, DistinctAtomTypes);

  Assert.AreEqual(2, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(1.625), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(2.625), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(3.625), FDump.Atoms[0].Z, 1E-9);
end;

procedure TLAMMPSParserTests.HeaderAtomCount_KeptAndWarned;
var
  Summary: string;
begin
  FDump.ParseFromFile(DataPath('lammps_countmismatch.data'));

  Assert.AreEqual(10, FDump.HeaderAtomCount);
  Assert.AreEqual(4, FDump.AtomCount);   

  Summary := FDump.GetSummaryText;
  Assert.IsTrue(Summary.Contains('Atom style: atomic'),
    'summary should name the atom style');
  Assert.IsTrue(Summary.Contains('WARNING: header declares 10 atoms, parsed 4'),
    'summary should warn about the count mismatch');

  FDump.ParseFromFile(DataPath('lammps_full.data'));
  Assert.AreEqual(6, FDump.HeaderAtomCount);
  Assert.AreEqual(6, FDump.AtomCount);
  Assert.IsFalse(FDump.GetSummaryText.Contains('WARNING'));
end;

procedure TLAMMPSParserTests.AtomTypeColor_TwentyDistinctThenWraps;
var
  I, J: Integer;
  Colors: array[1..20] of Integer;
begin
  for I := 1 to 20 do
    Colors[I] := FDump.AtomTypeColor(I);

  for I := 1 to 20 do
    for J := I + 1 to 20 do
      Assert.AreNotEqual(Colors[I], Colors[J],
        Format('types %d and %d share a colour', [I, J]));

  Assert.AreEqual(Colors[1], FDump.AtomTypeColor(21));
  Assert.AreEqual(Colors[2], FDump.AtomTypeColor(22));

  Assert.AreEqual(Colors[1], FDump.AtomTypeColor(0));
  Assert.AreEqual(Colors[1], FDump.AtomTypeColor(-7));
end;

procedure TLAMMPSParserTests.MassesAndBoxBounds_StillParse;
begin
  FDump.ParseFromFile(DataPath('lammps_full.data'));

  Assert.AreEqual<NativeInt>(2, Length(FDump.Masses));
  Assert.AreEqual(1, FDump.Masses[0].AtomType);
  Assert.AreEqual(Double(1.008), FDump.Masses[0].Mass, 1E-9);
  Assert.AreEqual(2, FDump.Masses[1].AtomType);
  Assert.AreEqual(Double(15.9994), FDump.Masses[1].Mass, 1E-9);

  Assert.AreEqual(Double(0), FDump.Box.XLo, 1E-9);
  Assert.AreEqual(Double(20), FDump.Box.XHi, 1E-9);
  Assert.AreEqual(Double(21), FDump.Box.YHi, 1E-9);
  Assert.AreEqual(Double(22), FDump.Box.ZHi, 1E-9);
  Assert.IsFalse(FDump.HasVelocities);

  FDump.ParseFromFile(DataPath('lammps_atomic.data'));
  Assert.AreEqual<NativeInt>(4, Length(FDump.Masses));
  Assert.AreEqual(Double(12.011), FDump.Masses[3].Mass, 1E-9);
  Assert.AreEqual(Double(30), FDump.Box.XHi, 1E-9);
  Assert.AreEqual(Double(32), FDump.Box.ZHi, 1E-9);
end;

// dump custom: id type q x y z ix iy iz - the column names on the
// "ITEM: ATOMS" line say which column is which, so nothing is inferred.
procedure TLAMMPSParserTests.Dump_ParsesAtomsFromNamedColumns;
begin
  FDump.ParseFromFile(DataPath('lammps_frame.dump'));

  Assert.AreEqual(6, FDump.AtomCount);
  Assert.AreEqual(5, DistinctAtomTypes);

  Assert.AreEqual(1, FDump.Atoms[0].ID);
  Assert.AreEqual(15, FDump.Atoms[0].AtomType);
  Assert.AreEqual(Double(6.05824), FDump.Atoms[0].X, 1E-6);
  Assert.AreEqual(Double(15.6859), FDump.Atoms[0].Y, 1E-6);
  Assert.AreEqual(Double(6.30761), FDump.Atoms[0].Z, 1E-6);

  Assert.AreEqual(3, FDump.Atoms[2].ID);
  Assert.AreEqual(2, FDump.Atoms[2].AtomType);
  Assert.AreEqual(Double(9.89903), FDump.Atoms[2].X, 1E-6);
end;

procedure TLAMMPSParserTests.Dump_ReadsHeaderCountAndBox;
begin
  FDump.ParseFromFile(DataPath('lammps_frame.dump'));

  Assert.AreEqual(6, FDump.HeaderAtomCount);
  Assert.AreEqual(Int64(2102813), FDump.Timestep);
  Assert.IsTrue(FDump.IsDumpFormat);

  Assert.AreEqual(Double(0), FDump.Box.XLo, 1E-9);
  Assert.AreEqual(Double(68.86634), FDump.Box.XHi, 1E-5);
  Assert.AreEqual(Double(72.42), FDump.Box.YHi, 1E-5);
  Assert.AreEqual(Double(227.198509), FDump.Box.ZHi, 1E-5);
end;

procedure TLAMMPSParserTests.Dump_MultiFrameKeepsLastFrame;
begin
  FDump.ParseFromFile(DataPath('lammps_traj.dump'));

  Assert.AreEqual(2, FDump.FrameCount);
  Assert.AreEqual(Int64(200), FDump.Timestep);
  Assert.AreEqual(3, FDump.AtomCount);
  Assert.AreEqual(Double(5), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(20), FDump.Box.XHi, 1E-9);
end;

// xs/ys/zs are box fractions; the viewer plots real coordinates.
procedure TLAMMPSParserTests.Dump_ScaledCoordsAreUnscaledToBox;
begin
  FDump.ParseFromFile(DataPath('lammps_scaled.dump'));

  Assert.AreEqual(2, FDump.AtomCount);
  Assert.AreEqual(Double(5), FDump.Atoms[0].X, 1E-9);
  Assert.AreEqual(Double(10), FDump.Atoms[0].Y, 1E-9);
  Assert.AreEqual(Double(20), FDump.Atoms[0].Z, 1E-9);

  Assert.AreEqual(Double(2.5), FDump.Atoms[1].X, 1E-9);
  Assert.AreEqual(Double(15), FDump.Atoms[1].Y, 1E-9);
  Assert.AreEqual(Double(4), FDump.Atoms[1].Z, 1E-9);
end;

// write_restart output is binary; it must be reported as such rather than
// silently parsing to zero atoms, which reads as "the file is empty".
procedure TLAMMPSParserTests.BinaryRestart_IsDetectedAndNotParsedAsText;
begin
  FDump.ParseFromFile(DataPath('lammps_binary.restart'));

  Assert.IsTrue(FDump.IsBinaryRestart);
  Assert.IsFalse(FDump.IsDumpFormat);
  Assert.AreEqual(0, FDump.AtomCount);
  Assert.Contains(FDump.GetSummaryText.ToLower, 'restart');

  FDump.ParseFromFile(DataPath('lammps_atomic.data'));
  Assert.IsFalse(FDump.IsBinaryRestart);
end;

// One parser instance is reused across files, so a file that is never parsed
// (an .lmpin deck) must not keep reporting the previous file's atoms.
procedure TLAMMPSParserTests.Clear_DropsPreviousFileState;
begin
  FDump.ParseFromFile(DataPath('lammps_atomic.data'));
  Assert.IsTrue(FDump.AtomCount > 0, 'fixture should parse');

  FDump.Clear;

  Assert.AreEqual(0, FDump.AtomCount);
  Assert.AreEqual(0, FDump.AtomTypeCount);
  Assert.AreEqual(0, FDump.HeaderAtomCount);
  Assert.AreEqual<NativeInt>(0, Length(FDump.Masses));
  Assert.AreEqual('', FDump.AtomStyle);
  Assert.AreEqual('', FDump.FileName);
  Assert.AreEqual(Double(0), FDump.Box.XHi, 1E-9);
  Assert.AreEqual(Double(0), FDump.Box.ZHi, 1E-9);
  Assert.IsFalse(FDump.IsDumpFormat);
  Assert.IsFalse(FDump.IsBinaryRestart);
end;

initialization
  TDUnitX.RegisterTestFixture(TLAMMPSParserTests);

end.
