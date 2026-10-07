unit unit_ActionType;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Blob,
  Aurelius.Types.DynamicProperties,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  unit_Equipment,
  unit_EquipmentType,
  unit_ItemTypes;

type
  TActionType = class;
  TActionTypes = TList<TActionType>;


  [Enumeration(TEnumMappingType.emInteger)]
  TActionKind = (Synthesys, Testing, Measurement, Analysis, Simulation, Other);

  [Entity]
  [Table('ActionTypes')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TActionType = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;
    
    [Column('Kind', [TColumnProp.Required])]
    [Description('')]
    [Enumeration]
    FKind: TActionKind;

    [Column('ItemType', [TColumnProp.Required])]
    [Enumeration]
    FItemType: TItemType;
    
    [Column('Title', [TColumnProp.Required])]
    [Description('')]
    FTitle: string;
    
    [Column('Description', [])]
    [Description('')]
    FDescription: string;
    
    [Column('CreatedDate', [TColumnProp.Required])]
    [Description('')]
    FCreatedDate: TDateTime;
    
    [Column('ModifiedDate', [])]
    [Description('')]
    FModifiedDate: Nullable<TDateTime>;
    
    [Column('CreatedBy', [])]
    [Description('')]
    FCreatedBy: Nullable<Integer>;
    
    [Column('ModifiedBy', [])]
    [Description('')]
    FModifiedBy: Nullable<Integer>;

    [Association([], [])]
    [JoinColumn('EquipmentTypeId', [], 'Id')]
    [Description('')]
    FEquipmentType: Proxy<TEquipmentType>;

    [Association([], [])]
    [JoinColumn('EquipmentId', [], 'Id')]
    [Description('')]
    FEquipment: Proxy<TEquipment>;

    function GetEquipmentType: TEquipmentType;
    procedure SetEquipmentType(const Value: TEquipmentType);
    function GetEquipment: TEquipment;
    procedure SetEquipment(const Value: TEquipment);
  public
    property Id: Integer read FId write FId;
    property Kind: TActionKind read FKind write FKind;
    property ItemType: TItemType read FItemType write FItemType;
    property Title: string read FTitle write FTitle;
    property Description: string read FDescription write FDescription;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property EquipmentType: TEquipmentType read GetEquipmentType write SetEquipmentType;
    property Equipment: TEquipment read GetEquipment write SetEquipment;
  end;
  
implementation

{ TActionType }

function TActionType.GetEquipmentType: TEquipmentType;
begin
  Result := FEquipmentType.Value;
end;

procedure TActionType.SetEquipmentType(const Value: TEquipmentType);
begin
  FEquipmentType.Value := Value;
end;

function TActionType.GetEquipment: TEquipment;
begin
  Result := FEquipment.Value;
end;

procedure TActionType.SetEquipment(const Value: TEquipment);
begin
  FEquipment.Value := Value;
end;

initialization
  RegisterEntity(TActionType);

end.
