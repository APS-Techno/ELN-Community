unit test_SeriesModel;

interface

uses
  System.SysUtils, DUnitX.TestFramework, unit_LocalNotebook, unit_ActionType, unit_ValueType,
  unit_ItemTypes, unit_SeriesTable, unit_SeriesMember, unit_SeriesModel;

type
  [TestFixture]
  TSeriesModelTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FModel: TSeriesModel;
    FProjectId: Integer;
    FPower, FThickness, FArFlow, FPressure: TValueType;
    FXrr: TActionType;
    function NewProject(const ATitle: string): Integer;
    function NewItem(AProjectId, AParent: Integer; ALevel: TItemLevel;
      AAction: TActionType; const ATitle: string): Integer;
    procedure AddValue(AItemId: Integer; AType: TValueType; ARec: TRecType;
      AValue, ATol: Double);
    procedure SetDeleted(AItemId: Integer);
    function NewSeries: Integer;
    function AuditCount(AType: Integer; AId: Int64; const AText: string): Integer;
    function MemberCount(ASeriesId: Integer): Integer;
    procedure ExpectSeriesError(const AProc: TProc);
    function StatementsFor(AMembers: Integer): Integer;
    function StdPlan: TSeriesPlan;
    function NewSeriesWithPoints(const ALevels: array of Double): Integer;
    function NewMcpSeries(const ALevels: array of Double): Integer;
    function SlotAt(ASeriesId: Integer; ALevel: Double): Integer;
    procedure LinkItems(ASeriesId: Integer; const AItems: array of Integer);
    procedure ExpectErrorText(const AText: string; const AProc: TProc);
    function NewDeposition(const ATitle: string; APower, ATol: Double): Integer;
    function MakeDraft(const ATitle: string): TSeriesDepositionDraft;
    function SlotCount(ASeriesId: Integer): Integer;
    function NewFolder(AProjectId: Integer): Integer;
    function NewMcp: TSeriesModel;
    function MemberOf(AItemId: Integer): TSeriesMember;
    function ListStatementsFor(ASeries: Integer): Integer;
    procedure RunSql(const ASql: string);
    function CountOf(const ATable: string): Integer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure EntitiesRoundTrip;
    [Test] procedure PlanEntitiesRoundTrip;
    [Test] procedure DuplicateMemberRejected;
    [Test] procedure CreateAndList;
    [Test] procedure CreateRejectsEmptyTitle;
    [Test] procedure LinkToSlotRefusesItemAlreadyInSeries;
    [Test] procedure ClosedSeriesRefusesAddAndReopenAllows;
    [Test] procedure ChangeStatusRejectsAbandonedToActive;
    [Test] procedure BuildTableReadsGrandchildValues;
    [Test] procedure BuildTableSkipsDeletedDescendant;
    [Test] procedure BuildTableExcludesRecycledAndForeignMembers;
    [Test] procedure UnlinkAcceptsExcludedItem;
    [Test] procedure MemberCountSkipsExcludedItems;
    [Test] procedure BuildTableKeysItemWithoutActionType;
    [Test] procedure BuildTableStatementCountIndependentOfMembers;
    [Test] procedure CreateWritesSeriesAudit;
    [Test] procedure MemberAndColumnWritesBumpVersion;
    [Test] procedure OnlyAuthorClosesAndReopens;
    [Test] procedure PurgeRemovesMembershipWithAudit;
    [Test] procedure CreateWithPlanMakesPlannedPoints;
    [Test] procedure McpCreateIsDraftAndCannotStart;
    [Test] procedure SavePlanRefusesFactorChangeWithPoints;
    [Test] procedure SavePlanRefusesRangeExcludingPoint;
    [Test] procedure UpdatePlanAndPointsRefusedChangesNothing;
    [Test] procedure UpdatePlanAndPointsChangesEverythingOnce;
    [Test] procedure RecycledValidMemberIsNotMeasured;
    [Test] procedure SplitResponseUsesChosenSource;
    [Test] procedure SavePlanDropsResponseBackToShown;
    [Test] procedure SetColumnRoleKeepsOtherPrefs;
    [Test] procedure AddPointRefusesDuplicateAndOutsideRange;
    [Test] procedure AddPointWhileActiveIsAdded;
    [Test] procedure AddPointWhileDraftIsPlanned;
    [Test] procedure FillGridAddsMissingCombinations;
    [Test] procedure RemovePointRefusedWithMember;
    [Test] procedure DefaultDepositionTitleFormatsLevels;
    [Test] procedure DepositionDefaultsFollowLastMember;
    [Test] procedure MakeDepositionWritesPlannedValuesAndMember;
    [Test] procedure EntryLabelsNamePlanValuesAndColumns;
    [Test] procedure MakeRefusedWhenSlotHasValidMember;
    [Test] procedure MakeRefusedWhileDraft;
    [Test] procedure LinkRefusedWhenSlotHasValidMember;
    [Test] procedure LinkRefusedWhenItemAlreadyInSeries;
    [Test] procedure LinkByValuesMatchesWithinTolerance;
    [Test] procedure LinkByValuesReportsNoValueAndAmbiguous;
    [Test] procedure LinkByValuesCreatesMissingOnlyWhenAsked;
    [Test] procedure LinkByValuesSecondItemSameSlotTaken;
    [Test] procedure MarkFailedFreesSlot;
    [Test] procedure UnlinkRemovesMembership;
    [Test] procedure ListSeriesCountsPointsAndMeasured;
    [Test] procedure ListSeriesStatementCountIndependentOfSeries;
    [Test] procedure MakeDepositionRollsBackWhenAuditFails;
    [Test] procedure MakeDepositionRollsBackWhenFixedTypeMissing;
    [Test] procedure LinkByValuesRollsBackWhenAuditFails;
    [Test] procedure LinkToSlotRejectsBadItems;
    [Test] procedure MeasuredWithoutResponsesNeedsOnlyValidMember;
    [Test] procedure PlanFolderMustBelongToProject;
    [Test] procedure MakeDepositionRefusedWhenFolderLeftProject;
    [Test] procedure CanDeleteRefusesTypeUsedByPlan;
    [Test] procedure MakeDepositionRefusesMissingFactorType;
    [Test] procedure McpActiveSeriesAcceptsOnlyPurposeAndPoints;
    [Test] procedure McpDraftSeriesPlanChangeAllowed;
    [Test] procedure ExcludedValidMemberRefusalNamesUnlinkExcluded;
    [Test] procedure LinkByValuesNearDuplicateNewPointsShareOnePoint;
  end;

implementation

uses
  System.IOUtils, System.DateUtils, System.Generics.Collections,
  Aurelius.Criteria.Linq, Aurelius.Types.Nullable, Aurelius.Drivers.Interfaces,
  unit_Project, unit_ProjectModel, unit_Item, unit_AuditLog,
  unit_RecycleBinModel, test_DesktopLoadStatements,
  unit_Series, unit_SeriesColumn,
  unit_SeriesFactor, unit_SeriesFixed, unit_SeriesSlot, unit_ValueTypeModel;

const
  Password = 'Synthetic-Series-Model-Only!';

procedure TSeriesModelTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-SeriesModel-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  FModel := TSeriesModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  FProjectId := NewProject('Series project');
  FPower := TValueType.Create;
  FPower.Symbol := 'PW';
  FPower.Title := 'Power';
  FPower.Units := 'W';
  FPower.CreatedDate := Now;
  FNotebook.Manager.Save(FPower);
  FThickness := TValueType.Create;
  FThickness.Symbol := 'TH';
  FThickness.Title := 'Thickness';
  FThickness.Units := 'nm';
  FThickness.CreatedDate := Now;
  FNotebook.Manager.Save(FThickness);
  FArFlow := TValueType.Create;
  FArFlow.Symbol := 'AF';
  FArFlow.Title := 'Ar flow';
  FArFlow.Units := 'sccm';
  FArFlow.CreatedDate := Now;
  FNotebook.Manager.Save(FArFlow);
  FPressure := TValueType.Create;
  FPressure.Symbol := 'PR';
  FPressure.Title := 'Pressure';
  FPressure.Units := 'mTorr';
  FPressure.CreatedDate := Now;
  FNotebook.Manager.Save(FPressure);
  FXrr := TActionType.Create;
  FXrr.Title := 'XRR';
  FXrr.CreatedDate := Now;
  FNotebook.Manager.Save(FXrr);
  FNotebook.Manager.Flush;
end;

procedure TSeriesModelTests.TearDown;
begin
  FreeAndNil(FModel);
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TSeriesModelTests.EntitiesRoundTrip;
var
  S: TSeries;
  M: TSeriesMember;
  C: TSeriesColumn;
  Created, Added: TDateTime;
  SeriesId, UserId: Integer;
begin
  UserId := FNotebook.Principal.Id;
  Created := EncodeDateTime(2026, 11, 4, 9, 30, 0, 0);
  Added := EncodeDateTime(2026, 11, 4, 10, 0, 0, 0);

  S := TSeries.Create;
  S.ProjectId := 7;
  S.Title := 'Rate calibration Ti';
  S.Purpose := 'Calibrate the deposition rate';
  S.Status := ssActive;
  S.TargetFolderId := 3;
  S.CreatedBy := UserId;
  S.CreatedDate := Created;
  S.CreatedVia := scvMcp;
  FNotebook.Manager.Save(S);
  FNotebook.Manager.Flush;
  SeriesId := S.Id;

  M := TSeriesMember.Create;
  M.SeriesId := SeriesId;
  M.ItemId := 41;
  M.SlotId := 2;
  M.AttemptState := satFailed;
  M.FailReason := 'Target arced';
  M.AddedBy := UserId;
  M.AddedDate := Added;
  FNotebook.Manager.Save(M);

  C := TSeriesColumn.Create;
  C.SeriesId := SeriesId;
  C.RecType := TEST_RESULT;
  C.ValueTypeId := 12;
  C.SourceKey := '';
  C.Role := scrResponse;
  C.SortOrder := 4;
  FNotebook.Manager.Save(C);
  FNotebook.Manager.Flush;

  FNotebook.Manager.Clear;

  S := FNotebook.Manager.Find<TSeries>(SeriesId);
  Assert.AreEqual(7, S.ProjectId);
  Assert.AreEqual('Rate calibration Ti', S.Title);
  Assert.AreEqual('Calibrate the deposition rate', S.Purpose);
  Assert.AreEqual(Ord(ssActive), Ord(S.Status));
  Assert.IsTrue(S.TargetFolderId.HasValue);
  Assert.AreEqual(3, S.TargetFolderId.Value);
  Assert.AreEqual(UserId, S.CreatedBy);
  Assert.AreEqual(Created, S.CreatedDate);
  Assert.AreEqual(Ord(scvMcp), Ord(S.CreatedVia));
  Assert.IsFalse(S.ModifiedDate.HasValue);
  Assert.AreEqual(1, S.Version);

  M := FNotebook.Manager.Find<TSeriesMember>
    .Where(Linq['SeriesId'] = SeriesId).UniqueResult;
  Assert.AreEqual(41, M.ItemId);
  Assert.IsTrue(M.SlotId.HasValue);
  Assert.AreEqual(2, M.SlotId.Value);
  Assert.AreEqual(Ord(satFailed), Ord(M.AttemptState));
  Assert.AreEqual('Target arced', M.FailReason);
  Assert.AreEqual(UserId, M.AddedBy);
  Assert.AreEqual(Added, M.AddedDate);

  C := FNotebook.Manager.Find<TSeriesColumn>
    .Where(Linq['SeriesId'] = SeriesId).UniqueResult;
  Assert.AreEqual(Ord(TEST_RESULT), Ord(C.RecType));
  Assert.AreEqual(12, C.ValueTypeId);
  Assert.AreEqual('', C.SourceKey);
  Assert.AreEqual(Ord(scrResponse), Ord(C.Role));
  Assert.AreEqual(4, C.SortOrder);
end;

procedure TSeriesModelTests.PlanEntitiesRoundTrip;
var
  F: TSeriesFactor;
  X: TSeriesFixed;
  S: TSeriesSlot;
  L: TSeriesSlotLevel;
  Added: TDateTime;
  FactorId, SlotId, UserId: Integer;
begin
  UserId := FNotebook.Principal.Id;
  Added := EncodeDateTime(2026, 11, 5, 8, 15, 0, 0);

  F := TSeriesFactor.Create;
  F.SeriesId := 5;
  F.ValueTypeId := 9;
  F.ApprovedMin := 1.5;
  F.ApprovedMax := 4.25;
  F.SortOrder := 2;
  FNotebook.Manager.Save(F);

  X := TSeriesFixed.Create;
  X.SeriesId := 5;
  X.ValueTypeId := 11;
  X.FixedValue := 0.75;
  X.Tol := 0.05;
  FNotebook.Manager.Save(X);

  S := TSeriesSlot.Create;
  S.SeriesId := 5;
  S.Origin := ssoAdded;
  S.AddedBy := UserId;
  S.AddedDate := Added;
  S.Reason := 'Extra point near the optimum';
  FNotebook.Manager.Save(S);
  FNotebook.Manager.Flush;
  FactorId := F.Id;
  SlotId := S.Id;

  L := TSeriesSlotLevel.Create;
  L.SlotId := SlotId;
  L.FactorId := FactorId;
  L.LevelValue := 3.125;
  FNotebook.Manager.Save(L);
  FNotebook.Manager.Flush;

  FNotebook.Manager.Clear;

  F := FNotebook.Manager.Find<TSeriesFactor>(FactorId);
  Assert.AreEqual(5, F.SeriesId);
  Assert.AreEqual(9, F.ValueTypeId);
  Assert.IsFalse(F.RangeMin.HasValue);
  Assert.IsFalse(F.RangeMax.HasValue);
  Assert.IsTrue(F.ApprovedMin.HasValue);
  Assert.AreEqual(1.5, F.ApprovedMin.Value);
  Assert.AreEqual(4.25, F.ApprovedMax.Value);
  Assert.AreEqual(2, F.SortOrder);

  X := FNotebook.Manager.Find<TSeriesFixed>
    .Where(Linq['SeriesId'] = 5).UniqueResult;
  Assert.AreEqual(11, X.ValueTypeId);
  Assert.AreEqual(0.75, X.FixedValue);
  Assert.AreEqual(0.05, X.Tol);

  S := FNotebook.Manager.Find<TSeriesSlot>(SlotId);
  Assert.AreEqual(5, S.SeriesId);
  Assert.AreEqual(Ord(ssoAdded), Ord(S.Origin));
  Assert.AreEqual(UserId, S.AddedBy);
  Assert.AreEqual(Added, S.AddedDate);
  Assert.AreEqual('Extra point near the optimum', S.Reason);

  L := FNotebook.Manager.Find<TSeriesSlotLevel>
    .Where(Linq['SlotId'] = SlotId).UniqueResult;
  Assert.AreEqual(FactorId, L.FactorId);
  Assert.AreEqual(3.125, L.LevelValue);
end;

procedure TSeriesModelTests.DuplicateMemberRejected;
var
  M: TSeriesMember;
  Raised: Boolean;
begin
  M := TSeriesMember.Create;
  M.SeriesId := 1;
  M.ItemId := 5;
  M.AttemptState := satValid;
  FNotebook.Manager.Save(M);
  FNotebook.Manager.Flush;

  M := TSeriesMember.Create;
  M.SeriesId := 1;
  M.ItemId := 5;
  M.AttemptState := satValid;
  Raised := False;
  try
    FNotebook.Manager.Save(M);
    FNotebook.Manager.Flush;
  except
    Raised := True;
  end;
  Assert.IsTrue(Raised, 'duplicate member must raise');
end;

function TSeriesModelTests.NewProject(const ATitle: string): Integer;
var
  Projects: TProjectsModel;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Result := Projects.AddProject(ATitle, '', FNotebook.Principal).Id;
  finally
    Projects.Free;
  end;
end;

function TSeriesModelTests.NewItem(AProjectId, AParent: Integer;
  ALevel: TItemLevel; AAction: TActionType; const ATitle: string): Integer;
var
  Item: TItem;
begin
  Item := TItem.Create;
  Item.Title := ATitle;
  Item.ProjectID := AProjectId;
  Item.Parent := AParent;
  Item.Type_ := TItemType.Measurement;
  Item.Level := ALevel;
  Item.ActionType := AAction;
  Item.CreatedBy := FNotebook.Principal.Id;
  Item.CreatedDate := Now;
  FNotebook.Manager.Save(Item);
  FNotebook.Manager.Flush;
  Result := Item.Id;
end;

procedure TSeriesModelTests.AddValue(AItemId: Integer; AType: TValueType;
  ARec: TRecType; AValue, ATol: Double);
var
  V: unit_Item.TValue;
begin
  V := unit_Item.TValue.Create;
  V.Item := FNotebook.Manager.Find<TItem>(AItemId);
  V.ValueType := AType;
  V.RecType := ARec;
  V.Value := AValue;
  V.Tol := ATol;
  V.CreatedDate := Now;
  FNotebook.Manager.Save(V);
  FNotebook.Manager.Flush;
end;

procedure TSeriesModelTests.SetDeleted(AItemId: Integer);
var
  Item: TItem;
begin
  Item := FNotebook.Manager.Find<TItem>(AItemId);
  Item.IsDeleted := True;
  Item.DeletedDate := Now;
  FNotebook.Manager.Flush;
end;

function TSeriesModelTests.NewSeries: Integer;
begin
  Result := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Series',
    'Purpose', Default(TSeriesPlan), nil);
end;

function Pts(const ALevels: array of Double): TArray<TSeriesPoint>;
var
  I: Integer;
begin
  SetLength(Result, Length(ALevels));
  for I := 0 to High(ALevels) do
    Result[I] := [ALevels[I]];
end;

function Grid2(const AFirst, ASecond: array of Double): TArray<TArray<Double>>;
var
  I: Integer;
begin
  SetLength(Result, 2);
  SetLength(Result[0], Length(AFirst));
  for I := 0 to High(AFirst) do
    Result[0][I] := AFirst[I];
  SetLength(Result[1], Length(ASecond));
  for I := 0 to High(ASecond) do
    Result[1][I] := ASecond[I];
end;

function ResponseOf(AValueTypeId: Integer): TSeriesResponseSpec;
begin
  Result := Default(TSeriesResponseSpec);
  Result.ValueTypeId := AValueTypeId;
end;

function TSeriesModelTests.StdPlan: TSeriesPlan;
begin
  Result := Default(TSeriesPlan);
  SetLength(Result.Factors, 1);
  Result.Factors[0].ValueTypeId := FPower.Id;
  SetLength(Result.Fixed, 1);
  Result.Fixed[0].ValueTypeId := FArFlow.Id;
  Result.Fixed[0].Value := 20;
  Result.Fixed[0].Tol := 1;
  Result.Responses := [ResponseOf(FThickness.Id)];
end;

function TSeriesModelTests.NewSeriesWithPoints(const ALevels: array of Double): Integer;
begin
  Result := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Ti rate',
    'Purpose', StdPlan, Pts(ALevels));
end;

function TSeriesModelTests.NewMcpSeries(const ALevels: array of Double): Integer;
var
  Mcp: TSeriesModel;
begin
  Mcp := TSeriesModel.Create(FNotebook.Manager, FNotebook.AccessPolicy, scvMcp);
  try
    Result := Mcp.CreateSeries(FNotebook.Principal, FProjectId, 'Ti rate',
      'Purpose', StdPlan, Pts(ALevels));
  finally
    Mcp.Free;
  end;
end;

function TSeriesModelTests.SlotAt(ASeriesId: Integer; ALevel: Double): Integer;
var
  Info: TSeriesPlanInfo;
  S: TSeriesSlotInfo;
begin
  Info := FModel.GetPlan(FNotebook.Principal, ASeriesId);
  for S in Info.Slots do
    if Abs(S.Levels[0] - ALevel) < 1e-9 then
      Exit(S.SlotId);
  Result := 0;
  Assert.Fail('no slot at ' + FloatToStr(ALevel));
end;

procedure TSeriesModelTests.LinkItems(ASeriesId: Integer;
  const AItems: array of Integer);
var
  Info: TSeriesPlanInfo;
  I: Integer;
begin
  Info := FModel.GetPlan(FNotebook.Principal, ASeriesId);
  for I := 0 to High(AItems) do
    FModel.LinkToSlot(FNotebook.Principal, ASeriesId, Info.Slots[I].SlotId, AItems[I]);
end;

procedure TSeriesModelTests.ExpectErrorText(const AText: string; const AProc: TProc);
var
  Msg: string;
begin
  Msg := '<no error>';
  try
    AProc();
  except
    on E: ESeriesError do
      Msg := E.Message;
  end;
  Assert.AreEqual(AText, Msg);
end;

function TSeriesModelTests.NewDeposition(const ATitle: string;
  APower, ATol: Double): Integer;
begin
  Result := NewItem(FProjectId, 0, TItemLevel.Proc, nil, ATitle);
  AddValue(Result, FPower, EXP_CONDITION, APower, ATol);
end;

function TSeriesModelTests.MakeDraft(const ATitle: string): TSeriesDepositionDraft;
begin
  Result := Default(TSeriesDepositionDraft);
  Result.Title := ATitle;
  Result.Description := 'Made from the plan';
end;

function TSeriesModelTests.SlotCount(ASeriesId: Integer): Integer;
var
  L: TSeriesSlots;
begin
  L := FNotebook.Manager.Find<TSeriesSlot>
    .Where(Linq['SeriesId'] = ASeriesId).Refreshing.List;
  try
    Result := L.Count;
  finally
    L.Free;
  end;
end;

function TSeriesModelTests.MemberOf(AItemId: Integer): TSeriesMember;
begin
  Result := FNotebook.Manager.Find<TSeriesMember>
    .Where(Linq['ItemId'] = AItemId).Refreshing.UniqueResult;
end;

function TSeriesModelTests.ListStatementsFor(ASeries: Integer): Integer;
var
  Counter: TStatementCounter;
  I, Id, D, M: Integer;
  L: TArray<TSeriesSummary>;
begin
  for I := 1 to ASeries do
  begin
    Id := FModel.CreateSeries(FNotebook.Principal, FProjectId,
      'S' + IntToStr(I), '', StdPlan, Pts([100, 200]));
    D := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'D' + IntToStr(I));
    M := NewItem(FProjectId, D, TItemLevel.Action, FXrr, 'M' + IntToStr(I));
    AddValue(M, FThickness, TEST_RESULT, 50, 0.5);
    LinkItems(Id, [D]);
  end;
  Counter := TStatementCounter.Create;
  try
    L := FModel.ListSeries(FNotebook.Principal, FProjectId);
    Result := Counter.Count;
  finally
    Counter.Free;
  end;
  Assert.IsTrue(Length(L) >= ASeries, 'series listed');
end;

function TSeriesModelTests.AuditCount(AType: Integer; AId: Int64;
  const AText: string): Integer;
var
  L: TAuditLogs;
  A: TAuditLog;
begin
  Result := 0;
  L := FNotebook.Manager.Find<TAuditLog>
    .Where((Linq['EntityType'] = AType) and (Linq['EntityId'] = AId)).Refreshing.List;
  try
    for A in L do
      if (AText = '') or (Pos(AText, A.Description) > 0) then
        Inc(Result);
  finally
    L.Free;
  end;
end;

function TSeriesModelTests.MemberCount(ASeriesId: Integer): Integer;
var
  L: TSeriesMembers;
begin
  L := FNotebook.Manager.Find<TSeriesMember>
    .Where(Linq['SeriesId'] = ASeriesId).Refreshing.List;
  try
    Result := L.Count;
  finally
    L.Free;
  end;
end;

procedure TSeriesModelTests.ExpectSeriesError(const AProc: TProc);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    AProc();
  except
    on ESeriesError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'ESeriesError expected');
end;

function TSeriesModelTests.StatementsFor(AMembers: Integer): Integer;
var
  Counter: TStatementCounter;
  SeriesId, I, D, S, M: Integer;
  Ids: TArray<Integer>;
  Levels: TArray<Double>;
  T: TSeriesTable;
begin
  SetLength(Levels, AMembers);
  for I := 0 to AMembers - 1 do
    Levels[I] := 100 + I;
  SeriesId := NewSeriesWithPoints(Levels);
  SetLength(Ids, AMembers);
  for I := 0 to AMembers - 1 do
  begin
    D := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'D' + IntToStr(I));
    S := NewItem(FProjectId, D, TItemLevel.Item, nil, 'S' + IntToStr(I));
    M := NewItem(FProjectId, S, TItemLevel.Action, FXrr, 'M' + IntToStr(I));
    AddValue(D, FPower, EXP_CONDITION, 100 + I, 0);
    AddValue(M, FThickness, TEST_RESULT, 50 + I, 0.5);
    Ids[I] := D;
  end;
  LinkItems(SeriesId, Ids);
  Counter := TStatementCounter.Create;
  try
    T := FModel.BuildTable(FNotebook.Principal, SeriesId, True);
    Result := Counter.Count;
  finally
    Counter.Free;
  end;
  Assert.AreEqual<NativeInt>(AMembers, Length(T.Rows), 'rows');
end;

procedure TSeriesModelTests.CreateAndList;
var
  Id: Integer;
  L: TArray<TSeriesSummary>;
begin
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId,
    '  Rate calibration Ti ', 'Calibrate', Default(TSeriesPlan), nil);
  L := FModel.ListSeries(FNotebook.Principal, FProjectId);
  Assert.AreEqual<NativeInt>(1, Length(L));
  Assert.AreEqual(Id, L[0].Id);
  Assert.AreEqual('Rate calibration Ti', L[0].Title);
  Assert.AreEqual('Calibrate', L[0].Purpose);
  Assert.AreEqual(Ord(ssActive), Ord(L[0].Status));
  Assert.AreEqual(0, L[0].MemberCount);
end;

procedure TSeriesModelTests.CreateRejectsEmptyTitle;
begin
  ExpectSeriesError(
    procedure
    begin
      FModel.CreateSeries(FNotebook.Principal, FProjectId, '   ', '',
        Default(TSeriesPlan), nil);
    end);
end;

procedure TSeriesModelTests.LinkToSlotRefusesItemAlreadyInSeries;
var
  Id, A: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100), A);
  ExpectErrorText('Item ' + IntToStr(A) + ' is already in this series.',
    procedure begin FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), A); end);
  Assert.AreEqual(1, MemberCount(Id));
end;

procedure TSeriesModelTests.ClosedSeriesRefusesAddAndReopenAllows;
var
  Id, A, Slot: Integer;
begin
  Id := NewSeriesWithPoints([100]);
  Slot := SlotAt(Id, 100);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  FModel.ChangeStatus(FNotebook.Principal, Id, ssClosed);
  ExpectSeriesError(
    procedure
    begin
      FModel.LinkToSlot(FNotebook.Principal, Id, Slot, A);
    end);
  ExpectSeriesError(
    procedure
    begin
      FModel.SetColumnRole(FNotebook.Principal, Id, TEST_RESULT, FThickness.Id,
        '', scrResponse);
    end);
  FModel.ChangeStatus(FNotebook.Principal, Id, ssActive);
  FModel.LinkToSlot(FNotebook.Principal, Id, Slot, A);
  Assert.AreEqual(1, MemberCount(Id));
end;

procedure TSeriesModelTests.ChangeStatusRejectsAbandonedToActive;
var
  Id: Integer;
begin
  Id := NewSeries;
  FModel.ChangeStatus(FNotebook.Principal, Id, ssAbandoned);
  ExpectSeriesError(
    procedure
    begin
      FModel.ChangeStatus(FNotebook.Principal, Id, ssActive);
    end);
end;

procedure TSeriesModelTests.BuildTableReadsGrandchildValues;
var
  Id, D, S, M, Col: Integer;
  T: TSeriesTable;
begin
  Id := NewSeriesWithPoints([200]);
  D := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'Deposition');
  S := NewItem(FProjectId, D, TItemLevel.Item, nil, 'Specimen');
  M := NewItem(FProjectId, S, TItemLevel.Action, FXrr, 'Measurement');
  AddValue(D, FPower, EXP_CONDITION, 200, 0);
  AddValue(M, FThickness, TEST_RESULT, 51.0, 0.5);
  LinkItems(Id, [D]);
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Assert.AreEqual<NativeInt>(1, Length(T.Rows));
  Assert.AreEqual('Deposition', T.Rows[0].Title);
  Col := T.ColumnIndex(EXP_CONDITION, FPower.Id, '');
  Assert.IsTrue(Col >= 0, 'power column');
  Assert.AreEqual<NativeInt>(1, Length(T.Rows[0].Cells[Col].Hits));
  Assert.AreEqual(200.0, T.Rows[0].Cells[Col].Hits[0].Value, 1e-9);
  Col := T.ColumnIndex(TEST_RESULT, FThickness.Id, '');
  Assert.IsTrue(Col >= 0, 'thickness column');
  Assert.AreEqual(51.0, T.Rows[0].Cells[Col].Hits[0].Value, 1e-9);
  Assert.AreEqual(0.5, T.Rows[0].Cells[Col].Hits[0].Tol, 1e-9);
  Assert.AreEqual(M, T.Rows[0].Cells[Col].Hits[0].ItemId);
  Assert.AreEqual(D, T.Rows[0].Cells[Col].Hits[0].RootItemId);
  Assert.IsTrue(T.Rows[0].State = srsMeasured);
  Col := T.ColumnIndex(EXP_CONDITION, FPower.Id, '');
  Assert.IsFalse(T.Rows[0].Cells[Col].Deviation);
  Assert.IsFalse(T.Rows[0].Cells[Col].HasPlanned);
end;

procedure TSeriesModelTests.BuildTableSkipsDeletedDescendant;
var
  Id, D, S, M, Col: Integer;
  T: TSeriesTable;
begin
  Id := NewSeriesWithPoints([200]);
  D := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'Deposition');
  S := NewItem(FProjectId, D, TItemLevel.Item, nil, 'Specimen');
  M := NewItem(FProjectId, S, TItemLevel.Action, FXrr, 'Measurement');
  AddValue(D, FPower, EXP_CONDITION, 200, 0);
  AddValue(M, FThickness, TEST_RESULT, 51.0, 0.5);
  SetDeleted(M);
  LinkItems(Id, [D]);
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Assert.AreEqual<NativeInt>(1, Length(T.Rows));
  Col := T.ColumnIndex(TEST_RESULT, FThickness.Id, '');
  Assert.IsTrue(Col >= 0, 'response column comes from the plan');
  Assert.IsTrue(T.Rows[0].Cells[Col].IsMissing, 'deleted descendant gives no value');
  Assert.IsTrue(T.Rows[0].State = srsDeposited);
  Col := T.ColumnIndex(EXP_CONDITION, FPower.Id, '');
  Assert.IsTrue(Col >= 0);
end;

procedure TSeriesModelTests.BuildTableExcludesRecycledAndForeignMembers;
var
  Id, A, B, C, Other: Integer;
  Item: TItem;
  T: TSeriesTable;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  Other := NewProject('Other');
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  B := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'B');
  C := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'C');
  LinkItems(Id, [A, B, C]);
  SetDeleted(A);
  Item := FNotebook.Manager.Find<TItem>(B);
  Item.ProjectID := Other;
  FNotebook.Manager.Flush;
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Assert.AreEqual<NativeInt>(3, Length(T.Rows));
  Assert.AreEqual(C, T.Rows[2].ItemId);
  Assert.IsTrue(T.Rows[0].State = srsPlanned);
  Assert.IsTrue(T.Rows[1].State = srsPlanned);
  Assert.AreEqual(0, T.Rows[0].ItemId);
  Assert.AreEqual(0, T.Rows[1].ItemId);
  Assert.AreEqual<NativeInt>(2, Length(T.Excluded));
  Assert.IsTrue(((T.Excluded[0] = A) and (T.Excluded[1] = B))
    or ((T.Excluded[0] = B) and (T.Excluded[1] = A)));
end;

procedure TSeriesModelTests.UnlinkAcceptsExcludedItem;
var
  Id, A, B, C, Other: Integer;
  Item: TItem;
  T: TSeriesTable;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  Other := NewProject('Other');
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  B := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'B');
  C := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'C');
  LinkItems(Id, [A, B, C]);
  SetDeleted(A);
  Item := FNotebook.Manager.Find<TItem>(B);
  Item.ProjectID := Other;
  FNotebook.Manager.Flush;
  FModel.Unlink(FNotebook.Principal, Id, A);
  FModel.Unlink(FNotebook.Principal, Id, B);
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Assert.AreEqual<NativeInt>(0, Length(T.Excluded));
  Assert.AreEqual<NativeInt>(3, Length(T.Rows));
  Assert.AreEqual(0, T.Rows[0].ItemId);
  Assert.AreEqual(0, T.Rows[1].ItemId);
  Assert.AreEqual(C, T.Rows[2].ItemId);
  Assert.AreEqual(1, MemberCount(Id));
end;

procedure TSeriesModelTests.MemberCountSkipsExcludedItems;
var
  Id, A, B, C, Other: Integer;
  Item: TItem;
  L: TArray<TSeriesSummary>;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  Other := NewProject('Other');
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  B := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'B');
  C := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'C');
  LinkItems(Id, [A, B, C]);
  SetDeleted(A);
  Item := FNotebook.Manager.Find<TItem>(B);
  Item.ProjectID := Other;
  FNotebook.Manager.Flush;
  L := FModel.ListSeries(FNotebook.Principal, FProjectId);
  Assert.AreEqual(1, L[0].MemberCount);
  Assert.AreEqual(1, FModel.Get(FNotebook.Principal, Id).MemberCount);
  Assert.AreEqual(FNotebook.Principal.Id, L[0].CreatedBy);
end;

procedure TSeriesModelTests.BuildTableKeysItemWithoutActionType;
var
  Id, D, S, Col: Integer;
  T: TSeriesTable;
begin
  Id := NewSeriesWithPoints([200]);
  D := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'Deposition');
  S := NewItem(FProjectId, D, TItemLevel.Item, nil, 'Specimen');
  AddValue(S, FThickness, TEST_RESULT, 12, 0);
  LinkItems(Id, [D]);
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Col := T.ColumnIndex(TEST_RESULT, FThickness.Id, '');
  Assert.IsTrue(Col >= 0);
  Assert.AreEqual(SeriesLevelKey(TItemLevel.Item),
    T.Rows[0].Cells[Col].Hits[0].SourceKey);
end;

procedure TSeriesModelTests.BuildTableStatementCountIndependentOfMembers;
var
  Small, Large: Integer;
begin
  Small := StatementsFor(2);
  Large := StatementsFor(20);
  Assert.AreEqual(Small, Large);
end;

procedure TSeriesModelTests.CreateWritesSeriesAudit;
var
  Id: Integer;
begin
  Id := NewSeries;
  Assert.AreEqual(1, AuditCount(Ord(aetSeries), Id, ''));
end;

procedure TSeriesModelTests.PurgeRemovesMembershipWithAudit;
var
  Id, A: Integer;
  Bin: TRecycleBinModel;
begin
  Id := NewSeriesWithPoints([200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  LinkItems(Id, [A]);
  SetDeleted(A);
  Bin := TRecycleBinModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Bin.PermanentlyDelete(FNotebook.Manager.Find<TItem>(A),
      FNotebook.Principal.Id));
  finally
    Bin.Free;
  end;
  Assert.AreEqual(0, MemberCount(Id));
  Assert.AreEqual(1, AuditCount(Ord(aetSeries), Id,
    'Purged item ' + IntToStr(A) + ' from the recycle bin; removed from the series.'));
end;

procedure TSeriesModelTests.MemberAndColumnWritesBumpVersion;
var
  Id, A: Integer;
  V: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  V := FNotebook.Manager.Find<TSeries>(Id).Version;
  LinkItems(Id, [A]);
  Assert.AreEqual(V + 1, FNotebook.Manager.Find<TSeries>(Id).Version, 'link');
  ExpectSeriesError(
    procedure
    begin
      FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), A);
    end);
  Assert.AreEqual(V + 1, FNotebook.Manager.Find<TSeries>(Id).Version, 'refused link');
  FModel.SetColumnRole(FNotebook.Principal, Id, TEST_RESULT, FThickness.Id, '',
    scrResponse);
  Assert.AreEqual(V + 2, FNotebook.Manager.Find<TSeries>(Id).Version, 'role');
  FModel.Unlink(FNotebook.Principal, Id, A);
  Assert.AreEqual(V + 3, FNotebook.Manager.Find<TSeries>(Id).Version, 'unlink');
  FModel.AddPoints(FNotebook.Principal, Id, Pts([300]), '');
  Assert.AreEqual(V + 4, FNotebook.Manager.Find<TSeries>(Id).Version, 'add point');
  FModel.MakeDeposition(FNotebook.Principal, Id, SlotAt(Id, 300), MakeDraft('Made'));
  Assert.AreEqual(V + 5, FNotebook.Manager.Find<TSeries>(Id).Version, 'make');
end;

procedure TSeriesModelTests.OnlyAuthorClosesAndReopens;
var
  Id: Integer;
  S: TSeries;
begin
  Id := NewSeries;
  S := FNotebook.Manager.Find<TSeries>(Id);
  S.CreatedBy := FNotebook.Principal.Id + 1000;
  FNotebook.Manager.Flush;
  ExpectSeriesError(
    procedure
    begin
      FModel.ChangeStatus(FNotebook.Principal, Id, ssClosed);
    end);
  S.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Flush;
  FModel.ChangeStatus(FNotebook.Principal, Id, ssClosed);
  S.CreatedBy := FNotebook.Principal.Id + 1000;
  FNotebook.Manager.Flush;
  ExpectSeriesError(
    procedure
    begin
      FModel.ChangeStatus(FNotebook.Principal, Id, ssActive);
    end);
  S.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Flush;
  FModel.ChangeStatus(FNotebook.Principal, Id, ssActive);
end;

procedure TSeriesModelTests.CreateWithPlanMakesPlannedPoints;
var
  Id: Integer;
  Info: TSeriesPlanInfo;
  S: TSeries;
  C: TSeriesColumn;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  S := FNotebook.Manager.Find<TSeries>(Id);
  Assert.AreEqual(Ord(ssActive), Ord(S.Status));
  Assert.AreEqual(Ord(scvDesktop), Ord(S.CreatedVia));
  Info := FModel.GetPlan(FNotebook.Principal, Id);
  Assert.AreEqual<NativeInt>(3, Length(Info.Slots));
  Assert.AreEqual(100.0, Info.Slots[0].Levels[0], 1e-9);
  Assert.AreEqual(200.0, Info.Slots[1].Levels[0], 1e-9);
  Assert.AreEqual(300.0, Info.Slots[2].Levels[0], 1e-9);
  Assert.AreEqual(Ord(ssoPlanned), Ord(Info.Slots[1].Origin));
  Assert.AreEqual(0, Info.Slots[1].ValidItemId);
  Assert.AreEqual<NativeInt>(1, Length(Info.Plan.Factors));
  Assert.AreEqual(FPower.Id, Info.Plan.Factors[0].ValueTypeId);
  Assert.IsFalse(Info.Plan.Factors[0].RangeMin.HasValue);
  Assert.AreEqual<NativeInt>(1, Length(Info.Plan.Fixed));
  Assert.AreEqual(FArFlow.Id, Info.Plan.Fixed[0].ValueTypeId);
  Assert.AreEqual(20.0, Info.Plan.Fixed[0].Value, 1e-9);
  Assert.AreEqual(1.0, Info.Plan.Fixed[0].Tol, 1e-9);
  Assert.AreEqual<NativeInt>(1, Length(Info.Plan.Responses));
  Assert.AreEqual(FThickness.Id, Info.Plan.Responses[0].ValueTypeId);
  C := FNotebook.Manager.Find<TSeriesColumn>
    .Where((Linq['SeriesId'] = Id) and (Linq['ValueTypeId'] = FThickness.Id)).UniqueResult;
  Assert.AreEqual(Ord(scrResponse), Ord(C.Role));
  Assert.AreEqual(Ord(TEST_RESULT), Ord(C.RecType));
  Assert.AreEqual('', C.SourceKey);
  Assert.AreEqual(1, AuditCount(Ord(aetSeries), Id, ''));
end;

procedure TSeriesModelTests.McpCreateIsDraftAndCannotStart;
var
  Id: Integer;
  Mcp: TSeriesModel;
  S: TSeries;
begin
  Id := NewMcpSeries([100, 200]);
  S := FNotebook.Manager.Find<TSeries>(Id);
  Assert.AreEqual(Ord(ssDraft), Ord(S.Status));
  Assert.AreEqual(Ord(scvMcp), Ord(S.CreatedVia));
  Assert.AreEqual(Ord(ssoPlanned),
    Ord(FModel.GetPlan(FNotebook.Principal, Id).Slots[0].Origin));
  Mcp := TSeriesModel.Create(FNotebook.Manager, FNotebook.AccessPolicy, scvMcp);
  try
    ExpectErrorText('A series is started in the desktop.',
      procedure
      begin
        Mcp.Start(FNotebook.Principal, Id);
      end);
  finally
    Mcp.Free;
  end;
  Assert.AreEqual(Ord(ssDraft), Ord(FNotebook.Manager.Find<TSeries>(Id).Status));
  FModel.Start(FNotebook.Principal, Id);
  Assert.AreEqual(Ord(ssActive), Ord(FNotebook.Manager.Find<TSeries>(Id).Status));
  ExpectSeriesError(
    procedure
    begin
      FModel.Start(FNotebook.Principal, Id);
    end);
end;

procedure TSeriesModelTests.SavePlanRefusesFactorChangeWithPoints;
var
  Id: Integer;
  Plan: TSeriesPlan;
  Empty: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Plan := StdPlan;
  Plan.Factors[0].ValueTypeId := FPressure.Id;
  ExpectErrorText('Remove all points before you change the factors.',
    procedure
    begin
      FModel.SavePlan(FNotebook.Principal, Id, Plan);
    end);
  Assert.AreEqual(FPower.Id,
    FModel.GetPlan(FNotebook.Principal, Id).Plan.Factors[0].ValueTypeId);
  Empty := NewSeriesWithPoints([]);
  FModel.SavePlan(FNotebook.Principal, Empty, Plan);
  Assert.AreEqual(FPressure.Id,
    FModel.GetPlan(FNotebook.Principal, Empty).Plan.Factors[0].ValueTypeId);
end;

procedure TSeriesModelTests.SavePlanRefusesRangeExcludingPoint;
var
  Id: Integer;
  Plan: TSeriesPlan;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  Plan := StdPlan;
  Plan.Factors[0].RangeMin := 50.0;
  Plan.Factors[0].RangeMax := 250.0;
  ExpectErrorText('Point 300 W is outside the new range.',
    procedure
    begin
      FModel.SavePlan(FNotebook.Principal, Id, Plan);
    end);
  Plan.Factors[0].RangeMax := 300.0;
  FModel.SavePlan(FNotebook.Principal, Id, Plan);
  Assert.AreEqual(300.0,
    FModel.GetPlan(FNotebook.Principal, Id).Plan.Factors[0].RangeMax.Value, 1e-9);
  Assert.AreEqual<NativeInt>(3, Length(FModel.GetPlan(FNotebook.Principal, Id).Slots));
end;

procedure TSeriesModelTests.UpdatePlanAndPointsRefusedChangesNothing;
var
  Id, Before, Audits: Integer;
  Plan: TSeriesPlan;
  Roles: string;

  function RoleText: string;
  var
    L: TSeriesColumns;
    C: TSeriesColumn;
  begin
    Result := '';
    L := FNotebook.Manager.Find<TSeriesColumn>
      .Where(Linq['SeriesId'] = Id).OrderBy('Id').Refreshing.List;
    try
      for C in L do
        Result := Result + Format('%d:%d;', [C.ValueTypeId, Ord(C.Role)]);
    finally
      L.Free;
    end;
  end;
begin
  Id := NewSeriesWithPoints([100, 200]);
  FModel.SetColumnRole(FNotebook.Principal, Id, TEST_RESULT, FPressure.Id, '', scrHidden);
  Before := FNotebook.Manager.Find<TSeries>(Id).Version;
  Audits := AuditCount(Ord(aetSeries), Id, '');
  Roles := RoleText;
  Plan := StdPlan;
  Plan.Factors[0].RangeMin := 50.0;
  Plan.Factors[0].RangeMax := 400.0;
  Plan.Responses := [ResponseOf(FThickness.Id), ResponseOf(FPressure.Id)];
  Plan.Fixed[0].Value := 25;
  ExpectSeriesError(
    procedure
    begin
      FModel.UpdatePlanAndPoints(FNotebook.Principal, Id, True, 'Changed', True,
        Plan, Pts([999]), 'Why');
    end);
  Assert.AreEqual(Before, FNotebook.Manager.Find<TSeries>(Id).Version, 'version');
  Assert.AreEqual(Audits, AuditCount(Ord(aetSeries), Id, ''), 'audit rows');
  Assert.AreEqual(Roles, RoleText, 'column roles');
  Assert.IsFalse(FModel.GetPlan(FNotebook.Principal, Id).Plan.Factors[0].RangeMax.HasValue,
    'range');
  Assert.AreEqual(20.0, FModel.GetPlan(FNotebook.Principal, Id).Plan.Fixed[0].Value, 1e-9);
  Assert.AreEqual<NativeInt>(1, Length(FModel.GetPlan(FNotebook.Principal, Id).Plan.Responses));
  Assert.AreEqual<NativeInt>(2, Length(FModel.GetPlan(FNotebook.Principal, Id).Slots));
  Assert.AreEqual('Purpose', FNotebook.Manager.Find<TSeries>(Id).Purpose, 'purpose');
end;

procedure TSeriesModelTests.UpdatePlanAndPointsChangesEverythingOnce;
var
  Id, Before, Audits: Integer;
  Plan: TSeriesPlan;
  Info: TSeriesPlanInfo;
  Added: TArray<Integer>;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Before := FNotebook.Manager.Find<TSeries>(Id).Version;
  Audits := AuditCount(Ord(aetSeries), Id, '');
  Plan := StdPlan;
  Plan.Factors[0].RangeMin := 50.0;
  Plan.Factors[0].RangeMax := 400.0;
  Plan.Responses := [ResponseOf(FThickness.Id), ResponseOf(FPressure.Id)];
  Plan.Fixed[0].Value := 25;
  Added := FModel.UpdatePlanAndPoints(FNotebook.Principal, Id, True, 'Changed', True,
    Plan, Pts([300]), 'Extend');
  Assert.AreEqual<NativeInt>(1, Length(Added));
  Info := FModel.GetPlan(FNotebook.Principal, Id);
  Assert.AreEqual(400.0, Info.Plan.Factors[0].RangeMax.Value, 1e-9);
  Assert.AreEqual(25.0, Info.Plan.Fixed[0].Value, 1e-9);
  Assert.AreEqual<NativeInt>(2, Length(Info.Plan.Responses));
  Assert.AreEqual<NativeInt>(3, Length(Info.Slots));
  Assert.AreEqual('Changed', FNotebook.Manager.Find<TSeries>(Id).Purpose);
  Assert.AreEqual(Before + 1, FNotebook.Manager.Find<TSeries>(Id).Version, 'one bump');
  Assert.AreEqual(Audits + 1, AuditCount(Ord(aetSeries), Id, ''), 'one audit row');
end;

procedure TSeriesModelTests.SavePlanDropsResponseBackToShown;
var
  Id: Integer;
  Plan: TSeriesPlan;
  C: TSeriesColumn;
begin
  Id := NewSeriesWithPoints([100]);
  Plan := StdPlan;
  Plan.Responses := nil;
  FModel.SavePlan(FNotebook.Principal, Id, Plan);
  C := FNotebook.Manager.Find<TSeriesColumn>
    .Where((Linq['SeriesId'] = Id) and (Linq['ValueTypeId'] = FThickness.Id))
    .Refreshing.UniqueResult;
  Assert.AreEqual(Ord(scrShown), Ord(C.Role));
  Assert.AreEqual<NativeInt>(0, Length(FModel.GetPlan(FNotebook.Principal, Id).Plan.Responses));
end;

procedure TSeriesModelTests.SetColumnRoleKeepsOtherPrefs;
var
  Id: Integer;
  L: TSeriesColumns;
  C: TSeriesColumn;
  Roles: array[0..1] of Integer;
begin
  Id := NewSeries;
  FModel.SetColumnRole(FNotebook.Principal, Id, TEST_RESULT, FThickness.Id, '', scrResponse);
  FModel.SetColumnRole(FNotebook.Principal, Id, EXP_CONDITION, FPower.Id, '', scrHidden);
  FModel.SetColumnRole(FNotebook.Principal, Id, TEST_RESULT, FThickness.Id, '', scrShown);
  L := FNotebook.Manager.Find<TSeriesColumn>
    .Where(Linq['SeriesId'] = Id).Refreshing.List;
  try
    Assert.AreEqual<NativeInt>(2, L.Count);
    Roles[0] := -1;
    Roles[1] := -1;
    for C in L do
      if C.ValueTypeId = FThickness.Id then
        Roles[0] := Ord(C.Role)
      else if C.ValueTypeId = FPower.Id then
        Roles[1] := Ord(C.Role);
  finally
    L.Free;
  end;
  Assert.AreEqual(Ord(scrShown), Roles[0]);
  Assert.AreEqual(Ord(scrHidden), Roles[1]);
end;

procedure TSeriesModelTests.AddPointRefusesDuplicateAndOutsideRange;
var
  Id: Integer;
  Plan: TSeriesPlan;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  Plan := StdPlan;
  Plan.Factors[0].RangeMin := 50.0;
  Plan.Factors[0].RangeMax := 400.0;
  FModel.SavePlan(FNotebook.Principal, Id, Plan);
  ExpectErrorText('Point 200 W already exists.',
    procedure
    begin
      FModel.AddPoints(FNotebook.Principal, Id, Pts([200]), '');
    end);
  ExpectSeriesError(
    procedure
    begin
      FModel.AddPoints(FNotebook.Principal, Id, Pts([200.0000000001]), '');
    end);
  ExpectErrorText('Point 500 W is outside the range.',
    procedure
    begin
      FModel.AddPoints(FNotebook.Principal, Id, Pts([350, 500]), '');
    end);
  Assert.AreEqual(3, SlotCount(Id), 'whole call refused');
  Assert.AreEqual<NativeInt>(1,
    Length(FModel.AddPoints(FNotebook.Principal, Id, Pts([350]), '')));
  Assert.AreEqual(4, SlotCount(Id));
end;

procedure TSeriesModelTests.AddPointWhileActiveIsAdded;
var
  Id: Integer;
  Ids: TArray<Integer>;
  Slot: TSeriesSlot;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Ids := FModel.AddPoints(FNotebook.Principal, Id, Pts([400]), 'Near the optimum');
  Assert.AreEqual<NativeInt>(1, Length(Ids));
  Slot := FNotebook.Manager.Find<TSeriesSlot>(Ids[0]);
  Assert.AreEqual(Ord(ssoAdded), Ord(Slot.Origin));
  Assert.AreEqual('Near the optimum', Slot.Reason);
  Assert.AreEqual(FNotebook.Principal.Id, Slot.AddedBy);
  Assert.AreEqual(Ord(ssoPlanned),
    Ord(FModel.GetPlan(FNotebook.Principal, Id).Slots[0].Origin));
end;

procedure TSeriesModelTests.AddPointWhileDraftIsPlanned;
var
  Id: Integer;
  Ids: TArray<Integer>;
begin
  Id := NewMcpSeries([100]);
  Ids := FModel.AddPoints(FNotebook.Principal, Id, Pts([400]), '');
  Assert.AreEqual(Ord(ssoPlanned),
    Ord(FNotebook.Manager.Find<TSeriesSlot>(Ids[0]).Origin));
end;

procedure TSeriesModelTests.FillGridAddsMissingCombinations;
var
  Id: Integer;
  Plan: TSeriesPlan;
  Pt: TArray<TSeriesPoint>;
  Ids: TArray<Integer>;
begin
  Plan := StdPlan;
  SetLength(Plan.Factors, 2);
  Plan.Factors[1].ValueTypeId := FPressure.Id;
  SetLength(Pt, 1);
  Pt[0] := [100, 5];
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Grid', '', Plan, Pt);
  Ids := FModel.FillGrid(FNotebook.Principal, Id, Grid2([100, 200], [5, 10]));
  Assert.AreEqual<NativeInt>(3, Length(Ids));
  Assert.AreEqual(4, SlotCount(Id));
  Assert.AreEqual<NativeInt>(0,
    Length(FModel.FillGrid(FNotebook.Principal, Id, Grid2([100, 200], [5, 10]))));
  Assert.AreEqual(4, SlotCount(Id));
end;

procedure TSeriesModelTests.RemovePointRefusedWithMember;
var
  Id, A, Slot: Integer;
  Levels: TList<TSeriesSlotLevel>;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  LinkItems(Id, [A]);
  Slot := SlotAt(Id, 100);
  ExpectErrorText('Unlink the depositions of this point first.',
    procedure
    begin
      FModel.RemovePoint(FNotebook.Principal, Id, Slot);
    end);
  Assert.AreEqual(2, SlotCount(Id));
  FModel.Unlink(FNotebook.Principal, Id, A);
  FModel.RemovePoint(FNotebook.Principal, Id, Slot);
  Assert.AreEqual(1, SlotCount(Id));
  Levels := FNotebook.Manager.Find<TSeriesSlotLevel>
    .Where(Linq['SlotId'] = Slot).Refreshing.List;
  try
    Assert.AreEqual<NativeInt>(0, Levels.Count);
  finally
    Levels.Free;
  end;
end;

procedure TSeriesModelTests.DefaultDepositionTitleFormatsLevels;
var
  Id: Integer;
  Plan: TSeriesPlan;
  Pt: TArray<TSeriesPoint>;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Assert.AreEqual('Ti rate 200 W',
    FModel.DefaultDepositionTitle(FNotebook.Principal, Id, SlotAt(Id, 200)));
  Plan := StdPlan;
  SetLength(Plan.Factors, 2);
  Plan.Factors[1].ValueTypeId := FPressure.Id;
  SetLength(Pt, 1);
  Pt[0] := [100.5, 5];
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Grid', '', Plan, Pt);
  Assert.AreEqual('Grid 100.5 W, 5 mTorr',
    FModel.DefaultDepositionTitle(FNotebook.Principal, Id,
      FModel.GetPlan(FNotebook.Principal, Id).Slots[0].SlotId));
end;

procedure TSeriesModelTests.DepositionDefaultsFollowLastMember;
var
  Id, A, B, At, Eq: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  FModel.DepositionDefaults(FNotebook.Principal, Id, At, Eq);
  Assert.AreEqual(0, At);
  Assert.AreEqual(0, Eq);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, FXrr, 'A');
  B := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'B');
  LinkItems(Id, [A]);
  FModel.DepositionDefaults(FNotebook.Principal, Id, At, Eq);
  Assert.AreEqual(FXrr.Id, At);
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), B);
  FModel.DepositionDefaults(FNotebook.Principal, Id, At, Eq);
  Assert.AreEqual(0, At, 'most recent member has no action type');
end;

procedure TSeriesModelTests.MakeDepositionWritesPlannedValuesAndMember;
var
  Id, ItemId, Folder, Slot: Integer;
  Plan: TSeriesPlan;
  Projects: TProjectsModel;
  Folders: TList<TFolder>;
  Item: TItem;
  V: unit_Item.TValue;
  Member: TSeriesMember;
  Version, SawPower, SawFlow: Integer;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Projects.AddFolder('Target', '', FProjectId, 0);
  finally
    Projects.Free;
  end;
  Folders := FNotebook.Manager.Find<TFolder>.List;
  try
    Assert.AreEqual<NativeInt>(1, Folders.Count);
    Folder := Folders[0].Id;
  finally
    Folders.Free;
  end;
  Plan := StdPlan;
  Plan.TargetFolderId := Folder;
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Ti rate', '', Plan,
    Pts([100, 200]));
  Assert.AreEqual(Folder,
    FModel.GetPlan(FNotebook.Principal, Id).Plan.TargetFolderId);
  Slot := SlotAt(Id, 200);
  Version := FNotebook.Manager.Find<TSeries>(Id).Version;
  ItemId := FModel.MakeDeposition(FNotebook.Principal, Id, Slot,
    MakeDraft('Ti rate 200 W'));
  Item := FNotebook.Manager.Find<TItem>(ItemId);
  Assert.IsNotNull(Item);
  Assert.AreEqual('Ti rate 200 W', Item.Title);
  Assert.AreEqual('Made from the plan', Item.Description);
  Assert.AreEqual(Ord(TItemLevel.Proc), Ord(Item.Level));
  Assert.AreEqual(Ord(TItemType.Synthesis), Ord(Item.Type_));
  Assert.AreEqual(FProjectId, Item.ProjectID);
  Assert.AreEqual(Folder, Item.FolderID);
  Assert.AreEqual(0, Item.Parent);
  Assert.AreEqual(FNotebook.Principal.Id, Item.CreatedBy.Value);
  Assert.AreEqual<NativeInt>(2, Item.Values.Count);
  SawPower := 0;
  SawFlow := 0;
  for V in Item.Values do
  begin
    Assert.AreEqual(Ord(EXP_CONDITION), Ord(V.RecType));
    Assert.AreEqual(Ord(vskPlanned), Ord(V.EffectiveSourceKind));
    Assert.AreEqual('Planned value from series Ti rate', V.Description);
    Assert.AreEqual('Planned value from series Ti rate', V.SourceNote);
    if V.ValueType.Id = FPower.Id then
    begin
      Inc(SawPower);
      Assert.AreEqual(200.0, V.Value, 1e-9);
      Assert.AreEqual(0.0, V.Tol, 1e-9);
    end
    else if V.ValueType.Id = FArFlow.Id then
    begin
      Inc(SawFlow);
      Assert.AreEqual(20.0, V.Value, 1e-9);
      Assert.AreEqual(1.0, V.Tol, 1e-9);
    end;
  end;
  Assert.AreEqual(1, SawPower);
  Assert.AreEqual(1, SawFlow);
  Member := MemberOf(ItemId);
  Assert.IsTrue(Member.SlotId.HasValue);
  Assert.AreEqual(Slot, Member.SlotId.Value);
  Assert.AreEqual(Ord(satValid), Ord(Member.AttemptState));
  Assert.AreEqual(ItemId, FModel.GetPlan(FNotebook.Principal, Id).Slots[1].ValidItemId);
  Assert.AreEqual(Version + 1, FNotebook.Manager.Find<TSeries>(Id).Version);
  Assert.AreEqual(1, AuditCount(Ord(aetItem), ItemId, ''));
  Assert.AreEqual(2, AuditCount(Ord(aetSeries), Id, ''));
end;

procedure TSeriesModelTests.EntryLabelsNamePlanValuesAndColumns;
var
  Id, ItemId: Integer;
  Plan: TSeriesPlan;
  Info: TSeriesPlanInfo;
  Item: TItem;
  V: unit_Item.TValue;
  T: TSeriesTable;
begin
  Plan := StdPlan;
  Plan.Factors[0].EntryLabel := 'Mo layer';
  Plan.Fixed[0].EntryLabel := 'Mo target';
  Plan.Responses[0].EntryLabel := 'Total stack';
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Ti rate', '', Plan,
    Pts([100, 200]));
  Info := FModel.GetPlan(FNotebook.Principal, Id);
  Assert.AreEqual('Mo layer', Info.Plan.Factors[0].EntryLabel);
  Assert.AreEqual('Mo target', Info.Plan.Fixed[0].EntryLabel);
  Assert.AreEqual('Total stack', Info.Plan.Responses[0].EntryLabel);

  ItemId := FModel.MakeDeposition(FNotebook.Principal, Id, SlotAt(Id, 100),
    MakeDraft('Ti rate 100 W'));
  Item := FNotebook.Manager.Find<TItem>(ItemId);
  for V in Item.Values do
  begin
    Assert.AreEqual('Planned value from series Ti rate', V.SourceNote);
    if V.ValueType.Id = FPower.Id then
      Assert.AreEqual('Mo layer', V.Description)
    else
      Assert.AreEqual('Mo target', V.Description);
  end;

  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Assert.AreEqual('Power (Mo layer)',
    T.Columns[T.ColumnIndex(EXP_CONDITION, FPower.Id, '')].Caption);
  Assert.AreEqual('Ar flow (Mo target)',
    T.Columns[T.ColumnIndex(EXP_CONDITION, FArFlow.Id, '')].Caption);
  Assert.AreEqual('Thickness (Total stack)',
    T.Columns[T.ColumnIndex(TEST_RESULT, FThickness.Id, '')].Caption);

  Plan.Factors[0].EntryLabel := 'Ti layer';
  FModel.SavePlan(FNotebook.Principal, Id, Plan);
  Info := FModel.GetPlan(FNotebook.Principal, Id);
  Assert.AreEqual('Ti layer', Info.Plan.Factors[0].EntryLabel,
    'a label changes while the series has points');
  Assert.AreEqual('Total stack', Info.Plan.Responses[0].EntryLabel);

  Plan.Factors[0].EntryLabel := StringOfChar('x', 101);
  ExpectSeriesError(
    procedure
    begin
      FModel.SavePlan(FNotebook.Principal, Id, Plan);
    end);
end;

procedure TSeriesModelTests.MakeRefusedWhenSlotHasValidMember;
var
  Id, Slot, Before: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Slot := SlotAt(Id, 200);
  FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('First'));
  Before := MemberCount(Id);
  ExpectSeriesError(
    procedure
    begin
      FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('Second'));
    end);
  Assert.AreEqual(Before, MemberCount(Id));
end;

procedure TSeriesModelTests.MakeRefusedWhileDraft;
var
  Id: Integer;
begin
  Id := NewMcpSeries([100]);
  ExpectSeriesError(
    procedure
    begin
      FModel.MakeDeposition(FNotebook.Principal, Id, SlotAt(Id, 100), MakeDraft('X'));
    end);
  Assert.AreEqual(0, MemberCount(Id));
end;

procedure TSeriesModelTests.LinkRefusedWhenSlotHasValidMember;
var
  Id, A, B: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  B := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'B');
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), A);
  ExpectSeriesError(
    procedure
    begin
      FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), B);
    end);
  Assert.AreEqual(1, MemberCount(Id));
end;

procedure TSeriesModelTests.LinkRefusedWhenItemAlreadyInSeries;
var
  Id, A, B: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  B := NewItem(FProjectId, A, TItemLevel.Item, nil, 'B');
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), A);
  ExpectSeriesError(
    procedure
    begin
      FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100), A);
    end);
  ExpectSeriesError(
    procedure
    begin
      FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100), B);
    end);
  Assert.AreEqual(1, MemberCount(Id));
end;

procedure TSeriesModelTests.LinkByValuesMatchesWithinTolerance;
var
  Id, A, B, C: Integer;
  Lines: TArray<TSeriesLinkLine>;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  A := NewDeposition('A', 199.97, 0.1);
  B := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'B');
  AddValue(NewItem(FProjectId, B, TItemLevel.Action, FXrr, 'B child'),
    FPower, EXP_CONDITION, 100, 0);
  C := NewDeposition('C', 205, 0.1);
  Lines := FModel.PreviewLinkByValues(FNotebook.Principal, Id, [A, B, C]);
  Assert.AreEqual<NativeInt>(3, Length(Lines));
  Assert.AreEqual(Ord(sloLinked), Ord(Lines[0].Outcome));
  Assert.AreEqual(SlotAt(Id, 200), Lines[0].SlotId);
  Assert.AreEqual(199.97, Lines[0].Levels[0], 1e-9);
  Assert.AreEqual(Ord(sloLinked), Ord(Lines[1].Outcome));
  Assert.AreEqual(SlotAt(Id, 100), Lines[1].SlotId);
  Assert.AreEqual(Ord(sloNewPoint), Ord(Lines[2].Outcome));
  Assert.AreEqual(0, MemberCount(Id), 'preview writes nothing');
  Lines := FModel.LinkByValues(FNotebook.Principal, Id, [A, B, C], False);
  Assert.AreEqual(Ord(sloLinked), Ord(Lines[0].Outcome));
  Assert.AreEqual(Ord(sloNewPoint), Ord(Lines[2].Outcome));
  Assert.AreEqual(2, MemberCount(Id));
  Assert.AreEqual(SlotAt(Id, 200), MemberOf(A).SlotId.Value);
  Assert.AreEqual(SlotAt(Id, 100), MemberOf(B).SlotId.Value);
  Assert.AreEqual(3, SlotCount(Id));
end;

procedure TSeriesModelTests.LinkByValuesReportsNoValueAndAmbiguous;
var
  Id, A, B, C, D, E: Integer;
  Lines: TArray<TSeriesLinkLine>;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  B := NewDeposition('B', 100, 0);
  AddValue(B, FPower, EXP_CONDITION, 200, 0);
  C := NewItem(FProjectId, A, TItemLevel.Item, nil, 'C');
  D := NewDeposition('D', 100, 0);
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100), D);
  E := NewDeposition('E', 100, 0);
  Lines := FModel.LinkByValues(FNotebook.Principal, Id, [A, B, C, D, E], True);
  Assert.AreEqual(Ord(sloNoValue), Ord(Lines[0].Outcome));
  Assert.AreEqual(Ord(sloAmbiguousValue), Ord(Lines[1].Outcome));
  Assert.AreEqual(Ord(sloNotRoot), Ord(Lines[2].Outcome));
  Assert.AreEqual(Ord(sloAlreadyMember), Ord(Lines[3].Outcome));
  Assert.AreEqual(Ord(sloSlotTaken), Ord(Lines[4].Outcome));
  Assert.AreEqual(1, MemberCount(Id));
  Assert.AreEqual(2, SlotCount(Id));
end;

procedure TSeriesModelTests.LinkByValuesCreatesMissingOnlyWhenAsked;
var
  Id, A, B: Integer;
  Plan: TSeriesPlan;
  Lines: TArray<TSeriesLinkLine>;
  Slot: TSeriesSlot;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Plan := StdPlan;
  Plan.Factors[0].RangeMin := 50.0;
  Plan.Factors[0].RangeMax := 400.0;
  FModel.SavePlan(FNotebook.Principal, Id, Plan);
  A := NewDeposition('A', 250, 0);
  B := NewDeposition('B', 500, 0);
  Lines := FModel.LinkByValues(FNotebook.Principal, Id, [A, B], False);
  Assert.AreEqual(Ord(sloNewPoint), Ord(Lines[0].Outcome));
  Assert.AreEqual(Ord(sloOutsideRange), Ord(Lines[1].Outcome));
  Assert.AreEqual(2, SlotCount(Id));
  Assert.AreEqual(0, MemberCount(Id));
  Lines := FModel.LinkByValues(FNotebook.Principal, Id, [A, B], True);
  Assert.AreEqual(Ord(sloNewPoint), Ord(Lines[0].Outcome));
  Assert.IsTrue(Lines[0].SlotId > 0);
  Assert.AreEqual(Ord(sloOutsideRange), Ord(Lines[1].Outcome));
  Assert.AreEqual(3, SlotCount(Id));
  Assert.AreEqual(1, MemberCount(Id));
  Slot := FNotebook.Manager.Find<TSeriesSlot>(Lines[0].SlotId);
  Assert.AreEqual(Ord(ssoAdded), Ord(Slot.Origin));
  Assert.AreEqual('Linked from existing deposition', Slot.Reason);
  Assert.AreEqual(Lines[0].SlotId, MemberOf(A).SlotId.Value);
end;

procedure TSeriesModelTests.LinkByValuesSecondItemSameSlotTaken;
var
  Id, A, B: Integer;
  Lines: TArray<TSeriesLinkLine>;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewDeposition('A', 200, 0);
  B := NewDeposition('B', 200, 0);
  Lines := FModel.LinkByValues(FNotebook.Principal, Id, [A, B], False);
  Assert.AreEqual(Ord(sloLinked), Ord(Lines[0].Outcome));
  Assert.AreEqual(Ord(sloSlotTaken), Ord(Lines[1].Outcome));
  Assert.AreEqual(1, MemberCount(Id));
  Assert.IsNotNull(MemberOf(A));
  Assert.IsNull(MemberOf(B));
end;

procedure TSeriesModelTests.MarkFailedFreesSlot;
var
  Id, Slot, First, Second: Integer;
  Member: TSeriesMember;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Slot := SlotAt(Id, 200);
  First := FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('First'));
  ExpectSeriesError(
    procedure
    begin
      FModel.MarkFailed(FNotebook.Principal, Id, First, '  ');
    end);
  FModel.MarkFailed(FNotebook.Principal, Id, First, 'Chamber leak');
  Member := MemberOf(First);
  Assert.AreEqual(Ord(satFailed), Ord(Member.AttemptState));
  Assert.AreEqual('Chamber leak', Member.FailReason);
  Assert.AreEqual(0, FModel.GetPlan(FNotebook.Principal, Id).Slots[1].ValidItemId);
  Second := FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('Second'));
  Assert.AreEqual(2, MemberCount(Id));
  Assert.AreEqual(Second, FModel.GetPlan(FNotebook.Principal, Id).Slots[1].ValidItemId);
  ExpectSeriesError(
    procedure
    begin
      FModel.MarkFailed(FNotebook.Principal, Id, First, 'Again');
    end);
end;

procedure TSeriesModelTests.UnlinkRemovesMembership;
var
  Id, A: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  LinkItems(Id, [A]);
  Assert.AreEqual(A, FModel.GetPlan(FNotebook.Principal, Id).Slots[0].ValidItemId);
  FModel.Unlink(FNotebook.Principal, Id, A);
  Assert.AreEqual(0, MemberCount(Id));
  Assert.AreEqual(0, FModel.GetPlan(FNotebook.Principal, Id).Slots[0].ValidItemId);
  ExpectSeriesError(
    procedure
    begin
      FModel.Unlink(FNotebook.Principal, Id, A);
    end);
end;

procedure TSeriesModelTests.ListSeriesCountsPointsAndMeasured;
var
  Id, Made, D, M, P3, P3M: Integer;
  L: TArray<TSeriesSummary>;
  T: TSeriesTable;
  Row: TSeriesTableRow;
  N: Integer;
  V: unit_Item.TValue;
begin
  Id := NewSeriesWithPoints([100, 200, 300]);
  Made := FModel.MakeDeposition(FNotebook.Principal, Id, SlotAt(Id, 100), MakeDraft('Made'));
  Assert.IsTrue(Made > 0);
  D := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'D');
  M := NewItem(FProjectId, D, TItemLevel.Action, FXrr, 'M');
  AddValue(M, FThickness, TEST_RESULT, 50, 0.5);
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), D);
  P3 := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'P3');
  P3M := NewItem(FProjectId, P3, TItemLevel.Action, FXrr, 'P3M');
  V := unit_Item.TValue.Create;
  V.Item := FNotebook.Manager.Find<TItem>(P3M);
  V.ValueType := FThickness;
  V.RecType := TEST_RESULT;
  V.Value := 60;
  V.Tol := 0.5;
  V.CreatedDate := Now;
  V.SourceKind := vskPlanned;
  FNotebook.Manager.Save(V);
  FNotebook.Manager.Flush;
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 300), P3);
  L := FModel.ListSeries(FNotebook.Principal, FProjectId);
  Assert.AreEqual<NativeInt>(1, Length(L));
  Assert.AreEqual(3, L[0].PointCount);
  Assert.AreEqual(1, L[0].MeasuredCount, 'planned mark never counts');
  Assert.AreEqual(3, L[0].MemberCount);
  Assert.AreEqual(1, FModel.Get(FNotebook.Principal, Id).MeasuredCount);
  Assert.AreEqual(3, FModel.Get(FNotebook.Principal, Id).PointCount);
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  N := 0;
  for Row in T.Rows do
    if Row.State = srsMeasured then
      Inc(N);
  Assert.AreEqual(L[0].MeasuredCount, N, 'builder agrees with the summary');
  Assert.IsTrue(T.Rows[0].State = srsDeposited);
  Assert.IsTrue(T.Rows[1].State = srsMeasured);
  Assert.IsTrue(T.Rows[2].State = srsDeposited);
end;

function MeasuredRows(const T: TSeriesTable): Integer;
var
  R: TSeriesTableRow;
begin
  Result := 0;
  for R in T.Rows do
    if R.State = srsMeasured then
      Inc(Result);
end;

procedure TSeriesModelTests.RecycledValidMemberIsNotMeasured;
var
  Plan: TSeriesPlan;
  Id, A, M: Integer;
  T: TSeriesTable;
  Pass: Integer;
begin
  for Pass := 0 to 1 do
  begin
    Plan := StdPlan;
    if Pass = 0 then
      Plan.Responses := nil;
    Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Recycled' + IntToStr(Pass), '',
      Plan, Pts([100, 200]));
    A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A' + IntToStr(Pass));
    M := NewItem(FProjectId, A, TItemLevel.Action, FXrr, 'M' + IntToStr(Pass));
    AddValue(M, FThickness, TEST_RESULT, 50, 0.5);
    FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100), A);
    SetDeleted(A);
    T := FModel.BuildTable(FNotebook.Principal, Id, True);
    Assert.AreEqual(0, MeasuredRows(T), 'table');
    Assert.AreEqual(0, FModel.Get(FNotebook.Principal, Id).MeasuredCount, 'summary');
  end;
end;

procedure TSeriesModelTests.SplitResponseUsesChosenSource;
var
  Plan: TSeriesPlan;
  Other: TActionType;
  Id, A, M: Integer;
  T: TSeriesTable;
begin
  Other := TActionType.Create;
  Other.Title := 'Profilometry';
  Other.CreatedDate := Now;
  FNotebook.Manager.Save(Other);
  FNotebook.Manager.Flush;
  Plan := StdPlan;
  Plan.Responses := nil;
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Split', '', Plan, Pts([100]));
  FModel.SetColumnRole(FNotebook.Principal, Id, TEST_RESULT, FThickness.Id,
    'at:' + IntToStr(FXrr.Id), scrResponse);
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  M := NewItem(FProjectId, A, TItemLevel.Action, Other, 'M');
  AddValue(M, FThickness, TEST_RESULT, 50, 0.5);
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100), A);
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Assert.AreEqual(0, MeasuredRows(T), 'table');
  Assert.AreEqual(0, FModel.Get(FNotebook.Principal, Id).MeasuredCount, 'summary');
  M := NewItem(FProjectId, A, TItemLevel.Action, FXrr, 'M2');
  AddValue(M, FThickness, TEST_RESULT, 51, 0.5);
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  Assert.AreEqual(1, MeasuredRows(T), 'table after chosen source');
  Assert.AreEqual(1, FModel.Get(FNotebook.Principal, Id).MeasuredCount, 'summary after');
end;

procedure TSeriesModelTests.RunSql(const ASql: string);
var
  Statement: IDBStatement;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand(ASql);
  Statement.Execute;
end;

function TSeriesModelTests.CountOf(const ATable: string): Integer;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
begin
  Statement := FNotebook.Connection.CreateStatement;
  Statement.SetSQLCommand('SELECT COUNT(*) FROM ' + ATable);
  Rows := Statement.ExecuteQuery;
  Assert.IsTrue(Rows.Next);
  Result := Rows.GetFieldValue(0);
end;

procedure TSeriesModelTests.MakeDepositionRollsBackWhenAuditFails;
var
  Id, Slot, Items, Values, Members, Version: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Slot := SlotAt(Id, 200);
  Items := CountOf('Items');
  Values := CountOf('DataValues');
  Members := CountOf('SeriesMembers');
  Version := FNotebook.Manager.Find<TSeries>(Id).Version;
  RunSql('CREATE TRIGGER BlockSeriesAudit BEFORE INSERT ON AuditLog WHEN NEW.EntityType = 11 ' +
    'BEGIN SELECT RAISE(ABORT, ''blocked''); END');
  try
    Assert.WillRaiseAny(
      procedure
      begin
        FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('Rolled back'));
      end);
  finally
    RunSql('DROP TRIGGER BlockSeriesAudit');
  end;
  Assert.AreEqual(Items, CountOf('Items'), 'items');
  Assert.AreEqual(Values, CountOf('DataValues'), 'values');
  Assert.AreEqual(Members, CountOf('SeriesMembers'), 'members');
  Assert.AreEqual(Version, FNotebook.Manager.Find<TSeries>(Id).Version, 'version');
  Assert.AreEqual(0, FModel.GetPlan(FNotebook.Principal, Id).Slots[1].ValidItemId);
  Assert.AreNotEqual(0, FModel.MakeDeposition(FNotebook.Principal, Id, Slot,
    MakeDraft('After')), 'slot usable again');
  Assert.AreEqual(Items + 1, CountOf('Items'));
end;

procedure TSeriesModelTests.MakeDepositionRollsBackWhenFixedTypeMissing;
var
  Id, Slot, Items, Values, Members, Version: Integer;
  X: TSeriesFixed;
begin
  Id := NewSeriesWithPoints([100, 200]);
  X := TSeriesFixed.Create;
  X.SeriesId := Id;
  X.ValueTypeId := 99999;
  X.FixedValue := 1;
  FNotebook.Manager.Save(X);
  FNotebook.Manager.Flush;
  Slot := SlotAt(Id, 200);
  Items := CountOf('Items');
  Values := CountOf('DataValues');
  Members := CountOf('SeriesMembers');
  Version := FNotebook.Manager.Find<TSeries>(Id).Version;
  ExpectSeriesError(
    procedure
    begin
      FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('Rolled back'));
    end);
  Assert.AreEqual(Items, CountOf('Items'), 'items');
  Assert.AreEqual(Values, CountOf('DataValues'), 'values');
  Assert.AreEqual(Members, CountOf('SeriesMembers'), 'members');
  Assert.AreEqual(Version, FNotebook.Manager.Find<TSeries>(Id).Version, 'version');
end;

procedure TSeriesModelTests.LinkByValuesRollsBackWhenAuditFails;
var
  Id, A, B, Slots, Members, Version: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewDeposition('A', 200, 0);
  B := NewDeposition('B', 250, 0);
  Slots := CountOf('SeriesSlots');
  Members := CountOf('SeriesMembers');
  Version := FNotebook.Manager.Find<TSeries>(Id).Version;
  RunSql('ALTER TABLE AuditLog RENAME TO AuditLogHidden');
  try
    Assert.WillRaiseAny(
      procedure
      begin
        FModel.LinkByValues(FNotebook.Principal, Id, [A, B], True);
      end);
  finally
    RunSql('ALTER TABLE AuditLogHidden RENAME TO AuditLog');
  end;
  Assert.AreEqual(Slots, CountOf('SeriesSlots'), 'slots');
  Assert.AreEqual(Members, CountOf('SeriesMembers'), 'members');
  Assert.AreEqual(Version, FNotebook.Manager.Find<TSeries>(Id).Version, 'version');
  Assert.AreEqual<NativeInt>(2, Length(FModel.GetPlan(FNotebook.Principal, Id).Slots));
  FModel.LinkByValues(FNotebook.Principal, Id, [A, B], True);
  Assert.AreEqual(2, MemberCount(Id));
  Assert.AreEqual(3, SlotCount(Id));
end;

procedure TSeriesModelTests.LinkToSlotRejectsBadItems;
var
  Id, Slot, Deleted, Foreign, Child, Parent, Folder: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Slot := SlotAt(Id, 100);
  Deleted := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'Deleted');
  SetDeleted(Deleted);
  Foreign := NewItem(NewProject('Other'), 0, TItemLevel.Proc, nil, 'Foreign');
  Parent := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'Parent');
  Child := NewItem(FProjectId, Parent, TItemLevel.Item, nil, 'Child');
  Folder := NewItem(FProjectId, 0, TItemLevel.Folder, nil, 'Folder');
  ExpectErrorText('Item ' + IntToStr(Deleted) + ' is deleted.',
    procedure begin FModel.LinkToSlot(FNotebook.Principal, Id, Slot, Deleted); end);
  ExpectErrorText('Item ' + IntToStr(Foreign) + ' belongs to another project.',
    procedure begin FModel.LinkToSlot(FNotebook.Principal, Id, Slot, Foreign); end);
  ExpectErrorText('Item ' + IntToStr(Child) +
    ' is not a top-level item; link the deposition item.',
    procedure begin FModel.LinkToSlot(FNotebook.Principal, Id, Slot, Child); end);
  ExpectErrorText('Item ' + IntToStr(Folder) + ' is a folder.',
    procedure begin FModel.LinkToSlot(FNotebook.Principal, Id, Slot, Folder); end);
  ExpectErrorText('Item 99999 not found.',
    procedure begin FModel.LinkToSlot(FNotebook.Principal, Id, Slot, 99999); end);
  Assert.AreEqual(0, MemberCount(Id));
end;

procedure TSeriesModelTests.MeasuredWithoutResponsesNeedsOnlyValidMember;
var
  Id, A, B: Integer;
  Plan: TSeriesPlan;
  L: TArray<TSeriesSummary>;
  T: TSeriesTable;
  Row: TSeriesTableRow;
  N: Integer;
begin
  Plan := StdPlan;
  Plan.Responses := nil;
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'No responses', '',
    Plan, Pts([100, 200, 300]));
  A := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'A');
  B := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'B');
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100), A);
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200), B);
  FModel.MarkFailed(FNotebook.Principal, Id, B, 'Bad run');
  L := FModel.ListSeries(FNotebook.Principal, FProjectId);
  Assert.AreEqual(3, L[0].PointCount);
  Assert.AreEqual(1, L[0].MeasuredCount, 'valid member only; failed and empty slots do not count');
  T := FModel.BuildTable(FNotebook.Principal, Id, True);
  N := 0;
  for Row in T.Rows do
    if Row.State = srsMeasured then
      Inc(N);
  Assert.AreEqual(L[0].MeasuredCount, N, 'builder agrees with the summary');
  Assert.AreEqual<NativeInt>(4, Length(T.Rows), 'three points and one failed attempt');
end;

function TSeriesModelTests.NewFolder(AProjectId: Integer): Integer;
var
  Projects: TProjectsModel;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Projects.AddFolder('Folder', '', AProjectId, 0);
  finally
    Projects.Free;
  end;
  Result := FNotebook.Manager.Find<TProject>(AProjectId).Folders.Last.Id;
end;

function TSeriesModelTests.NewMcp: TSeriesModel;
begin
  Result := TSeriesModel.Create(FNotebook.Manager, FNotebook.AccessPolicy, scvMcp);
end;

procedure TSeriesModelTests.PlanFolderMustBelongToProject;
var
  Id, Foreign, Own, Series: Integer;
  Plan: TSeriesPlan;
  Text: string;
begin
  Foreign := NewFolder(NewProject('Other'));
  Own := NewFolder(FProjectId);
  Id := NewSeriesWithPoints([100]);
  Series := CountOf('Series');
  Plan := StdPlan;
  Plan.TargetFolderId := Foreign;
  Text := Format('Folder %d not found in this project.', [Foreign]);
  ExpectErrorText(Text,
    procedure
    begin
      FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Foreign', '', Plan, nil);
    end);
  Assert.AreEqual(Series, CountOf('Series'), 'nothing created');
  ExpectErrorText(Text,
    procedure
    begin
      FModel.SavePlan(FNotebook.Principal, Id, Plan);
    end);
  Plan.TargetFolderId := 99999;
  ExpectErrorText('Folder 99999 not found in this project.',
    procedure
    begin
      FModel.SavePlan(FNotebook.Principal, Id, Plan);
    end);
  Assert.AreEqual(0, FModel.GetPlan(FNotebook.Principal, Id).Plan.TargetFolderId);
  Plan.TargetFolderId := Own;
  FModel.SavePlan(FNotebook.Principal, Id, Plan);
  Assert.AreEqual(Own, FModel.GetPlan(FNotebook.Principal, Id).Plan.TargetFolderId);
end;

procedure TSeriesModelTests.MakeDepositionRefusedWhenFolderLeftProject;
var
  Id, Slot, Folder, Items, Values, Members, Other: Integer;
  Plan: TSeriesPlan;
  Projects: TProjectsModel;
  Project: TProject;
begin
  Folder := NewFolder(FProjectId);
  Plan := StdPlan;
  Plan.TargetFolderId := Folder;
  Id := FModel.CreateSeries(FNotebook.Principal, FProjectId, 'Ti rate', '', Plan,
    Pts([100]));
  Slot := SlotAt(Id, 100);
  Other := NewProject('Other');
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Project := FNotebook.Manager.Find<TProject>(FProjectId);
    Projects.MoveFolder(Project.GetFolder(Folder), FProjectId, Other, 0,
      FNotebook.Principal.Id);
  finally
    Projects.Free;
  end;
  Items := CountOf('Items');
  Values := CountOf('DataValues');
  Members := CountOf('SeriesMembers');
  ExpectErrorText(Format('Folder %d not found in this project.', [Folder]),
    procedure
    begin
      FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('Refused'));
    end);
  Assert.AreEqual(Items, CountOf('Items'), 'items');
  Assert.AreEqual(Values, CountOf('DataValues'), 'values');
  Assert.AreEqual(Members, CountOf('SeriesMembers'), 'members');
end;

procedure TSeriesModelTests.CanDeleteRefusesTypeUsedByPlan;
var
  Types: TValueTypeModel;
begin
  NewSeriesWithPoints([100]);
  Types := TValueTypeModel.Create(FNotebook.Manager);
  try
    Assert.AreEqual('Cannot delete: used by a series plan.', Types.CanDelete(FPower.Id),
      'factor');
    Assert.AreEqual('Cannot delete: used by a series plan.', Types.CanDelete(FArFlow.Id),
      'fixed condition');
    Assert.AreEqual('Cannot delete: used by a series plan.', Types.CanDelete(FThickness.Id),
      'response');
    Assert.AreEqual('', Types.CanDelete(FPressure.Id), 'unused type');
  finally
    Types.Free;
  end;
end;

procedure TSeriesModelTests.MakeDepositionRefusesMissingFactorType;
var
  Id, Slot, Items, Values, Members, Version: Integer;
  F: TSeriesFactor;
begin
  Id := NewSeriesWithPoints([100, 200]);
  F := FNotebook.Manager.Find<TSeriesFactor>
    .Where(Linq['SeriesId'] = Id).Refreshing.UniqueResult;
  F.ValueTypeId := 99999;
  FNotebook.Manager.Flush;
  Slot := SlotAt(Id, 200);
  Items := CountOf('Items');
  Values := CountOf('DataValues');
  Members := CountOf('SeriesMembers');
  Version := FNotebook.Manager.Find<TSeries>(Id).Version;
  ExpectErrorText('Value type 99999 not found.',
    procedure
    begin
      FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('Refused'));
    end);
  Assert.AreEqual(Items, CountOf('Items'), 'items');
  Assert.AreEqual(Values, CountOf('DataValues'), 'values');
  Assert.AreEqual(Members, CountOf('SeriesMembers'), 'members');
  Assert.AreEqual(Version, FNotebook.Manager.Find<TSeries>(Id).Version, 'version');
end;

procedure TSeriesModelTests.McpActiveSeriesAcceptsOnlyPurposeAndPoints;
const
  Refusal = 'An active series plan is changed in the desktop. ' +
    'MCP can only add points to it.';
var
  Id, Before: Integer;
  Mcp: TSeriesModel;
  Plan: TSeriesPlan;
  Added: TArray<Integer>;
  Info: TSeriesPlanInfo;
begin
  Id := NewMcpSeries([100]);
  FModel.Start(FNotebook.Principal, Id);
  Mcp := NewMcp;
  try
    Before := FNotebook.Manager.Find<TSeries>(Id).Version;
    Plan := StdPlan;
    Plan.Fixed[0].Value := 25;
    ExpectErrorText(Refusal,
      procedure
      begin
        Mcp.UpdatePlanAndPoints(FNotebook.Principal, Id, True, 'Changed', True, Plan,
          Pts([200]), 'Why');
      end);
    Plan := StdPlan;
    Plan.Responses := nil;
    ExpectErrorText(Refusal,
      procedure
      begin
        Mcp.UpdatePlanAndPoints(FNotebook.Principal, Id, False, '', True, Plan, nil, '');
      end);
    Plan := StdPlan;
    Plan.Factors[0].RangeMax := 500.0;
    ExpectErrorText(Refusal,
      procedure
      begin
        Mcp.UpdatePlanAndPoints(FNotebook.Principal, Id, False, '', True, Plan, nil, '');
      end);
    Plan := StdPlan;
    Plan.TargetFolderId := NewFolder(FProjectId);
    ExpectErrorText(Refusal,
      procedure
      begin
        Mcp.UpdatePlanAndPoints(FNotebook.Principal, Id, False, '', True, Plan, nil, '');
      end);
    Info := FModel.GetPlan(FNotebook.Principal, Id);
    Assert.AreEqual(Before, FNotebook.Manager.Find<TSeries>(Id).Version, 'version');
    Assert.AreEqual(20.0, Info.Plan.Fixed[0].Value, 1e-9, 'fixed value');
    Assert.AreEqual<NativeInt>(1, Length(Info.Plan.Responses), 'responses');
    Assert.IsFalse(Info.Plan.Factors[0].RangeMax.HasValue, 'range');
    Assert.AreEqual(0, Info.Plan.TargetFolderId, 'folder');
    Assert.AreEqual<NativeInt>(1, Length(Info.Slots), 'points');
    Assert.AreEqual('Purpose', FNotebook.Manager.Find<TSeries>(Id).Purpose, 'purpose');
    Plan := Info.Plan;
    Added := Mcp.UpdatePlanAndPoints(FNotebook.Principal, Id, True, 'New purpose', True,
      Plan, Pts([200]), '');
    Assert.AreEqual<NativeInt>(1, Length(Added));
    Info := FModel.GetPlan(FNotebook.Principal, Id);
    Assert.AreEqual<NativeInt>(2, Length(Info.Slots));
    Assert.AreEqual(Ord(ssoAdded), Ord(Info.Slots[1].Origin));
    Assert.AreEqual('New purpose', FNotebook.Manager.Find<TSeries>(Id).Purpose);
    Added := Mcp.UpdatePlanAndPoints(FNotebook.Principal, Id, False, '', False,
      Default(TSeriesPlan), Pts([300]), '');
    Assert.AreEqual<NativeInt>(1, Length(Added), 'add_points without a plan');
  finally
    Mcp.Free;
  end;
end;

procedure TSeriesModelTests.McpDraftSeriesPlanChangeAllowed;
var
  Id: Integer;
  Mcp: TSeriesModel;
  Plan: TSeriesPlan;
begin
  Id := NewMcpSeries([100]);
  Mcp := NewMcp;
  try
    Plan := StdPlan;
    Plan.Fixed[0].Value := 25;
    Plan.Responses := nil;
    Mcp.UpdatePlanAndPoints(FNotebook.Principal, Id, False, '', True, Plan, nil, '');
  finally
    Mcp.Free;
  end;
  Assert.AreEqual(25.0, FModel.GetPlan(FNotebook.Principal, Id).Plan.Fixed[0].Value, 1e-9);
  Assert.AreEqual<NativeInt>(0, Length(FModel.GetPlan(FNotebook.Principal, Id).Plan.Responses));
end;

procedure TSeriesModelTests.ExcludedValidMemberRefusalNamesUnlinkExcluded;
const
  Text = 'This point has a deposition that is in the recycle bin or another project. ' +
    'Use Unlink excluded to free the point.';
var
  Id, Slot, Made, Other: Integer;
begin
  Id := NewSeriesWithPoints([100, 200]);
  Slot := SlotAt(Id, 100);
  Made := FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('First'));
  SetDeleted(Made);
  Other := NewItem(FProjectId, 0, TItemLevel.Proc, nil, 'Other');
  ExpectErrorText(Text,
    procedure
    begin
      FModel.MakeDeposition(FNotebook.Principal, Id, Slot, MakeDraft('Second'));
    end);
  ExpectErrorText(Text,
    procedure
    begin
      FModel.LinkToSlot(FNotebook.Principal, Id, Slot, Other);
    end);
  Assert.AreEqual(1, MemberCount(Id));
end;

procedure TSeriesModelTests.LinkByValuesNearDuplicateNewPointsShareOnePoint;
var
  Id, A, B, C: Integer;
  Preview, Lines: TArray<TSeriesLinkLine>;
begin
  Id := NewSeriesWithPoints([100, 200]);
  A := NewDeposition('A', 300, 0.5);
  B := NewDeposition('B', 300.3, 0.5);
  C := NewDeposition('C', 301, 0.5);
  Preview := FModel.PreviewLinkByValues(FNotebook.Principal, Id, [A, B, C]);
  Assert.AreEqual(Ord(sloNewPoint), Ord(Preview[0].Outcome), 'preview A');
  Assert.AreEqual(Ord(sloSlotTaken), Ord(Preview[1].Outcome), 'preview B');
  Assert.AreEqual(Ord(sloNewPoint), Ord(Preview[2].Outcome), 'preview C');
  Lines := FModel.LinkByValues(FNotebook.Principal, Id, [A, B, C], True);
  Assert.AreEqual(Ord(sloNewPoint), Ord(Lines[0].Outcome), 'apply A');
  Assert.AreEqual(Ord(sloSlotTaken), Ord(Lines[1].Outcome), 'apply B');
  Assert.AreEqual(Ord(sloNewPoint), Ord(Lines[2].Outcome), 'apply C');
  Assert.AreEqual(Lines[0].SlotId, Lines[1].SlotId, 'B points at the point of A');
  Assert.AreEqual(4, SlotCount(Id), 'one point for A and B, one for C');
  Assert.AreEqual(2, MemberCount(Id));
  Assert.IsNotNull(MemberOf(A));
  Assert.IsNull(MemberOf(B));
  Assert.IsNotNull(MemberOf(C));
end;

procedure TSeriesModelTests.ListSeriesStatementCountIndependentOfSeries;
var
  Small, Large: Integer;
begin
  Small := ListStatementsFor(1);
  Large := ListStatementsFor(5);
  Assert.AreEqual(Small, Large);
end;

initialization
  TDUnitX.RegisterTestFixture(TSeriesModelTests);

end.
