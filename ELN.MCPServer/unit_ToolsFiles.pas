unit unit_ToolsFiles;

interface

uses
  unit_MCPTools;

procedure RegisterFileTools(Registry: TToolRegistry);

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections,
  System.DateUtils,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Item, unit_Project, unit_FileType, unit_ELNPluginTypes,
  unit_JSONCompact, unit_ToolScope, unit_ToolDownloads, unit_ToolsWrite,
  unit_ToolHelpers, unit_PluginHost,
  unit_ReaderValueMappingModel, unit_ReaderValueStatistics,
  unit_FilePaths, unit_StorageCheck,
  Aurelius.Commands.Exceptions, Aurelius.Drivers.Interfaces,
  unit_ConflictHandler,
  unit_Hypothesis, unit_HypothesisGuard, unit_SignatureModel, unit_ItemModel;


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
  InBin, CheckStorage: Boolean;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);
  CheckStorage := GetOptBool(Params, 'check_storage', False);
  if CheckStorage and (Context.Storage = nil) then
    raise Exception.Create('check_storage needs notebook storage.');

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);

  InBin := ItemInRecycleBin(Context.Manager, Item);
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
      Obj.AddPair('is_deleted', TJSONBool.Create(InBin));
      if CheckStorage then
        Obj.AddPair('storage_status', StorageCheckStatusCode(
          CheckStoredFile(Context.Manager, Context.Storage, F).Status));
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

function DeleteFileInfoJSON(F: unit_Item.TFile; ItemId: Integer): TJSONObject;
var
  Ext: string;
begin
  if Assigned(F.FileType) then
    Ext := F.FileType.Ext
  else
    Ext := '';
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(F.Id));
  Result.AddPair('title', F.Title);
  Result.AddPair('extension', Ext);
  Result.AddPair('hash', F.Hash);
  Result.AddPair('item_id', TJSONNumber.Create(ItemId));
end;

function HandleDeleteFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Int64;
  DryRun, HasConfirm, Removed: Boolean;
  ConfirmHash, AttachPath, PreviewPath, BytesStatus, BytesError: string;
  F: unit_Item.TFile;
  Item: TItem;
  Project: TProject;
  HypId, ItemId, I: Integer;
  HypStatus: THypothesisStatus;
  Items, OpItems: TItemModel;
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  Committed: Boolean;
  OpFile: unit_Item.TFile;
  OpItem: TItem;
  Extracted: TArray<unit_Item.TValue>;
  ValueIds: TArray<Integer>;
  Checks, Rows, Ids: TJSONArray;
  Row: TJSONObject;
  TypeTitle: string;
begin
  FileId := GetReqInt64(Params, 'file_id');
  DryRun := GetOptBool(Params, 'dry_run', True);
  HasConfirm := GetOptStr(Params, 'confirm_hash', ConfirmHash);

  RequireFileRead(Context, FileId);
  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    RaiseOutOfScope;
  Context.Manager.Refresh(F);
  Item := F.Item;
  if not Assigned(Item) then
    RaiseOutOfScope;
  Context.Manager.Refresh(Item);
  RequireProjectRead(Context, Item.ProjectID);
  ItemId := Item.Id;

  if ItemInRecycleBin(Context.Manager, Item) then
    raise Exception.CreateFmt('Item %d is deleted.', [ItemId]);
  CheckProjectWriteAccess(Context, Item.ProjectID);
  if IsItemSignedCheck(Context.Manager, ItemId) then
    raise Exception.Create('Item is signed and cannot be modified.');
  if IsItemCitedByLockedHypothesis(Context.Manager, ItemId, HypId, HypStatus) then
    raise Exception.CreateFmt(
      'Item %d is a run of, or is cited by, hypothesis %d (%s); file %d cannot be deleted.',
      [ItemId, HypId, HypothesisStatusNames[HypStatus], FileId]);
  if IsFileCitedByLockedHypothesis(Context.Manager, FileId, HypId, HypStatus) then
    raise Exception.CreateFmt(
      'File %d is cited by hypothesis %d (%s); it cannot be deleted.',
      [FileId, HypId, HypothesisStatusNames[HypStatus]]);
  if HasConfirm and not SameText(Trim(ConfirmHash), Trim(F.Hash)) then
    raise Exception.CreateFmt(
      'confirm_hash does not match the stored hash of file %d.', [FileId]);
  if Context.Storage = nil then
    raise Exception.Create('delete_file needs notebook storage.');

  Items := TItemModel.Create(Context.Manager);
  try
    Extracted := Items.ReaderValuesOf(Item, FileId);
    Result := TJSONObject.Create;
    try
      Result.AddPair('dry_run', TJSONBool.Create(DryRun));
      Result.AddPair('file', DeleteFileInfoJSON(F, ItemId));
      if DryRun then
      begin
        Result.AddPair('deleted', TJSONBool.Create(False));
        Rows := TJSONArray.Create;
        Result.AddPair('values_to_delete', Rows);
        for I := 0 to High(Extracted) do
        begin
          if Assigned(Extracted[I].ValueType) then
            TypeTitle := Extracted[I].ValueType.Title
          else
            TypeTitle := '';
          Row := TJSONObject.Create;
          Rows.AddElement(Row);
          Row.AddPair('id', TJSONNumber.Create(Extracted[I].Id));
          Row.AddPair('value_type', TypeTitle);
          Row.AddPair('value', SmartNum(Extracted[I].Value));
        end;
        Checks := TJSONArray.Create;
        Result.AddPair('checks_passed', Checks);
        Checks.Add('scope');
        Checks.Add('not_deleted');
        Checks.Add('write_access');
        Checks.Add('not_signed');
        Checks.Add('no_locked_hypothesis');
        if HasConfirm then
          Checks.Add('confirm_hash');
        Exit;
      end;

      Project := Context.Manager.Find<TProject>(Item.ProjectID);
      AttachPath := AttachmentRelativePath(Project.FileFolder, Item.FolderName,
        F.FullName);
      PreviewPath := PreviewRelativePath(ItemId, FileId);
      Operation := TObjectManager.Create(Context.Manager.Connection);
      try
        OpFile := Operation.Find<unit_Item.TFile>(FileId);
        if (OpFile = nil) or (OpFile.Item = nil) then
          Removed := False
        else
        begin
          OpItem := OpFile.Item;
          OpItems := TItemModel.Create(Operation);
          try
            Extracted := OpItems.ReaderValuesOf(OpItem, FileId);
            SetLength(ValueIds, Length(Extracted));
            for I := 0 to High(Extracted) do
              ValueIds[I] := Extracted[I].Id;
            Transaction := TConflictHandler.BeginOperationTransaction(Context.Manager);
            Committed := False;
            try
              try
                Removed := OpItems.RemoveFile(OpFile, OpItem, Context.User.Id);
              except
                on E: EVersionedConcurrencyControl do
                  Removed := False;
              end;
              if Removed then
              begin
                Transaction.Commit;
                Committed := True;
              end;
            finally
              if not Committed then
                Transaction.Rollback;
            end;
          finally
            OpItems.Free;
          end;
        end;
      finally
        TConflictHandler.FreeOperationManager(Operation);
      end;
      if not Removed then
      begin
        RefreshCachedItem(Context, ItemId);
        raise Exception.Create('The file was not deleted. It may be signed or ' +
          'changed by another session.');
      end;

      BytesError := '';
      try
        if Context.Storage.Exists(AttachPath) then
        begin
          Context.Storage.DeleteFile(AttachPath);
          BytesStatus := 'removed';
        end
        else
          BytesStatus := 'absent';
      except
        on EAbort do
          raise;
        on E: Exception do
        begin
          BytesStatus := 'remaining';
          BytesError := StringReplace(StringReplace(E.Message, AttachPath,
            '(attachment)', [rfReplaceAll, rfIgnoreCase]),
            StringReplace(AttachPath, '/', '\', [rfReplaceAll]),
            '(attachment)', [rfReplaceAll, rfIgnoreCase]);
        end;
      end;
      try
        Context.Storage.DeleteFile(PreviewPath);
      except
        on EAbort do
          raise;
        on Exception do
          ;
      end;
      RefreshCachedItem(Context, ItemId);
      ForgetCachedRow(Context, Context.Manager.FindCached<unit_Item.TFile>(FileId));
      for I := 0 to High(ValueIds) do
        ForgetCachedRow(Context,
          Context.Manager.FindCached<unit_Item.TValue>(ValueIds[I]));

      Result.AddPair('deleted', TJSONBool.Create(True));
      Ids := TJSONArray.Create;
      Result.AddPair('values_deleted', Ids);
      for I := 0 to High(ValueIds) do
        Ids.Add(ValueIds[I]);
      Result.AddPair('bytes_status', BytesStatus);
      if BytesStatus = 'remaining' then
        Result.AddPair('bytes_error', BytesError);
    except
      Result.Free;
      raise;
    end;
  finally
    Items.Free;
  end;
end;


function MakeListFilesSchema: TJSONObject;
var
  Props, ItemId, CheckStorage: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  ItemId := TJSONObject.Create;
  ItemId.AddPair('type', 'integer');
  ItemId.AddPair('description', 'Item ID to list files for');
  Props.AddPair('item_id', ItemId);
  CheckStorage := TJSONObject.Create;
  CheckStorage.AddPair('type', 'boolean');
  CheckStorage.AddPair('description',
    'Read each file''s bytes and add storage_status. Default false.');
  Props.AddPair('check_storage', CheckStorage);
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

function MakeDeleteFileSchema: TJSONObject;
var
  Props, FileId, DryRun, ConfirmHash: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  FileId := TJSONObject.Create;
  FileId.AddPair('type', 'integer');
  FileId.AddPair('description', 'File ID to delete');
  Props.AddPair('file_id', FileId);
  DryRun := TJSONObject.Create;
  DryRun.AddPair('type', 'boolean');
  DryRun.AddPair('description', 'Default true: check and report only. ' +
    'Set false to delete.');
  Props.AddPair('dry_run', DryRun);
  ConfirmHash := TJSONObject.Create;
  ConfirmHash.AddPair('type', 'string');
  ConfirmHash.AddPair('description', 'Optional hash from list_files. The call ' +
    'is refused when the stored hash is different.');
  Props.AddPair('confirm_hash', ConfirmHash);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Result.AddPair('required', Req);
end;

function HandleDownloadFile(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  FileId: Int64;
  DestPath, FullDest, DestDir, TempPath, RelativePath, ActualHash: string;
  Overwrite, Stored: Boolean;
  F: unit_Item.TFile;
  Project: TProject;
  Status: TStorageCheckStatus;
  Size: Int64;
  Flags: DWORD;
begin
  FileId := GetReqInt64(Params, 'file_id');
  DestPath := GetReqStr(Params, 'dest_path');
  Overwrite := GetOptBool(Params, 'overwrite', False);

  CheckDownloadPathAllowed(Context, DestPath);
  RequireFileRead(Context, FileId);
  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if F.Item.IsDeleted then
    raise Exception.CreateFmt('File %d belongs to deleted item %d.',
      [FileId, F.Item.Id]);
  if Context.Storage = nil then
    raise Exception.Create('download_file needs notebook storage.');
  Project := Context.Manager.Find<TProject>(F.Item.ProjectID);
  if not Assigned(Project) or not Assigned(F.FileType) then
    raise Exception.CreateFmt(
      'File %d: storage_status error. The record has no project or file type.',
      [FileId]);
  RelativePath := AttachmentRelativePath(Project.FileFolder,
    F.Item.FolderName, F.FullName);

  try
    Stored := Context.Storage.Exists(RelativePath);
  except
    on E: Exception do
      raise Exception.CreateFmt('File %d: storage_status error. %s: %s',
        [FileId, E.ClassName, E.Message]);
  end;
  if not Stored then
    raise Exception.CreateFmt('File %d: storage_status missing. Notebook ' +
      'storage has no bytes for this record; nothing was written.', [FileId]);

  FullDest := TPath.GetFullPath(DestPath);
  DestDir := ExtractFileDir(FullDest);
  ForceDirectories(DestDir);
  CheckDownloadPathAllowed(Context, FullDest);

  TempPath := TPath.Combine(DestDir,
    '.eln-download-' + TGUID.NewGuid.ToString + '.tmp');
  try
    try
      Context.Storage.CopyOut(RelativePath, TempPath);
    except
      on E: Exception do
        raise Exception.CreateFmt('File %d: storage_status error. %s: %s',
          [FileId, E.ClassName, E.Message]);
    end;
    ActualHash := ComputeFileMD5(TempPath);
    Size := System.IOUtils.TFile.GetSize(TempPath);
    if Trim(F.Hash) = '' then
      Status := scsNoHash
    else if SameText(Trim(F.Hash), ActualHash) then
      Status := scsOk
    else
      Status := scsContentMismatch;

    Flags := MOVEFILE_WRITE_THROUGH;
    if Overwrite then
      Flags := Flags or MOVEFILE_REPLACE_EXISTING;
    if not MoveFileEx(PChar(TempPath), PChar(FullDest), Flags) then
    begin
      if GetLastError in [ERROR_ALREADY_EXISTS, ERROR_FILE_EXISTS] then
        raise Exception.CreateFmt(
          'dest_path already exists: %s. Pass overwrite true to replace it.',
          [FullDest]);
      RaiseLastOSError;
    end;
  finally
    if FileExists(TempPath) then
      System.SysUtils.DeleteFile(TempPath);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file_id', TJSONNumber.Create(FileId));
  Result.AddPair('dest_path', FullDest);
  Result.AddPair('size', TJSONNumber.Create(Size));
  Result.AddPair('md5', ActualHash);
  Result.AddPair('stored_hash', F.Hash);
  Result.AddPair('storage_status', StorageCheckStatusCode(Status));
end;

function MakeDownloadFileSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'File ID to download');
  Props.AddPair('file_id', P);
  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Absolute local path for the copy. Must sit ' +
    'under the server''s configured upload root; missing parent folders ' +
    'are created.');
  Props.AddPair('dest_path', P);
  P := TJSONObject.Create;
  P.AddPair('type', 'boolean');
  P.AddPair('description', 'Replace an existing file at dest_path. Default false.');
  Props.AddPair('overwrite', P);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('file_id');
  Req.Add('dest_path');
  Result.AddPair('required', Req);
end;


procedure RegisterFileTools(Registry: TToolRegistry);
begin
  Registry.Register('list_files',
    'List all files attached to an item. Returns file metadata including ' +
    'title, extension, file type description, hash, dates and is_deleted ' +
    '(true when the item or an ancestor is in the recycle bin). Set ' +
    'check_storage to add storage_status (ok, missing, content_mismatch, ' +
    'no_hash or error) from the stored bytes.',
    MakeListFilesSchema, HandleListFiles, tscProjectScoped);

  Registry.Register('download_file',
    'Read-only. Copy the stored bytes of a file to dest_path on the server ' +
    'computer. dest_path must sit under the configured upload root, which ' +
    'serves for both import and export; without it the tool is disabled. ' +
    'Returns file_id, dest_path, size, md5, stored_hash and storage_status ' +
    '(ok, content_mismatch or no_hash; the file is written in each case). ' +
    'Missing bytes or a storage failure give an error with storage_status ' +
    'missing or error and write nothing. overwrite false refuses an ' +
    'existing dest_path. Files of deleted items are refused.',
    MakeDownloadFileSchema, HandleDownloadFile, tscProjectScoped);

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
    'stale_selection, interval_unusable or no_step_found) appears when a ' +
    'key was left out; low_confidence appears when a Step Height was ' +
    'returned but is weak. ' +
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

  Registry.Register('delete_file',
    'Delete a file permanently. This cannot be undone from MCP. It also ' +
    'deletes the Reader values extracted from the file and their analysis ' +
    'snapshots. Manual and Unknown values stay. Call it with dry_run true ' +
    '(the default) first and check values_to_delete. Pass confirm_hash ' +
    '(the hash from list_files) to protect against a changed file. The call ' +
    'needs write access. It is refused for signed or deleted items, and for ' +
    'files or items that are a run of, or are cited by, a hypothesis in ' +
    'review or accepted. The result has bytes_status ' +
    '(removed, absent or remaining); the file record is deleted even when ' +
    'the bytes remain.',
    MakeDeleteFileSchema, HandleDeleteFile, tscProjectScoped);
end;

end.
