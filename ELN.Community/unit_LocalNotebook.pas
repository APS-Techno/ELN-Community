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
  ELocalNotebookUpgradeRequired = class(ELocalNotebookError);
  ELocalNotebookStorageRequired = class(ELocalNotebookError);
  ELocalNotebookStorageUnavailable = class(ELocalNotebookStorageRequired);

  // Open validates and never migrates; Upgrade is the only path that alters
  // an existing notebook, and it copies the database first.
  TLocalNotebook = class
  private
    FConnection: IDBConnection;
    FManager: TObjectManager;
    FPrincipal: TUser;
    FStorage: INotebookStorage;
    FAccessPolicy: IProjectAccessPolicy;
    FDatabasePath: string;
    FStorageRoot: string;
    constructor CreateFresh(const DatabasePath, StorageRoot, FirstName,
      LastName, SigningPassword: string);
    procedure Connect(const DatabasePath: string);
    constructor CreateForUpgrade(const DatabasePath: string);
    procedure VerifyCurrentSchema;
    procedure ReadPrincipal;
    class function CheckedDatabasePath(const DatabasePath: string): string; static;
    class function CheckedStorage(const DatabasePath, StorageRoot: string):
      INotebookStorage; static;
    class procedure CheckNoSidecars(const DatabasePath: string); static;
    class procedure CheckRollbackHeader(const DatabasePath: string); static;
    class procedure CheckEmptyStorageRoot(const StorageRoot: string); static;
    procedure UseStorageRoot(const StorageRoot: string);
    procedure UseSavedStorageRoot;
    function StorageSettingValue: string;
  public
    // An empty StorageRoot uses the attachment directory saved in the notebook.
    constructor Open(const DatabasePath, StorageRoot: string);
    class function CreateNew(const DatabasePath, StorageRoot, FirstName,
      LastName, SigningPassword: string): TLocalNotebook; static;
    class function Upgrade(const DatabasePath: string): string; static;
    destructor Destroy; override;
    function CanRememberStorageRoot: Boolean;
    procedure RememberStorageRoot;
    property Manager: TObjectManager read FManager;
    property Principal: TUser read FPrincipal;
    property Storage: INotebookStorage read FStorage;
    property Connection: IDBConnection read FConnection;
    property DatabasePath: string read FDatabasePath;
    property StorageRoot: string read FStorageRoot;
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
  unit_TimeHelper,
  unit_ReaderValueMappingModel,
  unit_SchemaUpdate;

const
  LOCAL_FORMAT_KEY = 'COMMUNITY_FORMAT_VERSION';
  LOCAL_FORMAT_VERSION = '5';
  LOCAL_STORAGE_KEY = 'COMMUNITY_ATTACHMENT_DIR';

function IsAbsoluteDirectory(const Path: string): Boolean;
begin
  Result := ((Length(Path) >= 3) and (Path[2] = ':') and (Path[3] = '\')) or
    StartsStr('\\', Path);
end;

function IsUpgradableFormat(const Stored: string): Boolean;
begin
  Result := (Stored = '2') or (Stored = '3') or (Stored = '4');
end;

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

procedure TLocalNotebook.UseStorageRoot(const StorageRoot: string);
begin
  FStorage := CheckedStorage(FDatabasePath, StorageRoot);
  FStorageRoot := TPath.GetFullPath(StorageRoot);
end;

procedure TLocalNotebook.UseSavedStorageRoot;
var
  Setting: TDBSetting;
  Saved, Root: string;
begin
  Setting := FManager.Find<TDBSetting>(LOCAL_STORAGE_KEY);
  if not Assigned(Setting) or (Setting.SettingValue = '') then
    raise ELocalNotebookStorageRequired.Create(
      'This notebook has no saved attachment directory');
  Saved := Setting.SettingValue.Replace('/', '\');
  try
    if IsAbsoluteDirectory(Saved) then
      Root := TPath.GetFullPath(Saved)
    else if (Pos(':', Saved) > 0) or (Saved[1] = '\') then
      raise EArgumentException.Create('A drive-relative path is ambiguous')
    else
      Root := TPath.GetFullPath(TPath.Combine(ExtractFileDir(FDatabasePath), Saved));
  except
    on E: EArgumentException do
      raise ELocalNotebookStorageUnavailable.Create(
        'The saved attachment directory is not valid: ' + Setting.SettingValue);
  end;
  if not TDirectory.Exists(Root) then
    raise ELocalNotebookStorageUnavailable.Create(
      'The saved attachment directory does not exist: ' + Root);
  try
    UseStorageRoot(Root);
  except
    on E: Exception do
      raise ELocalNotebookStorageUnavailable.Create(
        'The saved attachment directory cannot be used: ' + E.Message);
  end;
end;

function TLocalNotebook.StorageSettingValue: string;
var
  Base, Root, Relative: string;
begin
  Base := IncludeTrailingPathDelimiter(ExtractFileDir(FDatabasePath));
  Root := FStorageRoot;
  if Length(Root) > 3 then
    Root := ExcludeTrailingPathDelimiter(Root);
  Result := Root;
  if not SameText(ExtractFileDrive(Base), ExtractFileDrive(Root)) then
    Exit;
  Relative := ExcludeTrailingPathDelimiter(
    ExtractRelativePath(Base, IncludeTrailingPathDelimiter(Root)));
  if (Relative <> '') and (Pos(':', Relative) = 0) and
    SameText(TPath.GetFullPath(TPath.Combine(Base, Relative)), Root) then
    Result := Relative;
end;

function TLocalNotebook.CanRememberStorageRoot: Boolean;
var
  Setting: TDBSetting;
begin
  Setting := FManager.Find<TDBSetting>(LOCAL_STORAGE_KEY);
  Result := not Assigned(Setting) or (Setting.SettingValue <> StorageSettingValue);
end;

procedure TLocalNotebook.RememberStorageRoot;
var
  Value: string;
  Setting: TDBSetting;
begin
  Value := StorageSettingValue;
  Setting := FManager.Find<TDBSetting>(LOCAL_STORAGE_KEY);
  if Assigned(Setting) then
    Setting.SettingValue := Value
  else
  begin
    Setting := TDBSetting.Create;
    Setting.SettingKey := LOCAL_STORAGE_KEY;
    Setting.SettingValue := Value;
    FManager.Save(Setting);
  end;
  FManager.Flush;
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
  // Validate and hash before reserving a new file.
  Path := CheckedDatabasePath(DatabasePath);
  FDatabasePath := Path;
  UseStorageRoot(StorageRoot);
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
  if not ForceDirectories(FStorageRoot) then
    raise ELocalNotebookError.Create('Could not create the attachment directory');
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
  if CanRememberStorageRoot then
    RememberStorageRoot;
  TReaderValueMappingModel.CreateDefaultData(FManager);
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
  FDatabasePath := Path;
  if StorageRoot <> '' then
    UseStorageRoot(StorageRoot);
  // The native adapter opens read/write. Refuse recovery and persisted WAL
  // mode before it can change a notebook or create sidecars during validation.
  CheckNoSidecars(Path);
  CheckRollbackHeader(Path);
  Connect(Path);
  FormatSetting := FManager.Find<TDBSetting>(LOCAL_FORMAT_KEY);
  if Assigned(FormatSetting) and IsUpgradableFormat(FormatSetting.SettingValue) then
    raise ELocalNotebookUpgradeRequired.CreateFmt(
      'This notebook uses format %s. Upgrade it to format %s to open it; ' +
      'the upgrade first copies the database beside the original',
      [FormatSetting.SettingValue, LOCAL_FORMAT_VERSION]);
  if not Assigned(FormatSetting) or
    (FormatSetting.SettingValue <> LOCAL_FORMAT_VERSION) then
    raise ELocalNotebookError.Create('Unsupported local notebook format; conversion is required');
  if StorageRoot = '' then
    UseSavedStorageRoot;
  ReadPrincipal;
  FAccessPolicy := TLocalProjectAccessPolicy.Create(FPrincipal.Id);
end;

constructor TLocalNotebook.CreateForUpgrade(const DatabasePath: string);
begin
  inherited Create;
  Connect(DatabasePath);
end;

procedure TLocalNotebook.VerifyCurrentSchema;
var
  Statement: IDBStatement;
begin
  Statement := FConnection.CreateStatement;
  Statement.SetSQLCommand('SELECT SourceKind, SourceFileId, ReaderId, ' +
    'ReaderVersion, KeyName, SourceNote, ReaderUnits, ConversionFactor ' +
    'FROM DataValues WHERE 1 = 0');
  Statement.ExecuteQuery;
  Statement := FConnection.CreateStatement;
  Statement.SetSQLCommand(
    'SELECT RangeMin, RangeMax FROM ValueTypes WHERE 1 = 0');
  Statement.ExecuteQuery;
  Statement := FConnection.CreateStatement;
  Statement.SetSQLCommand('SELECT ReaderId, KeyPattern, ReaderUnits, ' +
    'ValueTypeId, Factor, Label FROM ReaderValueMappings WHERE 1 = 0');
  Statement.ExecuteQuery;
  Statement := FConnection.CreateStatement;
  Statement.SetSQLCommand(
    'SELECT FormulaId, FormulaVersion FROM DataValues WHERE 1 = 0');
  Statement.ExecuteQuery;
  Statement := FConnection.CreateStatement;
  Statement.SetSQLCommand('SELECT ResultValueId, Role, InputValueId, InputValue ' +
    'FROM DerivedValueInputs WHERE 1 = 0');
  Statement.ExecuteQuery;
end;

class function TLocalNotebook.Upgrade(const DatabasePath: string): string;
var
  Path: string;
  Notebook: TLocalNotebook;
  FormatSetting: TDBSetting;
  Skipped: TArray<string>;
  Backup: TFileStream;
  OldFormat: string;
begin
  Path := CheckedDatabasePath(DatabasePath);
  if not System.IOUtils.TFile.Exists(Path) then
    raise EFileNotFoundException.Create('Local notebook database does not exist');
  CheckNoSidecars(Path);
  CheckRollbackHeader(Path);
  Notebook := TLocalNotebook.CreateForUpgrade(Path);
  try
    FormatSetting := Notebook.FManager.Find<TDBSetting>(LOCAL_FORMAT_KEY);
    if not Assigned(FormatSetting) or
      not IsUpgradableFormat(FormatSetting.SettingValue) then
      raise ELocalNotebookError.Create('Only format 2, 3 or 4 notebooks can be upgraded');
    OldFormat := FormatSetting.SettingValue;
  finally
    Notebook.Free;
  end;

  Result := CheckedDatabasePath(TPath.Combine(ExtractFileDir(Path),
    TPath.GetFileNameWithoutExtension(Path) + '.format' + OldFormat + '-backup-' +
    FormatDateTime('yyyymmdd"-"hhnnss', Now) + '-' +
    TGUID.NewGuid.ToString + ExtractFileExt(Path)));
  if not CopyFile(PChar(Path), PChar(Result), True) then
    RaiseLastOSError;
  Backup := TFileStream.Create(Result, fmOpenReadWrite or fmShareExclusive);
  try
    if not FlushFileBuffers(Backup.Handle) then
      RaiseLastOSError;
  finally
    Backup.Free;
  end;

  Notebook := TLocalNotebook.CreateForUpgrade(Path);
  try
    Skipped := UpdateDatabaseAdditive(Notebook.FConnection);
    try
      Notebook.VerifyCurrentSchema;
      TReaderValueMappingModel.CreateDefaultData(Notebook.FManager);
    except
      on E: Exception do
        raise ELocalNotebookError.CreateFmt(
          'The format %s upgrade failed (%s). Skipped: %s. ' +
          'The original database is kept at %s',
          [LOCAL_FORMAT_VERSION, E.Message, string.Join('; ', Skipped), Result]);
    end;
    FormatSetting := Notebook.FManager.Find<TDBSetting>(LOCAL_FORMAT_KEY);
    FormatSetting.SettingValue := LOCAL_FORMAT_VERSION;
    Notebook.FManager.Flush;
  finally
    Notebook.Free;
  end;
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
