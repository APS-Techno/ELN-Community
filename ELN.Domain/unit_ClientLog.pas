unit unit_ClientLog;

interface

uses
  System.SysUtils,
  Aurelius.Mapping.Attributes;

type
  [Entity]
  [Table('ClientLog')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TClientLog = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Int64;

    // Keep the FK width compatible with Users.Id even though this row's Id is Int64.
    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('Route', [], 128)]
    FRoute: string;

    [Column('Message', [], 1024)]
    FMessage: string;

    [Column('Stack', [TColumnProp.Lazy], 8192)]
    FStack: string;

    [Column('UserAgent', [], 512)]
    FUserAgent: string;

    [Column('TsUtc', [TColumnProp.Required])]
    FTsUtc: TDateTime;
  public
    property Id: Int64 read FId write FId;
    property UserId: Integer read FUserId write FUserId;
    property Route: string read FRoute write FRoute;
    property Message_: string read FMessage write FMessage;
    property Stack: string read FStack write FStack;
    property UserAgent: string read FUserAgent write FUserAgent;
    property TsUtc: TDateTime read FTsUtc write FTsUtc;
  end;

implementation

initialization
  RegisterEntity(TClientLog);

end.
