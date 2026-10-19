unit test_ReaderValueMapping;

interface

uses
  DUnitX.TestFramework, unit_LocalNotebook;

type
  [TestFixture]
  TReaderValueMappingTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DepositionRecipeKeysConvertWithoutManualMapping;
    [Test] procedure DepositionCoCRecipeKeysResolveForBothReaders;
    [Test] procedure RecipeRulesCoverAnyMaterialAndKey;
    [Test] procedure MostSpecificPatternWins;
    [Test] procedure RepeatedMaterialKeysKeepMaterialLabel;
    [Test] procedure DefaultsPreserveEditedRulesAndValueTypes;
    [Test] procedure InvalidRulesAreRejected;
    [Test] procedure ReaderFamiliesResolveExpectedUnits;
    [Test] procedure PercentUnitLookupIsLiteral;
    [Test] procedure RememberedChoiceIsPersistedAndReplacesExactRule;
    [Test] procedure DimensionlessValueTypePostsFromEditorDataset;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Generics.Collections,
  Winapi.ActiveX,
  unit_DepositionData, unit_ELNPluginTypes,
  Data.DB,
  unit_ReaderValueMapping, unit_ReaderValueMappingModel, unit_ValueType, unit_ValueTypeModel;

procedure TReaderValueMappingTests.Setup;
begin
  CoInitialize(nil);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-ReaderMapping-' + TGUID.NewGuid.ToString);
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', 'Synthetic-Mapping-Only!');
end;

procedure TReaderValueMappingTests.TearDown;
begin
  FNotebook.Free;
  if TDirectory.Exists(FRoot) then TDirectory.Delete(FRoot, True);
  CoUninitialize;
end;

procedure TReaderValueMappingTests.DepositionRecipeKeysConvertWithoutManualMapping;
const
  XML = '<Recipe><Parameters><Group name="Parameters">' +
    '<Param name="P" unit="mTorr">2</Param>' +
    '<Param name="PowerBN" unit="W">134</Param>' +
    '<Param name="TimeBN" unit="s">50</Param>' +
    '<Param name="CurrentC" unit="mA">312</Param>' +
    '<Param name="TimeC" unit="s">190</Param>' +
    '<Param name="TimeCtop" unit="s">340</Param>' +
    '<Param name="Bias" unit="V">8</Param>' +
    '</Group></Parameters></Recipe>';
var
  JSON, Conditions, Recipe: TJSONObject;
  Snapshot: TDepoSnapshot;
  Resolver: TReaderValueMappingModel;
  KV: TPluginKeyValue;
  Resolution: TReaderValueResolution;
begin
  JSON := TJSONObject.Create;
  Snapshot := TDepoSnapshot.Create;
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    JSON.AddPair('kind', 'deposition-snapshot');
    Conditions := TJSONObject.Create;
    Recipe := TJSONObject.Create;
    Recipe.AddPair('content', XML);
    Conditions.AddPair('recipe', Recipe);
    JSON.AddPair('conditions', Conditions);
    Assert.IsTrue(Snapshot.LoadFromText(JSON.ToJSON));
    Assert.AreEqual(7, Length(Snapshot.BuildKeyValues),
      'All seven embedded conditions must reach extraction');
    for KV in Snapshot.BuildKeyValues do
    begin
      Resolution := Resolver.Resolve('aps.deposition', KV.Name, KV.Units);
      Assert.IsNotNull(Resolution.ValueType, KV.Name + ' must resolve');
      if KV.Name = 'Parameters.P' then
      begin
        Assert.AreEqual('Pressure', Resolution.ValueType.Title);
        Assert.AreEqual('Pa', Resolution.ValueType.Units);
        Assert.AreEqual(0.266644, KV.Value * Resolution.Factor, 1e-12);
      end
      else if KV.Name = 'Parameters.CurrentC' then
      begin
        Assert.AreEqual(0.312, KV.Value * Resolution.Factor, 1e-12);
        Assert.AreEqual('A', Resolution.ValueType.Units);
        Assert.AreEqual('C', Resolution.LabelText);
      end
      else if (KV.Name = 'Parameters.PowerBN') or (KV.Name = 'Parameters.TimeBN') then
        Assert.AreEqual('BN', Resolution.LabelText)
      else if KV.Name = 'Parameters.TimeCtop' then
        Assert.AreEqual('C top', Resolution.LabelText);
    end;
  finally
    Resolver.Free;
    Snapshot.Free;
    JSON.Free;
  end;
end;

procedure TReaderValueMappingTests.DepositionCoCRecipeKeysResolveForBothReaders;
type
  TExpected = record
    Key, Title, Units, LabelText: string;
    Value: Double;
  end;
const
  XML = '<Recipe><Parameters>' +
    '<Group name="Deposition Conditions">' +
    '<Param name="P" unit="mTorr">2.00mT</Param>' +
    '<Param name="Pbase" unit="mTorr">0mT</Param>' +
    '<Param name="ArFlow" unit="sccm">20</Param>' +
    '<Param name="N" unit="N">20</Param>' +
    '</Group><Group name="Layer Co">' +
    '<Param name="currentCo" unit="mA">50</Param>' +
    '<Param name="freqCo" unit="kHz">40</Param>' +
    '<Param name="dutyCo" unit="%">70</Param>' +
    '<Param name="timeCo" unit="sec">42.0</Param>' +
    '</Group><Group name="Layer C">' +
    '<Param name="currentC" unit="mA">300</Param>' +
    '<Param name="freqC" unit="kHz">50</Param>' +
    '<Param name="dutyC" unit="%">60</Param>' +
    '<Param name="timeC" unit="sec">108.0</Param>' +
    '</Group></Parameters></Recipe>';
  Readers: array[0..1] of string = ('aps.deposition', 'aps.recipe');
  Expected: array[0..11] of TExpected = (
    (Key: 'Deposition Conditions.P'; Title: 'Pressure'; Units: 'Pa'; LabelText: ''; Value: 0.266644),
    (Key: 'Deposition Conditions.Pbase'; Title: 'Pressure'; Units: 'Pa'; LabelText: ''; Value: 0),
    (Key: 'Deposition Conditions.ArFlow'; Title: 'Flow'; Units: 'sccm'; LabelText: ''; Value: 20),
    (Key: 'Deposition Conditions.N'; Title: 'Periods'; Units: ''; LabelText: ''; Value: 20),
    (Key: 'Layer Co.currentCo'; Title: 'Current'; Units: 'A'; LabelText: 'Co'; Value: 0.05),
    (Key: 'Layer Co.freqCo'; Title: 'Frequency'; Units: 'Hz'; LabelText: 'Co'; Value: 40000),
    (Key: 'Layer Co.dutyCo'; Title: 'Duty cycle'; Units: '%'; LabelText: 'Co'; Value: 70),
    (Key: 'Layer Co.timeCo'; Title: 'Time'; Units: 's'; LabelText: 'Co'; Value: 42),
    (Key: 'Layer C.currentC'; Title: 'Current'; Units: 'A'; LabelText: 'C'; Value: 0.3),
    (Key: 'Layer C.freqC'; Title: 'Frequency'; Units: 'Hz'; LabelText: 'C'; Value: 50000),
    (Key: 'Layer C.dutyC'; Title: 'Duty cycle'; Units: '%'; LabelText: 'C'; Value: 60),
    (Key: 'Layer C.timeC'; Title: 'Time'; Units: 's'; LabelText: 'C'; Value: 108));
var
  JSON, Conditions, Recipe: TJSONObject;
  Snapshot: TDepoSnapshot;
  Resolver: TReaderValueMappingModel;
  KeyValues: TArray<TPluginKeyValue>;
  KV: TPluginKeyValue;
  E: TExpected;
  Reader, Context: string;
  Found: Boolean;
  Resolution: TReaderValueResolution;
begin
  JSON := TJSONObject.Create;
  Snapshot := TDepoSnapshot.Create;
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    JSON.AddPair('kind', 'deposition-snapshot');
    Conditions := TJSONObject.Create;
    Recipe := TJSONObject.Create;
    Recipe.AddPair('content', XML);
    Conditions.AddPair('recipe', Recipe);
    JSON.AddPair('conditions', Conditions);
    Assert.IsTrue(Snapshot.LoadFromText(JSON.ToJSON));
    KeyValues := Snapshot.BuildKeyValues;
    Assert.AreEqual(12, Length(KeyValues), 'All twelve recipe conditions must reach extraction');
    for E in Expected do
    begin
      Found := False;
      for KV in KeyValues do
        if KV.Name = E.Key then
        begin
          Found := True;
          for Reader in Readers do
          begin
            Context := Reader + ' ' + KV.Name;
            Resolution := Resolver.Resolve(Reader, KV.Name, KV.Units);
            Assert.IsNotNull(Resolution.ValueType, Context + ' must resolve');
            Assert.AreEqual(E.Title, Resolution.ValueType.Title, Context);
            Assert.AreEqual(E.Units, Resolution.ValueType.Units, Context);
            Assert.AreEqual(E.Value, KV.Value * Resolution.Factor, 1e-9, Context);
            Assert.AreEqual(E.LabelText, Resolution.LabelText, Context);
          end;
        end;
      Assert.IsTrue(Found, E.Key + ' must be extracted');
    end;
  finally
    Resolver.Free;
    Snapshot.Free;
    JSON.Free;
  end;
end;

procedure TReaderValueMappingTests.RecipeRulesCoverAnyMaterialAndKey;
type
  TExpected = record
    Key, Units, Title, TargetUnits, LabelText: string;
    Value, Converted: Double;
  end;
const
  Readers: array[0..1] of string = ('aps.deposition', 'aps.recipe');
  Expected: array[0..17] of TExpected = (
    (Key: 'Layer Si3N4.powerSi3N4'; Units: 'W'; Title: 'Power'; TargetUnits: 'W'; LabelText: 'Si3N4'; Value: 350; Converted: 350),
    (Key: 'Layer BN.timeBNTop'; Units: 'sec'; Title: 'Time'; TargetUnits: 's'; LabelText: 'BN'; Value: 40; Converted: 40),
    (Key: 'Layer BN.BiasVoltageBN'; Units: 'V'; Title: 'Voltage'; TargetUnits: 'V'; LabelText: 'BN'; Value: 35; Converted: 35),
    (Key: 'Layer SiNx.SiCurrent'; Units: 'mA'; Title: 'Current'; TargetUnits: 'A'; LabelText: 'SiNx'; Value: 250; Converted: 0.25),
    (Key: 'Layer TiN.DCAFreq'; Units: 'kHz'; Title: 'Frequency'; TargetUnits: 'Hz'; LabelText: 'TiN'; Value: 40; Converted: 40000),
    (Key: 'Layer Ru.dutyRu'; Units: '%'; Title: 'Duty cycle'; TargetUnits: '%'; LabelText: 'Ru'; Value: 55; Converted: 55),
    (Key: 'Layer W.pulseTimeW'; Units: 'us'; Title: 'Time'; TargetUnits: 's'; LabelText: 'W'; Value: 5; Converted: 5e-6),
    (Key: 'Layer Mo/Si.timeMo'; Units: 'sec'; Title: 'Time'; TargetUnits: 's'; LabelText: 'Mo/Si'; Value: 12; Converted: 12),
    (Key: 'Parameters.Ptarget'; Units: 'mTorr'; Title: 'Pressure'; TargetUnits: 'Pa'; LabelText: ''; Value: 3; Converted: 0.399966),
    (Key: 'Parameters.Pbase'; Units: 'Torr'; Title: 'Pressure'; TargetUnits: 'Pa'; LabelText: ''; Value: 1e-6; Converted: 1.33322e-4),
    (Key: 'Parameters.Q'; Units: 'sccm'; Title: 'Flow'; TargetUnits: 'sccm'; LabelText: ''; Value: 12; Converted: 12),
    (Key: 'Parameters.Ical'; Units: 'mA'; Title: 'Current'; TargetUnits: 'A'; LabelText: ''; Value: 100; Converted: 0.1),
    (Key: 'Parameters.PowerTiN'; Units: 'W'; Title: 'Power'; TargetUnits: 'W'; LabelText: ''; Value: 200; Converted: 200),
    (Key: 'Parameters.Hold'; Units: 'sec'; Title: 'Time'; TargetUnits: 's'; LabelText: ''; Value: 30; Converted: 30),
    (Key: 'Parameters.TimeTiN'; Units: 's'; Title: 'Time'; TargetUnits: 's'; LabelText: ''; Value: 60; Converted: 60),
    (Key: 'Deposition Conditions.WarmUpTime'; Units: 'min'; Title: 'Time'; TargetUnits: 's'; LabelText: ''; Value: 10; Converted: 600),
    (Key: 'Deposition Conditions.StageHeight'; Units: 'mm'; Title: 'Distance'; TargetUnits: 'm'; LabelText: ''; Value: 45; Converted: 0.045),
    (Key: 'Deposition Conditions.MFC_N21'; Units: 'sccm'; Title: 'Flow'; TargetUnits: 'sccm'; LabelText: ''; Value: 8; Converted: 8));
var
  Resolver: TReaderValueMappingModel;
  Resolution: TReaderValueResolution;
  E: TExpected;
  Reader, Context: string;
begin
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    for Reader in Readers do
    begin
      for E in Expected do
      begin
        Context := Reader + ' ' + E.Key;
        Resolution := Resolver.Resolve(Reader, E.Key, E.Units);
        Assert.IsNotNull(Resolution.ValueType, Context + ' must resolve');
        Assert.AreEqual(E.Title, Resolution.ValueType.Title, Context);
        Assert.AreEqual(E.TargetUnits, Resolution.ValueType.Units, Context);
        Assert.AreEqual(E.Converted, E.Value * Resolution.Factor, 1e-12, Context);
        Assert.AreEqual(E.LabelText, Resolution.LabelText, Context);
      end;
      Resolution := Resolver.Resolve(Reader, 'Layer Co.speedCo', 'rpm');
      Assert.IsNull(Resolution.ValueType, Reader + ' must not map a unit without a rule');
      Assert.Contains(Resolution.Reason, 'Reader unit does not match mapping');
      Resolution := Resolver.Resolve(Reader, 'Layer .timeX', 'sec');
      Assert.IsNull(Resolution.ValueType, Reader + ' must not map a key without a material');
    end;
  finally
    Resolver.Free;
  end;
end;

procedure TReaderValueMappingTests.MostSpecificPatternWins;
var
  Types: TValueTypeModel;
  Resolver: TReaderValueMappingModel;
  Resolution: TReaderValueResolution;
  TopId: Integer;
begin
  Types := TValueTypeModel.Create(FNotebook.Manager);
  try
    Types.AddType('t', 'Synthetic top time', 's', 0);
    TopId := Types.FindByTitleUnits('Synthetic top time', 's').Id;
  finally
    Types.Free;
  end;
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    Resolver.Remember('aps.recipe', 'Layer <Material>.time<Material>Top', 'sec',
      FNotebook.Manager.Find<TValueType>(TopId), 1);
  finally
    Resolver.Free;
  end;
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    Resolution := Resolver.Resolve('aps.recipe', 'Layer BN.timeBNTop', 'sec');
    Assert.AreEqual(TopId, Resolution.ValueType.Id);
    Assert.AreEqual('BN', Resolution.LabelText);
    Resolution := Resolver.Resolve('aps.recipe', 'Layer BN.timeCTop', 'sec');
    Assert.AreEqual('Time', Resolution.ValueType.Title,
      'Every <Material> in a pattern must capture the same text');
    Resolution := Resolver.Resolve('aps.recipe', 'Layer BN.timeBN', 'sec');
    Assert.AreEqual('Time', Resolution.ValueType.Title);
    Assert.AreEqual('BN', Resolution.LabelText);
  finally
    Resolver.Free;
  end;
end;

procedure TReaderValueMappingTests.RepeatedMaterialKeysKeepMaterialLabel;
var
  Resolver: TReaderValueMappingModel;
  Resolution: TReaderValueResolution;
begin
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    Resolution := Resolver.Resolve('aps.xrcx', 'C Thickness (stack 2)', 'A');
    Assert.IsNotNull(Resolution.ValueType);
    Assert.AreEqual('Thickness', Resolution.ValueType.Title);
    Assert.AreEqual('C', Resolution.LabelText);
    Assert.AreEqual(1e-10, Resolution.Factor, 1e-22);
    Resolution := Resolver.Resolve('aps.xrcx', 'Co Roughness (stack 1 layer 3)', 'A');
    Assert.IsNotNull(Resolution.ValueType);
    Assert.AreEqual('Roughness', Resolution.ValueType.Title);
    Assert.AreEqual('Co', Resolution.LabelText);
    Resolution := Resolver.Resolve('aps.xrcx', 'Co Roughness (stack bad)', 'A');
    Assert.IsNull(Resolution.ValueType);
  finally
    Resolver.Free;
  end;
end;

procedure TReaderValueMappingTests.DefaultsPreserveEditedRulesAndValueTypes;
var
  Rows: TList<TReaderValueMapping>;
  Types: TList<TValueType>;
  Row: TReaderValueMapping;
  RuleId, TypeId: Integer;
begin
  Rows := FNotebook.Manager.Find<TReaderValueMapping>.List;
  try
    Row := Rows[0];
    RuleId := Row.Id;
    TypeId := Row.ValueType.Id;
    Row.Factor := 0.5;
    Row.LabelText := 'Owned label';
    Row.ValueType.Description := 'Owned definition';
    FNotebook.Manager.Flush;
    TReaderValueMappingModel.CreateDefaultData(FNotebook.Manager);
    FNotebook.Manager.Clear;
    Row := FNotebook.Manager.Find<TReaderValueMapping>(RuleId);
    Assert.AreEqual<Double>(0.5, Row.Factor);
    Assert.AreEqual('Owned label', Row.LabelText);
    Assert.AreEqual('Owned definition', FNotebook.Manager.Find<TValueType>(TypeId).Description);
  finally
    Rows.Free;
  end;
  Rows := FNotebook.Manager.Find<TReaderValueMapping>.List;
  Types := FNotebook.Manager.Find<TValueType>.List;
  try
    for Row in Rows do
    begin
      RuleId := 0;
      for var Other in Rows do
        if (Other.ReaderId = Row.ReaderId) and (Other.KeyPattern = Row.KeyPattern) and
          (Other.ReaderUnits = Row.ReaderUnits) then Inc(RuleId);
      Assert.AreEqual(1, RuleId, 'Seeding must not duplicate a rule');
    end;
    for var VT in Types do
    begin
      TypeId := 0;
      for var OtherType in Types do
        if (VT.Title = OtherType.Title) and (VT.Units = OtherType.Units) then Inc(TypeId);
      Assert.AreEqual(1, TypeId, 'Seeding must not duplicate a value type');
    end;
  finally
    Types.Free;
    Rows.Free;
  end;
end;

procedure TReaderValueMappingTests.InvalidRulesAreRejected;
var
  Resolver: TReaderValueMappingModel;
  Row: TReaderValueMapping;
begin
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  Row := TReaderValueMapping.Create;
  try
    Row.ReaderId := 'aps.xrcx';
    Row.KeyPattern := 'Period';
    Row.ReaderUnits := 'A';
    Row.Factor := 1e-10;
    var Types := FNotebook.Manager.Find<TValueType>.List;
    try
      Row.ValueType := Types[0];
    finally
      Types.Free;
    end;
    Assert.WillRaise(procedure begin Resolver.Validate(Row); end, EArgumentException);
    Row.KeyPattern := '<Unknown> Period';
    Assert.WillRaise(procedure begin Resolver.Validate(Row); end, EArgumentException);
    Row.KeyPattern := '<Material><Any>';
    Assert.WillRaise(procedure begin Resolver.Validate(Row); end, EArgumentException);
    Row.KeyPattern := 'Layer <Material>.<Any>';
    Resolver.Validate(Row);
    Row.KeyPattern := 'Custom period';
    Row.Factor := 0;
    Assert.WillRaise(procedure begin Resolver.Validate(Row); end, EArgumentException);
  finally
    Row.Free;
    Resolver.Free;
  end;
end;

procedure TReaderValueMappingTests.ReaderFamiliesResolveExpectedUnits;
var
  Resolver: TReaderValueMappingModel;
  Resolution: TReaderValueResolution;
begin
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    Resolution := Resolver.Resolve('aps.recipe', 'Layer Co.currentCo', 'mA');
    Assert.AreEqual(0.05, 50 * Resolution.Factor, 1e-12);
    Assert.AreEqual('Current', Resolution.ValueType.Title);
    Assert.AreEqual('Co', Resolution.LabelText);
    Resolution := Resolver.Resolve('aps.recipe', 'Layer C.timeC', 'sec');
    Assert.AreEqual('s', Resolution.ValueType.Units);
    Assert.AreEqual<Double>(1, Resolution.Factor);
    Resolution := Resolver.Resolve('aps.zrw', 'Fn', 'N');
    Assert.AreEqual('Normal force', Resolution.ValueType.Title);
    Resolution := Resolver.Resolve('aps.mit', 'Hardness', 'GPa');
    Assert.AreEqual('GPa', Resolution.ValueType.Units);
    Resolution := Resolver.Resolve('aps.fibps', 'Wear Area', 'um2');
    Assert.AreEqual('mm' + WideChar($00B2), Resolution.ValueType.Units);
    Assert.AreEqual(1e-6, Resolution.Factor, 1e-18);
    Resolution := Resolver.Resolve('aps.fibps', 'Wear Volume', 'um3');
    Assert.AreEqual('mm' + WideChar($00B3), Resolution.ValueType.Units);
    Assert.AreEqual(1e-9, Resolution.Factor, 1e-21);
  finally
    Resolver.Free;
  end;
end;

procedure TReaderValueMappingTests.PercentUnitLookupIsLiteral;
var
  VT: TValueType;
  Types: TValueTypeModel;
begin
  VT := TValueType.Create;
  VT.Title := 'Pressure';
  VT.Symbol := 'Synthetic percent';
  VT.Units := '%';
  VT.CreatedDate := Now;
  FNotebook.Manager.Save(VT);
  FNotebook.Manager.Flush;
  Types := TValueTypeModel.Create(FNotebook.Manager);
  try
    Assert.AreEqual(VT.Id, Types.FindByTitleUnits('Pressure', '%').Id,
      'A newly selected percent unit must not resolve an existing Pa definition');
  finally
    Types.Free;
  end;
end;

procedure TReaderValueMappingTests.RememberedChoiceIsPersistedAndReplacesExactRule;
var
  Types: TValueTypeModel;
  Resolver: TReaderValueMappingModel;
  Resolution: TReaderValueResolution;
  MetreId, MillimetreId, Count: Integer;
  Rows: TList<TReaderValueMapping>;
begin
  Types := TValueTypeModel.Create(FNotebook.Manager);
  try
    Types.AddType('h', 'Synthetic height', 'm', 0);
    Types.AddType('h', 'Synthetic height', 'mm', 0);
    MetreId := Types.FindByTitleUnits('Synthetic height', 'm').Id;
    MillimetreId := Types.FindByTitleUnits('Synthetic height', 'mm').Id;
  finally
    Types.Free;
  end;
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    Resolver.Remember('aps.fibps', 'Scan Height', 'um',
      FNotebook.Manager.Find<TValueType>(MetreId), 1e-6);
    Resolver.Remember('aps.fibps', 'Step Height', 'um',
      FNotebook.Manager.Find<TValueType>(MillimetreId), 1e-3);
    Assert.WillRaise(procedure
      begin
        Resolver.Remember('aps.fibps', 'Step Height', 'um',
          FNotebook.Manager.Find<TValueType>(MetreId), 0);
      end, EArgumentException);
  finally
    Resolver.Free;
  end;
  FNotebook.Manager.Clear;
  Resolver := TReaderValueMappingModel.Create(FNotebook.Manager);
  try
    Resolution := Resolver.Resolve('aps.fibps', 'Scan Height', 'um');
    Assert.AreEqual(MetreId, Resolution.ValueType.Id);
    Assert.AreEqual(1e-6, Resolution.Factor, 1e-18);
    Resolution := Resolver.Resolve('aps.fibps', 'Step Height', 'um');
    Assert.AreEqual(MillimetreId, Resolution.ValueType.Id,
      'A rejected choice must not change the remembered rule');
    Assert.AreEqual(1e-3, Resolution.Factor, 1e-15);
  finally
    Resolver.Free;
  end;
  Rows := FNotebook.Manager.Find<TReaderValueMapping>.List;
  try
    Count := 0;
    for var Row in Rows do
      if (Row.ReaderId = 'aps.fibps') and (Row.KeyPattern = 'Step Height') then
        Inc(Count);
    Assert.AreEqual(1, Count, 'Remembering an existing key replaces its rule');
  finally
    Rows.Free;
  end;
end;

procedure TReaderValueMappingTests.DimensionlessValueTypePostsFromEditorDataset;
var
  Types: TValueTypeModel;
  DS: TDataSet;
begin
  Types := TValueTypeModel.Create(FNotebook.Manager);
  try
    DS := Types.DataSet;
    DS.Append;
    DS.FieldByName('Symbol').AsString := 'n';
    DS.FieldByName('Title').AsString := 'Synthetic count';
    DS.FieldByName('CatID').AsInteger := 0;
    DS.FieldByName('CreatedDate').AsDateTime := Now;
    DS.Post;
    Assert.IsNotNull(Types.FindByTitleUnits('Synthetic count', ''),
      'A value type without a unit, such as Cycles, must be stored');
  finally
    Types.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TReaderValueMappingTests);
end.
