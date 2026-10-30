unit test_SearchIndex;

interface

uses
  System.SysUtils, System.Hash, System.Generics.Collections, DUnitX.TestFramework,
  unit_NotebookStorage, unit_LocalNotebook, unit_SearchPassages,
  unit_SearchDocumentProvider, unit_SearchIndexStore, unit_SearchIndexer,
  unit_TextEmbedder, unit_Item, unit_HybridSearch, unit_TextExtractors,
  unit_TextExtractorRegistry, unit_FileTextStage, test_SearchDoubles;

type
  TNotebookFixture = class
  protected
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProvider: ISearchDocumentSource;
    FProjectId: Integer;
    FItem1, FItem2, FEntryId, FValueId: Integer;
    FMdId, FPdfId: Int64;
    FMdPath: string;
    procedure BuildNotebook;
    procedure FreeNotebook;
  end;

  [TestFixture]
  TDocumentProviderTests = class(TNotebookFixture)
  private
    function Read: TSearchPassages;
    function IndexOf(const Passages: TSearchPassages; const Key: string): Integer;
    function Has(const Passages: TSearchPassages; const Key: string): Boolean;
    function MaxAuditId: Int64;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsAllFieldKinds;
    [Test]
    procedure LongDescriptionChunked;
    [Test]
    procedure DeletedItemExcluded;
    [Test]
    procedure PdfHasNameOnly;
    [Test]
    procedure MissingAttachmentBytesSkipped;
    [Test]
    procedure ProviderEmitsFileRequestsAndReadsNoBytes;
    [Test]
    procedure TextIsFolded;
    [Test]
    procedure IsItemLiveReportsProjectAndBin;
    [Test]
    procedure CancellationStopsReading;
    [Test]
    procedure ProviderDoesNotWrite;
    [Test]
    procedure NonUtf8TextFallsBackToAnsi;
  end;

  [TestFixture]
  TSearchIndexerTests = class(TNotebookFixture)
  private
    FStorePath: string;
    FStore: TSearchIndexStore;
    FFake: TFakeEmbedder;
    FEmbedder: ITextEmbedder;
    FIndexer: TSearchIndexer;
    procedure OpenIndexer(const Identity: string);
    function SourceCount: Integer;
    function CatalogHasItem(ItemId: Integer): Boolean;
    function CatalogKeys: TArray<string>;
    function CatalogHas(const Key: string): Boolean;
    function ItemById(Id: Integer): TItem;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FirstSyncAddsAll;
    [Test]
    procedure SecondSyncEmbedsNothing;
    [Test]
    procedure EditedDescriptionReembedsOnlyIt;
    [Test]
    procedure TagAssignWithoutAuditIsSeen;
    [Test]
    procedure RecycledItemRemoved;
    [Test]
    procedure ProjectMoveUpdatesScope;
    [Test]
    procedure CancelMidSyncThenResume;
    [Test]
    procedure IdentityChangeRebuilds;
    [Test]
    procedure SnapshotSourceFeedsIndexer;
    [Test]
    procedure ProgressReportsPendingTotalFirst;
  end;

  [TestFixture]
  TStorageFileReaderTests = class(TNotebookFixture)
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StorageReaderFromWorkerThread;
    [Test]
    procedure MissingAndOversizeFiles;
    [Test]
    procedure StampTracksSizeAndLastWrite;
  end;

  TSearchFixture = class(TNotebookFixture)
  protected
    FStore: TSearchIndexStore;
    FEmbedder: ITextEmbedder;
    FIndexer: TSearchIndexer;
    FSearcher: THybridSearcher;
    procedure OpenSearch(const Embedder: ITextEmbedder);
    procedure CloseSearch;
    procedure SyncAndReload;
    function VisibleIds: TArray<Integer>;
    function AddItem(const Title, FormData: string; ProjectId: Integer): TItem;
    function AddForeignProject: Integer;
    function HasItem(const Hits: TArray<THybridGroup>; ItemId: Integer): Boolean;
    function HitFor(const Hits: TArray<THybridGroup>; ItemId: Integer): Integer;
  end;

  TStagedSource = class(TInterfacedObject, ISearchDocumentSource)
  private
    FInner: ISearchDocumentSource;
    FStore: TSearchIndexStore;
    FRegistry: TTextExtractorRegistry;
    FStage: TFileTextStage;
    FReader: IFileContentReader;
  public
    constructor Create(const Inner: ISearchDocumentSource; const Storage: INotebookStorage;
      const StorePath: string);
    destructor Destroy; override;
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  [TestFixture]
  THybridSearchTests = class(TSearchFixture)
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OtherOwnerProjectNeverReturned;
    [Test]
    procedure EmptyVisibleSetGivesNothing;
    [Test]
    procedure StaleHitDroppedBeforeSync;
    [Test]
    procedure MovedToInvisibleProjectDropped;
    [Test]
    procedure ShortQueryEmpty;
    [Test]
    procedure LongQueryUsesTextLists;
  end;

  [TestFixture]
  TRealModelSearchTests = class(TSearchFixture)
  private
    FModel: ITextEmbedder;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure IdentifierFoundByTrigram;
    [Test]
    procedure CrossLingualFindsProtocolForm;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Math, System.SyncObjs, Aurelius.Engine.ObjectManager,
  unit_User, unit_Project, unit_ItemTypes, unit_ValueType, unit_FileType,
  unit_LabEntry, unit_Protocol, unit_Tag, unit_AuditLog, unit_FilePaths,
  unit_ProjectModel, unit_VectorSearch, unit_ItemModel, unit_TagModel, unit_FileRelocator, Aurelius.Drivers.SQLite.Import;

const
  FixturePassword = 'Synthetic-Search-Index-Only!';
  MdContent = '# Notes'#10'плёнка отслоилась';

procedure TNotebookFixture.BuildNotebook;
var
  Id: TGUID;
  Projects: TProjectsModel;
  Project: TProject;
  Manager: TObjectManager;
  ValueType: TValueType;
  MdType, PdfType: TFileType;
  Item1, Item2: TItem;
  Protocol: TProtocol;
  Value1, Value2: unit_Item.TValue;
  MdFile, PdfFile: unit_Item.TFile;
  Tag: TTag;
  ItemTag: TItemTag;
begin
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SearchIndex-' + GUIDToString(Id));
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', FixturePassword);
  Manager := FNotebook.Manager;

  Projects := TProjectsModel.Create(Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Project := Projects.AddProject('P1', '', FNotebook.Principal);
  finally
    Projects.Free;
  end;
  FProjectId := Project.Id;

  ValueType := TValueType.Create;
  ValueType.Symbol := 'd';
  ValueType.Title := 'Thickness';
  ValueType.Units := 'nm';
  ValueType.CreatedDate := Now;
  ValueType.CreatedBy := FNotebook.Principal.Id;
  Manager.Save(ValueType);
  MdType := TFileType.Create;
  MdType.Ext := '.md';
  MdType.CreatedDate := Now;
  Manager.Save(MdType);
  PdfType := TFileType.Create;
  PdfType.Ext := '.pdf';
  PdfType.CreatedDate := Now;
  Manager.Save(PdfType);
  Manager.Flush;

  Item1 := TItem.Create;
  Item1.Title := 'Mo/Si multilayer';
  Item1.Description := StringOfChar('x', 2600);
  Item1.Properties := 'substrate: float glass';
  Item1.ProjectID := Project.Id;
  Item1.Type_ := TItemType.Specimen;
  Item1.Level := TItemLevel.Item;
  Item1.CreatedBy := FNotebook.Principal.Id;
  Item1.CreatedDate := Now;

  Protocol := TProtocol.Create;
  Protocol.Title := 'Deposition run';
  Protocol.FormData := '{"substrate":"Si wafer"}';
  Protocol.ValidationStatus := vsDraft;
  Protocol.CreatedDate := Now;
  Item1.Entries.Add(Protocol);

  Value1 := unit_Item.TValue.Create;
  Value1.ValueType := ValueType;
  Value1.Value := 3.5;
  Value1.Description := 'period thickness';
  Value1.CreatedDate := Now;
  Value1.Item := Item1;
  Item1.Values.Add(Value1);

  MdFile := unit_Item.TFile.Create;
  MdFile.FileType := MdType;
  MdFile.Title := 'notes';
  MdFile.Hash := 'x';
  MdFile.CreatedDate := Now;
  MdFile.Item := Item1;
  Item1.Files.Add(MdFile);

  PdfFile := unit_Item.TFile.Create;
  PdfFile.FileType := PdfType;
  PdfFile.Title := 'paper';
  PdfFile.Hash := 'x';
  PdfFile.CreatedDate := Now;
  PdfFile.Item := Item1;
  Item1.Files.Add(PdfFile);
  Manager.Save(Item1);

  Item2 := TItem.Create;
  Item2.Title := 'Discarded sample';
  Item2.ProjectID := Project.Id;
  Item2.Type_ := TItemType.Specimen;
  Item2.Level := TItemLevel.Item;
  Item2.CreatedBy := FNotebook.Principal.Id;
  Item2.CreatedDate := Now;
  Item2.IsDeleted := True;
  Item2.DeletedDate := Now;
  Value2 := unit_Item.TValue.Create;
  Value2.ValueType := ValueType;
  Value2.Value := 1;
  Value2.Description := 'hidden value';
  Value2.CreatedDate := Now;
  Value2.Item := Item2;
  Item2.Values.Add(Value2);
  Manager.Save(Item2);

  Tag := TTag.Create;
  Tag.Name := 'XRR';
  Tag.CreatedBy := FNotebook.Principal.Id;
  Tag.CreatedDate := Now;
  Manager.Save(Tag);
  Manager.Flush;
  ItemTag := TItemTag.Create;
  ItemTag.ItemId := Item1.Id;
  ItemTag.TagId := Tag.Id;
  ItemTag.CreatedDate := Now;
  Manager.Save(ItemTag);
  Manager.Flush;

  FItem1 := Item1.Id;
  FItem2 := Item2.Id;
  FEntryId := Protocol.Id;
  FValueId := Value1.Id;
  FMdId := MdFile.Id;
  FPdfId := PdfFile.Id;
  FMdPath := AttachmentRelativePath(Project.FileFolder, Item1.FolderName, MdFile.FullName);
  FNotebook.Storage.WriteBytes(FMdPath, TEncoding.UTF8.GetBytes(MdContent));
  FNotebook.Storage.WriteBytes(AttachmentRelativePath(Project.FileFolder,
    Item1.FolderName, PdfFile.FullName), TEncoding.UTF8.GetBytes('# not indexed'));

  FProvider := TStagedSource.Create(TNotebookDocumentProvider.Create(Manager),
    FNotebook.Storage, TPath.Combine(FRoot, 'staged.sqlite'));
end;

procedure TNotebookFixture.FreeNotebook;
begin
  FProvider := nil;
  FreeAndNil(FNotebook);
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TDocumentProviderTests.Setup;
begin
  BuildNotebook;
end;

procedure TDocumentProviderTests.TearDown;
begin
  FreeNotebook;
end;

function TDocumentProviderTests.Read: TSearchPassages;
begin
  Result := FProvider.ReadSnapshot(nil).Passages;
end;

function TDocumentProviderTests.IndexOf(const Passages: TSearchPassages;
  const Key: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Passages) do
    if Passages[I].Key = Key then Exit(I);
  Result := -1;
end;

function TDocumentProviderTests.Has(const Passages: TSearchPassages;
  const Key: string): Boolean;
begin
  Result := IndexOf(Passages, Key) >= 0;
end;

function TDocumentProviderTests.MaxAuditId: Int64;
var
  Rows: TList<TAuditLog>;
  Row: TAuditLog;
begin
  Result := 0;
  Rows := FNotebook.Manager.Find<TAuditLog>.List;
  try
    for Row in Rows do
      if Row.Id > Result then Result := Row.Id;
  finally
    Rows.Free;
  end;
end;

procedure TDocumentProviderTests.ReadsAllFieldKinds;
var
  Passages: TSearchPassages;
  Keys: TArray<string>;
  Key: string;
  Index: Integer;
begin
  Passages := Read;
  Keys := [
    Format('item:%d:title#0', [FItem1]),
    Format('item:%d:description#0', [FItem1]),
    Format('item:%d:properties#0', [FItem1]),
    Format('item:%d:tags#0', [FItem1]),
    Format('entry:%d:title#0', [FEntryId]),
    Format('entry:%d:form#0', [FEntryId]),
    Format('value:%d:description#0', [FValueId]),
    Format('file:%d:name#0', [FMdId]),
    Format('file:%d:text#0', [FMdId])];
  for Key in Keys do
  begin
    Index := IndexOf(Passages, Key);
    Assert.IsTrue(Index >= 0, 'missing ' + Key);
    Assert.AreEqual(FProjectId, Passages[Index].ProjectId, Key);
    Assert.AreEqual(FItem1, Passages[Index].ItemId, Key);
  end;
  Assert.AreEqual('Mo/Si multilayer', Passages[IndexOf(Passages, Format('item:%d:title#0', [FItem1]))].Text);
  Assert.AreEqual('XRR', Passages[IndexOf(Passages, Format('item:%d:tags#0', [FItem1]))].Text);
  Assert.AreEqual('{"substrate":"Si wafer"}',
    Passages[IndexOf(Passages, Format('entry:%d:form#0', [FEntryId]))].Text);
  Assert.AreEqual('period thickness',
    Passages[IndexOf(Passages, Format('value:%d:description#0', [FValueId]))].Text);
  Index := IndexOf(Passages, Format('file:%d:name#0', [FMdId]));
  Assert.AreEqual(FMdId, Passages[Index].FileId);
  Assert.AreEqual(PassageHash(Passages[Index].Text), Passages[Index].ContentHash);
  Assert.IsFalse(Has(Passages, Format('item:%d:description#0', [FItem2])));
end;

procedure TDocumentProviderTests.LongDescriptionChunked;
var
  Passages: TSearchPassages;
begin
  Passages := Read;
  Assert.IsTrue(Has(Passages, Format('item:%d:description#0', [FItem1])));
  Assert.IsTrue(Has(Passages, Format('item:%d:description#1', [FItem1])));
  Assert.IsTrue(Has(Passages, Format('item:%d:description#2', [FItem1])));
  Assert.IsFalse(Has(Passages, Format('item:%d:description#3', [FItem1])));
end;

procedure TDocumentProviderTests.DeletedItemExcluded;
var
  Passage: TSearchPassage;
begin
  for Passage in Read do
  begin
    Assert.AreNotEqual(FItem2, Passage.ItemId, Passage.Key);
    Assert.IsFalse(Passage.Key.Contains('hidden'), Passage.Key);
    Assert.AreNotEqual('hidden value', Passage.Text, Passage.Key);
  end;
end;

procedure TDocumentProviderTests.PdfHasNameOnly;
var
  Passages: TSearchPassages;
begin
  Passages := Read;
  Assert.IsTrue(Has(Passages, Format('file:%d:name#0', [FPdfId])));
  Assert.IsFalse(Has(Passages, Format('file:%d:text#0', [FPdfId])));
end;

procedure TDocumentProviderTests.MissingAttachmentBytesSkipped;
var
  Passages: TSearchPassages;
begin
  FNotebook.Storage.DeleteFile(FMdPath);
  Passages := Read;
  Assert.IsTrue(Has(Passages, Format('file:%d:name#0', [FMdId])));
  Assert.IsFalse(Has(Passages, Format('file:%d:text#0', [FMdId])));
end;

procedure TDocumentProviderTests.ProviderEmitsFileRequestsAndReadsNoBytes;
var
  Provider: ISearchDocumentSource;
  Snapshot: TSearchSnapshot;
  Request: TFileTextRequest;
  Passage: TSearchPassage;
  FoundMd, FoundPdf: Boolean;
begin
  Provider := TNotebookDocumentProvider.Create(FNotebook.Manager);
  FNotebook.Storage.DeleteFile(FMdPath);
  Snapshot := Provider.ReadSnapshot(nil);
  FoundMd := False;
  FoundPdf := False;
  for Request in Snapshot.Files do
  begin
    Assert.AreEqual(FItem1, Request.ItemId);
    Assert.AreEqual(FProjectId, Request.ProjectId);
    if Request.FileId = FMdId then
    begin
      FoundMd := True;
      Assert.AreEqual('.md', LowerCase(Request.Ext));
      Assert.AreEqual(FMdPath, Request.RelativePath);
    end
    else if Request.FileId = FPdfId then
      FoundPdf := True;
  end;
  Assert.IsTrue(FoundMd, 'md request');
  Assert.IsTrue(FoundPdf, 'pdf request');
  Assert.AreEqual<NativeInt>(2, Length(Snapshot.Files));
  for Passage in Snapshot.Passages do
    Assert.AreNotEqual(Ord(pfFileText), Ord(Passage.Field), Passage.Key);
end;

procedure TDocumentProviderTests.TextIsFolded;
var
  Passages: TSearchPassages;
  Text: string;
begin
  Passages := Read;
  Text := Passages[IndexOf(Passages, Format('file:%d:text#0', [FMdId]))].Text;
  Assert.IsTrue(Text.Contains('пленка'), 'folded text');
  Assert.IsFalse(Text.Contains('плёнка'), 'unfolded text');
end;

procedure TDocumentProviderTests.NonUtf8TextFallsBackToAnsi;
var
  Passages: TSearchPassages;
  Head, Tail, Bytes: TBytes;
  Index: Integer;
begin
  Head := TEncoding.UTF8.GetBytes('temp 25 ');
  Tail := TEncoding.UTF8.GetBytes('C in vacuum');
  SetLength(Bytes, Length(Head) + 1 + Length(Tail));
  Move(Head[0], Bytes[0], Length(Head));
  Bytes[Length(Head)] := $B0;
  Move(Tail[0], Bytes[Length(Head) + 1], Length(Tail));
  FNotebook.Storage.WriteBytes(FMdPath, Bytes);
  Passages := Read;
  Index := IndexOf(Passages, Format('file:%d:text#0', [FMdId]));
  Assert.IsTrue(Index >= 0, 'text passage present');
  Assert.IsTrue(Passages[Index].Text.Contains('temp 25'), 'text content');
  Assert.IsTrue(Passages[Index].Text.Contains('in vacuum'), 'text tail');
end;

procedure TDocumentProviderTests.IsItemLiveReportsProjectAndBin;
var
  ProjectId: Integer;
begin
  Assert.IsTrue(FProvider.IsItemLive(FItem1, ProjectId));
  Assert.AreEqual(FProjectId, ProjectId);
  Assert.IsFalse(FProvider.IsItemLive(FItem2, ProjectId));
  Assert.IsFalse(FProvider.IsItemLive(FItem2 + 1000, ProjectId));
end;

procedure TDocumentProviderTests.CancellationStopsReading;
begin
  Assert.WillRaise(
    procedure
    begin
      FProvider.ReadSnapshot(function: Boolean begin Result := True; end);
    end, EOperationCancelled);
end;

procedure TDocumentProviderTests.ProviderDoesNotWrite;
var
  AuditBefore: Int64;
  TimeBefore: TDateTime;
  Passages: TSearchPassages;
begin
  AuditBefore := MaxAuditId;
  TimeBefore := System.IOUtils.TFile.GetLastWriteTimeUtc(FNotebook.DatabasePath);
  Passages := Read;
  Assert.IsTrue(Length(Passages) > 0);
  Assert.AreEqual(AuditBefore, MaxAuditId);
  Assert.AreEqual(TimeBefore, System.IOUtils.TFile.GetLastWriteTimeUtc(FNotebook.DatabasePath));
end;

procedure TSearchIndexerTests.Setup;
begin
  BuildNotebook;
  FStorePath := TPath.Combine(FRoot, 'search.sqlite');
  OpenIndexer('fake-1');
end;

procedure TSearchIndexerTests.TearDown;
begin
  FreeAndNil(FIndexer);
  FEmbedder := nil;
  FFake := nil;
  FreeAndNil(FStore);
  FreeNotebook;
end;

procedure TSearchIndexerTests.OpenIndexer(const Identity: string);
begin
  FreeAndNil(FIndexer);
  FreeAndNil(FStore);
  FFake := TFakeEmbedder.Create(Identity);
  FEmbedder := FFake;
  FStore := TSearchIndexStore.Open(FStorePath, Identity, StoreDim);
  FIndexer := TSearchIndexer.Create(FProvider, FStore, FEmbedder);
end;

function TSearchIndexerTests.SourceCount: Integer;
begin
  Result := Length(FProvider.ReadSnapshot(nil).Passages);
end;

function TSearchIndexerTests.CatalogKeys: TArray<string>;
var
  Catalog: TDictionary<string, TStoredPassage>;
begin
  Catalog := FStore.ReadCatalog;
  try
    Result := Catalog.Keys.ToArray;
  finally
    Catalog.Free;
  end;
end;

function TSearchIndexerTests.CatalogHas(const Key: string): Boolean;
var
  Catalog: TDictionary<string, TStoredPassage>;
begin
  Catalog := FStore.ReadCatalog;
  try
    Result := Catalog.ContainsKey(Key);
  finally
    Catalog.Free;
  end;
end;

function TSearchIndexerTests.CatalogHasItem(ItemId: Integer): Boolean;
var
  Catalog: TDictionary<string, TStoredPassage>;
  Row: TStoredPassage;
begin
  Result := False;
  Catalog := FStore.ReadCatalog;
  try
    for Row in Catalog.Values do
      if Row.ItemId = ItemId then Exit(True);
  finally
    Catalog.Free;
  end;
end;

function TSearchIndexerTests.ItemById(Id: Integer): TItem;
begin
  Result := FNotebook.Manager.Find<TItem>(Id);
end;

procedure TSearchIndexerTests.ProgressReportsPendingTotalFirst;
var
  Calls, FirstDone, FirstTotal, LastDone, LastTotal: Integer;
begin
  Calls := 0;
  FirstDone := -1;
  FirstTotal := -1;
  LastDone := -1;
  LastTotal := -1;
  FIndexer.Sync(nil,
    procedure(Done, Total: Integer)
    begin
      if Calls = 0 then
      begin
        FirstDone := Done;
        FirstTotal := Total;
      end;
      Inc(Calls);
      LastDone := Done;
      LastTotal := Total;
    end);
  Assert.AreEqual(0, FirstDone);
  Assert.AreEqual(SourceCount, FirstTotal);
  Assert.AreEqual(SourceCount, LastDone);
  Assert.AreEqual(SourceCount, LastTotal);
  Calls := 0;
  FIndexer.Sync(nil,
    procedure(Done, Total: Integer)
    begin
      Inc(Calls);
    end);
  Assert.AreEqual(0, Calls, 'no progress when nothing is pending');
end;

procedure TSearchIndexerTests.FirstSyncAddsAll;
var
  Stats: TSyncStats;
  Total: Integer;
begin
  Total := SourceCount;
  Assert.IsTrue(Total > 0);
  Stats := FIndexer.Sync;
  Assert.AreEqual(Total, Stats.Added);
  Assert.AreEqual(0, Stats.Changed + Stats.Moved + Stats.Removed + Stats.Unchanged);
  Assert.AreEqual(Total, FFake.Encoded);
  Assert.AreEqual<NativeInt>(Total, Length(CatalogKeys));
end;

procedure TSearchIndexerTests.SecondSyncEmbedsNothing;
var
  Stats: TSyncStats;
  Total: Integer;
begin
  Total := SourceCount;
  FIndexer.Sync;
  FFake.Encoded := 0;
  Stats := FIndexer.Sync;
  Assert.AreEqual(Total, Stats.Unchanged);
  Assert.AreEqual(0, Stats.Added + Stats.Changed + Stats.Moved + Stats.Removed);
  Assert.AreEqual(0, FFake.Encoded);
end;

procedure TSearchIndexerTests.EditedDescriptionReembedsOnlyIt;
var
  Item: TItem;
  Text: string;
  Stats: TSyncStats;
begin
  FIndexer.Sync;
  FFake.Encoded := 0;
  Item := ItemById(FItem1);
  Text := Item.Description;
  Text[1500] := 'y';
  Item.Description := Text;
  FNotebook.Manager.Flush;
  Stats := FIndexer.Sync;
  Assert.AreEqual(1, Stats.Changed);
  Assert.AreEqual(0, Stats.Added + Stats.Removed + Stats.Moved);
  Assert.AreEqual(1, FFake.Encoded);
end;

procedure TSearchIndexerTests.TagAssignWithoutAuditIsSeen;
var
  Tags: TTagModel;
  Tag: TTag;
  Stats: TSyncStats;
begin
  FIndexer.Sync;
  FFake.Encoded := 0;
  Tags := TTagModel.Create(FNotebook.Manager);
  try
    Tag := Tags.AddTag('Extra', '#000000', FNotebook.Principal.Id);
    Tags.AssignTag(FItem1, Tag.Id);
  finally
    Tags.Free;
  end;
  Stats := FIndexer.Sync;
  Assert.AreEqual(1, Stats.Changed);
  Assert.AreEqual(0, Stats.Added + Stats.Removed + Stats.Moved);
  Assert.AreEqual(1, FFake.Encoded);
  Assert.IsTrue(CatalogHas(Format('item:%d:tags#0', [FItem1])));
  Assert.IsTrue(FStore.PassageText(Format('item:%d:tags#0', [FItem1])).Contains('Extra'));
end;

procedure TSearchIndexerTests.RecycledItemRemoved;
var
  Items: TItemModel;
  Stats: TSyncStats;
begin
  FIndexer.Sync;
  Assert.IsTrue(CatalogHasItem(FItem1));
  FFake.Encoded := 0;
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Items.SoftDeleteItemTree(ItemById(FItem1), FNotebook.Principal.Id));
  finally
    Items.Free;
  end;
  Stats := FIndexer.Sync;
  Assert.IsTrue(Stats.Removed > 0);
  Assert.AreEqual(0, Stats.Added + Stats.Changed);
  Assert.AreEqual(0, FFake.Encoded);
  Assert.IsFalse(CatalogHasItem(FItem1));
end;

procedure TSearchIndexerTests.ProjectMoveUpdatesScope;
var
  Projects: TProjectsModel;
  Items: TItemModel;
  Destination: TProject;
  Relocator: IFileRelocator;
  Index: TExactVectorIndex;
  Query: TArray<Single>;
  Stats: TSyncStats;
  I: Integer;
begin
  FIndexer.Sync;
  FFake.Encoded := 0;
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Destination := Projects.AddProject('P2', '', FNotebook.Principal);
  finally
    Projects.Free;
  end;
  Relocator := TNotebookFileRelocator.Create(FNotebook.Storage);
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Items.MoveProc(ItemById(FItem1), Destination.Id, 0, FNotebook.Principal.Id, Relocator));
  finally
    Items.Free;
  end;
  Stats := FIndexer.Sync;
  Assert.IsTrue(Stats.Moved > 0);
  Assert.AreEqual(0, Stats.Added + Stats.Changed + Stats.Removed);
  Assert.AreEqual(0, FFake.Encoded);
  SetLength(Query, StoreDim);
  for I := 0 to StoreDim - 1 do
    Query[I] := 1 / Sqrt(StoreDim);
  Index := TExactVectorIndex.Create(StoreDim);
  try
    FStore.LoadVectors(Index);
    Assert.AreEqual<NativeInt>(Stats.Moved, Length(Index.Search(Query, 1000, [IntToStr(Destination.Id)], Default(TItemFilter))));
    Assert.AreEqual<NativeInt>(0, Length(Index.Search(Query, 1000, [IntToStr(FProjectId)], Default(TItemFilter))));
  finally
    Index.Free;
  end;
end;

procedure TSearchIndexerTests.CancelMidSyncThenResume;
var
  Item: TItem;
  Stats: TSyncStats;
  Keys: TArray<string>;
  Cancelled: TCancelCheck;
  Raised: Boolean;
  N, I: Integer;
begin
  N := SourceCount;
  for I := N + 1 to 70 do
  begin
    Item := TItem.Create;
    Item.Title := 'Bulk ' + IntToStr(I);
    Item.ProjectID := FProjectId;
    Item.Type_ := TItemType.Specimen;
    Item.Level := TItemLevel.Item;
    Item.CreatedBy := FNotebook.Principal.Id;
    Item.CreatedDate := Now;
    FNotebook.Manager.Save(Item);
    FNotebook.Manager.Flush;
  end;
  Assert.AreEqual(70, SourceCount);
  Cancelled := function: Boolean
    begin
      Result := FFake.Encoded >= SyncEmbedBatch;
    end;
  Raised := False;
  try
    FIndexer.Sync(Cancelled);
  except
    on EOperationCancelled do Raised := True;
  end;
  Assert.IsTrue(Raised, 'cancellation raised');
  Assert.AreEqual<NativeInt>(SyncEmbedBatch, Length(CatalogKeys));
  Stats := FIndexer.Sync;
  Assert.AreEqual(70 - SyncEmbedBatch, Stats.Added);
  Assert.AreEqual(SyncEmbedBatch, Stats.Unchanged);
  Keys := CatalogKeys;
  Assert.AreEqual<NativeInt>(70, Length(Keys));
end;

procedure TSearchIndexerTests.IdentityChangeRebuilds;
var
  Total: Integer;
  Stats: TSyncStats;
begin
  Total := SourceCount;
  FIndexer.Sync;
  OpenIndexer('fake-2');
  Assert.IsTrue(FStore.WasReset);
  Stats := FIndexer.Sync;
  Assert.AreEqual(Total, Stats.Added);
  Assert.AreEqual(Total, FFake.Encoded);
end;

procedure TSearchFixture.OpenSearch(const Embedder: ITextEmbedder);
begin
  CloseSearch;
  FEmbedder := Embedder;
  FStore := TSearchIndexStore.Open(TPath.Combine(FRoot, 'search.sqlite'), Embedder.Identity,
    Embedder.Dimension);
  FIndexer := TSearchIndexer.Create(FProvider, FStore, Embedder);
  FSearcher := THybridSearcher.Create(FStore, Embedder, FProvider);
end;

procedure TSearchFixture.CloseSearch;
begin
  FreeAndNil(FSearcher);
  FreeAndNil(FIndexer);
  FreeAndNil(FStore);
  FEmbedder := nil;
end;

procedure TSearchFixture.SyncAndReload;
begin
  FIndexer.Sync;
  FSearcher.Reload;
end;

function TSearchFixture.VisibleIds: TArray<Integer>;
var
  Visible: TDictionary<Integer, Boolean>;
begin
  Visible := FNotebook.AccessPolicy.VisibleProjectIds(FNotebook.Manager, FNotebook.Principal);
  try
    Result := Visible.Keys.ToArray;
  finally
    Visible.Free;
  end;
end;

function TSearchFixture.AddItem(const Title, FormData: string; ProjectId: Integer): TItem;
var
  Protocol: TProtocol;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.ProjectID := ProjectId;
  Result.Type_ := TItemType.Specimen;
  Result.Level := TItemLevel.Item;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  if FormData <> '' then
  begin
    Protocol := TProtocol.Create;
    Protocol.Title := 'Run notes';
    Protocol.FormData := FormData;
    Protocol.ValidationStatus := vsDraft;
    Protocol.CreatedDate := Now;
    Result.Entries.Add(Protocol);
  end;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
end;

function TSearchFixture.AddForeignProject: Integer;
var
  Owner: TUser;
  Projects: TProjectsModel;
begin
  Owner := TUser.Create;
  Owner.Username := 'other-owner';
  Owner.Password := 'unused';
  Owner.FirstName := 'Other';
  Owner.LastName := 'Owner';
  Owner.Role := dbUser;
  Owner.CreatedDate := Now;
  Owner.IsArchived := True;
  FNotebook.Manager.Save(Owner);
  FNotebook.Manager.Flush;
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Result := Projects.AddProject('Other owner project', '', Owner).Id;
  finally
    Projects.Free;
  end;
end;

function TSearchFixture.HitFor(const Hits: TArray<THybridGroup>; ItemId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Hits) do
    if Hits[I].ItemId = ItemId then Exit(I);
  Result := -1;
end;

function TSearchFixture.HasItem(const Hits: TArray<THybridGroup>; ItemId: Integer): Boolean;
begin
  Result := HitFor(Hits, ItemId) >= 0;
end;

procedure THybridSearchTests.Setup;
begin
  BuildNotebook;
  OpenSearch(TFakeEmbedder.Create('fake-hybrid'));
end;

procedure THybridSearchTests.TearDown;
begin
  CloseSearch;
  FreeNotebook;
end;

procedure THybridSearchTests.OtherOwnerProjectNeverReturned;
const
  WordQuery = 'Zirconium';
  TrigramQuery = 'conium ox';
  VectorQuery = 'Zirconium oxide foreign sample';
var
  ForeignProject: Integer;
  Foreign: TItem;
  Mine, Both: TArray<Integer>;
  Query: string;
  Hits: TArray<THybridGroup>;
  Hit: THybridGroup;
  Pos: Integer;
begin
  ForeignProject := AddForeignProject;
  Foreign := AddItem('Zirconium oxide foreign sample', '', ForeignProject);
  SyncAndReload;
  Mine := VisibleIds;
  Assert.AreEqual<NativeInt>(1, Length(Mine));
  Assert.AreEqual(FProjectId, Mine[0]);
  Both := [FProjectId, ForeignProject];

  for Query in [WordQuery, TrigramQuery, VectorQuery] do
  begin
    Hits := FSearcher.Search(Query, Mine, 50, THybridSearchOptions.Default);
    Assert.IsFalse(HasItem(Hits, Foreign.Id), 'foreign item returned for ' + Query);
    for Hit in Hits do
      Assert.AreNotEqual(ForeignProject, Hit.ProjectId, 'foreign project returned for ' + Query);
  end;

  Hits := FSearcher.Search(WordQuery, Both, 50, THybridSearchOptions.Default);
  Pos := HitFor(Hits, Foreign.Id);
  Assert.IsTrue(Pos >= 0, 'control: foreign item found by word when its project is eligible');
  Assert.IsTrue(hsWords in Hits[Pos].Sources);
  Hits := FSearcher.Search(TrigramQuery, Both, 50, THybridSearchOptions.Default);
  Pos := HitFor(Hits, Foreign.Id);
  Assert.IsTrue(Pos >= 0, 'control: foreign item found by trigram when its project is eligible');
  Assert.IsTrue(hsTrigram in Hits[Pos].Sources);
  Hits := FSearcher.Search(VectorQuery, Both, 50, THybridSearchOptions.Default);
  Pos := HitFor(Hits, Foreign.Id);
  Assert.IsTrue(Pos >= 0, 'control: foreign item found by vector when its project is eligible');
  Assert.IsTrue(hsVector in Hits[Pos].Sources);
  Assert.AreEqual(ForeignProject, Hits[Pos].ProjectId);
end;

procedure THybridSearchTests.EmptyVisibleSetGivesNothing;
begin
  SyncAndReload;
  Assert.IsTrue(Length(FSearcher.Search('Mo/Si multilayer', VisibleIds, 10, THybridSearchOptions.Default)) > 0, 'control');
  Assert.AreEqual<NativeInt>(0, Length(FSearcher.Search('Mo/Si multilayer', [], 10, THybridSearchOptions.Default)));
  Assert.AreEqual<NativeInt>(0, Length(FSearcher.Search('Mo/Si multilayer', [FProjectId + 1000], 10, THybridSearchOptions.Default)));
end;

procedure THybridSearchTests.StaleHitDroppedBeforeSync;
var
  Items: TItemModel;
  Hits: TArray<THybridGroup>;
begin
  SyncAndReload;
  Hits := FSearcher.Search('Mo/Si multilayer', VisibleIds, 20, THybridSearchOptions.Default);
  Assert.IsTrue(HasItem(Hits, FItem1), 'control: item found before it is recycled');
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Items.SoftDeleteItemTree(FNotebook.Manager.Find<TItem>(FItem1), FNotebook.Principal.Id));
  finally
    Items.Free;
  end;
  Hits := FSearcher.Search('Mo/Si multilayer', VisibleIds, 20, THybridSearchOptions.Default);
  Assert.IsFalse(HasItem(Hits, FItem1));
  Assert.AreEqual<NativeInt>(0, Length(Hits));
end;

procedure THybridSearchTests.MovedToInvisibleProjectDropped;
var
  ForeignProject: Integer;
  Item: TItem;
  Hits: TArray<THybridGroup>;
  Pos: Integer;
begin
  SyncAndReload;
  Hits := FSearcher.Search('Mo/Si multilayer', VisibleIds, 20, THybridSearchOptions.Default);
  Assert.IsTrue(HasItem(Hits, FItem1), 'control: item found in its own project');
  ForeignProject := AddForeignProject;
  Item := FNotebook.Manager.Find<TItem>(FItem1);
  Item.ProjectID := ForeignProject;
  FNotebook.Manager.Flush;
  Hits := FSearcher.Search('Mo/Si multilayer', VisibleIds, 20, THybridSearchOptions.Default);
  Assert.IsFalse(HasItem(Hits, FItem1));
  Hits := FSearcher.Search('Mo/Si multilayer', [FProjectId, ForeignProject], 20, THybridSearchOptions.Default);
  Pos := HitFor(Hits, FItem1);
  Assert.IsTrue(Pos >= 0, 'control: moved item found when its live project is eligible');
  Assert.AreEqual(ForeignProject, Hits[Pos].ProjectId, 'live project is reported');
end;

procedure THybridSearchTests.ShortQueryEmpty;
var
  Query: string;
  Hit: THybridGroup;
begin
  SyncAndReload;
  for Query in ['a', ' ', '', '  a  '] do
    Assert.AreEqual<NativeInt>(0, Length(FSearcher.Search(Query, VisibleIds, 10, THybridSearchOptions.Default)), '[' + Query + ']');
  Assert.IsTrue(Length(FSearcher.Search('Mo', VisibleIds, 10, THybridSearchOptions.Default)) > 0, 'two characters search');
  for Hit in FSearcher.Search('Mo', VisibleIds, 10, THybridSearchOptions.Default) do
    Assert.IsFalse(hsTrigram in Hit.Sources, 'trigram list needs three characters');
end;

procedure TRealModelSearchTests.SetupFixture;
begin
  FModel := TE5TextEmbedder.Create(TE5EmbedderConfig.FromArtifactRoot(TE5EmbedderConfig.DefaultArtifactRoot));
end;

procedure TRealModelSearchTests.TearDownFixture;
begin
  FModel := nil;
end;

procedure TRealModelSearchTests.Setup;
begin
  BuildNotebook;
  OpenSearch(FModel);
end;

procedure TRealModelSearchTests.TearDown;
begin
  CloseSearch;
  FreeNotebook;
end;

procedure TRealModelSearchTests.IdentifierFoundByTrigram;
var
  Item17, Item31: TItem;
  Hits: TArray<THybridGroup>;
  Pos17, Pos31: Integer;
begin
  AddItem('Annealing furnace calibration', '', FProjectId);
  AddItem('SMP-2023-017', '', FProjectId);
  AddItem('SMP-2024-117', '', FProjectId);
  Item31 := AddItem('SMP-2024-031', '', FProjectId);
  Item17 := AddItem('SMP-2024-017', '', FProjectId);
  SyncAndReload;
  Hits := FSearcher.Search('SMP-2024-017', VisibleIds, 10, THybridSearchOptions.Default);
  Assert.IsTrue(Length(Hits) > 0);
  Assert.AreEqual(Item17.Id, Hits[0].ItemId, 'first hit is the item with the identifier');
  Assert.IsTrue(Hits[0].Passages[0].Field = pfItemTitle);
  Assert.IsTrue(hsTrigram in Hits[0].Sources, 'identifier is found by the trigram list');
  Pos17 := HitFor(Hits, Item17.Id);
  Pos31 := HitFor(Hits, Item31.Id);
  Assert.IsTrue((Pos31 < 0) or (Pos17 < Pos31), 'SMP-2024-017 ranks ahead of SMP-2024-031');
end;

procedure TRealModelSearchTests.CrossLingualFindsProtocolForm;
var
  Item: TItem;
  Hits: TArray<THybridGroup>;
  I: Integer;
  Found: Boolean;
begin
  AddItem('Annealing furnace calibration', '{"temperature":"450 C","atmosphere":"nitrogen"}', FProjectId);
  AddItem('Ion beam sputtering target', '{"target":"molybdenum","gas":"argon"}', FProjectId);
  AddItem('Reflectometer alignment', '', FProjectId);
  Item := AddItem('Surface preparation log', '{"substrate":"кремниевая пластина (silicon wafer)"}', FProjectId);
  SyncAndReload;
  Hits := FSearcher.Search('подложка кремниевая пластина', VisibleIds, 10, THybridSearchOptions.Default);
  Assert.IsTrue(Length(Hits) >= 3);
  Found := False;
  for I := 0 to 2 do
    if (Hits[I].Passages[0].Field = pfProtocolForm) and (Hits[I].ItemId = Item.Id) then
      Found := True;
  Assert.IsTrue(Found, 'the protocol form passage is in the top three');
end;

procedure TSearchIndexerTests.SnapshotSourceFeedsIndexer;
var
  Expected, Actual: TDictionary<string, string>;
  Other: TSearchIndexStore;
  Indexer: TSearchIndexer;
  Catalog: TDictionary<string, TStoredPassage>;
  Pair: TPair<string, TStoredPassage>;
  Hash: TPair<string, string>;
  Snapshot: ISearchDocumentSource;
begin
  FIndexer.Sync;
  Expected := TDictionary<string, string>.Create;
  Actual := TDictionary<string, string>.Create;
  try
    Catalog := FStore.ReadCatalog;
    try
      for Pair in Catalog do
        Expected.Add(Pair.Key, Pair.Value.ContentHash);
    finally
      Catalog.Free;
    end;
    Assert.IsTrue(Expected.Count > 0);
    Snapshot := TPassageSnapshotSource.Create(FProvider.ReadSnapshot(nil).Passages);
    Other := TSearchIndexStore.Open(TPath.Combine(FRoot, 'snapshot.sqlite'), 'fake-1', StoreDim);
    try
      Indexer := TSearchIndexer.Create(Snapshot, Other, TFakeEmbedder.Create('fake-1'));
      try
        Indexer.Sync;
      finally
        Indexer.Free;
      end;
      Catalog := Other.ReadCatalog;
      try
        for Pair in Catalog do
          Actual.Add(Pair.Key, Pair.Value.ContentHash);
      finally
        Catalog.Free;
      end;
    finally
      Other.Free;
    end;
    Assert.AreEqual(Expected.Count, Actual.Count);
    for Hash in Expected do
    begin
      Assert.IsTrue(Actual.ContainsKey(Hash.Key), Hash.Key);
      Assert.AreEqual(Hash.Value, Actual[Hash.Key]);
    end;
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

procedure THybridSearchTests.LongQueryUsesTextLists;
var
  Fake: TFakeEmbedder;
  Item: TItem;
  Hits: TArray<THybridGroup>;
begin
  Fake := TFakeEmbedder.Create('fake-long');
  Fake.MaxQueryChars := 100;
  OpenSearch(Fake);
  Item := AddItem('Zirconium oxide film', '', FProjectId);
  SyncAndReload;
  Hits := FSearcher.Search('Zirconium ' + StringOfChar('q', 2000), VisibleIds, 10, THybridSearchOptions.Default);
  Assert.IsTrue(HasItem(Hits, Item.Id), 'item with the indexed word is found');
  Assert.IsTrue(Hits[HitFor(Hits, Item.Id)].Sources = [hsWords]);
end;

constructor TStagedSource.Create(const Inner: ISearchDocumentSource;
  const Storage: INotebookStorage; const StorePath: string);
begin
  inherited Create;
  FInner := Inner;
  FStore := TSearchIndexStore.Open(StorePath, 'staged-source', StoreDim);
  FRegistry := TTextExtractorRegistry.Create('');
  FStage := TFileTextStage.Create(FStore, FRegistry);
  FReader := TStorageFileReader.Create(Storage);
end;

destructor TStagedSource.Destroy;
begin
  FStage.Free;
  FRegistry.Free;
  FStore.Free;
  inherited;
end;

function TStagedSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Result := FInner.ReadSnapshot(Cancelled);
  Result.Passages := Result.Passages + FStage.BuildFilePassages(Result.Files, FReader, Cancelled, nil);
  Result.Files := nil;
end;

function TStagedSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  Result := FInner.IsItemLive(ItemId, ProjectId);
end;

procedure TStorageFileReaderTests.Setup;
begin
  BuildNotebook;
end;

procedure TStorageFileReaderTests.TearDown;
begin
  FreeNotebook;
end;

procedure TStorageFileReaderTests.StorageReaderFromWorkerThread;
const
  FileCount = 50;
  ThreadCount = 8;
var
  Expected: array of TBytes;
  Reader: IFileContentReader;
  Threads: array of TThread;
  Failures: Integer;
  I, J: Integer;

  function MakeThread(Offset: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        K, Index: Integer;
        Bytes: TBytes;
        Size: Int64;
      begin
        try
          for K := 0 to FileCount - 1 do
          begin
            Index := (K + Offset) mod FileCount;
            if not Reader.ReadFile('readerstress/f' + IntToStr(Index) + '.bin', 1 shl 20, Bytes, Size) or
              (Size <> Length(Expected[Index])) or (Length(Bytes) <> Size) or
              ((Size > 0) and not CompareMem(@Bytes[0], @Expected[Index][0], Size)) then
              TInterlocked.Increment(Failures);
          end;
        except
          TInterlocked.Increment(Failures);
        end;
      end);
    Result.FreeOnTerminate := False;
  end;

begin
  SetLength(Expected, FileCount);
  for I := 0 to FileCount - 1 do
  begin
    SetLength(Expected[I], 500 + I * 7);
    for J := 0 to High(Expected[I]) do
      Expected[I][J] := (I * 31 + J) mod 251;
    FNotebook.Storage.WriteBytes('readerstress/f' + IntToStr(I) + '.bin', Expected[I]);
  end;
  Reader := TStorageFileReader.Create(FNotebook.Storage);
  Failures := 0;
  SetLength(Threads, ThreadCount);
  for I := 0 to ThreadCount - 1 do
    Threads[I] := MakeThread(I * 7);
  for I := 0 to ThreadCount - 1 do
    Threads[I].Start;
  for I := 0 to ThreadCount - 1 do
  begin
    Threads[I].WaitFor;
    Threads[I].Free;
  end;
  Assert.AreEqual(0, Failures);
end;

procedure TStorageFileReaderTests.MissingAndOversizeFiles;
var
  Reader: IFileContentReader;
  Bytes: TBytes;
  Size: Int64;
  Data: TBytes;
  I: Integer;
begin
  SetLength(Data, 100);
  for I := 0 to High(Data) do
    Data[I] := I;
  FNotebook.Storage.WriteBytes('readerstress/known.bin', Data);
  Reader := TStorageFileReader.Create(FNotebook.Storage);
  Assert.IsFalse(Reader.ReadFile('readerstress/none.bin', 1000, Bytes, Size));
  Assert.IsTrue(Reader.ReadFile('readerstress/known.bin', 50, Bytes, Size));
  Assert.AreEqual<Int64>(100, Size);
  Assert.AreEqual<NativeInt>(0, Length(Bytes));
  Assert.IsTrue(Reader.ReadFile('readerstress/known.bin', 200, Bytes, Size));
  Assert.AreEqual<Int64>(100, Size);
  Assert.AreEqual<NativeInt>(100, Length(Bytes));
end;

procedure TStorageFileReaderTests.StampTracksSizeAndLastWrite;
var
  Reader: IFileContentReader;
  Size1, Size2, Write1, Write2: Int64;
begin
  FNotebook.Storage.WriteBytes('readerstress/stamp.bin', TBytes.Create(1, 2, 3));
  Reader := TStorageFileReader.Create(FNotebook.Storage);
  Assert.IsTrue(Reader.TryGetStamp('readerstress/stamp.bin', Size1, Write1));
  Assert.AreEqual<Int64>(3, Size1);
  Assert.IsTrue(Write1 <> 0);
  Assert.IsTrue(Reader.TryGetStamp('readerstress/stamp.bin', Size2, Write2));
  Assert.AreEqual(Write1, Write2);
  Assert.IsFalse(Reader.TryGetStamp('readerstress/none.bin', Size2, Write2));
  FNotebook.Storage.WriteBytes('readerstress/stamp.bin', TBytes.Create(1, 2, 3, 4));
  Assert.IsTrue(Reader.TryGetStamp('readerstress/stamp.bin', Size2, Write2));
  Assert.AreEqual<Int64>(4, Size2);
end;

initialization
  TDUnitX.RegisterTestFixture(TDocumentProviderTests);
  TDUnitX.RegisterTestFixture(TStorageFileReaderTests);
  TDUnitX.RegisterTestFixture(TSearchIndexerTests);
  TDUnitX.RegisterTestFixture(THybridSearchTests);
  TDUnitX.RegisterTestFixture(TRealModelSearchTests);

end.
