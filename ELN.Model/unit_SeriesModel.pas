unit unit_SeriesModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager,
  Aurelius.Types.Nullable,
  unit_User,
  unit_ItemTypes,
  unit_AuditLog,
  unit_ProjectAccessPolicy,
  unit_Series,
  unit_SeriesColumn,
  unit_SeriesSlot,
  unit_SeriesTable;

type
  ESeriesError = class(Exception);
  ESeriesAccess = class(ESeriesError);

  TSeriesSummary = record
    Id, ProjectId: Integer;
    Title, Purpose: string;
    Status: TSeriesStatus;
    MemberCount, PointCount, MeasuredCount: Integer;
    CreatedBy: Integer;
  end;

  TSeriesMembership = record
    SeriesId: Integer;
    Title, Levels: string;
    Failed: Boolean;
  end;

  TSeriesSlotInfo = record
    SlotId: Integer;
    Levels: TSeriesPoint;
    Origin: TSeriesSlotOrigin;
    ValidItemId: Integer;
  end;

  TSeriesPlanInfo = record
    Plan: TSeriesPlan;
    Slots: TArray<TSeriesSlotInfo>;
  end;

  TSeriesDepositionDraft = record
    Title, Description, Properties: string;
    ActionTypeId, EquipmentId: Integer;
  end;

  TSeriesLinkOutcome = (sloLinked, sloNewPoint, sloNoValue, sloAmbiguousValue,
    sloSlotTaken, sloAlreadyMember, sloOutsideRange, sloNotRoot);

  TSeriesLinkLine = record
    ItemId: Integer;
    Outcome: TSeriesLinkOutcome;
    SlotId: Integer;
    Levels: TSeriesPoint;
  end;

  TSeriesNode = record
    Parent: Integer;
    Level: TItemLevel;
    ActionTypeId: Integer;
  end;

  TSeriesFactorRef = record
    Id, ValueTypeId: Integer;
    RangeMin, RangeMax: Nullable<Double>;
    EntryLabel: string;
  end;

  TSeriesItemFacts = record
    ProjectId, Parent, Level: Integer;
    IsDeleted: Boolean;
  end;

  TSeriesSubtreeValue = record
    Root, TypeId: Integer;
    RecType: TRecType;
    Value, Tol: Double;
    Planned: Boolean;
    Key: string;
  end;

  TSeriesModel = class
  private
    FManager: TObjectManager;
    FAccess: IProjectAccessPolicy;
    FVia: TSeriesCreatedVia;
    procedure RequireRead(AUser: TUser; AProjectId: Integer);
    procedure RequireWrite(AUser: TUser; AProjectId: Integer);
    procedure RequireOpen(S: TSeries);
    procedure RequireActive(S: TSeries);
    procedure RequireValueType(AId: Integer);
    function LoadSeries(AId: Integer): TSeries;
    procedure Discard(AObj: TObject);
    procedure DiscardAll(AList: TList<TObject>);
    procedure DiscardAudit(AType: TAuditEntityType; AId: Integer);
    procedure Unwind(const ATrans: IDBTransaction; AError: Exception;
      S: TSeries);
    function MemberCounts(const AIds, AProjectIds: TArray<Integer>): TDictionary<Integer, Integer>;
    procedure SlotStats(AProjectId: Integer; const AIds: TArray<Integer>;
      APoints, AMeasured: TDictionary<Integer, Integer>);
    function Summarize(S: TSeries; ACount, APoints, AMeasured: Integer): TSeriesSummary;
    class function CleanTitle(const ATitle: string): string; static;
    procedure LoadNodes(AProjectId: Integer;
      ANodes: TDictionary<Integer, TSeriesNode>;
      AChildren: TDictionary<Integer, TList<Integer>>);
    function SubtreeValues(AProjectId: Integer;
      const ARoots, ATypeIds: TArray<Integer>): TArray<TSeriesSubtreeValue>;
    function LoadItemFacts(const AIds: TArray<Integer>): TDictionary<Integer, TSeriesItemFacts>;
    procedure CheckLinkable(S: TSeries; AItemId: Integer);
    function LoadFactors(AId: Integer): TArray<TSeriesFactorRef>;
    function FactorsOfPlan(const APlan: TSeriesPlan): TArray<TSeriesFactorRef>;
    function ReadSlots(AId: Integer;
      const AFactors: TArray<TSeriesFactorRef>): TArray<TSeriesSlotInfo>;
    function FindSlot(const ASlots: TArray<TSeriesSlotInfo>; ASlotId: Integer): Integer;
    function PointText(const AFactors: TArray<TSeriesFactorRef>;
      const ALevels: TSeriesPoint): string;
    procedure ValidatePlan(const APlan: TSeriesPlan);
    procedure CheckTargetFolder(AProjectId, AFolderId: Integer);
    procedure RaiseSlotTaken(S: TSeries; AItemId: Integer);
    procedure CheckNewPoints(const AFactors: TArray<TSeriesFactorRef>;
      const AExisting: TArray<TSeriesSlotInfo>; const APoints: TArray<TSeriesPoint>);
    function AddSlots(AId, AUserId: Integer; const AFactors: TArray<TSeriesFactorRef>;
      const APoints: TArray<TSeriesPoint>; AOrigin: TSeriesSlotOrigin;
      const AReason: string; AFresh: TList<TObject>): TArray<Integer>;
    procedure SyncFactors(AId: Integer; const APlan: TSeriesPlan;
      AFresh: TList<TObject>);
    procedure SyncFixed(AId: Integer; const APlan: TSeriesPlan;
      AFresh: TList<TObject>);
    procedure UpsertColumn(AId: Integer; ACols: TList<TSeriesColumn>;
      AFresh: TList<TObject>; ARecType: TRecType; AValueTypeId: Integer;
      const ASourceKey: string; ARole: TSeriesColumnRole; const AEntryLabel: string);
    procedure NewMember(AId, AItemId, ASlotId, AUserId: Integer;
      AFresh: TList<TObject>);
    function InsertPoints(AUser: TUser; AId: Integer;
      const APoints: TArray<TSeriesPoint>; const AReason: string;
      ASkipExisting: Boolean): TArray<Integer>;
    function ApplyPoints(S: TSeries; AUserId: Integer;
      const APoints: TArray<TSeriesPoint>; const AReason: string;
      ASkipExisting: Boolean; AFresh: TList<TObject>;
      out AAdded: Integer): TArray<Integer>;
    procedure CheckPlanAgainstPoints(AId: Integer;
      const AWanted: TArray<TSeriesFactorRef>);
    procedure ApplyPlan(S: TSeries; const APlan: TSeriesPlan;
      AFresh: TList<TObject>);
    function ComputeLinks(S: TSeries; const AFactors: TArray<TSeriesFactorRef>;
      const ASlots: TArray<TSeriesSlotInfo>;
      const AItemIds: TArray<Integer>): TArray<TSeriesLinkLine>;
  public
    constructor Create(AManager: TObjectManager; const AAccess: IProjectAccessPolicy;
      AVia: TSeriesCreatedVia = scvDesktop);
    function ListSeries(AUser: TUser; AProjectId: Integer): TArray<TSeriesSummary>;
    function Get(AUser: TUser; AId: Integer): TSeriesSummary;
    function ItemMemberships(AUser: TUser; AItemId: Integer): TArray<TSeriesMembership>;
    function FormatLevels(AUser: TUser; AId: Integer;
      const ALevels: TSeriesPoint): string;
    function ConfirmPlanned(AUser: TUser; AItemId: Integer): Integer;
    function CreateSeries(AUser: TUser; AProjectId: Integer;
      const ATitle, APurpose: string; const APlan: TSeriesPlan;
      const APoints: TArray<TSeriesPoint>): Integer;
    procedure UpdateSeries(AUser: TUser; AId: Integer; const ATitle, APurpose: string);
    procedure ChangeStatus(AUser: TUser; AId: Integer; ANew: TSeriesStatus);
    function GetPlan(AUser: TUser; AId: Integer): TSeriesPlanInfo;
    procedure SavePlan(AUser: TUser; AId: Integer; const APlan: TSeriesPlan);
    function UpdatePlanAndPoints(AUser: TUser; AId: Integer;
      AChangePurpose: Boolean; const APurpose: string; AChangePlan: Boolean;
      const APlan: TSeriesPlan; const APoints: TArray<TSeriesPoint>;
      const AReason: string): TArray<Integer>;
    procedure SetColumnRole(AUser: TUser; AId: Integer; ARecType: TRecType;
      AValueTypeId: Integer; const ASourceKey: string; ARole: TSeriesColumnRole);
    function AddPoints(AUser: TUser; AId: Integer;
      const APoints: TArray<TSeriesPoint>; const AReason: string): TArray<Integer>;
    function FillGrid(AUser: TUser; AId: Integer;
      const ALevels: TArray<TArray<Double>>): TArray<Integer>;
    procedure RemovePoint(AUser: TUser; AId, ASlotId: Integer);
    procedure Start(AUser: TUser; AId: Integer);
    function DefaultDepositionTitle(AUser: TUser; AId, ASlotId: Integer): string;
    procedure DepositionDefaults(AUser: TUser; AId: Integer;
      out AActionTypeId, AEquipmentId: Integer);
    function MakeDeposition(AUser: TUser; AId, ASlotId: Integer;
      const ADraft: TSeriesDepositionDraft): Integer;
    procedure LinkToSlot(AUser: TUser; AId, ASlotId, AItemId: Integer);
    function PreviewLinkByValues(AUser: TUser; AId: Integer;
      const AItemIds: TArray<Integer>): TArray<TSeriesLinkLine>;
    function LinkByValues(AUser: TUser; AId: Integer;
      const AItemIds: TArray<Integer>; ACreateMissing: Boolean): TArray<TSeriesLinkLine>;
    procedure MarkFailed(AUser: TUser; AId, AItemId: Integer; const AReason: string);
    procedure Unlink(AUser: TUser; AId, AItemId: Integer);
    function BuildTable(AUser: TUser; AId: Integer;
      AIncludeFailed: Boolean): TSeriesTable;
  end;

implementation

uses
  System.Variants,
  System.TypInfo,
  System.Math,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections,
  Aurelius.Commands.Exceptions,
  unit_Item,
  unit_Project,
  unit_ActionType,
  unit_Equipment,
  unit_ValueType,
  unit_ValueSource,
  unit_ItemModel,
  unit_AuditHelper,
  unit_TimeHelper,
  unit_ConflictHandler,
  unit_SeriesMember,
  unit_SeriesFactor,
  unit_SeriesFixed,
  unit_HypothesisModel,
  unit_SignatureModel;

const
  MAX_TITLE = 255;
  MAX_DESCRIPTION = 255;
  MAX_REASON = 500;
  MAX_ENTRY_LABEL = 100;
  REL_EPS = 1e-9;
  ClosedText = 'The series is closed.';
  StatusNames: array[TSeriesStatus] of string = ('Draft', 'Active', 'Closed', 'Abandoned');


constructor TSeriesModel.Create(AManager: TObjectManager;
  const AAccess: IProjectAccessPolicy; AVia: TSeriesCreatedVia);
begin
  inherited Create;
  if AAccess = nil then
    raise EArgumentNilException.Create('Access');
  FManager := AManager;
  FAccess := AAccess;
  FVia := AVia;
end;

function PlannedDescription(const AEntryLabel, ANote: string): string;
begin
  if AEntryLabel <> '' then
    Result := AEntryLabel
  else
    Result := ANote;
end;

function ArrayHas(const AValues: TArray<Integer>; AValue: Integer): Boolean;
var
  V: Integer;
begin
  for V in AValues do
    if V = AValue then
      Exit(True);
  Result := False;
end;

function SameLevel(A, B: Double): Boolean;
begin
  Result := Abs(A - B) <= REL_EPS * Max(1.0, Max(Abs(A), Abs(B)));
end;

function SamePoint(const A, B: TSeriesPoint): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for I := 0 to High(A) do
      if not SameLevel(A[I], B[I]) then
        Exit(False);
end;

function InRange(const AFactor: TSeriesFactorRef; AValue: Double): Boolean;
begin
  Result := True;
  if AFactor.RangeMin.HasValue
    and (AValue < AFactor.RangeMin.Value - REL_EPS * Max(1.0, Abs(AFactor.RangeMin.Value))) then
    Result := False;
  if AFactor.RangeMax.HasValue
    and (AValue > AFactor.RangeMax.Value + REL_EPS * Max(1.0, Abs(AFactor.RangeMax.Value))) then
    Result := False;
end;

function LevelText(AValue: Double): string;
begin
  Result := FloatToStr(AValue, TFormatSettings.Invariant);
end;

function SameNullable(const A, B: Nullable<Double>): Boolean;
begin
  Result := (A.HasValue = B.HasValue) and (not A.HasValue or (A.Value = B.Value));
end;

function SamePlanShape(const A, B: TSeriesPlan): Boolean;
var
  I, J: Integer;
  Found: Boolean;
begin
  Result := (Length(A.Factors) = Length(B.Factors))
    and (Length(A.Fixed) = Length(B.Fixed))
    and (Length(A.Responses) = Length(B.Responses))
    and (A.TargetFolderId = B.TargetFolderId);
  if not Result then
    Exit;
  for I := 0 to High(A.Factors) do
    if (A.Factors[I].ValueTypeId <> B.Factors[I].ValueTypeId)
      or (A.Factors[I].EntryLabel <> B.Factors[I].EntryLabel)
      or not SameNullable(A.Factors[I].RangeMin, B.Factors[I].RangeMin)
      or not SameNullable(A.Factors[I].RangeMax, B.Factors[I].RangeMax) then
      Exit(False);
  for I := 0 to High(A.Fixed) do
  begin
    Found := False;
    for J := 0 to High(B.Fixed) do
      if (A.Fixed[I].ValueTypeId = B.Fixed[J].ValueTypeId)
        and (A.Fixed[I].EntryLabel = B.Fixed[J].EntryLabel)
        and (A.Fixed[I].Value = B.Fixed[J].Value)
        and (A.Fixed[I].Tol = B.Fixed[J].Tol) then
        Found := True;
    if not Found then
      Exit(False);
  end;
  for I := 0 to High(A.Responses) do
  begin
    Found := False;
    for J := 0 to High(B.Responses) do
      if (A.Responses[I].ValueTypeId = B.Responses[J].ValueTypeId)
        and (A.Responses[I].EntryLabel = B.Responses[J].EntryLabel) then
        Found := True;
    if not Found then
      Exit(False);
  end;
end;


procedure TSeriesModel.RequireRead(AUser: TUser; AProjectId: Integer);
begin
  if not FAccess.CanRead(FManager, AUser, AProjectId) then
    raise ESeriesAccess.Create('You cannot read that project.');
end;

procedure TSeriesModel.RequireWrite(AUser: TUser; AProjectId: Integer);
begin
  if not FAccess.CanWrite(FManager, AUser, AProjectId) then
    raise ESeriesAccess.Create('You do not have write access to this project.');
end;

procedure TSeriesModel.RequireOpen(S: TSeries);
begin
  if S.Status in [ssClosed, ssAbandoned] then
    raise ESeriesError.Create(ClosedText);
end;

procedure TSeriesModel.RequireActive(S: TSeries);
begin
  RequireOpen(S);
  if S.Status = ssDraft then
    raise ESeriesError.Create('Start the series first.');
end;

class function TSeriesModel.CleanTitle(const ATitle: string): string;
begin
  Result := Trim(ATitle);
  if (Result = '') or (Length(Result) > MAX_TITLE) then
    raise ESeriesError.CreateFmt('The title must be 1 to %d characters.', [MAX_TITLE]);
end;

function TSeriesModel.LoadSeries(AId: Integer): TSeries;
var
  WasCached: Boolean;
begin
  WasCached := FManager.IsCached<TSeries>(AId);
  Result := FManager.Find<TSeries>(AId);
  if Result = nil then
    raise ESeriesError.CreateFmt('Series %d not found.', [AId]);
  if WasCached then
    FManager.Refresh(Result);
end;

procedure TSeriesModel.Discard(AObj: TObject);
begin
  if AObj = nil then
    Exit;
  try
    FManager.Evict(AObj);
  except
  end;
  AObj.Free;
end;

procedure TSeriesModel.DiscardAudit(AType: TAuditEntityType; AId: Integer);
var
  Logs: TList<TAuditLog>;
  A: TAuditLog;
begin
  try
    Logs := FManager.Find<TAuditLog>
      .Where((Linq['EntityType'] = Ord(AType)) and (Linq['EntityId'] = AId)).List;
    try
      for A in Logs do
        Discard(A);
    finally
      Logs.Free;
    end;
  except
  end;
end;

procedure TSeriesModel.DiscardAll(AList: TList<TObject>);
var
  O: TObject;
begin
  for O in AList do
    Discard(O);
  AList.Clear;
end;

procedure TSeriesModel.Unwind(const ATrans: IDBTransaction; AError: Exception;
  S: TSeries);
begin
  try
    ATrans.Rollback;
  except
  end;
  TConflictHandler.ReloadConflicted(FManager, AError);
  if S <> nil then
    try
      FManager.Refresh(S);
    except
      try
        FManager.Evict(S);
        FManager.AddOwnership(S);
      except
      end;
    end;
  if AError is EVersionedConcurrencyControl then
    raise ESeriesError.Create('The series was changed by someone else. Reload and try again.');
end;

function TSeriesModel.MemberCounts(
  const AIds, AProjectIds: TArray<Integer>): TDictionary<Integer, Integer>;
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  ProjectOf, ItemProject: TDictionary<Integer, Integer>;
  Pairs: TList<TPair<Integer, Integer>>;
  ItemIds: TList<Integer>;
  P: TPair<Integer, Integer>;
  I, N, Proj: Integer;
  Done: Boolean;
begin
  Done := False;
  Result := TDictionary<Integer, Integer>.Create;
  ProjectOf := TDictionary<Integer, Integer>.Create;
  ItemProject := TDictionary<Integer, Integer>.Create;
  Pairs := TList<TPair<Integer, Integer>>.Create;
  ItemIds := TList<Integer>.Create;
  try
    for I := 0 to High(AIds) do
      ProjectOf.AddOrSetValue(AIds[I], AProjectIds[I]);
    for Chunk in IdChunks(AIds) do
    begin
      Rows := FManager.Find<TSeriesMember>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('SeriesId').As_('SeriesId'))
          .Add(TProjections.Prop('ItemId').As_('ItemId')))
        .Where(Linq['SeriesId']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
        begin
          Pairs.Add(TPair<Integer, Integer>.Create(
            Integer(Row.Values['SeriesId']), Integer(Row.Values['ItemId'])));
          ItemIds.Add(Integer(Row.Values['ItemId']));
        end;
      finally
        Rows.Free;
      end;
    end;
    for Chunk in IdChunks(ItemIds.ToArray) do
    begin
      Rows := FManager.Find<TItem>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('ProjectID').As_('ProjectId')))
        .Where(Linq['Id']._In(Chunk) and (Linq['IsDeleted'] = False))
        .ListValues;
      try
        for Row in Rows do
          ItemProject.AddOrSetValue(Integer(Row.Values['Id']),
            Integer(Row.Values['ProjectId']));
      finally
        Rows.Free;
      end;
    end;
    for P in Pairs do
      if ItemProject.TryGetValue(P.Value, Proj) and (Proj = ProjectOf[P.Key]) then
      begin
        Result.TryGetValue(P.Key, N);
        Result.AddOrSetValue(P.Key, N + 1);
      end;
    Done := True;
  finally
    ItemIds.Free;
    Pairs.Free;
    ItemProject.Free;
    ProjectOf.Free;
    if not Done then
      Result.Free;
  end;
end;

function TSeriesModel.Summarize(S: TSeries; ACount, APoints,
  AMeasured: Integer): TSeriesSummary;
begin
  Result.Id := S.Id;
  Result.ProjectId := S.ProjectId;
  Result.Title := S.Title;
  Result.Purpose := S.Purpose;
  Result.Status := S.Status;
  Result.MemberCount := ACount;
  Result.PointCount := APoints;
  Result.MeasuredCount := AMeasured;
  Result.CreatedBy := S.CreatedBy;
end;

function TSeriesModel.ListSeries(AUser: TUser;
  AProjectId: Integer): TArray<TSeriesSummary>;
var
  L: TList<TSeries>;
  Counts, Points, Measured: TDictionary<Integer, Integer>;
  Ids, Projs: TArray<Integer>;
  I, N, P, M: Integer;
begin
  RequireRead(AUser, AProjectId);
  L := FManager.Find<TSeries>
    .Where(Linq['ProjectId'] = AProjectId)
    .OrderBy('Id')
    .Refreshing
    .List;
  try
    SetLength(Ids, L.Count);
    SetLength(Projs, L.Count);
    for I := 0 to L.Count - 1 do
    begin
      Ids[I] := L[I].Id;
      Projs[I] := L[I].ProjectId;
    end;
    Counts := MemberCounts(Ids, Projs);
    Points := TDictionary<Integer, Integer>.Create;
    Measured := TDictionary<Integer, Integer>.Create;
    try
      SlotStats(AProjectId, Ids, Points, Measured);
      SetLength(Result, L.Count);
      for I := 0 to L.Count - 1 do
      begin
        if not Counts.TryGetValue(L[I].Id, N) then
          N := 0;
        if not Points.TryGetValue(L[I].Id, P) then
          P := 0;
        if not Measured.TryGetValue(L[I].Id, M) then
          M := 0;
        Result[I] := Summarize(L[I], N, P, M);
      end;
    finally
      Measured.Free;
      Points.Free;
      Counts.Free;
    end;
  finally
    L.Free;
  end;
end;

function TSeriesModel.Get(AUser: TUser; AId: Integer): TSeriesSummary;
var
  S: TSeries;
  Counts, Points, Measured: TDictionary<Integer, Integer>;
  N, P, M: Integer;
begin
  S := LoadSeries(AId);
  RequireRead(AUser, S.ProjectId);
  Counts := MemberCounts([AId], [S.ProjectId]);
  Points := TDictionary<Integer, Integer>.Create;
  Measured := TDictionary<Integer, Integer>.Create;
  try
    SlotStats(S.ProjectId, [AId], Points, Measured);
    if not Counts.TryGetValue(AId, N) then
      N := 0;
    if not Points.TryGetValue(AId, P) then
      P := 0;
    if not Measured.TryGetValue(AId, M) then
      M := 0;
  finally
    Measured.Free;
    Points.Free;
    Counts.Free;
  end;
  Result := Summarize(S, N, P, M);
end;

function TSeriesModel.ItemMemberships(AUser: TUser;
  AItemId: Integer): TArray<TSeriesMembership>;
var
  Members: TList<TSeriesMember>;
  Found: TList<TSeriesMembership>;
  M: TSeriesMember;
  S: TSeries;
  Row: TSeriesMembership;
  Factors: TArray<TSeriesFactorRef>;
  Slot: TSeriesSlotInfo;
begin
  Found := TList<TSeriesMembership>.Create;
  try
    Members := FManager.Find<TSeriesMember>
      .Where(Linq['ItemId'] = AItemId).OrderBy('Id').Refreshing.List;
    try
      for M in Members do
      begin
        S := LoadSeries(M.SeriesId);
        if not FAccess.CanRead(FManager, AUser, S.ProjectId) then
          Continue;
        Row.SeriesId := S.Id;
        Row.Title := S.Title;
        Row.Failed := M.AttemptState = satFailed;
        Row.Levels := '';
        if M.SlotId.HasValue then
        begin
          Factors := LoadFactors(S.Id);
          for Slot in ReadSlots(S.Id, Factors) do
            if Slot.SlotId = M.SlotId.Value then
              Row.Levels := PointText(Factors, Slot.Levels);
        end;
        Found.Add(Row);
      end;
    finally
      Members.Free;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TSeriesModel.FormatLevels(AUser: TUser; AId: Integer;
  const ALevels: TSeriesPoint): string;
var
  S: TSeries;
begin
  S := LoadSeries(AId);
  RequireRead(AUser, S.ProjectId);
  Result := PointText(LoadFactors(AId), ALevels);
end;

function TSeriesModel.ConfirmPlanned(AUser: TUser; AItemId: Integer): Integer;
var
  Item: TItem;
  Items: TItemModel;
begin
  Item := FManager.Find<TItem>(AItemId);
  if (Item = nil) or Item.IsDeleted then
    raise ESeriesError.CreateFmt('Item %d not found.', [AItemId]);
  RequireWrite(AUser, Item.ProjectID);
  if IsItemSignedCheck(FManager, AItemId) then
    raise ESeriesError.Create(
      'This deposition is signed. Its planned values cannot be confirmed.');
  Items := TItemModel.Create(FManager);
  try
    Result := Items.ConfirmPlannedValues(AUser.Id, AItemId);
  finally
    Items.Free;
  end;
end;

function TSeriesModel.CreateSeries(AUser: TUser; AProjectId: Integer;
  const ATitle, APurpose: string; const APlan: TSeriesPlan;
  const APoints: TArray<TSeriesPoint>): Integer;
var
  S: TSeries;
  Title: string;
  Trans: IDBTransaction;
  Fresh: TList<TObject>;
  Cols: TList<TSeriesColumn>;
  Factors: TArray<TSeriesFactorRef>;
  I: Integer;
begin
  Title := CleanTitle(ATitle);
  RequireWrite(AUser, AProjectId);
  ValidatePlan(APlan);
  CheckTargetFolder(AProjectId, APlan.TargetFolderId);
  Factors := FactorsOfPlan(APlan);
  if (Length(APoints) > 0) and (Length(Factors) = 0) then
    raise ESeriesError.Create('Add a factor before you add points.');
  CheckNewPoints(Factors, nil, APoints);
  Fresh := TList<TObject>.Create;
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := TSeries.Create;
      Fresh.Add(S);
      S.ProjectId := AProjectId;
      S.Title := Title;
      S.Purpose := APurpose;
      if FVia = scvMcp then
        S.Status := ssDraft
      else
        S.Status := ssActive;
      if APlan.TargetFolderId > 0 then
        S.TargetFolderId := APlan.TargetFolderId;
      S.CreatedBy := AUser.Id;
      S.CreatedDate := UTCNow;
      S.CreatedVia := FVia;
      FManager.Save(S);
      FManager.Flush;
      Result := S.Id;
      SyncFactors(Result, APlan, Fresh);
      SyncFixed(Result, APlan, Fresh);
      FManager.Flush;
      Factors := LoadFactors(Result);
      AddSlots(Result, AUser.Id, Factors, APoints, ssoPlanned, '', Fresh);
      Cols := FManager.Find<TSeriesColumn>
        .Where(Linq['SeriesId'] = Result).Refreshing.List;
      try
        for I := 0 to High(APlan.Responses) do
          UpsertColumn(Result, Cols, Fresh, TEST_RESULT,
            APlan.Responses[I].ValueTypeId, '', scrResponse,
            APlan.Responses[I].EntryLabel);
      finally
        Cols.Free;
      end;
      FManager.Flush;
      RecordAudit(FManager, aetSeries, Result, aoCreate, AUser.Id,
        Format('Created series "%s"', [Title]));
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        Unwind(Trans, E, nil);
        raise;
      end;
    end;
  finally
    Fresh.Free;
  end;
end;

procedure TSeriesModel.UpdateSeries(AUser: TUser; AId: Integer;
  const ATitle, APurpose: string);
var
  S: TSeries;
  Title: string;
  Trans: IDBTransaction;
begin
  Title := CleanTitle(ATitle);
  S := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    S := LoadSeries(AId);
    RequireWrite(AUser, S.ProjectId);
    S.Title := Title;
    S.Purpose := APurpose;
    S.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
      Format('Updated series "%s"', [Title]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Unwind(Trans, E, S);
      raise;
    end;
  end;
end;

procedure TSeriesModel.ChangeStatus(AUser: TUser; AId: Integer;
  ANew: TSeriesStatus);
var
  S: TSeries;
  Old: TSeriesStatus;
  Trans: IDBTransaction;
begin
  S := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    S := LoadSeries(AId);
    RequireWrite(AUser, S.ProjectId);
    Old := S.Status;
    if (Old in [ssActive, ssClosed]) and (ANew in [ssActive, ssClosed])
      and (AUser.Id <> S.CreatedBy) then
      raise ESeriesError.Create('Only the author can close or reopen the series.');
    if not (((Old = ssActive) and (ANew = ssClosed))
      or ((Old = ssClosed) and (ANew = ssActive))
      or ((Old = ssDraft) and (ANew = ssAbandoned))
      or ((Old = ssActive) and (ANew = ssAbandoned))) then
      raise ESeriesError.CreateFmt('A %s series cannot become %s.',
        [StatusNames[Old], StatusNames[ANew]]);
    S.Status := ANew;
    S.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
      Format('Status changed from %s to %s', [StatusNames[Old], StatusNames[ANew]]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Unwind(Trans, E, S);
      raise;
    end;
  end;
end;

procedure TSeriesModel.Unlink(AUser: TUser; AId, AItemId: Integer);
var
  S: TSeries;
  L: TList<TSeriesMember>;
  Trans: IDBTransaction;
begin
  S := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    S := LoadSeries(AId);
    RequireWrite(AUser, S.ProjectId);
    RequireOpen(S);
    L := FManager.Find<TSeriesMember>
      .Where((Linq['SeriesId'] = AId) and (Linq['ItemId'] = AItemId))
      .Refreshing.List;
    try
      if L.Count = 0 then
        raise ESeriesError.CreateFmt('Item %d is not in the series.', [AItemId]);
      FManager.Remove(L[0]);
    finally
      L.Free;
    end;
    S.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
      Format('Unlinked item %d', [AItemId]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Unwind(Trans, E, S);
      raise;
    end;
  end;
end;

procedure TSeriesModel.MarkFailed(AUser: TUser; AId, AItemId: Integer;
  const AReason: string);
var
  S: TSeries;
  L: TList<TSeriesMember>;
  Reason: string;
  Trans: IDBTransaction;
begin
  Reason := Trim(AReason);
  if Reason = '' then
    raise ESeriesError.Create('A reason is required.');
  if Length(Reason) > MAX_REASON then
    raise ESeriesError.CreateFmt('The reason must be at most %d characters.', [MAX_REASON]);
  S := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    S := LoadSeries(AId);
    RequireWrite(AUser, S.ProjectId);
    RequireOpen(S);
    L := FManager.Find<TSeriesMember>
      .Where((Linq['SeriesId'] = AId) and (Linq['ItemId'] = AItemId))
      .Refreshing.List;
    try
      if L.Count = 0 then
        raise ESeriesError.CreateFmt('Item %d is not in the series.', [AItemId]);
      if L[0].AttemptState = satFailed then
        raise ESeriesError.CreateFmt('Item %d is already marked as failed.', [AItemId]);
      L[0].AttemptState := satFailed;
      L[0].FailReason := Reason;
    finally
      L.Free;
    end;
    S.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
      Format('Marked item %d as failed: %s', [AItemId, Reason]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Unwind(Trans, E, S);
      raise;
    end;
  end;
end;

procedure TSeriesModel.SetColumnRole(AUser: TUser; AId: Integer;
  ARecType: TRecType; AValueTypeId: Integer; const ASourceKey: string;
  ARole: TSeriesColumnRole);
var
  S: TSeries;
  Cols: TList<TSeriesColumn>;
  C: TSeriesColumn;
  EntryLabel: string;
  Fresh: TList<TObject>;
  Trans: IDBTransaction;
begin
  S := nil;
  Fresh := TList<TObject>.Create;
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := LoadSeries(AId);
      RequireWrite(AUser, S.ProjectId);
      RequireOpen(S);
      Cols := FManager.Find<TSeriesColumn>
        .Where(Linq['SeriesId'] = AId).Refreshing.List;
      try
        EntryLabel := '';
        for C in Cols do
          if (C.RecType = ARecType) and (C.ValueTypeId = AValueTypeId)
            and (C.SourceKey = ASourceKey) then
            EntryLabel := C.EntryLabel;
        UpsertColumn(AId, Cols, Fresh, ARecType, AValueTypeId, ASourceKey, ARole,
          EntryLabel);
      finally
        Cols.Free;
      end;
      S.MarkModified(UTCNow);
      FManager.Flush;
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        Unwind(Trans, E, S);
        raise;
      end;
    end;
  finally
    Fresh.Free;
  end;
end;

procedure TSeriesModel.UpsertColumn(AId: Integer; ACols: TList<TSeriesColumn>;
  AFresh: TList<TObject>; ARecType: TRecType; AValueTypeId: Integer;
  const ASourceKey: string; ARole: TSeriesColumnRole; const AEntryLabel: string);
var
  C, Found: TSeriesColumn;
  Next: Integer;
begin
  Found := nil;
  Next := 0;
  for C in ACols do
  begin
    if (C.RecType = ARecType) and (C.ValueTypeId = AValueTypeId)
      and (C.SourceKey = ASourceKey) then
      Found := C;
    if C.SortOrder >= Next then
      Next := C.SortOrder + 1;
  end;
  if Found <> nil then
  begin
    Found.Role := ARole;
    Found.EntryLabel := AEntryLabel;
  end
  else
  begin
    Found := TSeriesColumn.Create;
    AFresh.Add(Found);
    Found.SeriesId := AId;
    Found.RecType := ARecType;
    Found.ValueTypeId := AValueTypeId;
    Found.SourceKey := ASourceKey;
    Found.Role := ARole;
    Found.SortOrder := Next;
    Found.EntryLabel := AEntryLabel;
    FManager.Save(Found);
    ACols.Add(Found);
  end;
end;

procedure TSeriesModel.LoadNodes(AProjectId: Integer;
  ANodes: TDictionary<Integer, TSeriesNode>;
  AChildren: TDictionary<Integer, TList<Integer>>);
var
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Node: TSeriesNode;
  List: TList<Integer>;
  Cur: Integer;
begin
  Rows := FManager.Find<TItem>
    .Select(TProjections.ProjectionList
      .Add(TProjections.Prop('Id').As_('Id'))
      .Add(TProjections.Prop('ParentID').As_('ParentId'))
      .Add(TProjections.Prop('Level').As_('Level')))
    .Where((Linq['ProjectID'] = AProjectId) and (Linq['IsDeleted'] = False))
    .ListValues;
  try
    for Row in Rows do
    begin
      Node.Parent := Integer(Row.Values['ParentId']);
      Node.Level := TItemLevel(Integer(Row.Values['Level']));
      Node.ActionTypeId := 0;
      ANodes.Add(Integer(Row.Values['Id']), Node);
    end;
  finally
    Rows.Free;
  end;

  Rows := FManager.Find<TItem>
    .CreateAlias('ActionType', 'at')
    .Select(TProjections.ProjectionList
      .Add(TProjections.Prop('Id').As_('Id'))
      .Add(TProjections.Prop('at.Id').As_('ActionTypeId')))
    .Where((Linq['ProjectID'] = AProjectId) and (Linq['IsDeleted'] = False))
    .ListValues;
  try
    for Row in Rows do
      if not VarIsNull(Row.Values['ActionTypeId'])
        and ANodes.TryGetValue(Integer(Row.Values['Id']), Node) then
      begin
        Node.ActionTypeId := Integer(Row.Values['ActionTypeId']);
        ANodes[Integer(Row.Values['Id'])] := Node;
      end;
  finally
    Rows.Free;
  end;

  for Cur in ANodes.Keys do
    if ANodes[Cur].Parent <> 0 then
    begin
      if not AChildren.TryGetValue(ANodes[Cur].Parent, List) then
      begin
        List := TList<Integer>.Create;
        AChildren.Add(ANodes[Cur].Parent, List);
      end;
      List.Add(Cur);
    end;
end;

function TSeriesModel.SubtreeValues(AProjectId: Integer;
  const ARoots, ATypeIds: TArray<Integer>): TArray<TSeriesSubtreeValue>;
var
  Nodes: TDictionary<Integer, TSeriesNode>;
  Children: TDictionary<Integer, TList<Integer>>;
  Owner: TDictionary<Integer, Integer>;
  ItemIds, Stack: TList<Integer>;
  Found: TList<TSeriesSubtreeValue>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Chunk: TArray<Variant>;
  List: TList<Integer>;
  V: TSeriesSubtreeValue;
  RootId, Cur, Child, ItemId: Integer;
begin
  Result := nil;
  if Length(ARoots) = 0 then
    Exit;
  Nodes := TDictionary<Integer, TSeriesNode>.Create;
  Children := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  Owner := TDictionary<Integer, Integer>.Create;
  ItemIds := TList<Integer>.Create;
  Stack := TList<Integer>.Create;
  Found := TList<TSeriesSubtreeValue>.Create;
  try
    LoadNodes(AProjectId, Nodes, Children);
    for RootId in ARoots do
      if Nodes.ContainsKey(RootId) and not Owner.ContainsKey(RootId) then
      begin
        Stack.Clear;
        Stack.Add(RootId);
        Owner.Add(RootId, RootId);
        while Stack.Count > 0 do
        begin
          Cur := Stack[Stack.Count - 1];
          Stack.Delete(Stack.Count - 1);
          ItemIds.Add(Cur);
          if Children.TryGetValue(Cur, List) then
            for Child in List do
              if not Owner.ContainsKey(Child) then
              begin
                Owner.Add(Child, RootId);
                Stack.Add(Child);
              end;
        end;
      end;

    for Chunk in IdChunks(ItemIds.ToArray) do
    begin
      Rows := FManager.Find<unit_Item.TValue>
        .CreateAlias('Item', 'i')
        .CreateAlias('ValueType', 'vt')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('i.Id').As_('ItemId'))
          .Add(TProjections.Prop('vt.Id').As_('TypeId'))
          .Add(TProjections.Prop('RecType').As_('RecType'))
          .Add(TProjections.Prop('Value').As_('V'))
          .Add(TProjections.Prop('Tol').As_('Tol'))
          .Add(TProjections.Prop('SourceKind').As_('SourceKind')))
        .Where(Linq['i.Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
        begin
          V.TypeId := Integer(Row.Values['TypeId']);
          if (Length(ATypeIds) > 0) and not ArrayHas(ATypeIds, V.TypeId) then
            Continue;
          ItemId := Integer(Row.Values['ItemId']);
          V.Root := Owner[ItemId];
          V.RecType := TRecType(Integer(Row.Values['RecType']));
          V.Value := Double(Row.Values['V']);
          if VarIsNull(Row.Values['Tol']) then
            V.Tol := 0
          else
            V.Tol := Double(Row.Values['Tol']);
          V.Planned := not VarIsNull(Row.Values['SourceKind'])
            and (Integer(Row.Values['SourceKind']) = Ord(vskPlanned));
          if ItemId = V.Root then
            V.Key := SERIES_ROOT_KEY
          else if Nodes[ItemId].ActionTypeId <> 0 then
            V.Key := SeriesActionTypeKey(Nodes[ItemId].ActionTypeId)
          else
            V.Key := SeriesLevelKey(Nodes[ItemId].Level);
          Found.Add(V);
        end;
      finally
        Rows.Free;
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
    Stack.Free;
    ItemIds.Free;
    Owner.Free;
    Children.Free;
    Nodes.Free;
  end;
end;

procedure TSeriesModel.SlotStats(AProjectId: Integer; const AIds: TArray<Integer>;
  APoints, AMeasured: TDictionary<Integer, Integer>);
var
  SlotSeries, SlotRoot: TDictionary<Integer, Integer>;
  Responses: TDictionary<Integer, TList<TSeriesColumnPref>>;
  Present: TDictionary<string, Boolean>;
  Roots: TList<Integer>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Cols: TList<TSeriesColumn>;
  Members: TList<TSeriesMember>;
  Chunk: TArray<Variant>;
  C: TSeriesColumn;
  M: TSeriesMember;
  Pref: TSeriesColumnPref;
  Prefs: TList<TSeriesColumnPref>;
  V: TSeriesSubtreeValue;
  Pair: TPair<Integer, Integer>;
  SeriesId, N: Integer;
  Nodes: TDictionary<Integer, TSeriesNode>;
  Children: TDictionary<Integer, TList<Integer>>;
  AllPresent: Boolean;
  Key: string;
begin
  SlotSeries := TDictionary<Integer, Integer>.Create;
  SlotRoot := TDictionary<Integer, Integer>.Create;
  Responses := TObjectDictionary<Integer, TList<TSeriesColumnPref>>.Create([doOwnsValues]);
  Present := TDictionary<string, Boolean>.Create;
  Roots := TList<Integer>.Create;
  try
    for Chunk in IdChunks(AIds) do
    begin
      Rows := FManager.Find<TSeriesSlot>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('SeriesId').As_('SeriesId'))
          .Add(TProjections.Prop('Id').As_('Id')))
        .Where(Linq['SeriesId']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
        begin
          SeriesId := Integer(Row.Values['SeriesId']);
          SlotSeries.Add(Integer(Row.Values['Id']), SeriesId);
          APoints.TryGetValue(SeriesId, N);
          APoints.AddOrSetValue(SeriesId, N + 1);
        end;
      finally
        Rows.Free;
      end;
    end;
    if SlotSeries.Count = 0 then
      Exit;

    for Chunk in IdChunks(AIds) do
    begin
      Cols := FManager.Find<TSeriesColumn>
        .Where(Linq['SeriesId']._In(Chunk)).Refreshing.List;
      try
        for C in Cols do
          if C.Role = scrResponse then
          begin
            if not Responses.TryGetValue(C.SeriesId, Prefs) then
            begin
              Prefs := TList<TSeriesColumnPref>.Create;
              Responses.Add(C.SeriesId, Prefs);
            end;
            Pref.RecType := C.RecType;
            Pref.ValueTypeId := C.ValueTypeId;
            Pref.SourceKey := C.SourceKey;
            Pref.Role := C.Role;
            Pref.SortOrder := C.SortOrder;
            Prefs.Add(Pref);
          end;
      finally
        Cols.Free;
      end;
    end;
    for Chunk in IdChunks(AIds) do
    begin
      Members := FManager.Find<TSeriesMember>
        .Where(Linq['SeriesId']._In(Chunk)).Refreshing.List;
      try
        for M in Members do
          if (M.AttemptState = satValid) and M.SlotId.HasValue
            and SlotSeries.ContainsKey(M.SlotId.Value) then
          begin
            SlotRoot.AddOrSetValue(M.SlotId.Value, M.ItemId);
            Roots.Add(M.ItemId);
          end;
      finally
        Members.Free;
      end;
    end;
    if Roots.Count = 0 then
      Exit;

    for V in SubtreeValues(AProjectId, Roots.ToArray, nil) do
      if not V.Planned then
      begin
        Present.AddOrSetValue(Format('%d|%d|%d|%s',
          [V.Root, Ord(V.RecType), V.TypeId, V.Key]), True);
        Present.AddOrSetValue(Format('%d|%d|%d|*',
          [V.Root, Ord(V.RecType), V.TypeId]), True);
      end;

    Nodes := TDictionary<Integer, TSeriesNode>.Create;
    Children := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
    try
      LoadNodes(AProjectId, Nodes, Children);
      for Pair in SlotRoot do
      begin
        if not Nodes.ContainsKey(Pair.Value) then
          Continue;
        SeriesId := SlotSeries[Pair.Key];
        AllPresent := True;
        if Responses.TryGetValue(SeriesId, Prefs) then
          for Pref in Prefs do
          begin
            if Pref.SourceKey = '' then
              Key := '*'
            else
              Key := Pref.SourceKey;
            if not Present.ContainsKey(Format('%d|%d|%d|%s',
              [Pair.Value, Ord(Pref.RecType), Pref.ValueTypeId, Key])) then
              AllPresent := False;
          end;
        if AllPresent then
        begin
          AMeasured.TryGetValue(SeriesId, N);
          AMeasured.AddOrSetValue(SeriesId, N + 1);
        end;
      end;
    finally
      Children.Free;
      Nodes.Free;
    end;
  finally
    Roots.Free;
    Present.Free;
    Responses.Free;
    SlotRoot.Free;
    SlotSeries.Free;
  end;
end;

function TSeriesModel.LoadItemFacts(
  const AIds: TArray<Integer>): TDictionary<Integer, TSeriesItemFacts>;
var
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Chunk: TArray<Variant>;
  Facts: TSeriesItemFacts;
  Done: Boolean;
begin
  Done := False;
  Result := TDictionary<Integer, TSeriesItemFacts>.Create;
  try
    for Chunk in IdChunks(AIds) do
    begin
      Rows := FManager.Find<TItem>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('ParentID').As_('ParentId'))
          .Add(TProjections.Prop('ProjectID').As_('ProjectId'))
          .Add(TProjections.Prop('Level').As_('Level'))
          .Add(TProjections.Prop('IsDeleted').As_('IsDeleted')))
        .Where(Linq['Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
        begin
          Facts.ProjectId := Integer(Row.Values['ProjectId']);
          Facts.Parent := Integer(Row.Values['ParentId']);
          Facts.Level := Integer(Row.Values['Level']);
          Facts.IsDeleted := Boolean(Row.Values['IsDeleted']);
          Result.AddOrSetValue(Integer(Row.Values['Id']), Facts);
        end;
      finally
        Rows.Free;
      end;
    end;
    Done := True;
  finally
    if not Done then
      Result.Free;
  end;
end;

procedure TSeriesModel.CheckLinkable(S: TSeries; AItemId: Integer);
var
  Facts: TDictionary<Integer, TSeriesItemFacts>;
  F: TSeriesItemFacts;
begin
  Facts := LoadItemFacts([AItemId]);
  try
    if not Facts.TryGetValue(AItemId, F) then
      raise ESeriesError.CreateFmt('Item %d not found.', [AItemId]);
    if F.IsDeleted then
      raise ESeriesError.CreateFmt('Item %d is deleted.', [AItemId]);
    if F.ProjectId <> S.ProjectId then
      raise ESeriesError.CreateFmt('Item %d belongs to another project.', [AItemId]);
    if F.Parent <> 0 then
      raise ESeriesError.CreateFmt(
        'Item %d is not a top-level item; link the deposition item.', [AItemId]);
    if F.Level = Ord(TItemLevel.Folder) then
      raise ESeriesError.CreateFmt('Item %d is a folder.', [AItemId]);
  finally
    Facts.Free;
  end;
end;

function TSeriesModel.LoadFactors(AId: Integer): TArray<TSeriesFactorRef>;
var
  L: TList<TSeriesFactor>;
  I: Integer;
begin
  L := FManager.Find<TSeriesFactor>
    .Where(Linq['SeriesId'] = AId).OrderBy('SortOrder').Refreshing.List;
  try
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do
    begin
      Result[I].Id := L[I].Id;
      Result[I].ValueTypeId := L[I].ValueTypeId;
      Result[I].RangeMin := L[I].RangeMin;
      Result[I].RangeMax := L[I].RangeMax;
      Result[I].EntryLabel := L[I].EntryLabel;
    end;
  finally
    L.Free;
  end;
end;

function TSeriesModel.FactorsOfPlan(const APlan: TSeriesPlan): TArray<TSeriesFactorRef>;
var
  I: Integer;
begin
  SetLength(Result, Length(APlan.Factors));
  for I := 0 to High(APlan.Factors) do
  begin
    Result[I].Id := 0;
    Result[I].ValueTypeId := APlan.Factors[I].ValueTypeId;
    Result[I].RangeMin := APlan.Factors[I].RangeMin;
    Result[I].RangeMax := APlan.Factors[I].RangeMax;
    Result[I].EntryLabel := APlan.Factors[I].EntryLabel;
  end;
end;

function TSeriesModel.ReadSlots(AId: Integer;
  const AFactors: TArray<TSeriesFactorRef>): TArray<TSeriesSlotInfo>;
var
  Slots: TList<TSeriesSlot>;
  Levels: TList<TSeriesSlotLevel>;
  Members: TList<TSeriesMember>;
  Index, FactorPos: TDictionary<Integer, Integer>;
  Ids: TArray<Integer>;
  Chunk: TArray<Variant>;
  L: TSeriesSlotLevel;
  M: TSeriesMember;
  I, At, Pos: Integer;
begin
  Index := TDictionary<Integer, Integer>.Create;
  FactorPos := TDictionary<Integer, Integer>.Create;
  try
    for I := 0 to High(AFactors) do
      FactorPos.Add(AFactors[I].Id, I);
    Slots := FManager.Find<TSeriesSlot>
      .Where(Linq['SeriesId'] = AId).OrderBy('Id').Refreshing.List;
    try
      SetLength(Result, Slots.Count);
      SetLength(Ids, Slots.Count);
      for I := 0 to Slots.Count - 1 do
      begin
        Result[I].SlotId := Slots[I].Id;
        Result[I].Origin := Slots[I].Origin;
        Result[I].ValidItemId := 0;
        Result[I].Levels := nil;
        SetLength(Result[I].Levels, Length(AFactors));
        Index.Add(Slots[I].Id, I);
        Ids[I] := Slots[I].Id;
      end;
    finally
      Slots.Free;
    end;
    for Chunk in IdChunks(Ids) do
    begin
      Levels := FManager.Find<TSeriesSlotLevel>
        .Where(Linq['SlotId']._In(Chunk)).Refreshing.List;
      try
        for L in Levels do
          if Index.TryGetValue(L.SlotId, At)
            and FactorPos.TryGetValue(L.FactorId, Pos) then
            Result[At].Levels[Pos] := L.LevelValue;
      finally
        Levels.Free;
      end;
    end;
    if Length(Ids) > 0 then
    begin
      Members := FManager.Find<TSeriesMember>
        .Where(Linq['SeriesId'] = AId).OrderBy('Id').Refreshing.List;
      try
        for M in Members do
          if (M.AttemptState = satValid) and M.SlotId.HasValue
            and Index.TryGetValue(M.SlotId.Value, At) then
            Result[At].ValidItemId := M.ItemId;
      finally
        Members.Free;
      end;
    end;
  finally
    FactorPos.Free;
    Index.Free;
  end;
end;

function TSeriesModel.FindSlot(const ASlots: TArray<TSeriesSlotInfo>;
  ASlotId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ASlots) do
    if ASlots[I].SlotId = ASlotId then
      Exit(I);
  raise ESeriesError.CreateFmt('Point %d is not in this series.', [ASlotId]);
end;

function TSeriesModel.PointText(const AFactors: TArray<TSeriesFactorRef>;
  const ALevels: TSeriesPoint): string;
var
  I: Integer;
  T: TValueType;
  Part: string;
begin
  Result := '';
  for I := 0 to High(ALevels) do
  begin
    Part := LevelText(ALevels[I]);
    if I <= High(AFactors) then
    begin
      T := FManager.Find<TValueType>(AFactors[I].ValueTypeId);
      if (T <> nil) and (T.Units <> '') then
        Part := Part + ' ' + T.Units;
    end;
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Part;
  end;
end;

procedure TSeriesModel.RequireValueType(AId: Integer);
begin
  if FManager.Find<TValueType>(AId) = nil then
    raise ESeriesError.CreateFmt('Value type %d not found.', [AId]);
end;

procedure TSeriesModel.ValidatePlan(const APlan: TSeriesPlan);
var
  Seen, SeenResponses: TList<Integer>;
  F: TSeriesFactorSpec;
  X: TSeriesFixedSpec;
  R: TSeriesResponseSpec;

  procedure CheckEntryLabel(const AEntryLabel: string);
  begin
    if Length(AEntryLabel) > MAX_ENTRY_LABEL then
      raise ESeriesError.CreateFmt('A label must be at most %d characters.',
        [MAX_ENTRY_LABEL]);
  end;

begin
  Seen := TList<Integer>.Create;
  SeenResponses := TList<Integer>.Create;
  try
    for F in APlan.Factors do
    begin
      RequireValueType(F.ValueTypeId);
      CheckEntryLabel(F.EntryLabel);
      if Seen.Contains(F.ValueTypeId) then
        raise ESeriesError.Create('A value type can be used only once in the plan.');
      Seen.Add(F.ValueTypeId);
      if F.RangeMin.HasValue and (IsNan(F.RangeMin.Value) or IsInfinite(F.RangeMin.Value)) then
        raise ESeriesError.Create('A range limit must be a finite number.');
      if F.RangeMax.HasValue and (IsNan(F.RangeMax.Value) or IsInfinite(F.RangeMax.Value)) then
        raise ESeriesError.Create('A range limit must be a finite number.');
      if F.RangeMin.HasValue and F.RangeMax.HasValue
        and (F.RangeMin.Value > F.RangeMax.Value) then
        raise ESeriesError.Create('The range minimum is above the maximum.');
    end;
    for X in APlan.Fixed do
    begin
      RequireValueType(X.ValueTypeId);
      CheckEntryLabel(X.EntryLabel);
      if Seen.Contains(X.ValueTypeId) then
        raise ESeriesError.Create('A value type can be used only once in the plan.');
      Seen.Add(X.ValueTypeId);
      if IsNan(X.Value) or IsInfinite(X.Value) then
        raise ESeriesError.Create('A fixed value must be a finite number.');
      if IsNan(X.Tol) or IsInfinite(X.Tol) or (X.Tol < 0) then
        raise ESeriesError.Create('A tolerance must be a finite number of at least 0.');
    end;
    for R in APlan.Responses do
    begin
      RequireValueType(R.ValueTypeId);
      CheckEntryLabel(R.EntryLabel);
      if SeenResponses.Contains(R.ValueTypeId) then
        raise ESeriesError.Create('A response can be used only once in the plan.');
      SeenResponses.Add(R.ValueTypeId);
    end;
    if APlan.TargetFolderId < 0 then
      raise ESeriesError.Create('The target folder is not valid.');
  finally
    SeenResponses.Free;
    Seen.Free;
  end;
end;

procedure TSeriesModel.CheckTargetFolder(AProjectId, AFolderId: Integer);
var
  Project: TProject;
begin
  if AFolderId <= 0 then
    Exit;
  Project := FManager.Find<TProject>(AProjectId);
  if (Project = nil) or (Project.GetFolder(AFolderId) = nil) then
    raise ESeriesError.CreateFmt('Folder %d not found in this project.', [AFolderId]);
end;

procedure TSeriesModel.RaiseSlotTaken(S: TSeries; AItemId: Integer);
var
  Item: TItem;
begin
  Item := FManager.Find<TItem>(AItemId);
  if (Item = nil) or Item.IsDeleted or (Item.ProjectID <> S.ProjectId) then
    raise ESeriesError.Create('This point has a deposition that is in the recycle bin ' +
      'or another project. Use Unlink excluded to free the point.');
  raise ESeriesError.Create('This point already has a deposition.');
end;

procedure TSeriesModel.CheckNewPoints(const AFactors: TArray<TSeriesFactorRef>;
  const AExisting: TArray<TSeriesSlotInfo>; const APoints: TArray<TSeriesPoint>);
var
  I, K, J: Integer;
begin
  for I := 0 to High(APoints) do
  begin
    if Length(APoints[I]) <> Length(AFactors) then
      raise ESeriesError.CreateFmt(
        'A point needs %d level(s), one for each factor.', [Length(AFactors)]);
    for K := 0 to High(AFactors) do
    begin
      if IsNan(APoints[I][K]) or IsInfinite(APoints[I][K]) then
        raise ESeriesError.Create('A level must be a finite number.');
      if not InRange(AFactors[K], APoints[I][K]) then
        raise ESeriesError.CreateFmt('Point %s is outside the range.',
          [PointText(AFactors, APoints[I])]);
    end;
    for J := 0 to High(AExisting) do
      if SamePoint(AExisting[J].Levels, APoints[I]) then
        raise ESeriesError.CreateFmt('Point %s already exists.',
          [PointText(AFactors, APoints[I])]);
    for J := 0 to I - 1 do
      if SamePoint(APoints[J], APoints[I]) then
        raise ESeriesError.CreateFmt('Point %s is listed twice.',
          [PointText(AFactors, APoints[I])]);
  end;
end;

function TSeriesModel.AddSlots(AId, AUserId: Integer;
  const AFactors: TArray<TSeriesFactorRef>; const APoints: TArray<TSeriesPoint>;
  AOrigin: TSeriesSlotOrigin; const AReason: string;
  AFresh: TList<TObject>): TArray<Integer>;
var
  Slot: TSeriesSlot;
  Level: TSeriesSlotLevel;
  Now: TDateTime;
  I, K: Integer;
begin
  SetLength(Result, Length(APoints));
  Now := UTCNow;
  for I := 0 to High(APoints) do
  begin
    Slot := TSeriesSlot.Create;
    AFresh.Add(Slot);
    Slot.SeriesId := AId;
    Slot.Origin := AOrigin;
    Slot.AddedBy := AUserId;
    Slot.AddedDate := Now;
    Slot.Reason := AReason;
    FManager.Save(Slot);
    FManager.Flush;
    Result[I] := Slot.Id;
    for K := 0 to High(AFactors) do
    begin
      Level := TSeriesSlotLevel.Create;
      AFresh.Add(Level);
      Level.SlotId := Slot.Id;
      Level.FactorId := AFactors[K].Id;
      Level.LevelValue := APoints[I][K];
      FManager.Save(Level);
    end;
  end;
end;

procedure TSeriesModel.SyncFactors(AId: Integer; const APlan: TSeriesPlan;
  AFresh: TList<TObject>);
var
  Old: TList<TSeriesFactor>;
  F: TSeriesFactor;
  Done: TArray<Boolean>;
  I: Integer;
begin
  SetLength(Done, Length(APlan.Factors));
  Old := FManager.Find<TSeriesFactor>
    .Where(Linq['SeriesId'] = AId).Refreshing.List;
  try
    for F in Old do
    begin
      I := 0;
      while (I <= High(APlan.Factors))
        and (APlan.Factors[I].ValueTypeId <> F.ValueTypeId) do
        Inc(I);
      if I > High(APlan.Factors) then
        FManager.Remove(F)
      else
      begin
        F.SortOrder := I;
        F.RangeMin := APlan.Factors[I].RangeMin;
        F.RangeMax := APlan.Factors[I].RangeMax;
        F.EntryLabel := APlan.Factors[I].EntryLabel;
        Done[I] := True;
      end;
    end;
  finally
    Old.Free;
  end;
  for I := 0 to High(APlan.Factors) do
    if not Done[I] then
    begin
      F := TSeriesFactor.Create;
      AFresh.Add(F);
      F.SeriesId := AId;
      F.ValueTypeId := APlan.Factors[I].ValueTypeId;
      F.RangeMin := APlan.Factors[I].RangeMin;
      F.RangeMax := APlan.Factors[I].RangeMax;
      F.EntryLabel := APlan.Factors[I].EntryLabel;
      F.SortOrder := I;
      FManager.Save(F);
    end;
end;

procedure TSeriesModel.SyncFixed(AId: Integer; const APlan: TSeriesPlan;
  AFresh: TList<TObject>);
var
  Old: TList<TSeriesFixed>;
  X: TSeriesFixed;
  Done: TArray<Boolean>;
  I: Integer;
begin
  SetLength(Done, Length(APlan.Fixed));
  Old := FManager.Find<TSeriesFixed>
    .Where(Linq['SeriesId'] = AId).Refreshing.List;
  try
    for X in Old do
    begin
      I := 0;
      while (I <= High(APlan.Fixed))
        and (APlan.Fixed[I].ValueTypeId <> X.ValueTypeId) do
        Inc(I);
      if I > High(APlan.Fixed) then
        FManager.Remove(X)
      else
      begin
        X.FixedValue := APlan.Fixed[I].Value;
        X.Tol := APlan.Fixed[I].Tol;
        X.EntryLabel := APlan.Fixed[I].EntryLabel;
        Done[I] := True;
      end;
    end;
  finally
    Old.Free;
  end;
  for I := 0 to High(APlan.Fixed) do
    if not Done[I] then
    begin
      X := TSeriesFixed.Create;
      AFresh.Add(X);
      X.SeriesId := AId;
      X.ValueTypeId := APlan.Fixed[I].ValueTypeId;
      X.FixedValue := APlan.Fixed[I].Value;
      X.Tol := APlan.Fixed[I].Tol;
      X.EntryLabel := APlan.Fixed[I].EntryLabel;
      FManager.Save(X);
    end;
end;

procedure TSeriesModel.NewMember(AId, AItemId, ASlotId, AUserId: Integer;
  AFresh: TList<TObject>);
var
  M: TSeriesMember;
begin
  M := TSeriesMember.Create;
  AFresh.Add(M);
  M.SeriesId := AId;
  M.ItemId := AItemId;
  M.SlotId := ASlotId;
  M.AttemptState := satValid;
  M.AddedBy := AUserId;
  M.AddedDate := UTCNow;
  FManager.Save(M);
end;

function TSeriesModel.GetPlan(AUser: TUser; AId: Integer): TSeriesPlanInfo;
var
  S: TSeries;
  Factors: TArray<TSeriesFactorRef>;
  Fixed: TList<TSeriesFixed>;
  Cols: TList<TSeriesColumn>;
  Responses: TList<TSeriesResponseSpec>;
  Response: TSeriesResponseSpec;
  C: TSeriesColumn;
  I: Integer;

  function HasResponse(AValueTypeId: Integer): Boolean;
  var
    R: TSeriesResponseSpec;
  begin
    for R in Responses do
      if R.ValueTypeId = AValueTypeId then
        Exit(True);
    Result := False;
  end;

begin
  S := LoadSeries(AId);
  RequireRead(AUser, S.ProjectId);
  Result := Default(TSeriesPlanInfo);
  Factors := LoadFactors(AId);
  SetLength(Result.Plan.Factors, Length(Factors));
  for I := 0 to High(Factors) do
  begin
    Result.Plan.Factors[I].ValueTypeId := Factors[I].ValueTypeId;
    Result.Plan.Factors[I].RangeMin := Factors[I].RangeMin;
    Result.Plan.Factors[I].RangeMax := Factors[I].RangeMax;
    Result.Plan.Factors[I].EntryLabel := Factors[I].EntryLabel;
  end;
  Fixed := FManager.Find<TSeriesFixed>
    .Where(Linq['SeriesId'] = AId).OrderBy('Id').Refreshing.List;
  try
    SetLength(Result.Plan.Fixed, Fixed.Count);
    for I := 0 to Fixed.Count - 1 do
    begin
      Result.Plan.Fixed[I].ValueTypeId := Fixed[I].ValueTypeId;
      Result.Plan.Fixed[I].Value := Fixed[I].FixedValue;
      Result.Plan.Fixed[I].Tol := Fixed[I].Tol;
      Result.Plan.Fixed[I].EntryLabel := Fixed[I].EntryLabel;
    end;
  finally
    Fixed.Free;
  end;
  Responses := TList<TSeriesResponseSpec>.Create;
  try
    Cols := FManager.Find<TSeriesColumn>
      .Where(Linq['SeriesId'] = AId).OrderBy('SortOrder').Refreshing.List;
    try
      for C in Cols do
        if (C.Role = scrResponse) and (C.RecType = TEST_RESULT)
          and not HasResponse(C.ValueTypeId) then
        begin
          Response.ValueTypeId := C.ValueTypeId;
          Response.EntryLabel := C.EntryLabel;
          Responses.Add(Response);
        end;
    finally
      Cols.Free;
    end;
    Result.Plan.Responses := Responses.ToArray;
  finally
    Responses.Free;
  end;
  if S.TargetFolderId.HasValue then
    Result.Plan.TargetFolderId := S.TargetFolderId.Value
  else
    Result.Plan.TargetFolderId := 0;
  Result.Slots := ReadSlots(AId, Factors);
end;

procedure TSeriesModel.CheckPlanAgainstPoints(AId: Integer;
  const AWanted: TArray<TSeriesFactorRef>);
var
  Old: TArray<TSeriesFactorRef>;
  Slots: TArray<TSeriesSlotInfo>;
  Slot: TSeriesSlotInfo;
  K: Integer;
begin
  Old := LoadFactors(AId);
  Slots := ReadSlots(AId, Old);
  if Length(Slots) = 0 then
    Exit;
  if Length(Old) <> Length(AWanted) then
    raise ESeriesError.Create('Remove all points before you change the factors.');
  for K := 0 to High(Old) do
    if Old[K].ValueTypeId <> AWanted[K].ValueTypeId then
      raise ESeriesError.Create('Remove all points before you change the factors.');
  for Slot in Slots do
    for K := 0 to High(Old) do
      if not InRange(AWanted[K], Slot.Levels[K]) then
        raise ESeriesError.CreateFmt('Point %s is outside the new range.',
          [PointText(Old, Slot.Levels)]);
end;

procedure TSeriesModel.ApplyPlan(S: TSeries; const APlan: TSeriesPlan;
  AFresh: TList<TObject>);
var
  Cols: TList<TSeriesColumn>;
  C: TSeriesColumn;
  R: TSeriesResponseSpec;
  Kept: Boolean;
begin
  SyncFactors(S.Id, APlan, AFresh);
  SyncFixed(S.Id, APlan, AFresh);
  Cols := FManager.Find<TSeriesColumn>
    .Where(Linq['SeriesId'] = S.Id).Refreshing.List;
  try
    for R in APlan.Responses do
      UpsertColumn(S.Id, Cols, AFresh, TEST_RESULT, R.ValueTypeId, '',
        scrResponse, R.EntryLabel);
    for C in Cols do
      if (C.Role = scrResponse) and (C.RecType = TEST_RESULT) then
      begin
        Kept := False;
        for R in APlan.Responses do
          if R.ValueTypeId = C.ValueTypeId then
            Kept := True;
        if not Kept then
        begin
          C.Role := scrShown;
          C.EntryLabel := '';
        end;
      end;
  finally
    Cols.Free;
  end;
  if APlan.TargetFolderId > 0 then
    S.TargetFolderId := APlan.TargetFolderId
  else
    S.TargetFolderId := SNull;
end;

procedure TSeriesModel.SavePlan(AUser: TUser; AId: Integer; const APlan: TSeriesPlan);
var
  S: TSeries;
  Trans: IDBTransaction;
  Fresh: TList<TObject>;
  Wanted: TArray<TSeriesFactorRef>;
begin
  ValidatePlan(APlan);
  Wanted := FactorsOfPlan(APlan);
  S := nil;
  Fresh := TList<TObject>.Create;
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := LoadSeries(AId);
      RequireWrite(AUser, S.ProjectId);
      RequireOpen(S);
      CheckTargetFolder(S.ProjectId, APlan.TargetFolderId);
      CheckPlanAgainstPoints(AId, Wanted);
      ApplyPlan(S, APlan, Fresh);
      S.MarkModified(UTCNow);
      FManager.Flush;
      RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
        Format('Saved the plan of series "%s"', [S.Title]));
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        Unwind(Trans, E, S);
        raise;
      end;
    end;
  finally
    Fresh.Free;
  end;
end;

function TSeriesModel.ApplyPoints(S: TSeries; AUserId: Integer;
  const APoints: TArray<TSeriesPoint>; const AReason: string;
  ASkipExisting: Boolean; AFresh: TList<TObject>;
  out AAdded: Integer): TArray<Integer>;
var
  Factors: TArray<TSeriesFactorRef>;
  Existing: TArray<TSeriesSlotInfo>;
  Todo: TList<TSeriesPoint>;
  Origin: TSeriesSlotOrigin;
  I, J: Integer;
  Known: Boolean;
begin
  Result := nil;
  AAdded := 0;
  Todo := TList<TSeriesPoint>.Create;
  try
    Factors := LoadFactors(S.Id);
    Existing := ReadSlots(S.Id, Factors);
    if (Length(APoints) > 0) and (Length(Factors) = 0) then
      raise ESeriesError.Create('Add a factor before you add points.');
    for I := 0 to High(APoints) do
    begin
      Known := False;
      if ASkipExisting then
      begin
        for J := 0 to High(Existing) do
          if SamePoint(Existing[J].Levels, APoints[I]) then
            Known := True;
        for J := 0 to Todo.Count - 1 do
          if SamePoint(Todo[J], APoints[I]) then
            Known := True;
      end;
      if not Known then
        Todo.Add(APoints[I]);
    end;
    CheckNewPoints(Factors, Existing, Todo.ToArray);
    if Todo.Count > 0 then
    begin
      if S.Status = ssDraft then
        Origin := ssoPlanned
      else
        Origin := ssoAdded;
      Result := AddSlots(S.Id, AUserId, Factors, Todo.ToArray, Origin, AReason, AFresh);
      AAdded := Todo.Count;
    end;
  finally
    Todo.Free;
  end;
end;

function TSeriesModel.InsertPoints(AUser: TUser; AId: Integer;
  const APoints: TArray<TSeriesPoint>; const AReason: string;
  ASkipExisting: Boolean): TArray<Integer>;
var
  S: TSeries;
  Trans: IDBTransaction;
  Fresh: TList<TObject>;
  Added: Integer;
begin
  if Length(AReason) > MAX_REASON then
    raise ESeriesError.CreateFmt('The reason must be at most %d characters.', [MAX_REASON]);
  Result := nil;
  S := nil;
  Fresh := TList<TObject>.Create;
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := LoadSeries(AId);
      RequireWrite(AUser, S.ProjectId);
      RequireOpen(S);
      Result := ApplyPoints(S, AUser.Id, APoints, AReason, ASkipExisting, Fresh, Added);
      if Added > 0 then
      begin
        S.MarkModified(UTCNow);
        FManager.Flush;
        RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
          Format('Added %d point(s)', [Added]));
      end;
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        Unwind(Trans, E, S);
        raise;
      end;
    end;
  finally
    Fresh.Free;
  end;
end;

function TSeriesModel.UpdatePlanAndPoints(AUser: TUser; AId: Integer;
  AChangePurpose: Boolean; const APurpose: string; AChangePlan: Boolean;
  const APlan: TSeriesPlan; const APoints: TArray<TSeriesPoint>;
  const AReason: string): TArray<Integer>;
var
  S: TSeries;
  Trans: IDBTransaction;
  Fresh: TList<TObject>;
  Wanted: TArray<TSeriesFactorRef>;
  Added: Integer;
  Changed: Boolean;
begin
  if Length(AReason) > MAX_REASON then
    raise ESeriesError.CreateFmt('The reason must be at most %d characters.', [MAX_REASON]);
  if AChangePlan then
    ValidatePlan(APlan);
  Result := nil;
  S := nil;
  Fresh := TList<TObject>.Create;
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := LoadSeries(AId);
      RequireWrite(AUser, S.ProjectId);
      RequireOpen(S);
      if AChangePlan and (FVia = scvMcp) and (S.Status = ssActive) then
      begin
        if not SamePlanShape(GetPlan(AUser, AId).Plan, APlan) then
          raise ESeriesError.Create('An active series plan is changed in the desktop. ' +
            'MCP can only add points to it.');
        AChangePlan := False;
      end;
      if AChangePlan then
      begin
        CheckTargetFolder(S.ProjectId, APlan.TargetFolderId);
        Wanted := FactorsOfPlan(APlan);
        CheckPlanAgainstPoints(AId, Wanted);
        if Length(APoints) > 0 then
          CheckNewPoints(Wanted, ReadSlots(AId, LoadFactors(AId)), APoints);
      end;
      Changed := AChangePurpose or AChangePlan;
      if AChangePurpose then
        S.Purpose := APurpose;
      if AChangePlan then
        ApplyPlan(S, APlan, Fresh);
      if Changed then
      begin
        S.MarkModified(UTCNow);
        FManager.Flush;
      end;
      Result := ApplyPoints(S, AUser.Id, APoints, AReason, False, Fresh, Added);
      if Added > 0 then
      begin
        if not Changed then
        begin
          S.MarkModified(UTCNow);
          FManager.Flush;
        end;
        Changed := True;
      end;
      if Changed then
        RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
          Format('Updated the plan of series "%s"', [S.Title]));
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        Unwind(Trans, E, S);
        raise;
      end;
    end;
  finally
    Fresh.Free;
  end;
end;

function TSeriesModel.AddPoints(AUser: TUser; AId: Integer;
  const APoints: TArray<TSeriesPoint>; const AReason: string): TArray<Integer>;
begin
  Result := InsertPoints(AUser, AId, APoints, AReason, False);
end;

function TSeriesModel.FillGrid(AUser: TUser; AId: Integer;
  const ALevels: TArray<TArray<Double>>): TArray<Integer>;
var
  Points: TList<TSeriesPoint>;
  Counter: TArray<Integer>;
  Pt: TSeriesPoint;
  K, Total: Integer;
  Carry: Boolean;
begin
  Result := nil;
  if Length(ALevels) = 0 then
    Exit;
  Total := 1;
  for K := 0 to High(ALevels) do
    Total := Total * Length(ALevels[K]);
  Points := TList<TSeriesPoint>.Create;
  try
    SetLength(Counter, Length(ALevels));
    while Points.Count < Total do
    begin
      Pt := nil;
      SetLength(Pt, Length(ALevels));
      for K := 0 to High(ALevels) do
        Pt[K] := ALevels[K][Counter[K]];
      Points.Add(Pt);
      K := High(ALevels);
      Carry := True;
      while Carry and (K >= 0) do
      begin
        Inc(Counter[K]);
        if Counter[K] >= Length(ALevels[K]) then
        begin
          Counter[K] := 0;
          Dec(K);
        end
        else
          Carry := False;
      end;
    end;
    Result := InsertPoints(AUser, AId, Points.ToArray, '', True);
  finally
    Points.Free;
  end;
end;

procedure TSeriesModel.RemovePoint(AUser: TUser; AId, ASlotId: Integer);
var
  S: TSeries;
  Trans: IDBTransaction;
  Factors: TArray<TSeriesFactorRef>;
  Slots: TArray<TSeriesSlotInfo>;
  At: Integer;
  Members: TList<TSeriesMember>;
  Levels: TList<TSeriesSlotLevel>;
  L: TSeriesSlotLevel;
  Slot: TSeriesSlot;
  Text: string;
begin
  S := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    S := LoadSeries(AId);
    RequireWrite(AUser, S.ProjectId);
    RequireOpen(S);
    Factors := LoadFactors(AId);
    Slots := ReadSlots(AId, Factors);
    At := FindSlot(Slots, ASlotId);
    Text := PointText(Factors, Slots[At].Levels);
    Members := FManager.Find<TSeriesMember>
      .Where(Linq['SlotId'] = ASlotId).Refreshing.List;
    try
      if Members.Count > 0 then
        raise ESeriesError.Create('Unlink the depositions of this point first.');
    finally
      Members.Free;
    end;
    Levels := FManager.Find<TSeriesSlotLevel>
      .Where(Linq['SlotId'] = ASlotId).Refreshing.List;
    try
      for L in Levels do
        FManager.Remove(L);
    finally
      Levels.Free;
    end;
    Slot := FManager.Find<TSeriesSlot>(ASlotId);
    FManager.Remove(Slot);
    S.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
      Format('Removed point %s', [Text]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Unwind(Trans, E, S);
      raise;
    end;
  end;
end;

procedure TSeriesModel.Start(AUser: TUser; AId: Integer);
var
  S: TSeries;
  Trans: IDBTransaction;
begin
  if FVia = scvMcp then
    raise ESeriesError.Create('A series is started in the desktop.');
  S := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    S := LoadSeries(AId);
    RequireWrite(AUser, S.ProjectId);
    if S.Status <> ssDraft then
      raise ESeriesError.Create('Only a draft series can be started.');
    S.Status := ssActive;
    S.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
      Format('Status changed from %s to %s', [StatusNames[ssDraft], StatusNames[ssActive]]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Unwind(Trans, E, S);
      raise;
    end;
  end;
end;

function TSeriesModel.DefaultDepositionTitle(AUser: TUser;
  AId, ASlotId: Integer): string;
var
  S: TSeries;
  Factors: TArray<TSeriesFactorRef>;
  Slots: TArray<TSeriesSlotInfo>;
begin
  S := LoadSeries(AId);
  RequireRead(AUser, S.ProjectId);
  Factors := LoadFactors(AId);
  Slots := ReadSlots(AId, Factors);
  Result := Trim(S.Title + ' ' + PointText(Factors, Slots[FindSlot(Slots, ASlotId)].Levels));
end;

procedure TSeriesModel.DepositionDefaults(AUser: TUser; AId: Integer;
  out AActionTypeId, AEquipmentId: Integer);
var
  S: TSeries;
  L: TList<TSeriesMember>;
  Item: TItem;
  I: Integer;
begin
  AActionTypeId := 0;
  AEquipmentId := 0;
  S := LoadSeries(AId);
  RequireRead(AUser, S.ProjectId);
  L := FManager.Find<TSeriesMember>
    .Where(Linq['SeriesId'] = AId).OrderBy('Id').Refreshing.List;
  try
    for I := L.Count - 1 downto 0 do
      if L[I].AttemptState = satValid then
      begin
        Item := FManager.Find<TItem>(L[I].ItemId);
        if (Item <> nil) and not Item.IsDeleted then
        begin
          if Assigned(Item.ActionType) then
            AActionTypeId := Item.ActionType.Id;
          if Assigned(Item.Equipment) then
            AEquipmentId := Item.Equipment.Id;
          Exit;
        end;
      end;
  finally
    L.Free;
  end;
end;

function TSeriesModel.MakeDeposition(AUser: TUser; AId, ASlotId: Integer;
  const ADraft: TSeriesDepositionDraft): Integer;
var
  S: TSeries;
  Trans: IDBTransaction;
  Fresh: TList<TObject>;
  Made: TList<unit_Item.TValue>;
  Items: TItemModel;
  Created, Item: TItem;
  Factors: TArray<TSeriesFactorRef>;
  Slots: TArray<TSeriesSlotInfo>;
  Fixed: TList<TSeriesFixed>;
  ActionType: TActionType;
  Equipment: TEquipment;
  V: unit_Item.TValue;
  Title, Note, PointDesc: string;
  At, I, Folder: Integer;
begin
  Result := 0;
  Title := CleanTitle(ADraft.Title);
  if Length(ADraft.Description) > MAX_DESCRIPTION then
    raise ESeriesError.CreateFmt('The description must be at most %d characters.',
      [MAX_DESCRIPTION]);
  S := nil;
  Item := nil;
  Fresh := TList<TObject>.Create;
  Made := TList<unit_Item.TValue>.Create;
  Items := TItemModel.Create(FManager);
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := LoadSeries(AId);
      RequireWrite(AUser, S.ProjectId);
      RequireActive(S);
      Factors := LoadFactors(AId);
      Slots := ReadSlots(AId, Factors);
      At := FindSlot(Slots, ASlotId);
      if Slots[At].ValidItemId <> 0 then
        RaiseSlotTaken(S, Slots[At].ValidItemId);
      ActionType := nil;
      if ADraft.ActionTypeId > 0 then
      begin
        ActionType := FManager.Find<TActionType>(ADraft.ActionTypeId);
        if ActionType = nil then
          raise ESeriesError.CreateFmt('Action type %d not found.', [ADraft.ActionTypeId]);
      end;
      Equipment := nil;
      if ADraft.EquipmentId > 0 then
      begin
        Equipment := FManager.Find<TEquipment>(ADraft.EquipmentId);
        if Equipment = nil then
          raise ESeriesError.CreateFmt('Equipment %d not found.', [ADraft.EquipmentId]);
      end;
      if S.TargetFolderId.HasValue then
        Folder := S.TargetFolderId.Value
      else
        Folder := 0;
      CheckTargetFolder(S.ProjectId, Folder);
      for I := 0 to High(Factors) do
        RequireValueType(Factors[I].ValueTypeId);
      Fixed := FManager.Find<TSeriesFixed>
        .Where(Linq['SeriesId'] = AId).OrderBy('Id').Refreshing.List;
      try
        for I := 0 to Fixed.Count - 1 do
          RequireValueType(Fixed[I].ValueTypeId);
      finally
        Fixed.Free;
      end;
      PointDesc := PointText(Factors, Slots[At].Levels);

      Items.AssignProject(S.ProjectId, Folder);
      Created := Items.AddItem(TItemType.Synthesis, Title, TItemLevel.Proc, 0,
        ADraft.Description, ActionType, Equipment, AUser.Id, ADraft.Properties);
      Result := Created.Id;
      Created.Free;
      Item := FManager.Find<TItem>(Result);

      Note := 'Planned value from series ' + S.Title;
      for I := 0 to High(Factors) do
        Made.Add(Items.NewValue(FManager.Find<TValueType>(Factors[I].ValueTypeId),
          EXP_CONDITION, Slots[At].Levels[I], AUser.Id, Item, 0,
          PlannedDescription(Factors[I].EntryLabel, Note),
          TValueSourceInfo.Planned(Note)));
      Fixed := FManager.Find<TSeriesFixed>
        .Where(Linq['SeriesId'] = AId).OrderBy('Id').Refreshing.List;
      try
        for I := 0 to Fixed.Count - 1 do
          Made.Add(Items.NewValue(FManager.Find<TValueType>(Fixed[I].ValueTypeId),
            EXP_CONDITION, Fixed[I].FixedValue, AUser.Id, Item, Fixed[I].Tol,
            PlannedDescription(Fixed[I].EntryLabel, Note),
            TValueSourceInfo.Planned(Note)));
      finally
        Fixed.Free;
      end;
      NewMember(AId, Result, ASlotId, AUser.Id, Fresh);
      S.MarkModified(UTCNow);
      FManager.Flush;
      RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
        Format('Made deposition %d for point %s', [Result, PointDesc]));
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        for V in Made do
        begin
          Item.Values.Remove(V);
          try
            FManager.Evict(V);
            FManager.AddOwnership(V);
          except
          end;
        end;
        if Result > 0 then
          DiscardAudit(aetItem, Result);
        if Item <> nil then
          Discard(Item);
        Unwind(Trans, E, S);
        raise;
      end;
    end;
  finally
    Items.Free;
    Made.Free;
    Fresh.Free;
  end;
end;

procedure TSeriesModel.LinkToSlot(AUser: TUser; AId, ASlotId, AItemId: Integer);
var
  S: TSeries;
  Trans: IDBTransaction;
  Fresh: TList<TObject>;
  Factors: TArray<TSeriesFactorRef>;
  Slots: TArray<TSeriesSlotInfo>;
  Existing: TList<TSeriesMember>;
  At: Integer;
  Text: string;
begin
  S := nil;
  Fresh := TList<TObject>.Create;
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := LoadSeries(AId);
      RequireWrite(AUser, S.ProjectId);
      RequireActive(S);
      CheckLinkable(S, AItemId);
      Factors := LoadFactors(AId);
      Slots := ReadSlots(AId, Factors);
      At := FindSlot(Slots, ASlotId);
      if Slots[At].ValidItemId <> 0 then
        RaiseSlotTaken(S, Slots[At].ValidItemId);
      Existing := FManager.Find<TSeriesMember>
        .Where((Linq['SeriesId'] = AId) and (Linq['ItemId'] = AItemId))
        .Refreshing.List;
      try
        if Existing.Count > 0 then
          raise ESeriesError.CreateFmt('Item %d is already in this series.', [AItemId]);
      finally
        Existing.Free;
      end;
      Text := PointText(Factors, Slots[At].Levels);
      NewMember(AId, AItemId, ASlotId, AUser.Id, Fresh);
      S.MarkModified(UTCNow);
      FManager.Flush;
      RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
        Format('Linked item %d to point %s', [AItemId, Text]));
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        Unwind(Trans, E, S);
        raise;
      end;
    end;
  finally
    Fresh.Free;
  end;
end;

function TSeriesModel.ComputeLinks(S: TSeries;
  const AFactors: TArray<TSeriesFactorRef>; const ASlots: TArray<TSeriesSlotInfo>;
  const AItemIds: TArray<Integer>): TArray<TSeriesLinkLine>;
var
  Facts: TDictionary<Integer, TSeriesItemFacts>;
  Wanted, Roots: TList<Integer>;
  InSeries: TDictionary<Integer, Boolean>;
  Lines: TList<TSeriesLinkLine>;
  Members: TList<TSeriesMember>;
  Chunk: TArray<Variant>;
  Taken: TArray<Boolean>;
  Types: TArray<Integer>;
  Values: TArray<TSeriesSubtreeValue>;
  Level, Tol: TArray<Double>;
  F: TSeriesItemFacts;
  Line: TSeriesLinkLine;
  V: TSeriesSubtreeValue;
  M: TSeriesMember;
  Id, K, I, Count, FreeAt, TakenAt, PendingAt: Integer;
  NoValue, Ambiguous, Within, Outside: Boolean;
  Pending: TList<TSeriesPoint>;
begin
  Result := nil;
  Wanted := TList<Integer>.Create;
  Roots := TList<Integer>.Create;
  InSeries := TDictionary<Integer, Boolean>.Create;
  Lines := TList<TSeriesLinkLine>.Create;
  Pending := TList<TSeriesPoint>.Create;
  Facts := nil;
  try
    for Id in AItemIds do
      if not Wanted.Contains(Id) then
        Wanted.Add(Id);
    if Wanted.Count = 0 then
      Exit;
    if Length(AFactors) = 0 then
      raise ESeriesError.Create('The series has no factors.');
    Facts := LoadItemFacts(Wanted.ToArray);
    for Id in Wanted do
    begin
      if not Facts.TryGetValue(Id, F) then
        raise ESeriesError.CreateFmt('Item %d not found.', [Id]);
      if F.IsDeleted then
        raise ESeriesError.CreateFmt('Item %d is deleted.', [Id]);
      if F.ProjectId <> S.ProjectId then
        raise ESeriesError.CreateFmt('Item %d belongs to another project.', [Id]);
    end;
    for Chunk in IdChunks(Wanted.ToArray) do
    begin
      Members := FManager.Find<TSeriesMember>
        .Where((Linq['SeriesId'] = S.Id) and Linq['ItemId']._In(Chunk))
        .Refreshing.List;
      try
        for M in Members do
          InSeries.AddOrSetValue(M.ItemId, True);
      finally
        Members.Free;
      end;
    end;
    for Id in Wanted do
    begin
      F := Facts[Id];
      if (F.Parent = 0) and (F.Level <> Ord(TItemLevel.Folder))
        and not InSeries.ContainsKey(Id) then
        Roots.Add(Id);
    end;
    SetLength(Types, Length(AFactors));
    for K := 0 to High(AFactors) do
      Types[K] := AFactors[K].ValueTypeId;
    Values := SubtreeValues(S.ProjectId, Roots.ToArray, Types);
    SetLength(Taken, Length(ASlots));
    for I := 0 to High(ASlots) do
      Taken[I] := ASlots[I].ValidItemId <> 0;

    for Id in Wanted do
    begin
      F := Facts[Id];
      Line.ItemId := Id;
      Line.SlotId := 0;
      Line.Levels := nil;
      if (F.Parent <> 0) or (F.Level = Ord(TItemLevel.Folder)) then
        Line.Outcome := sloNotRoot
      else if InSeries.ContainsKey(Id) then
        Line.Outcome := sloAlreadyMember
      else
      begin
        Level := nil;
        Tol := nil;
        SetLength(Level, Length(AFactors));
        SetLength(Tol, Length(AFactors));
        NoValue := False;
        Ambiguous := False;
        for K := 0 to High(AFactors) do
        begin
          Count := 0;
          for V in Values do
            if (V.Root = Id) and (V.RecType = EXP_CONDITION)
              and (V.TypeId = AFactors[K].ValueTypeId) then
            begin
              if Count = 0 then
              begin
                Level[K] := V.Value;
                Tol[K] := V.Tol;
                Count := 1;
              end
              else if SameLevel(Level[K], V.Value) then
                Tol[K] := Max(Tol[K], V.Tol)
              else
                Ambiguous := True;
            end;
          if Count = 0 then
            NoValue := True;
        end;
        if NoValue then
          Line.Outcome := sloNoValue
        else if Ambiguous then
          Line.Outcome := sloAmbiguousValue
        else
        begin
          Line.Levels := Level;
          FreeAt := -1;
          TakenAt := -1;
          for I := 0 to High(ASlots) do
          begin
            Within := True;
            for K := 0 to High(AFactors) do
              if Abs(ASlots[I].Levels[K] - Level[K]) >
                Max(Tol[K], REL_EPS * Max(1.0, Abs(Level[K]))) then
                Within := False;
            if Within then
              if Taken[I] then
              begin
                if TakenAt < 0 then
                  TakenAt := I;
              end
              else if FreeAt < 0 then
                FreeAt := I;
          end;
          if FreeAt >= 0 then
          begin
            Line.Outcome := sloLinked;
            Line.SlotId := ASlots[FreeAt].SlotId;
            Taken[FreeAt] := True;
          end
          else if TakenAt >= 0 then
          begin
            Line.Outcome := sloSlotTaken;
            Line.SlotId := ASlots[TakenAt].SlotId;
          end
          else
          begin
            Outside := False;
            for K := 0 to High(AFactors) do
              if not InRange(AFactors[K], Level[K]) then
                Outside := True;
            if Outside then
              Line.Outcome := sloOutsideRange
            else
            begin
              PendingAt := -1;
              for I := 0 to Pending.Count - 1 do
              begin
                Within := True;
                for K := 0 to High(AFactors) do
                  if Abs(Pending[I][K] - Level[K]) >
                    Max(Tol[K], REL_EPS * Max(1.0, Abs(Level[K]))) then
                    Within := False;
                if Within then
                begin
                  PendingAt := I;
                  Break;
                end;
              end;
              if PendingAt >= 0 then
              begin
                Line.Outcome := sloSlotTaken;
                Line.Levels := Pending[PendingAt];
              end
              else
              begin
                Line.Outcome := sloNewPoint;
                Pending.Add(Level);
              end;
            end;
          end;
        end;
      end;
      Lines.Add(Line);
    end;
    Result := Lines.ToArray;
  finally
    Pending.Free;
    Facts.Free;
    Lines.Free;
    InSeries.Free;
    Roots.Free;
    Wanted.Free;
  end;
end;

function TSeriesModel.PreviewLinkByValues(AUser: TUser; AId: Integer;
  const AItemIds: TArray<Integer>): TArray<TSeriesLinkLine>;
var
  S: TSeries;
  Factors: TArray<TSeriesFactorRef>;
begin
  S := LoadSeries(AId);
  RequireRead(AUser, S.ProjectId);
  Factors := LoadFactors(AId);
  Result := ComputeLinks(S, Factors, ReadSlots(AId, Factors), AItemIds);
end;

function TSeriesModel.LinkByValues(AUser: TUser; AId: Integer;
  const AItemIds: TArray<Integer>; ACreateMissing: Boolean): TArray<TSeriesLinkLine>;
var
  S: TSeries;
  Trans: IDBTransaction;
  Fresh: TList<TObject>;
  Factors: TArray<TSeriesFactorRef>;
  Slots: TArray<TSeriesSlotInfo>;
  Created: TList<TSeriesSlotInfo>;
  Info: TSeriesSlotInfo;
  Pt: TArray<TSeriesPoint>;
  Ids: TArray<Integer>;
  I, Applied: Integer;
begin
  Result := nil;
  S := nil;
  Applied := 0;
  Fresh := TList<TObject>.Create;
  Created := TList<TSeriesSlotInfo>.Create;
  Trans := FManager.Connection.BeginTransaction;
  try
    try
      S := LoadSeries(AId);
      RequireWrite(AUser, S.ProjectId);
      RequireActive(S);
      Factors := LoadFactors(AId);
      Slots := ReadSlots(AId, Factors);
      Result := ComputeLinks(S, Factors, Slots, AItemIds);
      for I := 0 to High(Result) do
        case Result[I].Outcome of
          sloLinked:
            begin
              NewMember(AId, Result[I].ItemId, Result[I].SlotId, AUser.Id, Fresh);
              Inc(Applied);
            end;
          sloNewPoint:
            if ACreateMissing then
            begin
              Pt := nil;
              SetLength(Pt, 1);
              Pt[0] := Result[I].Levels;
              Ids := AddSlots(AId, AUser.Id, Factors, Pt, ssoAdded,
                'Linked from existing deposition', Fresh);
              Info.SlotId := Ids[0];
              Info.Levels := Result[I].Levels;
              Created.Add(Info);
              Result[I].SlotId := Ids[0];
              NewMember(AId, Result[I].ItemId, Ids[0], AUser.Id, Fresh);
              Inc(Applied);
            end;
          sloSlotTaken:
            if Result[I].SlotId = 0 then
              for Info in Created do
                if SamePoint(Info.Levels, Result[I].Levels) then
                begin
                  Result[I].SlotId := Info.SlotId;
                  Break;
                end;
        end;
      if Applied > 0 then
      begin
        S.MarkModified(UTCNow);
        FManager.Flush;
        RecordAudit(FManager, aetSeries, AId, aoUpdate, AUser.Id,
          Format('Linked %d deposition(s) by value', [Applied]));
      end;
      Trans.Commit;
    except
      on E: Exception do
      begin
        DiscardAll(Fresh);
        Unwind(Trans, E, S);
        raise;
      end;
    end;
  finally
    Created.Free;
    Fresh.Free;
  end;
end;


function TSeriesModel.BuildTable(AUser: TUser; AId: Integer;
  AIncludeFailed: Boolean): TSeriesTable;
var
  S: TSeries;
  ProjectId: Integer;
  Members: TList<TSeriesMember>;
  Cols: TList<TSeriesColumn>;
  Nodes: TDictionary<Integer, TSeriesNode>;
  Children: TDictionary<Integer, TList<Integer>>;
  Owner: TDictionary<Integer, Integer>;
  Titles: TDictionary<Integer, string>;
  Sources: TDictionary<string, string>;
  RowInputs: TList<TSeriesRowInput>;
  Excluded: TList<Integer>;
  Hits: TList<TSeriesHit>;
  Prefs: TList<TSeriesColumnPref>;
  Roots, Stack: TList<Integer>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Chunk: TArray<Variant>;
  M: TSeriesMember;
  C: TSeriesColumn;
  Node: TSeriesNode;
  List: TList<Integer>;
  RI: TSeriesRowInput;
  H: TSeriesHit;
  Pref: TSeriesColumnPref;
  Info: TSeriesValueTypeInfo;
  Src: TSeriesSourceInfo;
  SrcList: TList<TSeriesSourceInfo>;
  TypeList: TList<TSeriesValueTypeInfo>;
  Pair: TPair<string, string>;
  ItemId, Cur, Child, RootId: Integer;
  ItemIds, TypeIds, ActionIds: TList<Integer>;
  PlanInfo: TSeriesPlanInfo;
  Slot: TSeriesSlotInfo;
  Valid: TSeriesMember;
  Fc: TSeriesFactorSpec;
  Fx: TSeriesFixedSpec;
  Rs: TSeriesResponseSpec;
  K: Integer;

  function PlanDecides(AValueTypeId: Integer): Boolean;
  var
    F: TSeriesFactorSpec;
    X: TSeriesFixedSpec;
  begin
    for F in PlanInfo.Plan.Factors do
      if F.ValueTypeId = AValueTypeId then
        Exit(True);
    for X in PlanInfo.Plan.Fixed do
      if X.ValueTypeId = AValueTypeId then
        Exit(True);
    Result := False;
  end;
begin
  S := LoadSeries(AId);
  RequireRead(AUser, S.ProjectId);
  ProjectId := S.ProjectId;

  Nodes := TDictionary<Integer, TSeriesNode>.Create;
  Children := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  Owner := TDictionary<Integer, Integer>.Create;
  Titles := TDictionary<Integer, string>.Create;
  Sources := TDictionary<string, string>.Create;
  RowInputs := TList<TSeriesRowInput>.Create;
  Excluded := TList<Integer>.Create;
  Hits := TList<TSeriesHit>.Create;
  Prefs := TList<TSeriesColumnPref>.Create;
  Roots := TList<Integer>.Create;
  Stack := TList<Integer>.Create;
  ItemIds := TList<Integer>.Create;
  TypeIds := TList<Integer>.Create;
  ActionIds := TList<Integer>.Create;
  SrcList := TList<TSeriesSourceInfo>.Create;
  TypeList := TList<TSeriesValueTypeInfo>.Create;
  Members := nil;
  Cols := nil;
  try
    Members := FManager.Find<TSeriesMember>
      .Where(Linq['SeriesId'] = AId).OrderBy('Id').Refreshing.List;
    Cols := FManager.Find<TSeriesColumn>
      .Where(Linq['SeriesId'] = AId).Refreshing.List;

    LoadNodes(ProjectId, Nodes, Children);
    PlanInfo := GetPlan(AUser, AId);
    for Fc in PlanInfo.Plan.Factors do
      TypeIds.Add(Fc.ValueTypeId);
    for Fx in PlanInfo.Plan.Fixed do
      if not TypeIds.Contains(Fx.ValueTypeId) then
        TypeIds.Add(Fx.ValueTypeId);
    for Rs in PlanInfo.Plan.Responses do
      if not TypeIds.Contains(Rs.ValueTypeId) then
        TypeIds.Add(Rs.ValueTypeId);

    for M in Members do
      if not Nodes.ContainsKey(M.ItemId) then
        Excluded.Add(M.ItemId)
      else if M.SlotId.HasValue then
        Roots.Add(M.ItemId);

    for Chunk in IdChunks(Roots.ToArray) do
    begin
      Rows := FManager.Find<TItem>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('Title').As_('Title')))
        .Where(Linq['Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
          Titles.AddOrSetValue(Integer(Row.Values['Id']), VarToStr(Row.Values['Title']));
      finally
        Rows.Free;
      end;
    end;

    for Slot in PlanInfo.Slots do
    begin
      Valid := nil;
      for M in Members do
        if M.SlotId.HasValue and (M.SlotId.Value = Slot.SlotId)
          and (M.AttemptState = satValid) then
          Valid := M;
      RI := Default(TSeriesRowInput);
      RI.SlotId := Slot.SlotId;
      RI.Origin := Slot.Origin;
      SetLength(RI.Levels, Length(Slot.Levels));
      for K := 0 to High(Slot.Levels) do
      begin
        RI.Levels[K].ValueTypeId := PlanInfo.Plan.Factors[K].ValueTypeId;
        RI.Levels[K].Value := Slot.Levels[K];
      end;
      if (Valid <> nil) and Nodes.ContainsKey(Valid.ItemId) then
      begin
        RI.HasMember := True;
        RI.MemberId := Valid.Id;
        RI.ItemId := Valid.ItemId;
        Titles.TryGetValue(Valid.ItemId, RI.Title);
      end;
      RowInputs.Add(RI);
      for M in Members do
        if M.SlotId.HasValue and (M.SlotId.Value = Slot.SlotId)
          and (M.AttemptState = satFailed) and Nodes.ContainsKey(M.ItemId) then
        begin
          RI.HasMember := True;
          RI.Failed := True;
          RI.MemberId := M.Id;
          RI.ItemId := M.ItemId;
          RI.Title := '';
          Titles.TryGetValue(M.ItemId, RI.Title);
          RowInputs.Add(RI);
        end;
    end;

    for RootId in Roots do
    begin
      Stack.Clear;
      Stack.Add(RootId);
      Owner.AddOrSetValue(RootId, RootId);
      while Stack.Count > 0 do
      begin
        Cur := Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        ItemIds.Add(Cur);
        if Children.TryGetValue(Cur, List) then
          for Child in List do
            if not Owner.ContainsKey(Child) then
            begin
              Owner.Add(Child, RootId);
              Stack.Add(Child);
            end;
      end;
    end;

    for Chunk in IdChunks(ItemIds.ToArray) do
    begin
      Rows := FManager.Find<unit_Item.TValue>
        .CreateAlias('Item', 'i')
        .CreateAlias('ValueType', 'vt')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('i.Id').As_('ItemId'))
          .Add(TProjections.Prop('vt.Id').As_('TypeId'))
          .Add(TProjections.Prop('RecType').As_('RecType'))
          .Add(TProjections.Prop('Value').As_('V'))
          .Add(TProjections.Prop('Tol').As_('Tol'))
          .Add(TProjections.Prop('SourceKind').As_('SourceKind')))
        .Where(Linq['i.Id']._In(Chunk))
        .OrderBy('Id')
        .ListValues;
      try
        for Row in Rows do
        begin
          ItemId := Integer(Row.Values['ItemId']);
          H.RootItemId := Owner[ItemId];
          H.ItemId := ItemId;
          H.ValueId := Integer(Row.Values['Id']);
          H.ValueTypeId := Integer(Row.Values['TypeId']);
          H.RecType := TRecType(Integer(Row.Values['RecType']));
          H.Value := Double(Row.Values['V']);
          if VarIsNull(Row.Values['Tol']) then
            H.Tol := 0
          else
            H.Tol := Double(Row.Values['Tol']);
          H.Planned := not VarIsNull(Row.Values['SourceKind'])
            and (Integer(Row.Values['SourceKind']) = Ord(vskPlanned));
          Node := Nodes[ItemId];
          if ItemId = H.RootItemId then
            H.SourceKey := SERIES_ROOT_KEY
          else if Node.ActionTypeId <> 0 then
          begin
            H.SourceKey := SeriesActionTypeKey(Node.ActionTypeId);
            if not ActionIds.Contains(Node.ActionTypeId) then
              ActionIds.Add(Node.ActionTypeId);
          end
          else
          begin
            H.SourceKey := SeriesLevelKey(Node.Level);
            Sources.AddOrSetValue(H.SourceKey,
              GetEnumName(TypeInfo(TItemLevel), Ord(Node.Level)));
          end;
          if not TypeIds.Contains(H.ValueTypeId) then
            TypeIds.Add(H.ValueTypeId);
          Hits.Add(H);
        end;
      finally
        Rows.Free;
      end;
    end;

    for Chunk in IdChunks(TypeIds.ToArray) do
    begin
      Rows := FManager.Find<TValueType>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('Title').As_('Title'))
          .Add(TProjections.Prop('Units').As_('Units')))
        .Where(Linq['Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
        begin
          Info.Id := Integer(Row.Values['Id']);
          Info.Title := VarToStr(Row.Values['Title']);
          Info.Units := VarToStr(Row.Values['Units']);
          TypeList.Add(Info);
        end;
      finally
        Rows.Free;
      end;
    end;

    for Chunk in IdChunks(ActionIds.ToArray) do
    begin
      Rows := FManager.Find<TActionType>
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('Title').As_('Title')))
        .Where(Linq['Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
          Sources.AddOrSetValue(SeriesActionTypeKey(Integer(Row.Values['Id'])),
            VarToStr(Row.Values['Title']));
      finally
        Rows.Free;
      end;
    end;

    for Pair in Sources do
    begin
      Src.Key := Pair.Key;
      Src.Caption := Pair.Value;
      SrcList.Add(Src);
    end;

    for C in Cols do
    begin
      Pref.RecType := C.RecType;
      Pref.ValueTypeId := C.ValueTypeId;
      Pref.SourceKey := C.SourceKey;
      Pref.EntryLabel := C.EntryLabel;
      Pref.Role := C.Role;
      Pref.SortOrder := C.SortOrder;
      if (C.RecType = TRecType.EXP_CONDITION) and PlanDecides(C.ValueTypeId) then
        Continue;
      Prefs.Add(Pref);
    end;
    for Fc in PlanInfo.Plan.Factors do
    begin
      Pref.RecType := TRecType.EXP_CONDITION;
      Pref.ValueTypeId := Fc.ValueTypeId;
      Pref.SourceKey := '';
      Pref.EntryLabel := Fc.EntryLabel;
      Pref.Role := scrVaried;
      Pref.SortOrder := Prefs.Count;
      Prefs.Add(Pref);
    end;
    for Fx in PlanInfo.Plan.Fixed do
    begin
      Pref.RecType := TRecType.EXP_CONDITION;
      Pref.ValueTypeId := Fx.ValueTypeId;
      Pref.SourceKey := '';
      Pref.EntryLabel := Fx.EntryLabel;
      Pref.Role := scrFixed;
      Pref.SortOrder := Prefs.Count;
      Prefs.Add(Pref);
    end;

    Result := BuildSeriesTable(RowInputs.ToArray, Hits.ToArray, TypeList.ToArray,
      SrcList.ToArray, Prefs.ToArray, PlanInfo.Plan.Fixed, AIncludeFailed);
    Result.Excluded := Excluded.ToArray;
  finally
    TypeList.Free;
    SrcList.Free;
    ActionIds.Free;
    TypeIds.Free;
    ItemIds.Free;
    Stack.Free;
    Roots.Free;
    Prefs.Free;
    Hits.Free;
    Excluded.Free;
    RowInputs.Free;
    Sources.Free;
    Titles.Free;
    Owner.Free;
    Children.Free;
    Nodes.Free;
    Cols.Free;
    Members.Free;
  end;
end;

end.
