unit test_ItemDurability;

interface

uses
  System.SysUtils, DUnitX.TestFramework,
  unit_LocalNotebook, unit_ItemModel, unit_ProjectModel, unit_Item,
  unit_Project, unit_NotebookStorage;

type
  [TestFixture]
  TItemDurabilityTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FItems: TItemModel;
    FProjects: TProjectsModel;
    FSource, FDestination: TProject;
    FRootItem, FChild, FDraft: TItem;
    FRelocator: IFileRelocator;
    function NewItem(const Title: string; ParentId: Integer = 0): TItem;
    function AddAttachment(Item: TItem; const Title: string): string;
    procedure SQL(const Command: string);
    procedure CheckUnchangedAfterFlush;
    procedure RenameRejected(const Trigger: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CreatedByUsesSuppliedActor;
    [Test] procedure RenameCommitsMetadataAndBytes;
    [Test] procedure RenameUpdateFailureCompensates;
    [Test] procedure RenameAuditFailureCompensates;
    [Test] procedure RenameStaleVersionRefuses;
    [Test] procedure RenamePartialMovesCompensate;
    [Test] procedure MoveProcLateFailureRollsBackWholeTree;
    [Test] procedure MoveProcStaleDescendantRefuses;
    [Test] procedure MoveProcPartialMovesCompensate;
    [Test] procedure FolderMoveIncludesRecycledBytes;
    [Test] procedure FolderMoveLateFailureRollsBackWholeTree;
    [Test] procedure RenameRefusesOuterTransaction;
    [Test] procedure SignedRecycledItemBlocksFolderMove;
    [Test] procedure FolderPartialMovesCompensate;
    [Test] procedure RenameConflictAfterMoveCompensates;
    [Test] procedure FolderStaleDescendantRefuses;
    [Test] procedure MoveProcConflictAfterMoveRollsBackTree;
    [Test] procedure RootListIncludesLegacyAndCanonicalItems;
    [Test] procedure LegacyRootAssignmentCreatesCanonicalItem;
    [Test] procedure MoveProcToLegacyRootPersistsCanonicalRoot;
    [Test] procedure FolderRootOperationsNormalizeLegacySentinel;
  end;

implementation

uses
  System.IOUtils, System.Generics.Collections,
  Aurelius.Drivers.Interfaces, Aurelius.Engine.ObjectManager,
  unit_FileRelocator, unit_FileType, unit_ItemTypes, unit_ConflictHandler,
  unit_Signature;

type
  TFailSecondMove = class(TInterfacedObject, IFileRelocator)
  private
    FInner: IFileRelocator;
    FCalls: Integer;
  public
    constructor Create(const Inner: IFileRelocator);
    procedure MoveFile(const OldPath, NewPath: string);
  end;

  TBeforeMove = class(TInterfacedObject, IFileRelocator)
  private
    FInner: IFileRelocator;
    FBefore: TProc;
  public
    constructor Create(const Inner: IFileRelocator; const BeforeMove: TProc);
    procedure MoveFile(const OldPath, NewPath: string);
  end;

constructor TBeforeMove.Create(const Inner: IFileRelocator; const BeforeMove: TProc);
begin
  inherited Create;
  FInner := Inner;
  FBefore := BeforeMove;
end;

procedure TBeforeMove.MoveFile(const OldPath, NewPath: string);
var
  Before: TProc;
begin
  Before := FBefore;
  FBefore := nil;
  if Assigned(Before) then
    Before();
  FInner.MoveFile(OldPath, NewPath);
end;

constructor TFailSecondMove.Create(const Inner: IFileRelocator);
begin
  inherited Create;
  FInner := Inner;
end;

procedure TFailSecondMove.MoveFile(const OldPath, NewPath: string);
begin
  Inc(FCalls);
  if FCalls = 2 then
    raise EInOutError.Create('Injected second attachment failure');
  FInner.MoveFile(OldPath, NewPath);
end;

procedure TItemDurabilityTests.Setup;
var
  Id: TGUID;
  ProjectId: Integer;
begin
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-ItemDurability-' + GUIDToString(Id));
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'attachments'), 'Synthetic', 'Scientist', 'Synthetic-Only-Password!');
  FItems := TItemModel.Create(FNotebook.Manager);
  FProjects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  FProjects.AssignUser(FNotebook.Principal);
  FSource := FProjects.AddProject('Source', '', FNotebook.Principal);
  FDestination := FProjects.AddProject('Destination', '', FNotebook.Principal);
  ProjectId := FSource.Id;
  FNotebook.Manager.Evict(FSource);
  FSource.Free;
  FSource := FNotebook.Manager.Find<TProject>(ProjectId);
  ProjectId := FDestination.Id;
  FNotebook.Manager.Evict(FDestination);
  FDestination.Free;
  FDestination := FNotebook.Manager.Find<TProject>(ProjectId);
  FItems.AssignProject(FSource.Id, 0);
  FRootItem := NewItem('Original');
  FChild := NewItem('Child', FRootItem.Id);
  FDraft := NewItem('Unrelated');
  FRelocator := TNotebookFileRelocator.Create(FNotebook.Storage);
end;

procedure TItemDurabilityTests.TearDown;
begin
  TConflictHandler.OnConflict := nil;
  FRelocator := nil;
  FProjects.Free;
  FItems.Free;
  FNotebook.Free;
  if DirectoryExists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TItemDurabilityTests.NewItem(const Title: string; ParentId: Integer): TItem;
var
  Created: TItem;
  Id: Integer;
begin
  Created := FItems.AddItem(TItemType.Specimen, Title, TItemLevel.Proc,
    ParentId, '', nil, nil, FNotebook.Principal.Id);
  Id := Created.Id;
  Created.Free;
  Result := FNotebook.Manager.Find<TItem>(Id);
end;

function TItemDurabilityTests.AddAttachment(Item: TItem; const Title: string): string;
var
  FileType: TFileType;
  Attachment: unit_Item.TFile;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.bin';
  FileType.Description := 'Synthetic binary';
  FileType.CreatedDate := Now;
  FNotebook.Manager.Save(FileType);
  FNotebook.Manager.Flush;
  Attachment := FItems.AddFile(FileType, Title, FNotebook.Principal.Id, Item);
  Result := Copy(BuildItemFileRemotePath(FSource.FileFolder, Item.FolderName,
    Attachment.FullName), 7, MaxInt);
  FNotebook.Storage.WriteBytes(Result, TBytes.Create(0, 255, 42));
end;

procedure TItemDurabilityTests.SQL(const Command: string);
var
  Statement: IDBStatement;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand(Command);
  Statement.Execute;
end;

procedure TItemDurabilityTests.CheckUnchangedAfterFlush;
var
  Fresh: TObjectManager;
begin
  Assert.AreEqual('pending draft', FDraft.Description, 'Unrelated draft must remain in memory');
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual('', Fresh.Find<TItem>(FDraft.Id).Description, 'Operation must not flush draft');
  finally
    Fresh.Free;
  end;
  FNotebook.Manager.Flush;
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(FSource.Id, Fresh.Find<TItem>(FRootItem.Id).ProjectID);
    Assert.AreEqual(FSource.Id, Fresh.Find<TItem>(FChild.Id).ProjectID);
    Assert.AreEqual('Original', Fresh.Find<TItem>(FRootItem.Id).Title);
    Assert.AreEqual('pending draft', Fresh.Find<TItem>(FDraft.Id).Description);
  finally
    Fresh.Free;
  end;
end;

procedure TItemDurabilityTests.CreatedByUsesSuppliedActor;
var
  Fresh: TObjectManager;
  Recent: TItems;
begin
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.IsTrue(Fresh.Find<TItem>(FRootItem.Id).CreatedBy.HasValue);
    Assert.AreEqual(FNotebook.Principal.Id, Fresh.Find<TItem>(FRootItem.Id).CreatedBy.Value);
  finally
    Fresh.Free;
  end;
  Recent := FItems.GetRecentItems(FNotebook.Principal.Id);
  try
    Assert.IsTrue(Recent.Contains(FRootItem));
  finally
    Recent.Free;
  end;
end;

procedure TItemDurabilityTests.RenameCommitsMetadataAndBytes;
var
  OldPath, NewPath: string;
  Fresh: TObjectManager;
begin
  OldPath := AddAttachment(FRootItem, 'data');
  NewPath := OldPath.Replace(FRootItem.FolderName, TItem.MakeFolderName(FRootItem.Id, 'Renamed'));
  FDraft.Description := 'pending draft';
  FRootItem.Title := 'Renamed';
  Assert.IsTrue(FItems.UpdateItemDurable(FRootItem, FNotebook.Principal.Id, FRelocator));
  Assert.IsFalse(FNotebook.Storage.Exists(OldPath));
  Assert.AreEqual<NativeInt>(3, Length(FNotebook.Storage.ReadBytes(NewPath)));
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual('Renamed', Fresh.Find<TItem>(FRootItem.Id).Title);
    Assert.AreEqual('', Fresh.Find<TItem>(FDraft.Id).Description);
  finally
    Fresh.Free;
  end;
  Assert.AreEqual('pending draft', FDraft.Description);
end;

procedure TItemDurabilityTests.RenameRejected(const Trigger: string);
var
  OldPath, NewPath: string;
begin
  OldPath := AddAttachment(FRootItem, 'data');
  NewPath := OldPath.Replace(FRootItem.FolderName, TItem.MakeFolderName(FRootItem.Id, 'Rejected'));
  SQL(Trigger);
  FDraft.Description := 'pending draft';
  FRootItem.Title := 'Rejected';
  Assert.WillRaise(procedure begin
    FItems.UpdateItemDurable(FRootItem, FNotebook.Principal.Id, FRelocator);
  end);
  SQL('DROP TRIGGER RejectWrite');
  Assert.AreEqual('Original', FRootItem.Title);
  Assert.IsTrue(FNotebook.Storage.Exists(OldPath));
  Assert.IsFalse(FNotebook.Storage.Exists(NewPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.RenameUpdateFailureCompensates;
begin
  RenameRejected('CREATE TRIGGER RejectWrite BEFORE UPDATE ON Items WHEN NEW.Id = ' +
    IntToStr(FRootItem.Id) + ' BEGIN SELECT RAISE(ABORT, ''injected update failure''); END');
end;

procedure TItemDurabilityTests.RenameAuditFailureCompensates;
begin
  RenameRejected('CREATE TRIGGER RejectWrite BEFORE INSERT ON AuditLog BEGIN ' +
    'SELECT RAISE(ABORT, ''injected audit failure''); END');
end;

procedure TItemDurabilityTests.RenameStaleVersionRefuses;
var
  OldPath: string;
begin
  OldPath := AddAttachment(FRootItem, 'data');
  SQL('UPDATE Items SET Version = Version + 1 WHERE Id = ' + IntToStr(FRootItem.Id));
  FDraft.Description := 'pending draft';
  FRootItem.Title := 'Rejected';
  Assert.IsFalse(FItems.UpdateItemDurable(FRootItem, FNotebook.Principal.Id, FRelocator));
  Assert.IsTrue(FNotebook.Storage.Exists(OldPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.RenamePartialMovesCompensate;
var
  FirstPath, SecondPath: string;
begin
  FirstPath := AddAttachment(FRootItem, 'first');
  SecondPath := AddAttachment(FRootItem, 'second');
  FDraft.Description := 'pending draft';
  FRootItem.Title := 'Rejected';
  FRelocator := TFailSecondMove.Create(FRelocator);
  Assert.WillRaise(procedure begin
    FItems.UpdateItemDurable(FRootItem, FNotebook.Principal.Id, FRelocator);
  end);
  Assert.IsTrue(FNotebook.Storage.Exists(FirstPath));
  Assert.IsTrue(FNotebook.Storage.Exists(SecondPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.MoveProcLateFailureRollsBackWholeTree;
begin
  SQL('CREATE TRIGGER RejectWrite BEFORE UPDATE ON Items WHEN NEW.Id = ' +
    IntToStr(FChild.Id) + ' BEGIN SELECT RAISE(ABORT, ''injected child failure''); END');
  FDraft.Description := 'pending draft';
  Assert.WillRaise(procedure begin
    FItems.MoveProc(FRootItem, FDestination.Id, 0, FNotebook.Principal.Id, FRelocator);
  end);
  SQL('DROP TRIGGER RejectWrite');
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.MoveProcStaleDescendantRefuses;
begin
  SQL('UPDATE Items SET Version = Version + 1 WHERE Id = ' + IntToStr(FChild.Id));
  FDraft.Description := 'pending draft';
  TConflictHandler.OnConflict := function(const Msg: string): TConflictResolution begin Result := crReload; end;
  Assert.IsFalse(FItems.MoveProc(FRootItem, FDestination.Id, 0, FNotebook.Principal.Id, FRelocator));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.MoveProcPartialMovesCompensate;
var
  FirstPath, SecondPath: string;
begin
  FirstPath := AddAttachment(FRootItem, 'first');
  SecondPath := AddAttachment(FChild, 'second');
  FDraft.Description := 'pending draft';
  FRelocator := TFailSecondMove.Create(FRelocator);
  Assert.WillRaise(procedure begin
    FItems.MoveProc(FRootItem, FDestination.Id, 0, FNotebook.Principal.Id, FRelocator);
  end);
  Assert.IsTrue(FNotebook.Storage.Exists(FirstPath));
  Assert.IsTrue(FNotebook.Storage.Exists(SecondPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.FolderMoveIncludesRecycledBytes;
var
  Folder, Nested: TFolder;
  OldPath, NewPath: string;
  Fresh: TObjectManager;
begin
  FProjects.AddFolder('Folder', '', FSource.Id, 0);
  Folder := FSource.Folders.Last;
  FProjects.AddFolder('Nested', '', FSource.Id, Folder.Id);
  Nested := FSource.Folders.Last;
  FRootItem.FolderID := Folder.Id;
  FChild.FolderID := Nested.Id;
  FChild.IsDeleted := True;
  FNotebook.Manager.Flush;
  OldPath := AddAttachment(FChild, 'recycled');
  NewPath := OldPath.Replace(FSource.FileFolder, FDestination.FileFolder);
  FDraft.Description := 'pending draft';
  Assert.IsTrue(FProjects.MoveFolder(Folder, FSource.Id, FDestination.Id, 0,
    FNotebook.Principal.Id, FRelocator));
  Assert.IsFalse(FNotebook.Storage.Exists(OldPath));
  Assert.AreEqual<NativeInt>(3, Length(FNotebook.Storage.ReadBytes(NewPath)));
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(FDestination.Id, Fresh.Find<TItem>(FChild.Id).ProjectID);
    Assert.AreEqual(Nested.Id, Fresh.Find<TItem>(FChild.Id).FolderID);
    Assert.IsTrue(Fresh.Find<TItem>(FChild.Id).IsDeleted);
    Assert.AreEqual('', Fresh.Find<TItem>(FDraft.Id).Description);
  finally
    TConflictHandler.FreeOperationManager(Fresh);
  end;
  Assert.AreEqual('pending draft', FDraft.Description);
  Assert.IsNull(FSource.GetFolder(Folder.Id));
  Assert.IsNotNull(FDestination.GetFolder(Folder.Id));
  Assert.IsNotNull(FDestination.GetFolder(Nested.Id));
  FNotebook.Manager.Flush;
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(FDestination.Id, Fresh.Find<TItem>(FChild.Id).ProjectID);
    Assert.IsNotNull(Fresh.Find<TProject>(FDestination.Id).GetFolder(Nested.Id));
  finally
    TConflictHandler.FreeOperationManager(Fresh);
  end;
end;

procedure TItemDurabilityTests.FolderMoveLateFailureRollsBackWholeTree;
var
  Folder: TFolder;
begin
  FProjects.AddFolder('Folder', '', FSource.Id, 0);
  Folder := FSource.Folders.Last;
  FRootItem.FolderID := Folder.Id;
  FChild.FolderID := Folder.Id;
  FNotebook.Manager.Flush;
  SQL('CREATE TRIGGER RejectWrite BEFORE INSERT ON AuditLog BEGIN ' +
    'SELECT RAISE(ABORT, ''injected audit failure''); END');
  FDraft.Description := 'pending draft';
  Assert.WillRaise(procedure begin
    FProjects.MoveFolder(Folder, FSource.Id, FDestination.Id, 0,
      FNotebook.Principal.Id, FRelocator);
  end);
  SQL('DROP TRIGGER RejectWrite');
  CheckUnchangedAfterFlush;
  Assert.AreEqual(0, Folder.ParentFolderID);
end;

procedure TItemDurabilityTests.RenameRefusesOuterTransaction;
var
  Transaction: IDBTransaction;
  OldPath: string;
begin
  OldPath := AddAttachment(FRootItem, 'data');
  FDraft.Description := 'pending draft';
  Transaction := FNotebook.Connection.BeginTransaction;
  try
    FRootItem.Title := 'Rejected';
    Assert.WillRaise(procedure begin
      FItems.UpdateItemDurable(FRootItem, FNotebook.Principal.Id, FRelocator);
    end);
  finally
    Transaction.Rollback;
  end;
  Assert.IsTrue(FNotebook.Storage.Exists(OldPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.SignedRecycledItemBlocksFolderMove;
var
  Folder: TFolder;
  Signature: TSignature;
begin
  FProjects.AddFolder('Folder', '', FSource.Id, 0);
  Folder := FSource.Folders.Last;
  FRootItem.FolderID := Folder.Id;
  FChild.FolderID := Folder.Id;
  FChild.IsDeleted := True;
  Signature := TSignature.Create;
  Signature.ItemId := FChild.Id;
  Signature.UserId := FNotebook.Principal.Id;
  Signature.UserName := 'Synthetic Scientist';
  Signature.SignedDate := Now;
  Signature.Meaning := 'Reviewed';
  Signature.ContentHash := StringOfChar('0', 64);
  FNotebook.Manager.Save(Signature);
  FNotebook.Manager.Flush;
  FDraft.Description := 'pending draft';
  Assert.IsFalse(FProjects.MoveFolder(Folder, FSource.Id, FDestination.Id, 0,
    FNotebook.Principal.Id, FRelocator));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.FolderPartialMovesCompensate;
var
  Folder: TFolder;
  FirstPath, SecondPath: string;
begin
  FProjects.AddFolder('Folder', '', FSource.Id, 0);
  Folder := FSource.Folders.Last;
  FRootItem.FolderID := Folder.Id;
  FChild.FolderID := Folder.Id;
  FNotebook.Manager.Flush;
  FirstPath := AddAttachment(FRootItem, 'first');
  SecondPath := AddAttachment(FChild, 'second');
  FDraft.Description := 'pending draft';
  FRelocator := TFailSecondMove.Create(FRelocator);
  Assert.WillRaise(procedure begin
    FProjects.MoveFolder(Folder, FSource.Id, FDestination.Id, 0,
      FNotebook.Principal.Id, FRelocator);
  end);
  Assert.IsTrue(FNotebook.Storage.Exists(FirstPath));
  Assert.IsTrue(FNotebook.Storage.Exists(SecondPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.RenameConflictAfterMoveCompensates;
var
  OldPath: string;
begin
  OldPath := AddAttachment(FRootItem, 'data');
  FRelocator := TBeforeMove.Create(FRelocator, procedure begin
    SQL('UPDATE Items SET Version = Version + 1 WHERE Id = ' + IntToStr(FRootItem.Id));
  end);
  FDraft.Description := 'pending draft';
  FRootItem.Title := 'Rejected';
  Assert.IsFalse(FItems.UpdateItemDurable(FRootItem, FNotebook.Principal.Id, FRelocator));
  Assert.IsTrue(FNotebook.Storage.Exists(OldPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.FolderStaleDescendantRefuses;
var
  Folder: TFolder;
begin
  FProjects.AddFolder('Folder', '', FSource.Id, 0);
  Folder := FSource.Folders.Last;
  FRootItem.FolderID := Folder.Id;
  FChild.FolderID := Folder.Id;
  FNotebook.Manager.Flush;
  SQL('UPDATE Items SET Version = Version + 1 WHERE Id = ' + IntToStr(FChild.Id));
  FDraft.Description := 'pending draft';
  Assert.IsFalse(FProjects.MoveFolder(Folder, FSource.Id, FDestination.Id, 0,
    FNotebook.Principal.Id, FRelocator));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.MoveProcConflictAfterMoveRollsBackTree;
var
  OldPath: string;
begin
  OldPath := AddAttachment(FRootItem, 'data');
  FRelocator := TBeforeMove.Create(FRelocator, procedure begin
    SQL('UPDATE Items SET Version = Version + 1 WHERE Id = ' + IntToStr(FChild.Id));
  end);
  FDraft.Description := 'pending draft';
  Assert.IsFalse(FItems.MoveProc(FRootItem, FDestination.Id, 0,
    FNotebook.Principal.Id, FRelocator));
  Assert.IsTrue(FNotebook.Storage.Exists(OldPath));
  CheckUnchangedAfterFlush;
end;

procedure TItemDurabilityTests.RootListIncludesLegacyAndCanonicalItems;
var
  Folder: TFolder;
  Items: TItems;
  RootId: Integer;
begin
  FProjects.AddFolder('Positive folder', '', FSource.Id, 0);
  Folder := FSource.Folders.Last;
  FRootItem.FolderID := -1;
  FChild.FolderID := 0;
  FDraft.FolderID := Folder.Id;
  FNotebook.Manager.Flush;
  for RootId := -1 to 0 do
  begin
    FItems.AssignProject(FSource.Id, RootId);
    Items := FItems.List;
    try
      Assert.AreEqual<NativeInt>(2, Items.Count);
      Assert.IsTrue(Items.Contains(FRootItem), 'Legacy root item must remain visible');
      Assert.IsTrue(Items.Contains(FChild), 'Canonical root item must remain visible');
      Assert.IsFalse(Items.Contains(FDraft), 'Positive folder items must not leak into root');
    finally
      Items.Free;
    end;
  end;
  FItems.AssignProject(FSource.Id, Folder.Id);
  Items := FItems.List;
  try
    Assert.AreEqual<NativeInt>(1, Items.Count);
    Assert.IsTrue(Items.Contains(FDraft));
  finally
    Items.Free;
  end;
end;

procedure TItemDurabilityTests.LegacyRootAssignmentCreatesCanonicalItem;
var
  Created: TItem;
  Fresh: TObjectManager;
begin
  FItems.AssignProject(FSource.Id, -1);
  Created := NewItem('Created from legacy root selection');
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(0, Fresh.Find<TItem>(Created.Id).FolderID);
  finally
    TConflictHandler.FreeOperationManager(Fresh);
  end;
end;

procedure TItemDurabilityTests.MoveProcToLegacyRootPersistsCanonicalRoot;
var
  Folder: TFolder;
  OldPath, NewPath: string;
  Fresh: TObjectManager;
begin
  FProjects.AddFolder('Source folder', '', FSource.Id, 0);
  Folder := FSource.Folders.Last;
  FRootItem.FolderID := Folder.Id;
  FChild.FolderID := Folder.Id;
  FChild.IsDeleted := True;
  FNotebook.Manager.Flush;
  OldPath := AddAttachment(FChild, 'recycled-root-move');
  NewPath := OldPath.Replace(FSource.FileFolder, FDestination.FileFolder);
  FDraft.Description := 'pending draft';
  Assert.IsTrue(FItems.MoveProc(FRootItem, FDestination.Id, -1,
    FNotebook.Principal.Id, FRelocator));
  Assert.IsFalse(FNotebook.Storage.Exists(OldPath));
  Assert.AreEqual<NativeInt>(3, Length(FNotebook.Storage.ReadBytes(NewPath)));
  Assert.AreEqual('pending draft', FDraft.Description);
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(0, Fresh.Find<TItem>(FRootItem.Id).FolderID);
    Assert.AreEqual(0, Fresh.Find<TItem>(FChild.Id).FolderID);
    Assert.AreEqual(FDestination.Id, Fresh.Find<TItem>(FChild.Id).ProjectID);
    Assert.AreEqual('', Fresh.Find<TItem>(FDraft.Id).Description);
  finally
    TConflictHandler.FreeOperationManager(Fresh);
  end;
  FNotebook.Manager.Flush;
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(0, Fresh.Find<TItem>(FRootItem.Id).FolderID);
    Assert.AreEqual(0, Fresh.Find<TItem>(FChild.Id).FolderID);
    Assert.AreEqual('pending draft', Fresh.Find<TItem>(FDraft.Id).Description);
  finally
    TConflictHandler.FreeOperationManager(Fresh);
  end;
end;

procedure TItemDurabilityTests.FolderRootOperationsNormalizeLegacySentinel;
var
  Folder, Nested: TFolder;
  Fresh: TObjectManager;
begin
  FProjects.AddFolder('Created at legacy root', '', FSource.Id, -1);
  Folder := FSource.Folders.Last;
  FProjects.AddFolder('Nested', '', FSource.Id, Folder.Id);
  Nested := FSource.Folders.Last;
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(0, Fresh.Find<TFolder>(Folder.Id).ParentFolderID);
    Assert.AreEqual(Folder.Id, Fresh.Find<TFolder>(Nested.Id).ParentFolderID);
  finally
    TConflictHandler.FreeOperationManager(Fresh);
  end;
  FDraft.Description := 'pending draft';
  Assert.IsTrue(FProjects.MoveFolder(Nested, FSource.Id, FDestination.Id, -1,
    FNotebook.Principal.Id, FRelocator));
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(0, Fresh.Find<TFolder>(Nested.Id).ParentFolderID);
    Assert.IsNotNull(Fresh.Find<TProject>(FDestination.Id).GetFolder(Nested.Id));
    Assert.AreEqual('', Fresh.Find<TItem>(FDraft.Id).Description);
  finally
    TConflictHandler.FreeOperationManager(Fresh);
  end;
  Assert.AreEqual('pending draft', FDraft.Description);
end;

initialization
  TDUnitX.RegisterTestFixture(TItemDurabilityTests);

end.
