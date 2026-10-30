unit unit_VectorSearch;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  EVectorSearchError = class(Exception);

  TVectorHit = record
    SourceId: string;
    Scope: string;
    Score: Double;
  end;

  TItemFilter = record
    Active: Boolean;
    ItemIds: TArray<Integer>;
    class function Only(const Ids: TArray<Integer>): TItemFilter; static;
  end;

  { Exact cosine search over L2-normalized vectors. A search sees only entries
    whose scope is in the caller's explicit eligible set; an empty set yields
    no results. An active item filter narrows the entries further before the
    TopK cut; an active filter without ids yields no results. }
  TExactVectorIndex = class
  private
    FDimension: Integer;
    FIds: TList<string>;
    FScopes: TList<string>;
    FItemIds: TList<Integer>;
    FVectors: TList<TArray<Single>>;
    FIdSet: TDictionary<string, Integer>;
    function GetCount: Integer;
  public
    constructor Create(Dimension: Integer);
    destructor Destroy; override;
    procedure Add(const SourceId, Scope: string; ItemId: Integer; const Vector: TArray<Single>);
    function Search(const Query: TArray<Single>; TopK: Integer;
      const EligibleScopes: TArray<string>; const AllowedItems: TItemFilter): TArray<TVectorHit>;
    property Count: Integer read GetCount;
    property Dimension: Integer read FDimension;
  end;

const
  NormTolerance = 1e-3;

function VectorNorm(const Vector: TArray<Single>): Double;

implementation

uses
  System.Generics.Defaults, System.Math;

function VectorNorm(const Vector: TArray<Single>): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Vector) do
    Result := Result + Sqr(Double(Vector[I]));
  Result := Sqrt(Result);
end;

{ TItemFilter }

class function TItemFilter.Only(const Ids: TArray<Integer>): TItemFilter;
begin
  Result.Active := True;
  Result.ItemIds := Ids;
end;

{ TExactVectorIndex }

constructor TExactVectorIndex.Create(Dimension: Integer);
begin
  inherited Create;
  if Dimension < 1 then
    raise EVectorSearchError.Create('Vector dimension must be positive');
  FDimension := Dimension;
  FIds := TList<string>.Create;
  FScopes := TList<string>.Create;
  FItemIds := TList<Integer>.Create;
  FVectors := TList<TArray<Single>>.Create;
  FIdSet := TDictionary<string, Integer>.Create;
end;

destructor TExactVectorIndex.Destroy;
begin
  FIdSet.Free;
  FVectors.Free;
  FItemIds.Free;
  FScopes.Free;
  FIds.Free;
  inherited;
end;

function TExactVectorIndex.GetCount: Integer;
begin
  Result := FIds.Count;
end;

procedure TExactVectorIndex.Add(const SourceId, Scope: string; ItemId: Integer;
  const Vector: TArray<Single>);
begin
  if SourceId = '' then
    raise EVectorSearchError.Create('Source id is empty');
  if FIdSet.ContainsKey(SourceId) then
    raise EVectorSearchError.CreateFmt('Duplicate source id: %s', [SourceId]);
  if Length(Vector) <> FDimension then
    raise EVectorSearchError.CreateFmt('Vector for %s has dimension %d, expected %d',
      [SourceId, Length(Vector), FDimension]);
  if not (Abs(VectorNorm(Vector) - 1) <= NormTolerance) then
    raise EVectorSearchError.CreateFmt('Vector for %s is not L2-normalized', [SourceId]);
  FIdSet.Add(SourceId, FIds.Count);
  FIds.Add(SourceId);
  FScopes.Add(Scope);
  FItemIds.Add(ItemId);
  FVectors.Add(Copy(Vector));
end;

function TExactVectorIndex.Search(const Query: TArray<Single>; TopK: Integer;
  const EligibleScopes: TArray<string>; const AllowedItems: TItemFilter): TArray<TVectorHit>;
var
  Eligible: TDictionary<string, Boolean>;
  Allowed: TDictionary<Integer, Boolean>;
  Hits: TList<TVectorHit>;
  Hit: TVectorHit;
  Scope: string;
  ItemId: Integer;
  I, D: Integer;
  Dot: Double;
  V: TArray<Single>;
begin
  if Length(Query) <> FDimension then
    raise EVectorSearchError.CreateFmt('Query has dimension %d, expected %d', [Length(Query), FDimension]);
  if not (Abs(VectorNorm(Query) - 1) <= NormTolerance) then
    raise EVectorSearchError.Create('Query vector is not L2-normalized');
  if TopK < 1 then
    raise EVectorSearchError.Create('TopK must be at least 1');
  if AllowedItems.Active and (Length(AllowedItems.ItemIds) = 0) then
    Exit(nil);
  Eligible := TDictionary<string, Boolean>.Create;
  Allowed := nil;
  Hits := TList<TVectorHit>.Create;
  try
    for Scope in EligibleScopes do
      Eligible.AddOrSetValue(Scope, True);
    if AllowedItems.Active then
    begin
      Allowed := TDictionary<Integer, Boolean>.Create;
      for ItemId in AllowedItems.ItemIds do
        Allowed.AddOrSetValue(ItemId, True);
    end;
    for I := 0 to FIds.Count - 1 do
    begin
      if not Eligible.ContainsKey(FScopes[I]) then
        Continue;
      if AllowedItems.Active and not Allowed.ContainsKey(FItemIds[I]) then
        Continue;
      V := FVectors[I];
      Dot := 0;
      for D := 0 to FDimension - 1 do
        Dot := Dot + Double(V[D]) * Query[D];
      Hit.SourceId := FIds[I];
      Hit.Scope := FScopes[I];
      Hit.Score := Dot;
      Hits.Add(Hit);
    end;
    Hits.Sort(TComparer<TVectorHit>.Construct(
      function(const A, B: TVectorHit): Integer
      begin
        Result := CompareValue(B.Score, A.Score);
        if Result = 0 then
          Result := CompareStr(A.SourceId, B.SourceId);
      end));
    Result := Copy(Hits.ToArray, 0, Min(TopK, Hits.Count));
  finally
    Hits.Free;
    Allowed.Free;
    Eligible.Free;
  end;
end;

end.
