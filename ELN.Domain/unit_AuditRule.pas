unit unit_AuditRule;

interface

uses
  SysUtils,
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable,
  Aurelius.Types.Proxy,
  unit_ActionType,
  unit_Equipment,
  unit_FileType,
  unit_ValueType;

type
  TAuditRule = class;
  TAuditRuleFile = class;
  TAuditRuleValue = class;

  TAuditRules = TList<TAuditRule>;
  TAuditRuleFiles = TList<TAuditRuleFile>;
  TAuditRuleValues = TList<TAuditRuleValue>;

  [Enumeration(TEnumMappingType.emInteger)]
  TAuditSeverity = (asError, asWarning);

  [Entity]
  [Table('AuditRules')]
  [Description('')]
  // These shared dictionary references and owner back-references are not owned
  // children. CascadeTypeAll includes Evict and would leave stale shared instances.
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TAuditRule = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    [Column('Title', [TColumnProp.Required], 200)]
    [Description('')]
    FTitle: string;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('ActionTypeID', [TColumnProp.Required], 'Id')]
    [Description('')]
    FActionType: Proxy<TActionType>;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('EquipmentID', [TColumnProp.Required], 'Id')]
    [Description('')]
    FEquipment: Proxy<TEquipment>;

    [Column('Severity', [TColumnProp.Required])]
    [Description('')]
    FSeverity: TAuditSeverity;

    [Column('IsActive', [TColumnProp.Required])]
    [Description('')]
    FIsActive: Boolean;

    [Column('Description', [], 500)]
    [Description('')]
    FDescription: string;

    [ManyValuedAssociation([], CascadeTypeAllRemoveOrphan, 'FAuditRule')]
    FRequiredFiles: Proxy<TAuditRuleFiles>;

    [ManyValuedAssociation([], CascadeTypeAllRemoveOrphan, 'FAuditRule')]
    FRequiredValues: Proxy<TAuditRuleValues>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;

    [Column('CreatedBy', [])]
    [Description('')]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    [Description('')]
    FModifiedBy: Nullable<Integer>;

    [Column('CreatedDate', [])]
    [Description('')]
    FCreatedDate: Nullable<TDateTime>;

    [Column('ModifiedDate', [])]
    [Description('')]
    FModifiedDate: Nullable<TDateTime>;

    function GetActionType: TActionType;
    procedure SetActionType(const Value: TActionType);
    function GetEquipment: TEquipment;
    procedure SetEquipment(const Value: TEquipment);
    function GetRequiredFiles: TAuditRuleFiles;
    function GetRequiredValues: TAuditRuleValues;
  public
    property Id: Integer read FId write FId;
    property Title: string read FTitle write FTitle;
    property ActionType: TActionType read GetActionType write SetActionType;
    property Equipment: TEquipment read GetEquipment write SetEquipment;
    property Severity: TAuditSeverity read FSeverity write FSeverity;
    property IsActive: Boolean read FIsActive write FIsActive;
    property Description: string read FDescription write FDescription;
    property RequiredFiles: TAuditRuleFiles read GetRequiredFiles;
    property RequiredValues: TAuditRuleValues read GetRequiredValues;
    property Version: Integer read FVersion write FVersion;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property CreatedDate: Nullable<TDateTime> read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
  end;

  [Entity]
  [Table('AuditRuleFiles')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TAuditRuleFile = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('AuditRuleID', [TColumnProp.Required], 'Id')]
    [Description('')]
    FAuditRule: Proxy<TAuditRule>;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('FileTypeID', [TColumnProp.Required], 'Id')]
    [Description('')]
    FFileType: Proxy<TFileType>;

    function GetAuditRule: TAuditRule;
    procedure SetAuditRule(const Value: TAuditRule);
    function GetFileType: TFileType;
    procedure SetFileType(const Value: TFileType);
  public
    property Id: Integer read FId write FId;
    property AuditRule: TAuditRule read GetAuditRule write SetAuditRule;
    property FileType: TFileType read GetFileType write SetFileType;
  end;

  [Entity]
  [Table('AuditRuleValues')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TAuditRuleValue = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('AuditRuleID', [TColumnProp.Required], 'Id')]
    [Description('')]
    FAuditRule: Proxy<TAuditRule>;

    [Association([TAssociationProp.Lazy, TAssociationProp.Required], [])]
    [JoinColumn('ValueTypeID', [TColumnProp.Required], 'Id')]
    [Description('')]
    FValueType: Proxy<TValueType>;

    function GetAuditRule: TAuditRule;
    procedure SetAuditRule(const Value: TAuditRule);
    function GetValueType: TValueType;
    procedure SetValueType(const Value: TValueType);
  public
    property Id: Integer read FId write FId;
    property AuditRule: TAuditRule read GetAuditRule write SetAuditRule;
    property ValueType: TValueType read GetValueType write SetValueType;
  end;

implementation


function TAuditRule.GetActionType: TActionType;
begin
  Result := FActionType.Value;
end;

procedure TAuditRule.SetActionType(const Value: TActionType);
begin
  FActionType.Value := Value;
end;

function TAuditRule.GetEquipment: TEquipment;
begin
  Result := FEquipment.Value;
end;

procedure TAuditRule.SetEquipment(const Value: TEquipment);
begin
  FEquipment.Value := Value;
end;

function TAuditRule.GetRequiredFiles: TAuditRuleFiles;
begin
  Result := FRequiredFiles.Value;
end;

function TAuditRule.GetRequiredValues: TAuditRuleValues;
begin
  Result := FRequiredValues.Value;
end;


function TAuditRuleFile.GetAuditRule: TAuditRule;
begin
  Result := FAuditRule.Value;
end;

procedure TAuditRuleFile.SetAuditRule(const Value: TAuditRule);
begin
  FAuditRule.Value := Value;
end;

function TAuditRuleFile.GetFileType: TFileType;
begin
  Result := FFileType.Value;
end;

procedure TAuditRuleFile.SetFileType(const Value: TFileType);
begin
  FFileType.Value := Value;
end;


function TAuditRuleValue.GetAuditRule: TAuditRule;
begin
  Result := FAuditRule.Value;
end;

procedure TAuditRuleValue.SetAuditRule(const Value: TAuditRule);
begin
  FAuditRule.Value := Value;
end;

function TAuditRuleValue.GetValueType: TValueType;
begin
  Result := FValueType.Value;
end;

procedure TAuditRuleValue.SetValueType(const Value: TValueType);
begin
  FValueType.Value := Value;
end;

initialization
  RegisterEntity(TAuditRule);
  RegisterEntity(TAuditRuleFile);
  RegisterEntity(TAuditRuleValue);

end.
