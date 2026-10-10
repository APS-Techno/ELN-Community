unit unit_Item;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Blob,
  Aurelius.Types.DynamicProperties,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  unit_Project,
  unit_Equipment,
  unit_LabEntry,
  unit_Protocol,
  unit_FileType,
  unit_Actiontype,
  unit_ValueType,
  unit_ItemTypes;

type

  TItem = class;
  TItems = TList<TItem>;

  TFile = class;
  TFiles = TList<TFile>;

  TValue = class;
  TValues = TList<TValue>;


  [Entity]
  [Table('Items')]
  [Description('Lab entry item representing a Proc, Specimen, Action, or Folder in the hierarchy')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TItem = class
  private
    [Column('ID', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('Primary key')]
    FId: Integer;

    [Column('ProjectID', [TColumnProp.Required])]
    [Description('Owning project ID')]
    FProjectID: Integer;

    [Column('FolderID', [TColumnProp.Required])]
    [Description('Owning folder ID')]
    FFolderID: Integer;

    [Column('Level', [TColumnProp.Required])]
    [Description('Hierarchy level: Proc (top-level procedure), Item (sample/specimen), Action (nested step), Folder (grouping)')]
    FLevel: TItemLevel;

    [Column('Type', [TColumnProp.Required])]
    [Description('Activity or material type: Synthesis, Treatment, Measurement, Specimen, Model, etc.')]
    FType_: TItemType;

    // STRICT-mode MySQL/MariaDB rejects overlong values rather than truncating
    // them; callers must check the stored width before saving.
    [Column('Title', [TColumnProp.Required, TColumnProp.Lazy], 255)]
    [Description('Item name displayed in the item tree')]
    FTitle:  string;

    [Column('Description', [TColumnProp.Lazy], 255)]
    [Description('Optional notes or description')]
    FDescription:  string;

    [Column('Properties', [TColumnProp.Lazy], 65536)]
    [Description('Free-text field for arbitrary additional metadata (e.g. substrate material, dimensions, roughness)')]
    FProperties: string;

    [Column('ParentID', [TColumnProp.Required])]
    [Description('Parent item ID; 0 for top-level items within a folder')]
    FParentID: integer;

    [ManyValuedAssociation([], CascadeTypeAllButRemove)]
    [ForeignJoinColumn('ItemID', [])]
    FEntries :  Proxy<TLabEntries>;

    [ManyValuedAssociation([], CascadeTypeAllRemoveOrphan, 'FItem')]
    FFilesList: Proxy<TFiles>;

    // The back-reference enables orphan removal when an item is hard-deleted.
    [ManyValuedAssociation([], CascadeTypeAllRemoveOrphan, 'FItem')]
    FValues : Proxy<TValues>;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('ActionType', [], 'Id')]
    [Description('Associated action type defining the procedure category and required equipment')]
    FActionType: Proxy<TActionType>;

    [Association([TAssociationProp.Lazy], [])]
    [JoinColumn('EquipmentId', [], 'Id')]
    [Description('Equipment used for this specific item')]
    FEquipment: Proxy<TEquipment>;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('Timestamp when the item was created')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('Timestamp of the last modification')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('User ID who created the item')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('User ID who last modified the item')]
    FModifiedBy: Nullable<Integer>;

    [Column('Expanded', [TColumnProp.Required])]
    [Description('Whether the item node is expanded in the item tree')]
    FExpanded: boolean;

    [Column('SortOrder', [])]
    [Description('Display order within the parent group; multiples of 10 to allow drag-and-drop insertions')]
    FSortOrder: Integer;

    [Column('IsDeleted', [TColumnProp.Required])]
    FIsDeleted: Boolean;

    [Column('DeletedDate', [])]
    FDeletedDate: Nullable<TDateTime>;

    [Column('DeletedBy', [])]
    FDeletedBy: Nullable<Integer>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;

    function GetFiles: TFiles;
    function GetEntries: TLabEntries;
    procedure SetFiles(const Value: TFiles);
    procedure SetEntries(const Value: TLabEntries);
    function GetFolderName: string;
    function GetType: TActionType;
    function GetValuesList: TValues;
    procedure SetType(const Value: TActionType);
    function GetEquipment: TEquipment;
    procedure SetEquipment(const Value: TEquipment);
  public
    constructor Create; virtual;
    destructor Destroy; override;

    property Id: Integer read FId write FId;
    property Type_: TItemType read FType_ write FType_;
    property Level: TItemLevel read FLevel write FLevel;
    property Title: string read FTitle write FTitle;
    property Description: string read FDescription write FDescription;
    property Properties: string read FProperties write FProperties;
    property Parent: integer read FParentID write FParentID;

    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property Expanded: boolean read FExpanded write FExpanded;
    property SortOrder: integer read FSortOrder write FSortOrder;
    property ProjectID: integer read FProjectID write FProjectID;
    property FolderID: integer read FFolderID write FFolderID;
    property Files: TFiles read GetFiles write SetFiles;
    property Entries: TLabEntries read GetEntries write SetEntries;
    property ActionType: TActionType read GetType write SetType;
    property Equipment: TEquipment read GetEquipment write SetEquipment;
    property Values: TValues read GetValuesList;
    // Storage folder for an item's attachments: '[0001]Title'. Public so the
    // model can name the folder for a title the item no longer carries.
    class function MakeFolderName(AId: Integer; const ATitle: string): string; static;
    property FolderName: string read GetFolderName;
    property IsDeleted: Boolean read FIsDeleted write FIsDeleted;
    property DeletedDate: Nullable<TDateTime> read FDeletedDate write FDeletedDate;
    property DeletedBy: Nullable<Integer> read FDeletedBy write FDeletedBy;
    property Version: Integer read FVersion write FVersion;
  end;

  [Entity]
  [Table('Files')]
  [Description('File attachment associated with a lab item')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TFile = class
  private
    // Attachment identities are never reused; 64-bit avoids exhaustion.
    // ItemID remains 32-bit to match Items.Id.
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('Primary key')]
    FId: Int64;

    [Column('Description', [TColumnProp.Lazy])]
    [Description('Optional notes about the file')]
    FDescription: string;

    [Column('Title', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('File name without extension (extension comes from FileType)')]
    FTitle: string;

    [Column('Hash', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('MD5 hash for file integrity verification')]
    FHash: string;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('Timestamp when the file was uploaded')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('Timestamp of the last modification')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('User ID who uploaded the file')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('User ID who last modified the file')]
    FModifiedBy: Nullable<Integer>;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('TypeID', [TColumnProp.Required], 'Id')]
    [Description('File type defining the extension and icon from the FileTypes reference table')]
    FFileType: Proxy<TFileType>;

    [Association([TAssociationProp.Lazy], [])]
    [JoinColumn('ItemID', [TColumnProp.Required])]
    FItem: Proxy<TItem>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;

    function GetFileType: TFileType;
    procedure SetFileType(const Value: TFileType);
    function GetItem: Titem;
    procedure SetItem(const Value: Titem);
  public
    property Id: Int64 read FId write FId;
    property Description: string read FDescription write FDescription;
    property Title: string read FTitle write FTitle;
    property Hash: string read FHash write FHash;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property FileType: TFileType read GetFileType write SetFileType;
    property Item: TItem read GetItem write SetItem;
    property Version: Integer read FVersion write FVersion;

    function FullName: string;
  end;

  [Entity]
  [Table('DataValues')]
  [Description('Measured or recorded numerical value associated with a lab item')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TValue = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('Primary key')]
    FId: Integer;

    // Back-reference to the owning item. Required for the FValues
    // CascadeTypeAllRemoveOrphan mapping on TItem to delete this row when
    // the item is hard-deleted.
    [Association([TAssociationProp.Lazy], [])]
    [JoinColumn('ItemID', [TColumnProp.Required])]
    FItem: Proxy<TItem>;

    // TValueType is shared, not owned here. Cascading Evict would leave a
    // stale dictionary instance and cause EObjectAlreadyPersistent on save.
    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('TypeID', [TColumnProp.Required], 'Id')]
    [Description('Value type defining the unit and measurement context')]
    FValueType: Proxy<TValueType>;

    [Column('RecType', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('Record type: measured, nominal, specification, etc.')]
    FRecType: TRecType;

    [Column('Value', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('Numerical value')]
    FValue: double;

    [Column('Tolerance', [TColumnProp.Lazy])]
    [Description('Tolerance for nominal or specification values')]
    FTol: double;

    [Column('Description', [TColumnProp.Lazy])]
    [Description('Optional notes')]
    FDescription: string;

    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('Timestamp when the value was recorded')]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    [Description('Timestamp of the last modification')]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    [Description('User ID who recorded the value')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('User ID who last modified the value')]
    FModifiedBy: Nullable<Integer>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;

    function GetValueType: TValueType;
    procedure SetValueType(const Value: TValueType);
    function GetItem: TItem;
    procedure SetItem(const Value: TItem);
  public
    property Id: Integer read FId write FId;
    property ValueType: TValueType read GetValueType write SetValueType;
    property RecType: TRecType read FRecType write FRecType;
    property Value: double read FValue write FValue;
    property Tol: double read FTol write FTol;
    property Description: string read FDescription write FDescription;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property Item: TItem read GetItem write SetItem;
    property Version: Integer read FVersion write FVersion;
  end;

implementation


constructor TItem.Create;
begin
  FFilesList.SetInitialValue(TFiles.Create);
  FEntries.SetInitialValue(TLabEntries.Create);
  FValues.SetInitialValue(TValues.Create);
  FIsDeleted := False;
end;

destructor TItem.Destroy;
begin
  if not ManagerShuttingDown then
  begin
    FFilesList.DestroyValue;
    FEntries.DestroyValue;
    FValues.DestroyValue;
  end;
  inherited;
end;

function TItem.GetFiles: TFiles;
begin
  Result := FFilesList.Value;
end;

class function TItem.MakeFolderName(AId: Integer; const ATitle: string): string;
begin
  Result := Format('[%.*d]%s', [4, AId, ATitle]);
end;

function TItem.GetFolderName: string;
begin
  Result := MakeFolderName(FID, FTitle);
end;

function TItem.GetEntries: TLabEntries;
begin
  Result := FEntries.Value;
end;

function TItem.GetType: TActionType;
begin
  Result := FActionType.Value;
end;

function TItem.GetValuesList: TValues;
begin
  Result := FValues.Value;
end;

procedure TItem.SetFiles(const Value: TFiles);
begin
  FFilesList.Value := Value;
end;

procedure TItem.SetEntries(const Value: TLabEntries);
begin
  FEntries.Value := Value;
end;


procedure TItem.SetType(const Value: TActionType);
begin
  FActionType.Value := Value;
end;

function TItem.GetEquipment: TEquipment;
begin
  Result := FEquipment.Value;
end;

procedure TItem.SetEquipment(const Value: TEquipment);
begin
  FEquipment.Value := Value;
end;


function TFile.FullName: string;
begin
  Result := Format('[%.*d]%s%s',[4, FId, Title, FFileType.Value.Ext]);
end;

function TFile.GetFileType: TFileType;
begin
  result := FFileType.Value;
end;

function TFile.GetItem: Titem;
begin
  Result := FItem.Value;
end;

procedure TFile.SetFileType(const Value: TFileType);
begin
  FFileType.Value := Value;
end;

procedure TFile.SetItem(const Value: Titem);
begin
  FItem.Value := Value;
end;


function TValue.GetValueType: TValueType;
begin
  Result := FValueType.Value;
end;

procedure TValue.SetValueType(const Value: TValueType);
begin
  FValueType.Value := Value;
end;

function TValue.GetItem: TItem;
begin
  Result := FItem.Value;
end;

procedure TValue.SetItem(const Value: TItem);
begin
  FItem.Value := Value;
end;

initialization
  RegisterEntity(TItem);
  RegisterEntity(TFile);
  RegisterEntity(TValue);
end.
