unit unit_TreeStateModel;

{ Own the manager so failed tree-state writes cannot poison shared drafts.
  Main-thread queued Flush batches expansion changes into one transaction.
  Preserve FKnown on failed reload: connection loss must not unseed the user. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_UserTreeState;

type
  /// Ord = the NodeKind column. tnkSeeded (NodeId 0) marks a user whose
  /// state was copied once from the old shared Expanded columns.
  TTreeNodeKind = (tnkSeeded, tnkProject, tnkFolder, tnkGroup, tnkUser, tnkItem);

const
  /// Rows of UserTreeState whose user or node no longer exists (no leading
  /// WHERE). Items in the Recycle Bin are still in Items, so their rows stay.
  TREE_STATE_ORPHAN_WHERE =
    'UserId NOT IN (SELECT Id FROM Users)' +
    ' OR (NodeKind = 1 AND NodeId NOT IN (SELECT Id FROM Projects))' +
    ' OR (NodeKind = 2 AND NodeId NOT IN (SELECT Id FROM Folders))' +
    ' OR (NodeKind = 3 AND NodeId NOT IN (SELECT Id FROM ProjectGroups))' +
    ' OR (NodeKind = 4 AND NodeId NOT IN (SELECT Id FROM Users))' +
    ' OR (NodeKind = 5 AND NodeId NOT IN (SELECT Id FROM Items))';

type
  TTreeStateModel = class
  private
    FManager: TObjectManager;
    FUserId: Integer;
    FRows: TDictionary<Int64, TUserTreeState>;   // manager-owned entities
    FRowsValid: Boolean;   // FRows matches the manager; else reload before writing
    FKnown: TDictionary<Int64, Boolean>;   // what the database holds
    FPending: TDictionary<Int64, Boolean>;
    FAutoFlush: Boolean;
    FFlushQueued: Boolean;
    FLastError: string;
    class function Key(AKind, ANodeId: Integer): Int64; static;
    procedure ReloadRows;
    procedure WritePending;
    procedure QueuedFlush;
  public
    /// Takes ownership of AManager (give it a manager of its own).
    constructor Create(AManager: TObjectManager);
    destructor Destroy; override;
    /// Flushes what the previous user left pending, then reads AUserId's rows.
    procedure Load(AUserId: Integer);
    function IsExpanded(Kind: TTreeNodeKind; NodeId: Integer; Default: Boolean): Boolean;
    procedure SetExpanded(Kind: TTreeNodeKind; NodeId: Integer; Value: Boolean);
    function Seeded: Boolean;
    procedure MarkSeeded;
    /// Writes every pending node. False (see LastError) when it could not;
    /// the changes stay pending.
    function Flush: Boolean;
    function PendingCount: Integer;
    property UserId: Integer read FUserId;
    /// Queue a Flush on the main thread after each change (the app). Tests
    /// switch it off and call Flush themselves.
    property AutoFlush: Boolean read FAutoFlush write FAutoFlush;
    property LastError: string read FLastError;
  end;

implementation

uses
  Aurelius.Criteria.Linq,
  Aurelius.Drivers.Interfaces;


constructor TTreeStateModel.Create(AManager: TObjectManager);
begin
  inherited Create;
  FManager := AManager;
  FRows := TDictionary<Int64, TUserTreeState>.Create;
  FKnown := TDictionary<Int64, Boolean>.Create;
  FPending := TDictionary<Int64, Boolean>.Create;
  FAutoFlush := True;
end;

destructor TTreeStateModel.Destroy;
begin
  // A queued flush must never run on a freed model.
  TThread.RemoveQueuedEvents(QueuedFlush);
  FPending.Free;
  FKnown.Free;
  FRows.Free;
  FManager.Free;
  inherited;
end;

class function TTreeStateModel.Key(AKind, ANodeId: Integer): Int64;
begin
  Result := (Int64(AKind) shl 32) or Int64(Cardinal(ANodeId));
end;

procedure TTreeStateModel.ReloadRows;
var
  List: TList<TUserTreeState>;
  Row: TUserTreeState;
begin
  FRows.Clear;
  FManager.Clear;
  FRowsValid := False;
  if FUserId <> 0 then
  begin
    // A raise here leaves FKnown as it was.
    List := FManager.Find<TUserTreeState>
      .Where(Linq['UserId'] = FUserId)
      .List;
    try
      FKnown.Clear;
      for Row in List do
      begin
        FRows.AddOrSetValue(Key(Row.NodeKind, Row.NodeId), Row);
        FKnown.AddOrSetValue(Key(Row.NodeKind, Row.NodeId), Row.Expanded);
      end;
    finally
      List.Free;
    end;
  end;
  FRowsValid := True;
end;

procedure TTreeStateModel.Load(AUserId: Integer);
begin
  Flush;
  TThread.RemoveQueuedEvents(QueuedFlush);
  FFlushQueued := False;
  FPending.Clear;
  FUserId := AUserId;
  FKnown.Clear;
  ReloadRows;
end;

function TTreeStateModel.IsExpanded(Kind: TTreeNodeKind; NodeId: Integer;
  Default: Boolean): Boolean;
var
  K: Int64;
begin
  K := Key(Ord(Kind), NodeId);
  if FPending.TryGetValue(K, Result) then Exit;
  if FKnown.TryGetValue(K, Result) then Exit;
  Result := Default;
end;

procedure TTreeStateModel.SetExpanded(Kind: TTreeNodeKind; NodeId: Integer;
  Value: Boolean);
var
  K: Int64;
  Stored, Old: Boolean;
begin
  if FUserId = 0 then Exit;
  K := Key(Ord(Kind), NodeId);
  if FKnown.TryGetValue(K, Stored) and (Stored = Value) then
  begin
    FPending.Remove(K);
    Exit;
  end;
  if FPending.TryGetValue(K, Old) and (Old = Value) then Exit;
  FPending.AddOrSetValue(K, Value);
  if FAutoFlush and not FFlushQueued then
  begin
    FFlushQueued := True;
    TThread.ForceQueue(nil, QueuedFlush);
  end;
end;

function TTreeStateModel.Seeded: Boolean;
begin
  Result := IsExpanded(tnkSeeded, 0, False);
end;

procedure TTreeStateModel.MarkSeeded;
begin
  SetExpanded(tnkSeeded, 0, True);
end;

procedure TTreeStateModel.WritePending;
var
  Trans: IDBTransaction;
  Pair: TPair<Int64, Boolean>;
  Row: TUserTreeState;
begin
  if not FRowsValid then
    ReloadRows;
  Trans := FManager.Connection.BeginTransaction;
  try
    for Pair in FPending do
      if FRows.TryGetValue(Pair.Key, Row) then
        Row.Expanded := Pair.Value
      else
      begin
        Row := TUserTreeState.Create;
        Row.UserId := FUserId;
        Row.NodeKind := Integer(Pair.Key shr 32);
        Row.NodeId := Integer(Cardinal(Pair.Key and $FFFFFFFF));
        Row.Expanded := Pair.Value;
        try
          FManager.Save(Row);   // the manager owns it from here
        except
          if not FManager.IsAttached(Row) then
            Row.Free;
          raise;
        end;
        FRows.Add(Pair.Key, Row);
      end;
    FManager.Flush;
    Trans.Commit;
  except
    Trans.Rollback;
    raise;
  end;
  for Pair in FPending do
    FKnown.AddOrSetValue(Pair.Key, Pair.Value);
  FPending.Clear;
end;

function TTreeStateModel.Flush: Boolean;
begin
  FFlushQueued := False;
  Result := True;
  if (FPending.Count = 0) or (FUserId = 0) then Exit;
  try
    WritePending;
  except
    // A row the other PC wrote meanwhile, or a lost write: start again from
    // what the database holds, once.
    try
      ReloadRows;
      WritePending;
    except
      on E: Exception do
      begin
        FLastError := E.Message;
        Result := False;
        // The manager may hold rows the rollback undid: reload before the
        // next write. FKnown still says what is stored.
        FRowsValid := False;
      end;
    end;
  end;
end;

procedure TTreeStateModel.QueuedFlush;
begin
  Flush;
end;

function TTreeStateModel.PendingCount: Integer;
begin
  Result := FPending.Count;
end;

end.
