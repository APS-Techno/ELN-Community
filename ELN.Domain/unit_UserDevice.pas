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
  // Blank DeviceKind reads as web for credentials stored before schema v8.
  DEVICE_KIND_WEB = 'web';
  /// <summary>MCP key-file credential. Never accepted by /auth/refresh.</summary>
  DEVICE_KIND_MCP = 'mcp';

// Empty means unrestricted to callers. Writers must reject nonempty input
// that parses to no positive IDs, or malformed input could widen the scope.
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

    // Web cookies and MCP key files share the "<id>:<token>" shape. Check kind
    // to prevent key replay through /auth/refresh. Blank means legacy web;
    // MCP credentials must explicitly store 'mcp'.
    [Column('DeviceKind', [], 16)]
    FDeviceKind: string;

    // Empty means unrestricted. Keep scope server-side: the confined party
    // has shell access and could edit a scope stored in its key file.
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
