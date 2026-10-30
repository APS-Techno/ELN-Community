unit test_MitMcp;

interface

uses
  DUnitX.TestFramework, System.JSON, System.SysUtils,
  unit_LocalNotebook, unit_MCPTools, unit_Project, unit_Item, unit_FileType,
  unit_PluginHost, unit_ValueType, unit_MitFilePlugin;

type
  [TestFixture]
  TMitMcpTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FContext: TToolContext;
    FRegistry: TToolRegistry;
    FProject: TProject;
    FItem: TItem;
    FHost: TPluginHost;
    FPlugin: TELNMitFileViewerPlugin;
    FMitType: TFileType;
    FHardnessType: TValueType;
    FFile: unit_Item.TFile;
    FBytes: TBytes;
    function AddProject(const Title: string): TProject;
    function AddItem(Project: TProject; const Title: string): TItem;
    function AddFile(Item: TItem; FileType: TFileType;
      const Title: string): unit_Item.TFile;
    procedure ReplaceBytes(const Bytes: TBytes);
    function Extract(Selection: TJSONValue): TJSONObject;
    function RowOf(Response: TJSONObject; const Name: string): TJSONValue;
    function StoreValue(const KeyName: string; Value: Double;
      Snapshot: TJSONValue; const ReaderVersion: string = '3'): Integer;
    function SettingsRowCount: Integer;
    function CallDrift: TJSONObject;
    function FlagsOf(Row: TJSONValue): string;
    function DriftRow(Report: TJSONObject; ValueId: Integer): TJSONValue;
    procedure ApplyShared(const Json: string);
    function SharedJson(const Checked: TArray<Integer>; Revision: Integer): string;
    function Mean(const Indents: array of Integer): Double;
    function SelectionObject(const Checked: TArray<Integer>): TJSONObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ExtractionReturnsSnapshotsOnSelectionDependentKeysOnly;
    [Test] procedure PerCallSelectionGivesMeanOfThoseIndentsAndStoresNothing;
    [Test] procedure ValueStoredFromPerCallSelectionIsUnchangedAndNextExtractionUsesAllIndents;
    [Test] procedure SharedSelectionTagsTheSnapshotAndItsChangeIsSelectionChanged;
    [Test] procedure ReplacedBytesAreSourceChangedAndReplayedOverTheStoredIndents;
    [Test] procedure ChangedBytesWithSameValuesAreSourceChangedOnly;
    [Test] procedure ValueWithoutSnapshotIsIntervalUnusable;
    [Test] procedure ValueStoredByReaderVersionTwoDrifts;
    [Test] procedure UnusableOrStaleSelectionIsRefused;
    [Test] procedure ToolDescriptionNamesTheIndentSelection;
  end;

implementation

uses
  System.IOUtils, System.Classes, System.Variants, System.Generics.Collections,
  Vcl.Forms, upfVisualClasses, upfIntf,
  Aurelius.Drivers.Interfaces, Aurelius.Engine.ObjectManager,
  unit_ProjectModel, unit_ItemTypes, unit_User,
  unit_ToolsFiles, unit_ToolsWrite, unit_ToolsValueChecks,
  unit_ELNPluginCore, unit_AnalysisSettingsModel, unit_MitAnalysis,
  test_MitReader;

const
  EvH: array[0..8] of Double = (5.682, 5.992, 5.624, 4.949, 5.844, 6.130,
    6.192, 6.578, 6.268);

function TMitMcpTests.AddProject(const Title: string): TProject;
var
  Projects: TProjectsModel;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Result := Projects.AddProject(Title, '', FNotebook.Principal);
  finally
    Projects.Free;
  end;
end;

function TMitMcpTests.AddItem(Project: TProject; const Title: string): TItem;
var
  Id: Integer;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.ProjectID := Project.Id;
  Result.Type_ := TItemType.Other;
  Result.Level := TItemLevel.Proc;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
  Id := Result.Id;
  FNotebook.Manager.Evict(Result);
  Result.Free;
  Result := FNotebook.Manager.Find<TItem>(Id);
end;

function TMitMcpTests.AddFile(Item: TItem; FileType: TFileType;
  const Title: string): unit_Item.TFile;
begin
  Result := unit_Item.TFile.Create;
  Result.Title := Title;
  Result.Item := Item;
  Result.FileType := FileType;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  Item.Files.Add(Result);
  FNotebook.Manager.Flush;
end;

procedure TMitMcpTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-MitMcp-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Tool fixture', 'fixture-password');
  FProject := AddProject('Synthetic indentation');
  FItem := AddItem(FProject, 'specimen');
  FContext := Default(TToolContext);
  FContext.Manager := FNotebook.Manager;
  FContext.User := FNotebook.Principal;
  FContext.AccessPolicy := FNotebook.AccessPolicy;
  FContext.Storage := FNotebook.Storage;
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'plugins'));
  FHost := TPluginHost.Create(TPath.Combine(FRoot, 'plugins'));
  FPlugin := TELNMitFileViewerPlugin.Create(nil);
  (ApplicationServices as IupfCommandServices).RegisterPlugin(FPlugin);
  FContext.PluginHost := FHost;
  FRegistry := TToolRegistry.Create(FContext);
  RegisterFileTools(FRegistry);
  RegisterWriteTools(FRegistry);
  RegisterValueCheckTools(FRegistry);
  FMitType := TFileType.Create;
  FMitType.Ext := '.mit';
  FMitType.CreatedDate := Now;
  FNotebook.Manager.Save(FMitType);
  FHardnessType := unit_ValueType.TValueType.Create;
  FHardnessType.Symbol := 'H';
  FHardnessType.Title := 'Hardness';
  FHardnessType.Units := 'GPa';
  FHardnessType.CreatedDate := Now;
  FHardnessType.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Save(FHardnessType);
  FNotebook.Manager.Flush;
  FBytes := MitBytes(EvidenceSpecs);
  FFile := AddFile(FItem, FMitType, 'indents');
  FNotebook.Storage.WriteBytes(Format('Projects\%s\%s\%s',
    [FProject.FileFolder, FItem.FolderName, FFile.FullName]), FBytes);
end;

procedure TMitMcpTests.TearDown;
begin
  FRegistry.Free;
  FreeAndNil(FPlugin);
  FreeAndNil(FHost);
  FNotebook.Free;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TMitMcpTests.ReplaceBytes(const Bytes: TBytes);
begin
  FBytes := Bytes;
  FNotebook.Storage.WriteBytes(Format('Projects\%s\%s\%s',
    [FProject.FileFolder, FItem.FolderName, FFile.FullName]), Bytes);
end;

function TMitMcpTests.Extract(Selection: TJSONValue): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('file_id', TJSONNumber.Create(FFile.Id));
    if Selection <> nil then
      Params.AddPair('selection', Selection);
    Result := FRegistry.Execute('extract_file_key_values', Params);
  finally
    Params.Free;
  end;
end;

function TMitMcpTests.RowOf(Response: TJSONObject; const Name: string): TJSONValue;
var
  Row: TJSONValue;
begin
  Result := nil;
  for Row in Response.GetValue<TJSONArray>('key_values') do
    if Row.GetValue<string>('name') = Name then
      Exit(Row);
end;

function TMitMcpTests.StoreValue(const KeyName: string; Value: Double;
  Snapshot: TJSONValue; const ReaderVersion: string): Integer;
var
  Params, Response: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('item_id', TJSONNumber.Create(FItem.Id));
    Params.AddPair('value', TJSONNumber.Create(Value));
    Params.AddPair('value_type_id', TJSONNumber.Create(FHardnessType.Id));
    Params.AddPair('tolerance', TJSONNumber.Create(0.1));
    Params.AddPair('description', 'Hardness of the synthetic indents');
    Params.AddPair('source_file_id', TJSONNumber.Create(FFile.Id));
    Params.AddPair('reader_id', 'aps.mit');
    Params.AddPair('reader_version', ReaderVersion);
    Params.AddPair('key_name', KeyName);
    Params.AddPair('reader_units', 'GPa');
    Params.AddPair('conversion_factor', TJSONNumber.Create(1));
    if Snapshot <> nil then
      Params.AddPair('analysis_snapshot', Snapshot);
    Response := FRegistry.Execute('add_value', Params);
  finally
    Params.Free;
  end;
  try
    Assert.IsNull(Response.FindValue('error'), 'add_value must succeed');
    Result := Response.GetValue<Integer>('id');
  finally
    Response.Free;
  end;
end;

function TMitMcpTests.SettingsRowCount: Integer;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('SELECT COUNT(*) FROM DBSettings WHERE SettingKey LIKE ''analysis:%''');
  Rows := Statement.ExecuteQuery;
  Assert.IsTrue(Rows.Next);
  Result := StrToInt(VarToStr(Rows.GetFieldValue(0)));
end;

function TMitMcpTests.CallDrift: TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('item_id', TJSONNumber.Create(FItem.Id));
    Result := FRegistry.Execute('check_value_drift', Params);
  finally
    Params.Free;
  end;
  Assert.IsNull(Result.FindValue('error'));
end;

function TMitMcpTests.FlagsOf(Row: TJSONValue): string;
var
  Flag: TJSONValue;
begin
  Result := '';
  for Flag in Row.GetValue<TJSONArray>('flags') do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Flag.Value;
  end;
end;

function TMitMcpTests.DriftRow(Report: TJSONObject; ValueId: Integer): TJSONValue;
var
  Row: TJSONValue;
begin
  Result := nil;
  for Row in Report.GetValue<TJSONArray>('drifted') do
    if Row.GetValue<Integer>('value_id') = ValueId then
      Exit(Row);
end;

function TMitMcpTests.SharedJson(const Checked: TArray<Integer>; Revision: Integer): string;
var
  Selection: TMitSelection;
begin
  Selection := Default(TMitSelection);
  Selection.Mode := msmIndents;
  Selection.Checked := Checked;
  Selection.FileHash := MitHashOf(FBytes);
  Result := MitSelectionToJson(Selection, Revision, FNotebook.Principal.Id,
    'apply-' + IntToStr(Revision), '2026-01-02T03:04:05Z');
end;

procedure TMitMcpTests.ApplyShared(const Json: string);
var
  Settings: TAnalysisSettingsModel;
  Expected, Current: string;
begin
  Settings := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    if not Settings.LoadSelection('aps.mit', FFile.Id, Expected) then
      Expected := '';
    Assert.IsTrue(aasApplied = Settings.ApplySelection(FNotebook.AccessPolicy,
      FNotebook.Principal, 'aps.mit', FFile.Id, Expected, Json, MitHashOf(FBytes),
      Current));
  finally
    Settings.Free;
  end;
end;

function TMitMcpTests.Mean(const Indents: array of Integer): Double;
var
  N: Integer;
begin
  Result := 0;
  for N in Indents do
    Result := Result + EvH[N - 1];
  Result := Result / Length(Indents);
end;

function TMitMcpTests.SelectionObject(const Checked: TArray<Integer>): TJSONObject;
var
  Arr: TJSONArray;
  N: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('mode', 'indents');
  Arr := TJSONArray.Create;
  Result.AddPair('checked', Arr);
  for N in Checked do
    Arr.Add(N);
end;

procedure TMitMcpTests.ExtractionReturnsSnapshotsOnSelectionDependentKeysOnly;
var
  Response: TJSONObject;
  Name: string;
  Snapshot: TJSONValue;
begin
  Response := Extract(nil);
  try
    Assert.IsNull(Response.FindValue('error'));
    Assert.AreEqual('3', Response.GetValue<string>('reader_version'));
    for Name in ['Hardness', 'Modulus', 'Reduced Modulus', 'Contact Depth',
      'Max Force', 'Indent Count'] do
    begin
      Assert.IsNotNull(RowOf(Response, Name), Name);
      Snapshot := RowOf(Response, Name).FindValue('analysis_snapshot');
      Assert.IsNotNull(Snapshot, Name + ' must carry a snapshot');
      Assert.AreEqual('automatic', Snapshot.GetValue<string>('mode'));
      Assert.AreEqual(Name, Snapshot.GetValue<string>('key_name'));
      Assert.AreEqual(MitHashOf(FBytes), Snapshot.GetValue<string>('file_hash'));
    end;
    Assert.IsNotNull(RowOf(Response, 'Indents Excluded'));
    Assert.IsNull(RowOf(Response, 'Indents Excluded').FindValue('analysis_snapshot'));
    Assert.IsNull(RowOf(Response, 'Hardness STD'), 'Paired STD keys are not listed');
    Assert.IsTrue(RowOf(Response, 'Hardness').GetValue<Boolean>('is_key'));
    Assert.IsTrue(RowOf(Response, 'Modulus').GetValue<Boolean>('is_key'));
    Assert.IsFalse(RowOf(Response, 'Reduced Modulus').GetValue<Boolean>('is_key'));
    Assert.AreEqual(Mean([1, 2, 3, 4, 5, 6, 7, 8, 9]),
      RowOf(Response, 'Hardness').GetValue<Double>('value'), 1e-5);
  finally
    Response.Free;
  end;
end;

procedure TMitMcpTests.PerCallSelectionGivesMeanOfThoseIndentsAndStoresNothing;
var
  Response: TJSONObject;
  Snapshot: TJSONValue;
begin
  Response := Extract(SelectionObject([1, 3]));
  try
    Assert.IsNull(Response.FindValue('error'));
    Assert.AreEqual(Mean([1, 3]), RowOf(Response, 'Hardness').GetValue<Double>('value'), 1e-5);
    Assert.AreEqual(2, RowOf(Response, 'Indent Count').GetValue<Integer>('value'));
    Snapshot := RowOf(Response, 'Hardness').FindValue('analysis_snapshot');
    Assert.AreEqual('indents', Snapshot.GetValue<string>('mode'));
    Assert.AreEqual(2, Snapshot.GetValue<TJSONArray>('checked').Count);
    Assert.IsNull(Snapshot.FindValue('shared_revision'));
    Assert.IsTrue(Pos('"checked":[1,3]', Snapshot.ToJSON) > 0, Snapshot.ToJSON);
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, SettingsRowCount, 'The per-call selection is not stored');
end;

procedure TMitMcpTests.ValueStoredFromPerCallSelectionIsUnchangedAndNextExtractionUsesAllIndents;
var
  Response: TJSONObject;
  Report: TJSONObject;
  Id: Integer;
begin
  Response := Extract(SelectionObject([2, 4, 6]));
  try
    Id := StoreValue('Hardness', RowOf(Response, 'Hardness').GetValue<Double>('converted_value'),
      TJSONObject.ParseJSONValue(RowOf(Response, 'Hardness')
        .GetValue<TJSONObject>('analysis_snapshot').ToJSON));
  finally
    Response.Free;
  end;
  Assert.AreEqual(1, SettingsRowCount, 'Only the value snapshot row exists');
  Report := CallDrift;
  try
    Assert.AreEqual(1, Report.GetValue<Integer>('checked'));
    Assert.AreEqual(1, Report.GetValue<Integer>('unchanged'));
    Assert.IsNull(DriftRow(Report, Id));
  finally
    Report.Free;
  end;
  Response := Extract(nil);
  try
    Assert.AreEqual(9, RowOf(Response, 'Indent Count').GetValue<Integer>('value'));
    Assert.AreEqual(Mean([1, 2, 3, 4, 5, 6, 7, 8, 9]),
      RowOf(Response, 'Hardness').GetValue<Double>('value'), 1e-5);
    Assert.AreEqual('automatic', RowOf(Response, 'Hardness')
      .GetValue<TJSONObject>('analysis_snapshot').GetValue<string>('mode'));
  finally
    Response.Free;
  end;
end;

procedure TMitMcpTests.SharedSelectionTagsTheSnapshotAndItsChangeIsSelectionChanged;
var
  Response: TJSONObject;
  Report: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
  Snapshot: TJSONValue;
begin
  ApplyShared(SharedJson([1, 2, 3], 1));
  Response := Extract(nil);
  try
    Snapshot := RowOf(Response, 'Hardness').GetValue<TJSONObject>('analysis_snapshot');
    Assert.AreEqual('indents', Snapshot.GetValue<string>('mode'));
    Assert.AreEqual(1, Snapshot.GetValue<Integer>('shared_revision'));
    Assert.AreEqual('apply-1', Snapshot.GetValue<string>('shared_apply_id'));
    Assert.AreEqual(Mean([1, 2, 3]), RowOf(Response, 'Hardness').GetValue<Double>('value'), 1e-5);
    Id := StoreValue('Hardness', RowOf(Response, 'Hardness').GetValue<Double>('converted_value'),
      TJSONObject.ParseJSONValue(Snapshot.ToJSON));
  finally
    Response.Free;
  end;
  Report := CallDrift;
  try
    Assert.AreEqual(1, Report.GetValue<Integer>('unchanged'));
  finally
    Report.Free;
  end;
  ApplyShared(SharedJson([4, 5], 2));
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row, 'The changed shared selection must be reported');
    Assert.AreEqual('selection_changed', FlagsOf(Row));
    Assert.AreEqual(Row.GetValue<Double>('stored_value'),
      Row.GetValue<Double>('current_value'), 1e-9,
      'The value is replayed over the stored indents, not the new selection');
  finally
    Report.Free;
  end;
end;

procedure TMitMcpTests.ReplacedBytesAreSourceChangedAndReplayedOverTheStoredIndents;
var
  Response: TJSONObject;
  Report: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
  Specs: TArray<TMitSpec>;
begin
  Response := Extract(SelectionObject([1, 2, 3]));
  try
    Id := StoreValue('Hardness', RowOf(Response, 'Hardness').GetValue<Double>('converted_value'),
      TJSONObject.ParseJSONValue(RowOf(Response, 'Hardness')
        .GetValue<TJSONObject>('analysis_snapshot').ToJSON));
  finally
    Response.Free;
  end;
  Specs := EvidenceSpecs;
  Specs[1].H := 9E9;
  ReplaceBytes(MitBytes(Specs));
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row, 'The replaced file must drift');
    Assert.AreEqual('value_changed,source_changed', FlagsOf(Row));
    Assert.AreEqual((EvH[0] + 9 + EvH[2]) / 3, Row.GetValue<Double>('current_value'), 1e-5,
      'The current value is the mean over the stored indents of the new file');
  finally
    Report.Free;
  end;
end;

procedure TMitMcpTests.ChangedBytesWithSameValuesAreSourceChangedOnly;
var
  Response, Report: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
begin
  Response := Extract(nil);
  try
    Id := StoreValue('Hardness', RowOf(Response, 'Hardness').GetValue<Double>('converted_value'),
      TJSONObject.ParseJSONValue(RowOf(Response, 'Hardness')
        .GetValue<TJSONObject>('analysis_snapshot').ToJSON));
  finally
    Response.Free;
  end;
  ReplaceBytes(MitBytes(EvidenceSpecs, 18));
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row, 'A file with other bytes must be reported');
    Assert.AreEqual('source_changed', FlagsOf(Row));
  finally
    Report.Free;
  end;
end;

procedure TMitMcpTests.ValueWithoutSnapshotIsIntervalUnusable;
var
  Report: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
begin
  Id := StoreValue('Hardness', Mean([1, 2, 3, 4, 5, 6, 7, 8, 9]), nil);
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row);
    Assert.AreEqual('interval_unusable', FlagsOf(Row));
  finally
    Report.Free;
  end;
end;

procedure TMitMcpTests.ValueStoredByReaderVersionTwoDrifts;
var
  Report: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
begin
  Id := StoreValue('Hardness', 6.2287, nil, '2');
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row);
    Assert.IsTrue(Pos('reader_version_changed', FlagsOf(Row)) > 0, FlagsOf(Row));
  finally
    Report.Free;
  end;
end;

procedure TMitMcpTests.UnusableOrStaleSelectionIsRefused;
var
  Response: TJSONObject;
  Selection: TJSONObject;
begin
  Response := Extract(SelectionObject([1, 99]));
  try
    Assert.IsNotNull(Response.FindValue('error'));
    Assert.IsTrue(Pos('interval_unusable', Response.GetValue<string>('error')) > 0,
      Response.GetValue<string>('error'));
    Assert.IsNull(Response.FindValue('key_values'));
  finally
    Response.Free;
  end;
  Selection := SelectionObject([1, 2]);
  Selection.AddPair('file_hash', 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF');
  Response := Extract(Selection);
  try
    Assert.IsTrue(Pos('stale_selection', Response.GetValue<string>('error')) > 0,
      Response.GetValue<string>('error'));
  finally
    Response.Free;
  end;
  Selection := TJSONObject.Create;
  Selection.AddPair('mode', 'regions');
  Response := Extract(Selection);
  try
    Assert.IsTrue(Pos('interval_unusable', Response.GetValue<string>('error')) > 0,
      Response.GetValue<string>('error'));
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, SettingsRowCount);
end;

procedure TMitMcpTests.ToolDescriptionNamesTheIndentSelection;
var
  Description: string;
  Found: Boolean;
  Tool: TJSONValue;
  List: TJSONArray;
begin
  List := FRegistry.GetToolsList;
  try
    Found := False;
    for Tool in List do
      if Tool.GetValue<string>('name') = 'extract_file_key_values' then
      begin
        Description := Tool.GetValue<string>('description');
        Found := True;
      end;
    Assert.IsTrue(Found);
    Assert.IsTrue(Pos('.mit', Description) > 0, 'The .mit selection form must be described');
    Assert.IsTrue(Pos('"mode":"indents"', Description) > 0, Description);
    Assert.IsTrue(Pos('checked', Description) > 0, Description);
  finally
    List.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMitMcpTests);

end.
