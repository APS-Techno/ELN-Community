unit unit_FileType;

interface

uses
  SysUtils, 
  Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.DynamicProperties,
  Aurelius.Types.Nullable,
  Aurelius.Types.Blob,
  Aurelius.Types.Proxy;

type
  TFileType = class;

  TFileTypes = TList<TFileType>;

  [Entity]
  [Table('FileTypes')]
  [Description('')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TFileType = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    [Column('Ext', [TColumnProp.Required, TColumnProp.Lazy])]
    [Description('')]
    FExt: string;

    [Column('Description', [TColumnProp.Lazy])]
    [Description('')]
    FDescription: string;

    [Column('Icon', [TColumnProp.Lazy])]
    [Description('')]
    FIcon: TBlob;

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
    property Ext: string read FExt write FExt;
    property Icon: TBlob read FIcon write FIcon;
    property Description: string read FDescription write FDescription;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
  end;
  
implementation

initialization
  RegisterEntity(TFileType);

end.
