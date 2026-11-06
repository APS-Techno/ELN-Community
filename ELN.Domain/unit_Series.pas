unit unit_Series;

{ Every enum here is stored as an integer ordinal. APPEND ONLY. }

interface

uses
  System.Generics.Collections,
  Aurelius.Mapping.Attributes,
  Aurelius.Types.Nullable;

type
  [Enumeration(TEnumMappingType.emInteger)]
  TSeriesStatus = (ssDraft, ssActive, ssClosed, ssAbandoned);

  [Enumeration(TEnumMappingType.emInteger)]
  TSeriesCreatedVia = (scvDesktop, scvMcp);

  TSeries = class;
  TSeriesList = TList<TSeries>;

  [Entity]
  [Table('Series')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  [DBIndex('IX_Series_ProjectId', 'ProjectId')]
  TSeries = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('ProjectId', [TColumnProp.Required])]
    FProjectId: Integer;

    [Column('Title', [TColumnProp.Required], 255)]
    FTitle: string;

    [Column('Purpose', [TColumnProp.Lazy], 65536)]
    FPurpose: string;

    [Column('Status', [TColumnProp.Required])]
    FStatus: TSeriesStatus;

    [Column('TargetFolderId', [])]
    FTargetFolderId: Nullable<Integer>;

    [Column('CreatedBy', [TColumnProp.Required])]
    FCreatedBy: Integer;

    [Column('CreatedDate', [TColumnProp.Required])]
    FCreatedDate: TDateTime;

    [Column('CreatedVia', [TColumnProp.Required])]
    FCreatedVia: TSeriesCreatedVia;

    [Column('ModifiedDate', [])]
    FModifiedDate: Nullable<TDateTime>;

    [Column('Version', [TColumnProp.Required])]
    [Version]
    FVersion: Integer;
  public
    constructor Create;
    procedure MarkModified(const ANow: TDateTime);
    property Id: Integer read FId write FId;
    property ProjectId: Integer read FProjectId write FProjectId;
    property Title: string read FTitle write FTitle;
    property Purpose: string read FPurpose write FPurpose;
    property Status: TSeriesStatus read FStatus write FStatus;
    property TargetFolderId: Nullable<Integer> read FTargetFolderId write FTargetFolderId;
    property CreatedBy: Integer read FCreatedBy write FCreatedBy;
    property CreatedDate: TDateTime read FCreatedDate write FCreatedDate;
    property CreatedVia: TSeriesCreatedVia read FCreatedVia write FCreatedVia;
    property ModifiedDate: Nullable<TDateTime> read FModifiedDate write FModifiedDate;
    property Version: Integer read FVersion write FVersion;
  end;

implementation

uses
  System.DateUtils;

constructor TSeries.Create;
begin
  inherited Create;
  FVersion := 1;
end;

procedure TSeries.MarkModified(const ANow: TDateTime);
begin
  if FModifiedDate.HasValue and (ANow <= FModifiedDate.Value) then
    FModifiedDate := IncMilliSecond(FModifiedDate.Value)
  else
    FModifiedDate := ANow;
end;

initialization
  RegisterEntity(TSeries);

end.
