unit unit_Comment;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  TComment = class;
  TComments = TList<TComment>;

  [Entity]
  [Table('Comments')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TComment = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('ItemId', [TColumnProp.Required])]
    FItemId: Integer;

    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('UserName', [TColumnProp.Required], 100)]
    FUserName: string;

    [Column('Text', [TColumnProp.Required], 2000)]
    FText: string;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    FModifiedDate: Nullable<TDateTime>;

    [Column('Version', [TColumnProp.Required])]
    FVersion: Integer;
  public
    property Id: Integer read FId write FId;
    property ItemId: Integer read FItemId write FItemId;
    property UserId: Integer read FUserId write FUserId;
    property UserName: string read FUserName write FUserName;
    property Text: string read FText write FText;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property Version: Integer read FVersion write FVersion;
  end;

implementation

initialization
  RegisterEntity(TComment);

end.
