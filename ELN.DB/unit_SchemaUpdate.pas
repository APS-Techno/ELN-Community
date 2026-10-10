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
