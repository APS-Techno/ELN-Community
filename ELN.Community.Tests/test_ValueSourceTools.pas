unit test_ValueSourceTools;

interface

procedure RunValueSourceTests;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.Generics.Collections,
  Vcl.Forms,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq, Aurelius.Drivers.Interfaces,
  upfVisualClasses, upfIntf,
  unit_AuthorizationTestSupport,
  unit_MCPTools, unit_PluginHost, unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ToolsWrite, unit_ToolsValues, unit_ToolsNavigation, unit_ToolsFiles,
  unit_ToolsValueChecks,
  unit_Project, unit_Item, unit_ItemTypes, unit_ValueType,
  unit_ReaderValueMapping,
  unit_FileType, unit_AuditLog, unit_FilePaths,
  unit_ItemModel, unit_DerivedFormulas;

type
  TDriftFixturePlugin = class(TupfVisualPlugin, IViewerPlugin,
    IKeyValueProvider, IReaderIdentity)
  private
    FData: string;
  public
    OutputScale: Double;
    OutputVersion: string;
    function GetFrame: TFrame;
    function GetCaption: string;
    function GetParams: TPluginParams;
    function LoadFromFile(const FileName: string): Boolean;
    function LoadFromStream(Stream: TMemoryStream): Boolean;
    procedure DisplayText(const Caption, Text: string);
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

  TRows = class
    class function Count<T: class>: Integer;
  end;

  TRowSnapshot = record
    Values, Audits, Items, ValueTypes, Files: Integer;
    class function Take: TRowSnapshot; static;
    function SameAs(const Other: TRowSnapshot): Boolean;
  end;

const
  DRIFT_READER_ID = 'synthetic.drift-reader';

function TDriftFixturePlugin.GetFrame: TFrame;
begin
  Result := nil;
end;

function TDriftFixturePlugin.GetCaption: string;
begin
  Result := 'Synthetic drift reader';
end;

function TDriftFixturePlugin.GetParams: TPluginParams;
begin
  Result := Default(TPluginParams);
  Result.PType := ptFile;
  Result.Ext := '.vdrift';
end;

function TDriftFixturePlugin.LoadFromFile(const FileName: string): Boolean;
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

function TDriftFixturePlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
begin
  Result := False;
end;

procedure TDriftFixturePlugin.DisplayText(const Caption, Text: string);
begin
end;

function TDriftFixturePlugin.GetKeyValues: TArray<TPluginKeyValue>;
var
  Parsed: TJSONObject;
begin
  Parsed := TJSONObject.ParseJSONValue(FData) as TJSONObject;
  try
    if Parsed.FindValue('area') <> nil then
    begin
      SetLength(Result, 3);
      Result[0] := Default(TPluginKeyValue);
      Result[0].Name := 'Wear Area';
      Result[0].Value := Parsed.GetValue<Double>('area');
      Result[0].Units := 'um2';
      Result[0].RecType := prResult;
      Result[1] := Default(TPluginKeyValue);
      Result[1].Name := 'Fn';
      Result[1].Value := Parsed.GetValue<Double>('fn');
      Result[1].Units := 'N';
      Result[1].RecType := prCondition;
      Result[2] := Default(TPluginKeyValue);
      Result[2].Name := 'Cycles';
      Result[2].Value := Parsed.GetValue<Double>('cycles');
      Result[2].RecType := prCondition;
      Exit;
    end;
    if Parsed.FindValue('cof') <> nil then
    begin
      SetLength(Result, 1);
      Result[0] := Default(TPluginKeyValue);
      Result[0].Name := 'COF';
      Result[0].Value := Parsed.GetValue<Double>('cof');
      Result[0].RecType := prResult;
      if Parsed.FindValue('std') <> nil then
      begin
        SetLength(Result, 2);
        Result[1] := Result[0];
        Result[1].Name := 'COF STD';
        Result[1].Value := Parsed.GetValue<Double>('std');
      end;
      Exit;
    end;
    SetLength(Result, 5);
    Result[0].Name := 'Thickness A';
    Result[0].Value := Parsed.GetValue<Double>('a') * OutputScale;
    Result[0].Units := 'nm';
    Result[0].RecType := prResult;
    Result[1].Name := 'Density B';
    Result[1].Value := Parsed.GetValue<Double>('b');
    Result[1].Units := 'g/cm3';
    Result[1].RecType := prResult;
    Result[2] := Result[0];
    Result[2].Name := 'Thickness A STD';
    Result[2].Value := 0.2;
    Result[3] := Result[1];
    Result[3].Name := 'Density B STD';
    Result[3].Units := 'wrong unit';
    Result[3].Value := 0.1;
    Result[4] := Result[1];
    Result[4].Name := 'Orphan STD';
  finally
    Parsed.Free;
  end;
end;

function TDriftFixturePlugin.GetReaderId: string;
begin
  Result := DRIFT_READER_ID;
end;

function TDriftFixturePlugin.GetReaderVersion: string;
begin
  Result := OutputVersion;
end;

class function TRows.Count<T>: Integer;
var
  Observer: TObjectManager;
  Rows: TList<T>;
begin
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Rows := Observer.Find<T>.List;
    try
      Result := Rows.Count;
    finally
      Rows.Free;
    end;
  finally
    Observer.Free;
  end;
end;

class function TRowSnapshot.Take: TRowSnapshot;
begin
  Result.Values := TRows.Count<unit_Item.TValue>;
  Result.Audits := TRows.Count<TAuditLog>;
  Result.Items := TRows.Count<TItem>;
  Result.ValueTypes := TRows.Count<TValueType>;
  Result.Files := TRows.Count<unit_Item.TFile>;
end;

function TRowSnapshot.SameAs(const Other: TRowSnapshot): Boolean;
begin
  Result := (Values = Other.Values) and (Audits = Other.Audits) and
    (Items = Other.Items) and (ValueTypes = Other.ValueTypes) and
    (Files = Other.Files);
end;

procedure Prepare;
begin
  Context.Storage := Notebook.Storage;
  FreeAndNil(Registry);
  Registry := TToolRegistry.Create(Context);
  RegisterWriteTools(Registry);
  RegisterValueTools(Registry);
  RegisterNavigationTools(Registry);
  RegisterFileTools(Registry);
  RegisterValueCheckTools(Registry);
end;

function NewItem(Project: TProject; ParentId: Integer;
  const Title: string): TItem;
var
  Id: Integer;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.ProjectID := Project.Id;
  Result.Parent := ParentId;
  Result.Type_ := TItemType.Specimen;
  Result.Level := TItemLevel.Item;
  Result.CreatedBy := Notebook.Principal.Id;
  Result.CreatedDate := Now;
  Notebook.Manager.Save(Result);
  Notebook.Manager.Flush;
  Id := Result.Id;
  Notebook.Manager.Evict(Result);
  Result.Free;
  Result := Notebook.Manager.Find<TItem>(Id);
end;

function NewValueType(const Title, Units: string; HasRange: Boolean;
  RangeMin, RangeMax: Double): Integer;
var
  ValueType: TValueType;
begin
  ValueType := TValueType.Create;
  ValueType.Symbol := 'd';
  ValueType.Title := Title;
  ValueType.Units := Units;
  if HasRange then
  begin
    ValueType.RangeMin := RangeMin;
    ValueType.RangeMax := RangeMax;
  end;
  ValueType.CreatedDate := Now;
  ValueType.CreatedBy := Notebook.Principal.Id;
  Notebook.Manager.Save(ValueType);
  Notebook.Manager.Flush;
  Result := ValueType.Id;
end;

function NewFileType(const Ext: string): Integer;
var
  FileType: TFileType;
begin
  FileType := TFileType.Create;
  FileType.Ext := Ext;
  FileType.CreatedDate := Now;
  Notebook.Manager.Save(FileType);
  Notebook.Manager.Flush;
  Result := FileType.Id;
end;

function StoreFile(Item: TItem; FileTypeId: Integer;
  const Title, Content: string): Int64;
var
  Dir, Path: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath,
    'ELN-ValueSourceInput-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    Path := TPath.Combine(Dir, 'input.bin');
    System.IOUtils.TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Content));
    Result := AttachFileToItem(Context, Item.Id, Path, FileTypeId, Title).Id;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

function ExpectRefused(const Tool, JSON, Fragment: string): string;
var
  Response: TJSONObject;
begin
  Result := '';
  try
    Response := Call(Tool, JSON);
    Response.Free;
  except
    on E: Exception do
    begin
      if E.ClassType <> Exception then
        raise;
      Result := E.Message;
    end;
  end;
  Check(Result <> '', Tool + ' must be refused: ' + JSON);
  Check(Pos(Fragment, Result) > 0,
    Format('%s refusal must mention "%s": %s', [Tool, Fragment, Result]));
end;

function CallId(const Tool, JSON: string): Integer;
var
  Response: TJSONObject;
begin
  Response := Call(Tool, JSON);
  try
    Result := Response.GetValue<Integer>('id');
  finally
    Response.Free;
  end;
end;

function Codes(Arr: TJSONArray): string;
var
  Element: TJSONValue;
begin
  Result := '';
  for Element in Arr do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Element.Value;
  end;
end;

function FindRow(Arr: TJSONArray; const Key: string; Id: Int64): TJSONObject;
var
  Element: TJSONValue;
begin
  for Element in Arr do
    if (Element as TJSONObject).GetValue<Int64>(Key) = Id then
      Exit(TJSONObject(Element));
  Result := nil;
end;

function StoredValue(Observer: TObjectManager; Id: Integer): unit_Item.TValue;
begin
  Result := Observer.Find<unit_Item.TValue>(Id);
  Check(Assigned(Result), Format('Value %d must be stored', [Id]));
end;

procedure TestReaderSourceRoundTrip;
var
  Project: TProject;
  Item: TItem;
  TypeId, ValueId: Integer;
  FileId: Int64;
  Response: TJSONObject;
  Row, Source: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Reader source item');
  FileId := StoreFile(Item, NewFileType('.vsrc'), 'scan', 'synthetic scan');
  TypeId := NewValueType('Synthetic period', 'nm', False, 0, 0);
  ValueId := CallId('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":3.2,"source_file_id":%d,' +
    '"reader_id":"synthetic.reader","reader_version":"7","key_name":"Period",' +
    '"reader_units":"A","conversion_factor":0.123456789}',
    [Item.Id, TypeId, FileId]));

  Response := Call('get_values', Format('{"item_id":%d}', [Item.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('results'), 'id', ValueId);
    Check(Assigned(Row), 'get_values must list the new value');
    Source := Row.GetValue<TJSONObject>('source');
    Check(Source.GetValue<string>('kind') = 'Reader', 'Reader kind round-trips');
    Check(Source.GetValue<Int64>('file_id') = FileId, 'Source file round-trips');
    Check(Source.GetValue<string>('reader_id') = 'synthetic.reader', 'Reader id round-trips');
    Check(Source.GetValue<string>('reader_version') = '7', 'Reader version round-trips');
    Check(Source.GetValue<string>('key_name') = 'Period', 'Key name round-trips');
    Check(Source.GetValue<string>('reader_units') = 'A', 'Original reader unit round-trips');
    Check(Abs(Source.GetValue<Double>('conversion_factor') - 0.123456789) < 1e-15,
      'Applied factor round-trips without display rounding');
    Check(Source.FindValue('note') = nil, 'An empty note is omitted');
  finally
    Response.Free;
  end;

  Response := Call('query_values', Format('{"project_id":%d}', [Project.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'value_id', ValueId);
    Check(Assigned(Row) and
      (Row.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Reader'),
      'query_values must return the source');
  finally
    Response.Free;
  end;

  Response := Call('get_item', Format('{"item_id":%d}', [Item.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'id', ValueId);
    Check(Assigned(Row) and
      (Row.GetValue<TJSONObject>('source').GetValue<Int64>('file_id') = FileId),
      'get_item must return the source');
  finally
    Response.Free;
  end;
end;

procedure TestMissingSourceStoresUnknown;
var
  Item: TItem;
  ValueId: Integer;
  Response: TJSONObject;
  Observer: TObjectManager;
  Stored: unit_Item.TValue;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Legacy caller item');
  Response := Call('add_value', Format('{"item_id":%d,"value_type_id":%d,"value":12}',
    [Item.Id, NewValueType('Synthetic count', '', False, 0, 0)]));
  try
    ValueId := Response.GetValue<Integer>('id');
    Check(Response.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Unknown',
      'A value without source fields reports Unknown');
    Check(Response.FindValue('confirmed_issues') = nil,
      'A plain value has no confirmed issues');
  finally
    Response.Free;
  end;
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Stored := StoredValue(Observer, ValueId);
    Check(Stored.SourceKind.HasValue and (Stored.SourceKind.Value = vskUnknown),
      'A value without source fields is stored as Unknown');
    Check(not Stored.SourceFileId.HasValue, 'No source file is stored');
  finally
    Observer.Free;
  end;
end;

procedure TestForeignProjectSourceRefused;
var
  Item, Foreign: TItem;
  FileId: Int64;
  TypeId: Integer;
  Before: TRowSnapshot;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Target item');
  Foreign := NewItem(AddProject(Notebook.Principal), 0, 'Other project item');
  FileId := StoreFile(Foreign, NewFileType('.vsrc'), 'foreign', 'foreign bytes');
  TypeId := NewValueType('Synthetic ratio', '', False, 0, 0);
  Before := TRowSnapshot.Take;
  ExpectRefused('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":1.5,"source_file_id":%d,' +
    '"source_note":"fit job 41"}',
    [Item.Id, TypeId, FileId]),
    'another project');
  Check(TRowSnapshot.Take.SameAs(Before), 'A refused source writes nothing');
end;

procedure TestUnrelatedItemSourceRefused;
var
  Project: TProject;
  Item, Sibling: TItem;
  TypeId: Integer;
  FileId: Int64;
  Before: TRowSnapshot;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Target item');
  Sibling := NewItem(Project, 0, 'Unrelated item');
  FileId := StoreFile(Sibling, NewFileType('.vsrc'), 'unrelated', 'other bytes');
  TypeId := NewValueType('Synthetic ratio', '', False, 0, 0);
  Before := TRowSnapshot.Take;
  ExpectRefused('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":1.5,"source_file_id":%d}',
    [Item.Id, TypeId, FileId]), 'is not attached to item');
  Check(TRowSnapshot.Take.SameAs(Before), 'A refused source writes nothing');
end;

procedure TestRelatedItemSourcesAccepted;
var
  Project: TProject;
  Parent, Child: TItem;
  TypeId, FileTypeId, ValueId: Integer;
  ParentFile, ChildFile: Int64;
  Observer: TObjectManager;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Parent := NewItem(Project, 0, 'Parent run');
  Child := NewItem(Project, Parent.Id, 'Child specimen');
  FileTypeId := NewFileType('.vsrc');
  ParentFile := StoreFile(Parent, FileTypeId, 'run log', 'parent bytes');
  ChildFile := StoreFile(Child, FileTypeId, 'child scan', 'child bytes');
  TypeId := NewValueType('Synthetic ratio', '', False, 0, 0);
  ValueId := CallId('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":2.5,"source_file_id":%d,' +
    '"reader_id":"synthetic.reader","key_name":"Ratio",' +
    '"reader_units":"","conversion_factor":1}',
    [Child.Id, TypeId, ParentFile]));
  CallId('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":2.5,"source_file_id":%d,' +
    '"source_note":"summary of child scan"}',
    [Parent.Id, TypeId, ChildFile]));
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Check(StoredValue(Observer, ValueId).SourceFileId.Value = ParentFile,
      'An ancestor file is an accepted source');
    Check(StoredValue(Observer, ValueId).ReaderVersion = 'unknown',
      'A Reader source without a version records unknown');
    Check(StoredValue(Observer, ValueId).ReaderUnits.HasValue and
      (StoredValue(Observer, ValueId).ReaderUnits.Value = ''),
      'Known dimensionless units remain distinct from legacy unknown units');
    Check(StoredValue(Observer, ValueId).ConversionFactor.HasValue,
      'Dimensionless Reader values retain conversion provenance');
  finally
    Observer.Free;
  end;
end;

procedure TestBatchIsAllOrNothing;
var
  Project: TProject;
  Item: TItem;
  TypeId, RangedId: Integer;
  FileId: Int64;
  Before, After: TRowSnapshot;
  Response: TJSONObject;
  Rows: TJSONArray;
  Observer: TObjectManager;
  Message: string;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Fit target');
  FileId := StoreFile(Item, NewFileType('.vsrc'), 'reflectivity', 'curve');
  TypeId := NewValueType('Synthetic roughness', 'nm', False, 0, 0);
  RangedId := NewValueType('Synthetic thickness', 'm', True, 1e-9, 1e-5);
  Before := TRowSnapshot.Take;
  Message := ExpectRefused('add_values', Format(
    '{"values":[' +
    '{"item_id":%0:d,"value_type_id":%1:d,"value":0.4,"source_file_id":%2:d,"source_note":"fit 9"},' +
    '{"item_id":%0:d,"value_type_id":%1:d,"value":0.5,"source_file_id":%2:d,"source_note":"fit 9"},' +
    '{"item_id":%0:d,"value_type_id":%3:d,"value":319.4,"source_file_id":%2:d,"source_note":"fit 9"}]}',
    [Item.Id, TypeId, FileId, RangedId]), 'values[2]');
  Check(Pos('above_range', Message) > 0, 'Batch refusal carries the issue code');
  Check(TRowSnapshot.Take.SameAs(Before), 'A refused batch writes nothing');

  Response := Call('add_values', Format(
    '{"values":[' +
    '{"item_id":%0:d,"value_type_id":%1:d,"value":0.4,"source_file_id":%2:d,"source_note":"fit 9"},' +
    '{"item_id":%0:d,"value_type_id":%3:d,"value":3.19e-7,"tolerance":2e-9,"source_file_id":%2:d,"source_note":"fit 9"}]}',
    [Item.Id, TypeId, FileId, RangedId]));
  try
    Check(Response.GetValue<Integer>('count') = 2, 'Both values are stored');
    Rows := Response.GetValue<TJSONArray>('values');
    After := TRowSnapshot.Take;
    Check(After.Values = Before.Values + 2, 'Two value rows are written');
    Check(After.Audits = Before.Audits + 2, 'One audit row per value');
    Observer := TObjectManager.Create(Notebook.Connection);
    try
      Check(StoredValue(Observer, Rows.Items[1].GetValue<Integer>('id')).SourceNote = 'fit 9',
        'Batch entries keep their source note');
      Check(StoredValue(Observer, Rows.Items[1].GetValue<Integer>('id')).EffectiveSourceKind = vskManual,
        'A file with a note infers a Manual source');
    finally
      Observer.Free;
    end;
  finally
    Response.Free;
  end;
end;

procedure TestRangeRefusedUntilConfirmed;
var
  Item: TItem;
  TypeId: Integer;
  Before: TRowSnapshot;
  Response: TJSONObject;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Thickness target');
  TypeId := NewValueType('Synthetic thickness', 'm', True, 1e-9, 1e-5);
  Before := TRowSnapshot.Take;
  ExpectRefused('add_value', Format('{"item_id":%d,"value_type_id":%d,"value":319.4}',
    [Item.Id, TypeId]), 'above_range');
  Check(TRowSnapshot.Take.SameAs(Before), 'An out-of-range refusal writes nothing');
  Response := Call('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":319.4,"confirm_out_of_range":true}',
    [Item.Id, TypeId]));
  try
    Check(Codes(Response.GetValue<TJSONArray>('confirmed_issues')) = 'above_range',
      'The confirmed issue is reported');
  finally
    Response.Free;
  end;
end;

procedure TestToleranceScaleRefused;
var
  Item: TItem;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Tolerance target');
  ExpectRefused('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":2.279e-05,"tolerance":0.0602}',
    [Item.Id, NewValueType('Synthetic thickness', 'm', False, 0, 0)]),
    'tolerance_exceeds_value');
end;

procedure TestIssueReportIsReadOnly;
var
  Project: TProject;
  Item: TItem;
  ValueId: Integer;
  Before: TRowSnapshot;
  Response: TJSONObject;
  Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Reported item');
  ValueId := CallId('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":319.4,"confirm_out_of_range":true}',
    [Item.Id, NewValueType('Synthetic thickness', 'm', True, 1e-9, 1e-5)]));
  Before := TRowSnapshot.Take;
  Response := Call('report_value_issues', '{}');
  try
    Check(Response.GetValue<Double>('tolerance_factor') = 1e3,
      'The default tolerance factor is reported');
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'value_id', ValueId);
    Check(Assigned(Row), 'The confirmed out-of-range value is listed');
    Check(Codes(Row.GetValue<TJSONArray>('issues')) = 'above_range',
      'The issue code is listed');
    Check(Row.GetValue<Integer>('project_id') = Project.Id, 'The row names its project');
  finally
    Response.Free;
  end;
  Response := Call('report_value_issues', Format('{"project_id":%d}', [Project.Id]));
  Response.Free;
  Check(TRowSnapshot.Take.SameAs(Before), 'The report changes nothing');
end;

procedure TestValueDriftReportsOnlyChangedValue;
var
  PluginDir: string;
  Host: TPluginHost;
  Plugin: TDriftFixturePlugin;
  Item: TItem;
  FileId: Int64;
  TypeId, ThicknessId, DensityId: Integer;
  Response: TJSONObject;
  Rows, Drifted: TJSONArray;
  Row: TJSONObject;
  ReaderVersion: string;
  Mapping: TReaderValueMapping;
  ExtractedTolerance: Double;
  CofFileId: Int64;
begin
  PluginDir := TPath.Combine(TPath.GetTempPath,
    'ELN-ValueDriftPlugins-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(PluginDir);
  Host := nil;
  Plugin := nil;
  try
    Host := TPluginHost.Create(PluginDir);
    Plugin := TDriftFixturePlugin.CreateNew(nil);
    Plugin.OutputScale := 1;
    Plugin.OutputVersion := '1';
    (ApplicationServices as IupfCommandServices).RegisterPlugin(Plugin);
    Context.PluginHost := Host;
    Prepare;

    Item := NewItem(AddProject(Notebook.Principal), 0, 'Drift item');
    FileId := StoreFile(Item, NewFileType('.vdrift'), 'layers', '{"a":2.5,"b":7}');
    TypeId := NewValueType('Synthetic reader output', 'm', False, 0, 0);
    Mapping := TReaderValueMapping.Create;
    Mapping.ReaderId := DRIFT_READER_ID;
    Mapping.KeyPattern := 'Thickness A';
    Mapping.ReaderUnits := 'nm';
    Mapping.ValueType := Notebook.Manager.Find<TValueType>(TypeId);
    Mapping.Factor := 1e-9;
    Mapping.LabelText := 'A';
    Notebook.Manager.Save(Mapping);
    Notebook.Manager.Flush;

    Response := Call('extract_file_key_values', Format('{"file_id":%d}', [FileId]));
    try
      Check(Response.FindValue('error') = nil, 'Key values are extracted');
      Check(Response.GetValue<Int64>('file_id') = FileId, 'The file id is returned');
      Check(Response.GetValue<string>('reader_id') = DRIFT_READER_ID,
        'The reader id is returned');
      ReaderVersion := Response.GetValue<string>('reader_version');
      Check(ReaderVersion = '1', 'The reader version is returned');
      Row := Response.GetValue<TJSONArray>('key_values').Items[0] as TJSONObject;
      Check(Response.GetValue<TJSONArray>('key_values').Count = 2,
        'STD entries are not separate extracted values');
      ExtractedTolerance := Row.GetValue<Double>('tolerance');
      Check(Abs(ExtractedTolerance - 0.2e-9) < 1e-21, 'STD uses the mapping factor');
      Check(Response.GetValue<TJSONArray>('warnings').Count = 1, 'Orphan STD is reported');
      Check(Response.GetValue<TJSONArray>('key_values').Items[1].FindValue('tolerance_warning') <> nil,
        'Invalid STD units are reported on the main value');
      Check(Abs(Row.GetValue<Double>('converted_value') - 2.5e-9) < 1e-21,
        'MCP extraction converts through the mapping');
      Check(Row.GetValue<Integer>('value_type_id') = TypeId,
        'MCP extraction resolves the target type');
      Check(Row.GetValue<string>('reader_units') = 'nm',
        'MCP extraction preserves original units');
    finally
      Response.Free;
    end;
    NewValueType('COF', '', False, 0, 0);
    CofFileId := StoreFile(Item, NewFileType('.vdrift'), 'cof', '{"cof":0.5,"std":0.02}');
    Response := Call('extract_file_key_values', Format('{"file_id":%d}', [CofFileId]));
    try
      Rows := Response.GetValue<TJSONArray>('key_values');
      Check(Rows.Count = 1, 'COF STD is consumed');
      Row := Rows.Items[0] as TJSONObject;
      Check(Row.GetValue<string>('value_type_units') = '', 'COF target is dimensionless');
      Check(Abs(Row.GetValue<Double>('tolerance') - 0.02) < 1e-15, 'COF STD remains dimensionless');
    finally
      Response.Free;
    end;
    CofFileId := StoreFile(Item, NewFileType('.vdrift'), 'cof without STD', '{"cof":0.4}');
    Response := Call('extract_file_key_values', Format('{"file_id":%d}', [CofFileId]));
    try
      Row := Response.GetValue<TJSONArray>('key_values').Items[0] as TJSONObject;
      Check(Row.FindValue('tolerance') = nil, 'A different file does not inherit the previous STD');
    finally
      Response.Free;
    end;

    Response := Call('add_values', Format(
      '{"values":[' +
      '{"item_id":%0:d,"value_type_id":%1:d,"value":2.5e-9,"tolerance":%5:s,"source_file_id":%2:d,' +
      '"reader_id":"%3:s","reader_version":"%4:s","key_name":"Thickness A",' +
      '"reader_units":"nm","conversion_factor":1e-9},' +
      '{"item_id":%0:d,"value_type_id":%1:d,"value":7,"source_file_id":%2:d,' +
      '"reader_id":"%3:s","reader_version":"%4:s","key_name":"Density B",' +
      '"reader_units":"g/cm3","conversion_factor":1}]}',
      [Item.Id, TypeId, FileId, DRIFT_READER_ID, ReaderVersion, FloatToStr(ExtractedTolerance, TFormatSettings.Invariant)]));
    try
      Rows := Response.GetValue<TJSONArray>('values');
      ThicknessId := Rows.Items[0].GetValue<Integer>('id');
      DensityId := Rows.Items[1].GetValue<Integer>('id');
    finally
      Response.Free;
    end;
    Check(Abs(Notebook.Manager.Find<TValue>(ThicknessId).Tol - ExtractedTolerance) < 1e-21,
      'Extracted tolerance survives the existing MCP writer');

    Response := Call('check_value_drift', Format('{"item_id":%d}', [Item.Id]));
    try
      Check(Response.GetValue<Integer>('checked') = 2, 'Both reader values are checked');
      Check(Response.GetValue<Integer>('unchanged') = 2, 'Unchanged output is not drift');
      Check(Response.GetValue<TJSONArray>('drifted').Count = 0, 'No value has drifted');
    finally
      Response.Free;
    end;

    Plugin.OutputScale := 2;
    Response := Call('check_value_drift', Format('{"item_id":%d}', [Item.Id]));
    try
      Drifted := Response.GetValue<TJSONArray>('drifted');
      Check(Drifted.Count = 1, 'Only the changed value is reported');
      Row := Drifted.Items[0] as TJSONObject;
      Check(Row.GetValue<Integer>('value_id') = ThicknessId, 'The changed value is named');
      Check(Codes(Row.GetValue<TJSONArray>('flags')) = 'value_changed',
        'The change is a value change only');
      Check(Abs(Row.GetValue<Double>('current_value') - 5e-9) < 1e-21,
        'The converted current output is reported');
      Check(Response.GetValue<Integer>('unchanged') = 1, 'The other value is unchanged');
    finally
      Response.Free;
    end;

    Plugin.OutputVersion := '2';
    Response := Call('check_value_drift', Format('{"item_id":%d}', [Item.Id]));
    try
      Drifted := Response.GetValue<TJSONArray>('drifted');
      Check(Drifted.Count = 2, 'A version change reports every value of that reader');
      Check(Codes(FindRow(Drifted, 'value_id', ThicknessId).GetValue<TJSONArray>('flags')) =
        'value_changed,reader_version_changed', 'Value and version change are both flagged');
      Check(Codes(FindRow(Drifted, 'value_id', DensityId).GetValue<TJSONArray>('flags')) =
        'reader_version_changed', 'An unchanged number reports only the version');
    finally
      Response.Free;
    end;
  finally
    FreeAndNil(Registry);
    Context.PluginHost := nil;
    Host.Free;
    Plugin.Free;
    if TDirectory.Exists(PluginDir) then
      TDirectory.Delete(PluginDir, True);
  end;
end;

procedure TestStorageCheckReportsContentMismatch;
var
  Project: TProject;
  Item: TItem;
  FileTypeId: Integer;
  GoodFile, ChangedFile: Int64;
  Changed: unit_Item.TFile;
  Response: TJSONObject;
  Files, Previous: TJSONArray;
  Row: TJSONObject;
  Before: TRowSnapshot;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Stored item');
  FileTypeId := NewFileType('.vsrc');
  GoodFile := StoreFile(Item, FileTypeId, 'intact', 'intact bytes');
  ChangedFile := StoreFile(Item, FileTypeId, 'altered', 'original bytes');
  Changed := Notebook.Manager.Find<unit_Item.TFile>(ChangedFile);
  Notebook.Storage.WriteBytes(AttachmentRelativePath(Project.FileFolder,
    Item.FolderName, Changed.FullName), TEncoding.UTF8.GetBytes('altered bytes'));
  Before := TRowSnapshot.Take;

  Response := Call('check_storage', Format(
    '{"item_id":%d,"baseline":[' +
    '{"file_id":%d,"status":"missing","note":"listed in an earlier report"},' +
    '{"file_id":999999999,"status":"missing","note":"never existed"}]}',
    [Item.Id, GoodFile]));
  try
    Check(Response.GetValue<Integer>('checked') = 2, 'Both files are checked');
    Check(Response.GetValue<TJSONObject>('counts').GetValue<Integer>('ok') = 1,
      'One file is intact');
    Check(Response.GetValue<TJSONObject>('counts').GetValue<Integer>('content_mismatch') = 1,
      'One file has changed bytes');
    Files := Response.GetValue<TJSONArray>('files');
    Check(Files.Count = 1, 'Only the changed file is listed');
    Row := Files.Items[0] as TJSONObject;
    Check(Row.GetValue<Int64>('file_id') = ChangedFile, 'The changed file is named');
    Check(Row.GetValue<string>('status') = 'content_mismatch', 'Its status is content_mismatch');
    Previous := Response.GetValue<TJSONArray>('previously_reported');
    Check(Previous.Count = 2, 'Every baseline entry is echoed');
    Row := FindRow(Previous, 'file_id', GoodFile);
    Check(Assigned(Row) and (Row.GetValue<string>('previous_status') = 'missing') and
      (Row.GetValue<string>('current_status') = 'ok') and
      (Row.GetValue<string>('note') = 'listed in an earlier report'),
      'A baseline entry shows its earlier and current status');
    Check(FindRow(Previous, 'file_id', 999999999).GetValue<string>('current_status') = 'not_found',
      'An unknown baseline file is not_found');
  finally
    Response.Free;
  end;

  Response := Call('check_storage', Format('{"project_id":%d,"include_ok":true}',
    [Project.Id]));
  try
    Check(Response.GetValue<TJSONArray>('files').Count = 2, 'include_ok lists every file');
  finally
    Response.Free;
  end;
  Check(TRowSnapshot.Take.SameAs(Before), 'The storage check writes nothing');
end;

function TypeIdOf(const Title, Units: string): Integer;
var
  Types: TList<TValueType>;
  VT: TValueType;
begin
  Result := 0;
  Types := Notebook.Manager.Find<TValueType>.List;
  try
    for VT in Types do
      if (VT.Title = Title) and (VT.Units = Units) then
        Exit(VT.Id);
  finally
    Types.Free;
  end;
  Check(False, Format('Seeded value type %s (%s) must exist', [Title, Units]));
end;

function AreaType: Integer;
begin
  Result := TypeIdOf('Wear area', 'mm' + #$00B2);
end;

function ForceType: Integer;
begin
  Result := TypeIdOf('Normal force', 'N');
end;

function CyclesType: Integer;
begin
  Result := TypeIdOf('Cycles', '');
end;

function AddManual(ItemId, TypeId: Integer; Value: Double): Integer;
begin
  Result := CallId('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":%s,"source_note":"lab book"}',
    [ItemId, TypeId, FloatToStr(Value, TFormatSettings.Invariant)]));
end;

function DerivedCall(ItemId: Integer; const FormulaId: string;
  AreaId, ForceId, CyclesId: Integer; const Extra: string = ''): string;
begin
  Result := Format('{"item_id":%d,"formula_id":"%s","inputs":{"area":%d,' +
    '"normal_force":%d,"cycles":%d}%s}',
    [ItemId, FormulaId, AreaId, ForceId, CyclesId, Extra]);
end;

procedure TestDerivedValueThroughTools;
var
  Project: TProject;
  Parent, Child: TItem;
  AreaId, ForceId, CyclesId, DerivedId: Integer;
  Response, Source, Row: TJSONObject;
  Inputs, Drifted: TJSONArray;
  Before, After: TRowSnapshot;
  Observer: TObjectManager;
  Stored: unit_Item.TValue;
  Audit: TList<TAuditLog>;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Parent := NewItem(Project, 0, 'Wear test');
  Child := NewItem(Project, Parent.Id, 'Wear track');
  AreaId := AddManual(Child.Id, AreaType, 0.004);
  ForceId := AddManual(Parent.Id, ForceType, 5);
  CyclesId := AddManual(Parent.Id, CyclesType, 1000);
  Before := TRowSnapshot.Take;
  Response := Call('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    AreaId, ForceId, CyclesId, ',"description":"synthetic wear"'));
  try
    DerivedId := Response.GetValue<Integer>('id');
    Check(Abs(Response.GetValue<Double>('value') - 4e-7) < 1e-18, 'K = A / (2 F N)');
    Check(Response.GetValue<Double>('tolerance') = 0, 'A Derived value has no tolerance');
    Check(Response.GetValue<string>('value_type') = 'Wear rate', 'The result type is Wear rate');
    Check(Response.GetValue<string>('units') = WearRateFormula.ResultUnits,
      'The result unit is mm3/(N mm)');
    Source := Response.GetValue<TJSONObject>('source');
    Check(Source.GetValue<string>('kind') = 'Derived', 'The source kind is Derived');
    Check(Source.GetValue<string>('formula_id') = WEAR_RATE_FORMULA_ID, 'The formula id is stored');
    Check(Source.GetValue<Integer>('formula_version') = 1, 'The formula version is stored');
    Inputs := Source.GetValue<TJSONArray>('inputs');
    Check(Inputs.Count = 3, 'Every input is stored');
    Check(FindRow(Inputs, 'value_id', AreaId).GetValue<string>('role') = 'area',
      'The area input keeps its role');
    Check(FindRow(Inputs, 'value_id', CyclesId).GetValue<Double>('used_value') = 1000,
      'The used input number is stored');
  finally
    Response.Free;
  end;
  After := TRowSnapshot.Take;
  Check(After.Values = Before.Values + 1, 'One value row is written');
  Check(After.Audits = Before.Audits + 1, 'One audit row is written');

  Response := Call('get_values', Format('{"item_id":%d}', [Parent.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('results'), 'id', DerivedId);
    Check(Assigned(Row), 'get_values lists the Derived value');
    Source := Row.GetValue<TJSONObject>('source');
    Check((Source.GetValue<string>('formula_id') = WEAR_RATE_FORMULA_ID) and
      (Source.GetValue<TJSONArray>('inputs').Count = 3), 'get_values shows the Derived source');
  finally
    Response.Free;
  end;
  Response := Call('get_item', Format('{"item_id":%d}', [Parent.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'id', DerivedId);
    Check(Assigned(Row) and (Row.GetValue<TJSONObject>('source').GetValue<Integer>(
      'formula_version') = 1), 'get_item shows the Derived source');
  finally
    Response.Free;
  end;

  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Stored := StoredValue(Observer, DerivedId);
    Check(Stored.EffectiveSourceKind = vskDerived, 'The stored kind is Derived');
    Check(Stored.Tol = 0, 'No tolerance is stored');
    Check(Stored.DerivedInputs.Count = 3, 'The input links are stored in their own table');
    Audit := Observer.Find<TAuditLog>.Where(
      (Linq['EntityType'] = Ord(aetValue)) and (Linq['EntityId'] = DerivedId)).List;
    try
      Check((Audit.Count = 1) and (Audit[0].Operation = aoCreate) and
        (Audit[0].UserId = Notebook.Principal.Id), 'The Derived write is audited');
    finally
      Audit.Free;
    end;
  finally
    Observer.Free;
  end;

  Response := Call('check_value_drift', Format('{"item_id":%d}', [Parent.Id]));
  try
    Check(Response.GetValue<Integer>('checked') = 1, 'Only the Derived value is checked');
    Drifted := Response.GetValue<TJSONArray>('drifted');
    Check(Drifted.Count = 1, 'A Derived value with Manual inputs is reported');
    Row := Drifted.Items[0] as TJSONObject;
    Check(Codes(Row.GetValue<TJSONArray>('flags')) = 'not_fully_rerunnable',
      'Manual inputs make the value not fully re-runnable');
    Check(Row.GetValue<string>('source_kind') = 'Derived', 'The row names the Derived kind');
    Check(Abs(Row.GetValue<Double>('current_value') - 4e-7) < 1e-18,
      'The recomputed value is reported');
  finally
    Response.Free;
  end;

  Notebook.Manager.Find<unit_Item.TValue>(AreaId).Value := 0.008;
  Notebook.Manager.Flush;
  Response := Call('check_value_drift', Format('{"item_id":%d}', [Parent.Id]));
  try
    Row := Response.GetValue<TJSONArray>('drifted').Items[0] as TJSONObject;
    Check(Codes(Row.GetValue<TJSONArray>('flags')) =
      'value_changed,input_changed,not_fully_rerunnable', 'A changed input is reported');
    Check(Abs(Row.GetValue<Double>('current_value') - 8e-7) < 1e-18,
      'The value is recomputed from the changed input');
    Check(FindRow(Row.GetValue<TJSONArray>('inputs'), 'value_id', AreaId)
      .GetValue<string>('status') = 'changed', 'The changed input is named');
  finally
    Response.Free;
  end;
end;

procedure TestDerivedValueAveragesAreaArray;
var
  Project: TProject;
  Parent: TItem;
  A1, A2, A3, ForceId, CyclesId, DerivedId, Count: Integer;
  Before: TRowSnapshot;
  Response: TJSONObject;
  Inputs: TJSONArray;
  Entry: TJSONValue;
  Observer: TObjectManager;
  Stored: unit_Item.TValue;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Parent := NewItem(Project, 0, 'Wear test');
  A1 := AddManual(Parent.Id, AreaType, 0.002);
  A2 := AddManual(Parent.Id, AreaType, 0.004);
  A3 := AddManual(Parent.Id, AreaType, 0.006);
  ForceId := AddManual(Parent.Id, ForceType, 5);
  CyclesId := AddManual(Parent.Id, CyclesType, 1000);
  Before := TRowSnapshot.Take;
  ExpectRefused('add_derived_value', Format('{"item_id":%d,"formula_id":"%s",' +
    '"inputs":{"area":[%d,%d],"normal_force":%d,"cycles":%d}}',
    [Parent.Id, WEAR_RATE_FORMULA_ID, A1, A1, ForceId, CyclesId]), 'given twice');
  ExpectRefused('add_derived_value', Format('{"item_id":%d,"formula_id":"%s",' +
    '"inputs":{"area":%d,"normal_force":[%d,%d],"cycles":%d}}',
    [Parent.Id, WEAR_RATE_FORMULA_ID, A1, ForceId, ForceId, CyclesId]), 'given twice');
  ExpectRefused('add_derived_value', Format('{"item_id":%d,"formula_id":"%s",' +
    '"inputs":{"area":[],"normal_force":%d,"cycles":%d}}',
    [Parent.Id, WEAR_RATE_FORMULA_ID, ForceId, CyclesId]), 'empty array');
  Check(TRowSnapshot.Take.SameAs(Before), 'Refused array inputs write nothing');

  Response := Call('add_derived_value', Format('{"item_id":%d,"formula_id":"%s",' +
    '"inputs":{"area":[%d,%d,%d],"normal_force":%d,"cycles":%d}}',
    [Parent.Id, WEAR_RATE_FORMULA_ID, A1, A2, A3, ForceId, CyclesId]));
  try
    DerivedId := Response.GetValue<Integer>('id');
    Check(Abs(Response.GetValue<Double>('value') - 4e-7) < 1e-18,
      'The mean area 0.004 gives K = 4e-7');
    Inputs := Response.GetValue<TJSONObject>('source').GetValue<TJSONArray>('inputs');
    Check(Inputs.Count = 5, 'Every input id is reported');
    Count := 0;
    for Entry in Inputs do
      if (Entry as TJSONObject).GetValue<string>('role') = 'area' then
        Inc(Count);
    Check(Count = 3, 'All three areas are listed under the area role');
  finally
    Response.Free;
  end;
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Stored := StoredValue(Observer, DerivedId);
    Check(Stored.DerivedInputs.Count = 5, 'Five input links are stored');
  finally
    Observer.Free;
  end;

  Response := Call('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    A2, ForceId, CyclesId));
  try
    Check(Abs(Response.GetValue<Double>('value') - 4e-7) < 1e-18,
      'A single plain id still works');
  finally
    Response.Free;
  end;
end;

procedure TestDerivedValueRefusals;
var
  Project: TProject;
  Parent, Sibling, Foreign: TItem;
  AreaId, ForceId, CyclesId, ZeroForce, ZeroCycles, NegativeArea, ZeroArea,
  WrongUnit, SiblingArea, ForeignArea: Integer;
  Before: TRowSnapshot;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Parent := NewItem(Project, 0, 'Wear test');
  Sibling := NewItem(Project, 0, 'Unrelated item');
  Foreign := NewItem(AddProject(Notebook.Principal), 0, 'Other project item');
  AreaId := AddManual(Parent.Id, AreaType, 0.004);
  ForceId := AddManual(Parent.Id, ForceType, 5);
  CyclesId := AddManual(Parent.Id, CyclesType, 1000);
  ZeroForce := AddManual(Parent.Id, ForceType, 0);
  ZeroCycles := AddManual(Parent.Id, CyclesType, 0);
  NegativeArea := AddManual(Parent.Id, AreaType, -0.001);
  ZeroArea := AddManual(Parent.Id, AreaType, 0);
  WrongUnit := AddManual(Parent.Id, NewValueType('Wear area', 'um2', False, 0, 0), 4000);
  SiblingArea := AddManual(Sibling.Id, AreaType, 0.004);
  ForeignArea := AddManual(Foreign.Id, AreaType, 0.004);
  Before := TRowSnapshot.Take;
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    AreaId, ForceId, CyclesId, ',"value":4e-7'), 'Unknown parameter value');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    AreaId, ZeroForce, CyclesId), 'normal_force must be positive');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    AreaId, ForceId, ZeroCycles), 'cycles must be positive');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    NegativeArea, ForceId, CyclesId), 'area is negative');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    WrongUnit, ForceId, CyclesId), 'the role requires Wear area');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    SiblingArea, ForceId, CyclesId), 'is not stored on item');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    ForeignArea, ForceId, CyclesId), 'another project');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    999999, ForceId, CyclesId), 'does not exist');
  ExpectRefused('add_derived_value', DerivedCall(Parent.Id, 'no_such_formula',
    AreaId, ForceId, CyclesId), 'Unknown formula');
  ExpectRefused('add_derived_value', Format('{"item_id":%d,"formula_id":"%s",' +
    '"inputs":{"area":%d,"normal_force":%d}}',
    [Parent.Id, WEAR_RATE_FORMULA_ID, AreaId, ForceId]), 'Missing input for role cycles');
  ExpectRefused('add_value', Format('{"item_id":%d,"value_type_id":%d,"value":1,' +
    '"source_kind":"Derived"}', [Parent.Id, ForceType]), 'add_derived_value');
  Check(TRowSnapshot.Take.SameAs(Before), 'Refused Derived values write nothing');

  Response := Call('add_derived_value', DerivedCall(Parent.Id, WEAR_RATE_FORMULA_ID,
    ZeroArea, ForceId, CyclesId));
  try
    Check(Response.GetValue<Double>('value') = 0, 'A zero wear area gives a zero wear rate');
  finally
    Response.Free;
  end;
end;

procedure TestDerivedValueNeedsStorage;
var
  Item: TItem;
  AreaId, ForceId, CyclesId: Integer;
  Statement: IDBStatement;
  Before: TRowSnapshot;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Old store');
  AreaId := AddManual(Item.Id, AreaType, 0.004);
  ForceId := AddManual(Item.Id, ForceType, 5);
  CyclesId := AddManual(Item.Id, CyclesType, 1000);
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand('DROP TABLE DerivedValueInputs');
  Statement.Execute;
  Statement := nil;
  Before := TRowSnapshot.Take;
  ExpectRefused('add_derived_value', DerivedCall(Item.Id, WEAR_RATE_FORMULA_ID,
    AreaId, ForceId, CyclesId), 'no storage for Derived values');
  Check(TRowSnapshot.Take.SameAs(Before), 'A store without Derived tables writes nothing');
end;

procedure TestDerivedDriftReaderInputs;
var
  PluginDir: string;
  Host: TPluginHost;
  Plugin: TDriftFixturePlugin;
  Project: TProject;
  Item: TItem;
  FileId: Int64;
  AreaId, ForceId, CyclesId, DerivedId: Integer;
  Response, Row: TJSONObject;
  Rows, Drifted: TJSONArray;
  Changed: unit_Item.TFile;
  Items: TItemModel;
begin
  PluginDir := TPath.Combine(TPath.GetTempPath,
    'ELN-DerivedDriftPlugins-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(PluginDir);
  Host := nil;
  Plugin := nil;
  try
    Host := TPluginHost.Create(PluginDir);
    Plugin := TDriftFixturePlugin.CreateNew(nil);
    Plugin.OutputScale := 1;
    Plugin.OutputVersion := '1';
    (ApplicationServices as IupfCommandServices).RegisterPlugin(Plugin);
    Context.PluginHost := Host;
    Prepare;

    Project := AddProject(Notebook.Principal);
    Item := NewItem(Project, 0, 'Wear drift');
    FileId := StoreFile(Item, NewFileType('.vdrift'), 'wear',
      '{"area":4000,"fn":5,"cycles":1000}');
    Response := Call('add_values', Format(
      '{"values":[' +
      '{"item_id":%0:d,"value_type_id":%1:d,"value":0.004,"source_file_id":%4:d,' +
      '"reader_id":"%5:s","reader_version":"1","key_name":"Wear Area",' +
      '"reader_units":"um2","conversion_factor":1e-6},' +
      '{"item_id":%0:d,"value_type_id":%2:d,"value":5,"source_file_id":%4:d,' +
      '"reader_id":"%5:s","reader_version":"1","key_name":"Fn",' +
      '"reader_units":"N","conversion_factor":1},' +
      '{"item_id":%0:d,"value_type_id":%3:d,"value":1000,"source_file_id":%4:d,' +
      '"reader_id":"%5:s","reader_version":"1","key_name":"Cycles",' +
      '"reader_units":"","conversion_factor":1}]}',
      [Item.Id, AreaType, ForceType, CyclesType, FileId, DRIFT_READER_ID]));
    try
      Rows := Response.GetValue<TJSONArray>('values');
      AreaId := Rows.Items[0].GetValue<Integer>('id');
      ForceId := Rows.Items[1].GetValue<Integer>('id');
      CyclesId := Rows.Items[2].GetValue<Integer>('id');
    finally
      Response.Free;
    end;
    DerivedId := CallId('add_derived_value', DerivedCall(Item.Id,
      WEAR_RATE_FORMULA_ID, AreaId, ForceId, CyclesId));

    Response := Call('check_value_drift', Format('{"item_id":%d}', [Item.Id]));
    try
      Check(Response.GetValue<Integer>('checked') = 4, 'Three Reader values and one Derived value are checked');
      Check(Response.GetValue<Integer>('unchanged') = 4, 'Unchanged files give no drift');
    finally
      Response.Free;
    end;

    Changed := Notebook.Manager.Find<unit_Item.TFile>(FileId);
    Notebook.Storage.WriteBytes(AttachmentRelativePath(Project.FileFolder,
      Item.FolderName, Changed.FullName),
      TEncoding.UTF8.GetBytes('{"area":8000,"fn":5,"cycles":1000}'));
    Response := Call('check_value_drift', Format('{"item_id":%d}', [Item.Id]));
    try
      Drifted := Response.GetValue<TJSONArray>('drifted');
      Check(Drifted.Count = 2, 'The changed input and the Derived value are reported');
      Check(Codes(FindRow(Drifted, 'value_id', AreaId).GetValue<TJSONArray>('flags')) =
        'value_changed', 'The re-read input is reported');
      Row := FindRow(Drifted, 'value_id', DerivedId);
      Check(Codes(Row.GetValue<TJSONArray>('flags')) = 'value_changed,input_changed',
        'The Derived value is recomputed from the re-read input');
      Check(Abs(Row.GetValue<Double>('current_value') - 8e-7) < 1e-18,
        'The recomputed wear rate uses the new reader output');
    finally
      Response.Free;
    end;

    Items := TItemModel.Create(Notebook.Manager);
    try
      Items.RemoveValue(Notebook.Manager.Find<unit_Item.TValue>(CyclesId), Item,
        Notebook.Principal.Id);
    finally
      Items.Free;
    end;
    Check(Notebook.Manager.Find<unit_Item.TValue>(DerivedId) <> nil,
      'Deleting an input keeps the Derived value');
    Response := Call('check_value_drift', Format('{"item_id":%d}', [Item.Id]));
    try
      Row := FindRow(Response.GetValue<TJSONArray>('drifted'), 'value_id', DerivedId);
      Check(Pos('input_missing', Codes(Row.GetValue<TJSONArray>('flags'))) > 0,
        'A deleted input is reported as missing');
      Check(FindRow(Row.GetValue<TJSONArray>('inputs'), 'value_id', CyclesId)
        .GetValue<string>('status') = 'missing', 'The missing input is named');
    finally
      Response.Free;
    end;
  finally
    FreeAndNil(Registry);
    Context.PluginHost := nil;
    Host.Free;
    Plugin.Free;
    if TDirectory.Exists(PluginDir) then
      TDirectory.Delete(PluginDir, True);
  end;
end;

procedure RunValueSourceTests;
begin
  RunTest('add_value Reader source round-trips through get_values', TestReaderSourceRoundTrip);
  RunTest('add_value without source stores Unknown', TestMissingSourceStoresUnknown);
  RunTest('add_value refuses a source file from another project', TestForeignProjectSourceRefused);
  RunTest('add_value refuses a source file of an unrelated item', TestUnrelatedItemSourceRefused);
  RunTest('add_value accepts ancestor and descendant source files', TestRelatedItemSourcesAccepted);
  RunTest('add_values is all-or-nothing', TestBatchIsAllOrNothing);
  RunTest('add_value refuses out-of-range values until confirmed', TestRangeRefusedUntilConfirmed);
  RunTest('add_value refuses a tolerance larger than the value', TestToleranceScaleRefused);
  RunTest('report_value_issues lists confirmed issues and writes nothing', TestIssueReportIsReadOnly);
  RunTest('check_value_drift reports only changed reader output', TestValueDriftReportsOnlyChangedValue);
  RunTest('check_storage reports content mismatch and echoes the baseline',
    TestStorageCheckReportsContentMismatch);
  RunTest('add_derived_value computes, stores and reports the Derived source',
    TestDerivedValueThroughTools);
  RunTest('add_derived_value averages an array of wear areas',
    TestDerivedValueAveragesAreaArray);
  RunTest('add_derived_value refuses client numbers and invalid inputs',
    TestDerivedValueRefusals);
  RunTest('add_derived_value refuses a store without Derived tables',
    TestDerivedValueNeedsStorage);
  RunTest('check_value_drift re-reads Derived inputs and reports missing inputs',
    TestDerivedDriftReaderInputs);
end;

end.
