unit unit_ProjectModel;

interface

uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  System.Generics.Collections,
  unit_User,
  unit_FileRelocator,
  unit_NotebookStorage,
  unit_Project,
  unit_ProjectAccessPolicy,
  unit_Types,
  unit_TELNModel,
  unit_ELNDB_Dictionary,
  unit_AuditLog;

type
  TProjectList = TList<TProject>;

  TProjectStats = record
    Project: TProject;
    ItemCount: Integer;
    FileCount: Integer;
  end;
  TProjectStatsList = TList<TProjectStats>;

  TProjectsModel = class(TELNModel)
    private
      FUser: TUser;
      FUserID: Integer;

      FManager: TObjectManager;
      FAccess: IProjectAccessPolicy;
    protected
      function GetDataSet: TAureliusDataset; override;
      function GetProjectList: TProjectList;
    public
      constructor Create(Manager: TObjectManager; const Access: IProjectAccessPolicy);
      procedure AssignUser(AUser: TUser);
      property DataSet:TAureliusDataset read GetDataSet;
      procedure OpenDataSet; override;
      property List: TProjectList read GetProjectList;

      property AssignedUserID: Integer read FUserID;
      property Manager: TObjectManager read FManager;
      property Access: IProjectAccessPolicy read FAccess;

      function GetProjectAccess(ProjectID: Integer): TProjectAccess;
      procedure SetExpanded(const ProjectID: integer; State: boolean);
      function AddProject(const Title, Description: string; Owner: TUser): TProject;
      function GetProject(const ID: integer): TProject;
      procedure AddFolder(const Title, Description: string; ProjectID, ParentFolderID: integer);
      function MoveFolder(Folder: TFolder; OldProjectID, NewProjectID, NewParentFolderID: integer;
        UserId: Integer; const Relocator: IFileRelocator = nil): Boolean;
      function Update(const Project: TProject): Boolean;
      function GetProjectStats(UserId: Integer = -1; DateFrom: TDateTime = 0): TProjectStatsList;
      procedure ReorderProjects(const OrderedIds: TArray<Integer>);
      function IsProjectEmpty(ProjectID: Integer): Boolean;
      function ProjectHasRecycleBinItems(ProjectID: Integer): Boolean;
      function DeleteProject(ProjectID: Integer; UserId: Integer): Boolean;
      procedure EvictCache;
  end;

implementation

uses
  System.Classes,
  unit_AuditHelper,
  unit_ConflictHandler,
  unit_Item,
  unit_ItemTypes,
  unit_SignatureModel,
  unit_Hypothesis,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Commands.Exceptions,
  unit_TimeHelper;


procedure TProjectsModel.AddFolder(const Title, Description: string;
  ProjectID, ParentFolderID: integer);
var
  Folder: TFolder;
  Project: TProject;
begin
  if ParentFolderID < 0 then
    ParentFolderID := 0;
  Project := FManager.Find<TProject>(ProjectID);

  Folder := TFolder.Create;
  Folder.Title := Title;
  Folder.Description := Description;
  Folder.ParentFolderID := ParentFolderID;
  Folder.CreatedDate := UTCNow;
  Folder.CreatedBy := Project.Owner.Id;
  Folder.Expanded := True;

  Project.Folders.Add(Folder);
  FManager.SaveOrUpdate(Project);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetFolder, Folder.Id, aoCreate, Project.Owner.Id,
    'Created folder "' + Title + '" in project "' + Project.Title + '"');
end;

function TProjectsModel.AddProject(const Title, Description: string;
  Owner: TUser): TProject;
var
  Project: TProject;
begin
  Project := TProject.Create;

  Project.Title := Title;
  Project.Owner := Owner;
  Project.Description := Description;
  Project.CreatedDate := UTCNow;
  Project.CreatedBy := Owner.ID;
  Project.Expanded := True;
  Project.IsArchived := False;
  FManager.Save(Project);

  Project.FileFolder := Format('[%.*d]%s',[5, Project.Id, Project.Title]);
  FManager.Flush(Project);
  RecordAudit(FManager, aetProject, Project.Id, aoCreate, Owner.Id,
    'Created project "' + Title + '"');

  // Return the saved entity. Callers must never re-query the list to find it:
  // the list is scoped to whichever user was last assigned (which need not be
  // Owner) and is ordered by SortOrder, so neither "last element" nor "any
  // element" is reliably the project just created.
  Result := Project;
end;

procedure TProjectsModel.AssignUser(AUser: TUser);
begin
  FUser := AUser;
  if AUser = nil then
    FUserID := 0
  else
    FUserID := AUser.Id;
end;

constructor TProjectsModel.Create(Manager: TObjectManager;
  const Access: IProjectAccessPolicy);
begin
  inherited Create;
  if Access = nil then
    raise EArgumentNilException.Create('Access');
  FManager := Manager;
  FAccess := Access;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
end;

function TProjectsModel.GetProjectAccess(ProjectID: Integer): TProjectAccess;
begin
  Result := FAccess.GetProjectAccess(FManager, FUser, ProjectID);
end;

function TProjectsModel.GetDataSet: TAureliusDataset;
begin
  if not Assigned(FDataSet) then
    OpenDataSet;

  Result := FDataSet;
end;

function TProjectsModel.GetProject(const ID: integer): TProject;
begin
  Result := FManager.Find<TProject>(ID);
end;

function TProjectsModel.GetProjectList: TProjectList;
begin
  Result := FAccess.ProjectList(FManager, FUser);
end;

procedure TProjectsModel.OpenDataSet;
begin
  FDataSet.Close;
  FDataSet.SetSourceCriteria(FAccess.ProjectDataSetCriteria(FManager, FUser));
  FDataSet.Open;
end;

function TProjectsModel.MoveFolder(Folder: TFolder; OldProjectID, NewProjectID,
  NewParentFolderID: integer; UserId: Integer;
  const Relocator: IFileRelocator): Boolean;
var
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  OldProject, NewProject, CachedProject: TProject;
  Current, SubFolder, CachedFolder: TFolder;
  AllItems, Items: TList<TItem>;
  Item, CachedItem: TItem;
  Attachment: unit_Item.TFile;
  SubtreeFolders: TList<TFolder>;
  Moves: TFileMoveJournal;
  Committed, Stale, RefreshProjects: Boolean;

  procedure CollectChildFolders(ParentID: Integer);
  var
    Child: TFolder;
  begin
    for Child in OldProject.Folders do
      if (Child.ParentFolderID = ParentID) and not SubtreeFolders.Contains(Child) then
      begin
        SubtreeFolders.Add(Child);
        CollectChildFolders(Child.Id);
      end;
  end;

  procedure CheckProjectCache(Project: TProject);
  var
    Cached: TProject;
    Child: TFolder;
  begin
    Cached := FManager.FindCached<TProject>(Project.Id);
    if Cached = nil then
      Exit;
    if FManager.HasChanges(Cached) then
      raise EInvalidOperation.Create('Save or cancel project edits before moving a folder.');
    for Child in Cached.Folders do
      if FManager.HasChanges(Child) then
        raise EInvalidOperation.Create('Save or cancel folder edits before moving a folder.');
    Stale := Stale or (Cached.Version <> Project.Version);
  end;

begin
  Result := False;
  if Folder = nil then
    Exit;
  if NewParentFolderID < 0 then
    NewParentFolderID := 0;
  Operation := TObjectManager.Create(FManager.Connection);
  AllItems := TList<TItem>.Create;
  SubtreeFolders := TList<TFolder>.Create;
  Moves := TFileMoveJournal.Create(Relocator);
  RefreshProjects := False;
  try
    Transaction := TConflictHandler.BeginOperationTransaction(FManager);
    Committed := False;
    try
      try
        OldProject := Operation.Find<TProject>(OldProjectID);
        NewProject := Operation.Find<TProject>(NewProjectID);
        if (OldProject = nil) or (NewProject = nil) then
          raise EInvalidOperation.Create('The source or destination project no longer exists.');
        Current := OldProject.GetFolder(Folder.Id);
        if Current = nil then
          Exit(False);
        SubtreeFolders.Add(Current);
        CollectChildFolders(Current.Id);
        if (NewParentFolderID <> 0) and (NewProject.GetFolder(NewParentFolderID) = nil) then
          raise EInvalidOperation.Create('The destination folder is not in the destination project.');
        if OldProjectID = NewProjectID then
          for SubFolder in SubtreeFolders do
            if SubFolder.Id = NewParentFolderID then
              raise EInvalidOperation.Create('A folder cannot be moved into its own subtree.');
        Stale := Current.Version <> Folder.Version;
        CheckProjectCache(OldProject);
        CheckProjectCache(NewProject);
        RefreshProjects := True;
        for SubFolder in SubtreeFolders do
        begin
          CachedFolder := FManager.FindCached<TFolder>(SubFolder.Id);
          if Assigned(CachedFolder) then
            Stale := Stale or (CachedFolder.Version <> SubFolder.Version);
          Items := Operation.Find<TItem>
            .Where((Linq['FolderID'] = SubFolder.Id) and
              (Linq['ProjectID'] = OldProjectID)).List;
          try
            AllItems.AddRange(Items);
          finally
            Items.Free;
          end;
        end;
        for Item in AllItems do
        begin
          CachedItem := FManager.FindCached<TItem>(Item.Id);
          if Assigned(CachedItem) then
          begin
            if FManager.HasChanges(CachedItem) then
              raise EInvalidOperation.Create('Save or cancel item edits before moving a folder.');
            Stale := Stale or (CachedItem.Version <> Item.Version);
          end;
          if IsItemSignedCheck(Operation, Item.Id) then
            Exit(False);
        end;
        if Stale then
          Exit(False);
        if OldProjectID <> NewProjectID then
        begin
          for Item in AllItems do
          begin
            for Attachment in Item.Files do
              Moves.Add(BuildItemFileRemotePath(OldProject.FileFolder, Item.FolderName, Attachment.FullName),
                BuildItemFileRemotePath(NewProject.FileFolder, Item.FolderName, Attachment.FullName));
            Item.ProjectID := NewProjectID;
          end;
          // Removing from OldProject first would write a forbidden NULL FK.
          // The operation manager is discarded after the transaction.
          for SubFolder in SubtreeFolders do
            NewProject.Folders.Add(SubFolder);
        end;
        Current.ParentFolderID := NewParentFolderID;
        Moves.Execute;
        Operation.Flush;
        RecordAudit(Operation, aetFolder, Current.Id, aoUpdate, UserId,
          Format('Moved folder "%s" (%d items) from project %d to project %d',
            [Current.Title, AllItems.Count, OldProjectID, NewProjectID]));
        Transaction.Commit;
        Committed := True;
        Result := True;
      finally
        if not Committed then
        begin
          try
            Transaction.Rollback;
          finally
            Moves.Rollback;
          end;
        end;
      end;
    except
      on E: EVersionedConcurrencyControl do
      begin
        if Assigned(TConflictHandler.OnConflict) then
          TConflictHandler.OnConflict(E.Message);
        Result := False;
      end;
    end;
  finally
    try
      for Item in AllItems do
      begin
        CachedItem := FManager.FindCached<TItem>(Item.Id);
        if Assigned(CachedItem) and not FManager.HasChanges(CachedItem) then
          FManager.Refresh(CachedItem);
      end;
      if RefreshProjects then
      begin
        CachedProject := FManager.FindCached<TProject>(OldProjectID);
        if Assigned(CachedProject) then
          FManager.Refresh(CachedProject);
        if OldProjectID <> NewProjectID then
        begin
          CachedProject := FManager.FindCached<TProject>(NewProjectID);
          if Assigned(CachedProject) then
            FManager.Refresh(CachedProject);
        end;
      end;
    finally
      Moves.Free;
      SubtreeFolders.Free;
      AllItems.Free;
      TConflictHandler.FreeOperationManager(Operation);
    end;
  end;
end;

procedure TProjectsModel.SetExpanded(const ProjectID: integer; State: boolean);
var
  Project: TProject;
begin
  Project := FManager.Find<TProject>(ProjectID);
  Project.Expanded := State;
  try
    FManager.Flush;
  except
    // UI state: ignore the conflict, but reload the entity that conflicted
    // (this one, or a stale one from elsewhere). Left dirty it would fail
    // every later Flush on this shared manager.
    on E: EVersionedConcurrencyControl do
      TConflictHandler.ReloadConflicted(FManager, E);
  end;
end;

function TProjectsModel.Update(const Project: TProject): Boolean;
begin
  Project.ModifiedDate := UTCNow;
  Project.ModifiedBy   := Project.Owner.Id;
  FManager.Update(Project);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetProject, Project.Id, aoUpdate, Project.Owner.Id,
      'Updated project "' + Project.Title + '"');
end;

function TProjectsModel.GetProjectStats(UserId: Integer; DateFrom: TDateTime): TProjectStatsList;
var
  Projects: TProjectList;
  P: TProject;
  Stats: TProjectStats;
  ItemDic: TItemDictionary;
  Items: TList<TItem>;
  Criteria: TCriteria;
begin
  Result := TProjectStatsList.Create;
  ItemDic := TItemDictionary.Create;
  try
    Projects := List;
    for P in Projects do
    begin
      Stats.Project := P;

      Criteria := FManager.Find<TItem>
        .Where((ItemDic.ProjectID = P.Id) and (ItemDic.IsDeleted = False)
          and (ItemDic.Level = Ord(TItemLevel.Proc)));
      if UserId > 0 then
        Criteria.Where(ItemDic.CreatedBy = UserId);
      if DateFrom > 0 then
        Criteria.Where(ItemDic.ModifiedDate >= DateFrom);
      Items := Criteria.List<TItem>;
      Stats.ItemCount := Items.Count;
      Items.Free;

      Criteria := FManager.Find<TItem>
        .Where((ItemDic.ProjectID = P.Id) and (ItemDic.IsDeleted = False)
          and (ItemDic.Level <> Ord(TItemLevel.Proc)));
      if UserId > 0 then
        Criteria.Where(ItemDic.CreatedBy = UserId);
      if DateFrom > 0 then
        Criteria.Where(ItemDic.ModifiedDate >= DateFrom);
      Items := Criteria.List<TItem>;
      Stats.FileCount := Items.Count;
      Items.Free;

      Result.Add(Stats);
    end;
  finally
    ItemDic.Free;
  end;
end;

procedure TProjectsModel.ReorderProjects(const OrderedIds: TArray<Integer>);
var
  I: Integer;
  Project: TProject;
begin
  for I := 0 to High(OrderedIds) do
  begin
    Project := FManager.Find<TProject>(OrderedIds[I]);
    if Assigned(Project) then
    begin
      Project.SortOrder := I + 1;
      FManager.Flush;
    end;
  end;
end;

function TProjectsModel.IsProjectEmpty(ProjectID: Integer): Boolean;
var
  Project: TProject;
  Items: TList<TItem>;
  ItemDic: TItemDictionary;
  Hyps: TList<THypothesis>;
begin
  Project := FManager.Find<TProject>(ProjectID);
  if not Assigned(Project) then Exit(True);

  if Project.Folders.Count > 0 then
    Exit(False);

  ItemDic := TItemDictionary.Create;
  try
    Items := FManager.Find<TItem>
      .Where((ItemDic.ProjectID = ProjectID) and (ItemDic.IsDeleted = False))
      .List;
    try
      Result := Items.Count = 0;
    finally
      Items.Free;
    end;
  finally
    ItemDic.Free;
  end;
  if not Result then
    Exit;

  // Experiment tree: hypotheses hold a plain-integer ProjectId (no FK, no
  // cascade), so deleting the project would orphan them and their seals.
  Hyps := FManager.Find<THypothesis>
    .Where(Linq['ProjectId'] = ProjectID)
    .Take(1)
    .List;
  try
    Result := Hyps.Count = 0;
  finally
    Hyps.Free;
  end;
end;

function TProjectsModel.ProjectHasRecycleBinItems(ProjectID: Integer): Boolean;
var
  Items: TList<TItem>;
  ItemDic: TItemDictionary;
begin
  // Soft-deleted (recycle-bin) items still reference this project by integer
  // ProjectID with no FK cascade. Hard-deleting the project would orphan them,
  // so a project holding recycle-bin items must not be treated as deletable.
  ItemDic := TItemDictionary.Create;
  try
    Items := FManager.Find<TItem>
      .Where((ItemDic.ProjectID = ProjectID) and (ItemDic.IsDeleted = True))
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

function TProjectsModel.DeleteProject(ProjectID: Integer; UserId: Integer): Boolean;
var
  Project: TProject;
  ProjectTitle: string;
begin
  Project := FManager.Find<TProject>(ProjectID);
  if not Assigned(Project) then Exit(False);

  ProjectTitle := Project.Title;

  if not FAccess.RemoveProject(FManager, FUser, Project) then
    Exit(False);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetProject, ProjectID, aoDelete, UserId,
      'Deleted project "' + ProjectTitle + '"');
end;

procedure TProjectsModel.EvictCache;
var
  Projects: TList<TProject>;
  Project: TProject;
  Folders: TList<TFolder>;
  Folder: TFolder;
begin
  Folders := FManager.Find<TFolder>.List;
  try
    for Folder in Folders do
      FManager.Evict(Folder);
  finally
    Folders.Free;
  end;

  Projects := FManager.Find<TProject>.List;
  try
    for Project in Projects do
      FManager.Evict(Project);
  finally
    Projects.Free;
  end;
end;

end.
