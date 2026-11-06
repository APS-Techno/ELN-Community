unit test_SeriesLinkVM;

interface

uses
  System.SysUtils, DUnitX.TestFramework, unit_LocalNotebook, unit_ValueType,
  unit_SeriesTable, unit_SeriesModel, unit_SeriesLinkVM;

type
  [TestFixture]
  TSeriesLinkVMTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FModel: TSeriesModel;
    FProjectId: Integer;
    FPower, FArFlow: TValueType;
    function NewType(const ASymbol, ATitle, AUnits: string): TValueType;
    function NewItem(const ATitle: string): Integer;
    function NewDeposition(const ATitle: string; APower: Double): Integer;
    function NewSeries(const ATitle: string; const ALevels: array of Double): Integer;
    function NewVM(const AItems: array of Integer): TSeriesLinkVM;
    function SlotAt(ASeriesId: Integer; ALevel: Double): TSeriesSlotInfo;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PreviewNamesEachOutcome;
    [Test] procedure NewPointsAreAddedOnlyWhenTicked;
    [Test] procedure ApplyWithNewPointsGivesFourPointTable;
    [Test] procedure SingleItemChoosesFreePointByHand;
    [Test] procedure ApplyReportsLinkedAndSkipped;
    [Test] procedure OnlyActiveSeriesAreListed;
    [Test] procedure MembershipTextShowsLevelsAndFailed;
    [Test] procedure ConfirmPlannedConfirmsOnceAndRefusesUnknownItem;
  end;

implementation

uses
  System.IOUtils, Aurelius.Types.Nullable,
  unit_Project, unit_ProjectModel, unit_Item, unit_ItemTypes, unit_Series,
  unit_ItemModel;

const
  Password = 'Synthetic-Series-Link-Only!';
  Arrow = #$2192;

function TSeriesLinkVMTests.NewType(const ASymbol, ATitle, AUnits: string): TValueType;
begin
  Result := TValueType.Create;
  Result.Symbol := ASymbol;
  Result.Title := ATitle;
  Result.Units := AUnits;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
end;

procedure TSeriesLinkVMTests.Setup;
var
  Projects: TProjectsModel;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SeriesLink-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    FProjectId := Projects.AddProject('Series link project', '', FNotebook.Principal).Id;
  finally
    Projects.Free;
  end;
  FPower := NewType('PW', 'Power', 'W');
  FArFlow := NewType('AF', 'Ar flow', 'sccm');
  FNotebook.Manager.Flush;
  FModel := TSeriesModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
end;

procedure TSeriesLinkVMTests.TearDown;
begin
  FreeAndNil(FModel);
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TSeriesLinkVMTests.NewItem(const ATitle: string): Integer;
var
  Item: TItem;
begin
  Item := TItem.Create;
  Item.Title := ATitle;
  Item.ProjectID := FProjectId;
  Item.Parent := 0;
  Item.Type_ := TItemType.Synthesis;
  Item.Level := TItemLevel.Proc;
  Item.CreatedBy := FNotebook.Principal.Id;
  Item.CreatedDate := Now;
  FNotebook.Manager.Save(Item);
  FNotebook.Manager.Flush;
  Result := Item.Id;
end;

function TSeriesLinkVMTests.NewDeposition(const ATitle: string; APower: Double): Integer;
var
  V: unit_Item.TValue;
begin
  Result := NewItem(ATitle);
  V := unit_Item.TValue.Create;
  V.Item := FNotebook.Manager.Find<TItem>(Result);
  V.ValueType := FPower;
  V.RecType := TRecType.EXP_CONDITION;
  V.Value := APower;
  V.CreatedDate := Now;
  FNotebook.Manager.Save(V);
  FNotebook.Manager.Flush;
end;

function TSeriesLinkVMTests.NewSeries(const ATitle: string;
  const ALevels: array of Double): Integer;
var
  Plan: TSeriesPlan;
  Points: TArray<TSeriesPoint>;
  I: Integer;
begin
  Plan := Default(TSeriesPlan);
  SetLength(Plan.Factors, 1);
  Plan.Factors[0].ValueTypeId := FPower.Id;
  Plan.Factors[0].RangeMin := 100.0;
  Plan.Factors[0].RangeMax := 300.0;
  SetLength(Plan.Fixed, 1);
  Plan.Fixed[0].ValueTypeId := FArFlow.Id;
  Plan.Fixed[0].Value := 20;
  Plan.Fixed[0].Tol := 1;
  SetLength(Points, Length(ALevels));
  for I := 0 to High(ALevels) do
    Points[I] := [ALevels[I]];
  Result := FModel.CreateSeries(FNotebook.Principal, FProjectId, ATitle, '', Plan, Points);
end;

function TSeriesLinkVMTests.NewVM(const AItems: array of Integer): TSeriesLinkVM;
var
  Ids: TArray<Integer>;
  I: Integer;
begin
  SetLength(Ids, Length(AItems));
  for I := 0 to High(AItems) do
    Ids[I] := AItems[I];
  Result := TSeriesLinkVM.Create(FNotebook.Manager, FNotebook.Principal,
    FNotebook.AccessPolicy, FProjectId, Ids);
end;

function TSeriesLinkVMTests.SlotAt(ASeriesId: Integer; ALevel: Double): TSeriesSlotInfo;
var
  S: TSeriesSlotInfo;
begin
  for S in FModel.GetPlan(FNotebook.Principal, ASeriesId).Slots do
    if Abs(S.Levels[0] - ALevel) < 1e-9 then
      Exit(S);
  Result := Default(TSeriesSlotInfo);
  Assert.Fail('no slot at ' + FloatToStr(ALevel));
end;

procedure TSeriesLinkVMTests.PreviewNamesEachOutcome;
var
  VM: TSeriesLinkVM;
  A, B, C, D, E, F: Integer;
begin
  NewSeries('Ti rate', [100, 200, 300]);
  A := NewDeposition('A', 100);
  B := NewDeposition('B', 200);
  C := NewDeposition('C', 260);
  D := NewItem('D');
  E := NewDeposition('E', 350);
  F := NewDeposition('F', 100);
  VM := NewVM([A, B, C, D, E, F]);
  try
    Assert.AreEqual<NativeInt>(6, Length(VM.Lines));
    Assert.AreEqual('A ' + Arrow + ' 100 W', VM.Lines[0]);
    Assert.AreEqual('B ' + Arrow + ' 200 W', VM.Lines[1]);
    Assert.AreEqual('C ' + Arrow + ' new point 260 W (not added)', VM.Lines[2]);
    Assert.AreEqual('D: no Power value', VM.Lines[3]);
    Assert.AreEqual('E: 350 W is outside the range of the plan', VM.Lines[4]);
    Assert.AreEqual('F: point 100 W already has a deposition', VM.Lines[5]);
    VM.CreateMissing := True;
    Assert.AreEqual('C ' + Arrow + ' new point 260 W', VM.Lines[2]);
  finally
    VM.Free;
  end;
end;

procedure TSeriesLinkVMTests.NewPointsAreAddedOnlyWhenTicked;
var
  VM: TSeriesLinkVM;
  Id, C: Integer;
  R: TSeriesLinkResult;
begin
  Id := NewSeries('Ti rate', [100, 200, 300]);
  C := NewDeposition('C', 260);
  VM := NewVM([C]);
  try
    Assert.IsFalse(VM.CanApply, 'a new point needs the check box');
    VM.CreateMissing := True;
    Assert.IsTrue(VM.CanApply);
    R := VM.Apply;
    Assert.AreEqual(Id, R.SeriesId);
    Assert.AreEqual(1, R.Linked);
    Assert.AreEqual(0, R.Skipped);
  finally
    VM.Free;
  end;
  Assert.AreEqual<NativeInt>(4, Length(FModel.GetPlan(FNotebook.Principal, Id).Slots));
  Assert.AreEqual(C, SlotAt(Id, 260).ValidItemId);
end;

procedure TSeriesLinkVMTests.ApplyWithNewPointsGivesFourPointTable;
var
  VM: TSeriesLinkVM;
  Id, A, B, C: Integer;
  T: TSeriesTable;
  R: TSeriesLinkResult;
begin
  Id := NewSeries('Ti rate', [100, 200, 300]);
  A := NewDeposition('A', 100);
  B := NewDeposition('B', 200);
  C := NewDeposition('C', 260);
  VM := NewVM([A, B, C]);
  try
    Assert.AreEqual('A ' + Arrow + ' 100 W', VM.Lines[0]);
    Assert.AreEqual('B ' + Arrow + ' 200 W', VM.Lines[1]);
    Assert.StartsWith('C ' + Arrow + ' new point 260 W', VM.Lines[2]);
    VM.CreateMissing := True;
    R := VM.Apply;
    Assert.AreEqual(3, R.Linked);
    Assert.AreEqual(0, R.Skipped);
  finally
    VM.Free;
  end;
  T := FModel.BuildTable(FNotebook.Principal, Id, False);
  Assert.AreEqual<NativeInt>(4, Length(T.Rows));
  Assert.AreEqual(A, SlotAt(Id, 100).ValidItemId);
  Assert.AreEqual(B, SlotAt(Id, 200).ValidItemId);
  Assert.AreEqual(0, SlotAt(Id, 300).ValidItemId);
  Assert.AreEqual(C, SlotAt(Id, 260).ValidItemId);
end;

procedure TSeriesLinkVMTests.SingleItemChoosesFreePointByHand;
var
  VM: TSeriesLinkVM;
  Id, X, Y: Integer;
  Texts: TArray<string>;
begin
  Id := NewSeries('Ti rate', [100, 200, 300]);
  X := NewItem('X');
  Y := NewDeposition('Y', 100);
  VM := NewVM([X]);
  try
    Assert.AreEqual('X: no Power value', VM.Lines[0]);
    Assert.IsFalse(VM.CanApply);
    Assert.IsTrue(VM.CanChoosePoint);
    Texts := VM.PointTexts;
    Assert.AreEqual<NativeInt>(3, Length(Texts));
    Assert.AreEqual('200 W', Texts[1]);
    VM.ChoosePoint(1);
    Assert.AreEqual('X ' + Arrow + ' 200 W', VM.Lines[0]);
    Assert.IsTrue(VM.CanApply);
    Assert.AreEqual(1, VM.Apply.Linked);
  finally
    VM.Free;
  end;
  Assert.AreEqual(X, SlotAt(Id, 200).ValidItemId);
  VM := NewVM([X, Y]);
  try
    Assert.IsFalse(VM.CanChoosePoint, 'by hand is for one item');
  finally
    VM.Free;
  end;
end;

procedure TSeriesLinkVMTests.ApplyReportsLinkedAndSkipped;
var
  VM: TSeriesLinkVM;
  Id, A, D: Integer;
  R: TSeriesLinkResult;
begin
  Id := NewSeries('Ti rate', [100, 200, 300]);
  A := NewDeposition('A', 100);
  D := NewItem('D');
  VM := NewVM([A, D]);
  try
    R := VM.Apply;
    Assert.AreEqual(1, R.Linked);
    Assert.AreEqual(1, R.Skipped);
  finally
    VM.Free;
  end;
  Assert.AreEqual(A, SlotAt(Id, 100).ValidItemId);
end;

procedure TSeriesLinkVMTests.OnlyActiveSeriesAreListed;
var
  VM: TSeriesLinkVM;
  Plan: TSeriesPlan;
  Mcp: TSeriesModel;
  First, Second, A: Integer;
begin
  First := NewSeries('First', [100, 200]);
  Second := NewSeries('Second', [100, 300]);
  Plan := Default(TSeriesPlan);
  Mcp := TSeriesModel.Create(FNotebook.Manager, FNotebook.AccessPolicy, scvMcp);
  try
    Mcp.CreateSeries(FNotebook.Principal, FProjectId, 'Draft one', '', Plan, nil);
  finally
    Mcp.Free;
  end;
  A := NewDeposition('A', 300);
  VM := NewVM([A]);
  try
    Assert.AreEqual<NativeInt>(2, Length(VM.Series));
    Assert.AreEqual(First, VM.Series[0].Id);
    Assert.StartsWith('A ' + Arrow + ' new point 300 W', VM.Lines[0]);
    VM.SelectSeries(1);
    Assert.AreEqual(Second, VM.Series[VM.SeriesIndex].Id);
    Assert.AreEqual('A ' + Arrow + ' 300 W', VM.Lines[0]);
  finally
    VM.Free;
  end;
end;

procedure TSeriesLinkVMTests.MembershipTextShowsLevelsAndFailed;
var
  Id, A, B: Integer;
  M: TArray<TSeriesMembership>;
begin
  Id := NewSeries('Ti rate', [100, 200]);
  A := NewDeposition('A', 100);
  B := NewDeposition('B', 200);
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 100).SlotId, A);
  FModel.LinkToSlot(FNotebook.Principal, Id, SlotAt(Id, 200).SlotId, B);
  FModel.MarkFailed(FNotebook.Principal, Id, B, 'Bad run');
  Assert.AreEqual('Series: Ti rate (100 W)',
    TSeriesLinkVM.MembershipText(FModel.ItemMemberships(FNotebook.Principal, A)));
  Assert.AreEqual('Series: Ti rate (200 W, failed)',
    TSeriesLinkVM.MembershipText(FModel.ItemMemberships(FNotebook.Principal, B)));
  Assert.AreEqual('', TSeriesLinkVM.MembershipText(
    FModel.ItemMemberships(FNotebook.Principal, NewItem('Loose'))));
  M := FModel.ItemMemberships(FNotebook.Principal, A) +
    FModel.ItemMemberships(FNotebook.Principal, B);
  Assert.AreEqual('Series: Ti rate (100 W), Ti rate (200 W, failed)',
    TSeriesLinkVM.MembershipText(M));
end;

procedure TSeriesLinkVMTests.ConfirmPlannedConfirmsOnceAndRefusesUnknownItem;
var
  Id, Item: Integer;
  Draft: TSeriesDepositionDraft;
  Items: TItemModel;
  Raised: Boolean;
begin
  Id := NewSeries('Ti rate', [100, 200]);
  Draft := Default(TSeriesDepositionDraft);
  Draft.Title := 'Made';
  Item := FModel.MakeDeposition(FNotebook.Principal, Id, SlotAt(Id, 100).SlotId, Draft);
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Assert.IsTrue(Items.HasPlannedValues(Item));
    Assert.AreEqual(2, FModel.ConfirmPlanned(FNotebook.Principal, Item));
    Assert.IsFalse(Items.HasPlannedValues(Item));
    Assert.AreEqual(0, FModel.ConfirmPlanned(FNotebook.Principal, Item));
  finally
    Items.Free;
  end;
  Raised := False;
  try
    FModel.ConfirmPlanned(FNotebook.Principal, 99999);
  except
    on ESeriesError do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'unknown item');
end;

initialization
  TDUnitX.RegisterTestFixture(TSeriesLinkVMTests);

end.
