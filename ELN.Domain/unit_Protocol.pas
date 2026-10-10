unit unit_Protocol;

interface

uses
  System.SysUtils,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable,
  unit_LabEntry;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TProtocolType = (
    ptExperiment,
    ptMeasurement,
    ptAnalysis,
    ptSynthesis,
    ptTesting,
    ptOther,
    ptNote
  );

  [Enumeration(TEnumMappingType.emInteger)]
  TValidationStatus = (
    vsDraft,
    vsInReview,
    vsApproved,
    vsRejected
  );

  [Entity]
  [DiscriminatorValue('Protocol')]
  TProtocol = class(TLabEntry)
  private
    [Column('TemplateId', [])]
    FTemplateId: Nullable<Integer>;

    [Column('FormData', [TColumnProp.Lazy], 65536)]
    FFormData: string;  // Serialized HTML form values; JSON or XML.

    [Column('ProtocolType', [])]
    FProtocolType: Nullable<TProtocolType>;

    [Column('ValidationStatus', [])]
    FValidationStatus: TValidationStatus;

    [Column('EquipModel', [])]
    FEquipModel: string;

    [Column('EquipManufacturer', [])]
    FEquipManufacturer: string;

    [Column('EquipLocation', [])]
    FEquipLocation: string;
  public
    constructor Create;

    property TemplateId: Nullable<Integer> read FTemplateId write FTemplateId;
    property FormData: string read FFormData write FFormData;
    property ProtocolType: Nullable<TProtocolType> read FProtocolType write FProtocolType;
    property ValidationStatus: TValidationStatus read FValidationStatus write FValidationStatus;
    property EquipModel: string read FEquipModel write FEquipModel;
    property EquipManufacturer: string read FEquipManufacturer write FEquipManufacturer;
    property EquipLocation: string read FEquipLocation write FEquipLocation;
  end;

implementation


constructor TProtocol.Create;
begin
  inherited;
  FValidationStatus := vsDraft;
end;

initialization
  RegisterEntity(TProtocol);

end.
