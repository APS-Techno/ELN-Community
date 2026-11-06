unit unit_SeriesMember;

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TSeriesAttemptState = (satValid, satFailed);

  TSeriesMember = class;
  TSeriesMembers = TList<TSeriesMember>;

  [Entity]
  [Table('SeriesMembers')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [DBIndex('IX_SeriesMembers_ItemId', 'ItemId')]
  [UniqueKey('SeriesId,ItemId')]
  TSeriesMember = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('SeriesId', [TColumnProp.Required])]
    FSeriesId: Integer;

    [Column('ItemId', [TColumnProp.Required])]
    FItemId: Integer;

    [Column('SlotId', [])]
    FSlotId: Nullable<Integer>;

    [Column('AttemptState', [TColumnProp.Required])]
    FAttemptState: TSeriesAttemptState;

    [Column('FailReason', [], 500)]
    FFailReason: string;

    [Column('AddedBy', [])]
    FAddedBy: Integer;

    [Column('AddedDate', [])]
    FAddedDate: TDateTime;
  public
    property Id: Integer read FId write FId;
    property SeriesId: Integer read FSeriesId write FSeriesId;
    property ItemId: Integer read FItemId write FItemId;
    property SlotId: Nullable<Integer> read FSlotId write FSlotId;
    property AttemptState: TSeriesAttemptState read FAttemptState write FAttemptState;
    property FailReason: string read FFailReason write FFailReason;
    property AddedBy: Integer read FAddedBy write FAddedBy;
    property AddedDate: TDateTime read FAddedDate write FAddedDate;
  end;

implementation

initialization
  RegisterEntity(TSeriesMember);

end.
