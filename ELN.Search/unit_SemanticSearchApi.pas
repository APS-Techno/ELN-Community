unit unit_SemanticSearchApi;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  unit_TextEmbedder, unit_SearchPassages, unit_HybridSearch;

type
  ESemanticSearchUnavailable = class(Exception);

  ESemanticFilterError = class(Exception);

  ESemanticSearchAccessDenied = class(Exception);

  TServiceState = (ssIdle, ssSyncing, ssFailed);

  TServicePhase = (spIdle, spExtracting, spEmbedding);

  TSemanticSearchStatus = record
    State: TServiceState;
    Phase: TServicePhase;
    FilesDone: Integer;
    FilesTotal: Integer;
    IndexedPassages: Integer;
    PendingPassages: Integer;
    LastError: string;
    LastSyncComplete: Boolean;
    DroppedGroups: Integer;
    function IsComplete: Boolean;
  end;

  TSemanticDateField = (sdfNone, sdfCreated, sdfModified);

  TValueConstraint = record
    ValueType: string;
    HasMin, HasMax: Boolean;
    Min, Max: Double;
    UnitSymbol: string;
    RecType: string;
  end;

  TSemanticSearchFilter = record
    FolderId: Integer;
    ItemTypes: TArray<string>;
    Levels: TArray<string>;
    ActionTypeId: Integer;
    DateField: TSemanticDateField;
    DateFrom, DateTo: TDateTime;
    Values: TArray<TValueConstraint>;
    function IsEmpty: Boolean;
  end;

  TAppliedLimit = record
    ValueTypeId: Integer;
    ValueType, Units, RecType, RequestedUnit: string;
    HasMin, HasMax: Boolean;
    Min, Max: Double;
  end;

  TSemanticSearchRequest = record
    Query: string;
    VisibleProjectIds: TArray<Integer>;
    TopK: Integer;
    Filter: TSemanticSearchFilter;
    Rerank: Boolean;
  end;

  TSemanticSearchResult = record
    Groups: TArray<THybridGroup>;
    Reranked: Boolean;
    IndexStatus: TSemanticSearchStatus;
    FiltersApplied: string;
  end;

  ISemanticSearch = interface
    ['{3F1B6C2E-8D47-4A59-B2E1-9C04D7A6E3F8}']
    function Search(const Request: TSemanticSearchRequest;
      const Cancelled: TCancelCheck): TSemanticSearchResult;
    // Status and RerankerAvailable run on the UI thread (status timer): return cached state,
    // never wait for a running search, a lock held by it, or network I/O.
    function Status: TSemanticSearchStatus;
    function RerankerAvailable: Boolean;
    function IsRemote: Boolean;
  end;

  IDeliveryGate = interface
    ['{7A3C1D52-9B84-4E6F-A0D1-52C8E3F4B791}']
    function IsOpen: Boolean;
    procedure Close;
  end;

  TSearchDone = reference to procedure(const Result: TSemanticSearchResult; const Error: string);

  TSemanticSearchRunner = class
  private
    FSearch: ISemanticSearch;
    FGate: IDeliveryGate;
    FGeneration: Integer;
    FThreads: TList<TThread>;
    procedure ReapThreads;
  public
    constructor Create(const Search: ISemanticSearch);
    destructor Destroy; override;
    procedure Start(const Request: TSemanticSearchRequest; const OnDone: TSearchDone);
  end;

const
  PassageFieldNames: array[TPassageField] of string = ('title', 'description',
    'properties', 'tags', 'entry_title', 'protocol_form', 'value_description',
    'file_name', 'file_text');
  HitSourceNames: array[TSearchHitSource] of string = ('vector', 'words', 'trigram');

function CreateDeliveryGate: IDeliveryGate;

implementation

type
  TDeliveryGate = class(TInterfacedObject, IDeliveryGate)
  private
    FOpen: Boolean;
  public
    constructor Create;
    function IsOpen: Boolean;
    procedure Close;
  end;

constructor TDeliveryGate.Create;
begin
  inherited Create;
  FOpen := True;
end;

function TDeliveryGate.IsOpen: Boolean;
begin
  Result := FOpen;
end;

procedure TDeliveryGate.Close;
begin
  FOpen := False;
end;

function CreateDeliveryGate: IDeliveryGate;
begin
  Result := TDeliveryGate.Create;
end;

function TSemanticSearchStatus.IsComplete: Boolean;
begin
  Result := (State <> ssSyncing) and LastSyncComplete;
end;

function TSemanticSearchFilter.IsEmpty: Boolean;
begin
  Result := (FolderId <= 0) and (Length(ItemTypes) = 0) and (Length(Levels) = 0) and
    (ActionTypeId <= 0) and (DateField = sdfNone) and (Length(Values) = 0);
end;

constructor TSemanticSearchRunner.Create(const Search: ISemanticSearch);
begin
  inherited Create;
  if Search = nil then
    raise EArgumentNilException.Create('A semantic search is required');
  FSearch := Search;
  FGate := CreateDeliveryGate;
  FThreads := TList<TThread>.Create;
end;

destructor TSemanticSearchRunner.Destroy;
var
  Thread: TThread;
begin
  if FGate <> nil then
    FGate.Close;
  TInterlocked.Increment(FGeneration);
  if FThreads <> nil then
    for Thread in FThreads do
    begin
      Thread.WaitFor;
      Thread.Free;
    end;
  FThreads.Free;
  inherited;
end;

procedure TSemanticSearchRunner.ReapThreads;
var
  I: Integer;
begin
  for I := FThreads.Count - 1 downto 0 do
    if FThreads[I].Finished then
    begin
      FThreads[I].Free;
      FThreads.Delete(I);
    end;
end;

procedure TSemanticSearchRunner.Start(const Request: TSemanticSearchRequest;
  const OnDone: TSearchDone);
var
  Search: ISemanticSearch;
  Gate: IDeliveryGate;
  Generation: Integer;
  Thread: TThread;
begin
  if not Assigned(OnDone) then
    raise EArgumentNilException.Create('A completion handler is required');
  Generation := TInterlocked.Increment(FGeneration);
  Search := FSearch;
  Gate := FGate;
  Thread := TThread.CreateAnonymousThread(
    procedure
    var
      Outcome: TSemanticSearchResult;
      Failure: string;
    begin
      Outcome := Default(TSemanticSearchResult);
      Failure := '';
      try
        Outcome := Search.Search(Request,
          function: Boolean
          begin
            Result := TInterlocked.CompareExchange(FGeneration, 0, 0) <> Generation;
          end);
      except
        on E: Exception do
          Failure := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Gate.IsOpen then
            OnDone(Outcome, Failure);
        end);
    end);
  Thread.FreeOnTerminate := False;
  ReapThreads;
  FThreads.Add(Thread);
  Thread.Start;
end;

end.
