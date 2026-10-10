unit unit_LinkType;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  TLinkType = class;
  TLinkTypes = TList<TLinkType>;

  [Entity]
  [Table('LinkTypes')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TLinkType = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('ForwardText', [TColumnProp.Required], 100)]
    FForwardText: string;

    [Column('ReverseText', [TColumnProp.Required], 100)]
    FReverseText: string;

    [Column('Description', [], 500)]
    FDescription: string;

    [Column('SortOrder', [TColumnProp.Required])]
    FSortOrder: Integer;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    FModifiedBy: Nullable<Integer>;
  public
    property Id: Integer read FId write FId;
    property ForwardText: string read FForwardText write FForwardText;
    property ReverseText: string read FReverseText write FReverseText;
    property Description: string read FDescription write FDescription;
    property SortOrder: Integer read FSortOrder write FSortOrder;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    function IsSymmetric: Boolean;
  end;

implementation


function TLinkType.IsSymmetric: Boolean;
begin
  Result := SameText(Trim(FForwardText), Trim(FReverseText));
end;

initialization
  RegisterEntity(TLinkType);

end.
