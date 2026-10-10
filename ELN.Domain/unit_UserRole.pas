unit unit_UserRole;

interface

uses
  SysUtils, 
  Generics.Collections, 
  Aurelius.Mapping.Attributes, 
  Aurelius.Types.Blob, 
  Aurelius.Types.DynamicProperties, 
  Aurelius.Types.Nullable, 
  Aurelius.Types.Proxy, 
  unit_Project,
  unit_User;

type
  TUserRole = class;
  
  [Entity]
  [Table('UserRoles')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TUserRole = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;
    
    [Column('Role', [TColumnProp.Required])]
    [Description('')]
    FRole: Integer;
    
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
    
    // This reference is not owned here. Cascading Evict would leave a stale
    // shared instance and cause EObjectAlreadyPersistent on a later save.
    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('ProjectId', [TColumnProp.Required], 'Id')]
    [Description('')]
    FProject: Proxy<TProject>;
    
    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('UserID', [TColumnProp.Required], 'Id')]
    [Description('')]
    FUser: Proxy<TUser>;
    function GetProject: TProject;
    procedure SetProject(const Value: TProject);
    function GetUser: TUser;
    procedure SetUser(const Value: TUser);
  public
    property Id: Integer read FId write FId;
    property Role: Integer read FRole write FRole;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property Project: TProject read GetProject write SetProject;
    property User: TUser read GetUser write SetUser;
  end;
  
implementation


function TUserRole.GetProject: TProject;
begin
  result := FProject.Value;
end;

procedure TUserRole.SetProject(const Value: TProject);
begin
  FProject.Value := Value;
end;

function TUserRole.GetUser: TUser;
begin
  result := FUser.Value;
end;

procedure TUserRole.SetUser(const Value: TUser);
begin
  FUser.Value := Value;
end;

initialization
  RegisterEntity(TUserRole);

end.
