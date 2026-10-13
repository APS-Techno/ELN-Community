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
  RebuildWithoutColumns('DataValues', ['SourceKind', 'SourceFileId',
    'ReaderId', 'ReaderVersion', 'KeyName', 'SourceNote']);
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
    end, 'a format 3 notebook is not upgraded again');

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
    RunTest('category state is notebook-local and read-only on open',
      TestCategoryIsolationAndReadOnlyLoad);
    RunTest('format 2 notebook asks for an explicit upgrade',
      TestFormat2NeedsExplicitUpgrade);
    RunTest('format 2 upgrade keeps data, writes a backup and adds sources',
      TestFormat2UpgradeKeepsDataAndBackup);
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
