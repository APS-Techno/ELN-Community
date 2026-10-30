unit unit_ToolsNavigation;

interface

uses
  System.JSON,
  unit_MCPTools;

procedure RegisterNavigationTools(Registry: TToolRegistry);

function HandleListItems(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleGetItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleListProjects(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleSearch(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleSearchSemantic(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

var
  SemanticSyncDeadlineMs: Cardinal = 20000;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  System.TypInfo, System.DateUtils, System.Rtti,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Item, unit_Project, unit_ItemTypes, unit_ELNDB_Dictionary,
  unit_LabEntry, unit_ValueType, unit_SearchModel,
  unit_SearchPassages, unit_SearchDocumentProvider, unit_HybridSearch,
  unit_SemanticSearchApi, unit_SemanticSearchService, unit_SemanticSearchFilter,
  unit_SearchVisibility,
  unit_ActionType, unit_Equipment, unit_Tag, unit_TagModel,
  unit_JSONCompact, unit_ToolHelpers, unit_ToolsTags, unit_ToolScope;

const
  SearchResultKindNames: array[TSearchResultKind] of string =
    ('Item', 'Entry', 'File', 'Value', 'Tag');


function DateToISO(const DT: TDateTime): string;
begin
  Result := DateToISO8601(DT, False);
end;

function NullableDateToJSON(const Value: Nullable<TDateTime>): TJSONValue;
begin
  if Value.HasValue then
    Result := TJSONString.Create(DateToISO(Value.Value))
  else
    Result := TJSONNull.Create;
end;


function ItemTypeToStr(AType: TItemType): string;
begin
  Result := TRttiEnumerationType.GetName<TItemType>(AType);
end;

function StrToItemType(const S: string; out AType: TItemType): Boolean;
var
  V: Integer;
begin
  V := GetEnumValue(TypeInfo(TItemType), S);
  Result := V >= 0;
  if Result then
    AType := TItemType(V);
end;


function ItemLevelToStr(ALevel: TItemLevel): string;
begin
  Result := TRttiEnumerationType.GetName<TItemLevel>(ALevel);
end;

function StrToItemLevel(const S: string; out ALevel: TItemLevel): Boolean;
var
  V: Integer;
begin
  V := GetEnumValue(TypeInfo(TItemLevel), S);
  Result := V >= 0;
  if Result then
    ALevel := TItemLevel(V);
end;


function GetOptBool(const Params: TJSONObject; const Key: string;
  Default: Boolean): Boolean;
begin
  Result := Default;
  if (Params <> nil) and (Params.FindValue(Key) <> nil) then
    Result := Params.GetValue<Boolean>(Key);
end;

function GetOptInt(const Params: TJSONObject; const Key: string;
  out Value: Integer): Boolean;
begin
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil);
  if Result then
    Value := Params.GetValue<Integer>(Key);
end;

function GetOptStr(const Params: TJSONObject; const Key: string;
  out Value: string): Boolean;
begin
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil) and
            not (Params.FindValue(Key) is TJSONNull);
  if Result then
    Value := Params.GetValue<string>(Key);
end;

function GetReqInt(const Params: TJSONObject; const Key: string): Integer;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<Integer>(Key);
end;

function GetReqStr(const Params: TJSONObject; const Key: string): string;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<string>(Key);
end;


type
  // ItemId -> that item's tags. Owns the value lists but never the TTag
  // objects inside them - those belong to the Aurelius object manager.
  TItemTagMap = TObjectDictionary<Integer, TTags>;

// One tag as {"id","name","color","color_rgb"}. 'color' is the stored value
// verbatim; 'color_rgb' is its byte swap, or '' when the stored value is not
// '#' + 6 hex digits - a malformed legacy row must degrade, not abort the read.
function TagToJSON(Tag: TTag): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(Tag.Id));
  Result.AddPair('name', Tag.Name);
  Result.AddPair('color', Tag.Color);
  Result.AddPair('color_rgb', TrySwapHexByteOrder(Tag.Color));
end;

// The tags array for one item, ordered by tag id (the ItemTags row order is
// undefined, so the caller would otherwise see an unstable response). Sorts the
// supplied list in place; both callers own the list they pass. Tags may be nil,
// which yields an empty array.
function TagsToJSONArray(Tags: TTags): TJSONArray;
var
  Tag: TTag;
begin
  if Assigned(Tags) then
    Tags.Sort(TComparer<TTag>.Construct(
      function(const L, R: TTag): Integer
      begin
        Result := L.Id - R.Id;
      end));

  Result := TJSONArray.Create;
  try
    if Assigned(Tags) then
      for Tag in Tags do
        Result.AddElement(TagToJSON(Tag));
  except
    Result.Free;
    raise;
  end;
end;

// Builds the whole ItemId -> tags map with exactly TWO queries, whatever the
// row count: one for every ItemTags link and one for every Tag. list_items can
// return hundreds of rows, and a per-item GetTagsForItem would turn that into
// hundreds of round-trips.
function BuildItemTagMap(const Context: TToolContext): TItemTagMap;
var
  TagsById: TDictionary<Integer, TTag>;
  AllTags: TTags;
  Links: TItemTags;
  Link: TItemTag;
  Tag: TTag;
  List: TTags;
begin
  Result := TItemTagMap.Create([doOwnsValues]);
  try
    TagsById := TDictionary<Integer, TTag>.Create;
    try
      AllTags := Context.Manager.Find<TTag>.List;
      try
        for Tag in AllTags do
          TagsById.AddOrSetValue(Tag.Id, Tag);
      finally
        // The list is ours; the TTag objects in it are manager-owned.
        AllTags.Free;
      end;

      Links := Context.Manager.Find<TItemTag>.List;
      try
        for Link in Links do
        begin
          // An orphan link (tag row deleted out from under it) is skipped
          // rather than reported as a tag with no name.
          if not TagsById.TryGetValue(Link.TagId, Tag) then
            Continue;
          if not Result.TryGetValue(Link.ItemId, List) then
          begin
            List := TTags.Create;
            Result.Add(Link.ItemId, List);
          end;
          List.Add(Tag);
        end;
      finally
        Links.Free;
      end;
    finally
      TagsById.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;


function HandleListProjects(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  IncludeArchived: Boolean;
  Projects: TList<TProject>;
  Project: TProject;
  Arr: TJSONArray;
  Obj: TJSONObject;
  ItemDic: TItemDictionary;
  Items: TList<TItem>;
  OwnerName: string;
begin
  IncludeArchived := GetOptBool(Params, 'include_archived', False);

  if IncludeArchived then
    Projects := Context.Manager.Find<TProject>.List
  else
    Projects := Context.Manager.Find<TProject>
      .Where(Linq['IsArchived'] = False)
      .List;

  ItemDic := TItemDictionary.Create;
  try
    Arr := TJSONArray.Create;
    try
      for Project in Projects do
      begin
        // A confined session simply does not see out-of-scope projects -
        // filtered, not refused, or the tool would be useless under a scope.
        if not IsProjectVisible(Context, Project.Id) then
          Continue;

        Items := Context.Manager.Find<TItem>
          .Where((ItemDic.ProjectID = Project.Id) and (ItemDic.IsDeleted = False))
          .List;
        try
          Obj := TJSONObject.Create;
          Obj.AddPair('id', TJSONNumber.Create(Project.Id));
          Obj.AddPair('title', Project.Title);
          Obj.AddPair('description', Project.Description);

          if Assigned(Project.Owner) then
            OwnerName := Project.Owner.Username
          else
            OwnerName := '';
          Obj.AddPair('owner', OwnerName);

          Obj.AddPair('start_date', NullableDateToJSON(Project.StartDate));
          Obj.AddPair('end_date', NullableDateToJSON(Project.EndDate));
          Obj.AddPair('is_archived', TJSONBool.Create(Project.IsArchived));
          Obj.AddPair('item_count', TJSONNumber.Create(Items.Count));

          Arr.AddElement(Obj);
        finally
          Items.Free;
        end;
      end;
    except
      Arr.Free;
      raise;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('projects', Arr);
  finally
    ItemDic.Free;
    Projects.Free;
  end;
end;

function HandleListFolders(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId: Integer;
  Project: TProject;
  Folder: TFolder;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  ProjectId := GetReqInt(Params, 'project_id');
  // Before the existence check: an out-of-scope project must produce the
  // uniform refusal, never "Project not found" vs a folder listing.
  RequireProjectRead(Context, ProjectId);

  Project := Context.Manager.Find<TProject>(ProjectId);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project not found: %d', [ProjectId]);

  Arr := TJSONArray.Create;
  try
    for Folder in Project.Folders do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', TJSONNumber.Create(Folder.Id));
      Obj.AddPair('title', Folder.Title);
      Obj.AddPair('parent_folder_id', TJSONNumber.Create(Folder.ParentFolderID));
      Obj.AddPair('sort_order', TJSONNumber.Create(Folder.SortOrder));
      Arr.AddElement(Obj);
    end;
  except
    Arr.Free;
    raise;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('folders', Arr);
end;

function HandleListItems(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId, FolderId: Integer;
  HasFolder: Boolean;
  ItemTypeStr, LevelStr: string;
  HasType, HasLevel, IncludeTags: Boolean;
  ItemType: TItemType;
  ItemLevel: TItemLevel;
  ItemDic: TItemDictionary;
  Items: TList<TItem>;
  Item: TItem;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Criteria: TLinqExpression;
  TagMap: TItemTagMap;
  ItemTags: TTags;
begin
  ProjectId := GetReqInt(Params, 'project_id');
  RequireProjectRead(Context, ProjectId);
  HasFolder := GetOptInt(Params, 'folder_id', FolderId);
  HasType := GetOptStr(Params, 'item_type', ItemTypeStr);
  HasLevel := GetOptStr(Params, 'level', LevelStr);
  // Off by default, and when off no 'tags' key is emitted at all: existing
  // callers must keep seeing byte-identical item objects.
  IncludeTags := GetOptBool(Params, 'include_tags', False);

  if HasType and not StrToItemType(ItemTypeStr, ItemType) then
    raise Exception.CreateFmt('Invalid item_type: %s', [ItemTypeStr]);
  if HasLevel and not StrToItemLevel(LevelStr, ItemLevel) then
    raise Exception.CreateFmt('Invalid level: %s', [LevelStr]);

  ItemDic := TItemDictionary.Create;
  try
    Criteria := (ItemDic.ProjectID = ProjectId) and (ItemDic.IsDeleted = False);

    if HasFolder then
      Criteria := Criteria and (ItemDic.FolderID = FolderId);
    if HasType then
      Criteria := Criteria and (ItemDic.Type_ = Ord(ItemType));
    if HasLevel then
      Criteria := Criteria and (ItemDic.Level = Ord(ItemLevel));

    TagMap := nil;
    if IncludeTags then
      TagMap := BuildItemTagMap(Context);
    try
      Items := Context.Manager.Find<TItem>
        .Where(Criteria)
        .List;
      try
        Arr := TJSONArray.Create;
        try
          for Item in Items do
          begin
            Obj := TJSONObject.Create;
            Obj.AddPair('id', TJSONNumber.Create(Item.Id));
            Obj.AddPair('url', MakeElnItemUrl(Item));
            Obj.AddPair('title', Item.Title);
            Obj.AddPair('level', ItemLevelToStr(Item.Level));
            Obj.AddPair('type', ItemTypeToStr(Item.Type_));
            Obj.AddPair('description', Item.Description);
            Obj.AddPair('parent_id', TJSONNumber.Create(Item.Parent));
            Obj.AddPair('folder_id', TJSONNumber.Create(Item.FolderID));
            Obj.AddPair('created_date', DateToISO(Item.CreatedDate));
            Obj.AddPair('modified_date', NullableDateToJSON(Item.ModifiedDate));

            if Assigned(Item.ActionType) then
              Obj.AddPair('action_type', Item.ActionType.Title)
            else
              Obj.AddPair('action_type', TJSONNull.Create);

            if Assigned(Item.Equipment) then
              Obj.AddPair('equipment', Item.Equipment.Model)
            else
              Obj.AddPair('equipment', TJSONNull.Create);

            if IncludeTags then
            begin
              if not TagMap.TryGetValue(Item.Id, ItemTags) then
                ItemTags := nil;
              Obj.AddPair('tags', TagsToJSONArray(ItemTags));
            end;

            Arr.AddElement(Obj);
          end;
        except
          Arr.Free;
          raise;
        end;

        Result := TJSONObject.Create;
        Result.AddPair('items', Arr);
      finally
        Items.Free;
      end;
    finally
      TagMap.Free;
    end;
  finally
    ItemDic.Free;
  end;
end;

function HandleGetItem(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  InBin: Boolean;
  Item: TItem;
  ItemDic: TItemDictionary;
  Children: TList<TItem>;
  Child: TItem;
  F: TFile;
  V: TValue;
  E: TLabEntry;
  ChildArr, FilesArr, ValuesArr, EntriesArr: TJSONArray;
  Obj: TJSONObject;
  TagModel: TTagModel;
  Tags: TTags;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);

  Result := TJSONObject.Create;
  try
    Result.AddPair('id', TJSONNumber.Create(Item.Id));
    Result.AddPair('url', MakeElnItemUrl(Item));
    Result.AddPair('title', Item.Title);
    Result.AddPair('level', ItemLevelToStr(Item.Level));
    Result.AddPair('type', ItemTypeToStr(Item.Type_));
    Result.AddPair('description', Item.Description);
    Result.AddPair('properties', Item.Properties);
    Result.AddPair('parent_id', TJSONNumber.Create(Item.Parent));
    Result.AddPair('project_id', TJSONNumber.Create(Item.ProjectID));
    Result.AddPair('folder_id', TJSONNumber.Create(Item.FolderID));
    Result.AddPair('sort_order', TJSONNumber.Create(Item.SortOrder));
    Result.AddPair('is_deleted', TJSONBool.Create(Item.IsDeleted));
    Result.AddPair('created_date', DateToISO(Item.CreatedDate));
    Result.AddPair('modified_date', NullableDateToJSON(Item.ModifiedDate));

    // Tags - always present. get_item is a single-item read, so the per-item
    // query TTagModel does is fine here (list_items uses the batched map).
    TagModel := TTagModel.Create(Context.Manager);
    try
      Tags := TagModel.GetTagsForItem(ItemId);
      try
        Result.AddPair('tags', TagsToJSONArray(Tags));
      finally
        Tags.Free;
      end;
    finally
      TagModel.Free;
    end;

    ItemDic := TItemDictionary.Create;
    try
      Children := Context.Manager.Find<TItem>
        .Where((ItemDic.ParentID = ItemId) and (ItemDic.IsDeleted = False))
        .List;
    finally
      ItemDic.Free;
    end;
    try
      ChildArr := TJSONArray.Create;
      for Child in Children do
      begin
        Obj := TJSONObject.Create;
        Obj.AddPair('id', TJSONNumber.Create(Child.Id));
        Obj.AddPair('url', MakeElnItemUrl(Child));
        Obj.AddPair('title', Child.Title);
        Obj.AddPair('level', ItemLevelToStr(Child.Level));
        Obj.AddPair('type', ItemTypeToStr(Child.Type_));
        ChildArr.AddElement(Obj);
      end;
      Result.AddPair('children', ChildArr);
    finally
      Children.Free;
    end;

    FilesArr := TJSONArray.Create;
    InBin := ItemInRecycleBin(Context.Manager, Item);
    for F in Item.Files do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', TJSONNumber.Create(F.Id));
      Obj.AddPair('title', F.Title);
      Obj.AddPair('full_name', F.FullName);
      Obj.AddPair('hash', F.Hash);
      Obj.AddPair('created_date', DateToISO(F.CreatedDate));
      Obj.AddPair('is_deleted', TJSONBool.Create(InBin));
      FilesArr.AddElement(Obj);
    end;
    Result.AddPair('files', FilesArr);

    ValuesArr := TJSONArray.Create;
    for V in Item.Values do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', TJSONNumber.Create(V.Id));
      Obj.AddPair('value', SmartNum(V.Value));
      Obj.AddPair('tolerance', SmartNum(V.Tol));
      Obj.AddPair('description', V.Description);
      if Assigned(V.ValueType) then
      begin
        Obj.AddPair('value_type', V.ValueType.Title);
        Obj.AddPair('units', V.ValueType.Units);
        Obj.AddPair('symbol', V.ValueType.Symbol);
      end;
      Obj.AddPair('source', ValueSourceJSON(V));
      ValuesArr.AddElement(Obj);
    end;
    Result.AddPair('values', ValuesArr);

    EntriesArr := TJSONArray.Create;
    for E in Item.Entries do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', TJSONNumber.Create(E.Id));
      Obj.AddPair('title', E.Title);
      Obj.AddPair('created_date', DateToISO(E.CreatedDate));
      EntriesArr.AddElement(Obj);
    end;
    Result.AddPair('entries', EntriesArr);
  except
    Result.Free;
    raise;
  end;
end;

function HandleSearch(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Query: string;
  ProjectId: Integer;
  HasProject: Boolean;
  SearchModel: TSearchModel;
  Results: TSearchResults;
  R: TSearchResult;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  Query := GetReqStr(Params, 'query');
  HasProject := GetOptInt(Params, 'project_id', ProjectId);

  SearchModel := TSearchModel.Create(Context.Manager, Context.AccessPolicy);
  try
    SearchModel.AssignUser(Context.User);
    Results := SearchModel.Search(Query);
    try
      Arr := TJSONArray.Create;
      try
        for R in Results do
        begin
          if HasProject and (R.ProjectId <> ProjectId) then
            Continue;

        // Search spans projects: omit invisible hits instead of refusing the whole query.
          if not IsProjectVisible(Context, R.ProjectId) then
            Continue;

          Obj := TJSONObject.Create;
          Obj.AddPair('item_id', TJSONNumber.Create(R.ItemId));
          Obj.AddPair('project_id', TJSONNumber.Create(R.ProjectId));
          Obj.AddPair('folder_id', TJSONNumber.Create(R.FolderId));
          Obj.AddPair('kind', SearchResultKindNames[R.Kind]);
          Obj.AddPair('entity_name', R.EntityName);
          Obj.AddPair('matched_field', R.MatchedField);
          Obj.AddPair('project_path', R.ProjectPath);
          if R.Kind = srkFile then
          begin
            Obj.AddPair('file_id', TJSONNumber.Create(R.FileId));
            Obj.AddPair('full_name', R.FullName);
            Obj.AddPair('extension', R.Extension);
          end;
          Arr.AddElement(Obj);
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('results', Arr);
    finally
      Results.Free;
    end;
  finally
    SearchModel.Free;
  end;
end;

resourcestring
  SSemanticUnavailable = 'Semantic search is not installed. Install it in ' +
    'ELN Community: Tools > Semantic Search Setup. Use the search tool for ' +
    'keyword search. [semantic_search_unavailable]';
  SSemanticCouldNotStart = 'Semantic search could not start: %s ' +
    '[semantic_search_unavailable]';
  STopKRange = 'top_k must be an integer from 1 to 50.';
  SNotAnArray = '%s must be an array.';
  SNotAString = '%s must contain only strings.';
  SNotPositive = '%s must be a positive integer.';
  SBadDateField = 'date_field must be "created" or "modified".';
  SBadIsoDate = '%s must be an ISO 8601 date, for example 2026-01-31.';
  SBadValueEntry = 'values[%d] must be an object.';
  SNoValueType = 'values[%d].value_type is required.';
  SBadLimit = 'values[%d].%s must be a number.';
  SBadFiltersApplied = 'The semantic search returned an invalid filters_applied object.';

const
  DefaultTopK = 10;
  MaxTopK = 50;
  MinQueryChars = 2;

function SemanticVisibleIds(const Context: TToolContext; HasProject: Boolean;
  ProjectId: Integer): TArray<Integer>;
var
  Id: Integer;
  Ids: TList<Integer>;
begin
  Ids := TList<Integer>.Create;
  try
    for Id in SearchVisibleProjectIds(Context.Manager, Context.AccessPolicy, Context.User) do
      if (not HasProject or (Id = ProjectId)) and IsProjectVisible(Context, Id) then
        Ids.Add(Id);
    Result := Ids.ToArray;
  finally
    Ids.Free;
  end;
end;

function ReadFilterStrings(const Params: TJSONObject; const Key: string): TArray<string>;
var
  Node, Entry: TJSONValue;
begin
  Result := nil;
  Node := Params.FindValue(Key);
  if (Node = nil) or (Node is TJSONNull) then
    Exit;
  if not (Node is TJSONArray) then
    raise Exception.CreateFmt(SNotAnArray, [Key]);
  for Entry in TJSONArray(Node) do
  begin
    if not (Entry is TJSONString) or (Entry is TJSONNumber) then
      raise Exception.CreateFmt(SNotAString, [Key]);
    Result := Result + [Entry.Value];
  end;
end;

function ReadFilterId(const Params: TJSONObject; const Key: string): Integer;
begin
  Result := 0;
  if GetOptInt(Params, Key, Result) and (Result < 1) then
    raise Exception.CreateFmt(SNotPositive, [Key]);
end;

function ReadFilterDate(const Params: TJSONObject; const Key: string): TDateTime;
var
  Text: string;
begin
  Result := 0;
  if not GetOptStr(Params, Key, Text) then
    Exit;
  if Text.Contains('T') or Text.Contains(':') or Text.Contains(' ') then
    raise Exception.CreateFmt(SBadIsoDate, [Key]);
  try
    Result := ISO8601ToDate(Text, True);
  except
    on EDateTimeException do
      raise Exception.CreateFmt(SBadIsoDate, [Key]);
  end;
end;

function ReadFilterLimit(const Entry: TJSONObject; Index: Integer;
  const Key: string; out Limit: Double): Boolean;
var
  Node: TJSONValue;
begin
  Limit := 0;
  Node := Entry.FindValue(Key);
  if (Node = nil) or (Node is TJSONNull) then
    Exit(False);
  if not (Node is TJSONNumber) then
    raise Exception.CreateFmt(SBadLimit, [Index, Key]);
  Limit := TJSONNumber(Node).AsDouble;
  Result := True;
end;

function ReadFilterValues(const Params: TJSONObject): TArray<TValueConstraint>;
var
  Node, Entry: TJSONValue;
  Obj: TJSONObject;
  Constraint: TValueConstraint;
  Text: string;
  Index: Integer;
begin
  Result := nil;
  Node := Params.FindValue('values');
  if (Node = nil) or (Node is TJSONNull) then
    Exit;
  if not (Node is TJSONArray) then
    raise Exception.CreateFmt(SNotAnArray, ['values']);
  Index := 0;
  for Entry in TJSONArray(Node) do
  begin
    if not (Entry is TJSONObject) then
      raise Exception.CreateFmt(SBadValueEntry, [Index]);
    Obj := TJSONObject(Entry);
    Constraint := Default(TValueConstraint);
    if not GetOptStr(Obj, 'value_type', Constraint.ValueType) or (Trim(Constraint.ValueType) = '') then
      raise Exception.CreateFmt(SNoValueType, [Index]);
    Constraint.HasMin := ReadFilterLimit(Obj, Index, 'min', Constraint.Min);
    Constraint.HasMax := ReadFilterLimit(Obj, Index, 'max', Constraint.Max);
    if GetOptStr(Obj, 'unit', Text) then
      Constraint.UnitSymbol := Text;
    if GetOptStr(Obj, 'rec_type', Text) then
      Constraint.RecType := Text;
    Result := Result + [Constraint];
    Inc(Index);
  end;
end;

function ReadSemanticFilter(const Params: TJSONObject): TSemanticSearchFilter;
var
  Text: string;
  HasFrom, HasTo: Boolean;
begin
  Result := Default(TSemanticSearchFilter);
  Result.FolderId := ReadFilterId(Params, 'folder_id');
  Result.ItemTypes := ReadFilterStrings(Params, 'item_types');
  Result.Levels := ReadFilterStrings(Params, 'levels');
  Result.ActionTypeId := ReadFilterId(Params, 'action_type_id');
  Result.DateFrom := ReadFilterDate(Params, 'date_from');
  Result.DateTo := ReadFilterDate(Params, 'date_to');
  HasFrom := Params.FindValue('date_from') is TJSONString;
  HasTo := Params.FindValue('date_to') is TJSONString;
  if GetOptStr(Params, 'date_field', Text) then
  begin
    if SameText(Trim(Text), 'created') then
      Result.DateField := sdfCreated
    else if SameText(Trim(Text), 'modified') then
      Result.DateField := sdfModified
    else
      raise Exception.Create(SBadDateField);
  end
  else if HasFrom or HasTo then
    Result.DateField := sdfCreated;
  Result.Values := ReadFilterValues(Params);
end;

function IndexJson(const Status: TSemanticSearchStatus): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('complete', TJSONBool.Create(Status.IsComplete));
  Result.AddPair('indexed_passages', TJSONNumber.Create(Status.IndexedPassages));
  Result.AddPair('pending_passages', TJSONNumber.Create(Status.PendingPassages));
  Result.AddPair('files_pending', TJSONNumber.Create(Status.FilesTotal - Status.FilesDone));
end;

function HandleSearchSemantic(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Search: ISemanticSearch;
  Request: TSemanticSearchRequest;
  ProjectId: Integer;
  HasProject: Boolean;
  Provider: ISearchDocumentSource;
  Searched: TSemanticSearchResult;
  Group: THybridGroup;
  Passage: THybridHit;
  Item: TItem;
  SearchModel: TSearchModel;
  HitSource: TSearchHitSource;
  Arr, SourcesArr, PassagesArr: TJSONArray;
  Obj, PassageObj, Applied: TJSONObject;
  Parsed: TJSONValue;
begin
  Search := Context.SemanticSearch;
  if Search = nil then
    raise Exception.Create(SSemanticUnavailable);
  Request := Default(TSemanticSearchRequest);
  Request.Query := GetReqStr(Params, 'query');
  HasProject := GetOptInt(Params, 'project_id', ProjectId);
  if HasProject then
    RequireProjectRead(Context, ProjectId);
  if not GetOptInt(Params, 'top_k', Request.TopK) then
    Request.TopK := DefaultTopK;
  if (Request.TopK < 1) or (Request.TopK > MaxTopK) then
    raise Exception.Create(STopKRange);
  Request.Filter := ReadSemanticFilter(Params);
  Request.Rerank := True;

  if Length(Trim(Request.Query)) < MinQueryChars then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('groups', TJSONArray.Create);
    Result.AddPair('index', IndexJson(Search.Status));
    Result.AddPair('reranked', TJSONBool.Create(False));
    Exit;
  end;

  Request.VisibleProjectIds := SemanticVisibleIds(Context, HasProject, ProjectId);
  try
    if (Context.SemanticIndex <> nil) and not Search.IsRemote then
    begin
      if not Request.Filter.IsEmpty then
        ResolveSemanticFilter(Context.Manager, Request.VisibleProjectIds, Request.Filter);
      Provider := TNotebookDocumentProvider.Create(Context.Manager);
      Context.SemanticIndex.SyncNow(Provider.ReadSnapshot(nil),
        TStorageFileReader.Create(Context.Storage), SemanticSyncDeadlineMs);
    end;
    Searched := Search.Search(Request, nil);
  except
    on E: ESemanticSearchUnavailable do
      raise Exception.Create(Format(SSemanticCouldNotStart, [E.Message]));
  end;

  Arr := TJSONArray.Create;
  try
    SearchModel := TSearchModel.Create(Context.Manager, Context.AccessPolicy);
    try
      SearchModel.AssignUser(Context.User);
      for Group in Searched.Groups do
      begin
        if not IsProjectVisible(Context, Group.ProjectId) then
          Continue;
        Item := Context.Manager.Find<TItem>(Group.ItemId);
        if Item = nil then
          Continue;
        SourcesArr := TJSONArray.Create;
        for HitSource in Group.Sources do
          SourcesArr.Add(HitSourceNames[HitSource]);
        PassagesArr := TJSONArray.Create;
        for Passage in Group.Passages do
        begin
          PassageObj := TJSONObject.Create;
          PassagesArr.AddElement(PassageObj);
          PassageObj.AddPair('field', PassageFieldNames[Passage.Field]);
          PassageObj.AddPair('file_id', TJSONNumber.Create(Passage.FileId));
          PassageObj.AddPair('snippet', Passage.Snippet);
          PassageObj.AddPair('score', TJSONNumber.Create(Passage.Score));
        end;
        Obj := TJSONObject.Create;
        Arr.AddElement(Obj);
        Obj.AddPair('item_id', TJSONNumber.Create(Group.ItemId));
        Obj.AddPair('item_title', Item.Title);
        Obj.AddPair('project_id', TJSONNumber.Create(Group.ProjectId));
        Obj.AddPair('project_path',
          SearchModel.BuildProjectPath(Item.ProjectID, Item.FolderID));
        Obj.AddPair('score', TJSONNumber.Create(Group.Score));
        Obj.AddPair('sources', SourcesArr);
        Obj.AddPair('passages', PassagesArr);
      end;
    finally
      SearchModel.Free;
    end;
    Applied := nil;
    if Searched.FiltersApplied <> '' then
    begin
      Parsed := TJSONObject.ParseJSONValue(Searched.FiltersApplied);
      if not (Parsed is TJSONObject) then
      begin
        Parsed.Free;
        raise Exception.Create(SBadFiltersApplied);
      end;
      Applied := TJSONObject(Parsed);
    end;
    Result := TJSONObject.Create;
    Result.AddPair('groups', Arr);
    Result.AddPair('reranked', TJSONBool.Create(Searched.Reranked));
    Result.AddPair('index', IndexJson(Searched.IndexStatus));
    if Applied <> nil then
      Result.AddPair('filters_applied', Applied);
  except
    Arr.Free;
    raise;
  end;
end;


function MakeListProjectsSchema: TJSONObject;
var
  Props, IncArchived: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  IncArchived := TJSONObject.Create;
  IncArchived.AddPair('type', 'boolean');
  IncArchived.AddPair('description', 'Include archived projects (default: false)');
  Props.AddPair('include_archived', IncArchived);
  Result.AddPair('properties', Props);
end;

function MakeListFoldersSchema: TJSONObject;
var
  Props, ProjId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  ProjId := TJSONObject.Create;
  ProjId.AddPair('type', 'integer');
  ProjId.AddPair('description', 'Project ID');
  Props.AddPair('project_id', ProjId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('project_id');
  Result.AddPair('required', Req);
end;

function MakeListItemsSchema: TJSONObject;
var
  Props, ProjId, FoldId, IType, Lvl, IncTags: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  ProjId := TJSONObject.Create;
  ProjId.AddPair('type', 'integer');
  ProjId.AddPair('description', 'Project ID');
  Props.AddPair('project_id', ProjId);

  FoldId := TJSONObject.Create;
  FoldId.AddPair('type', 'integer');
  FoldId.AddPair('description', 'Filter by folder ID');
  Props.AddPair('folder_id', FoldId);

  IType := TJSONObject.Create;
  IType.AddPair('type', 'string');
  IType.AddPair('description',
    'Filter by item type: Synthesis, Treatment, Measurement, Testing, ' +
    'Characterization, Computing, Specimen, Model, Other');
  Props.AddPair('item_type', IType);

  Lvl := TJSONObject.Create;
  Lvl.AddPair('type', 'string');
  Lvl.AddPair('description', 'Filter by level: Proc, Item, Action, Folder');
  Props.AddPair('level', Lvl);

  IncTags := TJSONObject.Create;
  IncTags.AddPair('type', 'boolean');
  IncTags.AddPair('description',
    'Include each item''s tags in the response (default false). Off by ' +
    'default because it costs extra queries; get_item always returns tags.');
  Props.AddPair('include_tags', IncTags);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('project_id');
  Result.AddPair('required', Req);
end;

function MakeGetItemSchema: TJSONObject;
var
  Props, ItemId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  ItemId := TJSONObject.Create;
  ItemId.AddPair('type', 'integer');
  ItemId.AddPair('description', 'Item ID');
  Props.AddPair('item_id', ItemId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;

function MakeSearchSchema: TJSONObject;
var
  Props, QStr, ProjId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  QStr := TJSONObject.Create;
  QStr.AddPair('type', 'string');
  QStr.AddPair('description', 'Search query (min 2 characters)');
  Props.AddPair('query', QStr);

  ProjId := TJSONObject.Create;
  ProjId.AddPair('type', 'integer');
  ProjId.AddPair('description', 'Limit search to a specific project');
  Props.AddPair('project_id', ProjId);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('query');
  Result.AddPair('required', Req);
end;

procedure AddSchemaProp(Props: TJSONObject; const Name, TypeName, Description: string);
var
  Prop: TJSONObject;
begin
  Prop := TJSONObject.Create;
  Prop.AddPair('type', TypeName);
  Prop.AddPair('description', Description);
  Props.AddPair(Name, Prop);
end;

function StringArraySchema(const Description: string): TJSONObject;
var
  Items: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'array');
  Items := TJSONObject.Create;
  Items.AddPair('type', 'string');
  Result.AddPair('items', Items);
  Result.AddPair('description', Description);
end;

function ValueFiltersSchema: TJSONObject;
var
  Items, Props: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'array');
  Items := TJSONObject.Create;
  Items.AddPair('type', 'object');
  Props := TJSONObject.Create;
  AddSchemaProp(Props, 'value_type', 'string', 'Title or symbol of the value type, as in query_values.');
  AddSchemaProp(Props, 'min', 'number', 'Lowest value, inclusive.');
  AddSchemaProp(Props, 'max', 'number', 'Highest value, inclusive.');
  AddSchemaProp(Props, 'unit', 'string',
    'Unit of min and max. The limits are converted into the unit of the value type. ' +
    'Empty means the unit of the value type. A unit of another dimension is an error.');
  AddSchemaProp(Props, 'rec_type', 'string', 'EXP_CONDITION or TEST_RESULT. Empty means both.');
  Items.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('value_type');
  Items.AddPair('required', Req);
  Result.AddPair('items', Items);
  Result.AddPair('description',
    'Only items that have a recorded value for every entry (AND). min and max ' +
    'are inclusive.');
end;

function MakeSearchSemanticSchema: TJSONObject;
var
  Props, QStr, ProjId, TopK: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  QStr := TJSONObject.Create;
  QStr.AddPair('type', 'string');
  QStr.AddPair('description', 'Search query in natural language (min 2 characters)');
  Props.AddPair('query', QStr);

  TopK := TJSONObject.Create;
  TopK.AddPair('type', 'integer');
  TopK.AddPair('minimum', TJSONNumber.Create(1));
  TopK.AddPair('maximum', TJSONNumber.Create(50));
  TopK.AddPair('default', TJSONNumber.Create(10));
  TopK.AddPair('description', 'Maximum number of item groups');
  Props.AddPair('top_k', TopK);

  ProjId := TJSONObject.Create;
  ProjId.AddPair('type', 'integer');
  ProjId.AddPair('description', 'Limit search to a specific project');
  Props.AddPair('project_id', ProjId);

  AddSchemaProp(Props, 'folder_id', 'integer',
    'Only items in this folder and its subfolders. The folder must be in a project you can read.');
  Props.AddPair('item_types', StringArraySchema(
    'Only items of these types: Synthesis, Treatment, Measurement, Testing, ' +
    'Characterization, Computing, Specimen, Model, Other, Wiki.'));
  Props.AddPair('levels', StringArraySchema(
    'Only items of these hierarchy levels: Proc, Item, Action, Folder.'));
  AddSchemaProp(Props, 'action_type_id', 'integer', 'Only items of this action type.');
  AddSchemaProp(Props, 'date_field', 'string',
    'Which date date_from and date_to test: created (default) or modified. ' +
    'An item without a modified date never matches modified.');
  AddSchemaProp(Props, 'date_from', 'string',
    'First day, ISO 8601 date, for example 2026-01-31. The day is included.');
  AddSchemaProp(Props, 'date_to', 'string',
    'Last day, ISO 8601 date. The whole day is included.');
  Props.AddPair('values', ValueFiltersSchema);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('query');
  Result.AddPair('required', Req);
end;


procedure RegisterNavigationTools(Registry: TToolRegistry);
begin
  Registry.Register('list_projects',
    'List all projects with item counts. Returns project metadata including ' +
    'title, description, owner, dates, and number of items.',
    MakeListProjectsSchema, HandleListProjects, tscProjectScoped);

  Registry.Register('list_folders',
    'List all folders within a project. Returns folder hierarchy with ' +
    'parent references and sort order.',
    MakeListFoldersSchema, HandleListFolders, tscProjectScoped);

  Registry.Register('list_items',
    'List items (experiments, specimens, actions) in a project. ' +
    'Optionally filter by folder, item type, or hierarchy level. ' +
    'Each item includes a `url` field — an eln://item/N (or ' +
    'eln://specimen/<title>) link that opens the item in the desktop ' +
    'ELN client when clicked in a markdown-rendering chat client. ' +
    'Set include_tags:true to get each item''s tags as well (off by default ' +
    'because it costs extra queries).',
    MakeListItemsSchema, HandleListItems, tscProjectScoped);

  Registry.Register('get_item',
    'Get detailed information about a single item including its children, ' +
    'attached files, recorded values, lab entries, and tags (each tag as ' +
    'id, name, color (#BBGGRR, as stored) and color_rgb (#RRGGBB)). ' +
    'The item and each entry in the children array include a `url` field — ' +
    'an eln://item/N (or eln://specimen/<title>) link that opens the item ' +
    'in the desktop ELN client when clicked in a markdown-rendering chat ' +
    'client.',
    MakeGetItemSchema, HandleGetItem, tscProjectScoped);

  Registry.Register('search',
    'Full-text search across items, protocols, files, values, and tags. ' +
    'File-name matches include the complete filename, extension, and file ID. ' +
    'Supports multi-word queries with automatic intersection.',
    MakeSearchSchema, HandleSearch, tscProjectScoped);

  Registry.Register('search_semantic',
    'Search by meaning across item titles, descriptions, properties, tags, ' +
    'entries, protocol forms, value descriptions, and the names and text of ' +
    'attached files. Combines vector and word matching. Brings the index up ' +
    'to date first; index.complete is false when it is still catching up, ' +
    'so repeat the call to finish. Returns groups, one per item, best first: ' +
    'each group has item_id, item_title, project_id, project_path, score, ' +
    'sources, and up to 3 passages with field, file_id, snippet, and score. ' +
    'top_k counts groups. This replaces the earlier flat hits list. ' +
    'When the optional reranking model is installed, a second model sorts ' +
    'the best 20 groups by how well the best passage of each group answers ' +
    'the query; reranked is true when that order was used, and false when ' +
    'the model is not installed, took too long, or failed. Then the groups ' +
    'are in hybrid order. The score of a group is the hybrid score and does ' +
    'not follow the reranked order. ' +
    'Optional filters narrow the search before ranking, so a strict filter ' +
    'still finds items that a plain search would rank low. Filters are ' +
    'explicit parameters; nothing is read from the query text. ' +
    'filters_applied echoes what was enforced, with value limits converted ' +
    'into the unit of each value type. Filters never reach beyond the ' +
    'projects the caller can read.',
    MakeSearchSemanticSchema, HandleSearchSemantic, tscProjectScoped);
end;

end.
