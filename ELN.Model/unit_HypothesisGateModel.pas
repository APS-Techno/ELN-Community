unit unit_HypothesisGateModel;

{ Human gate execution must remain outside MCP dependencies. Keep status,
  history and audit writes in this unit and in the same transaction. }

interface

uses
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_Hypothesis,
  unit_ProjectAccessPolicy;

type
  THypothesisGateModel = class
  private
    FManager: TObjectManager;
    FAccess: IProjectAccessPolicy;
    procedure DoGate(AUser: TUser; ADeviceId, AId, AExpectedVersion: Integer;
      ATo: THypothesisStatus; const AComment: string);
  public
    constructor Create(AManager: TObjectManager; const AAccess: IProjectAccessPolicy);
    procedure Approve(AUser: TUser; ADeviceId, AId, AExpectedVersion: Integer;
      const AComment: string);
    procedure Reject(AUser: TUser; ADeviceId, AId, AExpectedVersion: Integer;
      const AComment: string);
    procedure Accept(AUser: TUser; ADeviceId, AId, AExpectedVersion: Integer;
      const AComment: string);
    procedure ReturnForRework(AUser: TUser; ADeviceId, AId,
      AExpectedVersion: Integer; const AComment: string);
    procedure Transition(AUser: TUser; ADeviceId, AId, AExpectedVersion: Integer;
      ATo: THypothesisStatus; const AComment: string);
    function AllowedGateTargets(AUser: TUser; AId: Integer): TArray<THypothesisStatus>;
    function VerifySeal(AId: Integer): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Aurelius.Drivers.Interfaces,
  unit_AuditLog,
  unit_AuditHelper,
  unit_TimeHelper,
  unit_HypothesisRules,
  unit_HypothesisModel,
  unit_HypothesisHash,
  unit_HypothesisStatusChange;

constructor THypothesisGateModel.Create(AManager: TObjectManager;
  const AAccess: IProjectAccessPolicy);
begin
  inherited Create;
  if AAccess = nil then
    raise EArgumentNilException.Create('Access');
  FManager := AManager;
  FAccess := AAccess;
end;

procedure THypothesisGateModel.DoGate(AUser: TUser; ADeviceId, AId,
  AExpectedVersion: Integer; ATo: THypothesisStatus; const AComment: string);
var
  H: THypothesis;
  Gate: THypothesisGate;
  Reason: string;
  Actors: THypActors;
  R: THypRefusal;
  C: THypothesisStatusChange;
  Trans: IDBTransaction;
  OldStatus: THypothesisStatus;
begin
  // Refused, never cut: a truncated reject reason reads as the whole one.
  if HypCommentLength(AComment) > MAX_HYP_COMMENT then
    raise EHypothesisError.Create(hrCommentTooLong);
  H := THypothesisModel.Load(FManager, AId);
  THypothesisModel.CheckVersion(H, AExpectedVersion);
  if H.Status in FinalStatuses then
    raise EHypothesisError.Create(hrFinal, Format(
      'The hypothesis is %s; its status can no longer change.',
      [HypothesisStatusNames[H.Status]]));
  if not GateOfTransition(H.Status, ATo, Gate) then
    raise EHypothesisError.Create(hrNotAllowed, Format(
      '%s -> %s is not a gate transition.',
      [HypothesisStatusNames[H.Status], HypothesisStatusNames[ATo]]));
  if not FAccess.CanPassGate(FManager, AUser, H, Gate, Reason) then
    raise EHypothesisNotApprover.Create(Reason);

  if Gate = hgApproveProposals then
    Actors := [haProposalApprover]
  else
    Actors := [haConclusionApprover];
  R := CheckTransition(H.Status, ATo, Actors,
    THypFacts.Make(Trim(AComment) <> '', True, True, 1));
  if R <> hrOk then
    raise EHypothesisError.Create(R);

  OldStatus := H.Status;
  C := nil;
  Trans := FManager.Connection.BeginTransaction;
  try
    H.Status := ATo;
    H.MarkModified(UTCNow);
    if ATo = hsAccepted then
      H.ContentHash := ComputeHypothesisHash(H,
        THypothesisModel.RunsOf(FManager, AId),
        THypothesisModel.EvidenceOf(FManager, AId));
    FManager.Flush;

    C := THypothesisStatusChange.Create;
    C.HypothesisId := H.Id;
    C.OldStatus := OldStatus;
    C.NewStatus := ATo;
    C.ChangedBy := AUser.Id;
    if ADeviceId > 0 then
      C.ChangedDeviceId := ADeviceId;
    C.ChangedDate := UTCNow;
    C.Comment := AComment;
    FManager.Save(C);
    FManager.Flush;

    RecordAudit(FManager, aetHypothesis, H.Id, aoUpdate, AUser.Id, Format(
      '%s -> %s%s', [HypothesisStatusNames[OldStatus], HypothesisStatusNames[ATo],
      IfThen(Trim(AComment) <> '', ': ' + AComment, '')]));
    Trans.Commit;
  except
    on E: Exception do
    begin
      if Assigned(C) then
      begin
        try FManager.Evict(C); except end;
        C.Free;
      end;
      // Guarded rollback, then H back to the committed row (or detached when
      // the connection is gone); raises EHypothesisConflict when someone else
      // committed a change between Load and Flush.
      THypothesisModel.UnwindFailedWrite(FManager, Trans, H, E);
      raise;
    end;
  end;
end;

procedure THypothesisGateModel.Approve(AUser: TUser; ADeviceId, AId,
  AExpectedVersion: Integer; const AComment: string);
begin
  DoGate(AUser, ADeviceId, AId, AExpectedVersion, hsApproved, AComment);
end;

procedure THypothesisGateModel.Reject(AUser: TUser; ADeviceId, AId,
  AExpectedVersion: Integer; const AComment: string);
begin
  DoGate(AUser, ADeviceId, AId, AExpectedVersion, hsRejected, AComment);
end;

procedure THypothesisGateModel.Accept(AUser: TUser; ADeviceId, AId,
  AExpectedVersion: Integer; const AComment: string);
begin
  DoGate(AUser, ADeviceId, AId, AExpectedVersion, hsAccepted, AComment);
end;

procedure THypothesisGateModel.ReturnForRework(AUser: TUser; ADeviceId, AId,
  AExpectedVersion: Integer; const AComment: string);
begin
  DoGate(AUser, ADeviceId, AId, AExpectedVersion, hsApproved, AComment);
end;

procedure THypothesisGateModel.Transition(AUser: TUser; ADeviceId, AId,
  AExpectedVersion: Integer; ATo: THypothesisStatus; const AComment: string);
begin
  DoGate(AUser, ADeviceId, AId, AExpectedVersion, ATo, AComment);
end;

function THypothesisGateModel.AllowedGateTargets(AUser: TUser;
  AId: Integer): TArray<THypothesisStatus>;
begin
  Result := THypothesisModel.AllowedGateTargetsFor(FManager, AUser,
    THypothesisModel.Load(FManager, AId), FAccess);
end;

function THypothesisGateModel.VerifySeal(AId: Integer): Boolean;
begin
  Result := THypothesisModel.SealStateOf(FManager,
    THypothesisModel.Load(FManager, AId)) = hssIntact;
end;

end.
