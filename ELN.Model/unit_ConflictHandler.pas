unit unit_ConflictHandler;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_NotebookStorage,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager;

type
  TConflictResolution = (crReload, crCancel);
  TConflictCallback = reference to function(const Msg: string): TConflictResolution;

  // Keep the successful move journal until the database transaction commits.
  // Rollback attempts every reversal and reports any paths needing recovery.
  TFileMoveJournal = class
  private
    FRelocator: IFileRelocator;
    FMoves: TList<TPair<string, string>>;
    FCompleted: Integer;
  public
    constructor Create(const Relocator: IFileRelocator);
    destructor Destroy; override;
    procedure Add(const OldPath, NewPath: string);
    procedure Execute;
    procedure Rollback;
  end;

  TConflictHandler = class
    class var OnConflict: TConflictCallback;
    class function SafeFlush(Manager: TObjectManager): Boolean;
    // Does not flush, detach or destroy any entity in the host manager.
    class procedure FreeOperationManager(Manager: TObjectManager);
    // Attachment journals cannot outlive an outer caller transaction.
    class function BeginOperationTransaction(Manager: TObjectManager): IDBTransaction;
    /// <summary>After an optimistic-lock failure (E is
    /// EVersionedConcurrencyControl; anything else is ignored): reloads the
    /// entity that conflicted, if Manager caches it. Its changes can never be
    /// flushed (the row moved on), and left dirty in a long-lived shared
    /// manager they would fail every later Flush, whoever calls it. Never
    /// raises.</summary>
    class procedure ReloadConflicted(Manager: TObjectManager; E: Exception);
  end;

implementation

uses
  System.Classes,
  Aurelius.Commands.Exceptions,
  unit_Project;

constructor TFileMoveJournal.Create(const Relocator: IFileRelocator);
begin
  inherited Create;
  FRelocator := Relocator;
  FMoves := TList<TPair<string, string>>.Create;
end;

destructor TFileMoveJournal.Destroy;
begin
  FMoves.Free;
  inherited;
end;

procedure TFileMoveJournal.Add(const OldPath, NewPath: string);
begin
  if OldPath = NewPath then
    Exit;
  if FRelocator = nil then
    raise EInvalidOperation.Create('Attachment relocation is required for this change.');
  FMoves.Add(TPair<string, string>.Create(OldPath, NewPath));
end;

procedure TFileMoveJournal.Execute;
begin
  while FCompleted < FMoves.Count do
  begin
    FRelocator.MoveFile(FMoves[FCompleted].Key, FMoves[FCompleted].Value);
    Inc(FCompleted);
  end;
end;

procedure TFileMoveJournal.Rollback;
var
  I: Integer;
  Failures: string;
begin
  Failures := '';
  for I := FCompleted - 1 downto 0 do
    try
      FRelocator.MoveFile(FMoves[I].Value, FMoves[I].Key);
    except
      on E: Exception do
        Failures := Failures + sLineBreak + FMoves[I].Value + ' -> ' +
          FMoves[I].Key + ': ' + E.Message;
    end;
  FCompleted := 0;
  if Failures <> '' then
    raise EInvalidOperation.Create('Attachment rollback failed. Recover these paths:' + Failures);
end;

class procedure TConflictHandler.FreeOperationManager(Manager: TObjectManager);
var
  Previous: Boolean;
begin
  Previous := ManagerShuttingDown;
  ManagerShuttingDown := True;
  try
    Manager.Free;
  finally
    ManagerShuttingDown := Previous;
  end;
end;

class function TConflictHandler.BeginOperationTransaction(
  Manager: TObjectManager): IDBTransaction;
var
  State: IDBConnection2;
begin
  if not Supports(Manager.Connection, IDBConnection2, State) then
    raise EInvalidOperation.Create('This connection cannot establish transaction ownership.');
  if State.InTransaction then
    raise EInvalidOperation.Create('Finish the active transaction before moving attachments.');
  Result := Manager.Connection.BeginTransaction;
end;

class function TConflictHandler.SafeFlush(Manager: TObjectManager): Boolean;
begin
  try
    Manager.Flush;
    Result := True;
  except
    on E: EVersionedConcurrencyControl do
    begin
      ReloadConflicted(Manager, E);
      if Assigned(OnConflict) then
        OnConflict(E.Message)
      else
        raise;
      Result := False;
    end;
  end;
end;

function QuotedAfter(const S, ALabel: string): string;
var
  P, Q: Integer;
begin
  Result := '';
  P := Pos(ALabel + ' "', S);
  if P = 0 then
    Exit;
  Inc(P, Length(ALabel) + 2);
  Q := Pos('"', S, P);
  if Q > P then
    Result := Copy(S, P, Q - P);
end;

class procedure TConflictHandler.ReloadConflicted(Manager: TObjectManager;
  E: Exception);
var
  Clazz: TClass;
  Obj: TObject;
begin
  if not (E is EVersionedConcurrencyControl) then
    Exit;
  // The exception carries no fields: Aurelius names the entity only in its
  // message, 'Entity class: "%s", Id: "%s", Version: %s'
  // (Aurelius.Commands.Exceptions). The Id is formatted by the same
  // TUtils.VariantToString as the identity-map key, so FindCached matches
  // it as a string. test_HypothesisConcurrency pins the format.
  try
    Clazz := Manager.Explorer.Hierarchy.FindClassByName(
      QuotedAfter(E.Message, 'Entity class:'));
    if Clazz = nil then
      Exit;
    Obj := Manager.FindCached(Clazz, QuotedAfter(E.Message, 'Id:'));
    if Obj = nil then
      Exit;
    Manager.Refresh(Obj);
    // Refresh ignores a row that is gone (InternalRefresh skips zero rows),
    // so a row deleted meanwhile leaves Obj dirty. Detach it; the manager
    // still owns and frees it.
    // Evict cascades to Obj's child collections, which are then
    // owned by nobody and leak; accepted over a manager poisoned for good.
    if Manager.HasChanges(Obj) then
    begin
      Manager.Evict(Obj);
      Manager.AddOwnership(Obj);
    end;
  except
  end;
end;

end.
