unit test_SemanticSearchService;

interface

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections, DUnitX.TestFramework, unit_SearchPassages,
  unit_SearchIndexStore, unit_TextEmbedder, unit_HybridSearch, unit_SemanticSearchApi,
  unit_SemanticSearchService, unit_TextExtractors, unit_CrossEncoder, unit_PassageContext,
  test_SearchDoubles;

type
  TAllLiveSource = class(TInterfacedObject, ISearchDocumentSource)
  public
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  TSelectiveLiveSource = class(TInterfacedObject, ISearchDocumentSource)
  public
    DeadItem: Integer;
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  TThreadProbeSource = class(TInterfacedObject, ISearchDocumentSource)
  private
    FProject: Integer;
  public
    Threads: TArray<TThreadID>;
    constructor Create(Project: Integer = 1);
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  TBlockingLiveSource = class(TInterfacedObject, ISearchDocumentSource)
  public
    Armed: Boolean;
    Entered, Release: TEvent;
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  [TestFixture]
  TSemanticSearchServiceTests = class
  private
    FRoot: string;
    FStorePath: string;
    FFake: TFakeEmbedder;
    FEmbedderRef: ITextEmbedder;
    FFactoryRuns: Integer;
    FService: TSemanticSearchService;
    FCross: TFakeCrossEncoder;
    FCrossRef: ICrossEncoder;
    FCrossRuns: Integer;
    FResolveCalls: Integer;
    FResolvedIds: TArray<Integer>;
    FAllowedItems: TArray<Integer>;
    FFilterError: string;
    procedure OpenService(BatchDelayMs: Cardinal);
    procedure OpenRerankServiceWith(const CrossFactory: TCrossEncoderFactory;
      const Live: ISearchDocumentSource);
    procedure OpenRerankService;
    procedure SyncPassages(Count: Integer);
    function KeysOf(const Groups: TArray<THybridGroup>): string;
    function PlainOptions: THybridSearchOptions;
    function ContextPartsOf(const Title: string): TPassageContextParts;
    function LocalSearch: ISemanticSearch;
    function RequestFor(const Query: string; TopK: Integer): TSemanticSearchRequest;
{$IFDEF MSWINDOWS}
    procedure StopCycle(const StorePath: string);
    function AllocatedBlocks: NativeInt;
{$ENDIF}
    function MakePassages(Count: Integer): TSearchPassages;
    function WaitUntilIdle(TimeoutMs: Cardinal): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SearchWhileSyncing;
    [Test]
    procedure SearchWaitsAtMostOneBatch;
{$IFDEF MSWINDOWS}
    [Test]
    procedure DestroyDuringSyncStopsWorker;
{$ENDIF}
    [Test]
    procedure SecondStartSyncIgnoredWhileRunning;
    [Test]
    procedure StatusReportsExtractionThenEmbeddingPhase;
    [Test]
    procedure CancelDuringLastFileIsIncomplete;
    [Test]
    procedure NeverSyncedIsNotComplete;
    [Test]
    procedure OnDoneQueuedOnMainThread;
    [Test]
    procedure SyncNowRespectsDeadline;
    [Test]
    procedure FactoryFailureMakesUnavailable;
    [Test]
    procedure CancelSyncLeavesPending;
    [Test]
    procedure UserCancelDuringFilePhaseSkipsEmbedding;
    [Test]
    procedure SyncNowWhileSyncingDoesNothing;
    [Test]
    procedure SearchFindsSyncedPassage;
    [Test]
    procedure SearchNotBlockedByExtraction;
    [Test]
    procedure DeadlineDuringFilePhaseStillEmbedsItemPassages;
    [Test]
    procedure RerankReordersTheTopTwentyOnly;
    [Test]
    procedure RerankedTopKCutsAfterReordering;
    [Test]
    procedure DepthLargerThanTheListReordersTheWholeList;
    [Test]
    procedure NoRerankerKeepsTheHybridOrder;
    [Test]
    procedure ZeroDepthDoesNotLoadTheReranker;
    [Test]
    procedure SingleGroupIsNotReranked;
    [Test]
    procedure SlowRerankerPastTheBudgetReturnsTheHybridOrder;
    [Test]
    procedure RerankerThatIgnoresCancelPastTheBudgetReturnsTheHybridOrder;
    [Test]
    procedure RerankerErrorReturnsTheHybridOrder;
    [Test]
    procedure LoadFailureDisablesTheReranker;
    [Test]
    procedure SyncDuringRerankDoesNotWait;
    [Test]
    procedure RerankedListHasOnlyLiveGroups;
    [Test]
    procedure RerankInputIsContextAndBestPassageOfEachGroup;
    [Test]
    procedure ItemContextIsReplacedAtEverySync;
    [Test]
    procedure RunnerDeliversOnTheMainThread;
    [Test]
    procedure RunnerReportsTheFailureText;
    [Test]
    procedure FreeingTheRunnerDropsTheDelivery;
    [Test]
    procedure NewerSearchCancelsTheRunningRerank;
    [Test]
    procedure MainThreadSourceRunsTheInnerSourceOnTheMainThread;
    [Test]
    procedure RunnerRunsTheLiveChecksOnTheMainThread;
    [Test]
    procedure LocalSearchMapsTheRequest;
    [Test]
    procedure LocalSearchResolvesTheFilterAndEchoesIt;
    [Test]
    procedure LocalSearchKeepsTheFilterErrorMessage;
    [Test]
    procedure MainThreadResolverRunsOnTheMainThread;
    [Test]
    procedure StatusAndRerankerAvailableDoNotWaitForARunningSearch;
    [Test]
    procedure ConcurrentSearchesCheckLivenessOnTheirOwnSources;
    [Test]
    procedure NilLiveSourceUsesTheServiceSource;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Diagnostics, System.Math, System.JSON,
  unit_VectorSearch, unit_LocalSemanticSearch, unit_MainThreadSearchSource;

type
  TSearchRoundsThread = class(TThread)
  private
    FService: TSemanticSearchService;
    FSource: ISearchDocumentSource;
    FGo: TEvent;
    FRounds: Integer;
  protected
    procedure Execute; override;
  public
    SearchThread: TThreadID;
    Projects: TArray<Integer>;
    Failure: string;
    constructor Create(Service: TSemanticSearchService; const Source: ISearchDocumentSource;
      Go: TEvent; Rounds: Integer);
  end;

const
  FakeIdentity = 'fake-service';
  BigDeadlineMs = 60000;

constructor TSearchRoundsThread.Create(Service: TSemanticSearchService;
  const Source: ISearchDocumentSource; Go: TEvent; Rounds: Integer);
begin
  inherited Create(False);
  FService := Service;
  FSource := Source;
  FGo := Go;
  FRounds := Rounds;
end;

procedure TSearchRoundsThread.Execute;
var
  Options: THybridSearchOptions;
  Groups: TArray<THybridGroup>;
  Group: THybridGroup;
  Round: Integer;
begin
  SearchThread := TThread.CurrentThread.ThreadID;
  try
    if FGo.WaitFor(10000) <> wrSignaled then
      raise Exception.Create('no start signal');
    Options := THybridSearchOptions.Default;
    Options.LiveSource := FSource;
    for Round := 1 to FRounds do
    begin
      Groups := FService.Search('passage', [1, 2], 30, Options).Groups;
      for Group in Groups do
        Projects := Projects + [Group.ProjectId];
    end;
  except
    on E: Exception do
      Failure := E.Message;
  end;
end;

function TAllLiveSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Result := Default(TSearchSnapshot);
end;

function TAllLiveSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  ProjectId := 1;
  Result := True;
end;

function TSelectiveLiveSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Result := Default(TSearchSnapshot);
end;

function TSelectiveLiveSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  ProjectId := 1;
  Result := ItemId <> DeadItem;
end;

constructor TThreadProbeSource.Create(Project: Integer);
begin
  inherited Create;
  FProject := Project;
end;

function TThreadProbeSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Threads := Threads + [TThread.CurrentThread.ThreadID];
  Result := Default(TSearchSnapshot);
end;

function TThreadProbeSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  Threads := Threads + [TThread.CurrentThread.ThreadID];
  ProjectId := FProject;
  Result := True;
end;

function TBlockingLiveSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Result := Default(TSearchSnapshot);
end;

function TBlockingLiveSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  if Armed then
  begin
    Armed := False;
    Entered.SetEvent;
    Release.WaitFor(20000);
  end;
  ProjectId := 1;
  Result := True;
end;

procedure TSemanticSearchServiceTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'eln-semantic-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FStorePath := TPath.Combine(FRoot, 'search.sqlite');
  FFactoryRuns := 0;
  FCrossRuns := 0;
end;

procedure TSemanticSearchServiceTests.TearDown;
begin
  FreeAndNil(FService);
  FEmbedderRef := nil;
  FCrossRef := nil;
  FCross := nil;
  FFake := nil;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TSemanticSearchServiceTests.OpenService(BatchDelayMs: Cardinal);
begin
  FFake := TFakeEmbedder.Create(FakeIdentity);
  FEmbedderRef := FFake;
  FFake.BatchDelayMs := BatchDelayMs;
  FService := TSemanticSearchService.Create(FStorePath,
    function: ITextEmbedder
    begin
      Inc(FFactoryRuns);
      Result := FFake;
    end, nil, TAllLiveSource.Create, '');
end;

{$IFDEF MSWINDOWS}
procedure TSemanticSearchServiceTests.StopCycle(const StorePath: string);
var
  Fake: TFakeEmbedder;
  Embedder: ITextEmbedder;
  Service: TSemanticSearchService;
begin
  Fake := TFakeEmbedder.Create(FakeIdentity);
  Fake.BatchDelayMs := 20;
  Embedder := Fake;
  Service := TSemanticSearchService.Create(StorePath,
    function: ITextEmbedder
    begin
      Result := Embedder;
    end, nil, TAllLiveSource.Create, '');
  try
    Service.StartSync(SnapshotOf(MakePassages(200)), nil, nil, nil);
    Sleep(50);
  finally
    Service.Free;
  end;
end;

function TSemanticSearchServiceTests.AllocatedBlocks: NativeInt;
var
  State: TMemoryManagerState;
  Small: TSmallBlockTypeState;
begin
  GetMemoryManagerState(State);
  Result := State.AllocatedMediumBlockCount + State.AllocatedLargeBlockCount;
  for Small in State.SmallBlockTypeStates do
    Inc(Result, Small.AllocatedBlockCount);
end;
{$ENDIF}

function TSemanticSearchServiceTests.MakePassages(Count: Integer): TSearchPassages;
var
  I: Integer;
begin
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    Result[I].Key := 'p' + IntToStr(I);
    Result[I].ProjectId := 1;
    Result[I].ItemId := 1000 + I;
    Result[I].FileId := 0;
    Result[I].Field := pfItemDescription;
    Result[I].Text := 'passage text number ' + IntToStr(I);
    Result[I].ContentHash := PassageHash(Result[I].Text);
  end;
end;

function TSemanticSearchServiceTests.WaitUntilIdle(TimeoutMs: Cardinal): Boolean;
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  repeat
    CheckSynchronize(5);
    if FService.Status.State <> ssSyncing then
      Exit(True);
  until Watch.ElapsedMilliseconds > TimeoutMs;
  Result := False;
end;

procedure TSemanticSearchServiceTests.SearchWhileSyncing;
const
  TopK = 5;
var
  Watch: TStopwatch;
  Hits: TArray<THybridGroup>;
  I: Integer;
  MaxWaitMs: Int64;
begin
  OpenService(20);
  FService.StartSync(SnapshotOf(MakePassages(200)), nil, nil, nil);
  MaxWaitMs := 0;
  for I := 1 to 10 do
  begin
    Watch := TStopwatch.StartNew;
    Hits := FService.Search('passage', [1], TopK, THybridSearchOptions.Default).Groups;
    MaxWaitMs := Max(MaxWaitMs, Watch.ElapsedMilliseconds);
    Assert.IsTrue(Length(Hits) <= TopK, 'at most TopK hits');
    Sleep(15);
  end;
  Assert.IsTrue(MaxWaitMs < 500, 'slowest search ' + IntToStr(MaxWaitMs) + ' ms');
  Assert.IsTrue(WaitUntilIdle(30000), 'sync finished');
  Assert.AreEqual(200, FService.Status.IndexedPassages);
  Assert.AreEqual<NativeInt>(TopK, Length(FService.Search('passage', [1], TopK, THybridSearchOptions.Default).Groups));
end;

procedure TSemanticSearchServiceTests.SearchWaitsAtMostOneBatch;
var
  Watch: TStopwatch;
  MaxWaitMs: Int64;
begin
  OpenService(20);
  FService.StartSync(SnapshotOf(MakePassages(1000)), nil, nil, nil);
  MaxWaitMs := 0;
  while FService.Status.State = ssSyncing do
  begin
    Watch := TStopwatch.StartNew;
    FService.Search('passage', [1], 5, THybridSearchOptions.Default);
    MaxWaitMs := Max(MaxWaitMs, Watch.ElapsedMilliseconds);
    Sleep(10);
  end;
  Assert.IsTrue(MaxWaitMs < 250, 'slowest search ' + IntToStr(MaxWaitMs) + ' ms');
  Assert.AreEqual(1000, FService.Status.IndexedPassages);
end;

{$IFDEF MSWINDOWS}
procedure TSemanticSearchServiceTests.DestroyDuringSyncStopsWorker;
var
  Watch: TStopwatch;
  Store: TSearchIndexStore;
  Catalog: TDictionary<string, TStoredPassage>;
  Before: NativeInt;
  WarmupPath, MeasuredPath: string;
begin
  WarmupPath := TPath.Combine(FRoot, 'warmup.sqlite');
  MeasuredPath := TPath.Combine(FRoot, 'measured.sqlite');
  StopCycle(WarmupPath);
  Before := AllocatedBlocks;
  StopCycle(MeasuredPath);
  Assert.AreEqual<NativeInt>(Before, AllocatedBlocks, 'memory blocks after a stopped sync');
  OpenService(20);
  FService.StartSync(SnapshotOf(MakePassages(200)), nil, nil, nil);
  Sleep(50);
  Watch := TStopwatch.StartNew;
  FreeAndNil(FService);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 1000, 'destroy took ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
  Store := TSearchIndexStore.Open(FStorePath, FakeIdentity, FFake.Dimension);
  try
    Assert.IsFalse(Store.WasReset, 'store reopens cleanly');
    Catalog := Store.ReadCatalog;
    try
      Assert.IsTrue((Catalog.Count > 0) and (Catalog.Count < 200), 'sync stopped part way');
    finally
      Catalog.Free;
    end;
  finally
    Store.Free;
  end;
end;
{$ENDIF}

procedure TSemanticSearchServiceTests.SecondStartSyncIgnoredWhileRunning;
var
  FirstDone, SecondDone: Integer;
begin
  FirstDone := 0;
  SecondDone := 0;
  OpenService(20);
  FService.StartSync(SnapshotOf(MakePassages(100)), nil, nil,
    procedure(Status: TSemanticSearchStatus)
    begin
      Inc(FirstDone);
    end);
  Assert.AreEqual(Ord(ssSyncing), Ord(FService.Status.State));
  FService.StartSync(SnapshotOf(MakePassages(100)), nil, nil,
    procedure(Status: TSemanticSearchStatus)
    begin
      Inc(SecondDone);
    end);
  Assert.IsTrue(WaitUntilIdle(30000), 'sync finished');
  CheckSynchronize(50);
  Assert.AreEqual(1, FirstDone);
  Assert.AreEqual(0, SecondDone);
  Assert.AreEqual(100, FFake.Encoded, 'one sync embedded each passage once');
end;

procedure TSemanticSearchServiceTests.OnDoneQueuedOnMainThread;
var
  Calls: Integer;
  CallbackThread: TThreadID;
  Reported: TSemanticSearchStatus;
  Watch: TStopwatch;
begin
  Calls := 0;
  CallbackThread := 0;
  OpenService(0);
  FService.StartSync(SnapshotOf(MakePassages(50)), nil, nil,
    procedure(Status: TSemanticSearchStatus)
    begin
      Inc(Calls);
      CallbackThread := TThread.CurrentThread.ThreadID;
      Reported := Status;
    end);
  Assert.IsTrue(WaitUntilIdle(30000), 'sync finished');
  Watch := TStopwatch.StartNew;
  while (Calls = 0) and (Watch.ElapsedMilliseconds < 5000) do
    CheckSynchronize(10);
  Assert.AreEqual(1, Calls);
  Assert.AreEqual<TThreadID>(MainThreadID, CallbackThread);
  Assert.AreEqual(Ord(ssIdle), Ord(Reported.State));
  Assert.AreEqual(50, Reported.IndexedPassages);
end;

procedure TSemanticSearchServiceTests.SyncNowRespectsDeadline;
var
  Passages: TSearchPassages;
  Outcome: TSyncOutcome;
begin
  OpenService(20);
  Passages := MakePassages(200);
  Outcome := FService.SyncNow(SnapshotOf(Passages), nil, 50);
  Assert.IsFalse(Outcome.Complete);
  Assert.IsTrue(FService.Status.PendingPassages > 0);
  Assert.IsTrue(FService.Status.IndexedPassages > 0);
  Assert.AreEqual(Ord(ssIdle), Ord(FService.Status.State));
  Outcome := FService.SyncNow(SnapshotOf(Passages), nil, BigDeadlineMs);
  Assert.IsTrue(Outcome.Complete);
  Assert.AreEqual(0, FService.Status.PendingPassages);
  Assert.AreEqual(200, FService.Status.IndexedPassages);
end;

procedure TSemanticSearchServiceTests.FactoryFailureMakesUnavailable;
begin
  FService := TSemanticSearchService.Create(FStorePath,
    function: ITextEmbedder
    begin
      Inc(FFactoryRuns);
      raise Exception.Create('model files missing');
    end, nil, TAllLiveSource.Create, '');
  Assert.WillRaise(
    procedure
    begin
      FService.Search('passage', [1], 5, THybridSearchOptions.Default);
    end, ESemanticSearchUnavailable, 'model files missing');
  Assert.AreEqual(Ord(ssFailed), Ord(FService.Status.State));
  Assert.AreEqual('model files missing', FService.Status.LastError);
  Assert.WillRaise(
    procedure
    begin
      FService.SyncNow(SnapshotOf(MakePassages(1)), nil, BigDeadlineMs);
    end, ESemanticSearchUnavailable);
  Assert.AreEqual(1, FFactoryRuns, 'the factory runs once');
end;

procedure TSemanticSearchServiceTests.CancelSyncLeavesPending;
var
  Indexed: Integer;
  Watch: TStopwatch;
begin
  OpenService(20);
  FService.StartSync(SnapshotOf(MakePassages(200)), nil, nil, nil);
  Watch := TStopwatch.StartNew;
  while not (FService.Status.PendingPassages in [1..199]) and (Watch.ElapsedMilliseconds < 5000) do
    Sleep(5);
  FService.CancelSync;
  Assert.IsTrue(WaitUntilIdle(5000), 'worker stopped');
  Assert.IsTrue(FService.Status.PendingPassages > 0);
  Indexed := FService.Status.IndexedPassages;
  Assert.IsTrue((Indexed > 0) and (Indexed < 200));
  Assert.IsTrue(FService.SyncNow(SnapshotOf(MakePassages(200)), nil, BigDeadlineMs).Complete);
  Assert.AreEqual(200, FService.Status.IndexedPassages);
end;

procedure TSemanticSearchServiceTests.UserCancelDuringFilePhaseSkipsEmbedding;
const
  FileCount = 40;
var
  Extractor: TCountingExtractor;
  ExtractorRef: ITextExtractor;
  Reader: TMemoryFileReader;
  ReaderRef: IFileContentReader;
  Snapshot: TSearchSnapshot;
  Watch: TStopwatch;
  ProgressCalls, I: Integer;
begin
  ProgressCalls := 0;
  OpenService(0);
  Extractor := TCountingExtractor.Create;
  ExtractorRef := Extractor;
  FService.Registry.Register(ExtractorRef, ['.dbl']);
  Reader := TMemoryFileReader.Create;
  ReaderRef := Reader;
  Reader.ReadDelayMs := 100;
  Snapshot := SnapshotOf(MakePassages(12));
  SetLength(Snapshot.Files, FileCount);
  for I := 0 to FileCount - 1 do
  begin
    Reader.Put('f' + IntToStr(I), TEncoding.UTF8.GetBytes('cancel text ' + IntToStr(I)));
    Snapshot.Files[I].FileId := I + 1;
    Snapshot.Files[I].ItemId := 1000 + I;
    Snapshot.Files[I].ProjectId := 1;
    Snapshot.Files[I].Ext := '.dbl';
    Snapshot.Files[I].RelativePath := 'f' + IntToStr(I);
  end;
  FService.StartSync(Snapshot, ReaderRef,
    procedure(Done, Total: Integer)
    begin
      Inc(ProgressCalls);
    end, nil);
  Sleep(250);
  FService.CancelSync;
  Assert.IsTrue(WaitUntilIdle(3000), 'worker stopped');
  CheckSynchronize(50);
  Assert.AreEqual(0, ProgressCalls, 'the indexer did not start after a user cancel');
  Assert.AreEqual(0, FFake.Encoded);
  Watch := TStopwatch.StartNew;
  FreeAndNil(FService);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 1000, 'destroy took ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
end;

procedure TSemanticSearchServiceTests.SyncNowWhileSyncingDoesNothing;
var
  Outcome: TSyncOutcome;
begin
  OpenService(20);
  FService.StartSync(SnapshotOf(MakePassages(100)), nil, nil, nil);
  Outcome := FService.SyncNow(SnapshotOf(MakePassages(100)), nil, BigDeadlineMs);
  Assert.IsFalse(Outcome.Complete);
  Assert.IsTrue(WaitUntilIdle(30000), 'sync finished');
  Assert.AreEqual(100, FFake.Encoded, 'only the background sync embedded');
end;

procedure TSemanticSearchServiceTests.SearchFindsSyncedPassage;
var
  Passages: TSearchPassages;
  Hits: TArray<THybridGroup>;
begin
  OpenService(0);
  Passages := MakePassages(3);
  Passages[1].Text := 'zirconium oxide film';
  Passages[1].ContentHash := PassageHash(Passages[1].Text);
  Assert.IsTrue(FService.SyncNow(SnapshotOf(Passages), nil, BigDeadlineMs).Complete);
  Hits := FService.Search('zirconium', [1], 5, THybridSearchOptions.Default).Groups;
  Assert.IsTrue(Length(Hits) > 0);
  Assert.AreEqual('p1', Hits[0].Passages[0].Key);
  Assert.IsTrue(hsWords in Hits[0].Sources);
  Assert.AreEqual<NativeInt>(0, Length(FService.Search('zirconium', [2], 5, THybridSearchOptions.Default).Groups));
end;

procedure TSemanticSearchServiceTests.SearchNotBlockedByExtraction;
const
  FileCount = 40;
var
  Extractor: TCountingExtractor;
  ExtractorRef: ITextExtractor;
  Reader: TMemoryFileReader;
  ReaderRef: IFileContentReader;
  Snapshot: TSearchSnapshot;
  Watch: TStopwatch;
  MaxWaitMs: Int64;
  I: Integer;
begin
  OpenService(0);
  Extractor := TCountingExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.DelayMs := 25;
  FService.Registry.Register(ExtractorRef, ['.dbl']);
  Reader := TMemoryFileReader.Create;
  ReaderRef := Reader;
  Snapshot := Default(TSearchSnapshot);
  SetLength(Snapshot.Files, FileCount);
  for I := 0 to FileCount - 1 do
  begin
    Reader.Put('f' + IntToStr(I), TEncoding.UTF8.GetBytes('extracted text number ' + IntToStr(I)));
    Snapshot.Files[I].FileId := I + 1;
    Snapshot.Files[I].ItemId := 1000 + I;
    Snapshot.Files[I].ProjectId := 1;
    Snapshot.Files[I].Ext := '.dbl';
    Snapshot.Files[I].RelativePath := 'f' + IntToStr(I);
  end;
  FService.StartSync(Snapshot, ReaderRef, nil, nil);
  MaxWaitMs := 0;
  while FService.Status.State = ssSyncing do
  begin
    Watch := TStopwatch.StartNew;
    FService.Search('extracted', [1], 5, THybridSearchOptions.Default);
    MaxWaitMs := Max(MaxWaitMs, Watch.ElapsedMilliseconds);
    Sleep(10);
  end;
  Assert.IsTrue(MaxWaitMs < 250, 'slowest search ' + IntToStr(MaxWaitMs) + ' ms');
  Assert.AreEqual(FileCount, FService.Status.IndexedPassages);
  Assert.AreEqual(FileCount, Extractor.Calls);
end;

procedure TSemanticSearchServiceTests.NeverSyncedIsNotComplete;
begin
  OpenService(0);
  Assert.IsFalse(FService.Status.IsComplete);
end;

procedure TSemanticSearchServiceTests.CancelDuringLastFileIsIncomplete;
const
  FileCount = 3;
var
  Extractor: TCountingExtractor;
  ExtractorRef: ITextExtractor;
  Reader: TMemoryFileReader;
  ReaderRef: IFileContentReader;
  Snapshot: TSearchSnapshot;
  I: Integer;
begin
  OpenService(0);
  Extractor := TCountingExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.OnCall :=
    procedure(Call: Integer)
    begin
      if Call = FileCount then
        FService.CancelSync;
    end;
  FService.Registry.Register(ExtractorRef, ['.dbl']);
  Reader := TMemoryFileReader.Create;
  ReaderRef := Reader;
  Snapshot := Default(TSearchSnapshot);
  SetLength(Snapshot.Files, FileCount);
  for I := 0 to FileCount - 1 do
  begin
    Reader.Put('f' + IntToStr(I), TEncoding.UTF8.GetBytes('last file text ' + IntToStr(I)));
    Snapshot.Files[I].FileId := I + 1;
    Snapshot.Files[I].ItemId := 1000 + I;
    Snapshot.Files[I].ProjectId := 1;
    Snapshot.Files[I].Ext := '.dbl';
    Snapshot.Files[I].RelativePath := 'f' + IntToStr(I);
  end;
  Assert.IsFalse(FService.SyncNow(Snapshot, ReaderRef, BigDeadlineMs).Complete);
  Assert.IsFalse(FService.Status.IsComplete);
  Assert.IsTrue(FService.SyncNow(Snapshot, ReaderRef, BigDeadlineMs).Complete);
  Assert.IsTrue(FService.Status.IsComplete);
end;

procedure TSemanticSearchServiceTests.StatusReportsExtractionThenEmbeddingPhase;
const
  FileCount = 30;
var
  Extractor: TCountingExtractor;
  ExtractorRef: ITextExtractor;
  Reader: TMemoryFileReader;
  ReaderRef: IFileContentReader;
  Snapshot: TSearchSnapshot;
  Status: TSemanticSearchStatus;
  SawExtracting, SawEmbedding: Boolean;
  I: Integer;
begin
  OpenService(20);
  Extractor := TCountingExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.DelayMs := 20;
  FService.Registry.Register(ExtractorRef, ['.dbl']);
  Reader := TMemoryFileReader.Create;
  ReaderRef := Reader;
  Snapshot := SnapshotOf(MakePassages(100));
  SetLength(Snapshot.Files, FileCount);
  for I := 0 to FileCount - 1 do
  begin
    Reader.Put('f' + IntToStr(I), TEncoding.UTF8.GetBytes('phase text number ' + IntToStr(I)));
    Snapshot.Files[I].FileId := I + 1;
    Snapshot.Files[I].ItemId := 1000 + I;
    Snapshot.Files[I].ProjectId := 1;
    Snapshot.Files[I].Ext := '.dbl';
    Snapshot.Files[I].RelativePath := 'f' + IntToStr(I);
  end;
  SawExtracting := False;
  SawEmbedding := False;
  FService.StartSync(Snapshot, ReaderRef, nil, nil);
  while FService.Status.State = ssSyncing do
  begin
    Status := FService.Status;
    if Status.Phase = spExtracting then
    begin
      SawExtracting := True;
      Assert.AreEqual(FileCount, Status.FilesTotal);
      Assert.AreEqual(0, Status.PendingPassages, 'extraction does not report passages');
    end
    else if Status.Phase = spEmbedding then
      SawEmbedding := True;
    Sleep(5);
  end;
  Assert.IsTrue(SawExtracting, 'extraction phase seen');
  Assert.IsTrue(SawEmbedding, 'embedding phase seen');
  Assert.AreEqual(Ord(spIdle), Ord(FService.Status.Phase));
  Assert.AreEqual(0, FService.Status.FilesTotal - FService.Status.FilesDone);
end;

procedure TSemanticSearchServiceTests.DeadlineDuringFilePhaseStillEmbedsItemPassages;
const
  FileCount = 40;
  ItemPassages = 12;
var
  Extractor: TCountingExtractor;
  ExtractorRef: ITextExtractor;
  Reader: TMemoryFileReader;
  ReaderRef: IFileContentReader;
  Snapshot: TSearchSnapshot;
  I, ReadsAfterFirst: Integer;
begin
  OpenService(0);
  Extractor := TCountingExtractor.Create;
  ExtractorRef := Extractor;
  FService.Registry.Register(ExtractorRef, ['.dbl']);
  Reader := TMemoryFileReader.Create;
  ReaderRef := Reader;
  Reader.ReadDelayMs := 60;
  Snapshot := SnapshotOf(MakePassages(ItemPassages));
  SetLength(Snapshot.Files, FileCount);
  for I := 0 to FileCount - 1 do
  begin
    Reader.Put('f' + IntToStr(I), TEncoding.UTF8.GetBytes('deadline text number ' + IntToStr(I)));
    Snapshot.Files[I].FileId := I + 1;
    Snapshot.Files[I].ItemId := 1000 + I;
    Snapshot.Files[I].ProjectId := 1;
    Snapshot.Files[I].Ext := '.dbl';
    Snapshot.Files[I].RelativePath := 'f' + IntToStr(I);
  end;
  Assert.IsFalse(FService.SyncNow(Snapshot, ReaderRef, 150).Complete);
  Assert.IsFalse(FService.Status.IsComplete);
  Assert.IsTrue(FService.Status.IndexedPassages >= ItemPassages,
    'item passages are embedded: ' + IntToStr(FService.Status.IndexedPassages));
  ReadsAfterFirst := Reader.Reads;
  Assert.IsTrue(ReadsAfterFirst < FileCount, 'the file phase was cut');
  Reader.ReadDelayMs := 0;
  Assert.IsTrue(FService.SyncNow(Snapshot, ReaderRef, BigDeadlineMs).Complete);
  Assert.AreEqual(ItemPassages + FileCount, FService.Status.IndexedPassages);
  Assert.AreEqual(FileCount - ReadsAfterFirst, Reader.Reads - ReadsAfterFirst,
    'files read before the cut are not read again');
end;

procedure TSemanticSearchServiceTests.OpenRerankServiceWith(const CrossFactory: TCrossEncoderFactory;
  const Live: ISearchDocumentSource);
begin
  FFake := TFakeEmbedder.Create(FakeIdentity);
  FEmbedderRef := FFake;
  FService := TSemanticSearchService.Create(FStorePath,
    function: ITextEmbedder
    begin
      Result := FFake;
    end, CrossFactory, Live, '');
end;

procedure TSemanticSearchServiceTests.OpenRerankService;
begin
  FCross := TFakeCrossEncoder.Create;
  FCrossRef := FCross;
  OpenRerankServiceWith(
    function: ICrossEncoder
    begin
      Inc(FCrossRuns);
      Result := FCrossRef;
    end, TAllLiveSource.Create);
  FService.RerankBudgetMs := BigDeadlineMs;
end;

procedure TSemanticSearchServiceTests.SyncPassages(Count: Integer);
begin
  Assert.IsTrue(FService.SyncNow(SnapshotOf(MakePassages(Count)), nil, BigDeadlineMs).Complete);
end;

function TSemanticSearchServiceTests.KeysOf(const Groups: TArray<THybridGroup>): string;
var
  Group: THybridGroup;
begin
  Result := '';
  for Group in Groups do
    Result := Result + Group.Passages[0].Key + ',';
end;

function TSemanticSearchServiceTests.PlainOptions: THybridSearchOptions;
begin
  Result := THybridSearchOptions.Default;
  Result.RerankDepth := 0;
end;

function TSemanticSearchServiceTests.ContextPartsOf(const Title: string): TPassageContextParts;
begin
  Result := Default(TPassageContextParts);
  Result.ProjectTitle := 'Proj';
  Result.FolderPath := ['Top', 'Sub'];
  Result.ItemTitle := Title;
  Result.ItemKind := 'Specimen';
end;

procedure TSemanticSearchServiceTests.RerankReordersTheTopTwentyOnly;
var
  Plain, Ranked: TSemanticSearchResult;
  Expected: string;
  I: Integer;
begin
  OpenRerankService;
  SyncPassages(30);
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Ranked := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.IsFalse(Plain.Reranked);
  Assert.IsTrue(Ranked.Reranked);
  Assert.AreEqual<NativeInt>(30, Length(Ranked.Groups));
  Expected := '';
  for I := 19 downto 0 do
    Expected := Expected + Plain.Groups[I].Passages[0].Key + ',';
  for I := 20 to 29 do
    Expected := Expected + Plain.Groups[I].Passages[0].Key + ',';
  Assert.AreEqual(Expected, KeysOf(Ranked.Groups));
  Assert.AreEqual<NativeInt>(20, Length(FCross.Inputs));
  Assert.AreEqual(1, FCross.Calls);
  Assert.AreEqual('passage', FCross.Queries[0]);
end;

procedure TSemanticSearchServiceTests.RerankedTopKCutsAfterReordering;
var
  Plain, Ranked: TSemanticSearchResult;
  Expected: string;
  I: Integer;
begin
  OpenRerankService;
  SyncPassages(30);
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Ranked := FService.Search('passage', [1], 5, THybridSearchOptions.Default);
  Assert.IsTrue(Ranked.Reranked);
  Expected := '';
  for I := 19 downto 15 do
    Expected := Expected + Plain.Groups[I].Passages[0].Key + ',';
  Assert.AreEqual(Expected, KeysOf(Ranked.Groups));
  Assert.AreEqual<NativeInt>(20, Length(FCross.Inputs));
end;

procedure TSemanticSearchServiceTests.DepthLargerThanTheListReordersTheWholeList;
var
  Plain, Ranked: TSemanticSearchResult;
  Expected: string;
  I: Integer;
begin
  OpenRerankService;
  SyncPassages(7);
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Ranked := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.IsTrue(Ranked.Reranked);
  Expected := '';
  for I := 6 downto 0 do
    Expected := Expected + Plain.Groups[I].Passages[0].Key + ',';
  Assert.AreEqual(Expected, KeysOf(Ranked.Groups));
  Assert.AreEqual<NativeInt>(7, Length(FCross.Inputs));
end;

procedure TSemanticSearchServiceTests.NoRerankerKeepsTheHybridOrder;
var
  Plain, Result: TSemanticSearchResult;
begin
  OpenService(0);
  SyncPassages(30);
  Assert.IsFalse(FService.RerankerAvailable);
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Result := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.IsFalse(Result.Reranked);
  Assert.AreEqual(KeysOf(Plain.Groups), KeysOf(Result.Groups));
  Assert.AreEqual<NativeInt>(30, Length(Result.Groups));
end;

procedure TSemanticSearchServiceTests.ZeroDepthDoesNotLoadTheReranker;
var
  Result: TSemanticSearchResult;
begin
  OpenRerankService;
  SyncPassages(30);
  Assert.IsTrue(FService.RerankerAvailable);
  Result := FService.Search('passage', [1], 30, PlainOptions);
  Assert.IsFalse(Result.Reranked);
  Assert.AreEqual(0, FCrossRuns, 'the model is not loaded');
  Assert.AreEqual(0, FCross.Calls);
end;

procedure TSemanticSearchServiceTests.SingleGroupIsNotReranked;
var
  Result: TSemanticSearchResult;
begin
  OpenRerankService;
  SyncPassages(1);
  Result := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.AreEqual<NativeInt>(1, Length(Result.Groups));
  Assert.IsFalse(Result.Reranked);
  Assert.AreEqual(0, FCross.Calls);
end;

procedure TSemanticSearchServiceTests.SlowRerankerPastTheBudgetReturnsTheHybridOrder;
var
  Plain, Result: TSemanticSearchResult;
  Watch: TStopwatch;
begin
  OpenRerankService;
  SyncPassages(30);
  FService.RerankBudgetMs := 100;
  FCross.DelayMs := 5000;
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Watch := TStopwatch.StartNew;
  Result := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'returned after ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
  Assert.IsFalse(Result.Reranked);
  Assert.AreEqual(KeysOf(Plain.Groups), KeysOf(Result.Groups));
end;

procedure TSemanticSearchServiceTests.RerankerThatIgnoresCancelPastTheBudgetReturnsTheHybridOrder;
var
  Plain, Result: TSemanticSearchResult;
begin
  OpenRerankService;
  SyncPassages(30);
  FService.RerankBudgetMs := 100;
  FCross.DelayMs := 400;
  FCross.IgnoreCancel := True;
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Result := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.AreEqual(1, FCross.Calls, 'the reranker ran');
  Assert.IsFalse(Result.Reranked);
  Assert.AreEqual(KeysOf(Plain.Groups), KeysOf(Result.Groups));
end;

procedure TSemanticSearchServiceTests.RerankerErrorReturnsTheHybridOrder;
var
  Plain, Result: TSemanticSearchResult;
begin
  OpenRerankService;
  SyncPassages(30);
  FCross.OnScore :=
    procedure
    begin
      raise ECrossEncoderError.Create('model returned garbage');
    end;
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Result := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.IsFalse(Result.Reranked);
  Assert.AreEqual(KeysOf(Plain.Groups), KeysOf(Result.Groups));
  Assert.IsTrue(FService.RerankerAvailable, 'a scoring error does not unload the reranker');
end;

procedure TSemanticSearchServiceTests.LoadFailureDisablesTheReranker;
var
  Plain, Result: TSemanticSearchResult;
begin
  OpenRerankServiceWith(
    function: ICrossEncoder
    begin
      Inc(FCrossRuns);
      raise ECrossEncoderError.Create('reranker files missing');
    end, TAllLiveSource.Create);
  SyncPassages(30);
  Assert.IsTrue(FService.RerankerAvailable, 'a factory is set');
  Plain := FService.Search('passage', [1], 30, PlainOptions);
  Result := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.IsFalse(Result.Reranked);
  Assert.AreEqual(KeysOf(Plain.Groups), KeysOf(Result.Groups));
  Assert.IsFalse(FService.RerankerAvailable);
  FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.AreEqual(1, FCrossRuns, 'the factory runs once');
end;

procedure TSemanticSearchServiceTests.SyncDuringRerankDoesNotWait;
var
  Entered, Release: TEvent;
  Worker: TThread;
  Ranked: TSemanticSearchResult;
  Watch: TStopwatch;
  Outcome: TSyncOutcome;
begin
  OpenRerankService;
  SyncPassages(30);
  Ranked := Default(TSemanticSearchResult);
  Entered := TEvent.Create;
  Release := TEvent.Create;
  try
    FCross.OnScore :=
      procedure
      begin
        Entered.SetEvent;
        Release.WaitFor(20000);
      end;
    Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        Ranked := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
      end);
    Worker.FreeOnTerminate := False;
    Worker.Start;
    try
      Assert.AreEqual(Ord(wrSignaled), Ord(Entered.WaitFor(10000)), 'the rerank started');
      Watch := TStopwatch.StartNew;
      Outcome := FService.SyncNow(SnapshotOf(MakePassages(31)), nil, BigDeadlineMs);
      Assert.IsTrue(Outcome.Complete, 'sync finished');
      Assert.IsTrue(Watch.ElapsedMilliseconds < 3000, 'sync took ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
      Assert.AreEqual(31, FService.Status.IndexedPassages);
    finally
      Release.SetEvent;
      Worker.WaitFor;
      Worker.Free;
    end;
    Assert.IsTrue(Ranked.Reranked, 'the search finished after the release');
  finally
    Entered.Free;
    Release.Free;
  end;
end;

procedure TSemanticSearchServiceTests.RerankedListHasOnlyLiveGroups;
var
  Source: TSelectiveLiveSource;
  SourceRef: ISearchDocumentSource;
  Result: TSemanticSearchResult;
  Group: THybridGroup;
begin
  Source := TSelectiveLiveSource.Create;
  SourceRef := Source;
  Source.DeadItem := 1003;
  FCross := TFakeCrossEncoder.Create;
  FCrossRef := FCross;
  OpenRerankServiceWith(
    function: ICrossEncoder
    begin
      Result := FCrossRef;
    end, SourceRef);
  SyncPassages(30);
  Result := FService.Search('passage', [1], 30, THybridSearchOptions.Default);
  Assert.IsTrue(Result.Reranked);
  Assert.AreEqual<NativeInt>(29, Length(Result.Groups));
  for Group in Result.Groups do
    Assert.AreNotEqual(1003, Group.ItemId);
  Assert.AreEqual<NativeInt>(20, Length(FCross.Inputs));
  for Group in Result.Groups do
    Assert.AreNotEqual('passage text number 3', Group.Passages[0].Snippet);
  Assert.IsFalse(TArray.Contains<string>(FCross.Inputs, 'passage text number 3'),
    'the reranker never sees a dead item');
end;

procedure TSemanticSearchServiceTests.RerankInputIsContextAndBestPassageOfEachGroup;
var
  Passages: TSearchPassages;
  Snapshot: TSearchSnapshot;
  Parts: TPassageContextParts;
  Result: TSemanticSearchResult;
begin
  OpenRerankService;
  Passages := MakePassages(3);
  Passages[0].Text := 'passage text number 0 zirconium';
  Passages[0].ContentHash := PassageHash(Passages[0].Text);
  SetLength(Passages, 4);
  Passages[3] := Passages[0];
  Passages[3].Key := 'p0b';
  Passages[3].Text := 'passage second text of item zero';
  Passages[3].ContentHash := PassageHash(Passages[3].Text);
  Parts := ContextPartsOf('Zero');
  Snapshot := SnapshotOf(Passages);
  Snapshot.ItemContexts := [TItemContextEntry.Make(1000, PassageContextPartsToJson(Parts))];
  Assert.IsTrue(FService.SyncNow(Snapshot, nil, BigDeadlineMs).Complete);
  Result := FService.Search('zirconium', [1], 30, THybridSearchOptions.Default);
  Assert.IsTrue(Result.Reranked);
  Assert.AreEqual<NativeInt>(3, Length(Result.Groups));
  Assert.AreEqual<NativeInt>(3, Length(FCross.Inputs), 'one input for each group, not for each passage');
  Assert.AreEqual(BuildPassageContext(Parts, pfItemDescription) + #10 + 'passage text number 0 zirconium',
    FCross.Inputs[0]);
  Assert.IsTrue(TArray.Contains<string>(FCross.Inputs, 'passage text number 1'));
  Assert.IsTrue(TArray.Contains<string>(FCross.Inputs, 'passage text number 2'));
end;

procedure TSemanticSearchServiceTests.ItemContextIsReplacedAtEverySync;
var
  Passages: TSearchPassages;
  Snapshot: TSearchSnapshot;
  Parts: TPassageContextParts;
begin
  OpenRerankService;
  Passages := MakePassages(3);
  Passages[0].Text := 'passage text number 0 zirconium';
  Passages[0].ContentHash := PassageHash(Passages[0].Text);
  Parts := ContextPartsOf('Zero');
  Snapshot := SnapshotOf(Passages);
  Snapshot.ItemContexts := [TItemContextEntry.Make(1000, PassageContextPartsToJson(Parts))];
  Assert.IsTrue(FService.SyncNow(Snapshot, nil, BigDeadlineMs).Complete);
  FService.Search('zirconium', [1], 30, THybridSearchOptions.Default);
  Assert.AreEqual(BuildPassageContext(Parts, pfItemDescription) + #10 + 'passage text number 0 zirconium',
    FCross.Inputs[0]);
  Parts.ProjectTitle := 'Renamed';
  Snapshot.ItemContexts := [TItemContextEntry.Make(1000, PassageContextPartsToJson(Parts))];
  Assert.IsTrue(FService.SyncNow(Snapshot, nil, BigDeadlineMs).Complete);
  FService.Search('zirconium', [1], 30, THybridSearchOptions.Default);
  Assert.AreEqual(BuildPassageContext(Parts, pfItemDescription) + #10 + 'passage text number 0 zirconium',
    FCross.Inputs[0], 'a project rename reaches the reranker input');
  Snapshot.ItemContexts := nil;
  Assert.IsTrue(FService.SyncNow(Snapshot, nil, BigDeadlineMs).Complete);
  FService.Search('zirconium', [1], 30, THybridSearchOptions.Default);
  Assert.AreEqual('passage text number 0 zirconium', FCross.Inputs[0], 'a removed item loses its context');
end;

function TSemanticSearchServiceTests.LocalSearch: ISemanticSearch;
begin
  Result := TLocalSemanticSearch.Create(FService,
    function(Filter: TSemanticSearchFilter; Ids: TArray<Integer>): TItemFilter
    begin
      Inc(FResolveCalls);
      FResolvedIds := Ids;
      if FFilterError <> '' then
        raise ESemanticFilterError.Create(FFilterError);
      Result := TItemFilter.Only(FAllowedItems);
    end,
    function(Values: TArray<TValueConstraint>): TArray<TAppliedLimit>
    var
      Limit: TAppliedLimit;
    begin
      Limit := Default(TAppliedLimit);
      Limit.ValueTypeId := 4;
      Limit.ValueType := 'Probe hardness';
      Limit.Units := 'MPa';
      Limit.HasMin := True;
      Limit.Min := 10000;
      Limit.RequestedUnit := 'GPa';
      Result := [Limit];
    end);
end;

function TSemanticSearchServiceTests.RequestFor(const Query: string;
  TopK: Integer): TSemanticSearchRequest;
begin
  Result := Default(TSemanticSearchRequest);
  Result.Query := Query;
  Result.VisibleProjectIds := [1];
  Result.TopK := TopK;
  Result.Rerank := True;
end;

procedure TSemanticSearchServiceTests.RunnerDeliversOnTheMainThread;
var
  Runner: TSemanticSearchRunner;
  Delivered: TSemanticSearchResult;
  Failure: string;
  Calls: Integer;
  CallbackThread: TThreadID;
  Watch: TStopwatch;
begin
  Calls := 0;
  CallbackThread := 0;
  OpenRerankService;
  SyncPassages(30);
  Runner := TSemanticSearchRunner.Create(LocalSearch);
  try
    Runner.Start(RequestFor('passage', 30),
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
        Inc(Calls);
        CallbackThread := TThread.CurrentThread.ThreadID;
        Delivered := Result;
        Failure := Error;
      end);
    Watch := TStopwatch.StartNew;
    while (Calls = 0) and (Watch.ElapsedMilliseconds < 10000) do
      CheckSynchronize(10);
  finally
    Runner.Free;
  end;
  Assert.AreEqual(1, Calls);
  Assert.AreEqual<TThreadID>(MainThreadID, CallbackThread);
  Assert.AreEqual('', Failure);
  Assert.IsTrue(Delivered.Reranked);
  Assert.AreEqual<NativeInt>(30, Length(Delivered.Groups));
end;

procedure TSemanticSearchServiceTests.RunnerReportsTheFailureText;
var
  Runner: TSemanticSearchRunner;
  Failure: string;
  Calls: Integer;
  Watch: TStopwatch;
begin
  Calls := 0;
  FService := TSemanticSearchService.Create(FStorePath,
    function: ITextEmbedder
    begin
      raise Exception.Create('model files missing');
    end, nil, TAllLiveSource.Create, '');
  Runner := TSemanticSearchRunner.Create(LocalSearch);
  try
    Runner.Start(RequestFor('passage', 30),
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
        Inc(Calls);
        Failure := Error;
      end);
    Watch := TStopwatch.StartNew;
    while (Calls = 0) and (Watch.ElapsedMilliseconds < 10000) do
      CheckSynchronize(10);
  finally
    Runner.Free;
  end;
  Assert.AreEqual(1, Calls);
  Assert.AreEqual('model files missing', Failure);
end;

procedure TSemanticSearchServiceTests.FreeingTheRunnerDropsTheDelivery;
var
  Runner: TSemanticSearchRunner;
  Entered, Release: TEvent;
  Calls: Integer;
begin
  Calls := 0;
  OpenRerankService;
  SyncPassages(30);
  Entered := TEvent.Create;
  Release := TEvent.Create;
  Runner := TSemanticSearchRunner.Create(LocalSearch);
  try
    FCross.OnScore :=
      procedure
      begin
        Entered.SetEvent;
        Release.WaitFor(20000);
      end;
    Runner.Start(RequestFor('passage', 30),
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
        Inc(Calls);
      end);
    Assert.AreEqual(Ord(wrSignaled), Ord(Entered.WaitFor(10000)), 'the rerank started');
    Release.SetEvent;
    FreeAndNil(Runner);
    CheckSynchronize(50);
    Assert.AreEqual(0, Calls);
  finally
    Runner.Free;
    Entered.Free;
    Release.Free;
  end;
end;

procedure TSemanticSearchServiceTests.NewerSearchCancelsTheRunningRerank;
var
  Runner: TSemanticSearchRunner;
  FirstReranked: Boolean;
  FirstDone: Integer;
  Watch: TStopwatch;
begin
  FirstReranked := True;
  FirstDone := 0;
  OpenRerankService;
  SyncPassages(30);
  FCross.DelayMs := 8000;
  Runner := TSemanticSearchRunner.Create(LocalSearch);
  try
    Runner.Start(RequestFor('passage', 30),
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
        Inc(FirstDone);
        FirstReranked := Result.Reranked;
      end);
    Watch := TStopwatch.StartNew;
    while (FCross.Calls = 0) and (Watch.ElapsedMilliseconds < 10000) do
      Sleep(5);
    Assert.AreEqual(1, FCross.Calls, 'the first rerank started');
    Runner.Start(RequestFor('passage', 30),
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
      end);
    Watch := TStopwatch.StartNew;
    while (FirstDone = 0) and (Watch.ElapsedMilliseconds < 3000) do
      CheckSynchronize(10);
  finally
    Runner.Free;
  end;
  Assert.AreEqual(1, FirstDone, 'the first search ended soon after the second began');
  Assert.IsFalse(FirstReranked);
end;

procedure TSemanticSearchServiceTests.MainThreadSourceRunsTheInnerSourceOnTheMainThread;
var
  Probe: TThreadProbeSource;
  ProbeRef, Wrapped: ISearchDocumentSource;
  Worker: TThread;
  ProjectId: Integer;
  Live, Done: Boolean;
  Watch: TStopwatch;
begin
  Probe := TThreadProbeSource.Create;
  ProbeRef := Probe;
  Wrapped := TMainThreadSearchSource.Create(ProbeRef);
  Assert.IsTrue(Wrapped.IsItemLive(1, ProjectId));
  Assert.AreEqual<TThreadID>(MainThreadID, Probe.Threads[0], 'a call on the main thread runs in place');
  Probe.Threads := nil;
  Live := False;
  Done := False;
  ProjectId := 0;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      Live := Wrapped.IsItemLive(7, ProjectId);
      Wrapped.ReadSnapshot(nil);
      Done := True;
    end);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  try
    Watch := TStopwatch.StartNew;
    while not Done and (Watch.ElapsedMilliseconds < 10000) do
      CheckSynchronize(10);
  finally
    Worker.WaitFor;
    Worker.Free;
  end;
  Assert.IsTrue(Done);
  Assert.IsTrue(Live);
  Assert.AreEqual(1, ProjectId);
  Assert.AreEqual<NativeInt>(2, Length(Probe.Threads));
  Assert.AreEqual<TThreadID>(MainThreadID, Probe.Threads[0]);
  Assert.AreEqual<TThreadID>(MainThreadID, Probe.Threads[1]);
end;

procedure TSemanticSearchServiceTests.RunnerRunsTheLiveChecksOnTheMainThread;
var
  Runner: TSemanticSearchRunner;
  Probe: TThreadProbeSource;
  ProbeRef: ISearchDocumentSource;
  Delivered: TSemanticSearchResult;
  Calls: Integer;
  Watch: TStopwatch;
  Id: TThreadID;
begin
  Calls := 0;
  Probe := TThreadProbeSource.Create;
  ProbeRef := Probe;
  FCross := TFakeCrossEncoder.Create;
  FCrossRef := FCross;
  OpenRerankServiceWith(
    function: ICrossEncoder
    begin
      Result := FCrossRef;
    end, TMainThreadSearchSource.Create(ProbeRef));
  SyncPassages(30);
  Assert.AreEqual<NativeInt>(0, Length(Probe.Threads));
  Runner := TSemanticSearchRunner.Create(LocalSearch);
  try
    Runner.Start(RequestFor('passage', 30),
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
        Inc(Calls);
        Delivered := Result;
      end);
    Watch := TStopwatch.StartNew;
    while (Calls = 0) and (Watch.ElapsedMilliseconds < 10000) do
      CheckSynchronize(10);
  finally
    Runner.Free;
  end;
  Assert.AreEqual(1, Calls);
  Assert.AreEqual<NativeInt>(30, Length(Delivered.Groups));
  Assert.AreEqual<NativeInt>(30, Length(Probe.Threads), 'one live check for each item');
  for Id in Probe.Threads do
    Assert.AreEqual<TThreadID>(MainThreadID, Id);
end;

procedure TSemanticSearchServiceTests.LocalSearchMapsTheRequest;
var
  Search: ISemanticSearch;
  Request: TSemanticSearchRequest;
  Outcome: TSemanticSearchResult;
begin
  OpenRerankService;
  SyncPassages(30);
  Search := LocalSearch;
  Assert.IsFalse(Search.IsRemote);
  Assert.IsTrue(Search.RerankerAvailable);
  Assert.AreEqual(30, Search.Status.IndexedPassages);
  Request := RequestFor('passage', 5);
  Request.Rerank := False;
  Outcome := Search.Search(Request, nil);
  Assert.IsFalse(Outcome.Reranked);
  Assert.AreEqual(0, FCross.Calls, 'no rerank was asked for');
  Assert.AreEqual<NativeInt>(5, Length(Outcome.Groups));
  Assert.AreEqual(30, Outcome.IndexStatus.IndexedPassages);
  Assert.IsTrue(Outcome.IndexStatus.IsComplete);
  Assert.AreEqual('', Outcome.FiltersApplied, 'no filter, no echo');
  Assert.AreEqual(0, FResolveCalls, 'an empty filter is not resolved');
  Request.Rerank := True;
  Outcome := Search.Search(Request, nil);
  Assert.IsTrue(Outcome.Reranked);
  Assert.AreEqual<NativeInt>(5, Length(Outcome.Groups));
  Request.VisibleProjectIds := [2];
  Assert.AreEqual<NativeInt>(0, Length(Search.Search(Request, nil).Groups),
    'the visible projects reach the service');
end;

procedure TSemanticSearchServiceTests.LocalSearchResolvesTheFilterAndEchoesIt;
var
  Request: TSemanticSearchRequest;
  Outcome: TSemanticSearchResult;
  Constraint: TValueConstraint;
  Echo, Limit: TJSONObject;
  Ids: TArray<Integer>;
begin
  OpenService(0);
  SyncPassages(30);
  FAllowedItems := [1003, 1005];
  Request := RequestFor('passage', 30);
  Request.Filter.FolderId := 9;
  Request.Filter.ItemTypes := [' Testing '];
  Request.Filter.DateField := sdfCreated;
  Request.Filter.DateFrom := EncodeDate(2026, 1, 31);
  Constraint := Default(TValueConstraint);
  Constraint.ValueType := 'PH';
  Constraint.HasMin := True;
  Constraint.Min := 10;
  Constraint.UnitSymbol := 'GPa';
  Request.Filter.Values := [Constraint];
  Outcome := LocalSearch.Search(Request, nil);
  Assert.AreEqual(1, FResolveCalls);
  Assert.AreEqual<NativeInt>(1, Length(FResolvedIds));
  Assert.AreEqual(1, FResolvedIds[0]);
  Assert.AreEqual<NativeInt>(2, Length(Outcome.Groups));
  Ids := [Outcome.Groups[0].ItemId, Outcome.Groups[1].ItemId];
  TArray.Sort<Integer>(Ids);
  Assert.AreEqual(1003, Ids[0]);
  Assert.AreEqual(1005, Ids[1]);
  Echo := TJSONObject.ParseJSONValue(Outcome.FiltersApplied) as TJSONObject;
  try
    Assert.IsNotNull(Echo, Outcome.FiltersApplied);
    Assert.AreEqual(9, Echo.GetValue<Integer>('folder_id'));
    Assert.AreEqual('Testing', Echo.GetValue<TJSONArray>('item_types').Items[0].Value);
    Assert.IsNull(Echo.GetValue('levels'));
    Assert.AreEqual('created', Echo.GetValue<string>('date_field'));
    Assert.AreEqual('2026-01-31', Echo.GetValue<string>('date_from'));
    Assert.IsNull(Echo.GetValue('date_to'));
    Limit := Echo.GetValue<TJSONArray>('values').Items[0] as TJSONObject;
    Assert.AreEqual('Probe hardness', Limit.GetValue<string>('value_type'));
    Assert.AreEqual(4, Limit.GetValue<Integer>('value_type_id'));
    Assert.AreEqual('MPa', Limit.GetValue<string>('unit'));
    Assert.AreEqual(10000.0, Limit.GetValue<Double>('min'), 1e-9);
    Assert.IsNull(Limit.GetValue('max'));
    Assert.IsNull(Limit.GetValue('rec_type'));
    Assert.AreEqual('GPa', Limit.GetValue<string>('requested_unit'));
  finally
    Echo.Free;
  end;
end;

procedure TSemanticSearchServiceTests.LocalSearchKeepsTheFilterErrorMessage;
var
  Request: TSemanticSearchRequest;
  Message: string;
begin
  OpenService(0);
  SyncPassages(3);
  FFilterError := 'The folder does not exist or is not available.';
  Request := RequestFor('passage', 5);
  Request.Filter.FolderId := 9;
  Message := '';
  try
    LocalSearch.Search(Request, nil);
  except
    on E: ESemanticFilterError do
      Message := E.Message;
  end;
  Assert.AreEqual(FFilterError, Message);
end;

procedure TSemanticSearchServiceTests.MainThreadResolverRunsOnTheMainThread;
var
  Runner: TSemanticSearchRunner;
  Threads: TArray<TThreadID>;
  Request: TSemanticSearchRequest;
  Delivered: TSemanticSearchResult;
  Failure: string;
  Calls: Integer;
  Watch: TStopwatch;
  Id: TThreadID;
begin
  Threads := nil;
  OpenService(0);
  SyncPassages(3);
  Runner := TSemanticSearchRunner.Create(TLocalSemanticSearch.Create(FService,
    MainThreadFilterResolver(
      function(Filter: TSemanticSearchFilter; Ids: TArray<Integer>): TItemFilter
      begin
        Threads := Threads + [TThread.CurrentThread.ThreadID];
        if Filter.FolderId = 9 then
          raise ESemanticFilterError.Create('folder gone');
        Result := TItemFilter.Only([1001]);
      end),
    MainThreadLimitDescriber(
      function(Values: TArray<TValueConstraint>): TArray<TAppliedLimit>
      begin
        Threads := Threads + [TThread.CurrentThread.ThreadID];
        Result := nil;
      end)));
  try
    Request := RequestFor('passage', 5);
    Request.Filter.ItemTypes := ['Testing'];
    Request.Filter.Values := [Default(TValueConstraint)];
    Calls := 0;
    Runner.Start(Request,
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
        Inc(Calls);
        Delivered := Result;
        Failure := Error;
      end);
    Watch := TStopwatch.StartNew;
    while (Calls = 0) and (Watch.ElapsedMilliseconds < 10000) do
      CheckSynchronize(10);
    Assert.AreEqual(1, Calls);
    Assert.AreEqual('', Failure);
    Assert.AreEqual<NativeInt>(1, Length(Delivered.Groups));
    Assert.AreEqual(1001, Delivered.Groups[0].ItemId);
    Assert.AreEqual<NativeInt>(2, Length(Threads), 'the resolver and the describer ran');
    for Id in Threads do
      Assert.AreEqual<TThreadID>(MainThreadID, Id);
    Request.Filter.FolderId := 9;
    Calls := 0;
    Runner.Start(Request,
      procedure(const Result: TSemanticSearchResult; const Error: string)
      begin
        Inc(Calls);
        Failure := Error;
      end);
    Watch := TStopwatch.StartNew;
    while (Calls = 0) and (Watch.ElapsedMilliseconds < 10000) do
      CheckSynchronize(10);
    Assert.AreEqual(1, Calls);
    Assert.AreEqual('folder gone', Failure, 'the filter error text reaches the caller');
  finally
    Runner.Free;
  end;
end;

procedure TSemanticSearchServiceTests.StatusAndRerankerAvailableDoNotWaitForARunningSearch;
var
  Source: TBlockingLiveSource;
  SourceRef: ISearchDocumentSource;
  Search: ISemanticSearch;
  Worker: TThread;
  Watch: TStopwatch;
  Status: TSemanticSearchStatus;
  Available: Boolean;
begin
  Source := TBlockingLiveSource.Create;
  SourceRef := Source;
  Source.Entered := TEvent.Create;
  Source.Release := TEvent.Create;
  try
    FCross := TFakeCrossEncoder.Create;
    FCrossRef := FCross;
    OpenRerankServiceWith(
      function: ICrossEncoder
      begin
        Result := FCrossRef;
      end, SourceRef);
    SyncPassages(5);
    Search := LocalSearch;
    Source.Armed := True;
    Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        Search.Search(RequestFor('passage', 5), nil);
      end);
    Worker.FreeOnTerminate := False;
    Worker.Start;
    try
      Assert.AreEqual(Ord(wrSignaled), Ord(Source.Entered.WaitFor(10000)),
        'the search holds the service lock in its live check');
      Watch := TStopwatch.StartNew;
      Status := Search.Status;
      Available := Search.RerankerAvailable;
      Assert.IsTrue(Watch.ElapsedMilliseconds < 1000,
        'returned after ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
      Assert.AreEqual(5, Status.IndexedPassages);
      Assert.IsTrue(Available);
    finally
      Source.Release.SetEvent;
      Worker.WaitFor;
      Worker.Free;
    end;
  finally
    Source.Entered.Free;
    Source.Release.Free;
  end;
end;

procedure TSemanticSearchServiceTests.ConcurrentSearchesCheckLivenessOnTheirOwnSources;
const
  Rounds = 5;
  Items = 30;
var
  Own, First, Second: TThreadProbeSource;
  OwnRef, FirstRef, SecondRef: ISearchDocumentSource;
  Go: TEvent;
  FirstWorker, SecondWorker: TSearchRoundsThread;
  Id: TThreadID;
  Project: Integer;
begin
  Own := TThreadProbeSource.Create;
  OwnRef := Own;
  OpenRerankServiceWith(nil, OwnRef);
  SyncPassages(Items);
  First := TThreadProbeSource.Create(1);
  FirstRef := First;
  Second := TThreadProbeSource.Create(2);
  SecondRef := Second;
  Go := TEvent.Create;
  try
    FirstWorker := TSearchRoundsThread.Create(FService, FirstRef, Go, Rounds);
    try
      SecondWorker := TSearchRoundsThread.Create(FService, SecondRef, Go, Rounds);
      try
        Go.SetEvent;
        FirstWorker.WaitFor;
        SecondWorker.WaitFor;
        Assert.AreEqual('', FirstWorker.Failure);
        Assert.AreEqual('', SecondWorker.Failure);
        Assert.AreEqual<NativeInt>(0, Length(Own.Threads), 'the service source was not asked');
        Assert.AreEqual<NativeInt>(Rounds * Items, Length(First.Threads),
          'one live check for each item in each search');
        for Id in First.Threads do
          Assert.AreEqual<TThreadID>(FirstWorker.SearchThread, Id, 'first source, other thread');
        Assert.AreEqual<NativeInt>(Rounds * Items, Length(Second.Threads),
          'one live check for each item in each search');
        for Id in Second.Threads do
          Assert.AreEqual<TThreadID>(SecondWorker.SearchThread, Id, 'second source, other thread');
        Assert.AreEqual<NativeInt>(Rounds * Items, Length(FirstWorker.Projects));
        for Project in FirstWorker.Projects do
          Assert.AreEqual(1, Project, 'the first search reports the project of its own source');
        Assert.AreEqual<NativeInt>(Rounds * Items, Length(SecondWorker.Projects));
        for Project in SecondWorker.Projects do
          Assert.AreEqual(2, Project, 'the second search reports the project of its own source');
      finally
        SecondWorker.Free;
      end;
    finally
      FirstWorker.Free;
    end;
  finally
    Go.Free;
  end;
end;

procedure TSemanticSearchServiceTests.NilLiveSourceUsesTheServiceSource;
var
  Own, Other: TThreadProbeSource;
  OwnRef, OtherRef: ISearchDocumentSource;
  Options: THybridSearchOptions;
  Groups: TArray<THybridGroup>;
begin
  Own := TThreadProbeSource.Create;
  OwnRef := Own;
  OpenRerankServiceWith(nil, OwnRef);
  SyncPassages(30);
  Options := PlainOptions;
  Assert.IsTrue(Options.LiveSource = nil, 'no per-search source by default');
  Groups := FService.Search('passage', [1, 2], 30, Options).Groups;
  Assert.AreEqual<NativeInt>(30, Length(Own.Threads), 'the service source checks each item');
  Assert.AreEqual(1, Groups[0].ProjectId);
  Other := TThreadProbeSource.Create(2);
  OtherRef := Other;
  Options.LiveSource := OtherRef;
  Groups := FService.Search('passage', [1, 2], 30, Options).Groups;
  Assert.AreEqual<NativeInt>(30, Length(Other.Threads), 'the per-search source checks each item');
  Assert.AreEqual(2, Groups[0].ProjectId);
  Assert.AreEqual<NativeInt>(30, Length(Own.Threads), 'the service source was not asked');
  Options := PlainOptions;
  Groups := FService.Search('passage', [1, 2], 30, Options).Groups;
  Assert.AreEqual<NativeInt>(60, Length(Own.Threads), 'the per-search source does not stay');
  Assert.AreEqual<NativeInt>(30, Length(Other.Threads));
  Assert.AreEqual(1, Groups[0].ProjectId);
end;

initialization
  TDUnitX.RegisterTestFixture(TSemanticSearchServiceTests);

end.
