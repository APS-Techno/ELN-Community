unit unit_SchemaUpdate;

{
  Aurelius UpdateDatabase can drop constraints absent from the mapping.
  Execute only additions; skip creates whose names already exist because
  they can be the second half of an alter. Column changes remain validation
  errors: Aurelius produces no DDL command for them.
}

interface

uses
  Aurelius.Drivers.Interfaces,
  Aurelius.Mapping.Explorer,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Schema.Commands,
  Aurelius.Sql.Metadata;

type
  TAdditiveDatabaseManager = class(TDatabaseManager)
  public
    // Returns descriptions of skipped commands; empty means none were skipped.
    function UpdateDatabaseAdditive: TArray<string>;
    class function IsAdditive(ACommand: TDDLCommand; AExistingDB: TDatabaseMetadata;
      out ADescription: string): Boolean; static;
  end;

function UpdateDatabaseAdditive(const AConnection: IDBConnection;
  AExplorer: TMappingExplorer = nil): TArray<string>;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Commands.AbstractCommandPerformer,
  Aurelius.Commands.CommandPerformerFactory,
  Aurelius.Schema.Utils;

function QualifiedName(ATable: TTableMetadata; const AName: string): string;
begin
  if ATable = nil then
    Result := AName
  else if AName = '' then
    Result := ATable.Name
  else
    Result := ATable.Name + '.' + AName;
end;

function ExistingTable(AExistingDB: TDatabaseMetadata; ATable: TTableMetadata): TTableMetadata;
begin
  Result := nil;
  if (AExistingDB <> nil) and (ATable <> nil) then
    Result := TSchemaUtils.FindTable(AExistingDB, ATable.Name, ATable.Schema);
end;


class function TAdditiveDatabaseManager.IsAdditive(ACommand: TDDLCommand;
  AExistingDB: TDatabaseMetadata; out ADescription: string): Boolean;
var
  T: TTableMetadata;
begin
  Result := False;
  if ACommand is TCreateTableCommand then
  begin
    ADescription := 'create table ' + TCreateTableCommand(ACommand).Table.Name;
    Result := True;
  end
  else if ACommand is TCreateColumnCommand then
  begin
    ADescription := 'create column ' + QualifiedName(
      TCreateColumnCommand(ACommand).Column.Table, TCreateColumnCommand(ACommand).Column.Name);
    Result := True;
  end
  else if ACommand is TCreateSequenceCommand then
  begin
    ADescription := 'create sequence ' + TCreateSequenceCommand(ACommand).Sequence.Name;
    Result := True;
  end
  else if ACommand is TCreateDBIndexCommand then
  begin
    ADescription := 'create index ' + QualifiedName(
      TCreateDBIndexCommand(ACommand).DBIndex.Table, TCreateDBIndexCommand(ACommand).DBIndex.Name);
    // Aurelius re-creates an index whose columns changed under the SAME name
    // (without dropping the old one): that is an alter, not an addition.
    T := ExistingTable(AExistingDB, TCreateDBIndexCommand(ACommand).DBIndex.Table);
    Result := (T = nil) or (TCreateDBIndexCommand(ACommand).DBIndex.Name = '') or
      (TSchemaUtils.FindDBIndex(T, TCreateDBIndexCommand(ACommand).DBIndex.Name) = nil);
    if not Result then
      ADescription := 'alter index ' + QualifiedName(
        TCreateDBIndexCommand(ACommand).DBIndex.Table, TCreateDBIndexCommand(ACommand).DBIndex.Name);
  end
  else if ACommand is TCreateForeignKeyCommand then
  begin
    ADescription := 'create foreign key ' + QualifiedName(
      TCreateForeignKeyCommand(ACommand).ForeignKey.FromTable,
      TCreateForeignKeyCommand(ACommand).ForeignKey.Name);
    // A changed foreign key is planned as drop + create with the same name;
    // the drop is skipped below, so the create must be skipped too.
    T := ExistingTable(AExistingDB, TCreateForeignKeyCommand(ACommand).ForeignKey.FromTable);
    Result := (T = nil) or (TCreateForeignKeyCommand(ACommand).ForeignKey.Name = '') or
      (TSchemaUtils.FindForeignKey(T, TCreateForeignKeyCommand(ACommand).ForeignKey.Name) = nil);
    if not Result then
      ADescription := 'alter foreign key ' + QualifiedName(
        TCreateForeignKeyCommand(ACommand).ForeignKey.FromTable,
        TCreateForeignKeyCommand(ACommand).ForeignKey.Name);
  end
  else if ACommand is TDropForeignKeyCommand then
    ADescription := 'drop foreign key ' + QualifiedName(
      TDropForeignKeyCommand(ACommand).ForeignKey.FromTable,
      TDropForeignKeyCommand(ACommand).ForeignKey.Name)
  else if ACommand is TDropUniqueKeyCommand then
    ADescription := 'drop unique key ' + QualifiedName(
      TDropUniqueKeyCommand(ACommand).Uniquekey.Table,
      TDropUniqueKeyCommand(ACommand).Uniquekey.Name)
  else if ACommand is TDropDBIndexCommand then
    ADescription := 'drop index ' + QualifiedName(
      TDropDBIndexCommand(ACommand).DBIndex.Table, TDropDBIndexCommand(ACommand).DBIndex.Name)
  else if ACommand is TDropTableCommand then
    ADescription := 'drop table ' + TDropTableCommand(ACommand).Table.Name
  else if ACommand is TDropSequenceCommand then
    ADescription := 'drop sequence ' + TDropSequenceCommand(ACommand).Sequence.Name
  else if ACommand is TDropColumnCommand then
    ADescription := 'drop column ' + QualifiedName(
      TDropColumnCommand(ACommand).Column.Table, TDropColumnCommand(ACommand).Column.Name)
  else
    // TEnableForeignKeysCommand (only planned around destructive SQLite
    // rebuilds) and any command a future Aurelius adds: not additive until
    // someone decides otherwise.
    ADescription := ACommand.ClassName;
end;

function TAdditiveDatabaseManager.UpdateDatabaseAdditive: TArray<string>;
var
  Trans: IDBTransaction;
  Cmd: TDDLCommand;
  Keep: TList<string>;
  Skipped: TList<string>;
  Descr, SQL: string;
  Performer: TSQLPerformer;
  procedure MigrateThicknessToNanometres(APerformer: TSQLPerformer);
  const
    THICKNESS_IN_METRES =
      'SELECT Id FROM ValueTypes WHERE LOWER(Title) = ''thickness'' AND Units = ''m''';
  var
    HasValueTypes, HasMappings, HasValues: Boolean;
    C: TDDLCommand;
  begin
    HasValueTypes := (ExistingDB <> nil) and
      (TSchemaUtils.FindTable(ExistingDB, 'ValueTypes', '') <> nil);
    HasMappings := (ExistingDB <> nil) and
      (TSchemaUtils.FindTable(ExistingDB, 'ReaderValueMappings', '') <> nil);
    HasValues := (ExistingDB <> nil) and
      (TSchemaUtils.FindTable(ExistingDB, 'DataValues', '') <> nil);
    for C in Commands do
      if C is TCreateTableCommand then
        if SameText(TCreateTableCommand(C).Table.Name, 'ValueTypes') then
          HasValueTypes := True
        else if SameText(TCreateTableCommand(C).Table.Name, 'ReaderValueMappings') then
          HasMappings := True
        else if SameText(TCreateTableCommand(C).Table.Name, 'DataValues') then
          HasValues := True;
    if not HasValueTypes then
      Exit;
    if HasMappings then
    begin
      APerformer.ExecuteSQL(
        'UPDATE ReaderValueMappings SET Factor = Factor * 1000000000 ' +
        'WHERE ValueTypeId IN (' + THICKNESS_IN_METRES + ')');
      APerformer.ExecuteSQL(
        'UPDATE ReaderValueMappings SET Factor = 0.1 ' +
        'WHERE ReaderId = ''aps.xrcx'' AND KeyPattern = ''<Material> Thickness'' ' +
        'AND ReaderUnits = ''A'' AND ABS(Factor - 1e-10) < 1e-20 ' +
        'AND ValueTypeId IN (' +
        'SELECT Id FROM ValueTypes WHERE LOWER(Title) = ''thickness'' AND Units = ''nm'')');
      APerformer.ExecuteSQL(
        'UPDATE ReaderValueMappings SET Factor = 1000 ' +
        'WHERE ReaderId = ''aps.fibps'' AND KeyPattern = ''Step Height'' ' +
        'AND ReaderUnits = ''um'' AND ABS(Factor - 1e-6) < 1e-16 ' +
        'AND ValueTypeId IN (' +
        'SELECT Id FROM ValueTypes WHERE LOWER(Title) = ''thickness'' AND Units = ''nm'')');
    end;
    if HasValues then
      APerformer.ExecuteSQL(
        'UPDATE DataValues SET Value = Value * 1000000000, ' +
        'Tolerance = Tolerance * 1000000000, ' +
        'ConversionFactor = ConversionFactor * 1000000000 ' +
        'WHERE TypeID IN (' + THICKNESS_IN_METRES + ')');
    APerformer.ExecuteSQL(
      'UPDATE ValueTypes SET Units = ''nm'', ' +
      'RangeMin = RangeMin * 1000000000, RangeMax = RangeMax * 1000000000 ' +
      'WHERE LOWER(Title) = ''thickness'' AND Units = ''m''');
  end;
begin
  Keep := TList<string>.Create;
  Skipped := TList<string>.Create;
  try
    if UseTransactions then
      Trans := Connection.BeginTransaction
    else
      Trans := nil;
    try
      ValidateDatabase;
      for Cmd in Commands do
        if IsAdditive(Cmd, ExistingDB, Descr) then
          Keep.Add(Cmd.BuildSQL(SQLGenerator))
        else
          Skipped.Add(Descr);
      if SQLExecutionEnabled then
      begin
        Performer := CommandFactory.GetSqlCommand<TSQLPerformer>;
        try
          for SQL in Keep do
            Performer.ExecuteSQL(SQL);
          MigrateThicknessToNanometres(Performer);
        finally
          Performer.Free;
        end;
      end;
      if Trans <> nil then
        Trans.Commit;
    except
      if Trans <> nil then
        Trans.Rollback;
      raise;
    end;
    Result := Skipped.ToArray;
  finally
    Skipped.Free;
    Keep.Free;
  end;
end;

function UpdateDatabaseAdditive(const AConnection: IDBConnection;
  AExplorer: TMappingExplorer): TArray<string>;
var
  DBM: TAdditiveDatabaseManager;
begin
  if AExplorer = nil then
    AExplorer := TMappingExplorer.Default;
  DBM := TAdditiveDatabaseManager.Create(AConnection, AExplorer);
  try
    Result := DBM.UpdateDatabaseAdditive;
  finally
    DBM.Free;
  end;
end;

end.
