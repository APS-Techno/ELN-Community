unit unit_HypothesisStatusChange;


interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable,
  unit_Hypothesis;

type
  THypothesisStatusChange = class;
  THypothesisStatusChanges = TList<THypothesisStatusChange>;

  [Entity]
  [Table('HypothesisStatusHistory')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  THypothesisStatusChange = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('HypothesisId', [TColumnProp.Required])]
    FHypothesisId: Integer;

    [Column('OldStatus', [TColumnProp.Required])]
    FOldStatus: THypothesisStatus;

    [Column('NewStatus', [TColumnProp.Required])]
    FNewStatus: THypothesisStatus;

    [Column('ChangedBy', [TColumnProp.Required])]
    FChangedBy: Integer;

    [Column('ChangedDeviceId', [])]
    FChangedDeviceId: Nullable<Integer>;

    [Column('ChangedDate', [TColumnProp.Required])]
    FChangedDate: TDateTime;

    [Column('Comment', [], 500)]
    FComment: string;
  public
    property Id: Integer read FId write FId;
    property HypothesisId: Integer read FHypothesisId write FHypothesisId;
    property OldStatus: THypothesisStatus read FOldStatus write FOldStatus;
    property NewStatus: THypothesisStatus read FNewStatus write FNewStatus;
    property ChangedBy: Integer read FChangedBy write FChangedBy;
    property ChangedDeviceId: Nullable<Integer> read FChangedDeviceId write FChangedDeviceId;
    property ChangedDate: TDateTime read FChangedDate write FChangedDate;
    property Comment: string read FComment write FComment;
  end;

implementation

initialization
  RegisterEntity(THypothesisStatusChange);

end.
