unit unit_HypothesisEvidence;

{ One citation the conclusion rests on: an item as a whole, one of its files,
  or one of its values. FileHash and ValueSnapshot are copied by the server at
  citation time and never supplied by a caller; they let the dashboard flag
  evidence that changed afterwards. FileId is Int64 because Files.Id is. }

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  THypothesisEvidence = class;
  THypothesisEvidenceList = TList<THypothesisEvidence>;

  [Entity]
  [Table('HypothesisEvidence')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [DBIndex('IX_HypothesisEvidence_ItemId', 'ItemId')]
  THypothesisEvidence = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('HypothesisId', [TColumnProp.Required])]
    FHypothesisId: Integer;

    [Column('ItemId', [TColumnProp.Required])]
    FItemId: Integer;

    [Column('FileId', [])]
    FFileId: Nullable<Int64>;

    [Column('ValueId', [])]
    FValueId: Nullable<Integer>;

    [Column('Note', [], 500)]
    FNote: string;

    [Column('FileHash', [], 32)]
    FFileHash: string;

    [Column('ValueSnapshot', [])]
    FValueSnapshot: Nullable<Double>;

    [Column('AddedBy', [TColumnProp.Required])]
    FAddedBy: Integer;

    [Column('AddedDate', [TColumnProp.Required])]
    FAddedDate: TDateTime;
  public
    property Id: Integer read FId write FId;
    property HypothesisId: Integer read FHypothesisId write FHypothesisId;
    property ItemId: Integer read FItemId write FItemId;
    property FileId: Nullable<Int64> read FFileId write FFileId;
    property ValueId: Nullable<Integer> read FValueId write FValueId;
    property Note: string read FNote write FNote;
    property FileHash: string read FFileHash write FFileHash;
    property ValueSnapshot: Nullable<Double> read FValueSnapshot write FValueSnapshot;
    property AddedBy: Integer read FAddedBy write FAddedBy;
    property AddedDate: TDateTime read FAddedDate write FAddedDate;
  end;

implementation

initialization
  RegisterEntity(THypothesisEvidence);

end.
