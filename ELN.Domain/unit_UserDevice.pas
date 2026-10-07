unit unit_UserDevice;

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Blob,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  unit_User;

const
  /// <summary>WebAPI refresh-cookie credential. Also the reading for a blank
  /// column, so rows written before schema v8 stay web credentials.</summary>
  DEVICE_KIND_WEB = 'web';
  /// <summary>MCP key-file credential. Never accepted by /auth/refresh.</summary>
  DEVICE_KIND_MCP = 'mcp';

/// <summary>Splits a stored ProjectScope into project ids. Anything that is
/// not a positive integer is DROPPED, never treated as a wildcard: an empty
/// result means "unrestricted" to callers, so a malformed entry must shrink
/// the scope, never widen it. Callers that write a scope are responsible for
/// refusing input that parses to nothing.</summary>
function ParseProjectScope(const AScope: string): TArray<Integer>;

type
  TUserDevice = class;
  TUserDevices = TList<TUserDevice>;

  [Entity]
  [Table('UserDevices')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TUserDevice = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Association([TAssociationProp.Required], [])]
    [JoinColumn('UserId', [TColumnProp.Required], 'Id')]
    FUser: Proxy<TUser>;

    [Column('DeviceLabel', [TColumnProp.Required], 120)]
    FDeviceLabel: string;

    [Column('RefreshTokenHash', [TColumnProp.Required], 120)]
    FRefreshTokenHash: string;

    [Column('WebauthnCredentialId', [])]
    FWebauthnCredentialId: TBlob;

    [Column('WebauthnPublicKey', [])]
    FWebauthnPublicKey: TBlob;

    [Column('CreatedUtc', [TColumnProp.Required])]
    FCreatedUtc: TDateTime;

    [Column('LastUsedUtc', [TColumnProp.Required])]
    FLastUsedUtc: TDateTime;

    [Column('RevokedUtc', [])]
    FRevokedUtc: Nullable<TDateTime>;

    // Which subsystem this credential belongs to. The WebAPI refresh cookie
    // and the MCP key file are the SAME secret shape ("<id>:<token>"), so
    // without this a key file could be replayed as an eln_rt cookie against
    // /auth/refresh and exchanged for a role-bearing JWT - escaping the MCP
    // tool surface entirely. Empty is read as 'web' so pre-v8 rows keep
    // working; an MCP key must be explicitly 'mcp', which means an old row
    // can never be used as one.
    [Column('DeviceKind', [], 16)]
    FDeviceKind: string;

    // Comma-separated project ids this credential may read. Empty means
    // unrestricted. Server-side on purpose: the confined party has shell
    // access, so a scope kept in the key file would be self-asserted.
    [Column('ProjectScope', [], 255)]
    FProjectScope: string;

    function GetUser: TUser;
    procedure SetUser(const Value: TUser);
  public
    property Id: Integer read FId write FId;
    property User: TUser read GetUser write SetUser;
    property DeviceLabel: string read FDeviceLabel write FDeviceLabel;
    property RefreshTokenHash: string read FRefreshTokenHash write FRefreshTokenHash;
    property WebauthnCredentialId: TBlob read FWebauthnCredentialId write FWebauthnCredentialId;
    property WebauthnPublicKey: TBlob read FWebauthnPublicKey write FWebauthnPublicKey;
    property CreatedUtc: TDateTime read FCreatedUtc write FCreatedUtc;
    property LastUsedUtc: TDateTime read FLastUsedUtc write FLastUsedUtc;
    property RevokedUtc: Nullable<TDateTime> read FRevokedUtc write FRevokedUtc;
    property DeviceKind: string read FDeviceKind write FDeviceKind;
    property ProjectScope: string read FProjectScope write FProjectScope;
  end;

implementation

uses
  System.SysUtils, Aurelius.Engine.ObjectManager;

function ParseProjectScope(const AScope: string): TArray<Integer>;
var
  Parts: TArray<string>;
  Part: string;
  N: Integer;
  Buf: TList<Integer>;
begin
  Result := nil;
  if Trim(AScope) = '' then
    Exit;
  Buf := TList<Integer>.Create;
  try
    Parts := AScope.Split([',']);
    for Part in Parts do
      if TryStrToInt(Trim(Part), N) and (N > 0) then
        Buf.Add(N);
    Result := Buf.ToArray;
  finally
    Buf.Free;
  end;
end;

function TUserDevice.GetUser: TUser;
begin
  Result := FUser.Value;
end;

procedure TUserDevice.SetUser(const Value: TUser);
begin
  FUser.Value := Value;
end;

initialization
  RegisterEntity(TUserDevice);

end.
