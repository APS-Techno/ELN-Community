unit unit_ItemLink;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Proxy,
  unit_LinkType;

type
  TItemLink = class;
  TItemLinks = TList<TItemLink>;

  [Entity]
  [Table('ItemLinks')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TItemLink = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('SourceItemId', [TColumnProp.Required])]
    FSourceItemId: Integer;

    [Column('TargetItemId', [TColumnProp.Required])]
    FTargetItemId: Integer;

    [Association([], [])]
    [JoinColumn('LinkTypeId', [], 'Id')]
    FLinkType: Proxy<TLinkType>;

    [Column('Label', [TColumnProp.Required], 200)]
    FLabel: string;

    [Column('Notes', [], 1000)]
    FNotes: string;

    [Column('CreatedBy', [TColumnProp.Required])]
    FCreatedBy: Integer;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    function GetLinkType: TLinkType;
    procedure SetLinkType(const Value: TLinkType);
  public
    property Id: Integer read FId write FId;
    property SourceItemId: Integer read FSourceItemId write FSourceItemId;
    property TargetItemId: Integer read FTargetItemId write FTargetItemId;
    property LinkType: TLinkType read GetLinkType write SetLinkType;
    property Label_: string read FLabel write FLabel;
    property Notes: string read FNotes write FNotes;
    property CreatedBy: Integer read FCreatedBy write FCreatedBy;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
  end;

implementation


function TItemLink.GetLinkType: TLinkType;
begin
  Result := FLinkType.Value;
end;

procedure TItemLink.SetLinkType(const Value: TLinkType);
begin
  FLinkType.Value := Value;
end;

initialization
  RegisterEntity(TItemLink);

end.
