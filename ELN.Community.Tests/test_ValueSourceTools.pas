unit test_ValueSourceTools;

interface

procedure RunValueSourceTests;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash,
  System.Generics.Collections, System.Variants, System.Math,
  Vcl.Forms,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq, Aurelius.Drivers.Interfaces,
  upfVisualClasses, upfIntf,
  unit_AuthorizationTestSupport,
  unit_MCPTools, unit_PluginHost, unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ToolsWrite, unit_ToolsValues, unit_ToolsNavigation, unit_ToolsFiles,
  unit_ToolsWiki,
  unit_ToolsValueChecks, unit_ToolsValueEdit, unit_ToolsMetadata,
  unit_Project, unit_Item, unit_ItemTypes, unit_ValueType, unit_User,
  unit_ReaderValueMapping,
  unit_FileType, unit_AuditLog, unit_FilePaths,
  unit_ItemModel, unit_DerivedFormulas, unit_ValueSource,
  unit_Hypothesis, unit_HypothesisRun, unit_HypothesisEvidence, unit_Signature,
  unit_AnalysisSettingsModel, unit_NotebookStorage, unit_ViewerStateModel,
  unit_ToolScope, unit_ToolsHypotheses, unit_ToolsSeries, unit_JSONCompact,
  unit_SeriesTable, unit_SeriesModel, unit_ActionType, unit_Series, unit_SeriesColumn,
  unit_ProjectModel;

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

  TFailingDeleteStorage = class(TInterfacedObject, INotebookStorage)
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

  TCopyInFailStorage = class(TInterfacedObject, INotebookStorage)
  private
    FInner: INotebookStorage;
  public
    FailOnCall: Integer;
    CopyInCalls: Integer;
    constructor Create(const Inner: INotebookStorage);
    procedure MoveFile(const OldPath, NewPath: string);
    function ReadBytes(const RelativePath: string): TBytes;
    procedure WriteBytes(const RelativePath: string; const Data: TBytes);
    procedure CopyIn(const SourcePath, RelativePath: string);
    procedure CopyOut(const RelativePath, TargetPath: string);
    function Exists(const RelativePath: string): Boolean;
    procedure DeleteFile(const RelativePath: string);
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

constructor TFailingDeleteStorage.Create(const Inner: INotebookStorage);
begin
  inherited Create;
  FInner := Inner;
end;

procedure TFailingDeleteStorage.MoveFile(const OldPath, NewPath: string);
begin
  FInner.MoveFile(OldPath, NewPath);
end;

function TFailingDeleteStorage.ReadBytes(const RelativePath: string): TBytes;
begin
  Result := FInner.ReadBytes(RelativePath);
end;

procedure TFailingDeleteStorage.WriteBytes(const RelativePath: string;
  const Data: TBytes);
begin
  FInner.WriteBytes(RelativePath, Data);
end;

procedure TFailingDeleteStorage.CopyIn(const SourcePath, RelativePath: string);
begin
  FInner.CopyIn(SourcePath, RelativePath);
end;

procedure TFailingDeleteStorage.CopyOut(const RelativePath, TargetPath: string);
begin
  FInner.CopyOut(RelativePath, TargetPath);
end;

function TFailingDeleteStorage.Exists(const RelativePath: string): Boolean;
begin
  Result := FInner.Exists(RelativePath);
end;

procedure TFailingDeleteStorage.DeleteFile(const RelativePath: string);
begin
  if RelativePath.StartsWith('Projects/') then
    raise EInOutError.Create('synthetic delete failure');
  FInner.DeleteFile(RelativePath);
end;

constructor TCopyInFailStorage.Create(const Inner: INotebookStorage);
begin
  inherited Create;
  FInner := Inner;
end;

procedure TCopyInFailStorage.MoveFile(const OldPath, NewPath: string);
begin
  FInner.MoveFile(OldPath, NewPath);
end;

function TCopyInFailStorage.ReadBytes(const RelativePath: string): TBytes;
begin
  Result := FInner.ReadBytes(RelativePath);
end;

procedure TCopyInFailStorage.WriteBytes(const RelativePath: string;
  const Data: TBytes);
begin
  FInner.WriteBytes(RelativePath, Data);
end;

procedure TCopyInFailStorage.CopyIn(const SourcePath, RelativePath: string);
begin
  Inc(CopyInCalls);
  if CopyInCalls = FailOnCall then
    raise EInOutError.Create('injected CopyIn failure');
  FInner.CopyIn(SourcePath, RelativePath);
end;

procedure TCopyInFailStorage.CopyOut(const RelativePath, TargetPath: string);
begin
  FInner.CopyOut(RelativePath, TargetPath);
end;

function TCopyInFailStorage.Exists(const RelativePath: string): Boolean;
begin
  Result := FInner.Exists(RelativePath);
end;

procedure TCopyInFailStorage.DeleteFile(const RelativePath: string);
begin
  FInner.DeleteFile(RelativePath);
end;

procedure Prepare(const Storage: INotebookStorage = nil);
begin
  if Storage = nil then
    Context.Storage := Notebook.Storage
  else
    Context.Storage := Storage;
  FreeAndNil(Registry);
  Registry := TToolRegistry.Create(Context);
  RegisterWriteTools(Registry);
  RegisterValueTools(Registry);
  RegisterNavigationTools(Registry);
  RegisterFileTools(Registry);
  RegisterValueCheckTools(Registry);
  RegisterValueEditTools(Registry);
  RegisterMetadataTools(Registry);
  RegisterWikiTools(Registry);
  RegisterHypothesisTools(Registry);
  RegisterSeriesTools(Registry);
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

function NewDownloadRoot: string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'ELN-DownloadRoot-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Result);
  Context.UploadRoot := Result;
  Prepare;
end;

function DownloadJSON(FileId: Int64; const DestPath: string;
  Overwrite: Boolean = False): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('file_id', TJSONNumber.Create(FileId));
    Obj.AddPair('dest_path', DestPath);
    Obj.AddPair('overwrite', TJSONBool.Create(Overwrite));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function TempFilesIn(const Dir: string): Integer;
begin
  if not TDirectory.Exists(Dir) then
    Exit(0);
  Result := Length(TDirectory.GetFiles(Dir, '*.tmp'));
end;

procedure CreateJunction(const LinkPath, TargetPath: string);
var
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  CommandLine: string;
  ExitCode: DWORD;
begin
  CommandLine := Format('cmd.exe /c mklink /J "%s" "%s"', [LinkPath, TargetPath]);
  UniqueString(CommandLine);
  StartupInfo := Default(TStartupInfo);
  StartupInfo.cb := SizeOf(StartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := SW_HIDE;
  if not CreateProcess(nil, PChar(CommandLine), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, StartupInfo, ProcessInfo) then
    RaiseLastOSError;
  try
    WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
    GetExitCodeProcess(ProcessInfo.hProcess, ExitCode);
  finally
    CloseHandle(ProcessInfo.hThread);
    CloseHandle(ProcessInfo.hProcess);
  end;
  Check((ExitCode = 0) and TDirectory.Exists(LinkPath), 'The junction fixture exists');
end;

procedure TestDownloadFileWritesStoredBytes;
var
  Project: TProject;
  Item: TItem;
  FileTypeId: Integer;
  GoodFile, ChangedFile: Int64;
  Good, Changed: unit_Item.TFile;
  Root, Dir, Dest, ChangedDest: string;
  Response: TJSONObject;
  Before: TRowSnapshot;
begin
  Root := NewDownloadRoot;
  try
    Project := AddProject(Notebook.Principal);
    Item := NewItem(Project, 0, 'Download item');
    FileTypeId := NewFileType('.vdl');
    GoodFile := StoreFile(Item, FileTypeId, 'intact', 'intact bytes');
    ChangedFile := StoreFile(Item, FileTypeId, 'altered', 'original bytes');
    Good := Notebook.Manager.Find<unit_Item.TFile>(GoodFile);
    Changed := Notebook.Manager.Find<unit_Item.TFile>(ChangedFile);
    Notebook.Storage.WriteBytes(AttachmentRelativePath(Project.FileFolder,
      Item.FolderName, Changed.FullName), TEncoding.UTF8.GetBytes('altered bytes!'));
    Before := TRowSnapshot.Take;

    Dir := TPath.Combine(Root, 'specimen\nested');
    Dest := TPath.Combine(Dir, 'intact.vdl');
    Response := Call('download_file', DownloadJSON(GoodFile, Dest));
    try
      Check(SameText(Response.GetValue<string>('dest_path'), Dest), 'dest_path is the full path');
      Check(Response.GetValue<Int64>('size') = Length('intact bytes'), 'size is the stored size');
      Check(SameText(Response.GetValue<string>('md5'), Good.Hash), 'md5 matches the upload hash');
      Check(Response.GetValue<string>('storage_status') = 'ok', 'An intact file is ok');
    finally
      Response.Free;
    end;
    Check(System.IOUtils.TFile.ReadAllText(Dest, TEncoding.UTF8) = 'intact bytes',
      'Missing parent folders are created and the stored bytes are written');

    ChangedDest := TPath.Combine(Dir, 'altered.vdl');
    Response := Call('download_file', DownloadJSON(ChangedFile, ChangedDest));
    try
      Check(Response.GetValue<string>('storage_status') = 'content_mismatch',
        'Changed bytes report content_mismatch');
      Check(Response.GetValue<Int64>('size') = Length('altered bytes!'),
        'The size is that of the bytes in storage');
      Check(not SameText(Response.GetValue<string>('md5'),
        Response.GetValue<string>('stored_hash')), 'md5 and stored_hash differ');
    finally
      Response.Free;
    end;
    Check(System.IOUtils.TFile.ReadAllText(ChangedDest, TEncoding.UTF8) = 'altered bytes!',
      'A mismatched file is still written');

    ExpectRefused('download_file', DownloadJSON(ChangedFile, Dest), 'already exists');
    Check(System.IOUtils.TFile.ReadAllText(Dest, TEncoding.UTF8) = 'intact bytes',
      'overwrite false keeps the existing contents');
    Response := Call('download_file', DownloadJSON(ChangedFile, Dest, True));
    Response.Free;
    Check(System.IOUtils.TFile.ReadAllText(Dest, TEncoding.UTF8) = 'altered bytes!',
      'overwrite true replaces the file');

    Check(TempFilesIn(Dir) = 0, 'No temporary file is left');
    Check(TRowSnapshot.Take.SameAs(Before), 'download_file writes nothing to the notebook');
  finally
    TDirectory.Delete(Root, True);
  end;
end;

procedure TestDownloadFileRefusals;
var
  Project, Foreign: TProject;
  Item, Gone, ForeignItem: TItem;
  FileTypeId: Integer;
  GoodFile, MissingFile, GoneFile, ForeignFile: Int64;
  F: unit_Item.TFile;
  Root, Outside, Link, Dest, Missing, Hidden: string;
  Before: TRowSnapshot;
begin
  Root := NewDownloadRoot;
  Outside := TPath.Combine(TPath.GetTempPath,
    'ELN-DownloadOutside-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Outside);
  Link := TPath.Combine(Root, 'link');
  try
    Project := AddProject(Notebook.Principal);
    Foreign := AddProject(Notebook.Principal);
    FileTypeId := NewFileType('.vdl');
    Item := NewItem(Project, 0, 'Download item');
    GoodFile := StoreFile(Item, FileTypeId, 'intact', 'intact bytes');
    MissingFile := StoreFile(Item, FileTypeId, 'gone', 'soon gone');
    F := Notebook.Manager.Find<unit_Item.TFile>(MissingFile);
    Notebook.Storage.DeleteFile(AttachmentRelativePath(Project.FileFolder,
      Item.FolderName, F.FullName));
    Gone := NewItem(Project, 0, 'Deleted item');
    GoneFile := StoreFile(Gone, FileTypeId, 'deleted', 'deleted bytes');
    Gone.IsDeleted := True;
    Notebook.Manager.Flush;
    ForeignItem := NewItem(Foreign, 0, 'Foreign item');
    ForeignFile := StoreFile(ForeignItem, FileTypeId, 'foreign', 'foreign bytes');
    Before := TRowSnapshot.Take;

    Dest := TPath.Combine(Root, 'out\missing.vdl');
    ExpectRefused('download_file', DownloadJSON(MissingFile, Dest), 'storage_status missing');
    Check(not FileExists(Dest), 'Missing bytes write no file');
    Check(TempFilesIn(ExtractFileDir(Dest)) = 0, 'Missing bytes leave no temporary file');

    ExpectRefused('download_file', DownloadJSON(GoodFile,
      TPath.Combine(Outside, 'a.vdl')), 'outside the allowed upload root');
    ExpectRefused('download_file', DownloadJSON(GoodFile,
      Root + '\..\' + ExtractFileName(Outside) + '\b.vdl'), 'outside the allowed upload root');
    CreateJunction(Link, Outside);
    ExpectRefused('download_file', DownloadJSON(GoodFile,
      TPath.Combine(Link, 'c.vdl')), 'reparse point');
    Check(Length(TDirectory.GetFiles(Outside)) = 0, 'Refused paths are not written');

    ExpectRefused('download_file', DownloadJSON(GoneFile,
      TPath.Combine(Root, 'deleted.vdl')), 'deleted item');

    Context.ScopedProjects := [Project.Id];
    Prepare;
    Missing := ExpectRefused('download_file', DownloadJSON(999999,
      TPath.Combine(Root, 'x.vdl')), 'outside');
    Hidden := ExpectRefused('download_file', DownloadJSON(ForeignFile,
      TPath.Combine(Root, 'x.vdl')), 'outside');
    Check(Missing = Hidden, 'Missing and out-of-scope files share one refusal');
    Check(not FileExists(TPath.Combine(Root, 'x.vdl')), 'A hidden file is not written');

    Context.UploadRoot := '';
    Prepare;
    ExpectRefused('download_file', DownloadJSON(GoodFile,
      TPath.Combine(Root, 'y.vdl')), 'disabled');
    Check(TRowSnapshot.Take.SameAs(Before), 'Refused downloads write nothing to the notebook');
  finally
    if TDirectory.Exists(Link) then
      RemoveDir(Link);
    TDirectory.Delete(Root, True);
    TDirectory.Delete(Outside, True);
  end;
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

const
  EDIT_READER_ID = 'synthetic.edit-reader';

function RowCount(const SQL: string): Integer;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
begin
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand(SQL);
  Rows := Statement.ExecuteQuery;
  Check(Rows.Next, 'A count query returns one row');
  Result := StrToInt(VarToStr(Rows.GetFieldValue(0)));
end;

function StoredSnapshot(ValueId: Integer): string;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
begin
  Result := '';
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand(Format('SELECT SettingValue FROM DBSettings WHERE ' +
    'SettingKey = ''%s''', [TAnalysisSettingsModel.ValueKey(EDIT_READER_ID, ValueId)]));
  Rows := Statement.ExecuteQuery;
  if Rows.Next then
    Result := VarToStr(Rows.GetFieldValue(0));
end;

function AuditRows(EntityType: TAuditEntityType; EntityId: Int64): TList<TAuditLog>;
var
  Observer: TObjectManager;
  Rows: TList<TAuditLog>;
  Row: TAuditLog;
begin
  Result := TObjectList<TAuditLog>.Create(True);
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Rows := Observer.Find<TAuditLog>.Where((Linq['EntityType'] = Ord(EntityType)) and
      (Linq['EntityId'] = EntityId)).OrderBy('Id').List;
    try
      for Row in Rows do
      begin
        Observer.Evict(Row);
        Result.Add(Row);
      end;
    finally
      Rows.Free;
    end;
  finally
    Observer.Free;
  end;
end;

function ValueExists(ValueId: Integer): Boolean;
begin
  Result := RowCount(Format('SELECT COUNT(*) FROM DataValues WHERE Id = %d',
    [ValueId])) = 1;
end;

function StoredNumber(ValueId: Integer): Double;
var
  Observer: TObjectManager;
begin
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Result := StoredValue(Observer, ValueId).Value;
  finally
    Observer.Free;
  end;
end;

procedure SignItem(ItemId: Integer);
var
  Signature: TSignature;
begin
  Signature := TSignature.Create;
  Signature.ItemId := ItemId;
  Signature.UserId := Notebook.Principal.Id;
  Signature.UserName := 'Synthetic Scientist';
  Signature.SignedDate := Now;
  Signature.Meaning := 'Reviewed';
  Signature.ContentHash := StringOfChar('0', 64);
  Notebook.Manager.Save(Signature);
  Notebook.Manager.Flush;
end;

function AddLockedHypothesis(Project: TProject; Status: THypothesisStatus): Integer;
var
  H: THypothesis;
begin
  H := AddHypothesis(Project);
  H.Status := Status;
  Notebook.Manager.Flush;
  Result := H.Id;
end;

procedure AddRun(HypothesisId, ItemId: Integer);
var
  Run: THypothesisRun;
begin
  Run := THypothesisRun.Create;
  Run.HypothesisId := HypothesisId;
  Run.ItemId := ItemId;
  Run.Role := hrrRun;
  Run.AddedBy := Notebook.Principal.Id;
  Run.AddedDate := Now;
  Notebook.Manager.Save(Run);
  Notebook.Manager.Flush;
end;

procedure AddValueEvidence(HypothesisId, ItemId, ValueId: Integer);
var
  Evidence: THypothesisEvidence;
begin
  Evidence := THypothesisEvidence.Create;
  Evidence.HypothesisId := HypothesisId;
  Evidence.ItemId := ItemId;
  Evidence.ValueId := ValueId;
  Evidence.AddedBy := Notebook.Principal.Id;
  Evidence.AddedDate := Now;
  Notebook.Manager.Save(Evidence);
  Notebook.Manager.Flush;
end;

function SnapshotFor(FileId: Int64; const Content, Marker: string): string;
var
  Hash: THashMD5;
begin
  Hash := THashMD5.Create;
  Hash.Update(TEncoding.UTF8.GetBytes(Content));
  Result := Format('{"file_id":%d,"file_hash":"%s","marker":"%s"}',
    [FileId, UpperCase(Hash.HashAsString), Marker]);
end;

function ItemListsValue(ItemId, ValueId: Integer): Boolean;
var
  Response: TJSONObject;
begin
  Response := Call('get_item', Format('{"item_id":%d}', [ItemId]));
  try
    Result := Assigned(FindRow(Response.GetValue<TJSONArray>('values'), 'id', ValueId));
  finally
    Response.Free;
  end;
end;

function ItemValueNumber(ItemId, ValueId: Integer): Double;
var
  Response: TJSONObject;
  Row: TJSONObject;
begin
  Response := Call('get_item', Format('{"item_id":%d}', [ItemId]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'id', ValueId);
    Check(Assigned(Row), Format('get_item must list value %d', [ValueId]));
    Result := Row.GetValue<Double>('value');
  finally
    Response.Free;
  end;
end;

procedure TestRemoveValueWritesItemAudit;
var
  Project: TProject;
  Item: TItem;
  TypeId, KeepId, GoneId: Integer;
  Before: TRowSnapshot;
  Response: TJSONObject;
  Audit: TList<TAuditLog>;
  Logs: TJSONArray;
  Log: TJSONValue;
  Found: Boolean;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Removal target');
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  KeepId := AddManual(Item.Id, TypeId, 10);
  GoneId := CallId('add_value', Format('{"item_id":%d,"value_type_id":%d,' +
    '"value":42.125,"tolerance":0.5,"description":"old fit","source_note":"lab"}',
    [Item.Id, TypeId]));
  Check(ItemListsValue(Item.Id, GoneId), 'The session caches the item with the value');
  Before := TRowSnapshot.Take;

  Response := Call('remove_value', Format(
    '{"value_id":%d,"reason":"reader fix"}', [GoneId]));
  try
    Check(Response.GetValue<Integer>('id') = GoneId, 'The response names the removed value');
    Check(Response.GetValue<Double>('value') = 42.125, 'The response carries the old number');
    Check(Response.GetValue<string>('description') = 'old fit',
      'The response carries the old description');
    Check(Response.GetValue<TJSONArray>('dependent_derived_value_ids').Count = 0,
      'A plain value has no dependents');
  finally
    Response.Free;
  end;

  Check(not ValueExists(GoneId), 'The value row is deleted');
  Check(ValueExists(KeepId), 'Other values of the item stay');
  Check(TRows.Count<unit_Item.TValue> = Before.Values - 1,
    'Exactly one value row is deleted');
  Check(TRows.Count<TAuditLog> = Before.Audits + 1, 'One audit row per removed value');
  Audit := AuditRows(aetItem, Item.Id);
  try
    Check(Audit.Count = 1, 'The removal is audited on the item');
    Check(Audit[0].Operation = aoUpdate, 'The item audit row is an update');
    Check(Audit[0].UserId = Notebook.Principal.Id, 'The removal is attributed');
    Check(Pos(Format('Removed value %d', [GoneId]), Audit[0].Description) > 0,
      'The audit row names the value: ' + Audit[0].Description);
    Check(Pos('value 42.125, tolerance 0.5', Audit[0].Description) > 0,
      'The audit row keeps the old number: ' + Audit[0].Description);
    Check(Pos('reason "reader fix"', Audit[0].Description) > 0,
      'The audit row keeps the reason');
    Check(Pos('description "old fit"', Audit[0].Description) > 0,
      'The audit row keeps the old description');
  finally
    Audit.Free;
  end;

  Response := Call('get_audit_log', Format('{"entity_type":"Item","entity_id":%d}',
    [Item.Id]));
  try
    Logs := Response.GetValue<TJSONArray>('audit_log');
    Found := False;
    for Log in Logs do
      if Pos('value 42.125', Log.GetValue<string>('description')) > 0 then
        Found := True;
    Check(Found, 'get_audit_log shows the old number after the hard delete');
  finally
    Response.Free;
  end;

  Check(not ItemListsValue(Item.Id, GoneId), 'The cached item no longer lists the value');
  Before := TRowSnapshot.Take;
  ExpectRefused('remove_value', Format('{"value_id":%d}', [GoneId]),
    'outside this session');
  ExpectRefused('update_value', Format('{"value_id":%d,"value":1}', [GoneId]),
    'outside this session');
  Check(TRowSnapshot.Take.SameAs(Before), 'A removed value cannot be removed again');
end;

procedure TestValueEditRefusals;
var
  Project, Foreign: TProject;
  Item, Signed, Deleted, ForeignItem, RunItem, CitedItem: TItem;
  TypeId, ValueId, SignedId, DeletedId, ForeignId, LockedRunId, CitedId, HypId: Integer;
  Before: TRowSnapshot;
  Missing, Hidden: string;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Foreign := AddProject(Notebook.Principal);
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  Item := NewItem(Project, 0, 'Open item');
  ValueId := AddManual(Item.Id, TypeId, 1);
  Signed := NewItem(Project, 0, 'Signed item');
  SignedId := AddManual(Signed.Id, TypeId, 2);
  SignItem(Signed.Id);
  Deleted := NewItem(Project, 0, 'Deleted item');
  DeletedId := AddManual(Deleted.Id, TypeId, 3);
  Deleted.IsDeleted := True;
  Notebook.Manager.Flush;
  ForeignItem := NewItem(Foreign, 0, 'Foreign item');
  ForeignId := AddManual(ForeignItem.Id, TypeId, 4);
  RunItem := NewItem(Project, 0, 'Run item');
  LockedRunId := AddManual(RunItem.Id, TypeId, 5);
  AddRun(AddLockedHypothesis(Project, hsInReview), RunItem.Id);
  CitedItem := NewItem(Project, 0, 'Cited item');
  CitedId := AddManual(CitedItem.Id, TypeId, 6);
  AddValueEvidence(AddLockedHypothesis(Project, hsAccepted), CitedItem.Id, CitedId);
  HypId := AddLockedHypothesis(Project, hsApproved);
  AddValueEvidence(HypId, Item.Id, ValueId);

  Before := TRowSnapshot.Take;
  ExpectRefused('remove_value', Format('{"value_id":%d}', [SignedId]), 'is signed');
  ExpectRefused('update_value', Format('{"value_id":%d,"value":9}', [SignedId]),
    'is signed');
  ExpectRefused('remove_value', Format('{"value_id":%d}', [DeletedId]),
    'deleted item');
  ExpectRefused('update_value', Format('{"value_id":%d,"value":9}', [DeletedId]),
    'deleted item');
  ExpectRefused('remove_value', Format('{"value_id":%d}', [LockedRunId]),
    '(InReview)');
  ExpectRefused('update_value', Format('{"value_id":%d,"value":9}', [LockedRunId]),
    '(InReview)');
  ExpectRefused('remove_value', Format('{"value_id":%d}', [CitedId]), '(Accepted)');
  ExpectRefused('update_value', Format('{"value_id":%d,"description":"x"}', [CitedId]),
    '(Accepted)');

  Context.ScopedProjects := [Project.Id];
  Prepare;
  Missing := ExpectRefused('remove_value', '{"value_id":999999}', 'outside');
  Hidden := ExpectRefused('remove_value', Format('{"value_id":%d}', [ForeignId]),
    'outside');
  Check(Missing = Hidden, 'Missing and out-of-scope values share one refusal');
  Hidden := ExpectRefused('update_value', Format('{"value_id":%d,"value":9}',
    [ForeignId]), 'outside');
  Check(Missing = Hidden, 'update_value gives the same refusal out of scope');
  Check(TRowSnapshot.Take.SameAs(Before), 'Refused edits write nothing');
  Check(ValueExists(ForeignId) and (StoredNumber(SignedId) = 2),
    'Refused values are unchanged');

  Response := Call('remove_value', Format('{"value_id":%d}', [ValueId]));
  Response.Free;
  Check(not ValueExists(ValueId),
    'An Approved hypothesis citing the value does not block the removal');
end;

procedure TestRemoveDerivedInputKeepsDerived;
var
  Project: TProject;
  Item: TItem;
  AreaId, ForceId, CyclesId, DerivedId: Integer;
  Response: TJSONObject;
  Dependents: TJSONArray;
  Audit: TList<TAuditLog>;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Wear item');
  AreaId := AddManual(Item.Id, AreaType, 0.004);
  ForceId := AddManual(Item.Id, ForceType, 5);
  CyclesId := AddManual(Item.Id, CyclesType, 1000);
  DerivedId := CallId('add_derived_value', DerivedCall(Item.Id,
    WEAR_RATE_FORMULA_ID, AreaId, ForceId, CyclesId));

  Response := Call('remove_value', Format('{"value_id":%d}', [ForceId]));
  try
    Dependents := Response.GetValue<TJSONArray>('dependent_derived_value_ids');
    Check((Dependents.Count = 1) and
      ((Dependents.Items[0] as TJSONNumber).AsInt = DerivedId),
      'The response names the Derived value that used the input');
  finally
    Response.Free;
  end;
  Check(ValueExists(DerivedId), 'Removing an input keeps the Derived value');
  Check(RowCount(Format('SELECT COUNT(*) FROM DerivedValueInputs WHERE ' +
    'ResultValueId = %d', [DerivedId])) = 3, 'The Derived value keeps its input rows');
  Audit := AuditRows(aetItem, Item.Id);
  try
    Check(Pos(Format('input of Derived values %d', [DerivedId]),
      Audit.Last.Description) > 0, 'The audit row names the dependent value');
  finally
    Audit.Free;
  end;

  Response := Call('remove_values', Format('{"value_ids":[%d,%d]}',
    [CyclesId, DerivedId]));
  try
    Check(Response.GetValue<Integer>('count') = 2, 'Both values are removed');
    Check(Response.GetValue<TJSONArray>('values').Items[0]
      .GetValue<TJSONArray>('dependent_derived_value_ids').Count = 0,
      'A Derived value removed in the same call is not a dependent');
  finally
    Response.Free;
  end;
  Check(RowCount(Format('SELECT COUNT(*) FROM DerivedValueInputs WHERE ' +
    'ResultValueId = %d', [DerivedId])) = 0, 'A removed Derived value takes its input rows');
  Check(ValueExists(AreaId), 'Values outside the batch stay');
end;

procedure TestRemoveValuesIsAllOrNothing;
var
  Project: TProject;
  Item, Signed: TItem;
  TypeId, A, B, C: Integer;
  Before, After: TRowSnapshot;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Batch item');
  Signed := NewItem(Project, 0, 'Signed batch item');
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  A := AddManual(Item.Id, TypeId, 1);
  B := AddManual(Item.Id, TypeId, 2);
  C := AddManual(Signed.Id, TypeId, 3);
  SignItem(Signed.Id);
  Before := TRowSnapshot.Take;
  ExpectRefused('remove_values', Format('{"value_ids":[%d,999999]}', [A]),
    'value_ids[1]');
  ExpectRefused('remove_values', Format('{"value_ids":[%d,%d,%d]}', [A, B, C]),
    'value_ids[2]');
  ExpectRefused('remove_values', Format('{"value_ids":[%d,%d]}', [A, A]), 'repeats');
  ExpectRefused('remove_values', '{"value_ids":[]}', 'empty');
  Check(TRowSnapshot.Take.SameAs(Before), 'A refused batch removes nothing');

  Response := Call('remove_values', Format('{"value_ids":[%d,%d],"reason":"retake"}',
    [A, B]));
  try
    Check(Response.GetValue<Integer>('count') = 2, 'The batch reports both values');
  finally
    Response.Free;
  end;
  After := TRowSnapshot.Take;
  Check(After.Values = Before.Values - 2, 'Two value rows are deleted');
  Check(After.Audits = Before.Audits + 2, 'One audit row per removed value');
  Check(not ValueExists(A) and not ValueExists(B) and ValueExists(C),
    'Only the listed values are removed');
end;

procedure TestUpdateManualValue;
var
  Project: TProject;
  Item: TItem;
  TypeId, RangedId, ValueId, DerivedId: Integer;
  Before: TRowSnapshot;
  Response: TJSONObject;
  Audit: TList<TAuditLog>;
  Observer: TObjectManager;
  Stored: unit_Item.TValue;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Update item');
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  RangedId := NewValueType('Synthetic thickness', 'm', True, 1e-9, 1e-5);
  ValueId := CallId('add_value', Format('{"item_id":%d,"value_type_id":%d,' +
    '"value":12.5,"tolerance":0.25,"description":"first fit","source_note":"lab"}',
    [Item.Id, TypeId]));
  Check(ItemValueNumber(Item.Id, ValueId) = 12.5, 'The session caches the old number');
  Before := TRowSnapshot.Take;

  Response := Call('update_value', Format(
    '{"value_id":%d,"value":13.75,"tolerance":0.5,"description":"second fit"}',
    [ValueId]));
  try
    Check(Response.GetValue<Boolean>('changed'), 'The update reports a change');
    Check(Response.GetValue<Double>('value') = 13.75, 'The response has the new number');
    Check(Response.GetValue<TJSONObject>('previous').GetValue<Double>('value') = 12.5,
      'The response has the old number');
    Check(Response.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Manual',
      'The source kind does not change');
  finally
    Response.Free;
  end;
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Stored := StoredValue(Observer, ValueId);
    Check((Stored.Value = 13.75) and (Stored.Tol = 0.5) and
      (Stored.Description = 'second fit'), 'The new fields are stored');
    Check(Stored.SourceNote = 'lab', 'The source fields stay');
    Check(Stored.ModifiedBy.HasValue and (Stored.ModifiedBy.Value = Notebook.Principal.Id),
      'The change is attributed on the row');
  finally
    Observer.Free;
  end;
  Check(TRows.Count<TAuditLog> = Before.Audits + 1, 'One audit row per update');
  Audit := AuditRows(aetValue, ValueId);
  try
    Check(Audit.Last.Operation = aoUpdate, 'The update is audited on the value');
    Check(Pos('value 12.5, tolerance 0.25', Audit.Last.Description) > 0,
      'The audit row keeps the old number: ' + Audit.Last.Description);
    Check(Pos('description "first fit"', Audit.Last.Description) > 0,
      'The audit row keeps the old description');
  finally
    Audit.Free;
  end;
  Check(ItemValueNumber(Item.Id, ValueId) = 13.75, 'The cached item shows the new number');

  Before := TRowSnapshot.Take;
  Response := Call('update_value', Format('{"value_id":%d,"value":13.75}', [ValueId]));
  try
    Check(not Response.GetValue<Boolean>('changed'), 'An equal value is not a change');
  finally
    Response.Free;
  end;
  ExpectRefused('update_value', Format('{"value_id":%d}', [ValueId]), 'Nothing to change');
  ExpectRefused('update_value', Format('{"value_id":%d,"source_note":"x"}', [ValueId]),
    'remove_value plus add_value');
  ExpectRefused('update_value', Format('{"value_id":%d,"colour":"x"}', [ValueId]),
    'Unknown parameter colour');
  ExpectRefused('update_value', Format('{"value_id":%d,"reader_version":"2"}', [ValueId]),
    'only to a Reader value');
  ExpectRefused('update_value', Format('{"value_id":%d,"value_type_id":%d}',
    [ValueId, RangedId]), 'above_range');
  ExpectRefused('update_value', Format('{"value_id":%d,"value_type_id":%d}',
    [ValueId, 999999]), 'ValueType not found');
  ExpectRefused('update_value', Format('{"value_id":%d,"rec_type":"OTHER"}', [ValueId]),
    'Invalid rec_type');
  Check(TRowSnapshot.Take.SameAs(Before), 'Refused and unchanged updates write nothing');
  Check(StoredNumber(ValueId) = 13.75, 'Refused updates keep the number');

  Response := Call('update_value', Format('{"value_id":%d,"value_type_id":%d,' +
    '"rec_type":"EXP_CONDITION","confirm_out_of_range":true}', [ValueId, RangedId]));
  try
    Check(Codes(Response.GetValue<TJSONArray>('confirmed_issues')) = 'above_range',
      'A confirmed update reports its issues');
    Check(Response.GetValue<string>('rec_type') = 'EXP_CONDITION', 'rec_type changes');
  finally
    Response.Free;
  end;

  DerivedId := CallId('add_derived_value', DerivedCall(Item.Id, WEAR_RATE_FORMULA_ID,
    AddManual(Item.Id, AreaType, 0.004), AddManual(Item.Id, ForceType, 5),
    AddManual(Item.Id, CyclesType, 1000)));
  ExpectRefused('update_value', Format('{"value_id":%d,"value":1}', [DerivedId]),
    'add_derived_value');
  Response := Call('update_value', Format('{"value_id":%d,"description":"wear K"}',
    [DerivedId]));
  try
    Check(Response.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Derived',
      'A Derived description can change without changing the source');
  finally
    Response.Free;
  end;
end;

procedure TestUpdateReaderValueAfterReaderFix;
var
  Project: TProject;
  Item: TItem;
  TypeId, ValueId: Integer;
  FileId: Int64;
  Response: TJSONObject;
  Audit: TList<TAuditLog>;
  Before: TRowSnapshot;
  Snapshot: string;
const
  CONTENT = 'synthetic step scan';
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Reader fix item');
  FileId := StoreFile(Item, NewFileType('.vstep'), 'scan', CONTENT);
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  ValueId := CallId('add_value', Format('{"item_id":%d,"value_type_id":%d,' +
    '"value":80,"source_file_id":%d,"reader_id":"%s","reader_version":"1",' +
    '"key_name":"Step Height","reader_units":"nm","conversion_factor":1,' +
    '"analysis_snapshot":%s}',
    [Item.Id, TypeId, FileId, EDIT_READER_ID, SnapshotFor(FileId, CONTENT, 'old')]));
  Check(Pos('"marker":"old"', StoredSnapshot(ValueId)) > 0, 'The first snapshot is stored');

  Before := TRowSnapshot.Take;
  ExpectRefused('update_value', Format('{"value_id":%d,"analysis_snapshot":%s}',
    [ValueId, SnapshotFor(FileId, 'other bytes', 'bad')]), 'file_hash');
  ExpectRefused('update_value', Format('{"value_id":%d,"key_name":"Other"}', [ValueId]),
    'remove_value plus add_value');
  Check(TRowSnapshot.Take.SameAs(Before), 'A refused snapshot writes nothing');
  Check(Pos('"marker":"old"', StoredSnapshot(ValueId)) > 0, 'The old snapshot stays');

  Response := Call('update_value', Format('{"value_id":%d,"value":92.5,' +
    '"reader_version":"2","analysis_snapshot":%s}',
    [ValueId, SnapshotFor(FileId, CONTENT, 'new')]));
  try
    Check(Response.GetValue<TJSONObject>('source').GetValue<string>('reader_version') = '2',
      'The reader version changes');
    Check(Response.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Reader',
      'The value stays a Reader value');
    Check(Response.GetValue<TJSONObject>('previous').GetValue<string>('reader_version') = '1',
      'The response has the old reader version');
  finally
    Response.Free;
  end;
  Snapshot := StoredSnapshot(ValueId);
  Check((Pos('"marker":"new"', Snapshot) > 0) and
    (Pos(Format('"value_id":%d', [ValueId]), Snapshot) > 0),
    'The new snapshot replaces the old one: ' + Snapshot);
  Check(StoredNumber(ValueId) = 92.5, 'The new number is stored');
  Audit := AuditRows(aetValue, ValueId);
  try
    Check(Pos('value 80, tolerance 0', Audit.Last.Description) > 0,
      'The audit row keeps the old number: ' + Audit.Last.Description);
    Check(Pos('reader version "1"', Audit.Last.Description) > 0,
      'The audit row keeps the old reader version');
  finally
    Audit.Free;
  end;

  Response := Call('update_value', Format('{"value_id":%d,"analysis_snapshot":""}',
    [ValueId]));
  Response.Free;
  Check(StoredSnapshot(ValueId) = '', 'An empty analysis_snapshot deletes the snapshot');

  Response := Call('update_value', Format('{"value_id":%d,"analysis_snapshot":%s}',
    [ValueId, SnapshotFor(FileId, CONTENT, 'again')]));
  Response.Free;
  Check(StoredSnapshot(ValueId) <> '', 'A snapshot can be stored again');
  Response := Call('remove_value', Format('{"value_id":%d}', [ValueId]));
  Response.Free;
  Check(StoredSnapshot(ValueId) = '', 'remove_value deletes the analysis snapshot');
end;

function FileEntry(Arr: TJSONArray; FileId: Int64): TJSONObject;
begin
  Result := FindRow(Arr, 'id', FileId);
  Check(Assigned(Result), 'File ' + IntToStr(FileId) + ' is listed');
end;

function FileDeleted(Arr: TJSONArray; FileId: Int64): Boolean;
begin
  Result := FileEntry(Arr, FileId).GetValue<Boolean>('is_deleted');
end;

procedure TestFileStatusShowsLiveDuplicates;
var
  Project: TProject;
  Item: TItem;
  FileTypeId: Integer;
  First, Second: Int64;
  Response: TJSONObject;
  Files: TJSONArray;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Duplicate files');
  FileTypeId := NewFileType('.vdup');
  First := StoreFile(Item, FileTypeId, 'same', 'same bytes');
  Second := StoreFile(Item, FileTypeId, 'same', 'same bytes');

  Response := Call('list_files', Format('{"item_id":%d,"check_storage":true}', [Item.Id]));
  try
    Files := Response.GetValue<TJSONArray>('files');
    Check(Files.Count = 2, 'Both duplicates are listed');
    Check(not FileDeleted(Files, First) and not FileDeleted(Files, Second),
      'Live duplicates are not deleted');
    Check(FileEntry(Files, First).GetValue<string>('storage_status') = 'ok',
      'First duplicate has bytes');
    Check(FileEntry(Files, Second).GetValue<string>('storage_status') = 'ok',
      'Second duplicate has bytes');
  finally
    Response.Free;
  end;

  Response := Call('get_item', Format('{"item_id":%d}', [Item.Id]));
  try
    Files := Response.GetValue<TJSONArray>('files');
    Check(not FileDeleted(Files, First) and not FileDeleted(Files, Second),
      'get_item shows live duplicates as not deleted');
  finally
    Response.Free;
  end;

  Response := Call('list_files', Format('{"item_id":%d}', [Item.Id]));
  try
    Files := Response.GetValue<TJSONArray>('files');
    Check(FileEntry(Files, First).FindValue('storage_status') = nil,
      'storage_status is absent without check_storage');
  finally
    Response.Free;
  end;
end;

procedure TestFileStatusReportsMissingBytes;
var
  Project: TProject;
  Item: TItem;
  FileTypeId: Integer;
  FileId: Int64;
  F: unit_Item.TFile;
  Response: TJSONObject;
  Files: TJSONArray;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Missing bytes');
  FileTypeId := NewFileType('.vmiss');
  FileId := StoreFile(Item, FileTypeId, 'gone', 'soon gone');
  F := Notebook.Manager.Find<unit_Item.TFile>(FileId);
  Notebook.Storage.DeleteFile(AttachmentRelativePath(Project.FileFolder,
    Item.FolderName, F.FullName));

  Response := Call('list_files', Format('{"item_id":%d,"check_storage":true}', [Item.Id]));
  try
    Files := Response.GetValue<TJSONArray>('files');
    Check(FileEntry(Files, FileId).GetValue<string>('storage_status') = 'missing',
      'A record without bytes is missing');
    Check(not FileDeleted(Files, FileId), 'A missing file is not deleted');
  finally
    Response.Free;
  end;
end;

procedure TestFileStatusFollowsRecycleBin;
var
  Project: TProject;
  ItemA, ParentP, ChildB: TItem;
  FileTypeId: Integer;
  FileA, FileB: Int64;
  Items: TItemModel;
  Response: TJSONObject;
  Files: TJSONArray;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ItemA := NewItem(Project, 0, 'Deleted item');
  ParentP := NewItem(Project, 0, 'Deleted parent');
  ChildB := NewItem(Project, ParentP.Id, 'Live child');
  FileTypeId := NewFileType('.vbin');
  FileA := StoreFile(ItemA, FileTypeId, 'on A', 'a bytes');
  FileB := StoreFile(ChildB, FileTypeId, 'on B', 'b bytes');
  Items := TItemModel.Create(Notebook.Manager);
  try
    Check(Items.DeleteItem(ItemA, Notebook.Principal.Id), 'Item A moves to the recycle bin');
    Check(Items.DeleteItem(ParentP, Notebook.Principal.Id), 'Parent P moves to the recycle bin');
  finally
    Items.Free;
  end;

  Response := Call('list_files', Format('{"item_id":%d}', [ItemA.Id]));
  try
    Check(FileDeleted(Response.GetValue<TJSONArray>('files'), FileA),
      'A file of a deleted item is deleted');
  finally
    Response.Free;
  end;
  Response := Call('list_files', Format('{"item_id":%d}', [ChildB.Id]));
  try
    Check(FileDeleted(Response.GetValue<TJSONArray>('files'), FileB),
      'A file under a deleted ancestor is deleted');
  finally
    Response.Free;
  end;
  Response := Call('get_item', Format('{"item_id":%d}', [ChildB.Id]));
  try
    Files := Response.GetValue<TJSONArray>('files');
    Check(FileDeleted(Files, FileB), 'get_item reports the ancestor deletion');
  finally
    Response.Free;
  end;
  Response := Call('get_item', Format('{"item_id":%d}', [ItemA.Id]));
  try
    Check(Response.GetValue<Boolean>('is_deleted'), 'Item-level is_deleted stays true');
    Check(FileDeleted(Response.GetValue<TJSONArray>('files'), FileA),
      'get_item reports the item deletion');
  finally
    Response.Free;
  end;
end;

procedure TestWikiSkipsMarkdownWithoutBytes;
var
  Project: TProject;
  Item: TItem;
  MdTypeId: Integer;
  M1Id, M2Id: Int64;
  M1, M2: unit_Item.TFile;
  Path1, Path2, Refusal: string;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Wiki duplicates');
  MdTypeId := NewFileType('.md');
  M1Id := StoreFile(Item, MdTypeId, 'page-old', 'stale body');
  M2Id := StoreFile(Item, MdTypeId, 'page-live', 'live body');
  M1 := Notebook.Manager.Find<unit_Item.TFile>(M1Id);
  M2 := Notebook.Manager.Find<unit_Item.TFile>(M2Id);
  Path1 := AttachmentRelativePath(Project.FileFolder, Item.FolderName, M1.FullName);
  Path2 := AttachmentRelativePath(Project.FileFolder, Item.FolderName, M2.FullName);
  Notebook.Storage.DeleteFile(Path1);

  Response := Call('wiki_get_page', Format('{"item_id":%d}', [Item.Id]));
  try
    Check(Response.GetValue<string>('body_md') = 'live body',
      'The page body comes from the markdown file that has bytes');
  finally
    Response.Free;
  end;

  Response := Call('wiki_update_page', Format('{"item_id":%d,"body_md":"new body"}',
    [Item.Id]));
  Response.Free;
  Check(not Notebook.Storage.Exists(Path1), 'The update does not resurrect the record without bytes');
  Check(TEncoding.UTF8.GetString(Notebook.Storage.ReadBytes(Path2)) = 'new body',
    'The update writes the markdown file that has bytes');

  Notebook.Storage.DeleteFile(Path2);
  Refusal := ExpectRefused('wiki_get_page', Format('{"item_id":%d}', [Item.Id]),
    'missing from storage');
  Check(Pos(IntToStr(M1Id), Refusal) > 0, 'The refusal names the first candidate: ' + Refusal);
end;

procedure ExpectStorageFailure(const Tool, JSON: string);
var
  Response: TJSONObject;
  Raised: Boolean;
begin
  Raised := False;
  try
    Response := Call(Tool, JSON);
    Response.Free;
  except
    on E: Exception do
    begin
      Raised := True;
      Check(E is EInOutError, Tool + ' keeps the storage error class for the transport ' +
        'sanitizer, got ' + E.ClassName);
      Check(Pos('injected CopyIn failure', E.Message) > 0, 'The storage error is kept: ' + E.Message);
    end;
  end;
  Check(Raised, Tool + ' must fail: ' + JSON);
end;

function PrepareWiki: TCopyInFailStorage;
var
  Root: string;
begin
  Root := TPath.Combine(TPath.GetDirectoryName(Notebook.DatabasePath), 'upload');
  TDirectory.CreateDirectory(Root);
  Context.UploadRoot := Root;
  Result := TCopyInFailStorage.Create(Notebook.Storage);
  Prepare(Result);
end;

function WikiAttachment(const Name, Content: string): string;
begin
  Result := TPath.Combine(Context.UploadRoot, Name);
  System.IOUtils.TFile.WriteAllBytes(Result, TEncoding.UTF8.GetBytes(Content));
end;

function WikiCreateJSON(ProjectId: Integer; const Title, Body: string;
  const Attachments: array of string): string;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  Path: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('project_id', TJSONNumber.Create(ProjectId));
    Obj.AddPair('section', 'Analysis');
    Obj.AddPair('title', Title);
    Obj.AddPair('body_md', Body);
    if Length(Attachments) > 0 then
    begin
      Arr := TJSONArray.Create;
      for Path in Attachments do
        Arr.Add(Path);
      Obj.AddPair('attachments', Arr);
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function WikiUpdateJSON(ItemId: Integer; const Body: string;
  const Attachments: array of string): string;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  Path: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('item_id', TJSONNumber.Create(ItemId));
    Obj.AddPair('body_md', Body);
    if Length(Attachments) > 0 then
    begin
      Arr := TJSONArray.Create;
      for Path in Attachments do
        Arr.Add(Path);
      Obj.AddPair('attachments', Arr);
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function StorageFileCount: Integer;
var
  Dir: string;
begin
  Dir := TPath.Combine(Notebook.StorageRoot, 'Projects');
  if TDirectory.Exists(Dir) then
    Result := Length(TDirectory.GetFiles(Dir, '*', TSearchOption.soAllDirectories))
  else
    Result := 0;
end;

function CreateWikiPage(ProjectId: Integer; const Title, Body: string;
  const Attachments: array of string): Integer;
var
  Response: TJSONObject;
begin
  Response := Call('wiki_create_page', WikiCreateJSON(ProjectId, Title, Body, Attachments));
  try
    Result := Response.GetValue<Integer>('item_id');
  finally
    Response.Free;
  end;
end;

function WikiBody(ItemId: Integer): string;
var
  Response: TJSONObject;
begin
  Response := Call('wiki_get_page', Format('{"item_id":%d}', [ItemId]));
  try
    Result := Response.GetValue<string>('body_md');
  finally
    Response.Free;
  end;
end;

procedure CheckStoredFilesIntact(ItemId: Integer; ExpectedCount: Integer);
var
  Observer: TObjectManager;
  Item: TItem;
  Project: TProject;
  F: unit_Item.TFile;
  Path: string;
begin
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Item := Observer.Find<TItem>(ItemId);
    Check(Assigned(Item), Format('Item %d must exist', [ItemId]));
    Project := Observer.Find<TProject>(Item.ProjectID);
    Check(Item.Files.Count = ExpectedCount,
      Format('Item %d must have %d files, has %d', [ItemId, ExpectedCount, Item.Files.Count]));
    for F in Item.Files do
    begin
      Path := AttachmentRelativePath(Project.FileFolder, Item.FolderName, F.FullName);
      Check(Notebook.Storage.Exists(Path), 'Bytes must exist for ' + Path);
      Check(SameText(ComputeFileMD5(TPath.Combine(Notebook.StorageRoot, Path)), F.Hash),
        'Stored bytes must match the recorded hash for ' + Path);
    end;
  finally
    Observer.Free;
  end;
end;

procedure TestWikiCreateWritesPageAndAttachments;
var
  Project: TProject;
  Before: TRowSnapshot;
  ItemId: Integer;
begin
  PrepareWiki;
  Project := AddProject(Notebook.Principal);
  NewFileType('.md');
  NewFileType('.txt');
  Before := TRowSnapshot.Take;
  ItemId := CreateWikiPage(Project.Id, 'Plan', 'body text',
    [WikiAttachment('a.txt', 'alpha'), WikiAttachment('b.txt', 'beta')]);
  Check(TRows.Count<TItem> = Before.Items + 1, 'One page item is created');
  Check(TRows.Count<unit_Item.TFile> = Before.Files + 3, 'Body and two attachments are recorded');
  Check(StorageFileCount = 3, 'Three files are stored');
  CheckStoredFilesIntact(ItemId, 3);
  Check(WikiBody(ItemId) = 'body text', 'The page body reads back');
end;

procedure CheckWikiFailureLeavesNothing(Storage: TCopyInFailStorage; FailAfter: Integer);
var
  Project: TProject;
  Before: TRowSnapshot;
  StoredBefore, ExistingId: Integer;
  Attachments: TArray<string>;
begin
  Project := AddProject(Notebook.Principal);
  NewFileType('.md');
  NewFileType('.txt');
  ExistingId := CreateWikiPage(Project.Id, 'Existing', 'existing body',
    [WikiAttachment('keep.txt', 'keep')]);
  Attachments := [WikiAttachment('a.txt', 'alpha'), WikiAttachment('b.txt', 'beta')];
  Before := TRowSnapshot.Take;
  StoredBefore := StorageFileCount;

  Storage.FailOnCall := Storage.CopyInCalls + FailAfter;
  ExpectStorageFailure('wiki_create_page', WikiCreateJSON(Project.Id, 'Plan', 'body text',
    Attachments));
  Check(TRowSnapshot.Take.SameAs(Before), 'A failed create leaves no item, file or audit row');
  Check(StorageFileCount = StoredBefore, 'A failed create leaves no stored bytes');
  CheckStoredFilesIntact(ExistingId, 2);
  Check(WikiBody(ExistingId) = 'existing body', 'The existing page keeps its body');

  Storage.FailOnCall := 0;
  CheckStoredFilesIntact(CreateWikiPage(Project.Id, 'Plan', 'body text', Attachments), 3);
end;

procedure TestWikiCreateBodyCopyFailureLeavesNothing;
begin
  CheckWikiFailureLeavesNothing(PrepareWiki, 1);
end;

procedure TestWikiCreateAttachmentCopyFailureLeavesNothing;
begin
  CheckWikiFailureLeavesNothing(PrepareWiki, 3);
end;

procedure TestWikiCreateMissingMarkdownTypeWritesNothing;
var
  Project: TProject;
  Before: TRowSnapshot;
begin
  PrepareWiki;
  Project := AddProject(Notebook.Principal);
  Before := TRowSnapshot.Take;
  ExpectRefused('wiki_create_page', WikiCreateJSON(Project.Id, 'Plan', 'body', []),
    'No FileTypes row for ".md"');
  Check(TRows.Count<TItem> = Before.Items, 'No page item is created');
  Check(TRows.Count<unit_Item.TFile> = Before.Files, 'No file row is created');
  Check(StorageFileCount = 0, 'No bytes are stored');
end;

procedure TestWikiCreateRefusesCaseDuplicate;
var
  Project: TProject;
  Before: TRowSnapshot;
begin
  PrepareWiki;
  Project := AddProject(Notebook.Principal);
  NewFileType('.md');
  CreateWikiPage(Project.Id, 'Notes', 'first', []);
  Before := TRowSnapshot.Take;
  ExpectRefused('wiki_create_page', WikiCreateJSON(Project.Id, 'notes', 'second', []),
    'already exists');
  Check(TRowSnapshot.Take.SameAs(Before), 'A duplicate title writes nothing');
end;

procedure TestWikiCreateMissingAttachmentSourceWritesNothing;
var
  Project: TProject;
  Before: TRowSnapshot;
begin
  PrepareWiki;
  Project := AddProject(Notebook.Principal);
  NewFileType('.md');
  NewFileType('.txt');
  Before := TRowSnapshot.Take;
  ExpectRefused('wiki_create_page', WikiCreateJSON(Project.Id, 'Plan', 'body',
    [WikiAttachment('a.txt', 'alpha'), TPath.Combine(Context.UploadRoot, 'absent.txt')]),
    'Attachment not found');
  Check(TRows.Count<TItem> = Before.Items, 'No page item is created');
  Check(TRows.Count<unit_Item.TFile> = Before.Files, 'No file row is created');
  Check(StorageFileCount = 0, 'No bytes are stored');
end;

procedure TestWikiUpdateFailureRestoresBody;
var
  Storage: TCopyInFailStorage;
  Project: TProject;
  Before: TRowSnapshot;
  ItemId, StoredBefore: Integer;
begin
  Storage := PrepareWiki;
  Project := AddProject(Notebook.Principal);
  NewFileType('.md');
  NewFileType('.txt');
  ItemId := CreateWikiPage(Project.Id, 'Plan', 'old body', []);
  Before := TRowSnapshot.Take;
  StoredBefore := StorageFileCount;

  Storage.FailOnCall := Storage.CopyInCalls + 2;
  ExpectStorageFailure('wiki_update_page', WikiUpdateJSON(ItemId, 'new body',
    [WikiAttachment('a.txt', 'alpha')]));
  Check(TRowSnapshot.Take.SameAs(Before), 'A failed update leaves no new row');
  Check(StorageFileCount = StoredBefore, 'A failed update leaves no new bytes');
  CheckStoredFilesIntact(ItemId, 1);
  Check(WikiBody(ItemId) = 'old body', 'A failed update restores the old body');
end;

type
  TDeleteFixture = record
    Item: TItem;
    FileId: Int64;
    ReaderA, ReaderB, ManualId: Integer;
    Path, Hash: string;
  end;

const
  DELETE_CONTENT = 'synthetic step scan';
  DELETE_REAL = '{"file_id":%d,"dry_run":false%s}';

procedure AddFileEvidence(HypothesisId, ItemId: Integer; FileId: Int64);
var
  Evidence: THypothesisEvidence;
begin
  Evidence := THypothesisEvidence.Create;
  Evidence.HypothesisId := HypothesisId;
  Evidence.ItemId := ItemId;
  Evidence.FileId := FileId;
  Evidence.AddedBy := Notebook.Principal.Id;
  Evidence.AddedDate := Now;
  Notebook.Manager.Save(Evidence);
  Notebook.Manager.Flush;
end;

procedure AddReference(HypothesisId, ItemId: Integer);
var
  Run: THypothesisRun;
begin
  Run := THypothesisRun.Create;
  Run.HypothesisId := HypothesisId;
  Run.ItemId := ItemId;
  Run.Role := hrrReference;
  Run.AddedBy := Notebook.Principal.Id;
  Run.AddedDate := Now;
  Notebook.Manager.Save(Run);
  Notebook.Manager.Flush;
end;

procedure AddItemEvidence(HypothesisId, ItemId: Integer);
var
  Evidence: THypothesisEvidence;
begin
  Evidence := THypothesisEvidence.Create;
  Evidence.HypothesisId := HypothesisId;
  Evidence.ItemId := ItemId;
  Evidence.AddedBy := Notebook.Principal.Id;
  Evidence.AddedDate := Now;
  Notebook.Manager.Save(Evidence);
  Notebook.Manager.Flush;
end;

function FindHypotheses(const ItemIds: array of Integer): TJSONObject;
var
  Arr: TJSONArray;
  Id: Integer;
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    for Id in ItemIds do
      Arr.Add(Id);
    Obj.AddPair('item_ids', Arr);
    Result := Call('find_hypotheses_for_item', Obj.ToJSON);
  finally
    Obj.Free;
  end;
end;

function LinkKey(HypothesisId: Integer; const Kind: string; Link: TJSONObject): string;
begin
  Result := Format('%d|%s', [HypothesisId, Kind]);
  if Kind = 'Evidence' then
    Result := Result + '|' + Link.GetValue('evidence_id').ToJSON + '|' +
      Link.GetValue('file_id').ToJSON + '|' + Link.GetValue('value_id').ToJSON;
end;

function ToolLinkKeys(Entry: TJSONObject): TStringList;
var
  Hyp, Link: TJSONValue;
  HypId: Integer;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupAccept;
  for Hyp in Entry.GetValue<TJSONArray>('hypotheses') do
  begin
    HypId := (Hyp as TJSONObject).GetValue<Integer>('hypothesis_id');
    for Link in (Hyp as TJSONObject).GetValue<TJSONArray>('links') do
      Result.Add(LinkKey(HypId, (Link as TJSONObject).GetValue<string>('kind'),
        TJSONObject(Link)));
  end;
end;

function DetailLinkKeys(ItemId: Integer; const HypothesisIds: array of Integer): TStringList;
var
  HypId: Integer;
  Detail: TJSONObject;
  Row: TJSONValue;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupAccept;
  for HypId in HypothesisIds do
  begin
    Detail := Call('get_hypothesis', Format('{"hypothesis_id":%d}', [HypId]));
    try
      for Row in Detail.GetValue<TJSONArray>('runs') do
        if (Row as TJSONObject).GetValue('item_id').ToJSON = IntToStr(ItemId) then
          Result.Add(LinkKey(HypId, (Row as TJSONObject).GetValue<string>('role'),
            TJSONObject(Row)));
      for Row in Detail.GetValue<TJSONArray>('evidence') do
        if (Row as TJSONObject).GetValue('item_id').ToJSON = IntToStr(ItemId) then
          Result.Add(LinkKey(HypId, 'Evidence', TJSONObject(Row)));
    finally
      Detail.Free;
    end;
  end;
end;

function EntryFor(Response: TJSONObject; ItemId: Integer): TJSONObject;
begin
  Result := FindRow(Response.GetValue<TJSONArray>('items'), 'item_id', ItemId);
  Check(Assigned(Result), Format('Item %d must have an entry', [ItemId]));
end;

procedure TestFindHypothesesReturnsAllLinkKinds;
var
  Project: TProject;
  Item: TItem;
  H1, H2, ValueId: Integer;
  FileId: Int64;
  Response, Detail, Hyp: TJSONObject;
  Keys: TStringList;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Linked item');
  H1 := AddLockedHypothesis(Project, hsApproved);
  H2 := AddLockedHypothesis(Project, hsInReview);
  FileId := StoreFile(Item, NewFileType('.vsrc'), 'scan', 'bytes');
  ValueId := AddManual(Item.Id, NewValueType('Synthetic step', 'nm', False, 0, 0), 5);
  AddRun(H1, Item.Id);
  AddReference(H2, Item.Id);
  AddItemEvidence(H1, Item.Id);
  AddFileEvidence(H1, Item.Id, FileId);
  AddValueEvidence(H1, Item.Id, ValueId);

  Response := FindHypotheses([Item.Id]);
  try
    Keys := ToolLinkKeys(EntryFor(Response, Item.Id));
    try
      Check(Keys.Count = 5, 'Run, Reference and three evidence rows: ' + Keys.CommaText);
      Check(Keys.IndexOf(Format('%d|Run', [H1])) >= 0, 'The Run link is listed');
      Check(Keys.IndexOf(Format('%d|Reference', [H2])) >= 0, 'The Reference link is listed');
    finally
      Keys.Free;
    end;
    Hyp := FindRow(EntryFor(Response, Item.Id).GetValue<TJSONArray>('hypotheses'),
      'hypothesis_id', H1);
    Check(Hyp.GetValue<TJSONArray>('links').Count = 4, 'H1 groups its four links');
    Detail := Call('get_hypothesis', Format('{"hypothesis_id":%d}', [H1]));
    try
      Check(Hyp.GetValue<string>('status') = Detail.GetValue<string>('status'),
        'The status matches get_hypothesis');
      Check(Hyp.GetValue('outcome').ToJSON = Detail.GetValue('outcome').ToJSON,
        'The outcome matches get_hypothesis');
      Check(Hyp.GetValue<string>('title') = Detail.GetValue<string>('title'),
        'The title matches get_hypothesis');
      Check(Hyp.GetValue<Integer>('project_id') = Project.Id, 'The project is listed');
    finally
      Detail.Free;
    end;
  finally
    Response.Free;
  end;
end;

procedure TestFindHypothesesMatchesGetHypothesis;
var
  Project: TProject;
  Items: array[0..2] of TItem;
  Hyps: array[0..2] of Integer;
  I, TypeId: Integer;
  Response: TJSONObject;
  Expected, Actual: TStringList;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  for I := 0 to 2 do
  begin
    Items[I] := NewItem(Project, 0, 'Item ' + IntToStr(I));
    Hyps[I] := AddLockedHypothesis(Project, hsApproved);
  end;
  AddRun(Hyps[0], Items[0].Id);
  AddRun(Hyps[1], Items[0].Id);
  AddReference(Hyps[2], Items[0].Id);
  AddItemEvidence(Hyps[0], Items[0].Id);
  AddItemEvidence(Hyps[0], Items[0].Id);
  AddRun(Hyps[2], Items[1].Id);
  AddValueEvidence(Hyps[1], Items[1].Id, AddManual(Items[1].Id, TypeId, 2));

  Response := FindHypotheses([Items[0].Id, Items[1].Id, Items[2].Id]);
  try
    for I := 0 to 2 do
    begin
      Expected := DetailLinkKeys(Items[I].Id, Hyps);
      Actual := ToolLinkKeys(EntryFor(Response, Items[I].Id));
      try
        Check(Expected.Text = Actual.Text, Format('Item %d links: expected %s, got %s',
          [I, Expected.CommaText, Actual.CommaText]));
      finally
        Expected.Free;
        Actual.Free;
      end;
    end;
  finally
    Response.Free;
  end;
end;

procedure TestFindHypothesesUnavailableItemsAreUniform;
var
  Project: TProject;
  Item, Hidden, Deleted: TItem;
  Response: TJSONObject;
  Missing, Foreign: string;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Plain item');
  Deleted := NewItem(Project, 0, 'Binned item');
  Deleted.IsDeleted := True;
  Notebook.Manager.Flush;
  AddRun(AddLockedHypothesis(Project, hsApproved), Deleted.Id);
  Hidden := NewItem(AddProject(AddUser('hidden-owner', dbUser)), 0, 'Hidden item');

  Response := FindHypotheses([999999, Hidden.Id, Item.Id, Item.Id, Deleted.Id]);
  try
    Check(Response.GetValue<TJSONArray>('items').Count = 4, 'A repeated id counts once');
    Missing := EntryFor(Response, 999999).GetValue<string>('error');
    Foreign := EntryFor(Response, Hidden.Id).GetValue<string>('error');
    Check(Missing = 'Item 999999 is not available.', 'Missing item message: ' + Missing);
    Check(Foreign = Format('Item %d is not available.', [Hidden.Id]),
      'Unreadable item message: ' + Foreign);
    Check(EntryFor(Response, Hidden.Id).Count = 2, 'An unavailable entry has only item_id and error');
    Check(EntryFor(Response, Item.Id).GetValue<TJSONArray>('hypotheses').Count = 0,
      'An item without links has an empty list');
    Check(EntryFor(Response, Deleted.Id).GetValue<Boolean>('is_deleted'),
      'An item in the recycle bin is flagged');
    Check(EntryFor(Response, Deleted.Id).GetValue<TJSONArray>('hypotheses').Count = 1,
      'An item in the recycle bin still lists its links');
  finally
    Response.Free;
  end;
end;

procedure TestFindHypothesesHidesForeignHypothesis;
var
  Project: TProject;
  Item: TItem;
  Foreign: THypothesis;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Visible item');
  Foreign := AddHypothesis(AddProject(AddUser('hidden-owner', dbUser)));
  Foreign.Title := 'Secret foreign expectation';
  Notebook.Manager.Flush;
  AddReference(Foreign.Id, Item.Id);

  Response := FindHypotheses([Item.Id]);
  try
    Check(EntryFor(Response, Item.Id).GetValue<TJSONArray>('hypotheses').Count = 0,
      'A link to an unreadable hypothesis is removed');
    Check(Pos('Secret foreign expectation', Response.ToJSON) = 0, 'The title does not leak');
    Check(Pos(Format('"hypothesis_id":%d', [Foreign.Id]), Response.ToJSON) = 0,
      'The id does not leak');
  finally
    Response.Free;
  end;
end;

procedure TestFindHypothesesScopedSession;
var
  P1, P2: TProject;
  Item, Other: TItem;
  Local, Remote: Integer;
  Response: TJSONObject;
  Keys: TStringList;
begin
  P1 := AddProject(Notebook.Principal);
  P2 := AddProject(Notebook.Principal);
  Item := NewItem(P1, 0, 'Scoped item');
  Other := NewItem(P2, 0, 'Other project item');
  Local := AddLockedHypothesis(P1, hsApproved);
  Remote := AddLockedHypothesis(P2, hsApproved);
  AddRun(Local, Item.Id);
  AddReference(Remote, Item.Id);
  Context.ScopedProjects := [P1.Id];
  Prepare;

  Response := FindHypotheses([Item.Id, Other.Id]);
  try
    Keys := ToolLinkKeys(EntryFor(Response, Item.Id));
    try
      Check(Keys.CommaText = Format('%d|Run', [Local]),
        'Only the in-scope hypothesis is listed: ' + Keys.CommaText);
    finally
      Keys.Free;
    end;
    Check(EntryFor(Response, Other.Id).GetValue<string>('error') =
      Format('Item %d is not available.', [Other.Id]), 'An out-of-scope item is unavailable');
  finally
    Response.Free;
  end;
end;

procedure TestFindHypothesesLimits;
var
  Ids: TArray<Integer>;
  I: Integer;
  Response: TJSONObject;
begin
  Prepare;
  SetLength(Ids, 200);
  for I := 0 to High(Ids) do
    Ids[I] := 100000 + I;
  Response := FindHypotheses(Ids);
  try
    Check(Response.GetValue<TJSONArray>('items').Count = 200, '200 ids are accepted');
  finally
    Response.Free;
  end;
  ExpectRefused('find_hypotheses_for_item', '{"item_ids":[' +
    StringReplace(StringOfChar('1', 200), '1', '1,', [rfReplaceAll]) + '1]}', 'item_ids');
  ExpectRefused('find_hypotheses_for_item', '{"item_ids":[]}', 'item_ids');
  ExpectRefused('find_hypotheses_for_item', '{"item_ids":[0]}', 'item_ids');
  ExpectRefused('find_hypotheses_for_item', '{"item_ids":[-1]}', 'item_ids');
  ExpectRefused('find_hypotheses_for_item', '{"item_ids":["5"]}', 'item_ids');
  ExpectRefused('find_hypotheses_for_item', '{}', 'item_ids');
end;

procedure TestFindHypothesesWritesNothing;
var
  Project: TProject;
  Item: TItem;
  Before: TRowSnapshot;
  Runs, Evidence, Hyps: Integer;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Read-only item');
  AddRun(AddLockedHypothesis(Project, hsApproved), Item.Id);
  Before := TRowSnapshot.Take;
  Runs := TRows.Count<THypothesisRun>;
  Evidence := TRows.Count<THypothesisEvidence>;
  Hyps := TRows.Count<THypothesis>;
  Response := FindHypotheses([Item.Id]);
  Response.Free;
  Check(TRowSnapshot.Take.SameAs(Before), 'No item, file, value or audit row changes');
  Check((TRows.Count<THypothesisRun> = Runs) and
    (TRows.Count<THypothesisEvidence> = Evidence) and
    (TRows.Count<THypothesis> = Hyps), 'No hypothesis row changes');
end;

function crt_strtod(Str: PAnsiChar; EndPtr: PPAnsiChar): Double; cdecl;
  external 'ucrtbase.dll' name 'strtod';

// Delphi's Win64 float text conversion is not correctly rounded in the last
// digit, so the UCRT parser is the oracle for exact JSON numbers.
function ParseExact(const Text: string; out Value: Double): Boolean;
var
  A: AnsiString;
  Stop: PAnsiChar;
begin
  A := AnsiString(Text);
  Value := crt_strtod(PAnsiChar(A), @Stop);
  Result := (A <> '') and (Stop^ = #0);
end;

function BitsToDouble(Bits: Int64): Double;
begin
  Result := PDouble(@Bits)^;
end;

type
  TExactSample = record
    Bits: Int64;
    Text: string;
  end;

const
  EXACT_SAMPLES: array[0..11] of TExactSample = (
    (Bits: 4579388775385388062; Text: '0.014285714285714287'),
    (Bits: 4599676419421066581; Text: '0.3333333333333333'),
    (Bits: 9218868437227405311; Text: '1.7976931348623157e+308'),
    (Bits: 4591870180174331904; Text: '0.10000000149011612'),
    (Bits: -4540151737703765857; Text: '-123456.789012345'),
    (Bits: 118622047889322841; Text: '1e-300'),
    (Bits: 1; Text: '4.94065645841247e-324'),
    (Bits: 4508321993853365645; Text: '2.5e-7'),
    (Bits: 4591870180066957722; Text: '0.1'),
    (Bits: 4846369599423283201; Text: '10000000000000002'),
    (Bits: 4638387860618067575; Text: '123.456'),
    (Bits: -4674685261256255423; Text: '-0.000123456789'));

procedure TestExactNumRoundTrips;
var
  Sample: TExactSample;
  V, Back: Double;
  Json: TJSONValue;
  Text: string;
begin
  for Sample in EXACT_SAMPLES do
  begin
    V := BitsToDouble(Sample.Bits);
    Json := ExactNum(V);
    try
      Check(Json is TJSONNumber, 'A finite value is a JSON number');
      Text := Json.ToJSON;
      Check(Text = Sample.Text, Format('Bits %d: expected %s, got %s',
        [Sample.Bits, Sample.Text, Text]));
      Check(ParseExact(Text, Back) and (Back = V),
        Format('%s must parse back to the identical Double', [Text]));
    finally
      Json.Free;
    end;
  end;
  Json := ExactNum(9007199254740992.0);
  try
    Check(Json.ToJSON = '9007199254740992', '2^53 is written as an integer: ' + Json.ToJSON);
  finally
    Json.Free;
  end;
  V := BitsToDouble(Low(Int64));
  Json := ExactNum(V);
  try
    Check(Json.ToJSON = '-0', 'Negative zero keeps its sign: ' + Json.ToJSON);
    Check(ParseExact(Json.ToJSON, Back) and (PInt64(@Back)^ = Low(Int64)),
      'Negative zero reads back with the sign bit set');
  finally
    Json.Free;
  end;
  Json := ExactNum(3e9);
  try
    Check(Json.ToJSON = '3000000000', 'An integral value is written as an integer: ' + Json.ToJSON);
  finally
    Json.Free;
  end;
  Json := ExactNum(0.1);
  try
    Check(Json.ToJSON = '0.1', 'The shortest exact form is used: ' + Json.ToJSON);
  finally
    Json.Free;
  end;
  Json := ExactNum(NaN);
  try
    Check(Json is TJSONNull, 'NaN is written as null');
  finally
    Json.Free;
  end;
  Json := ExactNum(Infinity);
  try
    Check(Json is TJSONNull, 'Infinity is written as null');
  finally
    Json.Free;
  end;
end;

procedure CheckFields(Obj: TJSONObject; const Names: array of string; const Where: string);
var
  Name: string;
begin
  for Name in Names do
    Check(Obj.FindValue(Name) <> nil, Format('%s keeps the field %s', [Where, Name]));
end;

procedure SetStoredNumbers(ValueId: Integer; Value, Tol: Double);
var
  Stored: unit_Item.TValue;
begin
  Stored := Notebook.Manager.Find<unit_Item.TValue>(ValueId);
  Stored.Value := Value;
  Stored.Tol := Tol;
  Notebook.Manager.Flush;
end;

function JSONDouble(Obj: TJSONObject; const Name: string): Double;
begin
  Check(Obj.GetValue(Name) is TJSONNumber, Name + ' is a JSON number');
  Check(ParseExact(Obj.GetValue(Name).ToJSON, Result),
    Name + ' parses as a number: ' + Obj.GetValue(Name).ToJSON);
end;

const
  GET_VALUES_FIELDS: array[0..7] of string = ('id', 'type_symbol', 'type_title',
    'units', 'value', 'tolerance', 'description', 'source');
  QUERY_VALUES_FIELDS: array[0..12] of string = ('value_id', 'item_id', 'item_title',
    'project_id', 'project_title', 'type_symbol', 'type_title', 'units', 'value',
    'tolerance', 'rec_type', 'created_date', 'source');

procedure TestGetValuesAddsTypeRoleAndAncestors;
var
  Project: TProject;
  Root, Mid, Leaf: TItem;
  TypeId, CondId, ResId: Integer;
  FileId: Int64;
  Response, Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Root := NewItem(Project, 0, 'Root run');
  Mid := NewItem(Project, Root.Id, 'Middle step');
  Leaf := NewItem(Project, Mid.Id, 'Leaf specimen');
  TypeId := NewValueType('Synthetic period', 'nm', False, 0, 0);
  CondId := CallId('add_value', Format('{"item_id":%d,"value_type_id":%d,"value":2,' +
    '"rec_type":"EXP_CONDITION","source_note":"lab book"}', [Leaf.Id, TypeId]));
  FileId := StoreFile(Leaf, NewFileType('.vsrc'), 'scan', 'synthetic scan');
  ResId := CallId('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":3.2,"rec_type":"TEST_RESULT",' +
    '"source_file_id":%d,"reader_id":"synthetic.reader","reader_version":"7",' +
    '"key_name":"Period","reader_units":"A","conversion_factor":0.1}',
    [Leaf.Id, TypeId, FileId]));

  Response := Call('get_values', Format('{"item_id":%d}', [Leaf.Id]));
  try
    Check(Response.GetValue<Integer>('item_id') = Leaf.Id, 'The item id is listed');
    Check(Response.GetValue<Integer>('project_id') = Project.Id, 'The project id is listed');
    Check(Response.GetValue('ancestor_ids').ToJSON = Format('[%d,%d]', [Root.Id, Mid.Id]),
      'Ancestors go from the root to the parent: ' + Response.GetValue('ancestor_ids').ToJSON);
    Check(Response.FindValue('ancestors_incomplete') = nil, 'A complete chain has no flag');

    Row := FindRow(Response.GetValue<TJSONArray>('conditions'), 'id', CondId);
    Check(Assigned(Row), 'The condition is listed');
    CheckFields(Row, GET_VALUES_FIELDS, 'get_values');
    Check(Row.GetValue<Integer>('type_id') = TypeId, 'The condition has its type id');
    Check(Row.GetValue<string>('rec_type') = 'EXP_CONDITION', 'The condition has its role');
    Check(Row.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Manual',
      'The Manual source is unchanged');

    Row := FindRow(Response.GetValue<TJSONArray>('results'), 'id', ResId);
    Check(Assigned(Row), 'The result is listed');
    CheckFields(Row, GET_VALUES_FIELDS, 'get_values');
    Check(Row.GetValue<Integer>('type_id') = TypeId, 'The result has its type id');
    Check(Row.GetValue<string>('rec_type') = 'TEST_RESULT', 'The result has its role');
    Check(Row.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Reader',
      'The Reader source is unchanged');
  finally
    Response.Free;
  end;
end;

procedure TestGetValuesRootItemHasNoAncestors;
var
  Root: TItem;
  Response: TJSONObject;
begin
  Prepare;
  Root := NewItem(AddProject(Notebook.Principal), 0, 'Root run');
  AddManual(Root.Id, NewValueType('Synthetic step', 'nm', False, 0, 0), 1);
  Response := Call('get_values', Format('{"item_id":%d}', [Root.Id]));
  try
    Check(Response.GetValue('ancestor_ids').ToJSON = '[]', 'A root item has no ancestors');
    Check(Response.FindValue('ancestors_incomplete') = nil, 'A root chain is complete');
  finally
    Response.Free;
  end;
end;

procedure TestQueryValuesAddsTypeIdAndAncestors;
var
  Project: TProject;
  Root, Mid, Leaf: TItem;
  TypeId, RootValue, LeafValue: Integer;
  Response, Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Root := NewItem(Project, 0, 'Root run');
  Mid := NewItem(Project, Root.Id, 'Middle step');
  Leaf := NewItem(Project, Mid.Id, 'Leaf specimen');
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  RootValue := AddManual(Root.Id, TypeId, 1);
  LeafValue := AddManual(Leaf.Id, TypeId, 2);

  Response := Call('query_values', Format('{"project_id":%d}', [Project.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'value_id', LeafValue);
    Check(Assigned(Row), 'The leaf value is listed');
    CheckFields(Row, QUERY_VALUES_FIELDS, 'query_values');
    Check(Row.GetValue<Integer>('type_id') = TypeId, 'The leaf row has its type id');
    Check(Row.GetValue('ancestor_ids').ToJSON = Format('[%d,%d]', [Root.Id, Mid.Id]),
      'The leaf row lists its ancestors: ' + Row.GetValue('ancestor_ids').ToJSON);
    Check(Row.FindValue('ancestors_incomplete') = nil, 'A complete chain has no flag');

    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'value_id', RootValue);
    Check(Assigned(Row), 'The root value is listed');
    CheckFields(Row, QUERY_VALUES_FIELDS, 'query_values');
    Check(Row.GetValue('ancestor_ids').ToJSON = '[]', 'The root row has no ancestors');
  finally
    Response.Free;
  end;
end;

procedure TestValueAncestorsStopAtMissingParent;
var
  Project: TProject;
  Orphan: TItem;
  ValueId: Integer;
  Response, Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Orphan := NewItem(Project, 999999, 'Orphan specimen');
  ValueId := AddManual(Orphan.Id, NewValueType('Synthetic step', 'nm', False, 0, 0), 1);

  Response := Call('get_values', Format('{"item_id":%d}', [Orphan.Id]));
  try
    Check(Response.GetValue('ancestor_ids').ToJSON = '[]', 'No ancestor is known');
    Check(Response.GetValue<Boolean>('ancestors_incomplete'), 'The chain is flagged incomplete');
  finally
    Response.Free;
  end;
  Response := Call('query_values', Format('{"project_id":%d}', [Project.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'value_id', ValueId);
    Check(Row.GetValue<Boolean>('ancestors_incomplete'), 'The row is flagged incomplete');
  finally
    Response.Free;
  end;
end;

procedure TestValueToolsKeepExactNumbers;
var
  Project: TProject;
  Item: TItem;
  Narrow: Single;
  Samples, Tols: TArray<Double>;
  Ids: TArray<Integer>;
  TypeId, I: Integer;
  Response, Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Precise item');
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  Narrow := 0.1;
  Samples := [0.1, 1 / 3, -123456.789012345, 3e9, 1e-300, Narrow];
  SetLength(Ids, Length(Samples));
  SetLength(Tols, Length(Samples));
  for I := 0 to High(Samples) do
  begin
    Tols[I] := Abs(Samples[I]) / 7;
    Ids[I] := AddManual(Item.Id, TypeId, 1);
    SetStoredNumbers(Ids[I], Samples[I], Tols[I]);
  end;

  Response := Call('get_values', Format('{"item_id":%d}', [Item.Id]));
  try
    for I := 0 to High(Samples) do
    begin
      Row := FindRow(Response.GetValue<TJSONArray>('results'), 'id', Ids[I]);
      Check(JSONDouble(Row, 'value') = Samples[I],
        'get_values keeps the stored value: ' + Row.GetValue('value').ToJSON);
      Check(JSONDouble(Row, 'tolerance') = Tols[I],
        'get_values keeps the stored tolerance: ' + Row.GetValue('tolerance').ToJSON);
    end;
  finally
    Response.Free;
  end;
  Response := Call('query_values', Format('{"project_id":%d}', [Project.Id]));
  try
    for I := 0 to High(Samples) do
    begin
      Row := FindRow(Response.GetValue<TJSONArray>('values'), 'value_id', Ids[I]);
      Check(JSONDouble(Row, 'value') = Samples[I],
        'query_values keeps the stored value: ' + Row.GetValue('value').ToJSON);
      Check(JSONDouble(Row, 'tolerance') = Tols[I],
        'query_values keeps the stored tolerance: ' + Row.GetValue('tolerance').ToJSON);
    end;
  finally
    Response.Free;
  end;
end;

function AddConcluded(Project: TProject; Status: THypothesisStatus;
  HasOutcome: Boolean; Outcome: THypothesisOutcome; Modified: Boolean): Integer;
var
  H: THypothesis;
begin
  H := AddHypothesis(Project);
  H.Status := Status;
  if HasOutcome then
    H.Outcome := Outcome;
  if Modified then
    H.ModifiedDate := EncodeDate(2026, 10, 30) + EncodeTime(12, 0, 0, 0);
  Notebook.Manager.Flush;
  Result := H.Id;
end;

procedure TestListHypothesesShowsOutcome;
var
  Project: TProject;
  Ids: array[0..5] of Integer;
  Expected: array[0..5] of string;
  I: Integer;
  Response, Detail, Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Ids[0] := AddConcluded(Project, hsInReview, True, hoSupported, True);
  Ids[1] := AddConcluded(Project, hsAccepted, True, hoRefuted, True);
  Ids[2] := AddConcluded(Project, hsInReview, True, hoInconclusive, False);
  Ids[3] := AddConcluded(Project, hsApproved, False, hoSupported, False);
  Ids[4] := AddConcluded(Project, hsProposed, False, hoSupported, True);
  Ids[5] := AddConcluded(Project, hsAbandoned, True, hoRefuted, True);
  Expected[0] := '"Supported"';
  Expected[1] := '"Refuted"';
  Expected[2] := '"Inconclusive"';
  Expected[3] := 'null';
  Expected[4] := 'null';
  Expected[5] := '"Refuted"';

  Response := Call('list_hypotheses', Format('{"project_id":%d}', [Project.Id]));
  try
    for I := 0 to High(Ids) do
    begin
      Row := FindRow(Response.GetValue<TJSONArray>('hypotheses'), 'id', Ids[I]);
      Check(Assigned(Row), Format('Hypothesis %d is listed', [Ids[I]]));
      Check(Row.GetValue('outcome').ToJSON = Expected[I],
        Format('Row %d outcome: %s', [I, Row.GetValue('outcome').ToJSON]));
      Detail := Call('get_hypothesis', Format('{"hypothesis_id":%d}', [Ids[I]]));
      try
        Check(Row.GetValue('outcome').ToJSON = Detail.GetValue('outcome').ToJSON,
          'The list outcome matches get_hypothesis');
        Check(Row.GetValue('modified_date').ToJSON = Detail.GetValue('modified_date').ToJSON,
          'The list modified_date matches get_hypothesis');
      finally
        Detail.Free;
      end;
    end;
    Row := FindRow(Response.GetValue<TJSONArray>('hypotheses'), 'id', Ids[2]);
    Check(Row.GetValue('modified_date') is TJSONNull, 'An unmodified hypothesis has null');
    Row := FindRow(Response.GetValue<TJSONArray>('hypotheses'), 'id', Ids[0]);
    Check(Copy(Row.GetValue<string>('modified_date'), 1, 16) = '2026-10-30T12:00',
      'The modified date is ISO 8601: ' + Row.GetValue<string>('modified_date'));
  finally
    Response.Free;
  end;
end;

procedure TestGetHypothesisHasOneOutcomeKey;
var
  Response: TJSONObject;
  I, Count: Integer;
begin
  Prepare;
  Response := Call('get_hypothesis', Format('{"hypothesis_id":%d}',
    [AddConcluded(AddProject(Notebook.Principal), hsInReview, True, hoSupported, True)]));
  try
    Count := 0;
    for I := 0 to Response.Count - 1 do
      if Response.Pairs[I].JsonString.Value = 'outcome' then
        Inc(Count);
    Check(Count = 1, Format('get_hypothesis has %d outcome keys', [Count]));
    Check(Response.GetValue<string>('outcome') = 'Supported', 'The outcome is unchanged');
  finally
    Response.Free;
  end;
end;

procedure TestListHypothesesScopeUnchanged;
var
  P1, P2: TProject;
  Response, Row: TJSONObject;
  Element: TJSONValue;
begin
  P1 := AddProject(Notebook.Principal);
  P2 := AddProject(Notebook.Principal);
  AddConcluded(P1, hsInReview, True, hoSupported, False);
  AddConcluded(P2, hsInReview, True, hoRefuted, False);
  AddConcluded(AddProject(AddUser('hidden-owner', dbUser)), hsInReview, True, hoRefuted, False);
  Context.ScopedProjects := [P1.Id];
  Prepare;

  Response := Call('list_hypotheses', '{}');
  try
    Check(Response.GetValue<TJSONArray>('hypotheses').Count = 1, 'Only the scoped project is listed');
    for Element in Response.GetValue<TJSONArray>('hypotheses') do
    begin
      Row := Element as TJSONObject;
      Check(Row.GetValue<Integer>('project_id') = P1.Id, 'The row is in scope');
      CheckFields(Row, ['id', 'project_id', 'parent_id', 'title', 'status', 'derived_state',
        'created_by', 'run_count', 'evidence_count', 'version', 'key_value', 'outcome',
        'modified_date'], 'list_hypotheses');
    end;
  finally
    Response.Free;
  end;
end;

function MakeDeleteFixture(Project: TProject; FileTypeId, TypeId: Integer;
  const Title: string): TDeleteFixture;
var
  F: unit_Item.TFile;
begin
  Result.Item := NewItem(Project, 0, Title);
  Result.FileId := StoreFile(Result.Item, FileTypeId, 'scan', DELETE_CONTENT);
  Result.ReaderA := CallId('add_value', Format('{"item_id":%d,"value_type_id":%d,' +
    '"value":80,"source_file_id":%d,"reader_id":"%s","reader_version":"1",' +
    '"key_name":"Step Height","reader_units":"nm","conversion_factor":1,' +
    '"analysis_snapshot":%s}', [Result.Item.Id, TypeId, Result.FileId,
    EDIT_READER_ID, SnapshotFor(Result.FileId, DELETE_CONTENT, 'a')]));
  Result.ReaderB := CallId('add_value', Format('{"item_id":%d,"value_type_id":%d,' +
    '"value":5,"source_file_id":%d,"reader_id":"%s","reader_version":"1",' +
    '"key_name":"Roughness","reader_units":"nm","conversion_factor":1}',
    [Result.Item.Id, TypeId, Result.FileId, EDIT_READER_ID]));
  Result.ManualId := AddManual(Result.Item.Id, TypeId, 10);
  F := Notebook.Manager.Find<unit_Item.TFile>(Result.FileId);
  Result.Hash := F.Hash;
  Result.Path := AttachmentRelativePath(Project.FileFolder,
    Result.Item.FolderName, F.FullName);
  Check(Notebook.Storage.Exists(Result.Path), 'The fixture file has bytes');
end;

function NewDeleteFixture(Project: TProject; const Title: string): TDeleteFixture;
begin
  Result := MakeDeleteFixture(Project, NewFileType('.vdel'),
    NewValueType('Synthetic step', 'nm', False, 0, 0), Title);
end;

function JSONHasId(Arr: TJSONArray; Id: Integer): Boolean;
var
  Element: TJSONValue;
begin
  Result := False;
  for Element in Arr do
    if (Element as TJSONNumber).AsInt = Id then
      Exit(True);
end;

function DeleteAuditCount(EntityType: TAuditEntityType; EntityId: Int64): Integer;
var
  Rows: TList<TAuditLog>;
  Row: TAuditLog;
begin
  Result := 0;
  Rows := AuditRows(EntityType, EntityId);
  try
    for Row in Rows do
      if Row.Operation = aoDelete then
        Inc(Result);
  finally
    Rows.Free;
  end;
end;

function RefuseDelete(const Fx: TDeleteFixture; const Extra, Fragment: string): string;
var
  Before: TRowSnapshot;
begin
  Before := TRowSnapshot.Take;
  Result := ExpectRefused('delete_file', Format(DELETE_REAL, [Fx.FileId, Extra]),
    Fragment);
  Check(TRowSnapshot.Take.SameAs(Before), 'A refused delete changes no row: ' + Fragment);
  Check(Notebook.Storage.Exists(Fx.Path), 'A refused delete keeps the bytes: ' + Fragment);
end;

procedure TestDeleteFileDryRunChangesNothing;
var
  Project: TProject;
  Fx: TDeleteFixture;
  Before: TRowSnapshot;
  Response: TJSONObject;
  Rows: TJSONArray;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Fx := NewDeleteFixture(Project, 'Dry run');
  Before := TRowSnapshot.Take;

  Response := Call('delete_file', Format('{"file_id":%d}', [Fx.FileId]));
  try
    Check(Response.GetValue<Boolean>('dry_run'), 'dry_run defaults to true');
    Check(not Response.GetValue<Boolean>('deleted'), 'A dry run deletes nothing');
    Rows := Response.GetValue<TJSONArray>('values_to_delete');
    Check(Rows.Count = 2, 'Exactly the two Reader values are listed');
    Check(Assigned(FindRow(Rows, 'id', Fx.ReaderA)) and
      Assigned(FindRow(Rows, 'id', Fx.ReaderB)), 'Both Reader values are named');
    Check(Codes(Response.GetValue<TJSONArray>('checks_passed')) =
      'scope,not_deleted,write_access,not_signed,no_locked_hypothesis',
      'The checks are listed: ' + Codes(Response.GetValue<TJSONArray>('checks_passed')));
    Check(Response.GetValue<TJSONObject>('file').GetValue<Int64>('id') = Fx.FileId,
      'The file is described');
    Check(Pos('Projects/', Response.ToJSON) = 0, 'No storage path is returned');
  finally
    Response.Free;
  end;
  Response := Call('delete_file', Format('{"file_id":%d,"confirm_hash":"%s"}',
    [Fx.FileId, LowerCase(Fx.Hash)]));
  try
    Check(Codes(Response.GetValue<TJSONArray>('checks_passed')) =
      'scope,not_deleted,write_access,not_signed,no_locked_hypothesis,confirm_hash',
      'A given confirm_hash is listed');
  finally
    Response.Free;
  end;
  Check(TRowSnapshot.Take.SameAs(Before), 'A dry run changes no row');
  Check(Notebook.Storage.Exists(Fx.Path), 'A dry run keeps the bytes');
end;

procedure TestDeleteFileRemovesRecordBytesValues;
var
  Project: TProject;
  Fx: TDeleteFixture;
  Preview, Refusal: string;
  States: TViewerStateModel;
  Response: TJSONObject;
  Before: TRowSnapshot;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Fx := NewDeleteFixture(Project, 'Delete target');
  Preview := PreviewRelativePath(Fx.Item.Id, Fx.FileId);
  Notebook.Storage.WriteBytes(Preview, TEncoding.UTF8.GetBytes('png'));
  States := TViewerStateModel.Create(Notebook.Manager);
  try
    States.SaveOrUpdate(Notebook.Principal.Id, Fx.FileId, EDIT_READER_ID, '{}');
    Check(StoredSnapshot(Fx.ReaderA) <> '', 'The snapshot is stored');
    Check(States.GetState(Notebook.Principal.Id, Fx.FileId) <> nil, 'The viewer state is stored');
    Check(ItemListsValue(Fx.Item.Id, Fx.ReaderA), 'The session caches the item');

    Response := Call('delete_file', Format(DELETE_REAL,
      [Fx.FileId, ',"confirm_hash":"' + Fx.Hash + '"']));
    try
      Check(not Response.GetValue<Boolean>('dry_run'), 'A real call is not a dry run');
      Check(Response.GetValue<Boolean>('deleted'), 'The file is deleted');
      Check(Response.GetValue<string>('bytes_status') = 'removed', 'The bytes are removed');
      Check(Response.GetValue<TJSONArray>('values_deleted').Count = 2,
        'Two values are deleted');
      Check(JSONHasId(Response.GetValue<TJSONArray>('values_deleted'), Fx.ReaderA) and
        JSONHasId(Response.GetValue<TJSONArray>('values_deleted'), Fx.ReaderB),
        'Both Reader values are named');
      Check(Pos('Projects/', Response.ToJSON) = 0, 'No storage path is returned');
    finally
      Response.Free;
    end;

    Check(States.GetState(Notebook.Principal.Id, Fx.FileId) = nil,
      'The viewer state is gone');
  finally
    States.Free;
  end;
  Check(Notebook.Manager.Find<unit_Item.TFile>(Fx.FileId) = nil, 'The file record is gone');
  Check(not ValueExists(Fx.ReaderA) and not ValueExists(Fx.ReaderB),
    'Both Reader values are gone');
  Check(ValueExists(Fx.ManualId), 'The Manual value stays');
  Check(not Notebook.Storage.Exists(Fx.Path), 'The attachment bytes are gone');
  Check(not Notebook.Storage.Exists(Preview), 'The preview is gone');
  Check(StoredSnapshot(Fx.ReaderA) = '', 'The analysis snapshot is gone');
  Check(DeleteAuditCount(aetFile, Fx.FileId) = 1, 'One file delete audit row');
  Check((DeleteAuditCount(aetValue, Fx.ReaderA) = 1) and
    (DeleteAuditCount(aetValue, Fx.ReaderB) = 1), 'One audit row per removed value');
  Check(DeleteAuditCount(aetValue, Fx.ManualId) = 0, 'The Manual value is not audited as deleted');
  Check(not ItemListsValue(Fx.Item.Id, Fx.ReaderA), 'The cached item no longer lists the value');

  Before := TRowSnapshot.Take;
  Refusal := ExpectRefused('delete_file', Format(DELETE_REAL, [Fx.FileId, '']), 'outside');
  Check(Refusal = ExpectRefused('delete_file', '{"file_id":999999,"dry_run":false}',
    'outside'), 'A deleted file refuses like a missing one: ' + Refusal);
  Check(TRowSnapshot.Take.SameAs(Before), 'The second call changes nothing');
end;

procedure TestDeleteFileWithoutBytes;
var
  Project: TProject;
  Fx: TDeleteFixture;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Fx := NewDeleteFixture(Project, 'No bytes');
  Notebook.Storage.DeleteFile(Fx.Path);
  Response := Call('delete_file', Format(DELETE_REAL, [Fx.FileId, '']));
  try
    Check(Response.GetValue<Boolean>('deleted'), 'A record without bytes is deleted');
    Check(Response.GetValue<string>('bytes_status') = 'absent', 'The bytes were absent');
  finally
    Response.Free;
  end;
  Check(Notebook.Manager.Find<unit_Item.TFile>(Fx.FileId) = nil, 'The file record is gone');
end;

procedure TestDeleteFileKeepsRecordGoneWhenBytesFail;
var
  Project: TProject;
  Fx: TDeleteFixture;
  Response: TJSONObject;
begin
  Prepare(TFailingDeleteStorage.Create(Notebook.Storage));
  Project := AddProject(Notebook.Principal);
  Fx := NewDeleteFixture(Project, 'Bytes fail');
  Response := Call('delete_file', Format(DELETE_REAL, [Fx.FileId, '']));
  try
    Check(Response.GetValue<Boolean>('deleted'), 'The record is deleted');
    Check(Response.GetValue<string>('bytes_status') = 'remaining', 'The bytes remain');
    Check(Pos('synthetic delete failure', Response.GetValue<string>('bytes_error')) > 0,
      'The storage error is returned');
    Check(Pos('Projects/', Response.ToJSON) = 0, 'No storage path is returned');
  finally
    Response.Free;
  end;
  Check(Notebook.Manager.Find<unit_Item.TFile>(Fx.FileId) = nil, 'The file record is gone');
  Check(Notebook.Storage.Exists(Fx.Path), 'The bytes are still stored');
end;

procedure ExecuteNotebookSQL(const SQL: string);
var
  Statement: IDBStatement;
begin
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand(SQL);
  Statement.Execute;
end;

procedure TestDeleteFileFailureLeavesEveryRow;
var
  Project: TProject;
  Fx: TDeleteFixture;
  Before: TRowSnapshot;
  Failure: string;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Fx := NewDeleteFixture(Project, 'Audit fails');
  Check(ItemListsValue(Fx.Item.Id, Fx.ReaderA), 'The session caches the item');
  Before := TRowSnapshot.Take;
  ExecuteNotebookSQL('CREATE TRIGGER DeleteAuditDown BEFORE INSERT ON AuditLog ' +
    'BEGIN SELECT RAISE(ABORT, ''synthetic audit failure''); END');
  try
    Failure := '';
    try
      Response := Call('delete_file', Format(DELETE_REAL, [Fx.FileId, '']));
      Response.Free;
    except
      on E: Exception do
        Failure := E.Message;
    end;
  finally
    ExecuteNotebookSQL('DROP TRIGGER DeleteAuditDown');
  end;
  Check(Failure <> '', 'A failed audit write fails the call');
  Check(TRowSnapshot.Take.SameAs(Before), 'A failed delete changes no row');
  Check(ValueExists(Fx.ReaderA) and ValueExists(Fx.ReaderB) and ValueExists(Fx.ManualId),
    'Every value stays');
  Check(RowCount(Format('SELECT COUNT(*) FROM Files WHERE Id = %d', [Fx.FileId])) = 1,
    'The file record stays');
  Check(Notebook.Storage.Exists(Fx.Path), 'The bytes stay');
  Check(StoredSnapshot(Fx.ReaderA) <> '', 'The analysis snapshot stays');
  Check(DeleteAuditCount(aetFile, Fx.FileId) = 0, 'No file audit row');
  Check(ItemListsValue(Fx.Item.Id, Fx.ReaderA), 'The cached item still lists the value');

  Response := Call('delete_file', Format(DELETE_REAL, [Fx.FileId, '']));
  try
    Check(Response.GetValue<Boolean>('deleted'), 'The same call succeeds once the failure is gone');
  finally
    Response.Free;
  end;
end;

procedure TestDeleteFileRefusals;
var
  Project, Archived, Foreign: TProject;
  FileTypeId, TypeId: Integer;
  Open, Signed, Run, Cited, Hash, Gone, Held, Elsewhere: TDeleteFixture;
  Missing, Hidden: string;
begin
  Prepare;
  FileTypeId := NewFileType('.vdel');
  TypeId := NewValueType('Synthetic step', 'nm', False, 0, 0);
  Project := AddProject(Notebook.Principal);
  Archived := AddProject(Notebook.Principal);
  Foreign := AddProject(Notebook.Principal);
  Signed := MakeDeleteFixture(Project, FileTypeId, TypeId, 'Signed');
  SignItem(Signed.Item.Id);
  Held := MakeDeleteFixture(Archived, FileTypeId, TypeId, 'Archived');
  Archived.IsArchived := True;
  Notebook.Manager.Flush;
  Run := MakeDeleteFixture(Project, FileTypeId, TypeId, 'Run');
  AddRun(AddLockedHypothesis(Project, hsInReview), Run.Item.Id);
  Cited := MakeDeleteFixture(Project, FileTypeId, TypeId, 'Cited');
  AddFileEvidence(AddLockedHypothesis(Project, hsAccepted), Cited.Item.Id, Cited.FileId);
  Hash := MakeDeleteFixture(Project, FileTypeId, TypeId, 'Hash');
  Gone := MakeDeleteFixture(Project, FileTypeId, TypeId, 'Deleted');
  Gone.Item.IsDeleted := True;
  Notebook.Manager.Flush;
  Elsewhere := MakeDeleteFixture(Foreign, FileTypeId, TypeId, 'Out of scope');
  Open := MakeDeleteFixture(Project, FileTypeId, TypeId, 'Open');

  RefuseDelete(Signed, '', 'is signed');
  RefuseDelete(Held, '', 'archived');
  RefuseDelete(Run, '', '(InReview)');
  RefuseDelete(Cited, '', '(Accepted)');
  RefuseDelete(Hash, ',"confirm_hash":"0000"', 'confirm_hash');
  RefuseDelete(Gone, '', 'is deleted');

  Context.ScopedProjects := [Project.Id];
  Prepare;
  Missing := ExpectRefused('delete_file', '{"file_id":999999,"dry_run":false}', 'outside');
  Hidden := RefuseDelete(Elsewhere, '', 'outside');
  Check(Missing = Hidden, 'Missing and out-of-scope files share one refusal');
  Check(Notebook.Storage.Exists(Open.Path), 'An untouched file keeps its bytes');
end;

procedure TestDeleteFileRefusesMovedCitedFile;
var
  Project: TProject;
  Fx: TDeleteFixture;
  ItemB: TItem;
  HypId: Integer;
  H: THypothesis;
  F: unit_Item.TFile;
  NewPath: string;
  Before: TRowSnapshot;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Fx := NewDeleteFixture(Project, 'Cited source');
  ItemB := NewItem(Project, 0, 'Move target');
  Response := Call('move_file', Format('{"file_id":%d,"target_item_id":%d}',
    [Fx.FileId, ItemB.Id]));
  Response.Free;
  HypId := AddLockedHypothesis(Project, hsApproved);
  AddFileEvidence(HypId, Fx.Item.Id, Fx.FileId);
  H := Notebook.Manager.Find<THypothesis>(HypId);
  H.Status := hsInReview;
  Notebook.Manager.Flush;
  F := Notebook.Manager.Find<unit_Item.TFile>(Fx.FileId);
  NewPath := AttachmentRelativePath(Project.FileFolder, ItemB.FolderName, F.FullName);
  Check(Notebook.Storage.Exists(NewPath), 'The moved file has bytes');

  Before := TRowSnapshot.Take;
  ExpectRefused('delete_file', Format(DELETE_REAL, [Fx.FileId, '']),
    Format('hypothesis %d', [HypId]));
  Check(TRowSnapshot.Take.SameAs(Before), 'The refusal changes no row');
  Check(Notebook.Storage.Exists(NewPath), 'The refusal keeps the bytes');
end;

procedure TestDeleteFileCitedByApprovedHypothesis;
var
  Project: TProject;
  Fx: TDeleteFixture;
  HypId: Integer;
  Response: TJSONObject;
  Evidence: TJSONArray;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Fx := NewDeleteFixture(Project, 'Approved cites');
  HypId := AddLockedHypothesis(Project, hsApproved);
  AddFileEvidence(HypId, Fx.Item.Id, Fx.FileId);
  Response := Call('delete_file', Format(DELETE_REAL, [Fx.FileId, '']));
  try
    Check(Response.GetValue<Boolean>('deleted'),
      'An Approved hypothesis does not block the delete');
  finally
    Response.Free;
  end;
  Response := Call('get_hypothesis', Format('{"hypothesis_id":%d}', [HypId]));
  try
    Evidence := Response.GetValue<TJSONArray>('evidence');
    Check(Evidence.Count = 1, 'The evidence row stays');
    Check((Evidence.Items[0] as TJSONObject).GetValue<Boolean>('missing'),
      'The evidence is flagged missing');
  finally
    Response.Free;
  end;
end;

var
  SeedXrrId: Integer;

function SeedSeries(Project: TProject; out ProcId: Integer): Integer;
var
  Model: TSeriesModel;
  Power, Thickness: TValueType;
  Xrr: TActionType;
  Proc, Spec, Meas: TItem;
  SeedPlan: TSeriesPlan;

  function Make(AParent: Integer; ALevel: TItemLevel; AAction: TActionType;
    const ATitle: string): TItem;
  begin
    Result := TItem.Create;
    Result.Title := ATitle;
    Result.ProjectID := Project.Id;
    Result.Parent := AParent;
    Result.Type_ := TItemType.Measurement;
    Result.Level := ALevel;
    Result.ActionType := AAction;
    Result.CreatedBy := Notebook.Principal.Id;
    Result.CreatedDate := Now;
    Notebook.Manager.Save(Result);
    Notebook.Manager.Flush;
  end;

  procedure Add(AItem: TItem; AType: TValueType; ARec: TRecType; AValue, ATol: Double);
  var
    V: unit_Item.TValue;
  begin
    V := unit_Item.TValue.Create;
    V.Item := AItem;
    V.ValueType := AType;
    V.RecType := ARec;
    V.Value := AValue;
    V.Tol := ATol;
    V.CreatedDate := Now;
    Notebook.Manager.Save(V);
    Notebook.Manager.Flush;
  end;

begin
  Power := Notebook.Manager.Find<TValueType>(NewValueType('Power', 'W', False, 0, 0));
  Thickness := Notebook.Manager.Find<TValueType>(NewValueType('Thickness', 'nm', False, 0, 0));
  Xrr := TActionType.Create;
  Xrr.Title := 'XRR';
  Xrr.CreatedDate := Now;
  Notebook.Manager.Save(Xrr);
  Notebook.Manager.Flush;
  SeedXrrId := Xrr.Id;
  SeedPlan := Default(TSeriesPlan);
  SetLength(SeedPlan.Factors, 1);
  SeedPlan.Factors[0].ValueTypeId := Power.Id;
  SetLength(SeedPlan.Responses, 1);
  SeedPlan.Responses[0].ValueTypeId := Thickness.Id;
  Proc := Make(0, TItemLevel.Proc, nil, 'Deposition');
  Spec := Make(Proc.Id, TItemLevel.Item, nil, 'Specimen');
  Meas := Make(Spec.Id, TItemLevel.Action, Xrr, 'Measurement');
  Add(Proc, Power, EXP_CONDITION, 200, 0);
  Add(Meas, Thickness, TEST_RESULT, 51.0, 0.5);
  ProcId := Proc.Id;
  Model := TSeriesModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Result := Model.CreateSeries(Notebook.Principal, Project.Id, 'Power scan',
      'Vary power', SeedPlan, [[200.0]]);
    Model.LinkToSlot(Notebook.Principal, Result, Model.GetPlan(Notebook.Principal,
      Result).Slots[0].SlotId, ProcId);
  finally
    Model.Free;
  end;
end;

procedure TestListSeriesReturnsFixtureSeries;
var
  Project: TProject;
  SeriesId, ProcId: Integer;
  Response, Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  SeriesId := SeedSeries(Project, ProcId);
  Response := Call('list_series', Format('{"project_id":%d}', [Project.Id]));
  try
    Check(Response.GetValue<Integer>('project_id') = Project.Id, 'The project id is echoed');
    Check(Response.GetValue<TJSONArray>('series').Count = 1, 'One series is listed');
    Row := FindRow(Response.GetValue<TJSONArray>('series'), 'id', SeriesId);
    Check(Assigned(Row), 'The fixture series is listed');
    CheckFields(Row, ['id', 'title', 'purpose', 'status', 'member_count'], 'list_series');
    Check(Row.GetValue<string>('title') = 'Power scan', 'Title');
    Check(Row.GetValue<string>('purpose') = 'Vary power', 'Purpose');
    Check(Row.GetValue<string>('status') = 'Active', 'Status uses the enum name');
    Check(Row.GetValue<Integer>('member_count') = 1, 'Member count');
  finally
    Response.Free;
  end;
end;

procedure TestGetSeriesTableCellsAreInvariantNumbers;
var
  Project: TProject;
  SeriesId, ProcId: Integer;
  Response, Col, Row, Hit: TJSONObject;
  Cols, Cells: TJSONArray;
  I, Found: Integer;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  SeriesId := SeedSeries(Project, ProcId);
  Response := Call('get_series_table', Format('{"series_id":%d}', [SeriesId]));
  try
    CheckFields(Response, ['series_id', 'project_id', 'title', 'status', 'columns',
      'rows', 'excluded_item_ids'], 'get_series_table');
    Cols := Response.GetValue<TJSONArray>('columns');
    Check(Cols.Count = 2, Format('Two columns, got %d', [Cols.Count]));
    Check(Response.GetValue<TJSONArray>('rows').Count = 1, 'One row');
    Row := Response.GetValue<TJSONArray>('rows').Items[0] as TJSONObject;
    Check(Row.GetValue<Integer>('item_id') = ProcId, 'Row item id');
    Check(Row.GetValue<string>('title') = 'Deposition', 'Row title');
    Cells := Row.GetValue<TJSONArray>('cells');
    Check(Cells.Count = 2, 'One cell per column');
    Found := 0;
    for I := 0 to Cols.Count - 1 do
    begin
      Col := Cols.Items[I] as TJSONObject;
      CheckFields(Col, ['rec_type', 'value_type_id', 'caption', 'units', 'source_key',
        'role'], 'column');
      if Col.GetValue<string>('rec_type') = 'EXP_CONDITION' then
        Check(Col.GetValue<string>('role') = 'Varied', 'A factor column is Varied')
      else
        Check(Col.GetValue<string>('role') = 'Response', 'A response column is Response');
      Check((Cells.Items[I] as TJSONArray).Count = 1, 'One hit per cell');
      Hit := (Cells.Items[I] as TJSONArray).Items[0] as TJSONObject;
      CheckFields(Hit, ['value', 'tol', 'value_id', 'item_id', 'source_key'], 'hit');
      if Col.GetValue<string>('rec_type') = 'EXP_CONDITION' then
      begin
        Inc(Found);
        Check(JSONDouble(Hit, 'value') = 200, 'Power value');
        Check(Hit.GetValue<string>('source_key') = 'root', 'Condition hit source key');
        Check(Hit.GetValue('value').ToJSON = '200', 'Power is a plain JSON number: ' +
          Hit.GetValue('value').ToJSON);
      end
      else
      begin
        Inc(Found, 10);
        Check(Col.GetValue<string>('rec_type') = 'TEST_RESULT', 'Result rec_type');
        Check(JSONDouble(Hit, 'value') = 51.0, 'Thickness value');
        Check(Hit.GetValue<string>('source_key') = 'at:' + IntToStr(SeedXrrId),
          'Thickness hit source key is the XRR action type');
        Check(JSONDouble(Hit, 'tol') = 0.5, 'Thickness tolerance');
        Check(Hit.GetValue('value').ToJSON = '51', 'Thickness is a JSON number: ' +
          Hit.GetValue('value').ToJSON);
        Check(Hit.GetValue('tol').ToJSON = '0.5', 'Tolerance uses the invariant point');
      end;
    end;
    Check(Found = 11, 'Both rec types appear');
  finally
    Response.Free;
  end;
end;

procedure TestSeriesToolsRefuseOutOfScope;
var
  P1, P2, P3: TProject;
  Own, Foreign, Denied, ProcId: Integer;
  Missing, Hidden: string;
  Stranger: TUser;
begin
  P1 := AddProject(Notebook.Principal);
  P2 := AddProject(Notebook.Principal);
  Own := SeedSeries(P1, ProcId);
  Foreign := SeedSeries(P2, ProcId);
  Context.ScopedProjects := [P1.Id];
  Prepare;
  ExpectRefused('list_series', Format('{"project_id":%d}', [P2.Id]), 'outside');
  Hidden := ExpectRefused('get_series_table', Format('{"series_id":%d}', [Foreign]),
    'outside');
  Missing := ExpectRefused('get_series_table', '{"series_id":999999}', 'outside');
  Check(Missing = Hidden, 'Missing and out-of-scope series share one refusal');
  Stranger := AddUser('series-hidden-owner', dbUser);
  P3 := AddProject(Notebook.Principal);
  Denied := SeedSeries(P3, ProcId);
  P3.Owner := Stranger;
  Notebook.Manager.Flush;
  Hidden := ExpectRefused('get_series_table', Format('{"series_id":%d}', [Denied]), 'outside');
  Check(Missing = Hidden, 'A series of an unreadable project gives the same refusal');
  Call('get_series_table', Format('{"series_id":%d}', [Own])).Free;
end;

function CallKeyed(const Tool, JSON, Key: string): Integer;
var
  Response: TJSONObject;
begin
  Response := Call(Tool, JSON);
  try
    Result := Response.GetValue<Integer>(Key);
  finally
    Response.Free;
  end;
end;

function PowerPlanJSON(ProjectId, PowerId: Integer; const Points: string): string;
begin
  Result := Format('{"project_id":%d,"title":"MCP plan","purpose":"Scan",' +
    '"factors":[{"value_type_id":%d,"range_min":100,"range_max":300}],' +
    '"points":%s}', [ProjectId, PowerId, Points]);
end;

function SeriesRows(SeriesId: Integer): TJSONArray;
var
  Response: TJSONObject;
begin
  Response := Call('get_series_table', Format('{"series_id":%d}', [SeriesId]));
  try
    Result := Response.GetValue<TJSONArray>('rows').Clone as TJSONArray;
  finally
    Response.Free;
  end;
end;

procedure TestCreateSeriesIsDraftViaMcp;
var
  Project: TProject;
  PowerId, SeriesId: Integer;
  Response: TJSONObject;
  Rows: TJSONArray;
  Model: TSeriesModel;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  PowerId := NewValueType('Plan power', 'W', False, 0, 0);
  Response := Call('create_series', PowerPlanJSON(Project.Id, PowerId, '[[100],[200]]'));
  try
    Check(Response.GetValue<string>('status') = 'Draft', 'MCP creates a Draft series');
    SeriesId := Response.GetValue<Integer>('series_id');
  finally
    Response.Free;
  end;
  Model := TSeriesModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Check(Model.GetPlan(Notebook.Principal, SeriesId).Plan.Factors[0].ValueTypeId = PowerId,
      'The factor is stored');
  finally
    Model.Free;
  end;
  Rows := SeriesRows(SeriesId);
  try
    Check(Rows.Count = 2, 'Two planned rows');
    Check((Rows.Items[0] as TJSONObject).GetValue<string>('state') = 'Planned',
      'A new row is Planned');
    Check((Rows.Items[0] as TJSONObject).GetValue<string>('origin') = 'Planned',
      'A draft point has the Planned origin');
  finally
    Rows.Free;
  end;
  ExpectRefused('create_series', PowerPlanJSON(Project.Id, PowerId, '[[999]]'),
    '[refusal]');
end;

procedure TestUpdateSeriesPlanRefusedChangesNothing;
var
  Project: TProject;
  PowerId, ThicknessId, SeriesId: Integer;
  Before, After: string;
  Model: TSeriesModel;
  V0, A0: Integer;

  function Snapshot: string;
  var
    R: TJSONObject;
  begin
    R := Call('get_series_table', Format('{"series_id":%d}', [SeriesId]));
    try
      Result := R.GetValue<TJSONObject>('plan').ToJSON + R.GetValue<TJSONArray>('columns').ToJSON;
    finally
      R.Free;
    end;
  end;

  function SeriesVersion: Integer;
  var
    S: TSeries;
  begin
    S := Notebook.Manager.Find<TSeries>
      .Where(Linq['Id'] = SeriesId).Refreshing.UniqueResult;
    Result := S.Version;
  end;

  function AuditRows: Integer;
  var
    L: TAuditLogs;
  begin
    L := Notebook.Manager.Find<TAuditLog>
      .Where((Linq['EntityType'] = Ord(aetSeries)) and (Linq['EntityId'] = SeriesId))
      .Refreshing.List;
    try
      Result := L.Count;
    finally
      L.Free;
    end;
  end;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  PowerId := NewValueType('Plan power', 'W', False, 0, 0);
  ThicknessId := NewValueType('Plan thickness', 'nm', False, 0, 0);
  SeriesId := CallKeyed('create_series', PowerPlanJSON(Project.Id, PowerId, '[[100],[200]]'),
    'series_id');
  Model := TSeriesModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Model.SetColumnRole(Notebook.Principal, SeriesId, TEST_RESULT, ThicknessId, '', scrHidden);
    V0 := SeriesVersion;
  finally
    Model.Free;
  end;
  A0 := AuditRows;
  Before := Snapshot;
  ExpectRefused('update_series_plan', Format(
    '{"series_id":%d,"purpose":"Changed","factors":[{"value_type_id":%d,"range_min":50,' +
    '"range_max":400}],"responses":[{"value_type_id":%d}],"add_points":[[999]],"reason":"Bad"}',
    [SeriesId, PowerId, ThicknessId]), '[refusal]');
  After := Snapshot;
  Check(Before = After, 'A refused call leaves plan and column roles unchanged');
  Check(SeriesVersion = V0, 'Version unchanged');
  Check(AuditRows = A0, 'No audit row written');
  Call('update_series_plan', Format(
    '{"series_id":%d,"purpose":"Changed","factors":[{"value_type_id":%d,"range_min":50,' +
    '"range_max":400}],"responses":[{"value_type_id":%d}],"add_points":[[300]],"reason":"Ok"}',
    [SeriesId, PowerId, ThicknessId])).Free;
  Check(SeriesVersion = V0 + 1, Format('One version bump %d -> %d', [V0, SeriesVersion]));
  Check(AuditRows = A0 + 1, 'One audit row');
  Check(Snapshot <> Before, 'The plan changed');
end;

procedure TestUpdateSeriesPlanAddsPoints;
var
  Project: TProject;
  PowerId, SeriesId: Integer;
  Response: TJSONObject;
  Rows: TJSONArray;
  Listed: TJSONArray;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  PowerId := NewValueType('Plan power', 'W', False, 0, 0);
  SeriesId := CallKeyed('create_series', PowerPlanJSON(Project.Id, PowerId, '[[100]]'), 'series_id');
  Response := Call('update_series_plan', Format(
    '{"series_id":%d,"purpose":"Wider","add_points":[[200],[300]],"reason":"Extend"}',
    [SeriesId]));
  Response.Free;
  Rows := SeriesRows(SeriesId);
  try
    Check(Rows.Count = 3, 'The points are added');
  finally
    Rows.Free;
  end;
  ExpectRefused('update_series_plan', Format(
    '{"series_id":%d,"purpose":"Rejected","add_points":[[999]],"reason":"Bad"}',
    [SeriesId]), '[refusal]');
  Response := Call('list_series', Format('{"project_id":%d}', [Project.Id]));
  try
    Listed := Response.GetValue<TJSONArray>('series');
    Check((Listed.Items[0] as TJSONObject).GetValue<string>('purpose') = 'Wider',
      'A refused call leaves the purpose unchanged');
  finally
    Response.Free;
  end;
  Rows := SeriesRows(SeriesId);
  try
    Check(Rows.Count = 3, 'A refused call adds no point');
  finally
    Rows.Free;
  end;
  ExpectRefused('update_series_plan', Format(
    '{"series_id":%d,"factors":[{"value_type_id":%d,"range_min":100,"range_max":150}]}',
    [SeriesId, PowerId]), '[refusal]');
  ExpectRefused('update_series_plan', '{"series_id":999999,"purpose":"x"}', 'outside');
end;

procedure TestPlanToolsRefusedInReadOnlyMode;
var
  Refused: Integer;
  Tool: string;
begin
  Prepare;
  Registry.EnterReadOnly;
  Refused := 0;
  for Tool in ['create_series', 'update_series_plan'] do
    try
      Call(Tool, '{}').Free;
    except
      on EToolAccessRefused do
        Inc(Refused);
    end;
  Check(Refused = 2, 'Both plan tools are refused in read-only mode');
end;

function PowerColumn(Response: TJSONObject; PowerId: Integer): Integer;
var
  Cols: TJSONArray;
  I: Integer;
begin
  Result := -1;
  Cols := Response.GetValue<TJSONArray>('columns');
  for I := 0 to Cols.Count - 1 do
    if (Cols.Items[I].GetValue<Integer>('value_type_id') = PowerId) and
       (Cols.Items[I].GetValue<string>('rec_type') = 'EXP_CONDITION') then
      Result := I;
  Check(Result >= 0, 'The power column exists');
end;

procedure TestGetSeriesTableShowsPlanAndStates;
var
  Project: TProject;
  PowerId, SeriesId, SlotId, Col, I: Integer;
  Response: TJSONObject;
  Model: TSeriesModel;
  Draft: TSeriesDepositionDraft;
  Rows, Hits: TJSONArray;
  Row, Marks, Plan, Factor, Hit: TJSONObject;
  SawPlanned, SawMade: Boolean;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  PowerId := NewValueType('Plan power', 'W', False, 0, 0);
  SeriesId := CallKeyed('create_series', Format(
    '{"project_id":%d,"title":"MCP plan","factors":[{"value_type_id":%d,"label":" Mo layer ",' +
    '"range_min":100,"range_max":300}],"responses":[{"value_type_id":%d,"label":"Total stack"}],' +
    '"points":[[100],[200]]}',
    [Project.Id, PowerId, NewValueType('Plan thickness', 'nm', False, 0, 0)]), 'series_id');
  Response := Call('get_series_table', Format('{"series_id":%d}', [SeriesId]));
  try
    Col := PowerColumn(Response, PowerId);
    Rows := Response.GetValue<TJSONArray>('rows');
    SlotId := 0;
    for I := 0 to Rows.Count - 1 do
    begin
      Row := Rows.Items[I] as TJSONObject;
      Marks := Row.GetValue<TJSONArray>('cell_marks').Items[Col] as TJSONObject;
      if JSONDouble(Marks, 'planned_value') = 200 then
        SlotId := Row.GetValue<Integer>('slot_id');
    end;
    Check(SlotId > 0, 'The planned row of 200 W is found');
    Plan := Response.GetValue<TJSONObject>('plan');
    Factor := Plan.GetValue<TJSONArray>('factors').Items[0] as TJSONObject;
    Check(Factor.GetValue<Integer>('value_type_id') = PowerId, 'Plan factor id');
    Check(Factor.GetValue<string>('title') = 'Plan power', 'Plan factor title');
    Check(Factor.GetValue<string>('units') = 'W', 'Plan factor units');
    Check(JSONDouble(Factor, 'range_min') = 100, 'Plan range minimum');
    Check(JSONDouble(Factor, 'range_max') = 300, 'Plan range maximum');
    Check(Factor.GetValue<string>('label') = 'Mo layer', 'Plan factor label is trimmed');
    Check((Plan.GetValue<TJSONArray>('responses').Items[0] as TJSONObject)
      .GetValue<string>('label') = 'Total stack', 'Plan response label');
    CheckFields(Plan, ['fixed', 'responses', 'target_folder_id'], 'plan');
  finally
    Response.Free;
  end;
  Model := TSeriesModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Model.Start(Notebook.Principal, SeriesId);
    Draft := Default(TSeriesDepositionDraft);
    Draft.Title := 'Made 200';
    Model.MakeDeposition(Notebook.Principal, SeriesId, SlotId, Draft);
  finally
    Model.Free;
  end;
  Response := Call('get_series_table', Format('{"series_id":%d}', [SeriesId]));
  try
    Col := PowerColumn(Response, PowerId);
    SawPlanned := False;
    SawMade := False;
    Rows := Response.GetValue<TJSONArray>('rows');
    for I := 0 to Rows.Count - 1 do
    begin
      Row := Rows.Items[I] as TJSONObject;
      Marks := Row.GetValue<TJSONArray>('cell_marks').Items[Col] as TJSONObject;
      if Row.GetValue<Integer>('slot_id') = SlotId then
      begin
        SawMade := True;
        Check(Row.GetValue<string>('state') = 'Deposited', 'A made row is Deposited');
        Hits := Row.GetValue<TJSONArray>('cells').Items[Col] as TJSONArray;
        Check(Hits.Count = 1, 'One planned hit');
        Hit := Hits.Items[0] as TJSONObject;
        Check(Hit.GetValue<Boolean>('planned'), 'The hit is marked planned');
      end
      else
      begin
        SawPlanned := True;
        Check(Row.GetValue<string>('state') = 'Planned', 'An untouched row is Planned');
        Check(JSONDouble(Marks, 'planned_value') = 100, 'Planned value 100');
        Check(Marks.FindValue('deviation') = nil, 'No deviation without a hit');
      end;
    end;
    Check(SawPlanned and SawMade, 'Both rows are present');
  finally
    Response.Free;
  end;
end;

function NewPlannedValue(Item: TItem; TypeId: Integer; Number: Double): Integer;
var
  Val: unit_Item.TValue;
begin
  Val := unit_Item.TValue.Create;
  Val.ValueType := Notebook.Manager.Find<TValueType>(TypeId);
  Val.RecType := TEST_RESULT;
  Val.Value := Number;
  Val.CreatedDate := Now;
  Val.CreatedBy := Notebook.Principal.Id;
  Val.Item := Item;
  ApplySource(Val, TValueSourceInfo.Planned(''));
  Item.Values.Add(Val);
  Notebook.Manager.Update(Item);
  Notebook.Manager.Flush;
  Result := Val.Id;
end;

procedure TestAddValueRefusesPlanned;
var
  Item: TItem;
  TypeId: Integer;
  Before: TRowSnapshot;
  Message: string;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Planned refusal');
  TypeId := NewValueType('Synthetic thickness', 'm', False, 0, 0);
  Before := TRowSnapshot.Take;
  Message := ExpectRefused('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":1e-6,"source_kind":"Planned"}',
    [Item.Id, TypeId]), 'Invalid source_kind: Planned');
  Check(Pos('Planned,', Message) = 0, 'The accepted kinds do not list Planned');
  Check(TRowSnapshot.Take.SameAs(Before), 'The refusal writes nothing');
end;

procedure TestUpdateAndRemoveRefusePlanned;
var
  Item: TItem;
  TypeId, ValueId: Integer;
  Before: TRowSnapshot;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Planned edit refusal');
  TypeId := NewValueType('Synthetic thickness', 'm', False, 0, 0);
  ValueId := NewPlannedValue(Item, TypeId, 1e-6);
  Before := TRowSnapshot.Take;
  ExpectRefused('update_value', Format('{"value_id":%d,"value":2e-6}', [ValueId]),
    'Planned values are confirmed or corrected in the desktop.');
  ExpectRefused('remove_value', Format('{"value_id":%d}', [ValueId]),
    'Planned values are confirmed or corrected in the desktop.');
  Check(TRowSnapshot.Take.SameAs(Before), 'The refusals write nothing');
  Check(ValueExists(ValueId), 'The Planned value is still stored');
end;

procedure TestDerivedValueRefusesPlannedInput;
var
  Item: TItem;
  PlannedArea, ForceId, CyclesId: Integer;
  Before: TRowSnapshot;
begin
  Prepare;
  Item := NewItem(AddProject(Notebook.Principal), 0, 'Planned wear test');
  PlannedArea := NewPlannedValue(Item, AreaType, 0.004);
  ForceId := AddManual(Item.Id, ForceType, 5);
  CyclesId := AddManual(Item.Id, CyclesType, 1000);
  Before := TRowSnapshot.Take;
  ExpectRefused('add_derived_value', DerivedCall(Item.Id, WEAR_RATE_FORMULA_ID,
    PlannedArea, ForceId, CyclesId), 'confirm it in the desktop first');
  Check(TRowSnapshot.Take.SameAs(Before), 'The refusal writes nothing');
end;

function SeriesFolderId(ProjectId: Integer): Integer;
var
  Projects: TProjectsModel;
begin
  Projects := TProjectsModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Projects.AssignUser(Notebook.Principal);
    Projects.AddFolder('Series folder', '', ProjectId, 0);
  finally
    Projects.Free;
  end;
  Result := Notebook.Manager.Find<TProject>(ProjectId).Folders.Last.Id;
end;

procedure TestSeriesToolsRefuseBadTargetFolder;
var
  Project, Other: TProject;
  PowerId, SeriesId, Foreign, Own: Integer;
  Before, After: string;
  Rows: TJSONArray;

  function WithFolder(FolderId: Integer): string;
  begin
    Result := Format('{"project_id":%d,"title":"Folder plan","factors":' +
      '[{"value_type_id":%d}],"points":[[100]],"target_folder_id":%d}',
      [Project.Id, PowerId, FolderId]);
  end;

  function Snapshot: string;
  var
    R: TJSONObject;
  begin
    R := Call('get_series_table', Format('{"series_id":%d}', [SeriesId]));
    try
      Result := R.GetValue<TJSONObject>('plan').ToJSON;
    finally
      R.Free;
    end;
  end;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Other := AddProject(Notebook.Principal);
  PowerId := NewValueType('Folder power', 'W', False, 0, 0);
  Foreign := SeriesFolderId(Other.Id);
  Own := SeriesFolderId(Project.Id);
  ExpectRefused('create_series', WithFolder(99999), 'Folder 99999 not found in this project');
  ExpectRefused('create_series', WithFolder(Foreign),
    Format('Folder %d not found in this project', [Foreign]));
  SeriesId := CallKeyed('create_series', WithFolder(Own), 'series_id');
  Before := Snapshot;
  ExpectRefused('update_series_plan', Format('{"series_id":%d,"target_folder_id":99999}',
    [SeriesId]), 'Folder 99999 not found in this project');
  ExpectRefused('update_series_plan', Format(
    '{"series_id":%d,"target_folder_id":%d,"add_points":[[200]]}', [SeriesId, Foreign]),
    Format('Folder %d not found in this project', [Foreign]));
  After := Snapshot;
  Check(Before = After, 'A refused folder leaves the plan unchanged');
  Rows := SeriesRows(SeriesId);
  try
    Check(Rows.Count = 1, 'A refused call adds no point');
  finally
    Rows.Free;
  end;
end;

procedure TestActiveSeriesPlanChangeRefusedViaMcp;
var
  Project: TProject;
  PowerId, ThicknessId, SeriesId: Integer;
  Model: TSeriesModel;
  Before, After: string;
  Rows: TJSONArray;

  function Snapshot: string;
  var
    R: TJSONObject;
  begin
    R := Call('get_series_table', Format('{"series_id":%d}', [SeriesId]));
    try
      Result := R.GetValue<TJSONObject>('plan').ToJSON;
    finally
      R.Free;
    end;
  end;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  PowerId := NewValueType('Active power', 'W', False, 0, 0);
  ThicknessId := NewValueType('Active thickness', 'nm', False, 0, 0);
  SeriesId := CallKeyed('create_series', PowerPlanJSON(Project.Id, PowerId, '[[100]]'),
    'series_id');
  Call('update_series_plan', Format(
    '{"series_id":%d,"factors":[{"value_type_id":%d,"range_min":100,"range_max":400}]}',
    [SeriesId, PowerId])).Free;
  Model := TSeriesModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Model.Start(Notebook.Principal, SeriesId);
  finally
    Model.Free;
  end;
  Before := Snapshot;
  ExpectRefused('update_series_plan', Format(
    '{"series_id":%d,"factors":[{"value_type_id":%d,"range_min":100,"range_max":500}],' +
    '"add_points":[[200]]}', [SeriesId, PowerId]),
    'An active series plan is changed in the desktop. MCP can only add points to it.');
  ExpectRefused('update_series_plan', Format('{"series_id":%d,"responses":[{"value_type_id":%d}]}',
    [SeriesId, ThicknessId]), 'An active series plan is changed in the desktop');
  After := Snapshot;
  Check(Before = After, 'A refused call leaves the plan unchanged');
  Rows := SeriesRows(SeriesId);
  try
    Check(Rows.Count = 1, 'A refused call adds no point');
  finally
    Rows.Free;
  end;
  Call('update_series_plan', Format(
    '{"series_id":%d,"purpose":"Adaptive","factors":[{"value_type_id":%d,' +
    '"range_min":100,"range_max":400}],"add_points":[[250]]}', [SeriesId, PowerId])).Free;
  Call('update_series_plan', Format('{"series_id":%d,"add_points":[[300]]}',
    [SeriesId])).Free;
  Rows := SeriesRows(SeriesId);
  try
    Check(Rows.Count = 3, 'Points are added to an Active series');
  finally
    Rows.Free;
  end;
end;

procedure TestGetValuesShowsPlanned;
var
  Project: TProject;
  Item: TItem;
  TypeId, ValueId: Integer;
  Response: TJSONObject;
  Row: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  Item := NewItem(Project, 0, 'Planned display');
  TypeId := NewValueType('Synthetic thickness', 'm', True, 1e-9, 1e-5);
  ValueId := NewPlannedValue(Item, TypeId, 319.4);
  Response := Call('get_values', Format('{"item_id":%d}', [Item.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('results'), 'id', ValueId);
    Check(Assigned(Row), 'get_values lists the Planned value');
    Check(Row.GetValue<TJSONObject>('source').GetValue<string>('kind') = 'Planned',
      'The source kind is Planned');
  finally
    Response.Free;
  end;
  Response := Call('report_value_issues', Format('{"project_id":%d}', [Project.Id]));
  try
    Row := FindRow(Response.GetValue<TJSONArray>('values'), 'value_id', ValueId);
    Check(Assigned(Row), 'report_value_issues lists the Planned value like a Manual one');
  finally
    Response.Free;
  end;
end;

procedure RunValueSourceTests;
begin
  RunTest('delete_file dry run lists the Reader values and changes nothing',
    TestDeleteFileDryRunChangesNothing);
  RunTest('delete_file removes the record, bytes, Reader values and state',
    TestDeleteFileRemovesRecordBytesValues);
  RunTest('delete_file reports a file whose bytes were already absent',
    TestDeleteFileWithoutBytes);
  RunTest('delete_file keeps the record deletion when the bytes cannot be removed',
    TestDeleteFileKeepsRecordGoneWhenBytesFail);
  RunTest('delete_file failure leaves the file, values, snapshots and audit untouched',
    TestDeleteFileFailureLeavesEveryRow);
  RunTest('delete_file refuses signed, archived, locked, mismatched, deleted and hidden files',
    TestDeleteFileRefusals);
  RunTest('delete_file refuses a moved file still cited by a locked hypothesis',
    TestDeleteFileRefusesMovedCitedFile);
  RunTest('delete_file proceeds when only an Approved hypothesis cites the file',
    TestDeleteFileCitedByApprovedHypothesis);
  RunTest('list_files and get_item show live duplicates as not deleted',
    TestFileStatusShowsLiveDuplicates);
  RunTest('list_files reports a record without bytes as missing',
    TestFileStatusReportsMissingBytes);
  RunTest('file is_deleted follows the item and its ancestors',
    TestFileStatusFollowsRecycleBin);
  RunTest('wiki tools skip markdown records without bytes',
    TestWikiSkipsMarkdownWithoutBytes);
  RunTest('wiki_create_page stores the page, body and attachments',
    TestWikiCreateWritesPageAndAttachments);
  RunTest('wiki_create_page body storage failure leaves no page, row or bytes',
    TestWikiCreateBodyCopyFailureLeavesNothing);
  RunTest('wiki_create_page attachment storage failure leaves no page, row or bytes',
    TestWikiCreateAttachmentCopyFailureLeavesNothing);
  RunTest('wiki_create_page without a markdown file type writes nothing',
    TestWikiCreateMissingMarkdownTypeWritesNothing);
  RunTest('wiki_create_page refuses a title that differs only in case',
    TestWikiCreateRefusesCaseDuplicate);
  RunTest('wiki_create_page with a missing attachment source writes nothing',
    TestWikiCreateMissingAttachmentSourceWritesNothing);
  RunTest('wiki_update_page failure restores the old body and adds nothing',
    TestWikiUpdateFailureRestoresBody);
  RunTest('find_hypotheses_for_item returns Run, Reference and evidence links',
    TestFindHypothesesReturnsAllLinkKinds);
  RunTest('find_hypotheses_for_item matches get_hypothesis',
    TestFindHypothesesMatchesGetHypothesis);
  RunTest('find_hypotheses_for_item reports missing and hidden items the same way',
    TestFindHypothesesUnavailableItemsAreUniform);
  RunTest('find_hypotheses_for_item hides hypotheses of unreadable projects',
    TestFindHypothesesHidesForeignHypothesis);
  RunTest('find_hypotheses_for_item honours the session scope',
    TestFindHypothesesScopedSession);
  RunTest('find_hypotheses_for_item accepts 1 to 200 positive ids',
    TestFindHypothesesLimits);
  RunTest('find_hypotheses_for_item writes nothing',
    TestFindHypothesesWritesNothing);
  RunTest('ExactNum writes the shortest text that parses back to the same Double',
    TestExactNumRoundTrips);
  RunTest('get_values adds type id, role, item, project and ancestors',
    TestGetValuesAddsTypeRoleAndAncestors);
  RunTest('get_values of a root item has no ancestors', TestGetValuesRootItemHasNoAncestors);
  RunTest('query_values adds type id and ancestors', TestQueryValuesAddsTypeIdAndAncestors);
  RunTest('value ancestors stop at a missing parent', TestValueAncestorsStopAtMissingParent);
  RunTest('get_values and query_values keep exact numbers', TestValueToolsKeepExactNumbers);
  RunTest('list_hypotheses shows the stored outcome and modified date',
    TestListHypothesesShowsOutcome);
  RunTest('get_hypothesis keeps exactly one outcome key', TestGetHypothesisHasOneOutcomeKey);
  RunTest('list_hypotheses keeps its scope filter and fields', TestListHypothesesScopeUnchanged);
  RunTest('list_series returns the fixture series', TestListSeriesReturnsFixtureSeries);
  RunTest('get_series_table returns columns and invariant numbers',
    TestGetSeriesTableCellsAreInvariantNumbers);
  RunTest('series tools refuse a project outside the scope', TestSeriesToolsRefuseOutOfScope);
  RunTest('create_series makes a Draft series through MCP', TestCreateSeriesIsDraftViaMcp);
  RunTest('update_series_plan adds points and changes nothing on refusal',
    TestUpdateSeriesPlanAddsPoints);
  RunTest('update_series_plan refusal changes nothing and success bumps once',
    TestUpdateSeriesPlanRefusedChangesNothing);
  RunTest('plan tools are refused in read-only mode', TestPlanToolsRefusedInReadOnlyMode);
  RunTest('get_series_table shows the plan and row states',
    TestGetSeriesTableShowsPlanAndStates);
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
  RunTest('download_file writes stored bytes, reports the hash and honours overwrite',
    TestDownloadFileWritesStoredBytes);
  RunTest('download_file refuses missing bytes, outside paths, deleted, hidden and disabled',
    TestDownloadFileRefusals);
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
  RunTest('remove_value deletes the row and audits the old number on the item',
    TestRemoveValueWritesItemAudit);
  RunTest('remove_value and update_value refuse signed, deleted, locked and hidden values',
    TestValueEditRefusals);
  RunTest('remove_value keeps a Derived value whose input it removes',
    TestRemoveDerivedInputKeepsDerived);
  RunTest('remove_values is all-or-nothing', TestRemoveValuesIsAllOrNothing);
  RunTest('update_value changes fields, checks range and keeps the source',
    TestUpdateManualValue);
  RunTest('update_value replaces a Reader version and snapshot after a reader fix',
    TestUpdateReaderValueAfterReaderFix);
  RunTest('add_value refuses the Planned source kind', TestAddValueRefusesPlanned);
  RunTest('update_value and remove_value refuse a Planned value',
    TestUpdateAndRemoveRefusePlanned);
  RunTest('add_derived_value refuses a Planned input', TestDerivedValueRefusesPlannedInput);
  RunTest('series tools refuse a target folder of another project',
    TestSeriesToolsRefuseBadTargetFolder);
  RunTest('update_series_plan changes an Active series only by points',
    TestActiveSeriesPlanChangeRefusedViaMcp);
  RunTest('get_values shows a Planned source and report_value_issues lists it',
    TestGetValuesShowsPlanned);
end;

end.
