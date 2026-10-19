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
    procedure DoChanged;
    function OwnsHypothesisProject(AUserId: Integer): Boolean;
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
    function GetProjects(AUserId: Integer): TList<TProject>;
    function GetSortedFolders(Project: TProject): TList<TFolder>;
    function GetFavorites: TList<TFavorite>;
    function ProjectMatchesFilter(Project: TProject): Boolean;

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
  System.StrUtils, System.Generics.Defaults, Aurelius.Criteria.Linq;


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
end;

destructor TProjectTreeVM.Destroy;
begin
  FHypBadges.Free;
  inherited;
end;

procedure TProjectTreeVM.DoChanged;
begin
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

function TProjectTreeVM.GetProjects(AUserId: Integer): TList<TProject>;
var
  Proj: TProject;
  Folder: TFolder;
  AnyFolderMatches: Boolean;
  Viewer: TUser;
  Source: TList<TProject>;
begin
  Result := TList<TProject>.Create;

  // AUserId selects an owner group, never an acting principal. In particular,
  // an active supervisor may browse archived owners, while a revoked viewer
  // must not gain the selected owner's authority.
  Viewer := FUsersModel.CurrentUser;
  try
    if (AUserId > 0) and IsSupervisorMode then
      Source := FProjectsModel.Access.ProjectDataSetCriteria(
        FProjectsModel.Manager, Viewer).Where(Linq['Owner.Id'] = AUserId)
        .OrderBy('SortOrder').OrderBy('ID').List
    else
      Source := FProjectsModel.Access.ProjectList(FProjectsModel.Manager, Viewer);
    try
      for Proj in Source do
      begin
        if Proj.IsArchived and (not FShowArchived) then
          Continue;

        if (AUserId > 0) and Assigned(Proj.Owner) and (Proj.Owner.Id <> AUserId) then
          Continue;

        // An archived owner is listed only for their projects with
        // hypotheses (GetUsers); the rest wait for "Show Archived".
        if (AUserId > 0) and (not FShowArchived) and Assigned(Proj.Owner) and
           Proj.Owner.IsArchived and (HypothesisCount(Proj.Id) = 0) then
          Continue;

        if FFilterText <> '' then
        begin
          if not ProjectMatchesFilter(Proj) then
          begin
            AnyFolderMatches := False;
            if Assigned(Proj.Folders) then
              for Folder in Proj.Folders do
                if ContainsText(Folder.Title, FFilterText) or
                   ContainsText(Folder.Description, FFilterText) then
                begin
                  AnyFolderMatches := True;
                  Break;
                end;
            if not AnyFolderMatches then
              Continue;
          end;
        end;

        Result.Add(Proj);
      end;
    finally
      Source.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TProjectTreeVM.GetSortedFolders(Project: TProject): TList<TFolder>;
var
  Folder: TFolder;
begin
  Result := TList<TFolder>.Create;
  if not Assigned(Project.Folders) then
    Exit;

  for Folder in Project.Folders do
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
