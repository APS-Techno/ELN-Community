unit unit_SemanticSearchService;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  unit_SearchPassages, unit_SearchIndexStore, unit_SearchIndexer, unit_HybridSearch,
  unit_TextEmbedder, unit_TextExtractorRegistry, unit_CrossEncoder, unit_SemanticSearchApi;

type
  TEmbedderFactory = reference to function: ITextEmbedder;

  TSyncOutcome = record
    Stats: TSyncStats;
    Complete: Boolean;
  end;

  TSemanticSearchService = class
  private
    FStorePath: string;
    FRegistry: TTextExtractorRegistry;
    FFactory: TEmbedderFactory;
    FLiveSource: ISearchDocumentSource;
    FLock: TCriticalSection;
    FStateLock: TCriticalSection;
    FStatus: TSemanticSearchStatus;
    FCancel: Boolean;
    FWaiters: Integer;
    FFactoryError: string;
    FEmbedder: ITextEmbedder;
    FStore: TSearchIndexStore;
    FSearcher: THybridSearcher;
    FWorker: TThread;
    FGate: IDeliveryGate;
    FRerankFactory: TCrossEncoderFactory;
    FRerankLock: TCriticalSection;
    FEncoder: ICrossEncoder;
    FRerankFailed: Boolean;
    FRerankBudgetMs: Cardinal;
    procedure EnterLock;
    procedure YieldLock;
    procedure EnsureOpen;
    procedure MarkFailed(const Msg: string);
    procedure FailSync(const Msg: string);
    procedure ClearFailure;
    procedure SetPending(Count: Integer);
    procedure SetFiles(Done, Total: Integer);
    procedure SetPhase(Phase: TServicePhase);
    procedure RefreshIndexed;
    function TryBeginSync: Boolean;
    function IsCancelRequested: Boolean;
    procedure FinishSync(const Outcome: TSyncOutcome);
    function RunSync(const Snapshot: TSearchSnapshot; const Reader: IFileContentReader;
      const Cancelled: TCancelCheck; const OnProgress: TSyncProgress;
      EmbedBudgetMs: Cardinal): TSyncOutcome;
    procedure RunWorker(const Snapshot: TSearchSnapshot; const Reader: IFileContentReader;
      const OnProgress: TSyncProgress; const OnDone: TProc<TSemanticSearchStatus>;
      const Gate: IDeliveryGate);
    procedure LeaveLockFairly;
    function TryRerank(const Query: string; const Inputs: TArray<string>;
      const Cancelled: TCancelCheck; out Scores: TArray<Single>): Boolean;
    procedure MarkRerankFailed;
  public
    constructor Create(const StorePath: string; const EmbedderFactory: TEmbedderFactory;
      const RerankerFactory: TCrossEncoderFactory; const LiveSource: ISearchDocumentSource;
      const PdfiumLibraryPath: string);
    destructor Destroy; override;
    procedure StartSync(const Snapshot: TSearchSnapshot; const Reader: IFileContentReader;
      const OnProgress: TSyncProgress; const OnDone: TProc<TSemanticSearchStatus>);
    function SyncNow(const Snapshot: TSearchSnapshot; const Reader: IFileContentReader;
      DeadlineMs: Cardinal): TSyncOutcome;
    procedure CancelSync;
    function Search(const Query: string; const VisibleProjectIds: TArray<Integer>;
      TopK: Integer; const Options: THybridSearchOptions;
      const Cancelled: TCancelCheck = nil): TSemanticSearchResult;
    function RerankerAvailable: Boolean;
    function Status: TSemanticSearchStatus;
    property Registry: TTextExtractorRegistry read FRegistry;
    property RerankBudgetMs: Cardinal read FRerankBudgetMs write FRerankBudgetMs;
  end;

function E5EmbedderFactory(const ArtifactRoot: string): TEmbedderFactory;

const
  DefaultRerankBudgetMs = 1500;

implementation

uses
  System.Diagnostics, System.Math, unit_FileTextStage;

constructor TSemanticSearchService.Create(const StorePath: string;
  const EmbedderFactory: TEmbedderFactory; const RerankerFactory: TCrossEncoderFactory;
  const LiveSource: ISearchDocumentSource; const PdfiumLibraryPath: string);
begin
  inherited Create;
  if not Assigned(EmbedderFactory) or (LiveSource = nil) then
    raise EArgumentNilException.Create('Embedder factory and live source are required');
  FStorePath := StorePath;
  FFactory := EmbedderFactory;
  FLiveSource := LiveSource;
  FRerankFactory := RerankerFactory;
  FRerankBudgetMs := DefaultRerankBudgetMs;
  FRerankLock := TCriticalSection.Create;
  FRegistry := TTextExtractorRegistry.Create(PdfiumLibraryPath);
  FLock := TCriticalSection.Create;
  FStateLock := TCriticalSection.Create;
  FGate := CreateDeliveryGate;
  FStatus := Default(TSemanticSearchStatus);
end;

destructor TSemanticSearchService.Destroy;
begin
  FGate.Close;
  CancelSync;
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FEncoder := nil;
  FRerankLock.Free;
  FSearcher.Free;
  FStore.Free;
  FEmbedder := nil;
  FStateLock.Free;
  FLock.Free;
  FRegistry.Free;
  inherited;
end;

procedure TSemanticSearchService.EnterLock;
begin
  TInterlocked.Increment(FWaiters);
  try
    FLock.Enter;
  finally
    TInterlocked.Decrement(FWaiters);
  end;
end;

procedure TSemanticSearchService.LeaveLockFairly;
begin
  // A critical section is not fair: without this hand-over the worker would re-take the lock
  // before a waiting Search is scheduled.
  FLock.Leave;
  while TInterlocked.CompareExchange(FWaiters, 0, 0) > 0 do
    Sleep(1);
end;

procedure TSemanticSearchService.YieldLock;
begin
  LeaveLockFairly;
  FLock.Enter;
end;

procedure TSemanticSearchService.MarkFailed(const Msg: string);
begin
  FStateLock.Enter;
  try
    FStatus.LastError := Msg;
    if FStatus.State <> ssSyncing then
      FStatus.State := ssFailed;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.FailSync(const Msg: string);
begin
  FStateLock.Enter;
  try
    FStatus.State := ssFailed;
    FStatus.Phase := spIdle;
    FStatus.LastSyncComplete := False;
    FStatus.LastError := Msg;
    FCancel := False;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.ClearFailure;
begin
  FStateLock.Enter;
  try
    if FStatus.State = ssFailed then
    begin
      FStatus.State := ssIdle;
      FStatus.LastError := '';
    end;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.SetPending(Count: Integer);
begin
  FStateLock.Enter;
  try
    FStatus.PendingPassages := Count;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.SetFiles(Done, Total: Integer);
begin
  FStateLock.Enter;
  try
    FStatus.Phase := spExtracting;
    FStatus.FilesDone := Done;
    FStatus.FilesTotal := Total;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.SetPhase(Phase: TServicePhase);
begin
  FStateLock.Enter;
  try
    FStatus.Phase := Phase;
    if Phase = spEmbedding then
      FStatus.PendingPassages := 0;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.RefreshIndexed;
var
  Catalog: TDictionary<string, TStoredPassage>;
  Count: Integer;
begin
  Catalog := FStore.ReadCatalog;
  try
    Count := Catalog.Count;
  finally
    Catalog.Free;
  end;
  FStateLock.Enter;
  try
    FStatus.IndexedPassages := Count;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.EnsureOpen;
begin
  if FFactoryError <> '' then
    raise ESemanticSearchUnavailable.Create(FFactoryError);
  if FEmbedder = nil then
  try
    FEmbedder := FFactory();
    if FEmbedder = nil then
      raise ESemanticSearchUnavailable.Create('The embedder factory returned no embedder');
  except
    on E: Exception do
    begin
      FEmbedder := nil;
      FFactoryError := E.Message;
      MarkFailed(E.Message);
      raise ESemanticSearchUnavailable.Create(E.Message);
    end;
  end;
  if FSearcher <> nil then
    Exit;
  try
    FStore := TSearchIndexStore.Open(FStorePath, FEmbedder.Identity, FEmbedder.Dimension);
    FSearcher := THybridSearcher.Create(FStore, FEmbedder, FLiveSource);
    RefreshIndexed;
    ClearFailure;
  except
    on E: Exception do
    begin
      FreeAndNil(FSearcher);
      FreeAndNil(FStore);
      MarkFailed(E.Message);
      raise ESemanticSearchUnavailable.Create(E.Message);
    end;
  end;
end;

function TSemanticSearchService.TryBeginSync: Boolean;
begin
  FStateLock.Enter;
  try
    Result := FStatus.State <> ssSyncing;
    if Result then
    begin
      FStatus.State := ssSyncing;
      FStatus.LastSyncComplete := False;
      FCancel := False;
    end;
  finally
    FStateLock.Leave;
  end;
end;

function TSemanticSearchService.IsCancelRequested: Boolean;
begin
  FStateLock.Enter;
  try
    Result := FCancel;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.FinishSync(const Outcome: TSyncOutcome);
begin
  FStateLock.Enter;
  try
    FStatus.State := ssIdle;
    FStatus.Phase := spIdle;
    FStatus.LastError := '';
    FStatus.LastSyncComplete := Outcome.Complete;
    FCancel := False;
    if Outcome.Complete then
    begin
      FStatus.PendingPassages := 0;
      FStatus.FilesDone := 0;
      FStatus.FilesTotal := 0;
    end;
  finally
    FStateLock.Leave;
  end;
end;

function TSemanticSearchService.RunSync(const Snapshot: TSearchSnapshot;
  const Reader: IFileContentReader; const Cancelled: TCancelCheck;
  const OnProgress: TSyncProgress; EmbedBudgetMs: Cardinal): TSyncOutcome;
var
  Indexer: TSearchIndexer;
  Stage: TFileTextStage;
  FilePassages: TSearchPassages;
  FilesCut: Boolean;
  EmbedWatch: TStopwatch;
  EmbedCancelled: TCancelCheck;
begin
  Result := Default(TSyncOutcome);
  FilesCut := False;
  EnterLock;
  try
    EnsureOpen;
    FStore.ReplaceItemContexts(Snapshot.ItemContexts);
    Stage := TFileTextStage.Create(FStore, FRegistry);
  finally
    FLock.Leave;
  end;
  SetFiles(0, Length(Snapshot.Files));
  try
    Stage.EnterStore := EnterLock;
    Stage.LeaveStore := LeaveLockFairly;
    try
      FilePassages := Stage.BuildFilePassages(Snapshot.Files, Reader, Cancelled,
        procedure(Done, Total: Integer)
        begin
          SetFiles(Done, Total);
        end);
    except
      on EOperationCancelled do
      begin
        if IsCancelRequested then
          Exit;
        FilesCut := True;
        FilePassages := Stage.CachedFilePassages(Snapshot.Files);
      end;
    end;
  finally
    Stage.Free;
  end;
  EmbedCancelled := Cancelled;
  if FilesCut then
  begin
    EmbedWatch := TStopwatch.StartNew;
    EmbedCancelled :=
      function: Boolean
      begin
        Result := IsCancelRequested or (EmbedWatch.ElapsedMilliseconds > EmbedBudgetMs);
      end;
  end;
  SetPhase(spEmbedding);
  EnterLock;
  try
    Indexer := TSearchIndexer.Create(
      TPassageSnapshotSource.Create(Snapshot.Passages + FilePassages), FStore, FEmbedder);
    try
      try
        Result.Stats := Indexer.Sync(EmbedCancelled,
          procedure(Done, Total: Integer)
          begin
            SetPending(Total - Done);
            if Assigned(OnProgress) then
              OnProgress(Done, Total);
            YieldLock;
          end);
        Result.Complete := not FilesCut;
      except
        on EOperationCancelled do;
      end;
    finally
      Indexer.Free;
    end;
    FSearcher.Reload;
    RefreshIndexed;
  finally
    FLock.Leave;
  end;
end;

procedure TSemanticSearchService.RunWorker(const Snapshot: TSearchSnapshot;
  const Reader: IFileContentReader; const OnProgress: TSyncProgress;
  const OnDone: TProc<TSemanticSearchStatus>; const Gate: IDeliveryGate);
var
  Queued: TSyncProgress;
  Final: TSemanticSearchStatus;
begin
  Queued := nil;
  if Assigned(OnProgress) then
    Queued :=
      procedure(Done, Total: Integer)
      begin
        TThread.Queue(nil,
          procedure
          begin
            if Gate.IsOpen then
              OnProgress(Done, Total);
          end);
      end;
  try
    FinishSync(RunSync(Snapshot, Reader,
      function: Boolean
      begin
        Result := IsCancelRequested;
      end, Queued, High(Cardinal)));
  except
    on E: Exception do
      FailSync(E.Message);
  end;
  if Assigned(OnDone) then
  begin
    Final := Status;
    TThread.Queue(nil,
      procedure
      begin
        if Gate.IsOpen then
          OnDone(Final);
      end);
  end;
end;

procedure TSemanticSearchService.StartSync(const Snapshot: TSearchSnapshot;
  const Reader: IFileContentReader; const OnProgress: TSyncProgress;
  const OnDone: TProc<TSemanticSearchStatus>);
var
  Gate: IDeliveryGate;
begin
  if not TryBeginSync then
    Exit;
  Gate := FGate;
  try
    if FWorker <> nil then
    begin
      FWorker.WaitFor;
      FreeAndNil(FWorker);
    end;
    FWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        RunWorker(Snapshot, Reader, OnProgress, OnDone, Gate);
      end);
    FWorker.FreeOnTerminate := False;
    FWorker.Start;
  except
    on E: Exception do
    begin
      FailSync(E.Message);
      raise;
    end;
  end;
end;

function TSemanticSearchService.SyncNow(const Snapshot: TSearchSnapshot;
  const Reader: IFileContentReader; DeadlineMs: Cardinal): TSyncOutcome;
var
  Watch: TStopwatch;
begin
  Result := Default(TSyncOutcome);
  if not TryBeginSync then
    Exit;
  Watch := TStopwatch.StartNew;
  try
    Result := RunSync(Snapshot, Reader,
      function: Boolean
      begin
        Result := IsCancelRequested or (Watch.ElapsedMilliseconds > DeadlineMs);
      end, nil, DeadlineMs);
  except
    on E: Exception do
    begin
      FailSync(E.Message);
      raise;
    end;
  end;
  FinishSync(Result);
end;

procedure TSemanticSearchService.CancelSync;
begin
  FStateLock.Enter;
  try
    if FStatus.State = ssSyncing then
      FCancel := True;
  finally
    FStateLock.Leave;
  end;
end;

function TSemanticSearchService.RerankerAvailable: Boolean;
begin
  FStateLock.Enter;
  try
    Result := Assigned(FRerankFactory) and not FRerankFailed;
  finally
    FStateLock.Leave;
  end;
end;

procedure TSemanticSearchService.MarkRerankFailed;
begin
  FStateLock.Enter;
  try
    FRerankFailed := True;
  finally
    FStateLock.Leave;
  end;
end;

function TSemanticSearchService.TryRerank(const Query: string; const Inputs: TArray<string>;
  const Cancelled: TCancelCheck; out Scores: TArray<Single>): Boolean;
var
  Encoder: ICrossEncoder;
  Watch: TStopwatch;
  Budget: Cardinal;
begin
  Scores := nil;
  Result := False;
  FRerankLock.Enter;
  try
    if FEncoder = nil then
    begin
      if not RerankerAvailable then
        Exit;
      try
        FEncoder := FRerankFactory();
      except
        on Exception do
          FEncoder := nil;
      end;
      if FEncoder = nil then
      begin
        MarkRerankFailed;
        Exit;
      end;
    end;
    Encoder := FEncoder;
    Budget := FRerankBudgetMs;
    Watch := TStopwatch.StartNew;
    try
      Scores := Encoder.Score(Query, Inputs,
        function: Boolean
        begin
          Result := (Watch.ElapsedMilliseconds > Budget) or (Assigned(Cancelled) and Cancelled());
        end);
    except
      on Exception do
        Exit;
    end;
    Result := (Length(Scores) = Length(Inputs)) and (Watch.ElapsedMilliseconds <= Budget) and
      not (Assigned(Cancelled) and Cancelled());
  finally
    FRerankLock.Leave;
  end;
end;

function TSemanticSearchService.Search(const Query: string;
  const VisibleProjectIds: TArray<Integer>; TopK: Integer; const Options: THybridSearchOptions;
  const Cancelled: TCancelCheck): TSemanticSearchResult;
var
  Depth: Integer;
  Groups: TArray<THybridGroup>;
  Inputs: TArray<string>;
  Scores: TArray<Single>;
begin
  Result := Default(TSemanticSearchResult);
  Depth := 0;
  if (Options.RerankDepth > 0) and (TopK > 0) and RerankerAvailable then
    Depth := Options.RerankDepth;
  EnterLock;
  try
    EnsureOpen;
    Groups := FSearcher.Search(Query, VisibleProjectIds, Max(TopK, Depth), Options);
    if (Depth > 0) and (Length(Groups) > 1) then
      Inputs := FSearcher.RerankInputs(Groups, Depth);
  finally
    FLock.Leave;
  end;
  if (Length(Inputs) > 1) and TryRerank(Query.Trim, Inputs, Cancelled, Scores) then
  begin
    Groups := ApplyRerankScores(Groups, Scores);
    Result.Reranked := True;
  end;
  if Length(Groups) > TopK then
    SetLength(Groups, Max(TopK, 0));
  Result.Groups := Groups;
  Result.IndexStatus := Status;
end;

function TSemanticSearchService.Status: TSemanticSearchStatus;
begin
  FStateLock.Enter;
  try
    Result := FStatus;
  finally
    FStateLock.Leave;
  end;
end;

function E5EmbedderFactory(const ArtifactRoot: string): TEmbedderFactory;
begin
  Result :=
    function: ITextEmbedder
    begin
      Result := TE5TextEmbedder.Create(TE5EmbedderConfig.FromArtifactRoot(ArtifactRoot));
    end;
end;

end.
