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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Rtti,
  Winapi.Windows,
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
  // Simulates another local application changing the canonical file after
  // CopyOut has delivered the editor's original bytes, before open completes.
  TEditAfterCopyStorage = class(TInterfacedObject, INotebookStorage, IFileRelocator)
  private
    FStorage: INotebookStorage;
    FFailCopy: Boolean;
    FArmed: Boolean;
    FWorkingEditPath: string;
    FAtomicReplacePath: string;
    FAtomicReplaceSucceeded: Boolean;
  public
    constructor Create(const Storage: INotebookStorage);
    function ReadBytes(const RelativePath: string): TBytes;
    procedure WriteBytes(const RelativePath: string; const Data: TBytes);
    procedure CopyIn(const SourcePath, RelativePath: string);
    procedure CopyOut(const RelativePath, TargetPath: string);
    procedure MoveFile(const OldPath, NewPath: string);
    procedure DeleteFile(const RelativePath: string);
    function Exists(const RelativePath: string): Boolean;
    property FailCopy: Boolean read FFailCopy write FFailCopy;
    property WorkingEditPath: string read FWorkingEditPath write FWorkingEditPath;
    property AtomicReplacePath: string read FAtomicReplacePath write FAtomicReplacePath;
    property AtomicReplaceSucceeded: Boolean read FAtomicReplaceSucceeded;
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
    // Exercise a real same-directory atomic save at the working-install boundary.
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
end;

procedure TEditAfterCopyStorage.CopyOut(const RelativePath, TargetPath: string);
begin
  FStorage.CopyOut(RelativePath, TargetPath);
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
    // This is a test-only boundary injection, not a production testing API.
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
  FileId: Integer;
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

initialization
  TDUnitX.RegisterTestFixture(TTestLocalElnFileService);

end.
