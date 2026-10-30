unit test_ValueSourceDesktop;

interface

uses
  DUnitX.TestFramework, Aurelius.Engine.ObjectManager, unit_LocalNotebook,
  unit_Item, unit_ItemTreeVM, unit_ELNPluginTypes;

type
  [TestFixture]
  TValueSourceDesktopTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FVM: TItemTreeVM;
    FItem: TItem;
    FFresh: TObjectManager;
    function ThicknessType: Integer;
    function FreshValue(ValueId: Integer): TValue;
    function NewZrwFile(const Title: string): unit_Item.TFile;
    function SnapshotWithoutValueId(Value: TValue): string;
    function CofKeysOf(const Keys: TArray<TPluginKeyValue>): TArray<TPluginKeyValue>;
    function CofCount: Integer;
    function CofValue: TValue;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ManualEntryThroughItemTreePersistsManual;
    [Test] procedure ExtractedValueRecordsReaderSource;
    [Test] procedure EditedValueRecordsModification;
    [Test] procedure MaterialExtractionConvertsAndKeepsProvenance;
    [Test] procedure BothExtractionPathsValidateConvertedNumbers;
    [Test] procedure DialogConvertsChosenUnitsAndRemembersChoice;
    [Test] procedure ZrwCofStoresSameValueToleranceAndSnapshotInBothPaths;
    [Test] procedure AttachedContextUsesAppliedSharedSelection;
    [Test] procedure StaleSharedSelectionStoresNoCofAndReportsStatus;
    [Test] procedure ExtractionHelperReportsLineNumberedLoadError;
    [Test] procedure WriteChosenValuesMatchesNameAndUnits;
    [Test] procedure WriteChosenValuesSkipsMissingAndIssues;
    [Test] procedure WriteChosenValuesUsesCheckedOccurrence;
    [Test] procedure WriteChosenValuesPairsDuplicateKeysInOrder;
    [Test] procedure ReExtractionFromOneFileUpdatesItsValue;
    [Test] procedure DerivedValueDialogComputesFromChosenInputs;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.UITypes, System.JSON, Vcl.Forms,
  Vcl.ExtCtrls, dlg_Value,
  unit_Project, unit_ItemTypes, unit_ProjectAccessPolicy, unit_ValueType,
  unit_ReaderValueMappingModel, unit_ReaderValueStatistics,
  unit_FileType, unit_ValueSource, unit_ELNPluginCore,
  unit_DataModel, dlg_ExtractValues, unit_ActionDialogVM,
  unit_AnalysisSettingsModel, unit_ZRWPlateau, unit_ZRWViewerPlugin,
  unit_ElnAnalysisSettings,
  test_ZRWExtraction, dlg_DerivedValue, unit_DerivedFormulas;

type
  TExtractionDialogDriver = class
    Attempts: Integer;
    WarningsShown: Integer;
    TargetTitle: string;
    procedure Tick(Sender: TObject);
  end;

procedure TExtractionDialogDriver.Tick(Sender: TObject);
begin
  if (Screen.ActiveForm <> nil) and (Screen.ActiveForm.ClassName = 'TMessageForm') then
  begin
    Inc(WarningsShown);
    Screen.ActiveForm.ModalResult := mrOK;
    Exit;
  end;
  if Screen.ActiveForm is TdlgExtractValues then
  begin
    Inc(Attempts);
    if (Attempts = 1) and (TargetTitle <> '') then
    begin
      var Dlg := TdlgExtractValues(Screen.ActiveForm);
      for var I := 0 to Dlg.lbValueType.Items.Count - 1 do
        if Pos(TargetTitle, Dlg.lbValueType.Items[I]) > 0 then
        begin
          Dlg.lbValueType.ItemIndex := I;
          Dlg.lbValueTypeClick(Dlg.lbValueType);
          Break;
        end;
    end;
    if Attempts = 1 then
      TdlgExtractValues(Screen.ActiveForm).btnOK.Click
    else
      TdlgExtractValues(Screen.ActiveForm).btnCancel.Click;
  end;
end;

const
  Password = 'Synthetic-Value-Source-Only!';

procedure TValueSourceDesktopTests.Setup;
var
  Id: TGUID;
  Project: TProject;
  Detached: TItem;
begin
  Assert.IsNull(Model, 'Fixture must not replace a live desktop model');
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-ValueSource-' + GUIDToString(Id));
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Model := TDataModel.Create(FNotebook.Connection, FNotebook.Principal.Id,
    FNotebook.AccessPolicy, FNotebook.Storage);
  Project := Model.Projects.AddProject('Synthetic project', '', Model.User);
  Model.Items.AssignProject(Project.Id, 0);
  Detached := Model.Items.AddItem(TItemType.Other, 'Synthetic procedure',
    TItemLevel.Proc, 0, '', nil, nil, Model.User.Id);
  FItem := Model.Manager.Find<TItem>(Detached.Id);
  Detached.Free;
  FVM := TItemTreeVM.Create(Model.Items, Model.Authors, Model.History,
    Model.Signatures, Model.Comments, Model.Tags, Model.ItemLinks, Model.Access);
  FVM.SetLocation(Project.Id, 0, paReadWrite);
end;

procedure TValueSourceDesktopTests.TearDown;
begin
  FreeAndNil(FFresh);
  FVM.Free;
  FreeAndNil(Model);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TValueSourceDesktopTests.ThicknessType: Integer;
begin
  Model.ValueTypes.AddType('d', 'Synthetic thickness', 'm', 0);
  Result := Model.ValueTypes.FindByTitleUnits('Synthetic thickness', 'm').Id;
end;

function TValueSourceDesktopTests.FreshValue(ValueId: Integer): TValue;
begin
  FreeAndNil(FFresh);
  FFresh := TObjectManager.Create(Model.Connection);
  Result := FFresh.Find<TValue>(ValueId);
  Assert.IsNotNull(Result, 'The value must be persisted');
end;

procedure TValueSourceDesktopTests.ManualEntryThroughItemTreePersistsManual;
var
  VT: TValueType;
  Stored: TValue;
begin
  VT := Model.Manager.Find<TValueType>(ThicknessType);
  FVM.AddValue(VT, EXP_CONDITION, 5e-8, FItem, 0, 'typed by hand',
    TValueSourceInfo.Manual);
  Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
  Stored := FreshValue(FItem.Values[0].Id);
  Assert.IsTrue(Stored.SourceKind.HasValue, 'Manual entry must not stay Unknown');
  Assert.IsTrue(Stored.SourceKind.Value = vskManual);
  Assert.IsFalse(Stored.SourceFileId.HasValue);
  Assert.AreEqual('', Stored.ReaderId);
end;

procedure TValueSourceDesktopTests.EditedValueRecordsModification;
var
  VT: TValueType;
  VM: TActionDialogVM;
  V: TValue;
  Before: TValueFields;
  Stored: TValue;
  ValueId: Integer;
begin
  VT := Model.Manager.Find<TValueType>(ThicknessType);
  FVM.AddValue(VT, EXP_CONDITION, 5e-8, FItem, 0, 'typed by hand',
    TValueSourceInfo.Manual);
  ValueId := FItem.Values[0].Id;
  VM := TActionDialogVM.Create(Model.ActionTypes, Model.Equipments,
    Model.Items, Model.User.Id);
  try
    VM.LoadForEdit(FItem, [FItem.Level]);
    V := FItem.Values[0];

    VM.ValueEdited(V, TValueFields.Read(V));
    Stored := FreshValue(ValueId);
    Assert.IsFalse(Stored.ModifiedDate.HasValue,
      'A value saved without changes keeps no modification stamp');

    Before := TValueFields.Read(V);
    V.Value := 6e-8;
    VM.ValueEdited(V, Before);
    Stored := FreshValue(ValueId);
    Assert.IsTrue(Stored.ModifiedDate.HasValue, 'An edited value is stamped');
    Assert.IsTrue(Stored.ModifiedBy.HasValue);
    Assert.AreEqual(Model.User.Id, Stored.ModifiedBy.Value);
    Assert.AreEqual<Double>(6e-8, Stored.Value);
  finally
    VM.Free;
  end;
end;

procedure TValueSourceDesktopTests.ExtractedValueRecordsReaderSource;
var
  VT: TValueType;
  FileType: TFileType;
  AFile: unit_Item.TFile;
  KV: TPluginKeyValue;
  Stored: TValue;
  Mapping: TReaderValueResolution;
begin
  VT := Model.Manager.Find<TValueType>(ThicknessType);
  FileType := TFileType.Create;
  FileType.Ext := '.synthetic';
  FileType.Description := 'Synthetic measurement';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'scan', Model.User.Id, FItem);
  Assert.IsNotNull(AFile);

  KV := Default(TPluginKeyValue);
  KV.Name := 'Synthetic thickness';
  KV.Value := 1.5e-6;
  KV.Units := 'm';
  KV.Description := 'fit';
  KV.RecType := prResult;
  KV.IsKey := True;
  Mapping := Default(TReaderValueResolution);
  Mapping.ValueType := VT;
  Mapping.Factor := 1;
  WriteExtractedValue(Model.Items, Mapping, KV, Model.User.Id, FItem, AFile.Id,
    'synthetic.reader', '2.1', '', 0);

  Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
  Stored := FreshValue(FItem.Values[0].Id);
  Assert.IsTrue(Stored.EffectiveSourceKind = vskReader);
  Assert.IsTrue(Stored.RecType = TEST_RESULT);
  Assert.AreEqual<Double>(1.5e-6, Stored.Value);
  Assert.AreEqual<Int64>(AFile.Id, Stored.SourceFileId.Value);
  Assert.AreEqual('synthetic.reader', Stored.ReaderId);
  Assert.AreEqual('2.1', Stored.ReaderVersion);
  Assert.AreEqual('Synthetic thickness', Stored.KeyName);
end;

procedure TValueSourceDesktopTests.MaterialExtractionConvertsAndKeepsProvenance;
var
  Mapping: TReaderValueResolution;
  Resolver: TReaderValueMappingModel;
  FileType: TFileType;
  AFile: unit_Item.TFile;
  KV: TPluginKeyValue;
  Stored: TValue;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.xrcx';
  FileType.Description := 'Synthetic XRCX';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'synthetic fit', Model.User.Id, FItem);
  KV := Default(TPluginKeyValue);
  KV.Name := 'Co Thickness';
  KV.Value := 15;
  KV.Units := 'A';
  KV.RecType := prResult;
  Resolver := TReaderValueMappingModel.Create(Model.Manager);
  try
    Mapping := Resolver.Resolve('aps.xrcx', KV.Name, KV.Units);
    WriteExtractedValue(Model.Items, Mapping, KV, Model.User.Id, FItem,
      AFile.Id, 'aps.xrcx', '1', '', 0);
  finally
    Resolver.Free;
  end;
  Stored := FreshValue(FItem.Values[0].Id);
  Assert.AreEqual(15e-10, Stored.Value, 1e-22);
  Assert.AreEqual('Co', Stored.Description);
  Assert.AreEqual('Co Thickness', Stored.KeyName);
  Assert.AreEqual('A', Stored.ReaderUnits.Value);
  Assert.AreEqual(1e-10, Stored.ConversionFactor.Value, 1e-22);
end;

procedure TValueSourceDesktopTests.BothExtractionPathsValidateConvertedNumbers;
var
  Resolver: TReaderValueMappingModel;
  Mapping: TReaderValueResolution;
  FileType: TFileType;
  AFile: unit_Item.TFile;
  KV: TPluginKeyValue;
  Automatic: TValue;
  AutoId, Questions: Integer;
  SavedConfirmation: TValueIssueConfirmation;
  Timer: TTimer;
  Driver: TExtractionDialogDriver;
  Warning: string;
  AutoStd: TPluginKeyValue;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.xrcx';
  FileType.Description := 'Synthetic conversion test';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'mapped scan', Model.User.Id, FItem);
  KV := Default(TPluginKeyValue);
  KV.Name := 'Co Thickness';
  KV.Units := 'A';
  KV.Value := 15;
  KV.IsKey := True;
  KV.RecType := prResult;
  Resolver := TReaderValueMappingModel.Create(Model.Manager);
  try
    Mapping := Resolver.Resolve('aps.xrcx', KV.Name, KV.Units);
    Mapping.ValueType.RangeMin := 0;
    Mapping.ValueType.RangeMax := 1e-7;
    Model.Manager.Flush;
    AutoStd := KV;
    AutoStd.Name := KV.Name + ' STD';
    AutoStd.Value := 0.2;
    Assert.AreEqual(0, WriteAutomaticExtractedValues(Model.Items, Resolver, [AutoStd, KV],
      Model.User.Id, FItem, AFile.Id, 'aps.xrcx', '1', nil, 1000, Warning));
    Assert.AreEqual<NativeInt>(1, FItem.Values.Count, 'A key-flagged STD is not a second value');
    AutoId := FItem.Values[0].Id;
    Automatic := FreshValue(AutoId);
    Assert.AreEqual(15e-10, Automatic.Value, 1e-22);
    Assert.AreEqual(0.2e-10, Automatic.Tol, 1e-22);
    KV.Value := 2000;
    Assert.IsFalse(TryWriteAutomaticExtractedValue(Model.Items, Mapping, KV,
      Model.User.Id, FItem, AFile.Id, 'aps.xrcx', '1', '', 1000, 0));
    Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
    Assert.AreEqual(15e-10, FreshValue(AutoId).Value, 1e-22);
    KV.Value := 15;
    KV.Description := 'paired STD test';
    SavedConfirmation := ConfirmValueIssues;
    Questions := 0;
    Driver := TExtractionDialogDriver.Create;
    Timer := TTimer.Create(nil);
    try
      Timer.Interval := 100;
      Timer.OnTimer := Driver.Tick;
      ConfirmValueIssues := function(const Text: string): Boolean
        begin
          Inc(Questions);
          Result := False;
        end;
      begin
        var StdKV := KV;
        StdKV.Name := KV.Name + ' STD';
        StdKV.Value := 0.2;
        StdKV.IsKey := False;
        Assert.IsTrue(ShowExtractValuesDialog([KV, StdKV], FItem, Model.User.Id,
          AFile.Id, 'aps.xrcx', '1', nil));
      end;
      Assert.AreEqual(0, Questions, 'Converted value is inside the range');
      Assert.AreEqual<NativeInt>(1, FItem.Values.Count, 'The dialog updates the value of this file');
      Assert.AreEqual(AutoId, FItem.Values[0].Id);
      Assert.AreEqual(15e-10, FreshValue(AutoId).Value, 1e-22);
      Assert.AreEqual('A', FreshValue(AutoId).ReaderUnits.Value);
      Assert.AreEqual(0.2e-10, FreshValue(AutoId).Tol, 1e-22);
      Driver.Attempts := 0;
      begin
        var StdKV := KV;
        StdKV.Name := KV.Name + ' STD';
        StdKV.Value := -0.2;
        StdKV.IsKey := True;
        Assert.IsTrue(ShowExtractValuesDialog([StdKV, KV], FItem, Model.User.Id,
          AFile.Id, 'aps.xrcx', '1', nil));
      end;
      Assert.AreEqual<NativeInt>(1, FItem.Values.Count, 'Invalid STD is not stored separately');
      Assert.AreEqual(15e-10, FreshValue(AutoId).Value, 1e-22);
      Assert.AreEqual<Double>(0, FreshValue(AutoId).Tol);
      Assert.AreEqual(1, Driver.WarningsShown, 'Invalid STD reason must be visibly reported');
      Driver.Attempts := 0;
      begin
        var Orphan := KV;
        Orphan.Name := 'Absent STD';
        Assert.IsTrue(ShowExtractValuesDialog([KV, Orphan], FItem, Model.User.Id,
          AFile.Id, 'aps.xrcx', '1', nil));
      end;
      Assert.AreEqual(2, Driver.WarningsShown, 'Orphan STD must be visibly reported');
      Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
      Model.ValueTypes.AddType('RT', 'Synthetic raw thickness', 'A', 0);
      Driver.Attempts := 0;
      Driver.TargetTitle := 'Synthetic raw thickness';
      AutoStd.Value := 0.2;
      Assert.IsTrue(ShowExtractValuesDialog([KV, AutoStd], FItem, Model.User.Id,
        AFile.Id, 'aps.xrcx', '1', nil));
      Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
      Assert.AreEqual(15.0, FreshValue(AutoId).Value, 1e-12);
      Assert.AreEqual(0.2, FreshValue(AutoId).Tol, 1e-12);
      Assert.AreEqual(1.0, FreshValue(AutoId).ConversionFactor.Value, 1e-12);
    finally
      ConfirmValueIssues := SavedConfirmation;
      Timer.Free;
      Driver.Free;
    end;
  finally
    Resolver.Free;
  end;
end;

procedure TValueSourceDesktopTests.DialogConvertsChosenUnitsAndRemembersChoice;
var
  TypeId: Integer;
  FileType: TFileType;
  AFile: unit_Item.TFile;
  KV: TPluginKeyValue;
  Stored: TValue;
  Timer: TTimer;
  Driver: TExtractionDialogDriver;
  Resolver: TReaderValueMappingModel;
  Resolution: TReaderValueResolution;
begin
  TypeId := ThicknessType;
  FileType := TFileType.Create;
  FileType.Ext := '.synthetic';
  FileType.Description := 'Synthetic profile';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'profile', Model.User.Id, FItem);
  KV := Default(TPluginKeyValue);
  KV.Name := 'Synthetic step';
  KV.Value := 0.35;
  KV.Units := 'um';
  KV.RecType := prResult;
  KV.IsKey := True;
  Driver := TExtractionDialogDriver.Create;
  Timer := TTimer.Create(nil);
  try
    Driver.TargetTitle := 'Synthetic thickness';
    Timer.Interval := 100;
    Timer.OnTimer := Driver.Tick;
    Assert.IsTrue(ShowExtractValuesDialog([KV], FItem, Model.User.Id,
      AFile.Id, 'synthetic.profiler', '1', nil));
  finally
    Timer.Free;
    Driver.Free;
  end;
  Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
  Stored := FreshValue(FItem.Values[0].Id);
  Assert.AreEqual(0.35e-6, Stored.Value, 1e-18);
  Assert.AreEqual('um', Stored.ReaderUnits.Value);
  Assert.AreEqual(1e-6, Stored.ConversionFactor.Value, 1e-18);
  Resolver := TReaderValueMappingModel.Create(Model.Manager);
  try
    Resolution := Resolver.Resolve('synthetic.profiler', KV.Name, KV.Units);
    Assert.IsNotNull(Resolution.ValueType, 'The choice must be remembered');
    Assert.AreEqual(TypeId, Resolution.ValueType.Id);
    Assert.AreEqual(1e-6, Resolution.Factor, 1e-18);
  finally
    Resolver.Free;
  end;
end;

function TValueSourceDesktopTests.NewZrwFile(const Title: string): unit_Item.TFile;
var
  FileType: TFileType;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.zrw';
  FileType.Description := 'Synthetic ZRW';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  Result := Model.Items.AddFile(FileType, Title, Model.User.Id, FItem);
  Assert.IsNotNull(Result);
end;

function TValueSourceDesktopTests.SnapshotWithoutValueId(Value: TValue): string;
var
  Settings: TAnalysisSettingsModel;
  Json: TJSONObject;
begin
  Settings := TAnalysisSettingsModel.Create(Model.Manager);
  try
    Assert.IsTrue(Settings.LoadSnapshot(Value, Result),
      'The COF value must carry its snapshot');
  finally
    Settings.Free;
  end;
  Json := TJSONObject.ParseJSONValue(Result) as TJSONObject;
  try
    Assert.AreEqual(Value.Id, Json.GetValue<Integer>('value_id'));
    Json.RemovePair('value_id').Free;
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

function TValueSourceDesktopTests.CofKeysOf(
  const Keys: TArray<TPluginKeyValue>): TArray<TPluginKeyValue>;
var
  Key: TPluginKeyValue;
begin
  Result := nil;
  for Key in Keys do
    if Key.Name.StartsWith('COF') then
      Result := Result + [Key];
end;

procedure TValueSourceDesktopTests.ZrwCofStoresSameValueToleranceAndSnapshotInBothPaths;
var
  Plugin: TELNZRWViewerPlugin;
  Analysis: IAnalysisKeyValueProvider;
  AFile: unit_Item.TFile;
  CofKeys: TArray<TPluginKeyValue>;
  Resolver: TReaderValueMappingModel;
  Timer: TTimer;
  Driver: TExtractionDialogDriver;
  Path, Warning, AutoSnapshot, DialogSnapshot: string;
  AutoValue, AutoTol, DialogValue, DialogTol: Double;
  Parsed: TJSONObject;
begin
  Path := TPath.Combine(FRoot, 'friction.zrw');
  WriteSyntheticZrw(Path);
  AFile := NewZrwFile('friction');
  Plugin := TELNZRWViewerPlugin.Create(nil);
  Driver := TExtractionDialogDriver.Create;
  Timer := TTimer.Create(nil);
  Resolver := TReaderValueMappingModel.Create(Model.Manager);
  try
    Assert.IsTrue(Plugin.LoadFromFile(Path));
    Analysis := AttachAnalysisContext(Plugin, Path, AFile.Id);
    Assert.IsTrue(Analysis <> nil, 'The ZRW reader provides an analysis context');
    CofKeys := CofKeysOf(Plugin.GetKeyValues);
    Assert.AreEqual<NativeInt>(2, Length(CofKeys));

    Assert.AreEqual(0, WriteAutomaticExtractedValues(Model.Items, Resolver, CofKeys,
      Model.User.Id, FItem, AFile.Id, 'aps.zrw', '2', Analysis, 1000, Warning));
    Assert.AreEqual('', Warning);
    Assert.AreEqual<NativeInt>(1, FItem.Values.Count, 'COF STD is not stored separately');
    AutoValue := FreshValue(FItem.Values[0].Id).Value;
    AutoTol := FreshValue(FItem.Values[0].Id).Tol;
    AutoSnapshot := SnapshotWithoutValueId(FItem.Values[0]);

    Model.Items.RemoveValue(FItem.Values[0], FItem, Model.User.Id);
    Assert.AreEqual<NativeInt>(0, FItem.Values.Count);
    Timer.Interval := 100;
    Timer.OnTimer := Driver.Tick;
    Assert.IsTrue(ShowExtractValuesDialog(CofKeys, FItem, Model.User.Id,
      AFile.Id, 'aps.zrw', '2', Analysis));
    Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
    DialogValue := FreshValue(FItem.Values[0].Id).Value;
    DialogTol := FreshValue(FItem.Values[0].Id).Tol;
    DialogSnapshot := SnapshotWithoutValueId(FItem.Values[0]);

    Assert.AreEqual(0.4 + 0.0002 * 49.5, AutoValue, 1e-9);
    Assert.IsTrue(AutoTol > 0, 'COF STD becomes the tolerance');
    Assert.AreEqual(AutoValue, DialogValue, 0.0);
    Assert.AreEqual(AutoTol, DialogTol, 0.0);
    Assert.AreEqual(AutoSnapshot, DialogSnapshot);
    Parsed := TJSONObject.ParseJSONValue(AutoSnapshot) as TJSONObject;
    try
      Assert.AreEqual('automatic', Parsed.GetValue<string>('mode'));
      Assert.AreEqual<Int64>(AFile.Id, Parsed.GetValue<Int64>('file_id'));
      Assert.AreEqual(TAnalysisSettingsModel.ContentHash(Path),
        Parsed.GetValue<string>('file_hash'));
      Assert.AreEqual('COF', Parsed.GetValue<string>('key_name'));
    finally
      Parsed.Free;
    end;
  finally
    Analysis := nil;
    Resolver.Free;
    Timer.Free;
    Driver.Free;
    Plugin.Free;
  end;
end;

procedure TValueSourceDesktopTests.AttachedContextUsesAppliedSharedSelection;
var
  Plugin: TELNZRWViewerPlugin;
  Analysis: IAnalysisKeyValueProvider;
  AFile: unit_Item.TFile;
  Settings: TAnalysisSettingsModel;
  Resolver: TReaderValueMappingModel;
  Selection: TZRWSelection;
  Path, Current, Warning, Snapshot: string;
  Parsed: TJSONObject;
begin
  Path := TPath.Combine(FRoot, 'shared.zrw');
  WriteSyntheticZrw(Path);
  AFile := NewZrwFile('shared');
  Selection := Default(TZRWSelection);
  Selection.Mode := zsmManual;
  Selection.Interval.StartCycle := 20;
  Selection.Interval.EndCycle := 60;
  Selection.ReaderVersion := '2';
  Selection.AlgorithmVersion := '1';
  Selection.FileHash := TAnalysisSettingsModel.ContentHash(Path);
  Selection.ApplyId := 'apply-1';
  Selection.AppliedAt := '2026-01-02T03:04:05Z';
  Selection.AppliedBy := Model.User.Id;
  Selection.Revision := 1;
  Settings := TAnalysisSettingsModel.Create(Model.Manager);
  Resolver := TReaderValueMappingModel.Create(Model.Manager);
  Plugin := TELNZRWViewerPlugin.Create(nil);
  try
    Assert.IsTrue(aasApplied = Settings.ApplySelection(Model.Access, Model.User,
      'aps.zrw', AFile.Id, '', SelectionToJson(Selection), Selection.FileHash, Current));
    Assert.IsTrue(Plugin.LoadFromFile(Path));
    Analysis := AttachAnalysisContext(Plugin, Path, AFile.Id);
    Assert.AreEqual(0, WriteAutomaticExtractedValues(Model.Items, Resolver,
      Plugin.GetKeyValues, Model.User.Id, FItem, AFile.Id, 'aps.zrw', '2',
      Analysis, 1000, Warning));
    Assert.AreEqual(1, CofCount, 'The applied selection yields one COF value');
    Snapshot := SnapshotWithoutValueId(CofValue);
    Parsed := TJSONObject.ParseJSONValue(Snapshot) as TJSONObject;
    try
      Assert.AreEqual('manual', Parsed.GetValue<string>('mode'));
      Assert.AreEqual<Double>(20, Parsed.GetValue<Double>('start'));
      Assert.AreEqual(1, Parsed.GetValue<Integer>('shared_revision'));
      Assert.AreEqual('apply-1', Parsed.GetValue<string>('shared_apply_id'));
    finally
      Parsed.Free;
    end;
    Assert.AreEqual(0.4 + 0.0002 * 39.5, CofValue.Value, 1e-9);
  finally
    Analysis := nil;
    Plugin.Free;
    Resolver.Free;
    Settings.Free;
  end;
end;

procedure TValueSourceDesktopTests.StaleSharedSelectionStoresNoCofAndReportsStatus;
var
  Plugin: TELNZRWViewerPlugin;
  Analysis: IAnalysisKeyValueProvider;
  AFile: unit_Item.TFile;
  Settings: TAnalysisSettingsModel;
  Resolver: TReaderValueMappingModel;
  Selection: TZRWSelection;
  Applied, Changed, Current, Warning: string;
begin
  Applied := TPath.Combine(FRoot, 'applied.zrw');
  Changed := TPath.Combine(FRoot, 'changed.zrw');
  WriteSyntheticZrw(Applied);
  WriteSyntheticZrw(Changed, False);
  AFile := NewZrwFile('stale');
  Selection := Default(TZRWSelection);
  Selection.Mode := zsmManual;
  Selection.Interval.StartCycle := 20;
  Selection.Interval.EndCycle := 60;
  Selection.ReaderVersion := '2';
  Selection.AlgorithmVersion := '1';
  Selection.FileHash := TAnalysisSettingsModel.ContentHash(Applied);
  Selection.ApplyId := 'apply-1';
  Selection.AppliedAt := '2026-01-02T03:04:05Z';
  Selection.AppliedBy := Model.User.Id;
  Selection.Revision := 1;
  Settings := TAnalysisSettingsModel.Create(Model.Manager);
  Resolver := TReaderValueMappingModel.Create(Model.Manager);
  Plugin := TELNZRWViewerPlugin.Create(nil);
  try
    Assert.IsTrue(aasApplied = Settings.ApplySelection(Model.Access, Model.User,
      'aps.zrw', AFile.Id, '', SelectionToJson(Selection), Selection.FileHash, Current));
    Assert.IsTrue(Plugin.LoadFromFile(Changed));
    Analysis := AttachAnalysisContext(Plugin, Changed, AFile.Id);
    WriteAutomaticExtractedValues(Model.Items, Resolver, Plugin.GetKeyValues,
      Model.User.Id, FItem, AFile.Id, 'aps.zrw', '2', Analysis, 1000, Warning);
    Assert.AreEqual(0, CofCount, 'A stale selection must not produce a COF value');
    Assert.AreEqual(ANALYSIS_STATUS_STALE_SELECTION, Analysis.GetAnalysisStatus);
    Assert.IsTrue(Pos(AnalysisStatusText(ANALYSIS_STATUS_STALE_SELECTION), Warning) > 0,
      'The status text must reach the user: ' + Warning);
  finally
    Analysis := nil;
    Plugin.Free;
    Resolver.Free;
    Settings.Free;
  end;
end;

procedure TValueSourceDesktopTests.ExtractionHelperReportsLineNumberedLoadError;
var
  Plugin: TELNZRWViewerPlugin;
  Bad: string;
  Text: string;
begin
  Bad := TPath.Combine(FRoot, 'bad.zrw');
  WriteMalformedZrw(Bad);
  Plugin := TELNZRWViewerPlugin.Create(nil);
  try
    Assert.IsFalse(Plugin.LoadFromFile(Bad));
    Text := PluginLoadErrorText(Plugin, 'Plugin could not load the file.');
    Assert.IsTrue(Pos('line 5', Text) > 0, Text);
  finally
    Plugin.Free;
  end;
end;

function TValueSourceDesktopTests.CofCount: Integer;
var
  Value: TValue;
begin
  Result := 0;
  for Value in FItem.Values do
    if Value.KeyName = 'COF' then
      Inc(Result);
end;

function TValueSourceDesktopTests.CofValue: TValue;
var
  Candidate: TValue;
begin
  Result := nil;
  for Candidate in FItem.Values do
    if Candidate.KeyName = 'COF' then
      Exit(Candidate);
end;

procedure TValueSourceDesktopTests.WriteChosenValuesMatchesNameAndUnits;
var
  FileType: TFileType;
  AFile: unit_Item.TFile;
  Choice: TExtractChoice;
  Keys: TArray<TPluginKeyValue>;
  Skipped: Integer;
begin
  ThicknessType;
  FileType := TFileType.Create;
  FileType.Ext := '.xrcx';
  FileType.Description := 'Synthetic chosen values';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'chosen scan', Model.User.Id, FItem);
  Choice.Name := 'd';
  Choice.Units := 'm';
  Choice.Occurrence := 0;
  Choice.Mapping := Default(TReaderValueResolution);
  Choice.Mapping.ValueType := Model.ValueTypes.FindByTitleUnits('Synthetic thickness', 'm');
  Choice.Mapping.Factor := 1;
  SetLength(Keys, 3);
  Keys[0] := Default(TPluginKeyValue);
  Keys[0].Name := 'd';
  Keys[0].Units := 'm';
  Keys[0].Value := 2e-9;
  Keys[0].IsKey := True;
  Keys[0].RecType := prResult;
  Keys[1] := Keys[0];
  Keys[1].Units := 'nm';
  Keys[1].Value := 3;
  Keys[2] := Keys[0];
  Keys[2].Name := 'e';
  Keys[2].Units := 'm';
  Keys[2].Value := 1;
  Assert.AreEqual(1, WriteChosenValues([Choice], Keys, Model.User.Id, FItem,
    AFile.Id, 'aps.xrcx', '1', nil, False, 1000, Skipped));
  Assert.AreEqual(0, Skipped);
  Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
  Assert.AreEqual(2e-9, FreshValue(FItem.Values[0].Id).Value, 1e-22);
end;

procedure TValueSourceDesktopTests.WriteChosenValuesSkipsMissingAndIssues;
var
  FileType: TFileType;
  AFile: unit_Item.TFile;
  Choices: TArray<TExtractChoice>;
  Keys: TArray<TPluginKeyValue>;
  VT: TValueType;
  Skipped: Integer;
begin
  ThicknessType;
  VT := Model.ValueTypes.FindByTitleUnits('Synthetic thickness', 'm');
  VT.RangeMax := 4.0;
  Model.Manager.Flush(VT);
  FileType := TFileType.Create;
  FileType.Ext := '.xrcx';
  FileType.Description := 'Synthetic chosen values';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'chosen scan', Model.User.Id, FItem);
  SetLength(Choices, 2);
  Choices[0].Name := 'd';
  Choices[0].Units := 'm';
  Choices[0].Occurrence := 0;
  Choices[0].Mapping := Default(TReaderValueResolution);
  Choices[0].Mapping.ValueType := VT;
  Choices[0].Mapping.Factor := 1;
  Choices[1] := Choices[0];
  Choices[1].Name := 'h';
  SetLength(Keys, 1);
  Keys[0] := Default(TPluginKeyValue);
  Keys[0].Name := 'd';
  Keys[0].Units := 'm';
  Keys[0].Value := 5;
  Keys[0].IsKey := True;
  Keys[0].RecType := prResult;
  Assert.AreEqual(0, WriteChosenValues(Choices, Keys, Model.User.Id, FItem,
    AFile.Id, 'aps.xrcx', '1', nil, True, 1000, Skipped));
  Assert.AreEqual(2, Skipped);
  Assert.AreEqual<NativeInt>(0, FItem.Values.Count);
  Assert.AreEqual(1, WriteChosenValues(Choices, Keys, Model.User.Id, FItem,
    AFile.Id, 'aps.xrcx', '1', nil, False, 1000, Skipped));
  Assert.AreEqual(1, Skipped);
  Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
end;

procedure TValueSourceDesktopTests.WriteChosenValuesPairsDuplicateKeysInOrder;
var
  FileType: TFileType;
  AFile: unit_Item.TFile;
  Choices: TArray<TExtractChoice>;
  Keys: TArray<TPluginKeyValue>;
  Skipped: Integer;
  A, B: Double;
begin
  ThicknessType;
  FileType := TFileType.Create;
  FileType.Ext := '.xrcx';
  FileType.Description := 'Synthetic chosen values';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'chosen scan', Model.User.Id, FItem);
  SetLength(Choices, 2);
  Choices[0].Name := 'd';
  Choices[0].Units := 'm';
  Choices[0].Occurrence := 0;
  Choices[0].Mapping := Default(TReaderValueResolution);
  Choices[0].Mapping.ValueType := Model.ValueTypes.FindByTitleUnits('Synthetic thickness', 'm');
  Choices[0].Mapping.Factor := 1;
  Choices[1] := Choices[0];
  Choices[1].Occurrence := 1;
  SetLength(Keys, 2);
  Keys[0] := Default(TPluginKeyValue);
  Keys[0].Name := 'd';
  Keys[0].Units := 'm';
  Keys[0].Value := 2e-9;
  Keys[0].IsKey := True;
  Keys[0].RecType := prResult;
  Keys[1] := Keys[0];
  Keys[1].Value := 3e-9;
  Assert.AreEqual(2, WriteChosenValues(Choices, Keys, Model.User.Id, FItem,
    AFile.Id, 'aps.xrcx', '1', nil, False, 1000, Skipped));
  Assert.AreEqual(0, Skipped);
  Assert.AreEqual<NativeInt>(2, FItem.Values.Count);
  A := FreshValue(FItem.Values[0].Id).Value;
  B := FreshValue(FItem.Values[1].Id).Value;
  Assert.AreEqual(5e-9, A + B, 1e-22);
  Assert.AreNotEqual(A, B);
  SetLength(Keys, 1);
  Assert.AreEqual(1, WriteChosenValues(Choices, Keys, Model.User.Id, FItem,
    AFile.Id, 'aps.xrcx', '1', nil, False, 1000, Skipped));
  Assert.AreEqual(1, Skipped);
  Assert.AreEqual<NativeInt>(2, FItem.Values.Count,
    'Extracting the file again updates the first occurrence instead of adding one');
end;

procedure TValueSourceDesktopTests.ReExtractionFromOneFileUpdatesItsValue;
var
  Resolver: TReaderValueMappingModel;
  FileType: TFileType;
  AFile, Other: unit_Item.TFile;
  KV: TPluginKeyValue;
  Warning: string;
  ValueId: Integer;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.xrcx';
  FileType.Description := 'Synthetic repeated extraction';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'fit', Model.User.Id, FItem);
  Other := Model.Items.AddFile(FileType, 'second fit', Model.User.Id, FItem);
  KV := Default(TPluginKeyValue);
  KV.Name := 'Co Thickness';
  KV.Units := 'A';
  KV.Value := 15;
  KV.IsKey := True;
  KV.RecType := prResult;
  Resolver := TReaderValueMappingModel.Create(Model.Manager);
  try
    Assert.AreEqual(0, WriteAutomaticExtractedValues(Model.Items, Resolver, [KV],
      Model.User.Id, FItem, AFile.Id, 'aps.xrcx', '1', nil, 1000, Warning));
    Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
    ValueId := FItem.Values[0].Id;
    WriteAutomaticExtractedValues(Model.Items, Resolver, [KV], Model.User.Id,
      FItem, AFile.Id, 'aps.xrcx', '1', nil, 1000, Warning);
    Assert.AreEqual<NativeInt>(1, FItem.Values.Count,
      'A second extraction from the same file must not add a value');
    Assert.IsFalse(FreshValue(ValueId).ModifiedDate.HasValue,
      'An unchanged number is not written again');
    KV.Value := 16;
    WriteAutomaticExtractedValues(Model.Items, Resolver, [KV], Model.User.Id,
      FItem, AFile.Id, 'aps.xrcx', '1', nil, 1000, Warning);
    Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
    Assert.AreEqual(ValueId, FItem.Values[0].Id, 'The stored value keeps its ID');
    Assert.AreEqual(16e-10, FreshValue(ValueId).Value, 1e-22);
    Assert.IsTrue(FreshValue(ValueId).ModifiedDate.HasValue);
    WriteAutomaticExtractedValues(Model.Items, Resolver, [KV], Model.User.Id,
      FItem, Other.Id, 'aps.xrcx', '1', nil, 1000, Warning);
    Assert.AreEqual<NativeInt>(2, FItem.Values.Count, 'Another file gives its own value');
  finally
    Resolver.Free;
  end;
end;

procedure TValueSourceDesktopTests.WriteChosenValuesUsesCheckedOccurrence;
var
  FileType: TFileType;
  AFile: unit_Item.TFile;
  Choice: TExtractChoice;
  Keys: TArray<TPluginKeyValue>;
  Skipped: Integer;
begin
  ThicknessType;
  FileType := TFileType.Create;
  FileType.Ext := '.xrcx';
  FileType.Description := 'Synthetic chosen values';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'chosen scan', Model.User.Id, FItem);
  Choice.Name := 'd';
  Choice.Units := 'm';
  Choice.Occurrence := 1;
  Choice.Mapping := Default(TReaderValueResolution);
  Choice.Mapping.ValueType := Model.ValueTypes.FindByTitleUnits('Synthetic thickness', 'm');
  Choice.Mapping.Factor := 1;
  SetLength(Keys, 2);
  Keys[0] := Default(TPluginKeyValue);
  Keys[0].Name := 'd';
  Keys[0].Units := 'm';
  Keys[0].Value := 2e-9;
  Keys[0].IsKey := True;
  Keys[0].RecType := prResult;
  Keys[1] := Keys[0];
  Keys[1].Value := 3e-9;
  Assert.AreEqual(1, WriteChosenValues([Choice], Keys, Model.User.Id, FItem,
    AFile.Id, 'aps.xrcx', '1', nil, False, 1000, Skipped));
  Assert.AreEqual(0, Skipped);
  Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
  Assert.AreEqual(3e-9, FreshValue(FItem.Values[0].Id).Value, 1e-22);
  SetLength(Keys, 1);
  Assert.AreEqual(0, WriteChosenValues([Choice], Keys, Model.User.Id, FItem,
    AFile.Id, 'aps.xrcx', '1', nil, False, 1000, Skipped));
  Assert.AreEqual(1, Skipped);
  Assert.AreEqual<NativeInt>(1, FItem.Values.Count);
end;

procedure TValueSourceDesktopTests.DerivedValueDialogComputesFromChosenInputs;
var
  Dialog: TdlgDerivedValue;
  ValueEditor: TdlgValue;
  Saved: TValueIssueConfirmation;
  I, Formula: Integer;
  StoredId: Integer;
  Stored: TValue;
begin
  FVM.AddValue(Model.ValueTypes.FindByTitleUnits('Wear area', 'mm' + #$00B2),
    TEST_RESULT, 0.004, FItem, 0, 'track', TValueSourceInfo.Manual('profile'));
  FVM.AddValue(Model.ValueTypes.FindByTitleUnits('Normal force', 'N'),
    EXP_CONDITION, 5, FItem, 0, '', TValueSourceInfo.Manual('setup'));
  FVM.AddValue(Model.ValueTypes.FindByTitleUnits('Cycles', ''),
    EXP_CONDITION, 1000, FItem, 0, '', TValueSourceInfo.Manual('setup'));
  FVM.AddValue(Model.Manager.Find<TValueType>(ThicknessType), TEST_RESULT, 1e-6,
    FItem, 0, '', TValueSourceInfo.Manual('other'));
  Dialog := TdlgDerivedValue.Create(nil);
  try
    Dialog.Load(Model.Manager, FItem, 1e3);
    Formula := -1;
    for I := 0 to Dialog.lbFormula.Items.Count - 1 do
      if Pos(WEAR_RATE_FORMULA_ID, Dialog.lbFormula.Items[I]) > 0 then
        Formula := I;
    Assert.IsTrue(Formula >= 0, 'The wear-rate formula is offered');
    Dialog.lbFormula.ItemIndex := Formula;
    Dialog.lbFormulaClick(Dialog.lbFormula);
    Assert.AreEqual<NativeInt>(3, Dialog.lbRoles.Items.Count, 'Every role is listed');
    Assert.IsFalse(Dialog.btnSave.Enabled, 'Nothing can be stored before inputs are chosen');
    for I := 0 to Dialog.lbRoles.Items.Count - 1 do
    begin
      Dialog.lbRoles.ItemIndex := I;
      Dialog.lbRolesClick(Dialog.lbRoles);
      Assert.AreEqual<NativeInt>(1, Dialog.lbCandidates.Items.Count,
        'Only values of the required type and unit are offered');
      Dialog.lbCandidates.Selected[0] := True;
      Dialog.lbCandidatesClick(Dialog.lbCandidates);
    end;
    Assert.IsTrue(Dialog.Valid, 'Chosen inputs give a value');
    Assert.IsTrue(Dialog.btnSave.Enabled);
    Assert.AreEqual(4e-7, Dialog.Computation.Number, 1e-20);
    Assert.Contains(Dialog.lblResult.Caption, 'Wear rate');
    Dialog.ModalResult := mrOk;
    Assert.IsTrue(Dialog.CloseQuery);
    StoredId := Dialog.Store(Model.User.Id).Id;
  finally
    Dialog.Free;
  end;
  Stored := FreshValue(StoredId);
  Assert.IsTrue(Stored.EffectiveSourceKind = vskDerived);
  Assert.AreEqual(WEAR_RATE_FORMULA_ID, Stored.FormulaId.Value);
  Assert.AreEqual(1, Stored.FormulaVersion.Value);
  Assert.AreEqual<NativeInt>(3, Stored.DerivedInputs.Count);
  Assert.AreEqual<Double>(0, Stored.Tol, 'The client stores no tolerance');

  Saved := ConfirmValueIssues;
  ValueEditor := TdlgValue.Create(nil);
  try
    ConfirmValueIssues :=
      function(const Text: string): Boolean
      begin
        Result := True;
      end;
    ValueEditor.LoadValueTypes(Model.ValueTypes.GetTypes);
    ValueEditor.LoadValue(Stored, '');
    Assert.Contains(ValueEditor.lblSource.Caption, 'derived by ' + WEAR_RATE_FORMULA_ID);
    Assert.Contains(ValueEditor.lblSource.Caption, 'area = value');
    ValueEditor.edDescription.Text := 'Only the description changes';
    ValueEditor.ApplyTo(Stored);
    Assert.IsTrue(Stored.EffectiveSourceKind = vskDerived,
      'An untouched number keeps the Derived source');
    ValueEditor.edValue.Text := '5e-7';
    ValueEditor.ApplyTo(Stored);
    Assert.IsTrue(Stored.EffectiveSourceKind = vskManual,
      'A number typed by hand makes the value Manual');
    Assert.Contains(Stored.SourceNote, 'was derived by ' + WEAR_RATE_FORMULA_ID);
  finally
    ConfirmValueIssues := Saved;
    ValueEditor.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TValueSourceDesktopTests);

end.
