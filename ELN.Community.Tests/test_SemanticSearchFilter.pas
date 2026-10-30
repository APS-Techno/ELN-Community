unit test_SemanticSearchFilter;

interface

uses
  System.SysUtils, System.Generics.Collections, DUnitX.TestFramework,
  Aurelius.Types.Nullable, unit_VectorSearch, unit_SemanticSearchApi, unit_SemanticSearchFilter,
  unit_Item, unit_ValueType, unit_ItemTypes, unit_SearchVisibility, test_SearchIndex,
  test_SearchDoubles;

type
  [TestFixture]
  TSemanticSearchFilterTests = class(TNotebookFixture)
  private
    FOtherProjectId: Integer;
    FTop, FSub, FSide, FOtherFolder: Integer;
    FActionTypeId: Integer;
    FHardness, FTemperature: TValueType;
    FA, FB, FC, FD, FE: Integer;
    function NewFilter: TSemanticSearchFilter;
    function Resolve(const Filter: TSemanticSearchFilter): TItemFilter;
    function ResolveFor(const Visible: TArray<Integer>;
      const Filter: TSemanticSearchFilter): TItemFilter;
    function ErrorOf(const Visible: TArray<Integer>;
      const Filter: TSemanticSearchFilter): string;
    function Constraint(const ValueType: string; const Min, Max: Nullable<Double>;
      const UnitSymbol: string; const RecType: string = ''): TValueConstraint;
    function Day(Year, Month, DayOfMonth: Word; Hour: Word = 0; Minute: Word = 0): TDateTime;
    procedure ExpectIds(const Expected: array of Integer; const Actual: TItemFilter);
    procedure AddData;
    function NewItem(const Title: string; ProjectId, FolderId: Integer; ItemType: TItemType;
      Level: TItemLevel; Created, Modified: TDateTime): TItem;
    procedure AddValue(Item: TItem; ValueType: TValueType; RecType: TRecType; Number: Double);
    function NewValueType(const Symbol, Title, Units: string): TValueType;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ValueIsStoredInTheTypeUnits;
    [Test]
    procedure FolderIncludesItsSubfolders;
    [Test]
    procedure LeafFolderHoldsOnlyItsOwnItems;
    [Test]
    procedure FolderInAnInvisibleProjectGivesTheNotFoundError;
    [Test]
    procedure InvisibleAndMissingFolderShareOneMessage;
    [Test]
    procedure FolderOfAVisibleProjectResolvesWhenItsProjectIsVisible;
    [Test]
    procedure ItemTypeSelectsItems;
    [Test]
    procedure UnknownItemTypeRaises;
    [Test]
    procedure LevelSelectsItems;
    [Test]
    procedure ItemTypeAndLevelCombine;
    [Test]
    procedure ActionTypeSelectsItems;
    [Test]
    procedure CreatedRangeIncludesTheEndDay;
    [Test]
    procedure ModifiedRangeSkipsItemsWithoutModifiedDate;
    [Test]
    procedure ModifiedFieldWithoutLimitsSkipsItemsWithoutModifiedDate;
    [Test]
    procedure ReversedDateRangeRaises;
    [Test]
    procedure HardnessAboveTenGigapascalMatchesTheMegapascalType;
    [Test]
    procedure HardnessBelowTenGigapascalMatchesTheLowItem;
    [Test]
    procedure ValueTypeResolvesBySymbolIgnoringCase;
    [Test]
    procedure RecTypeRestrictsTheValue;
    [Test]
    procedure UnknownRecTypeRaises;
    [Test]
    procedure PressureUnitAgainstALengthTypeRaises;
    [Test]
    procedure UnknownUnitRaises;
    [Test]
    procedure UnknownValueTypeRaises;
    [Test]
    procedure MinimumAboveMaximumRaises;
    [Test]
    procedure CelsiusThresholdAgainstAKelvinType;
    [Test]
    procedure ItemNeedsOnlyOneValueToSatisfyAConstraint;
    [Test]
    procedure TwoConstraintsAreCombinedWithAnd;
    [Test]
    procedure ValueConstraintCombinesWithFolder;
    [Test]
    procedure ValueConstraintNeverReachesAnInvisibleProject;
    [Test]
    procedure EmptyFilterIsInactiveAndRunsNoQuery;
    [Test]
    procedure NoMatchGivesAnActiveEmptyFilter;
    [Test]
    procedure NoVisibleProjectGivesAnActiveEmptyFilter;
    [Test]
    procedure LongVisibleProjectListIsChunked;
    [Test]
    procedure NilVisibleSetMeansEveryProject;
    [Test]
    procedure EmptyVisibleSetGivesNoGroup;
    [Test]
    procedure LocalPolicyKeepsItsVisibleSet;
  end;

implementation

uses
  System.DateUtils, System.Math, Aurelius.Engine.ObjectManager, unit_NotebookStorage,
  unit_LocalNotebook, unit_Project, unit_ActionType, unit_ProjectModel, unit_ItemModel,
  unit_ValueSource, unit_ValueDrift, Aurelius.Drivers.SQLite.Import;

type
  THardnessRunner = class(TInterfacedObject, IValueReaderRunner)
  private
    FGigapascal: Double;
  public
    constructor Create(Gigapascal: Double);
    function Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
  end;

constructor THardnessRunner.Create(Gigapascal: Double);
begin
  inherited Create;
  FGigapascal := Gigapascal;
end;

function THardnessRunner.Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
begin
  Result := Default(TReaderRun);
  Result.Succeeded := True;
  Result.ReaderId := 'synthetic.hardness';
  Result.ReaderVersion := '1';
  SetLength(Result.Values, 1);
  Result.Values[0].Name := 'Hardness';
  Result.Values[0].Value := FGigapascal;
  Result.Values[0].Units := 'GPa';
end;

function Celsius: string;
begin
  Result := WideChar($00B0) + 'C';
end;

function None: Nullable<Double>;
begin
  Result := Default(Nullable<Double>);
end;

function Some(Value: Double): Nullable<Double>;
begin
  Result := Value;
end;

procedure TSemanticSearchFilterTests.Setup;
begin
  BuildNotebook;
  AddData;
end;

procedure TSemanticSearchFilterTests.TearDown;
begin
  FreeNotebook;
end;

function TSemanticSearchFilterTests.NewFilter: TSemanticSearchFilter;
begin
  Result := Default(TSemanticSearchFilter);
end;

function TSemanticSearchFilterTests.Resolve(const Filter: TSemanticSearchFilter): TItemFilter;
begin
  Result := ResolveFor([FProjectId], Filter);
end;

function TSemanticSearchFilterTests.ResolveFor(const Visible: TArray<Integer>;
  const Filter: TSemanticSearchFilter): TItemFilter;
begin
  Result := ResolveSemanticFilter(FNotebook.Manager, Visible, Filter);
end;

function TSemanticSearchFilterTests.ErrorOf(const Visible: TArray<Integer>;
  const Filter: TSemanticSearchFilter): string;
begin
  try
    ResolveFor(Visible, Filter);
  except
    on E: ESemanticFilterError do
      Exit(E.Message);
  end;
  Assert.Fail('ESemanticFilterError expected');
  Result := '';
end;

function TSemanticSearchFilterTests.Constraint(const ValueType: string;
  const Min, Max: Nullable<Double>; const UnitSymbol, RecType: string): TValueConstraint;
begin
  Result := Default(TValueConstraint);
  Result.ValueType := ValueType;
  Result.HasMin := Min.HasValue;
  if Min.HasValue then
    Result.Min := Min.Value;
  Result.HasMax := Max.HasValue;
  if Max.HasValue then
    Result.Max := Max.Value;
  Result.UnitSymbol := UnitSymbol;
  Result.RecType := RecType;
end;

function TSemanticSearchFilterTests.Day(Year, Month, DayOfMonth, Hour, Minute: Word): TDateTime;
begin
  Result := EncodeDateTime(Year, Month, DayOfMonth, Hour, Minute, 0, 0);
end;

procedure TSemanticSearchFilterTests.ExpectIds(const Expected: array of Integer;
  const Actual: TItemFilter);
var
  Want, Got: TArray<Integer>;
  I: Integer;
begin
  Assert.IsTrue(Actual.Active, 'A resolved filter is active');
  SetLength(Want, Length(Expected));
  for I := 0 to High(Expected) do
    Want[I] := Expected[I];
  TArray.Sort<Integer>(Want);
  Got := Copy(Actual.ItemIds);
  TArray.Sort<Integer>(Got);
  Assert.AreEqual(Length(Want), Length(Got), 'Item count');
  for I := 0 to High(Want) do
    Assert.AreEqual(Want[I], Got[I], 'Item ' + IntToStr(I));
end;

function TSemanticSearchFilterTests.NewItem(const Title: string; ProjectId, FolderId: Integer;
  ItemType: TItemType; Level: TItemLevel; Created, Modified: TDateTime): TItem;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.ProjectID := ProjectId;
  Result.FolderID := FolderId;
  Result.Type_ := ItemType;
  Result.Level := Level;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Created;
  if Modified > 0 then
    Result.ModifiedDate := Modified;
end;

procedure TSemanticSearchFilterTests.AddValue(Item: TItem; ValueType: TValueType;
  RecType: TRecType; Number: Double);
var
  Value: unit_Item.TValue;
begin
  Value := unit_Item.TValue.Create;
  Value.ValueType := ValueType;
  Value.RecType := RecType;
  Value.Value := Number;
  Value.CreatedDate := Now;
  Value.Item := Item;
  Item.Values.Add(Value);
end;

function TSemanticSearchFilterTests.NewValueType(const Symbol, Title, Units: string): TValueType;
begin
  Result := TValueType.Create;
  Result.Symbol := Symbol;
  Result.Title := Title;
  Result.Units := Units;
  Result.CreatedDate := Now;
  Result.CreatedBy := FNotebook.Principal.Id;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
end;

procedure TSemanticSearchFilterTests.AddData;
var
  Manager: TObjectManager;
  Projects: TProjectsModel;
  Other: TProject;
  Project: TProject;
  Top, Sub, Side, Foreign: TFolder;
  Action: TActionType;
  A, B, C, D, E: TItem;
begin
  Manager := FNotebook.Manager;
  Projects := TProjectsModel.Create(Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    Other := Projects.AddProject('Hidden project', '', FNotebook.Principal);
  finally
    Projects.Free;
  end;
  FOtherProjectId := Other.Id;

  Project := Manager.Find<TProject>(FProjectId);
  Top := TFolder.Create;
  Top.Title := 'Top';
  Top.CreatedDate := Now;
  Top.CreatedBy := FNotebook.Principal.Id;
  Project.Folders.Add(Top);
  Side := TFolder.Create;
  Side.Title := 'Side';
  Side.CreatedDate := Now;
  Side.CreatedBy := FNotebook.Principal.Id;
  Project.Folders.Add(Side);
  Manager.Flush;
  Sub := TFolder.Create;
  Sub.Title := 'Sub';
  Sub.ParentFolderID := Top.Id;
  Sub.CreatedDate := Now;
  Sub.CreatedBy := FNotebook.Principal.Id;
  Project.Folders.Add(Sub);
  Other := Manager.Find<TProject>(FOtherProjectId);
  Foreign := TFolder.Create;
  Foreign.Title := 'Foreign';
  Foreign.CreatedDate := Now;
  Foreign.CreatedBy := FNotebook.Principal.Id;
  Other.Folders.Add(Foreign);
  Manager.Flush;
  FTop := Top.Id;
  FSub := Sub.Id;
  FSide := Side.Id;
  FOtherFolder := Foreign.Id;

  Action := TActionType.Create;
  Action.Title := 'X-ray reflectometry';
  Action.CreatedDate := Now;
  Manager.Save(Action);
  Manager.Flush;
  FActionTypeId := Action.Id;

  FHardness := NewValueType('H', 'Hardness', 'MPa');
  FTemperature := NewValueType('T', 'Sample temperature', 'K');

  A := NewItem('A', FProjectId, FTop, TItemType.Specimen, TItemLevel.Item,
    Day(2026, 1, 10, 10), Day(2026, 1, 20, 12));
  AddValue(A, FHardness, TEST_RESULT, 12000);
  AddValue(A, FTemperature, EXP_CONDITION, 400);
  AddValue(A, FTemperature, EXP_CONDITION, 250);
  Manager.Save(A);

  B := NewItem('B', FProjectId, FSub, TItemType.Measurement, TItemLevel.Action,
    Day(2026, 2, 5, 23, 30), 0);
  B.ActionType := Action;
  AddValue(B, FHardness, TEST_RESULT, 9000);
  AddValue(B, FTemperature, EXP_CONDITION, 300);
  Manager.Save(B);

  C := NewItem('C', FProjectId, FSide, TItemType.Testing, TItemLevel.Proc,
    Day(2026, 2, 6), Day(2026, 2, 7, 9));
  AddValue(C, FHardness, EXP_CONDITION, 15000);
  Manager.Save(C);

  D := NewItem('D', FOtherProjectId, FOtherFolder, TItemType.Specimen, TItemLevel.Item,
    Day(2026, 1, 15), 0);
  AddValue(D, FHardness, TEST_RESULT, 20000);
  AddValue(D, FTemperature, EXP_CONDITION, 500);
  Manager.Save(D);

  E := NewItem('E', FProjectId, FTop, TItemType.Specimen, TItemLevel.Item,
    Day(2026, 1, 12), 0);
  E.IsDeleted := True;
  E.DeletedDate := Now;
  AddValue(E, FHardness, TEST_RESULT, 30000);
  Manager.Save(E);
  Manager.Flush;

  FA := A.Id;
  FB := B.Id;
  FC := C.Id;
  FD := D.Id;
  FE := E.Id;
end;

procedure TSemanticSearchFilterTests.ValueIsStoredInTheTypeUnits;
var
  Items: TItemModel;
  Item: TItem;
  Report: TValueDriftReport;
  Row: TValueDriftRow;
begin
  Item := NewItem('Reader item', FProjectId, 0, TItemType.Measurement, TItemLevel.Item,
    Day(2026, 3, 1), 0);
  FNotebook.Manager.Save(Item);
  FNotebook.Manager.Flush;
  Items := TItemModel.Create(FNotebook.Manager);
  try
    Items.AddValue(FHardness, TEST_RESULT, 12000, FNotebook.Principal.Id, Item, 0, '',
      TValueSourceInfo.Reader(1, 'synthetic.hardness', '1', 'Hardness', 'GPa', 1000));
  finally
    Items.Free;
  end;
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], THardnessRunner.Create(12));
  Assert.AreEqual(1, Report.Checked);
  Assert.AreEqual(1, Report.Unchanged,
    'A reader value of 12 GPa is stored as 12000 in the MPa type, so the stored number is in the type units');
  Report := CheckValueDrift(FNotebook.Manager, [Item.Id], THardnessRunner.Create(9));
  Assert.AreEqual(1, Integer(Length(Report.Rows)));
  Row := Report.Rows[0];
  Assert.AreEqual(9000.0, Row.CurrentValue, 1e-9, 'The reader output is converted into the type units');
end;

procedure TSemanticSearchFilterTests.FolderIncludesItsSubfolders;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.FolderId := FTop;
  ExpectIds([FA, FB], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.LeafFolderHoldsOnlyItsOwnItems;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.FolderId := FSub;
  ExpectIds([FB], Resolve(Filter));
  Filter.FolderId := FSide;
  ExpectIds([FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.FolderInAnInvisibleProjectGivesTheNotFoundError;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.FolderId := FOtherFolder;
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.InvisibleAndMissingFolderShareOneMessage;
var
  Hidden, Missing: TSemanticSearchFilter;
begin
  Hidden := NewFilter;
  Hidden.FolderId := FOtherFolder;
  Missing := NewFilter;
  Missing.FolderId := 987654;
  Assert.AreEqual(ErrorOf([FProjectId], Missing), ErrorOf([FProjectId], Hidden));
end;

procedure TSemanticSearchFilterTests.FolderOfAVisibleProjectResolvesWhenItsProjectIsVisible;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.FolderId := FOtherFolder;
  ExpectIds([FD], ResolveFor([FProjectId, FOtherProjectId], Filter));
end;

procedure TSemanticSearchFilterTests.ItemTypeSelectsItems;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.ItemTypes := ['Specimen'];
  ExpectIds([FItem1, FA], Resolve(Filter));
  Filter.ItemTypes := ['specimen', 'Testing'];
  ExpectIds([FItem1, FA, FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.UnknownItemTypeRaises;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.ItemTypes := ['Bogus'];
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.LevelSelectsItems;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Levels := ['Action'];
  ExpectIds([FB], Resolve(Filter));
  Filter.Levels := ['Proc', 'Action'];
  ExpectIds([FB, FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ItemTypeAndLevelCombine;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.ItemTypes := ['Specimen', 'Measurement'];
  Filter.Levels := ['Item'];
  ExpectIds([FItem1, FA], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ActionTypeSelectsItems;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.ActionTypeId := FActionTypeId;
  ExpectIds([FB], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.CreatedRangeIncludesTheEndDay;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.DateField := sdfCreated;
  Filter.DateFrom := Day(2026, 2, 5);
  Filter.DateTo := Day(2026, 2, 5);
  ExpectIds([FB], Resolve(Filter));
  Filter.DateFrom := Day(2026, 1, 1);
  ExpectIds([FA, FB], Resolve(Filter));
  Filter.DateFrom := Day(2026, 2, 6);
  Filter.DateTo := Day(2026, 2, 6);
  ExpectIds([FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ModifiedRangeSkipsItemsWithoutModifiedDate;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.DateField := sdfModified;
  Filter.DateFrom := Day(2026, 1, 20);
  Filter.DateTo := Day(2026, 1, 20);
  ExpectIds([FA], Resolve(Filter));
  Filter.DateFrom := Day(2026, 2, 1);
  Filter.DateTo := Day(2026, 2, 28);
  ExpectIds([FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ModifiedFieldWithoutLimitsSkipsItemsWithoutModifiedDate;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.DateField := sdfModified;
  ExpectIds([FA, FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ReversedDateRangeRaises;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.DateField := sdfCreated;
  Filter.DateFrom := Day(2026, 2, 6);
  Filter.DateTo := Day(2026, 2, 5);
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.HardnessAboveTenGigapascalMatchesTheMegapascalType;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa')];
  ExpectIds([FA, FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.HardnessBelowTenGigapascalMatchesTheLowItem;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', None, Some(10), 'GPa')];
  ExpectIds([FB], Resolve(Filter));
  Filter.Values := [Constraint('Hardness', Some(9000), Some(12000), '')];
  ExpectIds([FA, FB], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ValueTypeResolvesBySymbolIgnoringCase;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('h', Some(10), None, 'GPa')];
  ExpectIds([FA, FC], Resolve(Filter));
  Filter.Values := [Constraint('HARDNESS', Some(10), None, 'GPa')];
  ExpectIds([FA, FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.RecTypeRestrictsTheValue;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa', 'TEST_RESULT')];
  ExpectIds([FA], Resolve(Filter));
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa', 'EXP_CONDITION')];
  ExpectIds([FC], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.UnknownRecTypeRaises;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa', 'RESULT')];
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.PressureUnitAgainstALengthTypeRaises;
var
  Filter: TSemanticSearchFilter;
begin
  NewValueType('d', 'Film thickness', 'nm');
  Filter := NewFilter;
  Filter.Values := [Constraint('Film thickness', Some(10), None, 'GPa')];
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.UnknownUnitRaises;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', Some(10), None, 'furlong')];
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.UnknownValueTypeRaises;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Elasticity', Some(10), None, 'GPa')];
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
  Filter.Values := [Constraint('', Some(10), None, 'GPa')];
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.MinimumAboveMaximumRaises;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', Some(10), Some(5), 'GPa')];
  Assert.WillRaise(procedure begin Resolve(Filter); end, ESemanticFilterError);
end;

procedure TSemanticSearchFilterTests.CelsiusThresholdAgainstAKelvinType;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Sample temperature', Some(100), None, Celsius)];
  ExpectIds([FA], Resolve(Filter));
  Filter.Values := [Constraint('Sample temperature', Some(20), Some(30), Celsius)];
  ExpectIds([FB], Resolve(Filter));
  Filter.Values := [Constraint('Sample temperature', Some(290), Some(310), 'K')];
  ExpectIds([FB], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ItemNeedsOnlyOneValueToSatisfyAConstraint;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Sample temperature', None, Some(0), Celsius)];
  ExpectIds([FA], Resolve(Filter));
  Filter.Values := [Constraint('Sample temperature', Some(100), None, Celsius)];
  ExpectIds([FA], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.TwoConstraintsAreCombinedWithAnd;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa'),
    Constraint('Sample temperature', Some(100), None, Celsius)];
  ExpectIds([FA], Resolve(Filter));
  Filter.Values := [Constraint('Hardness', None, Some(10), 'GPa'),
    Constraint('Sample temperature', None, Some(0), Celsius)];
  ExpectIds([], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ValueConstraintCombinesWithFolder;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.FolderId := FTop;
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa')];
  ExpectIds([FA], Resolve(Filter));
  Filter.FolderId := FSide;
  ExpectIds([FC], Resolve(Filter));
  Filter.FolderId := FSub;
  ExpectIds([], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.ValueConstraintNeverReachesAnInvisibleProject;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.Values := [Constraint('Hardness', Some(16), None, 'GPa')];
  ExpectIds([], ResolveFor([FProjectId], Filter));
  ExpectIds([FD], ResolveFor([FProjectId, FOtherProjectId], Filter));
  Filter := NewFilter;
  Filter.ItemTypes := ['Specimen'];
  ExpectIds([FItem1, FA], ResolveFor([FProjectId], Filter));
  ExpectIds([FItem1, FA, FD], ResolveFor([FProjectId, FOtherProjectId], Filter));
end;

procedure TSemanticSearchFilterTests.EmptyFilterIsInactiveAndRunsNoQuery;
var
  Resolved: TItemFilter;
begin
  Assert.IsTrue(NewFilter.IsEmpty);
  Resolved := ResolveSemanticFilter(nil, [FProjectId], NewFilter);
  Assert.IsFalse(Resolved.Active);
  Assert.AreEqual<NativeInt>(0, Length(Resolved.ItemIds));
end;

procedure TSemanticSearchFilterTests.NoMatchGivesAnActiveEmptyFilter;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.ItemTypes := ['Wiki'];
  ExpectIds([], Resolve(Filter));
end;

procedure TSemanticSearchFilterTests.NoVisibleProjectGivesAnActiveEmptyFilter;
var
  Filter: TSemanticSearchFilter;
begin
  Filter := NewFilter;
  Filter.ItemTypes := ['Specimen'];
  ExpectIds([], ResolveFor(nil, Filter));
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa')];
  ExpectIds([], ResolveFor(nil, Filter));
end;

procedure TSemanticSearchFilterTests.LongVisibleProjectListIsChunked;
var
  Filter: TSemanticSearchFilter;
  Visible: TArray<Integer>;
  I: Integer;
begin
  SetLength(Visible, 1001);
  Visible[0] := FProjectId;
  for I := 1 to 1000 do
    Visible[I] := 100000 + I;
  Filter := NewFilter;
  Filter.ItemTypes := ['Specimen'];
  ExpectIds([FItem1, FA], ResolveFor(Visible, Filter));
  Filter.Values := [Constraint('Hardness', Some(10), None, 'GPa')];
  ExpectIds([FA], ResolveFor(Visible, Filter));
  Filter.FolderId := FTop;
  ExpectIds([FA], ResolveFor(Visible, Filter));
end;

procedure TSemanticSearchFilterTests.NilVisibleSetMeansEveryProject;
var
  Filter: TSemanticSearchFilter;
  Visible: TArray<Integer>;
  Idx: Integer;
begin
  Visible := SearchVisibleProjectIds(FNotebook.Manager,
    TUnrestrictedPolicy.Create(FNotebook.AccessPolicy, True), FNotebook.Principal);
  TArray.Sort<Integer>(Visible);
  Assert.AreEqual<Integer>(2, Length(Visible));
  Assert.IsTrue(TArray.BinarySearch<Integer>(Visible, FProjectId, Idx), 'First project');
  Assert.IsTrue(TArray.BinarySearch<Integer>(Visible, FOtherProjectId, Idx), 'Second project');
  Filter := NewFilter;
  Filter.FolderId := FOtherFolder;
  ExpectIds([FD], ResolveFor(Visible, Filter));
end;

procedure TSemanticSearchFilterTests.EmptyVisibleSetGivesNoGroup;
var
  Filter: TSemanticSearchFilter;
  Visible: TArray<Integer>;
begin
  Visible := SearchVisibleProjectIds(FNotebook.Manager,
    TUnrestrictedPolicy.Create(FNotebook.AccessPolicy, False), FNotebook.Principal);
  Assert.AreEqual<Integer>(0, Length(Visible));
  Filter := NewFilter;
  Filter.ItemTypes := ['Specimen'];
  ExpectIds([], ResolveFor(Visible, Filter));
end;

procedure TSemanticSearchFilterTests.LocalPolicyKeepsItsVisibleSet;
var
  Visible: TArray<Integer>;
  Idx: Integer;
begin
  Visible := SearchVisibleProjectIds(FNotebook.Manager, FNotebook.AccessPolicy,
    FNotebook.Principal);
  TArray.Sort<Integer>(Visible);
  Assert.AreEqual<Integer>(2, Length(Visible));
  Assert.IsTrue(TArray.BinarySearch<Integer>(Visible, FProjectId, Idx), 'First project');
  Assert.IsTrue(TArray.BinarySearch<Integer>(Visible, FOtherProjectId, Idx), 'Second project');
end;

initialization
  TDUnitX.RegisterTestFixture(TSemanticSearchFilterTests);

end.
