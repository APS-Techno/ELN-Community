unit unit_Favorite;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes;

type
  TFavorite = class;
  TFavorites = TList<TFavorite>;

  [Enumeration(TEnumMappingType.emInteger)]
  TFavoriteType = (ftProject, ftFolder, ftItem);

  [Entity]
  [Table('Favorites')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TFavorite = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('ProjectId', [TColumnProp.Required])]
    FProjectId: Integer;

    [Column('FolderId', [])]
    FFolderId: Integer;

    [Column('ItemId', [])]
    FItemId: Integer;

    [Column('FavoriteType', [TColumnProp.Required])]
    FFavoriteType: TFavoriteType;

    [Column('Title', [TColumnProp.Required], 255)]
    FTitle: string;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;
  public
    property Id: Integer read FId write FId;
    property UserId: Integer read FUserId write FUserId;
    property ProjectId: Integer read FProjectId write FProjectId;
    property FolderId: Integer read FFolderId write FFolderId;
    property ItemId: Integer read FItemId write FItemId;
    property FavoriteType: TFavoriteType read FFavoriteType write FFavoriteType;
    property Title: string read FTitle write FTitle;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
  end;

implementation

initialization
  RegisterEntity(TFavorite);

end.
