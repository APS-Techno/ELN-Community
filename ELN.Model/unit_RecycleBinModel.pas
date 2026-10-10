unit unit_RecycleBinModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Item,
  unit_ELNDB_Dictionary,
  unit_AuditLog;

type
  TRecycleBinModel = class
  private
    FManager: TObjectManager;
    FDic: TItemDictionary;

    procedure ExecSQL(const ASQL: string);
    procedure CollectSubtree(AItem: TItem; AList: TList<TItem>);
    procedure PurgeItemRows(AItemId: Integer);
    function PurgeItems(AItems: TList<TItem>): Boolean;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;

    function GetDeletedItems: TItems;
    function RestoreItem(Item: TItem; UserId: Integer): Boolean;
    function PermanentlyDelete(Item: TItem; UserId: Integer): Boolean;
    function EmptyBin(UserId: Integer): Boolean; overload;
    // AKeptRootCount: binned subtrees still in the bin afterwards. ARefused:
    // the purge was refused (a citation got locked, or an item was restored,
    // meanwhile) and rolled back, so nothing at all was deleted.
    function EmptyBin(UserId: Integer; out AKeptRootCount: Integer;
      out ARefused: Boolean): Boolean; overload;
    function GetDeletedCount: Integer;
  end;

implementation

uses
  Aurelius.Drivers.Interfaces,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Projections,
  unit_Hypothesis,
  unit_HypothesisGuard,
  unit_HypothesisModel,
  unit_AuditHelper,
  unit_ConflictHandler;

const
  // Delete by item ID, not the cached graph: unloaded children still hold FKs,
  // and non-FK references can target reused item IDs. ProtocolStatusHistory
  // must go before LabEntries or its parent-ID subselect finds nothing.
  ItemChildDeletes: array[0..10] of string = (
    'DELETE FROM Files WHERE ItemID = %ID%',
    'DELETE FROM DataValues WHERE ItemID = %ID%',
    'DELETE FROM ProtocolStatusHistory WHERE ProtocolId IN '+
      '(SELECT ID FROM LabEntries WHERE ItemID = %ID%)',
    'DELETE FROM LabEntries WHERE ItemID = %ID%',
    'DELETE FROM Comments WHERE ItemId = %ID%',
    'DELETE FROM ItemTags WHERE ItemId = %ID%',
    'DELETE FROM Favorites WHERE ItemId = %ID%',
    'DELETE FROM ItemLinks WHERE SourceItemId = %ID% OR TargetItemId = %ID%',
    // Experiment tree: a purged item leaves no dangling citations. An item
    // cited by an InReview/Accepted hypothesis is never purged: PurgeItems
    // refuses the whole purge first (it may have been cited, and binned,
    // while the hypothesis was still Approved).
    'DELETE FROM HypothesisRuns WHERE ItemId = %ID%',
    'DELETE FROM HypothesisEvidence WHERE ItemId = %ID%',
    // Per-user expanded state: item ids can be reused (SQLite), so the
    // purged item's rows go now, not at the next DB Maintenance.
    'DELETE FROM UserTreeState WHERE NodeKind = 5 AND NodeId = %ID%'
  );

constructor TRecycleBinModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDic := TItemDictionary.Create;
end;

destructor TRecycleBinModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TRecycleBinModel.GetDeletedItems: TItems;
begin
  Result := FManager.Find<TItem>
    .Where(FDic.IsDeleted = True)
    .OrderBy('DeletedDate')
    .List;
end;

function TRecycleBinModel.RestoreItem(Item: TItem; UserId: Integer): Boolean;

  procedure RestoreOne(AItem: TItem);
  var
    Children: TList<TItem>;
    Child: TItem;
  begin
    AItem.IsDeleted := False;
    AItem.DeletedDate := SNull;
    AItem.DeletedBy := SNull;
    FManager.Update(AItem);

    Children := FManager.Find<TItem>
      .Where((FDic.ParentID = AItem.Id) and (FDic.IsDeleted = True))
      .List;
    try
      for Child in Children do
        RestoreOne(Child);
    finally
      Children.Free;
    end;
  end;

begin
  // Flush once for the whole subtree rather than N times (once per node).
  // The previous per-recursion flush was O(N) round-trips against the DB and
  // left the tree partially restored on a mid-recursion conflict.
  RestoreOne(Item);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetItem, Item.Id, aoUpdate, UserId,
      'Restored item "' + Item.Title + '" from recycle bin');
end;

procedure TRecycleBinModel.ExecSQL(const ASQL: string);
var
  Statement: IDBStatement;
begin
  Statement := FManager.Connection.CreateStatement;
  Statement.SetSQLCommand(ASQL);
  Statement.Execute;
end;

procedure TRecycleBinModel.PurgeItemRows(AItemId: Integer);
var
  I: Integer;
begin
  for I := Low(ItemChildDeletes) to High(ItemChildDeletes) do
    ExecSQL(StringReplace(ItemChildDeletes[I], '%ID%', IntToStr(AItemId),
      [rfReplaceAll]));
end;

procedure TRecycleBinModel.CollectSubtree(AItem: TItem; AList: TList<TItem>);
var
  Children: TList<TItem>;
  Child: TItem;
begin
  // Guard against a circular parent chain, and against the same item arriving
  // twice when EmptyBin walks a parent and its child from the same flat list.
  if AList.IndexOf(AItem) >= 0 then
    Exit;
  AList.Add(AItem);

  Children := FManager.Find<TItem>
    .Where((FDic.ParentID = AItem.Id) and (FDic.IsDeleted = True))
    .List;
  try
    for Child in Children do
      CollectSubtree(Child, AList);
  finally
    Children.Free;
  end;
end;

function TRecycleBinModel.PurgeItems(AItems: TList<TItem>): Boolean;
var
  Item: TItem;
  Transaction: IDBTransaction;
  HypId, I: Integer;
  HypStatus: THypothesisStatus;
  Ids: TArray<Integer>;
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Restored: Boolean;
begin
  SetLength(Ids, AItems.Count);
  for I := 0 to AItems.Count - 1 do
    Ids[I] := AItems[I].Id;
  // One transaction for the whole subtree: a purge that fails halfway would
  // otherwise leave an item stripped of its files but still in the bin.
  Transaction := FManager.Connection.BeginTransaction;
  try
    // The list comes from an earlier walk or a dialog opened long ago:
    // another session may have restored an item since. Deleting by id would
    // then destroy a live item with its files and entries. Refuse the whole
    // purge. A projection, so the check reads the database, not this
    // (possibly long-lived) manager's cached IsDeleted.
    for Chunk in IdChunks(Ids) do
    begin
      Rows := FManager.Find<TItem>
        .Select(TProjections.Prop('Id'))
        .Where(Linq['Id']._In(Chunk) and (FDic.IsDeleted = False))
        .ListValues;
      try
        Restored := Rows.Count > 0;
      finally
        Rows.Free;
      end;
      if Restored then
      begin
        Transaction.Rollback;
        Exit(False);
      end;
    end;

    // An item can be cited while its hypothesis is Approved, then binned
    // (allowed), and the hypothesis accepted afterwards. Refuse the whole
    // purge before touching anything. R4: run the check inside the same
    // transaction as the deletes, immediately before them, to narrow the
    // window between the check and its use -- a caller may have checked
    // this same list already (EmptyBin), but another session can still move
    // a hypothesis to InReview/Accepted between that check and this one.
    for Item in AItems do
      if IsItemCitedByLockedHypothesis(FManager, Item.Id, HypId, HypStatus) then
      begin
        Transaction.Rollback;
        Exit(False);
      end;

    for Item in AItems do
    begin
      PurgeItemRows(Item.Id);
      ExecSQL('DELETE FROM Items WHERE Id = ' + IntToStr(Item.Id));
    end;
    Transaction.Commit;
  except
    Transaction.Rollback;
    raise;
  end;

  // Drop the purged objects from the identity map. RecordAudit below calls
  // Flush, which would otherwise try to write rows that no longer exist.
  for Item in AItems do
    FManager.Evict(Item);
  Result := True;
end;

function TRecycleBinModel.PermanentlyDelete(Item: TItem; UserId: Integer): Boolean;
var
  Subtree: TList<TItem>;
  ItemId: Integer;
  ItemTitle: string;
begin
  // Read before the purge: Title is a lazy column and the item is evicted below.
  ItemId := Item.Id;
  ItemTitle := Item.Title;

  Subtree := TList<TItem>.Create;
  try
    CollectSubtree(Item, Subtree);
    Result := PurgeItems(Subtree);
  finally
    Subtree.Free;
  end;

  if not Result then
    Exit;
  RecordAudit(FManager, aetItem, ItemId, aoDelete, UserId,
    'Permanently deleted item "' + ItemTitle + '"');
end;

function TRecycleBinModel.EmptyBin(UserId: Integer): Boolean;
var
  KeptRootCount: Integer;
  Refused: Boolean;
begin
  Result := EmptyBin(UserId, KeptRootCount, Refused);
end;

function TRecycleBinModel.EmptyBin(UserId: Integer;
  out AKeptRootCount: Integer; out ARefused: Boolean): Boolean;
var
  BinnedParent: TDictionary<Integer, Integer>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Walked, ToPurge: TList<TItem>;
  Root: TItem;
  Id, PurgeRootCount: Integer;
  Purged: Boolean;

  procedure Walk(ARoot: TItem);
  var
    Subtree: TList<TItem>;
    SubItem: TItem;
    HypId: Integer;
    HypStatus: THypothesisStatus;
    Locked: Boolean;
  begin
    Subtree := TList<TItem>.Create;
    try
      CollectSubtree(ARoot, Subtree);
      Locked := False;
      for SubItem in Subtree do
      begin
        Walked.Add(SubItem);
        if not Locked then
          Locked := IsItemCitedByLockedHypothesis(FManager, SubItem.Id, HypId, HypStatus);
      end;
      if Locked then
        Inc(AKeptRootCount)
      else
      begin
        Inc(PurgeRootCount);
        for SubItem in Subtree do
          if ToPurge.IndexOf(SubItem) < 0 then
            ToPurge.Add(SubItem);
      end;
    finally
      Subtree.Free;
    end;
  end;

begin
  AKeptRootCount := 0;
  ARefused := False;
  PurgeRootCount := 0;
  Purged := False;

  // Project committed parent links: cached restored parents can otherwise
  // make a binned child look covered by an ancestor and skip its purge.
  BinnedParent := TDictionary<Integer, Integer>.Create;
  Walked := TList<TItem>.Create;
  ToPurge := TList<TItem>.Create;
  try
    Rows := FManager.Find<TItem>
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id'))
        .Add(TProjections.Prop('ParentID').As_('ParentId')))
      .Where(FDic.IsDeleted = True)
      .ListValues;
    try
      for Row in Rows do
        BinnedParent.Add(Integer(Row.Values['Id']), Integer(Row.Values['ParentId']));
    finally
      Rows.Free;
    end;

    for Id in BinnedParent.Keys do
      if not BinnedParent.ContainsKey(BinnedParent[Id]) then
      begin
        Root := FManager.Find<TItem>(Id);
        if Assigned(Root) then
          Walk(Root);
      end;
    // Parent cycles have no root; walk them explicitly so no binned item is skipped.
    for Id in BinnedParent.Keys do
    begin
      Root := FManager.Find<TItem>(Id);
      if Assigned(Root) and (Walked.IndexOf(Root) < 0) then
        Walk(Root);
    end;

    if ToPurge.Count > 0 then
    begin
      // PurgeItems re-checks every item inside its own transaction; a
      // False here means another session locked or restored one of them
      // between the walk above and now, and the purge rolled back: NOTHING
      // was deleted, so every subtree queued for it was kept too (MO-8).
      ARefused := not PurgeItems(ToPurge);
      Purged := not ARefused;
      if ARefused then
        Inc(AKeptRootCount, PurgeRootCount);
    end;
  finally
    ToPurge.Free;
    Walked.Free;
    BinnedParent.Free;
  end;

  Result := AKeptRootCount = 0;
  // Audit exactly when something was permanently deleted: a partial purge
  // (some subtrees kept) still deleted every other binned item and must be
  // on record, while an empty bin, an all-kept bin or a
  // refused purge (PurgeItems rolls back) deleted nothing and must not claim
  // it emptied anything.
  if not Purged then
    Exit;
  if AKeptRootCount > 0 then
    RecordAudit(FManager, aetItem, 0, aoDelete, UserId,
      Format('Emptied recycle bin (%d kept: cited by a hypothesis in review/accepted)',
        [AKeptRootCount]))
  else
    RecordAudit(FManager, aetItem, 0, aoDelete, UserId,
      'Emptied recycle bin');
end;

function TRecycleBinModel.GetDeletedCount: Integer;
var
  Items: TItems;
begin
  Items := FManager.Find<TItem>
    .Where(FDic.IsDeleted = True)
    .List;
  try
    Result := Items.Count;
  finally
    Items.Free;
  end;
end;

end.
