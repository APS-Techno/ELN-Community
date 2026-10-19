unit unit_ToolsFiles;

interface

uses
  unit_MCPTools;

procedure RegisterFileTools(Registry: TToolRegistry);

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections,
  System.DateUtils,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Item, unit_Project, unit_FileType, unit_ELNPluginTypes,
  unit_JSONCompact, unit_ToolScope, unit_ToolDownloads, unit_ToolsWrite,
  unit_ToolHelpers, unit_PluginHost,
  unit_ReaderValueMappingModel, unit_ReaderValueStatistics,
  unit_FilePaths;


function DateToISO(const DT: TDateTime): string;
begin
  Result := DateToISO8601(DT, False);
end;

function NullableDateToJSON(const Value: Nullable<TDateTime>): TJSONValue;
begin
  if Value.HasValue then
    Result := TJSONString.Create(DateToISO(Value.Value))
  else
    Result := TJSONNull.Create;
end;

function GetReqInt(const Params: TJSONObject; const Key: string): Integer;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<Integer>(Key);
end;



function HandleListFiles(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  Item: TItem;
  F: unit_Item.TFile;
  FT: TFileType;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);

  Arr := TJSONArray.Create;
  try
    for F in Item.Files do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', TJSONNumber.Create(F.Id));
      Obj.AddPair('title', F.Title);

      FT := F.FileType;
      if Assigned(FT) then
      begin
        Obj.AddPair('extension', FT.Ext);
        Obj.AddPair('file_type', FT.Description);
      end
      else
      begin
        Obj.AddPair('extension', '');
        Obj.AddPair('file_type', '');
      end;

      Obj.AddPair('hash', F.Hash);
      Obj.AddPair('created_date', DateToISO(F.CreatedDate));
      Obj.AddPair('modified_date', NullableDateToJSON(F.ModifiedDate));
      Arr.AddElement(Obj);
    end;
  except
    Arr.Free;
    raise;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('files', Arr);
end;

function HandleListFileTypes(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Types: TList<TFileType>;
  FT: TFileType;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  Types := Context.Manager.Find<TFileType>.List;
  try
    Arr := TJSONArray.Create;
    try
      for FT in Types do
      begin
        Obj := TJSONObject.Create;
        Obj.AddPair('id', TJSONNumber.Create(FT.Id));
        Obj.AddPair('extension', FT.Ext);
        Obj.AddPair('description', FT.Description);
        Arr.AddElement(Obj);
      end;
    except
      Arr.Free;
      raise;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('file_types', Arr);
  finally
    Types.Free;
  end;
end;

function HandleExtractFileData(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Int64;
  F: unit_Item.TFile;
  FT: TFileType;
  LocalPath, Ext, FileName, PluginJSON: string;
  ParsedData: TJSONValue;
begin
  FileId := GetReqInt64(Params, 'file_id');
  RequireFileRead(Context, FileId);

  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);

  FT := F.FileType;
  if Assigned(FT) then
    Ext := FT.Ext
  else
    Ext := '';
  FileName := F.Title + Ext;
  Ext := FileFormatExtension(FileName, Ext);

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

  try
    try
      PluginJSON := Context.PluginHost.ExtractDetailedInfo(LocalPath, Ext);
    finally
      DeleteLocalDownload(LocalPath);
    end;

    Result := TJSONObject.Create;
    try
      Result.AddPair('file_id', TJSONNumber.Create(F.Id));
      Result.AddPair('file_title', F.Title);
      Result.AddPair('file_name', FileName);
      Result.AddPair('extension', Ext);

      ParsedData := TJSONObject.ParseJSONValue(PluginJSON);
      if Assigned(ParsedData) then
      try
        Result.AddPair('data', CompactJSON(ParsedData));
      finally
        ParsedData.Free;
      end
      else
        Result.AddPair('data', TJSONObject.Create);
    except
      Result.Free;
      raise;
    end;
  except
    on E: Exception do
    begin
      Result := TJSONObject.Create;
      Result.AddPair('error', E.Message);
    end;
  end;
end;

function HandleExtractFileKeyValues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Int64;
  F: unit_Item.TFile;
  FT: TFileType;
  LocalPath, Ext, FileName, ReaderId, ReaderVersion: string;
  KeyValues: TArray<TPluginKeyValue>;
  KV: TPluginKeyValue;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Resolver: TReaderValueMappingModel;
  Mapping: TReaderValueResolution;
  Inputs: TArray<TReaderStatisticInput>;
  Statistics: TArray<TReaderValueStatistics>;
  I: Integer;
  Tolerance: Double;
  Warning: string;
  Analysis: TReaderAnalysis;
  Warnings: TJSONArray;
  SelectionField: TJSONValue;
  SelectionText: string;
begin
  FileId := GetReqInt64(Params, 'file_id');
  RequireFileRead(Context, FileId);
  SelectionText := '';
  SelectionField := Params.FindValue('selection');
  if (SelectionField <> nil) and not (SelectionField is TJSONNull) then
  begin
    if not (SelectionField is TJSONObject) then
    begin
      Result := TJSONObject.Create;
      Result.AddPair('error', 'selection must be a JSON object.');
      Exit;
    end;
    SelectionText := SelectionField.ToJSON;
  end;

  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);

  FT := F.FileType;
  if Assigned(FT) then
    Ext := FT.Ext
  else
    Ext := '';
  FileName := F.Title + Ext;
  Ext := FileFormatExtension(FileName, Ext);

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

  try
    try
      KeyValues := Context.PluginHost.ExtractReaderAnalysis(LocalPath, Ext,
        FileId, Context.Manager, SelectionText, ReaderId, ReaderVersion,
        Analysis);
    finally
      DeleteLocalDownload(LocalPath);
    end;

    if (SelectionText <> '') and
      ((Analysis.Status = 'interval_unusable') or
       (Analysis.Status = 'stale_selection')) then
      raise Exception.CreateFmt('The selection was refused: analysis_status ' +
        '%s.', [Analysis.Status]);

    Arr := TJSONArray.Create;
    Warnings := TJSONArray.Create;
    try
      SetLength(Inputs, Length(KeyValues));
      for I := 0 to High(KeyValues) do
      begin
        Inputs[I].Name := KeyValues[I].Name;
        Inputs[I].Units := KeyValues[I].Units;
        Inputs[I].Value := KeyValues[I].Value;
      end;
      Statistics := AnalyzeReaderStatistics(Inputs);
      Resolver := TReaderValueMappingModel.Create(Context.Manager);
      try
      for I := 0 to High(KeyValues) do
      begin
        KV := KeyValues[I];
        if Statistics[I].IsStandardDeviation then
        begin
          if Statistics[I].Warning <> '' then Warnings.Add(Statistics[I].Warning);
          Continue;
        end;
        Obj := TJSONObject.Create;
        Obj.AddPair('name', KV.Name);
        Obj.AddPair('value', SmartNum(KV.Value));
        Obj.AddPair('units', KV.Units);

        case KV.RecType of
          prCondition: Obj.AddPair('rec_type', 'CONDITION');
          prResult:    Obj.AddPair('rec_type', 'RESULT');
        end;

        Obj.AddPair('is_key', TJSONBool.Create(KV.IsKey));
        Obj.AddPair('description', KV.Description);
        Mapping := Resolver.Resolve(ReaderId, KV.Name, KV.Units);
        Tolerance := ConvertedReaderTolerance(Statistics[I], Mapping.Factor, Warning);
        if Warning <> '' then Obj.AddPair('tolerance_warning', Warning);
        if Mapping.ValueType <> nil then
        begin
          Obj.AddPair('value_type_id', TJSONNumber.Create(Mapping.ValueType.Id));
          Obj.AddPair('converted_value', TJSONNumber.Create(KV.Value * Mapping.Factor));
          Obj.AddPair('value_type_units', Mapping.ValueType.Units);
          Obj.AddPair('reader_units', KV.Units);
          Obj.AddPair('conversion_factor', TJSONNumber.Create(Mapping.Factor));
          Obj.AddPair('label', Mapping.LabelText);
          Obj.AddPair('mapped_description', Mapping.Description(KV.Description));
          if Statistics[I].HasStandardDeviation and (Warning = '') then
            Obj.AddPair('tolerance', TJSONNumber.Create(Tolerance));
        end
        else
          Obj.AddPair('unmapped_reason', Mapping.Reason);
        if Analysis.Snapshots[I] <> '' then
          Obj.AddPair('analysis_snapshot',
            AnalysisSnapshotValue(Analysis.Snapshots[I]));
        Arr.AddElement(Obj);
      end;
      finally
        Resolver.Free;
      end;
    except
      Arr.Free;
      Warnings.Free;
      raise;
    end;

    Result := TJSONObject.Create;
    try
      Result.AddPair('file_id', TJSONNumber.Create(F.Id));
      Result.AddPair('file_title', F.Title);
      Result.AddPair('file_name', FileName);
      Result.AddPair('extension', Ext);
      Result.AddPair('reader_id', ReaderId);
      Result.AddPair('reader_version', ReaderVersion);
      if Analysis.Status <> '' then
        Result.AddPair('analysis_status', Analysis.Status);
      Result.AddPair('key_values', Arr);
      Result.AddPair('warnings', Warnings);
    except
      Result.Free;
      raise;
    end;
  except
    on E: Exception do
    begin
      Result := TJSONObject.Create;
      Result.AddPair('error', E.Message);
    end;
  end;
end;


function MakeListFilesSchema: TJSONObject;
var
  Props, ItemId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  ItemId := TJSONObject.Create;
  ItemId.AddPair('type', 'integer');
  ItemId.AddPair('description', 'Item ID to list files for');
  Props.AddPair('item_id', ItemId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;

function MakeListFileTypesSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('properties', TJSONObject.Create);
end;

function MakeExtractFileDataSchema: TJSONObject;
var
  Props, FileId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  FileId := TJSONObject.Create;
  FileId.AddPair('type', 'integer');
  FileId.AddPair('description', 'File ID to extract data from');
  Props.AddPair('file_id', FileId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Result.AddPair('required', Req);
end;

function MakeExtractFileKeyValuesSchema: TJSONObject;
var
  Props, FileId, Selection: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  FileId := TJSONObject.Create;
  FileId.AddPair('type', 'integer');
  FileId.AddPair('description', 'File ID to extract key values from');
  Props.AddPair('file_id', FileId);
  Selection := TJSONObject.Create;
  Selection.AddPair('type', 'object');
  Selection.AddPair('description', 'Optional analysis selection used for ' +
    'this call only and not stored. FIBPS: rect_a and rect_b as inclusive ' +
    'pixel indices [x0,y0,x1,y1], pix_w and pix_h equal to the map size. ' +
    'MIT: mode indents with checked, the 1-based indent numbers, or mode ' +
    'automatic for every usable indent. ' +
    'ZRW: the shared-selection object with the current file_hash.');
  Props.AddPair('selection', Selection);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Result.AddPair('required', Req);
end;


procedure RegisterFileTools(Registry: TToolRegistry);
begin
  Registry.Register('list_files',
    'List all files attached to an item. Returns file metadata including ' +
    'title, extension, file type description, hash, and dates.',
    MakeListFilesSchema, HandleListFiles, tscProjectScoped);

  Registry.Register('list_file_types',
    'List all registered file types. Returns the extension and description ' +
    'for each file type supported by the system.',
    MakeListFileTypesSchema, HandleListFileTypes, tscGlobalRef);

  Registry.Register('extract_file_data',
    'Extract detailed structured data from a file using the appropriate ' +
    'viewer plugin. Returns parsed JSON data containing the file''s full ' +
    'content (parameters, curves, metadata) as understood by the plugin. ' +
    'The header includes the filename and format extension, including .depo.json.',
    MakeExtractFileDataSchema, HandleExtractFileData, tscProjectScoped);

  Registry.Register('extract_file_key_values',
    'Extract key measurement values from a file using the appropriate ' +
    'viewer plugin. Returns an array of named values with units, record ' +
    'type (CONDITION or RESULT), and key flag, plus file_id, reader_id and ' +
    'reader_version. Mapped keys also include value_type_id, converted_value, ' +
    'value_type_units, reader_units, conversion_factor, label and mapped_description. ' +
    'Paired STD keys are omitted; valid STD supplies tolerance in target units. ' +
    'Invalid STD supplies tolerance_warning; orphan STD is listed in warnings. ' +
    'Pass tolerance to add_value or add_values when present. ' +
    'Unmapped keys include unmapped_reason. To store a mapped value, use ' +
    'converted_value as value and mapped_description as description; pass ' +
    'source_file_id = file_id, reader_id, reader_version, key_name = name, ' +
    'reader_units and conversion_factor to add_value or add_values. ' +
    'A key computed from an analysis (for example COF) also carries ' +
    'analysis_snapshot, the JSON of the interval and file hash it used; pass ' +
    'it unchanged as analysis_snapshot to add_value or add_values so the ' +
    'value can be re-checked later. analysis_status (no_plateau, ' +
    'stale_selection or interval_unusable) appears when a key was left out. ' +
    'Drift checks use the saved conversion, not later mapping edits. ' +
    'Optional selection (JSON object) replaces the stored shared selection ' +
    'for this call only and is never stored; a reader without analysis ' +
    'support, or a selection the reader cannot use (analysis_status ' +
    'interval_unusable or stale_selection), is refused with an error. For ' +
    'a .fibps file the selection is {"rect_a":[x0,y0,x1,y1],' +
    '"rect_b":[x0,y0,x1,y1],"pix_w":W,"pix_h":H}: inclusive pixel indices ' +
    'of the two flat regions, with pix_w and pix_h equal to the map size. ' +
    'The result then carries Step Height from those rectangles with an ' +
    'analysis_snapshot of mode regions; pass it unchanged to add_value or ' +
    'add_values. To choose the rectangles, call extract_file_data on the ' +
    '.fibps file: data.heightMap is the levelled height map downsampled to ' +
    'at most 96 cells per side, with x_px and y_px (first-pixel index of ' +
    'each cell) and stride. For a .mit file the selection is ' +
    '{"mode":"indents","checked":[1,3,5]}: the 1-based indent numbers ' +
    '(records[].index + 1 of extract_file_data) to average, or ' +
    '{"mode":"automatic"} for every usable indent. An unknown, repeated, ' +
    'estimated or otherwise excluded indent, or an empty list, makes the ' +
    'selection unusable and it is refused. Every selection-dependent key ' +
    '(Hardness, Modulus, Reduced Modulus, Contact Depth, Max Force, their ' +
    'STD keys and Indent Count) then comes from those indents and carries an ' +
    'analysis_snapshot of mode indents; pass it unchanged to add_value or ' +
    'add_values. Without a selection the shared selection of the file applies ' +
    '(the indents ticked in Desktop), else every usable indent. ' +
    'The header includes the filename and format ' +
    'extension, including .depo.json.',
    MakeExtractFileKeyValuesSchema, HandleExtractFileKeyValues, tscProjectScoped);
end;

end.
