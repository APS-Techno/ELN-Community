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
      { Private declarations }
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

      { The principal every query on this model is scoped to. }
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

{ TProjectsModel }

procedure TProjectsModel.AddFolder(const Title, Description: string;
  ProjectID, ParentFolderID: integer);
var
  Folder: TFolder;
  Project: TProject;
begin
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
  OldProject, NewProject: TProject;
  Items: TList<TItem>;
  AllItems: TList<TItem>;
  Item: TItem;
  F: unit_Item.TFile;
  IsCrossProject: Boolean;
  ItemDic: TItemDictionary;
  OldPath, NewPath: string;
  MovedItemCount: Integer;
  FileMoves: TList<TPair<string, string>>;
  Pair: TPair<string, string>;
  AllFolders: TFoldersList;
  SubtreeFolders: TList<TFolder>;
  SubFolder: TFolder;

  // Recursively collect the full subtree of child folders (by ParentFolderID)
  // rooted at ParentID, using the old project's already-loaded folder list.
  procedure CollectChildFolders(ParentID: Integer);
  var
    ChildF: TFolder;
  begin
    for ChildF in AllFolders do
      // The SubtreeFolders.Contains guard makes this robust against a
      // pre-existing folder cycle (e.g. a folder previously moved into its own
      // descendant): a folder already collected is never recursed into again,
      // so a cyclic graph can't drive unbounded recursion / stack overflow.
      if (ChildF.ParentFolderID = ParentID)
         and (not SubtreeFolders.Contains(ChildF)) then
      begin
        SubtreeFolders.Add(ChildF);
        CollectChildFolders(ChildF.Id);
      end;
  end;

begin
  IsCrossProject := OldProjectID <> NewProjectID;
  MovedItemCount := 0;
  SubtreeFolders := nil;
  NewProject := nil;  // assigned (and used) only on cross-project moves

  // Collected (oldPath -> newPath) WebDAV moves, replayed only AFTER the DB
  // move commits, so a file-move failure leaves the file reconcilable rather
  // than orphaning it behind an uncommitted DB.
  FileMoves := TList<TPair<string, string>>.Create;
  try

  if IsCrossProject then
  begin
    OldProject := FManager.Find<TProject>(OldProjectID);
    NewProject := FManager.Find<TProject>(NewProjectID);

    // Collect the FULL folder subtree (moved folder + every nested subfolder
    // via ParentFolderID recursion). On a cross-project move every folder in
    // the subtree must switch ProjectID and have its items reparented;
    // otherwise a nested subfolder keeps ProjectID=old while ParentFolderID
    // points into the new project and the whole subtree vanishes from both
    // trees.
    AllFolders := OldProject.Folders;
    SubtreeFolders := TList<TFolder>.Create;
    SubtreeFolders.Add(Folder);
    CollectChildFolders(Folder.Id);

    // Gather the contained items across the whole subtree. AllItems holds only
    // references (entities are owned by the manager); the per-folder query
    // lists are freed immediately.
    AllItems := TList<TItem>.Create;
    try
      ItemDic := TItemDictionary.Create;
      try
        for SubFolder in SubtreeFolders do
        begin
          Items := FManager.Find<TItem>
            .Where((ItemDic.FolderID = SubFolder.Id)
              and (ItemDic.ProjectID = OldProjectID)
              and (ItemDic.IsDeleted = False))
            .List;
          try
            for Item in Items do
              AllItems.Add(Item);
          finally
            Items.Free;
          end;
        end;
      finally
        ItemDic.Free;
      end;

      MovedItemCount := AllItems.Count;

      // Pre-flight over EVERY item in the subtree: reject before any mutation
      // if any item is signed.
      for Item in AllItems do
        if IsItemSignedCheck(FManager, Item.Id) then
          raise Exception.CreateFmt(
            'Cannot move folder: item "%s" (ID %d) is signed.',
            [Item.Title, Item.Id]);

      // Collect the file-move pairs while the items are still loaded. The paths
      // do not depend on the not-yet-committed ProjectID change.
      if Assigned(Relocator) then
        for Item in AllItems do
          for F in Item.Files do
          begin
            OldPath := BuildItemFileRemotePath(
              OldProject.FileFolder, Item.FolderName, F.FullName);
            NewPath := BuildItemFileRemotePath(
              NewProject.FileFolder, Item.FolderName, F.FullName);
            FileMoves.Add(TPair<string, string>.Create(OldPath, NewPath));
          end;

      // Reparent contained items to the new project.
      for Item in AllItems do
      begin
        Item.ProjectID := NewProjectID;
        FManager.Update(Item);
      end;
    finally
      AllItems.Free;
    end;
  end;

  // Folder reparent. Only the moved folder's ParentFolderID changes; nested
  // subfolders keep their ParentFolderID (folder Ids are stable across a move).
  Folder.ParentFolderID := NewParentFolderID;
  if not IsCrossProject then
    FManager.Update(Folder)
  else
  begin
    // Do NOT call OldProject.Folders.Remove — Aurelius writes ProjectID=NULL
    // immediately, violating the NOT NULL constraint before Add can fix it.
    // Adding to the new project's collection is sufficient; Aurelius cascade
    // on Update(NewProject) writes the correct FK value. Add EVERY folder in
    // the subtree so each subfolder's ProjectID switches too.
    for SubFolder in SubtreeFolders do
      NewProject.Folders.Add(SubFolder);
    FManager.Update(NewProject);
  end;

  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
  begin
    if IsCrossProject then
      RecordAudit(FManager, aetFolder, Folder.Id, aoUpdate, UserId,
        Format('Moved folder "%s" (%d items) from project %d to project %d',
          [Folder.Title, MovedItemCount, OldProjectID, NewProjectID]))
    else
      RecordAudit(FManager, aetFolder, Folder.Id, aoUpdate, UserId,
        'Moved folder "' + Folder.Title + '"');

    // DB committed and authoritative — now relocate the files on WebDAV.
    for Pair in FileMoves do
      Relocator.MoveFile(Pair.Key, Pair.Value);
  end;

  finally
    SubtreeFolders.Free;
    FileMoves.Free;
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
    // every later Flush on this shared manager (review M-1).
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

  // Check for folders
  if Project.Folders.Count > 0 then
    Exit(False);

  // Check for items (exclude soft-deleted)
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
  // Evict all folders from the identity map so next query fetches fresh data
  Folders := FManager.Find<TFolder>.List;
  try
    for Folder in Folders do
      FManager.Evict(Folder);
  finally
    Folders.Free;
  end;

  // Evict all projects
  Projects := FManager.Find<TProject>.List;
  try
    for Project in Projects do
      FManager.Evict(Project);
  finally
    Projects.Free;
  end;
end;

end.
