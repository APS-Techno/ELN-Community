unit test_LazyCollections;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DUnitX.TestFramework,
  Aurelius.Engine.ObjectManager,
  unit_Item, unit_Project, unit_LabEntry, unit_ValueType, unit_FileType,
  unit_DataModel,
  test_DesktopLoadStatements;

type
  TItemFile = unit_Item.TFile;

  [TestFixture]
  TLazyCollectionTests = class
  private
    function NewManager(Fixture: TDesktopLoadFixture): TObjectManager;
    function LeakedBytes(Fixture: TDesktopLoadFixture; const Scenario: TProc): NativeInt;
    function CollectionStatements(Fixture: TDesktopLoadFixture): Integer;
    function FirstFileId(Fixture: TDesktopLoadFixture; ItemId: Integer): Int64;
    procedure FreeLoadedChildren(Item: TItem);
    function TeardownScenario(Fixture: TDesktopLoadFixture; Latch,
      ReadCollections: Boolean): Integer;
    function TeardownLeak(Latch, ReadCollections: Boolean): NativeInt;
    function AnyValueType(Data: TDataModel): TValueType;
    function AnyFileType(Data: TDataModel): TFileType;
    function AddLateFile(Fixture: TDesktopLoadFixture; ItemId: Integer): Int64;
    function EvictCacheScenario(Fixture: TDesktopLoadFixture): Integer;
    function ConflictScenario(Fixture: TDesktopLoadFixture): Integer;
    function ForgetScenario(Fixture: TDesktopLoadFixture; RowId: Integer): Integer;
  public
    [Test] procedure NewObjectsReportLoaded;
    [Test] procedure SavedItemReportsLoadedBeforeAndAfterEvict;
    [Test] procedure FreshItemLoadRunsNoCollectionStatement;
    [Test] procedure FreshProjectLoadRunsNoFoldersStatement;
    [Test] procedure FreshItemListsStayUnloadedUntilRead;
    [Test] procedure FreshProjectFoldersStayUnloadedUntilRead;
    [Test] procedure EvictedUnloadedItemStaysUnloadedAndRefusesRead;
    [Test] procedure EvictedLoadedItemKeepsItsLists;
    [Test] procedure EvictCascadeReachesLoadedListOnly;
    [Test] procedure FreeingEvictedUnloadedItemsLeaksNothing;
    [Test] procedure TeardownWithUnloadedListsWithoutLatch;
    [Test] procedure TeardownWithLoadedListsWithoutLatch;
    [Test] procedure TeardownWithUnloadedListsUnderLatchLeaksNoMoreThanLoaded;
    [Test] procedure BatchFilesAreTheObjectsOfALaterLazyList;
    [Test] procedure LazyListAfterBatchFilesKeepsTheSameObjects;
    [Test] procedure AddItemResultIsTransientAndReloadable;
    [Test] procedure WritesAfterAddItemSurviveReload;
    [Test] procedure EvictCacheRunsNoCollectionStatement;
    [Test] procedure EvictCacheEvictsLoadedChildrenAndTheNextReadIsCurrent;
    [Test] procedure EvictCacheLeavesNothingBehind;
    [Test] procedure RefreshReloadsALoadedListAndKeepsAnUnloadedListUnloaded;
    [Test] procedure MoveFileWithUnloadedLists;
    [Test] procedure MoveFileWithLoadedLists;
    [Test] procedure ProjectsEvictCacheDropsLoadedFoldersAndTheNextReadIsCurrent;
    [Test] procedure PurgedItemLeavesNoCachedChildOfAnUnloadedList;
    [Test] procedure ConflictEvictOfDeletedRowLeavesNothingBehind;
    [Test] procedure McpMoveFileLeavesNoCachedItemOrFile;
    [Test] procedure ForgetCachedRowKeepsOwnershipWithTheManager;
  end;

implementation

uses
  System.JSON,
  Aurelius.Criteria.Linq, Aurelius.Types.Exceptions,
  unit_ItemTypes, unit_ValueSource, unit_FilePaths, unit_ConflictHandler,
  unit_RecycleBinModel, unit_MCPTools, unit_ToolsWrite, unit_ToolHelpers,
  unit_ItemModel;

function TLazyCollectionTests.NewManager(Fixture: TDesktopLoadFixture): TObjectManager;
begin
  Result := TObjectManager.Create(Fixture.Notebook.Connection);
end;

{$WARN SYMBOL_PLATFORM OFF}
function AllocatedBytes: NativeInt;
var
  State: TMemoryManagerState;
  Small: TSmallBlockTypeState;
begin
  GetMemoryManagerState(State);
  Result := State.TotalAllocatedMediumBlockSize + State.TotalAllocatedLargeBlockSize;
  for Small in State.SmallBlockTypeStates do
    Inc(Result, NativeInt(Small.UseableBlockSize) * NativeInt(Small.AllocatedBlockCount));
end;
{$WARN SYMBOL_PLATFORM ON}

function TLazyCollectionTests.LeakedBytes(Fixture: TDesktopLoadFixture;
  const Scenario: TProc): NativeInt;
var
  Before: NativeInt;
begin
  Scenario;
  Fixture.Counter.Clear;
  Before := AllocatedBytes;
  Scenario;
  Fixture.Counter.Clear;
  Result := AllocatedBytes - Before;
end;

function TLazyCollectionTests.CollectionStatements(Fixture: TDesktopLoadFixture): Integer;
begin
  Result := Fixture.Counter.CountMatching('LabEntries') +
    Fixture.Counter.CountMatching('Files') +
    Fixture.Counter.CountMatching('DataValues');
end;

function TLazyCollectionTests.FirstFileId(Fixture: TDesktopLoadFixture;
  ItemId: Integer): Int64;
var
  Probe: TObjectManager;
begin
  Probe := NewManager(Fixture);
  try
    Result := Probe.Find<TItem>(ItemId).Files[0].Id;
  finally
    Probe.Free;
  end;
end;

procedure TLazyCollectionTests.FreeLoadedChildren(Item: TItem);
var
  Entry: TLabEntry;
  AFile: TItemFile;
  Row: unit_Item.TValue;
  Entries: TArray<TLabEntry>;
  Files: TArray<TItemFile>;
  Rows: TArray<unit_Item.TValue>;
begin
  if Item.EntriesLoaded then
    Entries := Item.Entries.ToArray;
  if Item.FilesLoaded then
    Files := Item.Files.ToArray;
  if Item.ValuesLoaded then
    Rows := Item.Values.ToArray;
  for Entry in Entries do
    Entry.Free;
  for AFile in Files do
    AFile.Free;
  for Row in Rows do
    Row.Free;
end;

procedure TLazyCollectionTests.NewObjectsReportLoaded;
var
  Item: TItem;
  Project: TProject;
begin
  Item := TItem.Create;
  Project := TProject.Create;
  try
    Assert.IsTrue(Item.EntriesLoaded, 'new item entries');
    Assert.IsTrue(Item.FilesLoaded, 'new item files');
    Assert.IsTrue(Item.ValuesLoaded, 'new item values');
    Assert.IsTrue(Project.FoldersLoaded, 'new project folders');
    Assert.AreEqual<NativeInt>(0, Item.Entries.Count, 'new item entries read');
    Assert.AreEqual<NativeInt>(0, Item.Files.Count, 'new item files read');
    Assert.AreEqual<NativeInt>(0, Item.Values.Count, 'new item values read');
    Assert.AreEqual<NativeInt>(0, Project.Folders.Count, 'new project folders read');
  finally
    Project.Free;
    Item.Free;
  end;
end;

procedure TLazyCollectionTests.SavedItemReportsLoadedBeforeAndAfterEvict;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Item: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Item := TItem.Create;
      try
        Item.Title := 'Saved synthetic';
        Item.Type_ := TItemType.Other;
        Item.Level := TItemLevel.Proc;
        Item.CreatedDate := Now;
        Item.ProjectID := Fixture.ProjectAId;
        Item.FolderID := Fixture.FolderAId;
        Item.Expanded := True;
        Manager.Save(Item);
        Manager.Flush;
        Assert.IsTrue(Item.EntriesLoaded and Item.FilesLoaded and Item.ValuesLoaded,
          'saved and attached');
        Manager.Evict(Item);
        Assert.IsTrue(Item.EntriesLoaded and Item.FilesLoaded and Item.ValuesLoaded,
          'saved and evicted');
        Assert.AreEqual<NativeInt>(0, Item.Files.Count, 'evicted new item reads its empty list');
      finally
        Item.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.FreshItemLoadRunsNoCollectionStatement;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Items: TList<TItem>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Fixture.Counter.Clear;
      Manager.Find<TItem>(Fixture.ItemIds[0]);
      Assert.AreEqual(0, CollectionStatements(Fixture), 'Find by id');
      Items := Manager.Find<TItem>.List;
      try
        Assert.IsTrue(Items.Count >= 4, 'items listed');
      finally
        Items.Free;
      end;
      Assert.AreEqual(0, CollectionStatements(Fixture), 'Find list');
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.FreshProjectLoadRunsNoFoldersStatement;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Projects: TList<TProject>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Fixture.Counter.Clear;
      Projects := Manager.Find<TProject>.List;
      try
        Assert.IsTrue(Projects.Count >= 2, 'projects listed');
      finally
        Projects.Free;
      end;
      Assert.AreEqual(0, Fixture.Counter.CountMatching('Folders'), 'Find list');
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.FreshItemListsStayUnloadedUntilRead;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Item: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Item := Manager.Find<TItem>(Fixture.ItemIds[0]);
      Assert.IsFalse(Item.EntriesLoaded, 'entries before read');
      Assert.IsFalse(Item.FilesLoaded, 'files before read');
      Assert.IsFalse(Item.ValuesLoaded, 'values before read');
      Assert.AreEqual<NativeInt>(2, Item.Files.Count, 'files read');
      Assert.IsTrue(Item.FilesLoaded, 'files after read');
      Assert.IsFalse(Item.EntriesLoaded, 'entries after files read');
      Assert.IsFalse(Item.ValuesLoaded, 'values after files read');
      Assert.AreEqual<NativeInt>(2, Item.Entries.Count, 'entries read');
      Assert.AreEqual<NativeInt>(2, Item.Values.Count, 'values read');
      Assert.IsTrue(Item.EntriesLoaded and Item.ValuesLoaded, 'all after read');
      Assert.AreSame(Item, Manager.Find<TItem>(Fixture.ItemIds[0]), 'identity map');
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.FreshProjectFoldersStayUnloadedUntilRead;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Project: TProject;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Project := Manager.Find<TProject>(Fixture.ProjectAId);
      Assert.IsFalse(Project.FoldersLoaded, 'folders before read');
      Assert.AreEqual<NativeInt>(2, Project.Folders.Count, 'folders read');
      Assert.IsTrue(Project.FoldersLoaded, 'folders after read');
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.EvictedUnloadedItemStaysUnloadedAndRefusesRead;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Item: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Item := Manager.Find<TItem>(Fixture.ItemIds[0]);
      Manager.Evict(Item);
      try
        Assert.IsFalse(Item.EntriesLoaded, 'entries after evict');
        Assert.IsFalse(Item.FilesLoaded, 'files after evict');
        Assert.IsFalse(Item.ValuesLoaded, 'values after evict');
        Assert.WillRaise(
          procedure
          begin
            Assert.AreEqual<NativeInt>(2, Item.Files.Count);
          end, EObjectManagerNotSet);
      finally
        Item.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.EvictedLoadedItemKeepsItsLists;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Item: TItem;
  AFile: TItemFile;
  Entry: TLabEntry;
  Row: unit_Item.TValue;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Item := Manager.Find<TItem>(Fixture.ItemIds[0]);
      Assert.AreEqual<NativeInt>(2, Item.Files.Count);
      Assert.AreEqual<NativeInt>(2, Item.Entries.Count);
      Assert.AreEqual<NativeInt>(2, Item.Values.Count);
      Manager.Evict(Item);
      try
        Assert.IsTrue(Item.EntriesLoaded and Item.FilesLoaded and Item.ValuesLoaded,
          'lists stay loaded');
        Assert.AreEqual<NativeInt>(2, Item.Files.Count, 'files after evict');
        for AFile in Item.Files do
          Assert.IsFalse(Manager.IsAttached(AFile), 'file evicted by cascade');
        for Entry in Item.Entries do
          Assert.IsFalse(Manager.IsAttached(Entry), 'entry evicted by cascade');
        for Row in Item.Values do
          Assert.IsFalse(Manager.IsAttached(Row), 'value evicted by cascade');
      finally
        FreeLoadedChildren(Item);
        Item.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.EvictCascadeReachesLoadedListOnly;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Unloaded, Loaded: TItem;
  FileOfUnloaded: TItemFile;
  FilesOfLoaded: TArray<TItemFile>;
  AFile: TItemFile;
  UnloadedFileId: Int64;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    UnloadedFileId := FirstFileId(Fixture, Fixture.ItemIds[0]);
    Manager := NewManager(Fixture);
    try
      Unloaded := Manager.Find<TItem>(Fixture.ItemIds[0]);
      FileOfUnloaded := Manager.Find<TItemFile>(UnloadedFileId);
      Assert.IsFalse(Unloaded.FilesLoaded, 'list stays unloaded');
      Loaded := Manager.Find<TItem>(Fixture.ItemIds[1]);
      FilesOfLoaded := Loaded.Files.ToArray;
      Assert.AreEqual<NativeInt>(2, Length(FilesOfLoaded), 'files of the loaded list');

      Manager.Evict(Unloaded);
      Assert.IsTrue(Manager.IsAttached(FileOfUnloaded),
        'cascade does not reach a file of an unloaded list');
      Manager.Evict(Loaded);
      for AFile in FilesOfLoaded do
        Assert.IsFalse(Manager.IsAttached(AFile), 'cascade reaches a loaded list');

      for AFile in FilesOfLoaded do
        AFile.Free;
      Unloaded.Free;
      Loaded.Free;
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.FreeingEvictedUnloadedItemsLeaksNothing;
var
  Fixture: TDesktopLoadFixture;
  Leaked: NativeInt;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Leaked := LeakedBytes(Fixture,
      procedure
      var
        Manager: TObjectManager;
        Items: TList<TItem>;
        Item: TItem;
      begin
        Manager := NewManager(Fixture);
        try
          Items := Manager.Find<TItem>.List;
          try
            for Item in Items do
              Manager.Evict(Item);
            for Item in Items do
              Item.Free;
          finally
            Items.Free;
          end;
        finally
          Manager.Free;
        end;
      end);
    Assert.AreEqual<NativeInt>(0, Leaked, 'bytes left after freeing evicted unloaded items');
  finally
    Fixture.Free;
  end;
end;

function TLazyCollectionTests.TeardownScenario(Fixture: TDesktopLoadFixture;
  Latch, ReadCollections: Boolean): Integer;
var
  Manager: TObjectManager;
  Items: TList<TItem>;
  Projects: TList<TProject>;
  Item: TItem;
  Project: TProject;
  Prior: Boolean;
begin
  Result := 0;
  Manager := NewManager(Fixture);
  Prior := unit_Project.ManagerShuttingDown;
  try
    Items := Manager.Find<TItem>.List;
    try
      if ReadCollections then
        for Item in Items do
          Inc(Result, Item.Entries.Count + Item.Files.Count + Item.Values.Count);
    finally
      Items.Free;
    end;
    Projects := Manager.Find<TProject>.List;
    try
      if ReadCollections then
        for Project in Projects do
          Inc(Result, Project.Folders.Count);
    finally
      Projects.Free;
    end;
    unit_Project.ManagerShuttingDown := Latch;
    if Latch then
      Manager.Clear;
  finally
    try
      Manager.Free;
    finally
      unit_Project.ManagerShuttingDown := Prior;
    end;
  end;
end;

function TLazyCollectionTests.TeardownLeak(Latch, ReadCollections: Boolean): NativeInt;
var
  Fixture: TDesktopLoadFixture;
  Read: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Read := 0;
    Result := LeakedBytes(Fixture,
      procedure
      begin
        Read := TeardownScenario(Fixture, Latch, ReadCollections);
      end);
    Assert.AreEqual(ReadCollections, Read > 0, 'collections read as requested');
    TDUnitX.CurrentRunner.Log(TLogLevel.Information,
      Format('teardown latch=%s read=%s: %d bytes left',
        [BoolToStr(Latch, True), BoolToStr(ReadCollections, True), Result]));
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.TeardownWithUnloadedListsWithoutLatch;
begin
  Assert.AreEqual<NativeInt>(0, TeardownLeak(False, False), 'bytes left');
end;

procedure TLazyCollectionTests.TeardownWithLoadedListsWithoutLatch;
begin
  Assert.AreEqual<NativeInt>(0, TeardownLeak(False, True), 'bytes left');
end;

procedure TLazyCollectionTests.TeardownWithUnloadedListsUnderLatchLeaksNoMoreThanLoaded;
var
  Unloaded, Loaded: NativeInt;
begin
  Unloaded := TeardownLeak(True, False);
  Loaded := TeardownLeak(True, True);
  Assert.IsTrue(Unloaded <= Loaded,
    Format('unloaded lists leave %d bytes, loaded lists leave %d bytes', [Unloaded, Loaded]));
end;

procedure TLazyCollectionTests.BatchFilesAreTheObjectsOfALaterLazyList;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Item: TItem;
  Batch: TList<TItemFile>;
  AFile: TItemFile;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Item := Manager.Find<TItem>(Fixture.ItemIds[0]);
      Batch := Manager.Find<TItemFile>
        .CreateAlias('Item', 'i')
        .Where(Linq['i.Id'] = Fixture.ItemIds[0])
        .OrderBy('Id')
        .List;
      try
        Assert.AreEqual<NativeInt>(2, Batch.Count, 'batch read');
        Assert.IsFalse(Item.FilesLoaded, 'batch read does not load the list');
        Assert.AreEqual<NativeInt>(2, Item.Files.Count, 'lazy list');
        for AFile in Batch do
          Assert.IsTrue(Item.Files.Contains(AFile), 'same object in both reads');
      finally
        Batch.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.LazyListAfterBatchFilesKeepsTheSameObjects;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Item: TItem;
  Batch: TList<TItemFile>;
  AFile: TItemFile;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Batch := Manager.Find<TItemFile>
        .CreateAlias('Item', 'i')
        .Where(Linq['i.Id'] = Fixture.ItemIds[0])
        .OrderBy('Id')
        .List;
      try
        Item := Manager.Find<TItem>(Fixture.ItemIds[0]);
        Assert.AreEqual<NativeInt>(2, Item.Files.Count, 'lazy list');
        for AFile in Batch do
        begin
          Assert.IsTrue(Item.Files.Contains(AFile), 'same object in both reads');
          Assert.AreSame(Item, AFile.Item, 'owner is the managed item');
        end;
      finally
        Batch.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

function TLazyCollectionTests.AnyValueType(Data: TDataModel): TValueType;
var
  Rows: TList<TValueType>;
begin
  Rows := Data.Manager.Find<TValueType>.List;
  try
    Result := Rows[0];
  finally
    Rows.Free;
  end;
end;

function TLazyCollectionTests.AnyFileType(Data: TDataModel): TFileType;
var
  Rows: TList<TFileType>;
begin
  Rows := Data.Manager.Find<TFileType>.List;
  try
    Result := Rows[0];
  finally
    Rows.Free;
  end;
end;

function TLazyCollectionTests.AddLateFile(Fixture: TDesktopLoadFixture;
  ItemId: Integer): Int64;
var
  Writer: TDataModel;
  Item: TItem;
  Added: TItemFile;
begin
  Writer := Fixture.NewDataModel;
  try
    Item := Writer.Manager.Find<TItem>(ItemId);
    Added := Writer.Items.AddFile(AnyFileType(Writer), 'late.txt', Writer.User.Id, Item);
    Assert.IsNotNull(Added, 'late file added');
    Result := Added.Id;
  finally
    Writer.Free;
  end;
end;

procedure TLazyCollectionTests.AddItemResultIsTransientAndReloadable;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Created, Reloaded: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Data := Fixture.NewDataModel;
    try
      Data.Items.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
      Created := Data.Items.AddItem(TItemType.Other, 'Transient result',
        TItemLevel.Proc, 0, '', nil, nil, Data.User.Id);
      try
        Assert.IsFalse(Data.Manager.IsAttached(Created), 'AddItem returns an evicted item');
        Reloaded := Data.Manager.Find<TItem>(Created.Id);
        Assert.AreNotSame(Created, Reloaded, 'a reload is a different object');
        Assert.IsFalse(Reloaded.FilesLoaded, 'the reloaded item has lazy lists');
        Assert.AreEqual<NativeInt>(0, Reloaded.Files.Count, 'reloaded files');
      finally
        Created.Free;
      end;
    finally
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.WritesAfterAddItemSurviveReload;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Item: TItem;
  Fresh: TObjectManager;
  Stored: TItem;
  ValueType: TValueType;
  FileType: TFileType;
  Id: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Data := Fixture.NewDataModel;
    try
      Data.Items.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
      ValueType := AnyValueType(Data);
      FileType := AnyFileType(Data);
      Item := Data.Items.AddItem(TItemType.Other, 'Written after AddItem',
        TItemLevel.Proc, 0, '', nil, nil, Data.User.Id);
      Id := Item.Id;
      Data.Items.AddValue(ValueType, TRecType.EXP_CONDITION, 1.5, Data.User.Id,
        Item, 0, 'first', TValueSourceInfo.Unknown);
      Data.Items.AddValue(ValueType, TRecType.TEST_RESULT, 2.5, Data.User.Id,
        Item, 0, 'second', TValueSourceInfo.Unknown);
      Assert.IsNotNull(Data.Items.AddFile(FileType, 'attached', Data.User.Id, Item),
        'file written');
      Data.Items.AddNote('note', 'body', Data.User.Id, Item);
      Assert.AreSame(Item, Data.Manager.Find<TItem>(Id), 'the written item is managed again');

      Fresh := NewManager(Fixture);
      try
        Stored := Fresh.Find<TItem>(Id);
        Assert.AreEqual<NativeInt>(2, Stored.Values.Count, 'values after reload');
        Assert.AreEqual<NativeInt>(1, Stored.Files.Count, 'files after reload');
        Assert.AreEqual<NativeInt>(1, Stored.Entries.Count, 'entries after reload');
      finally
        Fresh.Free;
      end;
    finally
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

function TLazyCollectionTests.EvictCacheScenario(Fixture: TDesktopLoadFixture): Integer;
var
  Manager: TObjectManager;
  Items: TItemModel;
  Held: TItems;
  Item: TItem;
begin
  Manager := NewManager(Fixture);
  try
    Items := TItemModel.Create(Manager);
    try
      Items.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
      Held := Items.List;
      try
        Assert.AreEqual<NativeInt>(2, Held[0].Files.Count, 'files of the first item');
        Assert.AreEqual<NativeInt>(2, Held[0].Entries.Count, 'entries of the first item');
        Assert.AreEqual<NativeInt>(2, Held[0].Values.Count, 'values of the first item');
        Assert.AreEqual<NativeInt>(2, Held[1].Files.Count, 'files of the second item');
        Fixture.Counter.Clear;
        Items.EvictCache;
        Result := CollectionStatements(Fixture);
        for Item in Held do
        begin
          Assert.IsFalse(Manager.IsAttached(Item), 'item evicted');
          FreeLoadedChildren(Item);
          Item.Free;
        end;
      finally
        Held.Free;
      end;
    finally
      Items.Free;
    end;
  finally
    Manager.Free;
  end;
end;

procedure TLazyCollectionTests.EvictCacheRunsNoCollectionStatement;
var
  Fixture: TDesktopLoadFixture;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Assert.AreEqual(0, EvictCacheScenario(Fixture), 'EvictCache must not load a list to evict it');
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.EvictCacheEvictsLoadedChildrenAndTheNextReadIsCurrent;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Held: TItems;
  First: TItem;
  FirstId: Integer;
  Files: TArray<TItemFile>;
  Entries: TArray<TLabEntry>;
  Rows: TArray<unit_Item.TValue>;
  Item: TItem;
  AFile: TItemFile;
  Entry: TLabEntry;
  Row: unit_Item.TValue;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Data := Fixture.NewDataModel;
    try
      Data.Items.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
      Held := Data.Items.List;
      try
        First := Held[0];
        FirstId := First.Id;
        Files := First.Files.ToArray;
        Entries := First.Entries.ToArray;
        Rows := First.Values.ToArray;
        Assert.AreEqual<NativeInt>(2, Length(Files), 'files held');
        Assert.AreEqual<NativeInt>(2, Length(Entries), 'entries held');
        Assert.AreEqual<NativeInt>(2, Length(Rows), 'values held');
        AddLateFile(Fixture, FirstId);
        Data.Items.EvictCache;
        for AFile in Files do
          Assert.IsFalse(Data.Manager.IsAttached(AFile), 'file evicted');
        for Entry in Entries do
          Assert.IsFalse(Data.Manager.IsAttached(Entry), 'entry evicted');
        for Row in Rows do
          Assert.IsFalse(Data.Manager.IsAttached(Row), 'value evicted');
        Assert.AreEqual<NativeInt>(3, Data.Manager.Find<TItem>(FirstId).Files.Count,
          'the next read sees the file added through the second manager');
        for AFile in Files do
          AFile.Free;
        for Entry in Entries do
          Entry.Free;
        for Row in Rows do
          Row.Free;
        for Item in Held do
          Item.Free;
      finally
        Held.Free;
      end;
    finally
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.EvictCacheLeavesNothingBehind;
var
  Fixture: TDesktopLoadFixture;
  Leaked: NativeInt;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Leaked := LeakedBytes(Fixture,
      procedure
      begin
        EvictCacheScenario(Fixture);
      end);
    Assert.AreEqual<NativeInt>(0, Leaked, 'bytes left after EvictCache and freeing the evicted objects');
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.RefreshReloadsALoadedListAndKeepsAnUnloadedListUnloaded;
var
  Fixture: TDesktopLoadFixture;
  Manager: TObjectManager;
  Loaded, Unloaded: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Manager := NewManager(Fixture);
    try
      Loaded := Manager.Find<TItem>(Fixture.ItemIds[0]);
      Unloaded := Manager.Find<TItem>(Fixture.ItemIds[1]);
      Assert.AreEqual<NativeInt>(2, Loaded.Files.Count, 'files before');
      AddLateFile(Fixture, Fixture.ItemIds[0]);
      AddLateFile(Fixture, Fixture.ItemIds[1]);
      Manager.Refresh(Loaded);
      Manager.Refresh(Unloaded);
      Assert.AreEqual<NativeInt>(3, Loaded.Files.Count, 'Refresh reloads a loaded list');
      Assert.IsFalse(Unloaded.FilesLoaded, 'Refresh does not load an unloaded list');
      Assert.AreEqual<NativeInt>(3, Unloaded.Files.Count, 'the first read is current');
    finally
      Manager.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.MoveFileWithUnloadedLists;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Fresh: TObjectManager;
  AFile: TItemFile;
  OldParent, NewParent: TItem;
  FileId: Int64;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    FileId := FirstFileId(Fixture, Fixture.ItemIds[0]);
    Data := Fixture.NewDataModel;
    try
      AFile := Data.Manager.Find<TItemFile>(FileId);
      OldParent := AFile.Item;
      NewParent := Data.Manager.Find<TItem>(Fixture.ItemIds[1]);
      Assert.IsFalse(OldParent.FilesLoaded or NewParent.FilesLoaded, 'lists unloaded');
      Assert.IsTrue(Data.Items.MoveFile(AFile, Fixture.ItemIds[1], Data.User.Id), 'moved');
      Assert.IsFalse(Data.Manager.IsAttached(AFile), 'file evicted');
      Assert.IsFalse(Data.Manager.IsAttached(OldParent), 'old parent evicted');
      Assert.IsFalse(Data.Manager.IsAttached(NewParent), 'new parent evicted');
      Fresh := NewManager(Fixture);
      try
        Assert.AreEqual<NativeInt>(1, Fresh.Find<TItem>(Fixture.ItemIds[0]).Files.Count, 'old parent files');
        Assert.AreEqual<NativeInt>(3, Fresh.Find<TItem>(Fixture.ItemIds[1]).Files.Count, 'new parent files');
        Assert.AreEqual(Fixture.ItemIds[1], Fresh.Find<TItemFile>(FileId).Item.Id, 'file owner');
      finally
        Fresh.Free;
      end;
      AFile.Free;
      OldParent.Free;
      NewParent.Free;
    finally
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.MoveFileWithLoadedLists;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  AFile: TItemFile;
  OldParent, NewParent: TItem;
  OldFiles, NewFiles: TArray<TItemFile>;
  FileId: Int64;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    FileId := FirstFileId(Fixture, Fixture.ItemIds[0]);
    Data := Fixture.NewDataModel;
    try
      AFile := Data.Manager.Find<TItemFile>(FileId);
      OldParent := AFile.Item;
      NewParent := Data.Manager.Find<TItem>(Fixture.ItemIds[1]);
      OldFiles := OldParent.Files.ToArray;
      NewFiles := NewParent.Files.ToArray;
      Assert.AreEqual<NativeInt>(2, Length(OldFiles), 'files of the old parent');
      Assert.AreEqual<NativeInt>(2, Length(NewFiles), 'files of the new parent');
      Assert.IsTrue(Data.Items.MoveFile(AFile, Fixture.ItemIds[1], Data.User.Id), 'moved');
      for AFile in OldFiles + NewFiles do
        Assert.IsFalse(Data.Manager.IsAttached(AFile), 'no file of a loaded list stays attached');
      Assert.AreEqual<NativeInt>(3, Data.Manager.Find<TItem>(Fixture.ItemIds[1]).Files.Count,
        'the next read is current');
      for AFile in OldFiles + NewFiles do
        AFile.Free;
      OldParent.Free;
      NewParent.Free;
    finally
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.ProjectsEvictCacheDropsLoadedFoldersAndTheNextReadIsCurrent;
var
  Fixture: TDesktopLoadFixture;
  Data, Writer: TDataModel;
  Projects: TList<TProject>;
  Folders: TList<TFolder>;
  Held: TArray<TProject>;
  HeldFolders: TArray<TFolder>;
  Project: TProject;
  Folder: TFolder;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Data := Fixture.NewDataModel;
    try
      Assert.AreEqual<NativeInt>(2, Data.Manager.Find<TProject>(Fixture.ProjectAId).Folders.Count,
        'folders of the first project');
      Assert.IsFalse(Data.Manager.Find<TProject>(Fixture.ProjectBId).FoldersLoaded,
        'folders of the second project stay unloaded');
      Writer := Fixture.NewDataModel;
      try
        Writer.Projects.AddFolder('Late folder', '', Fixture.ProjectAId, 0);
      finally
        Writer.Free;
      end;
      Projects := Data.Manager.Find<TProject>.List;
      Folders := Data.Manager.Find<TFolder>.List;
      try
        Held := Projects.ToArray;
        HeldFolders := Folders.ToArray;
      finally
        Projects.Free;
        Folders.Free;
      end;
      Assert.AreEqual<NativeInt>(2, Length(Held), 'projects held');
      Assert.AreEqual<NativeInt>(4, Length(HeldFolders), 'folders held, with the late one');
      Data.Projects.EvictCache;
      for Project in Held do
        Assert.IsFalse(Data.Manager.IsAttached(Project), 'project evicted');
      for Folder in HeldFolders do
        Assert.IsFalse(Data.Manager.IsAttached(Folder), 'folder evicted');
      Assert.AreEqual<NativeInt>(3, Data.Manager.Find<TProject>(Fixture.ProjectAId).Folders.Count,
        'the next read sees the folder added through the second manager');
      for Project in Held do
        Project.Free;
      for Folder in HeldFolders do
        Folder.Free;
    finally
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.PurgedItemLeavesNoCachedChildOfAnUnloadedList;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Probe: TObjectManager;
  Bin: TRecycleBinModel;
  Item: TItem;
  AFile: TItemFile;
  Row: unit_Item.TValue;
  Entry: TLabEntry;
  FileId: Int64;
  RowId, EntryId: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Probe := NewManager(Fixture);
    try
      Item := Probe.Find<TItem>(Fixture.ItemIds[3]);
      FileId := Item.Files[0].Id;
      RowId := Item.Values[0].Id;
      EntryId := Item.Entries[0].Id;
    finally
      Probe.Free;
    end;
    Data := Fixture.NewDataModel;
    try
      Data.Items.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
      Item := Data.Manager.Find<TItem>(Fixture.ItemIds[3]);
      AFile := Data.Manager.Find<TItemFile>(FileId);
      Row := Data.Manager.Find<unit_Item.TValue>(RowId);
      Entry := Data.Manager.Find<TLabEntry>(EntryId);
      Assert.IsFalse(Item.FilesLoaded or Item.ValuesLoaded or Item.EntriesLoaded, 'lists unloaded');
      Assert.IsTrue(Data.Items.SoftDeleteItemTree(Item, Data.User.Id), 'binned');
      Bin := TRecycleBinModel.Create(Data.Manager);
      try
        Assert.IsTrue(Bin.PermanentlyDelete(Item, Data.User.Id), 'purged');
      finally
        Bin.Free;
      end;
      Assert.IsFalse(Data.Manager.IsAttached(Item), 'item evicted');
      Item.Free;
      Assert.IsFalse(Data.Manager.IsAttached(AFile), 'the purged file leaves the identity map');
      Assert.IsFalse(Data.Manager.IsAttached(Row), 'the purged value leaves the identity map');
      Assert.IsFalse(Data.Manager.IsAttached(Entry), 'the purged entry leaves the identity map');
      Assert.IsNull(Data.Manager.FindCached<TItemFile>(FileId), 'file not cached');
      Assert.IsNull(Data.Manager.Find<TItemFile>(FileId), 'file row is gone');
    finally
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

function TLazyCollectionTests.ConflictScenario(Fixture: TDesktopLoadFixture): Integer;
var
  Writer, Reader: TObjectManager;
  WriterItems: TItemModel;
  Created, Item, Victim: TItem;
  Id: Integer;
begin
  Result := 0;
  Writer := NewManager(Fixture);
  try
    WriterItems := TItemModel.Create(Writer);
    try
      WriterItems.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
      Created := WriterItems.AddItem(TItemType.Other, 'Conflict', TItemLevel.Proc, 0,
        '', nil, nil, Fixture.Notebook.Principal.Id);
      Id := Created.Id;
      Created.Free;
      Reader := NewManager(Fixture);
      try
        Item := Reader.Find<TItem>(Id);
        Victim := Writer.Find<TItem>(Id);
        Writer.Remove(Victim);
        Writer.Flush;
        Item.Description := 'changed after the row is gone';
        TConflictHandler.OnConflict :=
          function(const Msg: string): TConflictResolution
          begin
            Result := crReload;
          end;
        try
          if not TConflictHandler.SafeFlush(Reader) then
            Inc(Result);
        finally
          TConflictHandler.OnConflict := nil;
        end;
      finally
        Reader.Free;
      end;
    finally
      WriterItems.Free;
    end;
  finally
    Writer.Free;
  end;
end;

procedure TLazyCollectionTests.ConflictEvictOfDeletedRowLeavesNothingBehind;
var
  Fixture: TDesktopLoadFixture;
  Leaked: NativeInt;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Assert.AreEqual(1, ConflictScenario(Fixture), 'the conflict is reported');
    Leaked := LeakedBytes(Fixture,
      procedure
      begin
        ConflictScenario(Fixture);
      end);
    Assert.AreEqual<NativeInt>(0, Leaked, 'bytes left after a conflicted row is evicted');
  finally
    Fixture.Free;
  end;
end;

procedure TLazyCollectionTests.McpMoveFileLeavesNoCachedItemOrFile;
var
  Fixture: TDesktopLoadFixture;
  Context: TToolContext;
  Registry: TToolRegistry;
  Params, Response: TJSONObject;
  Manager, Fresh: TObjectManager;
  Source, Target: TItem;
  Project: TProject;
  AFile: TItemFile;
  FileId: Int64;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    FileId := FirstFileId(Fixture, Fixture.ItemIds[0]);
    Manager := Fixture.Notebook.Manager;
    AFile := Manager.Find<TItemFile>(FileId);
    Source := AFile.Item;
    Target := Manager.Find<TItem>(Fixture.ItemIds[1]);
    Project := Manager.Find<TProject>(Source.ProjectID);
    Fixture.Notebook.Storage.WriteBytes(
      AttachmentRelativePath(Project.FileFolder, Source.FolderName, AFile.FullName),
      [1, 2, 3]);
    Context := Default(TToolContext);
    Context.Manager := Manager;
    Context.User := Fixture.Notebook.Principal;
    Context.AccessPolicy := Fixture.Notebook.AccessPolicy;
    Context.Storage := Fixture.Notebook.Storage;
    Registry := TToolRegistry.Create(Context);
    try
      RegisterWriteTools(Registry);
      Params := TJSONObject.ParseJSONValue(Format('{"file_id":%d,"target_item_id":%d}',
        [FileId, Fixture.ItemIds[1]])) as TJSONObject;
      try
        Response := Registry.Execute('move_file', Params);
        Response.Free;
      finally
        Params.Free;
      end;
    finally
      Registry.Free;
    end;
    Assert.IsFalse(Manager.IsAttached(Source), 'source evicted');
    Assert.IsFalse(Manager.IsAttached(Target), 'target evicted');
    Assert.IsFalse(Manager.IsAttached(AFile), 'file evicted');
    Fresh := NewManager(Fixture);
    try
      Assert.AreEqual<NativeInt>(1, Fresh.Find<TItem>(Fixture.ItemIds[0]).Files.Count, 'source files');
      Assert.AreEqual<NativeInt>(3, Fresh.Find<TItem>(Fixture.ItemIds[1]).Files.Count, 'target files');
    finally
      Fresh.Free;
    end;
    Assert.AreEqual<NativeInt>(3, Manager.Find<TItem>(Fixture.ItemIds[1]).Files.Count,
      'the session manager reads the moved file under its new item');
    AFile.Free;
    Source.Free;
    Target.Free;
  finally
    Fixture.Free;
  end;
end;

function TLazyCollectionTests.ForgetScenario(Fixture: TDesktopLoadFixture;
  RowId: Integer): Integer;
var
  Manager: TObjectManager;
  Row: unit_Item.TValue;
  Context: TToolContext;
begin
  Manager := NewManager(Fixture);
  try
    Row := Manager.Find<unit_Item.TValue>(RowId);
    Context := Default(TToolContext);
    Context.Manager := Manager;
    ForgetCachedRow(Context, Row);
    Result := Ord(not Manager.IsAttached(Row) and
      (Manager.FindCached<unit_Item.TValue>(RowId) = nil));
  finally
    Manager.Free;
  end;
end;

procedure TLazyCollectionTests.ForgetCachedRowKeepsOwnershipWithTheManager;
var
  Fixture: TDesktopLoadFixture;
  Probe: TObjectManager;
  RowId: Integer;
  Leaked: NativeInt;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Probe := NewManager(Fixture);
    try
      RowId := Probe.Find<TItem>(Fixture.ItemIds[0]).Values[0].Id;
    finally
      Probe.Free;
    end;
    Assert.AreEqual(1, ForgetScenario(Fixture, RowId), 'the forgotten row leaves the identity map');
    Leaked := LeakedBytes(Fixture,
      procedure
      begin
        ForgetScenario(Fixture, RowId);
      end);
    Assert.AreEqual<NativeInt>(0, Leaked, 'bytes left after the manager frees the forgotten row');
  finally
    Fixture.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLazyCollectionTests);
end.
