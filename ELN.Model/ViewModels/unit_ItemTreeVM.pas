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
  unit_ProjectAccessPolicy, unit_NotebookStorage, Aurelius.Types.Nullable,
  unit_ValueSource;

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
    FItemsCache: TItems;
    FCommentedItems: TDictionary<Integer, Integer>;
    FTagsCache: TDictionary<Integer, TTags>;
    FLinkCountCache: TDictionary<Integer, Integer>;
    FRunItems: TDictionary<Integer, Boolean>;
    FHypManager: TObjectManager;
    FEntryLookup: TObjectDictionary<Integer, TLabEntries>;
    FFileLookup: TObjectDictionary<Integer, TFiles>;
    FValueLookup: TObjectDictionary<Integer, TValues>;
    FLoadedEntries: TDictionary<Integer, TLabEntry>;
    FLoadedFiles: TDictionary<Int64, TFile>;
    FLoadedValues: TDictionary<Integer, TValue>;
    FLoadedOwners: TDictionary<Integer, Boolean>;
    FNoEntries: TLabEntries;
    FNoFiles: TFiles;
    FNoValues: TValues;

    FOnChanged: TNotifyEvent;
    procedure DoChanged;
    procedure ClearCaches;
    procedure DropLookups;
    procedure DropLoadedRecord;
    procedure EvictRecordedOwners;
    procedure FillLookups(const AItemIds: TArray<Integer>);
    procedure ReadEntries(const AItemIds: TArray<Integer>);
    procedure ReadFiles(const AItemIds: TArray<Integer>);
    procedure ReadValues(const AItemIds: TArray<Integer>);
    procedure ForgetLookupChildren;
    function LiveItem(Item: TItem): TItem;
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
    function EntriesOf(Item: TItem): TLabEntries;
    function FilesOf(Item: TItem): TFiles;
    function ValuesOf(Item: TItem): TValues;
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
      var ParentItem: TItem; Tol: double; const Description: string;
      const Source: TValueSourceInfo);
    function AddFile(FileType: TFileType; const Title: string;
      var ParentItem: TItem): TFile;
    function AddNote(Protocol: TProtocol; var ParentItem: TItem): Boolean;
    function AddProtocol(Protocol: TProtocol; var ParentItem: TItem): Boolean;
    function DeleteItem(Item: TItem): Boolean;
    procedure DeleteFile(AFile: TFile; var ParentItem: TItem);
    function DeleteEntry(Entry: TLabEntry; var ParentItem: TItem): Boolean;
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
  System.StrUtils, System.Variants,
  Aurelius.Criteria.Base, Aurelius.Criteria.Linq, Aurelius.Criteria.Projections,
  unit_HypothesisModel;


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
  FNoEntries := TLabEntries.Create;
  FNoFiles := TFiles.Create;
  FNoValues := TValues.Create;
end;

destructor TItemTreeVM.Destroy;
begin
  ClearCaches;
  DropLoadedRecord;
  FNoValues.Free;
  FNoFiles.Free;
  FNoEntries.Free;
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
  FreeAndNil(FItemsCache);
  DropLookups;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TItemTreeVM.ClearCaches;
var
  Pair: TPair<Integer, TTags>;
begin
  FreeAndNil(FItemsCache);
  DropLookups;
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
  FreeAndNil(FItemsCache);
  DropLookups;
  DropLoadedRecord;
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

  FItemsCache := FItemModel.List;
  AllItemIds := TList<Integer>.Create;
  try
    for Item in FItemsCache do
      AllItemIds.Add(Item.Id);
    FillLookups(AllItemIds.ToArray);

    FCommentedItems := FCommentModel.GetCommentedItemIds(AllItemIds);
    FTagsCache := FTagModel.GetTagsForItems(AllItemIds.ToArray);
    FLinkCountCache := FItemLinkModel.GetLinkCounts(AllItemIds.ToArray);

    FreeAndNil(FRunItems);
    if Assigned(FHypManager) then
      FRunItems := RunItemIds(FHypManager, AllItemIds.ToArray);
  finally
    AllItemIds.Free;
  end;
end;

procedure TItemTreeVM.DropLookups;
begin
  FreeAndNil(FEntryLookup);
  FreeAndNil(FFileLookup);
  FreeAndNil(FValueLookup);
end;

procedure TItemTreeVM.DropLoadedRecord;
begin
  FreeAndNil(FLoadedEntries);
  FreeAndNil(FLoadedFiles);
  FreeAndNil(FLoadedValues);
  FreeAndNil(FLoadedOwners);
end;

procedure TItemTreeVM.FillLookups(const AItemIds: TArray<Integer>);
var
  Id: Integer;
begin
  DropLookups;
  FEntryLookup := TObjectDictionary<Integer, TLabEntries>.Create([doOwnsValues]);
  FFileLookup := TObjectDictionary<Integer, TFiles>.Create([doOwnsValues]);
  FValueLookup := TObjectDictionary<Integer, TValues>.Create([doOwnsValues]);
  if FLoadedEntries = nil then
  begin
    FLoadedEntries := TDictionary<Integer, TLabEntry>.Create;
    FLoadedFiles := TDictionary<Int64, TFile>.Create;
    FLoadedValues := TDictionary<Integer, TValue>.Create;
    FLoadedOwners := TDictionary<Integer, Boolean>.Create;
  end;
  try
    for Id in AItemIds do
    begin
      FEntryLookup.Add(Id, TLabEntries.Create);
      FFileLookup.Add(Id, TFiles.Create);
      FValueLookup.Add(Id, TValues.Create);
    end;
    ReadEntries(AItemIds);
    ReadFiles(AItemIds);
    ReadValues(AItemIds);
  except
    DropLookups;
    raise;
  end;
end;

procedure TItemTreeVM.ReadEntries(const AItemIds: TArray<Integer>);
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Owner: TDictionary<Integer, Integer>;
  EntryIds: TList<Integer>;
  Found: TLabEntries;
  Entry: TLabEntry;
  OwnerId: Integer;
begin
  Owner := TDictionary<Integer, Integer>.Create;
  EntryIds := TList<Integer>.Create;
  try
    for Chunk in unit_HypothesisModel.IdChunks(AItemIds) do
    begin
      Rows := FItemModel.Manager.Find<TItem>
        .CreateAlias('FEntries', 'e')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('ItemId'))
          .Add(TProjections.Prop('e.Id').As_('EntryId')))
        .Where(Linq['Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
          if not VarIsNull(Row.Values['EntryId']) then
            Owner.AddOrSetValue(Integer(Row.Values['EntryId']),
              Integer(Row.Values['ItemId']));
      finally
        Rows.Free;
      end;
    end;
    EntryIds.AddRange(Owner.Keys);
    EntryIds.Sort;
    for Chunk in unit_HypothesisModel.IdChunks(EntryIds.ToArray) do
    begin
      Found := FItemModel.Manager.Find<TLabEntry>
        .Where(Linq['Id']._In(Chunk))
        .OrderBy('Id')
        .List;
      try
        for Entry in Found do
          if Owner.TryGetValue(Entry.Id, OwnerId) then
          begin
            FEntryLookup[OwnerId].Add(Entry);
            FLoadedEntries.AddOrSetValue(Entry.Id, Entry);
            FLoadedOwners.AddOrSetValue(OwnerId, True);
          end;
      finally
        Found.Free;
      end;
    end;
  finally
    EntryIds.Free;
    Owner.Free;
  end;
end;

procedure TItemTreeVM.ReadFiles(const AItemIds: TArray<Integer>);
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Owner: TDictionary<Int64, Integer>;
  FileIds: TList<Int64>;
  Found: TFiles;
  AFile: TFile;
  OwnerId: Integer;
begin
  Owner := TDictionary<Int64, Integer>.Create;
  FileIds := TList<Int64>.Create;
  try
    for Chunk in unit_HypothesisModel.IdChunks(AItemIds) do
    begin
      Rows := FItemModel.Manager.Find<TFile>
        .CreateAlias('Item', 'i')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('i.Id').As_('ItemId')))
        .Where(Linq['i.Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
          Owner.AddOrSetValue(Int64(Row.Values['Id']), Integer(Row.Values['ItemId']));
      finally
        Rows.Free;
      end;
    end;
    FileIds.AddRange(Owner.Keys);
    FileIds.Sort;
    for Chunk in unit_HypothesisModel.IdChunks(FileIds.ToArray) do
    begin
      Found := FItemModel.Manager.Find<TFile>
        .Where(Linq['Id']._In(Chunk))
        .OrderBy('Id')
        .List;
      try
        for AFile in Found do
          if Owner.TryGetValue(AFile.Id, OwnerId) then
          begin
            FFileLookup[OwnerId].Add(AFile);
            FLoadedFiles.AddOrSetValue(AFile.Id, AFile);
            FLoadedOwners.AddOrSetValue(OwnerId, True);
          end;
      finally
        Found.Free;
      end;
    end;
  finally
    FileIds.Free;
    Owner.Free;
  end;
end;

procedure TItemTreeVM.ReadValues(const AItemIds: TArray<Integer>);
var
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
  Owner: TDictionary<Integer, Integer>;
  ValueIds: TList<Integer>;
  Found: TValues;
  AValue: TValue;
  OwnerId: Integer;
begin
  Owner := TDictionary<Integer, Integer>.Create;
  ValueIds := TList<Integer>.Create;
  try
    for Chunk in unit_HypothesisModel.IdChunks(AItemIds) do
    begin
      Rows := FItemModel.Manager.Find<TValue>
        .CreateAlias('Item', 'i')
        .Select(TProjections.ProjectionList
          .Add(TProjections.Prop('Id').As_('Id'))
          .Add(TProjections.Prop('i.Id').As_('ItemId')))
        .Where(Linq['i.Id']._In(Chunk))
        .ListValues;
      try
        for Row in Rows do
          Owner.AddOrSetValue(Integer(Row.Values['Id']), Integer(Row.Values['ItemId']));
      finally
        Rows.Free;
      end;
    end;
    ValueIds.AddRange(Owner.Keys);
    ValueIds.Sort;
    for Chunk in unit_HypothesisModel.IdChunks(ValueIds.ToArray) do
    begin
      Found := FItemModel.Manager.Find<TValue>
        .Where(Linq['Id']._In(Chunk))
        .OrderBy('Id')
        .List;
      try
        for AValue in Found do
          if Owner.TryGetValue(AValue.Id, OwnerId) then
          begin
            FValueLookup[OwnerId].Add(AValue);
            FLoadedValues.AddOrSetValue(AValue.Id, AValue);
            FLoadedOwners.AddOrSetValue(OwnerId, True);
          end;
      finally
        Found.Free;
      end;
    end;
  finally
    ValueIds.Free;
    Owner.Free;
  end;
end;

function TItemTreeVM.LiveItem(Item: TItem): TItem;
begin
  Result := FItemModel.Manager.Find<TItem>(Item.Id);
end;

procedure TItemTreeVM.ForgetLookupChildren;
var
  Manager: TObjectManager;

  procedure Forget(Child, Cached: TObject);
  begin
    if (Cached <> nil) and (Cached = Child) then
    begin
      Manager.Evict(Child);
      Manager.AddOwnership(Child);
    end;
  end;

var
  Entry: TPair<Integer, TLabEntry>;
  AFile: TPair<Int64, TFile>;
  Row: TPair<Integer, TValue>;
begin
  Manager := FItemModel.Manager;
  if Assigned(FLoadedEntries) then
    for Entry in FLoadedEntries do
      Forget(Entry.Value, Manager.FindCached<TLabEntry>(Entry.Key));
  if Assigned(FLoadedFiles) then
    for AFile in FLoadedFiles do
      Forget(AFile.Value, Manager.FindCached<TFile>(AFile.Key));
  if Assigned(FLoadedValues) then
    for Row in FLoadedValues do
      Forget(Row.Value, Manager.FindCached<TValue>(Row.Key));
end;

function TItemTreeVM.Items: TItems;
begin
  if Assigned(FItemsCache) then
  begin
    Result := TItems.Create;
    try
      Result.AddRange(FItemsCache);
    except
      Result.Free;
      raise;
    end;
  end
  else
  begin
    FItemModel.AssignProject(FProjectId, FFolderId);
    Result := FItemModel.List;
  end;
end;

function TItemTreeVM.EntriesOf(Item: TItem): TLabEntries;
var
  Live: TItem;
begin
  if Item.EntriesLoaded then
    Exit(Item.Entries);
  if Assigned(FEntryLookup) and FEntryLookup.TryGetValue(Item.Id, Result) then
    Exit;
  Live := LiveItem(Item);
  if Live = nil then
    Result := FNoEntries
  else
    Result := Live.Entries;
end;

function TItemTreeVM.FilesOf(Item: TItem): TFiles;
var
  Live: TItem;
begin
  if Item.FilesLoaded then
    Exit(Item.Files);
  if Assigned(FFileLookup) and FFileLookup.TryGetValue(Item.Id, Result) then
    Exit;
  Live := LiveItem(Item);
  if Live = nil then
    Result := FNoFiles
  else
    Result := Live.Files;
end;

function TItemTreeVM.ValuesOf(Item: TItem): TValues;
var
  Live: TItem;
begin
  if Item.ValuesLoaded then
    Exit(Item.Values);
  if Assigned(FValueLookup) and FValueLookup.TryGetValue(Item.Id, Result) then
    Exit;
  Live := LiveItem(Item);
  if Live = nil then
    Result := FNoValues
  else
    Result := Live.Values;
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
    for E in EntriesOf(Item) do
      if (E is TProtocol) and ContainsText(TProtocol(E).Title, FFilterText) then
      begin
        Result := True;
        Exit;
      end;
  if not Result then
    for F in FilesOf(Item) do
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
  const Description: string; const Source: TValueSourceInfo);
begin
  FItemModel.AddValue(ValueType, RecType, AValue, UserId,
    ParentItem, Tol, Description, Source);
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

function TItemTreeVM.DeleteEntry(Entry: TLabEntry; var ParentItem: TItem): Boolean;
begin
  Result := FItemModel.RemoveEntry(Entry, ParentItem, UserId);
  if Result then
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

procedure TItemTreeVM.EvictRecordedOwners;
var
  Manager: TObjectManager;
  Pair: TPair<Integer, Boolean>;
  Cached: TItem;
begin
  if not Assigned(FLoadedOwners) then
    Exit;
  Manager := FItemModel.Manager;
  for Pair in FLoadedOwners do
  begin
    Cached := Manager.FindCached<TItem>(Pair.Key);
    if Cached <> nil then
      Manager.Evict(Cached);
  end;
end;

procedure TItemTreeVM.EvictCache;
begin
  ForgetLookupChildren;
  DropLookups;
  FreeAndNil(FItemsCache);
  FItemModel.EvictCache;
  EvictRecordedOwners;
  DropLoadedRecord;
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
