{ Suppress selection broadcasts while rebuilding the tree; inserting nodes
  would otherwise trigger repeated item-tree reloads. }
unit frame_ProjectsPanel;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  VirtualTrees.BaseAncestorVCL, VirtualTrees.BaseTree, VirtualTrees.AncestorVCL,
  VirtualTrees.DrawTree, Vcl.ExtCtrls, RzPanel, RzButton, System.ImageList,
  Vcl.ImgList, VirtualTrees,
  VirtualTrees.HeaderPopup, UITypes,
  VirtualTrees.Types, Vcl.Menus, unit_Project, unit_ProjectGroup, unit_User, unit_ProjectModel,
  Vcl.StdCtrls, RzLabel,
  Vcl.VirtualImageList, Vcl.BaseImageCollection, Vcl.ImageCollection,
  Winapi.ActiveX, System.Types, RzEdit, Vcl.Mask, dm_TreeImages,
  unit_Favorite, Vcl.ActnList, unit_ProjectTreeVM, unit_HypothesesVM,
  unit_TreeLook, unit_ProjectAccessPolicy, System.Actions;

const
  WM_DEFERRED_FILL = WM_USER + 42;

type
  TNavigateItemProc = procedure(Sender: TObject; ProjectId, FolderId, ItemId: Integer) of object;
  TProjectPermissionsEvent = function(Project: TProject): Boolean of object;

  TNodeType = (ntNone, ntUser, ntProject, ntFolder, ntFavorites, ntFavoriteItem, ntGroup);

  TUserSortMode = (usmManual, usmById, usmByName);


type

  PNodeData = ^TNodeData;
  TNodeData = record
    case NodeType: TNodeType of
      ntUser   : (User: TUser);
      ntProject: (Project: TProject);
      ntFolder : (Folder: TFolder; ProjectID: integer; ProjectName: string[255]);
      ntFavorites: ();
      ntFavoriteItem: (FavId, FavProjectId, FavFolderId, FavItemId: Integer;
                       FavType: TFavoriteType; FavTitle: string[255]);
      // GroupOwnerId caches the subtree owner so DnD checks need no proxy loads
      ntGroup  : (Group: TProjectGroup; GroupOwnerId: Integer);
    end;

  TframeProjectTree = class(TFrame)
    pnlMain: TRzPanel;
    pnlBottom: TRzPanel;
    Tree: TVirtualStringTree;
    pmProject: TPopupMenu;
    miProjectNewFolder: TMenuItem;
    miProjectSep1: TMenuItem;
    miProjectEdit: TMenuItem;
    miProjectArchive: TMenuItem;
    miProjectDelete: TMenuItem;
    miProjectSep2: TMenuItem;
    miProjectRefresh: TMenuItem;
    miProjectSep3: TMenuItem;
    miProjectShare: TMenuItem;
    miProjectHypotheses: TMenuItem;
    miProjectSep4: TMenuItem;
    miProjectCopyMCPLink: TMenuItem;
    miProjectSort: TMenuItem;
    miProjectSortMoveUp: TMenuItem;
    miProjectSortMoveDown: TMenuItem;
    miProjectSortSep: TMenuItem;
    miProjectSortByName: TMenuItem;
    miProjectSortByDate: TMenuItem;
    pmFolder: TPopupMenu;
    miFolderNewFolder: TMenuItem;
    miFolderSep1: TMenuItem;
    miFolderEdit: TMenuItem;
    miFolderMoveUp: TMenuItem;
    miFolderDelete: TMenuItem;
    miFolderSep2: TMenuItem;
    miFolderRefresh: TMenuItem;
    miFolderSep3: TMenuItem;
    miFolderCopyMCPLink: TMenuItem;
    miFolderSort: TMenuItem;
    miFolderSortMoveUp: TMenuItem;
    miFolderSortMoveDown: TMenuItem;
    miFolderSortSep: TMenuItem;
    miFolderSortByName: TMenuItem;
    miFolderSortByDate: TMenuItem;
    pmRoot: TPopupMenu;
    miRootNewGroup: TMenuItem;
    miSortUsers: TMenuItem;
    miSortUsersManual: TMenuItem;
    miSortUsersById: TMenuItem;
    miSortUsersByName: TMenuItem;
    pmGroup: TPopupMenu;
    miGroupNewProject: TMenuItem;
    miGroupSep1: TMenuItem;
    miGroupRename: TMenuItem;
    miGroupDelete: TMenuItem;
    lblTitle: TRzLabel;
    lblCreated: TRzLabel;
    lbModified: TRzLabel;
    lblDataFolder: TRzLabel;
    lblComment: TRzLabel;
    RzPanel1: TRzPanel;
    RzToolbar1: TRzToolbar;
    BtnNewFolder: TRzToolButton;
    BtnNewProject: TRzToolButton;
    BtnNewTopicWiki: TRzToolButton;
    RzSpacer1: TRzSpacer;
    btnEditItem: TRzToolButton;
    btnLeft: TRzToolButton;
    RzSpacer3: TRzSpacer;
    btnDeleteItem: TRzToolButton;
    RzSpacer4: TRzSpacer;
    btnRefresh: TRzToolButton;
    RzSpacer5: TRzSpacer;
    btnShowArchived: TRzToolButton;
    RzSpacer6: TRzSpacer;
    btnHypotheses: TRzToolButton;
    pnlSearch: TRzPanel;
    edSearch: TRzEdit;
    btnClearSearch: TRzBitBtn;
    procedure btnClearSearchClick(Sender: TObject);
    procedure btnDeleteItemClick(Sender: TObject);
    procedure btnEditItemClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnShowArchivedClick(Sender: TObject);
    procedure edSearchChange(Sender: TObject);
    procedure btnLeftClick(Sender: TObject);
    procedure BtnNewFolderClick(Sender: TObject);
    procedure BtnNewProjectClick(Sender: TObject);
    procedure BtnNewTopicWikiClick(Sender: TObject);
    procedure TreeGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure TreeGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure TreeFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeGetImageIndexEx(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Kind: TVTImageKind; Column: TColumnIndex; var Ghosted: Boolean;
      var ImageIndex: TImageIndex; var ImageList: TCustomImageList);
    procedure TreeGetPopupMenu(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; const P: TPoint; var AskParent: Boolean;
      var PopupMenu: TPopupMenu);
    procedure TreeBeforeCellPaint(Sender: TBaseVirtualTree;
      TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
    procedure TreeAfterCellPaint(Sender: TBaseVirtualTree;
      TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      CellRect: TRect);
    procedure TreePaintText(Sender: TBaseVirtualTree;
      const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType);
    procedure TreeDrawText(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; Column: TColumnIndex; const Text: string;
      const CellRect: TRect; var DefaultDraw: Boolean);
    procedure TreeFocusChanging(Sender: TBaseVirtualTree; OldNode,
      NewNode: PVirtualNode; OldColumn, NewColumn: TColumnIndex;
      var Allowed: Boolean);
    procedure TreeExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeCollapsed(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeDragAllowed(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; var Allowed: Boolean);
    procedure miProjectNewFolderClick(Sender: TObject);
    procedure miProjectEditClick(Sender: TObject);
    procedure miProjectArchiveClick(Sender: TObject);
    procedure miProjectDeleteClick(Sender: TObject);
    procedure miFolderNewFolderClick(Sender: TObject);
    procedure miFolderEditClick(Sender: TObject);
    procedure miFolderMoveUpClick(Sender: TObject);
    procedure miFolderDeleteClick(Sender: TObject);
    procedure miRefreshClick(Sender: TObject);
    procedure TreeDragDrop(Sender: TBaseVirtualTree; Source: TObject; DataObject:
        TVTDragDataObject; Formats: TFormatArray; Shift: TShiftState; Pt: TPoint;
        var Effect: Integer; Mode: TDropMode);
    procedure TreeDragOver(Sender: TBaseVirtualTree; Source: TObject; Shift:
        TShiftState; State: TDragState; Pt: TPoint; Mode: TDropMode; var Effect:
        Integer; var Accept: Boolean);
    procedure miProjectShareClick(Sender: TObject);
    procedure miProjectHypothesesClick(Sender: TObject);
    procedure miProjectCopyMCPLinkClick(Sender: TObject);
    procedure miFolderCopyMCPLinkClick(Sender: TObject);
    procedure miSortMoveUpClick(Sender: TObject);
    procedure miSortMoveDownClick(Sender: TObject);
    procedure miSortByNameClick(Sender: TObject);
    procedure miSortByDateClick(Sender: TObject);
    procedure miRootNewGroupClick(Sender: TObject);
    procedure miSortUsersModeClick(Sender: TObject);
    procedure miGroupNewProjectClick(Sender: TObject);
    procedure miGroupRenameClick(Sender: TObject);
    procedure miGroupDeleteClick(Sender: TObject);
  private
    FLook: TTreeLook;
    FVM: TProjectTreeVM;
    FUpdating: boolean;
    FShowArchived: boolean;
    FFilterText: string;
    FSelectedNode: PVirtualNode;
    FFavoritesNode: PVirtualNode;
    FpmFavorite: TPopupMenu;
    FmiRemoveFavorite: TMenuItem;
    FmiAddFavorite: TMenuItem;
    FmiFolderAddFavorite: TMenuItem;
    FmiProjectAudit: TMenuItem;
    FmiFolderAudit: TMenuItem;
    FOnAuditNavigate: TNavigateItemProc;
    FOnOpenHypotheses: TOpenHypothesisEvent;
    FOnProjectPermissions: TProjectPermissionsEvent;
    FActionList: TActionList;
    FPendingGroupOwnerId: Integer;
    FUserSortMode: TUserSortMode;
    procedure SyncSortUsersMenu;
    procedure actNonGuestUpdate(Sender: TObject);
    procedure actHypothesesUpdate(Sender: TObject);
    procedure actShareUpdate(Sender: TObject);
    function CanWriteToProject(ProjectId: Integer): Boolean;
    procedure CreateActions;
    procedure DoProjectAudit(Sender: TObject);
    procedure DoFolderAudit(Sender: TObject);

    procedure PromptNewGroup(OwnerId: Integer);
    procedure BtnNewGroupClick(Sender: TObject);
    procedure CreateFavoriteMenuItems;
    procedure miRemoveFavoriteClick(Sender: TObject);
    procedure miAddFavoriteClick(Sender: TObject);
    procedure InsertFavorites;

    procedure InsertFolder(const Folder: TFolder;
                           Parent: PVirtualNode;
                           ProjectID: integer;
                           ProjectName: string);
    function InsertProject(Parent: PVirtualNode; const Project: TProject): PVirtualNode;
    function InsertGroup(Parent: PVirtualNode; const Group: TProjectGroup): PVirtualNode;
    function FindParentFolder(Root: PVirtualNode; ParentID: integer): PVirtualNode;
    function FillProjects(const User: PVirtualNode): PVirtualNode;
    procedure SeedTreeState;
    function RestoreNodeStatesAndFindSelection(Root: PVirtualNode;
      LastProjectID, LastFolderID: Integer): PVirtualNode;
    function AddUser(const User: TUser): PVirtualNode;
    function FindOwnerUser(Node: PVirtualNode): TUser;
    procedure DisplayProjectInfo(const Data: PNodeData);
    procedure DisplayFolderInfo(const Data: PNodeData);
    procedure ReorderSiblings(SourceNode, TargetNode: PVirtualNode;
      Mode: TDropMode; NodeType: TNodeType);
    function CollectSiblings(Node: PVirtualNode;
      out NodeType: TNodeType): TList<PVirtualNode>;
    procedure PersistSiblingOrder(NodeType: TNodeType;
      const Nodes: TList<PVirtualNode>);
    procedure MoveSibling(Direction: Integer);
    procedure SortSiblings(SortByDate: Boolean);
    procedure SaveColumnWidths;
    procedure LoadColumnWidths;
    procedure WMDeferredFill(var Msg: Winapi.Messages.TMessage); message WM_DEFERRED_FILL;
    function RowColor(Node: PVirtualNode): TColor;
  public
    actNewProject: TAction;
    actNewTopicWiki: TAction;
    actNewFolder: TAction;
    actNewGroup: TAction;
    actEdit: TAction;
    actArchive: TAction;
    actShare: TAction;
    actHypotheses: TAction;
    actDelete: TAction;
    actRefresh: TAction;
    actShowArchived: TAction;
    destructor Destroy; override;
    constructor Create(AOwner: TComponent); override;
    procedure Init;
    /// <summary>Rebuilds the tree. ARefreshBadges re-reads the "HYP n"
    /// counts first; the search box passes False so typing never re-queries
    /// them (a filter change cannot change them).</summary>
    procedure FillTree(ARefreshBadges: Boolean = True);
    procedure Clear;
    procedure ResetSession;
    procedure RestoreLastSelection;
    procedure RefreshFavorites;
    procedure RefreshHypothesisBadges;
    procedure ScaleForDPI;
    procedure SelectProject(ProjectId: Integer);
    procedure SelectFolder(FolderId: Integer);
    property OnAuditNavigate: TNavigateItemProc read FOnAuditNavigate write FOnAuditNavigate;
    property OnOpenHypotheses: TOpenHypothesisEvent read FOnOpenHypotheses write FOnOpenHypotheses;
    property OnProjectPermissions: TProjectPermissionsEvent
      read FOnProjectPermissions write FOnProjectPermissions;
  end;

implementation

uses
  System.Math,
  unit_TreeBadges,
  unit_TreeStateModel,
  unit_TreeAppearance,
  unit_Helpers,
  unit_Common,
  unit_DataModel,
  System.Messaging,
  System.Generics.Defaults,
  Vcl.Clipbrd,
  dlg_Project,
  DateUtils,
  unit_DlgConstants,
  System.StrUtils,
  unit_NotebookSettings,
  unit_Item,
  unit_WikiSeeder,
  unit_ExperimentTemplateModel,
  frame_ItemTree,
  dlg_AuditReport;

{$R *.dfm}

procedure TframeProjectTree.Clear;
begin
  if Assigned(FLook) then
    FLook.ClearHover;
  Tree.Clear;
  // Tree.Clear frees every node, so a retained FSelectedNode is now dangling.
  // Nil it: on a logout followed by a cancelled/failed re-login, ConnectDB
  // exits before FillTree reassigns it, and RestoreLastSelection would
  // otherwise dereference the freed node (AV).
  FSelectedNode := nil;
end;

constructor TframeProjectTree.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ResetSession;
end;

procedure TframeProjectTree.ResetSession;
var
  I: Integer;
begin
  Enabled := False;
  if Assigned(FActionList) then
  begin
    FActionList.State := asNormal;
    for I := 0 to FActionList.ActionCount - 1 do
      (FActionList.Actions[I] as TAction).Enabled := False;
    FActionList.State := asSuspended;
  end;
  Clear;
  FFavoritesNode := nil;
  FreeAndNil(FVM);
end;

function TframeProjectTree.FillProjects(const User: PVirtualNode): PVirtualNode;
var
  Project: TProject;
  Folder: TFolder;
  Root, SelectedNode: PVirtualNode;
  LastProjID, LastFoldID: Integer;
  ProjectMatches: Boolean;
  UserId: Integer;
  Projects: TList<TProject>;
  SortedFolders: TList<TFolder>;
begin
  SelectedNode := nil;
  LastProjID := FVM.LastProjectId;
  LastFoldID := FVM.LastFolderId;

  UserId := 0;
  if Assigned(User) then
  begin
    var UserData := PNodeData(Tree.GetNodeData(User));
    UserId := UserData.User.Id;
  end;

  Projects := FVM.GetProjects(UserId);
  // Group nodes sit between the user level and projects. The map is keyed by
  // the subtree owner's groups, so a shared project (whose GroupID references
  // its OWNER's group) never finds a match here and falls to the root.
  var Groups: TProjectGroupList := nil;
  var GroupNodes: TDictionary<Integer, PVirtualNode> := nil;
  try
    Groups := FVM.GetGroups(UserId); 
    GroupNodes := TDictionary<Integer, PVirtualNode>.Create;
    for var Group in Groups do
    begin
      if FVM.FilterText <> '' then
      begin
        var HasMatch := False;
        for Project in Projects do
          if Project.GroupID.HasValue and (Project.GroupID.Value = Group.Id) then
          begin
            HasMatch := True;
            Break;
          end;
        if not HasMatch then
          Continue;
      end;
      GroupNodes.Add(Group.Id, InsertGroup(User, Group));
    end;

    for Project in Projects do
    begin
      var ProjParent := User;
      if Project.GroupID.HasValue then
      begin
        var GroupNode: PVirtualNode;
        if GroupNodes.TryGetValue(Project.GroupID.Value, GroupNode) then
          ProjParent := GroupNode;
      end;
      Root := InsertProject(ProjParent, Project);

      SortedFolders := FVM.GetSortedFolders(Project);
      try
        if SortedFolders.Count = 0 then
        begin
          if not Assigned(SelectedNode) then
            SelectedNode := RestoreNodeStatesAndFindSelection(Root, LastProjID, LastFoldID);
          Continue;
        end;

        ProjectMatches := FVM.ProjectMatchesFilter(Project);

        var Remaining: TList<TFolder> := TList<TFolder>.Create;
        try
          for Folder in SortedFolders do
          begin
            if (FVM.FilterText <> '') and (not ProjectMatches) and
               not ContainsText(Folder.Title, FVM.FilterText) and
               not ContainsText(Folder.Description, FVM.FilterText) then
              Continue;

            if Folder.ParentFolderID <= 0 then
              InsertFolder(Folder, Root, Project.Id, Project.Title)
            else
              Remaining.Add(Folder);
          end;
          var PrevCount: Integer := Remaining.Count + 1;
          while (Remaining.Count > 0) and (Remaining.Count < PrevCount) do
          begin
            PrevCount := Remaining.Count;
            // Forward scan so same-parent siblings keep their SortOrder
            // (Remaining is already SortOrder-sorted). Iterating backwards here
            // appended nested siblings in reverse, defeating folder sort.
            var I: Integer := 0;
            while I < Remaining.Count do
            begin
              var ParentNode := FindParentFolder(Root, Remaining[I].ParentFolderID);
              if Assigned(ParentNode) then
              begin
                InsertFolder(Remaining[I], ParentNode, Project.ID, Project.Title);
                Remaining.Delete(I);
                // Do not advance: the next element shifts into index I.
              end
              else
                Inc(I);
            end;
          end;
        finally
          Remaining.Free;
        end;

        if FVM.IsNodeExpanded(tnkProject, Project.Id, Project.Expanded) then
        begin
          if Assigned(User) then
            Tree.Expanded[User] := True;
          Tree.Expanded[Root] := True;
        end;

        if not Assigned(SelectedNode) then
          SelectedNode := RestoreNodeStatesAndFindSelection(Root, LastProjID, LastFoldID);
      finally
        SortedFolders.Free;
      end;
    end;

    for var Pair in GroupNodes do
    begin
      var GData := PNodeData(Tree.GetNodeData(Pair.Value));
      Tree.Expanded[Pair.Value] :=
        FVM.IsNodeExpanded(tnkGroup, GData.Group.Id, GData.Group.Expanded) or
        (FVM.FilterText <> '');
    end;
  finally
    GroupNodes.Free;
    Groups.Free;
    Projects.Free;
  end;

  Result := SelectedNode;
end;

function TframeProjectTree.RestoreNodeStatesAndFindSelection(Root: PVirtualNode;
  LastProjectID, LastFolderID: Integer): PVirtualNode;
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Result := nil;
  Node := Tree.GetFirstChild(Root);

  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) then
    begin
      case Data.NodeType of
        ntProject: begin
          Tree.Expanded[Node] := FVM.IsNodeExpanded(tnkProject, Data.Project.ID,
            Data.Project.Expanded);
          if LastProjectID = Data.Project.ID then
            Result := Node;
        end;
        ntFolder: begin
          Tree.Expanded[Node] := FVM.IsNodeExpanded(tnkFolder, Data.Folder.ID,
            Data.Folder.Expanded);
          if LastFolderID = Data.Folder.ID then
            Result := Node;
        end;
      end;
    end;
    Node := Tree.GetNext(Node, True);
  end;
end;

function TframeProjectTree.AddUser(const User: TUser): PVirtualNode;
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.AddChild(nil);
  Data := Tree.GetNodeData(Node);

  Data.NodeType := ntUser;
  Data.User     := User;
  Result        := Node;
end;

function TframeProjectTree.FindOwnerUser(Node: PVirtualNode): TUser;
var
  N: PVirtualNode;
  Data: PNodeData;
begin
  Result := nil;
  N := Node;
  while Assigned(N) do
  begin
    Data := Tree.GetNodeData(N);
    if Assigned(Data) and (Data.NodeType = ntUser) then
      Exit(Data.User);
    N := N.Parent;
    if N = Tree.RootNode then
      Break;
  end;
end;

procedure TframeProjectTree.btnDeleteItemClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntProject:
    begin
      case FVM.CanDeleteProject(Data.Project.Id) of
        dcNotEmpty:
        begin
          MessageDlg('Cannot delete project "' + Data.Project.Title +
            '" because it contains folders or items.' + sLineBreak +
            'Remove all contents first.',
            mtWarning, [mbOK], 0);
          Exit;
        end;
        dcHasRecycleBinItems:
        begin
          MessageDlg('Cannot delete project "' + Data.Project.Title +
            '" because it contains items in the recycle bin.' + sLineBreak +
            'Empty the recycle bin first.',
            mtWarning, [mbOK], 0);
          Exit;
        end;
      end;

      if MessageDlg('Are you sure you want to permanently delete project "' +
        Data.Project.Title + '"?' + sLineBreak + sLineBreak +
        'This action cannot be undone.',
        mtWarning, [mbYes, mbNo], 0, mbNo) <> mrYes then
        Exit;

      FVM.DeleteProject(Data.Project.Id);
      FillTree;
    end;

    ntFolder:
    begin
      case FVM.CanDeleteFolder(Data.Folder.Id) of
        dcNotEmpty:
        begin
          MessageDlg('Cannot delete folder "' + Data.Folder.Title +
            '" because it contains items or subfolders.',
            mtWarning, [mbOK], 0);
          Exit;
        end;
        dcHasRecycleBinItems:
        begin
          MessageDlg('Cannot delete folder "' + Data.Folder.Title +
            '" because it contains items in the recycle bin.' + sLineBreak +
            'Empty the recycle bin first.',
            mtWarning, [mbOK], 0);
          Exit;
        end;
      end;

      if MessageDlg('Delete folder "' + Data.Folder.Title + '"?',
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
        Exit;

      FVM.DeleteFolder(Data.Folder.Id, Data.ProjectID);
      FillTree;
    end;
  end;
end;

procedure TframeProjectTree.btnEditItemClick(Sender: TObject);
begin
  TreeDblClick(Sender);
end;

procedure TframeProjectTree.btnLeftClick(Sender: TObject);
var
  Node, ParentNode: PVirtualNode;
  Data, ParentData: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntFolder) then Exit;

  ParentNode := Node.Parent;
  if (not Assigned(ParentNode)) or (ParentNode = Tree.RootNode) then Exit;

  ParentData := Tree.GetNodeData(ParentNode);
  if not Assigned(ParentData) then Exit;

  case ParentData.NodeType of
    ntProject:
      begin
        ShowMessage('This folder is already at the top level.');
        Exit;
      end;
    ntFolder:
      begin
        Data.Folder.ParentFolderID := ParentData.Folder.ParentFolderID;
        FVM.ReparentFolderUp(Data.Folder);
        FillTree;
      end;
  end;
end;

procedure TframeProjectTree.BtnNewFolderClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Title, Comment: string;
begin
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
  begin
    Data := Tree.GetNodeData(Node);
    if not (Data.NodeType in [ntUser, ntGroup]) and ShowProjectDialog(dmNew, 'folder', Title, Comment) then
    begin
      if Data.NodeType = ntProject then
         FVM.AddFolder(Title, Comment, Data.Project.Id, 0);
      if Data.NodeType = ntFolder then
         FVM.AddFolder(Title, Comment, Data.ProjectID, Data.Folder.Id);
      FillTree;
    end;
  end;
end;

procedure TframeProjectTree.BtnNewProjectClick(Sender: TObject);
var
  Title, Comment: string;
  Owner: TUser;
  Node: PVirtualNode;
begin
  Owner := FVM.CurrentUser;
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
  begin
    var OwnerUser := FindOwnerUser(Node);
    if Assigned(OwnerUser) then
      Owner := OwnerUser;
  end;

  if ShowProjectDialog(dmNew, 'project', Title, Comment) then
  begin
    FVM.AddProject(Title, Comment, Owner);
    FillTree;
  end;
end;

procedure TframeProjectTree.BtnNewTopicWikiClick(Sender: TObject);
var
  Title, Comment: string;
  Owner: TUser;
  Node: PVirtualNode;
  Data: PNodeData;
  NewProject: TProject;
  WikiTemplateId: Integer;
  SeedRoot: TItem;
  TargetProjectId, TargetFolderId: Integer;
  TargetLabel: string;
begin
  TargetProjectId := 0;
  TargetFolderId := 0;
  TargetLabel := '';
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) then
      case Data.NodeType of
        ntFolder:
          begin
            TargetProjectId := Data.ProjectID;
            TargetFolderId := Data.Folder.ID;
            TargetLabel := Format('folder "%s"', [Data.Folder.Title]);
          end;
        ntProject:
          begin
            TargetProjectId := Data.Project.ID;
            TargetFolderId := 0;
            TargetLabel := Format('project "%s"', [Data.Project.Title]);
          end;
      end;
  end;

  WikiTemplateId := Model.ExperimentTemplates.FindTemplateByName('Wiki');

  if TargetProjectId > 0 then
  begin
    if WikiTemplateId <= 0 then
    begin
      MessageDlg('Wiki template not available in this database.',
        mtWarning, [mbOK], 0);
      Exit;
    end;
    if MessageDlg(Format('Add a Wiki to %s?', [TargetLabel]),
      mtConfirmation, [mbOK, mbCancel], 0) <> mrOk then
      Exit;
    try
      SeedRoot := Model.ExperimentTemplates.ApplyTemplate(
        WikiTemplateId, TargetProjectId, TargetFolderId, Model.User.Id);
      if Assigned(SeedRoot) then
        unit_WikiSeeder.WriteReadmeContent(SeedRoot, Model.User.Id);
    except
      on E: EWikiFolderExists do
      begin
        MessageDlg('A Wiki folder already exists in this location. ' +
          'Remove or rename it before re-applying the Wiki template.',
          mtWarning, [mbOK], 0);
        Exit;
      end;
      on E: Exception do
      begin
        MessageDlg('Failed to add wiki: ' + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    FillTree;
    Exit;
  end;

  Owner := FVM.CurrentUser;
  if Assigned(Node) then
  begin
    var OwnerUser := FindOwnerUser(Node);
    if Assigned(OwnerUser) then
      Owner := OwnerUser;
  end;

  if not ShowProjectDialog(dmNew, 'topic wiki', Title, Comment) then
    Exit;

  NewProject := FVM.AddProject(Title, Comment, Owner);
  if not Assigned(NewProject) then
  begin
    MessageDlg('Project created, but could not be located for wiki seeding.',
      mtError, [mbOK], 0);
    FillTree;
    Exit;
  end;

  if WikiTemplateId > 0 then
  begin
    try
      SeedRoot := Model.ExperimentTemplates.ApplyTemplate(
        WikiTemplateId, NewProject.Id, 0, Model.User.Id);
      if Assigned(SeedRoot) then
        unit_WikiSeeder.WriteReadmeContent(SeedRoot, Model.User.Id);
    except
      on E: Exception do
        MessageDlg('Project created, but wiki seeding failed: ' + E.Message,
          mtError, [mbOK], 0);
    end;
  end
  else
    MessageDlg('Wiki template not available in this database. ' +
      'The project was created empty; add wiki pages manually.',
      mtWarning, [mbOK], 0);

  FillTree;
end;

procedure TframeProjectTree.FillTree(ARefreshBadges: Boolean);
var
  User: TUser;
  SelectedNode, TempNode: PVirtualNode;
begin
  SelectedNode := nil;
  if not Assigned(FVM) then Exit;
  FVM.ShowArchived := FShowArchived;
  FVM.FilterText := FFilterText;
  // Before GetUsers/GetProjects: they show archived owners' projects that
  // hold hypotheses, and the badges paint from the same counts.
  if ARefreshBadges then
    FVM.RefreshHypothesisBadges;
  FUpdating := True;
  try
    if Assigned(FLook) then
      FLook.ClearHover;
    Tree.Clear;
    FFavoritesNode := nil;

    InsertFavorites;

    if not FVM.IsSupervisorMode then
      SelectedNode := FillProjects(Nil)
    else begin
      var Users := FVM.GetUsers;
      try
        case FUserSortMode of
          usmById:
            Users.Sort(TComparer<TUser>.Construct(
              function(const L, R: TUser): Integer
              begin
                Result := L.Id - R.Id;
              end));
          usmByName:
            Users.Sort(TComparer<TUser>.Construct(
              function(const L, R: TUser): Integer
              begin
                Result := CompareText(L.FirstName + ' ' + L.LastName,
                                      R.FirstName + ' ' + R.LastName);
                if Result = 0 then
                  Result := L.Id - R.Id;
              end));
        end;

        if Users.Count <= 1 then
          SelectedNode := FillProjects(Nil)
        else begin
          for User in Users do
          begin
              var UserNode := AddUser(User);
              TempNode := FillProjects(UserNode);
              // The user's own saved state for this node is the authority: it overrides the
              // "expand when a project inside is expanded" heuristic, so a
              // node the supervisor collapsed stays collapsed across rebuilds.
              Tree.Expanded[UserNode] :=
                FVM.IsNodeExpanded(tnkUser, User.Id, User.TreeExpanded);
              if (not Assigned(SelectedNode)) and Assigned(TempNode) then
                SelectedNode := TempNode;
          end;
        end;
      finally
        Users.Free;
      end;
    end;
  finally
    FUpdating := False;
  end;

  FSelectedNode := SelectedNode;

  // First fill for this user since per-user state: record what it showed
  // (today's shared state) so it becomes theirs. Never a filtered fill:
  // a filter forces groups open.
  if (FVM.FilterText = '') and not FVM.TreeStateSeeded then
    SeedTreeState;
end;

procedure TframeProjectTree.SeedTreeState;
var
  N: PVirtualNode;
  Data: PNodeData;
begin
  N := Tree.GetFirst;
  while Assigned(N) do
  begin
    Data := Tree.GetNodeData(N);
    if Assigned(Data) then
      case Data.NodeType of
        ntProject: FVM.SetNodeExpanded(tnkProject, Data.Project.Id, Tree.Expanded[N]);
        ntFolder:  FVM.SetNodeExpanded(tnkFolder, Data.Folder.Id, Tree.Expanded[N]);
        ntGroup:   FVM.SetNodeExpanded(tnkGroup, Data.Group.Id, Tree.Expanded[N]);
        ntUser:    FVM.SetNodeExpanded(tnkUser, Data.User.Id, Tree.Expanded[N]);
      end;
    N := Tree.GetNext(N);
  end;
  FVM.MarkTreeStateSeeded;
end;

function TframeProjectTree.FindParentFolder(Root: PVirtualNode; ParentID: integer): PVirtualNode;
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Result := Nil;
  Node := Tree.GetFirstChild(Root);
  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntFolder) and (Data.Folder.ID = ParentID) then
    begin
      Result := Node;
      Break;
    end;
    Node := Tree.GetNext(Node, True);
  end;
end;

procedure WireButton(Btn: TRzToolButton; Act: TAction);
var
  SavedImg, SavedDis: Integer;
begin
  SavedImg := Btn.ImageIndex;
  SavedDis := Btn.DisabledIndex;
  Btn.Action := Act;
  Btn.ImageIndex := SavedImg;
  Btn.DisabledIndex := SavedDis;
end;

procedure TframeProjectTree.CreateActions;

  function AddAction(const ACaption: string; AOnExecute, AOnUpdate: TNotifyEvent): TAction;
  begin
    Result := TAction.Create(FActionList);
    Result.ActionList := FActionList;
    Result.Caption := ACaption;
    Result.Hint := ACaption;
    Result.OnExecute := AOnExecute;
    Result.OnUpdate := AOnUpdate;
  end;

begin
  // Build actions once: they are user-agnostic and their enabled state is driven
  // live by OnUpdate. Re-running each login would leak a duplicate TActionList.
  if Assigned(FActionList) then
    Exit;

  FActionList := TActionList.Create(Self);

  actNewProject   := AddAction('New Project',    BtnNewProjectClick,      actNonGuestUpdate);
  actNewTopicWiki := AddAction('New Wiki',       BtnNewTopicWikiClick,    actNonGuestUpdate);
  actNewFolder    := AddAction('New Folder',     BtnNewFolderClick,       actNonGuestUpdate);
  actNewGroup     := AddAction('New Group',      BtnNewGroupClick,        actNonGuestUpdate);
  actEdit         := AddAction('Edit',           btnEditItemClick,        actNonGuestUpdate);
  actArchive      := AddAction('Archive',        miProjectArchiveClick,   actNonGuestUpdate);
  actShare        := AddAction('Share...',       miProjectShareClick,     actShareUpdate);
  actHypotheses   := AddAction('Hypotheses...',  miProjectHypothesesClick, actHypothesesUpdate);
  actDelete       := AddAction('Delete',         btnDeleteItemClick,      actNonGuestUpdate);
  actRefresh      := AddAction('Refresh',        btnRefreshClick,         nil);
  actShowArchived := AddAction('Show Archived',  btnShowArchivedClick,    nil);

  // Wire toolbar buttons to actions (save/restore ImageIndex + DisabledIndex
  // because Action assignment overwrites them with the action's defaults)
  WireButton(BtnNewProject,    actNewProject);
  WireButton(BtnNewTopicWiki,  actNewTopicWiki);
  WireButton(BtnNewFolder,     actNewFolder);
  WireButton(btnEditItem,    actEdit);
  WireButton(btnDeleteItem,  actDelete);
  WireButton(btnRefresh,     actRefresh);
  WireButton(btnShowArchived, actShowArchived);
  WireButton(btnHypotheses,  actHypotheses);
end;

procedure TframeProjectTree.actNonGuestUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := Assigned(FVM) and not FVM.IsReadOnly;
end;

procedure TframeProjectTree.actShareUpdate(Sender: TObject);
begin
  (Sender as TAction).Visible := Assigned(FOnProjectPermissions);
  (Sender as TAction).Enabled := Assigned(FVM) and
    Assigned(FOnProjectPermissions) and not FVM.IsReadOnly;
end;

procedure TframeProjectTree.actHypothesesUpdate(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Ok: Boolean;
begin
  Ok := False;
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
  begin
    Data := Tree.GetNodeData(Node);
    Ok := Assigned(Data) and (Data.NodeType in [ntProject, ntFolder]);
  end;
  (Sender as TAction).Enabled := Ok;
end;

function TframeProjectTree.CanWriteToProject(ProjectId: Integer): Boolean;
begin
  Result := Assigned(FVM) and Assigned(Model) and
    Model.Access.CanWrite(Model.Manager, Model.User, ProjectId);
end;

procedure TframeProjectTree.Init;
begin
  ResetSession;
  edSearch.TextHint := 'Filter projects...';

  // Init runs every login cycle; free the previous session's VM before rebuilding
  // (nil on first call) so a logout -> re-login doesn't leak one per cycle.
  FreeAndNil(FVM);
  FVM := TProjectTreeVM.Create(
    Model.Projects, Model.Folders, Model.Favorites,
    Model.Authors, Model.History, Model.Items, Model.ProjectGroups);
  FVM.TreeState := Model.TreeState;

  CreateActions;
  LoadColumnWidths;

  if not Assigned(FLook) then
    FLook := TTreeLook.Create(Tree, RowColor,
      function(Node: PVirtualNode): Boolean
      var
        D: PNodeData;
      begin
        D := Tree.GetNodeData(Node);
        Result := Assigned(D) and (D.NodeType <> ntFavoriteItem);
      end,
      procedure(Node: PVirtualNode)
      begin
        TreeClick(Tree);   
      end);

  var Settings := TNotebookSettings.Create;
  try
    var Mode := Settings.LoadUIValue('ProjectTree', 'UserSortMode', 0);
    if (Mode >= Ord(Low(TUserSortMode))) and (Mode <= Ord(High(TUserSortMode))) then
      FUserSortMode := TUserSortMode(Mode)
    else
      FUserSortMode := usmManual;
  finally
    Settings.Free;
  end;
  Enabled := True;
  FActionList.State := asNormal;
  actRefresh.Enabled := True;
  actShowArchived.Enabled := True;

  btnLeft.Enabled := not FVM.IsReadOnly;
  if FVM.IsReadOnly then
    Tree.TreeOptions.MiscOptions := Tree.TreeOptions.MiscOptions - [toAcceptOLEDrop];

  FillTree;
end;

procedure TframeProjectTree.ScaleForDPI;

  function S(V: Integer): Integer;
  begin
    Result := MulDiv(V, Screen.PixelsPerInch, 192);
  end;

begin
  if Screen.PixelsPerInch = 192 then Exit;

  RzToolbar1.ButtonWidth  := S(50);
  RzToolbar1.ButtonHeight := S(50);
  RzToolbar1.RowHeight    := S(60);

  Tree.DefaultNodeHeight := S(44);
  Tree.Indent            := S(36);
end;

destructor TframeProjectTree.Destroy;
begin
  ResetSession;
  FLook.Free;   // before the tree goes: it restores the tree's WindowProc
  SaveColumnWidths;
  inherited;
end;

procedure TframeProjectTree.SaveColumnWidths;
var
  Settings: TNotebookSettings;
  I: Integer;
begin
  Settings := TNotebookSettings.Create;
  try
    for I := 0 to Tree.Header.Columns.Count - 1 do
      Settings.SaveUIValue('ProjectTree', 'ColWidth' + IntToStr(I),
        Tree.Header.Columns[I].Width);
  finally
    Settings.Free;
  end;
end;

procedure TframeProjectTree.LoadColumnWidths;
var
  Settings: TNotebookSettings;
  I, W: Integer;
begin
  Settings := TNotebookSettings.Create;
  try
    for I := 0 to Tree.Header.Columns.Count - 1 do
    begin
      W := Settings.LoadUIValue('ProjectTree', 'ColWidth' + IntToStr(I), 0);
      if W > 0 then
        Tree.Header.Columns[I].Width := W;
    end;
  finally
    Settings.Free;
  end;
end;

procedure TframeProjectTree.btnClearSearchClick(Sender: TObject);
begin
  edSearch.Text := '';
end;

procedure TframeProjectTree.edSearchChange(Sender: TObject);
begin
  FFilterText := edSearch.Text;
  FillTree(False);
  RestoreLastSelection;
end;

procedure TframeProjectTree.InsertFolder(const Folder: TFolder;
                                     Parent: PVirtualNode;
                                     ProjectID: integer;
                                     ProjectName: string);
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Node := Tree.AddChild(Parent);
  Data := Tree.GetNodeData(Node);

  Data.NodeType    := ntFolder;
  Data.Folder      := Folder;
  {$WARN IMPLICIT_STRING_CAST_LOSS OFF}
  Data.ProjectName := ProjectName;
  {$WARN IMPLICIT_STRING_CAST_LOSS ON}
  Data.ProjectID   := ProjectID;
end;

function TframeProjectTree.InsertProject(Parent: PVirtualNode; const Project: TProject): PVirtualNode;
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Node := Tree.AddChild(Parent);
  Data := Tree.GetNodeData(Node);

  Data.NodeType := ntProject;
  Data.Project:= Project;
  Result := Node;
end;

function TframeProjectTree.InsertGroup(Parent: PVirtualNode;
  const Group: TProjectGroup): PVirtualNode;
var
  Data: PNodeData;
begin
  Result := Tree.AddChild(Parent);
  Data := Tree.GetNodeData(Result);

  Data.NodeType := ntGroup;
  Data.Group := Group;
  Data.GroupOwnerId := Group.OwnerId;
end;

procedure TframeProjectTree.TreeClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  MessageManager: TMessageManager;
  Message: TMessage;
  Location: TLocation;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntGroup : begin
      lblTitle.Caption := Data.Group.Title;
      lblComment.Caption := '';
      lblDataFolder.Caption := '';
      lblCreated.Caption := '';
      lbModified.Caption := '';
      Exit;
    end;
    ntProject : begin
      Location.Path := Format('[%s]',[Data.Project.Title]);
      Location.ProjectID := Data.Project.ID;
      Location.FolderID := 0;
      Location.Access := FVM.GetProjectAccess(Data.Project.ID);
      FVM.SelectNode(Data.Project.ID, 0);
      DisplayProjectInfo(Data);
    end;
    ntFolder  : begin
      {$WARN IMPLICIT_STRING_CAST OFF}
      Location.Path := Format('%s',[Data.Folder.Path(Data.ProjectName)]);
      {$WARN IMPLICIT_STRING_CAST ON}
      Location.ProjectID := Data.ProjectID;
      Location.FolderID := Data.Folder.ID;
      Location.Access := FVM.GetProjectAccess(Data.ProjectID);
      FVM.SelectNode(Data.ProjectID, Data.Folder.ID);
      DisplayFolderInfo(Data);
    end;
    ntFavoriteItem: begin
      Location.ProjectID := Data.FavProjectId;
      if Data.FavFolderId > 0 then
      begin
        Location.FolderID := Data.FavFolderId;
        Location.Path := Format('Favorites > %s', [string(Data.FavTitle)]);
      end
      else
      begin
        Location.FolderID := 0;
        Location.Path := Format('Favorites > %s', [string(Data.FavTitle)]);
      end;
      Location.Access := FVM.GetProjectAccess(Data.FavProjectId);
      FVM.SelectNode(Data.FavProjectId, Location.FolderID);
      {$WARN IMPLICIT_STRING_CAST OFF}
      lblTitle.Caption := string(Data.FavTitle);
      {$WARN IMPLICIT_STRING_CAST ON}
      lblComment.Caption := '';
      lblDataFolder.Caption := '';
      lblCreated.Caption := '';
      lbModified.Caption := '';
    end;
    else
      Exit; 
  end;

  MessageManager := TMessageManager.DefaultManager;
  Message := TMessage<TLocation>.Create(Location);
  MessageManager.SendMessage(Sender, Message, True);
end;

procedure TframeProjectTree.DisplayFolderInfo(const Data: PNodeData);
begin
  lblTitle.Caption := Data.Folder.Title;
  lblComment.Caption := Data.Folder.Description;
  lblDataFolder.Caption := '';
  lblCreated.Caption := 'Created ' + DateToStr(Data.Folder.CreatedDate);
  if Data.Folder.ModifiedDate.HasValue then
    lbModified.Caption := 'Modified ' + DateToStr(Data.Folder.ModifiedDate)
  else
    lbModified.Caption := '';
end;

procedure TframeProjectTree.DisplayProjectInfo(const Data: PNodeData);
begin
  lblTitle.Caption := Data.Project.Title;
  lblComment.Caption := Data.Project.Description;
  lblDataFolder.Caption := CleanFileName(Data.Project.FileFolder);
  lblCreated.Caption := 'Created ' + DateToStr(Data.Project.CreatedDate);
  if Data.Project.ModifiedDate.HasValue then
    lbModified.Caption := 'Modified ' + DateToStr(Data.Project.ModifiedDate)
  else
    lbModified.Caption := '';
end;

procedure TframeProjectTree.TreeCollapsed(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
var
  Data: PNodeData;
begin
  if FUpdating or (not Assigned(Node)) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntProject: FVM.SetNodeExpanded(tnkProject, Data.Project.ID, False);
    ntFolder : FVM.SetNodeExpanded(tnkFolder, Data.Folder.ID, False);
    ntGroup  : FVM.SetNodeExpanded(tnkGroup, Data.Group.Id, False);
    ntUser   : FVM.SetNodeExpanded(tnkUser, Data.User.Id, False);
  end;
end;

procedure TframeProjectTree.TreeDblClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Title, Comment: string;
begin
  if FVM.IsReadOnly then Exit;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntProject: begin
                  if not FVM.CanEditProject(Data.Project.Id) then Exit;
                  Title := Data.Project.Title;
                  Comment := Data.Project.Description;
                  var Archived: Boolean := Data.Project.IsArchived;
                  if ShowProjectDialog(dmEdit, 'project', Title, Comment, @Archived) then
                  begin
                    FVM.UpdateProject(Data.Project, Title, Comment, Archived);
                    DisplayProjectInfo(Data);
                    Tree.InvalidateNode(Node);
                  end;
               end;
    ntFolder : begin
                  Title := Data.Folder.Title;
                  Comment := Data.Folder.Description;
                  if ShowProjectDialog(dmEdit, 'folder', Title, Comment) then
                  begin
                    FVM.UpdateFolder(Data.Folder, Title, Comment);
                    DisplayFolderInfo(Data);
                    Tree.InvalidateNode(Node);
                  end;
               end;
  end;
end;

procedure TframeProjectTree.TreeExpanded(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
var
  Data: PNodeData;
begin
  if FUpdating or (not Assigned(Node)) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntProject: FVM.SetNodeExpanded(tnkProject, Data.Project.ID, True);
    ntFolder : FVM.SetNodeExpanded(tnkFolder, Data.Folder.ID, True);
    ntGroup  : FVM.SetNodeExpanded(tnkGroup, Data.Group.Id, True);
    ntUser   : FVM.SetNodeExpanded(tnkUser, Data.User.Id, True);
  end;
end;

procedure TframeProjectTree.TreeFocusChanging(Sender: TBaseVirtualTree; OldNode,
  NewNode: PVirtualNode; OldColumn, NewColumn: TColumnIndex;
  var Allowed: Boolean);
begin
  Allowed := (NewColumn <= 0) or (NewColumn = 2);
end;

procedure TframeProjectTree.TreeFreeNode(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
begin
end;

procedure TframeProjectTree.TreeGetCellText(Sender: TCustomVirtualStringTree;
  var E: TVSTGetCellTextEventArgs);
var
  Data: PNodeData;
begin
  E.CellText := '';
  if not Assigned(E.Node) then Exit;

  Data := Sender.GetNodeData(E.Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntUser: begin
              case E.Column of
                0: E.CellText := Format( '%s %s ',[Data.User.FirstName, Data.User.LastName]);
              end;
            end;
    ntGroup: begin
              case E.Column of
                0: E.CellText := Data.Group.Title;
              end;
            end;
    ntProject: begin
        case E.Column of
          0: 
            begin
              E.CellText := Data.Project.Title;
              case FVM.GetProjectAccess(Data.Project.Id) of
                paReadOnly:  E.CellText := Format('%s [RO %s%s]', [E.CellText,
                  Copy(Data.Project.Owner.FirstName, 1, 1), Copy(Data.Project.Owner.LastName, 1, 1)]);
                paReadWrite: E.CellText := Format('%s [RW %s%s]', [E.CellText,
                  Copy(Data.Project.Owner.FirstName, 1, 1), Copy(Data.Project.Owner.LastName, 1, 1)]);
              end;
              if Sender.GetNodeLevel(E.Node) > 0 then
                E.StaticTextAlignment := TAlignment.taRightJustify;
            end;
          1: E.CellText := Data.Project.Description;
          2: E.CellText := DateToStr(Data.Project.CreatedDate);
        end;
    end;
    ntFolder: begin
        case E.Column of
          0: 
            begin
              E.CellText := Data.Folder.Title;
              if Sender.GetNodeLevel(E.Node) > 0 then
                E.StaticTextAlignment := TAlignment.taRightJustify;
            end;
          1: E.CellText := Data.Folder.Description;
          2: E.CellText := DateToStr(Data.Folder.CreatedDate);
        end;
    end;
    ntFavorites: begin
        case E.Column of
          0: E.CellText := 'Favorites';
        end;
    end;
    ntFavoriteItem: begin
        case E.Column of
          {$WARN IMPLICIT_STRING_CAST OFF}
          0: E.CellText := string(Data.FavTitle);
          {$WARN IMPLICIT_STRING_CAST ON}
        end;
    end;
  end;
end;

procedure TframeProjectTree.TreeGetImageIndexEx(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: TImageIndex;
  var ImageList: TCustomImageList);
var
  Data: PNodeData;
begin
  case Kind of
    ikNormal, ikSelected:
      begin
        case Column of
          -1, 
          0: begin
               Data := Sender.GetNodeData(Node);
               if Assigned(Data) then
               begin
                 case Data.NodeType of
                   ntUser:    ImageIndex := -1; 
                   ntGroup:   ImageIndex := 1; 
                   ntProject: ImageIndex := 0;
                   ntFolder:  ImageIndex := 1;
                   ntFavorites: ImageIndex := 2; 
                   ntFavoriteItem:
                     case Data.FavType of
                       ftProject: ImageIndex := 0;
                       ftFolder:  ImageIndex := 1;
                       ftItem:    ImageIndex := 0;
                     end;
                   else       ImageIndex := -1;
                 end;
               end;
          end;
          1: ;
        end;
      end;
    ikOverlay:
      begin
      end;
  end;
end;

procedure TframeProjectTree.TreeGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TNodeData);
end;

procedure TframeProjectTree.TreeGetPopupMenu(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; const P: TPoint;
  var AskParent: Boolean; var PopupMenu: TPopupMenu);
var
  Data: PNodeData;
begin
  PopupMenu := nil;
  if FVM.IsReadOnly then Exit;

  if not Assigned(Node) then
  begin
    FPendingGroupOwnerId := FVM.UserId;
    SyncSortUsersMenu;
    PopupMenu := pmRoot;
    Exit;
  end;

  Tree.FocusedNode := Node;
  Tree.Selected[Node] := True;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  CreateFavoriteMenuItems;

  case Data.NodeType of
    ntProject: begin
      var Access := FVM.GetProjectAccess(Data.Project.Id);
      miProjectArchive.Caption := IfThen(Data.Project.IsArchived, 'Unarchive', 'Archive');
      miProjectEdit.Enabled := (Access = paOwner);
      miProjectArchive.Enabled := (Access = paOwner);
      miProjectNewFolder.Enabled := FVM.CanAddFolder(Data.Project.Id);
      miProjectDelete.Enabled := (Access = paOwner);
      miProjectSort.Enabled := (Access = paOwner);
      miProjectShare.Visible := Assigned(FOnProjectPermissions) and
        ((Access = paOwner) or FVM.IsSupervisorMode);

      if FVM.IsFavorite(ftProject, Data.Project.Id, 0) then
        FmiAddFavorite.Caption := 'Remove from Favorites'
      else
        FmiAddFavorite.Caption := 'Add to Favorites';

      PopupMenu := pmProject;
    end;
    ntFolder: begin
      var FolderWritable := CanWriteToProject(Data.ProjectID);
      miFolderNewFolder.Enabled := FolderWritable;
      miFolderEdit.Enabled := FolderWritable;
      miFolderMoveUp.Enabled := FolderWritable;
      miFolderSort.Enabled := FolderWritable;
      miFolderDelete.Enabled := FolderWritable;

      if Assigned(FmiFolderAddFavorite) then
      begin
        if FVM.IsFavorite(ftFolder, Data.ProjectID, Data.Folder.Id) then
          FmiFolderAddFavorite.Caption := 'Remove from Favorites'
        else
          FmiFolderAddFavorite.Caption := 'Add to Favorites';
      end;

      PopupMenu := pmFolder;
    end;
    ntFavoriteItem: begin
      PopupMenu := FpmFavorite;
    end;
    ntUser: begin
      FPendingGroupOwnerId := Data.User.Id;
      SyncSortUsersMenu;
      PopupMenu := pmRoot;
    end;
    ntGroup: begin
      FPendingGroupOwnerId := Data.GroupOwnerId;
      PopupMenu := pmGroup;
    end;
  end;
end;


function TframeProjectTree.RowColor(Node: PVirtualNode): TColor;
var
  Data: PNodeData;
begin
  Result := ProjectKindColor(prkFolder);
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;
  case Data.NodeType of
    ntUser:
      Result := ProjectKindColor(prkUser);
    ntGroup:
      Result := ProjectKindColor(prkGroup);
    ntProject:
      if Assigned(Data.Project) and Data.Project.IsArchived then
        Result := ProjectKindColor(prkArchived)
      else
        Result := ProjectKindColor(prkProject);
    ntFavorites, ntFavoriteItem:
      Result := ProjectKindColor(prkFavorites);
  end;
end;

procedure TframeProjectTree.TreeBeforeCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
begin
  if Assigned(FLook) then
    FLook.BeforeCellPaint(TargetCanvas, Node, CellPaintMode, CellRect, ContentRect);
end;

procedure TframeProjectTree.TreeAfterCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  CellRect: TRect);
begin
  if Assigned(FLook) then
    FLook.AfterCellPaint(TargetCanvas, Node, Column, CellRect);
end;

procedure TframeProjectTree.TreePaintText(Sender: TBaseVirtualTree;
  const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  TextType: TVSTTextType);
var
  Data: PNodeData;
begin
  if not Assigned(Node) then Exit;
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  if (Column = 0) and (Data.NodeType in [ntUser, ntFavorites, ntGroup]) then
    TargetCanvas.Font.Style := [fsBold]
  else if Assigned(FLook) then
    FLook.PaintText(TargetCanvas, Node, Column);   

  if (Data.NodeType = ntUser) and Assigned(Data.User) and Data.User.IsArchived then
  begin
    TargetCanvas.Font.Color := clGray;
    TargetCanvas.Font.Style := TargetCanvas.Font.Style + [fsItalic];
  end;

  if (Data.NodeType = ntProject) then
  begin
    if Data.Project.IsArchived then
    begin
      TargetCanvas.Font.Color := clGray;
      TargetCanvas.Font.Style := TargetCanvas.Font.Style + [fsItalic];
    end
    else if FVM.GetProjectAccess(Data.Project.Id) in [paReadOnly, paReadWrite] then
      TargetCanvas.Font.Style := TargetCanvas.Font.Style + [fsItalic];
  end;
end;

procedure TframeProjectTree.TreeDrawText(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  const Text: string; const CellRect: TRect; var DefaultDraw: Boolean);
var
  Data: PNodeData;
  Count, BadgeW, Avail: Integer;
  FullText, BadgeText: string;
  TitleR: TRect;
  TitleFont: TFont;
  Badges: TBadgePainter;
  Color: TColor;
begin
  if Column <> 0 then Exit;
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntProject) or
     not Assigned(Data.Project) then Exit;
  Count := FVM.HypothesisCount(Data.Project.Id);
  if Count = 0 then Exit;
  if FVM.HypothesisWaiting(Data.Project.Id) > 0 then
    Color := BADGE_PLUM
  else
    Color := BADGE_TEAL;
  BadgeText := 'HYP ' + IntToStr(Count);
  FullText := (Sender as TVirtualStringTree).Text[Node, Column];

  TitleFont := TFont.Create;
  try
    TitleFont.Assign(TargetCanvas.Font);   
    Badges := TBadgePainter.Create(TargetCanvas,
      (Sender as TVirtualStringTree).Font, FLook.PPI,
      FLook.RowBackground(Node));
    try
      BadgeW := Badges.Width(BadgeText);
      Avail := CellRect.Width - BadgeW - Badges.Gap;
      if Avail < MulDiv(24, FLook.PPI, 96) then Exit;

      TargetCanvas.Font.Assign(TitleFont);
      TitleR := CellRect;
      TitleR.Right := CellRect.Left +
        Min(TargetCanvas.TextWidth(FullText) + 1, Avail);
      Winapi.Windows.DrawTextW(TargetCanvas.Handle, PWideChar(FullText),
        Length(FullText), TitleR,
        DT_NOPREFIX or DT_VCENTER or DT_SINGLELINE or DT_LEFT or DT_END_ELLIPSIS);
      DefaultDraw := False;

      Badges.DrawAt(TitleR.Right + Badges.Gap, CellRect, BadgeText, Color);
    finally
      Badges.Free;   
    end;
  finally
    TitleFont.Free;
  end;
end;

procedure TframeProjectTree.RefreshHypothesisBadges;
begin
  if not Assigned(FVM) then Exit;
  FVM.RefreshHypothesisBadges;
  Tree.Invalidate;
end;

procedure TframeProjectTree.TreeDragAllowed(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; var Allowed: Boolean);
var
  Data: PNodeData;
begin
  Data := Sender.GetNodeData(Node);
  Allowed := Assigned(Data) and (Data.NodeType in [ntFolder, ntProject, ntGroup]);

  // A read-only shared folder must not be a drag SOURCE: dragging it would
  // relocate its items+files out of a project the user cannot write to.
  if Allowed and (Data.NodeType = ntFolder) and
     not CanWriteToProject(Data.ProjectID) then
    Allowed := False;
end;

procedure TframeProjectTree.btnShowArchivedClick(Sender: TObject);
begin
  FShowArchived := not FShowArchived;
  btnShowArchived.Down := FShowArchived;
  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.btnRefreshClick(Sender: TObject);
begin
  if not Assigned(FVM) then Exit;
  FVM.EvictCache;
  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.WMDeferredFill(var Msg: Winapi.Messages.TMessage);
begin
  if not Assigned(FVM) then Exit;
  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.RestoreLastSelection;
begin
  if Assigned(FSelectedNode) then
  begin
    Tree.Selected[FSelectedNode] := True;
    TreeClick(Tree);
    FSelectedNode := nil; 
  end;
end;

procedure TframeProjectTree.SelectProject(ProjectId: Integer);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirst;
  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntProject) and (Data.Project.ID = ProjectId) then
    begin
      Tree.ClearSelection;
      Tree.Selected[Node] := True;
      Tree.FocusedNode := Node;
      Tree.ScrollIntoView(Node, True);
      TreeClick(Tree);
      Exit;
    end;
    Node := Tree.GetNext(Node);
  end;
end;

procedure TframeProjectTree.SelectFolder(FolderId: Integer);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirst;
  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntFolder) and (Data.Folder.ID = FolderId) then
    begin
      Tree.ClearSelection;
      Tree.Selected[Node] := True;
      Tree.FocusedNode := Node;
      Tree.ScrollIntoView(Node, True);
      TreeClick(Tree);
      Exit;
    end;
    Node := Tree.GetNext(Node);
  end;
end;


procedure TframeProjectTree.miProjectNewFolderClick(Sender: TObject);
begin
  BtnNewFolderClick(Sender);
end;

procedure TframeProjectTree.PromptNewGroup(OwnerId: Integer);
var
  Title: string;
begin
  Title := Trim(InputBox('New Group', 'Group name:', ''));
  if Title = '' then Exit;
  FVM.AddGroup(Title, OwnerId);
  FillTree;
end;

procedure TframeProjectTree.miRootNewGroupClick(Sender: TObject);
begin
  PromptNewGroup(FPendingGroupOwnerId);
end;

procedure TframeProjectTree.SyncSortUsersMenu;
begin
  miSortUsers.Visible := FVM.IsSupervisorMode;
  case FUserSortMode of
    usmById:   miSortUsersById.Checked := True;
    usmByName: miSortUsersByName.Checked := True;
  else
    miSortUsersManual.Checked := True;
  end;
end;

procedure TframeProjectTree.miSortUsersModeClick(Sender: TObject);
var
  Settings: TNotebookSettings;
begin
  FUserSortMode := TUserSortMode((Sender as TMenuItem).Tag);
  (Sender as TMenuItem).Checked := True;
  Settings := TNotebookSettings.Create;
  try
    Settings.SaveUIValue('ProjectTree', 'UserSortMode', Ord(FUserSortMode));
  finally
    Settings.Free;
  end;
  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.BtnNewGroupClick(Sender: TObject);
begin
  var OwnerUser := FindOwnerUser(Tree.GetFirstSelected);
  if Assigned(OwnerUser) then
    PromptNewGroup(OwnerUser.Id)
  else
    PromptNewGroup(FVM.UserId);
end;

procedure TframeProjectTree.miGroupNewProjectClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Title, Comment: string;
  Owner: TUser;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntGroup) then Exit;

  Owner := FVM.CurrentUser;
  var OwnerUser := FindOwnerUser(Node);
  if Assigned(OwnerUser) then
    Owner := OwnerUser;

  if ShowProjectDialog(dmNew, 'project', Title, Comment) then
  begin
    var Created := FVM.AddProject(Title, Comment, Owner);
    FVM.MoveProjectToGroup(Created.Id, Data.Group.Id);
    FillTree;
  end;
end;

procedure TframeProjectTree.miGroupRenameClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Title: string;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntGroup) then Exit;

  Title := Trim(InputBox('Rename Group', 'Group name:', Data.Group.Title));
  if (Title = '') or (Title = Data.Group.Title) then Exit;
  FVM.RenameGroup(Data.Group, Title);
  FillTree;
end;

procedure TframeProjectTree.miGroupDeleteClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntGroup) then Exit;

  if MessageDlg('Delete group "' + Data.Group.Title + '"?' + sLineBreak +
       'Projects in it move back to the top level; nothing else is deleted.',
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;

  FVM.DeleteGroup(Data.Group.Id);
  FillTree;
end;

procedure TframeProjectTree.miProjectEditClick(Sender: TObject);
begin
  TreeDblClick(Sender);
end;

procedure TframeProjectTree.miProjectArchiveClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntProject) then Exit;

  FVM.ToggleArchive(Data.Project);
  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.miProjectDeleteClick(Sender: TObject);
begin
  btnDeleteItemClick(Sender);
end;

procedure TframeProjectTree.miFolderNewFolderClick(Sender: TObject);
begin
  BtnNewFolderClick(Sender);
end;

procedure TframeProjectTree.miFolderEditClick(Sender: TObject);
begin
  TreeDblClick(Sender);
end;

procedure TframeProjectTree.miFolderMoveUpClick(Sender: TObject);
begin
  btnLeftClick(Sender);
end;

procedure TframeProjectTree.miFolderDeleteClick(Sender: TObject);
begin
  btnDeleteItemClick(Sender);
end;

procedure TframeProjectTree.miRefreshClick(Sender: TObject);
begin
  btnRefreshClick(Sender);
end;

procedure TframeProjectTree.miProjectCopyMCPLinkClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntProject) then Exit;
  Clipboard.AsText := Format('list_items(project_id: %d)', [Data.Project.Id]);
end;

procedure TframeProjectTree.miFolderCopyMCPLinkClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntFolder) then Exit;
  Clipboard.AsText := Format('list_items(project_id: %d, folder_id: %d)',
    [Data.ProjectID, Data.Folder.Id]);
end;

procedure TframeProjectTree.ReorderSiblings(SourceNode, TargetNode: PVirtualNode;
  Mode: TDropMode; NodeType: TNodeType);
var
  ParentNode, Node: PVirtualNode;
  Data: PNodeData;
  Ids: TList<Integer>;
  SourceId: Integer;
  InsertIdx: Integer;
  OrderedIds: TArray<Integer>;
begin
  ParentNode := TargetNode.Parent;

  Data := Tree.GetNodeData(SourceNode);
  case NodeType of
    ntProject: SourceId := Data.Project.Id;
    ntFolder:  SourceId := Data.Folder.Id;
    ntGroup:   SourceId := Data.Group.Id;
  else
    Exit;
  end;

  Ids := TList<Integer>.Create;
  try
    Node := Tree.GetFirstChild(ParentNode);
    while Assigned(Node) do
    begin
      Data := Tree.GetNodeData(Node);
      if Assigned(Data) and (Data.NodeType = NodeType) and (Node <> SourceNode) then
      begin
        case NodeType of
          ntProject: Ids.Add(Data.Project.Id);
          ntFolder:  Ids.Add(Data.Folder.Id);
          ntGroup:   Ids.Add(Data.Group.Id);
        end;
      end;
      Node := Tree.GetNextSibling(Node);
    end;

    Data := Tree.GetNodeData(TargetNode);
    var TargetId: Integer;
    case NodeType of
      ntProject: TargetId := Data.Project.Id;
      ntFolder:  TargetId := Data.Folder.Id;
      ntGroup:   TargetId := Data.Group.Id;
    else
      TargetId := -1;
    end;

    InsertIdx := Ids.IndexOf(TargetId);
    if InsertIdx < 0 then InsertIdx := Ids.Count;

    if Mode in [dmBelow, dmOnNode] then
      Inc(InsertIdx);

    Ids.Insert(InsertIdx, SourceId);

    OrderedIds := Ids.ToArray;
    case NodeType of
      ntProject: FVM.ReorderProjects(OrderedIds);
      ntFolder:  FVM.ReorderFolders(OrderedIds);
      ntGroup:   FVM.ReorderGroups(OrderedIds);
    end;
  finally
    Ids.Free;
  end;

  PostMessage(Handle, WM_DEFERRED_FILL, 0, 0);
end;


function TframeProjectTree.CollectSiblings(Node: PVirtualNode;
  out NodeType: TNodeType): TList<PVirtualNode>;
var
  Data, SibData: PNodeData;
  ParentNode, Sib: PVirtualNode;
begin
  Result := TList<PVirtualNode>.Create;
  NodeType := ntNone;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;
  NodeType := Data.NodeType;
  if not (NodeType in [ntProject, ntFolder]) then Exit;

  ParentNode := Node.Parent;
  Sib := Tree.GetFirstChild(ParentNode);
  while Assigned(Sib) do
  begin
    SibData := Tree.GetNodeData(Sib);
    if Assigned(SibData) and (SibData.NodeType = NodeType) then
      Result.Add(Sib);
    Sib := Tree.GetNextSibling(Sib);
  end;
end;

procedure TframeProjectTree.PersistSiblingOrder(NodeType: TNodeType;
  const Nodes: TList<PVirtualNode>);
var
  Ids: TArray<Integer>;
  I: Integer;
  Data: PNodeData;
begin
  SetLength(Ids, Nodes.Count);
  for I := 0 to Nodes.Count - 1 do
  begin
    Data := Tree.GetNodeData(Nodes[I]);
    if NodeType = ntProject then
      Ids[I] := Data.Project.Id
    else
      Ids[I] := Data.Folder.Id;
  end;

  if NodeType = ntProject then
    FVM.ReorderProjects(Ids)
  else
    FVM.ReorderFolders(Ids);

  PostMessage(Handle, WM_DEFERRED_FILL, 0, 0);
end;

procedure TframeProjectTree.MoveSibling(Direction: Integer);
var
  Node, Tmp: PVirtualNode;
  NodeType: TNodeType;
  Sibs: TList<PVirtualNode>;
  Idx: Integer;
begin
  if FVM.IsReadOnly then Exit;
  Node := Tree.GetFirstSelected;
  Sibs := CollectSiblings(Node, NodeType);
  try
    if not (NodeType in [ntProject, ntFolder]) then Exit;
    if Sibs.Count < 2 then Exit;
    Idx := Sibs.IndexOf(Node);
    if Idx < 0 then Exit;
    if (Idx + Direction < 0) or (Idx + Direction >= Sibs.Count) then Exit;

    Tmp := Sibs[Idx];
    Sibs[Idx] := Sibs[Idx + Direction];
    Sibs[Idx + Direction] := Tmp;
    PersistSiblingOrder(NodeType, Sibs);
  finally
    Sibs.Free;
  end;
end;

procedure TframeProjectTree.SortSiblings(SortByDate: Boolean);
var
  Node: PVirtualNode;
  NodeType: TNodeType;
  Sibs: TList<PVirtualNode>;
begin
  if FVM.IsReadOnly then Exit;
  Node := Tree.GetFirstSelected;
  Sibs := CollectSiblings(Node, NodeType);
  try
    if not (NodeType in [ntProject, ntFolder]) then Exit;
    if Sibs.Count < 2 then Exit;

    Sibs.Sort(TComparer<PVirtualNode>.Construct(
      function(const L, R: PVirtualNode): Integer
      var
        DL, DR: PNodeData;
        CL, CR: TDateTime;
      begin
        DL := Tree.GetNodeData(L);
        DR := Tree.GetNodeData(R);
        if SortByDate then
        begin
          if NodeType = ntProject then
          begin
            CL := DL.Project.CreatedDate;
            CR := DR.Project.CreatedDate;
          end
          else
          begin
            CL := DL.Folder.CreatedDate;
            CR := DR.Folder.CreatedDate;
          end;
          if CL < CR then
            Result := -1
          else if CL > CR then
            Result := 1
          else
            Result := 0;
        end
        else if NodeType = ntProject then
          Result := CompareText(DL.Project.Title, DR.Project.Title)
        else
          Result := CompareText(DL.Folder.Title, DR.Folder.Title);
      end));

    PersistSiblingOrder(NodeType, Sibs);
  finally
    Sibs.Free;
  end;
end;

procedure TframeProjectTree.miSortMoveUpClick(Sender: TObject);
begin
  MoveSibling(-1);
end;

procedure TframeProjectTree.miSortMoveDownClick(Sender: TObject);
begin
  MoveSibling(+1);
end;

procedure TframeProjectTree.miSortByNameClick(Sender: TObject);
begin
  SortSiblings(False);
end;

procedure TframeProjectTree.miSortByDateClick(Sender: TObject);
begin
  SortSiblings(True);
end;

procedure TframeProjectTree.TreeDragDrop(Sender: TBaseVirtualTree; Source: TObject;
    DataObject: TVTDragDataObject; Formats: TFormatArray; Shift: TShiftState;
    Pt: TPoint; var Effect: Integer; Mode: TDropMode);
var
  TargetNode, SourceNode: PVirtualNode;
  TargetData, SourceData: PNodeData;
var
  OldLoc: TLocation;
begin
  if (Source is TBaseVirtualTree) and (TBaseVirtualTree(Source).Owner is TframeItemTree) then
  begin
    var DraggedProc := TframeItemTree(TBaseVirtualTree(Source).Owner).DraggedProc;
    if not Assigned(DraggedProc) then Exit;

    TargetNode := Sender.GetNodeAt(Pt);
    if not Assigned(TargetNode) then Exit;
    TargetData := Sender.GetNodeData(TargetNode);
    if not Assigned(TargetData) then Exit;

    var NewProjectID, NewFolderID: Integer;
    if TargetData.NodeType = ntProject then
    begin
      NewProjectID := TargetData.Project.Id;
      NewFolderID  := 0;
    end
    else if TargetData.NodeType = ntFolder then
    begin
      NewProjectID := TargetData.ProjectID;
      NewFolderID  := TargetData.Folder.Id;
    end
    else
      Exit;

    if not CanWriteToProject(NewProjectID) then Exit;

    // Initialize Access too: ItemTree uses it to decide whether editing is allowed.
    OldLoc := Default(TLocation);
    OldLoc.ProjectID := DraggedProc.ProjectID;
    OldLoc.FolderID  := DraggedProc.FolderID;
    if OldLoc.FolderID < 0 then
      OldLoc.FolderID := 0;
    OldLoc.Path      := '';
    OldLoc.Access    := FVM.GetProjectAccess(DraggedProc.ProjectID);

    FVM.MoveProc(DraggedProc, NewProjectID, NewFolderID, Model.Relocator);
    FillTree;
    TMessageManager.DefaultManager.SendMessage(Self,
      TMessage<TLocation>.Create(OldLoc), True);
    Exit;
  end;

  TargetNode := Sender.GetNodeAt(Pt);
  if not Assigned(TargetNode) then
  begin
    SourceNode := TBaseVirtualTree(Source).GetFirstSelected;
    if not Assigned(SourceNode) then Exit;
    SourceData := TBaseVirtualTree(Source).GetNodeData(SourceNode);
    if Assigned(SourceData) and (SourceData.NodeType = ntProject) and
       SourceData.Project.GroupID.HasValue and
       Assigned(SourceData.Project.Owner) and
       ((SourceData.Project.Owner.Id = FVM.UserId) or FVM.IsSupervisorMode) then
    begin
      FVM.MoveProjectToGroup(SourceData.Project.Id, 0);
      PostMessage(Handle, WM_DEFERRED_FILL, 0, 0);
    end;
    Exit;
  end;

  SourceNode := TBaseVirtualTree(Source).GetFirstSelected;
  if not Assigned(SourceNode) then Exit;

  TargetData := Sender.GetNodeData(TargetNode);
  SourceData := TBaseVirtualTree(Source).GetNodeData(SourceNode);
  if (not Assigned(TargetData)) or (not Assigned(SourceData)) then Exit;

  if (SourceData.NodeType = ntProject) and (TargetData.NodeType = ntGroup) then
  begin
    if Assigned(SourceData.Project.Owner) and
       (SourceData.Project.Owner.Id = TargetData.GroupOwnerId) then
    begin
      FVM.MoveProjectToGroup(SourceData.Project.Id, TargetData.Group.Id);
      PostMessage(Handle, WM_DEFERRED_FILL, 0, 0);
    end;
    Exit;
  end;

  if (SourceData.NodeType = ntProject) and (TargetData.NodeType = ntUser) then
  begin
    if Assigned(SourceData.Project.Owner) and
       (SourceData.Project.Owner.Id = TargetData.User.Id) then
    begin
      FVM.MoveProjectToGroup(SourceData.Project.Id, 0);
      PostMessage(Handle, WM_DEFERRED_FILL, 0, 0);
    end;
    Exit;
  end;

  if (SourceData.NodeType = ntGroup) and (TargetData.NodeType = ntGroup)
    and (SourceNode.Parent = TargetNode.Parent) then
  begin
    ReorderSiblings(SourceNode, TargetNode, Mode, ntGroup);
    Exit;
  end;


  if (SourceData.NodeType = ntProject) and (TargetData.NodeType = ntProject)
    and (SourceNode.Parent = TargetNode.Parent) then
  begin
    ReorderSiblings(SourceNode, TargetNode, Mode, ntProject);
    Exit;
  end;

  if (SourceData.NodeType = ntFolder) and (TargetData.NodeType = ntFolder) then
  begin
    if (SourceNode.Parent = TargetNode.Parent) and (Mode <> dmOnNode) then
    begin
      ReorderSiblings(SourceNode, TargetNode, Mode, ntFolder);
      Exit;
    end;
    if not CanWriteToProject(TargetData.ProjectID) then Exit;
    FVM.MoveFolder(SourceData.Folder,
      SourceData.ProjectID, TargetData.ProjectID,
      TargetData.Folder.Id, Model.Relocator);
    PostMessage(Handle, WM_DEFERRED_FILL, 0, 0);
    Exit;
  end;

  if (SourceData.NodeType = ntFolder) and (TargetData.NodeType = ntProject) then
  begin
    if not CanWriteToProject(TargetData.Project.Id) then Exit;
    FVM.MoveFolder(SourceData.Folder,
      SourceData.ProjectID, TargetData.Project.Id, 0, Model.Relocator);
    PostMessage(Handle, WM_DEFERRED_FILL, 0, 0);
    Exit;
  end;

end;

procedure TframeProjectTree.miProjectShareClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntProject) then Exit;

  if Assigned(FOnProjectPermissions) and FOnProjectPermissions(Data.Project) then
  begin
    FillTree;
    RestoreLastSelection;
  end;
end;

procedure TframeProjectTree.miProjectHypothesesClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;
  if not Assigned(FOnOpenHypotheses) then Exit;
  case Data.NodeType of
    ntProject: FOnOpenHypotheses(Self, Data.Project.Id, 0);
    ntFolder:  FOnOpenHypotheses(Self, Data.ProjectID, 0);
  end;
end;

procedure TframeProjectTree.InsertFavorites;
var
  Favs: TList<TFavorite>;
  Fav: TFavorite;
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Favs := FVM.GetFavorites;
  try
    if Favs.Count = 0 then
      Exit;

    FFavoritesNode := Tree.AddChild(nil);
    Data := Tree.GetNodeData(FFavoritesNode);
    Data.NodeType := ntFavorites;

    for Fav in Favs do
    begin
      Node := Tree.AddChild(FFavoritesNode);
      Data := Tree.GetNodeData(Node);
      Data.NodeType := ntFavoriteItem;
      Data.FavId := Fav.Id;
      Data.FavProjectId := Fav.ProjectId;
      Data.FavFolderId := Fav.FolderId;
      Data.FavItemId := Fav.ItemId;
      Data.FavType := Fav.FavoriteType;
      {$WARN IMPLICIT_STRING_CAST_LOSS OFF}
      Data.FavTitle := Fav.Title;
      {$WARN IMPLICIT_STRING_CAST_LOSS ON}
    end;

    Tree.Expanded[FFavoritesNode] := True;
  finally
    Favs.Free;
  end;
end;

procedure TframeProjectTree.CreateFavoriteMenuItems;
begin
  if not Assigned(FpmFavorite) then
  begin
    FpmFavorite := TPopupMenu.Create(Self);
    FpmFavorite.Images := dmTreeImages.vilMenuImages;
    FmiRemoveFavorite := TMenuItem.Create(FpmFavorite);
    FmiRemoveFavorite.Caption := 'Remove from Favorites';
    FmiRemoveFavorite.ImageIndex := 58;
    FmiRemoveFavorite.OnClick := miRemoveFavoriteClick;
    FpmFavorite.Items.Add(FmiRemoveFavorite);
  end;

  if not Assigned(FmiAddFavorite) then
  begin
    var Sep := TMenuItem.Create(pmProject);
    Sep.Caption := '-';
    pmProject.Items.Add(Sep);

    FmiAddFavorite := TMenuItem.Create(pmProject);
    FmiAddFavorite.Caption := 'Add to Favorites';
    FmiAddFavorite.ImageIndex := 58;
    FmiAddFavorite.OnClick := miAddFavoriteClick;
    pmProject.Items.Add(FmiAddFavorite);

    var Sep2 := TMenuItem.Create(pmFolder);
    Sep2.Caption := '-';
    pmFolder.Items.Add(Sep2);

    FmiFolderAddFavorite := TMenuItem.Create(pmFolder);
    FmiFolderAddFavorite.Caption := 'Add to Favorites';
    FmiFolderAddFavorite.ImageIndex := 58;
    FmiFolderAddFavorite.OnClick := miAddFavoriteClick;
    pmFolder.Items.Add(FmiFolderAddFavorite);
  end;

  if not Assigned(FmiProjectAudit) then
  begin
    var Sep3 := TMenuItem.Create(pmProject);
    Sep3.Caption := '-';
    pmProject.Items.Add(Sep3);

    FmiProjectAudit := TMenuItem.Create(pmProject);
    FmiProjectAudit.Caption := 'Data Quality Check...';
    FmiProjectAudit.ImageIndex := 62;
    FmiProjectAudit.OnClick := DoProjectAudit;
    pmProject.Items.Add(FmiProjectAudit);

    var Sep4 := TMenuItem.Create(pmFolder);
    Sep4.Caption := '-';
    pmFolder.Items.Add(Sep4);

    FmiFolderAudit := TMenuItem.Create(pmFolder);
    FmiFolderAudit.Caption := 'Data Quality Check...';
    FmiFolderAudit.ImageIndex := 62;
    FmiFolderAudit.OnClick := DoFolderAudit;
    pmFolder.Items.Add(FmiFolderAudit);
  end;
end;

procedure TframeProjectTree.miRemoveFavoriteClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntFavoriteItem) then Exit;

  FVM.RemoveFavorite(Data.FavId);
  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.miAddFavoriteClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntProject:
      FVM.ToggleFavorite(ftProject, Data.Project.Id, 0, Data.Project.Title);
    ntFolder:
      FVM.ToggleFavorite(ftFolder, Data.ProjectID, Data.Folder.Id, Data.Folder.Title);
  end;

  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.DoProjectAudit(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.FocusedNode;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (Data = nil) or (Data.NodeType <> ntProject) then Exit;
  TdlgAuditReport.Execute(Data.Project.Id, 0, FOnAuditNavigate);
end;

procedure TframeProjectTree.DoFolderAudit(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.FocusedNode;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (Data = nil) or (Data.NodeType <> ntFolder) then Exit;
  TdlgAuditReport.Execute(Data.ProjectID, Data.Folder.Id, FOnAuditNavigate);
end;

procedure TframeProjectTree.RefreshFavorites;
begin
  FillTree;
  RestoreLastSelection;
end;

procedure TframeProjectTree.TreeDragOver(Sender: TBaseVirtualTree; Source: TObject;
    Shift: TShiftState; State: TDragState; Pt: TPoint; Mode: TDropMode; var
    Effect: Integer; var Accept: Boolean);
var
  TargetNode, SourceNode: PVirtualNode;
  TargetData, SourceData: PNodeData;
begin
  Accept := False;
  if not (Source is TBaseVirtualTree) then Exit;

  if TBaseVirtualTree(Source).Owner is TframeItemTree then
  begin
    if not Assigned(TframeItemTree(TBaseVirtualTree(Source).Owner).DraggedProc) then Exit;
    TargetNode := Sender.GetNodeAt(Pt);
    if not Assigned(TargetNode) then Exit;
    TargetData := Sender.GetNodeData(TargetNode);
    if (not Assigned(TargetData)) or
       not (TargetData.NodeType in [ntProject, ntFolder]) then Exit;
    if TargetData.NodeType = ntProject then
    begin
      if not CanWriteToProject(TargetData.Project.Id) then Exit;
    end
    else
      if not CanWriteToProject(TargetData.ProjectID) then Exit;
    Accept := True;
    Effect := DROPEFFECT_MOVE;
    Exit;
  end;

  TargetNode := Sender.GetNodeAt(Pt);

  SourceNode := TBaseVirtualTree(Source).GetFirstSelected;
  if not Assigned(SourceNode) then Exit;

  SourceData := TBaseVirtualTree(Source).GetNodeData(SourceNode);
  if not Assigned(SourceData) then Exit;

  // Empty-area drop: a dragged project returns to the root (ungrouped).
  // Only a project that IS grouped and that this user may manage (own project,
  // or any project in supervisor mode) — otherwise a shared-to-me project
  // would let a viewer clear the OWNER's grouping.
  if not Assigned(TargetNode) then
  begin
    if (SourceData.NodeType = ntProject) and
       SourceData.Project.GroupID.HasValue and
       Assigned(SourceData.Project.Owner) and
       ((SourceData.Project.Owner.Id = FVM.UserId) or FVM.IsSupervisorMode) then
    begin
      Accept := True;
      Effect := DROPEFFECT_MOVE;
    end;
    Exit;
  end;

  TargetData := Sender.GetNodeData(TargetNode);
  if not Assigned(TargetData) then Exit;

  if TargetNode = SourceNode then Exit;

  if (SourceData.NodeType = ntProject) and (TargetData.NodeType = ntGroup) then
  begin
    if Assigned(SourceData.Project.Owner) and
       (SourceData.Project.Owner.Id = TargetData.GroupOwnerId) then
    begin
      Accept := True;
      Effect := DROPEFFECT_MOVE;
    end;
    Exit;
  end;

  if (SourceData.NodeType = ntProject) and (TargetData.NodeType = ntUser) then
  begin
    if Assigned(SourceData.Project.Owner) and
       (SourceData.Project.Owner.Id = TargetData.User.Id) then
    begin
      Accept := True;
      Effect := DROPEFFECT_MOVE;
    end;
    Exit;
  end;

  if (SourceData.NodeType = ntGroup) and (TargetData.NodeType = ntGroup)
    and (SourceNode.Parent = TargetNode.Parent) then
  begin
    Accept := True;
    Effect := DROPEFFECT_MOVE;
    Exit;
  end;


  if (SourceData.NodeType = ntProject) and (TargetData.NodeType = ntProject) then
  begin
    if SourceNode.Parent = TargetNode.Parent then
    begin
      Accept := True;
      Effect := DROPEFFECT_MOVE;
      Exit;
    end;
  end;

  if (SourceData.NodeType = ntFolder) and (TargetData.NodeType = ntFolder) then
  begin
    if (SourceNode.Parent = TargetNode.Parent) and (Mode <> dmOnNode) then
    begin
      Accept := True;
      Effect := DROPEFFECT_MOVE;
      Exit;
    end;
    if Mode = dmOnNode then
    begin
      if Tree.HasAsParent(TargetNode, SourceNode) then Exit;
      if not CanWriteToProject(TargetData.ProjectID) then Exit;
      Accept := True;
      Effect := DROPEFFECT_MOVE;
      Exit;
    end;
  end;

  if (SourceData.NodeType = ntFolder) and (TargetData.NodeType = ntProject)
    and (Mode = dmOnNode) then
  begin
    if not CanWriteToProject(TargetData.Project.Id) then Exit;
    Accept := True;
    Effect := DROPEFFECT_MOVE;
  end;
 end;

end.
