unit unit_UsersHistory;

interface

uses
  SysUtils, 
  Generics.Collections, 
  Aurelius.Mapping.Attributes, 
  Aurelius.Types.Blob, 
  Aurelius.Types.DynamicProperties, 
  Aurelius.Types.Nullable, 
  Aurelius.Types.Proxy;

type
  TUsersHistory = class;

  [Entity]
  [Table('UsersHistory')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TUsersHistory = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    [Column('IserId', [TColumnProp.Required])]
    [Description('')]
    FUserId: Integer;

    [Column('LastProject', [TColumnProp.Required])]
    [Description('')]
    FLastProject: Integer;
    
    [Column('LastFolder', [TColumnProp.Required])]
    [Description('')]
    FLastFolder: Integer;
    
    [Column('LastItem', [TColumnProp.Required])]
    [Description('')]
    FLastItem: Integer;

    [Column('LastItemChildren', [TColumnProp.Required])]
    [Description('')]
    FLastChildren: Integer;
    
  public
    property Id: Integer read FId write FId;
    property UserID: integer read FUserID write FUserID;
    property LastProject: Integer read FLastProject write FLastProject;
    property LastFolder: Integer read FLastFolder write FLastFolder;
    property LastItem: Integer read FLastItem write FLastItem;
    property LastChild: Integer read FLastChildren write FLastChildren;
  end;

implementation

{ TUsersHistory }

initialization
  RegisterEntity(TUsersHistory);

end.
