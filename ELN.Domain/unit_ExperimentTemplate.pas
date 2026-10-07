unit unit_ExperimentTemplate;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  // StructureJSON format (see unit_ExperimentTemplateModel for ApplyTemplate):
  //   "proc" object with "title", "type" (TItemType ordinal), optional "actionTypeId",
  //   and "children" array of child items with "title", "level", "type", "children".

  TExperimentTemplate = class;
  TExperimentTemplates = TList<TExperimentTemplate>;

  [Entity]
  [Table('ExperimentTemplates')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TExperimentTemplate = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('Name', [TColumnProp.Required], 200)]
    FName: string;

    [Column('Description', [], 500)]
    FDescription: string;

    [Column('Category', [], 100)]
    FCategory: string;

    [Column('StructureJSON', [TColumnProp.Required], 8000)]
    FStructureJSON: string;

    [Column('CreatedBy', [TColumnProp.Required])]
    FCreatedBy: Integer;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    [Column('ModifiedDate', [])]
    FModifiedDate: Nullable<TDateTime>;

    [Column('Version', [TColumnProp.Required])]
    FVersion: Integer;
  public
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Category: string read FCategory write FCategory;
    property StructureJSON: string read FStructureJSON write FStructureJSON;
    property CreatedBy: Integer read FCreatedBy write FCreatedBy;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property Version: Integer read FVersion write FVersion;
  end;

implementation

initialization
  RegisterEntity(TExperimentTemplate);

end.
