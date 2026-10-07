unit unit_FolderModel;

interface
uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  System.Generics.Collections,
  unit_Types,
  unit_Project,
  unit_Item,
  unit_TELNModel,
  unit_ELNDB_Dictionary,
  unit_AuditLog;

type
  TFolderModel = class(TELNModel)
    private
      FDic: TFolderDictionary;
      FFolder : TFolder;
      FManager: TObjectManager;

      function GetFolderID: integer;
      function GetDisplayName: string;
      function GetParentID: integer;
      procedure SetParentID(const Value: integer);
      function GetFoldersList: TFoldersList;
    public
      constructor Create(Manager: TObjectManager);

      destructor Destroy; override;
      property FolderID: integer read GetFolderID;
      property ParentID: integer read GetParentID write SetParentID;

      property Name:string read GetDisplayName;
      procedure OpenDataSet; override;
      property List: TFoldersList read GetFoldersList;
      procedure SetExpanded(const FolderID: integer; State: boolean);
      function ProjectID(const FolderID: integer): integer;
      function Update(const Folder: TFolder; UserId: Integer): Boolean;
      function IsFolderEmpty(FolderID: Integer): Boolean;
      function FolderHasRecycleBinItems(FolderID: Integer): Boolean;
      function DeleteFolder(FolderID, ProjectID: Integer; UserId: Integer): Boolean;
      procedure ReorderFolders(const OrderedIds: TArray<Integer>);
   end;

implementation

uses
  unit_AuditHelper,
  unit_ConflictHandler,
  Aurelius.Commands.Exceptions,
  unit_TimeHelper;

{ TFolderModel }

//procedure TFolderModel.AddFolder;
//var
//  Folder: TFolder;
//begin
//  Folder := TFolder.Create;
//  Folder.Name := Name;
//  Folder.Description := Description;
//  Folder.ParentFolderID := 0;
//  FFolder.Project := Project;
//  FManager.Save(Folder);
//end;

constructor TFolderModel.Create;
begin
  inherited Create;
  FDic := TFolderDictionary.Create;
  FManager := Manager;
end;

destructor TFolderModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TFolderModel.GetDisplayName: string;
begin
  if Assigned(FFolder) then
     Result := FFolder.Title
   else
     Result := 'Noname';
end;

function TFolderModel.GetFolderID: integer;
begin
  if Assigned(FFolder) then
    Result := FFolder.Id
  else
    Result := -1;
end;

function TFolderModel.GetFoldersList: TFoldersList;
begin
  Result := FManager.Find<TFolder>
    .OrderBy('ParentFolderID')
    .List;
end;

function TFolderModel.GetParentID: integer;
begin
  if Assigned(FFolder) then
    Result := FFolder.ParentFolderID
  else
    Result := -1;
end;

procedure TFolderModel.OpenDataSet;
begin
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
//  FDataSet.SetSourceCriteria(FManager.Find<TFolder>);
//  FDataSet.Open;
end;

function TFolderModel.ProjectID(const FolderID: integer): integer;
begin
  FDataSet.SetSourceCriteria(FManager.Find<TFolder>.
      Where(FDic.ID = FolderID));
  FDataSet.Open;
  Result := FDataSet.FieldByName('ProjectId').AsInteger;
  FDataSet.Close;
end;

procedure TFolderModel.SetExpanded(const FolderID: integer; State: boolean);
var
  Folder: TFolder;
begin
  Folder := FManager.Find<TFolder>(FolderID);
  Folder.Expanded := State;
  try
    FManager.Flush;
  except
    // UI state: ignore the conflict, but reload the entity that conflicted
    // (this one, or a stale one from elsewhere). Left dirty it would fail
    // every later Flush on this shared manager (review M-1).
    on E: EVersionedConcurrencyControl do
      TConflictHandler.ReloadConflicted(FManager, E);
  end;
end;

procedure TFolderModel.SetParentID(const Value: integer);
begin
  if Assigned(FFolder) then
    FFolder.ParentFolderID := Value;
end;

function TFolderModel.Update(const Folder: TFolder; UserId: Integer): Boolean;
begin
  Folder.ModifiedDate := UTCNow;
  Folder.ModifiedBy := UserId;
  FManager.Update(Folder);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetFolder, Folder.Id, aoUpdate, UserId,
      'Updated folder "' + Folder.Title + '"');
end;

function TFolderModel.IsFolderEmpty(FolderID: Integer): Boolean;
var
  ChildFolders: TFoldersList;
  Items: TList<TItem>;
  ItemDic: TItemDictionary;
begin
  ChildFolders := FManager.Find<TFolder>
    .Where(FDic.ParentFolderID = FolderID)
    .List;
  try
    if ChildFolders.Count > 0 then
      Exit(False);
  finally
    ChildFolders.Free;
  end;

  ItemDic := TItemDictionary.Create;
  try
    Items := FManager.Find<TItem>
      .Where((ItemDic.FolderID = FolderID) and (ItemDic.IsDeleted = False))
      .List;
    try
      Result := Items.Count = 0;
    finally
      Items.Free;
    end;
  finally
    ItemDic.Free;
  end;
end;

function TFolderModel.FolderHasRecycleBinItems(FolderID: Integer): Boolean;
var
  Items: TList<TItem>;
  ItemDic: TItemDictionary;
begin
  // Soft-deleted (recycle-bin) items still reference this folder by integer
  // FolderID with no FK cascade. Hard-deleting the folder would orphan them,
  // so a folder holding recycle-bin items must not be treated as deletable.
  ItemDic := TItemDictionary.Create;
  try
    Items := FManager.Find<TItem>
      .Where((ItemDic.FolderID = FolderID) and (ItemDic.IsDeleted = True))
      .List;
    try
      Result := Items.Count > 0;
    finally
      Items.Free;
    end;
  finally
    ItemDic.Free;
  end;
end;

function TFolderModel.DeleteFolder(FolderID, ProjectID: Integer; UserId: Integer): Boolean;
var
  Folder: TFolder;
  Project: TProject;
  FolderTitle: string;
begin
  Folder := FManager.Find<TFolder>(FolderID);
  if not Assigned(Folder) then Exit(False);

  FolderTitle := Folder.Title;

  // Folder is owned by Project.Folders collection (cascaded association).
  // Remove from parent collection first, then flush to delete.
  Project := FManager.Find<TProject>(ProjectID);
  if Assigned(Project) then
    Project.Folders.Remove(Folder);

  FManager.Remove(Folder);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetFolder, FolderID, aoDelete, UserId,
      'Deleted folder "' + FolderTitle + '"');
end;

procedure TFolderModel.ReorderFolders(const OrderedIds: TArray<Integer>);
var
  I: Integer;
  Folder: TFolder;
begin
  for I := 0 to High(OrderedIds) do
  begin
    Folder := FManager.Find<TFolder>(OrderedIds[I]);
    if Assigned(Folder) then
    begin
      Folder.SortOrder := I + 1;
      FManager.Flush;
    end;
  end;
end;

end.
