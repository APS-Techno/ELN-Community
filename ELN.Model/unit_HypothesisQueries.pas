unit unit_HypothesisQueries;

{ Eligibility reads must remain independent of human gate execution.
  SummaryNeedsDecision is shared by desktop and web so their needs_me rules
  agree. Query only requested run IDs, chunked to respect SQL limits. }

interface

uses
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_HypothesisModel,
  unit_ProjectAccessPolicy;

/// Shared needs_me rule for desktop and web; eligibility never executes a gate.
function SummaryNeedsDecision(AGates: TGateEligibility;
  const S: THypothesisSummary): Boolean;

/// Proposed hypotheses AUser may approve, and InReview ones AUser may
/// accept, across every project AUser can read. Oldest first, by
/// (ModifiedDate, else CreatedDate), then Id.
function NeedsMyApproval(AManager: TObjectManager;
  AUser: TUser; const AAccess: IProjectAccessPolicy): TArray<THypothesisSummary>;

/// Of AItemIds, those attached to any hypothesis with Role = Run. Caller
/// frees. Queries only the requested ids (chunked IN), never the whole table.
function RunItemIds(AManager: TObjectManager;
  const AItemIds: TArray<Integer>): TDictionary<Integer, Boolean>;

type
  THypProjectBadge = record
    Count: Integer;
    Waiting: Integer;
  end;

/// Per project id: how many hypotheses it holds and how many of them wait
/// on AUser (NeedsMyApproval, so the badge and "Waiting for You" agree).
/// Projects without hypotheses are absent. Counts cover every project; the
/// caller only shows them on project nodes AUser can already see. Caller
/// frees.
function HypothesisBadges(AManager: TObjectManager;
  AUser: TUser; const AAccess: IProjectAccessPolicy): TDictionary<Integer, THypProjectBadge>;

implementation

uses
  System.Variants,
  System.Generics.Defaults,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections,
  unit_Hypothesis,
  unit_HypothesisRun;

const
  // Ids per IN (...) list; same limit and reasoning as
  // unit_HypothesisModel.IN_CHUNK.
  IN_CHUNK = 500;

function IdChunks(const AIds: TArray<Integer>): TArray<TArray<Variant>>;
var
  L: TList<TArray<Variant>>;
  C: TArray<Variant>;
  I, N, K: Integer;
begin
  L := TList<TArray<Variant>>.Create;
  try
    I := 0;
    while I < Length(AIds) do
    begin
      N := Length(AIds) - I;
      if N > IN_CHUNK then
        N := IN_CHUNK;
      C := nil;
      SetLength(C, N);
      for K := 0 to N - 1 do
        C[K] := AIds[I + K];
      L.Add(C);
      Inc(I, N);
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function SummaryNeedsDecision(AGates: TGateEligibility;
  const S: THypothesisSummary): Boolean;
var
  Reason: string;
begin
  case S.Status of
    hsProposed: Result := AGates.CanPassGate(S.ProjectId, S.CreatedBy,
      hgApproveProposals, Reason);
    hsInReview: Result := AGates.CanPassGate(S.ProjectId, S.CreatedBy,
      hgAcceptConclusions, Reason);
  else
    Result := False;
  end;
end;

// Ascending: oldest first. ModifiedDate = 0 means never modified, so
// CreatedDate stands in for it - the same fallback SummaryToJson uses for
// the wire's modified_at.
function OldestFirst(const A, B: THypothesisSummary): Integer;
var
  AKey, BKey: TDateTime;
begin
  AKey := A.ModifiedDate;
  if AKey = 0 then
    AKey := A.CreatedDate;
  BKey := B.ModifiedDate;
  if BKey = 0 then
    BKey := B.CreatedDate;
  if AKey < BKey then
    Result := -1
  else if AKey > BKey then
    Result := 1
  else
    Result := A.Id - B.Id;
end;

function NeedsMyApprovalIn(AManager: TObjectManager; AUser: TUser;
  const AProjectIds: TArray<Integer>; const AAccess: IProjectAccessPolicy): TArray<THypothesisSummary>;
var
  Model: THypothesisModel;
  Gates: TGateEligibility;
  Flt: THypothesisFilter;
  All: TArray<THypothesisSummary>;
  S: THypothesisSummary;
  L: TList<THypothesisSummary>;
begin
  Result := nil;
  if AUser = nil then
    Exit;
  Model := THypothesisModel.Create(AManager, AAccess);
  Gates := AAccess.CreateGateEligibility(AManager, AUser);
  L := TList<THypothesisSummary>.Create;
  try
    Flt := THypothesisFilter.All;
    Flt.Statuses := [hsProposed, hsInReview];
    Flt.ProjectIds := AProjectIds;
    All := Model.List(AUser, Flt);
    for S in All do
      if SummaryNeedsDecision(Gates, S) then
        L.Add(S);
    L.Sort(TComparer<THypothesisSummary>.Construct(
      function(const A, B: THypothesisSummary): Integer
      begin
        Result := OldestFirst(A, B);
      end));
    Result := L.ToArray;
  finally
    L.Free;
    Gates.Free;
    Model.Free;
  end;
end;

function NeedsMyApproval(AManager: TObjectManager;
  AUser: TUser; const AAccess: IProjectAccessPolicy): TArray<THypothesisSummary>;
begin
  Result := NeedsMyApprovalIn(AManager, AUser, nil, AAccess);
end;

// A projection of ItemId alone, with the Run-role filter in the query: no
// THypothesisRun entity is hydrated or attached to AManager's identity map
// (the item tree calls this on the shared desktop manager on every fill), and
// a projection is fresh by construction, so no .Refreshing is needed.
function RunItemIds(AManager: TObjectManager;
  const AItemIds: TArray<Integer>): TDictionary<Integer, Boolean>;
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  Result := TDictionary<Integer, Boolean>.Create;
  if Length(AItemIds) = 0 then
    Exit;
  try
    for Chunk in IdChunks(AItemIds) do
    begin
      Rows := AManager.Find<THypothesisRun>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('ItemId').As_('ItemId')))
        .Where(Linq['ItemId']._In(Chunk) and (Linq['Role'] = Ord(hrrRun)))
        .ListValues;
      try
        for Row in Rows do
          if not VarIsNull(Row.Values['ItemId']) then
            Result.AddOrSetValue(Integer(Row.Values['ItemId']), True);
      finally
        Rows.Free;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

// Counts are two grouped projections (nothing hydrated into the shared
// desktop manager). Waiting reuses the NeedsMyApproval rule, but only over
// the projects that hold a Proposed or InReview node - and not at all when
// none does - because the project tree refreshes its badges on every rebuild.
function HypothesisBadges(AManager: TObjectManager;
  AUser: TUser; const AAccess: IProjectAccessPolicy): TDictionary<Integer, THypProjectBadge>;
var
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  B: THypProjectBadge;
  S: THypothesisSummary;
  Pending: TList<Integer>;
begin
  Result := TDictionary<Integer, THypProjectBadge>.Create;
  try
    Rows := AManager.Find<THypothesis>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Group('ProjectId').As_('ProjectId'))
        .Add(TProjections.Count('Id').As_('N')))
      .ListValues;
    try
      for Row in Rows do
      begin
        B.Count := Integer(Row.Values['N']);
        B.Waiting := 0;
        Result.AddOrSetValue(Integer(Row.Values['ProjectId']), B);
      end;
    finally
      Rows.Free;
    end;

    Pending := TList<Integer>.Create;
    try
      Rows := AManager.Find<THypothesis>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Group('ProjectId').As_('ProjectId')))
        .Where((Linq['Status'] = Ord(hsProposed)) or (Linq['Status'] = Ord(hsInReview)))
        .ListValues;
      try
        for Row in Rows do
          Pending.Add(Integer(Row.Values['ProjectId']));
      finally
        Rows.Free;
      end;

      if (Pending.Count > 0) and (AUser <> nil) then
        for S in NeedsMyApprovalIn(AManager, AUser, Pending.ToArray, AAccess) do
          if Result.TryGetValue(S.ProjectId, B) then
          begin
            Inc(B.Waiting);
            Result[S.ProjectId] := B;
          end;
    finally
      Pending.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
