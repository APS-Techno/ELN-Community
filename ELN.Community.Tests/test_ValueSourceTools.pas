unit test_ValueSourceTools;

interface

procedure RunValueSourceTests;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.Generics.Collections,
  Vcl.Forms,
  Aurelius.Engine.ObjectManager,
  upfVisualClasses, upfIntf,
  unit_AuthorizationTestSupport,
  unit_MCPTools, unit_PluginHost, unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ToolsWrite, unit_ToolsValues, unit_ToolsNavigation, unit_ToolsFiles,
  unit_ToolsValueChecks,
  unit_Project, unit_Item, unit_ItemTypes, unit_ValueType,
  unit_FileType, unit_AuditLog, unit_FilePaths;

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
    SetLength(Result, 2);
    Result[0].Name := 'Thickness A';
    Result[0].Value := Parsed.GetValue<Double>('a') * OutputScale;
    Result[0].Units := 'nm';
    Result[0].RecType := prResult;
    Result[1].Name := 'Density B';
    Result[1].Value := Parsed.GetValue<Double>('b');
    Result[1].Units := 'g/cm3';
    Result[1].RecType := prResult;
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
    '"reader_id":"synthetic.reader","reader_version":"7","key_name":"Period"}',
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
    '"reader_id":"synthetic.reader","key_name":"Ratio"}',
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
    TypeId := NewValueType('Synthetic reader output', '', False, 0, 0);

    Response := Call('extract_file_key_values', Format('{"file_id":%d}', [FileId]));
    try
      Check(Response.FindValue('error') = nil, 'Key values are extracted');
      Check(Response.GetValue<Int64>('file_id') = FileId, 'The file id is returned');
      Check(Response.GetValue<string>('reader_id') = DRIFT_READER_ID,
        'The reader id is returned');
      ReaderVersion := Response.GetValue<string>('reader_version');
      Check(ReaderVersion = '1', 'The reader version is returned');
    finally
      Response.Free;
    end;

    Response := Call('add_values', Format(
      '{"values":[' +
      '{"item_id":%0:d,"value_type_id":%1:d,"value":2.5,"source_file_id":%2:d,' +
      '"reader_id":"%3:s","reader_version":"%4:s","key_name":"Thickness A"},' +
      '{"item_id":%0:d,"value_type_id":%1:d,"value":7,"source_file_id":%2:d,' +
      '"reader_id":"%3:s","reader_version":"%4:s","key_name":"Density B"}]}',
      [Item.Id, TypeId, FileId, DRIFT_READER_ID, ReaderVersion]));
    try
      Rows := Response.GetValue<TJSONArray>('values');
      ThicknessId := Rows.Items[0].GetValue<Integer>('id');
      DensityId := Rows.Items[1].GetValue<Integer>('id');
    finally
      Response.Free;
    end;

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
      Check(Row.GetValue<Double>('current_value') = 5, 'The current output is reported');
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
end;

end.
