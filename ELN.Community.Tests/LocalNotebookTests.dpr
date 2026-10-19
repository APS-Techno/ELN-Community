program LocalNotebookTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Variants,
  System.RegularExpressions,
  System.Math,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Drivers.Interfaces,
  Aurelius.Drivers.SQLite,
  unit_LocalNotebook in '..\ELN.Community\unit_LocalNotebook.pas',
  unit_NotebookStorage in '..\ELN.Model\unit_NotebookStorage.pas',
  unit_User in '..\ELN.Domain\unit_User.pas',
  unit_Project in '..\ELN.Domain\unit_Project.pas',
  unit_Item in '..\ELN.Domain\unit_Item.pas',
  unit_ItemTypes,
  unit_ValueType,
  unit_ItemModel,
  unit_ValueSource,
  unit_ValueTypeModel,
  unit_ValueTypeCategories,
  unit_DBSettingsModel,
  unit_DBSetting,
  unit_ValueDrift,
  unit_ReaderValueMapping,
  unit_ReaderValueMappingModel,
  Bcrypt in '..\ELN.Model\Bcrypt.pas';

const
  SigningPassword = 'Synthetic-Notebook-Test-Only!';

var
  FixtureDir, DatabasePath, StorageRoot: string;
  Notebook: TLocalNotebook;
  Passed, Failed: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckBytes(const Expected, Actual: TBytes; const MessageText: string);
var
  I: Integer;
begin
  Check(Length(Expected) = Length(Actual), MessageText + ': byte count');
  for I := 0 to High(Expected) do
    Check(Expected[I] = Actual[I], MessageText + ': byte ' + IntToStr(I));
end;

procedure MustRaise(const Operation: TProc; const MessageText: string);
var
  RaisedException: Boolean;
begin
  RaisedException := False;
  try
    Operation();
  except
    on E: Exception do
      RaisedException := True;
  end;
  Check(RaisedException, MessageText + ': expected an exception');
end;

function CountActivePrincipals: Integer;
var
  Users: TList<TUser>;
  User: TUser;
begin
  Result := 0;
  Users := Notebook.Manager.Find<TUser>.List;
  try
    for User in Users do
      if not User.IsArchived then
        Inc(Result);
  finally
    // The query list is caller-owned; its entity instances are manager-owned.
    Users.Free;
  end;
end;

procedure CreateFixtureNotebook;
begin
  Notebook := TLocalNotebook.CreateNew(DatabasePath, StorageRoot,
    'Synthetic', 'Scientist', SigningPassword);
end;

procedure ExpectOpenRejected;
var
  Opened: TLocalNotebook;
begin
  Opened := nil;
  try
    MustRaise(
      procedure
      begin
        Opened := TLocalNotebook.Open(DatabasePath, StorageRoot);
      end, 'invalid notebook must not open');
  finally
    Opened.Free;
  end;
end;

procedure RunTest(const TestName: string; const Test: TProc);
var
  Id: TGUID;
begin
  CreateGUID(Id);
  FixtureDir := TPath.Combine(TPath.GetTempPath,
    'ELN-Local-Notebook-' + GUIDToString(Id));
  DatabasePath := TPath.Combine(FixtureDir, 'notebook.sqlite');
  StorageRoot := TPath.Combine(FixtureDir, 'attachments');
  Notebook := nil;
  try
    ForceDirectories(FixtureDir);
    try
      Test();
      Inc(Passed);
      WriteLn('PASS ', TestName);
    except
      on E: Exception do
      begin
        Inc(Failed);
        WriteLn('FAIL ', TestName, ': ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    FreeAndNil(Notebook);
    if DirectoryExists(FixtureDir) then
      TDirectory.Delete(FixtureDir, True);
  end;
end;

procedure TestFreshPrincipalAndReopen;
var
  OriginalId: Integer;
  RehashNeeded: Boolean;
  Users: TList<TUser>;
begin
  CreateFixtureNotebook;
  Check(FileExists(DatabasePath), 'CreateNew must create SQLite database');
  Check(Notebook.Manager <> nil, 'manager is available');
  Check(Notebook.Principal <> nil, 'principal is available');
  Check(Notebook.Storage <> nil, 'storage is available');
  Check(not Notebook.Principal.IsArchived, 'principal must be active');
  Check(CountActivePrincipals = 1, 'fresh notebook has exactly one active principal');
  Users := Notebook.Manager.Find<TUser>.List;
  try
    Check(Users.Count = 1, 'fresh notebook has exactly one account row');
  finally
    Users.Free;
  end;
  Check(Notebook.Principal.FirstName = 'Synthetic', 'first name is preserved');
  Check(Notebook.Principal.LastName = 'Scientist', 'last name is preserved');
  Check(Notebook.Principal.Password <> SigningPassword,
    'plaintext signing password must not be stored');
  Check(TBCrypt.CheckPassword(SigningPassword, Notebook.Principal.Password,
    RehashNeeded), 'stored BCrypt hash verifies signing password');
  Check(not TBCrypt.CheckPassword('Different-Synthetic-Input',
    Notebook.Principal.Password, RehashNeeded), 'wrong password is rejected');
  OriginalId := Notebook.Principal.Id;
  Check(OriginalId > 0, 'principal ID is persistent');
  FreeAndNil(Notebook);
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Check(Notebook.Principal.Id = OriginalId, 'reopen preserves principal ID');
  Check(CountActivePrincipals = 1, 'reopen must not create another principal');
  Check(TBCrypt.CheckPassword(SigningPassword, Notebook.Principal.Password,
    RehashNeeded), 'reopen preserves BCrypt hash');
end;

procedure TestOriginalEntitiesAndAttachments;
var
  Project: TProject;
  Item: TItem;
  ProjectId, ItemId, PrincipalId: Integer;
  AttachmentPath: string;
  Data: TBytes;
begin
  CreateFixtureNotebook;
  PrincipalId := Notebook.Principal.Id;
  Project := TProject.Create;
  Project.Title := 'Original scientific project';
  Project.FileFolder := 'fixture-project';
  Project.Owner := Notebook.Principal;
  Project.CreatedBy := PrincipalId;
  Project.CreatedDate := Now;
  Notebook.Manager.Save(Project);
  Notebook.Manager.Flush;
  ProjectId := Project.Id;

  Item := TItem.Create;
  Item.Title := 'Original specimen';
  Item.ProjectID := ProjectId;
  Item.FolderID := 0;
  Item.Parent := 0;
  Item.CreatedBy := PrincipalId;
  Item.CreatedDate := Now;
  Notebook.Manager.Save(Item);
  Notebook.Manager.Flush;
  ItemId := Item.Id;
  Check((ProjectId > 0) and (ItemId > 0), 'scientific entities receive IDs');

  AttachmentPath := 'Projects/fixture-project/specimen/arbitrary.bin';
  Data := TBytes.Create(0, 255, 128, 13, 10, 0, 254, 42);
  Notebook.Storage.WriteBytes(AttachmentPath, Data);
  FreeAndNil(Notebook);

  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Project := Notebook.Manager.Find<TProject>(ProjectId);
  Item := Notebook.Manager.Find<TItem>(ItemId);
  Check(Project <> nil, 'project survives reopen');
  Check(Item <> nil, 'item survives reopen');
  Check(Project.Title = 'Original scientific project', 'project title survives');
  Check(Project.Owner.Id = PrincipalId, 'project owner ID survives');
  Check(Project.CreatedBy.HasValue and (Project.CreatedBy.Value = PrincipalId),
    'project author ID survives');
  Check(Item.Title = 'Original specimen', 'item title survives');
  Check(Item.ProjectID = ProjectId, 'item project ID survives');
  Check(Item.CreatedBy.HasValue and (Item.CreatedBy.Value = PrincipalId),
    'item author ID survives');
  Check(Notebook.Principal.Id = PrincipalId, 'scientific author is local principal');
  CheckBytes(Data, Notebook.Storage.ReadBytes(AttachmentPath),
    'arbitrary attachment bytes survive close and reopen');
end;

procedure TestCreateNewPreservesExistingDatabase;
var
  OriginalBytes: TBytes;
  Unexpected: TLocalNotebook;
begin
  CreateFixtureNotebook;
  FreeAndNil(Notebook);
  OriginalBytes := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  Unexpected := nil;
  try
    MustRaise(
      procedure
      begin
        Unexpected := TLocalNotebook.CreateNew(DatabasePath, StorageRoot,
          'Replacement', 'Forbidden', SigningPassword);
      end, 'CreateNew must refuse existing database');
  finally
    Unexpected.Free;
  end;
  CheckBytes(OriginalBytes, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
    'existing SQLite database bytes must remain unchanged');
end;

procedure TestOpenMissingDoesNotCreateDatabase;
begin
  Check(not FileExists(DatabasePath), 'fixture starts with absent database');
  ExpectOpenRejected;
  Check(not FileExists(DatabasePath), 'Open missing database must not create a file');
end;

procedure TestOpenRejectsZeroActivePrincipals;
begin
  CreateFixtureNotebook;
  Notebook.Principal.IsArchived := True;
  Notebook.Manager.Flush;
  Check(CountActivePrincipals = 0, 'fixture has zero active principals');
  FreeAndNil(Notebook);
  ExpectOpenRejected;
end;

procedure TestOpenRejectsMultipleActivePrincipals;
var
  Extra: TUser;
begin
  CreateFixtureNotebook;
  Extra := TUser.Create;
  Extra.Username := 'synthetic-second-principal';
  Extra.Password := Notebook.Principal.Password;
  Extra.FirstName := 'Synthetic';
  Extra.LastName := 'Second';
  Extra.Role := dbUser;
  Extra.CreatedDate := Now;
  Extra.IsArchived := False;
  Notebook.Manager.Save(Extra);
  Notebook.Manager.Flush;
  Check(CountActivePrincipals = 2, 'fixture has two active principals');
  FreeAndNil(Notebook);
  ExpectOpenRejected;
end;

procedure TestDatabaseCannotBeAnAttachment;
var
  Unexpected: TLocalNotebook;
  OriginalBytes: TBytes;
begin
  Unexpected := nil;
  try
    MustRaise(
      procedure
      begin
        Unexpected := TLocalNotebook.CreateNew(DatabasePath, FixtureDir,
          'Synthetic', 'Scientist', SigningPassword);
      end, 'database inside writable attachment root must be refused');
  finally
    Unexpected.Free;
  end;
  Check(not FileExists(DatabasePath), 'rejected overlap must not create a database');
  CreateFixtureNotebook;
  FreeAndNil(Notebook);
  OriginalBytes := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  try
    MustRaise(
      procedure
      begin
        Unexpected := TLocalNotebook.Open(DatabasePath, FixtureDir);
      end, 'overlapping root must also be refused when opening');
  finally
    Unexpected.Free;
  end;
  CheckBytes(OriginalBytes, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
    'overlap rejection preserves database bytes');
end;

procedure TestOpenPreservesRecoverySidecars;
var
  Suffix: string;
  OriginalBytes, SidecarBytes: TBytes;
begin
  CreateFixtureNotebook;
  FreeAndNil(Notebook);
  OriginalBytes := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  SidecarBytes := TBytes.Create(0, 255, 42, 128);
  for Suffix in ['-journal', '-wal', '-shm'] do
  begin
    System.IOUtils.TFile.WriteAllBytes(DatabasePath + Suffix, SidecarBytes);
    ExpectOpenRejected;
    CheckBytes(OriginalBytes, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
      'recovery refusal preserves database');
    CheckBytes(SidecarBytes, System.IOUtils.TFile.ReadAllBytes(DatabasePath + Suffix),
      'recovery refusal preserves sidecar ' + Suffix);
    System.IOUtils.TFile.Delete(DatabasePath + Suffix);
  end;
end;

procedure TestCreateNewPreservesOrphanSidecars;
var
  Suffix: string;
  SidecarBytes: TBytes;
  Unexpected: TLocalNotebook;
begin
  SidecarBytes := TBytes.Create(12, 34, 56, 78);
  for Suffix in ['-journal', '-wal', '-shm'] do
  begin
    System.IOUtils.TFile.WriteAllBytes(DatabasePath + Suffix, SidecarBytes);
    Unexpected := nil;
    try
      MustRaise(
        procedure
        begin
          Unexpected := TLocalNotebook.CreateNew(DatabasePath, StorageRoot,
            'Synthetic', 'Scientist', SigningPassword);
        end, 'creation must refuse existing sidecar ' + Suffix);
    finally
      Unexpected.Free;
    end;
    Check(not FileExists(DatabasePath), 'sidecar refusal must not reserve a database');
    CheckBytes(SidecarBytes, System.IOUtils.TFile.ReadAllBytes(DatabasePath + Suffix),
      'creation preserves orphan sidecar');
    System.IOUtils.TFile.Delete(DatabasePath + Suffix);
  end;
end;

procedure TestOpenRefusesPersistedWalWithoutSidecars;
var
  WalBytes: TBytes;
begin
  CreateFixtureNotebook;
  FreeAndNil(Notebook);
  WalBytes := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  WalBytes[18] := 2;
  WalBytes[19] := 2;
  System.IOUtils.TFile.WriteAllBytes(DatabasePath, WalBytes);
  ExpectOpenRejected;
  CheckBytes(WalBytes, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
    'WAL refusal preserves database');
  Check(not FileExists(DatabasePath + '-wal'), 'WAL refusal must not create WAL');
  Check(not FileExists(DatabasePath + '-shm'), 'WAL refusal must not create shared memory');
end;

procedure TestCreateNewPreservesPopulatedStorageRoot;
var
  ExistingPath: string;
  Bytes: TBytes;
  Unexpected: TLocalNotebook;
begin
  ForceDirectories(StorageRoot);
  ExistingPath := TPath.Combine(StorageRoot, 'existing-scientific-data.bin');
  Bytes := TBytes.Create(0, 255, 19, 83);
  System.IOUtils.TFile.WriteAllBytes(ExistingPath, Bytes);
  Unexpected := nil;
  try
    MustRaise(
      procedure
      begin
        Unexpected := TLocalNotebook.CreateNew(DatabasePath, StorageRoot,
          'Synthetic', 'Scientist', SigningPassword);
      end, 'new notebook must not adopt a populated attachment root');
  finally
    Unexpected.Free;
  end;
  Check(not FileExists(DatabasePath), 'populated root refusal must not reserve database');
  CheckBytes(Bytes, System.IOUtils.TFile.ReadAllBytes(ExistingPath),
    'populated root refusal preserves existing scientific bytes');
end;

function SavedRootOpenError: ExceptClass;
var
  Opened: TLocalNotebook;
begin
  Result := nil;
  Opened := nil;
  try
    try
      Opened := TLocalNotebook.Open(DatabasePath, '');
    except
      on E: Exception do
        Result := ExceptClass(E.ClassType);
    end;
  finally
    Opened.Free;
  end;
end;

procedure SetSavedRoot(const Value: string);
var
  Setting: TDBSetting;
begin
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Setting := Notebook.Manager.Find<TDBSetting>('COMMUNITY_ATTACHMENT_DIR');
  if Value = '' then
    Notebook.Manager.Remove(Setting)
  else
    Setting.SettingValue := Value;
  Notebook.Manager.Flush;
  FreeAndNil(Notebook);
end;

procedure TestSavedRootOpensMovedNotebook;
var
  OldDir, NewDir: string;
  Data: TBytes;
begin
  OldDir := TPath.Combine(FixtureDir, 'before');
  NewDir := TPath.Combine(FixtureDir, 'after');
  DatabasePath := TPath.Combine(OldDir, 'notebook.sqlite');
  StorageRoot := TPath.Combine(OldDir, 'notebook files');
  CreateFixtureNotebook;
  Check(TDirectory.Exists(StorageRoot), 'CreateNew creates the attachment directory');
  Check(not Notebook.CanRememberStorageRoot, 'CreateNew saves an inner attachment directory');
  Data := TBytes.Create(7, 0, 255);
  Notebook.Storage.WriteBytes('Projects/p/i/data.bin', Data);
  FreeAndNil(Notebook);
  TDirectory.Move(OldDir, NewDir);
  DatabasePath := TPath.Combine(NewDir, 'notebook.sqlite');
  Notebook := TLocalNotebook.Open(DatabasePath, '');
  Check(SameText(Notebook.StorageRoot, TPath.Combine(NewDir, 'notebook files')),
    'saved directory follows the moved notebook folder');
  CheckBytes(Data, Notebook.Storage.ReadBytes('Projects/p/i/data.bin'),
    'attachments open through the saved directory');
end;

procedure TestSavedRootMustExist;
var
  OriginalBytes: TBytes;
begin
  CreateFixtureNotebook;
  FreeAndNil(Notebook);
  TDirectory.Delete(StorageRoot);
  OriginalBytes := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  Check(SavedRootOpenError = ELocalNotebookStorageUnavailable,
    'a missing saved directory is reported, not recreated');
  Check(not TDirectory.Exists(StorageRoot), 'refusal does not recreate the directory');
  CheckBytes(OriginalBytes, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
    'refusal preserves database bytes');
end;

procedure TestSiblingFilesLayoutFollowsMove;
var
  OldDir, NewDir: string;
  Data: TBytes;
begin
  OldDir := TPath.Combine(FixtureDir, 'Paper');
  NewDir := TPath.Combine(FixtureDir, 'Moved paper');
  DatabasePath := TPath.Combine(OldDir, 'DB\agent.sqlite');
  StorageRoot := TPath.Combine(OldDir, 'Files');
  CreateFixtureNotebook;
  Check(not Notebook.CanRememberStorageRoot, 'CreateNew saves a sibling Files directory');
  Data := TBytes.Create(1, 2, 3);
  Notebook.Storage.WriteBytes('Projects/p/i/data.bin', Data);
  FreeAndNil(Notebook);
  TDirectory.Move(OldDir, NewDir);
  DatabasePath := TPath.Combine(NewDir, 'DB\agent.sqlite');
  Notebook := TLocalNotebook.Open(DatabasePath, '');
  Check(SameText(Notebook.StorageRoot, TPath.Combine(NewDir, 'Files')),
    'a sibling Files directory follows the moved notebook folder');
  CheckBytes(Data, Notebook.Storage.ReadBytes('Projects/p/i/data.bin'),
    'attachments open through the sibling directory');
end;

procedure TestSavedRootAnyLocation;
var
  Outside, Value: string;
begin
  DatabasePath := TPath.Combine(FixtureDir, 'a\b\notebook.sqlite');
  StorageRoot := TPath.Combine(FixtureDir, 'a\b\attachments');
  Outside := TPath.Combine(FixtureDir, 'outside');
  ForceDirectories(Outside);
  CreateFixtureNotebook;
  FreeAndNil(Notebook);
  for Value in [Outside, '..\..\outside', '../../outside'] do
  begin
    SetSavedRoot(Value);
    Notebook := TLocalNotebook.Open(DatabasePath, '');
    Check(SameText(Notebook.StorageRoot, Outside), 'saved directory opens: ' + Value);
    FreeAndNil(Notebook);
  end;
  for Value in ['C:outside', '.', '..', '..\missing'] do
  begin
    SetSavedRoot(Value);
    Check(SavedRootOpenError = ELocalNotebookStorageUnavailable,
      'saved directory must be refused: ' + Value);
  end;
end;

procedure TestOuterRootIsSaved;
begin
  DatabasePath := TPath.Combine(FixtureDir, 'a\b\notebook.sqlite');
  CreateFixtureNotebook;
  Check(not Notebook.CanRememberStorageRoot, 'CreateNew saves an outer directory');
  FreeAndNil(Notebook);
  Notebook := TLocalNotebook.Open(DatabasePath, '');
  Check(SameText(Notebook.StorageRoot, StorageRoot), 'outer directory opens');
end;

procedure TestRememberRootOnExistingNotebook;
begin
  CreateFixtureNotebook;
  FreeAndNil(Notebook);
  SetSavedRoot('');
  Check(SavedRootOpenError = ELocalNotebookStorageRequired,
    'an older notebook without the setting asks for a directory');
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Check(Notebook.CanRememberStorageRoot, 'an inner directory can be remembered');
  FreeAndNil(Notebook);
  Check(SavedRootOpenError = ELocalNotebookStorageRequired,
    'an explicit open does not save the directory by itself');
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Notebook.RememberStorageRoot;
  FreeAndNil(Notebook);
  Notebook := TLocalNotebook.Open(DatabasePath, '');
  Check(SameText(Notebook.StorageRoot, StorageRoot), 'remembered directory opens');
end;

procedure TestCategoryIsolationAndReadOnlyLoad;
const
  CategoryKey = 'ValueTypeCategories';
  SourceCategories = '["Notebook A only","Another A-only group"]';
var
  FirstValues, SecondValues: TValueTypeModel;
  Second: TLocalNotebook;
begin
  CreateFixtureNotebook;
  TDBSettingsModel.StoreValue(Notebook.Manager, CategoryKey, SourceCategories);
  FirstValues := TValueTypeModel.Create(Notebook.Manager);
  try
    FirstValues.LoadCategories(False);
    Check(CategoryIDByName('Notebook A only') = 0, 'first notebook loads its categories');
    Second := TLocalNotebook.CreateNew(TPath.Combine(FixtureDir, 'second.sqlite'),
      TPath.Combine(FixtureDir, 'second-attachments'), 'Second', 'Scientist', SigningPassword);
    try
      SecondValues := TValueTypeModel.Create(Second.Manager);
      try
        Check(Second.Manager.Find<TDBSetting>(CategoryKey) = nil,
          'second notebook starts without a category setting');
        SecondValues.LoadCategories(False);
        Check(CategoryIDByName('Notebook A only') = -1,
          'missing category settings must not inherit another notebook');
        Check(Second.Manager.Find<TDBSetting>(CategoryKey) = nil,
          'read-only category load must not persist defaults');
        Check(Notebook.Manager.Find<TDBSetting>(CategoryKey).SettingValue = SourceCategories,
          'loading another notebook preserves the first notebook setting');
      finally
        SecondValues.Free;
      end;
    finally
      Second.Free;
    end;
  finally
    FirstValues.Free;
    ResetValueTypeCategories;
  end;
end;

procedure ExecuteSQL(const SQL: string);
var
  Statement: IDBStatement;
begin
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand(SQL);
  Statement.Execute;
end;

function QueryStrings(const SQL: string; FieldIndex: Integer = 0): TArray<string>;
var
  Statement: IDBStatement;
  ResultSet: IDBResultSet;
  Rows: TList<string>;
begin
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand(SQL);
  ResultSet := Statement.ExecuteQuery;
  Rows := TList<string>.Create;
  try
    while ResultSet.Next do
      Rows.Add(VarToStr(ResultSet.GetFieldValue(FieldIndex)));
    Result := Rows.ToArray;
  finally
    Rows.Free;
  end;
end;

// The bundled SQLite predates DROP COLUMN, so the fixture rebuilds the table
// from its stored DDL with the format 3 columns removed.
procedure RebuildWithoutColumns(const Table: string;
  const Removed: array of string);
var
  CreateSQL, Column, Kept: string;
  Indexes, Columns: TArray<string>;
  KeptList: TList<string>;
  IsRemoved: Boolean;
  R: string;
begin
  CreateSQL := QueryStrings('SELECT sql FROM sqlite_master WHERE type = ''table'' ' +
    'AND name = ''' + Table + '''')[0];
  Indexes := QueryStrings('SELECT sql FROM sqlite_master WHERE type = ''index'' ' +
    'AND tbl_name = ''' + Table + ''' AND sql IS NOT NULL');
  Columns := QueryStrings('PRAGMA table_info(' + Table + ')', 1);
  KeptList := TList<string>.Create;
  try
    for Column in Columns do
    begin
      IsRemoved := False;
      for R in Removed do
        IsRemoved := IsRemoved or SameText(R, Column);
      if not IsRemoved then
        KeptList.Add(Column);
    end;
    Kept := string.Join(', ', KeptList.ToArray);
  finally
    KeptList.Free;
  end;
  for R in Removed do
  begin
    Check(TRegEx.IsMatch(CreateSQL, ',\s*"?' + R + '"?\s', [roIgnoreCase]),
      'fixture DDL contains ' + R);
    CreateSQL := TRegEx.Replace(CreateSQL,
      ',\s*"?' + R + '"?\s+\w+(\s*\([^)]*\))?(\s+NULL)?', '', [roIgnoreCase]);
  end;
  ExecuteSQL('PRAGMA foreign_keys = OFF');
  ExecuteSQL('PRAGMA legacy_alter_table = ON');
  ExecuteSQL('ALTER TABLE ' + Table + ' RENAME TO ' + Table + '_format3');
  ExecuteSQL(CreateSQL);
  ExecuteSQL('INSERT INTO ' + Table + ' (' + Kept + ') SELECT ' + Kept +
    ' FROM ' + Table + '_format3');
  ExecuteSQL('DROP TABLE ' + Table + '_format3');
  for R in Indexes do
    ExecuteSQL(R);
  ExecuteSQL('PRAGMA legacy_alter_table = OFF');
  ExecuteSQL('PRAGMA foreign_keys = ON');
end;

procedure CreateFormat2Notebook(out ItemId, ValueId, ValueTypeId: Integer);
var
  Project: TProject;
  Item: TItem;
  VT: TValueType;
  V: TValue;
  Column: string;
begin
  CreateFixtureNotebook;
  Project := TProject.Create;
  Project.Title := 'Format 2 project';
  Project.FileFolder := 'format-2';
  Project.Owner := Notebook.Principal;
  Project.CreatedBy := Notebook.Principal.Id;
  Project.CreatedDate := Now;
  Notebook.Manager.Save(Project);
  Notebook.Manager.Flush;
  Item := TItem.Create;
  Item.Title := 'Format 2 specimen';
  Item.ProjectID := Project.Id;
  Item.CreatedBy := Notebook.Principal.Id;
  Item.CreatedDate := Now;
  Notebook.Manager.Save(Item);
  VT := TValueType.Create;
  VT.Symbol := 'd';
  VT.Title := 'Thickness';
  VT.Units := 'm';
  VT.CreatedDate := Now;
  Notebook.Manager.Save(VT);
  Notebook.Manager.Flush;
  V := TValue.Create;
  V.Item := Item;
  V.ValueType := VT;
  V.RecType := TEST_RESULT;
  V.Value := 2.279e-8;
  V.Tol := 1e-10;
  V.Description := 'pre-upgrade row';
  V.CreatedDate := Now;
  Notebook.Manager.Save(V);
  Notebook.Manager.Flush;
  ItemId := Item.Id;
  ValueId := V.Id;
  ValueTypeId := VT.Id;
  ExecuteSQL('DROP TABLE DerivedValueInputs');
  RebuildWithoutColumns('DataValues', ['SourceKind', 'SourceFileId',
    'ReaderId', 'ReaderVersion', 'KeyName', 'SourceNote',
    'ReaderUnits', 'ConversionFactor', 'FormulaId', 'FormulaVersion']);
  RebuildWithoutColumns('ValueTypes', ['RangeMin', 'RangeMax']);
  ExecuteSQL('UPDATE DBSettings SET SettingValue = ''2'' ' +
    'WHERE SettingKey = ''COMMUNITY_FORMAT_VERSION''');
  FreeAndNil(Notebook);
end;

procedure TestFormat2NeedsExplicitUpgrade;
var
  ItemId, ValueId, ValueTypeId: Integer;
  Before: TBytes;
  Opened: TLocalNotebook;
  UpgradeRequired: Boolean;
begin
  CreateFormat2Notebook(ItemId, ValueId, ValueTypeId);
  Before := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  UpgradeRequired := False;
  Opened := nil;
  try
    try
      Opened := TLocalNotebook.Open(DatabasePath, StorageRoot);
    except
      on E: ELocalNotebookUpgradeRequired do
        UpgradeRequired := True;
    end;
  finally
    Opened.Free;
  end;
  Check(UpgradeRequired, 'format 2 must ask for an upgrade');
  CheckBytes(Before, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
    'refused open leaves the format 2 database unchanged');
  Check(Length(TDirectory.GetFiles(FixtureDir, '*backup*')) = 0,
    'refused open creates no backup');
end;

procedure TestFormat2UpgradeKeepsDataAndBackup;
var
  ItemId, ValueId, ValueTypeId: Integer;
  Before: TBytes;
  BackupPath: string;
  V: TValue;
  VT: TValueType;
  Item: TItem;
  Items: TItemModel;
  NewValue: TValue;
begin
  CreateFormat2Notebook(ItemId, ValueId, ValueTypeId);
  Before := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  BackupPath := TLocalNotebook.Upgrade(DatabasePath);
  Check(SameText(ExtractFileDir(BackupPath), ExtractFileDir(DatabasePath)),
    'backup sits beside the notebook');
  Check(Pos('format2-backup', ExtractFileName(BackupPath)) > 0,
    'backup name marks the old format');
  CheckBytes(Before, System.IOUtils.TFile.ReadAllBytes(BackupPath),
    'backup holds the pre-upgrade bytes');
  MustRaise(
    procedure
    begin
      TLocalNotebook.Upgrade(DatabasePath);
    end, 'a format 5 notebook is not upgraded again');

  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  V := Notebook.Manager.Find<TValue>(ValueId);
  Check(V <> nil, 'pre-upgrade value survives');
  Check(SameValue(V.Value, 2.279e-8, 1e-20), 'value number survives');
  Check(SameValue(V.Tol, 1e-10, 1e-22), 'tolerance survives');
  Check(V.Description = 'pre-upgrade row', 'description survives');
  Check(V.Item.Id = ItemId, 'value owner survives');
  Check(not V.SourceKind.HasValue, 'pre-upgrade row has no stored source kind');
  Check(V.EffectiveSourceKind = vskUnknown, 'pre-upgrade row reads as Unknown');
  VT := Notebook.Manager.Find<TValueType>(ValueTypeId);
  Check(not VT.RangeMin.HasValue and not VT.RangeMax.HasValue,
    'existing value type has no range');

  Item := Notebook.Manager.Find<TItem>(ItemId);
  Items := TItemModel.Create(Notebook.Manager);
  try
    Items.AddValue(VT, EXP_CONDITION, 1.5, Notebook.Principal.Id, Item, 0,
      'typed by hand', TValueSourceInfo.Manual('lab book p. 12'));
  finally
    Items.Free;
  end;
  FreeAndNil(Notebook);

  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Item := Notebook.Manager.Find<TItem>(ItemId);
  NewValue := nil;
  for V in Item.Values do
    if V.Id <> ValueId then
      NewValue := V;
  Check(NewValue <> nil, 'post-upgrade value is stored');
  Check(NewValue.EffectiveSourceKind = vskManual, 'post-upgrade value keeps Manual');
  Check(NewValue.SourceNote = 'lab book p. 12', 'manual note is stored');
end;

procedure TestFormat3NeedsUpgradeAndKeepsBackup;
var
  Before: TBytes;
  BackupPath: string;
  Setting: TDBSetting;
  Opened: TLocalNotebook;
  Required: Boolean;
  ItemId, ValueId, ValueTypeId: Integer;
  Value: TValue;
begin
  CreateFormat2Notebook(ItemId, ValueId, ValueTypeId);
  TLocalNotebook.Upgrade(DatabasePath);
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Value := Notebook.Manager.Find<TValue>(ValueId);
  Value.SourceKind := vskReader;
  Value.SourceFileId := Int64(1);
  Value.ReaderId := 'legacy.reader';
  Value.ReaderVersion := '1';
  Value.KeyName := 'Legacy thickness';
  Notebook.Manager.Flush;
  ExecuteSQL('DROP TABLE DerivedValueInputs');
  RebuildWithoutColumns('DataValues', ['ReaderUnits', 'ConversionFactor',
    'FormulaId', 'FormulaVersion']);
  ExecuteSQL('DROP TABLE ReaderValueMappings');
  ExecuteSQL('UPDATE DBSettings SET SettingValue = ''3'' ' +
    'WHERE SettingKey = ''COMMUNITY_FORMAT_VERSION''');
  FreeAndNil(Notebook);
  Before := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  Required := False;
  Opened := nil;
  try
    try
      Opened := TLocalNotebook.Open(DatabasePath, StorageRoot);
    except
      on E: ELocalNotebookUpgradeRequired do
        Required := True;
    end;
  finally
    Opened.Free;
  end;
  Check(Required, 'format 3 requires explicit upgrade to format 5');
  CheckBytes(Before, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
    'refused format 3 open preserves bytes');
  BackupPath := TLocalNotebook.Upgrade(DatabasePath);
  Check(Pos('format3-backup', BackupPath) > 0, 'backup identifies format 3');
  CheckBytes(Before, System.IOUtils.TFile.ReadAllBytes(BackupPath),
    'format 3 backup retains original bytes');
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Setting := Notebook.Manager.Find<TDBSetting>('COMMUNITY_FORMAT_VERSION');
  Check(Setting.SettingValue = '5', 'upgrade stamps format 5');
  Value := Notebook.Manager.Find<TValue>(ValueId);
  Check(SameValue(Value.Value, 2.279e-8, 1e-20), 'format 3 value survives');
  Check(Value.Description = 'pre-upgrade row', 'format 3 description survives');
  Check(Value.EffectiveSourceKind = vskReader, 'format 3 Reader source survives');
  Check(not Value.ReaderUnits.HasValue and not Value.ConversionFactor.HasValue,
    'format 3 migration does not invent reader units or factors');
end;

procedure TestUpgradeSeedFailureCanBeRetried;
var
  ErrorText, RetryBackup: string;
  Observer: TObjectManager;
  Before: TBytes;
  Backups: TArray<string>;
  Connection: IDBConnection;
  Statement: IDBStatement;
begin
  CreateFixtureNotebook;
  ExecuteSQL('DELETE FROM ReaderValueMappings');
  ExecuteSQL('DELETE FROM ValueTypes');
  ExecuteSQL('UPDATE DBSettings SET SettingValue = ''3'' ' +
    'WHERE SettingKey = ''COMMUNITY_FORMAT_VERSION''');
  ExecuteSQL('CREATE TRIGGER fail_mapping_seed BEFORE INSERT ON ValueTypes ' +
    'BEGIN SELECT RAISE(ABORT, ''synthetic seed failure''); END');
  FreeAndNil(Notebook);
  Before := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  ErrorText := '';
  try
    TLocalNotebook.Upgrade(DatabasePath);
  except
    on E: Exception do ErrorText := E.Message;
  end;
  Check(ErrorText <> '', 'seed failure refuses upgrade');
  Backups := TDirectory.GetFiles(FixtureDir, '*format3-backup*');
  Check(Length(Backups) = 1, 'seed failure keeps the original backup');
  CheckBytes(Before, System.IOUtils.TFile.ReadAllBytes(Backups[0]),
    'seed failure backup preserves original bytes');
  Connection := TSQLiteNativeConnectionAdapter.Create(DatabasePath);
  Connection.Connect;
  Observer := TObjectManager.Create(Connection);
  try
    Check(Observer.Find<TDBSetting>('COMMUNITY_FORMAT_VERSION').SettingValue = '3',
      'seed failure does not stamp format 5');
  finally
    Observer.Free;
  end;
  Check(Pos(Backups[0], ErrorText) > 0, 'seed failure reports its backup path');
  Statement := Connection.CreateStatement;
  Statement.SetSQLCommand('DROP TRIGGER fail_mapping_seed');
  Statement.Execute;
  Statement := nil;
  Connection := nil;
  RetryBackup := TLocalNotebook.Upgrade(DatabasePath);
  Check(RetryBackup <> Backups[0], 'retry keeps the first backup');
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Check(Notebook.Manager.Find<TDBSetting>('COMMUNITY_FORMAT_VERSION').SettingValue = '5',
    'retry completes the migration');
end;

function FindValueType(const Title, Units: string): TValueType;
var
  Types: TList<TValueType>;
  VT: TValueType;
begin
  Result := nil;
  Types := Notebook.Manager.Find<TValueType>.List;
  try
    for VT in Types do
      if (VT.Title = Title) and (VT.Units = Units) then
        Exit(VT);
  finally
    Types.Free;
  end;
end;

function WearRateUnits: string;
begin
  Result := 'mm' + WideChar($00B3) + '/(N' + WideChar($00B7) + 'mm)';
end;

procedure TestFormat4UpgradesToFormat5;
var
  Project: TProject;
  Item: TItem;
  VT: TValueType;
  Items: TItemModel;
  ReaderId, ManualId, ItemId: Integer;
  V: TValue;
  Before: TBytes;
  BackupPath: string;
  Opened: TLocalNotebook;
  Required: Boolean;
begin
  CreateFixtureNotebook;
  Project := TProject.Create;
  Project.Title := 'Format 4 project';
  Project.FileFolder := 'format-4';
  Project.Owner := Notebook.Principal;
  Project.CreatedBy := Notebook.Principal.Id;
  Project.CreatedDate := Now;
  Notebook.Manager.Save(Project);
  Item := TItem.Create;
  Item.Title := 'Format 4 specimen';
  Item.ProjectID := Project.Id;
  Item.CreatedBy := Notebook.Principal.Id;
  Item.CreatedDate := Now;
  Notebook.Manager.Save(Item);
  Notebook.Manager.Flush;
  ItemId := Item.Id;
  Notebook.Manager.Evict(Item);
  Item.Free;
  Item := Notebook.Manager.Find<TItem>(ItemId);
  VT := FindValueType('Normal force', 'N');
  Items := TItemModel.Create(Notebook.Manager);
  try
    Items.AddValue(VT, EXP_CONDITION, 5, Notebook.Principal.Id, Item, 0, 'read',
      TValueSourceInfo.Reader(77, 'aps.zrw', '2', 'Fn', 'kgF', 9.80665));
    Items.AddValue(VT, EXP_CONDITION, 6, Notebook.Principal.Id, Item, 0, 'typed',
      TValueSourceInfo.Manual('lab book p. 4'));
  finally
    Items.Free;
  end;
  ReaderId := Item.Values[0].Id;
  ManualId := Item.Values[1].Id;
  ExecuteSQL('DELETE FROM ValueTypes WHERE Title = ''Wear rate''');
  ExecuteSQL('DROP TABLE DerivedValueInputs');
  RebuildWithoutColumns('DataValues', ['FormulaId', 'FormulaVersion']);
  ExecuteSQL('UPDATE DBSettings SET SettingValue = ''4'' ' +
    'WHERE SettingKey = ''COMMUNITY_FORMAT_VERSION''');
  FreeAndNil(Notebook);

  Before := System.IOUtils.TFile.ReadAllBytes(DatabasePath);
  Required := False;
  Opened := nil;
  try
    try
      Opened := TLocalNotebook.Open(DatabasePath, StorageRoot);
    except
      on E: ELocalNotebookUpgradeRequired do
        Required := Pos('format 5', E.Message) > 0;
    end;
  finally
    Opened.Free;
  end;
  Check(Required, 'format 4 requires explicit upgrade to format 5');
  CheckBytes(Before, System.IOUtils.TFile.ReadAllBytes(DatabasePath),
    'refused format 4 open preserves bytes');
  BackupPath := TLocalNotebook.Upgrade(DatabasePath);
  Check(Pos('format4-backup', BackupPath) > 0, 'backup identifies format 4');
  CheckBytes(Before, System.IOUtils.TFile.ReadAllBytes(BackupPath),
    'format 4 backup retains original bytes');

  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  Check(Notebook.Manager.Find<TDBSetting>('COMMUNITY_FORMAT_VERSION').SettingValue = '5',
    'upgrade stamps format 5');
  V := Notebook.Manager.Find<TValue>(ReaderId);
  Check(V.EffectiveSourceKind = vskReader, 'Reader value keeps its kind');
  Check((V.ReaderId = 'aps.zrw') and (V.KeyName = 'Fn') and
    (V.ReaderUnits.Value = 'kgF') and SameValue(V.ConversionFactor.Value, 9.80665, 1e-12),
    'Reader value keeps its A1 provenance');
  Check(not V.FormulaId.HasValue and not V.FormulaVersion.HasValue,
    'Reader value gets no formula');
  V := Notebook.Manager.Find<TValue>(ManualId);
  Check(V.EffectiveSourceKind = vskManual, 'Manual value keeps its kind');
  Check(V.SourceNote = 'lab book p. 4', 'Manual value keeps its note');
  Check(not V.ReaderUnits.HasValue and not V.ConversionFactor.HasValue,
    'Manual value gets no conversion provenance');
  Check(FindValueType('Wear rate', WearRateUnits) <> nil,
    'upgrade seeds the Wear rate value type');
  Check(Notebook.Manager.Find<TItem>(ItemId).Values.Count = 2, 'values survive the upgrade');
end;

procedure TestFreshNotebookSeedsDerivedTypes;
begin
  CreateFixtureNotebook;
  Check(FindValueType('Wear area', 'mm' + WideChar($00B2)) <> nil, 'Wear area mm2 exists');
  Check(FindValueType('Normal force', 'N') <> nil, 'Normal force N exists');
  Check(FindValueType('Cycles', '') <> nil, 'Cycles exists');
  Check(FindValueType('Wear rate', WearRateUnits) <> nil, 'Wear rate exists');
  Check(Notebook.Manager.Find<TDBSetting>('COMMUNITY_FORMAT_VERSION').SettingValue = '5',
    'a new notebook is format 5');
end;

type
  TSyntheticMappingReader = class(TInterfacedObject, IValueReaderRunner)
    OutputValue: Double;
    OutputUnits: string;
    function Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
  end;

function TSyntheticMappingReader.Run(FileId: Int64;
  const AnalysisSnapshot: string): TReaderRun;
begin
  Result := Default(TReaderRun);
  Result.Succeeded := True;
  Result.ReaderId := 'aps.xrcx';
  Result.ReaderVersion := '1';
  SetLength(Result.Values, 1);
  Result.Values[0].Name := 'Co Thickness';
  Result.Values[0].Value := OutputValue;
  Result.Values[0].Units := OutputUnits;
end;

procedure TestSavedFactorControlsDrift;
var
  ItemId, ValueId, ValueTypeId: Integer;
  V: TValue;
  Report: TValueDriftReport;
  Runner: IValueReaderRunner;
  Reader: TSyntheticMappingReader;
  Rows: TList<TReaderValueMapping>;
  Row: TReaderValueMapping;
begin
  CreateFormat2Notebook(ItemId, ValueId, ValueTypeId);
  TLocalNotebook.Upgrade(DatabasePath);
  Notebook := TLocalNotebook.Open(DatabasePath, StorageRoot);
  V := Notebook.Manager.Find<TValue>(ValueId);
  V.SourceKind := vskReader;
  V.SourceFileId := Int64(1);
  V.ReaderId := 'aps.xrcx';
  V.ReaderVersion := '1';
  V.KeyName := 'Co Thickness';
  V.Value := 15e-10;
  V.ConversionFactor := 1e-10;
  V.ReaderUnits := 'A';
  Notebook.Manager.Flush;
  Reader := TSyntheticMappingReader.Create;
  Reader.OutputValue := 15;
  Reader.OutputUnits := 'A';
  Runner := Reader;
  Report := CheckValueDrift(Notebook.Manager, [ItemId], Runner);
  Check(Report.Unchanged = 1, 'drift compares after the saved conversion');
  Rows := Notebook.Manager.Find<TReaderValueMapping>.List;
  try
    for Row in Rows do
      Row.Factor := 7;
    Notebook.Manager.Flush;
  finally
    Rows.Free;
  end;
  Report := CheckValueDrift(Notebook.Manager, [ItemId], Runner);
  Check(Report.Unchanged = 1, 'mapping edits do not reinterpret stored values');
  Reader.OutputValue := 30;
  Report := CheckValueDrift(Notebook.Manager, [ItemId], Runner);
  Check((Length(Report.Rows) = 1) and
    (vdfValueChanged in Report.Rows[0].Flags), 'changed input reports drift');
  Check(SameValue(Report.Rows[0].CurrentValue, 30e-10, 1e-22),
    'drift reports converted current value');
  Reader.OutputUnits := 'nm';
  Report := CheckValueDrift(Notebook.Manager, [ItemId], Runner);
  Check(vdfUnitsChanged in Report.Rows[0].Flags, 'changed unit is reported');
  Check(not Report.Rows[0].HasCurrentValue, 'changed unit is not converted');
end;

procedure TestMappingPrecedenceAndUnits;
var
  Resolver: TReaderValueMappingModel;
  Resolution: TReaderValueResolution;
  Row: TReaderValueMapping;
begin
  CreateFixtureNotebook;
  Resolver := TReaderValueMappingModel.Create(Notebook.Manager);
  try
    Resolution := Resolver.Resolve('aps.xrcx', 'Co Thickness', 'A');
    Check(Resolution.ValueType.Title = 'Thickness', 'material targets thickness');
    Check(Resolution.LabelText = 'Co', 'material becomes label');
    Check(SameValue(Resolution.Factor, 1e-10, 1e-22), 'angstrom conversion');
    Row := TReaderValueMapping.Create;
    Row.ReaderId := 'aps.xrcx';
    Row.KeyPattern := 'Co Thickness';
    Row.ReaderUnits := 'A';
    Row.ValueType := Resolution.ValueType;
    Row.Factor := 2e-10;
    Row.LabelText := 'Override';
    Notebook.Manager.Save(Row);
    Notebook.Manager.Flush;
  finally
    Resolver.Free;
  end;
  Resolver := TReaderValueMappingModel.Create(Notebook.Manager);
  try
    Resolution := Resolver.Resolve('aps.xrcx', 'Co Thickness', 'A');
    Check(Resolution.LabelText = 'Override', 'exact mapping overrides pattern');
    Check(SameValue(Resolution.Factor, 2e-10, 1e-22), 'exact factor wins');
    Resolution := Resolver.Resolve('aps.xrcx', 'Co Thickness', 'nm');
    Check(Resolution.ValueType = nil, 'wrong unit cannot use saved mapping');
    Check(Resolution.Reason <> '', 'wrong unit has an actionable reason');
    Resolution := Resolver.Resolve('other.reader', 'Thickness', 'm');
    Check(Resolution.ValueType <> nil, 'unmapped title-unit fallback works');
    Check(Resolution.Factor = 1, 'fallback has identity factor');
    Resolution := Resolver.Resolve('other.reader', 'Thickness', '%');
    Check(Resolution.ValueType = nil, 'unit text is literal, not a SQL wildcard');
    Resolution := Resolver.Resolve('aps.fibps', 'Wear Area', 'um2');
    Check(Resolution.ValueType.Units = 'mm' + WideChar($00B2),
      'wear area target uses the correct Unicode unit');
  finally
    Resolver.Free;
  end;
end;

begin
  try
    Passed := 0;
    Failed := 0;
    RunTest('fresh local BCrypt principal and stable reopen identity',
      TestFreshPrincipalAndReopen);
    RunTest('original scientific entities and arbitrary attachment persistence',
      TestOriginalEntitiesAndAttachments);
    RunTest('CreateNew preserves existing SQLite bytes',
      TestCreateNewPreservesExistingDatabase);
    RunTest('Open missing database never creates a file',
      TestOpenMissingDoesNotCreateDatabase);
    RunTest('Open refuses zero active principals',
      TestOpenRejectsZeroActivePrincipals);
    RunTest('Open refuses multiple active principals',
      TestOpenRejectsMultipleActivePrincipals);
    RunTest('database cannot be overwritten through attachment storage',
      TestDatabaseCannotBeAnAttachment);
    RunTest('Open refuses recovery sidecars without changing bytes',
      TestOpenPreservesRecoverySidecars);
    RunTest('CreateNew preserves unrelated sidecars',
      TestCreateNewPreservesOrphanSidecars);
    RunTest('Open refuses persisted WAL without creating sidecars',
      TestOpenRefusesPersistedWalWithoutSidecars);
    RunTest('CreateNew preserves a populated attachment directory',
      TestCreateNewPreservesPopulatedStorageRoot);
    RunTest('saved attachment directory follows a moved notebook',
      TestSavedRootOpensMovedNotebook);
    RunTest('missing saved attachment directory is refused',
      TestSavedRootMustExist);
    RunTest('sibling DB and Files directories follow a moved notebook',
      TestSiblingFilesLayoutFollowsMove);
    RunTest('saved attachment directory can be anywhere but must be valid',
      TestSavedRootAnyLocation);
    RunTest('outer attachment directory is saved at creation',
      TestOuterRootIsSaved);
    RunTest('existing notebook remembers its directory only on request',
      TestRememberRootOnExistingNotebook);
    RunTest('category state is notebook-local and read-only on open',
      TestCategoryIsolationAndReadOnlyLoad);
    RunTest('format 2 notebook asks for an explicit upgrade',
      TestFormat2NeedsExplicitUpgrade);
    RunTest('format 2 upgrade keeps data, writes a backup and adds sources',
      TestFormat2UpgradeKeepsDataAndBackup);
    RunTest('format 3 requires upgrade and retains backup',
      TestFormat3NeedsUpgradeAndKeepsBackup);
    RunTest('saved conversion factor controls drift', TestSavedFactorControlsDrift);
    RunTest('mapping precedence and unit mismatch', TestMappingPrecedenceAndUnits);
    RunTest('failed default seeding retains backup and permits retry',
      TestUpgradeSeedFailureCanBeRetried);
    RunTest('format 4 requires upgrade to format 5 and keeps sources',
      TestFormat4UpgradesToFormat5);
    RunTest('new notebook is format 5 with the Derived value types',
      TestFreshNotebookSeedsDerivedTypes);
    WriteLn(Format('%d passed; %d failed', [Passed, Failed]));
    if Failed > 0 then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      WriteLn('FAIL fixture: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
