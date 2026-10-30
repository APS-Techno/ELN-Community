unit test_PassageContext;

interface

uses
  System.SysUtils, System.Generics.Collections, DUnitX.TestFramework,
  unit_TextEmbedder, unit_SearchPassages, unit_PassageContext, unit_SearchIndexStore,
  unit_SearchIndexer, unit_VectorSearch, test_SearchIndex, test_SearchDoubles;

type
  TRecordingEmbedder = class(TInterfacedObject, ITextEmbedder)
  private
    FInner: ITextEmbedder;
    FFake: TFakeEmbedder;
    FTexts: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function Identity: string;
    function Dimension: Integer;
    function MaxTokens: Integer;
    function EncodeQuery(const Text: string): TEmbedding;
    function EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
      const Cancelled: TCancelCheck = nil): TArray<TEmbedding>;
    property Texts: TList<string> read FTexts;
    property Fake: TFakeEmbedder read FFake;
  end;

  [TestFixture]
  TPassageContextProviderTests = class(TNotebookFixture)
  private
    FOtherProjectId: Integer;
    FActionItemId: Integer;
    FStorePath: string;
    procedure AddContextData;
    function Provider(Mode: TPassageContextMode): ISearchDocumentSource;
    function Read(Mode: TPassageContextMode): TSearchPassages;
    function ContextOf(const Passages: TSearchPassages; const Key: string): string;
    procedure RenameProject(const Title: string);
    function ProjectPassageCount(const Passages: TSearchPassages; ProjectId: Integer): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FullContextCoversProjectFolderPathKindActionAndParent;
    [Test]
    procedure TitlePassageHasNoItemTitleInContext;
    [Test]
    procedure ItemModeHasProjectAndItemTitleOnly;
    [Test]
    procedure NoneModeKeepsStage5Hash;
    [Test]
    procedure FileTextRequestCarriesItemContext;
    [Test]
    procedure ProjectRenameChangesOnlyThatProjectsHashes;
    [Test]
    procedure ProjectRenameReembedsOnlyThatProject;
    [Test]
    procedure RenameSyncStaysCancelable;
    [Test]
    procedure ContextIsNotInFullTextIndex;
    [Test]
    procedure ItemContextsCarryTheFullPartsInEveryMode;
    [Test]
    procedure StoredItemContextsSurviveReopenAndAreReplaced;
  end;

implementation

uses
  System.IOUtils, System.Hash, Aurelius.Engine.ObjectManager, unit_NotebookStorage,
  unit_LocalNotebook, unit_SearchDocumentProvider, unit_Project, unit_Item, unit_ItemTypes,
  unit_ActionType, unit_ProjectModel, Aurelius.Drivers.SQLite.Import;

constructor TRecordingEmbedder.Create;
begin
  inherited Create;
  FFake := TFakeEmbedder.Create('recording-1');
  FInner := FFake;
  FTexts := TList<string>.Create;
end;

destructor TRecordingEmbedder.Destroy;
begin
  FTexts.Free;
  inherited;
end;

function TRecordingEmbedder.Identity: string;
begin
  Result := FInner.Identity;
end;

function TRecordingEmbedder.Dimension: Integer;
begin
  Result := FInner.Dimension;
end;

function TRecordingEmbedder.MaxTokens: Integer;
begin
  Result := FInner.MaxTokens;
end;

function TRecordingEmbedder.EncodeQuery(const Text: string): TEmbedding;
begin
  Result := FInner.EncodeQuery(Text);
end;

function TRecordingEmbedder.EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
  const Cancelled: TCancelCheck): TArray<TEmbedding>;
var
  Text: string;
begin
  for Text in Texts do
    FTexts.Add(Text);
  Result := FInner.EncodePassages(Texts, Policy, Cancelled);
end;

procedure TPassageContextProviderTests.Setup;
begin
  BuildNotebook;
  FStorePath := TPath.Combine(FRoot, 'context.search.sqlite');
  AddContextData;
end;

procedure TPassageContextProviderTests.TearDown;
begin
  FreeNotebook;
end;

procedure TPassageContextProviderTests.AddContextData;
var
  Manager: TObjectManager;
  Projects: TProjectsModel;
  Other: TProject;
  Project: TProject;
  Top, Sub: TFolder;
  Action: TActionType;
  Proc, Step, Bulk, Filler: TItem;
  I: Integer;

  function NewItem(const Title, Description: string; ProjectId, FolderId: Integer;
    Level: TItemLevel): TItem;
  begin
    Result := TItem.Create;
    Result.Title := Title;
    Result.Description := Description;
    Result.ProjectID := ProjectId;
    Result.FolderID := FolderId;
    Result.Type_ := TItemType.Measurement;
    Result.Level := Level;
    Result.CreatedBy := FNotebook.Principal.Id;
    Result.CreatedDate := Now;
  end;

begin
  Manager := FNotebook.Manager;
  Projects := TProjectsModel.Create(Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Other := Projects.AddProject('Zirconia coatings', '', FNotebook.Principal);
  finally
    Projects.Free;
  end;
  FOtherProjectId := Other.Id;

  Project := Manager.Find<TProject>(FProjectId);
  Top := TFolder.Create;
  Top.Title := 'Annealing';
  Top.CreatedDate := Now;
  Top.CreatedBy := FNotebook.Principal.Id;
  Project.Folders.Add(Top);
  Manager.Flush;
  Sub := TFolder.Create;
  Sub.Title := 'W/B4C stacks';
  Sub.ParentFolderID := Top.Id;
  Sub.CreatedDate := Now;
  Sub.CreatedBy := FNotebook.Principal.Id;
  Project.Folders.Add(Sub);
  Manager.Flush;

  Action := TActionType.Create;
  Action.Title := 'X-ray reflectometry';
  Action.CreatedDate := Now;
  Manager.Save(Action);
  Manager.Flush;

  Proc := NewItem('XRR scan of MS-0417', 'scan description', FProjectId, Sub.Id, TItemLevel.Proc);
  Manager.Save(Proc);
  Manager.Flush;
  Step := NewItem('Reflectivity recording', 'curve recorded', FProjectId, Sub.Id, TItemLevel.Action);
  Step.Parent := Proc.Id;
  Step.ActionType := Action;
  Manager.Save(Step);
  Manager.Flush;
  FActionItemId := Step.Id;

  Bulk := NewItem('Bulk sample', 'dense oxide', FOtherProjectId, 0, TItemLevel.Item);
  Manager.Save(Bulk);
  for I := 1 to 40 do
  begin
    Filler := NewItem('Filler ' + IntToStr(I), 'filler text ' + IntToStr(I), FProjectId, 0,
      TItemLevel.Item);
    Manager.Save(Filler);
  end;
  Manager.Flush;
end;

function TPassageContextProviderTests.Provider(Mode: TPassageContextMode): ISearchDocumentSource;
begin
  Result := TNotebookDocumentProvider.Create(FNotebook.Manager, Mode);
end;

function TPassageContextProviderTests.Read(Mode: TPassageContextMode): TSearchPassages;
begin
  Result := Provider(Mode).ReadSnapshot(nil).Passages;
end;

function TPassageContextProviderTests.ContextOf(const Passages: TSearchPassages;
  const Key: string): string;
var
  Passage: TSearchPassage;
begin
  for Passage in Passages do
    if Passage.Key = Key then Exit(Passage.Context);
  raise Exception.Create('No passage ' + Key);
end;

procedure TPassageContextProviderTests.RenameProject(const Title: string);
var
  Project: TProject;
begin
  Project := FNotebook.Manager.Find<TProject>(FProjectId);
  Project.Title := Title;
  FNotebook.Manager.Flush;
end;

function TPassageContextProviderTests.ProjectPassageCount(const Passages: TSearchPassages;
  ProjectId: Integer): Integer;
var
  Passage: TSearchPassage;
begin
  Result := 0;
  for Passage in Passages do
    if Passage.ProjectId = ProjectId then Inc(Result);
end;

procedure TPassageContextProviderTests.FullContextCoversProjectFolderPathKindActionAndParent;
begin
  Assert.AreEqual(
    'P1 > Annealing > W/B4C stacks | Item: Reflectivity recording | Measurement | ' +
    'X-ray reflectometry | Parent: XRR scan of MS-0417',
    ContextOf(Read(pcmFull), Format('item:%d:description#0', [FActionItemId])));
  Assert.AreEqual('P1 | Item: Mo/Si multilayer | Specimen',
    ContextOf(Read(pcmFull), Format('item:%d:description#0', [FItem1])));
  Assert.AreEqual('P1 | Item: Mo/Si multilayer | Specimen',
    ContextOf(Read(pcmFull), Format('value:%d:description#0', [FValueId])));
  Assert.AreEqual('P1 | Item: Mo/Si multilayer | Specimen',
    ContextOf(Read(pcmFull), Format('entry:%d:title#0', [FEntryId])));
end;

procedure TPassageContextProviderTests.TitlePassageHasNoItemTitleInContext;
begin
  Assert.AreEqual(
    'P1 > Annealing > W/B4C stacks | Measurement | X-ray reflectometry | Parent: XRR scan of MS-0417',
    ContextOf(Read(pcmFull), Format('item:%d:title#0', [FActionItemId])));
end;

procedure TPassageContextProviderTests.ItemModeHasProjectAndItemTitleOnly;
var
  Passages: TSearchPassages;
begin
  Passages := Read(pcmItem);
  Assert.AreEqual('P1 | Item: Reflectivity recording',
    ContextOf(Passages, Format('item:%d:description#0', [FActionItemId])));
  Assert.AreEqual('P1', ContextOf(Passages, Format('item:%d:title#0', [FActionItemId])));
end;

procedure TPassageContextProviderTests.NoneModeKeepsStage5Hash;
var
  Snapshot: TSearchSnapshot;
  Passage: TSearchPassage;
  Request: TFileTextRequest;
begin
  Snapshot := Provider(pcmNone).ReadSnapshot(nil);
  Assert.IsTrue(Length(Snapshot.Passages) > 0);
  for Passage in Snapshot.Passages do
  begin
    Assert.AreEqual('', Passage.Context, Passage.Key);
    Assert.AreEqual(PassageHash(Passage.Text), Passage.ContentHash, Passage.Key);
    Assert.AreEqual(Passage.Text, PassageEmbedText(Passage), Passage.Key);
  end;
  for Request in Snapshot.Files do
    Assert.AreEqual('', Request.Context);
end;

procedure TPassageContextProviderTests.FileTextRequestCarriesItemContext;
var
  Request: TFileTextRequest;
  Found: Boolean;
  Passage: TSearchPassage;
begin
  Found := False;
  for Request in Provider(pcmFull).ReadSnapshot(nil).Files do
    if Request.FileId = FMdId then
    begin
      Found := True;
      Assert.AreEqual('P1 | Item: Mo/Si multilayer | Specimen', Request.Context);
    end;
  Assert.IsTrue(Found, 'markdown request');
  for Passage in Read(pcmFull) do
    if Passage.Key = Format('file:%d:name#0', [FMdId]) then
      Assert.AreEqual('P1 | Item: Mo/Si multilayer | Specimen', Passage.Context);
end;

procedure TPassageContextProviderTests.ProjectRenameChangesOnlyThatProjectsHashes;
var
  Before, After: TSearchPassages;
  Hashes: TDictionary<string, string>;
  Texts: TDictionary<string, string>;
  Passage: TSearchPassage;
  Changed, Kept: Integer;
begin
  Before := Read(pcmFull);
  Hashes := TDictionary<string, string>.Create;
  Texts := TDictionary<string, string>.Create;
  try
    for Passage in Before do
    begin
      Hashes.Add(Passage.Key, Passage.ContentHash);
      Texts.Add(Passage.Key, Passage.Text);
    end;
    RenameProject('P1 renamed');
    After := Read(pcmFull);
    Assert.AreEqual<NativeInt>(Length(Before), Length(After));
    Changed := 0;
    Kept := 0;
    for Passage in After do
    begin
      Assert.AreEqual(Texts[Passage.Key], Passage.Text, Passage.Key);
      if Passage.ProjectId = FProjectId then
      begin
        Assert.AreNotEqual(Hashes[Passage.Key], Passage.ContentHash, Passage.Key);
        Inc(Changed);
      end
      else
      begin
        Assert.AreEqual(Hashes[Passage.Key], Passage.ContentHash, Passage.Key);
        Inc(Kept);
      end;
    end;
    Assert.AreEqual(ProjectPassageCount(After, FProjectId), Changed);
    Assert.IsTrue(Kept > 0);
  finally
    Texts.Free;
    Hashes.Free;
  end;
end;

procedure TPassageContextProviderTests.ProjectRenameReembedsOnlyThatProject;
var
  Store: TSearchIndexStore;
  Embedder: TRecordingEmbedder;
  EmbedderRef: ITextEmbedder;
  Indexer: TSearchIndexer;
  Stats: TSyncStats;
  Passages: TSearchPassages;
  Expected: string;
begin
  Passages := Read(pcmFull);
  Embedder := TRecordingEmbedder.Create;
  EmbedderRef := Embedder;
  Store := TSearchIndexStore.Open(FStorePath, Embedder.Identity, Embedder.Dimension);
  try
    Indexer := TSearchIndexer.Create(Provider(pcmFull), Store, EmbedderRef);
    try
      Stats := Indexer.Sync;
      Assert.AreEqual<NativeInt>(Length(Passages), Stats.Added);
      Expected := 'P1 > Annealing > W/B4C stacks | Item: Reflectivity recording | Measurement | ' +
        'X-ray reflectometry | Parent: XRR scan of MS-0417'#10'curve recorded';
      Assert.IsTrue(Embedder.Texts.Contains(Expected), 'embed input is context, line feed, text');
      Stats := Indexer.Sync;
      Assert.AreEqual(0, Stats.Added + Stats.Changed);
      RenameProject('P1 renamed');
      Stats := Indexer.Sync;
      Assert.AreEqual(ProjectPassageCount(Passages, FProjectId), Stats.Changed);
      Assert.AreEqual(ProjectPassageCount(Passages, FOtherProjectId), Stats.Unchanged);
      Assert.AreEqual(0, Stats.Added + Stats.Removed + Stats.Moved + Stats.Truncated);
    finally
      Indexer.Free;
    end;
  finally
    Store.Free;
  end;
end;

procedure TPassageContextProviderTests.RenameSyncStaysCancelable;
var
  Store: TSearchIndexStore;
  Embedder: TRecordingEmbedder;
  EmbedderRef: ITextEmbedder;
  Indexer: TSearchIndexer;
  Stats: TSyncStats;
  Passages: TSearchPassages;
  Cancelled: TCancelCheck;
  Stop: Boolean;
  EncodedBefore: Integer;
  Raised: Boolean;
begin
  Passages := Read(pcmFull);
  Embedder := TRecordingEmbedder.Create;
  EmbedderRef := Embedder;
  Store := TSearchIndexStore.Open(FStorePath, Embedder.Identity, Embedder.Dimension);
  try
    Indexer := TSearchIndexer.Create(Provider(pcmFull), Store, EmbedderRef);
    try
      Indexer.Sync;
      RenameProject('P1 renamed');
      Stop := False;
      EncodedBefore := Embedder.Fake.Encoded;
      Cancelled := function: Boolean
        begin
          Result := Stop;
          if Embedder.Fake.Encoded > EncodedBefore then Stop := True;
        end;
      Raised := False;
      try
        Indexer.Sync(Cancelled);
      except
        on EOperationCancelled do
          Raised := True;
      end;
      Assert.IsTrue(Raised, 'the sync stopped at the cancel');
      Embedder.Texts.Clear;
      Stats := Indexer.Sync;
      Assert.IsTrue(Stats.Changed > 0, 'the rest is still pending after a cancel');
      Assert.IsTrue(Stats.Unchanged > ProjectPassageCount(Passages, FOtherProjectId),
        'the batch that was finished before the cancel is kept');
      Assert.AreEqual(0, Indexer.Sync.Changed);
    finally
      Indexer.Free;
    end;
  finally
    Store.Free;
  end;
end;

procedure TPassageContextProviderTests.ContextIsNotInFullTextIndex;
var
  Store: TSearchIndexStore;
  Embedder: TRecordingEmbedder;
  EmbedderRef: ITextEmbedder;
  Indexer: TSearchIndexer;
begin
  Embedder := TRecordingEmbedder.Create;
  EmbedderRef := Embedder;
  Store := TSearchIndexStore.Open(FStorePath, Embedder.Identity, Embedder.Dimension);
  try
    Indexer := TSearchIndexer.Create(Provider(pcmFull), Store, EmbedderRef);
    try
      Indexer.Sync;
    finally
      Indexer.Free;
    end;
    Assert.IsTrue(Length(Store.MatchWords('oxide', [FProjectId, FOtherProjectId], 10, Default(TItemFilter))) > 0,
      'a word of a passage text is found');
    Assert.AreEqual<NativeInt>(0, Length(Store.MatchWords('zirconia', [FProjectId, FOtherProjectId], 10, Default(TItemFilter))));
    Assert.AreEqual<NativeInt>(0, Length(Store.MatchTrigrams('zirconia', [FProjectId, FOtherProjectId], 10, Default(TItemFilter))));
    Assert.AreEqual<NativeInt>(0, Length(Store.MatchWords('annealing', [FProjectId, FOtherProjectId], 10, Default(TItemFilter))));
  finally
    Store.Free;
  end;
end;

procedure TPassageContextProviderTests.ItemContextsCarryTheFullPartsInEveryMode;
var
  Mode: TPassageContextMode;
  Snapshot: TSearchSnapshot;
  Entry: TItemContextEntry;
  Passage: TSearchPassage;
  Seen: TDictionary<Integer, Boolean>;
  Parts: TPassageContextParts;
  Found: Boolean;
begin
  for Mode := Low(TPassageContextMode) to High(TPassageContextMode) do
  begin
    Snapshot := Provider(Mode).ReadSnapshot(nil);
    Seen := TDictionary<Integer, Boolean>.Create;
    try
      Found := False;
      for Entry in Snapshot.ItemContexts do
      begin
        Seen.AddOrSetValue(Entry.ItemId, True);
        if Entry.ItemId = FActionItemId then
        begin
          Assert.IsTrue(TryParsePassageContextParts(Entry.PartsJson, Parts));
          Assert.AreEqual(
            'P1 > Annealing > W/B4C stacks | Item: Reflectivity recording | Measurement | ' +
            'X-ray reflectometry | Parent: XRR scan of MS-0417',
            BuildPassageContext(Parts, pfItemDescription));
          Found := True;
        end;
      end;
      Assert.IsTrue(Found, 'the action item has a row');
      for Passage in Snapshot.Passages do
        Assert.IsTrue(Seen.ContainsKey(Passage.ItemId), 'every passage item has a row: ' + Passage.Key);
    finally
      Seen.Free;
    end;
  end;
end;

procedure TPassageContextProviderTests.StoredItemContextsSurviveReopenAndAreReplaced;
var
  Store: TSearchIndexStore;
  Json: string;
begin
  Store := TSearchIndexStore.Open(FStorePath, 'context-store', 8);
  try
    Store.ReplaceItemContexts([TItemContextEntry.Make(7, '{"a":1}'), TItemContextEntry.Make(9, '{"b":2}')]);
    Assert.IsTrue(Store.ReadItemContext(7, Json));
    Assert.AreEqual('{"a":1}', Json);
  finally
    Store.Free;
  end;
  Store := TSearchIndexStore.Open(FStorePath, 'context-store', 8);
  try
    Assert.IsFalse(Store.WasReset, 'the rows do not reset the store');
    Assert.IsTrue(Store.ReadItemContext(9, Json));
    Assert.AreEqual('{"b":2}', Json);
    Store.ReplaceItemContexts([TItemContextEntry.Make(9, '{"c":3}')]);
    Assert.IsFalse(Store.ReadItemContext(7, Json), 'a row that left the snapshot is removed');
    Assert.IsTrue(Store.ReadItemContext(9, Json));
    Assert.AreEqual('{"c":3}', Json);
    Store.ReplaceItemContexts(nil);
    Assert.IsFalse(Store.ReadItemContext(9, Json));
  finally
    Store.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPassageContextProviderTests);

end.
