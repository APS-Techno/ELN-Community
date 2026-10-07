unit unit_ProtocolStatusChange;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable,
  unit_Protocol;

type
  TProtocolStatusChange = class;
  TProtocolStatusChanges = TList<TProtocolStatusChange>;

  [Entity]
  [Table('ProtocolStatusHistory')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TProtocolStatusChange = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('ProtocolId', [TColumnProp.Required])]
    FProtocolId: Integer;

    [Column('OldStatus', [TColumnProp.Required])]
    FOldStatus: TValidationStatus;

    [Column('NewStatus', [TColumnProp.Required])]
    FNewStatus: TValidationStatus;

    [Column('ChangedBy', [TColumnProp.Required])]
    FChangedBy: Integer;

    [Column('ChangedDate', [TColumnProp.Required])]
    FChangedDate: TDateTime;

    [Column('Comment', [], 500)]
    FComment: string;
  public
    property Id: Integer read FId write FId;
    property ProtocolId: Integer read FProtocolId write FProtocolId;
    property OldStatus: TValidationStatus read FOldStatus write FOldStatus;
    property NewStatus: TValidationStatus read FNewStatus write FNewStatus;
    property ChangedBy: Integer read FChangedBy write FChangedBy;
    property ChangedDate: TDateTime read FChangedDate write FChangedDate;
    property Comment: string read FComment write FComment;
  end;

implementation

initialization
  RegisterEntity(TProtocolStatusChange);

end.
