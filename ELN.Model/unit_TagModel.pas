unit unit_TagModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  unit_Tag,
  unit_ELNDB_Dictionary;

type
  TTagModel = class
  private
    FManager: TObjectManager;
    FTagDic: TTagDictionary;
    FItemTagDic: TItemTagDictionary;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;

    // Tag CRUD
    function AddTag(const Name, Color: string; CreatedBy: Integer): TTag;
    procedure UpdateTag(Tag: TTag);
    procedure DeleteTag(TagId: Integer);
    function GetAllTags: TTags;
    function GetTag(TagId: Integer): TTag;
    function FindTagsByName(const AName: string): TTags;

    // Item-Tag assignment
    procedure AssignTag(ItemId, TagId: Integer);
    procedure UnassignTag(ItemId, TagId: Integer);
    function GetTagsForItem(ItemId: Integer): TTags;
    function GetItemIdsForTag(TagId: Integer): TList<Integer>;
    function IsTagAssigned(ItemId, TagId: Integer): Boolean;
  end;

implementation

uses
  Aurelius.Criteria.Base,
  unit_TimeHelper;

{ TTagModel }

constructor TTagModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FTagDic := TTagDictionary.Create;
  FItemTagDic := TItemTagDictionary.Create;
end;

destructor TTagModel.Destroy;
begin
  FreeAndNil(FTagDic);
  FreeAndNil(FItemTagDic);
  inherited;
end;

function TTagModel.AddTag(const Name, Color: string; CreatedBy: Integer): TTag;
begin
  Result := TTag.Create;
  Result.Name := Name;
  Result.Color := Color;
  Result.CreatedBy := CreatedBy;
  Result.CreatedDate := UTCNow;
  FManager.Save(Result);
  FManager.Flush;
end;

procedure TTagModel.UpdateTag(Tag: TTag);
begin
  FManager.Flush;
end;

procedure TTagModel.DeleteTag(TagId: Integer);
var
  Tag: TTag;
  Links: TItemTags;
  Link: TItemTag;
begin
  // Remove all item-tag links first
  Links := FManager.Find<TItemTag>
    .Where(FItemTagDic.TagId = TagId)
    .List;
  try
    for Link in Links do
      FManager.Remove(Link);
  finally
    Links.Free;
  end;

  Tag := FManager.Find<TTag>(TagId);
  if Assigned(Tag) then
    FManager.Remove(Tag);

  FManager.Flush;
end;

function TTagModel.GetAllTags: TTags;
begin
  Result := FManager.Find<TTag>
    .OrderBy(FTagDic.Name)
    .List;
end;

function TTagModel.GetTag(TagId: Integer): TTag;
begin
  Result := FManager.Find<TTag>(TagId);
end;

function TTagModel.FindTagsByName(const AName: string): TTags;
var
  All: TTags;
  Tag: TTag;
  Target: string;
begin
  // Matching is done in Delphi rather than with a SQL WHERE on purpose: '='
  // is case-SENSITIVE on SQLite but case-INSENSITIVE under MySQL's default
  // collation, so a query would behave differently in the test suite than in
  // production. Tag counts are small (tens), so the full scan is free.
  // Callers rely on the id ordering to report duplicate candidates stably.
  Result := TTags.Create;
  try
    Target := Trim(AName);
    All := FManager.Find<TTag>
      .OrderBy(FTagDic.Id)
      .List;
    try
      for Tag in All do
        if SameText(Trim(Tag.Name), Target) then
          Result.Add(Tag);
    finally
      All.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TTagModel.AssignTag(ItemId, TagId: Integer);
var
  Link: TItemTag;
begin
  if IsTagAssigned(ItemId, TagId) then
    Exit;

  Link := TItemTag.Create;
  Link.ItemId := ItemId;
  Link.TagId := TagId;
  Link.CreatedDate := UTCNow;
  FManager.Save(Link);
  FManager.Flush;
end;

procedure TTagModel.UnassignTag(ItemId, TagId: Integer);
var
  Links: TItemTags;
  Link: TItemTag;
begin
  Links := FManager.Find<TItemTag>
    .Where(
      (FItemTagDic.ItemId = ItemId) and
      (FItemTagDic.TagId = TagId))
    .List;
  try
    for Link in Links do
      FManager.Remove(Link);
    FManager.Flush;
  finally
    Links.Free;
  end;
end;

function TTagModel.GetTagsForItem(ItemId: Integer): TTags;
var
  Links: TItemTags;
  Link: TItemTag;
  Tag: TTag;
begin
  Result := TTags.Create;
  Links := FManager.Find<TItemTag>
    .Where(FItemTagDic.ItemId = ItemId)
    .List;
  try
    for Link in Links do
    begin
      Tag := FManager.Find<TTag>(Link.TagId);
      if Assigned(Tag) then
        Result.Add(Tag);
    end;
  finally
    Links.Free;
  end;
end;

function TTagModel.GetItemIdsForTag(TagId: Integer): TList<Integer>;
var
  Links: TItemTags;
  Link: TItemTag;
begin
  Result := TList<Integer>.Create;
  Links := FManager.Find<TItemTag>
    .Where(FItemTagDic.TagId = TagId)
    .List;
  try
    for Link in Links do
      Result.Add(Link.ItemId);
  finally
    Links.Free;
  end;
end;

function TTagModel.IsTagAssigned(ItemId, TagId: Integer): Boolean;
var
  Links: TItemTags;
begin
  Links := FManager.Find<TItemTag>
    .Where(
      (FItemTagDic.ItemId = ItemId) and
      (FItemTagDic.TagId = TagId))
    .Take(1)
    .List;
  try
    Result := Links.Count > 0;
  finally
    Links.Free;
  end;
end;

end.
