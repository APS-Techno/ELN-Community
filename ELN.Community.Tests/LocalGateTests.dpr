program LocalGateTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Drivers.Interfaces,
  Aurelius.Criteria.Linq,
  unit_LocalNotebook in '..\ELN.Community\unit_LocalNotebook.pas',
  unit_LocalProjectAccessPolicy in '..\ELN.Community\unit_LocalProjectAccessPolicy.pas',
  unit_ProjectAccessPolicy in '..\ELN.Model\unit_ProjectAccessPolicy.pas',
  unit_ProjectModel in '..\ELN.Model\unit_ProjectModel.pas',
  unit_SearchModel in '..\ELN.Model\unit_SearchModel.pas',
  unit_HypothesisModel in '..\ELN.Model\unit_HypothesisModel.pas',
  unit_HypothesisGateModel in '..\ELN.Model\unit_HypothesisGateModel.pas',
  unit_HypothesisQueries in '..\ELN.Model\unit_HypothesisQueries.pas',
  unit_HypothesisRules in '..\ELN.Model\unit_HypothesisRules.pas',
  unit_ProtocolStatusModel in '..\ELN.Model\unit_ProtocolStatusModel.pas',
  unit_User,
  unit_Project,
  unit_Item,
  unit_ItemTypes,
  unit_Hypothesis,
  unit_HypothesisStatusChange,
  unit_AuditLog,
  unit_Protocol,
  unit_ProtocolStatusChange,
  unit_SignatureModel,
  unit_DBSetting;

const
  FixtureSigningPassword = 'Synthetic-Local-Gates-Only!';

var
  FixtureDir: string;
  Notebook: TLocalNotebook;
  Model: THypothesisModel;
  Gates: THypothesisGateModel;
  Projects: TProjectsModel;
  OwnProject: TProject;
  Passed, Failed: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure ExpectException(AClass: ExceptClass; const Operation: TProc);
begin
  try
    Operation();
  except
    on E: Exception do
    begin
      Check(E.InheritsFrom(AClass), 'Unexpected exception class: ' + E.ClassName);
      Exit;
    end;
  end;
  raise Exception.Create('Expected exception: ' + AClass.ClassName);
end;

procedure ExpectRefusal(ARefusal: THypRefusal; const Operation: TProc);
begin
  try
    Operation();
  except
    on E: EHypothesisError do
    begin
      Check(E.Refusal = ARefusal, 'Unexpected scientific refusal');
      Exit;
    end;
  end;
  raise Exception.Create('Expected scientific refusal');
end;

function HasTarget(const Targets: TArray<THypothesisStatus>;
  Target: THypothesisStatus): Boolean;
var
  Status: THypothesisStatus;
begin
  for Status in Targets do
    if Status = Target then
      Exit(True);
  Result := False;
end;

function HypothesisAuditCount(HypothesisId: Integer): Integer;
var
  Rows: TList<TAuditLog>;
  Row: TAuditLog;
begin
  Rows := Notebook.Manager.Find<TAuditLog>
    .Where((Linq['EntityType'] = Ord(aetHypothesis)) and
      (Linq['EntityId'] = HypothesisId)).List;
  try
    Result := Rows.Count;
    for Row in Rows do
      Check(Row.UserId = Notebook.Principal.Id, 'Audit actor remains local scientist');
  finally
    Rows.Free;
  end;
end;

function NewProposal: THypothesis;
begin
  Result := Model.Propose(Notebook.Principal, 0, OwnProject.Id, 0,
    'Synthetic expectation', 'Synthetic scientific statement', '', 0);
end;

function AddSpecimen(AProjectId: Integer): TItem;
begin
  Result := TItem.Create;
  Result.Title := 'Synthetic access match';
  Result.Type_ := TItemType.Specimen;
  Result.Level := TItemLevel.Item;
  Result.ProjectID := AProjectId;
  Result.FolderID := 0;
  Result.Parent := 0;
  Result.CreatedBy := Notebook.Principal.Id;
  Result.CreatedDate := Now;
  Notebook.Manager.Save(Result);
  Notebook.Manager.Flush;
end;

function AddForeignUser: TUser;
begin
  Result := TUser.Create;
  Result.Username := 'synthetic-foreign';
  Result.Password := Notebook.Principal.Password;
  Result.FirstName := 'Foreign';
  Result.LastName := 'Scientist';
  Result.Role := dbAdmin;
  Result.CreatedDate := Now;
  Notebook.Manager.Save(Result);
  Notebook.Manager.Flush;
end;

function AddProtocol(AStatus: TValidationStatus; out AItem: TItem): TProtocol;
begin
  AItem := AddSpecimen(OwnProject.Id);
  Result := TProtocol.Create;
  Result.Title := 'Synthetic atomic protocol';
  Result.CreatedDate := Now;
  Result.CreatedBy := Notebook.Principal.Id;
  Result.ProtocolType := ptExperiment;
  Result.ValidationStatus := AStatus;
  AItem.Entries.Add(Result);
  Notebook.Manager.Flush;
end;

function ProtocolAuditCount(AProtocolId: Integer): Integer;
var
  Rows: TList<TAuditLog>;
begin
  Rows := Notebook.Manager.Find<TAuditLog>
    .Where((Linq['EntityType'] = Ord(aetProtocol)) and
      (Linq['EntityId'] = AProtocolId)).List;
  try
    Result := Rows.Count;
  finally
    Rows.Free;
  end;
end;

procedure CheckProtocolRows(AStatus: TProtocolStatusModel;
  AProtocolId, AExpectedCount: Integer);
var
  History: TProtocolStatusChanges;
begin
  History := AStatus.GetStatusHistory(AProtocolId);
  try
    Check(History.Count = AExpectedCount, 'Protocol transition history count');
  finally
    History.Free;
  end;
  Check(ProtocolAuditCount(AProtocolId) = AExpectedCount,
    'Protocol transition audit count');
end;

procedure TestOwnGatesKeepScientistIdentity;
var
  H: THypothesis;
  History: TArray<THypothesisHistoryView>;
  Waiting: TArray<THypothesisSummary>;
  OriginalVersion: Integer;
begin
  Check(Notebook.Principal.Role = dbUser, 'Local scientist is not elevated');
  H := NewProposal;
  OriginalVersion := H.Version;
  Waiting := NeedsMyApproval(Notebook.Manager, Notebook.Principal, Notebook.AccessPolicy);
  Check((Length(Waiting) = 1) and (Waiting[0].Id = H.Id), 'Own proposal waits for human approval');
  Check(HasTarget(Gates.AllowedGateTargets(Notebook.Principal, H.Id), hsApproved),
    'Preview offers local approval');
  Check(HasTarget(Gates.AllowedGateTargets(Notebook.Principal, H.Id), hsRejected),
    'Preview offers local rejection');
  Gates.Approve(Notebook.Principal, 0, H.Id, H.Version, 'Human proposal review');
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  Check(H.Status = hsApproved, 'Proposal passes the retained human gate');
  Check(H.Version > OriginalVersion, 'Gate bumps optimistic version');
  Check(H.CreatedBy = Notebook.Principal.Id, 'Original author is preserved');
  History := Model.Get(Notebook.Principal, H.Id).History;
  Check(Length(History) = 2, 'Proposal and approval both have history');
  Check(History[High(History)].NewStatus = hsApproved, 'Approval history records target state');
  Check(History[High(History)].ChangedBy = Notebook.Principal.Id, 'Human review actor is recorded');
  Check(History[High(History)].Comment = 'Human proposal review', 'Human review comment is retained');
  Check(HypothesisAuditCount(H.Id) = 2, 'Proposal and approval both have audit rows');
  Check(Notebook.Principal.Role = dbUser, 'Human gate did not promote scientist');
end;

procedure TestEvidenceVersionStateAndSeal;
var
  H: THypothesis;
  Item: TItem;
  BeforeAudit, OldVersion, BeforeHistory: Integer;
  D: THypothesisDetail;
begin
  H := NewProposal;
  Gates.Approve(Notebook.Principal, 0, H.Id, H.Version, '');
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  BeforeAudit := HypothesisAuditCount(H.Id);
  BeforeHistory := Length(Model.Get(Notebook.Principal, H.Id).History);
  ExpectRefusal(hrNeedsEvidence,
    procedure
    begin
      Model.SubmitConclusion(Notebook.Principal, 0, H.Id, H.Version,
        'Conclusion without evidence', hoSupported);
    end);
  Check(THypothesisModel.Load(Notebook.Manager, H.Id).Status = hsApproved,
    'Evidence refusal keeps status');
  Check(HypothesisAuditCount(H.Id) = BeforeAudit, 'Evidence refusal writes no audit');
  Check(Length(Model.Get(Notebook.Principal, H.Id).History) = BeforeHistory,
    'Evidence refusal writes no history');
  Item := AddSpecimen(OwnProject.Id);
  Model.AttachRun(Notebook.Principal, H.Id, Item.Id, hrrRun);
  Model.CiteEvidence(Notebook.Principal, H.Id, Item.Id, 0, 0, 'Synthetic evidence');
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  Model.SubmitConclusion(Notebook.Principal, 0, H.Id, H.Version,
    'Evidence supports the synthetic expectation', hoSupported);
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  Check(H.Status = hsInReview, 'Conclusion still needs human acceptance');
  Check(H.ContentHash = '', 'Submission alone does not seal conclusion');
  Check(HasTarget(Gates.AllowedGateTargets(Notebook.Principal, H.Id), hsAccepted),
    'Preview offers local acceptance');
  Check(HasTarget(Gates.AllowedGateTargets(Notebook.Principal, H.Id), hsApproved),
    'Preview offers return for rework');
  OldVersion := H.Version;
  BeforeAudit := HypothesisAuditCount(H.Id);
  ExpectException(EHypothesisConflict,
    procedure
    begin
      Gates.Accept(Notebook.Principal, 0, H.Id, OldVersion - 1, 'Stale review');
    end);
  Check(HypothesisAuditCount(H.Id) = BeforeAudit, 'Stale review writes no audit');
  Gates.Accept(Notebook.Principal, 0, H.Id, OldVersion, 'Human conclusion review');
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  Check(H.Status = hsAccepted, 'Human acceptance executes');
  Check(H.CreatedBy = Notebook.Principal.Id, 'Acceptance keeps author');
  Check(H.ContentHash <> '', 'Acceptance seals scientific content');
  Check(Gates.VerifySeal(H.Id), 'Accepted seal is intact');
  Check(Length(Gates.AllowedGateTargets(Notebook.Principal, H.Id)) = 0,
    'Final state has no gate targets');
  ExpectException(EHypothesisError,
    procedure
    begin
      Gates.ReturnForRework(Notebook.Principal, 0, H.Id, H.Version, 'Cannot reopen final state');
    end);
  D := Model.Get(Notebook.Principal, H.Id);
  Check((Length(D.Runs) = 1) and (Length(D.Evidence) = 1), 'Scientific evidence remains attached');
  Check(D.History[High(D.History)].ChangedBy = Notebook.Principal.Id, 'Acceptance history records actor');
  H.Conclusion := 'Synthetic tampering';
  Notebook.Manager.Flush;
  Check(not Gates.VerifySeal(H.Id), 'Altered conclusion breaks acceptance seal');
end;

procedure TestRejectAndReturnRequireComments;
var
  H: THypothesis;
  Item: TItem;
  BeforeAudit: Integer;
begin
  H := NewProposal;
  BeforeAudit := HypothesisAuditCount(H.Id);
  ExpectRefusal(hrNeedsComment,
    procedure
    begin
      Gates.Reject(Notebook.Principal, 0, H.Id, H.Version, ' ');
    end);
  Check(HypothesisAuditCount(H.Id) = BeforeAudit, 'Blank rejection writes no audit');
  Gates.Reject(Notebook.Principal, 0, H.Id, H.Version, 'Human rejection reason');
  Check(THypothesisModel.Load(Notebook.Manager, H.Id).Status = hsRejected,
    'Rejection with reason executes');
  H := NewProposal;
  Gates.Approve(Notebook.Principal, 0, H.Id, H.Version, '');
  Item := AddSpecimen(OwnProject.Id);
  Model.CiteEvidence(Notebook.Principal, H.Id, Item.Id, 0, 0, 'Evidence');
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  Model.SubmitConclusion(Notebook.Principal, 0, H.Id, H.Version, 'Conclusion', hoInconclusive);
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  BeforeAudit := HypothesisAuditCount(H.Id);
  ExpectRefusal(hrNeedsComment,
    procedure
    begin
      Gates.ReturnForRework(Notebook.Principal, 0, H.Id, H.Version, '');
    end);
  Check(HypothesisAuditCount(H.Id) = BeforeAudit, 'Blank return writes no audit');
  Gates.ReturnForRework(Notebook.Principal, 0, H.Id, H.Version, 'Human rework reason');
  H := THypothesisModel.Load(Notebook.Manager, H.Id);
  Check(H.Status = hsApproved, 'Return keeps the normal approved rework state');
  Check(H.ContentHash = '', 'Returned conclusion is not sealed');
end;

procedure TestPrincipalProjectAndAuthorBoundaries;
var
  Foreign: TUser;
  ForeignProject, Unowned: TProject;
  H: THypothesis;
  Eligibility: TGateEligibility;
  Reason: string;
  BeforeAudit: Integer;
begin
  Foreign := AddForeignUser;
  Check(not Notebook.AccessPolicy.CanEditReferenceData(Notebook.Manager, Foreign),
    'Foreign Admin identity cannot edit local scientific reference data');
  ForeignProject := Projects.AddProject('Foreign owned', '', Foreign);
  Unowned := Projects.AddProject('Unowned', '', Notebook.Principal);
  Unowned.Owner := nil;
  Notebook.Manager.Flush;
  H := NewProposal;
  Eligibility := Notebook.AccessPolicy.CreateGateEligibility(Notebook.Manager, Notebook.Principal);
  try
    Check(not Eligibility.PolicyInvalid, 'Local policy needs no approval administration');
    Check(Eligibility.PolicyError = '', 'Local policy has no team settings error');
    Check(not Eligibility.CanPassGate(OwnProject.Id, Foreign.Id, hgApproveProposals, Reason),
      'Local gates reject a foreign hypothesis author');
  finally
    Eligibility.Free;
  end;
  Check(not Notebook.AccessPolicy.CanWrite(Notebook.Manager, nil, OwnProject.Id), 'Nil identity is denied');
  Check(not Notebook.AccessPolicy.CanWrite(Notebook.Manager, Foreign, OwnProject.Id),
    'Foreign Admin identity cannot bypass local binding');
  Check(not Notebook.AccessPolicy.CanRead(Notebook.Manager, Notebook.Principal, ForeignProject.Id),
    'Foreign project is unreadable');
  Check(not Notebook.AccessPolicy.CanWrite(Notebook.Manager, Notebook.Principal, ForeignProject.Id),
    'Foreign project is unwritable');
  Check(not Notebook.AccessPolicy.CanWrite(Notebook.Manager, Notebook.Principal, Unowned.Id),
    'Unowned project is unwritable');
  Check(not Notebook.AccessPolicy.CanWrite(Notebook.Manager, Notebook.Principal, -1),
    'Missing project is unwritable');
  BeforeAudit := HypothesisAuditCount(H.Id);
  ExpectException(EHypothesisNotApprover,
    procedure
    begin
      Gates.Approve(Foreign, 0, H.Id, H.Version, 'Foreign review');
    end);
  Check(HypothesisAuditCount(H.Id) = BeforeAudit, 'Foreign review writes no audit');
  OwnProject.IsArchived := True;
  Notebook.Manager.Flush;
  Check(Length(Gates.AllowedGateTargets(Notebook.Principal, H.Id)) = 0,
    'Archived project has no preview gate targets');
  ExpectException(EHypothesisNotApprover,
    procedure
    begin
      Gates.Approve(Notebook.Principal, 0, H.Id, H.Version, 'Archived review');
    end);
  OwnProject.IsArchived := False;
  Notebook.Principal.IsArchived := True;
  Notebook.Manager.Flush;
  Check(not Notebook.AccessPolicy.CanCreateProjects(Notebook.Manager, Notebook.Principal),
    'Archived scientist cannot create projects');
  Check(not Notebook.AccessPolicy.CanEditReferenceData(Notebook.Manager, Notebook.Principal),
    'Archived scientist cannot edit scientific reference data');
  Check(Length(Gates.AllowedGateTargets(Notebook.Principal, H.Id)) = 0,
    'Archived identity has no preview gate targets');
end;

procedure TestLocalSearchScopeAndProtocolReview;
var
  Foreign: TUser;
  ForeignProject: TProject;
  Search: TSearchModel;
  Results: TSearchResults;
  Visible: TDictionary<Integer, Boolean>;
  Status: TProtocolStatusModel;
  Allowed: TArray<TValidationStatus>;
begin
  Foreign := AddForeignUser;
  ForeignProject := Projects.AddProject('Foreign owned', '', Foreign);
  AddSpecimen(OwnProject.Id);
  AddSpecimen(ForeignProject.Id);
  Visible := Notebook.AccessPolicy.VisibleProjectIds(Notebook.Manager, nil);
  try
    Check((Visible <> nil) and (Visible.Count = 0), 'Invalid local user is never unrestricted');
  finally
    Visible.Free;
  end;
  Search := TSearchModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Search.AssignUser(Notebook.Principal);
    Results := Search.Search('Synthetic access match');
    try
      Check(Results.Count = 1, 'Local search excludes foreign project matches');
      Check(Results[0].ProjectId = OwnProject.Id, 'Local search returns owned scientific data');
    finally
      Results.Free;
    end;
  finally
    Search.Free;
  end;
  Status := TProtocolStatusModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Allowed := Status.GetAllowedTransitions(vsInReview, Notebook.Principal,
      OwnProject.Id, Notebook.Principal.Id);
    Check(Length(Allowed) = 2, 'Local scientist reviews own protocol without elevated role');
    Check(not Status.CanTransition(vsInReview, vsApproved, Foreign,
      OwnProject.Id, Notebook.Principal.Id), 'Foreign Admin cannot review local protocol');
    Check(not Status.CanTransition(vsInReview, vsApproved, Notebook.Principal,
      OwnProject.Id, Foreign.Id), 'Local scientist cannot review foreign protocol author');
    Check(not Status.CanTransition(vsInReview, vsApproved, Notebook.Principal,
      ForeignProject.Id, Notebook.Principal.Id), 'Foreign project protocol cannot be reviewed');
  finally
    Status.Free;
  end;
  Check(not Notebook.AccessPolicy.CanBrowseAllProjects(Notebook.Manager, Notebook.Principal),
    'Local scientist has no team supervisor scope');
  Check(Notebook.AccessPolicy.CanEditReferenceData(Notebook.Manager, Notebook.Principal),
    'Local scientist can edit scientific reference data without team roles');
end;

procedure TestLocalReviewIgnoresTeamSettings;
var
  Setting: TDBSetting;
  H: THypothesis;
begin
  // A synthetic legacy team setting cannot control local scientific review.
  Setting := TDBSetting.Create;
  Setting.SettingKey := 'HYPOTHESIS_APPROVAL_POLICY';
  Setting.SettingValue := '{invalid synthetic JSON';
  Notebook.Manager.Save(Setting);
  Notebook.Manager.Flush;
  H := NewProposal;
  Gates.Approve(Notebook.Principal, 0, H.Id, H.Version, 'Local review');
  Check(THypothesisModel.Load(Notebook.Manager, H.Id).Status = hsApproved,
    'Local gate does not depend on a team approval settings editor');
end;

procedure TestLocalGateReadsCommittedFacts;
var
  OtherManager: TObjectManager;
  OtherUser: TUser;
  OtherProject: TProject;
  H: THypothesis;
  BeforeAudit: Integer;
begin
  H := NewProposal;
  OtherManager := TObjectManager.Create(Notebook.Connection);
  try
    OtherProject := OtherManager.Find<TProject>(OwnProject.Id);
    OtherProject.IsArchived := True;
    OtherManager.Flush;
    Check(not OwnProject.IsArchived, 'Shared project remains the old cached copy');
    Check(Length(Gates.AllowedGateTargets(Notebook.Principal, H.Id)) = 0,
      'Preview sees a project archived by another manager');
    BeforeAudit := HypothesisAuditCount(H.Id);
    ExpectException(EHypothesisNotApprover,
      procedure
      begin
        Gates.Approve(Notebook.Principal, 0, H.Id, H.Version, 'Stale project review');
      end);
    Check(HypothesisAuditCount(H.Id) = BeforeAudit, 'Archived project gate writes no audit');
    OtherProject.IsArchived := False;
    OtherUser := OtherManager.Find<TUser>(Notebook.Principal.Id);
    OtherUser.IsArchived := True;
    OtherManager.Flush;
    Check(not Notebook.Principal.IsArchived, 'Shared principal remains the old cached copy');
    Check(Length(Gates.AllowedGateTargets(Notebook.Principal, H.Id)) = 0,
      'Preview sees a principal archived by another manager');
    ExpectException(EHypothesisNotApprover,
      procedure
      begin
        Gates.Approve(Notebook.Principal, 0, H.Id, H.Version, 'Stale principal review');
      end);
    Check(HypothesisAuditCount(H.Id) = BeforeAudit, 'Archived principal gate writes no audit');
  finally
    OtherManager.Free;
  end;
end;

procedure TestProtocolReviewUsesCommittedContext;
var
  Status: TProtocolStatusModel;
  Item, OtherItem: TItem;
  Protocol, OtherProtocol: TProtocol;
  Foreign: TUser;
  ForeignProject: TProject;
  OtherManager: TObjectManager;
  ProjectId, AuthorId: Integer;
begin
  Protocol := AddProtocol(vsInReview, Item);
  Foreign := AddForeignUser;
  ForeignProject := Projects.AddProject('Foreign protocol destination', '', Foreign);
  Status := TProtocolStatusModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Check(Status.TryGetAccessContext(Protocol.Id, ProjectId, AuthorId),
      'Persisted protocol has a parent access context');
    Check(Status.CanTransition(vsInReview, vsApproved, Notebook.Principal,
      ProjectId, AuthorId), 'Own persisted protocol can be reviewed');
    OtherManager := TObjectManager.Create(Notebook.Connection);
    try
      OtherItem := OtherManager.Find<TItem>(Item.Id);
      OtherItem.ProjectID := ForeignProject.Id;
      OtherManager.Flush;
      Check(Item.ProjectID = OwnProject.Id, 'Shared parent item keeps its old cached project');
      Check(Status.TryGetAccessContext(Protocol.Id, ProjectId, AuthorId),
        'Moved protocol still has a parent access context');
      Check(ProjectId = ForeignProject.Id, 'Context reads committed parent project');
      Check(not Status.CanTransition(vsInReview, vsApproved, Notebook.Principal,
        ProjectId, AuthorId), 'Moved foreign-project protocol cannot be reviewed');
      ExpectException(EProtocolTransitionError,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, Protocol.Version,
            vsInReview, vsApproved, 'Moved-parent review');
        end);
      CheckProtocolRows(Status, Protocol.Id, 0);
      OtherItem.ProjectID := OwnProject.Id;
      OtherProtocol := OtherManager.Find<TProtocol>(Protocol.Id);
      OtherProtocol.CreatedBy := Foreign.Id;
      OtherManager.Flush;
      Check(Protocol.CreatedBy.Value = Notebook.Principal.Id,
        'Shared protocol keeps its old cached author');
      Check(Status.TryGetAccessContext(Protocol.Id, ProjectId, AuthorId),
        'Reauthored protocol still has an access context');
      Check(AuthorId = Foreign.Id, 'Context reads committed protocol author');
      Check(not Status.CanTransition(vsInReview, vsRejected, Notebook.Principal,
        ProjectId, AuthorId), 'Foreign-authored protocol cannot be reviewed');
      ExpectException(EProtocolTransitionError,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, OtherProtocol.Version,
            vsInReview, vsRejected, 'Foreign-author review');
        end);
      CheckProtocolRows(Status, Protocol.Id, 0);
    finally
      OtherManager.Free;
    end;
  finally
    Status.Free;
  end;
end;

procedure TestArchivedOwnershipRestoreAndRemoval;
var
  ArchivedId: Integer;
  Foreign: TUser;
  ForeignProject: TProject;
begin
  Foreign := AddForeignUser;
  ForeignProject := Projects.AddProject('Foreign cleanup target', '', Foreign);
  Check(not Projects.DeleteProject(ForeignProject.Id, Notebook.Principal.Id),
    'Local cleanup cannot remove a foreign project');
  OwnProject.IsArchived := True;
  Notebook.Manager.Flush;
  Check(Projects.GetProjectAccess(OwnProject.Id) = paOwner,
    'Archived owned project retains ownership for restore');
  Check(not Notebook.AccessPolicy.CanWrite(Notebook.Manager, Notebook.Principal, OwnProject.Id),
    'Archive ownership does not permit scientific content writes');
  OwnProject.IsArchived := False;
  Check(Projects.Update(OwnProject), 'Owner can restore the archived project');
  Check(Notebook.AccessPolicy.CanWrite(Notebook.Manager, Notebook.Principal, OwnProject.Id),
    'Restored project permits scientific content writes');
  OwnProject.IsArchived := True;
  Notebook.Manager.Flush;
  ArchivedId := OwnProject.Id;
  Check(Projects.IsProjectEmpty(ArchivedId), 'Cleanup fixture is an empty archived project');
  Check(Projects.DeleteProject(ArchivedId, Notebook.Principal.Id),
    'Owner can permanently remove an empty archived project');
  Check(Notebook.Manager.Find<TProject>(ArchivedId) = nil, 'Archived cleanup removes actual project');
end;

procedure TestAtomicProtocolTransitionKeepsHostDrafts;
var
  Status: TProtocolStatusModel;
  Item: TItem;
  Protocol: TProtocol;
  Observer: TObjectManager;
  StoredProject: TProject;
  History: TProtocolStatusChanges;
  Audit: TList<TAuditLog>;
  OriginalVersion, CommittedVersion: Integer;
begin
  Protocol := AddProtocol(vsInReview, Item);
  OriginalVersion := Protocol.Version;
  OwnProject.Description := 'Unflushed scientific draft';
  Status := TProtocolStatusModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    CommittedVersion := Status.Transition(Notebook.Principal, Protocol.Id,
      OriginalVersion, vsInReview, vsApproved, 'Human protocol review');
    Check(CommittedVersion > OriginalVersion, 'Atomic transition bumps version');
    Check(Protocol.ValidationStatus = vsInReview, 'Operation does not mutate a host snapshot');
    Check(OwnProject.Description = 'Unflushed scientific draft', 'Host draft remains in memory');
    Observer := TObjectManager.Create(Notebook.Connection);
    try
      StoredProject := Observer.Find<TProject>(OwnProject.Id);
      Check(StoredProject.Description = '', 'Protocol transition does not flush unrelated host drafts');
    finally
      Observer.Free;
    end;
    Notebook.Manager.Refresh(Protocol);
    Check(Protocol.ValidationStatus = vsApproved, 'Caller refresh sees committed approval');
    Check(Protocol.Version = CommittedVersion, 'Caller refresh adopts committed version');
    Check(Protocol.ModifiedDate.HasValue, 'Atomic transition records modified time');
    Check(Protocol.ModifiedBy.HasValue and
      (Protocol.ModifiedBy.Value = Notebook.Principal.Id), 'Atomic transition records modifier');
    History := Status.GetStatusHistory(Protocol.Id);
    try
      Check(History.Count = 1, 'Atomic approval has one history row');
      Check((History[0].OldStatus = vsInReview) and
        (History[0].NewStatus = vsApproved), 'History records the actual state transition');
      Check(History[0].ChangedBy = Notebook.Principal.Id, 'History records local scientist');
      Check(History[0].Comment = 'Human protocol review', 'History retains review comment');
      Check(History[0].ChangedDate = Protocol.ModifiedDate.Value,
        'Status and history share the operation timestamp');
    finally
      History.Free;
    end;
    Audit := Notebook.Manager.Find<TAuditLog>
      .Where((Linq['EntityType'] = Ord(aetProtocol)) and
        (Linq['EntityId'] = Protocol.Id)).List;
    try
      Check((Audit.Count = 1) and (Audit[0].UserId = Notebook.Principal.Id),
        'Atomic approval records local audit actor');
    finally
      Audit.Free;
    end;
    Check(OwnProject.Description = 'Unflushed scientific draft', 'Refreshing saved protocol keeps unrelated draft');
    Check(Notebook.Principal.Role = dbUser, 'Atomic review does not elevate local role');
  finally
    Status.Free;
  end;
end;

procedure TestAtomicProtocolVersionStateAndCommentRules;
var
  Status: TProtocolStatusModel;
  Item: TItem;
  Protocol, OtherProtocol: TProtocol;
  OtherManager: TObjectManager;
  ExpectedVersion, CurrentVersion: Integer;
begin
  Protocol := AddProtocol(vsInReview, Item);
  ExpectedVersion := Protocol.Version;
  Status := TProtocolStatusModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    OtherManager := TObjectManager.Create(Notebook.Connection);
    try
      OtherProtocol := OtherManager.Find<TProtocol>(Protocol.Id);
      OtherProtocol.Title := 'Changed by another manager';
      OtherManager.Flush;
      CurrentVersion := OtherProtocol.Version;
      ExpectException(EProtocolTransitionConflict,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, ExpectedVersion,
            vsInReview, vsApproved, 'Stale review');
        end);
      CheckProtocolRows(Status, Protocol.Id, 0);
      ExpectException(EProtocolTransitionConflict,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, CurrentVersion,
            vsDraft, vsInReview, 'Wrong from-state');
        end);
      CheckProtocolRows(Status, Protocol.Id, 0);
      ExpectException(EProtocolTransitionError,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, CurrentVersion,
            vsInReview, vsDraft, 'Invalid target');
        end);
      CheckProtocolRows(Status, Protocol.Id, 0);
      // Protocol rejection permits an empty reason; hypothesis rejection does not.
      CurrentVersion := Status.Transition(Notebook.Principal, Protocol.Id,
        CurrentVersion, vsInReview, vsRejected, '');
      CurrentVersion := Status.Transition(Notebook.Principal, Protocol.Id,
        CurrentVersion, vsRejected, vsDraft, '');
      CurrentVersion := Status.Transition(Notebook.Principal, Protocol.Id,
        CurrentVersion, vsDraft, vsInReview, '');
      CurrentVersion := Status.Transition(Notebook.Principal, Protocol.Id,
        CurrentVersion, vsInReview, vsApproved, 'Reviewed');
      CheckProtocolRows(Status, Protocol.Id, 4);
      ExpectException(EProtocolTransitionError,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, CurrentVersion,
            vsApproved, vsRejected, 'Cannot reopen final approval');
        end);
      CheckProtocolRows(Status, Protocol.Id, 4);
      OtherManager.Refresh(OtherProtocol);
      Check(OtherProtocol.ValidationStatus = vsApproved, 'Final approval remains unchanged');
      Check(OtherProtocol.Version = CurrentVersion, 'Refused final transition does not bump version');
    finally
      OtherManager.Free;
    end;
  finally
    Status.Free;
  end;
end;

procedure TestAtomicProtocolCurrentReadonlyFacts;
var
  Status: TProtocolStatusModel;
  Item: TItem;
  Protocol: TProtocol;
  OtherManager: TObjectManager;
  OtherProject: TProject;
  OtherUser, Foreign: TUser;
  Signatures: TSignatureModel;
begin
  Protocol := AddProtocol(vsInReview, Item);
  Status := TProtocolStatusModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    ExpectException(EProtocolTransitionError,
      procedure
      begin
        Status.Transition(nil, Protocol.Id, Protocol.Version,
          vsInReview, vsApproved, 'Missing actor review');
      end);
    Foreign := AddForeignUser;
    ExpectException(EProtocolTransitionError,
      procedure
      begin
        Status.Transition(Foreign, Protocol.Id, Protocol.Version,
          vsInReview, vsApproved, 'Foreign Admin review');
      end);
    CheckProtocolRows(Status, Protocol.Id, 0);
    OtherManager := TObjectManager.Create(Notebook.Connection);
    try
      OtherProject := OtherManager.Find<TProject>(OwnProject.Id);
      OtherProject.IsArchived := True;
      OtherManager.Flush;
      Check(not OwnProject.IsArchived, 'Host project snapshot is stale');
      ExpectException(EProtocolTransitionError,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, Protocol.Version,
            vsInReview, vsApproved, 'Archived project review');
        end);
      CheckProtocolRows(Status, Protocol.Id, 0);
      OtherProject.IsArchived := False;
      OtherUser := OtherManager.Find<TUser>(Notebook.Principal.Id);
      OtherUser.IsArchived := True;
      OtherManager.Flush;
      Check(not Notebook.Principal.IsArchived, 'Host identity snapshot is stale');
      ExpectException(EProtocolTransitionError,
        procedure
        begin
          Status.Transition(Notebook.Principal, Protocol.Id, Protocol.Version,
            vsInReview, vsApproved, 'Archived identity review');
        end);
      CheckProtocolRows(Status, Protocol.Id, 0);
      OtherUser.IsArchived := False;
      OtherManager.Flush;
    finally
      OtherManager.Free;
    end;
    Signatures := TSignatureModel.Create(Notebook.Manager);
    try
      Check(Signatures.SignItem(Item, Notebook.Principal, FixtureSigningPassword,
        'Review fixture', ''), 'Fixture creates a real item signature');
    finally
      Signatures.Free;
    end;
    ExpectException(EProtocolTransitionError,
      procedure
      begin
        Status.Transition(Notebook.Principal, Protocol.Id, Protocol.Version,
          vsInReview, vsApproved, 'Signed parent review');
      end);
    CheckProtocolRows(Status, Protocol.Id, 0);
    Item.IsDeleted := True;
    Notebook.Manager.Flush;
    ExpectException(EProtocolTransitionError,
      procedure
      begin
        Status.Transition(Notebook.Principal, Protocol.Id, Protocol.Version,
          vsInReview, vsApproved, 'Deleted parent review');
      end);
    CheckProtocolRows(Status, Protocol.Id, 0);
  finally
    Status.Free;
  end;
end;

procedure TestAtomicProtocolAuditFailureRollsBack;
var
  Status: TProtocolStatusModel;
  Item: TItem;
  Protocol, Stored: TProtocol;
  Observer: TObjectManager;
  Statement: IDBStatement;
  OriginalVersion, CommittedVersion: Integer;
  FailedAsExpected: Boolean;
begin
  Protocol := AddProtocol(vsInReview, Item);
  OriginalVersion := Protocol.Version;
  OwnProject.Description := 'Unflushed rollback fixture draft';
  Status := TProtocolStatusModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Statement := Notebook.Connection.CreateStatement;
    Statement.SetSQLCommand('CREATE TRIGGER ProtocolAuditDown BEFORE INSERT ON AuditLog ' +
      'BEGIN SELECT RAISE(ABORT, ''synthetic protocol audit failure''); END');
    Statement.Execute;
    try
      FailedAsExpected := False;
      try
        Status.Transition(Notebook.Principal, Protocol.Id, OriginalVersion,
          vsInReview, vsApproved, 'Must roll back');
      except
        on E: Exception do
        begin
          Check(Pos('synthetic protocol audit failure', E.Message) > 0,
            'The deterministic audit fixture causes the failure');
          FailedAsExpected := True;
        end;
      end;
      Check(FailedAsExpected, 'Synthetic audit failure must propagate');
    finally
      Statement := Notebook.Connection.CreateStatement;
      Statement.SetSQLCommand('DROP TRIGGER ProtocolAuditDown');
      Statement.Execute;
    end;
    Observer := TObjectManager.Create(Notebook.Connection);
    try
      Stored := Observer.Find<TProtocol>(Protocol.Id);
      Check(Stored.ValidationStatus = vsInReview, 'Audit failure rolls back actual status');
      Check(Stored.Version = OriginalVersion, 'Audit failure rolls back version bump');
      Check(not Stored.ModifiedDate.HasValue, 'Audit failure rolls back modified metadata');
      CheckProtocolRows(Status, Protocol.Id, 0);
      Check(Protocol.ValidationStatus = vsInReview, 'Failed operation leaves host snapshot unchanged');
      Check(OwnProject.Description = 'Unflushed rollback fixture draft',
        'Failed operation leaves unrelated host draft unchanged');
      CommittedVersion := Status.Transition(Notebook.Principal, Protocol.Id,
        OriginalVersion, vsInReview, vsApproved, 'Retry after storage recovery');
      Observer.Refresh(Stored);
      Check(Stored.ValidationStatus = vsApproved, 'A subsequent real transition succeeds');
      Check(Stored.Version = CommittedVersion, 'Subsequent transition version is coherent');
      CheckProtocolRows(Status, Protocol.Id, 1);
      Check(Observer.Find<TProject>(OwnProject.Id).Description = '',
        'Neither failed nor successful operation flushes host drafts');
    finally
      Observer.Free;
    end;
  finally
    Status.Free;
  end;
end;

procedure RunTest(const Name: string; const Test: TProc);
var
  Id: TGUID;
begin
  CreateGUID(Id);
  FixtureDir := TPath.Combine(TPath.GetTempPath, 'ELN-Local-Gates-' + GUIDToString(Id));
  Notebook := nil;
  Projects := nil;
  Model := nil;
  Gates := nil;
  try
    ForceDirectories(FixtureDir);
    try
      Notebook := TLocalNotebook.CreateNew(TPath.Combine(FixtureDir, 'notebook.sqlite'),
        TPath.Combine(FixtureDir, 'attachments'), 'Synthetic', 'Scientist',
        FixtureSigningPassword);
      Projects := TProjectsModel.Create(Notebook.Manager, Notebook.AccessPolicy);
      Projects.AssignUser(Notebook.Principal);
      OwnProject := Projects.AddProject('Owned scientific fixture', '', Notebook.Principal);
      Model := THypothesisModel.Create(Notebook.Manager, Notebook.AccessPolicy);
      Gates := THypothesisGateModel.Create(Notebook.Manager, Notebook.AccessPolicy);
      Test();
      Inc(Passed);
      WriteLn('PASS ', Name);
    except
      on E: Exception do
      begin
        Inc(Failed);
        WriteLn('FAIL ', Name, ': ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    Gates.Free;
    Model.Free;
    Projects.Free;
    Notebook.Free;
    if DirectoryExists(FixtureDir) then
      TDirectory.Delete(FixtureDir, True);
  end;
end;

begin
  RunTest('own human gates preserve local identity', TestOwnGatesKeepScientistIdentity);
  RunTest('evidence version state and acceptance seal', TestEvidenceVersionStateAndSeal);
  RunTest('rejection and rework need comments', TestRejectAndReturnRequireComments);
  RunTest('principal project and author boundaries', TestPrincipalProjectAndAuthorBoundaries);
  RunTest('local search and protocol review scope', TestLocalSearchScopeAndProtocolReview);
  RunTest('local review ignores team settings', TestLocalReviewIgnoresTeamSettings);
  RunTest('local gates read committed facts', TestLocalGateReadsCommittedFacts);
  RunTest('protocol review reads committed context', TestProtocolReviewUsesCommittedContext);
  RunTest('archive ownership restore and removal', TestArchivedOwnershipRestoreAndRemoval);
  RunTest('atomic protocol transition preserves host drafts', TestAtomicProtocolTransitionKeepsHostDrafts);
  RunTest('atomic protocol version state and comment rules', TestAtomicProtocolVersionStateAndCommentRules);
  RunTest('atomic protocol current read-only facts', TestAtomicProtocolCurrentReadonlyFacts);
  RunTest('atomic protocol audit failure rolls back', TestAtomicProtocolAuditFailureRollsBack);
  WriteLn('Passed: ', Passed, '; Failed: ', Failed);
  if Failed <> 0 then
    ExitCode := 1;
end.
