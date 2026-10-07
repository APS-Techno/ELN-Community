unit unit_LocalNotebook;

interface

uses
  System.SysUtils,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager,
  unit_NotebookStorage,
  unit_ProjectAccessPolicy,
  unit_User;

type
  ELocalNotebookError = class(Exception);

  // Independent local composition. Existing notebooks are never migrated here.
  // Initial format intentionally requires its own marker and one active identity.
  TLocalNotebook = class
  private
    FConnection: IDBConnection;
    FManager: TObjectManager;
    FPrincipal: TUser;
    FStorage: INotebookStorage;
    FAccessPolicy: IProjectAccessPolicy;
    constructor CreateFresh(const DatabasePath, StorageRoot, FirstName,
      LastName, SigningPassword: string);
    procedure Connect(const DatabasePath: string);
    procedure ReadPrincipal;
    class function CheckedDatabasePath(const DatabasePath: string): string; static;
    class function CheckedStorage(const DatabasePath, StorageRoot: string):
      INotebookStorage; static;
    class procedure CheckNoSidecars(const DatabasePath: string); static;
    class procedure CheckRollbackHeader(const DatabasePath: string); static;
    class procedure CheckEmptyStorageRoot(const StorageRoot: string); static;
  public
    constructor Open(const DatabasePath, StorageRoot: string);
    class function CreateNew(const DatabasePath, StorageRoot, FirstName,
      LastName, SigningPassword: string): TLocalNotebook; static;
    destructor Destroy; override;
    property Manager: TObjectManager read FManager;
    property Principal: TUser read FPrincipal;
    property Storage: INotebookStorage read FStorage;
    property Connection: IDBConnection read FConnection;
    property AccessPolicy: IProjectAccessPolicy read FAccessPolicy;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  Winapi.Windows,
  Aurelius.Drivers.SQLite,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Sql.SQLite,
  Aurelius.Sql.Register,
  Aurelius.Criteria.Linq,
  Bcrypt,
  unit_LocalNotebookStorage,
  unit_LocalProjectAccessPolicy,
  unit_DomainEntities,
  unit_DBSetting,
  unit_Project,
  unit_Item,
  unit_Protocol,
  unit_TimeHelper;

const
  LOCAL_FORMAT_KEY = 'COMMUNITY_FORMAT_VERSION';
  // Version 2 links the complete shared scientific entity catalog.
  LOCAL_FORMAT_VERSION = '2';

class function TLocalNotebook.CheckedDatabasePath(const DatabasePath: string): string;
var
  Directory: TLocalNotebookStorage;
begin
  Directory := TLocalNotebookStorage.Create(ExtractFilePath(DatabasePath));
  try
    Result := Directory.ResolvePath(ExtractFileName(DatabasePath));
  finally
    Directory.Free;
  end;
end;
class function TLocalNotebook.CheckedStorage(const DatabasePath,
  StorageRoot: string): INotebookStorage;
begin
  Result := TLocalNotebookStorage.Create(StorageRoot);
  if StartsText(IncludeTrailingPathDelimiter(TPath.GetFullPath(StorageRoot)),
    DatabasePath) then
    raise ELocalNotebookError.Create(
      'Notebook database must be outside the writable attachment directory');
end;


class procedure TLocalNotebook.CheckNoSidecars(const DatabasePath: string);
var
  Suffix, Path: string;
  Attributes, ErrorCode: DWORD;
begin
  for Suffix in ['-journal', '-wal', '-shm'] do
  begin
    Path := CheckedDatabasePath(DatabasePath + Suffix);
    Attributes := GetFileAttributes(PChar(Path));
    if Attributes <> INVALID_FILE_ATTRIBUTES then
      raise ELocalNotebookError.Create(
        'Close or recover the notebook in its owning client before opening it');
    ErrorCode := GetLastError;
    if not (ErrorCode in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND]) then
      RaiseLastOSError(ErrorCode);
  end;
end;

class procedure TLocalNotebook.CheckRollbackHeader(const DatabasePath: string);
const
  SQLiteSignature = 'SQLite format 3'#0;
var
  Stream: TFileStream;
  Header: array[0..19] of Byte;
  I: Integer;
begin
  Stream := TFileStream.Create(DatabasePath, fmOpenRead or fmShareDenyWrite);
  try
    Stream.ReadBuffer(Header, SizeOf(Header));
  finally
    Stream.Free;
  end;
  for I := 0 to Length(SQLiteSignature) - 1 do
    if Header[I] <> Ord(SQLiteSignature[I + 1]) then
      raise ELocalNotebookError.Create('Not a SQLite notebook');
  if (Header[18] <> 1) or (Header[19] <> 1) then
    raise ELocalNotebookError.Create(
      'Local notebooks require rollback-journal mode; conversion is required');
end;

procedure TLocalNotebook.Connect(const DatabasePath: string);
var
  Adapter: TSQLiteNativeConnectionAdapter;
  Generator: TSQLiteSQLGenerator;
begin
  Generator := TSQLiteSQLGenerator.Create;
  Generator.DateType := TSQLiteDateType.Text;
  TSQLGeneratorRegister.GetInstance.RegisterGenerator(Generator);
  Adapter := TSQLiteNativeConnectionAdapter.Create(DatabasePath);
  FConnection := Adapter;
  FConnection.Connect;
  Adapter.EnableForeignKeys;
  FManager := TObjectManager.Create(FConnection);
end;

class procedure TLocalNotebook.CheckEmptyStorageRoot(const StorageRoot: string);
var
  Root: string;
  Attributes: DWORD;
  Code: Integer;
  Search: TSearchRec;
begin
  Root := TPath.GetFullPath(StorageRoot);
  Attributes := GetFileAttributes(PChar(Root));
  if Attributes = INVALID_FILE_ATTRIBUTES then
  begin
    Code := GetLastError;
    if Code in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND] then
      Exit;
    RaiseLastOSError(Code);
  end;
  Code := FindFirst(IncludeTrailingPathDelimiter(Root) + '*', faAnyFile, Search);
  if Code = 0 then
  try
    repeat
      if (Search.Name <> '.') and (Search.Name <> '..') then
        raise ELocalNotebookError.Create(
          'A new notebook requires an empty attachment directory');
      Code := FindNext(Search);
    until Code <> 0;
  finally
    System.SysUtils.FindClose(Search);
  end;
  if not (Code in [ERROR_FILE_NOT_FOUND, ERROR_NO_MORE_FILES]) then
    RaiseLastOSError(Code);
end;

constructor TLocalNotebook.CreateFresh(const DatabasePath, StorageRoot,
  FirstName, LastName, SigningPassword: string);
var
  Path, PasswordHash: string;
  FileHandle: THandle;
  Database: TDatabaseManager;
  FormatSetting: TDBSetting;
begin
  inherited Create;
  if (Trim(FirstName + LastName) = '') or (SigningPassword = '') then
    raise EArgumentException.Create('Local profile and signing password are required');
  // Validate and hash before reserving a new file. No default password is used.
  Path := CheckedDatabasePath(DatabasePath);
  FStorage := CheckedStorage(Path, StorageRoot);
  CheckEmptyStorageRoot(StorageRoot);
  CheckNoSidecars(Path);
  PasswordHash := TBCrypt.HashPassword(SigningPassword);
  if not ForceDirectories(ExtractFileDir(Path)) then
    raise ELocalNotebookError.Create('Could not create notebook directory');
  Path := CheckedDatabasePath(Path);
  // CREATE_NEW is atomic: never truncate an existing database, including a race
  // with another creator. Failed creation leaves only our new file, never deletes.
  FileHandle := CreateFile(PChar(Path), GENERIC_READ or GENERIC_WRITE, 0, nil,
    CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  if FileHandle = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  CloseHandle(FileHandle);
  Connect(Path);
  Database := TDatabaseManager.Create(FConnection);
  try
    Database.BuildDatabase;
  finally
    Database.Free;
  end;
  FormatSetting := TDBSetting.Create;
  FormatSetting.SettingKey := LOCAL_FORMAT_KEY;
  FormatSetting.SettingValue := LOCAL_FORMAT_VERSION;
  FManager.Save(FormatSetting);
  FPrincipal := TUser.Create;
  FPrincipal.Username := 'local';
  FPrincipal.FirstName := FirstName;
  FPrincipal.LastName := LastName;
  FPrincipal.Password := PasswordHash;
  FPrincipal.Role := dbUser;
  FPrincipal.CreatedDate := UTCNow;
  FPrincipal.IsArchived := False;
  FManager.Save(FPrincipal);
  FManager.Flush;
  FAccessPolicy := TLocalProjectAccessPolicy.Create(FPrincipal.Id);
end;

class function TLocalNotebook.CreateNew(const DatabasePath, StorageRoot,
  FirstName, LastName, SigningPassword: string): TLocalNotebook;
begin
  Result := TLocalNotebook.CreateFresh(DatabasePath, StorageRoot, FirstName,
    LastName, SigningPassword);
end;

constructor TLocalNotebook.Open(const DatabasePath, StorageRoot: string);
var
  Path: string;
  FormatSetting: TDBSetting;
begin
  inherited Create;
  Path := CheckedDatabasePath(DatabasePath);
  if not System.IOUtils.TFile.Exists(Path) then
    raise EFileNotFoundException.Create('Local notebook database does not exist');
  FStorage := CheckedStorage(Path, StorageRoot);
  // The native adapter opens read/write. Refuse recovery and persisted WAL
  // mode before it can change a notebook or create sidecars during validation.
  CheckNoSidecars(Path);
  CheckRollbackHeader(Path);
  // No BuildDatabase, UpdateDatabase, migrations, account creation or role change.
  Connect(Path);
  FormatSetting := FManager.Find<TDBSetting>(LOCAL_FORMAT_KEY);
  if not Assigned(FormatSetting) or
    (FormatSetting.SettingValue <> LOCAL_FORMAT_VERSION) then
    raise ELocalNotebookError.Create('Unsupported local notebook format; conversion is required');
  ReadPrincipal;
  FAccessPolicy := TLocalProjectAccessPolicy.Create(FPrincipal.Id);
end;

procedure TLocalNotebook.ReadPrincipal;
var
  Users: TList<TUser>;
begin
  Users := FManager.Find<TUser>.Where(Linq['IsArchived'] = False).List;
  try
    if Users.Count <> 1 then
      raise ELocalNotebookError.Create('Local notebook requires exactly one active identity');
    FPrincipal := Users[0];
  finally
    Users.Free;
  end;
end;

destructor TLocalNotebook.Destroy;
var
  PriorShutdown: Boolean;
begin
  FPrincipal := nil;
  FAccessPolicy := nil;
  if Assigned(FManager) then
  begin
    PriorShutdown := ManagerShuttingDown;
    ManagerShuttingDown := True;
    try
      try
        FManager.Clear;
      finally
        FreeAndNil(FManager);
      end;
    finally
      ManagerShuttingDown := PriorShutdown;
    end;
  end;
  FConnection := nil;
  FStorage := nil;
  inherited Destroy;
end;

end.
