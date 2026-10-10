unit unit_ViewerState;

interface

uses
  System.SysUtils,
  Aurelius.Mapping.Attributes;

type
  [Entity]
  [Table('ViewerStates')]
  [Id('FId', TIdGenerator.IdentityOrSequence)]
  TViewerState = class
  private
    [Column('Id', [TColumnProp.Required, TColumnProp.NoInsert, TColumnProp.NoUpdate])]
    FId: Integer;

    [Column('UserId', [TColumnProp.Required])]
    FUserId: Integer;

    [Column('FileId', [TColumnProp.Required])]
    FFileId: Int64;

    [Column('PluginName', [TColumnProp.Required], 100)]
    FPluginName: string;

    [Column('StateData', [TColumnProp.Required], 8192)]
    FStateData: string;

    [Column('UpdatedDate', [TColumnProp.Required])]
    FUpdatedDate: TDateTime;
  public
    property Id: Integer read FId write FId;
    property UserId: Integer read FUserId write FUserId;
    property FileId: Int64 read FFileId write FFileId;
    property PluginName: string read FPluginName write FPluginName;
    property StateData: string read FStateData write FStateData;
    property UpdatedDate: TDateTime read FUpdatedDate write FUpdatedDate;
  end;

implementation

initialization
  RegisterEntity(TViewerState);

end.
