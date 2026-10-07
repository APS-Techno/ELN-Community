unit unit_Signature;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  TSignature = class;
  TSignatures = TList<TSignature>;

  [Entity]
  [Table('Signatures')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TSignature = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('ItemId', [TColumnProp.Required])]
    FItemId: Integer;

    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('UserName', [TColumnProp.Required], 200)]
    FUserName: string;

    [Column('SignedDate', [TColumnProp.Required])]
    FSignedDate: TDateTime;

    [Column('Meaning', [TColumnProp.Required], 50)]
    FMeaning: string;

    [Column('Comment', [], 500)]
    FComment: string;

    [Column('ContentHash', [TColumnProp.Required], 64)]
    FContentHash: string;
  public
    property Id: Integer read FId write FId;
    property ItemId: Integer read FItemId write FItemId;
    property UserId: Integer read FUserId write FUserId;
    property UserName: string read FUserName write FUserName;
    property SignedDate: TDateTime read FSignedDate write FSignedDate;
    property Meaning: string read FMeaning write FMeaning;
    property Comment: string read FComment write FComment;
    property ContentHash: string read FContentHash write FContentHash;
  end;

implementation

initialization
  RegisterEntity(TSignature);

end.
