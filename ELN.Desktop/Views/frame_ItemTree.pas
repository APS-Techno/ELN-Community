
unit frame_ItemTree;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ActiveX, System.SysUtils, System.Variants, System.Classes,
  System.Types, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  VirtualTrees.BaseAncestorVCL, VirtualTrees.BaseTree, VirtualTrees.AncestorVCL,
  VirtualTrees, VirtualTrees.Types, RzPanel, RzButton, RzSplit, Vcl.ExtCtrls, System.ImageList, Vcl.ImgList,
  System.UITypes,
  unit_Common,
  unit_TreeLook,
  unit_ProjectModel, unit_ProjectAccessPolicy,
  unit_ItemTreeVM,
  unit_ItemLinkModel,
  unit_HypothesesVM,
  System.Messaging,
  unit_ItemTypes,
  unit_Item,
  unit_ActionType,
  unit_Tag,
  unit_LabEntry,
  unit_Protocol,
  unit_FileType,
  Vcl.Menus,
  Vcl.StdCtrls,
  RzEdit,
  RzLabel,
  unit_ELNThumbnailList,
  frame_ContentViewer, Vcl.VirtualImageList,
  Vcl.Mask, System.Generics.Collections, System.Generics.Defaults, Vcl.ActnList,
  unit_PreviewQueue,
  unit_ELNPluginTypes,
  unit_NotebookSettings, System.Actions;

type
  TItemNavigateProc = procedure(Sender: TObject; ProjectId, FolderId, ItemId: Integer) of object;
  TPrepareItemFileEvent = function(FileId: Int64): string of object;

  TNodeType = (ntItem, ntAction, ntProtocol, ntFile);

  { NodeType determines the valid union field; all item levels use ntItem. }
  PNodeData = ^TNodeData;
  TNodeData = record
    case NodeType: TNodeType of
      ntItem: (Item : TItem);
      ntProtocol: (Protocol: TProtocol);
      ntFile: (AFile: TFile);
  end;

  PLinkNodeData = ^TLinkNodeData;
  TLinkNodeData = record
    LinkedItemId: Integer;
    LinkedProjectId: Integer;
    RelationText: string;
    Display: string;
    Notes: string;
    IsSource: Boolean;
    IsMoreRow: Boolean;
  end;


  TframeItemTree = class(TFrame)
    pnlBottom: TRzPanel;
    pnlMain: TRzPanel;
    pnlTitle: TRzPanel;
    lblPath: TRzLabel;
    lblName: TRzLabel;
    lblDetails: TRzLabel;
    pnlLinks: TRzPanel;
    pnlLinksHeader: TRzPanel;
    lblLinksCaption: TRzLabel;
    btnManageLinks: TButton;
    vstLinks: TVirtualStringTree;
    shpTypeBar: TShape;
    pmNew: TPopupMenu;
    miNewProc: TMenuItem;
    miNewItem: TMenuItem;
    miNewAction: TMenuItem;
    pmItem: TPopupMenu;
    miItemNew: TMenuItem;
    miItemNewFolder: TMenuItem;
    miItemSep1: TMenuItem;
    miItemEdit: TMenuItem;
    miItemDuplicate: TMenuItem;
    miItemMoveTo: TMenuItem;
    miItemSort: TMenuItem;
    miItemSortMoveUp: TMenuItem;
    miItemSortMoveDown: TMenuItem;
    miItemSortSep: TMenuItem;
    miItemSortByName: TMenuItem;
    miItemSortByDate: TMenuItem;
    miItemSep2: TMenuItem;
    miItemAdd: TMenuItem;
    miItemAddFile: TMenuItem;
    miItemAddNote: TMenuItem;
    miItemAddProtocol: TMenuItem;
    miItemAddValue: TMenuItem;
    miItemAnalyze:  TMenuItem;
    miItemSep3: TMenuItem;
    miItemHypothesis: TMenuItem;
    miItemAttachHypothesis: TMenuItem;
    miItemNewHypothesis: TMenuItem;
    miItemDelete: TMenuItem;
    miItemSep4: TMenuItem;
    miItemRegenPreviews: TMenuItem;
    miItemRefresh: TMenuItem;
    miItemSep5: TMenuItem;
    miItemCopyMCPLink: TMenuItem;
    pmProtocol: TPopupMenu;
    miProtocolEdit: TMenuItem;
    miProtocolSep1: TMenuItem;
    miProtocolDelete: TMenuItem;
    miProtocolSep2: TMenuItem;
    miProtocolRefresh: TMenuItem;
    miProtocolSep3: TMenuItem;
    miProtocolCopyMCPLink: TMenuItem;
    pmFile: TPopupMenu;
    miFileOpen: TMenuItem;
    miFileExport: TMenuItem;
    miFileReupload: TMenuItem;
    miFileMoveTo: TMenuItem;
    miFileEdit: TMenuItem;
    miFileExtractValues: TMenuItem;
    miFileSep1: TMenuItem;
    miFileDelete: TMenuItem;
    miFileSep2: TMenuItem;
    miFileCopyPath: TMenuItem;
    miFileSep3: TMenuItem;
    miFileRegenPreview: TMenuItem;
    miFileRefresh: TMenuItem;
    miFileSep4: TMenuItem;
    miFileCopyMCPLink: TMenuItem;
    RzPanel1: TRzPanel;
    pnlSearch: TRzPanel;
    Tree: TVirtualStringTree;
    RzPanel2: TRzPanel;
    RzToolbar1: TRzToolbar;
    BtnNewFolder: TRzToolButton;
    BtnNew: TRzToolButton;

    BtnAddFile: TRzToolButton;
    BtnAddNote: TRzToolButton;
    RzSpacer2: TRzSpacer;
    BtnEdit: TRzToolButton;
    BtnDuplicate: TRzToolButton;
    RzSpacer3: TRzSpacer;
    BtnDelete: TRzToolButton;
    btnAddProtocol: TRzToolButton;
    BtnAddValue: TRzToolButton;
    RzSpacer4: TRzSpacer;
    BtnExport: TRzToolButton;
    RzSpacer5: TRzSpacer;
    btnRefresh: TRzToolButton;
    RzSpacer6: TRzSpacer;
    btnExpandCollapse: TRzToolButton;
    btnClearSearch: TRzBitBtn;
    edSearch: TRzEdit;
    tmrStartup: TTimer;
    procedure BtnNewFolderClick(Sender: TObject);
    procedure BtnNewClick(Sender: TObject);
    procedure BtnAddFileClick(Sender: TObject);
    procedure BtnAddNoteClick(Sender: TObject);
    procedure BtnAddProtocolClick(Sender: TObject);
    procedure BtnAddValueClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure btnClearSearchClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnExpandCollapseClick(Sender: TObject);
    procedure edSearchChange(Sender: TObject);
    procedure TreeGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure TreeGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure TreeGetImageIndexEx(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Kind: TVTImageKind; Column: TColumnIndex; var Ghosted: Boolean;
      var ImageIndex: System.UITypes.TImageIndex; var ImageList: TCustomImageList);
    procedure TreeClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeDragAllowed(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; var Allowed: Boolean);
    procedure TreeDragOver(Sender: TBaseVirtualTree; Source: TObject;
      Shift: TShiftState; State: TDragState; Pt: TPoint; Mode: TDropMode;
      var Effect: Integer; var Accept: Boolean);
    procedure TreeDragDrop(Sender: TBaseVirtualTree; Source: TObject;
      DataObject: IDataObject; Formats: TFormatArray; Shift: TShiftState;
      Pt: TPoint; var Effect: Integer; Mode: TDropMode);
    procedure miNewProcClick(Sender: TObject);
    procedure miNewActionClick(Sender: TObject);
    procedure miNewItemClick(Sender: TObject);
    procedure BtnDuplicateClick(Sender: TObject);
    procedure BtnDeleteClick(Sender: TObject);
    procedure TreeAfterCellPaint(Sender: TBaseVirtualTree;
      TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      CellRect: TRect);
    procedure TreeBeforeCellPaint(Sender: TBaseVirtualTree;
      TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
    procedure TreePaintText(Sender: TBaseVirtualTree;
      const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType);
    procedure TreeGetPopupMenu(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; const P: TPoint; var AskParent: Boolean;
      var PopupMenu: TPopupMenu);
    procedure miItemNewClick(Sender: TObject);
    procedure miItemNewFolderClick(Sender: TObject);
    procedure miItemEditClick(Sender: TObject);
    procedure miItemDuplicateClick(Sender: TObject);
    procedure miItemAddFileClick(Sender: TObject);
    procedure miItemAddNoteClick(Sender: TObject);
    procedure miItemAddProtocolClick(Sender: TObject);
    procedure miItemAddValueClick(Sender: TObject);
    procedure miItemAnalyzeClick(Sender: TObject);
    procedure miItemMoveToClick(Sender: TObject);
    procedure miItemSortMoveUpClick(Sender: TObject);
    procedure miItemSortMoveDownClick(Sender: TObject);
    procedure miItemSortByNameClick(Sender: TObject);
    procedure miItemSortByDateClick(Sender: TObject);
    procedure miItemDeleteClick(Sender: TObject);
    procedure miItemAttachHypothesisClick(Sender: TObject);
    procedure miItemNewHypothesisClick(Sender: TObject);
    procedure miItemRefreshClick(Sender: TObject);
    procedure miItemRegenPreviewsClick(Sender: TObject);
    procedure miProtocolEditClick(Sender: TObject);
    procedure miProtocolDeleteClick(Sender: TObject);
    procedure miProtocolRefreshClick(Sender: TObject);
    procedure miFileOpenClick(Sender: TObject);
    procedure miFileExportClick(Sender: TObject);
    procedure miFileReuploadClick(Sender: TObject);
    procedure miFileMoveToClick(Sender: TObject);
    procedure miFileEditClick(Sender: TObject);
    procedure miFileExtractValuesClick(Sender: TObject);
    procedure miFileCopyPathClick(Sender: TObject);
    procedure miFileDeleteClick(Sender: TObject);
    procedure miFileRegenPreviewClick(Sender: TObject);
    procedure miFileRefreshClick(Sender: TObject);
    procedure miItemCopyMCPLinkClick(Sender: TObject);
    procedure miProtocolCopyMCPLinkClick(Sender: TObject);
    procedure miFileCopyMCPLinkClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure tmrStartupTimer(Sender: TObject);
    // Bound from the DFM, so these MUST stay in this implicitly published
    // section: DFM streaming resolves OnX = Handler through MethodAddress,
    // which only sees published RTTI. A private handler silently fails to bind.
    procedure btnManageLinksClick(Sender: TObject);
    procedure vstLinksGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure vstLinksGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure vstLinksGetHint(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; var LineBreakStyle: TVTTooltipLineBreakStyle;
      var HintText: string);
    procedure vstLinksNodeClick(Sender: TBaseVirtualTree;
      const HitInfo: THitInfo);
  private
    FFilterText: string;
    FThumbnailList: TELNThumbnailList;
    FRootPath : string;
    FItem: TItem;
    FLocation: TLocation;
    FContentViewer: TframeContentViewer;
    FPreviewSplitter: TRzSplitter;
    FCurrentFile: Int64;
    // Links backing the inline list; index-aligned with vstLinks rows except
    // for the trailing "+N more" row, which carries no index.
    FDetailLinks: TArray<TItemLinkInfo>;
    FDetailItemId: Integer;
    FDetailItemTitle: string;
    // pnlBottom's height with no links, captured from the live control on
    // first use so it already carries this monitor's DPI scaling.
    FDetailsBaseHeight: Integer;
    FSelectedNode: PVirtualNode;
    FNewItemParentID: Integer;
    FMessageRegistered: Boolean;
    FDraggedProc: TItem;
    FFileTypeIconIndex: TDictionary<Integer, Integer>; 
    FVM: TItemTreeVM;
    FFilling: Boolean;   // FillTree sets Expanded itself: not a user click
    FmiSignature: TMenuItem;
    FmiItemSign: TMenuItem;
    FmiItemViewSignature: TMenuItem;
    FmiItemVerifyIntegrity: TMenuItem;
    FmiItemBookmark: TMenuItem;
    FmiItemTags: TMenuItem;
    FmiItemComments: TMenuItem;
    FmiCopyLinkTarget: TMenuItem;
    FmiLinkTo: TMenuItem;
    FmiNewFromTemplate: TMenuItem;
    FTemplateMenuCreated: Boolean;
    FActionList: TActionList;
    FPreviewQueue: TPreviewQueue;
    FSessionCacheRoot: string;
    FLook: TTreeLook;
    FOnNavigateItem: TItemNavigateProc;
    FOnPrepareFile: TPrepareItemFileEvent;
    FOnOpenHypotheses: TOpenHypothesisEvent;
    FOnHypothesisDecisionsChanged: TNotifyEvent;
    procedure PreviewQueueStatus(const AText: string);
    procedure PreviewQueueUpdate(FileId: Int64; const APreviewPath: string);
    procedure PreviewQueueKeyValuesExtracted(ItemId: Integer;
      const KeyValues: TArray<TPluginKeyValue>);
    procedure SetStatusText(const AText: string);
    procedure actEditableUpdate(Sender: TObject);
    procedure actLinksUpdate(Sender: TObject);
    procedure actNonGuestUpdate(Sender: TObject);
    procedure CreateActions;
    procedure miNewFromTemplateClick(Sender: TObject);
    procedure BtnNewFromTemplateClick(Sender: TObject);
    procedure BtnReportClick(Sender: TObject);

    procedure BtnEditClick(Sender: TObject);
    procedure EditFileNode(AFile: TFile);
    procedure PrepareFilePopup;
    procedure ApplyAccessLevel;
    procedure UpdateFileButtons;
    procedure DoUpdateFile(Sender: TObject);
    procedure DoUpdatePreview(Sender: TObject);
    procedure DoExtractValues(Sender: TObject);
    procedure MessageListener(const Sender: TObject; const M: TMessage);
    procedure FillTree(const Location: TLocation);
    procedure TreeItemExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeItemCollapsed(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure SaveItemExpanded(Node: PVirtualNode; Value: Boolean);
    function InsertItem(const Parent: PVirtualNode; Item: TItem): PVirtualNode;
    function GetParentItem(const ID: integer): PVirtualNode;
    function InsertProtocol(const Protocol: TProtocol; Parent: PVirtualNode): PVirtualNode;
    function InsertFile(const AFile: TFile; Parent: PVirtualNode): PVirtualNode;
    procedure GetItemText(var E: TVSTGetCellTextEventArgs; Data: PNodeData);
    procedure GetFileText(var E: TVSTGetCellTextEventArgs; Data: PNodeData);
    procedure GetProtocolText(var E: TVSTGetCellTextEventArgs; Data: PNodeData);
    function GetParentItemFromNode(Node: PVirtualNode; out ParentID: Integer; out Levels: TItemLevels): Boolean;
    function IsTargetInSourceSubtree(Source, Target: TItem): Boolean;
    procedure ResolveNewItemParent;
    procedure SaveNewItemValues(Source, NewItem: TItem);
    function GetSelectedParentItem(out Item: TItem; out ActionType: TActionType): Boolean;
    procedure DisplayItemInfo(const Item: TItem);
    procedure DisplayProtocolView(const Protocol: TProtocol);
    procedure DisplayNotePreview(const Protocol: TProtocol);
    procedure DisplayFileInfo(const AFile: TFile);
    procedure LoadFileIcons;
    function PrepareFile(FileId: Int64): string;
    function GetPreviewPath(const ActionID: Integer; const FileID: Int64): string;
    function MaterializeFilePreview(const ActionID: Integer; const FileID: Int64): string;
    procedure CollectFilePreviews(Node: PVirtualNode);
    procedure QueueRegenFile(AFile: TFile; ParentItem: TItem;
      var Queue: TArray<TPreviewQueueItem>; var Skipped: Integer);
    procedure CollectRegenFiles(Node: PVirtualNode; Recurse: Boolean;
      var Queue: TArray<TPreviewQueueItem>; var Skipped: Integer);
    function FindProcNode(Node: PVirtualNode): PVirtualNode;
    procedure DisplayPreviewsForScope(ItemNode: PVirtualNode; Item: TItem);
    function GetRootItems: TItems;
    procedure MoveRootItem(Direction: Integer);
    procedure SortRootItems(AComparer: IComparer<TItem>);
    procedure CreateSignatureMenuItems;
    procedure miItemSignClick(Sender: TObject);
    procedure miItemViewSignatureClick(Sender: TObject);
    procedure miItemVerifyIntegrityClick(Sender: TObject);
    procedure miItemBookmarkClick(Sender: TObject);
    procedure miItemTagsClick(Sender: TObject);
    procedure miItemCommentsClick(Sender: TObject);
    procedure miItemLinksClick(Sender: TObject);
    procedure miCopyLinkTargetClick(Sender: TObject);
    procedure miLinkToClick(Sender: TObject);
    procedure pmItemPopup(Sender: TObject);
    procedure FillLinksPanel(ItemId: Integer);
    procedure CreateTemplateMenuItem;
    procedure UpdateInfoColors(AColor: TColor);
    function RowColor(Node: PVirtualNode): TColor;
    procedure SaveColumnWidths;
    procedure LoadColumnWidths;
  public
    actNew: TAction;
    actNewProc: TAction;
    actNewItem: TAction;
    actNewAction: TAction;
    actNewFromTemplate: TAction;
    actAddFile: TAction;
    actAddNote: TAction;
    actAddProtocol: TAction;
    actAddValue: TAction;
    actEdit: TAction;
    actDuplicate: TAction;
    actExport: TAction;
    actReport: TAction;
    actDelete: TAction;
    actRefresh: TAction;
    actLinks: TAction;
    destructor Destroy; override;
    constructor Create(AOwner: TComponent); override;
    procedure DisplayFilePreviews(const ActionID: integer; Files: TFiles);
    procedure RegisterMessage;
    procedure Init(AThumbnailList: TELNThumbnailList; AContentViewer: TframeContentViewer;
      APreviewSplitter: TRzSplitter);
    procedure SetShowItemIDs(Value: Boolean);
    procedure RefreshInfoColors;
    procedure Clear;
    procedure ResetSession;
    procedure RestoreLastSelection;
    /// <summary>Reloads the tree (fresh HYP badges after the Hypotheses view
    /// attached or removed a run) and re-selects the last node WITHOUT
    /// clicking it, so the content viewer keeps showing what it shows.
    /// btnRefreshClick re-clicks the node, which replaces the viewer.</summary>
    procedure RefreshKeepView;
    procedure ScaleForDPI;
    procedure SelectItem(ItemId: Integer);
    function SelectedItemId: Integer;
    // Selects the file node, or its owner when file children are hidden.
    // False for an owner-only selection: tree file commands require a file node.
    function SelectFile(FileId: Int64): Boolean;
    procedure ShowFilePopup(FileId: Int64);
    property DraggedProc: TItem read FDraggedProc;
    property OnPrepareFile: TPrepareItemFileEvent read FOnPrepareFile write FOnPrepareFile;
    property OnNavigateItem: TItemNavigateProc read FOnNavigateItem write FOnNavigateItem;
    property OnOpenHypotheses: TOpenHypothesisEvent read FOnOpenHypotheses write FOnOpenHypotheses;
    property OnHypothesisDecisionsChanged: TNotifyEvent
      read FOnHypothesisDecisionsChanged write FOnHypothesisDecisionsChanged;
  end;

implementation

uses
  unit_TreeBadges,
  unit_Helpers,
  unit_DataModel,
  unit_User,
  System.Rtti,
  System.TypInfo,
  unit_PreviewMessages,
  dlg_Project,
  dlg_Item,
  dlg_ItemMove,
  dlg_Action,
  dlg_File,
  dlg_FileEdit,
  editor_Protocols,
  dlg_Note,
  unit_DlgConstants,
  unit_Template,
  unit_ValueTypeModel,
  dlg_ProtocolTemplateSelect,
  dlg_PackageExport,
  dlg_ReportExport,
  frm_Analysis,
  dlg_Value,
  unit_PackageExport,
  System.StrUtils,
  System.Threading,
  unit_AuditLog,
  Aurelius.Engine.ObjectManager,
  dlg_Sign,
  dlg_SignatureView,
  unit_SignatureModel,
  unit_Favorite,
  unit_FavoritesModel,
  dlg_TagManager,
  dlg_Comments,
  dlg_LinkManager,
  dlg_LinkRelation,
  unit_LinkClipboard,
  dlg_ItemPicker,
  dlg_ExperimentTemplate,
  dlg_NewFromTemplate,
  unit_ExperimentTemplateModel,
  unit_WikiSeeder,
  unit_Comment,
  unit_CommentModel,
  Vcl.Imaging.PngImage,
  System.JSON,
  Vcl.Clipbrd,
  unit_ValueType,
  unit_ELNPluginCore,
  dlg_ExtractValues,
  dm_TreeImages,
  Vcl.Themes,
  System.Math,
  unit_TimeHelper,
  unit_Hypothesis,
  unit_HypothesisModel,
  dlg_HypothesisPick,
  dlg_HypothesisEdit,
  unit_TreeAppearance, System.IOUtils, Aurelius.Drivers.Interfaces,
  unit_ItemModel, unit_Project, unit_AuditHelper;
{$R *.dfm}

const
  CDefaultColor  = $00808080;  


function HexToColor(const S: string): TColor;
var
  Hex: string;
begin
  Hex := Trim(S);
  if (Length(Hex) > 0) and (Hex[1] = '#') then
    Hex := '$' + Copy(Hex, 2, Length(Hex) - 1);
  if Hex = '' then
    Result := clBlue
  else
    Result := TColor(StrToIntDef(Hex, Integer(clBlue)));
end;

procedure TframeItemTree.PreviewQueueStatus(const AText: string);
begin
  SetStatusText(AText);
end;

procedure TframeItemTree.PreviewQueueUpdate(FileId: Int64; const APreviewPath: string);
begin
  FThumbnailList.Update(FileId, APreviewPath);
end;

procedure TframeItemTree.PreviewQueueKeyValuesExtracted(ItemId: Integer;
  const KeyValues: TArray<TPluginKeyValue>);
var
  KV: TPluginKeyValue;
  VT: TValueType;
  Item: TItem;
  RecType: TRecType;
begin
  Item := Model.Items.GetItem(ItemId);
  if Item = nil then
    Exit;
  if not Model.Access.CanWrite(Model.Manager, Model.User, Item.ProjectID) then Exit;

  for KV in KeyValues do
  begin
    if not KV.IsKey then
      Continue;

    VT := Model.ValueTypes.FindByTitleUnits(KV.Name, KV.Units);
    if VT = nil then
      Continue;

    if KV.RecType = prResult then
      RecType := TEST_RESULT
    else
      RecType := EXP_CONDITION;

    Model.Items.AddValue(VT, RecType, KV.Value, FVM.UserId, Item,
      0, KV.Description);
  end;
end;

procedure TframeItemTree.SetStatusText(const AText: string);
begin
  TMessageManager.DefaultManager.SendMessage(Self,
    System.Messaging.TMessage<string>.Create(AText));
end;

procedure TframeItemTree.DoUpdatePreview(Sender: TObject);
var
  PreviewPath: string;
  Bmp: TBitmap;
  Png: TPngImage;
begin
  if not Assigned(FVM) or not FVM.CanEdit or not Assigned(FItem) then Exit;
  if (FCurrentFile <= 0) or not Assigned(FContentViewer) or
    not FContentViewer.IsFileDisplayed(FCurrentFile) then Exit;
  PreviewPath := GetPreviewPath(FItem.Id, FCurrentFile);
  ForceDirectories(ExtractFilePath(PreviewPath));

  Bmp := FContentViewer.GetPreview(400, 300);
  if Assigned(Bmp) then
  begin
    Png := TPngImage.Create;
    try
      Png.Assign(Bmp);
      Png.SaveToFile(PreviewPath);
    finally
      Png.Free;
      Bmp.Free;
    end;
  end
  else
    SaveScreenshot(PreviewPath, FContentViewer);

  Model.Storage.CopyIn(PreviewPath,
    Format('previews/[1000]/%.*d_%.*d.png', [5, FItem.Id, 5, FCurrentFile]));

  FThumbnailList.Update(FCurrentFile, PreviewPath);
end;

procedure TframeItemTree.BtnNewFolderClick(Sender: TObject);
var
  Title, Comment: string;
  Node: PVirtualNode;
  Data: PNodeData;
  ParentID: Integer;
begin
  if FLocation.ProjectID <= 0 then Exit;

  ParentID := 0;
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntItem) and
       (Data.Item.Level in [TItemLevel.Proc, TItemLevel.Folder]) then
      ParentID := Data.Item.Id;
  end;

  if ShowProjectDialog(dmNew, 'folder', Title, Comment) then
  begin
    var NewItem := Model.Items.AddItem(TItemType.Other, Title, TItemLevel.Folder, ParentID, '', nil, nil, Model.User.Id);
    FVM.SelectItem(NewItem.Id, 0);
    FillTree(FLocation);
    RestoreLastSelection;
  end;
end;

procedure TframeItemTree.BtnNewClick(Sender: TObject);
var
  Item: TItem;
  Node: PVirtualNode;
  ParentID: Integer;
  Levels: TItemLevels;
begin
  if FLocation.ProjectID <= 0 then Exit;

  ParentID := 0;
  Levels := [TItemLevel.Proc, TItemLevel.Item];

  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
    GetParentItemFromNode(Node, ParentID, Levels);
  Include(Levels, TItemLevel.Proc); 

  if not (Levels <= [TItemLevel.Proc]) and not (Levels <= [TItemLevel.Item])
     and not (Levels <= [TItemLevel.Action]) then
  begin
    FNewItemParentID := ParentID;
    miNewProc.Visible   := TItemLevel.Proc   in Levels;
    miNewItem.Visible   := TItemLevel.Item   in Levels;
    miNewAction.Visible := TItemLevel.Action in Levels;
    CreateTemplateMenuItem;
    FmiNewFromTemplate.Visible := TItemLevel.Proc in Levels;
    pmNew.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
    Exit;
  end;

  if TItemLevel.Item in Levels then
  begin
    Item := TItem.Create;
    try
      if ShowItemDialog(dmNew, Item) then
      begin
        var NewItem := Model.Items.AddItem(Item.Type_, Item.Title, Item.Level, ParentID,
                                Item.Description, Item.ActionType, nil, Model.User.Id);
        FVM.SelectItem(NewItem.Id, 0);
        FillTree(FLocation);
        RestoreLastSelection;
      end;
    finally
      Item.Free;
    end;
    Exit;
  end;

  Item := TItem.Create;
  try
    if ShowActionDialog(dmNew, Item, Levels) then
    begin
      var NewItem := Model.Items.AddItem(Item.Type_, Item.Title, Item.Level, ParentID,
                              Item.Description, Item.ActionType, Item.Equipment,
                              Model.User.Id, Item.Properties);
      SaveNewItemValues(Item, NewItem);
      FVM.SelectItem(NewItem.Id, 0);
      FillTree(FLocation);
      RestoreLastSelection;
    end;
  finally
    Item.Free;
  end;
end;

procedure TframeItemTree.ResolveNewItemParent;
var
  Node: PVirtualNode;
  ParentID: Integer;
  Levels: TItemLevels;
begin
  ParentID := 0;
  Levels := [];
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
    GetParentItemFromNode(Node, ParentID, Levels);
  FNewItemParentID := ParentID;
end;

procedure TframeItemTree.SaveNewItemValues(Source, NewItem: TItem);
var
  V: unit_Item.TValue;
begin
  for V in Source.Values do
    Model.Items.AddValue(V.ValueType, V.RecType, V.Value, Model.User.Id,
      NewItem, V.Tol, V.Description);
end;

procedure TframeItemTree.miNewProcClick(Sender: TObject);
var
  Item: TItem;
begin
  if FLocation.ProjectID <= 0 then Exit;
  Item := TItem.Create;
  try
    if ShowActionDialog(dmNew, Item, [TItemLevel.Proc]) then
    begin
      var NewItem := Model.Items.AddItem(Item.Type_, Item.Title, Item.Level, 0,
                              Item.Description, Item.ActionType, Item.Equipment,
                              Model.User.Id, Item.Properties);
      SaveNewItemValues(Item, NewItem);
      FVM.SelectItem(NewItem.Id, 0);
      FillTree(FLocation);
      RestoreLastSelection;
    end;
  finally
    Item.Free;
  end;
end;

procedure TframeItemTree.miNewActionClick(Sender: TObject);
var
  Item: TItem;
begin
  if FLocation.ProjectID <= 0 then Exit;
  ResolveNewItemParent;
  Item := TItem.Create;
  try
    if ShowActionDialog(dmNew, Item, [TItemLevel.Action]) then
    begin
      var NewItem := Model.Items.AddItem(Item.Type_, Item.Title, Item.Level, FNewItemParentID,
                              Item.Description, Item.ActionType, Item.Equipment,
                              Model.User.Id, Item.Properties);
      SaveNewItemValues(Item, NewItem);
      FVM.SelectItem(NewItem.Id, 0);
      FillTree(FLocation);
      RestoreLastSelection;
    end;
  finally
    Item.Free;
  end;
end;

procedure TframeItemTree.miNewItemClick(Sender: TObject);
var
  Item: TItem;
begin
  if FLocation.ProjectID <= 0 then Exit;
  ResolveNewItemParent;
  Item := TItem.Create;
  try
    if ShowItemDialog(dmNew, Item) then
    begin
      var NewItem := Model.Items.AddItem(Item.Type_, Item.Title, Item.Level, FNewItemParentID,
                              Item.Description, Item.ActionType, nil, Model.User.Id);

      if Item.Type_ = TItemType.Wiki then
        unit_WikiSeeder.WriteReadmeContent(NewItem, Model.User.Id,
          '# ' + NewItem.Title + #10#10,
          NewItem.Title);

      FVM.SelectItem(NewItem.Id, 0);
      FillTree(FLocation);
      RestoreLastSelection;
    end;
  finally
    Item.Free;
  end;
end;

function NextSampleTitle(const Title: string): string;
var
  Len, Pos: Integer;
  Suffix: string;
begin
  if Length(Title) = 0 then
    Exit('B');

  Len := Length(Title);
  Suffix := '';

  Pos := Len;
  while (Pos > 0) and CharInSet(Title[Pos], [')', ']']) do
  begin
    Suffix := Title[Pos] + Suffix;
    Dec(Pos);
  end;

  if (Pos > 0) and CharInSet(Title[Pos], ['A'..'Y']) then
    Result := Copy(Title, 1, Pos - 1) + Char(Ord(Title[Pos]) + 1) + Suffix
  else if (Pos > 0) and (Title[Pos] = 'Z') then
    Result := Copy(Title, 1, Pos - 1) + 'AA' + Suffix
  else
    Result := Copy(Title, 1, Pos) + 'B' + Suffix;
end;

procedure TframeItemTree.BtnDuplicateClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Src: TItem;
  Dest: TDuplicateResult;
  NewItem: TItem;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  Src := Data.Item;
  if Src.Level = TItemLevel.Folder then Exit;

  if not TdlgItemPicker.ExecuteDuplicate(Src.Id, Dest) then Exit;

  NewItem := FVM.DuplicateItem(Src, Dest.ProjectId, Dest.FolderId,
    Dest.ParentItemId, NextSampleTitle(Src.Title), Dest.LinkToOriginal);
  if not Assigned(NewItem) then Exit; 

  if (Dest.ProjectId = FLocation.ProjectID) and
     (Dest.FolderId = FLocation.FolderID) then
  begin
    FVM.SelectItem(NewItem.Id, 0);
    FillTree(FLocation);
    RestoreLastSelection;
  end;
end;

procedure TframeItemTree.BtnDeleteClick(Sender: TObject);
var
  Node, ParentNode: PVirtualNode;
  Data, ParentData: PNodeData;
  Item, ParentItem: TItem;
  FileId: Int64;
  ItemId: Integer;
  StoragePath, PreviewLocal, PreviewStorage: string;
  Blocker: string;
begin
  if not Assigned(FVM) or not FVM.CanEdit then Exit;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntItem:
    begin
      Item := Data.Item;
      Blocker := Model.Items.FindDeleteBlocker(Item);
      if Blocker <> '' then
      begin
        MessageDlg(Blocker, mtWarning, [mbOK], 0);
        Exit;
      end;
      if MessageDlg(Format('Move item "%s" to the recycle bin?', [Item.Title]),
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
        Exit;
      if not Model.Items.SoftDeleteItemTree(Item, Model.User.Id) then
      begin
        MessageDlg(Format('Failed to delete item "%s". The record may have been modified ' +
          'by another session. Please refresh and try again.', [Item.Title]),
          mtError, [mbOK], 0);
        Exit;
      end;
      FVM.SelectItem(0, 0);
    end;

    ntFile:
    begin
      ParentNode := Tree.NodeParent[Node];
      if not Assigned(ParentNode) then Exit;
      ParentData := Tree.GetNodeData(ParentNode);
      if not Assigned(ParentData) or (ParentData.NodeType <> ntItem) then Exit;
      ParentItem := ParentData.Item;
      if FVM.IsItemSigned(ParentItem.Id) then Exit;
      if MessageDlg(Format('Delete file "%s"?', [Data.AFile.Title]),
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
        Exit;

      // Resolve paths before DB delete (entity must still exist)
      FileId := Data.AFile.Id;
      ItemId := ParentItem.Id;
      StoragePath := StringReplace(Model.GetFileName(FileId), '\', '/', [rfReplaceAll]);
      PreviewLocal := GetPreviewPath(ItemId, FileId);
      PreviewStorage := Format('previews/[1000]/%.*d_%.*d.png', [5, ItemId, 5, FileId]);
      if not Model.Items.RemoveFile(Data.AFile, ParentItem, Model.User.Id) then
      begin
        MessageDlg('The file was not deleted. It may be signed or changed by another session.',
          mtWarning, [mbOK], 0);
        Exit;
      end;
      Model.Storage.DeleteFile(StoragePath);
      Model.Storage.DeleteFile(PreviewStorage);
      System.SysUtils.DeleteFile(PreviewLocal);

      FVM.SelectItem(ParentItem.Id, 0);
    end;

    ntProtocol:
    begin
      ParentNode := Tree.NodeParent[Node];
      if not Assigned(ParentNode) then Exit;
      ParentData := Tree.GetNodeData(ParentNode);
      if not Assigned(ParentData) or (ParentData.NodeType <> ntItem) then Exit;
      ParentItem := ParentData.Item;
      if MessageDlg(Format('Delete "%s"?', [Data.Protocol.Title]),
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
        Exit;
      FVM.DeleteEntry(Data.Protocol, ParentItem);
      FVM.SelectItem(ParentItem.Id, 0);
    end;
  else
    Exit;
  end;

  FillTree(FLocation);
  RestoreLastSelection;
end;

procedure TframeItemTree.BtnAddNoteClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  NewProtocol: TProtocol;
  ParentItem: TItem;
  Added: Boolean;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then
  begin
    ShowMessage('Please select an item to add a note to.');
    Exit;
  end;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  ParentItem := nil;
  case Data.NodeType of
    ntItem: ParentItem := Data.Item;
    ntProtocol, ntFile:
      begin
        Node := Tree.NodeParent[Node];
        if Assigned(Node) then
        begin
          Data := Tree.GetNodeData(Node);
          if Assigned(Data) and (Data.NodeType = ntItem) then
            ParentItem := Data.Item;
        end;
      end;
  end;

  if not Assigned(ParentItem) then
  begin
    ShowMessage('Could not find parent item. Please select an item.');
    Exit;
  end;
  if not FVM.CanEdit or IsItemSignedCheck(Model.Manager, ParentItem.Id) then Exit;

  NewProtocol := TProtocol.Create;
  Added := False;
  try
    NewProtocol.Title := 'New Note';
    NewProtocol.ProtocolType := ptNote;
    NewProtocol.ValidationStatus := vsDraft;
    NewProtocol.FormData := '';
    NewProtocol.CreatedDate := UTCNow;
    NewProtocol.CreatedBy := FVM.UserId;

    if TdlgNote.Execute(NewProtocol) then
      Added := FVM.AddNote(NewProtocol, ParentItem);
    if Added then
    begin
      Model.RecordAudit(aetNote, NewProtocol.Id, aoCreate,
        'Added note "' + NewProtocol.Title + '" to item "' + ParentItem.Title + '"');
      FVM.SelectItem(ParentItem.Id, NewProtocol.Id);
      FillTree(FLocation);
      RestoreLastSelection;
    end;
  finally
    if not Added then
      NewProtocol.Free;
  end;
end;

procedure TframeItemTree.BtnAddProtocolClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  NewProtocol: TProtocol;
  ParentItem: TItem;
  SelectedTemplate: TTemplate;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then
  begin
    ShowMessage('Please select an item to add a protocol to.');
    Exit;
  end;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  ParentItem := nil;
  case Data.NodeType of
    ntItem: ParentItem := Data.Item;
    ntProtocol, ntFile:
      begin
        Node := Tree.NodeParent[Node];
        if Assigned(Node) then
        begin
          Data := Tree.GetNodeData(Node);
          if Assigned(Data) and (Data.NodeType = ntItem) then
            ParentItem := Data.Item;
        end;
      end;
  end;

  if not Assigned(ParentItem) then
  begin
    ShowMessage('Could not find parent item. Please select an item.');
    Exit;
  end;
  if not FVM.CanEdit or IsItemSignedCheck(Model.Manager, ParentItem.Id) then Exit;

  if not ShowTemplateSelectDialog(SelectedTemplate) then
    Exit;

  NewProtocol := TProtocol.Create;
  NewProtocol.Title := 'New Protocol';
  NewProtocol.ProtocolType := ptExperiment;
  NewProtocol.ValidationStatus := vsDraft;
  NewProtocol.FormData := '';
  NewProtocol.CreatedDate := UTCNow;
  NewProtocol.CreatedBy := FVM.UserId;

  if Assigned(SelectedTemplate) then
  begin
    NewProtocol.TemplateId := SelectedTemplate.Id;
    NewProtocol.FormData := Model.Templates.BuildAutoFillData(
      SelectedTemplate, ParentItem, Model.User.DisplayName);
  end;

  if Assigned(ParentItem.ActionType) and Assigned(ParentItem.ActionType.Equipment) then
  begin
    NewProtocol.EquipModel := ParentItem.ActionType.Equipment.Model;
    NewProtocol.EquipManufacturer := ParentItem.ActionType.Equipment.Manufacturer;
    NewProtocol.EquipLocation := ParentItem.ActionType.Equipment.Location;
  end;

  if not FVM.AddProtocol(NewProtocol, ParentItem) then
  begin
    NewProtocol.Free;
    Exit;
  end;
  Model.RecordAudit(aetProtocol, NewProtocol.Id, aoCreate,
    'Added protocol "' + NewProtocol.Title + '" to item "' + ParentItem.Title + '"');

  TedProtocols.ShowEditor(NewProtocol, FContentViewer.FindPlugin('.protocol'));

  FVM.SelectItem(ParentItem.Id, NewProtocol.Id);
  FillTree(FLocation);
  RestoreLastSelection;
end;

procedure TframeItemTree.BtnAddValueClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  ParentItem: TItem;
  NewValue: unit_Item.TValue;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then
  begin
    ShowMessage('Please select a Proc or Action item.');
    Exit;
  end;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  ParentItem := nil;
  case Data.NodeType of
    ntItem:
      if Data.Item.Level in [TItemLevel.Proc, TItemLevel.Action] then
        ParentItem := Data.Item;
    ntProtocol, ntFile:
      begin
        Node := Tree.NodeParent[Node];
        if Assigned(Node) then
        begin
          Data := Tree.GetNodeData(Node);
          if Assigned(Data) and (Data.NodeType = ntItem) and
             (Data.Item.Level in [TItemLevel.Proc, TItemLevel.Action]) then
            ParentItem := Data.Item;
        end;
      end;
  end;

  if not Assigned(ParentItem) then
  begin
    ShowMessage('Please select a Proc or Action item to add a value to.');
    Exit;
  end;

  NewValue := unit_Item.TValue.Create;
  try
    if ShowValueDialog(dmNew, NewValue) then
    begin
      FVM.AddValue(NewValue.ValueType, NewValue.RecType, NewValue.Value,
        ParentItem, NewValue.Tol, NewValue.Description);
      FVM.SelectItem(ParentItem.Id, 0);
      FillTree(FLocation);
      RestoreLastSelection;
    end
    else
      NewValue.Free;
  except
    NewValue.Free;
    raise;
  end;
end;

procedure TframeItemTree.BtnAddFileClick(Sender: TObject);
var
  ParentItem: TItem;
  AActionType: TActionType;
  Files: TFileInfoArray;
  i: Integer;
  NewFile: unit_Item.TFile;
  TargetPath: string;
  Queue: TArray<TPreviewQueueItem>;
  QItem: TPreviewQueueItem;
begin
  if FLocation.ProjectID <= 0 then Exit;

  if not GetSelectedParentItem(ParentItem, AActionType) then Exit;
  if not FVM.CanEdit or FVM.IsItemSigned(ParentItem.Id) then Exit;

  if ShowFileDialogMulti(Files, AActionType) then
  begin
      Screen.Cursor := crHourGlass;
      try
        for i := 0 to High(Files) do
        begin
          if Length(Files) > 1 then
            SetStatusText(Format('Uploading file %d of %d...', [i + 1, Length(Files)]));

          NewFile := FVM.AddFile(Files[i].FileType, Files[i].Name, ParentItem);
          if not Assigned(NewFile) then Exit;

          if (Files[i].SourcePath <> '') and FileExists(Files[i].SourcePath) then
          begin
            TargetPath := StringReplace(Model.GetFileName(NewFile.Id), '\', '/', [rfReplaceAll]);
            try
              Model.Storage.CopyIn(Files[i].SourcePath, TargetPath);
            except
              FVM.DeleteFile(NewFile, ParentItem);
              SetStatusText('');
              MessageDlg(Format('Upload failed for "%s". Remaining files were skipped.',
                [Files[i].Name]), mtError, [mbOK], 0);
              Exit;
            end;

            QItem.FileId := NewFile.Id;
            QItem.ItemId := ParentItem.Id;
            QItem.FilePath := Files[i].SourcePath;
            QItem.PreviewPath := GetPreviewPath(ParentItem.Id, NewFile.Id);
            QItem.Extension := ExtractFileExt(Files[i].SourcePath);
            Queue := Queue + [QItem];
          end;
        end;
      finally
        SetStatusText('');
        Screen.Cursor := crDefault;
      end;

    if Length(Files) > 0 then
    begin
      FVM.SelectItem(ParentItem.Id, 0);
      FillTree(FLocation);
      RestoreLastSelection;
      FPreviewQueue.Start(Queue);
    end;
  end;
end;


procedure TframeItemTree.FillTree(const Location: TLocation);
var
  Item: TItem;
  Entry: TLabEntry;
  AFile: unit_Item.TFile;
  RootNode, ChildNode, SelectedNode: PVirtualNode;
  LastItemID: Integer;
  LastChildID: Int64;
begin
  if not Assigned(FVM) then Exit;
  FPreviewQueue.Stop;

  lblPath.Caption := '';
  lblName.Caption := '';
  lblDetails.Caption := '';

  if Assigned(FLook) then
    FLook.ClearHover;
  Tree.Clear;
  SelectedNode := nil;
  FVM.FilterText := FFilterText;
  FVM.LoadItemData;
  LastItemID := FVM.LastItemId;
  LastChildID := FVM.LastChildId;

  FFilling := True;
  Tree.BeginUpdate;
  try
  // Insert items into tree.  Items whose parent hasn't been inserted yet
  // (due to SortOrder) are deferred and inserted in a second pass.
  // FVM.Items returns a fresh caller-owned list — capture it once and free the
  // LIST (entities stay manager-owned) to avoid leaking one per tree rebuild.
  var SourceItems: TItems := FVM.Items;
  var Deferred: TList<TItem> := TList<TItem>.Create;
  try
    for Item in SourceItems do
    begin
      if FFilterText <> '' then
        if not FVM.ItemMatchesFilter(Item) then
          if (Item.Parent = 0) or not Assigned(GetParentItem(Item.Parent)) then
            Continue;

      if Item.Parent = 0 then
        RootNode := InsertItem(nil, Item)
      else
      begin
        var ParentNode := GetParentItem(Item.Parent);
        if not Assigned(ParentNode) then
        begin
          Deferred.Add(Item);
          Continue;
        end;
        RootNode := InsertItem(ParentNode, Item);
      end;

      if LastItemID = Item.Id then
        if LastChildID = 0 then
          SelectedNode := RootNode;

      for Entry in Item.Entries do
        if Entry is TProtocol then
        begin
          ChildNode := InsertProtocol(Entry as TProtocol, RootNode);
          if (LastItemID = Item.Id) and (LastChildID = Entry.Id) then
            SelectedNode := ChildNode;
        end;

      if Item.Type_ <> TItemType.Wiki then
        for AFile in Item.Files do
        begin
          ChildNode := InsertFile(AFile, RootNode);
          if (LastItemID = Item.Id) and (LastChildID = AFile.Id) then
            SelectedNode := ChildNode;
        end;

      Tree.Expanded[RootNode] := FVM.IsItemExpanded(Item.Id);
    end;

    for Item in Deferred do
    begin
      var ParentNode := GetParentItem(Item.Parent);
      if Assigned(ParentNode) then
        RootNode := InsertItem(ParentNode, Item)
      else
        RootNode := InsertItem(nil, Item);  

      if LastItemID = Item.Id then
        if LastChildID = 0 then
          SelectedNode := RootNode;

      for Entry in Item.Entries do
        if Entry is TProtocol then
        begin
          ChildNode := InsertProtocol(Entry as TProtocol, RootNode);
          if (LastItemID = Item.Id) and (LastChildID = Entry.Id) then
            SelectedNode := ChildNode;
        end;

      if Item.Type_ <> TItemType.Wiki then
        for AFile in Item.Files do
        begin
          ChildNode := InsertFile(AFile, RootNode);
          if (LastItemID = Item.Id) and (LastChildID = AFile.Id) then
            SelectedNode := ChildNode;
        end;

      Tree.Expanded[RootNode] := FVM.IsItemExpanded(Item.Id);
    end;

  finally
    Deferred.Free;
    SourceItems.Free;
  end;
  finally
    Tree.EndUpdate;
    FFilling := False;
  end;
  lblPath.Caption := Location.Path;

  FSelectedNode := SelectedNode;
end;

constructor TframeItemTree.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ResetSession;
end;

destructor TframeItemTree.Destroy;
begin
  ResetSession;
  FLook.Free;   // before the tree goes: it restores the tree's WindowProc
  SaveColumnWidths;
  FFileTypeIconIndex.Free;
  inherited;
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

procedure TframeItemTree.CreateActions;

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
  // Init runs on every login cycle; the actions and their control links are
  // user-agnostic (enabled state is driven live by the OnUpdate handlers), so
  // build them once. Re-running would orphan the old TActionList (owned by Self,
  // freed only at frame destroy) and leak a duplicate set every re-login.
  if Assigned(FActionList) then
    Exit;

  FActionList := TActionList.Create(Self);

  actNew            := AddAction('New',                  BtnNewClick,          actEditableUpdate);
  actNewProc        := AddAction('New Procedure',        miNewProcClick,       actEditableUpdate);
  actNewItem        := AddAction('New Item',             miNewItemClick,       actEditableUpdate);
  actNewAction      := AddAction('New Action',           miNewActionClick,     actEditableUpdate);
  actNewFromTemplate := AddAction('New from Template...', BtnNewFromTemplateClick, actEditableUpdate);
  CreateTemplateMenuItem;
  actAddFile        := AddAction('Add File',             BtnAddFileClick,      actEditableUpdate);
  actAddNote        := AddAction('Add Note',             BtnAddNoteClick,      actEditableUpdate);
  actAddProtocol    := AddAction('Add Protocol',         BtnAddProtocolClick,  actEditableUpdate);
  actAddValue       := AddAction('Add Value',            BtnAddValueClick,     actEditableUpdate);
  actEdit           := AddAction('Edit',                 BtnEditClick,         actEditableUpdate);
  actDuplicate      := AddAction('Duplicate',            BtnDuplicateClick,    actEditableUpdate);
  actExport         := AddAction('Export...',            BtnExportClick,       actNonGuestUpdate);
  actReport         := AddAction('Export Report...',     BtnReportClick,       actNonGuestUpdate);
  actReport.Enabled := False;
  actDelete         := AddAction('Delete',               BtnDeleteClick,       actEditableUpdate);
  actRefresh        := AddAction('Refresh',              btnRefreshClick,      nil);
  actLinks          := AddAction('Links...',             miItemLinksClick,     actLinksUpdate);

  // Wire toolbar buttons to actions (save/restore ImageIndex + DisabledIndex
  // because Action assignment overwrites them with the action's defaults)
  WireButton(BtnNew,         actNew);

  WireButton(BtnAddFile,     actAddFile);
  WireButton(BtnAddNote,     actAddNote);
  WireButton(btnAddProtocol, actAddProtocol);
  WireButton(BtnAddValue,    actAddValue);
  WireButton(BtnEdit,        actEdit);
  WireButton(BtnDuplicate,   actDuplicate);
  WireButton(BtnExport,      actExport);
  WireButton(BtnDelete,      actDelete);
  WireButton(btnRefresh,     actRefresh);
end;

procedure TframeItemTree.actLinksUpdate(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
    Data := Tree.GetNodeData(Node)
  else
    Data := nil;
  (Sender as TAction).Enabled :=
    Assigned(Data) and (Data.NodeType = ntItem);
end;

procedure TframeItemTree.actEditableUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := Assigned(FVM) and FVM.CanEdit;
end;

procedure TframeItemTree.actNonGuestUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := Assigned(FVM) and not FVM.IsReadOnly;
end;

procedure TframeItemTree.Init(AThumbnailList: TELNThumbnailList; AContentViewer: TframeContentViewer;
  APreviewSplitter: TRzSplitter);
var
  SessionId: TGUID;
begin
  ResetSession;
  CreateGUID(SessionId);
  FSessionCacheRoot := TPath.Combine(TPath.GetTempPath,
    'ELN3\sessions\' + GUIDToString(SessionId));
  edSearch.TextHint := 'Filter items...';
  LoadFileIcons;
  FThumbnailList := AThumbnailList;
  FContentViewer := AContentViewer;
  FPreviewSplitter := APreviewSplitter;
  FContentViewer.OnUpdateFile := DoUpdateFile;
  FContentViewer.OnUpdatePreview := DoUpdatePreview;
  FContentViewer.OnExtractValues := DoExtractValues;

  if not Assigned(FLook) then
    FLook := TTreeLook.Create(Tree, RowColor,
      function(Node: PVirtualNode): Boolean
      var
        D: PNodeData;
      begin
        D := Tree.GetNodeData(Node);
        Result := Assigned(D) and (D.NodeType = ntItem);
      end,
      procedure(Node: PVirtualNode)
      begin
        TreeClick(Tree);   
      end);

  CreateActions;

  // FVM and FPreviewQueue are session-bound and rebuilt each login; free the
  // previous instances first so a logout -> re-login doesn't leak a VM and a
  // PreviewQueue (with its live timer) per cycle. Both are nil on first Init.
  FreeAndNil(FVM);
  FVM := TItemTreeVM.Create(
    Model.Items, Model.Authors, Model.History,
    Model.Signatures, Model.Comments, Model.Tags, Model.ItemLinks, Model.Access);
  FVM.SetHypothesisManager(Model.Manager);
  FVM.TreeState := Model.TreeState;
  Tree.OnExpanded := TreeItemExpanded;
  Tree.OnCollapsed := TreeItemCollapsed;

  BtnNewFolder.Enabled := not FVM.IsReadOnly;


  FreeAndNil(FPreviewQueue);
  FPreviewQueue := TPreviewQueue.Create(Self, FContentViewer);
  FPreviewQueue.OnStatus := PreviewQueueStatus;
  FPreviewQueue.OnUpdate := PreviewQueueUpdate;
  FPreviewQueue.OnKeyValuesExtracted := PreviewQueueKeyValuesExtracted;

  LoadColumnWidths;

  begin
    var S := TNotebookSettings.Create;
    try
      SetShowItemIDs(S.ShowItemIDs);
    finally
      S.Free;
    end;
  end;

  RegisterMessage; // Subscribe to location messages before ProjectsPanel sends them
  Enabled := True;
  if Assigned(FActionList) then
  begin
    FActionList.State := asNormal;
    actRefresh.Enabled := True;
  end;
  tmrStartup.Enabled := True;
end;

procedure TframeItemTree.ScaleForDPI;

  function S(V: Integer): Integer;
  begin
    Result := MulDiv(V, Screen.PixelsPerInch, 192);
  end;

begin
  if Screen.PixelsPerInch = 192 then Exit;

  RzToolbar1.ButtonWidth  := S(50);
  RzToolbar1.ButtonHeight := S(50);
  RzToolbar1.RowHeight    := S(60);

  Tree.DefaultNodeHeight := S(40);
  Tree.Indent            := S(36);

end;

procedure TframeItemTree.SaveColumnWidths;
var
  Settings: TNotebookSettings;
  I: Integer;
begin
  Settings := TNotebookSettings.Create;
  try
    for I := 0 to Tree.Header.Columns.Count - 1 do
      Settings.SaveUIValue('ItemTree', 'ColWidth' + IntToStr(I),
        Tree.Header.Columns[I].Width);
  finally
    Settings.Free;
  end;
end;

procedure TframeItemTree.LoadColumnWidths;
var
  Settings: TNotebookSettings;
  I, W: Integer;
begin
  Settings := TNotebookSettings.Create;
  try
    for I := 0 to Tree.Header.Columns.Count - 1 do
    begin
      W := Settings.LoadUIValue('ItemTree', 'ColWidth' + IntToStr(I), 0);
      if W > 0 then
        Tree.Header.Columns[I].Width := W;
    end;
  finally
    Settings.Free;
  end;
end;

procedure TframeItemTree.SetShowItemIDs(Value: Boolean);
const
  ID_COLUMN = 3;
var
  Settings: TNotebookSettings;
  Col: TVirtualTreeColumn;
begin
  if (Tree = nil) or (Tree.Header.Columns.Count <= ID_COLUMN) then Exit;

  Col := Tree.Header.Columns[ID_COLUMN];
  if Value then
    Col.Options := Col.Options + [coVisible]
  else
    Col.Options := Col.Options - [coVisible];

  Tree.Invalidate;

  Settings := TNotebookSettings.Create;
  try
    Settings.ShowItemIDs := Value;
  finally
    Settings.Free;
  end;
end;

function TframeItemTree.InsertFile(const AFile: unit_Item.TFile;
  Parent: PVirtualNode): PVirtualNode;
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Node := Tree.AddChild(Parent);
  Data := Tree.GetNodeData(Node);

  Data.NodeType := ntFile;
  Data.AFile := AFile;
  Result := Node;
end;

function TframeItemTree.InsertItem(const Parent: PVirtualNode; Item: TItem): PVirtualNode;
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Node := Tree.AddChild(Parent);
  Data := Tree.GetNodeData(Node);

  Data.NodeType := ntItem;
  Data.Item := Item;
  Result := Node;

end;

function TframeItemTree.InsertProtocol(const Protocol: TProtocol;
  Parent: PVirtualNode): PVirtualNode;
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Node := Tree.AddChild(Parent);
  Data := Tree.GetNodeData(Node);

  Data.NodeType := ntProtocol;
  Data.Protocol := Protocol;
  Result := Node;
end;

procedure TframeItemTree.LoadFileIcons;
const
  CExtToIcon: array[0..36] of record Ext, Icon: string end = (
    (Ext: '.pdf';   Icon: 'PDF'),
    (Ext: '.xlsx';  Icon: 'XLSX'),
    (Ext: '.csv';   Icon: 'CSV'),
    (Ext: '.dat';   Icon: 'DAT'),
    (Ext: '.ascii'; Icon: 'ASCII'),
    (Ext: '.log';   Icon: 'LOG'),
    (Ext: '.tiff';  Icon: 'TIFF'),
    (Ext: '.tif';   Icon: 'TIFF'),
    (Ext: '.opju';  Icon: 'OPJU'),
    (Ext: '.xrcx';  Icon: 'XRCX'),
    (Ext: '.xrdml'; Icon: 'XRDML'),
    (Ext: '.rp4';   Icon: 'RP4'),
    (Ext: '.dsc';   Icon: 'DSC'),
    (Ext: '.fibps'; Icon: 'FIBPS'),
    (Ext: '.zrw';   Icon: 'ZRW'),
    (Ext: '.zrv';   Icon: 'ZRW'),
    (Ext: '.mit';   Icon: 'MIT'),
    (Ext: '.lmpin'; Icon: 'LMPIN'),
    (Ext: '.dump';  Icon: 'DUMP'),
    (Ext: '.data';  Icon: 'DUMP'),   
    (Ext: '.lammps';Icon: 'DUMP'),   
    (Ext: '.docx';  Icon: 'DOCX'),
    (Ext: '.pptx';  Icon: 'PPTX'),
    (Ext: '.png';   Icon: 'PNG'),
    (Ext: '.bmp';   Icon: 'BMP'),
    (Ext: '.jpg';   Icon: 'JPG'),
    (Ext: '.jpeg';  Icon: 'JPG'),
    (Ext: '.txt';   Icon: 'TXT'),
    (Ext: '.dm3';   Icon: 'DM3'),
    (Ext: '.dsr';   Icon: 'DSR'),
    (Ext: '.html';  Icon: 'HTML'),
    (Ext: '.htm';   Icon: 'HTML'),
    (Ext: '.xrfx';  Icon: 'XRFX'),
    (Ext: '.vk4';   Icon: 'VK4'),
    (Ext: '.md';    Icon: 'MD'),
    (Ext: '.tsv';   Icon: 'DEPO'),
    (Ext: '.json';  Icon: 'DEPO')
  );
var
  FileTypes: TFileTypes;
  FileType: TFileType;
  Ext, IconName: string;
  I, IconIdx, GenericIdx: Integer;
  VIL: TVirtualImageList;
begin
  FreeAndNil(FFileTypeIconIndex);
  FFileTypeIconIndex := TDictionary<Integer, Integer>.Create;

  VIL := dmTreeImages.vilFileTypeImages;
  GenericIdx := VIL.GetIndexByName('Generic');

  FileTypes := Model.FileTypes.GetFileTypes;
  for FileType in FileTypes do
  begin
    Ext := LowerCase(FileType.Ext);
    if (Ext <> '') and (Ext[1] <> '.') then
      Ext := '.' + Ext;

    IconName := '';
    for I := Low(CExtToIcon) to High(CExtToIcon) do
      if SameText(Ext, CExtToIcon[I].Ext) then
      begin
        IconName := CExtToIcon[I].Icon;
        Break;
      end;

    if IconName <> '' then
      IconIdx := VIL.GetIndexByName(IconName)
    else
      IconIdx := GenericIdx;

    if IconIdx >= 0 then
      FFileTypeIconIndex.Add(FileType.Id, IconIdx);
  end;
end;

procedure TframeItemTree.MessageListener(const Sender: TObject; const M: TMessage);
begin
  if not Assigned(FVM) then Exit;
  FLocation := (M as TMessage<TLocation>).Value;
  FRootPath := FLocation.Path;
  FVM.SetLocation(FLocation.ProjectID, FLocation.FolderID, FLocation.Access);
  ApplyAccessLevel;
  FContentViewer.Clear;
  FThumbnailList.Clear;
  FillTree(FLocation);
  RestoreLastSelection;
end;

procedure TframeItemTree.ApplyAccessLevel;
begin
  BtnNewFolder.Enabled := Assigned(FVM) and FVM.CanEdit;
end;

procedure TframeItemTree.RegisterMessage;
var
  MessageManager: TMessageManager;
begin
  if FMessageRegistered then Exit;
  FMessageRegistered := True;
  MessageManager := TMessageManager.DefaultManager;
  MessageManager.SubscribeToMessage(TMessage<TLocation>, MessageListener);
end;

procedure TframeItemTree.GetItemText(var E: TVSTGetCellTextEventArgs; Data: PNodeData);
begin
  case E.Column of
    0: 
      begin
        E.CellText := Data.Item.Title;
        if Tree.GetNodeLevel(E.Node) > 0 then
          E.StaticTextAlignment := TAlignment.taRightJustify;
      end;
    1: E.CellText := '';  // drawn manually in TreeAfterCellPaint
    2: E.CellText := DateToStr(FromUTC(Data.Item.CreatedDate));
    3: E.CellText := IntToStr(Data.Item.Id);
  end;
end;

procedure TframeItemTree.GetProtocolText(var E: TVSTGetCellTextEventArgs; Data: PNodeData);
var
  StatusBadge: string;
begin
  case E.Column of
    0: if Data.Protocol.ProtocolType.HasValue and (Data.Protocol.ProtocolType.Value = ptNote) then
         E.CellText := 'Note:'
       else
         E.CellText := 'Protocol:';
    1: begin
         StatusBadge := '';
         case Data.Protocol.ValidationStatus of
           vsApproved: StatusBadge := '[Approved] ';
           vsInReview: StatusBadge := '[In Review] ';
           vsRejected: StatusBadge := '[Rejected] ';
         end;
         E.CellText := StatusBadge + Data.Protocol.Title;
       end;
    2: E.CellText := DateToStr(FromUTC(Data.Protocol.CreatedDate));
    3: E.CellText := '';
  end;
end;

function TframeItemTree.GetParentItem(const ID: integer): PVirtualNode;
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Result := nil;
  Node := Tree.GetFirst;
  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntItem) and (Data.Item.ID = ID) then
    begin
      Result := Node;
      Break;
    end;
    Node := Tree.GetNext(Node);
  end;
end;

function TframeItemTree.GetParentItemFromNode(Node: PVirtualNode; out ParentID: Integer; out Levels: TItemLevels): Boolean;
var
  Data: PNodeData;
begin
  Result := False;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntItem:
      begin
        ParentID := Data.Item.Id;
        case Data.Item.Level of
          TItemLevel.Proc:   Levels := [TItemLevel.Item, TItemLevel.Action];
          TItemLevel.Item:   Levels := [TItemLevel.Action];
          TItemLevel.Action: Levels := [TItemLevel.Action];
          TItemLevel.Folder: Levels := [TItemLevel.Proc, TItemLevel.Item];
        end;
        Result := True;
      end;
    ntProtocol, ntFile:
      begin
        if Assigned(Node.Parent) and (Node.Parent <> Tree.RootNode) then
        begin
          Data := Tree.GetNodeData(Node.Parent);
          if Assigned(Data) and (Data.NodeType = ntItem) then
          begin
            ParentID := Data.Item.Id;
            case Data.Item.Level of
              TItemLevel.Proc:   Levels := [TItemLevel.Item, TItemLevel.Action];
              TItemLevel.Item:   Levels := [TItemLevel.Action];
              TItemLevel.Action: Levels := [TItemLevel.Action];
              TItemLevel.Folder: Levels := [TItemLevel.Proc, TItemLevel.Item];
            end;
            Result := True;
          end;
        end;
      end;
  end;
end;

function TframeItemTree.GetSelectedParentItem(out Item: TItem; out ActionType: TActionType): Boolean;
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Result := False;
  Item := nil;
  ActionType := nil;

  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntItem:
      begin
        Item := Data.Item;
        ActionType := Data.Item.ActionType;
        Result := True;
      end;
    ntProtocol, ntFile:
      begin
        if Assigned(Node.Parent) and (Node.Parent <> Tree.RootNode) then
        begin
          Data := Tree.GetNodeData(Node.Parent);
          if Assigned(Data) and (Data.NodeType = ntItem) then
          begin
            Item := Data.Item;
            ActionType := Data.Item.ActionType;
            Result := True;
          end;
        end;
      end;
  end;
end;

procedure TframeItemTree.GetFileText(var E: TVSTGetCellTextEventArgs; Data: PNodeData);
begin
  case E.Column of
    0: E.CellText := Data.AFile.Title;
    1: E.CellText := Data.AFile.Description;
    2: E.CellText := DateToStr(FromUTC(Data.AFile.CreatedDate));
    3: E.CellText := '';
  end;
end;

procedure TframeItemTree.UpdateInfoColors(AColor: TColor);
begin
  shpTypeBar.Brush.Color := AColor;
  lblName.Font.Color := AColor;
end;

procedure TframeItemTree.RefreshInfoColors;
begin
  if Assigned(Tree.FocusedNode) then
    UpdateInfoColors(RowColor(Tree.FocusedNode));
end;

procedure TframeItemTree.DisplayItemInfo(const Item: TItem);
var
  Details, PropsText: string;
  LatestComment: TComment;
  CommentText: string;
  JSONObj: TJSONObject;
  i: Integer;
begin
  UpdateInfoColors(ItemTypeColor(Item.Type_));
  lblName.Caption := Format('%s: %s',
    [TRttiEnumerationType.GetName(Item.Type_), Item.Title]);

  Details := '';

  if Assigned(Item.ActionType) and (Item.ActionType.Title <> '') then
  begin
    Details := Item.ActionType.Title;
    if Assigned(Item.ActionType.Equipment) then
    begin
      Details := Details + ' '#$2014' ' + Item.ActionType.Equipment.Model +
        ' (' + Item.ActionType.Equipment.Manufacturer;
      if Item.ActionType.Equipment.Location <> '' then
        Details := Details + ', ' + Item.ActionType.Equipment.Location;
      Details := Details + ')';
    end;
  end;

  if Item.Description <> '' then
  begin
    if Details <> '' then
      Details := Details + '  '#$2022'  ';
    Details := Details + Item.Description;
  end;

  if Item.Values.Count > 0 then
  begin
    if Details <> '' then
      Details := Details + #13#10;
    Details := Details + FormatValuesInline(Item.Values);
  end;

  if Item.Properties <> '' then
  begin
    JSONObj := TJSONObject.ParseJSONValue(Item.Properties) as TJSONObject;
    if Assigned(JSONObj) then
    try
      PropsText := '';
      for i := 0 to JSONObj.Count - 1 do
      begin
        if PropsText <> '' then
          PropsText := PropsText + ';  ';
        PropsText := PropsText + JSONObj.Pairs[i].JsonString.Value +
          ': ' + JSONObj.Pairs[i].JsonValue.Value;
      end;
      if PropsText <> '' then
      begin
        if Details <> '' then
          Details := Details + #13#10;
        Details := Details + PropsText;
      end;
    finally
      JSONObj.Free;
    end;
  end;

  if FVM.GetCommentCount(Item.Id) > 0 then
  begin
    LatestComment := FVM.GetLatestComment(Item.Id);
    if Assigned(LatestComment) then
    begin
      CommentText := LatestComment.Text;
      if Length(CommentText) > 100 then
        CommentText := Copy(CommentText, 1, 100) + '...';
      if Details <> '' then
        Details := Details + #13#10;
      Details := Details + #$00BB + ' ' + LatestComment.UserName + ': ' + CommentText;
    end;
  end;

  lblDetails.Caption := Details;

  FDetailItemId := Item.Id;
  FDetailItemTitle := Item.Title;
  FillLinksPanel(Item.Id);
end;

procedure TframeItemTree.Clear;
begin
  // Stop the preview queue so its timer can't keep firing during the
  // logout -> login modal and write extracted values via the previous
  // session VM.
  if Assigned(FPreviewQueue) then
    FPreviewQueue.Stop;
  if Assigned(FLook) then
    FLook.ClearHover;
  Tree.Clear;
  FSelectedNode := nil;
  FItem := nil;
  FDraggedProc := nil;
  FDetailLinks := nil;
  FDetailItemId := 0;
  FDetailItemTitle := '';
  vstLinks.Clear;
  pnlLinks.Visible := False;
  FCurrentFile := -1;
  lblPath.Caption := '';
  lblName.Caption := '';
  lblDetails.Caption := '';
  UpdateInfoColors(CDefaultColor);
  if Assigned(FThumbnailList) then FThumbnailList.Clear;
  UpdateFileButtons;
end;

procedure TframeItemTree.ResetSession;
var
  I: Integer;
begin
  Enabled := False;
  tmrStartup.Enabled := False;
  if FMessageRegistered then
  begin
    TMessageManager.DefaultManager.Unsubscribe(TMessage<TLocation>, MessageListener);
    FMessageRegistered := False;
  end;
  if Assigned(FActionList) then
  begin
    FActionList.State := asNormal;
    for I := 0 to FActionList.ActionCount - 1 do
      (FActionList.Actions[I] as TAction).Enabled := False;
    FActionList.State := asSuspended;
  end;
  Clear;
  FLocation := Default(TLocation);
  FRootPath := '';
  FreeAndNil(FPreviewQueue);
  // Retire paths only after the session's preview timer has been stopped/freed.
  FSessionCacheRoot := '';
  FreeAndNil(FVM);
  if Assigned(FContentViewer) then
  begin
    FContentViewer.OnUpdateFile := nil;
    FContentViewer.OnUpdatePreview := nil;
    FContentViewer.OnExtractValues := nil;
  end;
  FContentViewer := nil;
  FThumbnailList := nil;
  FPreviewSplitter := nil;
end;

procedure TframeItemTree.DisplayProtocolView(const Protocol: TProtocol);
var
  ProtocolTypeStr, StatusStr, ModifiedStr, TemplateHtml: string;
  Template: TTemplate;
begin
  UpdateInfoColors(ItemProtocolColor);
  lblName.Caption := Protocol.Title;

  if Protocol.ProtocolType.HasValue then
    ProtocolTypeStr := GetEnumName(TypeInfo(TProtocolType), Ord(Protocol.ProtocolType.Value))
  else
    ProtocolTypeStr := 'Not specified';

  StatusStr := GetEnumName(TypeInfo(TValidationStatus), Ord(Protocol.ValidationStatus));

  if Protocol.ModifiedDate.HasValue then
    ModifiedStr := DateToStr(FromUTC(Protocol.ModifiedDate.Value))
  else
    ModifiedStr := '';

  TemplateHtml := '';
  if Protocol.TemplateId.HasValue then
  begin
    Template := Model.Templates.GetTemplateById(Protocol.TemplateId.Value);
    if Assigned(Template) then
      TemplateHtml := Model.Templates.GetTemplateHtml(Template);
  end;

  FContentViewer.DisplayProtocol(
    Protocol.Title,
    ProtocolTypeStr,
    StatusStr,
    DateToStr(FromUTC(Protocol.CreatedDate)),
    ModifiedStr,
    Protocol.FormData,
    TemplateHtml,
    Protocol.EquipModel,
    Protocol.EquipManufacturer,
    Protocol.EquipLocation);
end;

procedure TframeItemTree.DisplayNotePreview(const Protocol: TProtocol);
begin
  UpdateInfoColors(ItemNoteColor);
  lblName.Caption := Protocol.Title;
  lblDetails.Caption := '';
  FContentViewer.DisplayNote(Protocol.Title, Protocol.FormData);
end;

procedure TframeItemTree.DisplayFileInfo(const AFile: unit_Item.TFile);
begin
  UpdateInfoColors(ItemFileColor);
  lblName.Caption := Format('File: %s',[AFile.Title]);
  lblDetails.Caption := AFile.Description;
end;

procedure TframeItemTree.UpdateFileButtons;
begin
  if Assigned(FContentViewer) then
    FContentViewer.ShowFileButtons(Assigned(FVM) and (FCurrentFile > 0));
end;

procedure TframeItemTree.DoExtractValues(Sender: TObject);
begin
  miFileExtractValuesClick(Sender);
end;

function TframeItemTree.PrepareFile(FileId: Int64): string;
begin
  if not Assigned(FOnPrepareFile) then
    raise EInvalidOperation.Create('The host has not supplied a file working-copy provider.');
  Result := FOnPrepareFile(FileId);
end;

procedure TframeItemTree.DoUpdateFile(Sender: TObject);
var
  ErrorMsg: string;
  SaveResult: TSaveResult;
begin
  if not Assigned(FVM) or not FVM.CanEdit then Exit;
  if FCurrentFile <= 0 then Exit;
  if not Assigned(ElnFileService) then
    raise EInvalidOperation.Create('The host has not supplied a file save service.');
  SaveResult := ElnFileService.SaveLocalFile(FCurrentFile,
    PrepareFile(FCurrentFile), ErrorMsg);
  if SaveResult = srOk then
  begin
    FileContentChanged(FCurrentFile);
    MessageDlg('File updated successfully.', mtInformation, [mbOK], 0);
  end
  else if SaveResult = srConflict then
    MessageDlg('File changed since it was opened. Reload it before saving.',
      mtWarning, [mbOK], 0)
  else
    MessageDlg(ErrorMsg, mtError, [mbOK], 0);
end;

function TframeItemTree.GetPreviewPath(const ActionID: Integer; const FileID: Int64): string;
begin
  if FSessionCacheRoot = '' then
    raise EInvalidOperation.Create('No preview session is active.');
  Result := TPath.Combine(TPath.Combine(FSessionCacheRoot, 'previews'),
    Format('%.*d_%.*d.png', [5, ActionID, 5, FileID]));
end;

function TframeItemTree.MaterializeFilePreview(const ActionID: Integer; const FileID: Int64): string;
var
  PreviewPath, StoragePath: string;
begin
  Result := '';
  PreviewPath := GetPreviewPath(ActionID, FileID);
  StoragePath := Format('previews/[1000]/%.*d_%.*d.png', [5, ActionID, 5, FileID]);
  try
    if not Model.Storage.Exists(StoragePath) then
    begin
      System.SysUtils.DeleteFile(PreviewPath);
      Exit;
    end;
    ForceDirectories(ExtractFilePath(PreviewPath));
    Model.Storage.CopyOut(StoragePath, PreviewPath);
    Result := PreviewPath;
  except
    on E: Exception do
    begin
      System.SysUtils.DeleteFile(PreviewPath);
      SetStatusText('Preview download failed: ' + E.Message);
    end;
  end;
end;

procedure TframeItemTree.DisplayFilePreviews(const ActionID: integer; Files: TFiles);
var
  AFile: unit_Item.TFile;
begin
  FThumbnailList.Clear;
  for AFile in Files do
    FThumbnailList.Add(AFile.Id, AFile.Title,
      MaterializeFilePreview(ActionID, AFile.Id));
end;

procedure TframeItemTree.CollectFilePreviews(Node: PVirtualNode);
var
  Child: PVirtualNode;
  Data, ParentData: PNodeData;
  ParentItem: TItem;
begin
  Child := Tree.GetFirstChild(Node);
  while Assigned(Child) do
  begin
    Data := Tree.GetNodeData(Child);
    if Assigned(Data) then
    begin
      if Data.NodeType = ntFile then
      begin
        ParentData := Tree.GetNodeData(Child.Parent);
        if Assigned(ParentData) and (ParentData.NodeType = ntItem) then
        begin
          ParentItem := ParentData.Item;
          FThumbnailList.Add(Data.AFile.Id, Data.AFile.Title,
            MaterializeFilePreview(ParentItem.Id, Data.AFile.Id));
        end;
      end
      else if Data.NodeType = ntItem then
        CollectFilePreviews(Child);
    end;
    Child := Tree.GetNextSibling(Child);
  end;
end;

function TframeItemTree.FindProcNode(Node: PVirtualNode): PVirtualNode;
var
  Current: PVirtualNode;
  Data: PNodeData;
begin
  Current := Node;
  while Assigned(Current) do
  begin
    Data := Tree.GetNodeData(Current);
    if Assigned(Data) and (Data.NodeType = ntItem) and
       (Data.Item.Level = TItemLevel.Proc) then
      Exit(Current);
    Current := Current.Parent;
    if Current = Tree.RootNode then
      Break;
  end;
  Result := nil;
end;

procedure TframeItemTree.DisplayPreviewsForScope(ItemNode: PVirtualNode; Item: TItem);
var
  Settings: TNotebookSettings;
  Scope: TPreviewScope;
  ProcNode: PVirtualNode;
begin
  Settings := TNotebookSettings.Create;
  try
    Scope := Settings.PreviewScope;
  finally
    Settings.Free;
  end;

  case Scope of
    psCurrentItem:
      DisplayFilePreviews(Item.Id, Item.Files);

    psItemAndChildren:
      CollectFilePreviews(ItemNode);

    psEntireProc:
    begin
      ProcNode := FindProcNode(ItemNode);
      if Assigned(ProcNode) then
        CollectFilePreviews(ProcNode)
      else
        CollectFilePreviews(ItemNode);
    end;

    psSiblingFiles:
      ; 
  end;
end;

procedure TframeItemTree.BtnExportClick(Sender: TObject);
var
  AllItems, SelectedItems: TItems;
  ExportPath: string;
  IncludeFiles, IncludeHistory: Boolean;
  Exporter: TELNPackageExporter;
  Options: TELNPackageExportOptions;
  ExportedBy: string;
begin
  if FLocation.ProjectID <= 0 then Exit;

  AllItems := FVM.Items;
  try
    if AllItems.Count = 0 then
    begin
      ShowMessage('No items to export.');
      Exit;
    end;

    if TdlgPackageExport.Execute(AllItems, SelectedItems, ExportPath,
      IncludeFiles, IncludeHistory) then
    begin
      try
        Options.IncludeFiles := IncludeFiles;
        Options.IncludeStatusHistory := IncludeHistory;

        if Assigned(Model.User) then
          ExportedBy := Model.User.DisplayName
        else
          ExportedBy := 'Unknown';

        // SelectedItems belong to the shared manager, and the exporter does not
        // own the one it is handed -- a fresh GetManager here was a second
        // identity map over the same rows, and it leaked.
        Exporter := TELNPackageExporter.Create(Model.Manager);
        try
          if Exporter.ExportItems(SelectedItems, ExportPath, ExportedBy, Options) then
            ShowMessage(Format('Export complete. %d items exported to: %s',
              [SelectedItems.Count, ExportPath]))
          else
            ShowMessage('Export failed.');
        finally
          Exporter.Free;
        end;
      finally
        SelectedItems.Free;
      end;
    end;
  finally
    AllItems.Free;
  end;
end;

procedure TframeItemTree.BtnReportClick(Sender: TObject);
var
  AllItems: TItems;
begin
  if FLocation.ProjectID <= 0 then Exit;
  if not Assigned(FItem) then Exit;

  AllItems := FVM.Items;
  try
    if AllItems.Count = 0 then
    begin
      ShowMessage('No items to report.');
      Exit;
    end;

    TdlgReportExport.Execute(FItem, AllItems, FContentViewer.FindPlugin('.html'),
      TPath.Combine(FSessionCacheRoot, 'reports'));
  finally
    AllItems.Free;
  end;
end;

procedure TframeItemTree.TreeClick(Sender: TObject);
var
  Node, ParentNode: PVirtualNode;
  Data, ParentData: PNodeData;
  BodyFile: unit_Item.TFile;
begin
  if not Assigned(FVM) then Exit;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then
  begin
    FContentViewer.Clear;
    FCurrentFile := -1;
    FItem := nil;
    lblPath.Caption := '';
    lblName.Caption := '';
    lblDetails.Caption := '';
    FThumbnailList.Clear;
    FileSelected(-1);
    UpdateFileButtons;
    Exit;
  end;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  if Assigned(FPreviewSplitter) then
    FPreviewSplitter.LowerRight.Visible :=
      not ((Data.NodeType = ntItem) and (Data.Item.Type_ = TItemType.Wiki));

  case Data.NodeType of
    ntItem: begin
              FContentViewer.Clear;
              FCurrentFile := -1;
              FItem := Data.Item;
              DisplayItemInfo(FItem);
              FThumbnailList.Clear;
              DisplayPreviewsForScope(Node, FItem);
              FileSelected(0);
              FVM.SelectItem(Data.Item.Id, 0);

              // Wiki items have no .md file child node; render the body .md
              // directly so single-click on a wiki page shows its content.
              if FItem.Type_ = TItemType.Wiki then
                for BodyFile in FItem.Files do
                  if SameText(BodyFile.FileType.Ext, '.md') then
                  begin
                    FCurrentFile := BodyFile.Id;
                    FileSelected(BodyFile.Id);
                    ImageClick(BodyFile.Id);
                    Break;
                  end;
            end;
    ntProtocol: begin
              FCurrentFile := 0;
              FItem := nil;
              if Data.Protocol.ProtocolType.HasValue and (Data.Protocol.ProtocolType.Value = ptNote) then
                DisplayNotePreview(Data.Protocol)
              else
                DisplayProtocolView(Data.Protocol);
              FileSelected(0);
              ParentNode := Node.Parent;
              if Assigned(ParentNode) then
              begin
                ParentData := Tree.GetNodeData(ParentNode);
                if Assigned(ParentData) and (ParentData.NodeType = ntItem) then
                begin
                  FItem := ParentData.Item;
                  DisplayPreviewsForScope(ParentNode, FItem);
                  FVM.SelectItem(ParentData.Item.Id, Data.Protocol.Id);
                end;
              end;
            end;
    ntFile: begin
              FCurrentFile := Data.AFile.Id;
              DisplayFileInfo(Data.AFile);
              FileSelected(Data.AFile.Id);
              ParentNode := Node.Parent;
              if Assigned(ParentNode) then
              begin
                ParentData := Tree.GetNodeData(ParentNode);
                if Assigned(ParentData) and (ParentData.NodeType = ntItem) then
                begin
                  FItem := ParentData.Item;
                  DisplayFilePreviews(FItem.Id, FItem.Files);
                  FVM.SelectItem(ParentData.Item.Id, Data.AFile.Id);
                end;
              end;
              ImageClick(Data.AFile.Id);
            end;
  end;
  UpdateFileButtons;
end;

procedure TframeItemTree.BtnEditClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntItem, ntProtocol:
      TreeDblClick(Sender);
    ntFile:
      EditFileNode(Data.AFile);
  end;
end;


procedure TframeItemTree.EditFileNode(AFile: unit_Item.TFile);
var
  NewTitle, NewDescription, OldPath, NewPath: string;
  Manager: TObjectManager;
  ItemsModel: TItemModel;
  FileEntity: unit_Item.TFile;
  Project: TProject;
  BaselineVersion: Integer;
  FileMoved, Updated: Boolean;

  procedure RestoreMovedFile;
  begin
    if not FileMoved then Exit;
    try
      Model.Storage.MoveFile(NewPath, OldPath);
      FileMoved := False;
    except
      on E: Exception do
        raise EInOutError.Create('The file metadata was not saved, and its ' +
          'bytes could not be moved back from "' + NewPath + '" to "' +
          OldPath + '":' + sLineBreak + E.Message);
    end;
  end;

begin
  if not Assigned(FVM) or not FVM.CanEdit then Exit;
  if not Assigned(AFile.Item) or FVM.IsItemSigned(AFile.Item.Id) then Exit;

  BaselineVersion := AFile.Version;
  FileMoved := False;

  if not ShowFileEditDialog(AFile.Title, AFile.Description,
    NewTitle, NewDescription) then
  begin
    DisplayFileInfo(AFile);
    Exit;
  end;

  // Keep attempted edits out of the shared manager and its owner collections.
  Manager := TObjectManager.Create(Model.Connection);
  try
    FileEntity := Manager.Find<unit_Item.TFile>(AFile.Id);
    if not Assigned(FileEntity) or not Assigned(FileEntity.Item) or
      FileEntity.Item.IsDeleted then
      raise EInvalidOperation.Create('The attachment no longer exists.');
    Project := Manager.Find<TProject>(FileEntity.Item.ProjectID);
    if not Assigned(Project) or Project.IsArchived or
      not Model.Access.CanWrite(Manager, Manager.Find<TUser>(Model.User.Id), Project.Id) or
      IsItemSignedCheck(Manager, FileEntity.Item.Id) then
      raise EInvalidOperation.Create('The attachment cannot be changed.');
    if FileEntity.Version <> BaselineVersion then
    begin
      Model.Manager.Refresh(AFile);
      raise EInvalidOperation.Create('File metadata changed. Refresh before renaming.');
    end;

    OldPath := Format('Projects/%s/%s/%s',
      [CleanFileName(Project.FileFolder), CleanFileName(FileEntity.Item.FolderName),
       FileEntity.FullName]);
    FileEntity.Title := NewTitle;
    FileEntity.Description := NewDescription;
    NewPath := Format('Projects/%s/%s/%s',
      [CleanFileName(Project.FileFolder), CleanFileName(FileEntity.Item.FolderName),
       FileEntity.FullName]);
    ItemsModel := TItemModel.Create(Manager);
    try
      if OldPath <> NewPath then
      begin
        Model.Storage.MoveFile(OldPath, NewPath);
        FileMoved := True;
      end;
      try
        Updated := ItemsModel.UpdateFile(FileEntity, Model.User.Id);
      except
        try
          Model.Manager.Refresh(AFile);
        finally
          RestoreMovedFile;
        end;
        raise;
      end;
      if not Updated then
      begin
        try
          Model.Manager.Refresh(AFile);
        finally
          RestoreMovedFile;
        end;
        Exit;
      end;
      Model.Manager.Refresh(AFile);
    finally
      ItemsModel.Free;
    end;
  finally
    Manager.Free;
  end;

  FillTree(FLocation);
  RestoreLastSelection;
end;

procedure TframeItemTree.TreeDblClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  if FVM.IsReadOnly then Exit;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntItem: begin
              if not FVM.CanEdit then Exit;
              FItem := Data.Item;
              if FVM.IsItemSigned(FItem.Id) then
              begin
                ShowSignatureView(FItem.Id);
                Exit;
              end;
              if FItem.Level in [TItemLevel.Proc, TItemLevel.Action] then
              begin
                if ShowActionDialog(dmEdit, FItem, [FItem.Level]) then
                begin
                  if not FVM.UpdateItem(FItem, Model.Relocator) then Exit;
                  FillTree(FLocation);
                  RestoreLastSelection;
                end
                else
                  DisplayItemInfo(FItem);
              end
              else if FItem.Level = TItemLevel.Item then
              begin
                if ShowItemDialog(dmEdit, FItem) then
                begin
                  if not FVM.UpdateItem(FItem, Model.Relocator) then Exit;
                  FillTree(FLocation);
                  RestoreLastSelection;
                end
                else
                  DisplayItemInfo(FItem);
              end;
            end;
    ntProtocol: begin
              if not FVM.CanEdit then Exit;
              var ProtocolParent := Model.Items.GetItemForEntry(Data.Protocol.Id);
              if not Assigned(ProtocolParent) then Exit;
              if IsItemSignedCheck(Model.Manager, ProtocolParent.Id) then
              begin
                ShowSignatureView(ProtocolParent.Id);
                Exit;
              end;
              if Data.Protocol.ProtocolType.HasValue and (Data.Protocol.ProtocolType.Value = ptNote) then
              begin
                var DraftNote := TProtocol.Create;
                try
                  DraftNote.Title := Data.Protocol.Title;
                  DraftNote.FormData := Data.Protocol.FormData;
                  if TdlgNote.Execute(DraftNote) then
                  begin
                    if not FVM.UpdateNote(Data.Protocol,
                      DraftNote.Title, DraftNote.FormData) then Exit;
                    FillTree(FLocation);
                    RestoreLastSelection;
                  end
                  else
                    DisplayNotePreview(Data.Protocol);
                finally
                  DraftNote.Free;
                end;
              end
              else
              begin
                TedProtocols.ShowEditor(Data.Protocol, FContentViewer.FindPlugin('.protocol'));
                FillTree(FLocation);
                RestoreLastSelection;
              end;
            end;
    ntFile: begin
              DisplayFileInfo(Data.AFile);
              ImageDBLClick(Data.AFile.Id);
            end;
  end;
end;

procedure TframeItemTree.TreeGetCellText(Sender: TCustomVirtualStringTree;
  var E: TVSTGetCellTextEventArgs);
var
  Data: PNodeData;
begin
  E.CellText := '';
  if not Assigned(E.Node) then Exit;

  Data := Sender.GetNodeData(E.Node);
  if not Assigned(Data) then Exit;

  case Data.NodeType of
    ntItem: GetItemText(E, Data);
    ntProtocol: GetProtocolText(E, Data);
    ntFile: GetFileText(E, Data);
  end;
end;

procedure TframeItemTree.TreeAfterCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  CellRect: TRect);
var
  Data: PNodeData;
  Tags: TTags;
  Tag: TTag;
  CommentCount, LinkCount: Integer;
  VST: TVirtualStringTree;
  CellText: string;
  X, Limit: Integer;
  C: TColor;
  Badges: TBadgePainter;
begin
  // Shared look first (gap, nesting lines, hover pill). From here on CellRect
  // is a header's band, so the badges centre on it. The hovered row's pill
  // replaces its comment/link badges.
  if Assigned(FLook) and FLook.AfterCellPaint(TargetCanvas, Node, Column, CellRect) then
    Exit;

  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  if not (Column in [0, 1]) then Exit;
  VST := Sender as TVirtualStringTree;
  if Column = 0 then
  begin
    CommentCount := FVM.GetCommentCount(Data.Item.Id);
    LinkCount := FVM.GetLinkCount(Data.Item.Id);
    if (CommentCount = 0) and (LinkCount = 0) then Exit;
    Badges := TBadgePainter.Create(TargetCanvas, VST.Font, FLook.PPI,
      FLook.RowBackground(Node));
    try
      X := CellRect.Right - Badges.Gap;
      if CommentCount > 0 then
        X := Badges.DrawRightAligned(X, CellRect, IntToStr(CommentCount),
          BADGE_SLATE) - Badges.Gap;
      if LinkCount > 0 then
        Badges.DrawRightAligned(X, CellRect, IntToStr(LinkCount) + ' ' + #$2192,
          BADGE_VIOLET);
    finally
      Badges.Free;
    end;
    Exit;
  end;

  Badges := TBadgePainter.Create(TargetCanvas, VST.Font, FLook.PPI,
    FLook.RowBackground(Node));
  try

    X := CellRect.Left + VST.TextMargin;
    Limit := CellRect.Right - Badges.Gap;

    Tags := FVM.GetTagsForItem(Data.Item.Id);
    if Assigned(Tags) then
      for Tag in Tags do
      begin
        if Tag.Color <> '' then
          C := HexToColor(Tag.Color)
        else
          C := BADGE_BLUE;
        if X + Badges.Width(Tag.Name) > Limit then Break;
        X := Badges.DrawAt(X, CellRect, Tag.Name, C, Limit) + Badges.Gap;
      end;

    if Data.Item.Values.Count > 0 then
      CellText := FormatValuesInline(Data.Item.Values)
    else
      CellText := Data.Item.Description;

    if CellText <> '' then
    begin
      TargetCanvas.Font.Assign(VST.Font);
      if vsSelected in Node.States then
        TargetCanvas.Font.Color := VST.Colors.SelectionTextColor
      else if TStyleManager.IsCustomStyleActive then
        TargetCanvas.Font.Color := StyleServices.GetSystemColor(VST.Font.Color)
      else
        TargetCanvas.Font.Color := VST.Font.Color;
      TargetCanvas.Brush.Style := bsClear;
      TargetCanvas.TextOut(X,
        CellRect.Top + (CellRect.Bottom - CellRect.Top - TargetCanvas.TextHeight(CellText)) div 2,
        CellText);
      TargetCanvas.Brush.Style := bsSolid;
      X := X + TargetCanvas.TextWidth(CellText) + VST.TextMargin;
    end;

    if FVM.IsItemSigned(Data.Item.Id) then
      X := Badges.DrawAt(X, CellRect, 'SIGNED', BADGE_RED, Limit) + Badges.Gap;
    if FVM.IsItemRun(Data.Item.Id) then
      Badges.DrawAt(X, CellRect, 'HYP', BADGE_TEAL, Limit);

  finally
    Badges.Free;
  end;
end;

procedure TframeItemTree.TreeGetImageIndexEx(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: System.UITypes.TImageIndex;
  var ImageList: TCustomImageList);
var
  Data: PNodeData;
begin
  if (Kind in [ikNormal, ikSelected]) and (Column = 0) and Assigned(Node) then
  begin
    Data := Sender.GetNodeData(Node);
    if Assigned(Data) then
    begin
      case Data.NodeType of
        ntItem:
          case Data.Item.Type_ of
            TItemType.Other: ImageIndex := 9;   
            TItemType.Wiki:  ImageIndex := 11;  
          else
            ImageIndex := ord(Data.Item.Type_);
          end;
        ntProtocol: begin
                  ImageIndex := 10;
                  if Data.Protocol.ProtocolType.HasValue then
                    case Data.Protocol.ProtocolType.Value of
                      ptExperiment:  ImageIndex := 7;   
                      ptMeasurement: ImageIndex := 2;   
                      ptAnalysis:    ImageIndex := 4;   
                      ptSynthesis:   ImageIndex := 0;   
                      ptTesting:     ImageIndex := 3;   
                      ptOther:       ImageIndex := 10;  
                      ptNote:        ImageIndex := 9;   
                    end;
                end;
        ntFile: begin
                  ImageList := dmTreeImages.vilFileTypeImages;
                  ImageIndex := -1;
                  if Assigned(Data.AFile.FileType) and Assigned(FFileTypeIconIndex) then
                  begin
                    var IconIdx: Integer;
                    if FFileTypeIconIndex.TryGetValue(Data.AFile.FileType.Id, IconIdx) then
                      ImageIndex := IconIdx;
                  end;
                end;
        else ImageIndex := -1;
      end;
    end;
  end;
end;

procedure TframeItemTree.TreeGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TNodeData);
end;

procedure TframeItemTree.TreeKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  if Shift <> [ssCtrl] then Exit;
  if not (Key in [VK_UP, VK_DOWN]) then Exit;

  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  if Data.Item.Parent <> 0 then Exit;

  if Key = VK_UP then
    MoveRootItem(-1)
  else
    MoveRootItem(+1);
  Key := 0;
end;

procedure TframeItemTree.TreeDragAllowed(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; var Allowed: Boolean);
var
  Data: PNodeData;
begin
  Data := Sender.GetNodeData(Node);
  Allowed := Assigned(Data) and (Data.NodeType = ntItem);
  if Allowed and (Data.Item.Parent = 0) then
    FDraggedProc := Data.Item
  else
    FDraggedProc := nil;
end;

procedure TframeItemTree.TreeDragOver(Sender: TBaseVirtualTree; Source: TObject;
  Shift: TShiftState; State: TDragState; Pt: TPoint; Mode: TDropMode;
  var Effect: Integer; var Accept: Boolean);
var
  TargetNode, SourceNode: PVirtualNode;
  TargetData, SourceData: PNodeData;
begin
  Accept := False;

  if not (Source is TBaseVirtualTree) then Exit;

  TargetNode := Sender.GetNodeAt(Pt);
  if not Assigned(TargetNode) then Exit;

  TargetData := Sender.GetNodeData(TargetNode);
  if (not Assigned(TargetData)) or (TargetData.NodeType <> ntItem) then Exit;

  SourceNode := TBaseVirtualTree(Source).GetFirstSelected;
  if not Assigned(SourceNode) then Exit;

  SourceData := TBaseVirtualTree(Source).GetNodeData(SourceNode);
  if (not Assigned(SourceData)) or (SourceData.NodeType <> ntItem) then Exit;

  if TargetNode = SourceNode then Exit;

  if (TargetData.Item.Level in [TItemLevel.Proc, TItemLevel.Item, TItemLevel.Action])
     and (SourceData.Item.Parent <> TargetData.Item.Id)
     and not IsTargetInSourceSubtree(SourceData.Item, TargetData.Item) then
  begin
    Accept := True;
    Effect := DROPEFFECT_MOVE;
    Exit;
  end;

  if SourceData.Item.Parent <> TargetData.Item.Parent then Exit;

  Accept := True;
  Effect := DROPEFFECT_MOVE;
end;

procedure TframeItemTree.TreeDragDrop(Sender: TBaseVirtualTree; Source: TObject;
  DataObject: IDataObject; Formats: TFormatArray; Shift: TShiftState;
  Pt: TPoint; var Effect: Integer; Mode: TDropMode);
var
  TargetNode, SourceNode, Node: PVirtualNode;
  TargetData, SourceData, NodeData: PNodeData;
  ParentNode: PVirtualNode;
  Siblings: TItems;
  SourceIdx, TargetIdx, InsertAt: integer;
begin
  if not (Source is TBaseVirtualTree) then Exit;

  TargetNode := Sender.GetNodeAt(Pt);
  if not Assigned(TargetNode) then Exit;

  SourceNode := TBaseVirtualTree(Source).GetFirstSelected;
  if not Assigned(SourceNode) then Exit;

  TargetData := Sender.GetNodeData(TargetNode);
  SourceData := TBaseVirtualTree(Source).GetNodeData(SourceNode);
  if (not Assigned(TargetData)) or (not Assigned(SourceData)) then Exit;
  if (TargetData.NodeType <> ntItem) or (SourceData.NodeType <> ntItem) then Exit;
  if TargetNode = SourceNode then Exit;

  // Re-check cycles at drop time:
  // TreeDragOver already checks, but the tree can change before TreeDragDrop.
  if (TargetData.Item.Level in [TItemLevel.Proc, TItemLevel.Item, TItemLevel.Action])
     and (SourceData.Item.Parent <> TargetData.Item.Id)
     and not IsTargetInSourceSubtree(SourceData.Item, TargetData.Item) then
  begin
    if not FVM.ReparentItem(SourceData.Item, TargetData.Item.Id) then Exit;
    FillTree(FLocation);
    Exit;
  end;

  if SourceData.Item.Parent <> TargetData.Item.Parent then Exit;

  Siblings := TItems.Create;
  try
    ParentNode := Sender.NodeParent[SourceNode];
    if ParentNode = Sender.RootNode then
      Node := Sender.GetFirst
    else
      Node := Sender.GetFirstChild(ParentNode);

    while Assigned(Node) do
    begin
      NodeData := Sender.GetNodeData(Node);
      if Assigned(NodeData) and (NodeData.NodeType = ntItem) then
        Siblings.Add(NodeData.Item);
      Node := Sender.GetNextSibling(Node);
    end;

    SourceIdx := Siblings.IndexOf(SourceData.Item);
    TargetIdx := Siblings.IndexOf(TargetData.Item);
    if (SourceIdx < 0) or (TargetIdx < 0) then Exit;

    Siblings.Delete(SourceIdx);
    if SourceIdx < TargetIdx then
      Dec(TargetIdx);

    if Mode = dmAbove then
      InsertAt := TargetIdx
    else
      InsertAt := TargetIdx + 1;

    Siblings.Insert(InsertAt, SourceData.Item);

    Model.Items.ReorderItems(Siblings);
    FillTree(FLocation);
  finally
    Siblings.Free;
  end;
end;

procedure TframeItemTree.TreeGetPopupMenu(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; const P: TPoint;
  var AskParent: Boolean; var PopupMenu: TPopupMenu);
var
  Data: PNodeData;
  IsProc, IsItem, IsAction, IsFolder: Boolean;
begin
  PopupMenu := nil;
  AskParent := False;
  if not Assigned(Node) then Exit;
  if FVM.IsReadOnly then Exit;

  Tree.FocusedNode := Node;
  Tree.Selected[Node] := True;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  var CanEdit: Boolean := Assigned(FVM) and FVM.CanEdit;

  case Data.NodeType of
    ntItem: begin
      IsProc   := Data.Item.Level = TItemLevel.Proc;
      IsItem   := Data.Item.Level = TItemLevel.Item;
      IsAction := Data.Item.Level = TItemLevel.Action;
      IsFolder := Data.Item.Level = TItemLevel.Folder;

      var IsSigned: Boolean := FVM.IsItemSigned(Data.Item.Id);


      miItemNew.Visible         := IsProc or IsItem or IsFolder;
      miItemNewFolder.Visible   := IsProc or IsFolder;
      miItemAdd.Visible         := not IsFolder;
      miItemAddValue.Visible    := IsProc or IsAction;
      miItemAnalyze.Visible     := IsProc;
      miItemSep1.Visible        := IsProc or IsItem or IsFolder;

      miItemEdit.Visible        := not IsFolder;
      miItemDuplicate.Visible   := not IsFolder;
      miItemSep2.Visible        := not IsFolder;

      miItemSep3.Visible        := not IsFolder;

      miItemDelete.Visible      := True;

      miItemNew.Enabled         := CanEdit;
      miItemNewFolder.Enabled   := CanEdit;
      miItemEdit.Enabled        := CanEdit and not IsSigned;
      miItemDuplicate.Enabled   := CanEdit;
      miItemMoveTo.Enabled      := CanEdit and not IsSigned;
      miItemMoveTo.Visible      := not IsFolder;
      miItemSort.Visible        := (Data.Item.Parent = 0) and not IsFolder;
      miItemSort.Enabled        := CanEdit;
      miItemAdd.Enabled         := CanEdit and not IsSigned;
      miItemDelete.Enabled      := CanEdit and not IsSigned;

      CreateSignatureMenuItems;
      FmiSignature.Visible              := not IsFolder;
      FmiItemSign.Visible               := not IsSigned;
      FmiItemSign.Enabled               := CanEdit;
      FmiItemViewSignature.Visible      := IsSigned;
      FmiItemVerifyIntegrity.Visible    := IsSigned;

      miItemHypothesis.Visible := not IsFolder;
      miItemAttachHypothesis.Enabled := CanEdit;
      miItemNewHypothesis.Enabled := CanEdit;

      FmiItemBookmark.Visible := not IsFolder;
      FmiItemTags.Visible := not IsFolder;
      FmiItemComments.Visible := not IsFolder;
      if not IsFolder then
      begin
        var CommentCount: Integer := FVM.GetCommentCount(Data.Item.Id);
        if CommentCount > 0 then
          FmiItemComments.Caption := Format('Comments (%d)...', [CommentCount])
        else
          FmiItemComments.Caption := 'Comments...';
      end;
      if not IsFolder then
      begin
        if Model.Favorites.IsFavorite(Model.User.Id, ftItem,
          Data.Item.ProjectID, Data.Item.FolderID, Data.Item.Id) then
          FmiItemBookmark.Caption := 'Remove from Favorites'
        else
          FmiItemBookmark.Caption := 'Add to Favorites';
      end;

      PopupMenu := pmItem;
    end;
    ntProtocol: begin
      miProtocolEdit.Enabled := CanEdit;
      miProtocolDelete.Enabled := CanEdit;
      PopupMenu := pmProtocol;
    end;
    ntFile: begin
      PrepareFilePopup;
      PopupMenu := pmFile;
    end;
  end;
end;


procedure TframeItemTree.miItemNewClick(Sender: TObject);
begin
  BtnNewClick(Sender);
end;

procedure TframeItemTree.miItemNewFolderClick(Sender: TObject);
begin
  BtnNewFolderClick(Sender);
end;

procedure TframeItemTree.miItemEditClick(Sender: TObject);
begin
  BtnEditClick(Sender);
end;

procedure TframeItemTree.miItemDuplicateClick(Sender: TObject);
begin
  BtnDuplicateClick(Sender);
end;

procedure TframeItemTree.miItemAddFileClick(Sender: TObject);
begin
  BtnAddFileClick(Sender);
end;

procedure TframeItemTree.miItemAddNoteClick(Sender: TObject);
begin
  BtnAddNoteClick(Sender);
end;

procedure TframeItemTree.miItemAddProtocolClick(Sender: TObject);
begin
  BtnAddProtocolClick(Sender);
end;

procedure TframeItemTree.miItemAddValueClick(Sender: TObject);
begin
  BtnAddValueClick(Sender);
end;

procedure TframeItemTree.miItemAnalyzeClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  if Data.Item.Level <> TItemLevel.Proc then Exit;
  TfrmAnalysis.Execute(Data.Item.ProjectID, Data.Item.FolderID);
end;

function TframeItemTree.IsTargetInSourceSubtree(Source, Target: TItem): Boolean;
var
  IdToItem: TDictionary<Integer, TItem>;
  Item, Current: TItem;
  Steps: Integer;
begin
  Result := False;
  if (not Assigned(Source)) or (not Assigned(Target)) then Exit;
  if Source.Id = Target.Id then
  begin
    Result := True;
    Exit;
  end;
  IdToItem := TDictionary<Integer, TItem>.Create;
  try
    var SrcItems: TItems := FVM.Items;
    try
      for Item in SrcItems do
        IdToItem.AddOrSetValue(Item.Id, Item);
    finally
      SrcItems.Free;
    end;
    Current := Target;
    Steps := 0;
    while (Current.Parent <> 0) and (Steps < 1000) do
    begin
      if not IdToItem.TryGetValue(Current.Parent, Current) then Break;
      if Current.Id = Source.Id then
      begin
        Result := True;
        Exit;
      end;
      Inc(Steps);
    end;
  finally
    IdToItem.Free;
  end;
end;

procedure TframeItemTree.miItemMoveToClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  SourceItem: TItem;
  NewParentId: Integer;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  SourceItem := Data.Item;

  // FVM.Items is caller-owned; free the LIST after the dialog closes.
  var MoveItems: TItems := FVM.Items;
  try
    if not TdlgItemMove.Execute(SourceItem, MoveItems, NewParentId) then Exit;
  finally
    MoveItems.Free;
  end;
  if NewParentId = SourceItem.Parent then Exit;

  if not FVM.ReparentItem(SourceItem, NewParentId) then Exit;
  FillTree(FLocation);
end;


function TframeItemTree.GetRootItems: TItems;
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Result := TItems.Create;
  Node := Tree.GetFirst;
  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntItem) and (Data.Item.Parent = 0) then
      Result.Add(Data.Item);
    Node := Tree.GetNextSibling(Node);
  end;
end;

procedure TframeItemTree.MoveRootItem(Direction: Integer);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Siblings: TItems;
  Idx: Integer;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  if Data.Item.Parent <> 0 then Exit;
  if not Assigned(FVM) or not FVM.CanEdit then Exit;

  Siblings := GetRootItems;
  try
    Idx := Siblings.IndexOf(Data.Item);
    if Idx < 0 then Exit;
    if (Idx + Direction < 0) or (Idx + Direction >= Siblings.Count) then Exit;

    Siblings.Exchange(Idx, Idx + Direction);
    Model.Items.ReorderItems(Siblings);
    FillTree(FLocation);
    RestoreLastSelection;
  finally
    Siblings.Free;
  end;
end;

procedure TframeItemTree.SortRootItems(AComparer: IComparer<TItem>);
var
  Siblings: TItems;
begin
  if not Assigned(FVM) or not FVM.CanEdit then Exit;

  Siblings := GetRootItems;
  try
    if Siblings.Count < 2 then Exit;
    Siblings.Sort(AComparer);
    Model.Items.ReorderItems(Siblings);
    FillTree(FLocation);
    RestoreLastSelection;
  finally
    Siblings.Free;
  end;
end;

procedure TframeItemTree.miItemSortMoveUpClick(Sender: TObject);
begin
  MoveRootItem(-1);
end;

procedure TframeItemTree.miItemSortMoveDownClick(Sender: TObject);
begin
  MoveRootItem(+1);
end;

procedure TframeItemTree.miItemSortByNameClick(Sender: TObject);
begin
  SortRootItems(TComparer<TItem>.Construct(
    function(const L, R: TItem): Integer
    begin
      Result := CompareText(L.Title, R.Title);
    end));
end;

procedure TframeItemTree.miItemSortByDateClick(Sender: TObject);
begin
  SortRootItems(TComparer<TItem>.Construct(
    function(const L, R: TItem): Integer
    begin
      if L.CreatedDate < R.CreatedDate then
        Result := -1
      else if L.CreatedDate > R.CreatedDate then
        Result := 1
      else
        Result := 0;
    end));
end;

procedure TframeItemTree.miItemDeleteClick(Sender: TObject);
begin
  BtnDeleteClick(Sender);
end;

procedure TframeItemTree.miItemAttachHypothesisClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  VM: THypothesesVM;
  HypId, ItemId, ProjectId: Integer;
  Role: THypothesisRunRole;
  O: TVMOutcome;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  // Copy what we need now: RefreshKeepView -> FillTree -> Tree.Clear frees
  // every node (and evicts the item), so Node/Data dangle after it.
  ItemId := Data.Item.Id;
  ProjectId := Data.Item.ProjectID;
  VM := THypothesesVM.Create(Model.Manager, Model.User, Model.Access);
  try
    if not TdlgHypothesisPick.Execute(VM.AttachableInProject(ProjectId),
      HypId, Role) then
      Exit;
    O := VM.AttachItem(HypId, ItemId, Role);
    if not O.Ok then
      MessageDlg(O.Message, mtWarning, [mbOK], 0)
    else
    begin
      RefreshKeepView;   
      if Assigned(FOnOpenHypotheses) then
        FOnOpenHypotheses(Self, ProjectId, HypId);
    end;
  finally
    VM.Free;
  end;
end;

procedure TframeItemTree.miItemNewHypothesisClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  VM: THypothesesVM;
  T, S, C, ItemTitle: string;
  K, ItemId, ProjectId: Integer;
  O: TVMOutcome;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  // Copy before the modal dialog: a broadcast handled while it is open can
  // rebuild the tree (MessageListener -> FillTree), freeing Node/Data.
  ItemId := Data.Item.Id;
  ProjectId := Data.Item.ProjectID;
  ItemTitle := Data.Item.Title;
  T := ''; S := ''; C := ''; K := 0;
  if not TdlgHypothesisEdit.Execute('New hypothesis from "' + ItemTitle + '"',
    False, T, S, C, K) then
    Exit;
  VM := THypothesesVM.Create(Model.Manager, Model.User, Model.Access);
  try
    O := VM.ProposeFromItem(ItemId, T, S, K);
    if not O.Ok then
      MessageDlg(O.Message, mtWarning, [mbOK], 0)
    else
    begin
      if Assigned(FOnHypothesisDecisionsChanged) then
        FOnHypothesisDecisionsChanged(Self);   
      if Assigned(FOnOpenHypotheses) then
        FOnOpenHypotheses(Self, ProjectId, VM.SelectedId);
    end;
  finally
    VM.Free;
  end;
end;

procedure TframeItemTree.miItemRefreshClick(Sender: TObject);
begin
  btnRefreshClick(Sender);
end;

procedure TframeItemTree.QueueRegenFile(AFile: unit_Item.TFile; ParentItem: TItem;
  
  var Queue: TArray<TPreviewQueueItem>; var Skipped: Integer);
var
  QItem: TPreviewQueueItem;
  FilePath: string;
begin
  if not Assigned(AFile) or not Assigned(ParentItem) then Exit;

  SetStatusText(Format('Downloading file %d...', [Length(Queue) + Skipped + 1]));
  FilePath := PrepareFile(AFile.Id);

  if not FileExists(FilePath) then
  begin
    Inc(Skipped);
    Exit;
  end;

  QItem.FileId := AFile.Id;
  QItem.ItemId := ParentItem.Id;
  QItem.FilePath := FilePath;
  QItem.PreviewPath := GetPreviewPath(ParentItem.Id, AFile.Id);
  QItem.Extension := AFile.FileType.Ext;
  Queue := Queue + [QItem];
end;

procedure TframeItemTree.CollectRegenFiles(Node: PVirtualNode; Recurse: Boolean;
  var Queue: TArray<TPreviewQueueItem>; var Skipped: Integer);
var
  Child: PVirtualNode;
  Data, ParentData, NodeData: PNodeData;
  AFile: unit_Item.TFile;
begin
  // Wiki items have no file-children in the tree (see FillTree). Enumerate
  // their files directly so "Regenerate previews" still covers the page body
  // and any attachments.
  NodeData := Tree.GetNodeData(Node);
  if Assigned(NodeData) and (NodeData.NodeType = ntItem) and
     (NodeData.Item.Type_ = TItemType.Wiki) then
  begin
    for AFile in NodeData.Item.Files do
      QueueRegenFile(AFile, NodeData.Item, Queue, Skipped);
  end;

  Child := Tree.GetFirstChild(Node);
  while Assigned(Child) do
  begin
    Data := Tree.GetNodeData(Child);
    if Assigned(Data) then
    begin
      if Data.NodeType = ntFile then
      begin
        ParentData := Tree.GetNodeData(Child.Parent);
        if Assigned(ParentData) and (ParentData.NodeType = ntItem) then
          QueueRegenFile(Data.AFile, ParentData.Item,
            Queue, Skipped);
      end
      else if (Data.NodeType = ntItem) and Recurse then
        CollectRegenFiles(Child, True, Queue, Skipped);
    end;
    Child := Tree.GetNextSibling(Child);
  end;
end;

procedure TframeItemTree.miItemRegenPreviewsClick(Sender: TObject);
var
  Node, StartNode: PVirtualNode;
  Data: PNodeData;
  Queue: TArray<TPreviewQueueItem>;
  Settings: TNotebookSettings;
  Scope: TPreviewScope;
  Skipped: Integer;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;

  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then
  begin
    SetStatusText('Select an item (not a file or protocol) to regenerate previews.');
    Exit;
  end;

  Skipped := 0;
  Screen.Cursor := crHourGlass;
  Settings := TNotebookSettings.Create;
  try
    Scope := Settings.PreviewScope;
      case Scope of
        psCurrentItem:
          CollectRegenFiles(Node, False, Queue, Skipped);

        psItemAndChildren:
          CollectRegenFiles(Node, True, Queue, Skipped);

        psEntireProc:
        begin
          StartNode := FindProcNode(Node);
          if Assigned(StartNode) then
            CollectRegenFiles(StartNode, True, Queue, Skipped)
          else
            CollectRegenFiles(Node, True, Queue, Skipped);
        end;

        psSiblingFiles:
          CollectRegenFiles(Node, True, Queue, Skipped);
      end;
  finally
    Settings.Free;
    Screen.Cursor := crDefault;
  end;

  if Length(Queue) = 0 then
  begin
    SetStatusText(Format('No files found (%d skipped).', [Skipped]));
    Exit;
  end;

  FPreviewQueue.Start(Queue);
end;


procedure TframeItemTree.miFileRegenPreviewClick(Sender: TObject);
begin
  DoUpdatePreview(Sender);
end;

procedure TframeItemTree.miProtocolEditClick(Sender: TObject);
begin
  BtnEditClick(Sender);
end;

procedure TframeItemTree.miProtocolDeleteClick(Sender: TObject);
begin
  BtnDeleteClick(Sender);
end;

procedure TframeItemTree.miProtocolRefreshClick(Sender: TObject);
begin
  btnRefreshClick(Sender);
end;

procedure TframeItemTree.miFileOpenClick(Sender: TObject);
begin
  TreeDblClick(Sender);
end;

procedure TframeItemTree.miFileExtractValuesClick(Sender: TObject);
var
  Node, ParentNode: PVirtualNode;
  Data, ParentData: PNodeData;
  AFile: unit_Item.TFile;
  ParentItem: TItem;
  Plugin: IViewerPlugin;
  KVProvider: IKeyValueProvider;
  KeyValues: TArray<TPluginKeyValue>;
  FilePath: string;
begin
  if not Assigned(FVM) or not FVM.CanEdit then Exit;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntFile) then Exit;
  AFile := Data.AFile;

  ParentNode := Tree.NodeParent[Node];
  if not Assigned(ParentNode) then Exit;
  ParentData := Tree.GetNodeData(ParentNode);
  if not Assigned(ParentData) or (ParentData.NodeType <> ntItem) then Exit;
  ParentItem := ParentData.Item;

  Plugin := FContentViewer.FindPlugin(AFile.FullName);
  if not Assigned(Plugin) then
  begin
    ShowMessage('No viewer plugin available for this file type.');
    Exit;
  end;

  if not Supports(Plugin, IKeyValueProvider, KVProvider) then
  begin
    ShowMessage('This file type does not support value extraction.');
    Exit;
  end;

  FilePath := PrepareFile(AFile.Id);

  if not FileExists(FilePath) then
  begin
    ShowMessage('File not found: ' + FilePath);
    Exit;
  end;

  if not Plugin.LoadFromFile(FilePath) then
  begin
    ShowMessage('Plugin could not load the file.');
    Exit;
  end;

  KeyValues := KVProvider.GetKeyValues;
  if Length(KeyValues) = 0 then
  begin
    ShowMessage('No values found in this file.');
    Exit;
  end;

  if ShowExtractValuesDialog(KeyValues, ParentItem, FVM.UserId) then
  begin
    FVM.SelectItem(ParentItem.Id, AFile.Id);
    FillTree(FLocation);
    RestoreLastSelection;
  end;
end;

procedure TframeItemTree.miFileExportClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  AFile: unit_Item.TFile;
  SourcePath, OrigName: string;
  Dlg: TSaveDialog;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntFile) then Exit;
  AFile := Data.AFile;

  SourcePath := StringReplace(Model.GetFileName(AFile.Id), '\', '/', [rfReplaceAll]);

  OrigName := AFile.Title + AFile.FileType.Ext;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Export File';
    Dlg.FileName := OrigName;
    Dlg.Filter := Format('%s (*%s)|*%s|All files (*.*)|*.*',
      [AFile.FileType.Description, AFile.FileType.Ext, AFile.FileType.Ext]);
    Dlg.DefaultExt := Copy(AFile.FileType.Ext, 2); 
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if Dlg.Execute then
      Model.Storage.CopyOut(SourcePath, Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TframeItemTree.miFileReuploadClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  AFile: unit_Item.TFile;
  SourcePath, TargetPath, NewHash, NewExt, FilterStr, OldPath: string;
  BackupPath, CheckPath, BaselineHash, Failure: string;
  BaselineVersion: Integer;
  Transaction: IDBTransaction;
  ItemsModel: TItemModel;
  Written, KeepBackup: Boolean;
  Project: TProject;
  Manager: TObjectManager;
  FileEntity: unit_Item.TFile;
  NewFileType: unit_FileType.TFileType;
  LinkedTypes: TFileTypes;
  Dlg: TOpenDialog;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntFile) then Exit;
  AFile := Data.AFile;
  if not Assigned(AFile.Item) or not FVM.CanEdit or
    FVM.IsItemSigned(AFile.Item.Id) then Exit;
  OldPath := StringReplace(Model.GetFileName(AFile.Id), '\', '/', [rfReplaceAll]);
  BaselineVersion := AFile.Version;
  BackupPath := TPath.GetTempFileName;
  CheckPath := TPath.GetTempFileName;
  KeepBackup := False;
  try
    Model.Storage.CopyOut(OldPath, BackupPath);
    BaselineHash := ComputeFileHash(BackupPath);

  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'Select replacement file';
    FilterStr := Format('%s (*%s)|*%s',
      [AFile.FileType.Description, AFile.FileType.Ext, AFile.FileType.Ext]);
    if Assigned(AFile.Item) and Assigned(AFile.Item.ActionType) then
    begin
      LinkedTypes := Model.ActionTypes.GetFileTypes(AFile.Item.ActionType.Id);
      if Assigned(LinkedTypes) then
        for var LFT in LinkedTypes do
          if not SameText(LFT.Ext, AFile.FileType.Ext) then
            FilterStr := FilterStr + Format('|%s (*%s)|*%s',
              [LFT.Description, LFT.Ext, LFT.Ext]);
    end;
    FilterStr := FilterStr + '|All files (*.*)|*.*';
    Dlg.Filter := FilterStr;
    if not Dlg.Execute then Exit;
    SourcePath := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  NewHash := ComputeFileHash(SourcePath);
  if NewHash = '' then
  begin
    MessageDlg('Cannot read the selected file.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  Manager := TObjectManager.Create(Model.Connection);
  try
    Written := False;
    Transaction := Model.Connection.BeginTransaction;
    try
      FileEntity := Manager.Find<unit_Item.TFile>(AFile.Id);
      if not Assigned(FileEntity) or not Assigned(FileEntity.Item) or
        FileEntity.Item.IsDeleted then
        raise EInvalidOperation.Create('The attachment no longer exists.');
      Project := Manager.Find<TProject>(FileEntity.Item.ProjectID);
      if not Assigned(Project) or Project.IsArchived or
        not Model.Access.CanWrite(Manager, Manager.Find<TUser>(Model.User.Id), Project.Id) or
        IsItemSignedCheck(Manager, FileEntity.Item.Id) then
        raise EInvalidOperation.Create('The attachment cannot be changed.');
      if FileEntity.Version <> BaselineVersion then
        raise EInvalidOperation.Create('File metadata changed. Refresh before replacing it.');
      Model.Storage.CopyOut(OldPath, CheckPath);
      if not SameText(ComputeFileHash(CheckPath), BaselineHash) then
        raise EInvalidOperation.Create('File bytes changed. Refresh before replacing it.');
      NewExt := LowerCase(ExtractFileExt(SourcePath));
      NewFileType := Model.FileTypes.GetFileTypeByExt(NewExt);
      if Assigned(NewFileType) then
        FileEntity.FileType := Manager.Find<unit_FileType.TFileType>(NewFileType.Id);
      TargetPath := Format('Projects/%s/%s/%s',
        [CleanFileName(Project.FileFolder), CleanFileName(FileEntity.Item.FolderName),
         FileEntity.FullName]);
      if (TargetPath <> OldPath) and Model.Storage.Exists(TargetPath) then
        raise EInvalidOperation.Create('The replacement destination already exists.');
      Written := True;
      Model.Storage.CopyIn(SourcePath, TargetPath);
      FileEntity.Hash := NewHash;
      ItemsModel := TItemModel.Create(Manager);
      try
        if not ItemsModel.UpdateFile(FileEntity, Model.User.Id) then
          raise EInvalidOperation.Create('File metadata update conflicted.');
        RecordAudit(Manager, aetFile, FileEntity.Id, aoUpdate, Model.User.Id,
          'Replaced attachment "' + FileEntity.Title + '"');
        Transaction.Commit;
      finally
        ItemsModel.Free;
      end;
    except
      on E: Exception do
      begin
        Failure := E.Message;
        KeepBackup := Written;
        try
          Transaction.Rollback;
          if Written then
          begin
            Model.Storage.CopyIn(BackupPath, OldPath);
            if TargetPath <> OldPath then Model.Storage.DeleteFile(TargetPath);
            KeepBackup := False;
          end;
        except
          on R: Exception do Failure := Failure + '; recovery failed: ' + R.Message +
            '; original bytes retained at ' + BackupPath;
        end;
        raise EInvalidOperation.Create(Failure);
      end;
    end;
    if TargetPath <> OldPath then Model.Storage.DeleteFile(OldPath);
    Model.Items.EvictCache;
  finally
    Manager.Free;
    Screen.Cursor := crDefault;
  end;

  MessageDlg('File reuploaded successfully.', mtInformation, [mbOK], 0);

  // The host resolves retained drafts and refreshes only after confirmation.
  // A second display request here would discard a kept viewer's unsaved edits.
  FileContentChanged(AFile.Id);

  // Refresh metadata without overriding the host's display decision.
  FillTree(FLocation);
  SelectFile(AFile.Id);
  finally
    if not KeepBackup then System.SysUtils.DeleteFile(BackupPath);
    System.SysUtils.DeleteFile(CheckPath);
  end;
end;

procedure TframeItemTree.miFileMoveToClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  AFile: unit_Item.TFile;
  DestItem: TItem;
  Dlg: TForm;
  LB: TListBox;
  Items: TList<TItem>;
  I, SelIdx, OldItemId: Integer;
  OldPath, NewPath: string;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntFile) then Exit;
  AFile := Data.AFile;
  if not Assigned(AFile.Item) or not FVM.CanEdit or
    FVM.IsItemSigned(AFile.Item.Id) then Exit;

  Items := TList<TItem>.Create;
  try
    // FVM.Items is caller-owned; free the source LIST after copying refs.
    var AllSrc: TItems := FVM.Items;
    try
      for DestItem in AllSrc do
        if DestItem.Id <> AFile.Item.Id then
          Items.Add(DestItem);
    finally
      AllSrc.Free;
    end;

    Dlg := TForm.CreateNew(Application);
    try
      Dlg.Caption := 'Move file "' + AFile.Title + '" to...';
      Dlg.Position := poMainFormCenter;
      Dlg.Width := 400;
      Dlg.Height := 400;
      Dlg.BorderStyle := bsDialog;

      LB := TListBox.Create(Dlg);
      LB.Parent := Dlg;
      LB.Align := alClient;
      LB.Font.Size := 10;
      LB.AlignWithMargins := True;
      LB.Margins.SetBounds(8, 8, 8, 0);

      for I := 0 to Items.Count - 1 do
      begin
        DestItem := Items[I];
        if DestItem.Parent = 0 then
          LB.Items.AddObject(DestItem.Title, TObject(DestItem.Id))
        else
          LB.Items.AddObject('    ' + DestItem.Title, TObject(DestItem.Id));
      end;

      with TButton.Create(Dlg) do
      begin
        Parent := Dlg;
        Caption := 'Move';
        ModalResult := mrOk;
        Align := alBottom;
        AlignWithMargins := True;
        Margins.SetBounds(8, 8, 8, 8);
        Height := 32;
        Default := True;
      end;

      LB.ItemIndex := 0;

      if (Dlg.ShowModal = mrOk) and (LB.ItemIndex >= 0) then
      begin
        SelIdx := Integer(LB.Items.Objects[LB.ItemIndex]);
        DestItem := Model.Items.GetItem(SelIdx);
        if not Assigned(DestItem) or DestItem.IsDeleted or
          FVM.IsItemSigned(DestItem.Id) or
          not Model.Access.CanWrite(Model.Manager, Model.User, DestItem.ProjectID) then Exit;
        if SelIdx <> AFile.Item.Id then
        begin
          OldItemId := AFile.Item.Id;
          OldPath := StringReplace(Model.GetFileName(AFile.Id), '\', '/', [rfReplaceAll]);
          if not Model.Items.MoveFile(AFile, SelIdx, Model.User.Id) then Exit;
          NewPath := StringReplace(Model.GetFileName(AFile.Id), '\', '/', [rfReplaceAll]);
          try
            if OldPath <> NewPath then Model.Storage.MoveFile(OldPath, NewPath);
          except
            Model.Items.MoveFile(AFile, OldItemId, Model.User.Id);
            raise;
          end;

          FillTree(FLocation);
        end;
      end;
    finally
      Dlg.Free;
    end;
  finally
    Items.Free;
  end;
end;

procedure TframeItemTree.miFileEditClick(Sender: TObject);
begin
  BtnEditClick(Sender);
end;

procedure TframeItemTree.miFileCopyPathClick(Sender: TObject);
begin
  if FCurrentFile <= 0 then Exit;
  Clipboard.AsText := PrepareFile(FCurrentFile);
end;

procedure TframeItemTree.miFileDeleteClick(Sender: TObject);
begin
  BtnDeleteClick(Sender);
end;

procedure TframeItemTree.miFileRefreshClick(Sender: TObject);
begin
  btnRefreshClick(Sender);
end;

procedure TframeItemTree.miItemCopyMCPLinkClick(Sender: TObject);
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntItem) then Exit;
  Clipboard.AsText := Format('get_item(item_id: %d)', [Data.Item.Id]);
end;

procedure TframeItemTree.miProtocolCopyMCPLinkClick(Sender: TObject);
var
  Data, ParentData: PNodeData;
  Node, ParentNode: PVirtualNode;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntProtocol) then Exit;

  ParentNode := Node.Parent;
  if not Assigned(ParentNode) or (ParentNode = Tree.RootNode) then Exit;
  ParentData := Tree.GetNodeData(ParentNode);
  if (not Assigned(ParentData)) or (ParentData.NodeType <> ntItem) then Exit;

  Clipboard.AsText := Format('get_protocols(item_id: %d)', [ParentData.Item.Id]);
end;

procedure TframeItemTree.miFileCopyMCPLinkClick(Sender: TObject);
var
  Data: PNodeData;
  Node: PVirtualNode;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if (not Assigned(Data)) or (Data.NodeType <> ntFile) then Exit;
  Clipboard.AsText := Format('extract_file_data(file_id: %d)', [Data.AFile.Id]);
end;

procedure TframeItemTree.btnRefreshClick(Sender: TObject);
begin
  if not Assigned(FVM) then Exit;
  if FLocation.ProjectID > 0 then
  begin
    FVM.EvictCache;
    FillTree(FLocation);
    RestoreLastSelection;
  end;
end;

procedure TframeItemTree.SaveItemExpanded(Node: PVirtualNode; Value: Boolean);
var
  D: PNodeData;
begin
  if FFilling or not Assigned(FVM) or not Assigned(Node) then Exit;
  D := Tree.GetNodeData(Node);
  if Assigned(D) and (D.NodeType = ntItem) and Assigned(D.Item) then
    FVM.SetItemExpanded(D.Item.Id, Value);
end;

procedure TframeItemTree.TreeItemExpanded(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  SaveItemExpanded(Node, True);
end;

procedure TframeItemTree.TreeItemCollapsed(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  SaveItemExpanded(Node, False);
end;

procedure TframeItemTree.btnExpandCollapseClick(Sender: TObject);
var
  IsExpanded: Boolean;
begin
  // Decide by what is on screen: FullCollapse can leave hidden nodes expanded
  // (under a collapsed last root), which kept this button collapsing forever.
  IsExpanded := TreeHasVisibleExpanded(Tree);

  Tree.BeginUpdate;
  try
    if IsExpanded then
    begin
      Tree.FullCollapse;
      btnExpandCollapse.ImageIndex := 10;
      btnExpandCollapse.Hint := 'Expand All';
    end
    else
    begin
      Tree.FullExpand;
      btnExpandCollapse.ImageIndex := 11;
      btnExpandCollapse.Hint := 'Collapse All';
    end;
  finally
    Tree.EndUpdate;
  end;
end;


function TframeItemTree.RowColor(Node: PVirtualNode): TColor;
var
  Data: PNodeData;
begin
  Result := CDefaultColor;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;
  case Data.NodeType of
    ntItem:
      if Assigned(Data.Item) then
        Result := ItemTypeColor(Data.Item.Type_);
    ntFile:
      Result := ItemFileColor;
    ntProtocol:
      if Assigned(Data.Protocol) and Data.Protocol.ProtocolType.HasValue and
         (Data.Protocol.ProtocolType.Value = ptNote) then
        Result := ItemNoteColor
      else
        Result := ItemProtocolColor;
  end;
end;

procedure TframeItemTree.TreeBeforeCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
begin
  if Assigned(FLook) then
    FLook.BeforeCellPaint(TargetCanvas, Node, CellPaintMode, CellRect, ContentRect);
end;

procedure TframeItemTree.TreePaintText(Sender: TBaseVirtualTree;
  const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  TextType: TVSTTextType);
var
  Data: PNodeData;
begin
  if Assigned(FLook) then
    FLook.PaintText(TargetCanvas, Node, Column);
  if vsSelected in Node.States then Exit;
  Data := Sender.GetNodeData(Node);
  if Assigned(Data) and (Data.NodeType in [ntProtocol, ntFile]) then
    TargetCanvas.Font.Color := MixColor(
      StyleServices.GetSystemColor(TargetCanvas.Font.Color),
      TreeRowBackground(Sender, nil), 0.45);
end;

procedure TframeItemTree.btnClearSearchClick(Sender: TObject);
begin
  edSearch.Text := '';
end;

procedure TframeItemTree.edSearchChange(Sender: TObject);
begin
  FFilterText := edSearch.Text;
  if FLocation.ProjectID > 0 then
  begin
    FillTree(FLocation);
    RestoreLastSelection;
  end;
end;

procedure TframeItemTree.RestoreLastSelection;
begin
  if Assigned(FSelectedNode) then
  begin
    Tree.Selected[FSelectedNode] := True;
    Tree.FocusedNode := FSelectedNode;
    TreeClick(Tree);
    FSelectedNode := nil; 
  end;
end;

procedure TframeItemTree.RefreshKeepView;
var
  Node, ParentNode: PVirtualNode;
  Data, ParentData: PNodeData;
begin
  if FLocation.ProjectID <= 0 then
    Exit;
  FVM.EvictCache;
  FillTree(FLocation);   // blanks the header; FItem is now an evicted instance
  Node := FSelectedNode;
  FSelectedNode := nil;
  Data := nil;
  if Assigned(Node) then
    Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then
  begin
    FItem := nil;
    FCurrentFile := -1;
    UpdateInfoColors(CDefaultColor);
    UpdateFileButtons;
    Exit;
  end;
  Tree.Selected[Node] := True;
  Tree.FocusedNode := Node;
  Tree.ScrollIntoView(Node, False);

  ParentData := nil;
  ParentNode := Node.Parent;
  if Assigned(ParentNode) and (ParentNode <> Tree.RootNode) then
    ParentData := Tree.GetNodeData(ParentNode);
  case Data.NodeType of
    ntItem:
      begin
        FItem := Data.Item;
        FCurrentFile := -1;
        DisplayItemInfo(FItem);
      end;
    ntProtocol:
      begin
        FCurrentFile := 0;
        if Data.Protocol.ProtocolType.HasValue and
          (Data.Protocol.ProtocolType.Value = ptNote) then
          UpdateInfoColors(ItemNoteColor)
        else
          UpdateInfoColors(ItemProtocolColor);
        lblName.Caption := Data.Protocol.Title;
        lblDetails.Caption := '';
        FItem := nil;
        if Assigned(ParentData) and (ParentData.NodeType = ntItem) then
          FItem := ParentData.Item;
      end;
    ntFile:
      begin
        FCurrentFile := Data.AFile.Id;
        DisplayFileInfo(Data.AFile);
        FItem := nil;
        if Assigned(ParentData) and (ParentData.NodeType = ntItem) then
          FItem := ParentData.Item;
      end;
  else
    FItem := nil;
  end;
  UpdateFileButtons;
end;

procedure TframeItemTree.tmrStartupTimer(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  tmrStartup.Enabled := False;
  if not Assigned(FVM) then Exit;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if Assigned(Data) and (Data.NodeType = ntFile) then
    TreeClick(Tree);
end;

function TframeItemTree.SelectedItemId: Integer;
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Result := 0;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then
    Exit;
  Data := Tree.GetNodeData(Node);
  if Assigned(Data) and (Data.NodeType = ntItem) and Assigned(Data.Item) then
    Result := Data.Item.Id;
end;

procedure TframeItemTree.SelectItem(ItemId: Integer);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirst;
  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntItem) and (Data.Item.Id = ItemId) then
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

procedure TframeItemTree.PrepareFilePopup;
var
  CanEdit: Boolean;
begin
  CanEdit := Assigned(FVM) and FVM.CanEdit;
  miFileReupload.Enabled := CanEdit;
  miFileMoveTo.Enabled := CanEdit;
  miFileDelete.Enabled := CanEdit;
end;

procedure TframeItemTree.ShowFilePopup(FileId: Int64);
var
  P: TPoint;
begin
  if FVM.IsReadOnly then Exit;
  if not SelectFile(FileId) then Exit;
  PrepareFilePopup;
  P := Mouse.CursorPos;
  pmFile.Popup(P.X, P.Y);
end;

function TframeItemTree.SelectFile(FileId: Int64): Boolean;
var
  Node, OwnerNode: PVirtualNode;
  Data: PNodeData;
  AFile: unit_Item.TFile;
begin
  Result := False;
  if not Assigned(FVM) then Exit;
  AFile := Model.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(AFile) or not Assigned(AFile.Item) then Exit;
  OwnerNode := nil;
  Node := Tree.GetFirst;
  while Assigned(Node) do
  begin
    Data := Tree.GetNodeData(Node);
    if Assigned(Data) and (Data.NodeType = ntItem) and
      (Data.Item.Id = AFile.Item.Id) then
      OwnerNode := Node;
    if Assigned(Data) and (Data.NodeType = ntFile) and (Data.AFile.Id = FileId) then
    begin
      Tree.ClearSelection;
      Tree.Selected[Node] := True;
      Tree.FocusedNode := Node;
      Tree.ScrollIntoView(Node, True);
      FCurrentFile := FileId;
      FItem := Data.AFile.Item;
      DisplayFileInfo(Data.AFile);
      if Assigned(FItem) then
        FVM.SelectItem(FItem.Id, FileId);
      UpdateFileButtons;
      Exit(True);
    end;
    Node := Tree.GetNext(Node);
  end;
  if Assigned(OwnerNode) then
  begin
    Tree.ClearSelection;
    Tree.Selected[OwnerNode] := True;
    Tree.FocusedNode := OwnerNode;
    Tree.ScrollIntoView(OwnerNode, True);
    FCurrentFile := FileId;
    FItem := AFile.Item;
    DisplayFileInfo(AFile);
    FVM.SelectItem(FItem.Id, 0);
    UpdateFileButtons;
    // Keep False: a file popup on this item node could delete its owner.
  end;
end;

procedure TframeItemTree.CreateSignatureMenuItems;
begin
  if Assigned(FmiSignature) then Exit; 

  FmiSignature := TMenuItem.Create(pmItem);
  FmiSignature.Caption := 'Signature';
  FmiSignature.ImageIndex := 16; 

  FmiItemSign := TMenuItem.Create(FmiSignature);
  FmiItemSign.Caption := 'Sign Item...';
  FmiItemSign.ImageIndex := 18; 
  FmiItemSign.OnClick := miItemSignClick;
  FmiSignature.Add(FmiItemSign);

  FmiItemViewSignature := TMenuItem.Create(FmiSignature);
  FmiItemViewSignature.Caption := 'View Signature...';
  FmiItemViewSignature.ImageIndex := 55; 
  FmiItemViewSignature.OnClick := miItemViewSignatureClick;
  FmiSignature.Add(FmiItemViewSignature);

  FmiItemVerifyIntegrity := TMenuItem.Create(FmiSignature);
  FmiItemVerifyIntegrity.Caption := 'Verify Integrity';
  FmiItemVerifyIntegrity.ImageIndex := 53; 
  FmiItemVerifyIntegrity.OnClick := miItemVerifyIntegrityClick;
  FmiSignature.Add(FmiItemVerifyIntegrity);

  // The popup is grouped by lifecycle: create / modify / annotate / link /
  // delete / utility. The DFM holds the create, modify, delete and utility
  // groups plus the five separators; the annotate group is inserted after
  // miItemSep2 and the link group after miItemSep3, so the runtime items land
  // inside their own group rather than wherever they happened to be appended.

  FmiItemBookmark := TMenuItem.Create(pmItem);
  FmiItemBookmark.Caption := 'Add to Favorites';
  FmiItemBookmark.ImageIndex := 58; 
  FmiItemBookmark.OnClick := miItemBookmarkClick;
  pmItem.Items.Insert(pmItem.Items.IndexOf(miItemSep2) + 1, FmiItemBookmark);

  FmiItemTags := TMenuItem.Create(pmItem);
  FmiItemTags.Caption := 'Tags...';
  FmiItemTags.ImageIndex := 43; 
  FmiItemTags.OnClick := miItemTagsClick;
  pmItem.Items.Insert(pmItem.Items.IndexOf(FmiItemBookmark) + 1, FmiItemTags);

  FmiItemComments := TMenuItem.Create(pmItem);
  FmiItemComments.Caption := 'Comments...';
  FmiItemComments.ImageIndex := 23; 
  FmiItemComments.OnClick := miItemCommentsClick;
  pmItem.Items.Insert(pmItem.Items.IndexOf(FmiItemTags) + 1, FmiItemComments);

  pmItem.Items.Insert(pmItem.Items.IndexOf(FmiItemComments) + 1, FmiSignature);

  FmiCopyLinkTarget := TMenuItem.Create(pmItem);
  FmiCopyLinkTarget.Caption := 'Copy as Link Target';
  FmiCopyLinkTarget.OnClick := miCopyLinkTargetClick;
  pmItem.Items.Insert(pmItem.Items.IndexOf(miItemSep3) + 1, FmiCopyLinkTarget);

  FmiLinkTo := TMenuItem.Create(pmItem);
  FmiLinkTo.Caption := 'Link to...';
  FmiLinkTo.OnClick := miLinkToClick;
  pmItem.Items.Insert(pmItem.Items.IndexOf(FmiCopyLinkTarget) + 1, FmiLinkTo);

  pmItem.OnPopup := pmItemPopup;
end;

procedure TframeItemTree.pmItemPopup(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Target: TItem;
begin
  FmiCopyLinkTarget.Visible := False;
  FmiLinkTo.Visible := False;

  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  FmiCopyLinkTarget.Visible := True;

  if not LinkClipboard.HasTarget then Exit;
  if LinkClipboard.ItemId = Data.Item.Id then Exit;

  if not Model.Access.CanWrite(Model.Manager, Model.User, Data.Item.ProjectID) then Exit;

  Target := Model.Items.GetItem(LinkClipboard.ItemId);
  if (not Assigned(Target)) or Target.IsDeleted then
  begin
    LinkClipboard.Clear;
    Exit;
  end;

  FmiLinkTo.Visible := True;

  if Model.ItemLinks.IsLinked(Data.Item.Id, LinkClipboard.ItemId) then
  begin
    FmiLinkTo.Caption := Format('Already linked to ''%s''', [LinkClipboard.Title]);
    FmiLinkTo.Enabled := False;
  end
  else
  begin
    FmiLinkTo.Caption := Format('Link to ''%s''...', [LinkClipboard.Title]);
    FmiLinkTo.Enabled := True;
  end;
end;


const
  LINKS_MAX_ROWS = 3;
  // fsFlatRounded draws a 2px edge top and bottom.
  LINKS_PANEL_BORDER = 4;

procedure TframeItemTree.FillLinksPanel(ItemId: Integer);
var
  Info: TItemLinkInfo;
  Node: PVirtualNode;
  Data: PLinkNodeData;
  Shown, I, RowsH: Integer;
begin
  // Captured once, before the panel is ever grown. Taking it from the live
  // control rather than a 96-DPI constant means this monitor's scaling is
  // already baked in and nothing below needs MulDiv.
  if FDetailsBaseHeight = 0 then
    FDetailsBaseHeight := pnlBottom.Height;

  FDetailLinks := Model.ItemLinks.GetLinksForItem(ItemId);

  if Length(FDetailLinks) = 0 then
  begin
    vstLinks.Clear;
    pnlLinks.Visible := False;
    pnlBottom.Height := FDetailsBaseHeight;
    Exit;
  end;

  vstLinks.BeginUpdate;
  try
    vstLinks.Clear;

    Shown := Length(FDetailLinks);
    if Shown > LINKS_MAX_ROWS then
      Shown := LINKS_MAX_ROWS;

    for I := 0 to Shown - 1 do
    begin
      Info := FDetailLinks[I];
      Node := vstLinks.AddChild(nil);
      Data := vstLinks.GetNodeData(Node);
      Data.LinkedItemId := Info.LinkedItemId;
      Data.LinkedProjectId := Info.LinkedItemProjectId;
      Data.RelationText := Info.RelationText;
      if Info.LinkedProjectName <> '' then
        Data.Display := Info.LinkedItemTitle + '   (' + Info.LinkedProjectName + ')'
      else
        Data.Display := Info.LinkedItemTitle;
      Data.Notes := Info.Notes;
      Data.IsSource := Info.IsSource;
      Data.IsMoreRow := False;
    end;

    if Length(FDetailLinks) > LINKS_MAX_ROWS then
    begin
      Node := vstLinks.AddChild(nil);
      Data := vstLinks.GetNodeData(Node);
      Data.RelationText := '';
      Data.Display := Format('+%d more...',
        [Length(FDetailLinks) - LINKS_MAX_ROWS]);
      Data.IsMoreRow := True;
    end;
  finally
    vstLinks.EndUpdate;
  end;

  pnlLinks.Visible := True;

  // pnlLinks is alTop, so growing pnlBottom alone does NOT grow it: an aligned
  // child keeps its own height and the extra space merely opens up below it,
  // leaving vstLinks (alClient inside pnlLinks) clipped to a sliver. Size the
  // panel to its content FIRST, then size the container to where the panel
  // actually ends.
  RowsH := Integer(vstLinks.RootNodeCount) * vstLinks.DefaultNodeHeight;

  pnlLinks.Height :=
      pnlLinksHeader.Height
    + pnlLinksHeader.Margins.Top + pnlLinksHeader.Margins.Bottom
    + RowsH
    + vstLinks.Margins.Top + vstLinks.Margins.Bottom
    + LINKS_PANEL_BORDER;

  pnlBottom.Height :=
      pnlLinks.Top + pnlLinks.Height + pnlLinks.Margins.Bottom
    + LINKS_PANEL_BORDER;
end;

procedure TframeItemTree.vstLinksGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TLinkNodeData);
end;

procedure TframeItemTree.vstLinksGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
var
  Data: PLinkNodeData;
begin
  CellText := '';
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  if Column <= 0 then
  begin
    if Data.IsMoreRow then
      CellText := ''
    else if Data.IsSource then
      CellText := #$2192 + '  ' + Data.RelationText
    else
      CellText := #$2190 + '  ' + Data.RelationText;
  end
  else
    CellText := Data.Display;
end;

procedure TframeItemTree.vstLinksGetHint(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex;
  var LineBreakStyle: TVTTooltipLineBreakStyle; var HintText: string);
var
  Data: PLinkNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if Assigned(Data) then
    HintText := Data.Notes;
end;

procedure TframeItemTree.vstLinksNodeClick(Sender: TBaseVirtualTree;
  const HitInfo: THitInfo);
var
  Data: PLinkNodeData;
  Target: TItem;
  FolderId: Integer;
begin
  if not Assigned(HitInfo.HitNode) then Exit;
  Data := Sender.GetNodeData(HitInfo.HitNode);
  if not Assigned(Data) then Exit;

  if Data.IsMoreRow then
  begin
    btnManageLinksClick(nil);
    Exit;
  end;

  FolderId := 0;
  Target := Model.Items.GetItem(Data.LinkedItemId);
  if Assigned(Target) then
    FolderId := Target.FolderID;
  if Assigned(FOnNavigateItem) then
    FOnNavigateItem(Self, Data.LinkedProjectId, FolderId, Data.LinkedItemId);
end;

procedure TframeItemTree.btnManageLinksClick(Sender: TObject);
begin
  if FDetailItemId <= 0 then Exit;
  miItemLinksClick(nil);
end;

procedure TframeItemTree.miCopyLinkTargetClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  LinkClipboard.SetTarget(Data.Item.Id, Data.Item.Title);
end;

procedure TframeItemTree.miLinkToClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Res: TLinkRelationResult;
  SourceId, TargetId: Integer;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  if not LinkClipboard.HasTarget then Exit;

  Res := Default(TLinkRelationResult);
  if not TdlgLinkRelation.Execute(Data.Item.Title, LinkClipboard.Title, Res) then
    Exit;

  if Res.IsForward then
  begin
    SourceId := Data.Item.Id;
    TargetId := LinkClipboard.ItemId;
  end
  else
  begin
    SourceId := LinkClipboard.ItemId;
    TargetId := Data.Item.Id;
  end;

  if Model.ItemLinks.AddLink(SourceId, TargetId, Res.LinkTypeId, Res.Notes,
       Model.User.Id) = nil then
    MessageDlg('These items are already linked.', mtInformation, [mbOK], 0)
  else
  begin
    FVM.InvalidateLinkCount([SourceId, TargetId]);
    DisplayItemInfo(Data.Item);
    Tree.Invalidate;
  end;
end;

procedure TframeItemTree.miItemSignClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  Meaning, Comment, Password: string;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  if FVM.IsItemSigned(Data.Item.Id) then
  begin
    MessageDlg('This item is already signed.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Meaning := '';
  Comment := '';
  Password := '';
  if ShowSignDialog(Meaning, Comment, Password, Data.Item.Title) then
  begin
    if Model.Signatures.SignItem(Data.Item, Model.User, Password, Meaning, Comment) then
    begin
      MessageDlg('Item signed successfully.', mtInformation, [mbOK], 0);
      FillTree(FLocation);
      RestoreLastSelection;
    end
    else
      MessageDlg('Signing failed. Please check your password.', mtError, [mbOK], 0);
  end;
end;

procedure TframeItemTree.miItemViewSignatureClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;
  ShowSignatureView(Data.Item.Id);
end;

procedure TframeItemTree.miItemVerifyIntegrityClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  case Model.Signatures.GetIntegrityState(Data.Item.Id) of
    sisVerified:
      MessageDlg('Integrity check PASSED. Content matches the signature.',
        mtInformation, [mbOK], 0);
    sisMismatch:
      MessageDlg('Integrity check FAILED. Content does not match the signature.',
        mtError, [mbOK], 0);
    sisLegacyUnverifiable:
      MessageDlg('Legacy signature; integrity cannot be verified.',
        mtWarning, [mbOK], 0);
    sisUnsigned:
      MessageDlg('No signature found for this item.', mtInformation, [mbOK], 0);
  end;
end;

procedure TframeItemTree.miItemBookmarkClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  Model.Favorites.ToggleFavorite(Model.User.Id, ftItem,
    Data.Item.ProjectID, Data.Item.FolderID, Data.Item.Id, Data.Item.Title);
end;

procedure TframeItemTree.miItemTagsClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  TdlgTagManager.ShowTagManager(Data.Item.Id, Data.Item.Title);
  // The badges are painted from the VM tag cache, which LoadItemData fills once
  // per tree build - refresh this item's entry or the repaint shows stale tags.
  FVM.RefreshTagsForItem(Data.Item.Id);
  Tree.InvalidateNode(Node);
end;

procedure TframeItemTree.miItemCommentsClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
  DisplayName: string;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  DisplayName := Model.User.FirstName + ' ' + Model.User.LastName;
  TdlgComments.ShowComments(Data.Item.Id, Data.Item.Title,
    Model.User.Id, DisplayName);
end;

procedure TframeItemTree.miItemLinksClick(Sender: TObject);
var
  Node: PVirtualNode;
  Data: PNodeData;
begin
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeType <> ntItem) then Exit;

  TdlgLinkManager.ShowLinks(Data.Item.Id, Data.Item.ProjectID, Data.Item.Title,
    procedure(AItemId, AProjectId: Integer)
    var
      Target: TItem;
      FolderId: Integer;
    begin
      FolderId := 0;
      Target := Model.Items.GetItem(AItemId);
      if Assigned(Target) then
        FolderId := Target.FolderID;
      if Assigned(FOnNavigateItem) then
        FOnNavigateItem(Self, AProjectId, FolderId, AItemId)
      else
      begin
        FVM.SelectItem(AItemId, 0);
        RestoreLastSelection;
      end;
    end);

  // The manager writes links straight through the model, so the VM's cached
  // counts (and therefore the tree badge and the inline list) are stale by the
  // time it closes. Refresh both for the item that was managed.
  FVM.InvalidateLinkCount([Data.Item.Id]);
  DisplayItemInfo(Data.Item);
  Tree.Invalidate;
  Tree.Invalidate;
end;

procedure TframeItemTree.CreateTemplateMenuItem;
var
  Sep: TMenuItem;
begin
  if FTemplateMenuCreated then Exit;
  FTemplateMenuCreated := True;

  Sep := TMenuItem.Create(pmNew);
  Sep.Caption := '-';
  pmNew.Items.Add(Sep);

  FmiNewFromTemplate := TMenuItem.Create(pmNew);
  FmiNewFromTemplate.Caption := 'From Template...';
  FmiNewFromTemplate.ImageIndex := 29; 
  FmiNewFromTemplate.OnClick := miNewFromTemplateClick;
  pmNew.Items.Add(FmiNewFromTemplate);
end;

procedure TframeItemTree.miNewFromTemplateClick(Sender: TObject);
begin
  BtnNewFromTemplateClick(Sender);
end;

procedure TframeItemTree.BtnNewFromTemplateClick(Sender: TObject);
var
  NewItem: TItem;
  TemplateName: string;
begin
  try
    if not TdlgNewFromTemplate.Execute(
      FLocation.ProjectID, FLocation.FolderID, Model.User.Id,
      NewItem, TemplateName) then
      Exit;
  except
    on E: EWikiFolderExists do
    begin
      MessageDlg('A Wiki folder already exists in this location. ' +
        'Remove or rename it before re-applying the Wiki template.',
        mtWarning, [mbOK], 0);
      Exit;
    end;
  end;

  // Wiki template is shipped by the app; name match is intentional.
  if SameText(TemplateName, 'Wiki') then
    unit_WikiSeeder.WriteReadmeContent(NewItem, Model.User.Id);

  FVM.SelectItem(NewItem.Id, 0);
  FillTree(FLocation);
  RestoreLastSelection;
end;

end.
