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
      KeyValues := Context.PluginHost.ExtractReaderKeyValues(LocalPath, Ext,
        ReaderId, ReaderVersion);
    finally
      DeleteLocalDownload(LocalPath);
    end;

    Arr := TJSONArray.Create;
    try
      for KV in KeyValues do
      begin
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
        Arr.AddElement(Obj);
      end;
    except
      Arr.Free;
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
      Result.AddPair('key_values', Arr);
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
  Props, FileId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  FileId := TJSONObject.Create;
  FileId.AddPair('type', 'integer');
  FileId.AddPair('description', 'File ID to extract key values from');
  Props.AddPair('file_id', FileId);
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
    'reader_version. To store a number from this list as a value, pass ' +
    'source_file_id = file_id, reader_id, reader_version and key_name = ' +
    'the key value name to add_value or add_values; check_value_drift then ' +
    'compares the stored value with the reader''s current output. The ' +
    'header includes the filename and format extension, including .depo.json.',
    MakeExtractFileKeyValuesSchema, HandleExtractFileKeyValues, tscProjectScoped);
end;

end.
