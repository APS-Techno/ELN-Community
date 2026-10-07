unit unit_SubmissionIdempotency;

interface

uses
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TSubmissionIdempotencyStatus = (sisInProgress, sisCompleted, sisFailed);

  [Entity]
  [Table('SubmissionIdempotency')]
  [Description('Idempotency-Key cache for POST /submissions (Plan 4).')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [UniqueKey('IdempotencyKey,UserId')]
  TSubmissionIdempotency = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('IdempotencyKey', [TColumnProp.Required], 36)]
    FIdempotencyKey: string;

    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('RequestHash', [TColumnProp.Required], 64)]
    FRequestHash: string;

    [Column('Status', [TColumnProp.Required])]
    FStatus: TSubmissionIdempotencyStatus;

    [Column('NewItemId', [])]
    FNewItemId: Nullable<Integer>;

    [Column('ResponseBody', [TColumnProp.Lazy], 65536)]
    FResponseBody: string;

    [Column('CreatedUTC', [TColumnProp.Required])]
    FCreatedUTC: TDateTime;

    [Column('CompletedUTC', [])]
    FCompletedUTC: Nullable<TDateTime>;
  public
    property Id: Integer read FId write FId;
    property IdempotencyKey: string read FIdempotencyKey write FIdempotencyKey;
    property UserId: Integer read FUserId write FUserId;
    property RequestHash: string read FRequestHash write FRequestHash;
    property Status: TSubmissionIdempotencyStatus read FStatus write FStatus;
    property NewItemId: Nullable<Integer> read FNewItemId write FNewItemId;
    property ResponseBody: string read FResponseBody write FResponseBody;
    property CreatedUTC: TDateTime read FCreatedUTC write FCreatedUTC;
    property CompletedUTC: Nullable<TDateTime> read FCompletedUTC write FCompletedUTC;
  end;

implementation

initialization
  RegisterEntity(TSubmissionIdempotency);

end.
