unit unit_ProjectGroup;

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes;

type
  TProjectGroup = class;
  TProjectGroupList = TList<TProjectGroup>;

  [Entity, Automapping]
  [Table('ProjectGroups')]
  [Description('Personal flat grouping of projects in the navigation tree')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TProjectGroup = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('OwnerId', [TColumnProp.Required])]
    [Description('User who owns this group; groups are personal, plain FK by convention')]
    FOwnerId: Integer;

    [Column('Title', [TColumnProp.Required], 255)]
    FTitle: string;

    [Column('SortOrder', [])]
    FSortOrder: Integer;

    [Column('Expanded', [])]
    FExpanded: Boolean;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;
  public
    property Id: Integer read FId;
    property OwnerId: Integer read FOwnerId write FOwnerId;
    property Title: string read FTitle write FTitle;
    property SortOrder: Integer read FSortOrder write FSortOrder;
    property Expanded: Boolean read FExpanded write FExpanded;
    property Version: Integer read FVersion write FVersion;
  end;

implementation

initialization
  RegisterEntity(TProjectGroup);

end.
