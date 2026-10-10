unit unit_FavoritesModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  unit_Favorite,
  unit_ELNDB_Dictionary;

type
  TFavoritesModel = class
  private
    FManager: TObjectManager;
    FDic: TFavoriteDictionary;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;

    procedure AddFavorite(UserId: Integer; FavType: TFavoriteType;
      ProjectId, FolderId, ItemId: Integer; const Title: string);
    procedure RemoveFavorite(Id: Integer);
    procedure RemoveFavoriteByTarget(UserId: Integer; FavType: TFavoriteType;
      ProjectId, FolderId, ItemId: Integer);
    function GetFavorites(UserId: Integer): TList<TFavorite>;
    function IsFavorite(UserId: Integer; FavType: TFavoriteType;
      ProjectId, FolderId, ItemId: Integer): Boolean;
    procedure ToggleFavorite(UserId: Integer; FavType: TFavoriteType;
      ProjectId, FolderId, ItemId: Integer; const Title: string);
  end;

implementation

uses
  Aurelius.Criteria.Base,
  unit_TimeHelper;


constructor TFavoritesModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDic := TFavoriteDictionary.Create;
end;

destructor TFavoritesModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

procedure TFavoritesModel.AddFavorite(UserId: Integer; FavType: TFavoriteType;
  ProjectId, FolderId, ItemId: Integer; const Title: string);
var
  Fav: TFavorite;
begin
  if IsFavorite(UserId, FavType, ProjectId, FolderId, ItemId) then
    Exit;

  Fav := TFavorite.Create;
  Fav.UserId := UserId;
  Fav.ProjectId := ProjectId;
  Fav.FolderId := FolderId;
  Fav.ItemId := ItemId;
  Fav.FavoriteType := FavType;
  Fav.Title := Title;
  Fav.CreatedDate := UTCNow;

  FManager.Save(Fav);
  FManager.Flush;
end;

procedure TFavoritesModel.RemoveFavorite(Id: Integer);
var
  Fav: TFavorite;
begin
  Fav := FManager.Find<TFavorite>(Id);
  if Assigned(Fav) then
  begin
    FManager.Remove(Fav);
    FManager.Flush;
  end;
end;

procedure TFavoritesModel.RemoveFavoriteByTarget(UserId: Integer;
  FavType: TFavoriteType; ProjectId, FolderId, ItemId: Integer);
var
  Favs: TList<TFavorite>;
  Fav: TFavorite;
begin
  Favs := FManager.Find<TFavorite>
    .Where(
      (FDic.UserId = UserId) and
      (FDic.FavoriteType = Ord(FavType)) and
      (FDic.ProjectId = ProjectId) and
      (FDic.FolderId = FolderId) and
      (FDic.ItemId = ItemId))
    .List;
  try
    for Fav in Favs do
    begin
      FManager.Remove(Fav);
      FManager.Flush;
    end;
  finally
    Favs.Free;
  end;
end;

function TFavoritesModel.GetFavorites(UserId: Integer): TList<TFavorite>;
begin
  Result := FManager.Find<TFavorite>
    .Where(FDic.UserId = UserId)
    .OrderBy('CreatedDate')
    .List;
end;

function TFavoritesModel.IsFavorite(UserId: Integer; FavType: TFavoriteType;
  ProjectId, FolderId, ItemId: Integer): Boolean;
var
  Favs: TList<TFavorite>;
begin
  Favs := FManager.Find<TFavorite>
    .Where(
      (FDic.UserId = UserId) and
      (FDic.FavoriteType = Ord(FavType)) and
      (FDic.ProjectId = ProjectId) and
      (FDic.FolderId = FolderId) and
      (FDic.ItemId = ItemId))
    .Take(1)
    .List;
  try
    Result := Favs.Count > 0;
  finally
    Favs.Free;
  end;
end;

procedure TFavoritesModel.ToggleFavorite(UserId: Integer; FavType: TFavoriteType;
  ProjectId, FolderId, ItemId: Integer; const Title: string);
begin
  if IsFavorite(UserId, FavType, ProjectId, FolderId, ItemId) then
    RemoveFavoriteByTarget(UserId, FavType, ProjectId, FolderId, ItemId)
  else
    AddFavorite(UserId, FavType, ProjectId, FolderId, ItemId, Title);
end;

end.
