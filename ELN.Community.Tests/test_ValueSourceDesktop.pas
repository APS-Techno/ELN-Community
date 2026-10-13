unit test_ValueSourceDesktop;

interface

uses
  DUnitX.TestFramework, Aurelius.Engine.ObjectManager, unit_LocalNotebook,
  unit_Item, unit_ItemTreeVM;

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
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ManualEntryThroughItemTreePersistsManual;
    [Test] procedure ExtractedValueRecordsReaderSource;
    [Test] procedure EditedValueRecordsModification;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  unit_Project, unit_ItemTypes, unit_ProjectAccessPolicy, unit_ValueType,
  unit_FileType, unit_ValueSource, unit_ELNPluginTypes, unit_DataModel,
  dlg_ExtractValues, unit_ActionDialogVM;

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
  Assert.AreEqual(1, FItem.Values.Count);
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
  WriteExtractedValue(Model.Items, VT, KV, Model.User.Id, FItem, AFile.Id,
    'synthetic.reader', '2.1');

  Assert.AreEqual(1, FItem.Values.Count);
  Stored := FreshValue(FItem.Values[0].Id);
  Assert.IsTrue(Stored.EffectiveSourceKind = vskReader);
  Assert.IsTrue(Stored.RecType = TEST_RESULT);
  Assert.AreEqual<Double>(1.5e-6, Stored.Value);
  Assert.AreEqual<Int64>(AFile.Id, Stored.SourceFileId.Value);
  Assert.AreEqual('synthetic.reader', Stored.ReaderId);
  Assert.AreEqual('2.1', Stored.ReaderVersion);
  Assert.AreEqual('Synthetic thickness', Stored.KeyName);
end;

initialization
  TDUnitX.RegisterTestFixture(TValueSourceDesktopTests);

end.
