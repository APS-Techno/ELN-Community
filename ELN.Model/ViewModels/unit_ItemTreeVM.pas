unit unit_ItemTreeVM;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_ItemModel, unit_AuthorModel, unit_UserHistoryModel,
  unit_SignatureModel, unit_CommentModel, unit_TagModel, unit_ItemLinkModel,
  unit_Item, unit_ItemTypes, unit_ActionType, unit_Equipment, unit_Protocol,
  unit_LabEntry, unit_FileType, unit_ValueType, unit_Tag, unit_Comment,
  unit_User, unit_Types, unit_HypothesisQueries, unit_TreeStateModel,
  unit_ProjectAccessPolicy, unit_NotebookStorage, Aurelius.Types.Nullable;

type
  TItemTreeVM = class
  private
    FItemModel: TItemModel;
    FUserModel: TAuthorModel;
    FHistoryModel: TUserHistoryModel;
    FSignatureModel: TSignatureModel;
    FCommentModel: TCommentModel;
    FTagModel: TTagModel;
    FItemLinkModel: TItemLinkModel;
    FAccess: IProjectAccessPolicy;
    FTreeState: TTreeStateModel;

    FProjectId: Integer;
    FFolderId: Integer;
    FProjectAccess: TProjectAccess;
    FFilterText: string;

    FSignedItems: TDictionary<Integer, Boolean>;
    FCommentedItems: TDictionary<Integer, Integer>;
    FTagsCache: TDictionary<Integer, TTags>;
    FLinkCountCache: TDictionary<Integer, Integer>;
    FRunItems: TDictionary<Integer, Boolean>;
    FHypManager: TObjectManager;

    FOnChanged: TNotifyEvent;
    procedure DoChanged;
    procedure ClearCaches;
  public
    constructor Create(
      AItemModel: TItemModel;
      AUserModel: TAuthorModel;
      AHistoryModel: TUserHistoryModel;
      ASignatureModel: TSignatureModel;
      ACommentModel: TCommentModel;
      ATagModel: TTagModel;
      AItemLinkModel: TItemLinkModel;
      const AAccess: IProjectAccessPolicy);
    destructor Destroy; override;

    /// Per-user expanded state (unit_TreeStateModel). An item nobody has
    /// touched is expanded. Without a TreeState: expanded, nothing saved.
    property TreeState: TTreeStateModel read FTreeState write FTreeState;
    function IsItemExpanded(ItemId: Integer): Boolean;
    procedure SetItemExpanded(ItemId: Integer; Value: Boolean);

    property FilterText: string read FFilterText write FFilterText;
    property ProjectId: Integer read FProjectId;
    property FolderId: Integer read FFolderId;
    property ProjectAccess: TProjectAccess read FProjectAccess;
    function IsReadOnly: Boolean;
    function CanEdit: Boolean;
    function UserId: Integer;

    procedure SetHypothesisManager(AManager: TObjectManager);
    function IsItemRun(ItemId: Integer): Boolean;

    procedure SetLocation(AProjectId, AFolderId: Integer; AAccess: TProjectAccess);
    procedure LoadItemData;
    function Items: TItems;
    function ItemMatchesFilter(Item: TItem): Boolean;
    function IsItemSigned(ItemId: Integer): Boolean;
    function GetCommentCount(ItemId: Integer): Integer;
    function GetTagsForItem(ItemId: Integer): TTags;
    function GetLinkCount(ItemId: Integer): Integer;
    procedure InvalidateLinkCount(const AItemIds: array of Integer);
    function GetLatestComment(ItemId: Integer): TComment;

    function AddItem(IType: TItemType; const Title: string; Level: TItemLevel;
      ParentId: Integer; const Description: string; AType: TActionType;
      AEquipment: TEquipment = nil; const Properties: string = ''): TItem;
    procedure AddValue(ValueType: TValueType; RecType: TRecType; AValue: double;
      var ParentItem: TItem; Tol: double; const Description: string);
    function AddFile(FileType: TFileType; const Title: string;
      var ParentItem: TItem): TFile;
    function AddNote(Protocol: TProtocol; var ParentItem: TItem): Boolean;
    function AddProtocol(Protocol: TProtocol; var ParentItem: TItem): Boolean;
    function DeleteItem(Item: TItem): Boolean;
    procedure DeleteFile(AFile: TFile; var ParentItem: TItem);
    procedure DeleteEntry(Entry: TLabEntry; var ParentItem: TItem);
    function UpdateItem(Item: TItem; const Relocator: IFileRelocator): Boolean;
    function ReparentItem(Item: TItem; NewParentId: Integer): Boolean;
    function UpdateNote(Protocol: TProtocol; const Title, FormData: string): Boolean;
    function DuplicateItem(Source: TItem; DstProjectId, DstFolderId,
      DstParentId: Integer; const NewTitle: string;
      LinkToOriginal: Boolean): TItem;
    function MoveItem(Item: TItem; NewProjectId, NewFolderId: Integer): Boolean;

    procedure SelectItem(ItemId: Integer; ChildId: Int64);
    function LastItemId: Integer;
    function LastChildId: Int64;

    procedure EvictCache;
    procedure RefreshTagsForItem(ItemId: Integer);

    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.StrUtils;


constructor TItemTreeVM.Create(
  AItemModel: TItemModel;
  AUserModel: TAuthorModel;
  AHistoryModel: TUserHistoryModel;
  ASignatureModel: TSignatureModel;
  ACommentModel: TCommentModel;
  ATagModel: TTagModel;
  AItemLinkModel: TItemLinkModel;
  const AAccess: IProjectAccessPolicy);
begin
  inherited Create;
  if AAccess = nil then
    raise EArgumentNilException.Create('Access');
  FAccess := AAccess;
  FItemModel := AItemModel;
  FUserModel := AUserModel;
  FHistoryModel := AHistoryModel;
  FSignatureModel := ASignatureModel;
  FCommentModel := ACommentModel;
  FTagModel := ATagModel;
  FItemLinkModel := AItemLinkModel;
end;

destructor TItemTreeVM.Destroy;
begin
  ClearCaches;
  inherited;
end;

function TItemTreeVM.IsItemExpanded(ItemId: Integer): Boolean;
begin
  Result := True;
  if Assigned(FTreeState) then
    Result := FTreeState.IsExpanded(tnkItem, ItemId, True);
end;

procedure TItemTreeVM.SetItemExpanded(ItemId: Integer; Value: Boolean);
begin
  if Assigned(FTreeState) then
    FTreeState.SetExpanded(tnkItem, ItemId, Value);
end;

procedure TItemTreeVM.DoChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TItemTreeVM.ClearCaches;
var
  Pair: TPair<Integer, TTags>;
begin
  FreeAndNil(FSignedItems);
  FreeAndNil(FCommentedItems);
  FreeAndNil(FLinkCountCache);
  FreeAndNil(FRunItems);
  if Assigned(FTagsCache) then
  begin
    for Pair in FTagsCache do
      Pair.Value.Free;
    FreeAndNil(FTagsCache);
  end;
end;

function TItemTreeVM.IsReadOnly: Boolean;
begin
  Result := not FAccess.CanCreateProjects(FItemModel.Manager, FUserModel.CurrentUser);
end;

function TItemTreeVM.CanEdit: Boolean;
begin
  Result := FAccess.CanWrite(FItemModel.Manager, FUserModel.CurrentUser, FProjectId);
end;

function TItemTreeVM.UserId: Integer;
begin
  if FUserModel.CurrentUser = nil then
    Result := 0
  else
    Result := FUserModel.CurrentUser.Id;
end;

procedure TItemTreeVM.SetHypothesisManager(AManager: TObjectManager);
begin
  FHypManager := AManager;
end;

function TItemTreeVM.IsItemRun(ItemId: Integer): Boolean;
begin
  Result := Assigned(FRunItems) and FRunItems.ContainsKey(ItemId);
end;

procedure TItemTreeVM.SetLocation(AProjectId, AFolderId: Integer;
  AAccess: TProjectAccess);
begin
  FProjectId := AProjectId;
  FFolderId := AFolderId;
  FProjectAccess := AAccess;
end;


procedure TItemTreeVM.LoadItemData;
var
  SignedIds: TList<Integer>;
  SigId: Integer;
  AllItemIds: TList<Integer>;
  Item: TItem;
  AId: Integer;
begin
  ClearCaches;
  FItemModel.AssignProject(FProjectId, FFolderId);

  FSignedItems := TDictionary<Integer, Boolean>.Create;
  SignedIds := FSignatureModel.GetSignedItemIds(FProjectId, FFolderId);
  try
    for SigId in SignedIds do
      FSignedItems.AddOrSetValue(SigId, True);
  finally
    SignedIds.Free;
  end;

  AllItemIds := TList<Integer>.Create;
  try
    // FItemModel.List returns a fresh caller-owned list each call; free the LIST
    // (entities remain manager-owned) to avoid leaking one per tree rebuild.
    var Items: TItems := FItemModel.List;
    try
      for Item in Items do
        AllItemIds.Add(Item.Id);
    finally
      Items.Free;
    end;

    FCommentedItems := FCommentModel.GetCommentedItemIds(AllItemIds);

    FTagsCache := TDictionary<Integer, TTags>.Create;
    FLinkCountCache := TDictionary<Integer, Integer>.Create;
    for AId in AllItemIds do
    begin
      FTagsCache.Add(AId, FTagModel.GetTagsForItem(AId));
      FLinkCountCache.Add(AId, FItemLinkModel.GetLinkCount(AId));
    end;

    FreeAndNil(FRunItems);
    if Assigned(FHypManager) then
      FRunItems := RunItemIds(FHypManager, AllItemIds.ToArray);
  finally
    AllItemIds.Free;
  end;
end;

function TItemTreeVM.Items: TItems;
begin
  Result := FItemModel.List;
end;

function TItemTreeVM.ItemMatchesFilter(Item: TItem): Boolean;
var
  E: TLabEntry;
  F: TFile;
begin
  if FFilterText = '' then
    Exit(True);

  Result := ContainsText(Item.Title, FFilterText) or
            ContainsText(Item.Description, FFilterText);
  if not Result then
    for E in Item.Entries do
      if (E is TProtocol) and ContainsText(TProtocol(E).Title, FFilterText) then
      begin
        Result := True;
        Exit;
      end;
  if not Result then
    for F in Item.Files do
      if ContainsText(F.Title, FFilterText) or
         ContainsText(F.Description, FFilterText) then
      begin
        Result := True;
        Exit;
      end;
end;

function TItemTreeVM.IsItemSigned(ItemId: Integer): Boolean;
begin
  Result := Assigned(FSignedItems) and FSignedItems.ContainsKey(ItemId);
end;

function TItemTreeVM.GetCommentCount(ItemId: Integer): Integer;
begin
  if Assigned(FCommentedItems) and FCommentedItems.ContainsKey(ItemId) then
    Result := FCommentedItems[ItemId]
  else
    Result := 0;
end;

function TItemTreeVM.GetTagsForItem(ItemId: Integer): TTags;
begin
  if Assigned(FTagsCache) and FTagsCache.ContainsKey(ItemId) then
    Result := FTagsCache[ItemId]
  else
    Result := nil;
end;

function TItemTreeVM.GetLinkCount(ItemId: Integer): Integer;
begin
  if Assigned(FLinkCountCache) and FLinkCountCache.ContainsKey(ItemId) then
    Result := FLinkCountCache[ItemId]
  else
    Result := 0;
end;

procedure TItemTreeVM.InvalidateLinkCount(const AItemIds: array of Integer);
var
  Id: Integer;
begin
  if not Assigned(FLinkCountCache) then Exit;
  // Recompute rather than evict: GetLinkCount reports 0 on a cache miss, so a
  // bare removal would blank the badge instead of refreshing it. Ids outside
  // the cache belong to items that are not loaded and are left alone.
  for Id in AItemIds do
    if FLinkCountCache.ContainsKey(Id) then
      FLinkCountCache[Id] := FItemLinkModel.GetLinkCount(Id);
end;

function TItemTreeVM.GetLatestComment(ItemId: Integer): TComment;
begin
  Result := FCommentModel.GetLatestComment(ItemId);
end;


function TItemTreeVM.AddItem(IType: TItemType; const Title: string;
  Level: TItemLevel; ParentId: Integer; const Description: string;
  AType: TActionType; AEquipment: TEquipment; const Properties: string): TItem;
begin
  Result := FItemModel.AddItem(IType, Title, Level, ParentId, Description,
    AType, AEquipment, UserId, Properties);
  DoChanged;
end;

procedure TItemTreeVM.AddValue(ValueType: TValueType; RecType: TRecType;
  AValue: double; var ParentItem: TItem; Tol: double;
  const Description: string);
begin
  FItemModel.AddValue(ValueType, RecType, AValue, UserId,
    ParentItem, Tol, Description);
  DoChanged;
end;

function TItemTreeVM.AddFile(FileType: TFileType; const Title: string;
  var ParentItem: TItem): TFile;
begin
  Result := FItemModel.AddFile(FileType, Title, UserId, ParentItem);
  DoChanged;
end;

function TItemTreeVM.AddNote(Protocol: TProtocol; var ParentItem: TItem): Boolean;
begin
  Result := AddProtocol(Protocol, ParentItem);
end;

function TItemTreeVM.AddProtocol(Protocol: TProtocol; var ParentItem: TItem): Boolean;
begin
  Result := False;
  if not Assigned(Protocol) or not Assigned(ParentItem) then Exit;
  if not FAccess.CanWrite(FItemModel.Manager, FUserModel.CurrentUser,
    ParentItem.ProjectID) then Exit;
  // Do not use the tree's cached signature state at a write boundary.
  if IsItemSignedCheck(FItemModel.Manager, ParentItem.Id) then Exit;
  ParentItem.Entries.Add(Protocol);
  try
    Result := FItemModel.UpdateItem(ParentItem, UserId);
  finally
    if not Result then
    begin
      ParentItem.Entries.Extract(Protocol);
      FItemModel.Manager.Evict(Protocol);
    end;
  end;
  if Result then
    DoChanged;
end;

function TItemTreeVM.DeleteItem(Item: TItem): Boolean;
begin
  Result := FItemModel.SoftDeleteItemTree(Item, UserId);
  if Result then
    DoChanged;
end;

procedure TItemTreeVM.DeleteFile(AFile: TFile; var ParentItem: TItem);
begin
  FItemModel.RemoveFile(AFile, ParentItem, UserId);
  DoChanged;
end;

procedure TItemTreeVM.DeleteEntry(Entry: TLabEntry; var ParentItem: TItem);
begin
  FItemModel.RemoveEntry(Entry, ParentItem, UserId);
  DoChanged;
end;

function TItemTreeVM.UpdateItem(Item: TItem;
  const Relocator: IFileRelocator): Boolean;
begin
  if not Assigned(Item) then
    raise EArgumentNilException.Create('Item');
  if not Assigned(Relocator) then
  begin
    FItemModel.Manager.Refresh(Item);
    raise EArgumentNilException.Create('Relocator');
  end;
  if not FAccess.CanWrite(FItemModel.Manager, FUserModel.CurrentUser,
    Item.ProjectID) then
  begin
    FItemModel.Manager.Refresh(Item);
    Exit(False);
  end;
  Result := FItemModel.UpdateItemDurable(Item, UserId, Relocator);
  if Result then
    DoChanged;
end;

function TItemTreeVM.ReparentItem(Item: TItem; NewParentId: Integer): Boolean;
var
  OldParent, OldVersion: Integer;
  OldModifiedDate: Nullable<TDateTime>;
  OldModifiedBy: Nullable<Integer>;
begin
  Result := False;
  if not Assigned(Item) then
    raise EArgumentNilException.Create('Item');
  if Item.Parent = NewParentId then Exit;
  if not FAccess.CanWrite(FItemModel.Manager, FUserModel.CurrentUser,
    Item.ProjectID) then Exit;
  if IsItemSignedCheck(FItemModel.Manager, Item.Id) then Exit;
  OldParent := Item.Parent;
  OldVersion := Item.Version;
  OldModifiedDate := Item.ModifiedDate;
  OldModifiedBy := Item.ModifiedBy;
  Item.Parent := NewParentId;
  try
    Result := FItemModel.UpdateItem(Item, UserId);
  finally
    // SafeFlush refreshes a version-conflicted item before returning False (or
    // re-raising without a callback). Do not dirty that winning state again.
    if not Result and (Item.Version = OldVersion) then
    begin
      Item.Parent := OldParent;
      Item.ModifiedDate := OldModifiedDate;
      Item.ModifiedBy := OldModifiedBy;
    end;
  end;
  if Result then
    DoChanged;
end;

function TItemTreeVM.UpdateNote(Protocol: TProtocol;
  const Title, FormData: string): Boolean;
var
  ParentItem: TItem;
begin
  Result := False;
  ParentItem := FItemModel.GetItemForEntry(Protocol.Id);
  if not Assigned(ParentItem) then Exit;
  if not FAccess.CanWrite(FItemModel.Manager, FUserModel.CurrentUser,
    ParentItem.ProjectID) then Exit;
  if IsItemSignedCheck(FItemModel.Manager, ParentItem.Id) then Exit;
  Protocol.Title := Title;
  Protocol.FormData := FormData;
  try
    Result := FItemModel.UpdateEntry(Protocol, UserId);
  finally
    if not Result then
      FItemModel.Manager.Refresh(Protocol);
  end;
  if Result then
    DoChanged;
end;

function TItemTreeVM.DuplicateItem(Source: TItem; DstProjectId, DstFolderId,
  DstParentId: Integer; const NewTitle: string;
  LinkToOriginal: Boolean): TItem;
begin
  if not FAccess.CanWrite(FItemModel.Manager, FUserModel.CurrentUser, DstProjectId) then
    Exit(nil);

  FItemModel.AssignProject(DstProjectId, DstFolderId);
  try
    Result := FItemModel.AddItem(Source.Type_, NewTitle,
      Source.Level, DstParentId, Source.Description, Source.ActionType,
      Source.Equipment, UserId);
  finally
    FItemModel.AssignProject(FProjectId, FFolderId);
  end;

  if LinkToOriginal and Assigned(Result) then
    FItemLinkModel.AddLinkByForwardText(Result.Id, Source.Id, 'derived from', '',
      UserId);
  DoChanged;
end;

function TItemTreeVM.MoveItem(Item: TItem; NewProjectId,
  NewFolderId: Integer): Boolean;
begin
  Result := FItemModel.MoveProc(Item, NewProjectId, NewFolderId,
    UserId);
  if Result then
    DoChanged;
end;


procedure TItemTreeVM.SelectItem(ItemId: Integer; ChildId: Int64);
begin
  FHistoryModel.UserRecord.LastItem := ItemId;
  FHistoryModel.UserRecord.LastChild := ChildId;
end;

function TItemTreeVM.LastItemId: Integer;
begin
  Result := FHistoryModel.UserRecord.LastItem;
end;

function TItemTreeVM.LastChildId: Int64;
begin
  Result := FHistoryModel.UserRecord.LastChild;
end;

procedure TItemTreeVM.EvictCache;
begin
  FItemModel.EvictCache;
end;

procedure TItemTreeVM.RefreshTagsForItem(ItemId: Integer);
var
  Old: TTags;
begin
  if not Assigned(FTagsCache) then
    Exit;

  // TTags is a non-owning TList<TTag>; the entities stay manager-owned.
  if FTagsCache.TryGetValue(ItemId, Old) then
    Old.Free;
  FTagsCache.AddOrSetValue(ItemId, FTagModel.GetTagsForItem(ItemId));
end;

end.
