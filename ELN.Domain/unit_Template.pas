unit unit_Template;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  unit_Equipment,
  unit_EquipmentType;

type
  TTemplate = class;
  TTemplateEquipmentType = class;
  TTemplateEquipment = class;

  TTemplates             = TList<TTemplate>;
  TTemplateEquipmentTypes = TList<TTemplateEquipmentType>;
  TTemplateEquipments     = TList<TTemplateEquipment>;

  [Entity]
  [Table('Templates')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TTemplate = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('Name', [TColumnProp.Required], 200)]
    FName: string;

    [Column('Description', [], 500)]
    FDescription: string;

    [Column('Category', [], 100)]
    FCategory: string;

    [Column('FormSchema', [TColumnProp.Lazy], 65536)]
    FFormSchema: string;

    [Column('IsActive', [TColumnProp.Required])]
    FIsActive: Boolean;

    [Column('Version', [TColumnProp.Required])]
    FVersion: Integer;

    [Column('ParentId', [])]
    FParentId: Nullable<Integer>;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    FModifiedDate: Nullable<TDateTime>;

    [ManyValuedAssociation([], CascadeTypeAllRemoveOrphan, 'FTemplate')]
    FEquipmentTypes: Proxy<TTemplateEquipmentTypes>;

    [ManyValuedAssociation([], CascadeTypeAllRemoveOrphan, 'FTemplate')]
    FEquipments: Proxy<TTemplateEquipments>;

    function GetEquipmentTypes: TTemplateEquipmentTypes;
    function GetEquipments: TTemplateEquipments;
  public
    constructor Create;

    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Category: string read FCategory write FCategory;
    property FormSchema: string read FFormSchema write FFormSchema;
    property IsActive: Boolean read FIsActive write FIsActive;
    property Version: Integer read FVersion write FVersion;
    property ParentId: Nullable<Integer> read FParentId write FParentId;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property EquipmentTypes: TTemplateEquipmentTypes read GetEquipmentTypes;
    property Equipments: TTemplateEquipments read GetEquipments;
  end;

  [Entity]
  [Table('TemplateEquipmentTypes')]
  [Description('Join: a template is allowed on this class of equipment.')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [UniqueKey('TemplateId,EquipmentTypeId')]
  TTemplateEquipmentType = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    // No cascade: this is a reference to a row owned elsewhere, not a child of
    // this entity. CascadeTypeAll carries TCascadeType.Evict, so cascading here
    // detaches the referenced row whenever this one is evicted, leaving a stale
    // instance alive while the next Find maps a fresh one -- two live instances
    // of one Id, and the next Save/Update cascade raises EObjectAlreadyPersistent.
    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('TemplateId', [TColumnProp.Required], 'Id')]
    FTemplate: Proxy<TTemplate>;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('EquipmentTypeId', [TColumnProp.Required], 'Id')]
    FEquipmentType: Proxy<TEquipmentType>;

    function GetTemplate: TTemplate;
    procedure SetTemplate(const Value: TTemplate);
    function GetEquipmentType: TEquipmentType;
    procedure SetEquipmentType(const Value: TEquipmentType);
  public
    property Id: Integer read FId write FId;
    property Template: TTemplate read GetTemplate write SetTemplate;
    property EquipmentType: TEquipmentType read GetEquipmentType write SetEquipmentType;
  end;

  [Entity]
  [Table('TemplateEquipments')]
  [Description('Join: a template is narrowed to this specific device.')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [UniqueKey('TemplateId,EquipmentId')]
  TTemplateEquipment = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('TemplateId', [TColumnProp.Required], 'Id')]
    FTemplate: Proxy<TTemplate>;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('EquipmentId', [TColumnProp.Required], 'Id')]
    FEquipment: Proxy<TEquipment>;

    function GetTemplate: TTemplate;
    procedure SetTemplate(const Value: TTemplate);
    function GetEquipment: TEquipment;
    procedure SetEquipment(const Value: TEquipment);
  public
    property Id: Integer read FId write FId;
    property Template: TTemplate read GetTemplate write SetTemplate;
    property Equipment: TEquipment read GetEquipment write SetEquipment;
  end;

implementation

uses
  unit_TimeHelper;

{ TTemplate }

constructor TTemplate.Create;
begin
  inherited;
  FIsActive := True;
  FVersion := 1;
  FCreatedDate := UTCNow;
end;

function TTemplate.GetEquipmentTypes: TTemplateEquipmentTypes;
begin
  Result := FEquipmentTypes.Value;
end;

function TTemplate.GetEquipments: TTemplateEquipments;
begin
  Result := FEquipments.Value;
end;

{ TTemplateEquipmentType }

function TTemplateEquipmentType.GetTemplate: TTemplate;
begin
  Result := FTemplate.Value;
end;

procedure TTemplateEquipmentType.SetTemplate(const Value: TTemplate);
begin
  FTemplate.Value := Value;
end;

function TTemplateEquipmentType.GetEquipmentType: TEquipmentType;
begin
  Result := FEquipmentType.Value;
end;

procedure TTemplateEquipmentType.SetEquipmentType(const Value: TEquipmentType);
begin
  FEquipmentType.Value := Value;
end;

{ TTemplateEquipment }

function TTemplateEquipment.GetTemplate: TTemplate;
begin
  Result := FTemplate.Value;
end;

procedure TTemplateEquipment.SetTemplate(const Value: TTemplate);
begin
  FTemplate.Value := Value;
end;

function TTemplateEquipment.GetEquipment: TEquipment;
begin
  Result := FEquipment.Value;
end;

procedure TTemplateEquipment.SetEquipment(const Value: TEquipment);
begin
  FEquipment.Value := Value;
end;

initialization
  RegisterEntity(TTemplate);
  RegisterEntity(TTemplateEquipmentType);
  RegisterEntity(TTemplateEquipment);

end.
