unit unit_ElnLinkHandler;


interface

uses
  System.Classes,
  unit_ELNPluginCore;

type
  TItemNavigationProc = reference to procedure(
    ProjectID, FolderID, ItemID: Integer);

  TElnLinkHandler = class(TInterfacedObject, IElnLinkHandler)
  private
    FNavigate: TItemNavigationProc;
  public
    constructor Create(const ANavigate: TItemNavigationProc);
    function HandleLink(const Url: string): Boolean;
  end;

procedure InstallElnLinkHandler(const ANavigate: TItemNavigationProc);
procedure UninstallElnLinkHandler;

// Set when an eln:// URL arrives via argv or WM_COPYDATA before the
// link handler has been installed (i.e., before login completes).
// Drained by frm_Main.FormShow via DispatchPendingElnUrl.
var
  PendingElnUrl: string;

procedure DispatchPendingElnUrl;

implementation

uses
  System.SysUtils, System.NetEncoding, System.StrUtils,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base, Aurelius.Criteria.Linq,
  unit_ELNDB_Dictionary,
  // unit_DataModel must come AFTER unit_ItemTypes — the latter exports an
  // unscoped `Model` enum value (TItemType.Model) that would otherwise shadow
  // the `Model: TDataModel` global.
  unit_Item, unit_ItemTypes, unit_DataModel;

function UrlDecode(const S: string): string;
begin
  Result := TNetEncoding.URL.Decode(S);
end;

function ParseElnUrl(const Url: string;
  out Kind, Ref: string): Boolean;
const
  PREFIX = 'eln://';
var
  Body: string;
  SlashPos: Integer;
begin
  Result := False;
  if not StartsText(PREFIX, Url) then Exit;
  Body := Copy(Url, Length(PREFIX) + 1, MaxInt);

  SlashPos := Pos('#', Body);
  if SlashPos > 0 then SetLength(Body, SlashPos - 1);
  SlashPos := Pos('?', Body);
  if SlashPos > 0 then SetLength(Body, SlashPos - 1);

  SlashPos := Pos('/', Body);
  if SlashPos <= 1 then Exit;

  Kind := LowerCase(Copy(Body, 1, SlashPos - 1));
  Ref  := Copy(Body, SlashPos + 1, MaxInt);
  Result := (Kind <> '') and (Ref <> '');
end;

function FindItemById(ID: Integer): TItem;
var
  Mgr: TObjectManager;
begin
  Result := nil;
  if ID <= 0 then Exit;
  Mgr := Model.Manager;
  Result := Mgr.Find<TItem>(ID);
  if Assigned(Result) and Result.IsDeleted then
    Result := nil;
end;

function FindSpecimenByTitle(const Title: string): TItem;
var
  Mgr: TObjectManager;
  Dic: TItemDictionary;
  Items: TItems;
  Wanted: string;
  Item: TItem;
begin
  Result := nil;
  if Title = '' then Exit;
  Wanted := LowerCase(Title);
  Mgr := Model.Manager;
  Dic := TItemDictionary.Create;
  try
    // Filter Type_ + IsDeleted in SQL; finalize the case-insensitive Title
    // comparison in Delphi to avoid leaning on collation behaviour that
    // differs between the SQLite and MySQL backends.
    Items := Mgr.Find<TItem>
      .Where(
        (Dic.Type_ = TItemType.Specimen) and
        (Dic.IsDeleted = False))
      .OrderBy(Dic.Id)
      .List;
    try
      for Item in Items do
        if LowerCase(Item.Title) = Wanted then
        begin
          Result := Item;
          Break;
        end;
    finally
      Items.Free;
    end;
  finally
    Dic.Free;
  end;
end;


constructor TElnLinkHandler.Create(const ANavigate: TItemNavigationProc);
begin
  inherited Create;
  FNavigate := ANavigate;
end;

function TElnLinkHandler.HandleLink(const Url: string): Boolean;
var
  Kind, Ref: string;
  Item: TItem;
  ID: Integer;
begin
  Result := False;
  if not Assigned(FNavigate) then Exit;
  if not ParseElnUrl(Url, Kind, Ref) then Exit;

  Item := nil;
  if Kind = 'item' then
  begin
    if TryStrToInt(Ref, ID) then
      Item := FindItemById(ID);
  end
  else if Kind = 'specimen' then
    Item := FindSpecimenByTitle(UrlDecode(Ref));

  if not Assigned(Item) then Exit;

  FNavigate(Item.ProjectID, Item.FolderID, Item.Id);
  Result := True;
end;

procedure InstallElnLinkHandler(const ANavigate: TItemNavigationProc);
begin
  ElnLinkHandler := TElnLinkHandler.Create(ANavigate);
end;

procedure UninstallElnLinkHandler;
begin
  ElnLinkHandler := nil;
end;

procedure DispatchPendingElnUrl;
var
  LocalUrl: string;
begin
  if PendingElnUrl = '' then Exit;
  if not Assigned(ElnLinkHandler) then Exit;

  // Copy then clear before invoking, so any re-entrant code (the
  // handler may show dialogs, etc.) sees the slot as empty.
  LocalUrl := PendingElnUrl;
  PendingElnUrl := '';
  ElnLinkHandler.HandleLink(LocalUrl);
end;

end.
