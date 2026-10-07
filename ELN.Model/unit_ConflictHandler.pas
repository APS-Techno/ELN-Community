unit unit_ConflictHandler;

interface

uses
  System.SysUtils,
  Aurelius.Engine.ObjectManager;

type
  TConflictResolution = (crReload, crCancel);
  TConflictCallback = reference to function(const Msg: string): TConflictResolution;

  TConflictHandler = class
    class var OnConflict: TConflictCallback;
    class function SafeFlush(Manager: TObjectManager): Boolean;
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
  Aurelius.Commands.Exceptions;

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

// The text between '<ALabel> "' and the next '"' in S; '' when absent.
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
    // ponytail: Evict cascades to Obj's child collections, which are then
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
