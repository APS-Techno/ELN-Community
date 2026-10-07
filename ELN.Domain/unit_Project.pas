unit unit_Project;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Blob,
  Aurelius.Types.DynamicProperties,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  unit_User;

var
  /// When True, entity destructors skip DestroyValue on proxy collections.
  /// Set before TObjectManager.Free to prevent cascade double-free.
  ManagerShuttingDown: Boolean;

type
  TProject = class;
  TFolder = class;
  TFoldersList = TList<TFolder>;

  [Entity, Automapping]
  [Table('Projects')]
  [Description('Research project grouping related experiments and data')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TProject = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('Primary key')]
    FId: Integer;

    // Explicit 255 = Aurelius' existing default, so no DDL changes. Spelled out
    // because STRICT-mode MySQL rejects rather than truncates; callers check
    // against MAX_TITLE_LEN / MAX_DESC_LEN in unit_ToolHelpers.pas.
    [Column('Title', [TColumnProp.Required, TColumnProp.Lazy], 255)]
    [Description('Project name displayed in the navigation tree')]
    FTitle: string;

    [Column('FileFolder', [TColumnProp.Lazy])]
    [Description('Directory name used for file storage under the user projects root')]
    FFileFolder: string;

    [Column('Description', [TColumnProp.Lazy], 255)]
    [Description('Optional project summary or notes')]

    FDescription: string;

    [Column('StartDate', [])]
    [Description('Project start date')]
    FStartDate: Nullable<TDateTime>;

    [Column('EndDate', [])]
    [Description('Project completion or end date')]
    FEndDate: Nullable<TDateTime>;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('Timestamp when the project was created')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('Timestamp of the last modification')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('User ID who created the project')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('User ID who last modified the project')]
    FModifiedBy: Nullable<Integer>;

    [Column('Expanded', [TColumnProp.Required])]
    [Description('Whether the project node is expanded in the navigation tree')]
    FExpanded: boolean;

    [Column('IsArchived', [TColumnProp.Required])]
    [Description('Whether the project is archived and hidden from default view')]
    FIsArchived: boolean;

    [Column('SortOrder', [TColumnProp.Required])]
    [Description('Display order in the navigation tree (0 = default, ordered by ID)')]
    FSortOrder: Integer;

    [Column('GroupID', [])]
    [Description('Owning user''s project group; NULL = ungrouped (tree root)')]
    FGroupID: Nullable<Integer>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;

    [ManyValuedAssociation([], CascadeTypeAll - [TCascadeType.Remove])]
    [ForeignJoinColumn('ProjectID', [TColumnProp.Required])]
    FFolders: Proxy<TFoldersList>;

    // No cascade: this is a reference to a row owned elsewhere, not a child of
    // this entity. CascadeTypeAll carries TCascadeType.Evict, so cascading here
    // detaches the referenced row whenever this one is evicted, leaving a stale
    // instance alive while the next Find maps a fresh one -- two live instances
    // of one Id, and the next Save/Update cascade raises EObjectAlreadyPersistent.
    [Association([TAssociationProp.Required], [])]
    [JoinColumn('OwnerId', [])]
    [Description('The user who owns this project')]
    FOwner: Proxy<TUser>;

    function GetOwner: TUser;
    procedure SetOwner(const Value: TUser);
    function GetFolders: TFoldersList;
    procedure SetFolders(const Value: TFoldersList);
  public

    constructor Create; virtual;
    destructor Destroy; override;

    property Id: Integer read FId write FId;
    property Owner: TUser read GetOwner write SetOwner;
    property Title: string read FTitle write FTitle;
    property FileFolder: string read FFileFolder write FFileFolder;
    property Description: string read FDescription write FDescription;
    property StartDate: Nullable<TDateTime> read FStartDate write FStartDate;
    property EndDate: Nullable<TDateTime> read FEndDate write FEndDate;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property Expanded: boolean read FExpanded write FExpanded;
    property IsArchived: boolean read FIsArchived write FIsArchived;
    property SortOrder: Integer read FSortOrder write FSortOrder;
    property GroupID: Nullable<Integer> read FGroupID write FGroupID;
    property Folders: TFoldersList read GetFolders write SetFolders;
    property Version: Integer read FVersion write FVersion;
    function GetFolder(const ID: integer): TFolder;
  end;

  [Entity, Automapping]
  [Table('Folders')]
  [Description('Sub-folder for organizing items within a project')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TFolder = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('Primary key')]
    FId: Integer;

    [Column('ParentFolderID', [TColumnProp.Required])]
    [Description('Parent folder ID; 0 for top-level folders directly under the project')]
    FParentFolderID: Integer;

    [Column('Title', [TColumnProp.Required, TColumnProp.Lazy], 255)]
    [Description('Folder name displayed in the navigation tree')]
    FTitle: string;

    [Column('Description', [TColumnProp.Lazy], 255)]
    [Description('Optional folder notes')]

    FDescription: string;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('Timestamp when the folder was created')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('Timestamp of the last modification')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('User ID who created the folder')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('User ID who last modified the folder')]
    FModifiedBy: Nullable<Integer>;

    [Column('Expanded', [TColumnProp.Required])]
    [Description('Whether the folder node is expanded in the navigation tree')]
    FExpanded: boolean;

    [Column('SortOrder', [TColumnProp.Required])]
    [Description('Display order within parent (0 = default, ordered by ID)')]
    FSortOrder: Integer;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;

  public
    function Path(const ProjectName: string):string;

    property Id: Integer read FId write FId;
    property Title: string read FTitle write FTitle;
    property Description: string read FDescription write FDescription;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property Expanded: boolean read FExpanded write FExpanded;
    property SortOrder: Integer read FSortOrder write FSortOrder;
    property ParentFolderID: integer read FParentFolderID write FParentFolderID;
    property Version: Integer read FVersion write FVersion;
  end;

implementation

{ TProject }

constructor TProject.Create;
begin
  FFolders.SetInitialValue(TFoldersList.Create);
  FIsArchived := False;
  FSortOrder := 0;
end;

destructor TProject.Destroy;
begin
  if not ManagerShuttingDown then
    FFolders.DestroyValue;
  inherited;
end;

function TProject.GetFolder(const ID: integer): TFolder;
var
  Folders: TFoldersList;
  F: TFolder;
begin
  Result := nil;
  Folders := FFolders.Value;
  for F in Folders do
    if F.Id = ID then
      Exit(F);
end;

function TProject.GetFolders: TFoldersList;
begin
  Result := FFolders.Value;
end;

function TProject.GetOwner: TUser;
begin
  Result := FOwner.Value;
end;

procedure TProject.SetFolders(const Value: TFoldersList);
begin
  FFolders.Value := Value;
end;

procedure TProject.SetOwner(const Value: TUser);
begin
  FOwner.Value := Value;
end;

{ TFolder }

function TFolder.Path(const ProjectName: string): string;
var
  S: string;
begin
  S := FTitle;
  Result := Format('[%s] \ %s',[ProjectName, S]);
end;

initialization
  RegisterEntity(TProject);
  RegisterEntity(TFolder);
end.
