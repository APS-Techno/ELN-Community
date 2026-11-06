unit unit_SeriesVM;

interface

uses
  System.SysUtils,
  System.Classes,
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_Series,
  unit_SeriesColumn,
  unit_SeriesTable,
  unit_SeriesModel,
  unit_SeriesExport,
  unit_ProjectAccessPolicy;

const
  NO_SERIES_TEXT = 'No series yet. Click New series... to make one.';
  NO_POINTS_TEXT = 'This series has no points. Click Edit plan... to add factors and levels.';

type
  TOpenSeriesEvent = procedure(Sender: TObject; AProjectId,
    ASeriesId: Integer) of object;

  TSeriesRowAction = (raMake, raLink, raOpen, raConfirm, raFail, raUnlink,
    raRemove);
  TSeriesRowActions = set of TSeriesRowAction;

  TSeriesVM = class
  private
    FManager: TObjectManager;
    FUser: TUser;
    FAccess: IProjectAccessPolicy;
    FModel: TSeriesModel;
    FProjectId: Integer;
    FSelectedId: Integer;
    FSelectedIndex: Integer;
    FSeries: TArray<TSeriesSummary>;
    FTable: TSeriesTable;
    FPlan: TSeriesPlanInfo;
    FCanWrite: Boolean;
    FShowFailed: Boolean;
    FOnChanged: TNotifyEvent;
    procedure Changed;
    function SelectedSeriesId: Integer;
    procedure SetShowFailed(AValue: Boolean);
    procedure LoadSelected;
    function SlotLevels(ASlotId: Integer; out ALevels: TSeriesPoint): Boolean;
    function UnitsOf(const APlan: TSeriesPlan): TArray<string>;
    function PointsFromText(const ALevelsText: string;
      const APlan: TSeriesPlan; AKnown: Boolean): TArray<TSeriesPoint>;
    function RowHasRootPlanned(const ARow: TSeriesTableRow): Boolean;
  public
    constructor Create(AManager: TObjectManager; AUser: TUser;
      const AAccess: IProjectAccessPolicy);
    destructor Destroy; override;
    class function ProgressText(const ASummary: TSeriesSummary): string; static;
    class function StateText(AState: TSeriesRowState): string; static;
    procedure OpenProject(AProjectId, ASeriesId: Integer);
    procedure Reload;
    procedure Select(AIndex: Integer);
    function NewSeries(const ATitle, APurpose: string; const APlan: TSeriesPlan;
      const ALevelsText: string): Integer;
    procedure SavePlan(const ATitle, APurpose: string; const APlan: TSeriesPlan;
      const ALevelsText: string);
    function AddPoint(const ALevels: TSeriesPoint; const AReason: string): Integer;
    procedure Start;
    procedure ChangeStatus(ANew: TSeriesStatus);
    procedure Unlink(AItemId: Integer);
    procedure RemoveExcluded;
    function SelectedIsAuthor: Boolean;
    procedure SetColumnRole(AColumn: Integer; ARole: TSeriesColumnRole);
    function ExportText(ADelimiter: Char): string;
    function EmptyText: string;
    function PointText(ARow: Integer): string;
    function FactorLabels: TArray<string>;
    function FactorUnits: TArray<string>;
    function RowActions(ARow: Integer): TSeriesRowActions;
    function DeviationHint(ARow, AColumn: Integer): string;
    function PlotValue(ARow, AColumn: Integer; out AValue, ATol: Double): Boolean;
    function PointsWaiting(const AColumns: TArray<Integer>): Integer;
    function DefaultDepositionTitle(ASlotId: Integer): string;
    procedure DepositionDefaults(out AActionTypeId, AEquipmentId: Integer);
    function MakeDeposition(ASlotId: Integer;
      const ADraft: TSeriesDepositionDraft): Integer;
    procedure LinkExisting(ASlotId, AItemId: Integer);
    function ConfirmPlanned(AItemId: Integer): Integer;
    procedure MarkFailed(AItemId: Integer; const AReason: string);
    procedure RemovePoint(ASlotId: Integer);
    property ProjectId: Integer read FProjectId;
    property Series: TArray<TSeriesSummary> read FSeries;
    property SelectedIndex: Integer read FSelectedIndex;
    property Table: TSeriesTable read FTable;
    property Plan: TSeriesPlanInfo read FPlan;
    property CanWrite: Boolean read FCanWrite;
    property ShowFailed: Boolean read FShowFailed write SetShowFailed;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  unit_ValueType,
  unit_SeriesSlot,
  unit_SeriesPlanInput;

const
  MAX_TITLE = 255;

constructor TSeriesVM.Create(AManager: TObjectManager; AUser: TUser;
  const AAccess: IProjectAccessPolicy);
begin
  inherited Create;
  if AAccess = nil then
    raise EArgumentNilException.Create('Access');
  FManager := AManager;
  FUser := AUser;
  FAccess := AAccess;
  FModel := TSeriesModel.Create(AManager, AAccess);
  FSelectedIndex := -1;
end;

destructor TSeriesVM.Destroy;
begin
  FModel.Free;
  inherited;
end;

class function TSeriesVM.ProgressText(const ASummary: TSeriesSummary): string;
begin
  Result := Format('%d/%d measured', [ASummary.MeasuredCount, ASummary.PointCount]);
end;

class function TSeriesVM.StateText(AState: TSeriesRowState): string;
begin
  case AState of
    srsPlanned: Result := 'planned';
    srsDeposited: Result := 'deposited';
    srsMeasured: Result := 'measured';
    srsFailed: Result := 'failed';
  else
    Result := '';
  end;
end;

procedure TSeriesVM.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TSeriesVM.SelectedSeriesId: Integer;
begin
  if (FSelectedIndex >= 0) and (FSelectedIndex <= High(FSeries)) then
    Result := FSeries[FSelectedIndex].Id
  else
    Result := 0;
end;

procedure TSeriesVM.SetShowFailed(AValue: Boolean);
begin
  if FShowFailed = AValue then
    Exit;
  FShowFailed := AValue;
  Reload;
end;

procedure TSeriesVM.LoadSelected;
begin
  FTable := Default(TSeriesTable);
  FPlan := Default(TSeriesPlanInfo);
  if FSelectedId <> 0 then
  begin
    FTable := FModel.BuildTable(FUser, FSelectedId, FShowFailed);
    FPlan := FModel.GetPlan(FUser, FSelectedId);
  end;
end;

procedure TSeriesVM.OpenProject(AProjectId, ASeriesId: Integer);
begin
  FProjectId := AProjectId;
  FSelectedId := ASeriesId;
  Reload;
end;

procedure TSeriesVM.Reload;
var
  I: Integer;
begin
  FSeries := nil;
  FSelectedIndex := -1;
  FCanWrite := False;
  if FProjectId <> 0 then
  begin
    FCanWrite := FAccess.CanWrite(FManager, FUser, FProjectId);
    FSeries := FModel.ListSeries(FUser, FProjectId);
    for I := 0 to High(FSeries) do
      if FSeries[I].Id = FSelectedId then
        FSelectedIndex := I;
    if (FSelectedIndex < 0) and (Length(FSeries) > 0) then
      FSelectedIndex := 0;
  end;
  FSelectedId := SelectedSeriesId;
  LoadSelected;
  Changed;
end;

procedure TSeriesVM.Select(AIndex: Integer);
begin
  if (AIndex < -1) or (AIndex > High(FSeries)) then
    Exit;
  FSelectedIndex := AIndex;
  FSelectedId := SelectedSeriesId;
  LoadSelected;
  Changed;
end;

function TSeriesVM.PointsFromText(const ALevelsText: string;
  const APlan: TSeriesPlan; AKnown: Boolean): TArray<TSeriesPoint>;
var
  Existing: TArray<TSeriesPoint>;
  Slot: TSeriesSlotInfo;
  Error: string;
begin
  Existing := nil;
  if AKnown then
    for Slot in FPlan.Slots do
      Existing := Existing + [Slot.Levels];
  if not BuildPlanPoints(ALevelsText, UnitsOf(APlan), Existing,
    FormatSettings, Result, Error) then
    raise ESeriesError.Create(Error);
end;

function TSeriesVM.NewSeries(const ATitle, APurpose: string;
  const APlan: TSeriesPlan; const ALevelsText: string): Integer;
var
  Points: TArray<TSeriesPoint>;
begin
  Points := PointsFromText(ALevelsText, APlan, False);
  Result := FModel.CreateSeries(FUser, FProjectId, ATitle, APurpose, APlan, Points);
  FSelectedId := Result;
  Reload;
end;

procedure TSeriesVM.SavePlan(const ATitle, APurpose: string;
  const APlan: TSeriesPlan; const ALevelsText: string);
var
  Points: TArray<TSeriesPoint>;
  Title: string;
  TitleChanged: Boolean;
begin
  if FSelectedId = 0 then
    Exit;
  Title := Trim(ATitle);
  if (Title = '') or (Length(Title) > MAX_TITLE) then
    raise ESeriesError.CreateFmt('The title must be 1 to %d characters.', [MAX_TITLE]);
  TitleChanged := Title <> FSeries[FSelectedIndex].Title;
  Points := PointsFromText(ALevelsText, APlan, True);
  try
    FModel.UpdatePlanAndPoints(FUser, FSelectedId, True, APurpose, True, APlan,
      Points, '');
    if TitleChanged then
      FModel.UpdateSeries(FUser, FSelectedId, Title, APurpose);
  finally
    Reload;
  end;
end;

function TSeriesVM.AddPoint(const ALevels: TSeriesPoint; const AReason: string): Integer;
var
  SlotIds: TArray<Integer>;
begin
  Result := 0;
  if FSelectedId = 0 then
    Exit;
  try
    SlotIds := FModel.AddPoints(FUser, FSelectedId, [ALevels], AReason);
    if Length(SlotIds) > 0 then
      Result := SlotIds[0];
  finally
    Reload;
  end;
end;

procedure TSeriesVM.Start;
begin
  if FSelectedId = 0 then
    Exit;
  try
    FModel.Start(FUser, FSelectedId);
  finally
    Reload;
  end;
end;

procedure TSeriesVM.ChangeStatus(ANew: TSeriesStatus);
begin
  if FSelectedId = 0 then
    Exit;
  FModel.ChangeStatus(FUser, FSelectedId, ANew);
  Reload;
end;

procedure TSeriesVM.Unlink(AItemId: Integer);
begin
  if FSelectedId = 0 then
    Exit;
  FModel.Unlink(FUser, FSelectedId, AItemId);
  Reload;
end;

procedure TSeriesVM.RemoveExcluded;
var
  Ids: TArray<Integer>;
  Id: Integer;
begin
  if FSelectedId = 0 then
    Exit;
  Ids := FTable.Excluded;
  try
    for Id in Ids do
      FModel.Unlink(FUser, FSelectedId, Id);
  finally
    Reload;
  end;
end;

function TSeriesVM.SelectedIsAuthor: Boolean;
begin
  Result := (FSelectedIndex >= 0)
    and (FSeries[FSelectedIndex].CreatedBy = FUser.Id);
end;

procedure TSeriesVM.SetColumnRole(AColumn: Integer; ARole: TSeriesColumnRole);
var
  Col: TSeriesTableColumn;
begin
  if (FSelectedId = 0) or (AColumn < 0) or (AColumn > High(FTable.Columns)) then
    Exit;
  Col := FTable.Columns[AColumn];
  FModel.SetColumnRole(FUser, FSelectedId, Col.RecType, Col.ValueTypeId,
    Col.SourceKey, ARole);
  Reload;
end;

function TSeriesVM.ExportText(ADelimiter: Char): string;
begin
  Result := SeriesTableToText(FTable, ADelimiter);
end;

function TSeriesVM.EmptyText: string;
begin
  if FSelectedIndex < 0 then
    Result := NO_SERIES_TEXT
  else if Length(FPlan.Slots) = 0 then
    Result := NO_POINTS_TEXT
  else
    Result := '';
end;

function TSeriesVM.SlotLevels(ASlotId: Integer; out ALevels: TSeriesPoint): Boolean;
var
  Slot: TSeriesSlotInfo;
begin
  for Slot in FPlan.Slots do
    if Slot.SlotId = ASlotId then
    begin
      ALevels := Slot.Levels;
      Exit(True);
    end;
  ALevels := nil;
  Result := False;
end;

function TSeriesVM.FactorUnits: TArray<string>;
begin
  Result := UnitsOf(FPlan.Plan);
end;

function TSeriesVM.UnitsOf(const APlan: TSeriesPlan): TArray<string>;
var
  I: Integer;
  T: TValueType;
begin
  SetLength(Result, Length(APlan.Factors));
  for I := 0 to High(Result) do
  begin
    T := FManager.Find<TValueType>(APlan.Factors[I].ValueTypeId);
    if T <> nil then
      Result[I] := T.Units;
  end;
end;

function TSeriesVM.FactorLabels: TArray<string>;
var
  I: Integer;
  T: TValueType;
begin
  SetLength(Result, Length(FPlan.Plan.Factors));
  for I := 0 to High(Result) do
  begin
    Result[I] := Format('Level %d', [I + 1]);
    T := FManager.Find<TValueType>(FPlan.Plan.Factors[I].ValueTypeId);
    if T <> nil then
    begin
      Result[I] := SeriesEntryCaption(T.Title, FPlan.Plan.Factors[I].EntryLabel);
      if T.Units <> '' then
        Result[I] := Result[I] + ', ' + T.Units;
    end;
  end;
end;

function TSeriesVM.PointText(ARow: Integer): string;
var
  Row: TSeriesTableRow;
  Levels: TSeriesPoint;
begin
  Result := '';
  if (ARow < 0) or (ARow > High(FTable.Rows)) then
    Exit;
  Row := FTable.Rows[ARow];
  if not SlotLevels(Row.SlotId, Levels) then
    Exit;
  Result := FormatPointText(Levels, FactorUnits);
  if Row.Origin = ssoAdded then
    Result := Result + ' (added)';
end;

function TSeriesVM.RowHasRootPlanned(const ARow: TSeriesTableRow): Boolean;
var
  Cell: TSeriesCell;
  Hit: TSeriesHit;
begin
  for Cell in ARow.Cells do
    for Hit in Cell.Hits do
      if Hit.Planned and (Hit.ItemId = ARow.ItemId) then
        Exit(True);
  Result := False;
end;

function TSeriesVM.RowActions(ARow: Integer): TSeriesRowActions;
var
  Row: TSeriesTableRow;
  Status: TSeriesStatus;
  Open: Boolean;
begin
  Result := [];
  if (ARow < 0) or (ARow > High(FTable.Rows)) or (FSelectedIndex < 0) then
    Exit;
  Row := FTable.Rows[ARow];
  Status := FSeries[FSelectedIndex].Status;
  Open := FCanWrite and (Status in [ssDraft, ssActive]);
  if Row.State = srsPlanned then
  begin
    if FCanWrite and (Status = ssActive) then
      Result := [raMake, raLink];
    if Open then
      Include(Result, raRemove);
    Exit;
  end;
  Include(Result, raOpen);
  if Open then
    Include(Result, raUnlink);
  if Row.State = srsFailed then
    Exit;
  if Open then
    Include(Result, raFail);
  if FCanWrite and RowHasRootPlanned(Row) then
    Include(Result, raConfirm);
end;

function TSeriesVM.DeviationHint(ARow, AColumn: Integer): string;
var
  Row: TSeriesTableRow;
  Col: TSeriesTableColumn;
  Levels: TSeriesPoint;
  Planned: Double;
  Known: Boolean;
  I: Integer;
begin
  Result := '';
  if (ARow < 0) or (ARow > High(FTable.Rows)) or (AColumn < 0)
    or (AColumn > High(FTable.Columns)) then
    Exit;
  Row := FTable.Rows[ARow];
  if (AColumn > High(Row.Cells)) or not Row.Cells[AColumn].Deviation then
    Exit;
  Col := FTable.Columns[AColumn];
  Known := False;
  Planned := 0;
  if SlotLevels(Row.SlotId, Levels) then
    for I := 0 to High(FPlan.Plan.Factors) do
      if (FPlan.Plan.Factors[I].ValueTypeId = Col.ValueTypeId) and (I <= High(Levels)) then
      begin
        Planned := Levels[I];
        Known := True;
      end;
  if not Known then
    for I := 0 to High(FPlan.Plan.Fixed) do
      if FPlan.Plan.Fixed[I].ValueTypeId = Col.ValueTypeId then
      begin
        Planned := FPlan.Plan.Fixed[I].Value;
        Known := True;
      end;
  if not Known then
    Exit('Differs from the plan');
  Result := 'Differs from the plan (' + SeriesNumberText(Planned);
  if Col.Units <> '' then
    Result := Result + ' ' + Col.Units;
  Result := Result + ')';
end;

function TSeriesVM.PlotValue(ARow, AColumn: Integer; out AValue,
  ATol: Double): Boolean;
var
  Cell: TSeriesCell;
  Hit, Data: TSeriesHit;
  Count: Integer;
begin
  AValue := 0;
  ATol := 0;
  Result := False;
  if (ARow < 0) or (ARow > High(FTable.Rows)) or (AColumn < 0) then
    Exit;
  if (FTable.Rows[ARow].State in [srsPlanned, srsFailed])
    or (AColumn > High(FTable.Rows[ARow].Cells)) then
    Exit;
  Cell := FTable.Rows[ARow].Cells[AColumn];
  Count := 0;
  Data := Default(TSeriesHit);
  for Hit in Cell.Hits do
    if not Hit.Planned then
    begin
      Data := Hit;
      Inc(Count);
    end;
  if Count <> 1 then
    Exit;
  AValue := Data.Value;
  ATol := Data.Tol;
  Result := True;
end;

function TSeriesVM.PointsWaiting(const AColumns: TArray<Integer>): Integer;
var
  Row: TSeriesTableRow;
  Col: Integer;
  Hit: TSeriesHit;
  Waiting: Boolean;
begin
  Result := 0;
  for Row in FTable.Rows do
  begin
    if Row.State = srsPlanned then
      Continue;
    Waiting := False;
    for Col in AColumns do
      if (Col >= 0) and (Col <= High(Row.Cells)) then
        for Hit in Row.Cells[Col].Hits do
          if Hit.Planned then
            Waiting := True;
    if Waiting then
      Inc(Result);
  end;
end;

function TSeriesVM.DefaultDepositionTitle(ASlotId: Integer): string;
begin
  Result := FModel.DefaultDepositionTitle(FUser, FSelectedId, ASlotId);
end;

procedure TSeriesVM.DepositionDefaults(out AActionTypeId, AEquipmentId: Integer);
begin
  FModel.DepositionDefaults(FUser, FSelectedId, AActionTypeId, AEquipmentId);
end;

function TSeriesVM.MakeDeposition(ASlotId: Integer;
  const ADraft: TSeriesDepositionDraft): Integer;
begin
  Result := 0;
  if FSelectedId = 0 then
    Exit;
  try
    Result := FModel.MakeDeposition(FUser, FSelectedId, ASlotId, ADraft);
  finally
    Reload;
  end;
end;

procedure TSeriesVM.LinkExisting(ASlotId, AItemId: Integer);
begin
  if FSelectedId = 0 then
    Exit;
  try
    FModel.LinkToSlot(FUser, FSelectedId, ASlotId, AItemId);
  finally
    Reload;
  end;
end;

function TSeriesVM.ConfirmPlanned(AItemId: Integer): Integer;
begin
  Result := 0;
  if FSelectedId = 0 then
    Exit;
  try
    Result := FModel.ConfirmPlanned(FUser, AItemId);
  finally
    Reload;
  end;
end;

procedure TSeriesVM.MarkFailed(AItemId: Integer; const AReason: string);
begin
  if FSelectedId = 0 then
    Exit;
  try
    FModel.MarkFailed(FUser, FSelectedId, AItemId, AReason);
  finally
    Reload;
  end;
end;

procedure TSeriesVM.RemovePoint(ASlotId: Integer);
begin
  if FSelectedId = 0 then
    Exit;
  try
    FModel.RemovePoint(FUser, FSelectedId, ASlotId);
  finally
    Reload;
  end;
end;

end.
