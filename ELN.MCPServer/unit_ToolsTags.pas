unit unit_ToolsTags;

// Tag write tools: create_tag, assign_tag, unassign_tag, get_item_tags.
//
// All four delegate to TTagModel (ELN.Model) rather than hand-rolling Aurelius
// calls, because TTagModel is exactly the code the desktop client runs. Sharing
// it is what guarantees the client and this server agree on tables, colour
// format and referential shape.

interface

uses
  System.JSON,
  unit_MCPTools;

procedure RegisterTagTools(Registry: TToolRegistry);

// The handlers are exported (unlike the other tool units, which keep them in
// the implementation section) so ELN.Tests can drive them directly against a
// real database without standing up the JSON-RPC transport.
function HandleCreateTag(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleAssignTag(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleUnassignTag(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleGetItemTags(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

// Converts between the desktop client's stored '#BBGGRR' (Delphi TColor byte
// order, see dlg_TagManager.pas:342) and web '#RRGGBB'. The swap is its own
// inverse, so one function serves both directions.
//
// The output is UPPERCASE hex, to match the desktop client byte for byte: the
// client writes tag colours with Format('#%.6x', [ColorToRGB(C)])
// (dlg_TagManager.pas:342), and Delphi's %x emits uppercase digits. Only values
// this server WRITES are uppercased - a colour already stored in the database is
// always echoed back verbatim, whatever case a legacy row happens to use.
function SwapHexByteOrder(const AHex: string): string;

// Read-side counterpart of SwapHexByteOrder: a malformed legacy Tags.Color must
// never abort a read, so an unconvertible value yields '' instead of raising.
// Exported because every read path that reports color_rgb (get_item_tags here,
// get_item / list_items in unit_ToolsNavigation) needs the same guard.
function TrySwapHexByteOrder(const AHex: string): string;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  Aurelius.Engine.ObjectManager,
  unit_Item, unit_Tag, unit_TagModel, unit_SignatureModel,
  unit_ToolsWrite, unit_ToolScope;

resourcestring
  SInvalidColor =
    'Invalid color "%s": expected 6 hex digits with a leading # (e.g. #00C000).';

{ ---- Helpers ---- }

function GetOptBool(const Params: TJSONObject; const Key: string;
  Default: Boolean): Boolean;
begin
  Result := Default;
  if (Params <> nil) and (Params.FindValue(Key) <> nil) and
     not (Params.FindValue(Key) is TJSONNull) then
    Result := Params.GetValue<Boolean>(Key);
end;

// True only for exactly '#' + 6 hex digits. Used both to guard the swap and to
// decide whether a legacy row's colour can be reported as color_rgb at all.
function IsHexColor(const AHex: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Length(AHex) <> 7) or (AHex[1] <> '#') then
    Exit;
  for I := 2 to 7 do
    if not CharInSet(AHex[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit;
  Result := True;
end;

procedure CheckHexColor(const AHex: string);
begin
  if not IsHexColor(AHex) then
    raise Exception.CreateFmt(SInvalidColor, [AHex]);
end;

function SwapHexByteOrder(const AHex: string): string;
begin
  CheckHexColor(AHex);
  Result := UpperCase('#' + Copy(AHex, 6, 2) + Copy(AHex, 4, 2) + Copy(AHex, 2, 2));
end;

function TrySwapHexByteOrder(const AHex: string): string;
begin
  if IsHexColor(AHex) then
    Result := SwapHexByteOrder(AHex)
  else
    Result := '';
end;

// 'id 3, id 6' - used by both the duplicate-name refusal in create_tag and the
// ambiguous-name refusal in assign_tag/unassign_tag.
function FormatTagIdList(Tags: TTags): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Tags.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format('id %d', [Tags[I].Id]);
  end;
end;

{ ---- create_tag ---- }

function HandleCreateTag(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  TagName, ColorBGR, ColorRGB, StoredColor: string;
  HasColor, HasColorRGB, AllowDuplicate: Boolean;
  TagModel: TTagModel;
  Existing: TTags;
  Tag: TTag;
begin
  // Tags have no project column. The injected policy decides global creation
  // access independently of project grants and reference-data editing.
  RequireWriteUser(Context);
  if Context.AccessPolicy = nil then
    raise Exception.Create('Access denied: no notebook access policy configured.');
  if not Context.AccessPolicy.CanCreateTags(Context.Manager, Context.User) then
    raise Exception.Create('Access denied: cannot create tags.');

  TagName := Trim(GetReqStr(Params, 'name'));
  if TagName = '' then
    raise Exception.Create('Tag name cannot be empty.');

  HasColor := GetOptStr(Params, 'color', ColorBGR);
  HasColorRGB := GetOptStr(Params, 'color_rgb', ColorRGB);
  if HasColor = HasColorRGB then
    raise Exception.Create(
      'Provide exactly one of color (#BBGGRR, the byte order the desktop ' +
      'client stores) or color_rgb (#RRGGBB, web order).');

  if HasColor then
  begin
    CheckHexColor(ColorBGR);
    StoredColor := UpperCase(ColorBGR);
  end
  else
    StoredColor := SwapHexByteOrder(ColorRGB);

  AllowDuplicate := GetOptBool(Params, 'allow_duplicate_name', False);

  TagModel := TTagModel.Create(Context.Manager);
  try
    // Tag names are not unique in the schema. Rather than silently create a
    // second "completed", refuse and name the existing id(s) so the caller can
    // decide between reusing one and deliberately duplicating.
    if not AllowDuplicate then
    begin
      Existing := TagModel.FindTagsByName(TagName);
      try
        if Existing.Count > 0 then
          raise Exception.CreateFmt(
            'Tag "%s" already exists (%s). Pass allow_duplicate_name:true to ' +
            'create another, or use the existing id with assign_tag.',
            [TagName, FormatTagIdList(Existing)]);
      finally
        Existing.Free;
      end;
    end;

    Tag := TagModel.AddTag(TagName, StoredColor, Context.User.Id);

    // No audit entry: TTagModel writes none for tag CRUD (the desktop client
    // does not either), and TAuditEntityType has no aetTag value to record
    // against. Adding one here would diverge from the client.

    Result := TJSONObject.Create;
    Result.AddPair('id', TJSONNumber.Create(Tag.Id));
    Result.AddPair('name', Tag.Name);
    Result.AddPair('color', Tag.Color);
    Result.AddPair('color_rgb', SwapHexByteOrder(Tag.Color));
  finally
    TagModel.Free;
  end;
end;

{ ---- assign_tag / unassign_tag shared resolution ---- }

// tag_id XOR tag_name. Returns a manager-owned TTag - do not free it.
function ResolveTag(TagModel: TTagModel; const Params: TJSONObject): TTag;
var
  TagId: Integer;
  TagName: string;
  HasId, HasName: Boolean;
  Matches: TTags;
begin
  HasId := GetOptInt(Params, 'tag_id', TagId);
  HasName := GetOptStr(Params, 'tag_name', TagName);
  if HasId = HasName then
    raise Exception.Create('Provide exactly one of tag_id or tag_name.');

  if HasId then
  begin
    Result := TagModel.GetTag(TagId);
    if not Assigned(Result) then
      raise Exception.CreateFmt('Tag not found: %d', [TagId]);
    Exit;
  end;

  Matches := TagModel.FindTagsByName(Trim(TagName));
  try
    if Matches.Count = 0 then
      raise Exception.CreateFmt(
        'Tag not found: "%s". Use create_tag to create it, or list_tags to ' +
        'see existing names.', [TagName]);
    // Duplicate names are legal in this schema, so picking the first match
    // would silently tag against the wrong tag. Always refuse and enumerate.
    if Matches.Count > 1 then
      raise Exception.CreateFmt(
        'Tag name "%s" is ambiguous: %d tags match (%s). Pass tag_id instead.',
        [TagName, Matches.Count, FormatTagIdList(Matches)]);
    Result := Matches[0];
  finally
    Matches.Free;
  end;
end;

// item_id XOR item_ids, de-duplicated preserving first-seen order.
function ResolveItemIds(const Params: TJSONObject): TList<Integer>;
var
  ItemId, I: Integer;
  HasId, HasIds: Boolean;
  IdsValue: TJSONValue;
  Arr: TJSONArray;
begin
  HasId := GetOptInt(Params, 'item_id', ItemId);

  IdsValue := nil;
  if Params <> nil then
    IdsValue := Params.FindValue('item_ids');
  HasIds := (IdsValue <> nil) and not (IdsValue is TJSONNull);

  if HasId = HasIds then
    raise Exception.Create('Provide exactly one of item_id or item_ids.');

  Result := TList<Integer>.Create;
  try
    if HasId then
      Result.Add(ItemId)
    else
    begin
      if not (IdsValue is TJSONArray) then
        raise Exception.Create('item_ids must contain only integers.');
      Arr := TJSONArray(IdsValue);
      if Arr.Count = 0 then
        raise Exception.Create('item_ids must contain at least one id.');
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONNumber) then
          raise Exception.Create('item_ids must contain only integers.');
        ItemId := TJSONNumber(Arr.Items[I]).AsInt;
        if not Result.Contains(ItemId) then
          Result.Add(ItemId);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

// Validate every item BEFORE any row is written, so a single bad id in a batch
// leaves the database untouched rather than half-tagged.
procedure PreflightItems(const Context: TToolContext; Ids: TList<Integer>);
var
  Id: Integer;
  Item: TItem;
begin
  for Id in Ids do
  begin
    // Scope first, with the uniform refusal: the write-path errors below
    // ("Item not found", "no write permission") would otherwise tell a
    // confined caller which out-of-scope ids exist.
    RequireItemRead(Context, Id);
    Item := Context.Manager.Find<TItem>(Id);
    if not Assigned(Item) then
      raise Exception.CreateFmt('Item not found: %d', [Id]);
    CheckProjectWriteAccess(Context, Item.ProjectID);
    if IsItemSignedCheck(Context.Manager, Id) then
      raise Exception.CreateFmt('Item %d is signed and cannot be modified.', [Id]);
  end;
end;

{ ---- assign_tag ---- }

function HandleAssignTag(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  TagModel: TTagModel;
  Tag: TTag;
  Ids: TList<Integer>;
  Id: Integer;
  AssignedArr, AlreadyArr: TJSONArray;
begin
  TagModel := TTagModel.Create(Context.Manager);
  try
    Tag := ResolveTag(TagModel, Params);
    Ids := ResolveItemIds(Params);
    try
      PreflightItems(Context, Ids);

      AssignedArr := TJSONArray.Create;
      try
        AlreadyArr := TJSONArray.Create;
        try
          for Id in Ids do
            if TagModel.IsTagAssigned(Id, Tag.Id) then
              AlreadyArr.AddElement(TJSONNumber.Create(Id))
            else
            begin
              TagModel.AssignTag(Id, Tag.Id);
              AssignedArr.AddElement(TJSONNumber.Create(Id));
            end;

          Result := TJSONObject.Create;
        except
          AlreadyArr.Free;
          raise;
        end;
      except
        AssignedArr.Free;
        raise;
      end;

      Result.AddPair('tag_id', TJSONNumber.Create(Tag.Id));
      Result.AddPair('tag_name', Tag.Name);
      Result.AddPair('assigned', AssignedArr);
      Result.AddPair('already_assigned', AlreadyArr);
      Result.AddPair('item_count',
        TJSONNumber.Create(AssignedArr.Count + AlreadyArr.Count));
    finally
      Ids.Free;
    end;
  finally
    TagModel.Free;
  end;
end;

{ ---- unassign_tag ---- }

function HandleUnassignTag(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  TagModel: TTagModel;
  Tag: TTag;
  Ids: TList<Integer>;
  Id: Integer;
  UnassignedArr, NotAssignedArr: TJSONArray;
begin
  TagModel := TTagModel.Create(Context.Manager);
  try
    Tag := ResolveTag(TagModel, Params);
    Ids := ResolveItemIds(Params);
    try
      PreflightItems(Context, Ids);

      UnassignedArr := TJSONArray.Create;
      try
        NotAssignedArr := TJSONArray.Create;
        try
          for Id in Ids do
            if TagModel.IsTagAssigned(Id, Tag.Id) then
            begin
              TagModel.UnassignTag(Id, Tag.Id);
              UnassignedArr.AddElement(TJSONNumber.Create(Id));
            end
            else
              NotAssignedArr.AddElement(TJSONNumber.Create(Id));

          Result := TJSONObject.Create;
        except
          NotAssignedArr.Free;
          raise;
        end;
      except
        UnassignedArr.Free;
        raise;
      end;

      Result.AddPair('tag_id', TJSONNumber.Create(Tag.Id));
      Result.AddPair('tag_name', Tag.Name);
      Result.AddPair('unassigned', UnassignedArr);
      Result.AddPair('not_assigned', NotAssignedArr);
    finally
      Ids.Free;
    end;
  finally
    TagModel.Free;
  end;
end;

{ ---- get_item_tags ---- }

function HandleGetItemTags(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  Item: TItem;
  TagModel: TTagModel;
  Tags: TTags;
  Tag: TTag;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  ItemId := GetReqInt(Params, 'item_id');
  // Uniform refusal for out-of-scope and missing-under-scope; inert without
  // a scope, where the plain "Item not found" below still applies.
  RequireItemRead(Context, ItemId);

  // Read-only: no write-access check and no signed-item check on purpose. The
  // tagging state of a signed item must stay readable.
  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);

  TagModel := TTagModel.Create(Context.Manager);
  try
    Tags := TagModel.GetTagsForItem(ItemId);
    try
      // GetTagsForItem follows the ItemTags rows, whose order is not defined.
      // Sort by tag id so the response is stable for the caller.
      Tags.Sort(TComparer<TTag>.Construct(
        function(const L, R: TTag): Integer
        begin
          Result := L.Id - R.Id;
        end));

      Arr := TJSONArray.Create;
      try
        for Tag in Tags do
        begin
          Obj := TJSONObject.Create;
          Obj.AddPair('id', TJSONNumber.Create(Tag.Id));
          Obj.AddPair('name', Tag.Name);
          // Emitted verbatim: a legacy row may hold '' or a value that is not
          // '#' + 6 hex digits, and neither may break the read.
          Obj.AddPair('color', Tag.Color);
          Obj.AddPair('color_rgb', TrySwapHexByteOrder(Tag.Color));
          Arr.AddElement(Obj);
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('item_id', TJSONNumber.Create(ItemId));
      Result.AddPair('tags', Arr);
    finally
      Tags.Free;
    end;
  finally
    TagModel.Free;
  end;
end;

{ ---- Schemas ---- }

function MakeCreateTagSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Tag name (trimmed; must not be empty)');
  Props.AddPair('name', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Color in the desktop client''s storage order: #BBGGRR (Delphi TColor ' +
    'byte order), stored verbatim. Mutually exclusive with color_rgb.');
  Props.AddPair('color', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Color in web order: #RRGGBB. Converted to #BBGGRR on write. ' +
    'Mutually exclusive with color.');
  Props.AddPair('color_rgb', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'boolean');
  P.AddPair('description',
    'Create the tag even though a tag with this name already exists ' +
    '(default: false, which makes a duplicate name an error listing the ' +
    'existing id(s)).');
  Props.AddPair('allow_duplicate_name', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('name');
  Result.AddPair('required', Req);
end;

function MakeAssignTagSchema: TJSONObject;
var
  Props, P, IdsItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Tag ID. Provide exactly one of tag_id or tag_name.');
  Props.AddPair('tag_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Tag name (case-insensitive). Provide exactly one of tag_id or tag_name. ' +
    'Tag names are not unique: a name matching more than one tag is an error ' +
    'listing every matching id, never a guess.');
  Props.AddPair('tag_name', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Item ID to tag. Provide exactly one of item_id or item_ids.');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  IdsItem := TJSONObject.Create;
  IdsItem.AddPair('type', 'integer');
  P.AddPair('items', IdsItem);
  P.AddPair('description',
    'Item IDs to tag in a single call. Duplicates are collapsed. Provide ' +
    'exactly one of item_id or item_ids.');
  Props.AddPair('item_ids', P);

  Result.AddPair('properties', Props);
end;

function MakeUnassignTagSchema: TJSONObject;
var
  Props, P, IdsItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Tag ID. Provide exactly one of tag_id or tag_name.');
  Props.AddPair('tag_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Tag name (case-insensitive). Provide exactly one of tag_id or tag_name. ' +
    'Tag names are not unique: a name matching more than one tag is an error ' +
    'listing every matching id, never a guess.');
  Props.AddPair('tag_name', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Item ID to untag. Provide exactly one of item_id or item_ids.');
  Props.AddPair('item_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'array');
  IdsItem := TJSONObject.Create;
  IdsItem.AddPair('type', 'integer');
  P.AddPair('items', IdsItem);
  P.AddPair('description',
    'Item IDs to untag in a single call. Duplicates are collapsed. Provide ' +
    'exactly one of item_id or item_ids.');
  Props.AddPair('item_ids', P);

  Result.AddPair('properties', Props);
end;

function MakeGetItemTagsSchema: TJSONObject;
var
  Props, P: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Item ID');
  Props.AddPair('item_id', P);

  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;

{ ---- Registration ---- }

procedure RegisterTagTools(Registry: TToolRegistry);
begin
  Registry.Register('create_tag',
    'Create a tag. Colors use the desktop client''s storage order: pass either ' +
    'color (#BBGGRR, Delphi TColor order, stored verbatim) or color_rgb ' +
    '(#RRGGBB, web order, converted on write) - exactly one. Tag names are NOT ' +
    'unique in this database; create_tag refuses a name that already exists ' +
    'unless allow_duplicate_name is true, and the error names the existing ' +
    'id(s). Requires write access.',
    MakeCreateTagSchema, HandleCreateTag, tscGlobalRef);

  Registry.Register('assign_tag',
    'Assign one tag to one or more items. Identify the tag by tag_id or ' +
    'tag_name, and the items by item_id or item_ids (an array - use it to tag ' +
    'many items in a single call). Tag names are not unique: an ambiguous ' +
    'tag_name is an error listing every matching id, never a guess. Assigning ' +
    'a tag an item already has is a no-op, not a duplicate. All items are ' +
    'validated before any change is applied. Refuses signed items. Requires ' +
    'write access.',
    MakeAssignTagSchema, HandleAssignTag, tscProjectScoped);

  Registry.Register('unassign_tag',
    'Remove one tag from one or more items. Identify the tag by tag_id or ' +
    'tag_name, and the items by item_id or item_ids (an array - use it to ' +
    'untag many items in a single call). Tag names are not unique: an ' +
    'ambiguous tag_name is an error listing every matching id, never a guess. ' +
    'Removing a tag an item does not have is a no-op, not an error. All items ' +
    'are validated before any change is applied. Refuses signed items. ' +
    'Requires write access.',
    MakeUnassignTagSchema, HandleUnassignTag, tscProjectScoped);

  Registry.Register('get_item_tags',
    'List the tags assigned to an item. Returns each tag''s stored color ' +
    '(#BBGGRR) and color_rgb (#RRGGBB). Read-only.',
    MakeGetItemTagsSchema, HandleGetItemTags, tscProjectScoped);
end;

end.
