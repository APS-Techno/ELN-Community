unit unit_SeriesSlot;

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TSeriesSlotOrigin = (ssoPlanned, ssoAdded);

  TSeriesSlot = class;
  TSeriesSlots = TList<TSeriesSlot>;
  TSeriesSlotLevel = class;
  TSeriesSlotLevels = TList<TSeriesSlotLevel>;

  [Entity]
  [Table('SeriesSlots')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [DBIndex('IX_SeriesSlots_SeriesId', 'SeriesId')]
  TSeriesSlot = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('SeriesId', [TColumnProp.Required])]
    FSeriesId: Integer;

    [Column('Origin', [TColumnProp.Required])]
    FOrigin: TSeriesSlotOrigin;

    [Column('AddedBy', [])]
    FAddedBy: Integer;

    [Column('AddedDate', [])]
    FAddedDate: TDateTime;

    [Column('Reason', [], 500)]
    FReason: string;
  public
    property Id: Integer read FId write FId;
    property SeriesId: Integer read FSeriesId write FSeriesId;
    property Origin: TSeriesSlotOrigin read FOrigin write FOrigin;
    property AddedBy: Integer read FAddedBy write FAddedBy;
    property AddedDate: TDateTime read FAddedDate write FAddedDate;
    property Reason: string read FReason write FReason;
  end;

  [Entity]
  [Table('SeriesSlotLevels')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [DBIndex('IX_SeriesSlotLevels_SlotId', 'SlotId')]
  [UniqueKey('SlotId,FactorId')]
  TSeriesSlotLevel = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('SlotId', [TColumnProp.Required])]
    FSlotId: Integer;

    [Column('FactorId', [TColumnProp.Required])]
    FFactorId: Integer;

    [Column('LevelValue', [])]
    FLevelValue: Double;
  public
    property Id: Integer read FId write FId;
    property SlotId: Integer read FSlotId write FSlotId;
    property FactorId: Integer read FFactorId write FFactorId;
    property LevelValue: Double read FLevelValue write FLevelValue;
  end;

implementation

initialization
  RegisterEntity(TSeriesSlot);
  RegisterEntity(TSeriesSlotLevel);

end.
