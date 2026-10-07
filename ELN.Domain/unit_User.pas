unit unit_User;

interface

uses
  SysUtils, 
  Generics.Collections, 
  Aurelius.Mapping.Attributes, 
  Aurelius.Types.Blob, 
  Aurelius.Types.DynamicProperties, 
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  unit_UsersHistory;

const
  DBRoleName : array of string = ['Guest', 'User', 'PowerUser', 'Supervisor', 'Admin'];

type

  [Enumeration(TEnumMappingType.emInteger)]
  TDBRole = (dbGuest, dbUser, dbPowerUser, dbSuper, dbAdmin);

  TUser = class;
  [Entity]
  [Table('Users')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TUser = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;
    
    [Column('Username', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('')]
    FUsername: string;
    
    [Column('Password', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('')]
    FPassword: string;

    [Column('FirstName', [TColumnProp.Lazy])]
    [Description('')]
    FFirstName: string;

    [Column('LastName', [TColumnProp.Lazy])]
    [Description('')]
    FLastName: string;

    [Column('Email', [TColumnProp.Lazy])]
    [Description('')]
    FEmail: string;

    [Column('Role', [TColumnProp.Required])]
    [Description('')]
    FRole: TDBRole;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('')]
    FModifiedBy: Nullable<Integer>;

    [Column('IsArchived', [TColumnProp.Required])]
    FIsArchived: Boolean;

    [Column('SortOrder', [TColumnProp.Required])]
    FSortOrder: Integer;

    // Nullable column (not Required) so the additive migration needs no
    // default for existing rows; NULL loads as False.
    [Column('TreeExpanded', [])]
    [Description('Whether this user''s node renders expanded in the supervisor project tree')]
    FTreeExpanded: Boolean;

    function GetRoleString: string;
    function GetDisplayName: string;
    function GetPathName: string;
  public
    constructor Create;
    property Id: Integer read FId write FId;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property FirstName: string read FFirstName write FFirstName;
    property LastName: string read FLastName write FLastName;
    property Email: string read FEmail write FEmail;
    property Role: TDBRole read FRole write FRole;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property IsArchived: Boolean read FIsArchived write FIsArchived;
    property SortOrder: Integer read FSortOrder write FSortOrder;
    property TreeExpanded: Boolean read FTreeExpanded write FTreeExpanded;
    property RoleString: string read GetRoleString;
    property DisplayName: string read GetDisplayName;
    property PathName: string read GetPathName;
  end;

/// <summary>True when Role is one of the five declared TDBRole values. The
/// column is a plain INT with no CHECK constraint and Aurelius loads it with a
/// bare ordinal cast, so a row written by hand or by an unvalidated import can
/// carry any number. Every allow-list gate must treat such a value as
/// "no role", never as "some role".</summary>
function IsKnownRole(Role: TDBRole): Boolean;

/// <summary>Display name for a role; safe for out-of-range ordinals, which
/// would otherwise overrun DBRoleName.</summary>
function RoleName(Role: TDBRole): string;

implementation

function IsKnownRole(Role: TDBRole): Boolean;
begin
  Result := Ord(Role) in [Ord(Low(TDBRole))..Ord(High(TDBRole))];
end;

function RoleName(Role: TDBRole): string;
begin
  if IsKnownRole(Role) then
    Result := DBRoleName[Ord(Role)]
  else
    Result := Format('Unknown(%d)', [Ord(Role)]);
end;

{ TUser }

constructor TUser.Create;
begin
  inherited;
  FIsArchived := False;
  FSortOrder := 0;
  FTreeExpanded := True;
end;

function TUser.GetDisplayName: string;
begin
  Result := FirstName + ' ' + LastName;
end;

function TUser.GetPathName: string;
begin
  Result := FirstName + ' ' + LastName;
end;

function TUser.GetRoleString: string;
begin
  Result := RoleName(Role);
end;

initialization
  RegisterEntity(TUser);

end.
