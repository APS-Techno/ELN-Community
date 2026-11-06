unit unit_ProjectTreeVM;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  unit_FileRelocator,
  unit_NotebookStorage,
  unit_ProjectModel, unit_FolderModel, unit_FavoritesModel,
  unit_AuthorModel, unit_UserHistoryModel, unit_ItemModel,
  unit_ProjectGroupModel, unit_ProjectGroup,
  unit_Project, unit_User, unit_Favorite, unit_Types, unit_Item,
  unit_HypothesisQueries, unit_TreeStateModel, unit_ProjectAccessPolicy;

type
  TDeleteCheck = (dcOK, dcNotEmpty, dcHasRecycleBinItems);

  TOwnerTree = class
  private
    FUsers: TList<TUser>;
    FProjects: TObjectDictionary<Integer, TList<TProject>>;
    FGroups: TObjectDictionary<Integer, TProjectGroupList>;
  public
    constructor Create(AUsers: TList<TUser>;
      AProjects: TObjectDictionary<Integer, TList<TProject>>;
      AGroups: TObjectDictionary<Integer, TProjectGroupList>);
    destructor Destroy; override;
    property Users: TList<TUser> read FUsers;
    property Projects: TObjectDictionary<Integer, TList<TProject>> read FProjects;
    property Groups: TObjectDictionary<Integer, TProjectGroupList> read FGroups;
  end;

  TProjectTreeVM = class
  private
    FProjectsModel: TProjectsModel;
    FFolderModel: TFolderModel;
    FFavoritesModel: TFavoritesModel;
    FUsersModel: TAuthorModel;
    FHistoryModel: TUserHistoryModel;
    FItemModel: TItemModel;
    FGroupsModel: TProjectGroupModel;
    FTreeState: TTreeStateModel;
    FShowArchived: Boolean;
    FFilterText: string;
    FOnChanged: TNotifyEvent;
    FHypBadges: TDictionary<Integer, THypProjectBadge>;
    FFolderLookup: TObjectDictionary<Integer, TFoldersList>;
    FNoFolders: TFoldersList;
    procedure DoChanged;
    procedure DropFolderLookup;
    procedure FillFolderLookup(const AProjectIds: TArray<Integer>);
    function OwnsHypothesisProject(AUserId: Integer): Boolean;
    function PassesFilterText(Project: TProject): Boolean;
    function ArchiveListed(Project: TProject): Boolean;
    function OwnerProjectListed(Project: TProject): Boolean;
    function OwnerProjectSource(const AOwnerIds: TArray<Integer>): TList<TProject>;
  public
    constructor Create(
      AProjectsModel: TProjectsModel;
      AFolderModel: TFolderModel;
      AFavoritesModel: TFavoritesModel;
      AUsersModel: TAuthorModel;
      AHistoryModel: TUserHistoryModel;
      AItemModel: TItemModel;
      AGroupsModel: TProjectGroupModel);
    destructor Destroy; override;

    property ShowArchived: Boolean read FShowArchived write FShowArchived;
    property FilterText: string read FFilterText write FFilterText;
    function IsSupervisorMode: Boolean;
    function IsReadOnly: Boolean;
    function UserId: Integer;

    function GetUsers: TList<TUser>;
    /// The users that get their own node. Empty when the tree lists the
    /// viewer's projects directly (not a supervisor, or only one user).
    function OwnerNodes: TList<TUser>;
    /// Nil when OwnerNodes is empty.
    function LoadOwnerTree: TOwnerTree;
    function GetProjects(AUserId: Integer): TList<TProject>;
    function GetProjectsByOwner(
      const AOwnerIds: TArray<Integer>): TObjectDictionary<Integer, TList<TProject>>;
    function GetGroupsByOwner(
      const AOwnerIds: TArray<Integer>): TObjectDictionary<Integer, TProjectGroupList>;
    function GetSortedFolders(Project: TProject): TList<TFolder>;
    function FoldersOf(Project: TProject): TFoldersList;
    function GetFavorites: TList<TFavorite>;
    function ProjectMatchesFilter(Project: TProject): Boolean;
    function ShownProjectIds: TArray<Integer>;

    // Hypothesis badges ("HYP n" on project nodes). RefreshHypothesisBadges
    // re-reads them for the current user; call it before filling the tree.
    // Until the first refresh every count is 0.
    procedure RefreshHypothesisBadges;
    function HypothesisCount(ProjectId: Integer): Integer;
    function HypothesisWaiting(ProjectId: Integer): Integer;

    function GetProjectAccess(ProjectId: Integer): TProjectAccess;
    function GetProject(ProjectId: Integer): TProject;
    function CanDeleteProject(ProjectId: Integer): TDeleteCheck;
    function CanDeleteFolder(FolderId: Integer): TDeleteCheck;
    function CanEditProject(ProjectId: Integer): Boolean;
    function CanAddFolder(ProjectId: Integer): Boolean;

    function AddProject(const Title, Comment: string; Owner: TUser): TProject;
    procedure AddFolder(const Title, Comment: string; ProjectId, ParentFolderId: Integer);
    procedure UpdateProject(Project: TProject; const Title, Comment: string; IsArchived: Boolean);
    procedure UpdateFolder(Folder: TFolder; const Title, Comment: string);
    procedure DeleteProject(ProjectId: Integer);
    procedure DeleteFolder(FolderId, ProjectId: Integer);
    procedure ToggleArchive(Project: TProject);

    procedure MoveFolder(Folder: TFolder; SrcProjectId, DstProjectId, DstParentFolderId: Integer;
      const Relocator: IFileRelocator = nil);
    function MoveProc(Proc: TItem; NewProjectId, NewFolderId: Integer;
      const Relocator: IFileRelocator = nil): Boolean;
    procedure ReparentFolderUp(Folder: TFolder);
    procedure ReorderProjects(const OrderedIds: TArray<Integer>);
    procedure ReorderFolders(const OrderedIds: TArray<Integer>);

    procedure ToggleFavorite(FavType: TFavoriteType; ProjectId, FolderId: Integer; const Title: string);
    procedure RemoveFavorite(FavId: Integer);
    function IsFavorite(FavType: TFavoriteType; ProjectId, FolderId: Integer): Boolean;

    procedure SelectNode(ProjectId, FolderId: Integer);
    // Expanded state, per user (unit_TreeStateModel). Until the user's state
    // has been seeded from the old shared columns, Shared decides; after that
    // the user's own row, and collapsed when there is none. Without a
    // TreeState (tests of other features) Shared decides and nothing is saved.
    property TreeState: TTreeStateModel read FTreeState write FTreeState;
    function IsNodeExpanded(Kind: TTreeNodeKind; NodeId: Integer; Shared: Boolean): Boolean;
    procedure SetNodeExpanded(Kind: TTreeNodeKind; NodeId: Integer; Value: Boolean);
    function TreeStateSeeded: Boolean;
    procedure MarkTreeStateSeeded;
    function LastProjectId: Integer;
    function LastFolderId: Integer;
    function CurrentUser: TUser;

    procedure EvictCache;

    function GetGroups(AUserId: Integer): TProjectGroupList;
    function AddGroup(const Title: string; OwnerId: Integer): TProjectGroup;
    function RenameGroup(Group: TProjectGroup; const Title: string): Boolean;
    function DeleteGroup(GroupId: Integer): Boolean;
    procedure ReorderGroups(const OrderedIds: TArray<Integer>);
    function MoveProjectToGroup(ProjectId, GroupId: Integer): Boolean;

    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.StrUtils, System.Generics.Defaults, System.Variants,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq, Aurelius.Criteria.Projections,
  unit_HypothesisModel;

constructor TOwnerTree.Create(AUsers: TList<TUser>;
  AProjects: TObjectDictionary<Integer, TList<TProject>>;
  AGroups: TObjectDictionary<Integer, TProjectGroupList>);
begin
  inherited Create;
  FUsers := AUsers;
  FProjects := AProjects;
  FGroups := AGroups;
end;

destructor TOwnerTree.Destroy;
begin
  FGroups.Free;
  FProjects.Free;
  FUsers.Free;
  inherited;
end;

constructor TProjectTreeVM.Create(
  AProjectsModel: TProjectsModel;
  AFolderModel: TFolderModel;
  AFavoritesModel: TFavoritesModel;
  AUsersModel: TAuthorModel;
  AHistoryModel: TUserHistoryModel;
  AItemModel: TItemModel;
  AGroupsModel: TProjectGroupModel);
begin
  inherited Create;
  FProjectsModel := AProjectsModel;
  FFolderModel := AFolderModel;
  FFavoritesModel := AFavoritesModel;
  FUsersModel := AUsersModel;
  FHistoryModel := AHistoryModel;
  FItemModel := AItemModel;
  FGroupsModel := AGroupsModel;
  FHypBadges := TDictionary<Integer, THypProjectBadge>.Create;
  FNoFolders := TFoldersList.Create;
end;

destructor TProjectTreeVM.Destroy;
begin
  DropFolderLookup;
  FNoFolders.Free;
  FHypBadges.Free;
  inherited;
end;

procedure TProjectTreeVM.DoChanged;
begin
  DropFolderLookup;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TProjectTreeVM.IsSupervisorMode: Boolean;
begin
  Result := FProjectsModel.Access.CanBrowseAllProjects(FProjectsModel.Manager,
    FUsersModel.CurrentUser);
end;

function TProjectTreeVM.IsReadOnly: Boolean;
begin
  Result := not FProjectsModel.Access.CanCreateProjects(FProjectsModel.Manager,
    FUsersModel.CurrentUser);
end;

function TProjectTreeVM.UserId: Integer;
begin
  if FUsersModel.CurrentUser = nil then
    Result := 0
  else
    Result := FUsersModel.CurrentUser.Id;
end;


function TProjectTreeVM.GetUsers: TList<TUser>;
begin
  if not IsSupervisorMode then
    Exit(TList<TUser>.Create);

  // Admin accounts are system accounts, often a second login of a person who
  // is also listed as a Super; only the signed-in Admin sees its own node.
  // Active users, plus any archived owner of a project with hypotheses: a
  // hypothesis seen on the web must be reachable here, and its project would
  // otherwise vanish with its owner (GetProjects shows only those projects).
  Result := FUsersModel.List;
  for var I := Result.Count - 1 downto 0 do
    if ((Result[I].Role = dbAdmin) and (Result[I].Id <> UserId)) or
       ((not FShowArchived) and Result[I].IsArchived and
        not OwnsHypothesisProject(Result[I].Id)) then
      Result.Delete(I);
end;

function TProjectTreeVM.OwnerNodes: TList<TUser>;
begin
  Result := GetUsers;
  if Result.Count <= 1 then
    Result.Clear;
end;

function TProjectTreeVM.LoadOwnerTree: TOwnerTree;
var
  Users: TList<TUser>;
  Ids: TArray<Integer>;
  Projects: TObjectDictionary<Integer, TList<TProject>>;
  Groups: TObjectDictionary<Integer, TProjectGroupList>;
  I: Integer;
begin
  Users := OwnerNodes;
  if Users.Count = 0 then
  begin
    Users.Free;
    Exit(nil);
  end;
  Projects := nil;
  Groups := nil;
  try
    SetLength(Ids, Users.Count);
    for I := 0 to Users.Count - 1 do
      Ids[I] := Users[I].Id;
    Projects := GetProjectsByOwner(Ids);
    Groups := GetGroupsByOwner(Ids);
    Result := TOwnerTree.Create(Users, Projects, Groups);
  except
    Groups.Free;
    Projects.Free;
    Users.Free;
    raise;
  end;
end;

function TProjectTreeVM.OwnsHypothesisProject(AUserId: Integer): Boolean;
var
  ProjectId: Integer;
  P: TProject;
begin
  Result := False;
  for ProjectId in FHypBadges.Keys do
  begin
    P := FProjectsModel.GetProject(ProjectId);
    if Assigned(P) and (not P.IsArchived) and Assigned(P.Owner) and
       (P.Owner.Id = AUserId) then
      Exit(True);
  end;
end;

procedure TProjectTreeVM.RefreshHypothesisBadges;
var
  Fresh: TDictionary<Integer, THypProjectBadge>;
begin
  Fresh := HypothesisBadges(FProjectsModel.Manager, FUsersModel.CurrentUser,
    FProjectsModel.Access);
  FHypBadges.Free;
  FHypBadges := Fresh;
end;

function TProjectTreeVM.HypothesisCount(ProjectId: Integer): Integer;
var
  B: THypProjectBadge;
begin
  if FHypBadges.TryGetValue(ProjectId, B) then
    Result := B.Count
  else
    Result := 0;
end;

function TProjectTreeVM.HypothesisWaiting(ProjectId: Integer): Integer;
var
  B: THypProjectBadge;
begin
  if FHypBadges.TryGetValue(ProjectId, B) then
    Result := B.Waiting
  else
    Result := 0;
end;

function TProjectTreeVM.ProjectMatchesFilter(Project: TProject): Boolean;
begin
  if FFilterText = '' then
    Exit(True);
  Result := ContainsText(Project.Title, FFilterText) or
            ContainsText(Project.Description, FFilterText);
end;

function TProjectTreeVM.PassesFilterText(Project: TProject): Boolean;
var
  Folder: TFolder;
begin
  if ProjectMatchesFilter(Project) then
    Exit(True);
  for Folder in FoldersOf(Project) do
    if ContainsText(Folder.Title, FFilterText) or
       ContainsText(Folder.Description, FFilterText) then
      Exit(True);
  Result := False;
end;

function TProjectTreeVM.GetProjects(AUserId: Integer): TList<TProject>;
var
  Proj: TProject;
  Source, Eligible: TList<TProject>;
  UnloadedIds: TList<Integer>;
  ByOwner: TObjectDictionary<Integer, TList<TProject>>;
begin
  if AUserId > 0 then
  begin
    ByOwner := GetProjectsByOwner([AUserId]);
    try
      Exit(ByOwner.ExtractPair(AUserId).Value);
    finally
      ByOwner.Free;
    end;
  end;

  Result := TList<TProject>.Create;
  try
    Source := FProjectsModel.Access.ProjectList(FProjectsModel.Manager,
      FUsersModel.CurrentUser);
    Eligible := TList<TProject>.Create;
    UnloadedIds := TList<Integer>.Create;
    try
      for Proj in Source do
      begin
        if not ArchiveListed(Proj) then
          Continue;
        Eligible.Add(Proj);
        if not Proj.FoldersLoaded then
          UnloadedIds.Add(Proj.Id);
      end;
      FillFolderLookup(UnloadedIds.ToArray);
      for Proj in Eligible do
        if PassesFilterText(Proj) then
          Result.Add(Proj);
    finally
      UnloadedIds.Free;
      Eligible.Free;
      Source.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TProjectTreeVM.ArchiveListed(Project: TProject): Boolean;
begin
  Result := FShowArchived or not Project.IsArchived;
end;

function TProjectTreeVM.OwnerProjectListed(Project: TProject): Boolean;
begin
  // An archived owner is listed only for their projects with
  // hypotheses (GetUsers); the rest wait for "Show Archived".
  Result := ArchiveListed(Project) and
    (FShowArchived or not Project.Owner.IsArchived or (HypothesisCount(Project.Id) > 0));
end;

function TProjectTreeVM.OwnerProjectSource(const AOwnerIds: TArray<Integer>): TList<TProject>;
var
  Viewer: TUser;
  Chunk: TArray<Variant>;
  Part: TList<TProject>;
begin
  Result := TList<TProject>.Create;
  try
    // An owner id selects an owner group, never an acting principal. In
    // particular, an active supervisor may browse archived owners, while a
    // revoked viewer must not gain the selected owner's authority.
    Viewer := FUsersModel.CurrentUser;
    if IsSupervisorMode then
      for Chunk in unit_HypothesisModel.IdChunks(AOwnerIds) do
      begin
        Part := FProjectsModel.Access.ProjectDataSetCriteria(
          FProjectsModel.Manager, Viewer).Where(Linq['Owner.Id']._In(Chunk))
          .OrderBy('SortOrder').OrderBy('ID').List;
        try
          Result.AddRange(Part);
        finally
          Part.Free;
        end;
      end
    else
    begin
      Part := FProjectsModel.Access.ProjectList(FProjectsModel.Manager, Viewer);
      try
        Result.AddRange(Part);
      finally
        Part.Free;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TProjectTreeVM.GetProjectsByOwner(
  const AOwnerIds: TArray<Integer>): TObjectDictionary<Integer, TList<TProject>>;
var
  Proj: TProject;
  Source, Eligible: TList<TProject>;
  UnloadedIds: TList<Integer>;
  OwnerId: Integer;
begin
  Result := TObjectDictionary<Integer, TList<TProject>>.Create([doOwnsValues]);
  Source := nil;
  Eligible := TList<TProject>.Create;
  UnloadedIds := TList<Integer>.Create;
  try
    try
      for OwnerId in AOwnerIds do
        if not Result.ContainsKey(OwnerId) then
          Result.Add(OwnerId, TList<TProject>.Create);
      if Result.Count = 0 then
        Exit;

      Source := OwnerProjectSource(AOwnerIds);
      for Proj in Source do
      begin
        if (not Assigned(Proj.Owner)) or (not Result.ContainsKey(Proj.Owner.Id)) then
          Continue;
        if not OwnerProjectListed(Proj) then
          Continue;
        Eligible.Add(Proj);
        if not Proj.FoldersLoaded then
          UnloadedIds.Add(Proj.Id);
      end;

      FillFolderLookup(UnloadedIds.ToArray);

      for Proj in Eligible do
        if PassesFilterText(Proj) then
          Result[Proj.Owner.Id].Add(Proj);
    except
      Result.Free;
      raise;
    end;
  finally
    UnloadedIds.Free;
    Eligible.Free;
    Source.Free;
  end;
end;

function TProjectTreeVM.ShownProjectIds: TArray<Integer>;
var
  Users: TList<TUser>;
  Owners: TDictionary<Integer, Boolean>;
  Source: TList<TProject>;
  Ids: TList<Integer>;
  Proj: TProject;
  User: TUser;
begin
  Owners := TDictionary<Integer, Boolean>.Create;
  Ids := TList<Integer>.Create;
  Source := nil;
  Users := OwnerNodes;
  try
    if Users.Count = 0 then
    begin
      Source := FProjectsModel.Access.ProjectList(FProjectsModel.Manager,
        FUsersModel.CurrentUser);
      for Proj in Source do
        if ArchiveListed(Proj) then
          Ids.Add(Proj.Id);
    end
    else
    begin
      for User in Users do
        Owners.AddOrSetValue(User.Id, True);
      Source := OwnerProjectSource(Owners.Keys.ToArray);
      for Proj in Source do
        if Assigned(Proj.Owner) and Owners.ContainsKey(Proj.Owner.Id) and
           OwnerProjectListed(Proj) then
          Ids.Add(Proj.Id);
    end;
    Result := Ids.ToArray;
  finally
    Source.Free;
    Users.Free;
    Ids.Free;
    Owners.Free;
  end;
end;

function TProjectTreeVM.GetGroupsByOwner(
  const AOwnerIds: TArray<Integer>): TObjectDictionary<Integer, TProjectGroupList>;
var
  Chunk: TArray<Variant>;
  Found: TProjectGroupList;
  Group: TProjectGroup;
  OwnerId: Integer;
begin
  Result := TObjectDictionary<Integer, TProjectGroupList>.Create([doOwnsValues]);
  try
    for OwnerId in AOwnerIds do
      if not Result.ContainsKey(OwnerId) then
        Result.Add(OwnerId, TProjectGroupList.Create);
    for Chunk in unit_HypothesisModel.IdChunks(AOwnerIds) do
    begin
      Found := FGroupsModel.ListGroupsIn(Chunk);
      try
        for Group in Found do
          Result[Group.OwnerId].Add(Group);
      finally
        Found.Free;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TProjectTreeVM.DropFolderLookup;
begin
  FreeAndNil(FFolderLookup);
end;

procedure TProjectTreeVM.FillFolderLookup(const AProjectIds: TArray<Integer>);
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Owner: TDictionary<Integer, Integer>;
  FolderIds: TList<Integer>;
  Found: TFoldersList;
  Folder: TFolder;
  Manager: TObjectManager;
  ProjectId, OwnerId: Integer;
begin
  if Length(AProjectIds) = 0 then
    Exit;
  Manager := FProjectsModel.Manager;
  if FFolderLookup = nil then
    FFolderLookup := TObjectDictionary<Integer, TFoldersList>.Create([doOwnsValues]);
  Owner := TDictionary<Integer, Integer>.Create;
  FolderIds := TList<Integer>.Create;
  try
    try
      for ProjectId in AProjectIds do
      begin
        FFolderLookup.Remove(ProjectId);
        FFolderLookup.Add(ProjectId, TFoldersList.Create);
      end;
      for Chunk in unit_HypothesisModel.IdChunks(AProjectIds) do
      begin
        Rows := Manager.Find<TProject>
          .CreateAlias('FFolders', 'f')
          .Select(TProjections.ProjectionList
            .Add(TProjections.Prop('Id').As_('ProjectId'))
            .Add(TProjections.Prop('f.Id').As_('FolderId')))
          .Where(Linq['Id']._In(Chunk))
          .ListValues;
        try
          for Row in Rows do
            if not VarIsNull(Row.Values['FolderId']) then
              Owner.AddOrSetValue(Integer(Row.Values['FolderId']),
                Integer(Row.Values['ProjectId']));
        finally
          Rows.Free;
        end;
      end;
      FolderIds.AddRange(Owner.Keys);
      FolderIds.Sort;
      for Chunk in unit_HypothesisModel.IdChunks(FolderIds.ToArray) do
      begin
        Found := Manager.Find<TFolder>
          .Where(Linq['Id']._In(Chunk))
          .OrderBy('Id')
          .List;
        try
          for Folder in Found do
            if Owner.TryGetValue(Folder.Id, OwnerId) then
              FFolderLookup[OwnerId].Add(Folder);
        finally
          Found.Free;
        end;
      end;
    except
      DropFolderLookup;
      raise;
    end;
  finally
    FolderIds.Free;
    Owner.Free;
  end;
end;

function TProjectTreeVM.FoldersOf(Project: TProject): TFoldersList;
var
  Manager: TObjectManager;
  Live: TProject;
begin
  Manager := FProjectsModel.Manager;
  Live := Manager.FindCached<TProject>(Project.Id);
  if Live <> Project then
    Live := Manager.Find<TProject>(Project.Id);
  if Live = nil then
    Exit(FNoFolders);
  if Live.FoldersLoaded then
    Exit(Live.Folders);
  if Assigned(FFolderLookup) and FFolderLookup.TryGetValue(Live.Id, Result) then
    Exit;
  Result := Live.Folders;
end;

function TProjectTreeVM.GetSortedFolders(Project: TProject): TList<TFolder>;
var
  Folder: TFolder;
begin
  Result := TList<TFolder>.Create;
  for Folder in FoldersOf(Project) do
    Result.Add(Folder);

  Result.Sort(TComparer<TFolder>.Construct(
    function(const A, B: TFolder): Integer
    begin
      Result := A.SortOrder - B.SortOrder;
      if Result = 0 then
        Result := A.Id - B.Id;
    end));
end;

function TProjectTreeVM.GetFavorites: TList<TFavorite>;
begin
  Result := FFavoritesModel.GetFavorites(UserId);
end;


function TProjectTreeVM.GetProjectAccess(ProjectId: Integer): TProjectAccess;
begin
  Result := FProjectsModel.GetProjectAccess(ProjectId);
end;

function TProjectTreeVM.GetProject(ProjectId: Integer): TProject;
begin
  Result := FProjectsModel.GetProject(ProjectId);
end;

function TProjectTreeVM.CanDeleteProject(ProjectId: Integer): TDeleteCheck;
begin
  if not FProjectsModel.IsProjectEmpty(ProjectId) then
    Result := dcNotEmpty
  else if FProjectsModel.ProjectHasRecycleBinItems(ProjectId) then
    // Only recycle-bin items remain: block the hard delete (which has no FK
    // cascade and would orphan those rows) until the bin is emptied.
    Result := dcHasRecycleBinItems
  else
    Result := dcOK;
end;

function TProjectTreeVM.CanDeleteFolder(FolderId: Integer): TDeleteCheck;
begin
  if not FFolderModel.IsFolderEmpty(FolderId) then
    Result := dcNotEmpty
  else if FFolderModel.FolderHasRecycleBinItems(FolderId) then
    // Only recycle-bin items remain: block the hard delete (which has no FK
    // cascade and would orphan those rows) until the bin is emptied.
    Result := dcHasRecycleBinItems
  else
    Result := dcOK;
end;

function TProjectTreeVM.CanEditProject(ProjectId: Integer): Boolean;
begin
  Result := GetProjectAccess(ProjectId) = paOwner;
end;

function TProjectTreeVM.CanAddFolder(ProjectId: Integer): Boolean;
begin
  Result := FProjectsModel.Access.CanWrite(FProjectsModel.Manager,
    FUsersModel.CurrentUser, ProjectId);
end;


function TProjectTreeVM.AddProject(const Title, Comment: string; Owner: TUser): TProject;
begin
  Result := FProjectsModel.AddProject(Title, Comment, Owner);
  DoChanged;
end;

procedure TProjectTreeVM.AddFolder(const Title, Comment: string;
  ProjectId, ParentFolderId: Integer);
begin
  FProjectsModel.AddFolder(Title, Comment, ProjectId, ParentFolderId);
  DoChanged;
end;

procedure TProjectTreeVM.UpdateProject(Project: TProject;
  const Title, Comment: string; IsArchived: Boolean);
begin
  Project.Title := Title;
  Project.Description := Comment;
  Project.IsArchived := IsArchived;
  FProjectsModel.Update(Project);
  DoChanged;
end;

procedure TProjectTreeVM.UpdateFolder(Folder: TFolder;
  const Title, Comment: string);
begin
  Folder.Title := Title;
  Folder.Description := Comment;
  FFolderModel.Update(Folder, UserId);
  DoChanged;
end;

procedure TProjectTreeVM.DeleteProject(ProjectId: Integer);
begin
  FProjectsModel.DeleteProject(ProjectId, UserId);
  DoChanged;
end;

procedure TProjectTreeVM.DeleteFolder(FolderId, ProjectId: Integer);
begin
  FFolderModel.DeleteFolder(FolderId, ProjectId, UserId);
  DoChanged;
end;

procedure TProjectTreeVM.ToggleArchive(Project: TProject);
begin
  Project.IsArchived := not Project.IsArchived;
  FProjectsModel.Update(Project);
  DoChanged;
end;


procedure TProjectTreeVM.MoveFolder(Folder: TFolder;
  SrcProjectId, DstProjectId, DstParentFolderId: Integer;
  const Relocator: IFileRelocator);
begin
  FProjectsModel.MoveFolder(Folder, SrcProjectId, DstProjectId,
    DstParentFolderId, UserId, Relocator);
  DoChanged;
end;

function TProjectTreeVM.MoveProc(Proc: TItem; NewProjectId, NewFolderId: Integer;
  const Relocator: IFileRelocator): Boolean;
begin
  Result := FItemModel.MoveProc(Proc, NewProjectId, NewFolderId, UserId, Relocator);
  if Result then
    DoChanged;
end;

procedure TProjectTreeVM.ReparentFolderUp(Folder: TFolder);
begin
  Folder.ParentFolderID := 0;
  FFolderModel.Update(Folder, UserId);
  DoChanged;
end;

procedure TProjectTreeVM.ReorderProjects(const OrderedIds: TArray<Integer>);
begin
  FProjectsModel.ReorderProjects(OrderedIds);
  DoChanged;
end;

procedure TProjectTreeVM.ReorderFolders(const OrderedIds: TArray<Integer>);
begin
  FFolderModel.ReorderFolders(OrderedIds);
  DoChanged;
end;


procedure TProjectTreeVM.ToggleFavorite(FavType: TFavoriteType;
  ProjectId, FolderId: Integer; const Title: string);
begin
  FFavoritesModel.ToggleFavorite(UserId, FavType, ProjectId, FolderId, 0, Title);
  DoChanged;
end;

procedure TProjectTreeVM.RemoveFavorite(FavId: Integer);
begin
  FFavoritesModel.RemoveFavorite(FavId);
  DoChanged;
end;

function TProjectTreeVM.IsFavorite(FavType: TFavoriteType;
  ProjectId, FolderId: Integer): Boolean;
begin
  Result := FFavoritesModel.IsFavorite(UserId, FavType, ProjectId, FolderId, 0);
end;


procedure TProjectTreeVM.SelectNode(ProjectId, FolderId: Integer);
begin
  FHistoryModel.UserRecord.LastProject := ProjectId;
  FHistoryModel.UserRecord.LastFolder := FolderId;
end;

function TProjectTreeVM.IsNodeExpanded(Kind: TTreeNodeKind; NodeId: Integer;
  Shared: Boolean): Boolean;
begin
  if not Assigned(FTreeState) or not FTreeState.Seeded then
    Result := Shared
  else
    Result := FTreeState.IsExpanded(Kind, NodeId, False);
end;

procedure TProjectTreeVM.SetNodeExpanded(Kind: TTreeNodeKind; NodeId: Integer;
  Value: Boolean);
begin
  if Assigned(FTreeState) then
    FTreeState.SetExpanded(Kind, NodeId, Value);
end;

function TProjectTreeVM.TreeStateSeeded: Boolean;
begin
  Result := not Assigned(FTreeState) or FTreeState.Seeded;
end;

procedure TProjectTreeVM.MarkTreeStateSeeded;
begin
  if Assigned(FTreeState) then
    FTreeState.MarkSeeded;
end;

function TProjectTreeVM.LastProjectId: Integer;
begin
  Result := FHistoryModel.UserRecord.LastProject;
end;

function TProjectTreeVM.LastFolderId: Integer;
begin
  Result := FHistoryModel.UserRecord.LastFolder;
end;

function TProjectTreeVM.CurrentUser: TUser;
begin
  Result := FUsersModel.CurrentUser;
end;

procedure TProjectTreeVM.EvictCache;
begin
  DropFolderLookup;
  FProjectsModel.EvictCache;
end;


function TProjectTreeVM.GetGroups(AUserId: Integer): TProjectGroupList;
begin
  if AUserId <= 0 then
    AUserId := UserId;
  Result := FGroupsModel.ListGroups(AUserId);
end;

function TProjectTreeVM.AddGroup(const Title: string; OwnerId: Integer): TProjectGroup;
begin
  if OwnerId <= 0 then
    OwnerId := UserId;
  Result := FGroupsModel.AddGroup(Title, OwnerId);
  DoChanged;
end;

function TProjectTreeVM.RenameGroup(Group: TProjectGroup; const Title: string): Boolean;
begin
  Result := FGroupsModel.RenameGroup(Group, Title);
  if Result then
    DoChanged;
end;

function TProjectTreeVM.DeleteGroup(GroupId: Integer): Boolean;
begin
  Result := FGroupsModel.DeleteGroup(GroupId, UserId);
  if Result then
    DoChanged;
end;

procedure TProjectTreeVM.ReorderGroups(const OrderedIds: TArray<Integer>);
begin
  FGroupsModel.ReorderGroups(OrderedIds);
  DoChanged;
end;

function TProjectTreeVM.MoveProjectToGroup(ProjectId, GroupId: Integer): Boolean;
begin
  Result := FGroupsModel.MoveProjectToGroup(ProjectId, GroupId, UserId);
  if Result then
    DoChanged;
end;

end.
