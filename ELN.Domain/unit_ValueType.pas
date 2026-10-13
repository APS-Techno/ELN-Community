unit unit_ValueType;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Blob,
  Aurelius.Types.DynamicProperties,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy;

type
  [Entity]
  [Table('ValueTypes')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TValueType = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    [Column('Symbol', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('Short physics notation (1-2 chars), e.g. W for power, I for current')]
    FSymbol: string;

    [Column('Title', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('')]
    FTitle: string;

    [Column('Units', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('')]
    FUnits: string;

    [Column('Description', [TColumnProp.Lazy])]
    [Description('')]
    FDescription: string;

    [Column('CatID', [TColumnProp.Lazy])]
    [Description('')]
    FCatID: integer;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('')]
    FModifiedBy: Nullable<Integer>;

    [Column('RangeMin', [])]
    [Description('Lowest plausible value in the type units; NULL means no lower limit')]
    FRangeMin: Nullable<Double>;

    [Column('RangeMax', [])]
    [Description('Highest plausible value in the type units; NULL means no upper limit')]
    FRangeMax: Nullable<Double>;

  public
    property Id: Integer read FId write FId;
    property Symbol: string read FSymbol write FSymbol;
    property Title: string read FTitle write FTitle;
    property Units: string read FUnits write FUnits;
    property CatID: integer read FCatID write FCatID;
    property Description: string read FDescription write FDescription;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property RangeMin: Nullable<Double> read FRangeMin write FRangeMin;
    property RangeMax: Nullable<Double> read FRangeMax write FRangeMax;
  end;

implementation

initialization
  RegisterEntity(TValueType);
end.
