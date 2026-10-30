unit unit_HybridSearch;

interface

uses
  System.SysUtils, System.Generics.Collections,
  unit_SearchPassages, unit_SearchIndexStore, unit_TextEmbedder, unit_VectorSearch;

type
  TSearchHitSource = (hsVector, hsWords, hsTrigram);

  THybridHit = record
    Key: string;
    ItemId, ProjectId: Integer;
    FileId: Int64;
    Field: TPassageField;
    Score: Double;
    Sources: set of TSearchHitSource;
    Snippet: string;
  end;

  THybridGroup = record
    ItemId, ProjectId: Integer;
    FileId: Int64;
    Score: Double;
    Sources: set of TSearchHitSource;
    Passages: TArray<THybridHit>;
  end;

  THybridSearchOptions = record
    Lists: set of TSearchHitSource;
    RrfK: Integer;
    CandidatesPerList: Integer;
    ListWeights: array[TSearchHitSource] of Double;
    FieldWeights: array[TPassageField] of Double;
    ItemFilter: TItemFilter;
    RerankDepth: Integer;
    LiveSource: ISearchDocumentSource;
    class function Default: THybridSearchOptions; static;
  end;

  THybridSearcher = class
  private
    FStore: TSearchIndexStore;
    FEmbedder: ITextEmbedder;
    FSource: ISearchDocumentSource;
    FIndex: TExactVectorIndex;
    FCatalog: TDictionary<string, TStoredPassage>;
  public
    constructor Create(Store: TSearchIndexStore; const Embedder: ITextEmbedder;
      const Source: ISearchDocumentSource);
    destructor Destroy; override;
    procedure Reload;
    function Search(const Query: string; const VisibleProjectIds: TArray<Integer>;
      TopK: Integer; const Options: THybridSearchOptions): TArray<THybridGroup>;
    function RerankInputs(const Groups: TArray<THybridGroup>; Depth: Integer): TArray<string>;
  end;

function ApplyRerankScores(const Groups: TArray<THybridGroup>;
  const Scores: TArray<Single>): TArray<THybridGroup>;

const
  DefaultRrfK = 60;
  DefaultCandidatesPerList = 50;
  DefaultRerankDepth = 20;
  MaxGroupPassages = 3;

implementation

uses
  System.Math, System.Character, System.Generics.Defaults, unit_PassageContext;

type
  TFusedEntry = record
    Ranks: array[TSearchHitSource] of Integer;
  end;

  TLiveState = record
    Live: Boolean;
    ProjectId: Integer;
  end;

const
  MinQueryChars = 2;
  TrigramQueryChars = 3;
  SnippetChars = 200;
  ScoreTolerance = 1e-12;

class function THybridSearchOptions.Default: THybridSearchOptions;
var
  Source: TSearchHitSource;
  Field: TPassageField;
begin
  Result.Lists := [hsVector, hsWords, hsTrigram];
  Result.ItemFilter.Active := False;
  Result.ItemFilter.ItemIds := nil;
  Result.RerankDepth := DefaultRerankDepth;
  Result.LiveSource := nil;
  Result.RrfK := DefaultRrfK;
  Result.CandidatesPerList := DefaultCandidatesPerList;
  for Source := Low(TSearchHitSource) to High(TSearchHitSource) do
    Result.ListWeights[Source] := 1;
  for Field := Low(TPassageField) to High(TPassageField) do
    Result.FieldWeights[Field] := 1;
end;

function SnippetOf(const Text: string): string;
var
  Count: Integer;
begin
  Count := Length(Text);
  if Count <= SnippetChars then
    Exit(Text);
  Count := SnippetChars;
  if Text[Count].IsHighSurrogate then
    Dec(Count);
  Result := Copy(Text, 1, Count);
end;

constructor THybridSearcher.Create(Store: TSearchIndexStore; const Embedder: ITextEmbedder;
  const Source: ISearchDocumentSource);
begin
  inherited Create;
  if (Store = nil) or (Embedder = nil) or (Source = nil) then
    raise EArgumentNilException.Create('Store, embedder and document source are required');
  FStore := Store;
  FEmbedder := Embedder;
  FSource := Source;
  Reload;
end;

destructor THybridSearcher.Destroy;
begin
  FCatalog.Free;
  FIndex.Free;
  inherited;
end;

procedure THybridSearcher.Reload;
var
  Index: TExactVectorIndex;
  Catalog: TDictionary<string, TStoredPassage>;
begin
  Index := TExactVectorIndex.Create(FEmbedder.Dimension);
  try
    FStore.LoadVectors(Index);
    Catalog := FStore.ReadCatalog;
  except
    Index.Free;
    raise;
  end;
  FCatalog.Free;
  FIndex.Free;
  FCatalog := Catalog;
  FIndex := Index;
end;

function THybridSearcher.Search(const Query: string; const VisibleProjectIds: TArray<Integer>;
  TopK: Integer; const Options: THybridSearchOptions): TArray<THybridGroup>;
var
  Text: string;
  Scopes: TArray<string>;
  Visible: TDictionary<Integer, Boolean>;
  Fused: TDictionary<string, TFusedEntry>;
  Live: TDictionary<Integer, TLiveState>;
  TieRanks: TDictionary<string, Integer>;
  Hits: TList<THybridHit>;
  Groups: TList<THybridGroup>;
  GroupOfItem: TDictionary<Integer, Integer>;
  Group: THybridGroup;
  Pair: TPair<string, TFusedEntry>;
  Stored: TStoredPassage;
  Hit: THybridHit;
  I, J, Id: Integer;
  Sources: set of TSearchHitSource;
  Source: TSearchHitSource;
  VectorHit: TVectorHit;
  TextHit: TTextHit;
  LiveSource: ISearchDocumentSource;

  procedure AddRank(const Key: string; Rank: Integer; Source: TSearchHitSource);
  var
    Entry: TFusedEntry;
  begin
    if not Fused.TryGetValue(Key, Entry) then
      Entry := Default(TFusedEntry);
    Entry.Ranks[Source] := Rank;
    Fused.AddOrSetValue(Key, Entry);
  end;

  function FusedScore(const Entry: TFusedEntry; Field: TPassageField): Double;
  var
    Source: TSearchHitSource;
  begin
    Result := 0;
    for Source := Low(TSearchHitSource) to High(TSearchHitSource) do
      if Entry.Ranks[Source] > 0 then
        Result := Result + Options.ListWeights[Source] / (Options.RrfK + Entry.Ranks[Source]);
    Result := Result * Options.FieldWeights[Field];
  end;

  function ZeroWeightRank(const Entry: TFusedEntry): Integer;
  var
    Source: TSearchHitSource;
  begin
    Result := MaxInt;
    for Source := Low(TSearchHitSource) to High(TSearchHitSource) do
      if (Options.ListWeights[Source] <= 0) and (Entry.Ranks[Source] > 0) then
        Result := Min(Result, Entry.Ranks[Source]);
  end;

  function IsVisibleLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  var
    State: TLiveState;
  begin
    if not Live.TryGetValue(ItemId, State) then
    begin
      State.Live := LiveSource.IsItemLive(ItemId, State.ProjectId);
      Live.Add(ItemId, State);
    end;
    ProjectId := State.ProjectId;
    Result := State.Live and Visible.ContainsKey(State.ProjectId);
  end;

begin
  Text := Query.Trim;
  if (Length(Text) < MinQueryChars) or (Length(VisibleProjectIds) = 0) or (TopK < 1) or
    (Options.ItemFilter.Active and (Length(Options.ItemFilter.ItemIds) = 0)) then
    Exit(nil);
  LiveSource := Options.LiveSource;
  if LiveSource = nil then
    LiveSource := FSource;
  Visible := TDictionary<Integer, Boolean>.Create;
  Fused := TDictionary<string, TFusedEntry>.Create;
  Live := TDictionary<Integer, TLiveState>.Create;
  TieRanks := TDictionary<string, Integer>.Create;
  Hits := TList<THybridHit>.Create;
  try
    SetLength(Scopes, Length(VisibleProjectIds));
    for I := 0 to High(VisibleProjectIds) do
    begin
      Visible.AddOrSetValue(VisibleProjectIds[I], True);
      Scopes[I] := IntToStr(VisibleProjectIds[I]);
    end;

    if (hsVector in Options.Lists) and (FIndex.Count > 0) then
    try
      I := 0;
      for VectorHit in FIndex.Search(FEmbedder.EncodeQuery(FoldSearchText(Text)).Vector,
        Options.CandidatesPerList, Scopes, Options.ItemFilter) do
      begin
        Inc(I);
        AddRank(VectorHit.SourceId, I, hsVector);
      end;
    except
      on ETextTooLong do;
    end;
    if hsWords in Options.Lists then
      for TextHit in FStore.MatchWords(Text, VisibleProjectIds, Options.CandidatesPerList,
        Options.ItemFilter) do
        AddRank(TextHit.Key, TextHit.Rank, hsWords);
    if (hsTrigram in Options.Lists) and (Length(Text) >= TrigramQueryChars) then
      for TextHit in FStore.MatchTrigrams(Text, VisibleProjectIds, Options.CandidatesPerList,
        Options.ItemFilter) do
        AddRank(TextHit.Key, TextHit.Rank, hsTrigram);

    for Pair in Fused do
    begin
      if not FCatalog.TryGetValue(Pair.Key, Stored) then
        Continue;
      if not IsVisibleLive(Stored.ItemId, Id) then
        Continue;
      Hit := Default(THybridHit);
      Hit.Key := Pair.Key;
      Hit.ItemId := Stored.ItemId;
      Hit.ProjectId := Id;
      Hit.FileId := Stored.FileId;
      Hit.Field := Stored.Field;
      Hit.Score := FusedScore(Pair.Value, Stored.Field);
      Sources := [];
      for Source := Low(TSearchHitSource) to High(TSearchHitSource) do
        if Pair.Value.Ranks[Source] > 0 then
          Include(Sources, Source);
      Hit.Sources := Sources;
      Hits.Add(Hit);
      TieRanks.Add(Hit.Key, ZeroWeightRank(Pair.Value));
    end;

    Hits.Sort(TComparer<THybridHit>.Construct(
      function(const A, B: THybridHit): Integer
      begin
        Result := CompareValue(B.Score, A.Score, ScoreTolerance);
        if Result = 0 then
          Result := CompareValue(TieRanks[A.Key], TieRanks[B.Key]);
        if Result = 0 then
          Result := CompareStr(A.Key, B.Key);
      end));

    Groups := TList<THybridGroup>.Create;
    GroupOfItem := TDictionary<Integer, Integer>.Create;
    try
      for Hit in Hits do
      begin
        if GroupOfItem.TryGetValue(Hit.ItemId, I) then
        begin
          Group := Groups[I];
          Group.Sources := Group.Sources + Hit.Sources;
          if Length(Group.Passages) < MaxGroupPassages then
            Group.Passages := Group.Passages + [Hit];
          Groups[I] := Group;
        end
        else
        begin
          Group := Default(THybridGroup);
          Group.ItemId := Hit.ItemId;
          Group.ProjectId := Hit.ProjectId;
          Group.FileId := Hit.FileId;
          Group.Score := Hit.Score;
          Group.Sources := Hit.Sources;
          Group.Passages := [Hit];
          GroupOfItem.Add(Hit.ItemId, Groups.Count);
          Groups.Add(Group);
        end;
      end;
      Groups.Sort(TComparer<THybridGroup>.Construct(
        function(const A, B: THybridGroup): Integer
        begin
          Result := CompareValue(B.Score, A.Score, ScoreTolerance);
          if Result = 0 then
            Result := CompareValue(TieRanks[A.Passages[0].Key], TieRanks[B.Passages[0].Key]);
          if Result = 0 then
            Result := CompareValue(A.ItemId, B.ItemId);
        end));
      if Groups.Count > TopK then
        Groups.DeleteRange(TopK, Groups.Count - TopK);
      Result := Groups.ToArray;
    finally
      GroupOfItem.Free;
      Groups.Free;
    end;
    for I := 0 to High(Result) do
      for J := 0 to High(Result[I].Passages) do
        Result[I].Passages[J].Snippet := SnippetOf(FStore.PassageText(Result[I].Passages[J].Key));
  finally
    Hits.Free;
    TieRanks.Free;
    Live.Free;
    Fused.Free;
    Visible.Free;
  end;
end;

function THybridSearcher.RerankInputs(const Groups: TArray<THybridGroup>;
  Depth: Integer): TArray<string>;
var
  I: Integer;
  Best: THybridHit;
  Json, Context: string;
  Parts: TPassageContextParts;
begin
  SetLength(Result, Min(Depth, Length(Groups)));
  for I := 0 to High(Result) do
  begin
    Best := Groups[I].Passages[0];
    Result[I] := FStore.PassageText(Best.Key);
    Context := '';
    if FStore.ReadItemContext(Best.ItemId, Json) and TryParsePassageContextParts(Json, Parts) then
      Context := BuildPassageContext(Parts, Best.Field);
    if Context <> '' then
      Result[I] := Context + #10 + Result[I];
  end;
end;

function ApplyRerankScores(const Groups: TArray<THybridGroup>;
  const Scores: TArray<Single>): TArray<THybridGroup>;
var
  Order: TArray<Integer>;
  I: Integer;
begin
  if Length(Scores) > Length(Groups) then
    raise EArgumentException.Create('More reranker scores than groups');
  SetLength(Order, Length(Scores));
  for I := 0 to High(Order) do
    Order[I] := I;
  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := CompareValue(Scores[B], Scores[A]);
      if Result = 0 then
        Result := CompareValue(A, B);
    end));
  SetLength(Result, Length(Groups));
  for I := 0 to High(Order) do
    Result[I] := Groups[Order[I]];
  for I := Length(Order) to High(Groups) do
    Result[I] := Groups[I];
end;

end.
