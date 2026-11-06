unit test_MCPCountTools;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  DUnitX.TestFramework,
  Aurelius.Events.Manager,
  unit_LocalNotebook, unit_MCPTools, unit_Project, unit_Item, unit_Tag,
  unit_FileType, unit_ValueType, unit_AuditLog;

type
  TSqlCounter = class
  private
    FProc: TSQLExecutingProc;
    FLog: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function CountMatching(const Fragment: string): Integer;
  end;

  [TestFixture]
  TMCPCountToolTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FFileType: TFileType;
    FValueType: TValueType;
    FP1, FP2, FP3, FP4: TProject;
    FT1, FT2: TTag;
    FScope: TArray<Integer>;
    procedure UseScope(const Projects: TArray<Integer>);
    function Run(const Tool: string; const Params: TJSONObject): TJSONObject;
    function CallProjects(IncludeArchived: Boolean): TJSONObject;
    function CallTags: TJSONObject;
    function CallStats(ProjectId: Integer): TJSONObject;
    function PairNames(Response: TJSONObject): string;
    function Activity(Response: TJSONObject): string;
    function ProjectCount(Response: TJSONObject; ProjectId: Integer): Integer;
    function TagCount(Response: TJSONObject; TagId: Integer): Integer;
    function ProjectIds(Response: TJSONObject): TArray<Integer>;
    procedure GrowFixture;
    procedure Measure(const Tool, Table: string; out Total, OnTable: Integer);
  public
    function AddProject(const Title: string; Archived: Boolean): TProject;
    function AddItem(Project: TProject; const Title: string;
      Deleted: Boolean): TItem;
    procedure AddFile(Item: TItem);
    procedure AddValue(Item: TItem);
    procedure AddProtocol(Item: TItem);
    procedure AddNote(Item: TItem);
    procedure AddAudit(Item: TItem; Operation: TAuditOperation;
      const Description: string; SecondsAhead: Integer);
    function AddTag(const Name: string): TTag;
    procedure TagItem(Tag: TTag; Item: TItem);
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ListProjectsCounts;
    [Test]
    procedure ListProjectsScoped;
    [Test]
    procedure ListTagsCountsVisibleNonDeleted;
    [Test]
    procedure ListTagsScoped;
    [Test]
    procedure ListProjectsFixedStatements;
    [Test]
    procedure ListTagsFixedStatements;
    [Test]
    procedure ProjectStatsCounts;
    [Test]
    procedure ProjectStatsEmpty;
    [Test]
    procedure ProjectStatsActivityUnchanged;
    [Test]
    procedure ProjectStatsFixedStatements;
  end;

implementation

uses
  System.IOUtils,
  Aurelius.Mapping.Explorer, Aurelius.Engine.ObjectManager,
  Aurelius.Drivers.Interfaces,
  unit_ProjectModel, unit_ItemTypes, unit_LabEntry, unit_Protocol,
  unit_ToolsNavigation, unit_ToolsMetadata;

constructor TSqlCounter.Create;
var
  Log: TList<string>;
begin
  inherited Create;
  FLog := TList<string>.Create;
  Log := FLog;
  FProc :=
    procedure(Args: TSQLExecutingArgs)
    begin
      Log.Add(Args.SQL);
    end;
  TMappingExplorer.Default.Events.OnSQLExecuting.Subscribe(FProc);
end;

destructor TSqlCounter.Destroy;
begin
  TMappingExplorer.Default.Events.OnSQLExecuting.Unsubscribe(FProc);
  FLog.Free;
  inherited;
end;

procedure TSqlCounter.Clear;
begin
  FLog.Clear;
end;

function TSqlCounter.Count: Integer;
begin
  Result := FLog.Count;
end;

function TSqlCounter.CountMatching(const Fragment: string): Integer;
var
  SQL: string;
begin
  Result := 0;
  for SQL in FLog do
    if SQL.ToUpper.Contains(Fragment.ToUpper) then
      Inc(Result);
end;

function TMCPCountToolTests.AddProject(const Title: string;
  Archived: Boolean): TProject;
var
  Projects: TProjectsModel;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Result := Projects.AddProject(Title, 'About ' + Title, FNotebook.Principal);
  finally
    Projects.Free;
  end;
  if Archived then
  begin
    Result.IsArchived := True;
    FNotebook.Manager.Flush;
  end;
end;

function TMCPCountToolTests.AddItem(Project: TProject; const Title: string;
  Deleted: Boolean): TItem;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.ProjectID := Project.Id;
  Result.Type_ := TItemType.Other;
  Result.Level := TItemLevel.Proc;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  Result.IsDeleted := Deleted;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
end;

procedure TMCPCountToolTests.AddFile(Item: TItem);
var
  Row: unit_Item.TFile;
begin
  Row := unit_Item.TFile.Create;
  Row.Title := 'file';
  Row.Item := Item;
  Row.FileType := FFileType;
  Row.CreatedBy := FNotebook.Principal.Id;
  Row.CreatedDate := Now;
  Item.Files.Add(Row);
  FNotebook.Manager.Flush;
end;

procedure TMCPCountToolTests.AddValue(Item: TItem);
var
  Row: TValue;
begin
  Row := TValue.Create;
  Row.Item := Item;
  Row.ValueType := FValueType;
  Row.Value := 1;
  Row.CreatedBy := FNotebook.Principal.Id;
  Row.CreatedDate := Now;
  Item.Values.Add(Row);
  FNotebook.Manager.Flush;
end;

procedure TMCPCountToolTests.AddProtocol(Item: TItem);
var
  Row: TProtocol;
begin
  Row := TProtocol.Create;
  Row.Title := 'protocol';
  Row.CreatedBy := FNotebook.Principal.Id;
  Row.CreatedDate := Now;
  Item.Entries.Add(Row);
  FNotebook.Manager.Flush;
end;

procedure TMCPCountToolTests.AddNote(Item: TItem);
var
  Statement: IDBStatement;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand(Format('INSERT INTO LabEntries (ItemID, EntryType, ' +
    'Title, CreatedDate, Version) VALUES (%d, ''Note'', ''note'', ' +
    'datetime(''now''), 1)', [Item.Id]));
  Statement.Execute;
end;

procedure TMCPCountToolTests.AddAudit(Item: TItem; Operation: TAuditOperation;
  const Description: string; SecondsAhead: Integer);
var
  Row: TAuditLog;
begin
  Row := TAuditLog.Create;
  Row.EntityType := aetItem;
  Row.EntityId := Item.Id;
  Row.Operation := Operation;
  Row.UserId := FNotebook.Principal.Id;
  Row.Timestamp := Now + SecondsAhead / SecsPerDay;
  Row.Description := Description;
  FNotebook.Manager.Save(Row);
  FNotebook.Manager.Flush;
end;

function TMCPCountToolTests.AddTag(const Name: string): TTag;
begin
  Result := TTag.Create;
  Result.Name := Name;
  Result.Color := '#336699';
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
end;

procedure TMCPCountToolTests.TagItem(Tag: TTag; Item: TItem);
var
  Link: TItemTag;
begin
  Link := TItemTag.Create;
  Link.ItemId := Item.Id;
  Link.TagId := Tag.Id;
  Link.CreatedDate := Now;
  FNotebook.Manager.Save(Link);
  FNotebook.Manager.Flush;
end;

procedure TMCPCountToolTests.UseScope(const Projects: TArray<Integer>);
begin
  FScope := Projects;
end;

procedure TMCPCountToolTests.Setup;
var
  I1a, I1b, I1c, I4a: TItem;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-MCPCount-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Tool fixture', 'fixture-password');

  FFileType := TFileType.Create;
  FFileType.Ext := '.txt';
  FFileType.CreatedDate := Now;
  FNotebook.Manager.Save(FFileType);
  FValueType := TValueType.Create;
  FValueType.Symbol := 'CT';
  FValueType.Title := 'Count type';
  FValueType.Units := 'nm';
  FValueType.CreatedDate := Now;
  FValueType.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Save(FValueType);
  FNotebook.Manager.Flush;

  FP1 := AddProject('P1', False);
  FP2 := AddProject('P2', False);
  FP3 := AddProject('P3', True);
  FP4 := AddProject('P4', False);
  I1a := AddItem(FP1, 'I1a', False);
  I1b := AddItem(FP1, 'I1b', False);
  I1c := AddItem(FP1, 'I1c deleted', True);
  AddItem(FP3, 'I3a', False);
  I4a := AddItem(FP4, 'I4a', False);
  AddItem(FP4, 'I4b', False);
  AddFile(I1a);
  AddValue(I1a);
  AddValue(I1a);
  AddProtocol(I1a);
  AddNote(I1a);
  AddFile(I1b);
  AddValue(I1b);
  AddFile(I1c);
  AddValue(I1c);
  AddProtocol(I1c);
  AddAudit(I1a, aoUpdate, 'I1a changed', 1);
  AddAudit(I1c, aoDelete, 'I1c removed', 2);
  AddAudit(I1b, aoCreate, 'I1b created', 3);
  AddAudit(I4a, aoUpdate, 'I4a changed', 4);
  FT1 := AddTag('T1');
  FT2 := AddTag('T2');
  TagItem(FT1, I1a);
  TagItem(FT1, I1c);
  TagItem(FT1, I4a);
  TagItem(FT2, I1c);
  FScope := nil;
end;

procedure TMCPCountToolTests.TearDown;
begin
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TMCPCountToolTests.Run(const Tool: string;
  const Params: TJSONObject): TJSONObject;
var
  Manager: TObjectManager;
  Context: TToolContext;
  Registry: TToolRegistry;
begin
  Manager := TObjectManager.Create(FNotebook.Connection);
  try
    Context := Default(TToolContext);
    Context.Manager := Manager;
    Context.User := FNotebook.Principal;
    Context.AccessPolicy := FNotebook.AccessPolicy;
    Context.Storage := FNotebook.Storage;
    Context.ScopedProjects := FScope;
    Registry := TToolRegistry.Create(Context);
    try
      RegisterNavigationTools(Registry);
      RegisterMetadataTools(Registry);
      Result := Registry.Execute(Tool, Params);
    finally
      Registry.Free;
    end;
  finally
    Manager.Free;
  end;
end;

function TMCPCountToolTests.CallProjects(IncludeArchived: Boolean): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    if IncludeArchived then
      Params.AddPair('include_archived', TJSONBool.Create(True));
    Result := Run('list_projects', Params);
  finally
    Params.Free;
  end;
end;

function TMCPCountToolTests.CallTags: TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Result := Run('list_tags', Params);
  finally
    Params.Free;
  end;
end;

function TMCPCountToolTests.ProjectCount(Response: TJSONObject;
  ProjectId: Integer): Integer;
var
  Row: TJSONValue;
begin
  Result := -1;
  for Row in Response.GetValue<TJSONArray>('projects') do
    if Row.GetValue<Integer>('id') = ProjectId then
      Exit(Row.GetValue<Integer>('item_count'));
end;

function TMCPCountToolTests.TagCount(Response: TJSONObject;
  TagId: Integer): Integer;
var
  Row: TJSONValue;
begin
  Result := -1;
  for Row in Response.GetValue<TJSONArray>('tags') do
    if Row.GetValue<Integer>('id') = TagId then
      Exit(Row.GetValue<Integer>('item_count'));
end;

function TMCPCountToolTests.ProjectIds(Response: TJSONObject): TArray<Integer>;
var
  Row: TJSONValue;
begin
  Result := nil;
  for Row in Response.GetValue<TJSONArray>('projects') do
    Result := Result + [Row.GetValue<Integer>('id')];
end;

procedure TMCPCountToolTests.GrowFixture;
var
  I: Integer;
  Item: TItem;
begin
  for I := 1 to 5 do
  begin
    Item := AddItem(FP1, 'grow1-' + IntToStr(I), False);
    TagItem(FT1, Item);
    AddFile(Item);
    AddValue(Item);
    AddProtocol(Item);
    AddNote(Item);
  end;
  for I := 1 to 5 do
    AddItem(FP4, 'grow4-' + IntToStr(I), False);
end;

procedure TMCPCountToolTests.Measure(const Tool, Table: string; out Total,
  OnTable: Integer);
var
  Counter: TSqlCounter;
  Response: TJSONObject;
begin
  Counter := TSqlCounter.Create;
  try
    if Tool = 'list_projects' then
      Response := CallProjects(False)
    else if Tool = 'get_project_stats' then
      Response := CallStats(FP1.Id)
    else
      Response := CallTags;
    Response.Free;
    Total := Counter.Count;
    OnTable := Counter.CountMatching('FROM ' + Table);
  finally
    Counter.Free;
  end;
end;

procedure TMCPCountToolTests.ListProjectsCounts;
var
  Response: TJSONObject;
  Row: TJSONObject;
  Names: TArray<string>;
  I: Integer;
begin
  Response := CallProjects(False);
  try
    Assert.AreEqual(2, ProjectCount(Response, FP1.Id), 'P1');
    Assert.AreEqual(0, ProjectCount(Response, FP2.Id), 'P2');
    Assert.AreEqual(2, ProjectCount(Response, FP4.Id), 'P4');
    Assert.AreEqual(-1, ProjectCount(Response, FP3.Id), 'P3 hidden');
    Row := Response.GetValue<TJSONArray>('projects').Items[0] as TJSONObject;
    SetLength(Names, Row.Count);
    for I := 0 to Row.Count - 1 do
      Names[I] := Row.Pairs[I].JsonString.Value;
    Assert.AreEqual('id,title,description,owner,start_date,end_date,' +
      'is_archived,item_count', string.Join(',', Names));
  finally
    Response.Free;
  end;
  Response := CallProjects(True);
  try
    Assert.AreEqual(1, ProjectCount(Response, FP3.Id), 'P3 archived');
    Assert.AreEqual(2, ProjectCount(Response, FP1.Id), 'P1 archived call');
  finally
    Response.Free;
  end;
end;

function TMCPCountToolTests.CallStats(ProjectId: Integer): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('project_id', TJSONNumber.Create(ProjectId));
    Result := Run('get_project_stats', Params);
  finally
    Params.Free;
  end;
end;

function TMCPCountToolTests.PairNames(Response: TJSONObject): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Response.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + Response.Pairs[I].JsonString.Value;
  end;
end;

function TMCPCountToolTests.Activity(Response: TJSONObject): string;
var
  Row: TJSONValue;
begin
  Result := '';
  for Row in Response.GetValue<TJSONArray>('recent_activity') do
  begin
    if Result <> '' then
      Result := Result + ';';
    Result := Result + Row.GetValue<string>('id') + '|' +
      Row.GetValue<string>('entity_type') + '|' +
      Row.GetValue<string>('operation') + '|' +
      Row.GetValue<string>('description');
  end;
end;

procedure TMCPCountToolTests.ListProjectsScoped;
var
  Response: TJSONObject;
  Ids: TArray<Integer>;
begin
  UseScope([FP1.Id]);
  Response := CallProjects(True);
  try
    Ids := ProjectIds(Response);
    Assert.AreEqual(1, Integer(Length(Ids)));
    Assert.AreEqual(FP1.Id, Ids[0]);
    Assert.AreEqual(2, ProjectCount(Response, FP1.Id));
  finally
    Response.Free;
  end;
end;

procedure TMCPCountToolTests.ListTagsCountsVisibleNonDeleted;
var
  Response: TJSONObject;
begin
  Response := CallTags;
  try
    Assert.AreEqual(2, TagCount(Response, FT1.Id), 'T1');
    Assert.AreEqual(0, TagCount(Response, FT2.Id), 'T2');
  finally
    Response.Free;
  end;
end;

procedure TMCPCountToolTests.ListTagsScoped;
var
  Response: TJSONObject;
begin
  UseScope([FP1.Id]);
  Response := CallTags;
  try
    Assert.AreEqual(1, TagCount(Response, FT1.Id), 'T1');
    Assert.AreEqual(0, TagCount(Response, FT2.Id), 'T2');
  finally
    Response.Free;
  end;
end;

procedure TMCPCountToolTests.ListProjectsFixedStatements;
var
  BeforeTotal, BeforeItems, AfterTotal, AfterItems: Integer;
begin
  Measure('list_projects', 'Items', BeforeTotal, BeforeItems);
  Measure('list_projects', 'Items', BeforeTotal, BeforeItems);
  GrowFixture;
  Measure('list_projects', 'Items', AfterTotal, AfterItems);
  Assert.AreEqual(BeforeTotal, AfterTotal, 'statements after growth');
  Assert.IsTrue(AfterItems <= 1,
    'statements on Items: ' + IntToStr(AfterItems));
end;

procedure TMCPCountToolTests.ListTagsFixedStatements;
var
  BeforeTotal, BeforeLinks, AfterTotal, AfterLinks: Integer;
begin
  Measure('list_tags', 'ItemTags', BeforeTotal, BeforeLinks);
  Measure('list_tags', 'ItemTags', BeforeTotal, BeforeLinks);
  GrowFixture;
  Measure('list_tags', 'ItemTags', AfterTotal, AfterLinks);
  Assert.AreEqual(BeforeTotal, AfterTotal, 'statements after growth');
  Assert.IsTrue(AfterLinks <= 1,
    'statements on ItemTags: ' + IntToStr(AfterLinks));
end;

procedure TMCPCountToolTests.ProjectStatsCounts;
var
  Response: TJSONObject;
begin
  Response := CallStats(FP1.Id);
  try
    Assert.AreEqual('P1', Response.GetValue<string>('project_title'));
    Assert.AreEqual(2, Response.GetValue<Integer>('item_count'), 'items');
    Assert.AreEqual(2, Response.GetValue<Integer>('file_count'), 'files');
    Assert.AreEqual(3, Response.GetValue<Integer>('value_count'), 'values');
    Assert.AreEqual(1, Response.GetValue<Integer>('protocol_count'), 'protocols');
    Assert.AreEqual(1, Response.GetValue<Integer>('tag_count'), 'tags');
    Assert.AreEqual('project_title,item_count,file_count,value_count,' +
      'protocol_count,tag_count,recent_activity', PairNames(Response));
  finally
    Response.Free;
  end;
end;

procedure TMCPCountToolTests.ProjectStatsEmpty;
var
  Response: TJSONObject;
begin
  Response := CallStats(FP2.Id);
  try
    Assert.AreEqual(0, Response.GetValue<Integer>('item_count'), 'items');
    Assert.AreEqual(0, Response.GetValue<Integer>('file_count'), 'files');
    Assert.AreEqual(0, Response.GetValue<Integer>('value_count'), 'values');
    Assert.AreEqual(0, Response.GetValue<Integer>('protocol_count'), 'protocols');
    Assert.AreEqual(0, Response.GetValue<Integer>('tag_count'), 'tags');
    Assert.AreEqual('2|Project|Create|Created project "P2"', Activity(Response));
  finally
    Response.Free;
  end;
end;

procedure TMCPCountToolTests.ProjectStatsActivityUnchanged;
var
  Response: TJSONObject;
begin
  Response := CallStats(FP1.Id);
  try
    Assert.AreEqual('7|Item|Create|I1b created;5|Item|Update|I1a changed;' +
      '1|Project|Create|Created project "P1"', Activity(Response));
  finally
    Response.Free;
  end;
end;

procedure TMCPCountToolTests.ProjectStatsFixedStatements;
var
  BeforeTotal, BeforeOnTable, AfterTotal, AfterOnTable: Integer;
begin
  Measure('get_project_stats', 'Items', BeforeTotal, BeforeOnTable);
  Measure('get_project_stats', 'Items', BeforeTotal, BeforeOnTable);
  GrowFixture;
  Measure('get_project_stats', 'Items', AfterTotal, AfterOnTable);
  Assert.AreEqual(BeforeTotal, AfterTotal, 'statements after growth');
end;

initialization
  TDUnitX.RegisterTestFixture(TMCPCountToolTests);

end.
