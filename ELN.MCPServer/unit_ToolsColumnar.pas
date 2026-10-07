unit unit_ToolsColumnar;

interface

uses
  unit_MCPTools;

procedure RegisterColumnarTools(Registry: TToolRegistry);

implementation

uses
  System.SysUtils, System.JSON,
  Aurelius.Engine.ObjectManager,
  unit_Item, unit_FileType, unit_ToolScope, unit_ToolDownloads;

function GetReqInt(const Params: TJSONObject; const Key: string): Integer;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<Integer>(Key);
end;


procedure SpliceInner(Outer, Inner: TJSONObject);
var
  Pair: TJSONPair;
  PairName: string;
begin
  // Move all pairs from Inner into Outer, leaving Inner empty.
  while Inner.Count > 0 do
  begin
    PairName := Inner.Pairs[0].JsonString.Value;
    Pair := Inner.RemovePair(PairName);
    Outer.AddPair(Pair);
  end;
end;

function HandleListFileColumns(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Integer;
  F: unit_Item.TFile;
  FT: TFileType;
  LocalPath, Ext: string;
  Inner: TJSONObject;
begin
  FileId := GetReqInt(Params, 'file_id');
  // Uniform refusal for out-of-scope and missing-under-scope; inert without
  // a scope, where the plain "File not found" below still applies.
  RequireFileRead(Context, FileId);

  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);

  FT := F.FileType;
  if Assigned(FT) then Ext := FT.Ext else Ext := '';

  try
    LocalPath := DownloadFileToLocal(Context, FileId);
  except
    on E: Exception do
    begin
      Result := TJSONObject.Create;
      Result.AddPair('error', E.Message);
      Exit;
    end;
  end;

  Inner := nil;
  try
    Inner := Context.PluginHost.ListFileColumns(LocalPath, Ext);
  finally
    try
      DeleteLocalDownload(LocalPath);
    except
      Inner.Free;
      raise;
    end;
  end;
  if Inner = nil then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('error', 'PluginHost returned nil');
    Exit;
  end;

  Result := TJSONObject.Create;
  try
    Result.AddPair('file_id', TJSONNumber.Create(F.Id));
    Result.AddPair('file_title', F.Title);
    SpliceInner(Result, Inner);
  finally
    Inner.Free;
  end;
end;

function HandleGetFileColumns(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Integer;
  F: unit_Item.TFile;
  FT: TFileType;
  LocalPath, Ext: string;
  Inner: TJSONObject;
begin
  FileId := GetReqInt(Params, 'file_id');
  // Uniform refusal for out-of-scope and missing-under-scope; inert without
  // a scope, where the plain "File not found" below still applies.
  RequireFileRead(Context, FileId);

  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);

  FT := F.FileType;
  if Assigned(FT) then Ext := FT.Ext else Ext := '';

  try
    LocalPath := DownloadFileToLocal(Context, FileId);
  except
    on E: Exception do
    begin
      Result := TJSONObject.Create;
      Result.AddPair('error', E.Message);
      Exit;
    end;
  end;

  Inner := nil;
  try
    Inner := Context.PluginHost.GetFileColumns(LocalPath, Ext, Params);
  finally
    try
      DeleteLocalDownload(LocalPath);
    except
      Inner.Free;
      raise;
    end;
  end;
  if Inner = nil then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('error', 'PluginHost returned nil');
    Exit;
  end;

  Result := TJSONObject.Create;
  try
    Result.AddPair('file_id', TJSONNumber.Create(F.Id));
    Result.AddPair('file_title', F.Title);
    SpliceInner(Result, Inner);
  finally
    Inner.Free;
  end;
end;

function MakeListFileColumnsSchema: TJSONObject;
var
  Props, FileId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  FileId := TJSONObject.Create;
  FileId.AddPair('type', 'integer');
  FileId.AddPair('description', 'File ID to list columns for');
  Props.AddPair('file_id', FileId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Result.AddPair('required', Req);
end;

function MakeGetFileColumnsSchema: TJSONObject;
var
  Props, FileId, Mode, Cols, MaxRows, Range: TJSONObject;
  ModeEnum: TJSONArray;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  FileId := TJSONObject.Create;
  FileId.AddPair('type', 'integer');
  FileId.AddPair('description', 'File ID to read columns from');
  Props.AddPair('file_id', FileId);

  Mode := TJSONObject.Create;
  Mode.AddPair('type', 'string');
  ModeEnum := TJSONArray.Create;
  ModeEnum.Add('raw');
  ModeEnum.Add('downsample');
  ModeEnum.Add('stats');
  Mode.AddPair('enum', ModeEnum);
  Mode.AddPair('description',
    'raw = unbinned rows; downsample = min/max-binned (default); ' +
    'stats = summary numbers, no series');
  Props.AddPair('mode', Mode);

  Cols := TJSONObject.Create;
  Cols.AddPair('type', 'array');
  Cols.AddPair('description',
    'Columns to fetch, by integer index or by name string. ' +
    'Ambiguous names error.');
  Props.AddPair('columns', Cols);

  MaxRows := TJSONObject.Create;
  MaxRows.AddPair('type', 'integer');
  MaxRows.AddPair('description',
    'Cap for downsample mode (default 500). Min/max-binned, so output is up to 2x this.');
  Props.AddPair('max_rows', MaxRows);

  Range := TJSONObject.Create;
  Range.AddPair('type', 'array');
  Range.AddPair('minItems', TJSONNumber.Create(2));
  Range.AddPair('maxItems', TJSONNumber.Create(2));
  var RangeItems := TJSONObject.Create;
  RangeItems.AddPair('type', 'integer');
  Range.AddPair('items', RangeItems);
  Range.AddPair('description',
    'Half-open [start, end) row range for raw + downsample. Optional.');
  Props.AddPair('row_range', Range);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Req.Add('columns');
  Result.AddPair('required', Req);
end;

procedure RegisterColumnarTools(Registry: TToolRegistry);
begin
  Registry.Register('list_file_columns',
    'List the columns of a tabular file (e.g. .log). Returns per-column ' +
    'metadata (index, name, units, dtype) plus total_rows and time_span. ' +
    'Use this before get_file_columns to discover what is available.',
    MakeListFileColumnsSchema, HandleListFileColumns, tscProjectScoped);

  Registry.Register('get_file_columns',
    'Fetch data for selected columns of a tabular file. Three modes: ' +
    '"stats" returns summary statistics per column; "downsample" (default) ' +
    'returns min/max-binned series capped at max_rows points (default 500); ' +
    '"raw" returns unbinned rows, optionally row-range scoped. columns can ' +
    'be integer index or name string; ambiguous names error.',
    MakeGetFileColumnsSchema, HandleGetFileColumns, tscProjectScoped);
end;

end.
