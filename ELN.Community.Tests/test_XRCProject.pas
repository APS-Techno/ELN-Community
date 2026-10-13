unit test_XRCProject;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils,
  System.Zip, System.Generics.Collections, System.JSON, unit_ELNPluginTypes,
  unit_XRCProject, unit_XRCProjectOutput;

type
  TXRCFixtureBase = class
  protected
    FDir: string;
    function LenStr(const S: string): TBytes;
    function Payload(ID: Integer; const Title: string; RowType, Group, Enabled,
      ExtType: Byte; LayerID, StackID: Integer; Form, Subj: Byte;
      const Tail: TBytes): TBytes;
    function Node(const APayload: TBytes; const Children: array of TBytes): TBytes;
    function GroupNode(Group: Byte; const Children: array of TBytes): TBytes;
    function ModelNode(ID: Integer; const Title, Json: string;
      const Children: array of TBytes): TBytes;
    function ExtNode(Stack, Layer: Integer; Subj: Byte; const Coefs: array of Single): TBytes;
    function DataNode(ID: Integer; const Title: string): TBytes;
    function Tree(const Roots: array of TBytes): TBytes;
    function WriteXRCX(const Name, Params: string; const ProjectDsc: TBytes;
      const DatNames: array of string): string;
    function WriteXRCXRaw(const Name: string; const Params, ProjectDsc: TBytes;
      const DatNames: array of string): string;
    function StdTree(const Json: string): TBytes;
    function Params8(const Extra: string = ''): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
  end;

  [TestFixture]
  TXRCProjectTests = class(TXRCFixtureBase)
  public
    [Test] procedure V8_PolynomialThicknessProfileApplied;
    [Test] procedure ActiveModelSelectedById;
    [Test] procedure UnknownActiveModelFallsBackToFirst;
    [Test] procedure ExtensionOfOtherModelIgnored;
    [Test] procedure TwoThetaRangeHalved;
    [Test] procedure FitFlagsAndRangesRead;
    [Test] procedure InvertedRangeReported;
    [Test] procedure FitResultAbsentWhenNoSection;
    [Test] procedure FitResultRead;
    [Test] procedure CurveRolesFromEntryNames;
    [Test] procedure Legacy_NoTreeFallsBackToJsonScan;
    [Test] procedure CorruptTreeDoesNotRaise;
    [Test] procedure FormatVersionRead;
    [Test] procedure Utf8BomParamsStillReadVersion;
    [Test] procedure OddTitleByteLengthFallsBack;
    [Test] procedure HugeStringLengthFallsBack;
  end;

  [TestFixture]
  TXRCProjectOutputTests = class(TXRCFixtureBase)
  private
    function Info(const P: TXRCProject): TJSONObject;
    function FindKV(const KVs: TArray<TPluginKeyValue>; const Name: string;
      out KV: TPluginKeyValue): Boolean;
    function Names(const KVs: TArray<TPluginKeyValue>): string;
  public
    [Test] procedure Json_TopLevelKeys;
    [Test] procedure Json_PeriodOnlyForRepeatedStacks;
    [Test] procedure Json_ProfileOnlyWhenPresent;
    [Test] procedure Json_SubstrateDensityUsed;
    [Test] procedure Json_NullSectionsWithoutParams;
    [Test] procedure Json_LegacyBinHasNoFit;
    [Test] procedure Json_FitResultAndCurves;
    [Test] procedure Json_CurveRangeInThetaWhenFileStoresTwoTheta;
    [Test] procedure Keys_PeriodAndChi2AreKey;
    [Test] procedure Keys_ConditionsAndUnits;
    [Test] procedure Keys_RepeatedMaterialSuffix;
    [Test] procedure LayerSequence_UsesProfile;
  end;

const
  WSI_JSON = '{"Stacks":[{"T":"ML","N":5,"Layers":[' +
    '{"M":"W","H":10,"s":3,"r":19.3},{"M":"Si","H":15,"s":4,"r":2.33}]}],' +
    '"Subs":{"M":"SiO2","s":3,"r":2.2}}';
  MO_JSON = '{"Stacks":[{"T":"ML","N":2,"Layers":[{"M":"Mo","H":20,"s":3,"r":10.2}]}],' +
    '"Subs":{"M":"Si","s":2,"r":2.33}}';
  CURVE_TEXT = '0.1'#9'1'#13#10'0.2'#9'0.5'#13#10'0.3'#9'0.25'#13#10;

implementation

procedure TXRCFixtureBase.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'ELN_XRC_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TXRCFixtureBase.TearDown;
begin
  TDirectory.Delete(FDir, True);
end;

function TXRCFixtureBase.LenStr(const S: string): TBytes;
var
  Body: TBytes;
  Size: Integer;
begin
  Body := TEncoding.Unicode.GetBytes(S);
  Size := Length(Body) + 1;
  SetLength(Result, 4 + Size);
  Move(Size, Result[0], 4);
  if Length(Body) > 0 then
    Move(Body[0], Result[4], Length(Body));
  Result[High(Result)] := 0;
end;

function Cat(const Parts: array of TBytes): TBytes;
var
  I, P: Integer;
begin
  P := 0;
  for I := 0 to High(Parts) do
    Inc(P, Length(Parts[I]));
  SetLength(Result, P);
  P := 0;
  for I := 0 to High(Parts) do
    if Length(Parts[I]) > 0 then
    begin
      Move(Parts[I][0], Result[P], Length(Parts[I]));
      Inc(P, Length(Parts[I]));
    end;
end;

function I32(V: Integer): TBytes;
begin
  SetLength(Result, 4);
  Move(V, Result[0], 4);
end;

function B1(V: Byte): TBytes;
begin
  Result := [V];
end;

function Chunk(Kind: Integer; const Body: TBytes): TBytes;
begin
  Result := Cat([I32(Kind), I32(Length(Body)), Body]);
end;

function TXRCFixtureBase.Payload(ID: Integer; const Title: string; RowType,
  Group, Enabled, ExtType: Byte; LayerID, StackID: Integer; Form, Subj: Byte;
  const Tail: TBytes): TBytes;
begin
  Result := Cat([I32(ID), LenStr(Title), B1(RowType), B1(Group), B1(1), B1(1),
    LenStr(''), I32(0), B1(Enabled), B1(ExtType), I32(LayerID), I32(StackID),
    B1(Form), B1(Subj), Tail]);
end;

function TXRCFixtureBase.Node(const APayload: TBytes; const Children: array of TBytes): TBytes;
var
  Base: TBytes;
  Pad: TBytes;
begin
  SetLength(Pad, 15);
  FillChar(Pad[0], 15, 0);
  Base := Cat([I32(Length(Children)), Pad, Cat(Children)]);
  Result := Chunk(1, Cat([Chunk(2, Base), Chunk(4, APayload)]));
end;

function TXRCFixtureBase.GroupNode(Group: Byte; const Children: array of TBytes): TBytes;
begin
  Result := Node(Payload(0, 'G', 0, Group, 0, 0, 0, 0, 0, 0, nil), Children);
end;

function TXRCFixtureBase.ModelNode(ID: Integer; const Title, Json: string;
  const Children: array of TBytes): TBytes;
begin
  Result := Node(Payload(ID, Title, 1, 0, 0, 0, 0, 0, 0, 0, LenStr(Json)), Children);
end;

function TXRCFixtureBase.ExtNode(Stack, Layer: Integer; Subj: Byte;
  const Coefs: array of Single): TBytes;
var
  Tail: TBytes;
  I: Integer;
  F: TBytes;
begin
  Tail := I32(Length(Coefs));
  for I := 0 to High(Coefs) do
  begin
    SetLength(F, 4);
    Move(Coefs[I], F[0], 4);
    Tail := Cat([Tail, F]);
  end;
  Result := Node(Payload(0, 'Ext', 3, 0, 1, 1, Layer, Stack, 1, Subj, Tail), []);
end;

function TXRCFixtureBase.DataNode(ID: Integer; const Title: string): TBytes;
begin
  Result := Node(Payload(ID, Title, 1, 1, 0, 0, 0, 0, 0, 0, nil), []);
end;

function TXRCFixtureBase.Tree(const Roots: array of TBytes): TBytes;
var
  Magic: TBytes;
  Count: Cardinal;
  C: TBytes;
begin
  Magic := TEncoding.Unicode.GetBytes(#$2045'VT'#3' '#$2046);
  Count := Length(Roots);
  SetLength(C, 4);
  Move(Count, C[0], 4);
  Result := Cat([Magic, C, Cat(Roots)]);
end;

function TXRCFixtureBase.StdTree(const Json: string): TBytes;
begin
  Result := Tree([GroupNode(0, [ModelNode(1, 'Model', Json, [])]),
    GroupNode(1, [DataNode(2, 'meas.dat')])]);
end;

function TXRCFixtureBase.Params8(const Extra: string): string;
begin
  Result := '[INFO]'#13#10'Version=8'#13#10 +
    '[ANGLE]'#13#10'Start=0.05'#13#10'End=5'#13#10'lambbda=1.54043'#13#10 +
    'width=0.015'#13#10'2teta=0'#13#10 +
    '[STATE]'#13#10'ActiveModel=1'#13#10'LinkedData=2'#13#10 + Extra;
end;

function TXRCFixtureBase.WriteXRCX(const Name, Params: string;
  const ProjectDsc: TBytes; const DatNames: array of string): string;
var
  B: TBytes;
begin
  if Params <> '' then
    B := TEncoding.ANSI.GetBytes(Params)
  else
    B := nil;
  Result := WriteXRCXRaw(Name, B, ProjectDsc, DatNames);
end;

function TXRCFixtureBase.WriteXRCXRaw(const Name: string; const Params,
  ProjectDsc: TBytes; const DatNames: array of string): string;
var
  Zip: TZipFile;
  D: string;
begin
  Result := TPath.Combine(FDir, Name);
  Zip := TZipFile.Create;
  try
    Zip.Open(Result, zmWrite);
    if Length(Params) > 0 then
      Zip.Add(Params, 'params.dsc');
    if Length(ProjectDsc) > 0 then
      Zip.Add(ProjectDsc, 'project.dsc');
    for D in DatNames do
      Zip.Add(TEncoding.ANSI.GetBytes(CURVE_TEXT), D);
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

function PatchTitleSize(const Tree: TBytes; NewSize: Integer): TBytes;
var
  I, Old: Integer;
begin
  Result := Copy(Tree);
  Old := 3;
  for I := 0 to Length(Result) - 7 do
    if CompareMem(@Result[I], @Old, 4) and (Result[I + 4] = $51) and
       (Result[I + 5] = 0) and (Result[I + 6] = 0) then
    begin
      Move(NewSize, Result[I], 4);
      Exit;
    end;
  raise Exception.Create('title Q not found');
end;

procedure TXRCProjectTests.V8_PolynomialThicknessProfileApplied;
var
  P: TXRCProject;
  L: TXRCLayer;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8,
    Tree([GroupNode(0, [ModelNode(1, 'Model', WSI_JSON, [ExtNode(0, 0, 0, [0.5])])]),
      GroupNode(1, [])]), ['calc.dat']));
  Assert.IsTrue(P.Model.Valid);
  L := P.Model.Stacks[0].Layers[0];
  Assert.AreEqual(Ord(pkPolynomial), Ord(L.Profile[xpThickness].Kind));
  Assert.AreEqual(1, Length(L.Profile[xpThickness].Coefficients));
  Assert.AreEqual(0.5, L.Profile[xpThickness].Coefficients[0], 1e-6);
  Assert.AreEqual(10.0, XRCProfileValue(L, xpThickness, 1), 1e-5);
  Assert.AreEqual(12.0, XRCProfileValue(L, xpThickness, 5), 1e-5);
  Assert.AreEqual(Ord(pkNone), Ord(P.Model.Stacks[0].Layers[1].Profile[xpThickness].Kind));
end;

procedure TXRCProjectTests.ActiveModelSelectedById;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx',
    StringReplace(Params8, 'ActiveModel=1', 'ActiveModel=9', []),
    Tree([GroupNode(0, [ModelNode(3, 'First', MO_JSON, []), ModelNode(9, 'Second', WSI_JSON, [])]),
      GroupNode(1, [])]), []));
  Assert.AreEqual('W', P.Model.Stacks[0].Layers[0].Material);
  Assert.AreEqual('Second', P.Model.Title);
  Assert.AreEqual(Ord(msProjectTree), Ord(P.Model.Source));
end;

procedure TXRCProjectTests.UnknownActiveModelFallsBackToFirst;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx',
    StringReplace(Params8, 'ActiveModel=1', 'ActiveModel=42', []),
    Tree([GroupNode(0, [ModelNode(3, 'First', MO_JSON, []), ModelNode(9, 'Second', WSI_JSON, [])]),
      GroupNode(1, [])]), []));
  Assert.AreEqual('Mo', P.Model.Stacks[0].Layers[0].Material);
end;

procedure TXRCProjectTests.ExtensionOfOtherModelIgnored;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx',
    StringReplace(Params8, 'ActiveModel=1', 'ActiveModel=9', []),
    Tree([GroupNode(0, [ModelNode(3, 'First', WSI_JSON, [ExtNode(0, 0, 0, [0.5])]),
      ModelNode(9, 'Second', WSI_JSON, [])]), GroupNode(1, [])]), []));
  Assert.AreEqual('Second', P.Model.Title);
  Assert.AreEqual(Ord(pkNone), Ord(P.Model.Stacks[0].Layers[0].Profile[xpThickness].Kind));
end;

procedure TXRCProjectTests.TwoThetaRangeHalved;
var
  P: TXRCProject;
  S: string;
begin
  S := StringReplace(Params8, 'Start=0.05', 'Start=0.2', []);
  S := StringReplace(S, 'End=5', 'End=8', []);
  S := StringReplace(S, 'width=0.015', 'width=0.02', []);
  S := StringReplace(S, '2teta=0', '2teta=1', []);
  P := LoadXRCProject(WriteXRCX('a.xrcx', S, StdTree(WSI_JSON), []));
  Assert.IsTrue(P.Calculation.Present);
  Assert.AreEqual(0.1, P.Calculation.ThetaMinDeg, 1e-9);
  Assert.AreEqual(4.0, P.Calculation.ThetaMaxDeg, 1e-9);
  Assert.AreEqual(0.02, P.Calculation.ResolutionDeg, 1e-9);
  Assert.AreEqual(1.54043, P.Calculation.WavelengthA, 1e-9);
end;

procedure TXRCProjectTests.FitFlagsAndRangesRead;
var
  P: TXRCProject;
  L: TXRCLayer;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8, StdTree(
    '{"Stacks":[{"T":"ML","N":2,"Layers":[{"M":"W","H":10,"s":3,"r":19.3,' +
    '"HF":true,"SP":true,"Hmin":8,"Hmax":12}]}],"Subs":{"M":"Si","s":2,"r":2.33}}'), []));
  L := P.Model.Stacks[0].Layers[0];
  Assert.IsTrue(L.HasFit);
  Assert.IsTrue(L.Fit[xpThickness].Fixed);
  Assert.IsFalse(L.Fit[xpThickness].Paired);
  Assert.IsTrue(L.Fit[xpRoughness].Paired);
  Assert.AreEqual(8.0, L.Fit[xpThickness].Min, 1e-9);
  Assert.AreEqual(12.0, L.Fit[xpThickness].Max, 1e-9);
  Assert.AreEqual(3.0, L.Fit[xpRoughness].Min, 1e-9);
  Assert.AreEqual(3.0, L.Fit[xpRoughness].Max, 1e-9);
end;

procedure TXRCProjectTests.InvertedRangeReported;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8, StdTree(
    '{"Stacks":[{"T":"ML","N":2,"Layers":[{"M":"W","H":10,"s":3,"r":15,' +
    '"Rmin":20,"Rmax":10}]}],"Subs":{"M":"Si","s":2,"r":2.33}}'), []));
  Assert.AreEqual(1, Length(P.InvertedRanges));
  Assert.AreEqual(Ord(xpDensity), Ord(P.InvertedRanges[0].Param));
  Assert.AreEqual(0, P.InvertedRanges[0].Stack);
  Assert.AreEqual(0, P.InvertedRanges[0].Layer);
end;

procedure TXRCProjectTests.FitResultAbsentWhenNoSection;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8, StdTree(WSI_JSON), []));
  Assert.IsFalse(P.FitResult.Present);
end;

procedure TXRCProjectTests.FitResultRead;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8(
    '[FITRESULT]'#13#10'chiSquared=0.0123'#13#10'chiSquaredPlain=0.0131'#13#10 +
    'chi2Scale=solved'#13#10'scaleRatio=0.97'#13#10'scaleClamped=False'#13#10 +
    'fittingMode=periodic'#13#10'seed=7'#13#10),
    StdTree(WSI_JSON), []));
  Assert.IsTrue(P.FitResult.Present);
  Assert.AreEqual(0.0123, P.FitResult.Chi2, 1e-9);
  Assert.AreEqual(0.0131, P.FitResult.Chi2Plain, 1e-9);
  Assert.AreEqual('solved', P.FitResult.Chi2Scale);
  Assert.AreEqual(Int64(7), P.FitResult.Seed);
end;

procedure TXRCProjectTests.CurveRolesFromEntryNames;
var
  P: TXRCProject;
  C: TXRCCurve;
  Calc, Meas: Boolean;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx',
    StringReplace(Params8, 'LinkedData=2', 'LinkedData=9', []),
    Tree([GroupNode(0, [ModelNode(1, 'Model', WSI_JSON, [])]),
      GroupNode(1, [DataNode(9, 'S1.xrdml')])]), ['calc.dat', 'data_9.dat']));
  Assert.AreEqual(2, Length(P.Curves));
  Calc := False;
  Meas := False;
  for C in P.Curves do
    if C.FileName = 'calc.dat' then
    begin
      Calc := True;
      Assert.AreEqual(Ord(crCalculated), Ord(C.Role));
      Assert.AreEqual(3, Length(C.X));
    end
    else
    begin
      Meas := True;
      Assert.AreEqual(Ord(crMeasured), Ord(C.Role));
      Assert.AreEqual('S1.xrdml', C.Title);
      Assert.IsTrue(C.Linked);
    end;
  Assert.IsTrue(Calc and Meas);
end;

procedure TXRCProjectTests.Legacy_NoTreeFallsBackToJsonScan;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx',
    StringReplace(Params8, 'Version=8', 'Version=5', []),
    Cat([TBytes.Create(1, 2, 3, 4), TEncoding.Unicode.GetBytes(WSI_JSON)]), []));
  Assert.IsTrue(P.Model.Valid);
  Assert.AreEqual(Ord(msLegacyJson), Ord(P.Model.Source));
  Assert.AreEqual('W', P.Model.Stacks[0].Layers[0].Material);
end;

procedure TXRCProjectTests.CorruptTreeDoesNotRaise;
var
  Bytes: TBytes;
  P: TXRCProject;
begin
  Bytes := StdTree(WSI_JSON);
  SetLength(Bytes, Length(Bytes) - 40);
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8, Bytes, []));
  Assert.AreNotEqual(Ord(msProjectTree), Ord(P.Model.Source));
end;

procedure TXRCProjectTests.FormatVersionRead;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx',
    StringReplace(Params8, 'Version=8', 'Version=7', []), StdTree(WSI_JSON), []));
  Assert.AreEqual(7, P.FormatVersion);
  Assert.AreEqual(Ord(msProjectTree), Ord(P.Model.Source));
end;

procedure TXRCProjectTests.Utf8BomParamsStillReadVersion;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCXRaw('a.xrcx',
    Cat([TEncoding.UTF8.GetPreamble, TEncoding.UTF8.GetBytes(
      StringReplace(Params8, '[INFO]'#13#10'Version=8'#13#10, '', []) + '[INFO]'#13#10'Version=8'#13#10)]),
    StdTree(WSI_JSON), []));
  Assert.AreEqual(8, P.FormatVersion);
  P := LoadXRCProject(WriteXRCXRaw('b.xrcx',
    Cat([TEncoding.UTF8.GetPreamble, TEncoding.UTF8.GetBytes(Params8)]),
    StdTree(WSI_JSON), []));
  Assert.AreEqual(8, P.FormatVersion);
  Assert.AreEqual(Ord(msProjectTree), Ord(P.Model.Source));
end;

procedure TXRCProjectTests.OddTitleByteLengthFallsBack;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8, PatchTitleSize(
    Tree([GroupNode(0, [ModelNode(1, 'Q', WSI_JSON, [])]), GroupNode(1, [])]), 2), []));
  Assert.AreNotEqual(Ord(msProjectTree), Ord(P.Model.Source));
end;

procedure TXRCProjectTests.HugeStringLengthFallsBack;
var
  P: TXRCProject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8, PatchTitleSize(
    Tree([GroupNode(0, [ModelNode(1, 'Q', WSI_JSON, [])]), GroupNode(1, [])]), MaxInt), []));
  Assert.AreNotEqual(Ord(msProjectTree), Ord(P.Model.Source));
end;

function TXRCProjectOutputTests.Info(const P: TXRCProject): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(BuildXRCDetailedInfo(P)) as TJSONObject;
  Assert.IsNotNull(Result);
end;

function TXRCProjectOutputTests.FindKV(const KVs: TArray<TPluginKeyValue>;
  const Name: string; out KV: TPluginKeyValue): Boolean;
var
  K: TPluginKeyValue;
begin
  for K in KVs do
    if K.Name = Name then
    begin
      KV := K;
      Exit(True);
    end;
  Result := False;
end;

function TXRCProjectOutputTests.Names(const KVs: TArray<TPluginKeyValue>): string;
var
  K: TPluginKeyValue;
begin
  Result := '';
  for K in KVs do
    Result := Result + K.Name + '|';
end;

procedure TXRCProjectOutputTests.Json_TopLevelKeys;
var
  J: TJSONObject;
  Key: string;
begin
  J := Info(LoadXRCProject(WriteXRCX('a.xrcx', Params8('[FIT]'#13#10'Mode=1'#13#10),
    StdTree(WSI_JSON), ['calc.dat'])));
  try
    for Key in ['format_version', 'order', 'units', 'model', 'stacks', 'substrate',
      'calculation', 'fit_settings', 'fit_result', 'curves', 'inverted_ranges',
      'layer_sequence'] do
      Assert.IsNotNull(J.Values[Key], Key);
    Assert.IsNull(J.Values['curveCount']);
    Assert.IsNull(J.Values['layerSequence']);
    Assert.AreEqual('surface_to_substrate', J.GetValue<string>('order'));
    Assert.AreEqual('A', J.GetValue<string>('units.length'));
    Assert.AreEqual('deg_theta', J.GetValue<string>('units.angle'));
    Assert.AreEqual(8, J.GetValue<Integer>('format_version'));
    Assert.AreEqual('project_tree', J.GetValue<string>('model.source'));
    Assert.AreEqual(1.54043, J.GetValue<Double>('calculation.wavelength_A'), 1e-9);
    Assert.AreEqual('periodic', J.GetValue<string>('fit_settings.mode'));
  finally
    J.Free;
  end;
end;

procedure TXRCProjectOutputTests.Json_PeriodOnlyForRepeatedStacks;
var
  J: TJSONObject;
  Stacks: TJSONArray;
begin
  J := Info(LoadXRCProject(WriteXRCX('a.xrcx', Params8, StdTree(
    '{"Stacks":[{"T":"Cap","N":1,"Layers":[{"M":"C","H":20,"s":3,"r":2}]},' +
    '{"T":"ML","N":5,"Layers":[{"M":"W","H":10,"s":3,"r":19.3},{"M":"Si","H":15,"s":4,"r":2.33}]}],' +
    '"Subs":{"M":"SiO2","s":3,"r":2.2}}'), [])));
  try
    Stacks := J.GetValue<TJSONArray>('stacks');
    Assert.IsNull((Stacks.Items[0] as TJSONObject).Values['period_A']);
    Assert.AreEqual(25.0, Stacks.Items[1].GetValue<Double>('period_A'), 1e-9);
    Assert.AreEqual(1, Stacks.Items[1].GetValue<Integer>('index'));
    Assert.AreEqual(1, Stacks.Items[1].GetValue<Integer>('layers[1].index'));
    Assert.AreEqual('Si', Stacks.Items[1].GetValue<string>('layers[1].material'));
    Assert.AreEqual(10.0, Stacks.Items[1].GetValue<Double>('layers[0].fit.thickness.min'), 1e-9);
  finally
    J.Free;
  end;
end;

procedure TXRCProjectOutputTests.Json_ProfileOnlyWhenPresent;
var
  J: TJSONObject;
  Layers: TJSONArray;
begin
  J := Info(LoadXRCProject(WriteXRCX('a.xrcx', Params8,
    Tree([GroupNode(0, [ModelNode(1, 'Model', WSI_JSON, [ExtNode(0, 0, 0, [0.5])])]),
      GroupNode(1, [])]), [])));
  try
    Layers := J.GetValue<TJSONArray>('stacks[0].layers');
    Assert.AreEqual('polynomial', Layers.Items[0].GetValue<string>('profile.thickness.kind'));
    Assert.AreEqual(0.5, Layers.Items[0].GetValue<Double>('profile.thickness.coefficients[0]'), 1e-6);
    Assert.IsNull((Layers.Items[0] as TJSONObject).GetValue<TJSONObject>('profile').Values['roughness']);
    Assert.IsNull((Layers.Items[1] as TJSONObject).Values['profile']);
  finally
    J.Free;
  end;
end;

procedure TXRCProjectOutputTests.Json_SubstrateDensityUsed;
var
  J: TJSONObject;
begin
  J := Info(LoadXRCProject(WriteXRCX('a.xrcx',
    StringReplace(Params8, 'Version=8', 'Version=7', []), StdTree(WSI_JSON), [])));
  try
    Assert.AreEqual('henke_bulk', J.GetValue<string>('substrate.density_used'));
  finally
    J.Free;
  end;
  J := Info(LoadXRCProject(WriteXRCX('b.xrcx', Params8, StdTree(WSI_JSON), [])));
  try
    Assert.AreEqual('stored', J.GetValue<string>('substrate.density_used'));
  finally
    J.Free;
  end;
end;

procedure TXRCProjectOutputTests.Json_NullSectionsWithoutParams;
var
  P: TXRCProject;
  J: TJSONObject;
  KV: TPluginKeyValue;
  KVs: TArray<TPluginKeyValue>;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', '', StdTree(WSI_JSON), []));
  J := Info(P);
  try
    Assert.IsTrue(J.Values['calculation'] is TJSONNull);
    Assert.IsTrue(J.Values['fit_settings'] is TJSONNull);
    Assert.IsTrue(J.Values['fit_result'] is TJSONNull);
  finally
    J.Free;
  end;
  KVs := BuildXRCKeyValues(P);
  Assert.IsFalse(FindKV(KVs, 'Wavelength', KV));
  Assert.IsFalse(FindKV(KVs, 'Resolution', KV));
  Assert.IsFalse(FindKV(KVs, 'Theta Min', KV));
  Assert.IsFalse(FindKV(KVs, 'Theta Max', KV));
  Assert.IsFalse(FindKV(KVs, 'Chi2', KV));
  Assert.IsTrue(FindKV(KVs, 'Substrate Roughness', KV));
end;

procedure TXRCProjectOutputTests.Json_LegacyBinHasNoFit;
var
  P: TXRCProject;
  J: TJSONObject;
begin
  P := LoadXRCProject(WriteXRCX('a.xrcx', Params8, StdTree(WSI_JSON), []));
  P.Model.Source := msLegacyBin;
  P.Model.Stacks[0].Layers[0].HasFit := False;
  P.Model.Stacks[0].Layers[1].HasFit := False;
  J := Info(P);
  try
    Assert.AreEqual('legacy_bin', J.GetValue<string>('model.source'));
    Assert.IsNull((J.GetValue<TJSONObject>('stacks[0].layers[0]')).Values['fit']);
  finally
    J.Free;
  end;
end;

procedure TXRCProjectOutputTests.Json_FitResultAndCurves;
var
  J: TJSONObject;
  Curves: TJSONArray;
  I: Integer;
  SawMeasured: Boolean;
begin
  J := Info(LoadXRCProject(WriteXRCX('a.xrcx', Params8(
    '[FITRESULT]'#13#10'chiSquared=0.0123'#13#10'chi2Scale=solved'#13#10'seed=7'#13#10),
    StdTree(WSI_JSON), ['calc.dat', 'data_2.dat'])));
  try
    Assert.AreEqual(0.0123, J.GetValue<Double>('fit_result.chi2'), 1e-9);
    Assert.AreEqual('solved', J.GetValue<string>('fit_result.chi2_scale'));
    Curves := J.GetValue<TJSONArray>('curves');
    Assert.AreEqual(2, Curves.Count);
    SawMeasured := False;
    for I := 0 to Curves.Count - 1 do
      if Curves.Items[I].GetValue<string>('role') = 'measured' then
      begin
        SawMeasured := True;
        Assert.AreEqual('meas.dat', Curves.Items[I].GetValue<string>('title'));
        Assert.IsTrue(Curves.Items[I].GetValue<Boolean>('linked'));
        Assert.AreEqual(3, Curves.Items[I].GetValue<Integer>('points'));
        Assert.AreEqual(0.1, Curves.Items[I].GetValue<Double>('theta_min_deg'), 1e-9);
        Assert.AreEqual(0.3, Curves.Items[I].GetValue<Double>('theta_max_deg'), 1e-9);
      end;
    Assert.IsTrue(SawMeasured);
  finally
    J.Free;
  end;
end;

procedure TXRCProjectOutputTests.Json_CurveRangeInThetaWhenFileStoresTwoTheta;
var
  J: TJSONObject;
begin
  J := Info(LoadXRCProject(WriteXRCX('a.xrcx', StringReplace(Params8, '2teta=0', '2teta=1', []),
    StdTree(WSI_JSON), ['calc.dat'])));
  try
    Assert.AreEqual(0.05, J.GetValue<Double>('curves[0].theta_min_deg'), 1e-9);
    Assert.AreEqual(0.15, J.GetValue<Double>('curves[0].theta_max_deg'), 1e-9);
  finally
    J.Free;
  end;
end;

procedure TXRCProjectOutputTests.Keys_PeriodAndChi2AreKey;
var
  KVs: TArray<TPluginKeyValue>;
  KV: TPluginKeyValue;
begin
  KVs := BuildXRCKeyValues(LoadXRCProject(WriteXRCX('a.xrcx',
    Params8('[FITRESULT]'#13#10'chiSquared=0.0123'#13#10), StdTree(WSI_JSON), [])));
  Assert.IsTrue(FindKV(KVs, 'Period', KV));
  Assert.IsTrue(KV.IsKey);
  Assert.AreEqual('A', KV.Units);
  Assert.AreEqual(25.0, KV.Value, 1e-9);
  Assert.AreEqual(Ord(prResult), Ord(KV.RecType));
  Assert.IsTrue(FindKV(KVs, 'Chi2', KV));
  Assert.IsTrue(KV.IsKey);
  Assert.AreEqual('', KV.Units);
  Assert.AreEqual(0.0123, KV.Value, 1e-9);
  for KV in KVs do
    if (KV.Name <> 'Period') and (KV.Name <> 'Chi2') then
      Assert.IsFalse(KV.IsKey, KV.Name);
end;

procedure TXRCProjectOutputTests.Keys_ConditionsAndUnits;
var
  KVs: TArray<TPluginKeyValue>;
  KV: TPluginKeyValue;
begin
  KVs := BuildXRCKeyValues(LoadXRCProject(WriteXRCX('a.xrcx', Params8, StdTree(WSI_JSON), [])));
  Assert.IsTrue(FindKV(KVs, 'Wavelength', KV));
  Assert.AreEqual('A', KV.Units);
  Assert.AreEqual(Ord(prCondition), Ord(KV.RecType));
  Assert.IsTrue(FindKV(KVs, 'Resolution', KV));
  Assert.AreEqual('deg', KV.Units);
  Assert.AreEqual(Ord(prCondition), Ord(KV.RecType));
  Assert.IsTrue(FindKV(KVs, 'Theta Min', KV));
  Assert.AreEqual('deg', KV.Units);
  Assert.AreEqual(0.05, KV.Value, 1e-9);
  Assert.IsTrue(FindKV(KVs, 'Theta Max', KV));
  Assert.AreEqual(5.0, KV.Value, 1e-9);
  Assert.IsTrue(FindKV(KVs, 'Substrate Roughness', KV));
  Assert.AreEqual('A', KV.Units);
  Assert.AreEqual(Ord(prCondition), Ord(KV.RecType));
  Assert.IsTrue(FindKV(KVs, 'W Density', KV));
  Assert.AreEqual('g/cm3', KV.Units);
  Assert.AreEqual(Ord(prResult), Ord(KV.RecType));
  Assert.IsTrue(FindKV(KVs, 'Si Roughness', KV));
  Assert.AreEqual(4.0, KV.Value, 1e-9);
end;

procedure TXRCProjectOutputTests.Keys_RepeatedMaterialSuffix;
var
  KVs: TArray<TPluginKeyValue>;
  KV: TPluginKeyValue;
  N: string;
begin
  KVs := BuildXRCKeyValues(LoadXRCProject(WriteXRCX('a.xrcx', Params8, StdTree(
    '{"Stacks":[{"T":"A","N":1,"Layers":[{"M":"C","H":1,"s":0,"r":2},' +
    '{"M":"W","H":2,"s":0,"r":19},{"M":"C","H":3,"s":0,"r":2}]},' +
    '{"T":"B","N":3,"Layers":[{"M":"W","H":4,"s":0,"r":19},{"M":"B4C","H":5,"s":0,"r":2.5}]}],' +
    '"Subs":{"M":"Si","s":0,"r":2.33}}'), [])));
  N := Names(KVs);
  Assert.IsTrue(FindKV(KVs, 'C Thickness', KV), N);
  Assert.AreEqual(1.0, KV.Value, 1e-9);
  Assert.IsTrue(FindKV(KVs, 'C Thickness (stack 1 layer 3)', KV), N);
  Assert.AreEqual(3.0, KV.Value, 1e-9);
  Assert.IsTrue(FindKV(KVs, 'W Thickness', KV), N);
  Assert.AreEqual(2.0, KV.Value, 1e-9);
  Assert.IsTrue(FindKV(KVs, 'W Thickness (stack 2)', KV), N);
  Assert.AreEqual(4.0, KV.Value, 1e-9);
  Assert.IsTrue(FindKV(KVs, 'B4C Thickness', KV), N);
  Assert.IsTrue(FindKV(KVs, 'W Density (stack 2)', KV), N);
  Assert.IsTrue(FindKV(KVs, 'Period', KV), N);
  Assert.AreEqual(9.0, KV.Value, 1e-9);
end;

procedure TXRCProjectOutputTests.LayerSequence_UsesProfile;
var
  J: TJSONObject;
  Seq: TJSONArray;
begin
  J := Info(LoadXRCProject(WriteXRCX('a.xrcx', Params8,
    Tree([GroupNode(0, [ModelNode(1, 'Model', WSI_JSON, [ExtNode(0, 0, 0, [0.5])])]),
      GroupNode(1, [])]), [])));
  try
    Seq := J.GetValue<TJSONArray>('layer_sequence');
    Assert.AreEqual(11, Seq.Count);
    Assert.AreEqual(10.0, Seq.Items[0].GetValue<Double>('h_A'), 1e-5);
    Assert.AreEqual(5, Seq.Items[8].GetValue<Integer>('period'));
    Assert.AreEqual(12.0, Seq.Items[8].GetValue<Double>('h_A'), 1e-5);
    Assert.IsTrue(Seq.Items[10].GetValue<Boolean>('substrate'));
  finally
    J.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TXRCProjectTests);
  TDUnitX.RegisterTestFixture(TXRCProjectOutputTests);

end.
