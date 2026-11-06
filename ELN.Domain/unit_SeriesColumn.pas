unit unit_SeriesColumn;

{ Column 'ColumnRole', not 'Role': ROLE is a keyword in MySQL 8. }

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  unit_ItemTypes;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TSeriesColumnRole = (scrShown, scrHidden, scrVaried, scrResponse, scrFixed);

  TSeriesColumn = class;
  TSeriesColumns = TList<TSeriesColumn>;

  [Entity]
  [Table('SeriesColumns')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [UniqueKey('SeriesId,RecType,ValueTypeId,SourceKey')]
  TSeriesColumn = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('SeriesId', [TColumnProp.Required])]
    FSeriesId: Integer;

    [Column('RecType', [TColumnProp.Required])]
    FRecType: TRecType;

    [Column('ValueTypeId', [TColumnProp.Required])]
    FValueTypeId: Integer;

    [Column('SourceKey', [TColumnProp.Required], 64)]
    FSourceKey: string;

    [Column('ColumnRole', [TColumnProp.Required])]
    FRole: TSeriesColumnRole;

    [Column('SortOrder', [TColumnProp.Required])]
    FSortOrder: Integer;

    [Column('EntryLabel', [], 100)]
    FEntryLabel: string;
  public
    property Id: Integer read FId write FId;
    property SeriesId: Integer read FSeriesId write FSeriesId;
    property RecType: TRecType read FRecType write FRecType;
    property ValueTypeId: Integer read FValueTypeId write FValueTypeId;
    property SourceKey: string read FSourceKey write FSourceKey;
    property Role: TSeriesColumnRole read FRole write FRole;
    property SortOrder: Integer read FSortOrder write FSortOrder;
    property EntryLabel: string read FEntryLabel write FEntryLabel;
  end;

implementation

initialization
  RegisterEntity(TSeriesColumn);

end.
