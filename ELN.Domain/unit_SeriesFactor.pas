unit unit_SeriesFactor;

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  TSeriesFactor = class;
  TSeriesFactors = TList<TSeriesFactor>;

  [Entity]
  [Table('SeriesFactors')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [UniqueKey('SeriesId,ValueTypeId')]
  TSeriesFactor = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('SeriesId', [TColumnProp.Required])]
    FSeriesId: Integer;

    [Column('ValueTypeId', [TColumnProp.Required])]
    FValueTypeId: Integer;

    [Column('RangeMin', [])]
    FRangeMin: Nullable<Double>;

    [Column('RangeMax', [])]
    FRangeMax: Nullable<Double>;

    [Column('ApprovedMin', [])]
    FApprovedMin: Nullable<Double>;

    [Column('ApprovedMax', [])]
    FApprovedMax: Nullable<Double>;

    [Column('SortOrder', [TColumnProp.Required])]
    FSortOrder: Integer;

    [Column('EntryLabel', [], 100)]
    FEntryLabel: string;
  public
    property Id: Integer read FId write FId;
    property SeriesId: Integer read FSeriesId write FSeriesId;
    property ValueTypeId: Integer read FValueTypeId write FValueTypeId;
    property RangeMin: Nullable<Double> read FRangeMin write FRangeMin;
    property RangeMax: Nullable<Double> read FRangeMax write FRangeMax;
    property ApprovedMin: Nullable<Double> read FApprovedMin write FApprovedMin;
    property ApprovedMax: Nullable<Double> read FApprovedMax write FApprovedMax;
    property SortOrder: Integer read FSortOrder write FSortOrder;
    property EntryLabel: string read FEntryLabel write FEntryLabel;
  end;

implementation

initialization
  RegisterEntity(TSeriesFactor);

end.
