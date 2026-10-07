unit unit_Equipment;

interface

uses
  SysUtils, 
  Generics.Collections, 
  Aurelius.Mapping.Attributes, 
  Aurelius.Types.Blob, 
  Aurelius.Types.DynamicProperties, 
  Aurelius.Types.Nullable, 
  Aurelius.Types.Proxy, 
  unit_EquipmentType;

type
  TEquipment = class;
  TEquipments = TList<TEquipment>;

  [Entity]
  [Table('Equipments')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TEquipment = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;
    
    [Column('Model', [TColumnProp.Required])]
    [Description('')]
    FModel: string;

    [Column('Manufacturer', [TColumnProp.Required])]
    [Description('')]
    FManufacturer: string;

    [Column('Location', [TColumnProp.Required])]
    [Description('')]
    FLocation: string;

    [Column('BookingURL', [])]
    [Description('')]
    FBookingUrl: string;

    [Column('InfoURL', [])]
    [Description('')]
    FInfoUrl: string;

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

    [Association([TAssociationProp.Required], [])]
    [JoinColumn('EquipmentTypeId', [TColumnProp.Required])]
    [Description('')]
    FEquipmenType: Proxy<TEquipmentType>;

    function GetEquipmenttypeid: TEquipmentType;
    procedure SetEquipmenttypeid(const Value: TEquipmentType);
  public
    property Id: Integer read FId write FId;
    property Model: string read FModel write FModel;
    property Manufacturer: string read FManufacturer write FManufacturer;
    property Location: string read FLocation write FLocation;
    property BookingUrl: string read FBookingUrl write FBookingUrl;
    property InfoUrl: string read FInfoUrl write FInfoUrl;
    property Description: string read FDescription write FDescription;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property EquipmentType: TEquipmentType read GetEquipmenttypeid write SetEquipmenttypeid;
  end;
  
implementation

{ TEquipment }

function TEquipment.GetEquipmenttypeid: TEquipmentType;
begin
  result := FEquipmenType.Value;
end;

procedure TEquipment.SetEquipmenttypeid(const Value: TEquipmentType);
begin
  FEquipmenType.Value := Value;
end;

initialization
  RegisterEntity(TEquipment);

end.
