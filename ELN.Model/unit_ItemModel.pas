unit unit_ItemModel;

interface
uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  System.Classes,
  System.Generics.Collections,
  unit_TELNModel,
  unit_ItemTypes,
  unit_Item,
  unit_ActionType,
  unit_Equipment,
  unit_LabEntry,
  unit_Protocol,
  unit_FileRelocator,
  unit_NotebookStorage,
  unit_FileType,
  unit_ValueType,
  unit_ELNDB_Dictionary,
  unit_AuditLog;

type

  TItemModel = class(TELNModel)
    private
      FDic: TItemDictionary;
      FManager: TObjectManager;
      FProjectID, FFolderID: integer;
      procedure CollectLiveSubtree(Item: TItem; AList: TList<TItem>);

   protected
      function GetDataSet: TAureliusDataset; override;
      function GetItemsList: TItems;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;
      procedure AssignProject(const ProjectId, FolderID: integer);
      property List: TItems read GetItemsList;
      property Manager: TObjectManager read FManager;

      function AddItem(const IType: TItemType;
                                  Title: string;
                                  Level: TItemLevel = TItemLevel.Proc;
                                 Parent: integer = 0;
                            Description: string = '';
                                  AType: TActionType = nil;
                             AEquipment: TEquipment = nil;
                                 UserId: Integer = 0;
                             Properties: string = ''): TItem;


      procedure AddNote(const Title, Content: string; UserId: Integer; var Item: TItem);
      procedure AddProtocol(const Title: string;
                            ProtocolType: TProtocolType;
                            TemplateId: Integer;
                            UserId: Integer;
                            var Item: TItem;
                            const FormData: string = '');

      function AddFile(const FType: TFileType;
                       Title: string; UserId: Integer; var  Item: TItem): TFile;

      procedure AddValue(ValueType: TValueType; RecType: TRecType;
        AValue: double; UserId: Integer; var Item: TItem;
        Tol: double = 0; Description: string = '');
      procedure RemoveValue(Val: TValue; var Item: TItem; UserId: Integer);
      function RemoveFile(AFile: TFile; var Item: TItem; UserId: Integer): Boolean;
      procedure RemoveEntry(Entry: TLabEntry; var Item: TItem; UserId: Integer);

      function GetItem(const ID:integer):TItem;
      function GetItemForEntry(EntryId: Integer): TItem;
      function UpdateItem(Item: TItem; UserId: Integer): Boolean;
      // Attachments are stored under files/Projects/<project>/[id]<title>/, so
      // a title change must move them or every existing file becomes
      // unreachable. Call BEFORE flushing the new title: Item.Title already
      // holds the new value, OldTitle the previous one. Moves file by file;
      // if one move fails, the files already moved are moved back (best
      // effort) and the exception is re-raised, so the caller can revert the
      // title without touching storage. No-op when the title is unchanged,
      // the item has no files, or Relocator is nil (local storage mode).
      procedure RelocateFilesForRename(Item: TItem; const OldTitle: string;
        const Relocator: IFileRelocator);
      function UpdateEntry(Entry: TLabEntry; UserId: Integer): Boolean;
      function UpdateFile(AFile: TFile; UserId: Integer): Boolean;
      function MoveFile(AFile: TFile; NewParentId, UserId: Integer): Boolean;
      function ReorderItems(Items: TItems): Boolean;
      function MoveProc(Proc: TItem; NewProjectID, NewFolderID, UserID: Integer;
  const Relocator: IFileRelocator = nil): Boolean;

      function IsItemEmpty(Item: TItem): Boolean;
      function DeleteItem(Item: TItem; UserId: Integer): Boolean;
      function SoftDeleteItemTree(Item: TItem; UserId: Integer): Boolean;
      // '' when Item and its whole live subtree may be deleted; otherwise the
      // user-facing sentence naming the signed or hypothesis-locked item that
      // blocks it.
      function FindDeleteBlocker(Item: TItem): string;
      function GetRecentItems(UserId: Integer; Count: Integer = 20): TItems; overload;
      function GetRecentItems(UserId: Integer; DateFrom: TDateTime; Count: Integer = 20): TItems; overload;
      procedure EvictCache;
  end;

implementation

uses
  unit_AuditHelper,
  unit_ConflictHandler,
  unit_SignatureModel,
  unit_DataModel,
  unit_Project,
  unit_TimeHelper,
  unit_Hypothesis,
  unit_HypothesisGuard;

{ TItemModel }

function TItemModel.AddFile(const FType: TFileType; Title: string;
  UserId: Integer; var Item: TItem): TFile;
var
  ManagedFileType: TFileType;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit(nil);

  // Get managed instance of FileType from ObjectManager
  ManagedFileType := FManager.Find<TFileType>(FType.Id);

  Result := TFile.Create;
  Result.FileType := ManagedFileType;
  Result.Title   := Title;
  Result.CreatedDate := UTCNow;
  Result.CreatedBy := UserId;
  Result.Item := Item;

  Item.Files.Add(Result);

  FManager.Update(Item);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit(nil);
  RecordAudit(FManager, aetFile, Result.Id, aoCreate, UserId,
    'Added file "' + Title + '" to item "' + Item.Title + '"');
end;

function TItemModel.AddItem(const IType: TItemType;
                                  Title: string;
                                  Level: TItemLevel;
                                 Parent: integer;
                            Description: string;
                                  AType: TActionType;
                             AEquipment: TEquipment;
                                 UserId: Integer;
                             Properties: string): TItem;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.Description := Description;
  Result.Type_ := IType;
  Result.Level := Level;
  Result.CreatedDate := UTCNow;
  Result.ProjectID := FProjectID;
  Result.FolderID := FFolderID;
  Result.Parent := Parent;
  Result.Expanded := True;
  Result.Properties := Properties;

  if Assigned(AType) then
    Result.ActionType := FManager.Find<TActionType>(AType.Id);

  if Assigned(AEquipment) then
    Result.Equipment := FManager.Find<TEquipment>(AEquipment.Id);

  FManager.Save(Result);
  FManager.Flush;
  RecordAudit(FManager, aetItem, Result.Id, aoCreate, UserId,
    'Created item "' + Title + '"');
  FManager.Evict(Result);
end;

procedure TItemModel.AddNote(const Title, Content: string; UserId: Integer; var Item: TItem);
var
  Protocol: TProtocol;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  Protocol := TProtocol.Create;
  Protocol.Title := Title;
  Protocol.FormData := Content;
  Protocol.ProtocolType := ptNote;
  Protocol.ValidationStatus := vsDraft;
  Protocol.CreatedDate := UTCNow;
  Protocol.CreatedBy := UserId;

  Item.Entries.Add(Protocol);
  FManager.Update(Item);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetNote, Protocol.Id, aoCreate, UserId,
    'Added note "' + Title + '" to item "' + Item.Title + '"');
end;

procedure TItemModel.AddProtocol(const Title: string;
                                 ProtocolType: TProtocolType;
                                 TemplateId: Integer;
                                 UserId: Integer;
                                 var Item: TItem;
                                 const FormData: string = '');
var
  Protocol: TProtocol;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  Protocol := TProtocol.Create;
  Protocol.Title := Title;
  Protocol.ProtocolType := ProtocolType;
  Protocol.TemplateId := TemplateId;
  Protocol.FormData := FormData;
  Protocol.ValidationStatus := vsDraft;
  Protocol.CreatedDate := UTCNow;
  Protocol.CreatedBy := UserId;

  // Snapshot equipment from parent Item's ActionType
  if Assigned(Item.ActionType) and Assigned(Item.ActionType.Equipment) then
  begin
    Protocol.EquipModel := Item.ActionType.Equipment.Model;
    Protocol.EquipManufacturer := Item.ActionType.Equipment.Manufacturer;
    Protocol.EquipLocation := Item.ActionType.Equipment.Location;
  end;

  Item.Entries.Add(Protocol);
  FManager.Update(Item);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetProtocol, Protocol.Id, aoCreate, UserId,
    'Added protocol "' + Title + '" to item "' + Item.Title + '"');
end;

procedure TItemModel.AssignProject(const ProjectID, FolderID: integer);
begin
  FProjectID := ProjectID;
  FFolderID := FolderID;
end;

constructor TItemModel.Create;
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TItemDictionary.Create;
end;

destructor TItemModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

procedure TItemModel.AddValue(ValueType: TValueType; RecType: TRecType;
  AValue: double; UserId: Integer; var Item: TItem;
  Tol: double; Description: string);
var
  ManagedValueType: TValueType;
  Val: TValue;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  ManagedValueType := FManager.Find<TValueType>(ValueType.Id);

  Val := TValue.Create;
  Val.ValueType := ManagedValueType;
  Val.RecType := RecType;
  Val.Value := AValue;
  Val.Tol := Tol;
  Val.Description := Description;
  Val.CreatedDate := UTCNow;
  Val.CreatedBy := UserId;
  Val.Item := Item;

  Item.Values.Add(Val);
  FManager.Update(Item);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetValue, Val.Id, aoCreate, UserId,
    'Added value to item "' + Item.Title + '"');
end;

procedure TItemModel.RemoveValue(Val: TValue; var Item: TItem; UserId: Integer);
var
  ValId: Integer;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  ValId := Val.Id;
  Item.Values.Remove(Val);
  FManager.Remove(Val);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetValue, ValId, aoDelete, UserId,
    'Removed value from item "' + Item.Title + '"');
end;

function TItemModel.RemoveFile(AFile: TFile; var Item: TItem; UserId: Integer): Boolean;
var
  FileId: Integer;
  FileTitle: string;
begin
  Result := False;
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  FileId := AFile.Id;
  FileTitle := AFile.Title;
  Item.Files.Remove(AFile);
  FManager.Remove(AFile);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetFile, FileId, aoDelete, UserId,
    'Removed file "' + FileTitle + '" from item "' + Item.Title + '"');
  if Assigned(Model) then
    Model.ViewerStates.DeleteForFile(FileId);
  Result := True;
end;

procedure TItemModel.RemoveEntry(Entry: TLabEntry; var Item: TItem; UserId: Integer);
var
  EntryId: Integer;
  EntryTitle: string;
  EntityType: TAuditEntityType;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  EntryId := Entry.Id;
  if Entry is TProtocol then
  begin
    EntryTitle := TProtocol(Entry).Title;
    if TProtocol(Entry).ProtocolType.HasValue and
       (TProtocol(Entry).ProtocolType.Value = ptNote) then
      EntityType := aetNote
    else
      EntityType := aetProtocol;
  end
  else
  begin
    EntryTitle := '';
    EntityType := aetProtocol;
  end;
  Item.Entries.Remove(Entry);
  FManager.Remove(Entry);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, EntityType, EntryId, aoDelete, UserId,
    'Removed entry "' + EntryTitle + '" from item "' + Item.Title + '"');
end;

function TItemModel.GetDataSet: TAureliusDataset;
begin
  if not Assigned(FDataSet) then
    OpenDataSet;

  Result := FDataSet;
end;

function TItemModel.GetItem(const ID: integer): TItem;
begin
  Result := FManager.Find<TItem>(ID);
end;

function TItemModel.GetItemForEntry(EntryId: Integer): TItem;
begin
  Result := FManager.Find<TItem>
    .CreateAlias('Entries', 'e')
    .Where(Linq['e.Id'] = EntryId)
    .UniqueResult;
end;

function TItemModel.GetItemsList: TItems;
begin
  Result := FManager.Find<TItem>
    .Where((FDic.ProjectID = FProjectID) and (FDic.FolderID = FFolderID)
      and (FDic.IsDeleted = False))
    .OrderBy('SortOrder')
    .OrderBy('Id')
    .List;
end;

function TItemModel.UpdateItem(Item: TItem; UserId: Integer): Boolean;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit(False);

  Item.ModifiedDate := UTCNow;
  Item.ModifiedBy := UserId;

  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetItem, Item.Id, aoUpdate, UserId,
      'Updated item "' + Item.Title + '"');
end;

procedure TItemModel.RelocateFilesForRename(Item: TItem; const OldTitle: string;
  const Relocator: IFileRelocator);
var
  Project: TProject;
  OldFolder, NewFolder, OldPath, NewPath: string;
  F: TFile;
  MovedOld, MovedNew: TStringList;
  i: Integer;
begin
  if (not Assigned(Item)) or (not Assigned(Relocator)) then Exit;
  if Item.Title = OldTitle then Exit;
  OldFolder := TItem.MakeFolderName(Item.Id, OldTitle);
  NewFolder := Item.FolderName;
  if OldFolder = NewFolder then Exit;
  if Item.Files.Count = 0 then Exit;

  Project := FManager.Find<TProject>(Item.ProjectID);
  if not Assigned(Project) then Exit;

  MovedOld := TStringList.Create;
  MovedNew := TStringList.Create;
  try
    for F in Item.Files do
    begin
      OldPath := BuildItemFileRemotePath(Project.FileFolder, OldFolder, F.FullName);
      NewPath := BuildItemFileRemotePath(Project.FileFolder, NewFolder, F.FullName);
      try
        Relocator.MoveFile(OldPath, NewPath);
      except
        on E: Exception do
        begin
          // Put back what was already moved so storage matches the title
          // the caller is about to restore. Failures here are swallowed:
          // the original error is the one worth reporting.
          for i := MovedOld.Count - 1 downto 0 do
            try
              Relocator.MoveFile(MovedNew[i], MovedOld[i]);
            except
            end;
          raise Exception.CreateFmt(
            'Could not move attachment "%s" to the renamed item folder: %s',
            [F.FullName, E.Message]);
        end;
      end;
      MovedOld.Add(OldPath);
      MovedNew.Add(NewPath);
    end;
  finally
    MovedNew.Free;
    MovedOld.Free;
  end;
end;

function TItemModel.UpdateEntry(Entry: TLabEntry; UserId: Integer): Boolean;
var
  ParentItem: TItem;
  EntityType: TAuditEntityType;
begin
  Result := False;

  ParentItem := GetItemForEntry(Entry.Id);
  if not Assigned(ParentItem) then
    Exit;
  if IsItemSignedCheck(FManager, ParentItem.Id) then
    Exit;

  Entry.ModifiedDate := UTCNow;
  Entry.ModifiedBy := UserId;
  FManager.Update(Entry);
  Result := TConflictHandler.SafeFlush(FManager);
  if not Result then
    Exit;

  if (Entry is TProtocol)
     and TProtocol(Entry).ProtocolType.HasValue
     and (TProtocol(Entry).ProtocolType.Value = ptNote) then
    EntityType := aetNote
  else
    EntityType := aetProtocol;

  RecordAudit(FManager, EntityType, Entry.Id, aoUpdate, UserId,
    'Updated entry "' + Entry.Title + '" on item "' + ParentItem.Title + '"');
end;

function TItemModel.UpdateFile(AFile: TFile; UserId: Integer): Boolean;
begin
  AFile.ModifiedDate := UTCNow;
  AFile.ModifiedBy := UserId;
  FManager.Update(AFile);
  Result := TConflictHandler.SafeFlush(FManager);
end;

function TItemModel.MoveFile(AFile: TFile; NewParentId, UserId: Integer): Boolean;
var
  OldParent, NewParent: TItem;
begin
  OldParent := AFile.Item;
  NewParent := FManager.Find<TItem>(NewParentId);
  if not Assigned(NewParent) then
    Exit(False);

  // Change FK directly — do NOT manipulate proxy collections
  // (CascadeAllRemoveOrphan on TItem.Files would delete the file as orphan)
  AFile.Item := NewParent;
  AFile.ModifiedDate := UTCNow;
  AFile.ModifiedBy := UserId;
  FManager.Update(AFile);
  Result := TConflictHandler.SafeFlush(FManager);

  if Result then
  begin
    RecordAudit(FManager, aetFile, AFile.Id, aoUpdate, UserId,
      'Moved file "' + AFile.Title + '" to "' + NewParent.Title + '"');
    // Evict stale entities so proxy collections reload from DB on next access
    FManager.Evict(AFile);
    FManager.Evict(OldParent);
    FManager.Evict(NewParent);
  end;
end;

function TItemModel.ReorderItems(Items: TItems): Boolean;
var
  I: Integer;
begin
  for I := 0 to Items.Count - 1 do
    Items[I].SortOrder := I * 10;
  Result := TConflictHandler.SafeFlush(FManager);
end;

procedure TItemModel.OpenDataSet;
begin
  FDataSet.SetSourceCriteria(FManager.Find<TItem>);
  FDataSet.Open;
end;

function TItemModel.IsItemEmpty(Item: TItem): Boolean;
var
  Children: TList<TItem>;
begin
  // Check for non-deleted child items
  Children := FManager.Find<TItem>
    .Where((FDic.ParentID = Item.Id) and (FDic.IsDeleted = False))
    .List;
  try
    if Children.Count > 0 then
      Exit(False);
  finally
    Children.Free;
  end;

  // Check entries, files, and values
  Result := (Item.Entries.Count = 0) and
            (Item.Files.Count = 0) and
            (Item.Values.Count = 0);
end;

procedure TItemModel.CollectLiveSubtree(Item: TItem; AList: TList<TItem>);
var
  Children: TList<TItem>;
  Child: TItem;
begin
  if AList.Contains(Item) then
    Exit;                       // circular parent-child guard
  AList.Add(Item);
  Children := FManager.Find<TItem>
    .Where((FDic.ParentID = Item.Id) and (FDic.IsDeleted = False))
    .List;
  try
    for Child in Children do
      CollectLiveSubtree(Child, AList);
  finally
    Children.Free;
  end;
end;

function TItemModel.FindDeleteBlocker(Item: TItem): string;
const
  StatusWord: array[Boolean] of string = ('accepted', 'in review');
var
  Subtree: TList<TItem>;
  I: TItem;
  HypId: Integer;
  HStatus: THypothesisStatus;
  Why: string;
begin
  Result := '';
  Subtree := TList<TItem>.Create;
  try
    CollectLiveSubtree(Item, Subtree);
    for I in Subtree do
    begin
      if IsItemSignedCheck(FManager, I.Id) then
        Why := 'is signed'
      else if IsItemCitedByLockedHypothesis(FManager, I.Id, HypId, HStatus) then
        Why := Format('is cited by hypothesis #%d (%s)',
          [HypId, StatusWord[HStatus = hsInReview]])
      else
        Continue;
      if I = Item then
        Exit(Format('Cannot delete item "%s": it %s.', [Item.Title, Why]))
      else
        Exit(Format('Cannot delete item "%s": "%s" inside it %s.',
          [Item.Title, I.Title, Why]));
    end;
  finally
    Subtree.Free;
  end;
end;

function TItemModel.DeleteItem(Item: TItem; UserId: Integer): Boolean;
begin
  if FindDeleteBlocker(Item) <> '' then
    Exit(False);

  Item.IsDeleted := True;
  Item.DeletedDate := UTCNow;
  Item.DeletedBy := UserId;
  FManager.Update(Item);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetItem, Item.Id, aoDelete, UserId,
      'Moved item "' + Item.Title + '" to recycle bin');
end;

function TItemModel.SoftDeleteItemTree(Item: TItem; UserId: Integer): Boolean;
var
  Subtree: TList<TItem>;
  I: TItem;
  Trans: IDBTransaction;
begin
  // Check the WHOLE live subtree first, then delete. The previous version
  // marked each child deleted before the recursive call checked whether that
  // child was signed, so a signed descendant was soft-deleted anyway.
  if FindDeleteBlocker(Item) <> '' then
    Exit(False);
  if Item.IsDeleted then
    Exit(True);

  Subtree := TList<TItem>.Create;
  try
    CollectLiveSubtree(Item, Subtree);
    // One transaction for the whole subtree: without it, a mid-batch version
    // conflict on one descendant (EVersionedConcurrencyControl) can commit the
    // UPDATEs that ran before it and leave the subtree partially soft-deleted,
    // exactly the "nothing is deleted" guarantee this method exists to give.
    Trans := FManager.Connection.BeginTransaction;
    try
      for I in Subtree do
      begin
        I.IsDeleted := True;
        I.DeletedDate := UTCNow;
        I.DeletedBy := UserId;
        FManager.Update(I);
      end;
      Result := TConflictHandler.SafeFlush(FManager);
      if Result then
        Trans.Commit
      else
      begin
        Trans.Rollback;
        for I in Subtree do
          FManager.Refresh(I);
      end;
    except
      Trans.Rollback;
      for I in Subtree do
        FManager.Refresh(I);
      raise;
    end;
  finally
    Subtree.Free;
  end;
  if Result then
    RecordAudit(FManager, aetItem, Item.Id, aoDelete, UserId,
      'Moved item "' + Item.Title + '" and descendants to recycle bin');
end;

function TItemModel.MoveProc(Proc: TItem; NewProjectID, NewFolderID, UserID: Integer;
  const Relocator: IFileRelocator): Boolean;
var
  AllItems: TItems;
  ToMove: TList<TItem>;
  Item: TItem;
  OldProjectID, OldFolderID: Integer;
  OldProject, NewProject: TProject;
  F: unit_Item.TFile;
  IsCrossProject: Boolean;
  OldPath, NewPath: string;

  procedure CollectDescendants(ParentID: Integer);
  var
    Child: TItem;
  begin
    for Child in AllItems do
      if Child.Parent = ParentID then
      begin
        ToMove.Add(Child);
        CollectDescendants(Child.Id);
      end;
  end;

begin
  if IsItemSignedCheck(FManager, Proc.Id) then
    Exit(False);

  OldProjectID := Proc.ProjectID;
  OldFolderID  := Proc.FolderID;
  IsCrossProject := OldProjectID <> NewProjectID;

  // Include soft-deleted (recycle-bin) descendants so they move with the
  // parent Proc; leaving them behind would strand them under a departed
  // parent. Their files stay at the old path (no relocation until restore).
  AllItems := FManager.Find<TItem>
    .Where((FDic.ProjectID = OldProjectID) and (FDic.FolderID = OldFolderID))
    .List;

  ToMove := TList<TItem>.Create;
  try
    ToMove.Add(Proc);
    CollectDescendants(Proc.Id);

    // Reject the move if ANY collected item (including soft-deleted
    // descendants) is signed, before any mutation — mirroring
    // TProjectsModel.MoveFolder, which rejects a folder move when any contained
    // item is signed. Without this, only the top Proc was checked and signed
    // descendants would be moved.
    for Item in ToMove do
      if IsItemSignedCheck(FManager, Item.Id) then
        Exit(False);

    // Commit the DB move FIRST. If the flush conflicts, nothing on WebDAV has
    // been touched, so DB and storage stay consistent (clean no-op). Only after
    // the DB is the authoritative source of truth do we relocate the files: a
    // file-move failure then leaves the file at its old path, reconcilable via
    // relocate_item_files, instead of the previous order's orphaned files
    // behind an uncommitted DB.
    for Item in ToMove do
    begin
      Item.ProjectID := NewProjectID;
      Item.FolderID  := NewFolderID;
      FManager.Update(Item);
    end;

    Result := TConflictHandler.SafeFlush(FManager);
    if not Result then
      Exit;

    RecordAudit(FManager, aetItem, Proc.Id, aoUpdate, UserID,
      Format('Moved Proc "%s" to project %d, folder %d',
        [Proc.Title, NewProjectID, NewFolderID]));

    if IsCrossProject and Assigned(Relocator) then
    begin
      OldProject := FManager.Find<TProject>(OldProjectID);
      NewProject := FManager.Find<TProject>(NewProjectID);
      for Item in ToMove do
      begin
        // Relocate files for soft-deleted descendants too: their ProjectID was
        // just switched to the new project, and RestoreItem does not relocate
        // files, so leaving the bytes at the old path would orphan the
        // attachment after a later restore.
        for F in Item.Files do
        begin
          OldPath := BuildItemFileRemotePath(
            OldProject.FileFolder, Item.FolderName, F.FullName);
          NewPath := BuildItemFileRemotePath(
            NewProject.FileFolder, Item.FolderName, F.FullName);
          Relocator.MoveFile(OldPath, NewPath);
        end;
      end;
    end;
  finally
    ToMove.Free;
    AllItems.Free; // criteria .List container (entities stay manager-owned)
  end;
end;

function TItemModel.GetRecentItems(UserId: Integer; Count: Integer): TItems;
begin
  Result := FManager.Find<TItem>
    .Where(FDic.IsDeleted = False)
    .Where(FDic.Level = Ord(TItemLevel.Proc))
    .Where(FDic.CreatedBy = UserId)
    .OrderBy(FDic.ModifiedDate, False)
    .Take(Count)
    .List;
end;

function TItemModel.GetRecentItems(UserId: Integer; DateFrom: TDateTime;
  Count: Integer): TItems;
var
  Criteria: TCriteria;
begin
  Criteria := FManager.Find<TItem>
    .Where(FDic.IsDeleted = False)
    .Where(FDic.Level = Ord(TItemLevel.Proc));

  if UserId > 0 then
    Criteria.Where(FDic.CreatedBy = UserId);

  if DateFrom > 0 then
    Criteria.Where(FDic.ModifiedDate >= DateFrom);

  Result := Criteria
    .OrderBy(FDic.ModifiedDate, False)
    .Take(Count)
    .List<TItem>;
end;

procedure TItemModel.EvictCache;
var
  Items: TItems;
  Item: TItem;
  Entry: TLabEntry;
  AFile: TFile;
  Val: TValue;
begin
  Items := GetItemsList;
  try
    for Item in Items do
    begin
      // Evict child entities loaded via Proxy<T>
      for Entry in Item.Entries do
        FManager.Evict(Entry);
      for AFile in Item.Files do
        FManager.Evict(AFile);
      for Val in Item.Values do
        FManager.Evict(Val);
      FManager.Evict(Item);
    end;
  finally
    Items.Free;
  end;
end;

end.
