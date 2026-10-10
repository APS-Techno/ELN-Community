unit unit_HypothesisModel;

{ This unit is compiled into MCP: human gate execution must remain in the
  separate gate unit. Status, history and audit writes are atomic.
  Session managers cache entities, so status reads refresh committed rows;
  writes use Version to detect concurrent changes. Failed writes must leave
  no dirty entities that a later shared-manager Flush could replay. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_Hypothesis,
  unit_HypothesisRun,
  unit_HypothesisEvidence,
  unit_HypothesisStatusChange,
  unit_HypothesisRules,
  unit_ProjectAccessPolicy;

type
  EHypothesisError = class(Exception)
  private
    FRefusal: THypRefusal;
  public
    constructor Create(ARefusal: THypRefusal; const AMessage: string = '');
    property Refusal: THypRefusal read FRefusal;
  end;

  EHypothesisAccess = class(Exception);
  EHypothesisNotFound = class(EHypothesisAccess);
  EHypothesisNotApprover = class(EHypothesisAccess);

  EHypothesisConflict = class(Exception)
  private
    FCurrentVersion: Integer;
  public
    constructor Create(ACurrentVersion: Integer);
    property CurrentVersion: Integer read FCurrentVersion;
  end;

  // An optimistic-lock failure on a record other than the hypothesis (the
  // write's Flush is global to a shared manager). That record has been
  // reloaded; retrying the write can succeed.
  EHypothesisOtherRecordChanged = class(EHypothesisError)
  public
    constructor Create;
  end;

  THypDerivedState = (hdsNone, hdsToMake, hdsWaitingForMeasurement, hdsReadyToConclude);

  // The acceptance seal: none unless the hypothesis is Accepted
  // and carries a ContentHash; otherwise intact or tampered.
  THypSealState = (hssNone, hssIntact, hssTampered);

  TKeyValueSummary = record
    N: Integer;
    Mean, Min, Max: Double;
  end;

  THypothesisSummary = record
    Id, ProjectId, ParentId, CreatedBy, Version: Integer;   // ParentId 0 = root
    Title: string;
    Status: THypothesisStatus;
    Derived: THypDerivedState;
    RunCount, EvidenceCount: Integer;
    KeyValueTypeId: Integer;                                  // 0 = none
    KeyValue: TKeyValueSummary;                               // N = 0 when none
    CreatedDate: TDateTime;
    ModifiedDate: TDateTime;                                  // 0 = never modified
  end;

  THypothesisRunView = record
    RunId, ItemId, ItemProjectId: Integer;
    ItemTitle: string;
    Role: THypothesisRunRole;
    Missing: Boolean;
  end;

  THypothesisEvidenceView = record
    EvidenceId, ItemId, ItemProjectId, ValueId: Integer;      // ValueId 0 = none
    FileId: Int64;                                            // 0 = none
    ItemTitle, Note, FileHash: string;
    HasSnapshot: Boolean;
    ValueSnapshot: Double;
    Changed, Missing: Boolean;
  end;

  THypothesisHistoryView = record
    OldStatus, NewStatus: THypothesisStatus;
    ChangedBy, ChangedDeviceId: Integer;                      // device 0 = none
    ChangedDate: TDateTime;
    Comment: string;
  end;

  THypothesisDetail = record
    Summary: THypothesisSummary;
    Statement, Change, Conclusion, ContentHash: string;
    HasOutcome: Boolean;
    Outcome: THypothesisOutcome;
    CreatedDeviceId: Integer;
    CreatedDate: TDateTime;
    Runs: TArray<THypothesisRunView>;
    Evidence: TArray<THypothesisEvidenceView>;
    History: TArray<THypothesisHistoryView>;
    ChildIds: TArray<Integer>;
  end;

  THypothesisFilter = record
    ProjectId: Integer;                                       // 0 = every readable project
    Statuses: set of THypothesisStatus;                       // [] = all
    DerivedStates: set of THypDerivedState;                   // [] = all
    RootId: Integer;                                          // 0 = all; else the subtree incl. root
    AuthorId: Integer;                                        // 0 = all
    // [] = no restriction; else only these projects (still only readable
    // ones) are read at all - an MCP session's project scope, so a scoped
    // key never makes the server scan the rest of the installation.
    ProjectIds: TArray<Integer>;
    class function All: THypothesisFilter; static;
  end;

const
  HypDerivedStateNames: array[THypDerivedState] of string =
    ('', 'to_make', 'waiting_for_measurement', 'ready_to_conclude');
  HypSealStateNames: array[THypSealState] of string =
    ('none', 'intact', 'tampered');

type
  THypothesisModel = class
  private
    FManager: TObjectManager;
    FAccess: IProjectAccessPolicy;
    procedure RequireWrite(AUser: TUser; AProjectId: Integer);
    procedure RequireRead(AUser: TUser; AProjectId: Integer);
    function LiveItemProjectId(AItemId: Integer): Integer;
    procedure WriteStatus(H: THypothesis; ANew: THypothesisStatus;
      AUser: TUser; ADeviceId: Integer; const AComment: string;
      out AChange: THypothesisStatusChange);
    procedure Discard(AObj: TObject);
    function ReadableProjectIds(AUser: TUser;
      const AFilter: THypothesisFilter): TArray<Integer>;
  public
    constructor Create(AManager: TObjectManager; const AAccess: IProjectAccessPolicy);
    class function Load(AManager: TObjectManager; AId: Integer): THypothesis; static;
    class procedure CheckVersion(H: THypothesis; AExpectedVersion: Integer); static;
    // For a write's except block, before it re-raises: rolls ATrans back and
    // puts H (nil allowed) back to its committed row. Also used by the gates.
    class procedure UnwindFailedWrite(AManager: TObjectManager;
      const ATrans: IDBTransaction; H: THypothesis; AError: Exception); static;
    class function RunsOf(AManager: TObjectManager; AId: Integer): TArray<THypothesisRun>; static;
    class function EvidenceOf(AManager: TObjectManager; AId: Integer): TArray<THypothesisEvidence>; static;
    function ActorsFor(AUser: TUser; H: THypothesis): THypActors;
    // Keep eligibility reads here so MCP clients cannot link human gate execution.
    class function AllowedGateTargetsFor(AManager: TObjectManager; AUser: TUser;
      H: THypothesis; const AAccess: IProjectAccessPolicy): TArray<THypothesisStatus>; overload; static;
    // Reuse per-request eligibility to avoid parsing the policy again.
    class function AllowedGateTargetsFor(AGates: TGateEligibility;
      H: THypothesis): TArray<THypothesisStatus>; overload; static;
    // Recomputes the seal from the committed runs/evidence (RunsOf/EvidenceOf
    // refresh) and compares it with H.ContentHash. hssNone unless Accepted;
    // an Accepted node with an empty ContentHash is hssTampered.
    class function SealStateOf(AManager: TObjectManager;
      H: THypothesis): THypSealState; static;

    function Propose(AUser: TUser; ADeviceId, AProjectId, AParentId: Integer;
      const ATitle, AStatement, AChange: string;
      AKeyValueTypeId: Integer): THypothesis;
    procedure UpdateProposed(AUser: TUser; AId, AExpectedVersion: Integer;
      const ATitle, AStatement, AChange: string; AKeyValueTypeId: Integer);
    function AttachRun(AUser: TUser; AId, AItemId: Integer;
      ARole: THypothesisRunRole): THypothesisRun;
    procedure DetachRun(AUser: TUser; AId, AItemId: Integer);
    function CiteEvidence(AUser: TUser; AId, AItemId: Integer; AFileId: Int64;
      AValueId: Integer; const ANote: string): THypothesisEvidence;
    procedure RemoveEvidence(AUser: TUser; AId, AEvidenceId: Integer);
    procedure SubmitConclusion(AUser: TUser; ADeviceId, AId,
      AExpectedVersion: Integer; const AConclusion: string;
      AOutcome: THypothesisOutcome);
    procedure Abandon(AUser: TUser; ADeviceId, AId, AExpectedVersion: Integer;
      const AComment: string);

    // Summaries must redact values outside readable projects and the MCP scope.
    function Get(AUser: TUser; AId: Integer;
      const AProjectScope: TArray<Integer> = nil): THypothesisDetail;      // raises EHypothesisAccess if unreadable
    function List(AUser: TUser; const AFilter: THypothesisFilter): TArray<THypothesisSummary>;
    function Tree(AUser: TUser; AProjectId, ARootId: Integer;              // ARootId 0 = whole project
      const AProjectScope: TArray<Integer> = nil): TArray<THypothesisSummary>;
  end;

/// AIds split into lists of at most 500 (IN_CHUNK), for Linq[...]._In: a
/// long IN (...) or OR chain fails on SQLite (999 parameters, expression
/// depth 1000).
function IdChunks(const AIds: TArray<Integer>): TArray<TArray<Variant>>; overload;

implementation

uses
  System.Variants,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections,
  Aurelius.Commands.Exceptions,
  Aurelius.Types.Nullable,
  unit_Item,
  unit_ItemTypes,
  unit_Project,
  unit_ValueType,
  unit_AuditLog,
  unit_AuditHelper,
  unit_TimeHelper,
  unit_ConflictHandler,
  unit_HypothesisHash;

const
  MAX_TITLE = 255;
  MAX_NOTE = 500;

type
  TLiveItem = record
    Title: string;
    ProjectId: Integer;
    IsDeleted: Boolean;
    IsFolder: Boolean;
  end;
  TLiveFile = record
    ItemId: Integer;
    Hash: string;
  end;
  TLiveValue = record
    ItemId: Integer;
    Value: Double;
  end;

  // Items, files and values as the database holds them NOW.
  // The MCP and desktop managers live for a whole session, so Find<TItem>,
  // Find<TFile> and Find<TValue> return whatever copy was cached when first
  // loaded - a stale hash, value or IsDeleted. These are projections, which
  // bypass the identity map (and leave the shared cached objects alone); a
  // row that is gone is simply absent. Not Manager.Refresh: on a vanished row
  // it silently keeps the stale copy. One statement per entity type per
  // IN_CHUNK ids.
  TLiveRows = class
  public
    Items: TDictionary<Integer, TLiveItem>;       // soft-deleted ones included
    Files: TDictionary<Int64, TLiveFile>;
    Values: TDictionary<Integer, TLiveValue>;
    constructor Create(AManager: TObjectManager; const AItemIds: TArray<Integer>;
      const AFileIds: TArray<Int64>; const AValueIds: TArray<Integer>);
    destructor Destroy; override;
  end;

function WriteVerdictText(V: TProjectWriteVerdict): string;
begin
  case V of
    pwNoUser:          Result := 'No user.';
    pwUserArchived:    Result := 'Your account is archived.';
    pwRoleCannotWrite: Result := 'Your role cannot change data.';
    pwProjectNotFound: Result := 'Project not found.';
    pwProjectArchived: Result := 'The project is archived.';
    pwNoPermission:    Result := 'You do not have write access to this project.';
  else
    Result := 'Access denied.';
  end;
end;


constructor EHypothesisError.Create(ARefusal: THypRefusal; const AMessage: string);
begin
  if AMessage = '' then
    inherited Create(RefusalText(ARefusal))
  else
    inherited Create(AMessage);
  FRefusal := ARefusal;
end;


constructor EHypothesisConflict.Create(ACurrentVersion: Integer);
begin
  inherited CreateFmt('The hypothesis was changed by someone else ' +
    '(now version %d). Reload and try again.', [ACurrentVersion]);
  FCurrentVersion := ACurrentVersion;
end;


constructor EHypothesisOtherRecordChanged.Create;
begin
  inherited Create(hrNotAllowed,
    'Another record was changed elsewhere; reload and try again.');
end;


constructor THypothesisModel.Create(AManager: TObjectManager;
  const AAccess: IProjectAccessPolicy);
begin
  inherited Create;
  if AAccess = nil then
    raise EArgumentNilException.Create('Access');
  FManager := AManager;
  FAccess := AAccess;
end;

class function THypothesisModel.Load(AManager: TObjectManager;
  AId: Integer): THypothesis;
var
  WasCached: Boolean;
begin
  WasCached := AManager.IsCached<THypothesis>(AId);
  Result := AManager.Find<THypothesis>(AId);
  if Result = nil then
    raise EHypothesisNotFound.CreateFmt('Hypothesis %d not found.', [AId]);
  // Find returns the identity-mapped instance as it was when this manager
  // first loaded it. Managers live for a whole MCP session / desktop run, so
  // reload it: every status check must see what is committed now.
  if WasCached then
    AManager.Refresh(Result);
end;

class procedure THypothesisModel.CheckVersion(H: THypothesis;
  AExpectedVersion: Integer);
begin
  if H.Version <> AExpectedVersion then
    raise EHypothesisConflict.Create(H.Version);
end;

class function THypothesisModel.RunsOf(AManager: TObjectManager;
  AId: Integer): TArray<THypothesisRun>;
var
  L: TList<THypothesisRun>;
begin
  // Refreshing: VerifySeal and the Accept hash must see a run row exactly as
  // committed now, not a copy this long-lived manager cached earlier.
  L := AManager.Find<THypothesisRun>.Where(Linq['HypothesisId'] = AId).Refreshing.List;
  try
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

class function THypothesisModel.EvidenceOf(AManager: TObjectManager;
  AId: Integer): TArray<THypothesisEvidence>;
var
  L: TList<THypothesisEvidence>;
begin
  // Refreshing: same reason as RunsOf -- an evidence row's Note (or any other
  // field) edited by another session must not be invisible to the seal.
  L := AManager.Find<THypothesisEvidence>.Where(Linq['HypothesisId'] = AId).Refreshing.List;
  try
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

procedure THypothesisModel.RequireWrite(AUser: TUser; AProjectId: Integer);
var
  V: TProjectWriteVerdict;
begin
  V := FAccess.CheckWrite(FManager, AUser, AProjectId);
  if V <> pwAllowed then
    raise EHypothesisAccess.Create(WriteVerdictText(V));
end;

procedure THypothesisModel.RequireRead(AUser: TUser; AProjectId: Integer);
begin
  if not FAccess.CanRead(FManager, AUser, AProjectId) then
    raise EHypothesisAccess.Create('You cannot read that project.');
end;

function THypothesisModel.LiveItemProjectId(AItemId: Integer): Integer;
var
  Live: TLiveRows;
  It: TLiveItem;
begin
  Live := TLiveRows.Create(FManager, [AItemId], nil, nil);
  try
    if (not Live.Items.TryGetValue(AItemId, It)) or It.IsDeleted then
      raise EHypothesisNotFound.CreateFmt('Item %d not found.', [AItemId]);
    if It.IsFolder then
      raise EHypothesisError.Create(hrNotAllowed, Format(
        'Item %d is a folder; attach or cite a Proc, Item or Action instead.', [AItemId]));
    Result := It.ProjectId;
  finally
    Live.Free;
  end;
end;

function THypothesisModel.ActorsFor(AUser: TUser; H: THypothesis): THypActors;
var
  Reason: string;
begin
  Result := [];
  if AUser = nil then
    Exit;
  if H.CreatedBy = AUser.Id then
    Include(Result, haAuthor);
  if FAccess.CanWrite(FManager, AUser, H.ProjectId) then
    Include(Result, haWriter);
  if FAccess.CanPassGate(FManager, AUser, H, hgApproveProposals, Reason) then
    Include(Result, haProposalApprover);
  if FAccess.CanPassGate(FManager, AUser, H, hgAcceptConclusions, Reason) then
    Include(Result, haConclusionApprover);
end;

class function THypothesisModel.AllowedGateTargetsFor(AManager: TObjectManager;
  AUser: TUser; H: THypothesis; const AAccess: IProjectAccessPolicy): TArray<THypothesisStatus>;
var
  Gates: TGateEligibility;
begin
  Gates := AAccess.CreateGateEligibility(AManager, AUser);
  try
    Result := AllowedGateTargetsFor(Gates, H);
  finally
    Gates.Free;
  end;
end;

class function THypothesisModel.AllowedGateTargetsFor(AGates: TGateEligibility;
  H: THypothesis): TArray<THypothesisStatus>;
var
  L: TList<THypothesisStatus>;
  T: THypothesisStatus;
  Gate: THypothesisGate;
  Reason: string;
begin
  L := TList<THypothesisStatus>.Create;
  try
    for T := Low(THypothesisStatus) to High(THypothesisStatus) do
      if GateOfTransition(H.Status, T, Gate) and
         AGates.CanPassGate(H.ProjectId, H.CreatedBy, Gate, Reason) then
        L.Add(T);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

class function THypothesisModel.SealStateOf(AManager: TObjectManager;
  H: THypothesis): THypSealState;
begin
  if H.Status <> hsAccepted then
    Exit(hssNone);
  // The Accept gate always writes a hash, so an Accepted row without one can
  // only come from an edit outside the model - and blanking the hash is the
  // easiest way to hide an edited conclusion. Tampered, not none.
  if H.ContentHash = '' then
    Exit(hssTampered);
  if SameText(H.ContentHash, ComputeHypothesisHash(H,
       RunsOf(AManager, H.Id), EvidenceOf(AManager, H.Id))) then
    Result := hssIntact
  else
    Result := hssTampered;
end;

procedure THypothesisModel.Discard(AObj: TObject);
begin
  if AObj = nil then
    Exit;
  try
    FManager.Evict(AObj);
  except
    // not attached - nothing to undo in the identity map
  end;
  AObj.Free;
end;

class procedure THypothesisModel.UnwindFailedWrite(AManager: TObjectManager;
  const ATrans: IDBTransaction; H: THypothesis; AError: Exception);
var
  OurVersion: Integer;
begin
  // Called from an except block, before the caller re-raises: undo the
  // database side, put H back to the committed row (the caller may hold it),
  // and report a lost optimistic lock in the model's own terms.
  //
  // On a lost connection Rollback and Refresh raise too. Neither secondary
  // error may replace the caller's, and H must not stay in the shared manager
  // dirty with the failed write: a later, unrelated Flush would commit it
  // with no history and no audit row. If H cannot be
  // reloaded, detach it; the manager still owns and frees it, so a caller
  // holding H keeps a valid object, and the next Load reads the row afresh.
  // A deleted row does not make Refresh fail (Aurelius ignores zero rows):
  // when H's row was deleted and H is the entity that lost the lock,
  // ReloadConflicted has already detached H, and Refresh then raises
  // (H is no longer mapped) into the same detach path, which is harmless.
  //
  // Flush is global: the optimistic lock that failed may be another dirty
  // entity's in this shared manager. It is a hypothesis
  // conflict only when the committed row, re-read after the rollback, is
  // NEWER than our copy. Our copy is V when our UPDATE of H lost the lock or
  // never ran, V+1 when it went through before another entity failed (the
  // rollback then puts the row back to V). Not read inside the failed
  // transaction: under MySQL's REPEATABLE READ that snapshot predates the
  // other client's commit. Any other conflict is reported as
  // EHypothesisOtherRecordChanged, after reloading the stale entity so a
  // retry can succeed.
  OurVersion := 0;
  if H <> nil then
    OurVersion := H.Version;
  try
    ATrans.Rollback;
  except
  end;
  TConflictHandler.ReloadConflicted(AManager, AError);
  if H = nil then
    Exit;
  try
    AManager.Refresh(H);
  except
    try
      AManager.Evict(H);
      AManager.AddOwnership(H);
    except
    end;
    Exit;
  end;
  if AError is EVersionedConcurrencyControl then
    if H.Version > OurVersion then
      raise EHypothesisConflict.Create(H.Version)
    else
      raise EHypothesisOtherRecordChanged.Create;
end;

procedure THypothesisModel.WriteStatus(H: THypothesis;
  ANew: THypothesisStatus; AUser: TUser; ADeviceId: Integer;
  const AComment: string; out AChange: THypothesisStatusChange);
begin
  AChange := nil;
  // Guard: this model owns the two non-gate status
  // moves only. A gate status written from here would bypass the approval
  // policy, whatever the caller checked beforehand.
  if not (ANew in [hsInReview, hsAbandoned]) then
    raise EHypothesisError.Create(hrNotAllowed, Format(
      'THypothesisModel cannot set status %s.', [HypothesisStatusNames[ANew]]));
  // Refused, never cut: a truncated reason reads as the whole one.
  if HypCommentLength(AComment) > MAX_HYP_COMMENT then
    raise EHypothesisError.Create(hrCommentTooLong);
  // AChange is an "out" param, not a function result: it must already point
  // at the caller's variable the instant it is created, so a caller's
  // except block can Discard() it even if Save/Flush below raises.
  AChange := THypothesisStatusChange.Create;
  AChange.HypothesisId := H.Id;
  AChange.OldStatus := H.Status;
  AChange.NewStatus := ANew;
  AChange.ChangedBy := AUser.Id;
  if ADeviceId > 0 then
    AChange.ChangedDeviceId := ADeviceId;
  AChange.ChangedDate := UTCNow;
  AChange.Comment := AComment;
  H.Status := ANew;
  H.MarkModified(UTCNow);
  FManager.Save(AChange);
  FManager.Flush;
end;

function THypothesisModel.Propose(AUser: TUser; ADeviceId, AProjectId,
  AParentId: Integer; const ATitle, AStatement, AChange: string;
  AKeyValueTypeId: Integer): THypothesis;
var
  R: THypRefusal;
  Parent, H: THypothesis;
  C: THypothesisStatusChange;
  Trans: IDBTransaction;
begin
  RequireWrite(AUser, AProjectId);
  R := CheckProposal(ATitle, AStatement, AChange, AParentId = 0);
  if R <> hrOk then
    raise EHypothesisError.Create(R);
  if Length(Trim(ATitle)) > MAX_TITLE then
    raise EHypothesisError.Create(hrNeedsTitle, 'The title is longer than 255 characters.');
  if AParentId <> 0 then
  begin
    Parent := Load(FManager, AParentId);
    if Parent.ProjectId <> AProjectId then
      raise EHypothesisError.Create(hrNotAllowed,
        'The parent hypothesis belongs to another project.');
    if Parent.Status in [hsRejected, hsAbandoned] then
      raise EHypothesisError.Create(hrNotAllowed,
        'A rejected or abandoned hypothesis cannot have children.');
  end;
  if (AKeyValueTypeId <> 0) and (FManager.Find<TValueType>(AKeyValueTypeId) = nil) then
    raise EHypothesisError.Create(hrNotAllowed,
      Format('Value type %d not found.', [AKeyValueTypeId]));

  H := nil;
  C := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := THypothesis.Create;
    H.ProjectId := AProjectId;
    if AParentId <> 0 then
      H.ParentId := AParentId;
    H.Title := Trim(ATitle);
    H.Statement := AStatement;
    H.Change := AChange;
    H.Status := hsProposed;
    if AKeyValueTypeId <> 0 then
      H.KeyValueTypeId := AKeyValueTypeId;
    H.CreatedBy := AUser.Id;
    if ADeviceId > 0 then
      H.CreatedDeviceId := ADeviceId;
    H.CreatedDate := UTCNow;
    FManager.Save(H);
    FManager.Flush;

    C := THypothesisStatusChange.Create;
    C.HypothesisId := H.Id;
    C.OldStatus := hsProposed;
    C.NewStatus := hsProposed;
    C.ChangedBy := AUser.Id;
    if ADeviceId > 0 then
      C.ChangedDeviceId := ADeviceId;
    C.ChangedDate := UTCNow;
    C.Comment := 'Proposed';
    FManager.Save(C);
    FManager.Flush;

    RecordAudit(FManager, aetHypothesis, H.Id, aoCreate, AUser.Id,
      'Proposed hypothesis "' + H.Title + '"');
    Trans.Commit;
  except
    try
      Trans.Rollback;   // raises too on a lost connection
    except
    end;
    Discard(C);
    Discard(H);
    raise;
  end;
  Result := H;
end;

procedure THypothesisModel.UpdateProposed(AUser: TUser; AId,
  AExpectedVersion: Integer; const ATitle, AStatement, AChange: string;
  AKeyValueTypeId: Integer);
var
  H: THypothesis;
  R: THypRefusal;
  Trans: IDBTransaction;
begin
  H := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := Load(FManager, AId);
    RequireWrite(AUser, H.ProjectId);
    CheckVersion(H, AExpectedVersion);
    if EditableFields(H.Status, ActorsFor(AUser, H)) = [] then
      raise EHypothesisError.Create(hrLocked,
        'Only the author can edit a hypothesis, and only while it is Proposed.');
    R := CheckProposal(ATitle, AStatement, AChange, not H.ParentId.HasValue);
    if R <> hrOk then
      raise EHypothesisError.Create(R);
    if Length(Trim(ATitle)) > MAX_TITLE then
      raise EHypothesisError.Create(hrNeedsTitle, 'The title is longer than 255 characters.');
    if (AKeyValueTypeId <> 0) and (FManager.Find<TValueType>(AKeyValueTypeId) = nil) then
      raise EHypothesisError.Create(hrNotAllowed,
        Format('Value type %d not found.', [AKeyValueTypeId]));

    H.Title := Trim(ATitle);
    H.Statement := AStatement;
    H.Change := AChange;
    if AKeyValueTypeId <> 0 then
      H.KeyValueTypeId := AKeyValueTypeId
    else
      H.KeyValueTypeId := SNull;
    H.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id,
      'Edited proposal "' + H.Title + '"');
    Trans.Commit;
  except
    // H is a persistent, identity-mapped entity the caller may still hold:
    // UnwindFailedWrite reloads it rather than leaving it out of sync with a
    // Flush that did not take effect.
    on E: Exception do
    begin
      UnwindFailedWrite(FManager, Trans, H, E);
      raise;
    end;
  end;
end;

function THypothesisModel.AttachRun(AUser: TUser; AId, AItemId: Integer;
  ARole: THypothesisRunRole): THypothesisRun;
var
  H: THypothesis;
  ItemProjectId: Integer;
  Existing: TList<THypothesisRun>;
  Trans: IDBTransaction;
begin
  H := nil;
  Result := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := Load(FManager, AId);
    RequireWrite(AUser, H.ProjectId);
    if ARole = hrrReference then
    begin
      if not CanChangeReferences(H.Status, ActorsFor(AUser, H)) then
        raise EHypothesisError.Create(hrLocked,
          'References can be added by the author while Proposed, or by any writer while Approved.');
    end
    else if not CanChangeRunsOrEvidence(H.Status) then
      raise EHypothesisError.Create(hrLocked,
        'Runs and evidence can only change while the hypothesis is Approved.');
    ItemProjectId := LiveItemProjectId(AItemId);
    if (ARole = hrrRun) and (ItemProjectId <> H.ProjectId) then
      raise EHypothesisError.Create(hrNotAllowed,
        'A Run item must belong to the hypothesis''s project; attach it as a Reference instead.');
    if ARole = hrrReference then
      RequireRead(AUser, ItemProjectId);
    Existing := FManager.Find<THypothesisRun>
      .Where((Linq['HypothesisId'] = AId) and (Linq['ItemId'] = AItemId)).List;
    try
      if Existing.Count > 0 then
        raise EHypothesisError.Create(hrNotAllowed,
          Format('Item %d is already attached to this hypothesis.', [AItemId]));
    finally
      Existing.Free;
    end;

    Result := THypothesisRun.Create;
    Result.HypothesisId := AId;
    Result.ItemId := AItemId;
    Result.Role := ARole;
    Result.AddedBy := AUser.Id;
    Result.AddedDate := UTCNow;
    FManager.Save(Result);
    H.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id,
      Format('Attached item %d as %s', [AItemId, HypothesisRunRoleNames[ARole]]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Discard(Result);
      UnwindFailedWrite(FManager, Trans, H, E);
      raise;
    end;
  end;
end;

procedure THypothesisModel.DetachRun(AUser: TUser; AId, AItemId: Integer);
var
  H: THypothesis;
  L: TList<THypothesisRun>;
  Run: THypothesisRun;
  Trans: IDBTransaction;
begin
  H := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := Load(FManager, AId);
    RequireWrite(AUser, H.ProjectId);
    L := FManager.Find<THypothesisRun>
      .Where((Linq['HypothesisId'] = AId) and (Linq['ItemId'] = AItemId)).List;
    try
      if L.Count = 0 then
        raise EHypothesisNotFound.CreateFmt('Item %d is not attached.', [AItemId]);
      Run := L[0];
      if Run.Role = hrrReference then
      begin
        if not CanChangeReferences(H.Status, ActorsFor(AUser, H)) then
          raise EHypothesisError.Create(hrLocked,
            'References can be removed by the author while Proposed, or by any writer while Approved.');
      end
      else if not CanChangeRunsOrEvidence(H.Status) then
        raise EHypothesisError.Create(hrLocked,
          'Runs and evidence can only change while the hypothesis is Approved.');
      // Remove runs the DELETE at once and, when it succeeds, the manager
      // frees Run; so Run is never touched again below or in the except
      // block. After a rollback the row is back and the next query reloads it.
      FManager.Remove(Run);
    finally
      L.Free;
    end;
    H.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id,
      Format('Detached item %d', [AItemId]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      UnwindFailedWrite(FManager, Trans, H, E);
      raise;
    end;
  end;
end;

function THypothesisModel.CiteEvidence(AUser: TUser; AId, AItemId: Integer;
  AFileId: Int64; AValueId: Integer; const ANote: string): THypothesisEvidence;
var
  H: THypothesis;
  Live: TLiveRows;
  LF: TLiveFile;
  LV: TLiveValue;
  Trans: IDBTransaction;
begin
  H := nil;
  Result := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := Load(FManager, AId);
    RequireWrite(AUser, H.ProjectId);
    if not CanChangeRunsOrEvidence(H.Status) then
      raise EHypothesisError.Create(hrLocked,
        'Runs and evidence can only change while the hypothesis is Approved.');
    if (AFileId <> 0) and (AValueId <> 0) then
      raise EHypothesisError.Create(hrNotAllowed, 'Cite a file or a value, not both.');
    if Length(ANote) > MAX_NOTE then
      raise EHypothesisError.Create(hrNotAllowed, 'The note is longer than 500 characters.');
    RequireRead(AUser, LiveItemProjectId(AItemId));

    Result := THypothesisEvidence.Create;
    Result.HypothesisId := AId;
    Result.ItemId := AItemId;
    Result.Note := ANote;
    Result.AddedBy := AUser.Id;
    Result.AddedDate := UTCNow;
    if (AFileId <> 0) or (AValueId <> 0) then
    begin
      // Fresh rows: the hash/value copied here is sealed by Accept.
      if AFileId <> 0 then
        Live := TLiveRows.Create(FManager, nil, [AFileId], nil)
      else
        Live := TLiveRows.Create(FManager, nil, nil, [AValueId]);
      try
        if AFileId <> 0 then
        begin
          if (not Live.Files.TryGetValue(AFileId, LF)) or (LF.ItemId <> AItemId) then
            raise EHypothesisError.Create(hrNotAllowed,
              Format('File %d does not belong to item %d.', [AFileId, AItemId]));
          Result.FileId := AFileId;
          Result.FileHash := LF.Hash;       // copied by the server, never supplied
        end
        else
        begin
          if (not Live.Values.TryGetValue(AValueId, LV)) or (LV.ItemId <> AItemId) then
            raise EHypothesisError.Create(hrNotAllowed,
              Format('Value %d does not belong to item %d.', [AValueId, AItemId]));
          Result.ValueId := AValueId;
          Result.ValueSnapshot := LV.Value; // copied by the server, never supplied
        end;
      finally
        Live.Free;
      end;
    end;
    FManager.Save(Result);
    H.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id,
      Format('Cited evidence from item %d', [AItemId]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      Discard(Result);
      UnwindFailedWrite(FManager, Trans, H, E);
      raise;
    end;
  end;
end;

procedure THypothesisModel.RemoveEvidence(AUser: TUser; AId, AEvidenceId: Integer);
var
  H: THypothesis;
  E: THypothesisEvidence;
  Trans: IDBTransaction;
begin
  H := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := Load(FManager, AId);
    RequireWrite(AUser, H.ProjectId);
    if not CanChangeRunsOrEvidence(H.Status) then
      raise EHypothesisError.Create(hrLocked,
        'Runs and evidence can only change while the hypothesis is Approved.');
    // A query, as in DetachRun, not Find(Id): that returns the cached copy
    // of a row another session has already deleted, and removing it again
    // would bump Version and write an audit row for nothing.
    E := FManager.Find<THypothesisEvidence>
      .Where((Linq['Id'] = AEvidenceId) and (Linq['HypothesisId'] = AId))
      .UniqueResult;
    if E = nil then
      raise EHypothesisNotFound.CreateFmt('Evidence %d not found on this hypothesis.', [AEvidenceId]);
    // As in DetachRun: a successful Remove frees E; never touch it again.
    FManager.Remove(E);
    H.MarkModified(UTCNow);
    FManager.Flush;
    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id,
      Format('Removed evidence %d', [AEvidenceId]));
    Trans.Commit;
  except
    on Ex: Exception do
    begin
      UnwindFailedWrite(FManager, Trans, H, Ex);
      raise;
    end;
  end;
end;

procedure THypothesisModel.SubmitConclusion(AUser: TUser; ADeviceId, AId,
  AExpectedVersion: Integer; const AConclusion: string;
  AOutcome: THypothesisOutcome);
var
  H: THypothesis;
  R: THypRefusal;
  C: THypothesisStatusChange;
  Trans: IDBTransaction;
begin
  H := nil;
  C := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := Load(FManager, AId);
    RequireWrite(AUser, H.ProjectId);
    CheckVersion(H, AExpectedVersion);
    R := CheckTransition(H.Status, hsInReview, ActorsFor(AUser, H),
      THypFacts.Make(False, Trim(AConclusion) <> '', True,
        Length(EvidenceOf(FManager, AId))));
    if R <> hrOk then
      raise EHypothesisError.Create(R);
    H.Conclusion := AConclusion;
    H.Outcome := AOutcome;
    WriteStatus(H, hsInReview, AUser, ADeviceId, 'Conclusion submitted', C);
    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id,
      'Submitted conclusion (' + HypothesisOutcomeNames[AOutcome] + ')');
    Trans.Commit;
  except
    on E: Exception do
    begin
      Discard(C);
      UnwindFailedWrite(FManager, Trans, H, E);
      raise;
    end;
  end;
end;

procedure THypothesisModel.Abandon(AUser: TUser; ADeviceId, AId, AExpectedVersion: Integer;
  const AComment: string);
var
  H: THypothesis;
  R: THypRefusal;
  C: THypothesisStatusChange;
  Trans: IDBTransaction;
begin
  H := nil;
  C := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H := Load(FManager, AId);
    RequireWrite(AUser, H.ProjectId);
    CheckVersion(H, AExpectedVersion);
    R := CheckTransition(H.Status, hsAbandoned, ActorsFor(AUser, H),
      THypFacts.Make(Trim(AComment) <> '', False, False, 0));
    if R <> hrOk then
      raise EHypothesisError.Create(R);
    WriteStatus(H, hsAbandoned, AUser, ADeviceId, AComment, C);
    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id,
      'Abandoned: ' + AComment);
    Trans.Commit;
  except
    on E: Exception do
    begin
      Discard(C);
      UnwindFailedWrite(FManager, Trans, H, E);
      raise;
    end;
  end;
end;

class function THypothesisFilter.All: THypothesisFilter;
begin
  Result := Default(THypothesisFilter);
end;

function DeriveState(H: THypothesis; ARunCount, AEvidenceCount: Integer): THypDerivedState;
begin
  if H.Status <> hsApproved then Exit(hdsNone);
  if ARunCount = 0 then Exit(hdsToMake);
  if AEvidenceCount = 0 then Exit(hdsWaitingForMeasurement);
  Result := hdsReadyToConclude;
end;

const
  // Ids per IN (...) list: far below every driver's parameter limit (999 on
  // old SQLite builds), so a very big project costs a few more statements
  // rather than failing.
  IN_CHUNK = 500;

type
  TValueKey = TPair<Integer, Integer>;

  // Batch facts by IN_CHUNK rather than query per node. Refresh run entities;
  // project counts and values to bypass stale session identity-map copies.
  THypListFacts = class
  private
    FRuns: TObjectDictionary<Integer, TList<THypothesisRun>>;  // lists do not own the runs
    FEvidence: TDictionary<Integer, Integer>;
    FValues: TObjectDictionary<TValueKey, TList<Double>>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadRunsAndEvidence(AManager: TObjectManager; const AIds: TArray<Integer>);
    procedure SetRuns(AHypId: Integer; const ARuns: TArray<THypothesisRun>);
    // The values of each node's key-value type over its Run items, for
    // every node in AHyps. Call once the runs are known. Only items whose
    // CURRENT project AUser can read and AScope allows count: a run moved
    // out of reach is redacted, so its values must not leak through n/mean.
    procedure LoadKeyValues(AManager: TObjectManager; const AHyps: TArray<THypothesis>;
      AUser: TUser; const AScope: TArray<Integer>; const AAccess: IProjectAccessPolicy);
    function RunsOf(AHypId: Integer): TArray<THypothesisRun>;
    function EvidenceCountOf(AHypId: Integer): Integer;
    function KeyValueOver(H: THypothesis;
      const ARuns: TArray<THypothesisRun>): TKeyValueSummary;
  end;

function VariantChunks(const AIds: TArray<Variant>): TArray<TArray<Variant>>;
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

function IdChunks(const AIds: TArray<Integer>): TArray<TArray<Variant>>; overload;
var
  V: TArray<Variant>;
  I: Integer;
begin
  SetLength(V, Length(AIds));
  for I := 0 to High(AIds) do
    V[I] := AIds[I];
  Result := VariantChunks(V);
end;

function IdChunks(const AIds: TArray<Int64>): TArray<TArray<Variant>>; overload;
var
  V: TArray<Variant>;
  I: Integer;
begin
  SetLength(V, Length(AIds));
  for I := 0 to High(AIds) do
    V[I] := AIds[I];
  Result := VariantChunks(V);
end;


constructor TLiveRows.Create(AManager: TObjectManager;
  const AItemIds: TArray<Integer>; const AFileIds: TArray<Int64>;
  const AValueIds: TArray<Integer>);
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  It: TLiveItem;
  LF: TLiveFile;
  LV: TLiveValue;
begin
  inherited Create;
  Items := TDictionary<Integer, TLiveItem>.Create;
  Files := TDictionary<Int64, TLiveFile>.Create;
  Values := TDictionary<Integer, TLiveValue>.Create;

  for Chunk in IdChunks(AItemIds) do
  begin
    Rows := AManager.Find<TItem>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('Title').As_('Title'))
        .Add(TProjections.Prop('ProjectID').As_('ProjectId'))
        .Add(TProjections.Prop('IsDeleted').As_('IsDeleted'))
        .Add(TProjections.Prop('Level').As_('Level')))
      .Where(Linq['Id']._In(Chunk))
      .ListValues;
    try
      for Row in Rows do
      begin
        It.Title := VarToStr(Row.Values['Title']);
        It.ProjectId := Integer(Row.Values['ProjectId']);
        It.IsDeleted := Boolean(Row.Values['IsDeleted']);
        It.IsFolder := Integer(Row.Values['Level']) = Ord(TItemLevel.Folder);
        Items.AddOrSetValue(Integer(Row.Values['Id']), It);
      end;
    finally
      Rows.Free;
    end;
  end;

  // The join on the item: a file or value whose item row is gone is absent.
  for Chunk in IdChunks(AFileIds) do
  begin
    Rows := AManager.Find<unit_Item.TFile>
      .CreateAlias('Item', 'i')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('i.Id').As_('ItemId'))
        .Add(TProjections.Prop('Hash').As_('Hash')))
      .Where(Linq['Id']._In(Chunk))
      .ListValues;
    try
      for Row in Rows do
      begin
        LF.ItemId := Integer(Row.Values['ItemId']);
        LF.Hash := VarToStr(Row.Values['Hash']);
        Files.AddOrSetValue(Row.Values['Id'], LF);
      end;
    finally
      Rows.Free;
    end;
  end;

  for Chunk in IdChunks(AValueIds) do
  begin
    Rows := AManager.Find<TValue>
      .CreateAlias('Item', 'i')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('i.Id').As_('ItemId'))
        .Add(TProjections.Prop('Value').As_('V')))
      .Where(Linq['Id']._In(Chunk))
      .ListValues;
    try
      for Row in Rows do
      begin
        LV.ItemId := Integer(Row.Values['ItemId']);
        LV.Value := Double(Row.Values['V']);
        Values.AddOrSetValue(Integer(Row.Values['Id']), LV);
      end;
    finally
      Rows.Free;
    end;
  end;
end;

destructor TLiveRows.Destroy;
begin
  Values.Free;
  Files.Free;
  Items.Free;
  inherited;
end;

function InProjectScope(const AProjectIds: TArray<Integer>; AId: Integer): Boolean;
var
  X: Integer;
begin
  if Length(AProjectIds) = 0 then
    Exit(True);
  for X in AProjectIds do
    if X = AId then
      Exit(True);
  Result := False;
end;


constructor THypListFacts.Create;
begin
  inherited Create;
  FRuns := TObjectDictionary<Integer, TList<THypothesisRun>>.Create([doOwnsValues]);
  FEvidence := TDictionary<Integer, Integer>.Create;
  FValues := TObjectDictionary<TValueKey, TList<Double>>.Create([doOwnsValues]);
end;

destructor THypListFacts.Destroy;
begin
  FValues.Free;
  FEvidence.Free;
  FRuns.Free;
  inherited;
end;

procedure THypListFacts.SetRuns(AHypId: Integer; const ARuns: TArray<THypothesisRun>);
var
  L: TList<THypothesisRun>;
begin
  L := TList<THypothesisRun>.Create;
  L.AddRange(ARuns);
  FRuns.AddOrSetValue(AHypId, L);
end;

procedure THypListFacts.LoadRunsAndEvidence(AManager: TObjectManager;
  const AIds: TArray<Integer>);
var
  Chunk: TArray<Variant>;
  Runs, L: TList<THypothesisRun>;
  R: THypothesisRun;
  Counts: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  for Chunk in IdChunks(AIds) do
  begin
    // Refreshing, as in RunsOf. Ordered like the per-node read this replaces,
    // which the (HypothesisId, ItemId) unique index answers in ItemId order:
    // the key-value mean is summed in run order, so the order is part of the
    // result.
    Runs := AManager.Find<THypothesisRun>
      .Where(Linq['HypothesisId']._In(Chunk))
      .OrderBy('HypothesisId')
      .OrderBy('ItemId')
      .Refreshing
      .List;
    try
      for R in Runs do
      begin
        if not FRuns.TryGetValue(R.HypothesisId, L) then
        begin
          L := TList<THypothesisRun>.Create;
          FRuns.Add(R.HypothesisId, L);
        end;
        L.Add(R);
      end;
    finally
      Runs.Free;
    end;

    Counts := AManager.Find<THypothesisEvidence>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Group('HypothesisId').As_('HypId'))
        .Add(TProjections.Count('Id').As_('N')))
      .Where(Linq['HypothesisId']._In(Chunk))
      .ListValues;
    try
      for Row in Counts do
        FEvidence.AddOrSetValue(Integer(Row.Values['HypId']), Integer(Row.Values['N']));
    finally
      Counts.Free;
    end;
  end;
end;

procedure THypListFacts.LoadKeyValues(AManager: TObjectManager;
  const AHyps: TArray<THypothesis>; AUser: TUser; const AScope: TArray<Integer>;
  const AAccess: IProjectAccessPolicy);
var
  H: THypothesis;
  R: THypothesisRun;
  Items, Types, Readable: TDictionary<Integer, Boolean>;
  TypeIds: TArray<Variant>;
  T, I, Pid: Integer;
  Ok: Boolean;
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Key: TValueKey;
  L: TList<Double>;
begin
  Items := TDictionary<Integer, Boolean>.Create;
  Types := TDictionary<Integer, Boolean>.Create;
  Readable := TDictionary<Integer, Boolean>.Create;
  try
    for H in AHyps do
    begin
      if not H.KeyValueTypeId.HasValue then
        Continue;
      Types.AddOrSetValue(H.KeyValueTypeId.Value, True);
      for R in RunsOf(H.Id) do
        if R.Role = hrrRun then
          Items.AddOrSetValue(R.ItemId, True);
    end;
    if (Items.Count = 0) or (Types.Count = 0) then
      Exit;
    SetLength(TypeIds, Types.Count);
    I := 0;
    for T in Types.Keys do
    begin
      TypeIds[I] := T;
      Inc(I);
    end;

    for Chunk in IdChunks(Items.Keys.ToArray) do
    begin
      // The join on the item drops the values of a missing or soft-deleted
      // item, which the per-run read skipped too. Ordered by Id: the
      // per-item read this replaces returned an item's values in row order.
      Rows := AManager.Find<TValue>
        .CreateAlias('Item', 'i')
        .CreateAlias('ValueType', 'vt')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('i.Id').As_('ItemId'))
          .Add(TProjections.Prop('i.ProjectID').As_('ProjectId'))
          .Add(TProjections.Prop('vt.Id').As_('TypeId'))
          .Add(TProjections.Prop('Value').As_('V')))
        .Where(Linq['i.Id']._In(Chunk) and Linq['vt.Id']._In(TypeIds) and
               (Linq['i.IsDeleted'] = False))
        .OrderBy('Id')
        .ListValues;
      try
        for Row in Rows do
        begin
          Pid := Integer(Row.Values['ProjectId']);
          if not Readable.TryGetValue(Pid, Ok) then
          begin
            Ok := InProjectScope(AScope, Pid) and
              AAccess.CanRead(AManager, AUser, Pid);
            Readable.Add(Pid, Ok);
          end;
          if not Ok then
            Continue;
          Key := TValueKey.Create(Integer(Row.Values['ItemId']), Integer(Row.Values['TypeId']));
          if not FValues.TryGetValue(Key, L) then
          begin
            L := TList<Double>.Create;
            FValues.Add(Key, L);
          end;
          L.Add(Double(Row.Values['V']));
        end;
      finally
        Rows.Free;
      end;
    end;
  finally
    Readable.Free;
    Types.Free;
    Items.Free;
  end;
end;

function THypListFacts.RunsOf(AHypId: Integer): TArray<THypothesisRun>;
var
  L: TList<THypothesisRun>;
begin
  if FRuns.TryGetValue(AHypId, L) then
    Result := L.ToArray
  else
    Result := nil;
end;

function THypListFacts.EvidenceCountOf(AHypId: Integer): Integer;
begin
  if not FEvidence.TryGetValue(AHypId, Result) then
    Result := 0;
end;

function THypListFacts.KeyValueOver(H: THypothesis;
  const ARuns: TArray<THypothesisRun>): TKeyValueSummary;
var
  R: THypothesisRun;
  L: TList<Double>;
  V, Sum: Double;
begin
  Result := Default(TKeyValueSummary);
  if not H.KeyValueTypeId.HasValue then
    Exit;
  Sum := 0;
  for R in ARuns do
  begin
    if R.Role <> hrrRun then
      Continue;
    // No entry: a missing or soft-deleted item, or no values of the type.
    if not FValues.TryGetValue(TValueKey.Create(R.ItemId, H.KeyValueTypeId.Value), L) then
      Continue;
    for V in L do
    begin
      if Result.N = 0 then
      begin
        Result.Min := V;
        Result.Max := V;
      end
      else
      begin
        if V < Result.Min then Result.Min := V;
        if V > Result.Max then Result.Max := V;
      end;
      Sum := Sum + V;
      Inc(Result.N);
    end;
  end;
  if Result.N > 0 then
    Result.Mean := Sum / Result.N;
end;

function Summarize(H: THypothesis; const ARuns: TArray<THypothesisRun>;
  AEvidenceCount: Integer; AFacts: THypListFacts): THypothesisSummary;
var
  R: THypothesisRun;
begin
  Result := Default(THypothesisSummary);
  Result.Id := H.Id;
  Result.ProjectId := H.ProjectId;
  if H.ParentId.HasValue then Result.ParentId := H.ParentId.Value;
  Result.CreatedBy := H.CreatedBy;
  Result.Version := H.Version;
  Result.Title := H.Title;
  Result.Status := H.Status;
  Result.CreatedDate := H.CreatedDate;
  if H.ModifiedDate.HasValue then Result.ModifiedDate := H.ModifiedDate.Value;
  // Run rows only: a Reference is not a run (spec 5.2 "no Run rows -> to
  // make"; review #13). Derived state, the to_make filters and every
  // run_count on the wire follow from this one count.
  for R in ARuns do
    if R.Role = hrrRun then
      Inc(Result.RunCount);
  Result.EvidenceCount := AEvidenceCount;
  Result.Derived := DeriveState(H, Result.RunCount, AEvidenceCount);
  if H.KeyValueTypeId.HasValue then
    Result.KeyValueTypeId := H.KeyValueTypeId.Value;
  Result.KeyValue := AFacts.KeyValueOver(H, ARuns);
end;

// ARoot and every descendant among AAll, through a parent -> children map
// built in one pass: O(n), where the fixed-point loop it replaced was
// O(n^2 * depth). ARoot itself is in the set whether or not it is in AAll.
procedure CollectSubtree(AAll: TList<THypothesis>; ARoot: Integer;
  AInTree: TDictionary<Integer, Boolean>);
var
  Children: TObjectDictionary<Integer, TList<Integer>>;
  Kids: TList<Integer>;
  Queue: TList<Integer>;
  H: THypothesis;
  I, Kid: Integer;
begin
  AInTree.Clear;
  Children := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  Queue := TList<Integer>.Create;
  try
    for H in AAll do
      if H.ParentId.HasValue then
      begin
        if not Children.TryGetValue(H.ParentId.Value, Kids) then
        begin
          Kids := TList<Integer>.Create;
          Children.Add(H.ParentId.Value, Kids);
        end;
        Kids.Add(H.Id);
      end;
    AInTree.Add(ARoot, True);
    Queue.Add(ARoot);
    I := 0;
    while I < Queue.Count do
    begin
      if Children.TryGetValue(Queue[I], Kids) then
        for Kid in Kids do
          if not AInTree.ContainsKey(Kid) then
          begin
            AInTree.Add(Kid, True);
            Queue.Add(Kid);
          end;
      Inc(I);
    end;
  finally
    Queue.Free;
    Children.Free;
  end;
end;

function THypothesisModel.ReadableProjectIds(AUser: TUser;
  const AFilter: THypothesisFilter): TArray<Integer>;
var
  Projects: TList<TProject>;
  Pr: TProject;
  L: TList<Integer>;
begin
  L := TList<Integer>.Create;
  try
    if AFilter.ProjectId <> 0 then
    begin
      if InProjectScope(AFilter.ProjectIds, AFilter.ProjectId) and
         FAccess.CanRead(FManager, AUser, AFilter.ProjectId) then
        L.Add(AFilter.ProjectId);
    end
    else
    begin
      Projects := FManager.Find<TProject>.List;
      try
        for Pr in Projects do
          if InProjectScope(AFilter.ProjectIds, Pr.Id) and
             FAccess.CanRead(FManager, AUser, Pr.Id) then
            L.Add(Pr.Id);
      finally
        Projects.Free;
      end;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

// Sort a copy for summation: Get and List must add doubles in the same order.
// Keep RunsOf ordering unchanged because it also feeds the acceptance seal.
function RunsSortedByItemId(const ARuns: TArray<THypothesisRun>): TArray<THypothesisRun>;
begin
  Result := Copy(ARuns);
  TArray.Sort<THypothesisRun>(Result, TComparer<THypothesisRun>.Construct(
    function(const L, R: THypothesisRun): Integer
    begin
      Result := L.ItemId - R.ItemId;
    end));
end;

function THypothesisModel.Get(AUser: TUser; AId: Integer;
  const AProjectScope: TArray<Integer>): THypothesisDetail;
var
  H: THypothesis;
  Runs: TArray<THypothesisRun>;
  Ev: TArray<THypothesisEvidence>;
  I: Integer;
  ItemIds, ValueIds: TArray<Integer>;
  FileIds: TArray<Int64>;
  Live: TLiveRows;
  It: TLiveItem;
  LF: TLiveFile;
  LV: TLiveValue;
  Hist: TList<THypothesisStatusChange>;
  Kids: TList<THypothesis>;
  Facts: THypListFacts;
begin
  H := Load(FManager, AId);
  if not FAccess.CanRead(FManager, AUser, H.ProjectId) then
    raise EHypothesisAccess.Create('You cannot read this hypothesis.');
  Runs := RunsOf(FManager, AId);
  Ev := EvidenceOf(FManager, AId);

  Result := Default(THypothesisDetail);
  Facts := THypListFacts.Create;
  try
    Facts.SetRuns(AId, Runs);
    Facts.LoadKeyValues(FManager, TArray<THypothesis>.Create(H), AUser, AProjectScope, FAccess);
    Result.Summary := Summarize(H, RunsSortedByItemId(Runs), Length(Ev), Facts);
  finally
    Facts.Free;
  end;
  Result.Statement := H.Statement;
  Result.Change := H.Change;
  Result.Conclusion := H.Conclusion;
  Result.ContentHash := H.ContentHash;
  Result.HasOutcome := H.Outcome.HasValue;
  if Result.HasOutcome then Result.Outcome := H.Outcome.Value;
  if H.CreatedDeviceId.HasValue then Result.CreatedDeviceId := H.CreatedDeviceId.Value;
  Result.CreatedDate := H.CreatedDate;

  // Missing/Changed are judged against the rows as committed now, one
  // projection per entity type (TLiveRows), never the session-cached copies.
  ItemIds := nil;
  FileIds := nil;
  ValueIds := nil;
  for I := 0 to High(Runs) do
    ItemIds := ItemIds + [Runs[I].ItemId];
  for I := 0 to High(Ev) do
  begin
    ItemIds := ItemIds + [Ev[I].ItemId];
    if Ev[I].FileId.HasValue then
      FileIds := FileIds + [Ev[I].FileId.Value];
    if Ev[I].ValueId.HasValue then
      ValueIds := ValueIds + [Ev[I].ValueId.Value];
  end;
  Live := TLiveRows.Create(FManager, ItemIds, FileIds, ValueIds);
  try
    SetLength(Result.Runs, Length(Runs));
    for I := 0 to High(Runs) do
    begin
      Result.Runs[I].RunId := Runs[I].Id;
      Result.Runs[I].ItemId := Runs[I].ItemId;
      Result.Runs[I].Role := Runs[I].Role;
      Result.Runs[I].Missing := True;
      if Live.Items.TryGetValue(Runs[I].ItemId, It) then
      begin
        Result.Runs[I].Missing := It.IsDeleted;
        Result.Runs[I].ItemTitle := It.Title;
        Result.Runs[I].ItemProjectId := It.ProjectId;
      end;
    end;

    SetLength(Result.Evidence, Length(Ev));
    for I := 0 to High(Ev) do
    begin
      Result.Evidence[I].EvidenceId := Ev[I].Id;
      Result.Evidence[I].ItemId := Ev[I].ItemId;
      Result.Evidence[I].Note := Ev[I].Note;
      Result.Evidence[I].FileHash := Ev[I].FileHash;
      Result.Evidence[I].HasSnapshot := Ev[I].ValueSnapshot.HasValue;
      if Result.Evidence[I].HasSnapshot then
        Result.Evidence[I].ValueSnapshot := Ev[I].ValueSnapshot.Value;
      Result.Evidence[I].Missing := True;
      if Live.Items.TryGetValue(Ev[I].ItemId, It) then
      begin
        Result.Evidence[I].Missing := It.IsDeleted;
        Result.Evidence[I].ItemTitle := It.Title;
        Result.Evidence[I].ItemProjectId := It.ProjectId;
      end;
      if Ev[I].FileId.HasValue then
      begin
        Result.Evidence[I].FileId := Ev[I].FileId.Value;
        if (not Live.Files.TryGetValue(Ev[I].FileId.Value, LF)) or (LF.ItemId <> Ev[I].ItemId) then
          Result.Evidence[I].Missing := True
        else if not SameText(LF.Hash, Ev[I].FileHash) then
          Result.Evidence[I].Changed := True;
      end;
      if Ev[I].ValueId.HasValue then
      begin
        Result.Evidence[I].ValueId := Ev[I].ValueId.Value;
        if (not Live.Values.TryGetValue(Ev[I].ValueId.Value, LV)) or (LV.ItemId <> Ev[I].ItemId) then
          Result.Evidence[I].Missing := True
        else if (not Ev[I].ValueSnapshot.HasValue) or (LV.Value <> Ev[I].ValueSnapshot.Value) then
          Result.Evidence[I].Changed := True;
      end;
    end;
  finally
    Live.Free;
  end;

  // Explicit order (oldest first; Id breaks a same-timestamp tie): callers
  // read "the last row" as the latest change, and SQL gives no order without
  // an ORDER BY.
  Hist := FManager.Find<THypothesisStatusChange>
    .Where(Linq['HypothesisId'] = AId)
    .OrderBy('ChangedDate').OrderBy('Id').List;
  try
    SetLength(Result.History, Hist.Count);
    for I := 0 to Hist.Count - 1 do
    begin
      Result.History[I].OldStatus := Hist[I].OldStatus;
      Result.History[I].NewStatus := Hist[I].NewStatus;
      Result.History[I].ChangedBy := Hist[I].ChangedBy;
      if Hist[I].ChangedDeviceId.HasValue then
        Result.History[I].ChangedDeviceId := Hist[I].ChangedDeviceId.Value;
      Result.History[I].ChangedDate := Hist[I].ChangedDate;
      Result.History[I].Comment := Hist[I].Comment;
    end;
  finally
    Hist.Free;
  end;

  Kids := FManager.Find<THypothesis>.Where(Linq['ParentId'] = AId).List;
  try
    SetLength(Result.ChildIds, Kids.Count);
    for I := 0 to Kids.Count - 1 do
      Result.ChildIds[I] := Kids[I].Id;
  finally
    Kids.Free;
  end;
end;

function THypothesisModel.List(AUser: TUser;
  const AFilter: THypothesisFilter): TArray<THypothesisSummary>;
var
  Pid: Integer;
  All: TList<THypothesis>;
  H: THypothesis;
  InTree: TDictionary<Integer, Boolean>;
  Picked: TList<THypothesis>;
  Ids: TList<Integer>;
  Facts: THypListFacts;
  Out_: TList<THypothesisSummary>;
  S: THypothesisSummary;
begin
  Out_ := TList<THypothesisSummary>.Create;
  InTree := TDictionary<Integer, Boolean>.Create;
  Picked := TList<THypothesis>.Create;
  Ids := TList<Integer>.Create;
  try
    for Pid in ReadableProjectIds(AUser, AFilter) do
    begin
      // Refreshing: a long-lived manager must not list a status it cached
      // before another client moved the node on.
      All := FManager.Find<THypothesis>.Where(Linq['ProjectId'] = Pid).Refreshing.List;
      try
        if AFilter.RootId <> 0 then
          CollectSubtree(All, AFilter.RootId, InTree);
        Picked.Clear;
        Ids.Clear;
        for H in All do
        begin
          if (AFilter.RootId <> 0) and not InTree.ContainsKey(H.Id) then Continue;
          if (AFilter.AuthorId <> 0) and (H.CreatedBy <> AFilter.AuthorId) then Continue;
          if (AFilter.Statuses <> []) and not (H.Status in AFilter.Statuses) then Continue;
          Picked.Add(H);
          Ids.Add(H.Id);
        end;
        if Picked.Count = 0 then
          Continue;
        Facts := THypListFacts.Create;
        try
          Facts.LoadRunsAndEvidence(FManager, Ids.ToArray);
          Facts.LoadKeyValues(FManager, Picked.ToArray, AUser, AFilter.ProjectIds, FAccess);
          for H in Picked do
          begin
            S := Summarize(H, Facts.RunsOf(H.Id), Facts.EvidenceCountOf(H.Id), Facts);
            if (AFilter.DerivedStates <> []) and not (S.Derived in AFilter.DerivedStates) then Continue;
            Out_.Add(S);
          end;
        finally
          Facts.Free;
        end;
      finally
        All.Free;
      end;
    end;
    Result := Out_.ToArray;
  finally
    Ids.Free;
    Picked.Free;
    InTree.Free;
    Out_.Free;
  end;
end;

function THypothesisModel.Tree(AUser: TUser; AProjectId, ARootId: Integer;
  const AProjectScope: TArray<Integer>): TArray<THypothesisSummary>;
var
  Flt: THypothesisFilter;
begin
  Flt := THypothesisFilter.All;
  Flt.ProjectId := AProjectId;
  Flt.RootId := ARootId;
  Flt.ProjectIds := AProjectScope;
  Result := List(AUser, Flt);
end;

end.
