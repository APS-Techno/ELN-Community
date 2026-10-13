unit test_MCPFileDiscovery;

interface

uses
  DUnitX.TestFramework, System.JSON,
  unit_LocalNotebook, unit_MCPTools, unit_Project, unit_Item, unit_FileType;

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
    function AddProject(const Title: string): TProject;
    function AddItem(Project: TProject; const Title: string): TItem;
    function AddFile(Item: TItem; FileType: TFileType;
      const Title: string): unit_Item.TFile;
    function CallSearch(const Query: string; ProjectId: Integer): TJSONObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CompoundFilenameKeepsDuplicateAttachmentsAndProjectScope;
    [Test] procedure MultiwordSearchKeepsFileIdentityAndOwnerContext;
    [Test] procedure CompleteStoredFilenameCanBeSearched;
    [Test] procedure ExactCaseUnicodeFilenamesRemainSearchable;
    [Test] procedure ExtractionIdentifiesOnlyTheCompleteCompoundSuffix;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  Vcl.Forms, upfVisualClasses, upfIntf,
  Aurelius.Drivers.Interfaces, Aurelius.Engine.ObjectManager,
  unit_ProjectModel, unit_ItemTypes, unit_User,
  unit_ToolsNavigation, unit_ToolsFiles, unit_PluginHost,
  unit_ELNPluginCore, unit_ELNPluginTypes;

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

initialization
  TDUnitX.RegisterTestFixture(TMCPFileDiscoveryTests);

end.
