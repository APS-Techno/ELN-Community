unit unit_ViewerStateModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Linq,
  unit_ViewerState,
  unit_ELNDB_Dictionary;

type
  TViewerStateModel = class
  private
    FManager: TObjectManager;
    FDic: TViewerStateDictionary;
  public
    constructor Create(Manager: TObjectManager);
    destructor Destroy; override;

    function GetState(UserId: Integer; FileId: Int64): TViewerState;
    procedure SaveOrUpdate(UserId: Integer; FileId: Int64;
      const PluginName, StateData: string);
    procedure DeleteForFile(FileId: Int64);
  end;

implementation

uses
  unit_TimeHelper;


constructor TViewerStateModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDic := TViewerStateDictionary.Create;
end;

destructor TViewerStateModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TViewerStateModel.GetState(UserId: Integer; FileId: Int64): TViewerState;
var
  List: TList<TViewerState>;
begin
  Result := nil;
  List := FManager.Find<TViewerState>
    .Where(
      (FDic.UserId = UserId) and
      (FDic.FileId = FileId))
    .Take(1)
    .List;
  try
    if List.Count > 0 then
      Result := List[0];
  finally
    List.Free;
  end;
end;

procedure TViewerStateModel.SaveOrUpdate(UserId: Integer; FileId: Int64;
  const PluginName, StateData: string);
var
  State: TViewerState;
  List: TList<TViewerState>;
begin
  List := FManager.Find<TViewerState>
    .Where(
      (FDic.UserId = UserId) and
      (FDic.FileId = FileId) and
      (FDic.PluginName = PluginName))
    .Take(1)
    .List;
  try
    if List.Count > 0 then
      State := List[0]
    else
      State := nil;
  finally
    List.Free;
  end;

  if Assigned(State) then
  begin
    State.PluginName := PluginName;
    State.StateData := StateData;
    State.UpdatedDate := UTCNow;
  end
  else
  begin
    State := TViewerState.Create;
    State.UserId := UserId;
    State.FileId := FileId;
    State.PluginName := PluginName;
    State.StateData := StateData;
    State.UpdatedDate := UTCNow;
    FManager.Save(State);
  end;
  FManager.Flush;
end;

procedure TViewerStateModel.DeleteForFile(FileId: Int64);
var
  List: TList<TViewerState>;
  State: TViewerState;
begin
  List := FManager.Find<TViewerState>
    .Where(FDic.FileId = FileId)
    .List;
  try
    for State in List do
      FManager.Remove(State);
  finally
    List.Free;
  end;
  FManager.Flush;
end;

end.
