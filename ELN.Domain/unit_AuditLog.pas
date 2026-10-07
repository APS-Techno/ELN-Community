unit unit_AuditLog;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TAuditEntityType = (aetProject, aetFolder, aetItem, aetFile, aetProtocol, aetNote, aetValue, aetSignature, aetProjectGroup, aetHypothesis, aetSetting);

  [Enumeration(TEnumMappingType.emInteger)]
  TAuditOperation = (aoCreate, aoUpdate, aoDelete);

  TAuditLog = class;
  TAuditLogs = TList<TAuditLog>;

  [Entity]
  [Table('AuditLog')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TAuditLog = class
  private
    // Append-only table: one row per create/update/delete across the whole
    // system. A 32-bit signed identity overflows at 2.1B rows; BIGINT gives
    // ~9.2 * 10^18, effectively unbounded for the product lifetime.
    // EntityId stays Integer because it FKs into Items/Projects/Users which
    // still use 32-bit identities.
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Int64;

    [Column('EntityType', [TColumnProp.Required])]
    FEntityType: TAuditEntityType;

    [Column('EntityId', [TColumnProp.Required])]
    FEntityId: Integer;

    [Column('Operation', [TColumnProp.Required])]
    FOperation: TAuditOperation;

    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('Timestamp', [TColumnProp.Required])]
    FTimestamp: TDateTime;

    [Column('Description', [], 500)]
    FDescription: string;
  public
    property Id: Int64 read FId write FId;
    property EntityType: TAuditEntityType read FEntityType write FEntityType;
    property EntityId: Integer read FEntityId write FEntityId;
    property Operation: TAuditOperation read FOperation write FOperation;
    property UserId: Integer read FUserId write FUserId;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property Description: string read FDescription write FDescription;
  end;

const
  AuditEntityTypeNames: array[TAuditEntityType] of string = (
    'Project', 'Folder', 'Item', 'File', 'Protocol', 'Note', 'Value', 'Signature', 'Project Group', 'Hypothesis', 'Setting');

  AuditOperationNames: array[TAuditOperation] of string = (
    'Create', 'Update', 'Delete');

implementation

initialization
  RegisterEntity(TAuditLog);

end.
