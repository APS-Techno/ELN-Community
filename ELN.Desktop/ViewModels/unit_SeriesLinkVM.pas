unit unit_SeriesLinkVM;

interface

uses
  System.SysUtils,
  Aurelius.Engine.ObjectManager,
  unit_User,
  unit_ProjectAccessPolicy,
  unit_SeriesTable,
  unit_SeriesModel;

type
  TSeriesLinkResult = record
    SeriesId, Linked, Skipped: Integer;
  end;

  TSeriesLinkVM = class
  private
    FManager: TObjectManager;
    FUser: TUser;
    FModel: TSeriesModel;
    FItemIds: TArray<Integer>;
    FSeries: TArray<TSeriesSummary>;
    FSeriesIndex: Integer;
    FCreateMissing: Boolean;
    FPlan: TSeriesPlanInfo;
    FFreeSlots: TArray<TSeriesSlotInfo>;
    FPointIndex: Integer;
    FLines: TArray<string>;
    FCanApply: Boolean;
    procedure Refresh;
    procedure SetCreateMissing(AValue: Boolean);
    function SeriesId: Integer;
    function ItemTitle(AItemId: Integer): string;
    function FactorNames: string;
    function LevelsText(const ALevels: TSeriesPoint): string;
    function SlotLevelsText(ASlotId: Integer; const AFallback: TSeriesPoint): string;
    function LineText(const ALine: TSeriesLinkLine): string;
  public
    constructor Create(AManager: TObjectManager; AUser: TUser;
      const AAccess: IProjectAccessPolicy; AProjectId: Integer;
      const AItemIds: TArray<Integer>);
    destructor Destroy; override;
    class function MembershipText(
      const AMemberships: TArray<TSeriesMembership>): string; static;
    procedure SelectSeries(AIndex: Integer);
    procedure ChoosePoint(AIndex: Integer);
    function CanChoosePoint: Boolean;
    function PointTexts: TArray<string>;
    function Apply: TSeriesLinkResult;
    property Series: TArray<TSeriesSummary> read FSeries;
    property SeriesIndex: Integer read FSeriesIndex;
    property PointIndex: Integer read FPointIndex;
    property CreateMissing: Boolean read FCreateMissing write SetCreateMissing;
    property Lines: TArray<string> read FLines;
    property CanApply: Boolean read FCanApply;
  end;

implementation

uses
  unit_Item,
  unit_ValueType,
  unit_Series;

const
  Arrow = #$2192;

constructor TSeriesLinkVM.Create(AManager: TObjectManager; AUser: TUser;
  const AAccess: IProjectAccessPolicy; AProjectId: Integer;
  const AItemIds: TArray<Integer>);
var
  S: TSeriesSummary;
begin
  inherited Create;
  FManager := AManager;
  FUser := AUser;
  FItemIds := AItemIds;
  FModel := TSeriesModel.Create(AManager, AAccess);
  FPointIndex := -1;
  FSeriesIndex := -1;
  for S in FModel.ListSeries(AUser, AProjectId) do
    if S.Status = ssActive then
      FSeries := FSeries + [S];
  if Length(FSeries) > 0 then
    FSeriesIndex := 0;
  Refresh;
end;

destructor TSeriesLinkVM.Destroy;
begin
  FModel.Free;
  inherited;
end;

function TSeriesLinkVM.SeriesId: Integer;
begin
  if (FSeriesIndex >= 0) and (FSeriesIndex <= High(FSeries)) then
    Result := FSeries[FSeriesIndex].Id
  else
    Result := 0;
end;

function TSeriesLinkVM.ItemTitle(AItemId: Integer): string;
var
  Item: TItem;
begin
  Item := FManager.Find<TItem>(AItemId);
  if Item = nil then
    Result := '#' + IntToStr(AItemId)
  else
    Result := Item.Title;
end;

function TSeriesLinkVM.FactorNames: string;
var
  F: TSeriesFactorSpec;
  T: TValueType;
begin
  Result := '';
  for F in FPlan.Plan.Factors do
  begin
    T := FManager.Find<TValueType>(F.ValueTypeId);
    if T = nil then
      Continue;
    if Result <> '' then
      Result := Result + '/';
    Result := Result + T.Title;
  end;
end;

function TSeriesLinkVM.LevelsText(const ALevels: TSeriesPoint): string;
begin
  Result := FModel.FormatLevels(FUser, SeriesId, ALevels);
end;

function TSeriesLinkVM.SlotLevelsText(ASlotId: Integer;
  const AFallback: TSeriesPoint): string;
var
  Slot: TSeriesSlotInfo;
begin
  for Slot in FPlan.Slots do
    if Slot.SlotId = ASlotId then
      Exit(LevelsText(Slot.Levels));
  Result := LevelsText(AFallback);
end;

function TSeriesLinkVM.LineText(const ALine: TSeriesLinkLine): string;
var
  Title: string;
begin
  Title := ItemTitle(ALine.ItemId);
  case ALine.Outcome of
    sloLinked:
      Result := Format('%s %s %s',
        [Title, Arrow, SlotLevelsText(ALine.SlotId, ALine.Levels)]);
    sloNewPoint:
    begin
      Result := Format('%s %s new point %s', [Title, Arrow, LevelsText(ALine.Levels)]);
      if not FCreateMissing then
        Result := Result + ' (not added)';
    end;
    sloNoValue:
      Result := Format('%s: no %s value', [Title, FactorNames]);
    sloAmbiguousValue:
      Result := Format('%s: several different %s values', [Title, FactorNames]);
    sloSlotTaken:
      Result := Format('%s: point %s already has a deposition',
        [Title, SlotLevelsText(ALine.SlotId, ALine.Levels)]);
    sloAlreadyMember:
      Result := Title + ': already in this series';
    sloOutsideRange:
      Result := Format('%s: %s is outside the range of the plan',
        [Title, LevelsText(ALine.Levels)]);
    sloNotRoot:
      Result := Title + ': not a top-level item';
  end;
end;

procedure TSeriesLinkVM.Refresh;
var
  Slot: TSeriesSlotInfo;
  Line: TSeriesLinkLine;
  Preview: TArray<TSeriesLinkLine>;
begin
  FPlan := Default(TSeriesPlanInfo);
  FFreeSlots := nil;
  FLines := nil;
  FCanApply := False;
  if SeriesId = 0 then
    Exit;
  try
    FPlan := FModel.GetPlan(FUser, SeriesId);
    for Slot in FPlan.Slots do
      if Slot.ValidItemId = 0 then
        FFreeSlots := FFreeSlots + [Slot];
    if (FPointIndex >= 0) and (FPointIndex <= High(FFreeSlots)) and CanChoosePoint then
    begin
      FLines := [Format('%s %s %s', [ItemTitle(FItemIds[0]), Arrow,
        LevelsText(FFreeSlots[FPointIndex].Levels)])];
      FCanApply := True;
      Exit;
    end;
    FPointIndex := -1;
    Preview := FModel.PreviewLinkByValues(FUser, SeriesId, FItemIds);
    for Line in Preview do
    begin
      FLines := FLines + [LineText(Line)];
      if (Line.Outcome = sloLinked)
        or ((Line.Outcome = sloNewPoint) and FCreateMissing) then
        FCanApply := True;
    end;
  except
    on E: ESeriesError do
    begin
      FLines := [E.Message];
      FCanApply := False;
    end;
  end;
end;

procedure TSeriesLinkVM.SetCreateMissing(AValue: Boolean);
begin
  FCreateMissing := AValue;
  Refresh;
end;

procedure TSeriesLinkVM.SelectSeries(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FSeries)) then
    Exit;
  FSeriesIndex := AIndex;
  FPointIndex := -1;
  Refresh;
end;

procedure TSeriesLinkVM.ChoosePoint(AIndex: Integer);
begin
  FPointIndex := AIndex;
  Refresh;
end;

function TSeriesLinkVM.CanChoosePoint: Boolean;
begin
  Result := (Length(FItemIds) = 1) and (Length(FFreeSlots) > 0);
end;

function TSeriesLinkVM.PointTexts: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(FFreeSlots));
  for I := 0 to High(FFreeSlots) do
    Result[I] := LevelsText(FFreeSlots[I].Levels);
end;

function TSeriesLinkVM.Apply: TSeriesLinkResult;
var
  Lines: TArray<TSeriesLinkLine>;
  Line: TSeriesLinkLine;
begin
  Result := Default(TSeriesLinkResult);
  Result.SeriesId := SeriesId;
  if not FCanApply then
    Exit;
  if FPointIndex >= 0 then
  begin
    FModel.LinkToSlot(FUser, SeriesId, FFreeSlots[FPointIndex].SlotId, FItemIds[0]);
    Result.Linked := 1;
    Exit;
  end;
  Lines := FModel.LinkByValues(FUser, SeriesId, FItemIds, FCreateMissing);
  for Line in Lines do
    if (Line.Outcome = sloLinked)
      or ((Line.Outcome = sloNewPoint) and (Line.SlotId <> 0)) then
      Inc(Result.Linked)
    else
      Inc(Result.Skipped);
end;

class function TSeriesLinkVM.MembershipText(
  const AMemberships: TArray<TSeriesMembership>): string;
var
  M: TSeriesMembership;
  Part, Detail: string;
begin
  Result := '';
  for M in AMemberships do
  begin
    Part := M.Title;
    Detail := M.Levels;
    if M.Failed then
    begin
      if Detail <> '' then
        Detail := Detail + ', ';
      Detail := Detail + 'failed';
    end;
    if Detail <> '' then
      Part := Part + ' (' + Detail + ')';
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Part;
  end;
  if Result <> '' then
    Result := 'Series: ' + Result;
end;

end.
