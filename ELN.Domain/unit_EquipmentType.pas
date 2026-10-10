unit unit_EquipmentType;

interface

uses
  SysUtils, 
  Generics.Collections, 
  Aurelius.Mapping.Attributes, 
  Aurelius.Types.Blob, 
  Aurelius.Types.DynamicProperties, 
  Aurelius.Types.Nullable, 
  Aurelius.Types.Proxy;

type
  TEquipmentType = class;
  
  [Entity]
  [Table('EquipmentTypes')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TEquipmentType = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;
    
    [Column('Type', [TColumnProp.Required])]
    [Description('')]
    FType_: string;
    
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
  public
    property Id: Integer read FId write FId;
    property Type_: string read FType_ write FType_;
    property Description: string read FDescription write FDescription;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
  end;
  
implementation


initialization
  RegisterEntity(TEquipmentType);

end.
