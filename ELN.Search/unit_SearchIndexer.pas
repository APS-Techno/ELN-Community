unit unit_SearchIndexer;

interface

uses
  System.SysUtils, unit_SearchPassages, unit_SearchIndexStore, unit_TextEmbedder;

type
  TSyncStats = record
    Added, Changed, Moved, Removed, Unchanged, Truncated: Integer;
    Elapsed: Double;
  end;

  TSyncProgress = reference to procedure(Done, Total: Integer);

  TSearchIndexer = class
  private
    FSource: ISearchDocumentSource;
    FStore: TSearchIndexStore;
    FEmbedder: ITextEmbedder;
    procedure CheckCancelled(const Cancelled: TCancelCheck);
  public
    constructor Create(const Source: ISearchDocumentSource; Store: TSearchIndexStore;
      const Embedder: ITextEmbedder);
    function Sync(const Cancelled: TCancelCheck = nil;
      const Progress: TSyncProgress = nil): TSyncStats;
  end;

const
  SyncEmbedBatch = 32;

implementation

uses
  System.Generics.Collections, System.Diagnostics;

constructor TSearchIndexer.Create(const Source: ISearchDocumentSource;
  Store: TSearchIndexStore; const Embedder: ITextEmbedder);
begin
  inherited Create;
  FSource := Source;
  FStore := Store;
  FEmbedder := Embedder;
end;

procedure TSearchIndexer.CheckCancelled(const Cancelled: TCancelCheck);
begin
  if Assigned(Cancelled) and Cancelled() then
    raise EOperationCancelled.Create('Search index synchronization was cancelled');
end;

function TSearchIndexer.Sync(const Cancelled: TCancelCheck;
  const Progress: TSyncProgress): TSyncStats;
var
  Watch: TStopwatch;
  Passages: TSearchPassages;
  Catalog: TDictionary<string, TStoredPassage>;
  SourceKeys: TDictionary<string, Boolean>;
  Removals: TList<string>;
  Moves, Pending: TList<TSearchPassage>;
  P: TSearchPassage;
  Row: TStoredPassage;
  Key: string;
  First, Count, I: Integer;
  Texts: TArray<string>;
  Embeddings: TArray<TEmbedding>;
begin
  Watch := TStopwatch.StartNew;
  Result := Default(TSyncStats);
  Passages := FSource.ReadSnapshot(Cancelled).Passages;
  Catalog := FStore.ReadCatalog;
  SourceKeys := TDictionary<string, Boolean>.Create;
  Removals := TList<string>.Create;
  Moves := TList<TSearchPassage>.Create;
  Pending := TList<TSearchPassage>.Create;
  try
    for P in Passages do
    begin
      SourceKeys.AddOrSetValue(P.Key, True);
      if not Catalog.TryGetValue(P.Key, Row) then
      begin
        Pending.Add(P);
        Inc(Result.Added);
      end
      else if Row.ContentHash <> P.ContentHash then
      begin
        Pending.Add(P);
        Inc(Result.Changed);
      end
      else if (Row.ProjectId <> P.ProjectId) or (Row.ItemId <> P.ItemId) or (Row.FileId <> P.FileId) then
      begin
        Moves.Add(P);
        Inc(Result.Moved);
      end
      else
        Inc(Result.Unchanged);
    end;
    for Key in Catalog.Keys do
      if not SourceKeys.ContainsKey(Key) then
        Removals.Add(Key);
    Result.Removed := Removals.Count;
    if Assigned(Progress) and (Pending.Count > 0) then Progress(0, Pending.Count);

    if (Removals.Count > 0) or (Moves.Count > 0) then
    begin
      CheckCancelled(Cancelled);
      FStore.BeginBatch;
      try
        for Key in Removals do
          FStore.Delete(Key);
        for P in Moves do
          FStore.UpdateCoordinates(P);
        FStore.CommitBatch;
      except
        FStore.RollbackBatch;
        raise;
      end;
    end;

    First := 0;
    while First < Pending.Count do
    begin
      CheckCancelled(Cancelled);
      Count := Pending.Count - First;
      if Count > SyncEmbedBatch then Count := SyncEmbedBatch;
      SetLength(Texts, Count);
      for I := 0 to Count - 1 do
        Texts[I] := PassageEmbedText(Pending[First + I]);
      Embeddings := FEmbedder.EncodePassages(Texts, olTruncate, Cancelled);
      FStore.BeginBatch;
      try
        for I := 0 to Count - 1 do
          FStore.Upsert(Pending[First + I], Embeddings[I].Vector);
        FStore.CommitBatch;
      except
        FStore.RollbackBatch;
        raise;
      end;
      for I := 0 to Count - 1 do
        if Embeddings[I].Truncated then Inc(Result.Truncated);
      Inc(First, Count);
      if Assigned(Progress) then Progress(First, Pending.Count);
    end;
  finally
    Pending.Free;
    Moves.Free;
    Removals.Free;
    SourceKeys.Free;
    Catalog.Free;
  end;
  Result.Elapsed := Watch.Elapsed.TotalSeconds;
end;

end.
