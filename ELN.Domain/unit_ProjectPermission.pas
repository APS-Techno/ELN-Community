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

  // Preserve NULL exactly so failed flag writes can restore the loaded state.
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

    // This reference is not owned here. Cascading Evict would leave a stale
    // shared instance and cause EObjectAlreadyPersistent on a later save.
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

    // NULL means false. Only unit_ApproverGrants may call the flag setters.
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
    function ApproverFlagsSnapshot: TApproverFlagsSnapshot;
    // Restore NULL as NULL so a later Flush does not persist a failed change.
    // Like SetApproverFlags, called only by unit_ApproverGrants.
    procedure RestoreApproverFlags(const ASnapshot: TApproverFlagsSnapshot);
  end;

implementation


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
