unit unit_SeriesFixed;

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes;

type
  TSeriesFixed = class;
  TSeriesFixeds = TList<TSeriesFixed>;

  [Entity]
  [Table('SeriesFixedConditions')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [UniqueKey('SeriesId,ValueTypeId')]
  TSeriesFixed = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('SeriesId', [TColumnProp.Required])]
    FSeriesId: Integer;

    [Column('ValueTypeId', [TColumnProp.Required])]
    FValueTypeId: Integer;

    [Column('FixedValue', [])]
    FFixedValue: Double;

    [Column('Tol', [])]
    FTol: Double;

    [Column('EntryLabel', [], 100)]
    FEntryLabel: string;
  public
    property Id: Integer read FId write FId;
    property SeriesId: Integer read FSeriesId write FSeriesId;
    property ValueTypeId: Integer read FValueTypeId write FValueTypeId;
    property FixedValue: Double read FFixedValue write FFixedValue;
    property Tol: Double read FTol write FTol;
    property EntryLabel: string read FEntryLabel write FEntryLabel;
  end;

implementation

initialization
  RegisterEntity(TSeriesFixed);

end.
