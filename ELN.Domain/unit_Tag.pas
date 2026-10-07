unit unit_Tag;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  TTag = class;
  TItemTag = class;
  TTags = TList<TTag>;
  TItemTags = TList<TItemTag>;

  [Entity]
  [Table('Tags')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TTag = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('Name', [TColumnProp.Required], 100)]
    FName: string;

    [Column('Color', [], 20)]
    FColor: string;

    [Column('CreatedBy', [TColumnProp.Required])]
    FCreatedBy: Integer;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;
  public
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Color: string read FColor write FColor;
    property CreatedBy: Integer read FCreatedBy write FCreatedBy;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
  end;

  [Entity]
  [Table('ItemTags')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TItemTag = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('ItemId', [TColumnProp.Required])]
    FItemId: Integer;

    [Column('TagId', [TColumnProp.Required])]
    FTagId: Integer;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;
  public
    property Id: Integer read FId write FId;
    property ItemId: Integer read FItemId write FItemId;
    property TagId: Integer read FTagId write FTagId;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
  end;

implementation

initialization
  RegisterEntity(TTag);
  RegisterEntity(TItemTag);

end.
