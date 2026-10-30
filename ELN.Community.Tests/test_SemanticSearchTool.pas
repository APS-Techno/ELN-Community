unit test_SemanticSearchTool;

interface

uses
  System.SysUtils, System.JSON, DUnitX.TestFramework,
  unit_LocalNotebook, unit_MCPTools, unit_SemanticSearchApi, unit_SemanticSearchService,
  unit_TextEmbedder, unit_CrossEncoder, unit_ProjectAccessPolicy, test_SearchDoubles;

type
  THashEmbedder = class(TInterfacedObject, ITextEmbedder)
  private
    FBatchDelayMs: Cardinal;
    function Embed(const Text: string): TEmbedding;
  public
    function Identity: string;
    function Dimension: Integer;
    function MaxTokens: Integer;
    function EncodeQuery(const Text: string): TEmbedding;
    function EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
      const Cancelled: TCancelCheck = nil): TArray<TEmbedding>;
    property BatchDelayMs: Cardinal read FBatchDelayMs write FBatchDelayMs;
  end;

  [TestFixture]
  TSemanticSearchToolTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FContext: TToolContext;
    FRegistry: TToolRegistry;
    FService: TSemanticSearchService;
    FCross: TFakeCrossEncoder;
    FCrossRef: ICrossEncoder;
    FEmbedder: THashEmbedder;
    FEmbedderRef: ITextEmbedder;
    FFake: TFakeSemanticSearch;
    FFakeRef: ISemanticSearch;
    FProject1, FProject2: Integer;
    FItem1, FItem2: Integer;
    FSavedDeadline: Cardinal;
    FFolder, FActionType: Integer;
    FProbeA, FProbeB: Integer;
    FPolicy: IProjectAccessPolicy;
    procedure UsePolicy(ReturnNil: Boolean);
    function AddProject(const Title: string): Integer;
    function AddItem(ProjectId: Integer; const Title, Description: string): Integer;
    procedure Rebuild(WithService: Boolean);
    function Call(const Query: string; ProjectId, TopK: Integer): TJSONObject;
    function HasHitFor(Response: TJSONObject; ProjectId: Integer): Boolean;
    function Failure(const Query: string; ProjectId, TopK: Integer): string;
    function AttachDocx(ProjectId, ItemId: Integer; const Sentence: string): Int64;
    function CallJson(const Query, ExtraJson: string): TJSONObject;
    function FailureJson(const Query, ExtraJson: string): string;
    function GroupIds(Response: TJSONObject): TArray<Integer>;
    procedure ExpectOnly(const ExtraJson: string; const Expected: array of Integer);
    procedure AddProbeData;
    procedure UseReranker;
    function GroupOrder(Response: TJSONObject): TArray<Integer>;
    procedure UseFake(Remote: Boolean);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReturnsHitsWithIndexStatus;
    [Test]
    procedure ScopedSessionNeverLeaks;
    [Test]
    procedure UnavailableWhenNoService;
    [Test]
    procedure IncompleteIndexReported;
    [Test]
    procedure RuntimeFailureKeepsCause;
    [Test]
    procedure ShortQueryReadsNothing;
    [Test]
    procedure RejectsTopKOutOfRange;
    [Test]
    procedure ListedInToolsList;
    [Test]
    procedure FileTextFoundThroughMcp;
    [Test]
    procedure ShortQueryIncompleteAfterDeadlineDuringExtraction;
    [Test]
    procedure NoFilterParameterKeepsTheStage5Result;
    [Test]
    procedure FolderIdNarrowsTheGroups;
    [Test]
    procedure ItemTypesNarrowTheGroups;
    [Test]
    procedure LevelsNarrowTheGroups;
    [Test]
    procedure ActionTypeIdNarrowsTheGroups;
    [Test]
    procedure DatesNarrowTheGroups;
    [Test]
    procedure DateEchoIsTheLiteralDayAndATimePartIsRefused;
    [Test]
    procedure ValuesNarrowTheGroupsAndEchoTheConvertedLimit;
    [Test]
    procedure UnknownUnitReturnsTheFilterErrorText;
    [Test]
    procedure CrossDimensionUnitReturnsTheFilterErrorText;
    [Test]
    procedure InvisibleFolderGivesTheNotFoundText;
    [Test]
    procedure BadFilterParametersReturnErrors;
    [Test]
    procedure SchemaListsTheFilterParameters;
    [Test]
    procedure RerankedIsFalseWithoutAReranker;
    [Test]
    procedure RerankerReordersTheGroupsAndSetsTheFlag;
    [Test]
    procedure ShortQueryReportsRerankedFalse;
    [Test]
    procedure RerankerFailureKeepsTheHybridGroupsAndFlagFalse;
    [Test]
    procedure DescriptionMentionsReranking;
    [Test]
    procedure NilVisibleSetMeansEveryProject;
    [Test]
    procedure EmptyVisibleSetGivesNoGroup;
    [Test]
    procedure RemoteSearchUsesTheInterfaceWithoutSync;
    [Test]
    procedure LocalSearchSyncsTheIndexFirst;
    [Test]
    procedure RemoteUnavailableKeepsTheCause;
    [Test]
    procedure ShortQueryReadsTheInterfaceStatus;
    [Test]
    procedure RemoteGroupOutsideTheScopeIsDropped;
    [Test]
    procedure InvalidFilterIsRejectedBeforeTheLocalSync;
  end;

implementation

uses
  System.IOUtils, System.Hash, System.Zip, System.Classes,
  Aurelius.Engine.ObjectManager,
  unit_Project, unit_ProjectModel, unit_Item, unit_ItemTypes,
  unit_ToolsNavigation, unit_SearchPassages, unit_SearchDocumentProvider, unit_FilePaths,
  unit_FileType, unit_TextExtractors, unit_ActionType, unit_ValueType, System.DateUtils,
  System.Generics.Collections, unit_LocalSemanticSearch, unit_SemanticSearchFilter;

const
  FakeDim = 8;
  FakeIdentity = 'tool-fake';
  UnavailableCode = 'semantic_search_unavailable';

function THashEmbedder.Identity: string;
begin
  Result := FakeIdentity;
end;

function THashEmbedder.Dimension: Integer;
begin
  Result := FakeDim;
end;

function THashEmbedder.MaxTokens: Integer;
begin
  Result := 512;
end;

function THashEmbedder.Embed(const Text: string): TEmbedding;
var
  Bytes: TBytes;
  I: Integer;
  Norm: Double;
begin
  Bytes := THashSHA2.GetHashBytes(Text);
  SetLength(Result.Vector, FakeDim);
  Norm := 0;
  for I := 0 to FakeDim - 1 do
  begin
    Result.Vector[I] := Bytes[I] - 127.5;
    Norm := Norm + Sqr(Double(Result.Vector[I]));
  end;
  Norm := Sqrt(Norm);
  for I := 0 to FakeDim - 1 do
    Result.Vector[I] := Result.Vector[I] / Norm;
  Result.TokenCount := 1;
  Result.SourceTokenCount := 1;
  Result.Truncated := False;
end;

function THashEmbedder.EncodeQuery(const Text: string): TEmbedding;
begin
  Result := Embed(Text);
end;

function THashEmbedder.EncodePassages(const Texts: TArray<string>;
  Policy: TOverlengthPolicy; const Cancelled: TCancelCheck): TArray<TEmbedding>;
var
  I: Integer;
begin
  if FBatchDelayMs > 0 then
    Sleep(FBatchDelayMs);
  SetLength(Result, Length(Texts));
  for I := 0 to High(Texts) do
    Result[I] := Embed(Texts[I]);
end;

function TSemanticSearchToolTests.AddProject(const Title: string): Integer;
var
  Projects: TProjectsModel;
  Project: TProject;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Project := Projects.AddProject(Title, '', FNotebook.Principal);
    Result := Project.Id;
  finally
    Projects.Free;
  end;
end;

function TSemanticSearchToolTests.AddItem(ProjectId: Integer;
  const Title, Description: string): Integer;
var
  Item: TItem;
begin
  Item := TItem.Create;
  Item.Title := Title;
  Item.Description := Description;
  Item.ProjectID := ProjectId;
  Item.Type_ := TItemType.Specimen;
  Item.Level := TItemLevel.Item;
  Item.CreatedBy := FNotebook.Principal.Id;
  Item.CreatedDate := Now;
  FNotebook.Manager.Save(Item);
  FNotebook.Manager.Flush;
  Result := Item.Id;
end;

procedure TSemanticSearchToolTests.Rebuild(WithService: Boolean);
begin
  FreeAndNil(FRegistry);
  FContext := Default(TToolContext);
  FContext.Manager := FNotebook.Manager;
  FContext.User := FNotebook.Principal;
  if FPolicy <> nil then
    FContext.AccessPolicy := FPolicy
  else
    FContext.AccessPolicy := FNotebook.AccessPolicy;
  FContext.Storage := FNotebook.Storage;
  if WithService then
  begin
    FContext.SemanticIndex := FService;
    if FFakeRef <> nil then
      FContext.SemanticSearch := FFakeRef
    else
      FContext.SemanticSearch := TLocalSemanticSearch.Create(FService,
        SemanticFilterResolver(FNotebook.Manager), ValueLimitDescriber(FNotebook.Manager));
  end;
  FRegistry := TToolRegistry.Create(FContext);
  RegisterNavigationTools(FRegistry);
end;

procedure TSemanticSearchToolTests.Setup;
begin
  FSavedDeadline := SemanticSyncDeadlineMs;
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SemanticTool-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Tool fixture', 'fixture-password');
  FProject1 := AddProject('Synthetic multilayers');
  FProject2 := AddProject('Synthetic crystals');
  FItem1 := AddItem(FProject1, 'Mo/Si multilayer',
    'interface roughness grows after annealing');
  FItem2 := AddItem(FProject2, 'Zirconia sample',
    'tungstenite dopant raised the zirconia hardness');
  FEmbedder := THashEmbedder.Create;
  FEmbedderRef := FEmbedder;
  FService := TSemanticSearchService.Create(TPath.Combine(FRoot, 'search.sqlite'),
    function: ITextEmbedder
    begin
      Result := FEmbedderRef;
    end, nil, TNotebookDocumentProvider.Create(FNotebook.Manager), '');
  Rebuild(True);
end;

procedure TSemanticSearchToolTests.TearDown;
begin
  SemanticSyncDeadlineMs := FSavedDeadline;
  FreeAndNil(FRegistry);
  FContext := Default(TToolContext);
  FFakeRef := nil;
  FFake := nil;
  FreeAndNil(FService);
  FPolicy := nil;
  FEmbedderRef := nil;
  FCrossRef := nil;
  FCross := nil;
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TSemanticSearchToolTests.Call(const Query: string; ProjectId,
  TopK: Integer): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('query', Query);
    if ProjectId <> 0 then
      Params.AddPair('project_id', TJSONNumber.Create(ProjectId));
    if TopK <> 0 then
      Params.AddPair('top_k', TJSONNumber.Create(TopK));
    Result := FRegistry.Execute('search_semantic', Params);
  finally
    Params.Free;
  end;
end;

function TSemanticSearchToolTests.HasHitFor(Response: TJSONObject;
  ProjectId: Integer): Boolean;
var
  Hit: TJSONValue;
begin
  Result := False;
  for Hit in Response.GetValue<TJSONArray>('groups') do
    if Hit.GetValue<Integer>('project_id') = ProjectId then
      Exit(True);
end;

function TSemanticSearchToolTests.Failure(const Query: string; ProjectId,
  TopK: Integer): string;
begin
  Result := '';
  try
    Call(Query, ProjectId, TopK).Free;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

function TSemanticSearchToolTests.CallJson(const Query, ExtraJson: string): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(ExtraJson) as TJSONObject;
  try
    Params.AddPair('query', Query);
    Result := FRegistry.Execute('search_semantic', Params);
  finally
    Params.Free;
  end;
end;

function TSemanticSearchToolTests.FailureJson(const Query, ExtraJson: string): string;
begin
  Result := '';
  try
    CallJson(Query, ExtraJson).Free;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

procedure TSemanticSearchToolTests.UsePolicy(ReturnNil: Boolean);
begin
  FPolicy := TUnrestrictedPolicy.Create(FNotebook.AccessPolicy, ReturnNil);
  Rebuild(True);
end;

procedure TSemanticSearchToolTests.UseFake(Remote: Boolean);
begin
  FFake := TFakeSemanticSearch.Create;
  FFakeRef := FFake;
  FFake.Remote := Remote;
  Rebuild(True);
end;

function TSemanticSearchToolTests.GroupIds(Response: TJSONObject): TArray<Integer>;
var
  Group: TJSONValue;
begin
  Result := nil;
  for Group in Response.GetValue<TJSONArray>('groups') do
    Result := Result + [Group.GetValue<Integer>('item_id')];
  TArray.Sort<Integer>(Result);
end;

procedure TSemanticSearchToolTests.ExpectOnly(const ExtraJson: string;
  const Expected: array of Integer);
var
  Response: TJSONObject;
  Want, Got: TArray<Integer>;
  I: Integer;
begin
  Response := CallJson('filterprobe', ExtraJson);
  try
    Got := GroupIds(Response);
    SetLength(Want, Length(Expected));
    for I := 0 to High(Expected) do
      Want[I] := Expected[I];
    TArray.Sort<Integer>(Want);
    Assert.AreEqual(Length(Want), Length(Got), ExtraJson);
    for I := 0 to High(Want) do
      Assert.AreEqual(Want[I], Got[I], ExtraJson);
    Assert.IsNotNull(Response.GetValue('filters_applied'), 'The applied filter is echoed');
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.AddProbeData;
var
  Manager: TObjectManager;
  Project: TProject;
  Folder: TFolder;
  Action: TActionType;
  Hardness: TValueType;
  Value: unit_Item.TValue;
  A, B: TItem;
begin
  Manager := FNotebook.Manager;
  Project := Manager.Find<TProject>(FProject1);
  Folder := TFolder.Create;
  Folder.Title := 'Probe folder';
  Folder.CreatedDate := Now;
  Folder.CreatedBy := FNotebook.Principal.Id;
  Project.Folders.Add(Folder);
  Action := TActionType.Create;
  Action.Title := 'Probe action';
  Action.CreatedDate := Now;
  Manager.Save(Action);
  Hardness := TValueType.Create;
  Hardness.Symbol := 'PH';
  Hardness.Title := 'Probe hardness';
  Hardness.Units := 'MPa';
  Hardness.CreatedDate := Now;
  Hardness.CreatedBy := FNotebook.Principal.Id;
  Manager.Save(Hardness);
  Manager.Flush;
  FFolder := Folder.Id;
  FActionType := Action.Id;

  A := TItem.Create;
  A.Title := 'Probe A';
  A.Description := 'filterprobe alpha';
  A.ProjectID := FProject1;
  A.FolderID := FFolder;
  A.Type_ := TItemType.Measurement;
  A.Level := TItemLevel.Action;
  A.ActionType := Action;
  A.CreatedBy := FNotebook.Principal.Id;
  A.CreatedDate := EncodeDateTime(2026, 1, 10, 10, 0, 0, 0);
  A.ModifiedDate := EncodeDateTime(2026, 2, 1, 12, 0, 0, 0);
  Value := unit_Item.TValue.Create;
  Value.ValueType := Hardness;
  Value.RecType := TEST_RESULT;
  Value.Value := 12000;
  Value.CreatedDate := Now;
  Value.Item := A;
  A.Values.Add(Value);
  Manager.Save(A);

  B := TItem.Create;
  B.Title := 'Probe B';
  B.Description := 'filterprobe beta';
  B.ProjectID := FProject1;
  B.Type_ := TItemType.Testing;
  B.Level := TItemLevel.Proc;
  B.CreatedBy := FNotebook.Principal.Id;
  B.CreatedDate := EncodeDateTime(2026, 3, 5, 9, 0, 0, 0);
  Value := unit_Item.TValue.Create;
  Value.ValueType := Hardness;
  Value.RecType := TEST_RESULT;
  Value.Value := 5000;
  Value.CreatedDate := Now;
  Value.Item := B;
  B.Values.Add(Value);
  Manager.Save(B);
  Manager.Flush;
  FProbeA := A.Id;
  FProbeB := B.Id;
end;

procedure TSemanticSearchToolTests.NoFilterParameterKeepsTheStage5Result;
var
  Response: TJSONObject;
begin
  AddProbeData;
  Response := CallJson('filterprobe', '{}');
  try
    Assert.AreEqual<NativeInt>(4, Length(GroupIds(Response)), 'Every indexed item is returned');
    Assert.IsNull(Response.GetValue('filters_applied'), 'No filter, no echo');
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.FolderIdNarrowsTheGroups;
begin
  AddProbeData;
  ExpectOnly(Format('{"folder_id":%d}', [FFolder]), [FProbeA]);
end;

procedure TSemanticSearchToolTests.ItemTypesNarrowTheGroups;
begin
  AddProbeData;
  ExpectOnly('{"item_types":["Testing"]}', [FProbeB]);
  ExpectOnly('{"item_types":["Testing","Measurement"]}', [FProbeA, FProbeB]);
end;

procedure TSemanticSearchToolTests.LevelsNarrowTheGroups;
begin
  AddProbeData;
  ExpectOnly('{"levels":["Action"]}', [FProbeA]);
  ExpectOnly('{"levels":["Proc"]}', [FProbeB]);
end;

procedure TSemanticSearchToolTests.ActionTypeIdNarrowsTheGroups;
begin
  AddProbeData;
  ExpectOnly(Format('{"action_type_id":%d}', [FActionType]), [FProbeA]);
end;

procedure TSemanticSearchToolTests.DatesNarrowTheGroups;
var
  Response: TJSONObject;
  Applied: TJSONObject;
begin
  AddProbeData;
  ExpectOnly('{"date_from":"2026-01-01","date_to":"2026-03-05"}', [FProbeA, FProbeB]);
  ExpectOnly('{"date_from":"2026-01-01","date_to":"2026-02-28"}', [FProbeA]);
  ExpectOnly('{"date_field":"modified","date_from":"2026-02-01","date_to":"2026-02-01"}', [FProbeA]);
  ExpectOnly('{"date_field":"created","date_from":"2026-03-01","date_to":"2026-03-31"}', [FProbeB]);
  Response := CallJson('filterprobe', '{"date_from":"2026-01-01","date_to":"2026-02-28"}');
  try
    Applied := Response.GetValue<TJSONObject>('filters_applied');
    Assert.AreEqual('created', Applied.GetValue<string>('date_field'), 'created is the default field');
    Assert.AreEqual('2026-01-01', Applied.GetValue<string>('date_from'));
    Assert.AreEqual('2026-02-28', Applied.GetValue<string>('date_to'));
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.DateEchoIsTheLiteralDayAndATimePartIsRefused;
var
  Response: TJSONObject;
  Applied: TJSONObject;
  Text: string;
begin
  AddProbeData;
  Response := CallJson('filterprobe', '{"date_from":"2026-01-31","date_to":"2026-03-01"}');
  try
    Applied := Response.GetValue<TJSONObject>('filters_applied');
    Assert.AreEqual('2026-01-31', Applied.GetValue<string>('date_from'), 'the day is not moved by the time zone');
    Assert.AreEqual('2026-03-01', Applied.GetValue<string>('date_to'));
  finally
    Response.Free;
  end;
  for Text in ['2026-01-31T10:00:00Z', '2026-01-31T00:00:00', '2026-01-31 10:00', '2026-01-31T00:00:00-05:00'] do
  begin
    Assert.IsTrue(FailureJson('filterprobe', '{"date_from":"' + Text + '"}').Contains('date_from'), Text);
    Assert.IsTrue(FailureJson('filterprobe', '{"date_to":"' + Text + '"}').Contains('date_to'), Text);
  end;
end;

procedure TSemanticSearchToolTests.ValuesNarrowTheGroupsAndEchoTheConvertedLimit;
var
  Response: TJSONObject;
  Limit: TJSONObject;
  Values: TJSONArray;
begin
  AddProbeData;
  ExpectOnly('{"values":[{"value_type":"Probe hardness","min":10,"unit":"GPa"}]}', [FProbeA]);
  ExpectOnly('{"values":[{"value_type":"Probe hardness","min":5000,"max":12000}]}', [FProbeA, FProbeB]);
  ExpectOnly('{"values":[{"value_type":"Probe hardness","min":5001,"max":11999}]}', []);
  Response := CallJson('filterprobe',
    '{"values":[{"value_type":"Probe hardness","min":10,"unit":"GPa","rec_type":"TEST_RESULT"}]}');
  try
    Values := Response.GetValue<TJSONObject>('filters_applied').GetValue<TJSONArray>('values');
    Assert.AreEqual(1, Values.Count);
    Limit := Values.Items[0] as TJSONObject;
    Assert.AreEqual('Probe hardness', Limit.GetValue<string>('value_type'));
    Assert.AreEqual('MPa', Limit.GetValue<string>('unit'), 'The unit of the value type');
    Assert.AreEqual(10000.0, Limit.GetValue<Double>('min'), 1e-6, 'The threshold is converted');
    Assert.IsNull(Limit.GetValue('max'));
    Assert.AreEqual('TEST_RESULT', Limit.GetValue<string>('rec_type'));
    Assert.AreEqual('GPa', Limit.GetValue<string>('requested_unit'));
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.UnknownUnitReturnsTheFilterErrorText;
begin
  AddProbeData;
  Assert.AreEqual('Unit "furlong" is not known.',
    FailureJson('filterprobe', '{"values":[{"value_type":"Probe hardness","min":1,"unit":"furlong"}]}'));
end;

procedure TSemanticSearchToolTests.CrossDimensionUnitReturnsTheFilterErrorText;
var
  Message: string;
begin
  AddProbeData;
  Message := FailureJson('filterprobe', '{"values":[{"value_type":"Probe hardness","min":1,"unit":"mm"}]}');
  Assert.IsTrue(Message.Contains('"mm" cannot be converted to "MPa"'), Message);
end;

procedure TSemanticSearchToolTests.InvisibleFolderGivesTheNotFoundText;
var
  Message, Missing: string;
  Foreign: TFolder;
begin
  AddProbeData;
  Foreign := TFolder.Create;
  Foreign.Title := 'Foreign';
  Foreign.CreatedDate := Now;
  Foreign.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Find<TProject>(FProject2).Folders.Add(Foreign);
  FNotebook.Manager.Flush;
  FRegistry.SetScope([FProject1]);
  Message := FailureJson('filterprobe', Format('{"folder_id":%d}', [Foreign.Id]));
  Missing := FailureJson('filterprobe', '{"folder_id":999999}');
  Assert.AreEqual('The folder does not exist or is not available.', Message);
  Assert.AreEqual(Missing, Message, 'A hidden folder and a missing folder read the same');
end;

procedure TSemanticSearchToolTests.BadFilterParametersReturnErrors;
begin
  AddProbeData;
  Assert.IsTrue(FailureJson('filterprobe', '{"date_field":"deleted"}').Contains('date_field'));
  Assert.IsTrue(FailureJson('filterprobe', '{"date_from":"last week"}').Contains('date_from'));
  Assert.IsTrue(FailureJson('filterprobe', '{"date_to":"31.12.2026"}').Contains('date_to'));
  Assert.IsTrue(FailureJson('filterprobe', '{"date_from":"2026-03-01","date_to":"2026-01-01"}')
    .Contains('start date is after the end date'));
  Assert.IsTrue(FailureJson('filterprobe', '{"item_types":["Nonsense"]}').Contains('Nonsense'));
  Assert.IsTrue(FailureJson('filterprobe', '{"levels":["Nonsense"]}').Contains('Nonsense'));
  Assert.IsTrue(FailureJson('filterprobe', '{"item_types":"Testing"}').Contains('item_types'));
  Assert.IsTrue(FailureJson('filterprobe', '{"values":[{"min":1}]}').Contains('value_type'));
  Assert.IsTrue(FailureJson('filterprobe', '{"values":[{"value_type":"Nope","min":1}]}')
    .Contains('Nope'));
  Assert.IsTrue(FailureJson('filterprobe',
    '{"values":[{"value_type":"Probe hardness","min":9,"max":1}]}').Contains('minimum is greater'));
  Assert.IsTrue(FailureJson('filterprobe',
    '{"values":[{"value_type":"Probe hardness","rec_type":"GUESS"}]}').Contains('GUESS'));
end;

procedure TSemanticSearchToolTests.SchemaListsTheFilterParameters;
var
  Tools: TJSONArray;
  Tool: TJSONValue;
  Props, Item: TJSONObject;
  Name: string;
begin
  Tools := FRegistry.GetToolsList;
  try
    for Tool in Tools do
      if Tool.GetValue<string>('name') = 'search_semantic' then
      begin
        Props := Tool.GetValue<TJSONObject>('inputSchema').GetValue<TJSONObject>('properties');
        for Name in ['folder_id', 'item_types', 'levels', 'action_type_id', 'date_field',
          'date_from', 'date_to', 'values'] do
          Assert.IsNotNull(Props.GetValue(Name), Name);
        Item := Props.GetValue<TJSONObject>('values').GetValue<TJSONObject>('items')
          .GetValue<TJSONObject>('properties');
        for Name in ['value_type', 'min', 'max', 'unit', 'rec_type'] do
          Assert.IsNotNull(Item.GetValue(Name), Name);
        Assert.IsTrue(Props.GetValue<TJSONObject>('values').GetValue<string>('description')
          .Contains('inclusive'));
      end;
  finally
    Tools.Free;
  end;
end;

function TSemanticSearchToolTests.AttachDocx(ProjectId, ItemId: Integer;
  const Sentence: string): Int64;
const
  WordNs = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
var
  Manager: TObjectManager;
  Project: TProject;
  Item: TItem;
  FileType: TFileType;
  Attached: unit_Item.TFile;
  Stream: TMemoryStream;
  Zip: TZipFile;
  Bytes: TBytes;
begin
  Manager := FNotebook.Manager;
  Project := Manager.Find<TProject>(ProjectId);
  Item := Manager.Find<TItem>(ItemId);
  FileType := TFileType.Create;
  FileType.Ext := '.docx';
  FileType.CreatedDate := Now;
  Manager.Save(FileType);
  Attached := unit_Item.TFile.Create;
  Attached.FileType := FileType;
  Attached.Title := 'report';
  Attached.Hash := 'x';
  Attached.CreatedDate := Now;
  Attached.Item := Item;
  Manager.Save(Attached);
  Manager.Flush;
  Stream := TMemoryStream.Create;
  try
    Zip := TZipFile.Create;
    try
      Zip.Open(Stream, zmWrite);
      Zip.Add(TEncoding.UTF8.GetBytes('<?xml version="1.0" encoding="UTF-8"?><w:document ' + WordNs +
        '><w:body><w:p><w:r><w:t>' + Sentence + '</w:t></w:r></w:p></w:body></w:document>'),
        'word/document.xml');
      Zip.Close;
    finally
      Zip.Free;
    end;
    SetLength(Bytes, Stream.Size);
    Move(Stream.Memory^, Bytes[0], Stream.Size);
  finally
    Stream.Free;
  end;
  FNotebook.Storage.WriteBytes(AttachmentRelativePath(Project.FileFolder, Item.FolderName,
    Attached.FullName), Bytes);
  Result := Attached.Id;
end;

procedure TSemanticSearchToolTests.FileTextFoundThroughMcp;
var
  FileId: Int64;
  Response: TJSONObject;
  Found, Passage: TJSONValue;
  Group, Hit: TJSONObject;
begin
  FileId := AttachDocx(FProject1, FItem1, 'Cryogenic quenching embrittles the tungsten carbide coating.');
  Response := Call('embrittles carbide', 0, 0);
  try
    Hit := nil;
    Group := nil;
    for Found in Response.GetValue<TJSONArray>('groups') do
      for Passage in Found.GetValue<TJSONArray>('passages') do
        if (Passage.GetValue<string>('field') = 'file_text') and
          (Passage.GetValue<Int64>('file_id') = FileId) then
        begin
          Group := Found as TJSONObject;
          Hit := Passage as TJSONObject;
        end;
    Assert.IsNotNull(Hit, 'The docx text is found');
    Assert.AreEqual(FItem1, Group.GetValue<Integer>('item_id'));
    Assert.IsTrue(Hit.GetValue<string>('snippet').Contains('embrittles'));
    Assert.AreEqual(0, Response.GetValue<TJSONObject>('index').GetValue<Integer>('files_pending'));
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.ShortQueryIncompleteAfterDeadlineDuringExtraction;
var
  I: Integer;
  Index: TJSONObject;
  Response: TJSONObject;
  Extractor: TCountingExtractor;
  ExtractorRef: ITextExtractor;
begin
  for I := 1 to 30 do
    AttachDocx(FProject1, FItem1, 'Extraction deadline sentence number ' + IntToStr(I));
  Extractor := TCountingExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.OnCall :=
    procedure(Call: Integer)
    begin
      if Call = 1 then
        FService.CancelSync;
    end;
  FService.Registry.Register(ExtractorRef, ['.docx']);
  Call('deadline sentence', 0, 0).Free;
  Response := Call(' a ', 0, 0);
  try
    Index := Response.GetValue<TJSONObject>('index');
    Assert.IsFalse(Index.GetValue<Boolean>('complete'));
    Assert.IsTrue(Index.GetValue<Integer>('files_pending') > 0);
  finally
    Response.Free;
  end;
  Extractor.OnCall := nil;
  Call('deadline sentence', 0, 0).Free;
  Response := Call(' a ', 0, 0);
  try
    Index := Response.GetValue<TJSONObject>('index');
    Assert.IsTrue(Index.GetValue<Boolean>('complete'));
    Assert.AreEqual(0, Index.GetValue<Integer>('files_pending'));
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.ReturnsHitsWithIndexStatus;
var
  Response: TJSONObject;
  Group: TJSONObject;
  Found: TJSONValue;
  Passage: TJSONValue;
  Passages: TJSONArray;
  Index: TJSONObject;
  HasDescription: Boolean;
  Count: Integer;
begin
  Response := Call('annealing roughness', 0, 0);
  try
    Assert.IsNull(Response.GetValue('hits'), 'the flat list is gone');
    Group := nil;
    Count := 0;
    for Found in Response.GetValue<TJSONArray>('groups') do
    begin
      if Found.GetValue<Integer>('item_id') = FItem1 then
      begin
        Group := Found as TJSONObject;
        Inc(Count);
      end;
    end;
    Assert.AreEqual(1, Count, 'one group per item');
    Assert.IsNotNull(Group, 'The query finds the item');
    Assert.AreEqual(FProject1, Group.GetValue<Integer>('project_id'));
    Assert.AreEqual('Mo/Si multilayer', Group.GetValue<string>('item_title'));
    Assert.AreEqual('Synthetic multilayers', Group.GetValue<string>('project_path'));
    Assert.IsNotNull(Group.GetValue('score'));
    Assert.IsTrue(Group.GetValue<TJSONArray>('sources').Count > 0);
    Passages := Group.GetValue<TJSONArray>('passages');
    Assert.IsTrue((Passages.Count >= 1) and (Passages.Count <= 3));
    HasDescription := False;
    for Passage in Passages do
    begin
      Assert.IsNotNull(Passage.GetValue<TJSONValue>('score'));
      Assert.IsNotNull(Passage.GetValue<TJSONValue>('file_id'));
      if (Passage.GetValue<string>('field') = 'description') and
        Passage.GetValue<string>('snippet').Contains('annealing') then
        HasDescription := True;
    end;
    Assert.IsTrue(HasDescription, 'The query finds the description');
    Index := Response.GetValue<TJSONObject>('index');
    Assert.IsTrue(Index.GetValue<Boolean>('complete'));
    Assert.IsTrue(Index.GetValue<Integer>('indexed_passages') > 0);
    Assert.AreEqual(0, Index.GetValue<Integer>('pending_passages'));
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.ScopedSessionNeverLeaks;
var
  Response: TJSONObject;
begin
  FRegistry.SetScope([FProject1]);
  Response := Call('tungstenite zirconia hardness', 0, 0);
  try
    Assert.IsFalse(HasHitFor(Response, FProject2), 'No hit from outside the scope');
  finally
    Response.Free;
  end;
  Assert.IsTrue(Failure('tungstenite zirconia hardness', FProject2, 0)
    .Contains('Access denied'), 'An out-of-scope project is refused');
  FRegistry.SetScope(nil);
  Response := Call('tungstenite zirconia hardness', FProject2, 0);
  try
    Assert.IsTrue(HasHitFor(Response, FProject2), 'The same query finds it unscoped');
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.UnavailableWhenNoService;
var
  Message: string;
begin
  Rebuild(False);
  Message := Failure('annealing roughness', 0, 0);
  Assert.IsTrue(Message.Contains(UnavailableCode), Message);
  Assert.IsTrue(Message.Contains('Tools > Semantic Search Setup'), Message);
end;

procedure TSemanticSearchToolTests.RuntimeFailureKeepsCause;
var
  Message: string;
begin
  FreeAndNil(FService);
  FService := TSemanticSearchService.Create(TPath.Combine(FRoot, 'broken.sqlite'),
    function: ITextEmbedder
    begin
      raise Exception.Create('model file is corrupt');
    end, nil, TNotebookDocumentProvider.Create(FNotebook.Manager), '');
  Rebuild(True);
  Message := Failure('annealing roughness', 0, 0);
  Assert.IsTrue(Message.Contains('model file is corrupt'), Message);
  Assert.IsTrue(Message.Contains(UnavailableCode), Message);
  Assert.IsFalse(Message.Contains('is not installed'), Message);
end;

procedure TSemanticSearchToolTests.ShortQueryReadsNothing;
var
  Response: TJSONObject;
begin
  Response := Call(' a ', 0, 0);
  try
    Assert.AreEqual<NativeInt>(0, Response.GetValue<TJSONArray>('groups').Count);
    Assert.AreEqual(0, Response.GetValue<TJSONObject>('index').GetValue<Integer>('indexed_passages'),
      'No passage was read or indexed');
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.UseReranker;
begin
  FreeAndNil(FRegistry);
  FreeAndNil(FService);
  FCross := TFakeCrossEncoder.Create;
  FCrossRef := FCross;
  FService := TSemanticSearchService.Create(TPath.Combine(FRoot, 'ranked.sqlite'),
    function: ITextEmbedder
    begin
      Result := FEmbedderRef;
    end,
    function: ICrossEncoder
    begin
      Result := FCrossRef;
    end, TNotebookDocumentProvider.Create(FNotebook.Manager), '');
  Rebuild(True);
end;

function TSemanticSearchToolTests.GroupOrder(Response: TJSONObject): TArray<Integer>;
var
  Group: TJSONValue;
begin
  Result := nil;
  for Group in Response.GetValue<TJSONArray>('groups') do
    Result := Result + [Group.GetValue<Integer>('item_id')];
end;

procedure TSemanticSearchToolTests.RerankedIsFalseWithoutAReranker;
var
  Response: TJSONObject;
begin
  Response := Call('zirconia hardness', 0, 0);
  try
    Assert.IsTrue(Response.GetValue<TJSONArray>('groups').Count > 0);
    Assert.IsFalse(Response.GetValue<Boolean>('reranked'));
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.RerankerReordersTheGroupsAndSetsTheFlag;
var
  Plain, Ranked: TJSONObject;
  Before, After: TArray<Integer>;
  I: Integer;
begin
  Plain := Call('zirconia hardness', 0, 0);
  try
    Before := GroupOrder(Plain);
  finally
    Plain.Free;
  end;
  Assert.AreEqual<NativeInt>(2, Length(Before));
  UseReranker;
  Ranked := Call('zirconia hardness', 0, 0);
  try
    After := GroupOrder(Ranked);
    Assert.IsTrue(Ranked.GetValue<Boolean>('reranked'));
  finally
    Ranked.Free;
  end;
  Assert.AreEqual<NativeInt>(2, Length(After));
  for I := 0 to 1 do
    Assert.AreEqual(Before[1 - I], After[I], 'the fake reranker reverses the order');
  Assert.AreEqual(1, FCross.Calls);
end;

procedure TSemanticSearchToolTests.ShortQueryReportsRerankedFalse;
var
  Response: TJSONObject;
begin
  UseReranker;
  Response := Call(' a ', 0, 0);
  try
    Assert.IsFalse(Response.GetValue<Boolean>('reranked'));
    Assert.AreEqual(0, FCross.Calls);
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.RerankerFailureKeepsTheHybridGroupsAndFlagFalse;
var
  Plain, Failed: TJSONObject;
  Before, After: TArray<Integer>;
begin
  Plain := Call('zirconia hardness', 0, 0);
  try
    Before := GroupOrder(Plain);
  finally
    Plain.Free;
  end;
  UseReranker;
  FCross.OnScore :=
    procedure
    begin
      raise ECrossEncoderError.Create('reranker failed');
    end;
  Failed := Call('zirconia hardness', 0, 0);
  try
    After := GroupOrder(Failed);
    Assert.IsFalse(Failed.GetValue<Boolean>('reranked'));
  finally
    Failed.Free;
  end;
  Assert.AreEqual<NativeInt>(Length(Before), Length(After));
  Assert.AreEqual(Before[0], After[0]);
  Assert.AreEqual(Before[1], After[1]);
end;

procedure TSemanticSearchToolTests.DescriptionMentionsReranking;
var
  Tools: TJSONArray;
  Tool: TJSONValue;
  Found: Boolean;
begin
  Found := False;
  Tools := FRegistry.GetToolsList;
  try
    for Tool in Tools do
      if Tool.GetValue<string>('name') = 'search_semantic' then
      begin
        Found := True;
        Assert.IsTrue(Tool.GetValue<string>('description').Contains('reranked'),
          'the description names the reranked flag');
      end;
  finally
    Tools.Free;
  end;
  Assert.IsTrue(Found);
end;

procedure TSemanticSearchToolTests.IncompleteIndexReported;
var
  I: Integer;
  First, Second: TJSONObject;
begin
  for I := 1 to 100 do
    AddItem(FProject1, 'Bulk sample ' + IntToStr(I), 'bulk filler number ' + IntToStr(I));
  FEmbedder.BatchDelayMs := 20;
  SemanticSyncDeadlineMs := 30;
  First := Call('bulk filler', 0, 0);
  try
    Assert.IsFalse(First.GetValue<TJSONObject>('index').GetValue<Boolean>('complete'));
    Assert.IsTrue(First.GetValue<TJSONObject>('index').GetValue<Integer>('pending_passages') > 0);
  finally
    First.Free;
  end;
  SemanticSyncDeadlineMs := 60000;
  Second := Call('bulk filler', 0, 0);
  try
    Assert.IsTrue(Second.GetValue<TJSONObject>('index').GetValue<Boolean>('complete'));
    Assert.AreEqual(0, Second.GetValue<TJSONObject>('index').GetValue<Integer>('pending_passages'));
  finally
    Second.Free;
  end;
end;

procedure TSemanticSearchToolTests.RejectsTopKOutOfRange;
begin
  Assert.IsTrue(Failure('annealing roughness', 0, 51).Contains('top_k'));
end;

procedure TSemanticSearchToolTests.ListedInToolsList;
var
  Tools: TJSONArray;
  Tool: TJSONValue;
  Schema, Props: TJSONObject;
  Found: Boolean;
begin
  Found := False;
  Tools := FRegistry.GetToolsList;
  try
    for Tool in Tools do
      if Tool.GetValue<string>('name') = 'search_semantic' then
      begin
        Found := True;
        Schema := Tool.GetValue<TJSONObject>('inputSchema');
        Props := Schema.GetValue<TJSONObject>('properties');
        Assert.IsNotNull(Props.GetValue('query'));
        Assert.IsNotNull(Props.GetValue('top_k'));
        Assert.IsNotNull(Props.GetValue('project_id'));
        Assert.AreEqual('query', Schema.GetValue<TJSONArray>('required').Items[0].Value);
      end;
  finally
    Tools.Free;
  end;
  Assert.IsTrue(Found, 'search_semantic is listed');
  Assert.AreEqual(tscProjectScoped, FRegistry.ScopingOf('search_semantic'));
end;

procedure TSemanticSearchToolTests.NilVisibleSetMeansEveryProject;
var
  Response: TJSONObject;
begin
  UsePolicy(True);
  Response := Call('interface roughness annealing', 0, 0);
  try
    Assert.IsTrue(HasHitFor(Response, FProject1), 'Project 1 is found');
  finally
    Response.Free;
  end;
  Response := Call('zirconia dopant hardness', 0, 0);
  try
    Assert.IsTrue(HasHitFor(Response, FProject2), 'Project 2 is found');
  finally
    Response.Free;
  end;
  Response := Call('zirconia dopant hardness', FProject2, 0);
  try
    Assert.IsTrue(HasHitFor(Response, FProject2), 'A project_id filter works');
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.EmptyVisibleSetGivesNoGroup;
var
  Response: TJSONObject;
begin
  UsePolicy(False);
  Response := Call('zirconia dopant hardness', 0, 0);
  try
    Assert.AreEqual(0, Response.GetValue<TJSONArray>('groups').Count);
  finally
    Response.Free;
  end;
end;

procedure TSemanticSearchToolTests.RemoteSearchUsesTheInterfaceWithoutSync;
var
  Response, Group, Index, Applied: TJSONObject;
  Request: TSemanticSearchRequest;
begin
  UseFake(True);
  FFake.Outcome.Groups := [FakeGroup(FItem1, FProject1, 'remote snippet')];
  FFake.Outcome.Reranked := True;
  FFake.Outcome.IndexStatus.LastSyncComplete := True;
  FFake.Outcome.IndexStatus.IndexedPassages := 7;
  FFake.Outcome.IndexStatus.PendingPassages := 2;
  FFake.Outcome.IndexStatus.FilesDone := 3;
  FFake.Outcome.IndexStatus.FilesTotal := 5;
  FFake.Outcome.FiltersApplied := '{"item_types":["Specimen"]}';
  Response := CallJson('remote query', '{"item_types":["Specimen"],"top_k":7}');
  try
    Assert.AreEqual(1, Response.GetValue<TJSONArray>('groups').Count);
    Group := Response.GetValue<TJSONArray>('groups').Items[0] as TJSONObject;
    Assert.AreEqual(FItem1, Group.GetValue<Integer>('item_id'));
    Assert.AreEqual('Mo/Si multilayer', Group.GetValue<string>('item_title'));
    Assert.AreEqual('remote snippet',
      Group.GetValue<TJSONArray>('passages').Items[0].GetValue<string>('snippet'));
    Assert.IsTrue(Response.GetValue<Boolean>('reranked'));
    Index := Response.GetValue<TJSONObject>('index');
    Assert.IsTrue(Index.GetValue<Boolean>('complete'));
    Assert.AreEqual(7, Index.GetValue<Integer>('indexed_passages'));
    Assert.AreEqual(2, Index.GetValue<Integer>('pending_passages'));
    Assert.AreEqual(2, Index.GetValue<Integer>('files_pending'));
    Applied := Response.GetValue<TJSONObject>('filters_applied');
    Assert.AreEqual('Specimen', Applied.GetValue<TJSONArray>('item_types').Items[0].Value);
  finally
    Response.Free;
  end;
  Assert.AreEqual<NativeInt>(1, Length(FFake.Requests));
  Request := FFake.Requests[0];
  Assert.AreEqual('remote query', Request.Query);
  Assert.AreEqual(7, Request.TopK);
  Assert.IsTrue(Request.Rerank);
  Assert.AreEqual<NativeInt>(1, Length(Request.Filter.ItemTypes));
  Assert.AreEqual('Specimen', Request.Filter.ItemTypes[0]);
  Assert.IsTrue(TArray.Contains<Integer>(Request.VisibleProjectIds, FProject1));
  Assert.IsTrue(TArray.Contains<Integer>(Request.VisibleProjectIds, FProject2));
  Assert.AreEqual(0, FService.Status.IndexedPassages, 'a remote search never syncs the local index');
  Assert.IsFalse(FService.Status.LastSyncComplete);
end;

procedure TSemanticSearchToolTests.LocalSearchSyncsTheIndexFirst;
begin
  UseFake(False);
  Call('annealing roughness', 0, 0).Free;
  Assert.IsTrue(FService.Status.IndexedPassages > 0, 'a local search syncs the index first');
  Assert.AreEqual<NativeInt>(1, Length(FFake.Requests));
end;

procedure TSemanticSearchToolTests.RemoteUnavailableKeepsTheCause;
var
  Message: string;
begin
  UseFake(True);
  FFake.Failure := 'search server is down';
  Message := Failure('annealing roughness', 0, 0);
  Assert.IsTrue(Message.Contains('Semantic search could not start: search server is down'), Message);
  Assert.IsTrue(Message.Contains(UnavailableCode), Message);
end;

procedure TSemanticSearchToolTests.ShortQueryReadsTheInterfaceStatus;
var
  Response, Index: TJSONObject;
begin
  UseFake(True);
  FFake.Current.State := ssSyncing;
  FFake.Current.FilesDone := 1;
  FFake.Current.FilesTotal := 4;
  FFake.Current.IndexedPassages := 5;
  FFake.Current.PendingPassages := 6;
  FFake.Current.LastSyncComplete := True;
  Response := Call(' a ', 0, 0);
  try
    Assert.AreEqual(0, Response.GetValue<TJSONArray>('groups').Count);
    Assert.IsFalse(Response.GetValue<Boolean>('reranked'));
    Index := Response.GetValue<TJSONObject>('index');
    Assert.IsFalse(Index.GetValue<Boolean>('complete'), 'a running sync is not complete');
    Assert.AreEqual(5, Index.GetValue<Integer>('indexed_passages'));
    Assert.AreEqual(6, Index.GetValue<Integer>('pending_passages'));
    Assert.AreEqual(3, Index.GetValue<Integer>('files_pending'));
  finally
    Response.Free;
  end;
  Assert.AreEqual<NativeInt>(0, Length(FFake.Requests), 'a short query does not search');
end;

procedure TSemanticSearchToolTests.RemoteGroupOutsideTheScopeIsDropped;
var
  Response: TJSONObject;
begin
  UseFake(True);
  FFake.Outcome.Groups := [FakeGroup(FItem1, FProject1, 'first'), FakeGroup(FItem2, FProject2, 'second')];
  FRegistry.SetScope([FProject1]);
  Response := Call('remote query', 0, 0);
  try
    Assert.IsTrue(HasHitFor(Response, FProject1));
    Assert.IsFalse(HasHitFor(Response, FProject2), 'a group outside the scope is dropped');
  finally
    Response.Free;
  end;
  Assert.IsFalse(TArray.Contains<Integer>(FFake.Requests[0].VisibleProjectIds, FProject2),
    'the request carries only the scope');
end;

procedure TSemanticSearchToolTests.InvalidFilterIsRejectedBeforeTheLocalSync;
begin
  AddProbeData;
  Assert.AreEqual('Unit "furlong" is not known.',
    FailureJson('filterprobe', '{"values":[{"value_type":"Probe hardness","min":1,"unit":"furlong"}]}'));
  Assert.AreEqual(0, FService.Status.IndexedPassages, 'the index was not synchronized');
  Assert.IsFalse(FService.Status.LastSyncComplete, 'no sync ran');
  Call('filterprobe', 0, 0).Free;
  Assert.IsTrue(FService.Status.IndexedPassages > 0, 'a valid request syncs the same index');
end;

initialization
  TDUnitX.RegisterTestFixture(TSemanticSearchToolTests);

end.
