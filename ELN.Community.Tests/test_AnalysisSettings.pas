unit test_AnalysisSettings;

interface

uses
  System.SysUtils, DUnitX.TestFramework, Aurelius.Engine.ObjectManager,
  unit_LocalNotebook, unit_ItemModel,
  unit_Item, unit_ValueSource, unit_AnalysisSettingsModel;

type
  [TestFixture]
  TAnalysisSettingsTests = class
  private
    FRoot, FDbPath, FFilesPath: string;
    FNotebook: TLocalNotebook;
    FSecond: TObjectManager;
    FItems: TItemModel;
    FProjectId, FItemId, FValueTypeId: Integer;
    FFileId: Int64;
    procedure Reopen;
    function Apply(Manager: TObjectManager; const Expected, New, Hash: string;
      out Current: string): TAnalysisApplyStatus;
    function SelectionJson(const Hash: string): string;
    function PaddedJson(const Hash: string; TotalLength: Integer): string;
    function RowCount(const Pattern: string): Integer;
    function CurrentItem: TItem;
    function ReaderSource(const ReaderId: string): TValueSourceInfo;
    function AddReaderValue(const ReaderId, Snapshot: string): Integer;
    function ApplyShared(const Expected, New: string): Boolean;
    function FindValue(ValueId: Integer): TValue;
    procedure ExecuteSql(const Sql: string);
    function DriftFlagsAfter(const Snapshot, RunHash: string;
      SharedBefore, SharedAfter: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ContentHashIsUpperCaseMd5;
    [Test] procedure AppliedSelectionSurvivesReopen;
    [Test] procedure SecondManagerWithEmptyExpectedConflicts;
    [Test] procedure StaleExpectedJsonConflictsAndKeepsRow;
    [Test] procedure CurrentExpectedJsonSwapsRow;
    [Test] procedure HashMismatchIsRejected;
    [Test] procedure SignedItemIsRejected;
    [Test] procedure ProjectWithoutWriteAccessIsDenied;
    [Test] procedure OversizedSelectionIsRejectedWithoutRow;
    [Test] procedure SelectionOfMaximumLengthIsApplied;
    [Test] procedure NonJsonSelectionIsInvalid;
    [Test] procedure AddValueWithSnapshotStoresBoth;
    [Test] procedure OversizedSnapshotStoresNothing;
    [Test] procedure SnapshotFailureAfterFlushRollsBackValue;
    [Test] procedure RemoveValueDeletesSnapshot;
    [Test] procedure RemoveFileDeletesItsExtractedValues;
    [Test] procedure RemoveFileDeletesViewerStateWithoutDesktopModel;
    [Test] procedure PurgeItemDeletesBothKinds;
    [Test] procedure OrphanSnapshotIsNotLoaded;
    [Test] procedure RegionsSnapshotMatchingSharedSelectionIsUnchanged;
    [Test] procedure ReplacedSharedSelectionIsSelectionChangedOnly;
    [Test] procedure RegionsSnapshotWithOtherFileHashIsSourceChanged;
    [Test] procedure RegionsSnapshotWithoutProvenanceIsNeverSelectionChanged;
    [Test] procedure DeletedSharedSelectionIsSelectionChangedWithProvenance;
  end;

implementation

uses
  System.IOUtils, System.Classes, System.Generics.Collections, System.JSON,
  Aurelius.Drivers.Interfaces,
  unit_Project, unit_ProjectModel, unit_ItemTypes, unit_FileType,
  unit_ValueType, unit_SignatureModel, unit_RecycleBinModel, unit_ValueDrift,
  unit_ViewerStateModel, unit_FilePaths, unit_DataModel;

const
  Password = 'Synthetic-Analysis-Settings-Only!';
  ReaderZrw = 'aps.zrw';
  HashA = 'ABCDEF0123456789ABCDEF0123456789';

procedure TAnalysisSettingsTests.Setup;
var
  Projects: TProjectsModel;
  FileType: TFileType;
  ValueType: TValueType;
  Detached, Host: TItem;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'eln-analysis-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FDbPath := TPath.Combine(FRoot, 'notebook.sqlite');
  FFilesPath := TPath.Combine(FRoot, 'attachments');
  FNotebook := TLocalNotebook.CreateNew(FDbPath, FFilesPath, 'Synthetic',
    'Scientist', Password);
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    FProjectId := Projects.AddProject('Analysis fixture', '', FNotebook.Principal).Id;
  finally
    Projects.Free;
  end;
  FItems := TItemModel.Create(FNotebook.Manager);
  FItems.AssignProject(FProjectId, 0);
  Detached := FItems.AddItem(TItemType.Specimen, 'Synthetic specimen',
    TItemLevel.Item, 0, '', nil, nil, FNotebook.Principal.Id);
  FItemId := Detached.Id;
  Detached.Free;
  FileType := TFileType.Create;
  FileType.Ext := '.zrw';
  FileType.CreatedDate := Now;
  FNotebook.Manager.Save(FileType);
  ValueType := TValueType.Create;
  ValueType.Symbol := 'COF';
  ValueType.Title := 'Coefficient of friction';
  ValueType.Units := '-';
  ValueType.CreatedDate := Now;
  FNotebook.Manager.Save(ValueType);
  FNotebook.Manager.Flush;
  FValueTypeId := ValueType.Id;
  Host := FNotebook.Manager.Find<TItem>(FItemId);
  FFileId := FItems.AddFile(FileType, 'tribometer.zrw', FNotebook.Principal.Id,
    Host).Id;
end;

procedure TAnalysisSettingsTests.TearDown;
begin
  FreeAndNil(FItems);
  FreeAndNil(FSecond);
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TAnalysisSettingsTests.Reopen;
begin
  FreeAndNil(FItems);
  FreeAndNil(FNotebook);
  FNotebook := TLocalNotebook.Open(FDbPath, FFilesPath);
  FItems := TItemModel.Create(FNotebook.Manager);
  FItems.AssignProject(FProjectId, 0);
end;

function TAnalysisSettingsTests.Apply(Manager: TObjectManager; const Expected,
  New, Hash: string; out Current: string): TAnalysisApplyStatus;
var
  Model: TAnalysisSettingsModel;
begin
  Model := TAnalysisSettingsModel.Create(Manager);
  try
    Result := Model.ApplySelection(FNotebook.AccessPolicy, FNotebook.Principal,
      ReaderZrw, FFileId, Expected, New, Hash, Current);
  finally
    Model.Free;
  end;
end;

function TAnalysisSettingsTests.SelectionJson(const Hash: string): string;
begin
  Result := Format('{"mode":"manual","start":1.5,"end":2.5,"file_hash":"%s",' +
    '"apply_id":"%s"}', [Hash, TGUID.NewGuid.ToString]);
end;

function TAnalysisSettingsTests.PaddedJson(const Hash: string;
  TotalLength: Integer): string;
var
  Base: string;
begin
  Base := '{"file_hash":"' + Hash + '","pad":""}';
  Result := '{"file_hash":"' + Hash + '","pad":"' +
    StringOfChar('x', TotalLength - Base.Length) + '"}';
end;

function TAnalysisSettingsTests.RowCount(const Pattern: string): Integer;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('SELECT COUNT(*) FROM DBSettings WHERE SettingKey LIKE ''' +
    Pattern + '''');
  Rows := Statement.ExecuteQuery;
  Assert.IsTrue(Rows.Next);
  Result := Rows.GetFieldValue(0);
end;

function TAnalysisSettingsTests.CurrentItem: TItem;
begin
  Result := FNotebook.Manager.Find<TItem>(FItemId);
end;

function TAnalysisSettingsTests.ReaderSource(const ReaderId: string): TValueSourceInfo;
begin
  Result := TValueSourceInfo.Reader(FFileId, ReaderId, '2', 'COF', 'u', 1.0);
end;

function TAnalysisSettingsTests.AddReaderValue(const ReaderId,
  Snapshot: string): Integer;
var
  Item: TItem;
begin
  Item := CurrentItem;
  if Snapshot = '' then
    FItems.AddValue(FNotebook.Manager.Find<TValueType>(FValueTypeId),
      TRecType.TEST_RESULT, 0.4, FNotebook.Principal.Id, Item, 0.01, 'COF',
      ReaderSource(ReaderId))
  else
    FItems.AddValue(FNotebook.Manager.Find<TValueType>(FValueTypeId),
      TRecType.TEST_RESULT, 0.4, FNotebook.Principal.Id, Item, 0.01, 'COF',
      ReaderSource(ReaderId), Snapshot);
  Result := Item.Values[Item.Values.Count - 1].Id;
end;

function TAnalysisSettingsTests.FindValue(ValueId: Integer): TValue;
begin
  Result := FNotebook.Manager.Find<TValue>(ValueId);
end;

procedure TAnalysisSettingsTests.ContentHashIsUpperCaseMd5;
var
  Path: string;
begin
  Path := TPath.Combine(FRoot, 'abc.bin');
  System.IOUtils.TFile.WriteAllBytes(Path, TEncoding.ASCII.GetBytes('abc'));
  Assert.AreEqual('900150983CD24FB0D6963F7D28E17F72',
    TAnalysisSettingsModel.ContentHash(Path));
end;

procedure TAnalysisSettingsTests.AppliedSelectionSurvivesReopen;
var
  Json, Current, Loaded: string;
  Model: TAnalysisSettingsModel;
begin
  Json := SelectionJson(HashA);
  Assert.AreEqual(Ord(aasApplied), Ord(Apply(FNotebook.Manager, '', Json, HashA, Current)));
  Assert.AreEqual(Json, Current);
  Reopen;
  Model := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Model.LoadSelection(ReaderZrw, FFileId, Loaded));
    Assert.AreEqual(Json, Loaded);
    Assert.IsFalse(Model.LoadSelection('other.reader', FFileId, Loaded));
  finally
    Model.Free;
  end;
end;

procedure TAnalysisSettingsTests.SecondManagerWithEmptyExpectedConflicts;
var
  First, Second, Current, Loaded: string;
  Model: TAnalysisSettingsModel;
begin
  FSecond := TObjectManager.Create(FNotebook.Connection);
  First := SelectionJson(HashA);
  Second := SelectionJson(HashA);
  Assert.AreEqual(Ord(aasApplied), Ord(Apply(FNotebook.Manager, '', First, HashA, Current)));
  Assert.AreEqual(Ord(aasConflict), Ord(Apply(FSecond, '', Second, HashA, Current)));
  Assert.AreEqual(First, Current);
  Model := TAnalysisSettingsModel.Create(FSecond);
  try
    Assert.IsTrue(Model.LoadSelection(ReaderZrw, FFileId, Loaded));
    Assert.AreEqual(First, Loaded);
  finally
    Model.Free;
  end;
end;

procedure TAnalysisSettingsTests.StaleExpectedJsonConflictsAndKeepsRow;
var
  First, Second, Third, Current, Loaded: string;
  Model: TAnalysisSettingsModel;
begin
  First := SelectionJson(HashA);
  Second := SelectionJson(HashA);
  Third := SelectionJson(HashA);
  Assert.AreEqual(Ord(aasApplied), Ord(Apply(FNotebook.Manager, '', First, HashA, Current)));
  Assert.AreEqual(Ord(aasApplied), Ord(Apply(FNotebook.Manager, First, Second, HashA, Current)));
  Assert.AreEqual(Ord(aasConflict), Ord(Apply(FNotebook.Manager, First, Third, HashA, Current)));
  Assert.AreEqual(Second, Current);
  Model := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Model.LoadSelection(ReaderZrw, FFileId, Loaded));
    Assert.AreEqual(Second, Loaded);
  finally
    Model.Free;
  end;
end;

procedure TAnalysisSettingsTests.CurrentExpectedJsonSwapsRow;
var
  First, Second, Current: string;
begin
  First := SelectionJson(HashA);
  Second := SelectionJson(HashA);
  Assert.AreEqual(Ord(aasApplied), Ord(Apply(FNotebook.Manager, '', First, HashA, Current)));
  Assert.AreEqual(Ord(aasApplied), Ord(Apply(FNotebook.Manager, First, Second, HashA, Current)));
  Assert.AreEqual(Second, Current);
end;

procedure TAnalysisSettingsTests.HashMismatchIsRejected;
var
  Current: string;
begin
  Assert.AreEqual(Ord(aasHashMismatch),
    Ord(Apply(FNotebook.Manager, '', SelectionJson(HashA), 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', Current)));
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.SignedItemIsRejected;
var
  Signatures: TSignatureModel;
  Current: string;
begin
  Signatures := TSignatureModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Signatures.SignItem(CurrentItem, FNotebook.Principal, Password,
      'Synthetic signature', ''));
  finally
    Signatures.Free;
  end;
  Assert.AreEqual(Ord(aasSigned),
    Ord(Apply(FNotebook.Manager, '', SelectionJson(HashA), HashA, Current)));
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.ProjectWithoutWriteAccessIsDenied;
var
  Current: string;
begin
  FNotebook.Manager.Find<TProject>(FProjectId).IsArchived := True;
  FNotebook.Manager.Flush;
  Assert.IsFalse(FNotebook.AccessPolicy.CanWrite(FNotebook.Manager,
    FNotebook.Principal, FProjectId), 'Fixture must deny writes');
  Assert.AreEqual(Ord(aasDenied),
    Ord(Apply(FNotebook.Manager, '', SelectionJson(HashA), HashA, Current)));
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.OversizedSelectionIsRejectedWithoutRow;
var
  Json, Current: string;
begin
  Json := PaddedJson(HashA, 2001);
  Assert.AreEqual(2001, Json.Length);
  Assert.AreEqual(Ord(aasTooLarge), Ord(Apply(FNotebook.Manager, '', Json, HashA, Current)));
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.SelectionOfMaximumLengthIsApplied;
var
  Json, Current: string;
begin
  Json := PaddedJson(HashA, 2000);
  Assert.AreEqual(2000, Json.Length);
  Assert.AreEqual(Ord(aasApplied), Ord(Apply(FNotebook.Manager, '', Json, HashA, Current)));
  Assert.AreEqual(1, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.NonJsonSelectionIsInvalid;
var
  Current: string;
begin
  Assert.AreEqual(Ord(aasInvalid), Ord(Apply(FNotebook.Manager, '', 'not json', HashA, Current)));
  Assert.AreEqual(Ord(aasInvalid), Ord(Apply(FNotebook.Manager, '', '{"mode":"manual"}', HashA, Current)));
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.AddValueWithSnapshotStoresBoth;
var
  ValueId: Integer;
  Loaded: string;
  Parsed: TJSONObject;
  Model: TAnalysisSettingsModel;
begin
  ValueId := AddReaderValue(ReaderZrw, '{"mode":"automatic","file_hash":"' + HashA + '"}');
  Reopen;
  Assert.IsNotNull(FindValue(ValueId));
  Assert.AreEqual(1, RowCount(TAnalysisSettingsModel.ValueKey(ReaderZrw, ValueId)));
  Model := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Model.LoadSnapshot(FindValue(ValueId), Loaded));
  finally
    Model.Free;
  end;
  Parsed := TJSONObject.ParseJSONValue(Loaded) as TJSONObject;
  try
    Assert.AreEqual(ValueId, Parsed.GetValue<Integer>('value_id'));
    Assert.AreEqual(FFileId, Parsed.GetValue<Int64>('file_id'));
    Assert.AreEqual(ReaderZrw, Parsed.GetValue<string>('reader_id'));
    Assert.AreEqual('COF', Parsed.GetValue<string>('key_name'));
    Assert.AreEqual('automatic', Parsed.GetValue<string>('mode'));
  finally
    Parsed.Free;
  end;
end;

procedure TAnalysisSettingsTests.OversizedSnapshotStoresNothing;
var
  Item: TItem;
begin
  Item := CurrentItem;
  Assert.WillRaise(
    procedure
    begin
      FItems.AddValue(FNotebook.Manager.Find<TValueType>(FValueTypeId),
        TRecType.TEST_RESULT, 0.4, FNotebook.Principal.Id, Item, 0.01, 'COF',
        ReaderSource(ReaderZrw), PaddedJson(HashA, 2001));
    end, EArgumentException);
  Reopen;
  Assert.AreEqual<NativeInt>(0, CurrentItem.Values.Count);
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.SnapshotFailureAfterFlushRollsBackValue;
var
  Item: TItem;
  LongReader: string;
begin
  LongReader := StringOfChar('r', 90);
  Item := CurrentItem;
  Assert.WillRaise(
    procedure
    begin
      FItems.AddValue(FNotebook.Manager.Find<TValueType>(FValueTypeId),
        TRecType.TEST_RESULT, 0.4, FNotebook.Principal.Id, Item, 0.01, 'COF',
        ReaderSource(LongReader), '{"file_hash":"' + HashA + '"}');
    end, EArgumentException);
  Assert.AreEqual<NativeInt>(0, Item.Values.Count);
  Reopen;
  Assert.AreEqual<NativeInt>(0, CurrentItem.Values.Count);
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.RemoveValueDeletesSnapshot;
var
  ValueId: Integer;
  Item: TItem;
begin
  ValueId := AddReaderValue(ReaderZrw, '{"file_hash":"' + HashA + '"}');
  Assert.AreEqual(1, RowCount('analysis:%'));
  Item := CurrentItem;
  FItems.RemoveValue(FindValue(ValueId), Item, FNotebook.Principal.Id);
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.RemoveFileDeletesItsExtractedValues;
var
  Current: string;
  Item: TItem;
  FileEntity: unit_Item.TFile;
  ExtractedId, ManualId: Integer;
begin
  ExtractedId := AddReaderValue(ReaderZrw, '{"file_hash":"' + HashA + '"}');
  Item := CurrentItem;
  FItems.AddValue(FNotebook.Manager.Find<TValueType>(FValueTypeId),
    TRecType.TEST_RESULT, 0.5, FNotebook.Principal.Id, Item, 0, 'COF',
    TValueSourceInfo.Manual('Edited by hand', FFileId));
  ManualId := Item.Values[Item.Values.Count - 1].Id;
  Assert.AreEqual(Ord(aasApplied),
    Ord(Apply(FNotebook.Manager, '', SelectionJson(HashA), HashA, Current)));
  Assert.AreEqual(2, RowCount('analysis:%'));
  FileEntity := FNotebook.Manager.Find<unit_Item.TFile>(FFileId);
  Assert.IsTrue(FItems.RemoveFile(FileEntity, Item, FNotebook.Principal.Id));
  Assert.AreEqual(0, RowCount('analysis:%'));
  Reopen;
  Assert.IsNull(FindValue(ExtractedId), 'A value read from the file goes with the file');
  Assert.IsNotNull(FindValue(ManualId), 'A Manual value stays');
  Assert.AreEqual<NativeInt>(1, CurrentItem.Values.Count);
end;

procedure TAnalysisSettingsTests.RemoveFileDeletesViewerStateWithoutDesktopModel;
var
  Item: TItem;
  FileEntity: unit_Item.TFile;
  States: TViewerStateModel;
begin
  Assert.IsNull(unit_DataModel.Model, 'The MCP host has no Desktop model');
  States := TViewerStateModel.Create(FNotebook.Manager);
  try
    States.SaveOrUpdate(FNotebook.Principal.Id, FFileId, 'aps.zrw', '{}');
    Assert.IsNotNull(States.GetState(FNotebook.Principal.Id, FFileId));
    Item := CurrentItem;
    FileEntity := FNotebook.Manager.Find<unit_Item.TFile>(FFileId);
    Assert.IsTrue(FItems.RemoveFile(FileEntity, Item, FNotebook.Principal.Id));
    Assert.IsNull(States.GetState(FNotebook.Principal.Id, FFileId));
  finally
    States.Free;
  end;
end;

procedure TAnalysisSettingsTests.PurgeItemDeletesBothKinds;
var
  Current: string;
  Bin: TRecycleBinModel;
begin
  AddReaderValue(ReaderZrw, '{"file_hash":"' + HashA + '"}');
  Assert.AreEqual(Ord(aasApplied),
    Ord(Apply(FNotebook.Manager, '', SelectionJson(HashA), HashA, Current)));
  Assert.AreEqual(2, RowCount('analysis:%'));
  Assert.IsTrue(FItems.SoftDeleteItemTree(CurrentItem, FNotebook.Principal.Id));
  Bin := TRecycleBinModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Bin.PermanentlyDelete(CurrentItem, FNotebook.Principal.Id));
  finally
    Bin.Free;
  end;
  Assert.AreEqual(0, RowCount('analysis:%'));
end;

procedure TAnalysisSettingsTests.OrphanSnapshotIsNotLoaded;
var
  ValueId: Integer;
  Value: TValue;
  Model: TAnalysisSettingsModel;
  Json: string;
begin
  ValueId := AddReaderValue(ReaderZrw, '');
  Value := FindValue(ValueId);
  Model := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    Assert.IsFalse(Model.LoadSnapshot(Value, Json), 'No row yet');
    Model.SaveSnapshot(ReaderZrw, ValueId, Format(
      '{"value_id":%d,"file_id":%d,"reader_id":"%s","key_name":"COF STD"}',
      [ValueId, FFileId, ReaderZrw]));
    Assert.IsFalse(Model.LoadSnapshot(Value, Json), 'Another key name is an orphan');
    Assert.AreEqual('', Json);
    Model.SaveSnapshot(ReaderZrw, ValueId, Format(
      '{"value_id":%d,"file_id":%d,"reader_id":"%s","key_name":"COF"}',
      [ValueId, FFileId, ReaderZrw]));
    Assert.IsTrue(Model.LoadSnapshot(Value, Json));
  finally
    Model.Free;
  end;
end;

function RegionsJson(const Extra: string): string;
begin
  Result := '"schema_version":1,"mode":"regions","rect_a":[0,0,1,1],' +
    '"rect_b":[2,2,3,3],"pix_w":4,"pix_h":4,"file_hash":"' + HashA + '"' + Extra;
end;

function RegionsSelection(Revision: Integer; const ApplyId: string): string;
begin
  Result := '{"reader_id":"aps.fibps",' + RegionsJson(Format(
    ',"apply_id":"%s","revision":%d', [ApplyId, Revision])) + '}';
end;

function RegionsSnapshot(Revision: Integer; const ApplyId: string;
  WithProvenance: Boolean; const Hash: string): string;
var
  Extra: string;
begin
  Extra := '';
  if WithProvenance then
    Extra := Format(',"shared_revision":%d,"shared_apply_id":"%s"',
      [Revision, ApplyId]);
  Result := '{"reader_id":"aps.fibps",' + RegionsJson(Extra) + '}';
  if Hash <> HashA then
    Result := StringReplace(Result, HashA, Hash, []);
end;

type
  TRegionsRunner = class(TInterfacedObject, IValueReaderRunner)
    CurrentHash: string;
    function Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
  end;

function TRegionsRunner.Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
begin
  Result := Default(TReaderRun);
  Result.Succeeded := True;
  Result.ReaderId := 'aps.fibps';
  Result.ReaderVersion := '2';
  Result.CurrentFileHash := CurrentHash;
  SetLength(Result.Values, 1);
  Result.Values[0].Name := 'COF';
  Result.Values[0].Value := 0.4;
  Result.Values[0].Units := 'u';
end;

function TAnalysisSettingsTests.ApplyShared(const Expected, New: string): Boolean;
var
  Model: TAnalysisSettingsModel;
  Current: string;
begin
  Model := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    Result := aasApplied = Model.ApplySelection(FNotebook.AccessPolicy,
      FNotebook.Principal, 'aps.fibps', FFileId, Expected, New, HashA, Current);
  finally
    Model.Free;
  end;
end;

function TAnalysisSettingsTests.DriftFlagsAfter(const Snapshot, RunHash: string;
  SharedBefore, SharedAfter: string): string;
var
  Runner: TRegionsRunner;
  Iface: IValueReaderRunner;
  Report: TValueDriftReport;
begin
  if SharedBefore <> '' then
    Assert.IsTrue(ApplyShared('', SharedBefore));
  AddReaderValue('aps.fibps', Snapshot);
  if SharedAfter = '-' then
    ExecuteSql('DELETE FROM DBSettings WHERE SettingKey LIKE ''analysis:%:file:%''')
  else if SharedAfter <> '' then
    Assert.IsTrue(ApplyShared(SharedBefore, SharedAfter));
  Runner := TRegionsRunner.Create;
  Runner.CurrentHash := RunHash;
  Iface := Runner;
  Report := CheckValueDrift(FNotebook.Manager, [FItemId], Iface);
  Assert.AreEqual(1, Report.Checked);
  if Length(Report.Rows) = 0 then
    Result := ''
  else
    Result := DriftFlagsText(Report.Rows[0].Flags);
end;

procedure TAnalysisSettingsTests.ExecuteSql(const Sql: string);
var
  Statement: IDBStatement;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand(Sql);
  Statement.Execute;
end;

procedure TAnalysisSettingsTests.RegionsSnapshotMatchingSharedSelectionIsUnchanged;
begin
  Assert.AreEqual('', DriftFlagsAfter(RegionsSnapshot(1, 'a1', True, HashA),
    HashA, RegionsSelection(1, 'a1'), ''));
end;

procedure TAnalysisSettingsTests.ReplacedSharedSelectionIsSelectionChangedOnly;
begin
  Assert.AreEqual('selection_changed', DriftFlagsAfter(
    RegionsSnapshot(1, 'a1', True, HashA), HashA, RegionsSelection(1, 'a1'),
    RegionsSelection(2, 'a2')));
end;

procedure TAnalysisSettingsTests.RegionsSnapshotWithOtherFileHashIsSourceChanged;
begin
  Assert.AreEqual('source_changed', DriftFlagsAfter(
    RegionsSnapshot(1, 'a1', True, HashA), 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
    RegionsSelection(1, 'a1'), ''));
end;

procedure TAnalysisSettingsTests.RegionsSnapshotWithoutProvenanceIsNeverSelectionChanged;
begin
  Assert.AreEqual('', DriftFlagsAfter(RegionsSnapshot(0, '', False, HashA),
    HashA, '', ''));
end;

procedure TAnalysisSettingsTests.DeletedSharedSelectionIsSelectionChangedWithProvenance;
begin
  Assert.AreEqual('selection_changed', DriftFlagsAfter(
    RegionsSnapshot(1, 'a1', True, HashA), HashA, RegionsSelection(1, 'a1'), '-'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalysisSettingsTests);

end.
