unit test_MCPFileDiscovery;

interface

uses
  DUnitX.TestFramework, System.JSON,
  unit_LocalNotebook, unit_MCPTools, unit_Project, unit_Item, unit_FileType,
  unit_PluginHost, unit_ZRWViewerPlugin, unit_ValueType, System.SysUtils;

type
  [TestFixture]
  TMCPFileDiscoveryTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FContext: TToolContext;
    FRegistry: TToolRegistry;
    FProject: TProject;
    FItem: TItem;
    FJSONType, FTextType: TFileType;
    FHost: TPluginHost;
    FPlugin: TELNZRWViewerPlugin;
    FZrwType: TFileType;
    FCofType: TValueType;
    FZrwFile: unit_Item.TFile;
    FZrwBytes: TBytes;
    function AddProject(const Title: string): TProject;
    function AddItem(Project: TProject; const Title: string): TItem;
    function AddFile(Item: TItem; FileType: TFileType;
      const Title: string): unit_Item.TFile;
    function CallSearch(const Query: string; ProjectId: Integer): TJSONObject;
    procedure PrepareZrw;
    function ZrwHash: string;
    procedure ReplaceZrwBytes(const Bytes: TBytes);
    function ExtractRaw: TJSONObject;
    function ExtractCofRow: TJSONObject;
    function ValueParams(Snapshot: TJSONValue; const SourceKind: string): TJSONObject;
    function StoredValueCount: Integer;
    function StoredSnapshotCount: Integer;
    function SnapshotOf(ValueId: Integer): TJSONObject;
    function StoreCofValue: Integer;
    procedure ApplyManualSelection(Start, Stop: Double);
    procedure DeleteSharedSelection;
    function CallDrift: TJSONObject;
    function FlagsOf(Row: TJSONValue): string;
    function DriftRow(Report: TJSONObject; ValueId: Integer): TJSONValue;
    function SettingsRowCount: Integer;
    function Refusal(const Tool: string; Params: TJSONObject): string;
    function ExtractWithSelection(FileId: Int64; Selection: TJSONValue): TJSONObject;
    function ManualSelectionObject(Start, Stop: Double): TJSONObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CompoundFilenameKeepsDuplicateAttachmentsAndProjectScope;
    [Test] procedure MultiwordSearchKeepsFileIdentityAndOwnerContext;
    [Test] procedure CompleteStoredFilenameCanBeSearched;
    [Test] procedure ExactCaseUnicodeFilenamesRemainSearchable;
    [Test] procedure ExtractionIdentifiesOnlyTheCompleteCompoundSuffix;
    [Test] procedure ExtractionReturnsAnalysisSnapshotForCof;
    [Test] procedure AddValueAndAddValuesPersistTheAnalysisSnapshot;
    [Test] procedure RefusesSnapshotOfAnotherFileChangedContentOrNonReaderSource;
    [Test] procedure MalformedFileReportsLineNumberedLoadError;
    [Test] procedure StaleSharedSelectionReturnsStatusAndNoCof;
    [Test] procedure DriftOfUnchangedCofReportsNoFlags;
    [Test] procedure DriftReportsSelectionChangedWhenSharedSelectionChangedAfterExtraction;
    [Test] procedure DriftTreatsMissingSharedSelectionAsChangeForManualSnapshotOnly;
    [Test] procedure DriftOfReplacedCurveReportsSourceAndValueChangedOverStoredInterval;
    [Test] procedure DriftOfReplacedCurveWithTooFewSamplesReportsIntervalUnusable;
    [Test] procedure DriftOfCofWithoutSnapshotReportsIntervalUnusableOnly;
    [Test] procedure DriftComparesEachCofValueWithItsOwnSnapshot;
    [Test] procedure DriftReportsLineNumberedLoadErrorAndWritesNothing;
    [Test] procedure PerCallSelectionGivesCofOverIntervalAndStoresNothing;
    [Test] procedure SelectionOnReaderWithoutAnalysisIsRefused;
    [Test] procedure MalformedSelectionIsRefusedWithStatus;
    [Test] procedure NonObjectSelectionIsRefused;
  end;

implementation

uses
  System.IOUtils, System.Classes,
  Vcl.Forms, upfVisualClasses, upfIntf,
  Aurelius.Drivers.Interfaces, Aurelius.Engine.ObjectManager,
  unit_ProjectModel, unit_ItemTypes, unit_User,
  unit_ToolsNavigation, unit_ToolsFiles, unit_ToolsWrite, unit_ToolsValueChecks,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_AnalysisSettingsModel, unit_ZRWPlateau, test_ZRWExtraction,
  System.Hash, System.Generics.Collections, System.Variants;

type
  TJSONFixturePlugin = class(TupfVisualPlugin, IViewerPlugin,
    IDetailedInfoProvider, IKeyValueProvider)
  private
    FData: string;
  public
    function GetFrame: TFrame;
    function GetCaption: string;
    function GetParams: TPluginParams;
    function LoadFromFile(const FileName: string): Boolean;
    function LoadFromStream(Stream: TMemoryStream): Boolean;
    procedure DisplayText(const Caption, Text: string);
    function GetDetailedInfo: string;
    function GetKeyValues: TArray<TPluginKeyValue>;
  end;

function TJSONFixturePlugin.GetFrame: TFrame;
begin
  Result := nil;
end;

function TJSONFixturePlugin.GetCaption: string;
begin
  Result := 'Synthetic JSON decoder';
end;

function TJSONFixturePlugin.GetParams: TPluginParams;
begin
  Result := Default(TPluginParams);
  Result.PType := ptFile;
  Result.Ext := '.json;.txt';
end;

function TJSONFixturePlugin.LoadFromFile(const FileName: string): Boolean;
var
  Parsed: TJSONValue;
begin
  FData := System.IOUtils.TFile.ReadAllText(FileName, TEncoding.UTF8);
  Parsed := TJSONObject.ParseJSONValue(FData);
  try
    Result := Parsed is TJSONObject;
  finally
    Parsed.Free;
  end;
end;

function TJSONFixturePlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
begin
  Result := False;
end;

procedure TJSONFixturePlugin.DisplayText(const Caption, Text: string);
begin
end;

function TJSONFixturePlugin.GetDetailedInfo: string;
begin
  Result := FData;
end;

function TJSONFixturePlugin.GetKeyValues: TArray<TPluginKeyValue>;
var
  Parsed: TJSONObject;
begin
  Parsed := TJSONObject.ParseJSONValue(FData) as TJSONObject;
  try
    SetLength(Result, 1);
    Result[0].Name := 'Warmup';
    Result[0].Value := Parsed.GetValue<Double>('warmup_seconds');
    Result[0].Units := 's';
    Result[0].RecType := prCondition;
  finally
    Parsed.Free;
  end;
end;

function TMCPFileDiscoveryTests.AddProject(const Title: string): TProject;
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

function TMCPFileDiscoveryTests.AddItem(Project: TProject;
  const Title: string): TItem;
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

function TMCPFileDiscoveryTests.AddFile(Item: TItem; FileType: TFileType;
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

procedure TMCPFileDiscoveryTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-MCPFileDiscovery-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Tool fixture', 'fixture-password');
  FProject := AddProject('Synthetic deposition files');
  FItem := AddItem(FProject, 'sample alpha');
  FJSONType := TFileType.Create;
  FJSONType.Ext := '.json';
  FJSONType.CreatedDate := Now;
  FNotebook.Manager.Save(FJSONType);
  FTextType := TFileType.Create;
  FTextType.Ext := '.txt';
  FTextType.CreatedDate := Now;
  FNotebook.Manager.Save(FTextType);
  FNotebook.Manager.Flush;
  FContext := Default(TToolContext);
  FContext.Manager := FNotebook.Manager;
  FContext.User := FNotebook.Principal;
  FContext.AccessPolicy := FNotebook.AccessPolicy;
  FContext.Storage := FNotebook.Storage;
  FRegistry := TToolRegistry.Create(FContext);
  RegisterNavigationTools(FRegistry);
  RegisterFileTools(FRegistry);
end;

procedure TMCPFileDiscoveryTests.TearDown;
begin
  FRegistry.Free;
  FreeAndNil(FPlugin);
  FreeAndNil(FHost);
  FNotebook.Free;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TMCPFileDiscoveryTests.CallSearch(const Query: string;
  ProjectId: Integer): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('query', Query);
    Params.AddPair('project_id', TJSONNumber.Create(ProjectId));
    Result := FRegistry.Execute('search', Params);
  finally
    Params.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.CompoundFilenameKeepsDuplicateAttachmentsAndProjectScope;
var
  First, Second: unit_Item.TFile;
  Other: TProject;
  Response: TJSONObject;
  Rows: TJSONArray;
  Row: TJSONValue;
  Id: Int64;
  FirstSeen, SecondSeen: Boolean;
begin
  First := AddFile(FItem, FJSONType, 'run_sample.depo');
  Second := AddFile(FItem, FJSONType, 'run_sample.depo');
  AddFile(FItem, FTextType, 'run_sample.depo');
  Other := AddProject('Other synthetic project');
  AddFile(AddItem(Other, 'sample alpha'), FJSONType, 'run_sample.depo');
  Response := CallSearch('DEPO.JSON', FProject.Id);
  try
    Rows := Response.GetValue<TJSONArray>('results');
    Assert.AreEqual(2, Rows.Count);
    FirstSeen := False;
    SecondSeen := False;
    for Row in Rows do
    begin
      Id := Row.GetValue<Int64>('file_id');
      FirstSeen := FirstSeen or (Id = First.Id);
      SecondSeen := SecondSeen or (Id = Second.Id);
      Assert.AreEqual(FProject.Id, Row.GetValue<Integer>('project_id'));
      Assert.AreEqual('.depo.json', Row.GetValue<string>('extension'));
      Assert.AreEqual(Format('[%.4d]run_sample.depo.json', [Id]),
        Row.GetValue<string>('full_name'));
    end;
    Assert.IsTrue(FirstSeen and SecondSeen);
  finally
    Response.Free;
  end;
  FRegistry.SetScope([FProject.Id]);
  Response := CallSearch('depo.json', Other.Id);
  try
    Assert.AreEqual(0, Response.GetValue<TJSONArray>('results').Count);
  finally
    Response.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.MultiwordSearchKeepsFileIdentityAndOwnerContext;
var
  FileRow: unit_Item.TFile;
  Response: TJSONObject;
  Rows: TJSONArray;
  Row: TJSONValue;
  FileSeen: Boolean;
begin
  FileRow := AddFile(FItem, FJSONType, 'run_one.depo');
  AddFile(FItem, FTextType, 'run_two');
  Response := CallSearch('alpha depo.json', FProject.Id);
  try
    Rows := Response.GetValue<TJSONArray>('results');
    FileSeen := False;
    for Row in Rows do
      if Row.GetValue<string>('kind') = 'File' then
      begin
        Assert.AreEqual(FileRow.Id, Row.GetValue<Int64>('file_id'));
        Assert.AreEqual(Format('[%.4d]run_one.depo.json', [FileRow.Id]),
          Row.GetValue<string>('full_name'));
        FileSeen := True;
      end;
    Assert.IsTrue(FileSeen, 'The owner-title intersection must retain its matching file');
  finally
    Response.Free;
  end;
  Response := CallSearch('run_two depo.json', FProject.Id);
  try
    Rows := Response.GetValue<TJSONArray>('results');
    Assert.AreEqual(1, Rows.Count);
    Assert.AreEqual('Item', Rows.Items[0].GetValue<string>('kind'));
    Assert.IsNull(Rows.Items[0].FindValue('file_id'));
  finally
    Response.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.CompleteStoredFilenameCanBeSearched;
const
  FileId: Int64 = 9007199254740993;
var
  FileRow: unit_Item.TFile;
  Response: TJSONObject;
  Rows: TJSONArray;
  Statement: IDBStatement;
  Observer: TObjectManager;
  Context: TToolContext;
begin
  FileRow := AddFile(FItem, FJSONType, 'run_one.depo');
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('UPDATE Files SET Id = ' + IntToStr(FileId) +
    ' WHERE Id = ' + IntToStr(FileRow.Id));
  Statement.Execute;
  Statement := nil;
  Observer := TObjectManager.Create(FNotebook.Connection);
  try
    Context := FContext;
    Context.Manager := Observer;
    Context.User := Observer.Find<TUser>(FNotebook.Principal.Id);
    FreeAndNil(FRegistry);
    FRegistry := TToolRegistry.Create(Context);
    RegisterNavigationTools(FRegistry);
    Response := CallSearch('[9007199254740993]run_one.depo.json', FProject.Id);
    try
      Rows := Response.GetValue<TJSONArray>('results');
      Assert.AreEqual(1, Rows.Count);
      Assert.AreEqual(FileId, Rows.Items[0].GetValue<Int64>('file_id'));
      Assert.AreEqual('[9007199254740993]run_one.depo.json',
        Rows.Items[0].GetValue<string>('full_name'));
    finally
      Response.Free;
    end;
  finally
    FreeAndNil(FRegistry);
    Observer.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.ExtractionIdentifiesOnlyTheCompleteCompoundSuffix;
const
  Titles: array[0..3] of string =
    ('snapshot.depo', 'snapshot.DEPO', 'snapshot.depo.json', 'plain');
  Extensions: array[0..3] of string = ('.depo.json', '.depo.json', '.txt', '.json');
  Tools: array[0..1] of string = ('extract_file_data', 'extract_file_key_values');
var
  Host: TPluginHost;
  Plugin: TJSONFixturePlugin;
  FileRow: unit_Item.TFile;
  Params, Response: TJSONObject;
  Tool: string;
  I: Integer;
  StoragePath: string;
begin
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'plugins'));
  Host := TPluginHost.Create(TPath.Combine(FRoot, 'plugins'));
  Plugin := nil;
  try
    Plugin := TJSONFixturePlugin.CreateNew(nil);
    (ApplicationServices as IupfCommandServices).RegisterPlugin(Plugin);
    FContext.PluginHost := Host;
    FreeAndNil(FRegistry);
    FRegistry := TToolRegistry.Create(FContext);
    RegisterFileTools(FRegistry);
    for I := Low(Titles) to High(Titles) do
    begin
      if I = 2 then
        FileRow := AddFile(FItem, FTextType, Titles[I])
      else
        FileRow := AddFile(FItem, FJSONType, Titles[I]);
      StoragePath := Format('Projects\%s\%s\%s',
        [FProject.FileFolder, FItem.FolderName, FileRow.FullName]);
      FNotebook.Storage.WriteBytes(StoragePath,
        TEncoding.UTF8.GetBytes('{"warmup_seconds":1200,"kind":"synthetic"}'));
      Params := TJSONObject.Create;
      try
        Params.AddPair('file_id', TJSONNumber.Create(FileRow.Id));
        for Tool in Tools do
        begin
          Response := FRegistry.Execute(Tool, Params);
          try
            Assert.IsNull(Response.FindValue('error'));
            Assert.AreEqual(Extensions[I], Response.GetValue<string>('extension'));
            Assert.AreEqual(Titles[I] + FileRow.FileType.Ext,
              Response.GetValue<string>('file_name'));
          finally
            Response.Free;
          end;
        end;
      finally
        Params.Free;
      end;
    end;
  finally
    FreeAndNil(FRegistry);
    Host.Free;
    Plugin.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.ExactCaseUnicodeFilenamesRemainSearchable;
const
  Title = #$0422#$0415#$0421#$0422;
  Queries: array[0..1] of string = (Title + '.depo.json', Title + '.DEPO.JSON');
var
  FileRow: unit_Item.TFile;
  Response: TJSONObject;
  Rows: TJSONArray;
  Query: string;
begin
  FileRow := AddFile(FItem, FJSONType, Title + '.depo');
  for Query in Queries do
  begin
    Response := CallSearch(Query, FProject.Id);
    try
      Rows := Response.GetValue<TJSONArray>('results');
      Assert.AreEqual(1, Rows.Count);
      Assert.AreEqual(FileRow.Id, Rows.Items[0].GetValue<Int64>('file_id'));
    finally
      Response.Free;
    end;
  end;
end;

function TMCPFileDiscoveryTests.ZrwHash: string;
var
  Hash: THashMD5;
begin
  Hash := THashMD5.Create;
  Hash.Update(FZrwBytes);
  Result := UpperCase(Hash.HashAsString);
end;

procedure TMCPFileDiscoveryTests.PrepareZrw;
begin
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'plugins'));
  FHost := TPluginHost.Create(TPath.Combine(FRoot, 'plugins'));
  FPlugin := TELNZRWViewerPlugin.Create(nil);
  (ApplicationServices as IupfCommandServices).RegisterPlugin(FPlugin);
  FContext.PluginHost := FHost;
  FreeAndNil(FRegistry);
  FRegistry := TToolRegistry.Create(FContext);
  RegisterFileTools(FRegistry);
  RegisterWriteTools(FRegistry);
  FZrwType := TFileType.Create;
  FZrwType.Ext := '.zrw';
  FZrwType.CreatedDate := Now;
  FNotebook.Manager.Save(FZrwType);
  FCofType := unit_ValueType.TValueType.Create;
  FCofType.Symbol := 'COF';
  FCofType.Title := 'COF';
  FCofType.Units := '';
  FCofType.CreatedDate := Now;
  FCofType.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Save(FCofType);
  FNotebook.Manager.Flush;
  FZrwBytes := SyntheticZrwBytes;
  FZrwFile := AddFile(FItem, FZrwType, 'friction');
  FNotebook.Storage.WriteBytes(Format('Projects\%s\%s\%s',
    [FProject.FileFolder, FItem.FolderName, FZrwFile.FullName]), FZrwBytes);
end;

function TMCPFileDiscoveryTests.ExtractCofRow: TJSONObject;
var
  Params, Response: TJSONObject;
  Row: TJSONValue;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('file_id', TJSONNumber.Create(FZrwFile.Id));
    Response := FRegistry.Execute('extract_file_key_values', Params);
  finally
    Params.Free;
  end;
  try
    Assert.IsNull(Response.FindValue('error'));
    Assert.IsNull(Response.FindValue('analysis_status'));
    Result := nil;
    for Row in Response.GetValue<TJSONArray>('key_values') do
      if Row.GetValue<string>('name') = 'COF' then
        Result := TJSONObject.ParseJSONValue(Row.ToJSON) as TJSONObject
      else
        Assert.IsNull(Row.FindValue('analysis_snapshot'),
          'Only COF carries the analysis snapshot');
    Assert.IsNotNull(Result, 'COF must be extracted');
  finally
    Response.Free;
  end;
end;

function TMCPFileDiscoveryTests.ValueParams(Snapshot: TJSONValue;
  const SourceKind: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('item_id', TJSONNumber.Create(FItem.Id));
  Result.AddPair('value', TJSONNumber.Create(0.499));
  Result.AddPair('value_type_id', TJSONNumber.Create(FCofType.Id));
  Result.AddPair('tolerance', TJSONNumber.Create(0.03));
  Result.AddPair('description', 'Mean friction coefficient');
  Result.AddPair('source_file_id', TJSONNumber.Create(FZrwFile.Id));
  if SourceKind <> '' then
    Result.AddPair('source_kind', SourceKind);
  if SourceKind <> 'Manual' then
  begin
    Result.AddPair('reader_id', 'aps.zrw');
    Result.AddPair('reader_version', '2');
    Result.AddPair('key_name', 'COF');
    Result.AddPair('reader_units', '');
    Result.AddPair('conversion_factor', TJSONNumber.Create(1));
  end;
  if Snapshot <> nil then
    Result.AddPair('analysis_snapshot', Snapshot);
end;

function TMCPFileDiscoveryTests.StoredValueCount: Integer;
var
  Observer: TObjectManager;
  Rows: TList<unit_Item.TValue>;
begin
  Observer := TObjectManager.Create(FNotebook.Connection);
  try
    Rows := Observer.Find<unit_Item.TValue>.List;
    try
      Result := Rows.Count;
    finally
      Rows.Free;
    end;
  finally
    Observer.Free;
  end;
end;

function TMCPFileDiscoveryTests.StoredSnapshotCount: Integer;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('SELECT COUNT(*) FROM DBSettings ' +
    'WHERE SettingKey LIKE ''analysis:%:value:%''');
  Rows := Statement.ExecuteQuery;
  Assert.IsTrue(Rows.Next);
  Result := StrToInt(VarToStr(Rows.GetFieldValue(0)));
end;

function TMCPFileDiscoveryTests.SnapshotOf(ValueId: Integer): TJSONObject;
var
  Observer: TObjectManager;
  Settings: TAnalysisSettingsModel;
  Json: string;
begin
  Observer := TObjectManager.Create(FNotebook.Connection);
  try
    Settings := TAnalysisSettingsModel.Create(Observer);
    try
      Assert.IsTrue(Settings.LoadSnapshot(Observer.Find<unit_Item.TValue>(ValueId), Json),
        'The stored value must carry its snapshot');
    finally
      Settings.Free;
    end;
  finally
    Observer.Free;
  end;
  Result := TJSONObject.ParseJSONValue(Json) as TJSONObject;
end;

function TMCPFileDiscoveryTests.Refusal(const Tool: string;
  Params: TJSONObject): string;
var
  Response: TJSONObject;
begin
  Result := '';
  try
    try
      Response := FRegistry.Execute(Tool, Params);
      Response.Free;
    except
      on E: Exception do
        Result := E.Message;
    end;
  finally
    Params.Free;
  end;
  Assert.IsTrue(Result <> '', Tool + ' must be refused');
  Assert.AreEqual(0, StoredValueCount, 'A refused call stores no value');
  Assert.AreEqual(0, StoredSnapshotCount, 'A refused call stores no snapshot');
end;

procedure TMCPFileDiscoveryTests.ExtractionReturnsAnalysisSnapshotForCof;
var
  Row, Snapshot: TJSONObject;
begin
  PrepareZrw;
  Row := ExtractCofRow;
  try
    Snapshot := Row.GetValue<TJSONObject>('analysis_snapshot');
    Assert.AreEqual('aps.zrw', Snapshot.GetValue<string>('reader_id'));
    Assert.AreEqual('COF', Snapshot.GetValue<string>('key_name'));
    Assert.AreEqual('automatic', Snapshot.GetValue<string>('mode'));
    Assert.AreEqual<Int64>(FZrwFile.Id, Snapshot.GetValue<Int64>('file_id'));
    Assert.AreEqual(ZrwHash,
      Snapshot.GetValue<string>('file_hash'));
    Assert.IsTrue(Row.GetValue<Double>('tolerance') > 0,
      'COF STD supplies the tolerance');
  finally
    Row.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.AddValueAndAddValuesPersistTheAnalysisSnapshot;
var
  Row, Params, Response: TJSONObject;
  Entries: TJSONArray;
  Stored: TJSONObject;
  Id: Integer;
begin
  PrepareZrw;
  Row := ExtractCofRow;
  try
    Params := ValueParams(TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON), '');
    try
      Response := FRegistry.Execute('add_value', Params);
    finally
      Params.Free;
    end;
    try
      Id := Response.GetValue<Integer>('id');
    finally
      Response.Free;
    end;
    Stored := SnapshotOf(Id);
    try
      Assert.AreEqual(Id, Stored.GetValue<Integer>('value_id'));
      Assert.AreEqual('automatic', Stored.GetValue<string>('mode'));
      Assert.AreEqual(ZrwHash,
        Stored.GetValue<string>('file_hash'));
    finally
      Stored.Free;
    end;

    Entries := TJSONArray.Create;
    Entries.AddElement(ValueParams(TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON), ''));
    Entries.AddElement(ValueParams(TJSONString.Create(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON), 'Reader'));
    Params := TJSONObject.Create;
    Params.AddPair('values', Entries);
    try
      Response := FRegistry.Execute('add_values', Params);
    finally
      Params.Free;
    end;
    try
      Assert.AreEqual(2, Response.GetValue<Integer>('count'));
      for Id := 0 to 1 do
      begin
        Stored := SnapshotOf(Response.GetValue<TJSONArray>('values').Items[Id]
          .GetValue<Integer>('id'));
        try
          Assert.AreEqual(Response.GetValue<TJSONArray>('values').Items[Id]
            .GetValue<Integer>('id'), Stored.GetValue<Integer>('value_id'));
          Assert.AreEqual('COF', Stored.GetValue<string>('key_name'));
        finally
          Stored.Free;
        end;
      end;
    finally
      Response.Free;
    end;
    Assert.AreEqual(3, StoredSnapshotCount);
  finally
    Row.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.RefusesSnapshotOfAnotherFileChangedContentOrNonReaderSource;
var
  Row, Snapshot: TJSONObject;
  Entries: TJSONArray;
  Params: TJSONObject;
  Message: string;
begin
  PrepareZrw;
  Row := ExtractCofRow;
  try
    Snapshot := TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON) as TJSONObject;
    Snapshot.RemovePair('file_id').Free;
    Snapshot.AddPair('file_id', TJSONNumber.Create(FZrwFile.Id + 1000));
    Message := Refusal('add_value', ValueParams(Snapshot, ''));
    Assert.IsTrue(Pos('file_id', Message) > 0, Message);

    Snapshot := TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON) as TJSONObject;
    Snapshot.RemovePair('file_hash').Free;
    Snapshot.AddPair('file_hash', 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF');
    Message := Refusal('add_value', ValueParams(Snapshot, ''));
    Assert.IsTrue(Pos('file_hash', Message) > 0, Message);

    Message := Refusal('add_value', ValueParams(TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON), 'Manual'));
    Assert.IsTrue(Pos('Reader source', Message) > 0, Message);

    Snapshot := TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON) as TJSONObject;
    Snapshot.RemovePair('file_hash').Free;
    Snapshot.AddPair('file_hash', 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF');
    Entries := TJSONArray.Create;
    Entries.AddElement(ValueParams(TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON), ''));
    Entries.AddElement(ValueParams(Snapshot, ''));
    Params := TJSONObject.Create;
    Params.AddPair('values', Entries);
    Message := Refusal('add_values', Params);
    Assert.IsTrue(Pos('values[1]', Message) > 0, Message);
    Assert.IsTrue(Pos('file_hash', Message) > 0, Message);
  finally
    Row.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.ReplaceZrwBytes(const Bytes: TBytes);
begin
  FNotebook.Storage.WriteBytes(Format('Projects\%s\%s\%s',
    [FProject.FileFolder, FItem.FolderName, FZrwFile.FullName]), Bytes);
end;

function TMCPFileDiscoveryTests.ExtractRaw: TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('file_id', TJSONNumber.Create(FZrwFile.Id));
    Result := FRegistry.Execute('extract_file_key_values', Params);
  finally
    Params.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.MalformedFileReportsLineNumberedLoadError;
var
  Response: TJSONObject;
begin
  PrepareZrw;
  ReplaceZrwBytes(MalformedZrwBytes);
  Response := ExtractRaw;
  try
    Assert.IsNotNull(Response.FindValue('error'), 'A malformed file must be an error');
    Assert.IsTrue(Pos('line 5', Response.GetValue<string>('error')) > 0,
      Response.GetValue<string>('error'));
  finally
    Response.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.StaleSharedSelectionReturnsStatusAndNoCof;
var
  Settings: TAnalysisSettingsModel;
  Selection: TZRWSelection;
  Current: string;
  Response: TJSONObject;
  Row: TJSONValue;
begin
  PrepareZrw;
  Selection := Default(TZRWSelection);
  Selection.Mode := zsmManual;
  Selection.Interval.StartCycle := 20;
  Selection.Interval.EndCycle := 60;
  Selection.ReaderVersion := '2';
  Selection.AlgorithmVersion := '1';
  Selection.FileHash := ZrwHash;
  Selection.ApplyId := 'apply-1';
  Selection.AppliedAt := '2026-01-02T03:04:05Z';
  Selection.AppliedBy := FNotebook.Principal.Id;
  Selection.Revision := 1;
  Settings := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(aasApplied = Settings.ApplySelection(FNotebook.AccessPolicy,
      FNotebook.Principal, 'aps.zrw', FZrwFile.Id, '', SelectionToJson(Selection),
      Selection.FileHash, Current));
  finally
    Settings.Free;
  end;
  ReplaceZrwBytes(SyntheticZrwBytes(False));
  Response := ExtractRaw;
  try
    Assert.IsNull(Response.FindValue('error'));
    Assert.AreEqual(ANALYSIS_STATUS_STALE_SELECTION,
      Response.GetValue<string>('analysis_status'));
    for Row in Response.GetValue<TJSONArray>('key_values') do
    begin
      Assert.AreNotEqual('COF', Row.GetValue<string>('name'));
      Assert.IsNull(Row.FindValue('analysis_snapshot'));
    end;
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, StoredValueCount);
  Assert.AreEqual(0, StoredSnapshotCount);
end;

function TMCPFileDiscoveryTests.StoreCofValue: Integer;
var
  Row, Params, Response: TJSONObject;
begin
  Row := ExtractCofRow;
  try
    Params := ValueParams(TJSONObject.ParseJSONValue(
      Row.GetValue<TJSONObject>('analysis_snapshot').ToJSON), '');
    Params.RemovePair('value').Free;
    Params.AddPair('value', TJSONNumber.Create(Row.GetValue<Double>('converted_value')));
    try
      Response := FRegistry.Execute('add_value', Params);
    finally
      Params.Free;
    end;
    try
      Result := Response.GetValue<Integer>('id');
    finally
      Response.Free;
    end;
  finally
    Row.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.ApplyManualSelection(Start, Stop: Double);
var
  Settings: TAnalysisSettingsModel;
  Selection: TZRWSelection;
  Expected, Current: string;
begin
  Selection := Default(TZRWSelection);
  Selection.Mode := zsmManual;
  Selection.Interval.StartCycle := Start;
  Selection.Interval.EndCycle := Stop;
  Selection.ReaderVersion := '2';
  Selection.AlgorithmVersion := '1';
  Selection.FileHash := ZrwHash;
  Selection.ApplyId := 'apply-1';
  Selection.AppliedAt := '2026-01-02T03:04:05Z';
  Selection.AppliedBy := FNotebook.Principal.Id;
  Selection.Revision := 1;
  Settings := TAnalysisSettingsModel.Create(FNotebook.Manager);
  try
    if not Settings.LoadSelection('aps.zrw', FZrwFile.Id, Expected) then
      Expected := '';
    Assert.IsTrue(aasApplied = Settings.ApplySelection(FNotebook.AccessPolicy,
      FNotebook.Principal, 'aps.zrw', FZrwFile.Id, Expected,
      SelectionToJson(Selection), Selection.FileHash, Current));
  finally
    Settings.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.DeleteSharedSelection;
var
  Statement: IDBStatement;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('DELETE FROM DBSettings WHERE SettingKey LIKE ''analysis:%:file:%''');
  Statement.Execute;
end;

function TMCPFileDiscoveryTests.SettingsRowCount: Integer;
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

function TMCPFileDiscoveryTests.CallDrift: TJSONObject;
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

function TMCPFileDiscoveryTests.FlagsOf(Row: TJSONValue): string;
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

function TMCPFileDiscoveryTests.DriftRow(Report: TJSONObject;
  ValueId: Integer): TJSONValue;
var
  Row: TJSONValue;
begin
  Result := nil;
  for Row in Report.GetValue<TJSONArray>('drifted') do
    if Row.GetValue<Integer>('value_id') = ValueId then
      Exit(Row);
end;

procedure TMCPFileDiscoveryTests.DriftOfUnchangedCofReportsNoFlags;
var
  Report: TJSONObject;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  StoreCofValue;
  Report := CallDrift;
  try
    Assert.AreEqual(1, Report.GetValue<Integer>('checked'));
    Assert.AreEqual(1, Report.GetValue<Integer>('unchanged'));
    Assert.AreEqual(0, Report.GetValue<TJSONArray>('drifted').Count);
  finally
    Report.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.DriftReportsSelectionChangedWhenSharedSelectionChangedAfterExtraction;
var
  Report: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  Id := StoreCofValue;
  ApplyManualSelection(20, 60);
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row, 'The changed selection must be reported');
    Assert.AreEqual('selection_changed', FlagsOf(Row));
    Assert.AreEqual(Row.GetValue<Double>('stored_value'),
      Row.GetValue<Double>('current_value'), 1e-9,
      'The value is recomputed over the stored interval, not the new selection');
  finally
    Report.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.DriftTreatsMissingSharedSelectionAsChangeForManualSnapshotOnly;
var
  Report: TJSONObject;
  Row: TJSONValue;
  ManualId, AutoId: Integer;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  AutoId := StoreCofValue;
  Report := CallDrift;
  try
    Assert.AreEqual(1, Report.GetValue<Integer>('unchanged'),
      'An automatic snapshot without a shared selection is not a change');
  finally
    Report.Free;
  end;
  ApplyManualSelection(20, 60);
  ManualId := StoreCofValue;
  DeleteSharedSelection;
  Report := CallDrift;
  try
    Row := DriftRow(Report, ManualId);
    Assert.IsNotNull(Row, 'A manual snapshot without a shared selection is a change');
    Assert.AreEqual('selection_changed', FlagsOf(Row));
    Assert.IsNull(DriftRow(Report, AutoId));
  finally
    Report.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.DriftOfReplacedCurveReportsSourceAndValueChangedOverStoredInterval;
var
  Report: TJSONObject;
  Row: TJSONValue;
  Id, Values, Settings: Integer;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  Id := StoreCofValue;
  ReplaceZrwBytes(SyntheticZrwBytes(False));
  Values := StoredValueCount;
  Settings := SettingsRowCount;
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row, 'The replaced curve must drift');
    Assert.AreEqual('value_changed,source_changed', FlagsOf(Row));
    Assert.AreEqual(0.5, Row.GetValue<Double>('current_value'), 1e-9,
      'The current value is the mean over the stored interval of the new curve');
  finally
    Report.Free;
  end;
  Assert.AreEqual(Values, StoredValueCount);
  Assert.AreEqual(Settings, SettingsRowCount);
end;

procedure TMCPFileDiscoveryTests.DriftOfReplacedCurveWithTooFewSamplesReportsIntervalUnusable;
var
  Report: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  ApplyManualSelection(20, 60);
  Id := StoreCofValue;
  ReplaceZrwBytes(ShortZrwBytes(10));
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row, 'An unusable interval must be reported');
    Assert.AreEqual('source_changed,interval_unusable', FlagsOf(Row));
    Assert.IsTrue(Row.GetValue<TJSONValue>('current_value') is TJSONNull,
      'No value is compared for an unusable interval');
  finally
    Report.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.DriftOfCofWithoutSnapshotReportsIntervalUnusableOnly;
var
  Report: TJSONObject;
  Params, Response: TJSONObject;
  Row: TJSONValue;
  Id: Integer;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  Params := ValueParams(nil, '');
  try
    Response := FRegistry.Execute('add_value', Params);
  finally
    Params.Free;
  end;
  try
    Assert.IsNull(Response.FindValue('error'));
    Id := Response.GetValue<Integer>('id');
  finally
    Response.Free;
  end;
  Report := CallDrift;
  try
    Assert.AreEqual(1, Report.GetValue<Integer>('checked'));
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row, 'A value without a calculation context must be reported');
    Assert.AreEqual('interval_unusable', FlagsOf(Row));
  finally
    Report.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.DriftComparesEachCofValueWithItsOwnSnapshot;
var
  Report: TJSONObject;
  Row: TJSONValue;
  AutoId, ManualId: Integer;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  AutoId := StoreCofValue;
  ApplyManualSelection(20, 60);
  ManualId := StoreCofValue;
  Report := CallDrift;
  try
    Assert.AreEqual(2, Report.GetValue<Integer>('checked'));
    Assert.IsNull(DriftRow(Report, ManualId),
      'The manual value must be compared over its own interval');
    Row := DriftRow(Report, AutoId);
    Assert.IsNotNull(Row, 'The automatic value differs from the new shared selection');
    Assert.AreEqual('selection_changed', FlagsOf(Row));
    Assert.AreEqual(Row.GetValue<Double>('stored_value'),
      Row.GetValue<Double>('current_value'), 1e-9);
  finally
    Report.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.DriftReportsLineNumberedLoadErrorAndWritesNothing;
var
  Report: TJSONObject;
  Row: TJSONValue;
  Id, Values, Settings: Integer;
begin
  PrepareZrw;
  RegisterValueCheckTools(FRegistry);
  Id := StoreCofValue;
  ReplaceZrwBytes(MalformedZrwBytes);
  Values := StoredValueCount;
  Settings := SettingsRowCount;
  Report := CallDrift;
  try
    Row := DriftRow(Report, Id);
    Assert.IsNotNull(Row);
    Assert.AreEqual('read_failed', FlagsOf(Row));
    Assert.IsTrue(Pos('line 5', Row.GetValue<string>('message')) > 0,
      Row.GetValue<string>('message'));
  finally
    Report.Free;
  end;
  Assert.AreEqual(Values, StoredValueCount);
  Assert.AreEqual(Settings, SettingsRowCount);
end;

function TMCPFileDiscoveryTests.ExtractWithSelection(FileId: Int64;
  Selection: TJSONValue): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('file_id', TJSONNumber.Create(FileId));
    Params.AddPair('selection', Selection);
    Result := FRegistry.Execute('extract_file_key_values', Params);
  finally
    Params.Free;
  end;
end;

function TMCPFileDiscoveryTests.ManualSelectionObject(Start, Stop: Double): TJSONObject;
var
  Selection: TZRWSelection;
begin
  Selection := Default(TZRWSelection);
  Selection.Mode := zsmManual;
  Selection.Interval.StartCycle := Start;
  Selection.Interval.EndCycle := Stop;
  Selection.ReaderVersion := '2';
  Selection.AlgorithmVersion := '1';
  Selection.FileHash := ZrwHash;
  Selection.ApplyId := 'apply-call';
  Selection.AppliedAt := '2026-01-02T03:04:05Z';
  Selection.AppliedBy := FNotebook.Principal.Id;
  Selection.Revision := 1;
  Result := TJSONObject.ParseJSONValue(SelectionToJson(Selection)) as TJSONObject;
end;

procedure TMCPFileDiscoveryTests.PerCallSelectionGivesCofOverIntervalAndStoresNothing;
var
  Response: TJSONObject;
  Row: TJSONValue;
  CallValue, SharedValue: Double;
  Found: Boolean;
begin
  PrepareZrw;
  Response := ExtractWithSelection(FZrwFile.Id, ManualSelectionObject(20, 60));
  try
    Assert.IsNull(Response.FindValue('error'));
    Found := False;
    CallValue := 0;
    for Row in Response.GetValue<TJSONArray>('key_values') do
      if Row.GetValue<string>('name') = 'COF' then
      begin
        Found := True;
        CallValue := Row.GetValue<Double>('value');
        Assert.IsNotNull(Row.FindValue('analysis_snapshot'));
      end;
    Assert.IsTrue(Found, 'COF must be extracted over the given interval');
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, SettingsRowCount, 'The per-call selection is not stored');
  ApplyManualSelection(20, 60);
  Row := ExtractCofRow;
  try
    SharedValue := Row.GetValue<Double>('value');
  finally
    Row.Free;
  end;
  Assert.AreEqual(SharedValue, CallValue, 1e-12);
end;

procedure TMCPFileDiscoveryTests.SelectionOnReaderWithoutAnalysisIsRefused;
var
  Host: TPluginHost;
  Plugin: TJSONFixturePlugin;
  FileRow: unit_Item.TFile;
  Response: TJSONObject;
  Selection: TJSONObject;
begin
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'plugins'));
  Host := TPluginHost.Create(TPath.Combine(FRoot, 'plugins'));
  Plugin := nil;
  try
    Plugin := TJSONFixturePlugin.CreateNew(nil);
    (ApplicationServices as IupfCommandServices).RegisterPlugin(Plugin);
    FContext.PluginHost := Host;
    FreeAndNil(FRegistry);
    FRegistry := TToolRegistry.Create(FContext);
    RegisterFileTools(FRegistry);
    FileRow := AddFile(FItem, FJSONType, 'plain');
    FNotebook.Storage.WriteBytes(Format('Projects\%s\%s\%s',
      [FProject.FileFolder, FItem.FolderName, FileRow.FullName]),
      TEncoding.UTF8.GetBytes('{"kind":"synthetic"}'));
    Selection := TJSONObject.Create;
    Selection.AddPair('rect_a', TJSONNumber.Create(1));
    Response := ExtractWithSelection(FileRow.Id, Selection);
    try
      Assert.IsNotNull(Response.FindValue('error'));
      Assert.IsNull(Response.FindValue('key_values'));
    finally
      Response.Free;
    end;
  finally
    FreeAndNil(FRegistry);
    Host.Free;
    Plugin.Free;
  end;
end;

procedure TMCPFileDiscoveryTests.MalformedSelectionIsRefusedWithStatus;
var
  Response: TJSONObject;
  Selection: TJSONObject;
begin
  PrepareZrw;
  Selection := TJSONObject.Create;
  Selection.AddPair('mode', 'manual');
  Selection.AddPair('start', 'not a number');
  Response := ExtractWithSelection(FZrwFile.Id, Selection);
  try
    Assert.IsNotNull(Response.FindValue('error'));
    Assert.IsTrue(Pos('interval_unusable', Response.GetValue<string>('error')) > 0,
      Response.GetValue<string>('error'));
    Assert.IsNull(Response.FindValue('key_values'));
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, SettingsRowCount);
end;

procedure TMCPFileDiscoveryTests.NonObjectSelectionIsRefused;
var
  Response: TJSONObject;
begin
  PrepareZrw;
  Response := ExtractWithSelection(FZrwFile.Id, TJSONString.Create('20-60'));
  try
    Assert.IsNotNull(Response.FindValue('error'));
    Assert.IsNull(Response.FindValue('key_values'));
  finally
    Response.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMCPFileDiscoveryTests);

end.
