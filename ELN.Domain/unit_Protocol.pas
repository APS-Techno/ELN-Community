unit unit_Protocol;

interface

uses
  System.SysUtils,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable,
  unit_LabEntry;

type
  /// <summary>
  /// Type of protocol/procedure being documented
  /// </summary>
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

  /// <summary>
  /// Validation/approval status for formal protocols
  /// </summary>
  [Enumeration(TEnumMappingType.emInteger)]
  TValidationStatus = (
    vsDraft,
    vsInReview,
    vsApproved,
    vsRejected
  );

  /// <summary>
  /// Formal, structured scientific protocol with HTML template-based forms.
  /// Supports predefined fields, validation workflow, and optional templates.
  /// </summary>
  [Entity]
  [DiscriminatorValue('Protocol')]
  TProtocol = class(TLabEntry)
  private
    [Column('TemplateId', [])]
    FTemplateId: Nullable<Integer>;  // Future: FK to TTemplate entity

    [Column('FormData', [TColumnProp.Lazy], 65536)]
    FFormData: string;  // JSON/XML serialized field values from HTML form

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

{ TProtocol }

constructor TProtocol.Create;
begin
  inherited;
  FValidationStatus := vsDraft;  // Default to draft status
end;

initialization
  RegisterEntity(TProtocol);

end.
