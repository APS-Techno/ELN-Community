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

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  System.TypInfo, System.DateUtils, System.Rtti,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Item, unit_Project, unit_ItemTypes, unit_ELNDB_Dictionary,
  unit_LabEntry, unit_ValueType, unit_SearchModel,
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
    for F in Item.Files do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', TJSONNumber.Create(F.Id));
      Obj.AddPair('title', F.Title);
      Obj.AddPair('full_name', F.FullName);
      Obj.AddPair('hash', F.Hash);
      Obj.AddPair('created_date', DateToISO(F.CreatedDate));
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
end;

end.
