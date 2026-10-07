unit unit_LocalProjectAccessPolicy;

interface

uses
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  unit_User,
  unit_Project,
  unit_Hypothesis,
  unit_ProjectAccessPolicy;

type
  TLocalProjectAccessPolicy = class(TInterfacedObject, IProjectAccessPolicy)
  private
    FPrincipalId: Integer;
    function CheckPrincipal(AManager: TObjectManager;
      AUser: TUser): TProjectWriteVerdict;
    function CheckProject(AManager: TObjectManager; AProjectId: Integer;
      AForWrite: Boolean): TProjectWriteVerdict;
  public
    constructor Create(APrincipalId: Integer);
    function CheckWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectWriteVerdict;
    function CanWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function CanRead(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function RemoveProject(AManager: TObjectManager; AUser: TUser;
      AProject: TProject): Boolean;
    function CanPassGate(AManager: TObjectManager; AUser: TUser;
      AHypothesis: THypothesis; AGate: THypothesisGate;
      out AReason: string): Boolean;
    function CreateGateEligibility(AManager: TObjectManager;
      AUser: TUser): TGateEligibility;
    function ProjectList(AManager: TObjectManager; AUser: TUser): TList<TProject>;
    function GetProjectAccess(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectAccess;
    function ProjectDataSetCriteria(AManager: TObjectManager;
      AUser: TUser): TCriteria<TProject>;
    function VisibleProjectIds(AManager: TObjectManager;
      AUser: TUser): TDictionary<Integer, Boolean>;
    function CanReviewProtocol(AManager: TObjectManager; AUser: TUser;
      AProjectId, AAuthorId: Integer): Boolean;
    function CanBrowseAllProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateTags(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanEditReferenceData(AManager: TObjectManager; AUser: TUser): Boolean;
    property PrincipalId: Integer read FPrincipalId;
  end;

implementation

uses
  System.SysUtils,
  System.Variants,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections;

type
  TLocalGateEligibility = class(TGateEligibility)
  private
    FAccess: IProjectAccessPolicy;
    FPrincipalId: Integer;
  public
    constructor Create(AManager: TObjectManager; AUser: TUser;
      const AAccess: IProjectAccessPolicy; APrincipalId: Integer);
    function CanPassGate(AProjectId, AAuthorId: Integer;
      AGate: THypothesisGate; out AReason: string): Boolean; override;
    function PolicyInvalid: Boolean; override;
    function PolicyError: string; override;
  end;

constructor TLocalProjectAccessPolicy.Create(APrincipalId: Integer);
begin
  inherited Create;
  if APrincipalId <= 0 then
    raise EArgumentOutOfRangeException.Create('PrincipalId must be positive.');
  FPrincipalId := APrincipalId;
end;

function TLocalProjectAccessPolicy.CheckPrincipal(AManager: TObjectManager;
  AUser: TUser): TProjectWriteVerdict;
var
  Rows: TObjectList<TCriteriaResult>;
begin
  if AUser = nil then
    Exit(pwNoUser);
  if AUser.IsArchived then
    Exit(pwUserArchived);
  if AUser.Id <> FPrincipalId then
    Exit(pwNoPermission);
  if AManager = nil then
    Exit(pwNoPermission);
  // Projections read committed facts without overwriting shared entity edits.
  Rows := AManager.Find<TUser>
    .Select(TProjections.ProjectionList
      .Add(TProjections.Prop('IsArchived').As_('Archived')))
    .Where(Linq['Id'] = FPrincipalId).ListValues;
  try
    if Rows.Count = 0 then
      Exit(pwNoUser);
    if VarIsNull(Rows[0].Values['Archived']) or
       Boolean(Rows[0].Values['Archived']) then
      Exit(pwUserArchived);
    Result := pwAllowed;
  finally
    Rows.Free;
  end;
end;

function TLocalProjectAccessPolicy.CheckProject(AManager: TObjectManager;
  AProjectId: Integer; AForWrite: Boolean): TProjectWriteVerdict;
var
  Rows: TObjectList<TCriteriaResult>;
begin
  Rows := AManager.Find<TProject>
    .CreateAlias('Owner', 'o')
    .Select(TProjections.ProjectionList
      .Add(TProjections.Prop('IsArchived').As_('Archived'))
      .Add(TProjections.Prop('o.Id').As_('OwnerId')))
    .Where(Linq['Id'] = AProjectId).ListValues;
  try
    if Rows.Count = 0 then
      Exit(pwProjectNotFound);
    if AForWrite and (VarIsNull(Rows[0].Values['Archived']) or
       Boolean(Rows[0].Values['Archived'])) then
      Exit(pwProjectArchived);
    if VarIsNull(Rows[0].Values['OwnerId']) or
       (Integer(Rows[0].Values['OwnerId']) <> FPrincipalId) then
      Exit(pwNoPermission);
    Result := pwAllowed;
  finally
    Rows.Free;
  end;
end;

function TLocalProjectAccessPolicy.CheckWrite(AManager: TObjectManager;
  AUser: TUser; AProjectId: Integer): TProjectWriteVerdict;
begin
  Result := CheckPrincipal(AManager, AUser);
  if Result = pwAllowed then
    Result := CheckProject(AManager, AProjectId, True);
end;

function TLocalProjectAccessPolicy.CanWrite(AManager: TObjectManager;
  AUser: TUser; AProjectId: Integer): Boolean;
begin
  Result := CheckWrite(AManager, AUser, AProjectId) = pwAllowed;
end;

function TLocalProjectAccessPolicy.CanRead(AManager: TObjectManager;
  AUser: TUser; AProjectId: Integer): Boolean;
begin
  Result := (CheckPrincipal(AManager, AUser) = pwAllowed) and
    (CheckProject(AManager, AProjectId, False) = pwAllowed);
end;

function TLocalProjectAccessPolicy.RemoveProject(AManager: TObjectManager;
  AUser: TUser; AProject: TProject): Boolean;
begin
  Result := (AProject <> nil) and CanRead(AManager, AUser, AProject.Id);
  if Result then
    AManager.Remove(AProject);
end;

function TLocalProjectAccessPolicy.CanPassGate(AManager: TObjectManager;
  AUser: TUser; AHypothesis: THypothesis; AGate: THypothesisGate;
  out AReason: string): Boolean;
var
  Eligibility: TGateEligibility;
begin
  AReason := '';
  if AHypothesis = nil then
  begin
    AReason := 'No hypothesis.';
    Exit(False);
  end;
  Eligibility := CreateGateEligibility(AManager, AUser);
  try
    Result := Eligibility.CanPassGate(AHypothesis.ProjectId,
      AHypothesis.CreatedBy, AGate, AReason);
  finally
    Eligibility.Free;
  end;
end;

function TLocalProjectAccessPolicy.CreateGateEligibility(
  AManager: TObjectManager; AUser: TUser): TGateEligibility;
begin
  Result := TLocalGateEligibility.Create(AManager, AUser, Self, FPrincipalId);
end;

function TLocalProjectAccessPolicy.ProjectList(AManager: TObjectManager;
  AUser: TUser): TList<TProject>;
begin
  if CheckPrincipal(AManager, AUser) <> pwAllowed then
    Exit(TList<TProject>.Create);
  Result := AManager.Find<TProject>.Where(Linq['Owner.Id'] = FPrincipalId)
    .OrderBy('SortOrder').OrderBy('ID').List;
end;

function TLocalProjectAccessPolicy.GetProjectAccess(AManager: TObjectManager;
  AUser: TUser; AProjectId: Integer): TProjectAccess;
begin
  // Ownership permits archive restore and permanent empty-archive cleanup.
  // Scientific content writes and human gates still require CanWrite.
  if CanRead(AManager, AUser, AProjectId) then
    Result := paOwner
  else
    Result := paReadOnly;
end;

function TLocalProjectAccessPolicy.ProjectDataSetCriteria(
  AManager: TObjectManager; AUser: TUser): TCriteria<TProject>;
begin
  Result := AManager.Find<TProject>;
  if CheckPrincipal(AManager, AUser) = pwAllowed then
    Result.Where(Linq['Owner.Id'] = FPrincipalId)
  else
    Result.Where(Linq['Id'] = -1);
end;

function TLocalProjectAccessPolicy.VisibleProjectIds(
  AManager: TObjectManager; AUser: TUser): TDictionary<Integer, Boolean>;
var
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  Result := TDictionary<Integer, Boolean>.Create;
  if CheckPrincipal(AManager, AUser) <> pwAllowed then
    Exit;
  try
    Rows := AManager.Find<TProject>
      .Select(TProjections.ProjectionList.Add(TProjections.Prop('Id').As_('Id')))
      .Where(Linq['Owner.Id'] = FPrincipalId).ListValues;
    try
      for Row in Rows do
        Result.AddOrSetValue(Integer(Row.Values['Id']), True);
    finally
      Rows.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLocalProjectAccessPolicy.CanReviewProtocol(AManager: TObjectManager;
  AUser: TUser; AProjectId, AAuthorId: Integer): Boolean;
begin
  Result := (AAuthorId = FPrincipalId) and CanWrite(AManager, AUser, AProjectId);
end;

function TLocalProjectAccessPolicy.CanBrowseAllProjects(
  AManager: TObjectManager; AUser: TUser): Boolean;
begin
  Result := False;
end;

function TLocalProjectAccessPolicy.CanCreateProjects(
  AManager: TObjectManager; AUser: TUser): Boolean;
begin
  Result := CheckPrincipal(AManager, AUser) = pwAllowed;
end;

function TLocalProjectAccessPolicy.CanCreateTags(
  AManager: TObjectManager; AUser: TUser): Boolean;
begin
  Result := CheckPrincipal(AManager, AUser) = pwAllowed;
end;

function TLocalProjectAccessPolicy.CanEditReferenceData(
  AManager: TObjectManager; AUser: TUser): Boolean;
begin
  Result := CheckPrincipal(AManager, AUser) = pwAllowed;
end;

constructor TLocalGateEligibility.Create(AManager: TObjectManager; AUser: TUser;
  const AAccess: IProjectAccessPolicy; APrincipalId: Integer);
begin
  inherited Create(AManager, AUser);
  FAccess := AAccess;
  FPrincipalId := APrincipalId;
end;

function TLocalGateEligibility.CanPassGate(AProjectId, AAuthorId: Integer;
  AGate: THypothesisGate; out AReason: string): Boolean;
begin
  AReason := '';
  Result := (AGate in [hgApproveProposals, hgAcceptConclusions]) and
    (AAuthorId = FPrincipalId) and FAccess.CanWrite(FManager, FUser, AProjectId);
  if not Result then
    AReason := 'Only the active local scientist can review their own hypothesis in an active owned project.';
end;

function TLocalGateEligibility.PolicyInvalid: Boolean;
begin
  // Local review has no team approval settings or account roles.
  Result := False;
end;

function TLocalGateEligibility.PolicyError: string;
begin
  Result := '';
end;

end.
