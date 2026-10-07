unit unit_HypothesisRun;

{ A run item attached to a hypothesis. Run = same project as the hypothesis;
  Reference = any project the author can read. Column 'RunRole': ROLE is a
  keyword in MySQL 8. }

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  unit_Hypothesis;

type
  THypothesisRun = class;
  THypothesisRuns = TList<THypothesisRun>;

  [Entity]
  [Table('HypothesisRuns')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [DBIndex('IX_HypothesisRuns_ItemId', 'ItemId')]
  [UniqueKey('HypothesisId,ItemId')]
  THypothesisRun = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('HypothesisId', [TColumnProp.Required])]
    FHypothesisId: Integer;

    [Column('ItemId', [TColumnProp.Required])]
    FItemId: Integer;

    [Column('RunRole', [TColumnProp.Required])]
    FRole: THypothesisRunRole;

    [Column('AddedBy', [TColumnProp.Required])]
    FAddedBy: Integer;

    [Column('AddedDate', [TColumnProp.Required])]
    FAddedDate: TDateTime;
  public
    property Id: Integer read FId write FId;
    property HypothesisId: Integer read FHypothesisId write FHypothesisId;
    property ItemId: Integer read FItemId write FItemId;
    property Role: THypothesisRunRole read FRole write FRole;
    property AddedBy: Integer read FAddedBy write FAddedBy;
    property AddedDate: TDateTime read FAddedDate write FAddedDate;
  end;

implementation

initialization
  RegisterEntity(THypothesisRun);

end.
