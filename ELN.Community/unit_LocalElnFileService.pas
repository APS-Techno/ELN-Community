unit unit_LocalElnFileService;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager,
  unit_ELNPluginCore,
  unit_NotebookStorage,
  unit_ProjectAccessPolicy,
  unit_User,
  unit_LocalNotebookStorage,
  unit_Item,
  unit_Project;

type
  // The host owns WorkingRoot and removes it only after releasing the service.
  // Plugins edit working copies, never the canonical notebook files.
  TLocalElnFileService = class(TInterfacedObject, IElnFileService)
  private
    type
      TOpenFile = record
        WorkingPath: string;
        StoragePath: string;
        Extension: string;
        Hash: string;
        Version: Integer;
      end;
  private
    FConnection: IDBConnection;
    FPrincipalId: Integer;
    FAccess: IProjectAccessPolicy;
    FStorage: INotebookStorage;
    FResolver: TLocalNotebookStorage;
    FWorkingResolver: TLocalNotebookStorage;
    FWorkingStorage: INotebookStorage;
    FStorageRoot: string;
    FOpenFiles: TDictionary<Integer, TOpenFile>;
    function RequireItem(Manager: TObjectManager; ItemId: Integer;
      RequireWrite: Boolean; out Project: TProject): TItem;
    function RequireFile(Manager: TObjectManager; FileId: Integer;
      RequireWrite: Boolean; out StoragePath: string): unit_Item.TFile;
    function RequireWorkingPath(FileId: Integer; const LocalPath: string): TOpenFile;
    function ValidateSource(const LocalPath: string): string;
    function SaveFile(FileId: Integer; const LocalPath: string; Force: Boolean;
      out ErrorMsg: string): TSaveResult;
    function RefreshFile(FileId: Integer; DiscardDraft, KeepWorkingPath: Boolean;
      out LocalPath, ErrorMsg: string): TSaveResult;
  public
    constructor Create(Manager: TObjectManager; PrincipalId: Integer;
      const Access: IProjectAccessPolicy; const Storage: INotebookStorage;
      const StorageRoot, WorkingRoot: string);
    destructor Destroy; override;
    // First open copies the canonical bytes and captures that copy's baseline.
    // Selecting an already-open file returns its draft without replacing it.
    function PrepareLocalFile(FileId: Integer): string;
    // A host notification refreshes only clean bytes unless the user has
    // explicitly resolved all editors and authorized discarding the draft.
    function RefreshLocalFile(FileId: Integer; DiscardDraft: Boolean;
      out LocalPath, ErrorMsg: string): TSaveResult;
    procedure CaptureOpenBaseline(FileId: Integer);
    // The last copied/saved baseline, not a new read of canonical storage.
    function GetOpenHash(FileId: Integer): string;
    function SaveLocalFile(FileId: Integer; const LocalPath: string;
      out ErrorMsg: string): TSaveResult;
    function SaveLocalFileForce(FileId: Integer; const LocalPath: string;
      out ErrorMsg: string): TSaveResult;
    function ReloadLocalFile(FileId: Integer; const LocalPath: string;
      out ErrorMsg: string): Boolean;
    function UploadAttachment(ItemId: Integer;
      const LocalPath, SuggestedName: string): string;
  end;

procedure InstallLocalElnFileService(Manager: TObjectManager; PrincipalId: Integer;
  const Access: IProjectAccessPolicy; const Storage: INotebookStorage;
  const StorageRoot, WorkingRoot: string);
procedure UninstallLocalElnFileService;
function PrepareLocalElnFile(FileId: Integer): string;
procedure CaptureLocalElnOpenBaseline(FileId: Integer);
function GetLocalElnOpenHash(FileId: Integer): string;
function RefreshLocalElnFile(FileId: Integer; DiscardDraft: Boolean;
  out LocalPath, ErrorMsg: string): TSaveResult;

implementation

uses
  System.Classes,
  Winapi.Windows,
  System.IOUtils,
  System.StrUtils,
  IdHashMessageDigest,
  unit_FilePaths,
  unit_ItemModel,
  unit_FileType,
  unit_SignatureModel,
  unit_TimeHelper;

type
  ELocalFileConflict = class(Exception);

function IsAbsolutePath(const Path: string): Boolean;
begin
  Result := ((Length(Path) >= 3) and (Path[2] = ':') and
    CharInSet(Path[3], ['\', '/'])) or StartsStr('\\', Path);
end;

function IsWithinRoot(const Root, Path: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(Root),
    ExcludeTrailingPathDelimiter(Path)) or
    StartsText(IncludeTrailingPathDelimiter(Root), Path);
end;

function FileMD5(const ResolvedPath: string): string;
var
  Stream: TFileStream;
  Hash: TIdHashMessageDigest5;
begin
  Stream := TFileStream.Create(ResolvedPath, fmOpenRead or fmShareDenyWrite);
  try
    Hash := TIdHashMessageDigest5.Create;
    try
      Result := Hash.HashStreamAsHex(Stream);
    finally
      Hash.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure ReleaseManager(var Manager: TObjectManager);
var
  PriorShutdown: Boolean;
begin
  PriorShutdown := ManagerShuttingDown;
  ManagerShuttingDown := True;
  try
    try
      Manager.Clear;
    finally
      FreeAndNil(Manager);
    end;
  finally
    ManagerShuttingDown := PriorShutdown;
  end;
end;

function NewBackupPath(FileId: Integer): string;
var
  Id: TGUID;
begin
  CreateGUID(Id);
  Result := Format('backups\%d-%s.bak', [FileId, GUIDToString(Id)]);
end;

constructor TLocalElnFileService.Create(Manager: TObjectManager;
  PrincipalId: Integer; const Access: IProjectAccessPolicy;
  const Storage: INotebookStorage;
  const StorageRoot, WorkingRoot: string);
var
  FullWorkingRoot: string;
begin
  inherited Create;
  if not Assigned(Manager) or (Manager.Connection = nil) then
    raise EArgumentException.Create('A notebook object manager is required');
  if PrincipalId <= 0 then
    raise EArgumentException.Create('A local principal is required');
  if Access = nil then
    raise EArgumentException.Create('An explicit project access policy is required');
  if Storage = nil then
    raise EArgumentException.Create('A notebook storage backend is required');
  FResolver := TLocalNotebookStorage.Create(StorageRoot);
  FStorageRoot := TPath.GetFullPath(StorageRoot);
  FWorkingResolver := TLocalNotebookStorage.Create(WorkingRoot);
  FWorkingStorage := FWorkingResolver;
  FullWorkingRoot := TPath.GetFullPath(WorkingRoot);
  if IsWithinRoot(FStorageRoot, FullWorkingRoot) or
    IsWithinRoot(FullWorkingRoot, FStorageRoot) then
    raise EArgumentException.Create('Notebook storage and working roots must be separate');
  FConnection := Manager.Connection;
  FPrincipalId := PrincipalId;
  FAccess := Access;
  FStorage := Storage;
  FOpenFiles := TDictionary<Integer, TOpenFile>.Create;
end;

destructor TLocalElnFileService.Destroy;
begin
  FOpenFiles.Free;
  FWorkingResolver := nil;
  FWorkingStorage := nil;
  FResolver.Free;
  FStorage := nil;
  FAccess := nil;
  FConnection := nil;
  inherited Destroy;
end;

function TLocalElnFileService.RequireItem(Manager: TObjectManager;
  ItemId: Integer; RequireWrite: Boolean; out Project: TProject): TItem;
var
  Principal: TUser;
begin
  // Resolve the pinned principal afresh in this operation's manager. Policy
  // implementations never receive a cached identity from another session.
  Principal := Manager.Find<TUser>(FPrincipalId);
  if not Assigned(Principal) then
    raise EArgumentException.Create('The pinned notebook principal does not exist');
  Result := Manager.Find<TItem>(ItemId);
  if not Assigned(Result) or Result.IsDeleted then
    raise EArgumentException.CreateFmt('Item not found: %d', [ItemId]);
  Project := Manager.Find<TProject>(Result.ProjectID);
  if not Assigned(Project) then
    raise EArgumentException.Create('The item project does not exist');
  if RequireWrite then
  begin
    if not FAccess.CanWrite(Manager, Principal, Project.Id) then
      raise EArgumentException.Create('The principal cannot write this project');
    if IsItemSignedCheck(Manager, Result.Id) then
      raise EArgumentException.CreateFmt('Item %d is signed; its files cannot be changed',
        [Result.Id]);
  end
  else if not FAccess.CanRead(Manager, Principal, Project.Id) then
    raise EArgumentException.Create('The principal cannot read this project');
end;

function TLocalElnFileService.RequireFile(Manager: TObjectManager;
  FileId: Integer; RequireWrite: Boolean;
  out StoragePath: string): unit_Item.TFile;
var
  Item: TItem;
  Project: TProject;
begin
  if FileId <= 0 then
    raise EArgumentException.Create('A positive file identifier is required');
  Result := Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(Result) or not Assigned(Result.Item) then
    raise EArgumentException.CreateFmt('File not found: %d', [FileId]);
  Item := RequireItem(Manager, Result.Item.Id, RequireWrite, Project);
  StoragePath := Format('Projects\%s\%s\%s',
    [CleanFileName(Project.FileFolder), CleanFileName(Item.FolderName), Result.FullName]);
  FResolver.ResolvePath(StoragePath);
end;

function TLocalElnFileService.RequireWorkingPath(FileId: Integer;
  const LocalPath: string): TOpenFile;
var
  Expected: string;
begin
  if not FOpenFiles.TryGetValue(FileId, Result) then
    raise EArgumentException.Create('No prepared working copy for this file');
  Expected := FWorkingResolver.ResolvePath(Result.WorkingPath);
  if not IsAbsolutePath(LocalPath) or
    not SameText(Expected, TPath.GetFullPath(LocalPath)) then
    raise EArgumentException.Create('The supplied path is not this file''s working copy');
end;

function TLocalElnFileService.ValidateSource(const LocalPath: string): string;
var
  Resolver: TLocalNotebookStorage;
begin
  if not IsAbsolutePath(LocalPath) then
    raise EArgumentException.Create('Attachment source must be an absolute file path');
  Result := TPath.GetFullPath(LocalPath);
  if IsWithinRoot(FStorageRoot, Result) then
    raise EArgumentException.Create('Use an external attachment source, not a notebook file');
  Resolver := TLocalNotebookStorage.Create(ExtractFileDir(Result));
  try
    Result := Resolver.ResolvePath(ExtractFileName(Result));
    if not System.IOUtils.TFile.Exists(Result) then
      raise EFileNotFoundException.Create('Attachment source does not exist');
  finally
    Resolver.Free;
  end;
end;

function TLocalElnFileService.PrepareLocalFile(FileId: Integer): string;
var
  Manager: TObjectManager;
  AFile: unit_Item.TFile;
  OpenFile: TOpenFile;
  StoragePath: string;
begin
  Manager := TObjectManager.Create(FConnection);
  try
    AFile := RequireFile(Manager, FileId, False, StoragePath);
    if FOpenFiles.TryGetValue(FileId, OpenFile) then
      Exit(FWorkingResolver.ResolvePath(OpenFile.WorkingPath));
    OpenFile.WorkingPath := Format('files\%d\%s', [FileId, AFile.FullName]);
    OpenFile.StoragePath := StoragePath;
    OpenFile.Extension := AFile.FileType.Ext;
    OpenFile.Version := AFile.Version;
    Result := FWorkingResolver.ResolvePath(OpenFile.WorkingPath);
    try
      FStorage.CopyOut(StoragePath, Result);
      // Hash the copied bytes: a later canonical edit must not advance this baseline.
      OpenFile.Hash := FileMD5(FWorkingResolver.ResolvePath(OpenFile.WorkingPath));
      FOpenFiles.Add(FileId, OpenFile);
    except
      FWorkingStorage.DeleteFile(OpenFile.WorkingPath);
      raise;
    end;
  finally
    ReleaseManager(Manager);
  end;
end;

procedure TLocalElnFileService.CaptureOpenBaseline(FileId: Integer);
begin
  PrepareLocalFile(FileId);
end;

function TLocalElnFileService.GetOpenHash(FileId: Integer): string;
var
  OpenFile: TOpenFile;
begin
  if not FOpenFiles.TryGetValue(FileId, OpenFile) then
    raise EArgumentException.Create('No prepared working copy for this file');
  Result := OpenFile.Hash;
end;


function TLocalElnFileService.SaveFile(FileId: Integer; const LocalPath: string;
  Force: Boolean; out ErrorMsg: string): TSaveResult;
var
  Manager: TObjectManager;
  Items: TItemModel;
  AFile: unit_Item.TFile;
  OpenFile: TOpenFile;
  StoragePath, BackupPath, CurrentHash, NewHash, Failure: string;
  Transaction: IDBTransaction;
  Written, HadBytes, KeepBackup, RolledBack, Restored: Boolean;
begin
  Result := srError;
  ErrorMsg := '';
  try
    // Missing baseline is a conflict, never permission for a silent overwrite.
    if not FOpenFiles.TryGetValue(FileId, OpenFile) then
    begin
      ErrorMsg := 'No open-time baseline; prepare or reload the file before saving';
      Exit(srConflict);
    end;
    OpenFile := RequireWorkingPath(FileId, LocalPath);
    Manager := TObjectManager.Create(FConnection);
    try
      BackupPath := NewBackupPath(FileId);
      Written := False;
      KeepBackup := False;
      HadBytes := False;
      try
        // Authorization and signature reads belong to the same DB transaction
        // as the metadata write, not an earlier cached host-manager snapshot.
        Transaction := FConnection.BeginTransaction;
        try
          AFile := RequireFile(Manager, FileId, True, StoragePath);
          if not SameText(StoragePath, OpenFile.StoragePath) then
            raise ELocalFileConflict.Create('The attachment path changed; reload before saving');
          HadBytes := FStorage.Exists(StoragePath);
          if HadBytes then
          begin
            FStorage.CopyOut(StoragePath, FWorkingResolver.ResolvePath(BackupPath));
            CurrentHash := FileMD5(FWorkingResolver.ResolvePath(BackupPath));
          end
          else
            CurrentHash := '';
          if not Force and (not HadBytes or
            not SameText(CurrentHash, OpenFile.Hash) or
            (AFile.Version <> OpenFile.Version)) then
            raise ELocalFileConflict.Create('The notebook file changed since it was opened');
          Items := TItemModel.Create(Manager);
          try
            FStorage.CopyIn(FWorkingResolver.ResolvePath(OpenFile.WorkingPath), StoragePath);
            Written := True;
            NewHash := FileMD5(FResolver.ResolvePath(StoragePath));
            AFile.Hash := NewHash;
            if not Items.UpdateFile(AFile, FPrincipalId) then
              raise ELocalFileConflict.Create('File metadata update conflicted');
            Transaction.Commit;
          finally
            Items.Free;
          end;
        except
          on E: Exception do
          begin
            Failure := E.Message;
            RolledBack := False;
            try
              Transaction.Rollback;
              RolledBack := True;
            except
              on R: Exception do
                Failure := Failure + '; database rollback failed: ' + R.Message;
            end;
            Restored := not Written;
            if Written then
            begin
              KeepBackup := HadBytes;
              if RolledBack then
                try
                  if HadBytes then
                    FStorage.CopyIn(FWorkingResolver.ResolvePath(BackupPath), StoragePath)
                  else
                    FStorage.DeleteFile(StoragePath);
                  KeepBackup := False;
                  Restored := True;
                except
                  on R: Exception do
                    Failure := Failure + '; file restoration failed: ' + R.Message;
                end;
              if KeepBackup then
                Failure := Failure + '; original bytes retained at ' +
                  FWorkingResolver.ResolvePath(BackupPath);
            end;
            if (E is ELocalFileConflict) and RolledBack and Restored then
              raise ELocalFileConflict.Create(Failure);
            raise EInvalidOperation.Create(Failure);
          end;
        end;
        OpenFile.Hash := NewHash;
        OpenFile.Version := AFile.Version;
        FOpenFiles.AddOrSetValue(FileId, OpenFile);
        Result := srOk;
      finally
        if not KeepBackup then
          FWorkingStorage.DeleteFile(BackupPath);
      end;
    finally
      ReleaseManager(Manager);
    end;
  except
    on E: ELocalFileConflict do
    begin
      ErrorMsg := E.Message;
      Result := srConflict;
    end;
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      Result := srError;
    end;
  end;
end;

function TLocalElnFileService.SaveLocalFile(FileId: Integer;
  const LocalPath: string; out ErrorMsg: string): TSaveResult;
begin
  Result := SaveFile(FileId, LocalPath, False, ErrorMsg);
end;

function TLocalElnFileService.SaveLocalFileForce(FileId: Integer;
  const LocalPath: string; out ErrorMsg: string): TSaveResult;
begin
  Result := SaveFile(FileId, LocalPath, True, ErrorMsg);
end;

function TLocalElnFileService.RefreshFile(FileId: Integer;
  DiscardDraft, KeepWorkingPath: Boolean;
  out LocalPath, ErrorMsg: string): TSaveResult;
var
  Manager: TObjectManager;
  AFile: unit_Item.TFile;
  OpenFile: TOpenFile;
  StoragePath, StagedPath, BaselineHash: string;
  WorkingGuard: THandle;
  Generation: TGUID;
begin
  Result := srError;
  LocalPath := '';
  ErrorMsg := '';
  try
    if not FOpenFiles.TryGetValue(FileId, OpenFile) then
    begin
      LocalPath := PrepareLocalFile(FileId);
      Exit(srOk);
    end;
    LocalPath := FWorkingResolver.ResolvePath(OpenFile.WorkingPath);
    BaselineHash := OpenFile.Hash;
    if not DiscardDraft and not SameText(FileMD5(LocalPath), OpenFile.Hash) then
    begin
      ErrorMsg := 'The working copy has unsaved changes';
      Exit(srConflict);
    end;
    Manager := TObjectManager.Create(FConnection);
    try
      AFile := RequireFile(Manager, FileId, False, StoragePath);
      if KeepWorkingPath and
        not SameText(AFile.FileType.Ext, OpenFile.Extension) then
      begin
        ErrorMsg := 'The attachment type changed; close the editor and reload through the notebook host';
        Exit(srConflict);
      end;
      if not KeepWorkingPath and
        (not DiscardDraft or not SameText(ExtractFileName(LocalPath), AFile.FullName)) then
      begin
        // A new generation never overwrites an older retained editor path.
        CreateGUID(Generation);
        OpenFile.WorkingPath := Format('files\%d\%s\%s',
          [FileId, GUIDToString(Generation), AFile.FullName]);
      end;
      OpenFile.StoragePath := StoragePath;
      OpenFile.Extension := AFile.FileType.Ext;
      OpenFile.Version := AFile.Version;
      StagedPath := NewBackupPath(FileId);
      WorkingGuard := INVALID_HANDLE_VALUE;
      try
        // Copy and hash before touching the draft. CopyOut may fail after
        // writing partial bytes; CopyIn uses the working storage's atomic write.
        FStorage.CopyOut(StoragePath, FWorkingResolver.ResolvePath(StagedPath));
        OpenFile.Hash := FileMD5(FWorkingResolver.ResolvePath(StagedPath));
        if not DiscardDraft then
        begin
          // Guard the old copy against direct writes and atomic replacement.
          // Installation targets a fresh generation, so no delete share is
          // needed and the original path stays intact after the guard closes.
          WorkingGuard := CreateFile(PChar(LocalPath), GENERIC_READ,
            FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
          if WorkingGuard = INVALID_HANDLE_VALUE then RaiseLastOSError;
          if not SameText(FileMD5(LocalPath), BaselineHash) then
          begin
            ErrorMsg := 'The working copy changed while the attachment was being refreshed';
            Exit(srConflict);
          end;
        end;
        FWorkingStorage.CopyIn(FWorkingResolver.ResolvePath(StagedPath), OpenFile.WorkingPath);
        FOpenFiles.AddOrSetValue(FileId, OpenFile);
        LocalPath := FWorkingResolver.ResolvePath(OpenFile.WorkingPath);
        Result := srOk;
      finally
        if WorkingGuard <> INVALID_HANDLE_VALUE then CloseHandle(WorkingGuard);
        FWorkingStorage.DeleteFile(StagedPath);
      end;
    finally
      ReleaseManager(Manager);
    end;
  except
    on E: Exception do
      ErrorMsg := E.Message;
  end;
end;

function TLocalElnFileService.RefreshLocalFile(FileId: Integer;
  DiscardDraft: Boolean; out LocalPath, ErrorMsg: string): TSaveResult;
begin
  Result := RefreshFile(FileId, DiscardDraft, False, LocalPath, ErrorMsg);
end;

function TLocalElnFileService.ReloadLocalFile(FileId: Integer;
  const LocalPath: string; out ErrorMsg: string): Boolean;
var
  RefreshedPath: string;
begin
  Result := False;
  ErrorMsg := '';
  try
    RequireWorkingPath(FileId, LocalPath);
    // Plugins reload the exact path they opened. A changed extension requires
    // host redisplay and plugin selection, not new-format bytes at the old path.
    Result := RefreshFile(FileId, True, True, RefreshedPath, ErrorMsg) = srOk;
  except
    on E: Exception do
      ErrorMsg := E.Message;
  end;
end;

function TLocalElnFileService.UploadAttachment(ItemId: Integer;
  const LocalPath, SuggestedName: string): string;
var
  Manager: TObjectManager;
  Items: TItemModel;
  Item: TItem;
  Project: TProject;
  AFile: unit_Item.TFile;
  FileType, Candidate: TFileType;
  FileTypes: TFileTypes;
  Source, Name, Ext, Title, StoragePath, Failure: string;
  Transaction: IDBTransaction;
  Written, RolledBack: Boolean;
begin
  Manager := TObjectManager.Create(FConnection);
  try
    Source := ValidateSource(LocalPath);
    Name := SuggestedName;
    if Name = '' then
      Name := ExtractFileName(Source);
    if (Name <> ExtractFileName(Name)) or (Pos(':', Name) > 0) then
      raise EArgumentException.Create('An attachment name must not contain a path');
    Name := CleanFileName(Name);
    Ext := ExtractFileExt(Name);
    Title := ChangeFileExt(Name, '');
    if (Trim(Title) = '') or (Length(Title) > 255) then
      raise EArgumentException.Create('Attachment title must contain 1 to 255 characters');
    FileType := nil;
    FileTypes := Manager.Find<TFileType>.List;
    try
      for Candidate in FileTypes do
        if SameText(Candidate.Ext, Ext) then
        begin
          FileType := Candidate;
          Break;
        end;
    finally
      FileTypes.Free;
    end;
    Items := TItemModel.Create(Manager);
    try
      Written := False;
      StoragePath := '';
      Transaction := FConnection.BeginTransaction;
      try
        Item := RequireItem(Manager, ItemId, True, Project);
        if not Assigned(FileType) then
        begin
          FileType := TFileType.Create;
          FileType.Ext := Ext;
          FileType.Description := Ext;
          FileType.CreatedDate := UTCNow;
          FileType.CreatedBy := FPrincipalId;
          Manager.Save(FileType);
          Manager.Flush;
        end;
        // AddFile supplies creation metadata, signature checks and the create audit.
        // Its flush remains inside this transaction until the bytes are stored.
        AFile := Items.AddFile(FileType, Title, FPrincipalId, Item);
        if not Assigned(AFile) then
          raise EInvalidOperation.Create('Attachment metadata creation failed');
        StoragePath := Format('Projects\%s\%s\%s',
          [CleanFileName(Project.FileFolder), CleanFileName(Item.FolderName), AFile.FullName]);
        FResolver.ResolvePath(StoragePath);
        if FStorage.Exists(StoragePath) then
          raise EInvalidOperation.Create('Attachment storage path already exists');
        FStorage.CopyIn(Source, StoragePath);
        Written := True;
        AFile.Hash := FileMD5(FResolver.ResolvePath(StoragePath));
        if not Items.UpdateFile(AFile, FPrincipalId) then
          raise EInvalidOperation.Create('Attachment metadata update conflicted');
        Transaction.Commit;
        Result := AFile.Title + AFile.FileType.Ext;
      except
        on E: Exception do
        begin
          Failure := E.Message;
          RolledBack := False;
          try
            Transaction.Rollback;
            RolledBack := True;
          except
            on R: Exception do
              Failure := Failure + '; database rollback failed: ' + R.Message;
          end;
          if Written and RolledBack then
            try
              FStorage.DeleteFile(StoragePath);
            except
              on R: Exception do
                Failure := Failure + '; attachment cleanup failed: ' + R.Message;
            end;
          if Written and not RolledBack then
            Failure := Failure + '; attachment bytes retained at ' +
              FResolver.ResolvePath(StoragePath);
          raise EInvalidOperation.Create(Failure);
        end;
      end;
    finally
      Items.Free;
    end;
  finally
    ReleaseManager(Manager);
  end;
end;

var
  GLocalService: TLocalElnFileService;

procedure InstallLocalElnFileService(Manager: TObjectManager; PrincipalId: Integer;
  const Access: IProjectAccessPolicy; const Storage: INotebookStorage;
  const StorageRoot, WorkingRoot: string);
var
  Service: TLocalElnFileService;
begin
  Service := TLocalElnFileService.Create(Manager, PrincipalId, Access, Storage,
    StorageRoot, WorkingRoot);
  ElnFileService := Service;
  GLocalService := Service;
end;

procedure UninstallLocalElnFileService;
begin
  GLocalService := nil;
  ElnFileService := nil;
end;

function PrepareLocalElnFile(FileId: Integer): string;
begin
  if not Assigned(GLocalService) then
    raise EInvalidOperation.Create('The local file service is not installed');
  Result := GLocalService.PrepareLocalFile(FileId);
end;

procedure CaptureLocalElnOpenBaseline(FileId: Integer);
begin
  if not Assigned(GLocalService) then
    raise EInvalidOperation.Create('The local file service is not installed');
  GLocalService.CaptureOpenBaseline(FileId);
end;

function GetLocalElnOpenHash(FileId: Integer): string;
begin
  if not Assigned(GLocalService) then
    raise EInvalidOperation.Create('The local file service is not installed');
  Result := GLocalService.GetOpenHash(FileId);
end;

function RefreshLocalElnFile(FileId: Integer; DiscardDraft: Boolean;
  out LocalPath, ErrorMsg: string): TSaveResult;
begin
  if not Assigned(GLocalService) then
    raise EInvalidOperation.Create('The local file service is not installed');
  Result := GLocalService.RefreshLocalFile(FileId, DiscardDraft, LocalPath, ErrorMsg);
end;

end.
