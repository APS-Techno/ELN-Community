unit test_ReadOnlySweep;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  DUnitX.TestFramework,
  Vcl.Forms,
  upfVisualClasses,
  unit_LocalNotebook, unit_MCPTools, unit_NotebookStorage, unit_PluginHost,
  unit_Project, unit_Item, unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ColumnarDataPlugin, unit_SemanticSearchApi, test_SearchDoubles;

type
  TWriteRefusingStorage = class(TInterfacedObject, INotebookStorage)
  private
    FInner: INotebookStorage;
  public
    constructor Create(const Inner: INotebookStorage);
    procedure MoveFile(const OldPath, NewPath: string);
    function ReadBytes(const RelativePath: string): TBytes;
    procedure WriteBytes(const RelativePath: string; const Data: TBytes);
    procedure CopyIn(const SourcePath, RelativePath: string);
    procedure CopyOut(const RelativePath, TargetPath: string);
    function Exists(const RelativePath: string): Boolean;
    procedure DeleteFile(const RelativePath: string);
  end;

  TSweepJsonPlugin = class(TupfVisualPlugin, IViewerPlugin,
    IDetailedInfoProvider, IKeyValueProvider, IReaderIdentity)
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
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

  [TestFixture]
  TReadOnlySweepTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FHost: TPluginHost;
    FJsonPlugin: TSweepJsonPlugin;
    FColumnarPlugin: TELNColumnarDataViewerPlugin;
    FSearch: TFakeSemanticSearch;
    FSearchRef: ISemanticSearch;
    FRegistry: TToolRegistry;
    FP, FQ, FItem, FQItem, FHypothesis, FSeries, FWikiItem, FValueId: Integer;
    FJsonFile, FCsvFile: Int64;
    function SeedProject(const Title: string): Integer;
    function DeepCheck(const Tool: string; Response: TJSONObject): string;
    function SeedItem(ProjectId: Integer; const Title: string): Integer;
    function SeedFileType(const Ext: string): Integer;
    function SeedFile(ItemId, FileTypeId: Integer; const Title: string;
      const Content: string): Int64;
    procedure SeedHypothesis;
    procedure SeedSeries;
    procedure SeedValueAndMapping(SeedRegistry: TToolRegistry);
    function SeedContext(const Storage: INotebookStorage): TToolContext;
    function ParamsFor(const Tool: string): string;
    function RefusalOf(const Tool, Json: string): string;
    function ExecuteJson(Registry: TToolRegistry; const Tool, Json: string): TJSONObject;
    function WriteToolNames: TArray<string>;
  public
    [SetupFixture] procedure SetupFixture;
    [TeardownFixture] procedure TeardownFixture;
    [Test] procedure EveryReadToolRunsWithoutWrites;
    [Test] procedure EveryWriteToolIsRefused;
    [Test] procedure ScopeRefusalUnchangedInReadOnly;
    [Test] procedure ListProjectsReturnsOnlyScope;
    [Test] procedure DatabaseRejectsWrites;
  end;

implementation

uses
  System.IOUtils, System.StrUtils, System.RegularExpressions,
  Aurelius.Drivers.Interfaces,
  upfIntf,
  unit_ProjectModel, unit_ItemTypes, unit_FileType, unit_ValueType,
  unit_Hypothesis, unit_HypothesisRun, unit_ReaderValueMapping, unit_SeriesTable,
  unit_SeriesModel,
  unit_ToolCatalog, unit_ReadToolAllowlist;

const
  JSON_READER_ID = 'synthetic.sweep-reader';
  JSON_BODY = '{"warmup_seconds":1200,"kind":"synthetic"}';
  CSV_BODY = 'x,y,label'#13#10'1,10,a'#13#10'2,20,b'#13#10'3,30,c'#13#10;

constructor TWriteRefusingStorage.Create(const Inner: INotebookStorage);
begin
  inherited Create;
  FInner := Inner;
end;

procedure TWriteRefusingStorage.MoveFile(const OldPath, NewPath: string);
begin
  raise EAssertionFailed.CreateFmt('Storage MoveFile(%s, %s) in a read-only sweep',
    [OldPath, NewPath]);
end;

function TWriteRefusingStorage.ReadBytes(const RelativePath: string): TBytes;
begin
  Result := FInner.ReadBytes(RelativePath);
end;

procedure TWriteRefusingStorage.WriteBytes(const RelativePath: string;
  const Data: TBytes);
begin
  raise EAssertionFailed.CreateFmt('Storage WriteBytes(%s) in a read-only sweep',
    [RelativePath]);
end;

procedure TWriteRefusingStorage.CopyIn(const SourcePath, RelativePath: string);
begin
  raise EAssertionFailed.CreateFmt('Storage CopyIn(%s, %s) in a read-only sweep',
    [SourcePath, RelativePath]);
end;

procedure TWriteRefusingStorage.CopyOut(const RelativePath, TargetPath: string);
begin
  FInner.CopyOut(RelativePath, TargetPath);
end;

function TWriteRefusingStorage.Exists(const RelativePath: string): Boolean;
begin
  Result := FInner.Exists(RelativePath);
end;

procedure TWriteRefusingStorage.DeleteFile(const RelativePath: string);
begin
  raise EAssertionFailed.CreateFmt('Storage DeleteFile(%s) in a read-only sweep',
    [RelativePath]);
end;

function TSweepJsonPlugin.GetFrame: TFrame;
begin
  Result := nil;
end;

function TSweepJsonPlugin.GetCaption: string;
begin
  Result := 'Synthetic sweep reader';
end;

function TSweepJsonPlugin.GetParams: TPluginParams;
begin
  Result := Default(TPluginParams);
  Result.PType := ptFile;
  Result.Ext := '.sweepjson';
end;

function TSweepJsonPlugin.LoadFromFile(const FileName: string): Boolean;
var
  Parsed: TJSONValue;
begin
  FData := TFile.ReadAllText(FileName, TEncoding.UTF8);
  Parsed := TJSONObject.ParseJSONValue(FData);
  try
    Result := Parsed is TJSONObject;
  finally
    Parsed.Free;
  end;
end;

function TSweepJsonPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
begin
  Result := False;
end;

procedure TSweepJsonPlugin.DisplayText(const Caption, Text: string);
begin
end;

function TSweepJsonPlugin.GetDetailedInfo: string;
begin
  Result := FData;
end;

function TSweepJsonPlugin.GetKeyValues: TArray<TPluginKeyValue>;
var
  Parsed: TJSONObject;
begin
  Parsed := TJSONObject.ParseJSONValue(FData) as TJSONObject;
  try
    SetLength(Result, 1);
    Result[0] := Default(TPluginKeyValue);
    Result[0].Name := 'Warmup';
    Result[0].Value := Parsed.GetValue<Double>('warmup_seconds');
    Result[0].Units := 's';
    Result[0].RecType := prCondition;
  finally
    Parsed.Free;
  end;
end;

function TSweepJsonPlugin.GetReaderId: string;
begin
  Result := JSON_READER_ID;
end;

function TSweepJsonPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TReadOnlySweepTests.SeedProject(const Title: string): Integer;
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

function TReadOnlySweepTests.SeedItem(ProjectId: Integer;
  const Title: string): Integer;
var
  Item: TItem;
begin
  Item := TItem.Create;
  Item.Title := Title;
  Item.ProjectID := ProjectId;
  Item.Type_ := TItemType.Other;
  Item.Level := TItemLevel.Proc;
  Item.CreatedBy := FNotebook.Principal.Id;
  Item.CreatedDate := Now;
  FNotebook.Manager.Save(Item);
  FNotebook.Manager.Flush;
  Result := Item.Id;
  FNotebook.Manager.Evict(Item);
  Item.Free;
end;

function TReadOnlySweepTests.SeedFileType(const Ext: string): Integer;
var
  FileType: TFileType;
begin
  FileType := TFileType.Create;
  FileType.Ext := Ext;
  FileType.CreatedDate := Now;
  FNotebook.Manager.Save(FileType);
  FNotebook.Manager.Flush;
  Result := FileType.Id;
end;

function TReadOnlySweepTests.SeedFile(ItemId, FileTypeId: Integer;
  const Title, Content: string): Int64;
var
  Item: TItem;
  FileRow: unit_Item.TFile;
  Project: TProject;
begin
  Item := FNotebook.Manager.Find<TItem>(ItemId);
  Project := FNotebook.Manager.Find<TProject>(Item.ProjectID);
  FileRow := unit_Item.TFile.Create;
  FileRow.Title := Title;
  FileRow.Item := Item;
  FileRow.FileType := FNotebook.Manager.Find<TFileType>(FileTypeId);
  FileRow.CreatedBy := FNotebook.Principal.Id;
  FileRow.CreatedDate := Now;
  Item.Files.Add(FileRow);
  FNotebook.Manager.Flush;
  FNotebook.Storage.WriteBytes(Format('Projects\%s\%s\%s',
    [Project.FileFolder, Item.FolderName, FileRow.FullName]),
    TEncoding.UTF8.GetBytes(Content));
  Result := FileRow.Id;
end;

procedure TReadOnlySweepTests.SeedSeries;
var
  Model: TSeriesModel;
  Plan: TSeriesPlan;
  PowerType: TValueType;
begin
  PowerType := TValueType.Create;
  PowerType.Symbol := 'P';
  PowerType.Title := 'Sweep power';
  PowerType.Units := 'W';
  PowerType.CreatedDate := Now;
  PowerType.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Save(PowerType);
  FNotebook.Manager.Flush;
  Plan := Default(TSeriesPlan);
  SetLength(Plan.Factors, 1);
  Plan.Factors[0].ValueTypeId := PowerType.Id;
  Plan.Factors[0].RangeMin := 100.0;
  Plan.Factors[0].RangeMax := 300.0;
  Model := TSeriesModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    FSeries := Model.CreateSeries(FNotebook.Principal, FP, 'Sweep series', '',
      Plan, [[100.0], [200.0]]);
    Model.LinkToSlot(FNotebook.Principal, FSeries,
      Model.GetPlan(FNotebook.Principal, FSeries).Slots[0].SlotId, FItem);
  finally
    Model.Free;
  end;
end;

procedure TReadOnlySweepTests.SeedHypothesis;
var
  H: THypothesis;
  Run: THypothesisRun;
begin
  H := THypothesis.Create;
  H.ProjectId := FP;
  H.Title := 'Sweep expectation';
  H.Statement := 'Synthetic statement';
  H.CreatedBy := FNotebook.Principal.Id;
  H.CreatedDate := Now;
  FNotebook.Manager.Save(H);
  FNotebook.Manager.Flush;
  H.Status := hsApproved;
  FNotebook.Manager.Flush;
  FHypothesis := H.Id;
  Run := THypothesisRun.Create;
  Run.HypothesisId := FHypothesis;
  Run.ItemId := FItem;
  Run.Role := hrrRun;
  Run.AddedBy := FNotebook.Principal.Id;
  Run.AddedDate := Now;
  FNotebook.Manager.Save(Run);
  FNotebook.Manager.Flush;
end;

function TReadOnlySweepTests.ExecuteJson(Registry: TToolRegistry; const Tool,
  Json: string): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(Json) as TJSONObject;
  try
    Result := Registry.Execute(Tool, Params);
  finally
    Params.Free;
  end;
end;

procedure TReadOnlySweepTests.SeedValueAndMapping(SeedRegistry: TToolRegistry);
var
  ValueType: TValueType;
  Mapping: TReaderValueMapping;
  Response: TJSONObject;
begin
  ValueType := TValueType.Create;
  ValueType.Symbol := 'w';
  ValueType.Title := 'Sweep warmup';
  ValueType.Units := 's';
  ValueType.CreatedDate := Now;
  ValueType.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Save(ValueType);
  FNotebook.Manager.Flush;
  Mapping := TReaderValueMapping.Create;
  Mapping.ReaderId := JSON_READER_ID;
  Mapping.KeyPattern := 'Warmup';
  Mapping.ReaderUnits := 's';
  Mapping.ValueType := ValueType;
  Mapping.Factor := 1;
  Mapping.LabelText := 'Warmup';
  FNotebook.Manager.Save(Mapping);
  FNotebook.Manager.Flush;
  Response := ExecuteJson(SeedRegistry, 'add_values', Format(
    '{"values":[{"item_id":%d,"value_type_id":%d,"value":1200,' +
    '"source_file_id":%d,"reader_id":"%s","reader_version":"1",' +
    '"key_name":"Warmup","reader_units":"s","conversion_factor":1}]}',
    [FItem, ValueType.Id, FJsonFile, JSON_READER_ID]));
  try
    FValueId := Response.GetValue<TJSONArray>('values').Items[0].GetValue<Integer>('id');
  finally
    Response.Free;
  end;
  Assert.IsTrue(FValueId > 0, 'add_values stored the reader value');
end;

function TReadOnlySweepTests.SeedContext(const Storage: INotebookStorage): TToolContext;
begin
  Result := Default(TToolContext);
  Result.Manager := FNotebook.Manager;
  Result.User := FNotebook.Principal;
  Result.AccessPolicy := FNotebook.AccessPolicy;
  Result.Storage := Storage;
  Result.PluginHost := FHost;
  Result.SemanticSearch := FSearchRef;
end;

procedure TReadOnlySweepTests.SetupFixture;
var
  SeedRegistry: TToolRegistry;
  JsonType, CsvType: Integer;
  Response: TJSONObject;
  Statement: IDBStatement;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-ReadOnlySweep-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Sweep fixture', 'fixture-password');
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'plugins'));
  FHost := TPluginHost.Create(TPath.Combine(FRoot, 'plugins'));
  FJsonPlugin := TSweepJsonPlugin.CreateNew(nil);
  (ApplicationServices as IupfCommandServices).RegisterPlugin(FJsonPlugin);
  FColumnarPlugin := TELNColumnarDataViewerPlugin.Create(nil);
  (ApplicationServices as IupfCommandServices).RegisterPlugin(FColumnarPlugin);
  FSearch := TFakeSemanticSearch.Create;
  FSearchRef := FSearch;
  FSearch.Remote := True;

  FP := SeedProject('Sweep project P');
  FQ := SeedProject('Sweep project Q');
  FItem := SeedItem(FP, 'Sweep item I');
  FQItem := SeedItem(FQ, 'Sweep item in Q');
  JsonType := SeedFileType('.sweepjson');
  CsvType := SeedFileType('.csv');
  SeedFileType('.md');
  FJsonFile := SeedFile(FItem, JsonType, 'sweep', JSON_BODY);
  FCsvFile := SeedFile(FItem, CsvType, 'table', CSV_BODY);
  SeedHypothesis;
  SeedSeries;

  SeedRegistry := TToolRegistry.Create(SeedContext(FNotebook.Storage));
  try
    RegisterAllTools(SeedRegistry);
    SeedValueAndMapping(SeedRegistry);
    Response := ExecuteJson(SeedRegistry, 'wiki_create_page', Format(
      '{"project_id":%d,"section":"Analysis","title":"Sweep page",' +
      '"body_md":"interface roughness notes"}', [FP]));
    try
      FWikiItem := Response.GetValue<Integer>('item_id');
    finally
      Response.Free;
    end;
  finally
    SeedRegistry.Free;
  end;

  FSearch.Outcome.Groups := [FakeGroup(FItem, FP, 'sweep snippet')];

  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('PRAGMA query_only = ON');
  Statement.Execute;

  FRegistry := TToolRegistry.Create(
    SeedContext(TWriteRefusingStorage.Create(FNotebook.Storage)));
  RegisterAllTools(FRegistry);
  FRegistry.SetScope([FP]);
  FRegistry.EnterReadOnly;
end;

procedure TReadOnlySweepTests.TeardownFixture;
var
  Statement: IDBStatement;
begin
  FreeAndNil(FRegistry);
  if FNotebook <> nil then
  begin
    Statement := FNotebook.Connection.CreateStatement;
    Statement.SetSQLCommand('PRAGMA query_only = OFF');
    Statement.Execute;
    Statement := nil;
  end;
  FSearchRef := nil;
  FSearch := nil;
  FreeAndNil(FColumnarPlugin);
  FreeAndNil(FJsonPlugin);
  FreeAndNil(FHost);
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TReadOnlySweepTests.ParamsFor(const Tool: string): string;
begin
  if MatchStr(Tool, ['get_audit_log', 'list_action_types', 'list_audit_rules',
    'list_equipment', 'list_file_types', 'list_hypotheses', 'list_projects',
    'list_tags', 'list_users', 'list_value_types', 'query_values',
    'report_value_issues']) then
    Exit('{}');
  if MatchStr(Tool, ['check_storage', 'correlate_values', 'get_hypothesis_tree',
    'get_project_stats', 'list_folders', 'list_items', 'list_series']) then
    Exit(Format('{"project_id":%d}', [FP]));
  if MatchStr(Tool, ['get_comments', 'get_item', 'get_item_links',
    'get_item_tags', 'get_protocols', 'get_signatures', 'get_values',
    'list_files', 'check_value_drift']) then
    Exit(Format('{"item_id":%d}', [FItem]));
  if MatchStr(Tool, ['extract_file_data', 'extract_file_key_values']) then
    Exit(Format('{"file_id":%d}', [FJsonFile]));
  if Tool = 'list_file_columns' then
    Exit(Format('{"file_id":%d}', [FCsvFile]));
  if Tool = 'get_file_columns' then
    Exit(Format('{"file_id":%d,"columns":[0,1]}', [FCsvFile]));
  if Tool = 'find_hypotheses_for_item' then
    Exit(Format('{"item_ids":[%d]}', [FItem]));
  if Tool = 'get_series_table' then
    Exit(Format('{"series_id":%d}', [FSeries]));
  if Tool = 'get_hypothesis' then
    Exit(Format('{"hypothesis_id":%d}', [FHypothesis]));
  if Tool = 'search' then
    Exit('{"query":"sweep"}');
  if Tool = 'search_semantic' then
    Exit('{"query":"interface roughness"}');
  if Tool = 'wiki_get_page' then
    Exit(Format('{"item_id":%d}', [FWikiItem]));
  raise Exception.CreateFmt('No sweep parameters for read tool "%s"', [Tool]);
end;

function TReadOnlySweepTests.RefusalOf(const Tool, Json: string): string;
var
  Response: TJSONObject;
begin
  Result := '';
  try
    Response := ExecuteJson(FRegistry, Tool, Json);
    Response.Free;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

function TReadOnlySweepTests.WriteToolNames: TArray<string>;
var
  Full: TToolRegistry;
  List: TJSONArray;
  Row: TJSONValue;
  Name: string;
  IsRead: Boolean;
  Allowed: string;
begin
  Result := nil;
  Full := TToolRegistry.Create(Default(TToolContext));
  try
    RegisterAllTools(Full);
    List := Full.GetToolsList;
    try
      for Row in List do
      begin
        Name := Row.GetValue<string>('name');
        IsRead := False;
        for Allowed in READ_TOOL_NAMES do
          if Allowed = Name then
            IsRead := True;
        if not IsRead then
          Result := Result + [Name];
      end;
    finally
      List.Free;
    end;
  finally
    Full.Free;
  end;
end;

function TReadOnlySweepTests.DeepCheck(const Tool: string;
  Response: TJSONObject): string;
const
  SEEDED_FILES_IN_SCOPE = 3;
var
  Row: TJSONValue;
begin
  Result := '';
  if Tool = 'check_value_drift' then
  begin
    if Response.GetValue<Integer>('checked') < 1 then
      Result := Result + 'check_value_drift: checked < 1'#13#10;
    if Response.GetValue<Integer>('unchanged') < 1 then
      Result := Result + 'check_value_drift: value V not reported unchanged'#13#10;
    for Row in Response.GetValue<TJSONArray>('drifted') do
      Result := Result + Format('check_value_drift: drifted row %s'#13#10, [Row.ToJSON]);
  end
  else if Tool = 'check_storage' then
  begin
    if Response.GetValue<Integer>('checked') < SEEDED_FILES_IN_SCOPE then
      Result := Result + 'check_storage: checked below seeded file count'#13#10;
    for Row in Response.GetValue<TJSONArray>('files') do
      if Row.GetValue<string>('status') = 'error' then
        Result := Result + Format('check_storage: error row %s'#13#10, [Row.ToJSON]);
  end
  else if Tool = 'list_files' then
  begin
    for Row in Response.GetValue<TJSONArray>('files') do
      if Row.FindValue('storage_status') <> nil then
        if MatchStr(Row.GetValue<string>('storage_status'),
          ['error', 'missing', 'content_mismatch']) then
          Result := Result + Format('list_files: storage %s'#13#10, [Row.ToJSON]);
  end;
end;

procedure TReadOnlySweepTests.EveryReadToolRunsWithoutWrites;
var
  Name, Failures: string;
  Response: TJSONObject;
begin
  Failures := '';
  for Name in READ_TOOL_NAMES do
  begin
    try
      Response := ExecuteJson(FRegistry, Name, ParamsFor(Name));
      try
        if Response.FindValue('error') <> nil then
          Failures := Failures + Format('%s: error key: %s'#13#10,
            [Name, Response.GetValue<string>('error')])
        else
          Failures := Failures + DeepCheck(Name, Response);
      finally
        Response.Free;
      end;
    except
      on E: Exception do
        Failures := Failures + Format('%s: %s: %s'#13#10,
          [Name, E.ClassName, E.Message]);
    end;
  end;
  Response := ExecuteJson(FRegistry, 'list_files',
    Format('{"item_id":%d,"check_storage":true}', [FItem]));
  try
    if Response.FindValue('error') <> nil then
      Failures := Failures + 'list_files check_storage: error key'#13#10
    else
      Failures := Failures + DeepCheck('list_files', Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('', Failures);
end;

procedure TReadOnlySweepTests.EveryWriteToolIsRefused;
var
  Names: TArray<string>;
  Name, Failures: string;
  Params: TJSONObject;
begin
  Names := WriteToolNames;
  Assert.AreEqual<NativeInt>(36, Length(Names));
  Failures := '';
  for Name in Names do
  begin
    Params := TJSONObject.Create;
    try
      try
        FRegistry.Execute(Name, Params).Free;
        Failures := Failures + Name + ': executed'#13#10;
      except
        on EToolAccessRefused do
        begin
        end;
        on E: Exception do
          Failures := Failures + Format('%s: %s: %s'#13#10,
            [Name, E.ClassName, E.Message]);
      end;
    finally
      Params.Free;
    end;
  end;
  Assert.AreEqual('', Failures);
end;

procedure TReadOnlySweepTests.ScopeRefusalUnchangedInReadOnly;
const
  MISSING_ID = 999999;
var
  Foreign, Missing: string;
begin
  Foreign := RefusalOf('get_item', Format('{"item_id":%d}', [FQItem]));
  Missing := RefusalOf('get_item', Format('{"item_id":%d}', [MISSING_ID]));
  Assert.IsTrue(Foreign <> '', 'out-of-scope item is refused');
  Assert.IsTrue(Missing <> '', 'missing item is refused');
  Assert.AreEqual(
    TRegEx.Replace(Missing, '\b' + IntToStr(MISSING_ID) + '\b', 'N'),
    TRegEx.Replace(Foreign, '\b' + IntToStr(FQItem) + '\b', 'N'));
end;

procedure TReadOnlySweepTests.DatabaseRejectsWrites;
var
  Statement: IDBStatement;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('CREATE TABLE SweepProbe (X INTEGER)');
  Assert.WillRaiseAny(
    procedure
    begin
      Statement.Execute;
    end);
end;

procedure TReadOnlySweepTests.ListProjectsReturnsOnlyScope;
var
  Response: TJSONObject;
  Rows: TJSONArray;
begin
  Response := ExecuteJson(FRegistry, 'list_projects', '{}');
  try
    Rows := Response.GetValue<TJSONArray>('projects');
    Assert.AreEqual<NativeInt>(1, Rows.Count);
    Assert.AreEqual(FP, Rows.Items[0].GetValue<Integer>('id'));
  finally
    Response.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TReadOnlySweepTests);

end.
