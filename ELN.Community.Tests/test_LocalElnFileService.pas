unit test_LocalElnFileService;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLocalElnFileService = class
  public
    [Test]
    procedure CanonicalEditAfterCopyIsNotMistakenForOpenBaseline;
    [Test]
    procedure CleanReloadAdvancesCopiedBaselineForNextSave;
    [Test]
    procedure CancelKeepsDraftAndOriginalConflictBaseline;
    [Test]
    procedure ExplicitReloadDiscardsDraftOnlyOnSuccess;
    [Test]
    procedure FailedReloadPreservesDraftAndBaseline;
    [Test]
    procedure PluginReloadRejectsChangedExtensionWithoutReplacingDraft;
    [Test]
    procedure CleanNotificationRefreshesBytesAndNextSaveBaseline;
    [Test]
    procedure DirtyNotificationKeepsDraftUntilExplicitResolution;
    [Test]
    procedure ExtensionChangingRefreshUpdatesPathAndNextSave;
    [Test]
    procedure FailedExtensionRefreshKeepsOldPathAndBaseline;
    [Test]
    procedure CanonicalEditDuringRefreshStillConflictsOnSave;
    [Test]
    procedure RenamedAttachmentRefreshUpdatesPathAndNextSave;
    [Test]
    procedure LockedWorkingCopyRefreshPreservesDraftAndBaseline;
    [Test]
    procedure WorkingEditDuringCanonicalCopyRequiresExplicitResolution;
    [Test]
    procedure AtomicExternalSaveCannotReplaceCleanCopyDuringRefreshInstall;
    [Test]
    procedure CanonicalWriteAfterBackupIsRefusedWithoutLosingDraft;
    [Test]
    procedure AtomicCanonicalReplaceAfterBackupIsDenied;
    [Test]
    procedure AtomicCanonicalReplaceAfterInstallIsDenied;
    [Test]
    procedure MetadataFailureRestoresBytesAndKeepsDraft;
    [Test]
    procedure FailedCompensationRetainsDurableBackup;
    [Test]
    procedure ForceSaveMissingFileRollsBackToAbsence;
    [Test]
    procedure MissingCanonicalCreatedBeforeInstallIsNotOverwritten;
    [Test]
    procedure GuardedBinaryInstallAndRollbackPreserveWholeFiles;
    [Test]
    procedure LockedCanonicalSavePreservesDraft;
    [Test]
    procedure DirectCanonicalWriteAfterBackupIsDenied;
    [Test]
    procedure GuardCommitReleasesHandlesBeforeInterfaceDestruction;
    [Test]
    procedure MissingFileGuardPreventsParentRenameAndJunctionSwap;
    [Test]
    procedure CommitAcknowledgementFailureRetainsCommittedBytesAndBackup;
    [Test]
    procedure MissingFileGuardPreventsInPlaceJunction;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Rtti,
  Winapi.Windows,
  Aurelius.Drivers.Interfaces,
  System.Variants,
  unit_NotebookStorage,
  unit_LocalNotebook,
  unit_LocalElnFileService,
  unit_ELNPluginCore,
  unit_ProjectModel,
  unit_ItemModel,
  unit_Project,
  unit_Item,
  unit_ItemTypes,
  unit_FileType,
  unit_FilePaths,
  unit_TimeHelper;

type
  TCommitThenRaise = class(TInterfacedObject, IDBTransaction)
  private
    FTransaction: IDBTransaction;
    FCommitted: Boolean;
  public
    constructor Create(const Transaction: IDBTransaction);
    procedure Commit;
    procedure Rollback;
  end;

  TCommitFailureConnection = class(TInterfacedObject, IDBConnection)
  private
    FConnection: IDBConnection;
    FInjected: Boolean;
  public
    constructor Create(const Connection: IDBConnection);
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    function CreateStatement: IDBStatement;
    function BeginTransaction: IDBTransaction;
    function SqlDialect: string;
  end;

constructor TCommitThenRaise.Create(const Transaction: IDBTransaction);
begin
  inherited Create;
  FTransaction := Transaction;
end;

procedure TCommitThenRaise.Commit;
begin
  FTransaction.Commit;
  FCommitted := True;
  raise EInOutError.Create('Synthetic lost commit acknowledgement');
end;

procedure TCommitThenRaise.Rollback;
begin
  // A successful no-op rollback is not evidence that Commit did not persist.
  if not FCommitted then FTransaction.Rollback;
end;

constructor TCommitFailureConnection.Create(const Connection: IDBConnection);
begin
  inherited Create;
  FConnection := Connection;
end;

procedure TCommitFailureConnection.Connect;
begin
  FConnection.Connect;
end;

procedure TCommitFailureConnection.Disconnect;
begin
  FConnection.Disconnect;
end;

function TCommitFailureConnection.IsConnected: Boolean;
begin
  Result := FConnection.IsConnected;
end;

function TCommitFailureConnection.CreateStatement: IDBStatement;
begin
  Result := FConnection.CreateStatement;
end;

function TCommitFailureConnection.BeginTransaction: IDBTransaction;
begin
  Result := FConnection.BeginTransaction;
  if not FInjected then
  begin
    FInjected := True;
    Result := TCommitThenRaise.Create(Result);
  end;
end;

function TCommitFailureConnection.SqlDialect: string;
begin
  Result := FConnection.SqlDialect;
end;

type
  // Simulates another local application changing the canonical file after
  // CopyOut has delivered the editor's original bytes, before open completes.
  TEditAfterCopyStorage = class(TInterfacedObject, INotebookStorage, IFileRelocator,
    INotebookStorageUpdates)
  private
    FStorage: INotebookStorage;
    FFailCopy: Boolean;
    FArmed: Boolean;
    FWorkingEditPath: string;
    FAtomicReplacePath: string;
    FAtomicReplaceSucceeded: Boolean;
    FAfterBackupReplacePath: string;
    FAfterInstallReplacePath: string;
    FFailRollback: Boolean;
    FAfterBackupWritePath: string;
    FDirectWriteSucceeded: Boolean;
    procedure AfterCopy(const RelativePath, TargetPath: string);
    procedure TryAtomicReplace(var Path: string);
  public
    constructor Create(const Storage: INotebookStorage);
    function ReadBytes(const RelativePath: string): TBytes;
    procedure WriteBytes(const RelativePath: string; const Data: TBytes);
    procedure CopyIn(const SourcePath, RelativePath: string);
    procedure CopyOut(const RelativePath, TargetPath: string);
    procedure MoveFile(const OldPath, NewPath: string);
    procedure DeleteFile(const RelativePath: string);
    function Exists(const RelativePath: string): Boolean;
    function BeginFileUpdate(const RelativePath: string): INotebookFileUpdate;
    property FailCopy: Boolean read FFailCopy write FFailCopy;
    property WorkingEditPath: string read FWorkingEditPath write FWorkingEditPath;
    property AtomicReplacePath: string read FAtomicReplacePath write FAtomicReplacePath;
    property AtomicReplaceSucceeded: Boolean read FAtomicReplaceSucceeded;
  end;

  TObservedFileUpdate = class(TInterfacedObject, INotebookFileUpdate)
  private
    FOwner: TEditAfterCopyStorage;
    FUpdate: INotebookFileUpdate;
    FPath: string;
  public
    constructor Create(Owner: TEditAfterCopyStorage; const Path: string);
    function Exists: Boolean;
    function OpenRead: TStream;
    procedure CopyOut(const TargetPath: string);
    procedure InstallFrom(const SourcePath: string);
    procedure Rollback;
    procedure Commit;
  end;

constructor TObservedFileUpdate.Create(Owner: TEditAfterCopyStorage; const Path: string);
begin
  inherited Create;
  FOwner := Owner;
  FPath := Path;
  FUpdate := (Owner.FStorage as INotebookStorageUpdates).BeginFileUpdate(Path);
end;

function TObservedFileUpdate.Exists: Boolean;
begin
  Result := FUpdate.Exists;
end;

function TObservedFileUpdate.OpenRead: TStream;
begin
  Result := FUpdate.OpenRead;
end;

procedure TObservedFileUpdate.CopyOut(const TargetPath: string);
begin
  FUpdate.CopyOut(TargetPath);
  FOwner.AfterCopy(FPath, TargetPath);
end;

procedure TObservedFileUpdate.InstallFrom(const SourcePath: string);
begin
  FUpdate.InstallFrom(SourcePath);
  FOwner.TryAtomicReplace(FOwner.FAfterInstallReplacePath);
end;

procedure TObservedFileUpdate.Rollback;
begin
  if FOwner.FFailRollback then
    raise EInOutError.Create('Synthetic restoration failure');
  FUpdate.Rollback;
end;

procedure TObservedFileUpdate.Commit;
begin
  FUpdate.Commit;
end;

function TEditAfterCopyStorage.BeginFileUpdate(const RelativePath: string): INotebookFileUpdate;
begin
  Result := TObservedFileUpdate.Create(Self, RelativePath);
end;

procedure TEditAfterCopyStorage.TryAtomicReplace(var Path: string);
var
  ExternalPath: string;
begin
  if Path = '' then Exit;
  ExternalPath := Path + '.external.tmp';
  System.IOUtils.TFile.WriteAllBytes(ExternalPath, TEncoding.UTF8.GetBytes('atomic external edit'));
  try
    FAtomicReplaceSucceeded := MoveFileEx(PChar(ExternalPath), PChar(Path),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
    Path := '';
  finally
    if System.IOUtils.TFile.Exists(ExternalPath) then System.IOUtils.TFile.Delete(ExternalPath);
  end;
end;

constructor TEditAfterCopyStorage.Create(const Storage: INotebookStorage);
begin
  inherited Create;
  FStorage := Storage;
  FArmed := True;
end;

function TEditAfterCopyStorage.ReadBytes(const RelativePath: string): TBytes;
begin
  Result := FStorage.ReadBytes(RelativePath);
end;

procedure TEditAfterCopyStorage.WriteBytes(const RelativePath: string;
  const Data: TBytes);
begin
  FStorage.WriteBytes(RelativePath, Data);
end;

procedure TEditAfterCopyStorage.CopyIn(const SourcePath, RelativePath: string);
var
  ExternalPath: string;
begin
  if FAtomicReplacePath <> '' then
  begin
    ExternalPath := FAtomicReplacePath + '.external.tmp';
    System.IOUtils.TFile.WriteAllBytes(ExternalPath, TEncoding.UTF8.GetBytes('atomic external draft'));
    try
      FAtomicReplaceSucceeded := MoveFileEx(PChar(ExternalPath), PChar(FAtomicReplacePath),
        MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
      FAtomicReplacePath := '';
    finally
      if System.IOUtils.TFile.Exists(ExternalPath) then System.IOUtils.TFile.Delete(ExternalPath);
    end;
  end;
  FStorage.CopyIn(SourcePath, RelativePath);
  TryAtomicReplace(FAfterInstallReplacePath);
end;

procedure TEditAfterCopyStorage.CopyOut(const RelativePath, TargetPath: string);
begin
  FStorage.CopyOut(RelativePath, TargetPath);
  AfterCopy(RelativePath, TargetPath);
end;

procedure TEditAfterCopyStorage.AfterCopy(const RelativePath, TargetPath: string);
var
  Handle: THandle;
  ByteWritten: Byte;
  Count: DWORD;
begin
  TryAtomicReplace(FAfterBackupReplacePath);
  if FAfterBackupWritePath <> '' then
  begin
    Handle := CreateFile(PChar(FAfterBackupWritePath), GENERIC_WRITE,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, 0);
    FDirectWriteSucceeded := Handle <> INVALID_HANDLE_VALUE;
    if FDirectWriteSucceeded then
    try
      ByteWritten := 42;
      Winapi.Windows.WriteFile(Handle, ByteWritten, 1, Count, nil);
    finally
      CloseHandle(Handle);
    end;
    FAfterBackupWritePath := '';
  end;
  if FFailCopy then
  begin
    System.IOUtils.TFile.WriteAllBytes(TargetPath, TEncoding.UTF8.GetBytes('partial copy'));
    raise EInOutError.Create('Synthetic copy failure');
  end;
  if FArmed then
  begin
    FArmed := False;
    FStorage.WriteBytes(RelativePath, TEncoding.UTF8.GetBytes('external edit'));
  end;
  if FWorkingEditPath <> '' then
  begin
    System.IOUtils.TFile.WriteAllBytes(FWorkingEditPath, TEncoding.UTF8.GetBytes('external working draft'));
    FWorkingEditPath := '';
  end;
end;

procedure TEditAfterCopyStorage.MoveFile(const OldPath, NewPath: string);
begin
  FStorage.MoveFile(OldPath, NewPath);
end;

procedure TEditAfterCopyStorage.DeleteFile(const RelativePath: string);
begin
  FStorage.DeleteFile(RelativePath);
end;

function TEditAfterCopyStorage.Exists(const RelativePath: string): Boolean;
begin
  Result := FStorage.Exists(RelativePath);
end;

type
  TWorkingCopyFixture = class
  public
    Root, StorageRoot, WorkingRoot, StoragePath, WorkingPath: string;
    Notebook: TLocalNotebook;
    Storage: INotebookStorage;
    CopyStorage: TEditAfterCopyStorage;
    Service: TLocalElnFileService;
    AFile: unit_Item.TFile;
    constructor Create;
    destructor Destroy; override;
    procedure Reupload(const Body, Ext: string);
  end;

constructor TWorkingCopyFixture.Create;
var
  Id: TGUID;
  Projects: TProjectsModel;
  Items: TItemModel;
  Project: TProject;
  Item: TItem;
  FileType: TFileType;
begin
  inherited Create;
  CreateGUID(Id);
  Root := TPath.Combine(TPath.GetTempPath, 'ELN-WorkingCopy-' + GUIDToString(Id));
  StorageRoot := TPath.Combine(Root, 'attachments');
  WorkingRoot := TPath.Combine(Root, 'working');
  Notebook := TLocalNotebook.CreateNew(TPath.Combine(Root, 'notebook.sqlite'),
    StorageRoot, 'Fixture', 'Author', 'fixture-signing-password');
  Projects := TProjectsModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Projects.AssignUser(Notebook.Principal);
    Project := Projects.AddProject('Fixture project', '', Notebook.Principal);
  finally
    Projects.Free;
  end;
  Items := TItemModel.Create(Notebook.Manager);
  try
    Items.AssignProject(Project.Id, 0);
    Item := Items.AddItem(TItemType.Other, 'Fixture item');
    FileType := TFileType.Create;
    FileType.Ext := '.md';
    FileType.CreatedDate := UTCNow;
    FileType.CreatedBy := Notebook.Principal.Id;
    Notebook.Manager.Save(FileType);
    Notebook.Manager.Flush;
    AFile := Items.AddFile(FileType, 'page', Notebook.Principal.Id, Item);
    StoragePath := Format('Projects\%s\%s\%s',
      [CleanFileName(Project.FileFolder), CleanFileName(Item.FolderName), AFile.FullName]);
    Notebook.Storage.WriteBytes(StoragePath, TEncoding.UTF8.GetBytes('opened bytes'));
  finally
    Items.Free;
  end;
  CopyStorage := TEditAfterCopyStorage.Create(Notebook.Storage);
  CopyStorage.FArmed := False;
  Storage := CopyStorage;
  Service := TLocalElnFileService.Create(Notebook.Manager, Notebook.Principal.Id,
    Notebook.AccessPolicy, Storage, StorageRoot, WorkingRoot);
  WorkingPath := Service.PrepareLocalFile(AFile.Id);
end;

destructor TWorkingCopyFixture.Destroy;
begin
  Service.Free;
  Storage := nil;
  Notebook.Free;
  if (Root <> '') and TDirectory.Exists(Root) then TDirectory.Delete(Root, True);
  inherited Destroy;
end;

procedure TWorkingCopyFixture.Reupload(const Body, Ext: string);
var
  FileType: TFileType;
  Items: TItemModel;
  OldPath: string;
begin
  OldPath := StoragePath;
  if not SameText(AFile.FileType.Ext, Ext) then
  begin
    FileType := TFileType.Create;
    FileType.Ext := Ext;
    FileType.CreatedDate := UTCNow;
    FileType.CreatedBy := Notebook.Principal.Id;
    Notebook.Manager.Save(FileType);
    Notebook.Manager.Flush;
    AFile.FileType := FileType;
    StoragePath := ChangeFileExt(StoragePath, Ext);
  end;
  Items := TItemModel.Create(Notebook.Manager);
  try
    if not Items.UpdateFile(AFile, Notebook.Principal.Id) then
      raise EInvalidOperation.Create('Fixture metadata update conflicted');
  finally
    Items.Free;
  end;
  Notebook.Storage.WriteBytes(StoragePath, TEncoding.UTF8.GetBytes(Body));
  if OldPath <> StoragePath then Notebook.Storage.DeleteFile(OldPath);
end;

procedure TTestLocalElnFileService.CleanReloadAdvancesCopiedBaselineForNextSave;
var
  Fixture: TWorkingCopyFixture;
  ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.Reupload('replacement bytes', '.md');
    Assert.IsTrue(Fixture.Service.ReloadLocalFile(Fixture.AFile.Id, Fixture.WorkingPath, ErrorText), ErrorText);
    Assert.AreEqual('replacement bytes', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('next edit'));
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.AreEqual('next edit', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.CancelKeepsDraftAndOriginalConflictBaseline;
var
  Fixture: TWorkingCopyFixture;
  ErrorText, Hash: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Hash := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('retained draft'));
    Fixture.Reupload('replacement bytes', '.md');
    Assert.AreEqual(Fixture.WorkingPath, Fixture.Service.PrepareLocalFile(Fixture.AFile.Id));
    Assert.AreEqual('retained draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    Assert.AreEqual(Hash, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
    Assert.AreEqual(Ord(srConflict), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.ExplicitReloadDiscardsDraftOnlyOnSuccess;
var
  Fixture: TWorkingCopyFixture;
  ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('discarded draft'));
    Fixture.Reupload('replacement bytes', '.md');
    Assert.IsTrue(Fixture.Service.ReloadLocalFile(Fixture.AFile.Id, Fixture.WorkingPath, ErrorText), ErrorText);
    Assert.AreEqual('replacement bytes', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.FailedReloadPreservesDraftAndBaseline;
var
  Fixture: TWorkingCopyFixture;
  ErrorText, Hash: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Hash := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('retained draft'));
    Fixture.Reupload('replacement bytes', '.md');
    Fixture.CopyStorage.FailCopy := True;
    Assert.IsFalse(Fixture.Service.ReloadLocalFile(Fixture.AFile.Id, Fixture.WorkingPath, ErrorText));
    Assert.AreEqual('retained draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath),
      'A partial CopyOut failure must not replace the draft');
    Assert.AreEqual(Hash, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.PluginReloadRejectsChangedExtensionWithoutReplacingDraft;
var
  Fixture: TWorkingCopyFixture;
  ErrorText, Hash: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Hash := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('markdown draft'));
    Fixture.Reupload('replacement text', '.txt');
    Assert.IsFalse(Fixture.Service.ReloadLocalFile(Fixture.AFile.Id, Fixture.WorkingPath, ErrorText),
      'A plugin cannot reinterpret a changed file type at its fixed old path');
    Assert.AreEqual('markdown draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    Assert.AreEqual(Hash, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.CleanNotificationRefreshesBytesAndNextSaveBaseline;
var
  Fixture: TWorkingCopyFixture;
  Path, ErrorText: string;
  RefreshResult: TSaveResult;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.Reupload('replacement bytes', '.md');
    RefreshResult := Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, False, Path, ErrorText);
    Assert.AreEqual(Ord(srOk), Ord(RefreshResult), ErrorText);
    Assert.AreEqual('replacement bytes', System.IOUtils.TFile.ReadAllText(Path));
    System.IOUtils.TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes('next edit'));
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Path, ErrorText)), ErrorText);
    Assert.AreEqual('next edit', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.DirtyNotificationKeepsDraftUntilExplicitResolution;
var
  Fixture: TWorkingCopyFixture;
  Path, ErrorText, Hash: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Hash := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('retained draft'));
    Fixture.Reupload('replacement bytes', '.txt');
    Assert.AreEqual(Ord(srConflict), Ord(Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, False, Path, ErrorText)));
    Assert.AreEqual(Fixture.WorkingPath, Path);
    Assert.AreEqual('retained draft', System.IOUtils.TFile.ReadAllText(Path));
    Assert.AreEqual(Hash, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
    Assert.AreEqual(Path, Fixture.Service.PrepareLocalFile(Fixture.AFile.Id));
    Assert.AreEqual(Ord(srConflict), Ord(Fixture.Service.SaveLocalFileForce(Fixture.AFile.Id, Path, ErrorText)),
      'Even force-save must refuse a changed canonical path');
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, True, Path, ErrorText)), ErrorText);
    Assert.AreEqual('.txt', ExtractFileExt(Path));
    Assert.AreEqual('replacement bytes', System.IOUtils.TFile.ReadAllText(Path));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.ExtensionChangingRefreshUpdatesPathAndNextSave;
var
  Fixture: TWorkingCopyFixture;
  Path, ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.Reupload('replacement text', '.txt');
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, False, Path, ErrorText)), ErrorText);
    Assert.AreEqual('.txt', ExtractFileExt(Path));
    Assert.AreEqual(Path, Fixture.Service.PrepareLocalFile(Fixture.AFile.Id));
    Assert.AreEqual('replacement text', System.IOUtils.TFile.ReadAllText(Path));
    System.IOUtils.TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes('text edit'));
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Path, ErrorText)), ErrorText);
    Assert.AreEqual('text edit', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)),
      'The former editor path must not remain an alias for the refreshed copy');
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.FailedExtensionRefreshKeepsOldPathAndBaseline;
var
  Fixture: TWorkingCopyFixture;
  Path, ErrorText, Hash: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Hash := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('retained draft'));
    Fixture.Reupload('replacement text', '.txt');
    Fixture.CopyStorage.FailCopy := True;
    Assert.AreEqual(Ord(srError), Ord(Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, True, Path, ErrorText)));
    Assert.AreEqual(Fixture.WorkingPath, Fixture.Service.PrepareLocalFile(Fixture.AFile.Id));
    Assert.AreEqual('retained draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    Assert.AreEqual(Hash, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.CanonicalEditDuringRefreshStillConflictsOnSave;
var
  Fixture: TWorkingCopyFixture;
  Path, ErrorText: string;
  RefreshResult: TSaveResult;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.Reupload('replacement bytes', '.md');
    Fixture.CopyStorage.FArmed := True;
    RefreshResult := Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, False, Path, ErrorText);
    Assert.AreEqual(Ord(srOk), Ord(RefreshResult), ErrorText);
    Assert.AreEqual('replacement bytes', System.IOUtils.TFile.ReadAllText(Path));
    System.IOUtils.TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes('next edit'));
    Assert.AreEqual(Ord(srConflict), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Path, ErrorText)));
    Assert.AreEqual('external edit', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.RenamedAttachmentRefreshUpdatesPathAndNextSave;
var
  Fixture: TWorkingCopyFixture;
  Path, OldStoragePath, ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    OldStoragePath := Fixture.StoragePath;
    Fixture.AFile.Title := 'renamed attachment';
    Fixture.StoragePath := TPath.Combine(ExtractFileDir(Fixture.StoragePath), Fixture.AFile.FullName);
    Fixture.Reupload('renamed bytes', '.md');
    Fixture.Notebook.Storage.DeleteFile(OldStoragePath);
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, False, Path, ErrorText)), ErrorText);
    Assert.IsTrue(Pos('renamed attachment', ExtractFileName(Path)) > 0);
    Assert.AreEqual('renamed bytes', System.IOUtils.TFile.ReadAllText(Path));
    System.IOUtils.TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes('next edit'));
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Path, ErrorText)), ErrorText);
    Assert.AreEqual('next edit', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.LockedWorkingCopyRefreshPreservesDraftAndBaseline;
var
  Fixture: TWorkingCopyFixture;
  Lock: TFileStream;
  Path, ErrorText, Hash: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Hash := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('retained draft'));
    Fixture.Reupload('replacement bytes', '.md');
    Lock := TFileStream.Create(Fixture.WorkingPath, fmOpenRead or fmShareExclusive);
    try
      Assert.AreEqual(Ord(srError), Ord(Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, True, Path, ErrorText)));
    finally
      Lock.Free;
    end;
    Assert.AreEqual(Fixture.WorkingPath, Fixture.Service.PrepareLocalFile(Fixture.AFile.Id));
    Assert.AreEqual('retained draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    Assert.AreEqual(Hash, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.WorkingEditDuringCanonicalCopyRequiresExplicitResolution;
var
  Fixture: TWorkingCopyFixture;
  Path, ErrorText, Hash: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Hash := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    Fixture.Reupload('replacement bytes', '.md');
    Fixture.CopyStorage.WorkingEditPath := Fixture.WorkingPath;
    Assert.AreEqual(Ord(srConflict), Ord(Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, False, Path, ErrorText)),
      'A clean copy can become a draft while canonical bytes are being staged');
    Assert.AreEqual('external working draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    Assert.AreEqual(Hash, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
    Assert.AreEqual(Fixture.WorkingPath, Fixture.Service.PrepareLocalFile(Fixture.AFile.Id));
    Assert.AreEqual('replacement bytes', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.AtomicExternalSaveCannotReplaceCleanCopyDuringRefreshInstall;
var
  Fixture: TWorkingCopyFixture;
  Context: TRttiContext;
  Field: TRttiField;
  WorkingStorage: INotebookStorage;
  BoundaryStorage: TEditAfterCopyStorage;
  Path, ErrorText: string;
  RefreshResult: TSaveResult;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    // Decorate the existing real working backend, keeping its resolver alive.
    Context := TRttiContext.Create;
    try
      Field := Context.GetType(Fixture.Service.ClassType).GetField('FWorkingStorage');
      Assert.IsNotNull(Field, 'Working storage boundary must be available to the fixture');
      WorkingStorage := Field.GetValue(Fixture.Service).AsInterface as INotebookStorage;
      BoundaryStorage := TEditAfterCopyStorage.Create(WorkingStorage);
      BoundaryStorage.FArmed := False;
      WorkingStorage := BoundaryStorage;
      Field.SetValue(Fixture.Service, System.Rtti.TValue.From<INotebookStorage>(WorkingStorage));
      Fixture.Reupload('replacement bytes', '.md');
      BoundaryStorage.AtomicReplacePath := Fixture.WorkingPath;
      RefreshResult := Fixture.Service.RefreshLocalFile(Fixture.AFile.Id, False, Path, ErrorText);
      Assert.AreEqual(Ord(srOk), Ord(RefreshResult), ErrorText);
      Assert.IsFalse(BoundaryStorage.AtomicReplaceSucceeded,
        'An external atomic save must be denied while the clean baseline is guarded');
      Assert.AreEqual('opened bytes', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath),
        'Clean refresh retains the original path instead of replacing it');
      Assert.AreEqual('replacement bytes', System.IOUtils.TFile.ReadAllText(Path));
      System.IOUtils.TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes('next edit'));
      Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(Fixture.AFile.Id, Path, ErrorText)), ErrorText);
    finally
      Context.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.CanonicalEditAfterCopyIsNotMistakenForOpenBaseline;
var
  Id: TGUID;
  Root, StorageRoot, WorkingRoot, StoragePath, WorkingPath, ErrorMsg: string;
  Notebook: TLocalNotebook;
  Projects: TProjectsModel;
  Items: TItemModel;
  Project: TProject;
  Item: TItem;
  FileType: TFileType;
  AFile: unit_Item.TFile;
  FileId: Int64;
  Storage: INotebookStorage;
  Service: TLocalElnFileService;
begin
  CreateGUID(Id);
  Root := TPath.Combine(TPath.GetTempPath, 'ELN-FileService-' + GUIDToString(Id));
  ForceDirectories(Root);
  try
    StorageRoot := TPath.Combine(Root, 'attachments');
    WorkingRoot := TPath.Combine(Root, 'working');
    Notebook := TLocalNotebook.CreateNew(TPath.Combine(Root, 'notebook.sqlite'),
      StorageRoot, 'Fixture', 'Author', 'fixture-signing-password');
    try
      Projects := TProjectsModel.Create(Notebook.Manager, Notebook.AccessPolicy);
      try
        Projects.AssignUser(Notebook.Principal);
        Project := Projects.AddProject('Fixture project', '', Notebook.Principal);
      finally
        Projects.Free;
      end;
      Items := TItemModel.Create(Notebook.Manager);
      try
        Items.AssignProject(Project.Id, 0);
        Item := Items.AddItem(TItemType.Other, 'Fixture item');
        FileType := TFileType.Create;
        FileType.Ext := '.md';
        FileType.CreatedDate := UTCNow;
        FileType.CreatedBy := Notebook.Principal.Id;
        Notebook.Manager.Save(FileType);
        Notebook.Manager.Flush;
        AFile := Items.AddFile(FileType, 'page', Notebook.Principal.Id, Item);
        FileId := AFile.Id;
        StoragePath := Format('Projects\%s\%s\%s',
          [CleanFileName(Project.FileFolder), CleanFileName(Item.FolderName), AFile.FullName]);
        Notebook.Storage.WriteBytes(StoragePath, TEncoding.UTF8.GetBytes('opened bytes'));
      finally
        Items.Free;
      end;
      Storage := TEditAfterCopyStorage.Create(Notebook.Storage);
      Service := TLocalElnFileService.Create(Notebook.Manager, Notebook.Principal.Id,
        Notebook.AccessPolicy, Storage, StorageRoot, WorkingRoot);
      try
        WorkingPath := Service.PrepareLocalFile(FileId);
        Assert.AreEqual('opened bytes', System.IOUtils.TFile.ReadAllText(WorkingPath));
        System.IOUtils.TFile.WriteAllBytes(WorkingPath, TEncoding.UTF8.GetBytes('editor draft'));
        Assert.AreEqual(WorkingPath, Service.PrepareLocalFile(FileId));
        Assert.AreEqual('editor draft', System.IOUtils.TFile.ReadAllText(WorkingPath),
          'Reselection must not replace the active draft');
        Assert.AreEqual(Ord(srConflict), Ord(Service.SaveLocalFile(FileId, WorkingPath, ErrorMsg)));
        Assert.AreEqual('external edit', TEncoding.UTF8.GetString(Notebook.Storage.ReadBytes(StoragePath)),
          'The canonical version changed after the copy and must not be overwritten');
        Assert.AreEqual(Ord(srOk), Ord(Service.SaveLocalFileForce(FileId, WorkingPath, ErrorMsg)));
        Assert.AreEqual('editor draft', TEncoding.UTF8.GetString(Notebook.Storage.ReadBytes(StoragePath)));
      finally
        Service.Free;
        Storage := nil;
      end;
    finally
      Notebook.Free;
    end;
  finally
    TDirectory.Delete(Root, True);
  end;
end;

procedure RejectFileMetadata(Notebook: TLocalNotebook);
var
  Statement: IDBStatement;
begin
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand('CREATE TRIGGER RejectFileSave BEFORE UPDATE ON Files ' +
    'BEGIN SELECT RAISE(ABORT, ''synthetic metadata failure''); END');
  Statement.Execute;
end;

procedure TTestLocalElnFileService.CanonicalWriteAfterBackupIsRefusedWithoutLosingDraft;
var
  Fixture: TWorkingCopyFixture;
  ErrorText, Baseline: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Baseline := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    System.IOUtils.TFile.WriteAllText(Fixture.WorkingPath, 'editor draft', TEncoding.UTF8);
    Fixture.CopyStorage.FArmed := True;
    Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.AreEqual('opened bytes', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Assert.AreEqual('editor draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    Assert.AreEqual(Baseline, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.AtomicCanonicalReplaceAfterBackupIsDenied;
var
  Fixture: TWorkingCopyFixture;
  ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.CopyStorage.FAfterBackupReplacePath := TPath.Combine(Fixture.StorageRoot, Fixture.StoragePath);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('saved draft'));
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.IsFalse(Fixture.CopyStorage.AtomicReplaceSucceeded, 'Canonical backup must remain guarded');
    Assert.AreEqual('saved draft', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.AtomicCanonicalReplaceAfterInstallIsDenied;
var
  Fixture: TWorkingCopyFixture;
  ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.CopyStorage.FAfterInstallReplacePath := TPath.Combine(Fixture.StorageRoot, Fixture.StoragePath);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('saved draft'));
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.IsFalse(Fixture.CopyStorage.AtomicReplaceSucceeded, 'Installed bytes must stay guarded through metadata commit');
    Assert.AreEqual('saved draft', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.MetadataFailureRestoresBytesAndKeepsDraft;
var
  Fixture: TWorkingCopyFixture;
  ErrorText, Baseline: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Baseline := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    Fixture.AFile.Description := 'unrelated host draft';
    RejectFileMetadata(Fixture.Notebook);
    System.IOUtils.TFile.WriteAllText(Fixture.WorkingPath, 'editor draft', TEncoding.UTF8);
    Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.AreEqual('opened bytes', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Assert.AreEqual('editor draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
    Assert.AreEqual(Baseline, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
    Assert.AreEqual('unrelated host draft', Fixture.AFile.Description);
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.FailedCompensationRetainsDurableBackup;
var
  Fixture: TWorkingCopyFixture;
  ErrorText: string;
  Backups: TArray<string>;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    RejectFileMetadata(Fixture.Notebook);
    Fixture.CopyStorage.FFailRollback := True;
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('editor draft'));
    Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Backups := TDirectory.GetFiles(TPath.Combine(Fixture.WorkingRoot, 'backups'), '*.bak');
    Assert.AreEqual(1, Length(Backups));
    Assert.AreEqual('opened bytes', System.IOUtils.TFile.ReadAllText(Backups[0]));
    Assert.IsTrue(Pos(Backups[0], ErrorText) > 0, 'Error must identify retained original bytes');
    Assert.AreEqual('editor draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.ForceSaveMissingFileRollsBackToAbsence;
var
  Fixture: TWorkingCopyFixture;
  ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.Notebook.Storage.DeleteFile(Fixture.StoragePath);
    RejectFileMetadata(Fixture.Notebook);
    System.IOUtils.TFile.WriteAllText(Fixture.WorkingPath, 'editor draft', TEncoding.UTF8);
    Assert.AreEqual(Ord(srConflict), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFileForce(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.IsFalse(Fixture.Notebook.Storage.Exists(Fixture.StoragePath));
    Assert.AreEqual('editor draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.MissingCanonicalCreatedBeforeInstallIsNotOverwritten;
var
  Fixture: TWorkingCopyFixture;
  Update: INotebookFileUpdate;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.Notebook.Storage.DeleteFile(Fixture.StoragePath);
    Update := (Fixture.Notebook.Storage as INotebookStorageUpdates).BeginFileUpdate(Fixture.StoragePath);
    Assert.IsFalse(Update.Exists);
    // A direct external creation can win the absent-name race. Do not use the
    // backend's atomic replace, whose parent write-open is correctly denied.
    System.IOUtils.TFile.WriteAllBytes(TPath.Combine(Fixture.StorageRoot, Fixture.StoragePath),
      TEncoding.UTF8.GetBytes('intervening creation'));
    Assert.WillRaise(procedure begin Update.InstallFrom(Fixture.WorkingPath); end);
    Update.Rollback;
    Update := nil;
    Assert.AreEqual('intervening creation',
      TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Update := nil;
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.GuardedBinaryInstallAndRollbackPreserveWholeFiles;
var
  Fixture: TWorkingCopyFixture;
  Update: INotebookFileUpdate;
  Original, Draft, Actual: TBytes;
  Stream: TStream;
  I: Integer;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Original := TBytes.Create(0, 255, 128, 0, 13, 10);
    SetLength(Draft, 131073);
    for I := 0 to High(Draft) do Draft[I] := Byte(I mod 256);
    Fixture.Notebook.Storage.WriteBytes(Fixture.StoragePath, Original);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, Draft);
    Update := (Fixture.Notebook.Storage as INotebookStorageUpdates).BeginFileUpdate(Fixture.StoragePath);
    Update.InstallFrom(Fixture.WorkingPath);
    Stream := Update.OpenRead;
    try
      SetLength(Actual, Stream.Size);
      Stream.ReadBuffer(Actual[0], Length(Actual));
    finally
      Stream.Free;
    end;
    Assert.AreEqual(Length(Draft), Length(Actual));
    Assert.IsTrue(CompareMem(@Draft[0], @Actual[0], Length(Draft)));
    Assert.WillRaise(procedure begin
      Fixture.Notebook.Storage.WriteBytes(Fixture.StoragePath, TBytes.Create(42));
    end);
    Update.Rollback;
    // Completion releases OS ownership even if Delphi retains an interface
    // expression temporary until this test routine exits.
    Actual := Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath);
    Assert.AreEqual(Length(Original), Length(Actual));
    Assert.IsTrue(CompareMem(@Original[0], @Actual[0], Length(Original)));
    Update := nil;
  finally
    Update := nil;
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.LockedCanonicalSavePreservesDraft;
var
  Fixture: TWorkingCopyFixture;
  Lock: TFileStream;
  ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    System.IOUtils.TFile.WriteAllText(Fixture.WorkingPath, 'editor draft', TEncoding.UTF8);
    Lock := TFileStream.Create(TPath.Combine(Fixture.StorageRoot, Fixture.StoragePath),
      fmOpenRead or fmShareExclusive);
    try
      Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFile(
        Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
      Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFileForce(
        Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    finally
      Lock.Free;
    end;
    Assert.AreEqual('opened bytes', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Assert.AreEqual('editor draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.DirectCanonicalWriteAfterBackupIsDenied;
var
  Fixture: TWorkingCopyFixture;
  ErrorText: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.CopyStorage.FAfterBackupWritePath := TPath.Combine(Fixture.StorageRoot, Fixture.StoragePath);
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('saved draft'));
    Assert.AreEqual(Ord(srOk), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.IsFalse(Fixture.CopyStorage.FDirectWriteSucceeded, 'Direct writes must be denied while comparing the backup');
    Assert.AreEqual('saved draft', TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.GuardCommitReleasesHandlesBeforeInterfaceDestruction;
var
  Fixture: TWorkingCopyFixture;
  Update: INotebookFileUpdate;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('committed bytes'));
    Update := (Fixture.Notebook.Storage as INotebookStorageUpdates).BeginFileUpdate(Fixture.StoragePath);
    Update.InstallFrom(Fixture.WorkingPath);
    Update.Commit;
    Assert.AreEqual('committed bytes',
      TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Fixture.Notebook.Storage.WriteBytes(Fixture.StoragePath, TEncoding.UTF8.GetBytes('later external edit'));
    Assert.AreEqual('later external edit',
      TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Update := nil;
    Assert.AreEqual('later external edit',
      TEncoding.UTF8.GetString(Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
  finally
    Update := nil;
    Fixture.Free;
  end;
end;

procedure SetTestJunction(const Path, Target: string);
type
  TMountPointBuffer = packed record
    Tag: DWORD;
    DataLength, Reserved: Word;
    SubstituteOffset, SubstituteLength, PrintOffset, PrintLength: Word;
    PathBuffer: array[0..1023] of WideChar;
  end;
var
  Buffer: TMountPointBuffer;
  Substitute, Names: string;
  Handle: THandle;
  Returned: DWORD;
begin
  Handle := CreateFile(PChar(Path), GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT, 0);
  if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    Substitute := '\??\' + Target;
    Names := Substitute + #0 + Target + #0;
    Assert.IsTrue(Length(Names) <= Length(Buffer.PathBuffer));
    FillChar(Buffer, SizeOf(Buffer), 0);
    Buffer.Tag := $A0000003; // IO_REPARSE_TAG_MOUNT_POINT
    Buffer.SubstituteLength := Length(Substitute) * SizeOf(WideChar);
    Buffer.PrintOffset := Buffer.SubstituteLength + SizeOf(WideChar);
    Buffer.PrintLength := Length(Target) * SizeOf(WideChar);
    Buffer.DataLength := 8 + Length(Names) * SizeOf(WideChar);
    Move(PChar(Names)^, Buffer.PathBuffer[0], Length(Names) * SizeOf(WideChar));
    if not DeviceIoControl(Handle, FSCTL_SET_REPARSE_POINT, @Buffer,
      8 + Buffer.DataLength, nil, 0, Returned, nil) then RaiseLastOSError;
  finally
    CloseHandle(Handle);
  end;
end;

procedure CreateTestJunction(const Path, Target: string);
begin
  if not CreateDirectory(PChar(Path), nil) then RaiseLastOSError;
  SetTestJunction(Path, Target);
end;

procedure TTestLocalElnFileService.MissingFileGuardPreventsParentRenameAndJunctionSwap;
var
  Fixture: TWorkingCopyFixture;
  Update: INotebookFileUpdate;
  ParentPath, MovedPath, RedirectPath, OutsidePath: string;
  ParentMoved, JunctionMoved: Boolean;
begin
  Fixture := TWorkingCopyFixture.Create;
  ParentMoved := False;
  JunctionMoved := False;
  try
    Fixture.Notebook.Storage.DeleteFile(Fixture.StoragePath);
    ParentPath := ExtractFileDir(TPath.Combine(Fixture.StorageRoot, Fixture.StoragePath));
    MovedPath := ParentPath + '.moved';
    RedirectPath := TPath.Combine(Fixture.Root, 'redirect');
    OutsidePath := TPath.Combine(Fixture.Root, 'outside');
    ForceDirectories(OutsidePath);
    CreateTestJunction(RedirectPath, OutsidePath);
    Update := (Fixture.Notebook.Storage as INotebookStorageUpdates).BeginFileUpdate(Fixture.StoragePath);
    ParentMoved := MoveFileEx(PChar(ParentPath), PChar(MovedPath), MOVEFILE_WRITE_THROUGH);
    if ParentMoved then
      JunctionMoved := MoveFileEx(PChar(RedirectPath), PChar(ParentPath), MOVEFILE_WRITE_THROUGH);
    Assert.IsFalse(ParentMoved, 'Missing-file update must pin its parent against renaming');
    Assert.IsFalse(JunctionMoved, 'A junction must not replace the guarded parent');
    Assert.IsFalse(MoveFileEx(PChar(Fixture.StorageRoot),
      PChar(Fixture.StorageRoot + '.moved'), MOVEFILE_WRITE_THROUGH),
      'The storage ancestor must also remain pinned');
    Update.InstallFrom(Fixture.WorkingPath);
    Update.Commit;
    Assert.AreEqual('opened bytes', TEncoding.UTF8.GetString(
      Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Assert.AreEqual(0, Length(TDirectory.GetFiles(OutsidePath)),
      'No staged or canonical bytes may be written through the redirect');
  finally
    if Update <> nil then Update.Rollback;
    Update := nil;
    if JunctionMoved then Winapi.Windows.RemoveDirectory(PChar(ParentPath))
    else if RedirectPath <> '' then Winapi.Windows.RemoveDirectory(PChar(RedirectPath));
    if ParentMoved then MoveFileEx(PChar(MovedPath), PChar(ParentPath), MOVEFILE_WRITE_THROUGH);
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.CommitAcknowledgementFailureRetainsCommittedBytesAndBackup;
var
  Fixture: TWorkingCopyFixture;
  Context: TRttiContext;
  Field: TRttiField;
  Connection: IDBConnection;
  Statement: IDBStatement;
  Rows: IDBResultSet;
  ErrorText, Baseline: string;
  Backups: TArray<string>;
  OriginalVersion: Integer;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Baseline := Fixture.Service.GetOpenHash(Fixture.AFile.Id);
    OriginalVersion := Fixture.AFile.Version;
    Connection := TCommitFailureConnection.Create(Fixture.Notebook.Connection);
    Context := TRttiContext.Create;
    try
      Field := Context.GetType(Fixture.Service.ClassType).GetField('FConnection');
      Assert.IsNotNull(Field);
      Field.SetValue(Fixture.Service, System.Rtti.TValue.From<IDBConnection>(Connection));
    finally
      Context.Free;
    end;
    System.IOUtils.TFile.WriteAllBytes(Fixture.WorkingPath, TEncoding.UTF8.GetBytes('committed draft'));
    Assert.AreEqual(Ord(srError), Ord(Fixture.Service.SaveLocalFile(
      Fixture.AFile.Id, Fixture.WorkingPath, ErrorText)), ErrorText);
    Assert.AreEqual('committed draft', TEncoding.UTF8.GetString(
      Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Statement := Fixture.Notebook.Connection.CreateStatement;
    Statement.SetSQLCommand('SELECT Version, Hash FROM Files WHERE Id = ' + IntToStr(Fixture.AFile.Id));
    Rows := Statement.ExecuteQuery;
    Assert.IsTrue(Rows.Next);
    Assert.AreEqual(OriginalVersion + 1, Integer(Rows.GetFieldValue(0)));
    Assert.IsFalse(SameText(Baseline, VarToStr(Rows.GetFieldValue(1))),
      'The real database commit must have persisted the new file hash');
    Rows := nil;
    Statement := nil;
    Backups := TDirectory.GetFiles(TPath.Combine(Fixture.WorkingRoot, 'backups'), '*.bak');
    Assert.AreEqual(1, Length(Backups));
    Assert.AreEqual('opened bytes', System.IOUtils.TFile.ReadAllText(Backups[0]));
    Assert.IsTrue(Pos(Backups[0], ErrorText) > 0);
    Assert.AreEqual(Baseline, Fixture.Service.GetOpenHash(Fixture.AFile.Id));
    Assert.AreEqual('committed draft', System.IOUtils.TFile.ReadAllText(Fixture.WorkingPath));
  finally
    Rows := nil;
    Statement := nil;
    Fixture.Free;
  end;
end;

procedure TTestLocalElnFileService.MissingFileGuardPreventsInPlaceJunction;
var
  Fixture: TWorkingCopyFixture;
  Update: INotebookFileUpdate;
  ParentPath, OutsidePath, ProbePath: string;
begin
  Fixture := TWorkingCopyFixture.Create;
  try
    Fixture.Notebook.Storage.DeleteFile(Fixture.StoragePath);
    ParentPath := ExtractFileDir(TPath.Combine(Fixture.StorageRoot, Fixture.StoragePath));
    OutsidePath := TPath.Combine(Fixture.Root, 'outside');
    ProbePath := TPath.Combine(Fixture.Root, 'probe');
    ForceDirectories(OutsidePath);
    CreateTestJunction(ProbePath, OutsidePath);
    Assert.IsTrue(Winapi.Windows.RemoveDirectory(PChar(ProbePath)));
    Update := (Fixture.Notebook.Storage as INotebookStorageUpdates).BeginFileUpdate(Fixture.StoragePath);
    Assert.WillRaise(procedure begin SetTestJunction(ParentPath, OutsidePath); end);
    Update.InstallFrom(Fixture.WorkingPath);
    Update.Commit;
    Assert.AreEqual('opened bytes', TEncoding.UTF8.GetString(
      Fixture.Notebook.Storage.ReadBytes(Fixture.StoragePath)));
    Assert.AreEqual(0, Length(TDirectory.GetFiles(OutsidePath)));
  finally
    if Update <> nil then Update.Rollback;
    Update := nil;
    if (ParentPath <> '') and
      ((GetFileAttributes(PChar(ParentPath)) and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
    begin
      Winapi.Windows.RemoveDirectory(PChar(ParentPath));
      CreateDirectory(PChar(ParentPath), nil);
    end;
    if ProbePath <> '' then Winapi.Windows.RemoveDirectory(PChar(ProbePath));
    Fixture.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLocalElnFileService);

end.
