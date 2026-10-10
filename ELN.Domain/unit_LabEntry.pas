unit unit_LabEntry;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  TLabEntry = class;
  TLabEntries = TList<TLabEntry>;

  [Entity]
  [Table('LabEntries')]
  [Inheritance(TInheritanceStrategy.SingleTable)]
  [DiscriminatorColumn('EntryType', TDiscriminatorType.dtString)]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TLabEntry = class
  private
    [Column('ID', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    [Description('')]
    FId: Integer;

    [Column('Title', [TColumnProp.Lazy], 255)]
    FTitle: string;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    FModifiedDate: Nullable<TDateTime>;

    [Column('CreatedBy', [])]
    FCreatedBy: Nullable<Integer>;

    [Column('ModifiedBy', [])]
    FModifiedBy: Nullable<Integer>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;
  public
    property Id: Integer read FId write FId;
    property Title: string read FTitle write FTitle;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property CreatedBy: Nullable<Integer> read FCreatedBy write FCreatedBy;
    property ModifiedBy: Nullable<Integer> read FModifiedBy write FModifiedBy;
    property Version: Integer read FVersion write FVersion;
  end;

implementation

initialization
  RegisterEntity(TLabEntry);

end.
