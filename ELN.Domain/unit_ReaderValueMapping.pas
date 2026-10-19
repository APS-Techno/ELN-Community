unit unit_ReaderValueMapping;

interface

uses
  Aurelius.Mapping.Attributes,
  unit_ValueType;

type
  [Entity]
  [Table('ReaderValueMappings')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TReaderValueMapping = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;
    [Column('ReaderId', [TColumnProp.Required], 100)]
    FReaderId: string;
    [Column('KeyPattern', [TColumnProp.Required], 255)]
    FKeyPattern: string;
    [Column('ReaderUnits', [TColumnProp.Required], 100)]
    FReaderUnits: string;
    [Association([TAssociationProp.Required], [])]
    [JoinColumn('ValueTypeId', [TColumnProp.Required], 'Id')]
    FValueType: TValueType;
    [Column('Factor', [TColumnProp.Required])]
    FFactor: Double;
    [Column('Label', [], 255)]
    FLabel: string;
  public
    property Id: Integer read FId write FId;
    property ReaderId: string read FReaderId write FReaderId;
    property KeyPattern: string read FKeyPattern write FKeyPattern;
    property ReaderUnits: string read FReaderUnits write FReaderUnits;
    property ValueType: TValueType read FValueType write FValueType;
    property Factor: Double read FFactor write FFactor;
    property LabelText: string read FLabel write FLabel;
  end;

implementation

initialization
  RegisterEntity(TReaderValueMapping);
end.
