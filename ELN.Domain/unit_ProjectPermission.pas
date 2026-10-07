unit unit_ProjectPermission;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Proxy,
  Aurelius.Types.Nullable,
  unit_Project,
  unit_User;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TAccessLevel = (alReadOnly, alReadWrite);

const
  AccessLevelName: array[TAccessLevel] of string = ('ReadOnly', 'ReadWrite');
  AccessLevelShort: array[TAccessLevel] of string = ('RO', 'RW');

type
  TProjectPermission = class;
  TProjectPermissions = TList<TProjectPermission>;

  /// <summary>The two approver-flag columns exactly as loaded, NULL
  /// included (a pre-Plan-4 grant has NULL in both). Opaque: only
  /// TProjectPermission reads or writes the fields. Used by
  /// unit_ApproverGrants to put a grant back to its loaded state when a
  /// flag change could not be saved.</summary>
  TApproverFlagsSnapshot = record
  private
    FApproveProposals: Nullable<Boolean>;
    FAcceptConclusions: Nullable<Boolean>;
  end;

  [Entity]
  [Table('ProjectPermissions')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TProjectPermission = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    // No cascade: this is a reference to a row owned elsewhere, not a child of
    // this entity. CascadeTypeAll carries TCascadeType.Evict, so cascading here
    // detaches the referenced row whenever this one is evicted, leaving a stale
    // instance alive while the next Find maps a fresh one -- two live instances
    // of one Id, and the next Save/Update cascade raises EObjectAlreadyPersistent.
    [Association([TAssociationProp.Lazy], [])]
    [JoinColumn('ProjectID', [TColumnProp.Required], 'Id')]
    FProject: Proxy<TProject>;

    [Association([TAssociationProp.Lazy], [])]
    [JoinColumn('UserID', [TColumnProp.Required], 'Id')]
    FUser: Proxy<TUser>;

    [Column('AccessLevel', [TColumnProp.Required])]
    FAccessLevel: TAccessLevel;

    [Column('GrantedBy', [TColumnProp.Required])]
    FGrantedBy: Integer;

    [Column('GrantedDate', [TColumnProp.Required])]
    FGrantedDate: TDateTime;

    // Per-project named approvers (experiment tree, spec 6.2). Null = false.
    // Written ONLY through SetApproverFlags (and RestoreApproverFlags, its
    // failure rollback), which only unit_ApproverGrants
    // calls; test_HypothesisLinkage enforces that.
    [Column('CanApproveProposals', [])]
    FCanApproveProposals: Nullable<Boolean>;

    [Column('CanAcceptConclusions', [])]
    FCanAcceptConclusions: Nullable<Boolean>;

    function GetCanApproveProposals: Boolean;
    function GetCanAcceptConclusions: Boolean;

    function GetProject: TProject;
    procedure SetProject(const Value: TProject);
    function GetUser: TUser;
    procedure SetUser(const Value: TUser);
  public
    property Id: Integer read FId write FId;
    property Project: TProject read GetProject write SetProject;
    property User: TUser read GetUser write SetUser;
    property AccessLevel: TAccessLevel read FAccessLevel write FAccessLevel;
    property GrantedBy: Integer read FGrantedBy write FGrantedBy;
    property GrantedDate: TDateTime read FGrantedDate write FGrantedDate;
    property CanApproveProposals: Boolean read GetCanApproveProposals;
    property CanAcceptConclusions: Boolean read GetCanAcceptConclusions;
    procedure SetApproverFlags(AApproveProposals, AAcceptConclusions: Boolean);
    /// <summary>The raw flag values (NULL stays NULL).</summary>
    function ApproverFlagsSnapshot: TApproverFlagsSnapshot;
    /// <summary>Writes back a snapshot taken by ApproverFlagsSnapshot,
    /// NULL as NULL, so the entity again equals what was loaded and a later
    /// Flush issues no UPDATE. Like SetApproverFlags, called only by
    /// unit_ApproverGrants (test_HypothesisLinkage).</summary>
    procedure RestoreApproverFlags(const ASnapshot: TApproverFlagsSnapshot);
  end;

implementation

{ TProjectPermission }

function TProjectPermission.GetProject: TProject;
begin
  Result := FProject.Value;
end;

procedure TProjectPermission.SetProject(const Value: TProject);
begin
  FProject.Value := Value;
end;

function TProjectPermission.GetUser: TUser;
begin
  Result := FUser.Value;
end;

procedure TProjectPermission.SetUser(const Value: TUser);
begin
  FUser.Value := Value;
end;

function TProjectPermission.GetCanApproveProposals: Boolean;
begin
  Result := FCanApproveProposals.HasValue and FCanApproveProposals.Value;
end;

function TProjectPermission.GetCanAcceptConclusions: Boolean;
begin
  Result := FCanAcceptConclusions.HasValue and FCanAcceptConclusions.Value;
end;

procedure TProjectPermission.SetApproverFlags(AApproveProposals,
  AAcceptConclusions: Boolean);
begin
  FCanApproveProposals := AApproveProposals;
  FCanAcceptConclusions := AAcceptConclusions;
end;

function TProjectPermission.ApproverFlagsSnapshot: TApproverFlagsSnapshot;
begin
  Result.FApproveProposals := FCanApproveProposals;
  Result.FAcceptConclusions := FCanAcceptConclusions;
end;

procedure TProjectPermission.RestoreApproverFlags(
  const ASnapshot: TApproverFlagsSnapshot);
begin
  FCanApproveProposals := ASnapshot.FApproveProposals;
  FCanAcceptConclusions := ASnapshot.FAcceptConclusions;
end;

initialization
  RegisterEntity(TProjectPermission);

end.
