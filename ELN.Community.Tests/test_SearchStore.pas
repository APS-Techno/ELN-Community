unit test_SearchStore;

interface

uses
  System.SysUtils, System.Generics.Collections, DUnitX.TestFramework, unit_SearchPassages,
  unit_SearchIndexStore, unit_TextEmbedder, unit_HybridSearch, unit_TextExtractors,
  unit_TextExtractorRegistry, unit_FileTextStage, unit_SearchIndexer, test_SearchDoubles;

type
  [TestFixture]
  TPassageChunkerTests = class
  private
    function Paragraph(Letter: Char; Len: Integer): string;
    function PatternWord(Len: Integer): string;
  public
    [Test]
    procedure ShortTextIsOneChunk;
    [Test]
    procedure EmptyOrBlankGivesNoChunks;
    [Test]
    procedure SplitsAtParagraphThenSentence;
    [Test]
    procedure SplitsAtSentenceWithoutOverlap;
    [Test]
    procedure SplitsAtSpaceWithOverlap;
    [Test]
    procedure HardSplitWithOverlap;
    [Test]
    procedure NoSurrogateSplit;
    [Test]
    procedure InvalidSizesAreRefused;
    [Test]
    procedure HashIsStable;
    [Test]
    procedure FoldsYo;
  end;

  [TestFixture]
  TSearchIndexStoreTests = class
  private
    FRoot: string;
    FPath: string;
    FStore: TSearchIndexStore;
    function Passage(const Key: string; ProjectId: Integer; const Text: string): TSearchPassage;
    function ItemPassage(const Key: string; ProjectId, ItemId: Integer; const Text: string): TSearchPassage;
    function Vec(Dim, Hot: Integer): TArray<Single>;
    function Keys(const Hits: TArray<TTextHit>): string;
    function CatalogCount: Integer;
    procedure Reopen(const Identity: string; Dimension: Integer);
    procedure ExecExternal(const Sql: string);
    function ExternalCount(const Sql: string): Integer;
    procedure SyncFromTwoThreads(FreshPath: Boolean);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CreatesAndReopens;
    [Test]
    procedure IdentityChangeResets;
    [Test]
    procedure DimensionChangeResets;
    [Test]
    procedure ForeignFileResets;
    [Test]
    procedure VectorRoundTrip;
    [Test]
    procedure UpsertReplacesAndFtsFollows;
    [Test]
    procedure DeleteRemovesFromFts;
    [Test]
    procedure WordsRespectProjects;
    [Test]
    procedure YoFolding;
    [Test]
    procedure TrigramFindsIdentifierFragment;
    [Test]
    procedure QuerySyntaxIsInert;
    [Test]
    procedure RollbackLeavesPriorState;
    [Test]
    procedure RollbackAfterEngineRollbackKeepsStoreUsable;
    [Test]
    procedure UpdateCoordinatesMovesProject;
    [Test]
    procedure PassageTextReturnsStoredText;
    [Test]
    procedure WrongDimensionVectorIsRefused;
    [Test]
    procedure InvalidDimensionRaisesStoreError;
    [Test]
    procedure TwoStoresSyncSameFile;
    [Test]
    procedure TwoStoresOpenFreshPathConcurrently;
    [Test]
    procedure IncompatibleStoreResetWithoutDelete;
    [Test]
    procedure FileTextRoundTripAndPrune;
    [Test]
    procedure SchemaV1StoreRebuilds;
    [Test]
    procedure ItemFilterRestrictsTextLists;
    [Test]
    procedure ItemFilterAppliesBeforeLimit;
    [Test]
    procedure ItemFilterFollowsMovedItem;
    [Test]
    procedure ItemIndexIsCreatedOnExistingStore;
  end;

  TStagePipeline = class
  private
    FRegistry: TTextExtractorRegistry;
    FExtractor: TCountingExtractor;
    FExtractorRef: ITextExtractor;
    FReader: TMemoryFileReader;
    FReaderRef: IFileContentReader;
    FStage: TFileTextStage;
  public
    constructor Create(Store: TSearchIndexStore);
    destructor Destroy; override;
    procedure Put(Id: Int64; const Text: string);
    function Run(const Ids: array of Int64; const Cancelled: TCancelCheck = nil): TSearchPassages;
    function RunFiles(const Files: TArray<TFileTextRequest>; const Progress: TSyncProgress): TSearchPassages;
    function CachedFiles(const Files: TArray<TFileTextRequest>): TSearchPassages;
    property Extractor: TCountingExtractor read FExtractor;
    property Reader: TMemoryFileReader read FReader;
  end;

  [TestFixture]
  TFileTextStageTests = class
  private
    FRoot: string;
    FStore: TSearchIndexStore;
    FA: TStagePipeline;
    function CachedMd5(Id: Int64): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FileTextCachedByContent;
    [Test]
    procedure ChangedBytesReExtract;
    [Test]
    procedure DeletedFileLosesPassagesAndCacheRow;
    [Test]
    procedure CachedFailureRetriedAfterBytesChange;
    [Test]
    procedure ExtractorVersionBumpReExtracts;
    [Test]
    procedure TwoPipelinesSameStoreNoReembed;
    [Test]
    procedure CancelDuringExtraction;
    [Test]
    procedure OversizeFileCachedBySize;
    [Test]
    procedure UnreadableFileGivesNoPassageAndNoCacheRow;
    [Test]
    procedure EverySupportedExtensionHasExtractor;
    [Test]
    procedure LimitReachedKeepsText;
    [Test]
    procedure UnavailableExtractorWritesNoRow;
    [Test]
    procedure UnexpectedExceptionNotCached;
    [Test]
    procedure ProgressReportsFiles;
    [Test]
    procedure UnchangedFilesAreNotReadAgain;
    [Test]
    procedure TouchedFileWithSameBytesIsReadOnce;
    [Test]
    procedure ChangedStampRewritesText;
    [Test]
    procedure ReaderWithoutStampsReadsEverySync;
    [Test]
    procedure CachedPassagesKeepUnvisitedFiles;
  end;

  TControlledEmbedder = class(TInterfacedObject, ITextEmbedder)
  public
    function Identity: string;
    function Dimension: Integer;
    function MaxTokens: Integer;
    function EncodeQuery(const Text: string): TEmbedding;
    function EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
      const Cancelled: TCancelCheck = nil): TArray<TEmbedding>;
  end;

  TFixedSource = class(TInterfacedObject, ISearchDocumentSource)
  private
    FProjects: TDictionary<Integer, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Place(ItemId, ProjectId: Integer);
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  [TestFixture]
  TFixedHybridSearchTests = class
  private
    FRoot: string;
    FFixedStore: TSearchIndexStore;
    FFixedSource: TFixedSource;
    FFixedDoc: ISearchDocumentSource;
    FFixedEmbedder: ITextEmbedder;
    FFixedSearcher: THybridSearcher;
    function Describe(const Hits: TArray<THybridGroup>): string;
    function FusionPassage(const Key: string; ItemId, ProjectId: Integer; const Text: string): TSearchPassage;
    function AngleVector(Degrees: Double): TArray<Single>;
    procedure OpenFixed(const Name: string);
    procedure AddFixed(const Key: string; ItemId: Integer; const Text: string; Degrees: Double);
    function FixedSearch(const Query: string; TopK: Integer;
      const Options: THybridSearchOptions): TArray<THybridGroup>;
    function HasItem(const Hits: TArray<THybridGroup>; ItemId: Integer): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FusionOrdersAndTiesByKey;
    [Test]
    procedure TwoPassagesOfOneItemGiveOneGroup;
    [Test]
    procedure TopKCountsGroups;
    [Test]
    procedure GroupKeepsAtMostThreePassages;
    [Test]
    procedure InvisibleItemInNoGroup;
    [Test]
    procedure WordsOnlyItemKeepsGroup;
    [Test]
    procedure WordsOnlyItemsKeepWordsOrderBesideVectorHits;
    [Test]
    procedure NoPositiveWeightCandidateKeepsWordsOrder;
    [Test]
    procedure WordsListScoresByDefault;
    [Test]
    procedure ShortQueryFindsWordsOnlyItemByDefault;
    [Test]
    procedure WordsOnlyKeepsWordsOrderWithZeroWeight;
    [Test]
    procedure ItemFilterDefaultsToInactive;
    [Test]
    procedure ItemFilterReturnsItemBeyondCandidateCut;
    [Test]
    procedure ActiveEmptyItemFilterGivesNoGroup;
    [Test]
    procedure ItemFilterNeverWidensAccess;
    [Test]
    procedure InactiveItemFilterKeepsEveryGroup;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Math, System.SyncObjs, System.Hash, unit_VectorSearch,
  Aurelius.Drivers.SQLite.Import;

function TPassageChunkerTests.Paragraph(Letter: Char; Len: Integer): string;
begin
  Result := Letter + StringOfChar('x', Len - 1);
end;

function TPassageChunkerTests.PatternWord(Len: Integer): string;
var
  I: Integer;
begin
  SetLength(Result, Len);
  for I := 1 to Len do
    Result[I] := Char(Ord('!') + (I * 7) mod 90);
end;

procedure TPassageChunkerTests.ShortTextIsOneChunk;
var
  Chunks: TArray<string>;
begin
  Chunks := ChunkText('abc', PassageMaxChars, PassageOverlapChars);
  Assert.AreEqual<NativeInt>(1, Length(Chunks));
  Assert.AreEqual('abc', Chunks[0]);
end;

procedure TPassageChunkerTests.EmptyOrBlankGivesNoChunks;
begin
  Assert.AreEqual<NativeInt>(0, Length(ChunkText('', PassageMaxChars, PassageOverlapChars)));
  Assert.AreEqual<NativeInt>(0, Length(ChunkText('  '#13#10, PassageMaxChars, PassageOverlapChars)));
end;

procedure TPassageChunkerTests.SplitsAtParagraphThenSentence;
var
  Chunks: TArray<string>;
  Text: string;
  I: Integer;
begin
  Text := Paragraph('A', 700) + #13#10#13#10 + Paragraph('B', 700) + #13#10#13#10 + Paragraph('C', 700);
  Chunks := ChunkText(Text, PassageMaxChars, PassageOverlapChars);
  Assert.AreEqual<NativeInt>(3, Length(Chunks));
  for I := 0 to High(Chunks) do
  begin
    Assert.IsTrue(Length(Chunks[I]) <= PassageMaxChars, 'chunk length');
    Assert.AreEqual(Char(Ord('A') + I), Chunks[I][1]);
    Assert.AreEqual(700, Length(Chunks[I]));
  end;
end;

procedure TPassageChunkerTests.SplitsAtSentenceWithoutOverlap;
var
  Chunks: TArray<string>;
  Text: string;
  I: Integer;
begin
  Text := '';
  for I := 1 to 80 do
    Text := Text + 'Alpha beta gamma delta. ';
  Text := Text.Trim;
  Chunks := ChunkText(Text, PassageMaxChars, PassageOverlapChars);
  Assert.AreEqual<NativeInt>(2, Length(Chunks));
  Assert.IsTrue(Length(Chunks[0]) <= PassageMaxChars, 'chunk length');
  Assert.IsTrue(Chunks[0].EndsWith('.'), 'first chunk ends at a sentence');
  Assert.AreEqual(Text, Chunks[0] + ' ' + Chunks[1]);
end;

procedure TPassageChunkerTests.SplitsAtSpaceWithOverlap;
var
  Chunks: TArray<string>;
  Text: string;
  I: Integer;
begin
  Text := '';
  for I := 1 to 300 do
    Text := Text + 'abcdefghi ';
  Text := Text.Trim;
  Chunks := ChunkText(Text, PassageMaxChars, PassageOverlapChars);
  Assert.IsTrue(Length(Chunks) >= 3, 'at least three chunks');
  for I := 0 to High(Chunks) do
  begin
    Assert.IsTrue(Length(Chunks[I]) <= PassageMaxChars, 'chunk length');
    Assert.IsTrue(Chunks[I].EndsWith('abcdefghi'), 'chunk ends at a word boundary');
  end;
  Assert.AreEqual(Copy(Chunks[0], Length(Chunks[0]) - 148, 149), Copy(Chunks[1], 1, 149));
end;

procedure TPassageChunkerTests.HardSplitWithOverlap;
var
  Chunks: TArray<string>;
  Text, Rebuilt: string;
  I: Integer;
begin
  Text := PatternWord(3000);
  Chunks := ChunkText(Text, PassageMaxChars, PassageOverlapChars);
  Assert.AreEqual<NativeInt>(3, Length(Chunks));
  Rebuilt := Chunks[0];
  for I := 0 to High(Chunks) do
  begin
    Assert.IsTrue(Length(Chunks[I]) <= PassageMaxChars, 'chunk length');
    if I > 0 then
    begin
      Assert.AreEqual(Copy(Chunks[I - 1], Length(Chunks[I - 1]) - PassageOverlapChars + 1, PassageOverlapChars),
        Copy(Chunks[I], 1, PassageOverlapChars), 'overlap');
      Rebuilt := Rebuilt + Copy(Chunks[I], PassageOverlapChars + 1, MaxInt);
    end;
  end;
  Assert.AreEqual(Text, Rebuilt);
end;

procedure TPassageChunkerTests.NoSurrogateSplit;
var
  Chunks: TArray<string>;
  Text, Emoji: string;
  Position, I: Integer;
  Intact: Boolean;
begin
  Emoji := string(Char($D83D)) + Char($DE00);
  for Position := 1197 to 1202 do
  begin
    Text := StringOfChar('a', Position - 1) + Emoji + StringOfChar('a', 300);
    Chunks := ChunkText(Text, PassageMaxChars, PassageOverlapChars);
    Intact := False;
    for I := 0 to High(Chunks) do
    begin
      Assert.IsFalse(Chunks[I][Length(Chunks[I])] = Char($D83D), 'chunk ends with a lone high surrogate');
      Assert.IsFalse(Chunks[I][1] = Char($DE00), 'chunk starts with a lone low surrogate');
      Intact := Intact or (Pos(Emoji, Chunks[I]) > 0);
    end;
    Assert.IsTrue(Intact, Format('emoji at %d survives whole', [Position]));
  end;
end;

procedure TPassageChunkerTests.InvalidSizesAreRefused;
begin
  Assert.WillRaise(procedure begin ChunkText('abc', 0, 0); end, EArgumentException);
  Assert.WillRaise(procedure begin ChunkText('abc', 10, -1); end, EArgumentException);
  Assert.WillRaise(procedure begin ChunkText('abc', 10, 10); end, EArgumentException);
end;

procedure TPassageChunkerTests.HashIsStable;
const
  Sample = 'Плёнка';
var
  Hasher: THashSHA2;
  Bytes: TBytes;
  Expected: string;
  B: Byte;
begin
  Hasher := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  Hasher.Update(TEncoding.UTF8.GetBytes(Sample));
  Bytes := Hasher.HashAsBytes;
  Expected := '';
  for B in Bytes do
    Expected := Expected + IntToHex(B, 2);
  Assert.AreEqual(64, Length(Expected));
  Assert.AreEqual(Expected, PassageHash(Sample));
  Assert.AreEqual(PassageHash(Sample), PassageHash(Sample));
  Assert.AreNotEqual(PassageHash(Sample), PassageHash('Пленка'));
end;

procedure TPassageChunkerTests.FoldsYo;
begin
  Assert.AreEqual('Елка пленка', FoldSearchText('Ёлка плёнка'));
end;

const
  StoreIdentity = 'test-embedder-1';

procedure TSearchIndexStoreTests.Setup;
var
  Id: TGUID;
begin
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SearchStore-' + GUIDToString(Id));
  ForceDirectories(FRoot);
  FPath := TPath.Combine(FRoot, 'search.sqlite');
  FStore := TSearchIndexStore.Open(FPath, StoreIdentity, StoreDim);
end;

procedure TSearchIndexStoreTests.TearDown;
begin
  FreeAndNil(FStore);
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TSearchIndexStoreTests.Passage(const Key: string; ProjectId: Integer;
  const Text: string): TSearchPassage;
begin
  Result.Key := Key;
  Result.ProjectId := ProjectId;
  Result.ItemId := ProjectId * 100 + 1;
  Result.FileId := 0;
  Result.Field := pfItemTitle;
  Result.Text := Text;
  Result.ContentHash := PassageHash(Text);
end;

function TSearchIndexStoreTests.Vec(Dim, Hot: Integer): TArray<Single>;
var
  I: Integer;
  Norm: Double;
begin
  SetLength(Result, Dim);
  Norm := 0;
  for I := 0 to Dim - 1 do
  begin
    Result[I] := Sin(I + 1 + Hot);
    Norm := Norm + Sqr(Double(Result[I]));
  end;
  Norm := Sqrt(Norm);
  for I := 0 to Dim - 1 do
    Result[I] := Result[I] / Norm;
end;

function TSearchIndexStoreTests.Keys(const Hits: TArray<TTextHit>): string;
var
  Hit: TTextHit;
begin
  Result := '';
  for Hit in Hits do
    Result := Result + Hit.Key + ';';
end;

function TSearchIndexStoreTests.CatalogCount: Integer;
var
  Catalog: TDictionary<string, TStoredPassage>;
begin
  Catalog := FStore.ReadCatalog;
  try
    Result := Catalog.Count;
  finally
    Catalog.Free;
  end;
end;

function TSearchIndexStoreTests.ItemPassage(const Key: string; ProjectId, ItemId: Integer;
  const Text: string): TSearchPassage;
begin
  Result := Passage(Key, ProjectId, Text);
  Result.ItemId := ItemId;
end;

procedure TSearchIndexStoreTests.Reopen(const Identity: string; Dimension: Integer);
begin
  FreeAndNil(FStore);
  FStore := TSearchIndexStore.Open(FPath, Identity, Dimension);
end;

procedure TSearchIndexStoreTests.CreatesAndReopens;
var
  Catalog: TDictionary<string, TStoredPassage>;
  Row: TStoredPassage;
  P: TSearchPassage;
begin
  Assert.IsFalse(FStore.WasReset, 'fresh store');
  P := Passage('a', 1, 'alpha');
  P.FileId := 77;
  P.Field := pfFileText;
  FStore.Upsert(P, Vec(StoreDim, 0));
  FStore.Upsert(Passage('b', 1, 'beta'), Vec(StoreDim, 1));
  FStore.Upsert(Passage('c', 2, 'gamma'), Vec(StoreDim, 2));
  Reopen(StoreIdentity, StoreDim);
  Assert.IsFalse(FStore.WasReset);
  Catalog := FStore.ReadCatalog;
  try
    Assert.AreEqual<NativeInt>(3, Catalog.Count);
    Row := Catalog['a'];
    Assert.AreEqual(1, Row.ProjectId);
    Assert.AreEqual(101, Row.ItemId);
    Assert.AreEqual<Int64>(77, Row.FileId);
    Assert.IsTrue(Row.Field = pfFileText);
    Assert.AreEqual(PassageHash('alpha'), Row.ContentHash);
  finally
    Catalog.Free;
  end;
end;

procedure TSearchIndexStoreTests.IdentityChangeResets;
begin
  FStore.Upsert(Passage('a', 1, 'alpha'), Vec(StoreDim, 0));
  Reopen('other-embedder', StoreDim);
  Assert.IsTrue(FStore.WasReset);
  Assert.AreEqual(0, CatalogCount);
  Assert.AreEqual<NativeInt>(0, Length(FStore.MatchWords('alpha', [1], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.DimensionChangeResets;
begin
  FStore.Upsert(Passage('a', 1, 'alpha'), Vec(StoreDim, 0));
  Reopen(StoreIdentity, StoreDim * 2);
  Assert.IsTrue(FStore.WasReset);
  Assert.AreEqual(0, CatalogCount);
  FStore.Upsert(Passage('a', 1, 'alpha'), Vec(StoreDim * 2, 0));
  Assert.AreEqual(1, CatalogCount);
end;

procedure TSearchIndexStoreTests.ForeignFileResets;
var
  Bytes: TBytes;
  I: Integer;
  Db, Stmt: Pointer;
  Tail: PChar;
begin
  FreeAndNil(FStore);
  SetLength(Bytes, 100);
  for I := 0 to High(Bytes) do
    Bytes[I] := Byte((I * 37 + 11) mod 251);
  System.IOUtils.TFile.WriteAllBytes(FPath, Bytes);
  FStore := TSearchIndexStore.Open(FPath, StoreIdentity, StoreDim);
  Assert.IsTrue(FStore.WasReset, 'random bytes');
  FStore.Upsert(Passage('a', 1, 'alpha'), Vec(StoreDim, 0));
  Assert.AreEqual(1, CatalogCount);

  FreeAndNil(FStore);
  System.IOUtils.TFile.Delete(FPath);
  Assert.IsTrue(LoadSQLiteLibrary);
  Db := nil;
  Assert.AreEqual(SQLITE_OK, f_sqlite3_open16(PChar(FPath), Db));
  try
    Stmt := nil;
    Assert.AreEqual(SQLITE_OK, f_sqlite3_prepare16_v2(Db, 'CREATE TABLE unrelated(x INTEGER)', -1, Stmt, Tail));
    Assert.AreEqual(SQLITE_DONE, f_sqlite3_step(Stmt));
    f_sqlite3_finalize(Stmt);
  finally
    f_sqlite3_close(Db);
  end;
  FStore := TSearchIndexStore.Open(FPath, StoreIdentity, StoreDim);
  Assert.IsTrue(FStore.WasReset, 'unrelated sqlite file');
  FStore.Upsert(Passage('a', 1, 'alpha'), Vec(StoreDim, 0));
  Assert.AreEqual(1, CatalogCount);
end;

procedure TSearchIndexStoreTests.VectorRoundTrip;
var
  Index: TExactVectorIndex;
  Query: TArray<Single>;
  Hits: TArray<TVectorHit>;
begin
  Reopen(StoreIdentity, 384);
  Query := Vec(384, 5);
  FStore.Upsert(Passage('k', 3, 'vector text'), Query);
  FStore.Upsert(Passage('other', 3, 'other text'), Vec(384, 9));
  Index := TExactVectorIndex.Create(384);
  try
    FStore.LoadVectors(Index);
    Assert.AreEqual(2, Index.Count);
    Hits := Index.Search(Query, 1, ['3'], Default(TItemFilter));
    Assert.AreEqual<NativeInt>(1, Length(Hits));
    Assert.AreEqual('k', Hits[0].SourceId);
    Assert.AreEqual('3', Hits[0].Scope);
    Assert.AreEqual(1.0, Hits[0].Score, 1e-6);
    Hits := Index.Search(Query, 1, ['3'], TItemFilter.Only([301]));
    Assert.AreEqual<NativeInt>(1, Length(Hits));
    Assert.AreEqual('k', Hits[0].SourceId);
    Assert.AreEqual<NativeInt>(0, Length(Index.Search(Query, 1, ['3'], TItemFilter.Only([999]))));
  finally
    Index.Free;
  end;
end;

procedure TSearchIndexStoreTests.UpsertReplacesAndFtsFollows;
begin
  FStore.Upsert(Passage('a', 1, 'oldword here'), Vec(StoreDim, 0));
  FStore.Upsert(Passage('a', 1, 'newword here'), Vec(StoreDim, 0));
  Assert.AreEqual(1, CatalogCount);
  Assert.AreEqual('a;', Keys(FStore.MatchWords('newword', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('', Keys(FStore.MatchWords('oldword', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('a;', Keys(FStore.MatchTrigrams('newword', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('', Keys(FStore.MatchTrigrams('oldword', [1], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.DeleteRemovesFromFts;
begin
  FStore.Upsert(Passage('a', 1, 'findable word'), Vec(StoreDim, 0));
  FStore.Delete('a');
  Assert.AreEqual(0, CatalogCount);
  Assert.AreEqual('', Keys(FStore.MatchWords('findable', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('', Keys(FStore.MatchTrigrams('findable', [1], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.WordsRespectProjects;
var
  Hits: TArray<TTextHit>;
begin
  FStore.Upsert(Passage('p1', 1, 'shared word'), Vec(StoreDim, 0));
  FStore.Upsert(Passage('p2', 2, 'shared word'), Vec(StoreDim, 1));
  Hits := FStore.MatchWords('shared', [1], 10, Default(TItemFilter));
  Assert.AreEqual<NativeInt>(1, Length(Hits));
  Assert.AreEqual('p1', Hits[0].Key);
  Assert.AreEqual(1, Hits[0].Rank);
  Assert.AreEqual<NativeInt>(0, Length(FStore.MatchWords('shared', [], 10, Default(TItemFilter))));
  Assert.AreEqual<NativeInt>(2, Length(FStore.MatchWords('shared', [1, 2], 10, Default(TItemFilter))));
  Assert.AreEqual<NativeInt>(1, Length(FStore.MatchWords('shared', [1, 2], 1, Default(TItemFilter))));
  Assert.AreEqual<NativeInt>(0, Length(FStore.MatchTrigrams('shared', [], 10, Default(TItemFilter))));
  Assert.AreEqual('p2;', Keys(FStore.MatchTrigrams('shared', [2], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.YoFolding;
begin
  FStore.Upsert(Passage('a', 1, 'пленка отслоилась'), Vec(StoreDim, 0));
  Assert.AreEqual('a;', Keys(FStore.MatchWords('плёнка', [1], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.TrigramFindsIdentifierFragment;
begin
  FStore.Upsert(Passage('a', 1, 'SMP-2024-017'), Vec(StoreDim, 0));
  Assert.AreEqual('a;', Keys(FStore.MatchTrigrams('2024-01', [1], 10, Default(TItemFilter))));
  Assert.AreEqual<NativeInt>(0, Length(FStore.MatchTrigrams('20', [1], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.QuerySyntaxIsInert;
var
  Query: string;
begin
  FStore.Upsert(Passage('a', 1, 'SMP-2024-017 and near x'), Vec(StoreDim, 0));
  for Query in ['"', 'a AND', 'NEAR(x', '*', '-x', 'SMP-2024-017', '', '   ', '"""',
    'alp' + #0 + 'ha', #0, #0#0#0, 'SMP-2024' + #0 + '-017', #1#2#31 + 'near'] do
    try
      FStore.MatchWords(Query, [1], 10, Default(TItemFilter));
      FStore.MatchTrigrams(Query, [1], 10, Default(TItemFilter));
    except
      on E: Exception do
        Assert.Fail('query [' + Query + '] raised ' + E.ClassName + ': ' + E.Message);
    end;
  Assert.AreEqual('a;', Keys(FStore.MatchWords('SMP-2024-017', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('a;', Keys(FStore.MatchWords('SMP-2024' + #0 + '-017', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('a;', Keys(FStore.MatchTrigrams('SMP-20' + #0 + '24', [1], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.RollbackLeavesPriorState;
begin
  FStore.Upsert(Passage('a', 1, 'keepword'), Vec(StoreDim, 0));
  FStore.BeginBatch;
  FStore.Upsert(Passage('b', 1, 'tempword'), Vec(StoreDim, 1));
  FStore.Delete('a');
  Assert.AreEqual(1, CatalogCount);
  FStore.RollbackBatch;
  Assert.AreEqual(1, CatalogCount);
  Assert.AreEqual('a;', Keys(FStore.MatchWords('keepword', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('', Keys(FStore.MatchWords('tempword', [1], 10, Default(TItemFilter))));
  FStore.BeginBatch;
  FStore.Upsert(Passage('b', 1, 'tempword'), Vec(StoreDim, 1));
  FStore.CommitBatch;
  Assert.AreEqual(2, CatalogCount);
  Assert.AreEqual('b;', Keys(FStore.MatchWords('tempword', [1], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.ExecExternal(const Sql: string);
var
  Db, Stmt: Pointer;
  Tail: PChar;
begin
  Assert.IsTrue(LoadSQLiteLibrary);
  Db := nil;
  Assert.AreEqual(SQLITE_OK, f_sqlite3_open16(PChar(FPath), Db));
  try
    Stmt := nil;
    Assert.AreEqual(SQLITE_OK, f_sqlite3_prepare16_v2(Db, PChar(Sql), -1, Stmt, Tail));
    Assert.AreEqual(SQLITE_DONE, f_sqlite3_step(Stmt));
    f_sqlite3_finalize(Stmt);
  finally
    f_sqlite3_close(Db);
  end;
end;

procedure TSearchIndexStoreTests.RollbackAfterEngineRollbackKeepsStoreUsable;
begin
  FStore.Upsert(Passage('a', 1, 'keepword'), Vec(StoreDim, 0));
  ExecExternal('CREATE TRIGGER abort_insert BEFORE INSERT ON passages ' +
    'BEGIN SELECT RAISE(ROLLBACK, ''forced rollback''); END');
  FStore.BeginBatch;
  Assert.WillRaise(
    procedure
    begin
      FStore.Upsert(Passage('b', 1, 'tempword'), Vec(StoreDim, 1));
    end, ESearchIndexError);
  try
    FStore.RollbackBatch;
  except
    on E: Exception do
      Assert.Fail('RollbackBatch raised ' + E.ClassName + ': ' + E.Message);
  end;
  ExecExternal('DROP TRIGGER abort_insert');
  FStore.BeginBatch;
  FStore.Upsert(Passage('b', 1, 'tempword'), Vec(StoreDim, 1));
  FStore.CommitBatch;
  Assert.AreEqual(2, CatalogCount);
end;

procedure TSearchIndexStoreTests.UpdateCoordinatesMovesProject;
var
  P: TSearchPassage;
begin
  P := Passage('a', 1, 'moving word');
  FStore.Upsert(P, Vec(StoreDim, 0));
  P.ProjectId := 2;
  P.ItemId := 555;
  FStore.UpdateCoordinates(P);
  Assert.AreEqual('', Keys(FStore.MatchWords('moving', [1], 10, Default(TItemFilter))));
  Assert.AreEqual('a;', Keys(FStore.MatchWords('moving', [2], 10, Default(TItemFilter))));
  Assert.AreEqual('a;', Keys(FStore.MatchTrigrams('moving', [2], 10, Default(TItemFilter))));
end;

procedure TSearchIndexStoreTests.PassageTextReturnsStoredText;
begin
  FStore.Upsert(Passage('a', 1, 'stored text'), Vec(StoreDim, 0));
  Assert.AreEqual('stored text', FStore.PassageText('a'));
  Assert.AreEqual('', FStore.PassageText('missing'));
end;

procedure TSearchIndexStoreTests.WrongDimensionVectorIsRefused;
begin
  Assert.WillRaise(
    procedure
    begin
      FStore.Upsert(Passage('a', 1, 'x'), Vec(StoreDim + 1, 0));
    end, ESearchIndexError);
end;

procedure TSearchIndexStoreTests.InvalidDimensionRaisesStoreError;
begin
  Assert.WillRaise(
    procedure
    begin
      TSearchIndexStore.Open(TPath.Combine(FRoot, 'bad.sqlite'), StoreIdentity, 0).Free;
    end, ESearchIndexError);
end;

function TControlledEmbedder.Identity: string;
begin
  Result := 'controlled-1';
end;

function TControlledEmbedder.Dimension: Integer;
begin
  Result := StoreDim;
end;

function TControlledEmbedder.MaxTokens: Integer;
begin
  Result := E5MaxTokens;
end;

function TControlledEmbedder.EncodeQuery(const Text: string): TEmbedding;
begin
  SetLength(Result.Vector, StoreDim);
  Result.Vector[0] := 1;
  Result.TokenCount := 1;
  Result.SourceTokenCount := 1;
  Result.Truncated := False;
end;

function TControlledEmbedder.EncodePassages(const Texts: TArray<string>;
  Policy: TOverlengthPolicy; const Cancelled: TCancelCheck): TArray<TEmbedding>;
begin
  raise ENotSupportedException.Create('Passages are stored with explicit vectors');
end;

constructor TFixedSource.Create;
begin
  inherited Create;
  FProjects := TDictionary<Integer, Integer>.Create;
end;

destructor TFixedSource.Destroy;
begin
  FProjects.Free;
  inherited;
end;

procedure TFixedSource.Place(ItemId, ProjectId: Integer);
begin
  FProjects.AddOrSetValue(ItemId, ProjectId);
end;

function TFixedSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Result := Default(TSearchSnapshot);
end;

function TFixedSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  ProjectId := 0;
  Result := FProjects.TryGetValue(ItemId, ProjectId);
end;

procedure TFixedHybridSearchTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-FixedHybrid-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
end;

procedure TFixedHybridSearchTests.TearDown;
begin
  FreeAndNil(FFixedSearcher);
  FreeAndNil(FFixedStore);
  FFixedDoc := nil;
  FFixedSource := nil;
  FFixedEmbedder := nil;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TFixedHybridSearchTests.Describe(const Hits: TArray<THybridGroup>): string;
var
  Group: THybridGroup;
begin
  Result := '';
  for Group in Hits do
  begin
    if Result <> '' then
      Result := Result + ';';
    Result := Result + Group.Passages[0].Key + ':';
    if hsVector in Group.Sources then Result := Result + 'V';
    if hsWords in Group.Sources then Result := Result + 'W';
    if hsTrigram in Group.Sources then Result := Result + 'T';
  end;
end;

function TFixedHybridSearchTests.FusionPassage(const Key: string; ItemId, ProjectId: Integer;
  const Text: string): TSearchPassage;
begin
  Result.Key := Key;
  Result.ProjectId := ProjectId;
  Result.ItemId := ItemId;
  Result.FileId := 0;
  Result.Field := pfItemTitle;
  Result.Text := Text;
  Result.ContentHash := PassageHash(Text);
end;

function TFixedHybridSearchTests.AngleVector(Degrees: Double): TArray<Single>;
begin
  SetLength(Result, StoreDim);
  Result[0] := Cos(Degrees * Pi / 180);
  Result[1] := Sin(Degrees * Pi / 180);
end;

procedure TFixedHybridSearchTests.OpenFixed(const Name: string);
begin
  FFixedEmbedder := TControlledEmbedder.Create;
  FFixedSource := TFixedSource.Create;
  FFixedDoc := FFixedSource;
  FFixedStore := TSearchIndexStore.Open(TPath.Combine(FRoot, Name + '.sqlite'),
    FFixedEmbedder.Identity, FFixedEmbedder.Dimension);
end;

procedure TFixedHybridSearchTests.AddFixed(const Key: string; ItemId: Integer; const Text: string;
  Degrees: Double);
begin
  FFixedStore.Upsert(FusionPassage(Key, ItemId, 1, Text), AngleVector(Degrees));
end;

function TFixedHybridSearchTests.FixedSearch(const Query: string; TopK: Integer;
  const Options: THybridSearchOptions): TArray<THybridGroup>;
begin
  FreeAndNil(FFixedSearcher);
  FFixedSearcher := THybridSearcher.Create(FFixedStore, FFixedEmbedder, FFixedDoc);
  Result := FFixedSearcher.Search(Query, [1], TopK, Options);
end;

function TFixedHybridSearchTests.HasItem(const Hits: TArray<THybridGroup>; ItemId: Integer): Boolean;
var
  Group: THybridGroup;
begin
  for Group in Hits do
    if Group.ItemId = ItemId then
      Exit(True);
  Result := False;
end;

procedure TFixedHybridSearchTests.TwoPassagesOfOneItemGiveOneGroup;
var
  Groups: TArray<THybridGroup>;
begin
  OpenFixed('group-one');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  AddFixed('p1', 101, 'mica', 10);
  AddFixed('p2', 101, 'mica film', 20);
  AddFixed('p3', 201, 'noise', 30);
  Groups := FixedSearch('mica', 10, THybridSearchOptions.Default);
  Assert.AreEqual<NativeInt>(2, Length(Groups));
  Assert.AreEqual(101, Groups[0].ItemId);
  Assert.AreEqual(1, Groups[0].ProjectId);
  Assert.AreEqual<NativeInt>(2, Length(Groups[0].Passages));
  Assert.IsTrue(Groups[0].Passages[0].Score >= Groups[0].Passages[1].Score, 'passages in fused order');
  Assert.AreEqual(Groups[0].Passages[0].Score, Groups[0].Score, 1e-12, 'group score is the best passage score');
  Assert.AreEqual(Groups[0].Passages[0].FileId, Groups[0].FileId);
  Assert.AreEqual('mica', Groups[0].Passages[0].Snippet.Substring(0, 4));
  Assert.AreEqual(201, Groups[1].ItemId);
  Assert.AreEqual<NativeInt>(1, Length(Groups[1].Passages));
end;

procedure TFixedHybridSearchTests.TopKCountsGroups;
var
  Groups: TArray<THybridGroup>;
begin
  OpenFixed('group-topk');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  FFixedSource.Place(301, 1);
  AddFixed('a1', 101, 'mica', 1);
  AddFixed('a2', 101, 'mica', 2);
  AddFixed('a3', 101, 'mica', 3);
  AddFixed('b1', 201, 'noise', 40);
  AddFixed('c1', 301, 'noise', 50);
  Groups := FixedSearch('mica', 2, THybridSearchOptions.Default);
  Assert.AreEqual<NativeInt>(2, Length(Groups));
  Assert.AreEqual(101, Groups[0].ItemId);
  Assert.AreEqual(201, Groups[1].ItemId);
end;

procedure TFixedHybridSearchTests.GroupKeepsAtMostThreePassages;
var
  Groups: TArray<THybridGroup>;
begin
  OpenFixed('group-cap');
  FFixedSource.Place(101, 1);
  AddFixed('a1', 101, 'mica', 1);
  AddFixed('a2', 101, 'mica', 2);
  AddFixed('a3', 101, 'mica', 3);
  AddFixed('a4', 101, 'mica', 4);
  Groups := FixedSearch('mica', 10, THybridSearchOptions.Default);
  Assert.AreEqual<NativeInt>(1, Length(Groups));
  Assert.AreEqual<NativeInt>(MaxGroupPassages, Length(Groups[0].Passages));
end;

procedure TFixedHybridSearchTests.InvisibleItemInNoGroup;
var
  Groups: TArray<THybridGroup>;
  Group: THybridGroup;
  Passage: THybridHit;
begin
  OpenFixed('group-hidden');
  FFixedSource.Place(101, 1);
  AddFixed('hidden', 901, 'mica', 0);
  AddFixed('shown', 101, 'mica', 20);
  Groups := FixedSearch('mica', 10, THybridSearchOptions.Default);
  Assert.AreEqual<NativeInt>(1, Length(Groups));
  for Group in Groups do
  begin
    Assert.AreNotEqual(901, Group.ItemId);
    for Passage in Group.Passages do
      Assert.AreNotEqual('hidden', Passage.Key);
  end;
end;

procedure TFixedHybridSearchTests.WordsOnlyItemKeepsGroup;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
begin
  OpenFixed('group-words');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  AddFixed('p1', 101, 'mica', 10);
  AddFixed('p2', 201, 'zirconium oxide', 80);
  Options := THybridSearchOptions.Default;
  Options.Lists := [hsWords];
  Groups := FixedSearch('zirconium', 10, Options);
  Assert.AreEqual<NativeInt>(1, Length(Groups));
  Assert.AreEqual(201, Groups[0].ItemId);
  Assert.IsTrue(Groups[0].Sources = [hsWords]);
  Assert.AreEqual<NativeInt>(1, Length(Groups[0].Passages));
  Assert.AreEqual('p2', Groups[0].Passages[0].Key);
end;

procedure TFixedHybridSearchTests.WordsListScoresByDefault;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
begin
  OpenFixed('weight-default');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  AddFixed('near', 101, 'noise', 10);
  AddFixed('word', 201, 'oxide of zirconium', 80);
  Groups := FixedSearch('zirconium oxide', 10, THybridSearchOptions.Default);
  Assert.AreEqual<NativeInt>(2, Length(Groups));
  Assert.AreEqual(201, Groups[0].ItemId, 'the words hit leads');
  Assert.IsTrue(Groups[0].Sources = [hsVector, hsWords]);
  Options := THybridSearchOptions.Default;
  Options.ListWeights[hsWords] := 0;
  Groups := FixedSearch('zirconium oxide', 10, Options);
  Assert.AreEqual(101, Groups[0].ItemId, 'with weight 0 the vector list decides');
  Assert.IsTrue(Groups[1].Sources = [hsVector, hsWords], 'the words hit is still reported');
end;

procedure TFixedHybridSearchTests.ShortQueryFindsWordsOnlyItemByDefault;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
  I, Position: Integer;
begin
  OpenFixed('weight-short');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(301, 1);
  FFixedSource.Place(302, 1);
  FFixedSource.Place(303, 1);
  AddFixed('v1', 301, 'noise', 1);
  AddFixed('v2', 302, 'noise', 2);
  AddFixed('v3', 303, 'noise', 3);
  AddFixed('sym', 101, 'Cr/Sc multilayer', 80);
  Options := THybridSearchOptions.Default;
  Options.CandidatesPerList := 3;
  Groups := FixedSearch('Cr', 10, Options);
  Position := -1;
  for I := 0 to High(Groups) do
    if Groups[I].ItemId = 101 then
      Position := I;
  Assert.IsTrue((Position >= 0) and (Position <= 1), 'a two-character query finds the item by its word');
  Options.ListWeights[hsWords] := 0;
  Groups := FixedSearch('Cr', 10, Options);
  Assert.AreEqual(101, Groups[High(Groups)].ItemId, 'with weight 0 the item comes last');
end;

procedure TFixedHybridSearchTests.WordsOnlyKeepsWordsOrderWithZeroWeight;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
begin
  OpenFixed('weight-words-only');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  AddFixed('a-long', 101, 'zirconium oxide coating on a silicon substrate with extra words', 10);
  AddFixed('z-short', 201, 'zirconium', 20);
  Options := THybridSearchOptions.Default;
  Options.ListWeights[hsWords] := 0;
  Options.Lists := [hsWords];
  Groups := FixedSearch('zirconium', 10, Options);
  Assert.AreEqual<NativeInt>(2, Length(Groups));
  Assert.AreEqual(201, Groups[0].ItemId, 'the order of the words list, not the key order');
end;

procedure TFixedHybridSearchTests.WordsOnlyItemsKeepWordsOrderBesideVectorHits;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
begin
  OpenFixed('weight-beside-vector');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  FFixedSource.Place(301, 1);
  FFixedSource.Place(302, 1);
  AddFixed('v1', 301, 'noise', 1);
  AddFixed('v2', 302, 'noise', 2);
  AddFixed('a-long', 101, 'zirconium coating on a silicon substrate with extra words', 80);
  AddFixed('z-best', 201, 'oxide zirconium', 85);
  Options := THybridSearchOptions.Default;
  Options.ListWeights[hsWords] := 0;
  Options.CandidatesPerList := 2;
  Groups := FixedSearch('zirconium oxide', 10, Options);
  Assert.AreEqual<NativeInt>(4, Length(Groups));
  Assert.AreEqual(301, Groups[0].ItemId);
  Assert.AreEqual(302, Groups[1].ItemId);
  Assert.AreEqual(201, Groups[2].ItemId, 'words-only items keep the order of the words list');
  Assert.AreEqual(101, Groups[3].ItemId);
  Assert.AreEqual('z-best', Groups[2].Passages[0].Key);
  Assert.AreEqual(Double(0), Groups[2].Score, 1e-12);
  Assert.AreEqual(Double(0), Groups[3].Score, 1e-12);
end;

procedure TFixedHybridSearchTests.NoPositiveWeightCandidateKeepsWordsOrder;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
begin
  OpenFixed('weight-no-positive');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  AddFixed('a-long', 101, 'zirconium coating on a silicon substrate with extra words', 80);
  AddFixed('z-best', 201, 'oxide zirconium', 85);
  Options := THybridSearchOptions.Default;
  Options.ListWeights[hsWords] := 0;
  Options.Lists := [hsWords, hsTrigram];
  Groups := FixedSearch('zirconium oxide', 10, Options);
  Assert.AreEqual<NativeInt>(2, Length(Groups));
  Assert.AreEqual(201, Groups[0].ItemId, 'no list with a positive weight has a candidate');
  Assert.AreEqual(101, Groups[1].ItemId);
  Options.Lists := [hsWords];
  Groups := FixedSearch('zirconium oxide', 10, Options);
  Assert.AreEqual<NativeInt>(2, Length(Groups));
  Assert.AreEqual(201, Groups[0].ItemId, 'single words list');
  Assert.AreEqual(101, Groups[1].ItemId);
end;

procedure TFixedHybridSearchTests.ItemFilterDefaultsToInactive;
begin
  Assert.IsFalse(THybridSearchOptions.Default.ItemFilter.Active);
  Assert.AreEqual<NativeInt>(0, Length(THybridSearchOptions.Default.ItemFilter.ItemIds));
end;

procedure TFixedHybridSearchTests.ItemFilterReturnsItemBeyondCandidateCut;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
  I: Integer;
begin
  OpenFixed('filter-starve');
  for I := 1 to 60 do
  begin
    FFixedSource.Place(1000 + I, 1);
    AddFixed(Format('n%.2d', [I]), 1000 + I, 'mica', I * 0.5);
  end;
  FFixedSource.Place(101, 1);
  AddFixed('z-target', 101, 'mica film on a silicon substrate with extra words', 85);
  Groups := FixedSearch('mica', 100, THybridSearchOptions.Default);
  Assert.IsFalse(HasItem(Groups, 101), 'control: the item is below the candidate cut in all three lists');
  Options := THybridSearchOptions.Default;
  Options.ItemFilter := TItemFilter.Only([101]);
  Groups := FixedSearch('mica', 100, Options);
  Assert.AreEqual<NativeInt>(1, Length(Groups));
  Assert.AreEqual(101, Groups[0].ItemId);
  Assert.AreEqual('z-target', Groups[0].Passages[0].Key);
  Assert.IsTrue(Groups[0].Sources = [hsVector, hsWords, hsTrigram], 'rank 1 in every list');
end;

procedure TFixedHybridSearchTests.ActiveEmptyItemFilterGivesNoGroup;
var
  Options: THybridSearchOptions;
begin
  OpenFixed('filter-empty');
  FFixedSource.Place(101, 1);
  AddFixed('a', 101, 'mica', 10);
  Assert.AreEqual<NativeInt>(1, Length(FixedSearch('mica', 10, THybridSearchOptions.Default)), 'control');
  Options := THybridSearchOptions.Default;
  Options.ItemFilter := TItemFilter.Only([]);
  Assert.IsTrue(Options.ItemFilter.Active);
  Assert.AreEqual<NativeInt>(0, Length(FixedSearch('mica', 10, Options)));
end;

procedure TFixedHybridSearchTests.ItemFilterNeverWidensAccess;
var
  Groups: TArray<THybridGroup>;
  Options: THybridSearchOptions;
begin
  OpenFixed('filter-access');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 2);
  FFixedSource.Place(301, 1);
  AddFixed('visible', 101, 'mica visible', 10);
  FFixedStore.Upsert(FusionPassage('hidden', 201, 2, 'mica hidden'), AngleVector(0));
  AddFixed('not-allowed', 301, 'mica other', 5);
  Options := THybridSearchOptions.Default;
  Options.ItemFilter := TItemFilter.Only([101, 201]);
  Groups := FixedSearch('mica', 10, Options);
  Assert.AreEqual<NativeInt>(1, Length(Groups));
  Assert.AreEqual(101, Groups[0].ItemId);
  Options.ItemFilter := TItemFilter.Only([201]);
  Assert.AreEqual<NativeInt>(0, Length(FixedSearch('mica', 10, Options)), 'only an invisible item is allowed');
  Groups := FFixedSearcher.Search('mica', [1, 2], 10, Options);
  Assert.AreEqual<NativeInt>(1, Length(Groups), 'control: the item is found when its project is visible');
  Assert.AreEqual(201, Groups[0].ItemId);
  Assert.AreEqual(2, Groups[0].ProjectId);
end;

procedure TFixedHybridSearchTests.InactiveItemFilterKeepsEveryGroup;
var
  Plain, Inactive: TArray<THybridGroup>;
  Options: THybridSearchOptions;
begin
  OpenFixed('filter-inactive');
  FFixedSource.Place(101, 1);
  FFixedSource.Place(201, 1);
  AddFixed('a', 101, 'mica quartz', 10);
  AddFixed('b', 201, 'mica', 40);
  Plain := FixedSearch('mica', 10, THybridSearchOptions.Default);
  Assert.AreEqual<NativeInt>(2, Length(Plain));
  Options := THybridSearchOptions.Default;
  Options.ItemFilter := TItemFilter.Only([101]);
  Options.ItemFilter.Active := False;
  Inactive := FixedSearch('mica', 10, Options);
  Assert.AreEqual(Describe(Plain), Describe(Inactive));
  Assert.AreEqual(Plain[0].Score, Inactive[0].Score, 0);
  Assert.AreEqual(Plain[1].Score, Inactive[1].Score, 0);
end;

procedure TFixedHybridSearchTests.FusionOrdersAndTiesByKey;
var
  Store: TSearchIndexStore;
  Source: TFixedSource;
  Document: ISearchDocumentSource;
  Embedder: ITextEmbedder;
  Searcher: THybridSearcher;
  Hits: TArray<THybridGroup>;
begin
  Embedder := TControlledEmbedder.Create;
  Source := TFixedSource.Create;
  Document := Source;
  Source.Place(101, 1);
  Source.Place(102, 1);
  Source.Place(103, 1);
  Source.Place(104, 1);
  Source.Place(201, 2);
  Store := TSearchIndexStore.Open(TPath.Combine(FRoot, 'fusion.sqlite'), Embedder.Identity,
    Embedder.Dimension);
  try
    Store.Upsert(FusionPassage('k-a', 101, 1, 'mica'), AngleVector(20));
    Store.Upsert(FusionPassage('k-b', 102, 1, 'mica'), AngleVector(10));
    Store.Upsert(FusionPassage('k-d', 103, 1, 'noise'), AngleVector(30));
    Store.Upsert(FusionPassage('k-t', 104, 1, 'SMP-2024-017'), AngleVector(40));
    Store.Upsert(FusionPassage('k-x', 201, 2, 'mica quartz'), AngleVector(0));
    Searcher := THybridSearcher.Create(Store, Embedder, Document);
    try
      Hits := Searcher.Search('mica quartz', [1], 10, THybridSearchOptions.Default);
      Assert.AreEqual('k-a:VW;k-b:VW;k-d:V;k-t:V', Describe(Hits));
      Assert.AreEqual(Double(1 / (DefaultRrfK + 1) + 1 / (DefaultRrfK + 2)), Hits[0].Score, 1e-12);
      Assert.AreEqual(Hits[0].Score, Hits[1].Score, 1e-12, 'tie is exact');
      Assert.AreEqual(Double(1 / (DefaultRrfK + 3)), Hits[2].Score, 1e-12);
      Assert.AreEqual('mica', Hits[0].Passages[0].Snippet);
      Assert.AreEqual(101, Hits[0].ItemId);
      Assert.AreEqual(1, Hits[0].ProjectId);

      Assert.AreEqual('k-a:VW;k-b:VW', Describe(Searcher.Search('mica quartz', [1], 2, THybridSearchOptions.Default)));

      Hits := Searcher.Search('2024-01', [1], 10, THybridSearchOptions.Default);
      Assert.AreEqual('k-t:VT;k-b:V;k-a:V;k-d:V', Describe(Hits));

      Hits := Searcher.Search('mica quartz', [1, 2], 10, THybridSearchOptions.Default);
      Assert.AreEqual('k-x:VWT', Copy(Describe(Hits), 1, 7));
      Assert.AreEqual(2, Hits[0].ProjectId);
    finally
      Searcher.Free;
    end;
  finally
    Store.Free;
  end;
end;

function TSearchIndexStoreTests.ExternalCount(const Sql: string): Integer;
var
  Db, Stmt: Pointer;
  Tail: PChar;
begin
  Assert.IsTrue(LoadSQLiteLibrary);
  Db := nil;
  Assert.AreEqual(SQLITE_OK, f_sqlite3_open16(PChar(FPath), Db));
  try
    Stmt := nil;
    try
      Assert.AreEqual(SQLITE_OK, f_sqlite3_prepare16_v2(Db, PChar(Sql), -1, Stmt, Tail));
      Assert.AreEqual(SQLITE_ROW, f_sqlite3_step(Stmt));
      Result := StrToInt(string(f_sqlite3_column_text16(Stmt, 0)));
    finally
      f_sqlite3_finalize(Stmt);
    end;
  finally
    f_sqlite3_close(Db);
  end;
end;

procedure TSearchIndexStoreTests.SyncFromTwoThreads(FreshPath: Boolean);
const
  PassageCount = 70;
var
  Passages: TSearchPassages;
  Threads: array[0..1] of TThread;
  Errors: array[0..1] of string;
  I: Integer;

  function MakeThread(Index: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        Store: TSearchIndexStore;
        Indexer: TSearchIndexer;
        Embedder: ITextEmbedder;
      begin
        try
          Embedder := TFakeEmbedder.Create(StoreIdentity);
          Store := TSearchIndexStore.Open(FPath, StoreIdentity, StoreDim);
          try
            Indexer := TSearchIndexer.Create(TPassageSnapshotSource.Create(Passages), Store, Embedder);
            try
              Indexer.Sync;
            finally
              Indexer.Free;
            end;
          finally
            Store.Free;
          end;
        except
          on E: Exception do
            Errors[Index] := E.ClassName + ': ' + E.Message;
        end;
      end);
    Result.FreeOnTerminate := False;
  end;

begin
  FreeAndNil(FStore);
  if FreshPath then
    TFile.Delete(FPath);
  SetLength(Passages, PassageCount);
  for I := 0 to PassageCount - 1 do
    Passages[I] := Passage('k' + IntToStr(I), 1 + I mod 3, 'passage number ' + IntToStr(I));
  for I := 0 to 1 do
  begin
    Errors[I] := '';
    Threads[I] := MakeThread(I);
  end;
  for I := 0 to 1 do
    Threads[I].Start;
  for I := 0 to 1 do
  begin
    Threads[I].WaitFor;
    Threads[I].Free;
  end;
  Assert.AreEqual('', Errors[0]);
  Assert.AreEqual('', Errors[1]);
  FStore := TSearchIndexStore.Open(FPath, StoreIdentity, StoreDim);
  Assert.AreEqual(PassageCount, CatalogCount);
  Assert.AreEqual(PassageCount, ExternalCount('SELECT COUNT(*) FROM passages'));
end;

procedure TSearchIndexStoreTests.TwoStoresSyncSameFile;
begin
  SyncFromTwoThreads(False);
end;

procedure TSearchIndexStoreTests.TwoStoresOpenFreshPathConcurrently;
var
  I: Integer;
begin
  for I := 1 to 5 do
    SyncFromTwoThreads(True);
end;

procedure TSearchIndexStoreTests.IncompatibleStoreResetWithoutDelete;
var
  Other: TSearchIndexStore;
  Catalog: TDictionary<string, TStoredPassage>;
begin
  FStore.Upsert(Passage('a', 1, 'alpha'), Vec(StoreDim, 0));
  Other := TSearchIndexStore.Open(FPath, 'other-embedder', StoreDim);
  try
    Assert.IsTrue(Other.WasReset);
    Assert.AreEqual(0, ExternalCount('SELECT COUNT(*) FROM passages'));
    try
      Catalog := FStore.ReadCatalog;
      Catalog.Free;
    except
      on ESearchIndexError do;
    end;
  finally
    Other.Free;
  end;
end;

constructor TStagePipeline.Create(Store: TSearchIndexStore);
begin
  inherited Create;
  FRegistry := TTextExtractorRegistry.Create('');
  FExtractor := TCountingExtractor.Create;
  FExtractorRef := FExtractor;
  FRegistry.Register(FExtractorRef, ['.dbl']);
  FReader := TMemoryFileReader.Create;
  FReaderRef := FReader;
  FStage := TFileTextStage.Create(Store, FRegistry);
end;

destructor TStagePipeline.Destroy;
begin
  FStage.Free;
  FRegistry.Free;
  inherited;
end;

procedure TStagePipeline.Put(Id: Int64; const Text: string);
begin
  FReader.Put('f' + IntToStr(Id), TEncoding.UTF8.GetBytes(Text));
end;

function TStagePipeline.Run(const Ids: array of Int64; const Cancelled: TCancelCheck): TSearchPassages;
var
  Files: TArray<TFileTextRequest>;
  I: Integer;
begin
  SetLength(Files, Length(Ids));
  for I := 0 to High(Ids) do
  begin
    Files[I].FileId := Ids[I];
    Files[I].ItemId := 10;
    Files[I].ProjectId := 1;
    Files[I].Ext := '.dbl';
    Files[I].RelativePath := 'f' + IntToStr(Ids[I]);
  end;
  Result := FStage.BuildFilePassages(Files, FReaderRef, Cancelled, nil);
end;

function TStagePipeline.RunFiles(const Files: TArray<TFileTextRequest>;
  const Progress: TSyncProgress): TSearchPassages;
begin
  Result := FStage.BuildFilePassages(Files, FReaderRef, nil, Progress);
end;

function TStagePipeline.CachedFiles(const Files: TArray<TFileTextRequest>): TSearchPassages;
begin
  Result := FStage.CachedFilePassages(Files);
end;

procedure TFileTextStageTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-FileText-' + TGUID.NewGuid.ToString);
  ForceDirectories(FRoot);
  FStore := TSearchIndexStore.Open(TPath.Combine(FRoot, 'stage.sqlite'), 'stage-test', StoreDim);
  FA := TStagePipeline.Create(FStore);
end;

procedure TFileTextStageTests.TearDown;
begin
  FreeAndNil(FA);
  FreeAndNil(FStore);
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TFileTextStageTests.CachedMd5(Id: Int64): string;
var
  Extractor, Text: string;
  Outcome: TExtractOutcome;
begin
  if not FStore.ReadFileText(Id, Result, Extractor, Outcome, Text) then
    Result := '';
end;

procedure TFileTextStageTests.FileTextCachedByContent;
var
  Passages: TSearchPassages;
begin
  FA.Put(1, 'alpha beta');
  Passages := FA.Run([1]);
  Assert.AreEqual<NativeInt>(1, Length(Passages));
  Assert.AreEqual('file:1:text#0', Passages[0].Key);
  Assert.AreEqual(Ord(pfFileText), Ord(Passages[0].Field));
  Assert.AreEqual(1, FA.Extractor.Calls);
  Passages := FA.Run([1]);
  Assert.AreEqual<NativeInt>(1, Length(Passages));
  Assert.AreEqual(1, FA.Extractor.Calls, 'second run uses the cache');
end;

procedure TFileTextStageTests.ChangedBytesReExtract;
var
  Passages: TSearchPassages;
begin
  FA.Put(1, 'one');
  FA.Run([1]);
  FA.Put(1, 'two words');
  Passages := FA.Run([1]);
  Assert.AreEqual(2, FA.Extractor.Calls);
  Assert.AreEqual('two words', Passages[0].Text);
end;

procedure TFileTextStageTests.DeletedFileLosesPassagesAndCacheRow;
var
  Passages: TSearchPassages;
begin
  FA.Put(1, 'first');
  FA.Put(2, 'second');
  Assert.AreEqual<NativeInt>(2, Length(FA.Run([1, 2])));
  Assert.IsTrue(CachedMd5(2) <> '');
  Passages := FA.Run([1]);
  Assert.AreEqual<NativeInt>(1, Length(Passages));
  Assert.AreEqual('file:1:text#0', Passages[0].Key);
  Assert.AreEqual('', CachedMd5(2));
  Assert.IsTrue(CachedMd5(1) <> '');
end;

procedure TFileTextStageTests.CachedFailureRetriedAfterBytesChange;
begin
  FA.Put(1, 'BAD data');
  Assert.AreEqual<NativeInt>(0, Length(FA.Run([1])));
  Assert.AreEqual(1, FA.Extractor.Calls);
  Assert.IsTrue(CachedMd5(1) <> '');
  Assert.AreEqual<NativeInt>(0, Length(FA.Run([1])));
  Assert.AreEqual(1, FA.Extractor.Calls, 'failure is cached');
  FA.Put(1, 'good data');
  Assert.AreEqual<NativeInt>(1, Length(FA.Run([1])));
  Assert.AreEqual(2, FA.Extractor.Calls);
end;

procedure TFileTextStageTests.ExtractorVersionBumpReExtracts;
var
  Md5, Extractor, Text: string;
  Outcome: TExtractOutcome;
begin
  FA.Put(1, 'versioned');
  FA.Run([1]);
  Assert.AreEqual(1, FA.Extractor.Calls);
  FA.Extractor.CurrentVersion := 2;
  FA.Run([1]);
  Assert.AreEqual(2, FA.Extractor.Calls);
  Assert.IsTrue(FStore.ReadFileText(1, Md5, Extractor, Outcome, Text));
  Assert.AreEqual('dbl:2', Extractor);
  Assert.AreEqual(Ord(eoText), Ord(Outcome));
end;

procedure TFileTextStageTests.TwoPipelinesSameStoreNoReembed;
var
  Fake: TFakeEmbedder;
  Embedder: ITextEmbedder;
  Other: TStagePipeline;
  Indexer: TSearchIndexer;
  Stats: TSyncStats;
  Passages: TSearchPassages;
  I: Integer;
begin
  Fake := TFakeEmbedder.Create('pipe');
  Embedder := Fake;
  for I := 1 to 3 do
    FA.Put(I, 'shared text ' + IntToStr(I));
  Passages := FA.Run([1, 2, 3]);
  Indexer := TSearchIndexer.Create(TPassageSnapshotSource.Create(Passages), FStore, Embedder);
  try
    Indexer.Sync;
  finally
    Indexer.Free;
  end;
  Assert.AreEqual(3, Fake.Encoded);
  Other := TStagePipeline.Create(FStore);
  try
    for I := 1 to 3 do
      Other.Put(I, 'shared text ' + IntToStr(I));
    Passages := Other.Run([1, 2, 3]);
    Indexer := TSearchIndexer.Create(TPassageSnapshotSource.Create(Passages), FStore, Embedder);
    try
      Stats := Indexer.Sync;
    finally
      Indexer.Free;
    end;
    Assert.AreEqual(0, Other.Extractor.Calls, 'second pipeline extracts nothing');
  finally
    Other.Free;
  end;
  Assert.AreEqual(0, Stats.Added + Stats.Changed);
  Assert.AreEqual(3, Fake.Encoded, 'no passage is embedded twice');
end;

procedure TFileTextStageTests.CancelDuringExtraction;
var
  Passages: TSearchPassages;
begin
  FA.Put(1, 'a');
  FA.Put(2, 'b');
  FA.Put(3, 'c');
  FA.Put(4, 'd');
  FA.Put(5, 'e');
  FA.Extractor.DelayMs := 50;
  Assert.WillRaise(
    procedure
    begin
      FA.Run([1, 2, 3, 4, 5],
        function: Boolean
        begin
          Result := FA.Extractor.Calls >= 2;
        end);
    end, EOperationCancelled);
  Assert.AreEqual(2, FA.Extractor.Calls);
  FA.Extractor.DelayMs := 0;
  Passages := FA.Run([1, 2, 3, 4, 5]);
  Assert.AreEqual<NativeInt>(5, Length(Passages));
  Assert.AreEqual(5, FA.Extractor.Calls, 'finished files stay cached');
end;

procedure TFileTextStageTests.OversizeFileCachedBySize;
var
  Md5, Extractor, Text: string;
  Outcome: TExtractOutcome;
begin
  FA.Reader.PutSize('f1', FileTextMaxBytes + 1);
  Assert.AreEqual<NativeInt>(0, Length(FA.Run([1])));
  Assert.AreEqual(0, FA.Extractor.Calls);
  Assert.IsTrue(FStore.ReadFileText(1, Md5, Extractor, Outcome, Text));
  Assert.AreEqual('size:' + IntToStr(FileTextMaxBytes + 1), Md5);
  Assert.AreEqual(Ord(eoTooLarge), Ord(Outcome));
  FA.Reader.PutSize('f1', FileTextMaxBytes + 2);
  FA.Run([1]);
  Assert.AreEqual('size:' + IntToStr(FileTextMaxBytes + 2), CachedMd5(1));
end;

procedure TFileTextStageTests.LimitReachedKeepsText;
var
  Passages: TSearchPassages;
  Md5, Extractor, Text: string;
  Outcome: TExtractOutcome;
begin
  FA.Put(1, 'LIMIT partial text');
  Passages := FA.Run([1]);
  Assert.AreEqual<NativeInt>(1, Length(Passages));
  Assert.IsTrue(FStore.ReadFileText(1, Md5, Extractor, Outcome, Text));
  Assert.AreEqual(Ord(eoLimitReached), Ord(Outcome));
  Assert.AreEqual('LIMIT partial text', Text);
  Passages := FA.Run([1]);
  Assert.AreEqual<NativeInt>(1, Length(Passages));
  Assert.AreEqual(1, FA.Extractor.Calls);
end;

procedure TFileTextStageTests.UnavailableExtractorWritesNoRow;
begin
  FA.Put(1, 'later text');
  FA.Extractor.Unavailable := True;
  Assert.AreEqual<NativeInt>(0, Length(FA.Run([1])));
  Assert.AreEqual('', CachedMd5(1));
  FA.Extractor.Unavailable := False;
  Assert.AreEqual<NativeInt>(1, Length(FA.Run([1])));
  Assert.AreEqual(2, FA.Extractor.Calls);
end;

procedure TFileTextStageTests.UnexpectedExceptionNotCached;
begin
  FA.Put(1, 'first');
  FA.Put(2, 'second');
  FA.Extractor.RaiseOnce := True;
  Assert.AreEqual<NativeInt>(1, Length(FA.Run([1, 2])));
  Assert.AreEqual('', CachedMd5(1));
  Assert.AreEqual<NativeInt>(2, Length(FA.Run([1, 2])));
  Assert.IsTrue(CachedMd5(1) <> '');
end;

procedure TFileTextStageTests.ProgressReportsFiles;
var
  Last, Total, Calls: Integer;
  Files: TArray<TFileTextRequest>;
begin
  FA.Put(1, 'a');
  FA.Put(2, 'b');
  SetLength(Files, 2);
  Files[0].FileId := 1; Files[0].Ext := '.dbl'; Files[0].RelativePath := 'f1';
  Files[1].FileId := 2; Files[1].Ext := '.dbl'; Files[1].RelativePath := 'f2';
  Last := 0; Total := 0; Calls := 0;
  FA.RunFiles(Files,
    procedure(Done, Count: Integer)
    begin
      Last := Done;
      Total := Count;
      Inc(Calls);
    end);
  Assert.AreEqual(2, Last);
  Assert.AreEqual(2, Total);
  Assert.AreEqual(2, Calls);
end;

procedure TFileTextStageTests.EverySupportedExtensionHasExtractor;
var
  Registry: TTextExtractorRegistry;
  Ext: string;
begin
  Registry := TTextExtractorRegistry.Create('');
  try
    for Ext in SupportedFileTextExtensions do
      Assert.IsNotNull(Registry.ForExtension(Ext), Ext);
  finally
    Registry.Free;
  end;
end;

procedure TFileTextStageTests.UnreadableFileGivesNoPassageAndNoCacheRow;
begin
  FA.Put(1, 'locked');
  FA.Reader.MakeUnreadable('f1');
  Assert.AreEqual<NativeInt>(0, Length(FA.Run([1])));
  Assert.AreEqual('', CachedMd5(1));
  Assert.AreEqual(0, FA.Extractor.Calls);
end;

procedure TSearchIndexStoreTests.FileTextRoundTripAndPrune;
var
  Md5, Extractor, Text: string;
  Outcome: TExtractOutcome;
begin
  FStore.WriteFileText(1, 'AA', 'e:1', eoText, 'ok', 'пленка text');
  Assert.IsTrue(FStore.ReadFileText(1, Md5, Extractor, Outcome, Text));
  Assert.AreEqual('AA', Md5);
  Assert.AreEqual('e:1', Extractor);
  Assert.AreEqual(Ord(eoText), Ord(Outcome));
  Assert.AreEqual('пленка text', Text);
  FStore.WriteFileText(1, 'BB', 'e:2', eoCorrupt, 'bad', '');
  Assert.IsTrue(FStore.ReadFileText(1, Md5, Extractor, Outcome, Text));
  Assert.AreEqual('BB', Md5);
  Assert.AreEqual(Ord(eoCorrupt), Ord(Outcome));
  FStore.WriteFileText(2, 'CC', 'e:1', eoNoText, '', '');
  FStore.WriteFileText(3, 'DD', 'e:1', eoText, '', 'three');
  FStore.DeleteFileTextExcept([2]);
  Assert.IsFalse(FStore.ReadFileText(1, Md5, Extractor, Outcome, Text));
  Assert.IsTrue(FStore.ReadFileText(2, Md5, Extractor, Outcome, Text));
  Assert.IsFalse(FStore.ReadFileText(3, Md5, Extractor, Outcome, Text));
  Assert.AreEqual(1, ExternalCount('SELECT COUNT(*) FROM file_text'));
end;

procedure TSearchIndexStoreTests.SchemaV1StoreRebuilds;
var
  Md5, Extractor, Text: string;
  Outcome: TExtractOutcome;
begin
  FStore.Upsert(Passage('a', 1, 'alpha'), Vec(StoreDim, 0));
  FreeAndNil(FStore);
  ExecExternal('DROP TABLE file_text');
  ExecExternal('UPDATE meta SET value = ''1'' WHERE key = ''schema_version''');
  FStore := TSearchIndexStore.Open(FPath, StoreIdentity, StoreDim);
  Assert.IsTrue(FStore.WasReset, 'version 1 store is rebuilt');
  Assert.AreEqual(0, CatalogCount);
  FStore.WriteFileText(1, 'AA', 'e:1', eoText, '', 'text');
  Assert.IsTrue(FStore.ReadFileText(1, Md5, Extractor, Outcome, Text));
end;

procedure TSearchIndexStoreTests.ItemFilterRestrictsTextLists;
var
  Hits: TArray<TTextHit>;
  Filter: TItemFilter;
begin
  FStore.Upsert(ItemPassage('p11', 1, 11, 'shared word'), Vec(StoreDim, 0));
  FStore.Upsert(ItemPassage('p12', 1, 12, 'shared word'), Vec(StoreDim, 1));
  FStore.Upsert(ItemPassage('p13', 2, 13, 'shared word'), Vec(StoreDim, 2));
  Assert.AreEqual('p12;', Keys(FStore.MatchWords('shared', [1, 2], 10, TItemFilter.Only([12]))));
  Assert.AreEqual('p12;', Keys(FStore.MatchTrigrams('shared', [1, 2], 10, TItemFilter.Only([12]))));
  Hits := FStore.MatchWords('shared', [1, 2], 10, TItemFilter.Only([13]));
  Assert.AreEqual<NativeInt>(1, Length(Hits));
  Assert.AreEqual(1, Hits[0].Rank, 'rank counts the filtered list');
  Assert.AreEqual('p11;p12;', Keys(FStore.MatchWords('shared', [1, 2], 10, TItemFilter.Only([11, 12, 99]))));
  Assert.AreEqual('', Keys(FStore.MatchWords('shared', [1, 2], 10, TItemFilter.Only([]))));
  Assert.AreEqual('', Keys(FStore.MatchTrigrams('shared', [1, 2], 10, TItemFilter.Only([]))));
  Assert.AreEqual('', Keys(FStore.MatchWords('shared', [1], 10, TItemFilter.Only([13]))), 'item outside the project list');
  Assert.AreEqual('', Keys(FStore.MatchTrigrams('shared', [1], 10, TItemFilter.Only([13]))), 'item outside the project list');
  Filter := TItemFilter.Only([12]);
  Filter.Active := False;
  Assert.AreEqual('p11;p12;p13;', Keys(FStore.MatchWords('shared', [1, 2], 10, Filter)));
  Assert.AreEqual('p11;p12;p13;', Keys(FStore.MatchTrigrams('shared', [1, 2], 10, Filter)));
end;

procedure TSearchIndexStoreTests.ItemFilterAppliesBeforeLimit;
var
  I: Integer;
begin
  for I := 1 to 60 do
    FStore.Upsert(ItemPassage(Format('k%.2d', [I]), 1, I, 'alpha'), Vec(StoreDim, I));
  FStore.Upsert(ItemPassage('z900', 1, 900, 'alpha beta gamma delta epsilon zeta eta theta'), Vec(StoreDim, 0));
  Assert.AreEqual<NativeInt>(50, Length(FStore.MatchWords('alpha', [1], 50, Default(TItemFilter))));
  Assert.IsFalse(Keys(FStore.MatchWords('alpha', [1], 50, Default(TItemFilter))).Contains('z900'), 'control: below the cut');
  Assert.IsFalse(Keys(FStore.MatchTrigrams('alpha', [1], 50, Default(TItemFilter))).Contains('z900'), 'control: below the cut');
  Assert.AreEqual('z900;', Keys(FStore.MatchWords('alpha', [1], 1, TItemFilter.Only([900]))));
  Assert.AreEqual('z900;', Keys(FStore.MatchTrigrams('alpha', [1], 1, TItemFilter.Only([900]))));
end;

procedure TSearchIndexStoreTests.ItemFilterFollowsMovedItem;
var
  P: TSearchPassage;
begin
  P := ItemPassage('a', 1, 101, 'moving word');
  FStore.Upsert(P, Vec(StoreDim, 0));
  P.ProjectId := 2;
  P.ItemId := 555;
  FStore.UpdateCoordinates(P);
  Assert.AreEqual('', Keys(FStore.MatchWords('moving', [2], 10, TItemFilter.Only([101]))));
  Assert.AreEqual('a;', Keys(FStore.MatchWords('moving', [2], 10, TItemFilter.Only([555]))));
  Assert.AreEqual('a;', Keys(FStore.MatchTrigrams('moving', [2], 10, TItemFilter.Only([555]))));
end;

procedure TSearchIndexStoreTests.ItemIndexIsCreatedOnExistingStore;
const
  IndexCount = 'SELECT COUNT(*) FROM sqlite_master WHERE type = ''index'' AND name = ''passages_item''';
begin
  Assert.AreEqual(1, ExternalCount(IndexCount), 'new store');
  FStore.Upsert(ItemPassage('a', 1, 5, 'keepword'), Vec(StoreDim, 0));
  FreeAndNil(FStore);
  ExecExternal('DROP INDEX passages_item');
  Assert.AreEqual(0, ExternalCount(IndexCount));
  FStore := TSearchIndexStore.Open(FPath, StoreIdentity, StoreDim);
  Assert.IsFalse(FStore.WasReset, 'the index is additive');
  Assert.AreEqual(1, CatalogCount);
  Assert.AreEqual(1, ExternalCount(IndexCount));
  Assert.AreEqual(1, ExternalCount('SELECT COUNT(*) FROM meta WHERE key = ''schema_version'' AND value = ''2'''));
end;

procedure TFileTextStageTests.UnchangedFilesAreNotReadAgain;
var
  Passages: TSearchPassages;
  ReadsAfterFirst: Integer;
begin
  FA.Put(1, 'alpha beta');
  FA.Put(2, 'gamma delta');
  Assert.AreEqual<NativeInt>(2, Length(FA.Run([1, 2])));
  ReadsAfterFirst := FA.Reader.Reads;
  Assert.AreEqual(2, ReadsAfterFirst);
  Passages := FA.Run([1, 2]);
  Assert.AreEqual<NativeInt>(2, Length(Passages));
  Assert.AreEqual(ReadsAfterFirst, FA.Reader.Reads, 'second sync reads no file');
  Assert.AreEqual(2, FA.Extractor.Calls);
end;

procedure TFileTextStageTests.TouchedFileWithSameBytesIsReadOnce;
begin
  FA.Put(1, 'alpha beta');
  FA.Run([1]);
  FA.Put(1, 'alpha beta');
  Assert.AreEqual<NativeInt>(1, Length(FA.Run([1])));
  Assert.AreEqual(2, FA.Reader.Reads, 'a new last-write time forces one read');
  Assert.AreEqual(1, FA.Extractor.Calls, 'the same bytes are not extracted again');
  FA.Run([1]);
  Assert.AreEqual(2, FA.Reader.Reads, 'the stamp is stored after the touch');
end;

procedure TFileTextStageTests.ChangedStampRewritesText;
var
  Passages: TSearchPassages;
begin
  FA.Put(1, 'one');
  FA.Run([1]);
  FA.Put(1, 'two words');
  Passages := FA.Run([1]);
  Assert.AreEqual('two words', Passages[0].Text);
  Assert.AreEqual(2, FA.Reader.Reads);
end;

procedure TFileTextStageTests.ReaderWithoutStampsReadsEverySync;
begin
  FA.Reader.NoStamps := True;
  FA.Put(1, 'alpha beta');
  FA.Run([1]);
  FA.Run([1]);
  Assert.AreEqual(2, FA.Reader.Reads);
  Assert.AreEqual(1, FA.Extractor.Calls, 'the content hash still avoids extraction');
end;

procedure TFileTextStageTests.CachedPassagesKeepUnvisitedFiles;
var
  Files: TArray<TFileTextRequest>;
  Passages: TSearchPassages;
begin
  FA.Put(1, 'alpha beta');
  FA.Put(2, 'gamma delta');
  FA.Run([1, 2]);
  SetLength(Files, 3);
  Files[0].FileId := 1;
  Files[1].FileId := 2;
  Files[2].FileId := 3;
  Passages := FA.CachedFiles(Files);
  Assert.AreEqual<NativeInt>(2, Length(Passages));
end;

initialization
  TDUnitX.RegisterTestFixture(TPassageChunkerTests);
  TDUnitX.RegisterTestFixture(TSearchIndexStoreTests);
  TDUnitX.RegisterTestFixture(TFileTextStageTests);
  TDUnitX.RegisterTestFixture(TFixedHybridSearchTests);

end.
