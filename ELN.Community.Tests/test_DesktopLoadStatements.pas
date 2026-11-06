unit test_DesktopLoadStatements;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DUnitX.TestFramework,
  Aurelius.Events.Manager,
  unit_LocalNotebook, unit_DataModel, unit_ItemTreeVM, unit_ProjectTreeVM;

type
  TStatementCounter = class
  private
    FProc: TSQLExecutingProc;
    FLog: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function CountMatching(const Table: string): Integer;
  end;

  TDesktopLoadFixture = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FCounter: TStatementCounter;
    FProjectAId: Integer;
    FFolderAId: Integer;
    FFolderA2Id: Integer;
    FProjectBId: Integer;
    FFolderBId: Integer;
    FBItemId: Integer;
    FRunItemId: Integer;
    FItemIds: TArray<Integer>;
    FFolderA2ItemIds: TArray<Integer>;
    FTouched: Integer;
    FLastBreakdown: string;
    function BuildBreakdown: string;
    procedure FillItemTree(Tree: TItemTreeVM);
    procedure FilterAll(Tree: TItemTreeVM);
    procedure PaintAll(Tree: TItemTreeVM);
  public
    constructor Create;
    destructor Destroy; override;
    function NewDataModel: TDataModel;
    procedure Build(N: Integer);
    function MissingItemId: Integer;
    function ExpectedLinkCount(Index: Integer;
      ForeignReadable: Boolean = True): Integer;
    procedure CreateItemTreeVm(out Data: TDataModel; out Vm: TItemTreeVM);
    function MeasureOpen: Integer;
    function MeasureProjectTree: Integer;
    function MeasureItemTree(Warm: Boolean): Integer;
    function MeasureItemTreePhase(const Phase: string): Integer;
    function Breakdown: string;
    property Counter: TStatementCounter read FCounter;
    property Notebook: TLocalNotebook read FNotebook;
    property ProjectAId: Integer read FProjectAId;
    property FolderAId: Integer read FFolderAId;
    property FolderA2Id: Integer read FFolderA2Id;
    property ProjectBId: Integer read FProjectBId;
    property FolderBId: Integer read FFolderBId;
    property ItemIds: TArray<Integer> read FItemIds;
    property FolderA2ItemIds: TArray<Integer> read FFolderA2ItemIds;
    property ForeignItemId: Integer read FBItemId;
    property RunItemId: Integer read FRunItemId;
    property Touched: Integer read FTouched;
  end;

  [TestFixture]
  TDesktopLoadStatementTests = class
  private
    procedure Report(const Path: string; N, Total: Integer;
      Fixture: TDesktopLoadFixture);
    procedure CheckLinkCounts(Fixture: TDesktopLoadFixture; Data: TDataModel;
      ForeignReadable: Boolean);
  public
    [Test] procedure BaselineOpen;
    [Test] procedure OpenFixedStatements;
    [Test] procedure BaselineProjectTree;
    [Test] procedure BaselineItemTreeCold;
    [Test] procedure BaselineItemTreeWarm;
    [Test] procedure BatchTagsEqualPerItem;
    [Test] procedure BatchLinkCountsEqualPerItem;
    [Test] procedure LinkCountsSelfAndDuplicateLinks;
    [Test] procedure CommentCountsUnchanged;
    [Test] procedure ItemsNoQueryAfterLoad;
    [Test] procedure ItemsAfterSetLocationReloads;
    [Test] procedure ItemTreeFixedStatements;
    [Test] procedure ChunkingOver500;
    [Test] procedure RefreshTagsAfterBatch;
  end;

  [TestFixture]
  TItemTreeLookupTests = class
  private
    procedure AddLateFile(Fixture: TDesktopLoadFixture; ItemId: Integer);
    procedure AddLateValue(Fixture: TDesktopLoadFixture; ItemId: Integer);
    procedure ReplaceThroughSecondManager(Fixture: TDesktopLoadFixture);
    function EvictScenario(Fixture: TDesktopLoadFixture): Integer;
  public
    [Test] procedure StatementsAreEqualAtNAnd3N;
    [Test] procedure LookupsReadNoStatementAfterLoad;
    [Test] procedure LookupsAreTheObjectsOfTheLazyListsInOrder;
    [Test] procedure LookupsAcrossTheChunkBoundary;
    [Test] procedure FilterReadsThroughTheLookups;
    [Test] procedure MissAfterDoChangedFallsBackToTheLazyList;
    [Test] procedure MissForAnItemOutsideTheLookupFallsBack;
    [Test] procedure MissAfterSetLocationFallsBack;
    [Test] procedure ModelDeleteAfterLoadLeavesNoFreedObjectInThePaint;
    [Test] procedure ModelAddAfterLoadShowsAtPaint;
    [Test] procedure EvictCacheAfterAModelDeleteTouchesNoFreedObject;
    [Test] procedure LoadedListIsReadBeforeTheLookupAndKeepsTheOthersBatched;
    [Test] procedure EvictCacheEvictsTheOwnerOfAMovedItem;
    [Test] procedure EvictCacheAfterDoChangedWithoutRefillStillEvictsTheChildren;
    [Test] procedure EvictedItemPaintsAndFiltersBeforeTheNextLoad;
    [Test] procedure EvictCacheDetachesTheLookupChildren;
    [Test] procedure EvictCacheGivesFreshDataAfterAReplaceThroughASecondManager;
    [Test] procedure EvictCacheLeavesNothingBehind;
  end;

  [TestFixture]
  TProjectTreeLookupTests = class
  private
    procedure AddExtraProjects(Fixture: TDesktopLoadFixture; Count: Integer);
    procedure CreateProjectVm(Fixture: TDesktopLoadFixture; out Data: TDataModel;
      out Vm: TProjectTreeVM);
    procedure AddFolderThroughSecondManager(Fixture: TDesktopLoadFixture;
      ProjectId: Integer; const Title: string);
    function FolderStatementsOfTheFill(Fixture: TDesktopLoadFixture;
      Vm: TProjectTreeVM; out Visible: Integer): Integer;
    function ProjectScenario(Fixture: TDesktopLoadFixture): Integer;
    procedure AddOwners(Fixture: TDesktopLoadFixture; Count: Integer);
    procedure CreateSupervisorVm(Fixture: TDesktopLoadFixture; out Data: TDataModel;
      out Vm: TProjectTreeVM);
    function SupervisorFill(Fixture: TDesktopLoadFixture; Vm: TProjectTreeVM;
      out Owners, Projects, Groups: Integer): Integer;
    function TreeProjectIds(Vm: TProjectTreeVM): TArray<Integer>;
  public
    [Test] procedure FolderStatementsAreConstantAtTwoAndSixProjects;
    [Test] procedure LookupIsTheFoldersOfEachProjectInOrder;
    [Test] procedure FilterReadsThroughTheLookup;
    [Test] procedure LoadedOwnListWinsOverTheLookup;
    [Test] procedure DeletingAFolderTheLookupHoldsReadsNoFreedFolder;
    [Test] procedure LookupAcrossTheChunkBoundary;
    [Test] procedure EvictedProjectIsFoundAgainBeforeItsFoldersAreRead;
    [Test] procedure EvictCacheDropsTheLookup;
    [Test] procedure DoChangedDropsTheLookup;
    [Test] procedure ANewFillRefreshesTheLookup;
    [Test] procedure LookupLeavesNothingBehind;
    [Test] procedure SupervisorStatementsAreConstantAtTwoAndSixOwners;
    [Test] procedure OwnerGroupsAreTheProjectsOfEachOwnerInOrder;
    [Test] procedure OwnerGroupsKeepOnlyTheProjectWithAMatchingFolder;
    [Test] procedure ShownProjectsAreTheProjectsOfTheTree;
    [Test] procedure OwnerNodesNeedASecondOwner;
  end;

implementation

uses
  System.IOUtils, System.RegularExpressions,
  Aurelius.Mapping.Explorer,
  unit_Project, unit_Item, unit_ProjectModel, unit_FolderModel,
  unit_FavoritesModel, unit_ProjectGroupModel,
  unit_ItemTypes, unit_LabEntry, unit_Protocol, unit_FileType, unit_ValueType,
  unit_Tag, unit_LinkType, unit_User, unit_ProjectAccessPolicy,
  unit_Hypothesis, unit_HypothesisRun, unit_ProjectGroup, unit_ItemLink,
  unit_ValueSource, unit_ItemModel, unit_AuthorModel, unit_UserHistoryModel,
  unit_SignatureModel, unit_CommentModel, unit_TagModel, unit_ItemLinkModel,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Base, Aurelius.Criteria.Linq;

type
  TSupervisorPolicy = class(TInterfacedObject, IProjectAccessPolicy)
  private
    FInner: IProjectAccessPolicy;
  public
    constructor Create(const AInner: IProjectAccessPolicy);
    function CheckWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectWriteVerdict;
    function CanWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function CanRead(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function RemoveProject(AManager: TObjectManager; AUser: TUser;
      AProject: TProject): Boolean;
    function CanPassGate(AManager: TObjectManager; AUser: TUser;
      AHypothesis: THypothesis; AGate: THypothesisGate;
      out AReason: string): Boolean;
    function CreateGateEligibility(AManager: TObjectManager;
      AUser: TUser): TGateEligibility;
    function ProjectList(AManager: TObjectManager; AUser: TUser): TList<TProject>;
    function GetProjectAccess(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectAccess;
    function ProjectDataSetCriteria(AManager: TObjectManager;
      AUser: TUser): TCriteria<TProject>;
    function VisibleProjectIds(AManager: TObjectManager;
      AUser: TUser): TDictionary<Integer, Boolean>;
    function CanReviewProtocol(AManager: TObjectManager; AUser: TUser;
      AProjectId, AAuthorId: Integer): Boolean;
    function CanBrowseAllProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateTags(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanEditReferenceData(AManager: TObjectManager; AUser: TUser): Boolean;
  end;

constructor TSupervisorPolicy.Create(const AInner: IProjectAccessPolicy);
begin
  inherited Create;
  FInner := AInner;
end;

function TSupervisorPolicy.CheckWrite(AManager: TObjectManager; AUser: TUser;
  AProjectId: Integer): TProjectWriteVerdict;
begin
  Result := FInner.CheckWrite(AManager, AUser, AProjectId);
end;

function TSupervisorPolicy.CanWrite(AManager: TObjectManager; AUser: TUser;
  AProjectId: Integer): Boolean;
begin
  Result := FInner.CanWrite(AManager, AUser, AProjectId);
end;

function TSupervisorPolicy.CanRead(AManager: TObjectManager; AUser: TUser;
  AProjectId: Integer): Boolean;
begin
  Result := True;
end;

function TSupervisorPolicy.RemoveProject(AManager: TObjectManager; AUser: TUser;
  AProject: TProject): Boolean;
begin
  Result := FInner.RemoveProject(AManager, AUser, AProject);
end;

function TSupervisorPolicy.CanPassGate(AManager: TObjectManager; AUser: TUser;
  AHypothesis: THypothesis; AGate: THypothesisGate; out AReason: string): Boolean;
begin
  Result := FInner.CanPassGate(AManager, AUser, AHypothesis, AGate, AReason);
end;

function TSupervisorPolicy.CreateGateEligibility(AManager: TObjectManager;
  AUser: TUser): TGateEligibility;
begin
  Result := FInner.CreateGateEligibility(AManager, AUser);
end;

function TSupervisorPolicy.ProjectList(AManager: TObjectManager;
  AUser: TUser): TList<TProject>;
begin
  Result := FInner.ProjectList(AManager, AUser);
end;

function TSupervisorPolicy.GetProjectAccess(AManager: TObjectManager;
  AUser: TUser; AProjectId: Integer): TProjectAccess;
begin
  Result := FInner.GetProjectAccess(AManager, AUser, AProjectId);
end;

function TSupervisorPolicy.ProjectDataSetCriteria(AManager: TObjectManager;
  AUser: TUser): TCriteria<TProject>;
begin
  Result := AManager.Find<TProject>;
end;

function TSupervisorPolicy.VisibleProjectIds(AManager: TObjectManager;
  AUser: TUser): TDictionary<Integer, Boolean>;
begin
  Result := FInner.VisibleProjectIds(AManager, AUser);
end;

function TSupervisorPolicy.CanReviewProtocol(AManager: TObjectManager;
  AUser: TUser; AProjectId, AAuthorId: Integer): Boolean;
begin
  Result := FInner.CanReviewProtocol(AManager, AUser, AProjectId, AAuthorId);
end;

function TSupervisorPolicy.CanBrowseAllProjects(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := True;
end;

function TSupervisorPolicy.CanCreateProjects(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := FInner.CanCreateProjects(AManager, AUser);
end;

function TSupervisorPolicy.CanCreateTags(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := FInner.CanCreateTags(AManager, AUser);
end;

function TSupervisorPolicy.CanEditReferenceData(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := FInner.CanEditReferenceData(AManager, AUser);
end;

const
  Password = 'Synthetic-Desktop-Load-Only!';
  MissingId = 987654321;
  ReportedTables: array[0..9] of string = ('Items', 'ItemTags', 'Tags',
    'ItemLinks', 'Comments', 'LabEntries', 'Files', 'Values', 'Projects',
    'Folders');

function SqlTable(const Reported: string): string;
begin
  if Reported = 'Values' then
    Result := 'DataValues'
  else
    Result := Reported;
end;

constructor TStatementCounter.Create;
var
  Log: TList<string>;
begin
  inherited Create;
  FLog := TList<string>.Create;
  Log := FLog;
  FProc :=
    procedure(Args: TSQLExecutingArgs)
    begin
      Log.Add(Args.SQL);
    end;
  TMappingExplorer.Default.Events.OnSQLExecuting.Subscribe(FProc);
end;

destructor TStatementCounter.Destroy;
begin
  TMappingExplorer.Default.Events.OnSQLExecuting.Unsubscribe(FProc);
  FLog.Free;
  inherited;
end;

procedure TStatementCounter.Clear;
begin
  FLog.Clear;
end;

function TStatementCounter.Count: Integer;
begin
  Result := FLog.Count;
end;

function TStatementCounter.CountMatching(const Table: string): Integer;
var
  SQL, Pattern: string;
begin
  Result := 0;
  Pattern := '\b' + TRegEx.Escape(Table) + '\b';
  for SQL in FLog do
    if TRegEx.IsMatch(SQL, Pattern, [roIgnoreCase]) then
      Inc(Result);
end;

constructor TDesktopLoadFixture.Create;
begin
  inherited Create;
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-DesktopLoad-' + TGUID.NewGuid.ToString);
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  FCounter := TStatementCounter.Create;
end;

destructor TDesktopLoadFixture.Destroy;
begin
  FCounter.Free;
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
  inherited;
end;

function TDesktopLoadFixture.NewDataModel: TDataModel;
begin
  Result := TDataModel.Create(FNotebook.Connection, FNotebook.Principal.Id,
    FNotebook.AccessPolicy, FNotebook.Storage);
end;

procedure TDesktopLoadFixture.Build(N: Integer);
var
  Data: TDataModel;
  UserId, I, Slot: Integer;
  ProjectA, ProjectB: TProject;
  Foreign: TUser;
  FileType: TFileType;
  ValueType: TValueType;
  LinkType: TLinkType;
  Tags: array[0..2] of TTag;
  Detached, Item: TItem;
  Row: unit_Item.TValue;
  Hypothesis: THypothesis;
  Run: THypothesisRun;
  Created: TItemLink;
begin
  if N < 4 then
    raise EArgumentException.Create('The fixture needs at least 4 items');
  Data := NewDataModel;
  try
    UserId := Data.User.Id;

    FileType := TFileType.Create;
    FileType.Ext := '.txt';
    FileType.CreatedDate := Now;
    Data.Manager.Save(FileType);
    ValueType := TValueType.Create;
    ValueType.Symbol := 'DL';
    ValueType.Title := 'Desktop load';
    ValueType.Units := 'nm';
    ValueType.CreatedDate := Now;
    ValueType.CreatedBy := UserId;
    Data.Manager.Save(ValueType);
    Data.Manager.Flush;
    LinkType := Data.LinkTypes.Add('relates to', 'is related by', '', 1);
    for I := 0 to 2 do
      Tags[I] := Data.Tags.AddTag('T' + IntToStr(I + 1), '#336699', UserId);

    ProjectA := Data.Projects.AddProject('Project A', '', Data.User);
    FProjectAId := ProjectA.Id;
    Data.Projects.AddFolder('Folder FA', '', FProjectAId, 0);
    Data.Projects.AddFolder('Folder FA2', '', FProjectAId, 0);
    FFolderAId := ProjectA.Folders[0].Id;
    FFolderA2Id := ProjectA.Folders[1].Id;

    Foreign := TUser.Create;
    Foreign.Username := 'foreign-owner';
    Foreign.FirstName := 'Synthetic';
    Foreign.LastName := 'Foreign';
    Foreign.Password := Data.User.Password;
    Foreign.Role := dbAdmin;
    Foreign.CreatedDate := Now;
    Data.Manager.Save(Foreign);
    Data.Manager.Flush;
    ProjectB := Data.Projects.AddProject('Project B', '', Foreign);
    FProjectBId := ProjectB.Id;
    Data.Projects.AddFolder('Folder FB', '', FProjectBId, 0);
    FFolderBId := ProjectB.Folders[0].Id;

    Data.Items.AssignProject(FProjectBId, FFolderBId);
    Detached := Data.Items.AddItem(TItemType.Other, 'B item', TItemLevel.Proc, 0,
      '', nil, nil, UserId);
    FBItemId := Detached.Id;
    Detached.Free;

    SetLength(FFolderA2ItemIds, 2);
    Data.Items.AssignProject(FProjectAId, FFolderA2Id);
    for I := 0 to 1 do
    begin
      Detached := Data.Items.AddItem(TItemType.Other, 'FA2 item ' + IntToStr(I + 1),
        TItemLevel.Proc, 0, '', nil, nil, UserId);
      FFolderA2ItemIds[I] := Detached.Id;
      Detached.Free;
    end;

    Data.Items.AssignProject(FProjectAId, FFolderAId);
    SetLength(FItemIds, N);
    for I := 0 to N - 1 do
    begin
      Detached := Data.Items.AddItem(TItemType.Other, 'Item ' + IntToStr(I + 1),
        TItemLevel.Proc, 0, '', nil, nil, UserId);
      FItemIds[I] := Detached.Id;
      Detached.Free;
      Item := Data.Manager.Find<TItem>(FItemIds[I]);
      Data.Items.AddNote('Entry ' + IntToStr(I + 1), '', UserId, Item);
      Data.Items.AddProtocol('Protocol ' + IntToStr(I + 1), ptExperiment, 0,
        UserId, Item);
      Data.Items.AddFile(FileType, 'first.txt', UserId, Item);
      Data.Items.AddFile(FileType, 'second.txt', UserId, Item);
      for Slot := 1 to 2 do
      begin
        Row := unit_Item.TValue.Create;
        Row.Item := Item;
        Row.ValueType := ValueType;
        Row.Value := Slot;
        Row.CreatedBy := UserId;
        Row.CreatedDate := Now;
        Item.Values.Add(Row);
      end;
      Data.Manager.Flush;
      Data.Tags.AssignTag(FItemIds[I], Tags[I mod 3].Id);
      if I mod 4 = 0 then
        Data.Tags.AssignTag(FItemIds[I], Tags[(I + 1) mod 3].Id);
      if I mod 2 = 0 then
        Data.Comments.AddComment(FItemIds[I], UserId, 'Synthetic', 'Comment');
    end;

    Hypothesis := THypothesis.Create;
    Hypothesis.ProjectId := FProjectAId;
    Hypothesis.Title := 'Synthetic expectation';
    Hypothesis.Statement := 'Synthetic statement';
    Hypothesis.CreatedBy := UserId;
    Hypothesis.CreatedDate := Now;
    Data.Manager.Save(Hypothesis);
    Data.Manager.Flush;
    Run := THypothesisRun.Create;
    Run.HypothesisId := Hypothesis.Id;
    Run.ItemId := FItemIds[1];
    Run.Role := hrrRun;
    Run.AddedBy := UserId;
    Run.AddedDate := Now;
    Data.Manager.Save(Run);
    Data.Manager.Flush;
    FRunItemId := FItemIds[1];

    Created := Data.ItemLinks.AddLink(FItemIds[0], FItemIds[1], LinkType.Id, '', UserId);
    Assert.IsNotNull(Created, 'link FA item 0 -> FA item 1');
    Created := Data.ItemLinks.AddLink(FItemIds[0], FBItemId, LinkType.Id, '', UserId);
    Assert.IsNotNull(Created, 'link FA item 0 -> foreign item');
    Created := Data.ItemLinks.AddLink(FItemIds[0], MissingId, LinkType.Id, '', UserId);
    Assert.IsNotNull(Created, 'link FA item 0 -> missing id');
    Created := Data.ItemLinks.AddLink(FBItemId, FItemIds[2], LinkType.Id, '', UserId);
    Assert.IsNotNull(Created, 'link foreign item -> FA item 2');
    Created := Data.ItemLinks.AddLink(MissingId, FItemIds[3], LinkType.Id, '', UserId);
    Assert.IsNotNull(Created, 'link missing id -> FA item 3');
    for I := 0 to N - 1 do
      Assert.AreEqual(ExpectedLinkCount(I), Data.ItemLinks.GetLinkCount(FItemIds[I]),
        'link count of FA item ' + IntToStr(I));
  finally
    Data.Free;
  end;
end;

function TDesktopLoadFixture.MissingItemId: Integer;
begin
  Result := MissingId;
end;

function TDesktopLoadFixture.ExpectedLinkCount(Index: Integer;
  ForeignReadable: Boolean): Integer;
begin
  case Index of
    0: Result := 2 + Ord(ForeignReadable);
    1, 3: Result := 1;
    2: Result := Ord(ForeignReadable);
  else
    Result := 0;
  end;
end;

function TDesktopLoadFixture.MeasureOpen: Integer;
var
  Data: TDataModel;
begin
  FCounter.Clear;
  Data := NewDataModel;
  try
    Data.History.LoadHistory(Data.User.Id);
    Data.TreeState.Load(Data.User.Id);
    Result := FCounter.Count;
    FLastBreakdown := BuildBreakdown;
  finally
    Data.Free;
  end;
end;

function TDesktopLoadFixture.MeasureProjectTree: Integer;
var
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Folders: TList<TFolder>;
  Groups: TProjectGroupList;
  Project: TProject;
begin
  Data := NewDataModel;
  try
    Vm := TProjectTreeVM.Create(Data.Projects, Data.Folders, Data.Favorites,
      Data.Authors, Data.History, Data.Items, Data.ProjectGroups);
    try
      Vm.TreeState := Data.TreeState;
      FCounter.Clear;
      Rows := Vm.GetProjects(0);
      try
        Groups := Vm.GetGroups(0);
        Groups.Free;
        for Project in Rows do
        begin
          Folders := Vm.GetSortedFolders(Project);
          Folders.Free;
        end;
      finally
        Rows.Free;
      end;
      Result := FCounter.Count;
      FLastBreakdown := BuildBreakdown;
    finally
      Vm.Free;
    end;
  finally
    Data.Free;
  end;
end;

procedure TDesktopLoadFixture.FillItemTree(Tree: TItemTreeVM);
var
  Items: TItems;
  Item: TItem;
  Entry: TLabEntry;
  AFile: unit_Item.TFile;
begin
  Tree.LoadItemData;
  Items := Tree.Items;
  try
    for Item in Items do
    begin
      for Entry in Tree.EntriesOf(Item) do
        if Entry is TProtocol then
          Inc(FTouched);
      if Item.Type_ <> TItemType.Wiki then
        for AFile in Tree.FilesOf(Item) do
          Inc(FTouched);
    end;
  finally
    Items.Free;
  end;
end;

procedure TDesktopLoadFixture.FilterAll(Tree: TItemTreeVM);
var
  Items: TItems;
  Item: TItem;
begin
  Tree.LoadItemData;
  Items := Tree.Items;
  try
    for Item in Items do
      if Tree.ItemMatchesFilter(Item) then
        Inc(FTouched);
  finally
    Items.Free;
  end;
end;

procedure TDesktopLoadFixture.PaintAll(Tree: TItemTreeVM);
var
  Items: TItems;
  Item: TItem;
  Row: unit_Item.TValue;
begin
  Items := Tree.Items;
  try
    for Item in Items do
      for Row in Tree.ValuesOf(Item) do
        if Row.ValueType.Symbol <> '' then
          Inc(FTouched);
  finally
    Items.Free;
  end;
end;

procedure TDesktopLoadFixture.CreateItemTreeVm(out Data: TDataModel;
  out Vm: TItemTreeVM);
begin
  Vm := nil;
  Data := NewDataModel;
  try
    Vm := TItemTreeVM.Create(Data.Items, Data.Authors, Data.History,
      Data.Signatures, Data.Comments, Data.Tags, Data.ItemLinks, Data.Access);
    Vm.SetHypothesisManager(Data.Manager);
    Vm.TreeState := Data.TreeState;
    Vm.SetLocation(FProjectAId, FFolderAId, paReadWrite);
  except
    FreeAndNil(Vm);
    FreeAndNil(Data);
    raise;
  end;
end;

function TDesktopLoadFixture.MeasureItemTree(Warm: Boolean): Integer;
var
  Data: TDataModel;
  Vm: TItemTreeVM;
begin
  CreateItemTreeVm(Data, Vm);
  try
    if Warm then
      FillItemTree(Vm);
    FTouched := 0;
    FCounter.Clear;
    FillItemTree(Vm);
    Result := FCounter.Count;
    FLastBreakdown := BuildBreakdown;
  finally
    Vm.Free;
    Data.Free;
  end;
end;

function TDesktopLoadFixture.MeasureItemTreePhase(const Phase: string): Integer;
var
  Data: TDataModel;
  Vm: TItemTreeVM;
begin
  CreateItemTreeVm(Data, Vm);
  try
    FTouched := 0;
    if Phase = 'warm' then
      FillItemTree(Vm);
    if Phase = 'filter' then
      Vm.FilterText := 'no-such-text';
    if Phase = 'paint' then
      Vm.LoadItemData;
    FTouched := 0;
    FCounter.Clear;
    if (Phase = 'cold') or (Phase = 'warm') then
      FillItemTree(Vm)
    else if Phase = 'filter' then
      FilterAll(Vm)
    else if Phase = 'paint' then
      PaintAll(Vm)
    else
      raise EArgumentException.Create('Unknown phase ' + Phase);
    Result := FCounter.Count;
    FLastBreakdown := BuildBreakdown;
  finally
    Vm.Free;
    Data.Free;
  end;
end;

function TDesktopLoadFixture.BuildBreakdown: string;
var
  Table: string;
begin
  Result := '';
  for Table in ReportedTables do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Table + '=' +
      IntToStr(FCounter.CountMatching(SqlTable(Table)));
  end;
end;

function TDesktopLoadFixture.Breakdown: string;
begin
  Result := FLastBreakdown;
end;

procedure TDesktopLoadStatementTests.Report(const Path: string; N, Total: Integer;
  Fixture: TDesktopLoadFixture);
begin
  TDUnitX.CurrentRunner.Log(TLogLevel.Information,
    Format('%s N=%d: %d statements (%s)', [Path, N, Total, Fixture.Breakdown]));
  Assert.IsTrue(Total > 0, Path + ' issued no statements');
end;

procedure TDesktopLoadStatementTests.BaselineOpen;
var
  Sizes: TArray<Integer>;
  N: Integer;
  Fixture: TDesktopLoadFixture;
begin
  Sizes := [10, 30];
  for N in Sizes do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(N);
      Report('open', N, Fixture.MeasureOpen, Fixture);
    finally
      Fixture.Free;
    end;
  end;
end;

procedure TDesktopLoadStatementTests.OpenFixedStatements;
var
  Totals: array[0..1] of Integer;
  Sizes: TArray<Integer>;
  I: Integer;
  Table: string;
  Fixture: TDesktopLoadFixture;
begin
  Sizes := [10, 30];
  for I := 0 to High(Sizes) do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(Sizes[I]);
      Totals[I] := Fixture.MeasureOpen;
      for Table in ['LabEntries', 'Files', 'DataValues', 'Folders'] do
        Assert.AreEqual(0, Fixture.Counter.CountMatching(Table),
          Format('open N=%d %s: %s', [Sizes[I], Table, Fixture.Breakdown]));
    finally
      Fixture.Free;
    end;
  end;
  Assert.AreEqual(Totals[0], Totals[1],
    Format('open N=10: %d statements, N=30: %d statements',
      [Totals[0], Totals[1]]));
end;

procedure TDesktopLoadStatementTests.BaselineProjectTree;
var
  Sizes: TArray<Integer>;
  N: Integer;
  Fixture: TDesktopLoadFixture;
begin
  Sizes := [10, 30];
  for N in Sizes do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(N);
      Report('project-tree', N, Fixture.MeasureProjectTree, Fixture);
    finally
      Fixture.Free;
    end;
  end;
end;

procedure TDesktopLoadStatementTests.BaselineItemTreeCold;
var
  Sizes: TArray<Integer>;
  N: Integer;
  Fixture: TDesktopLoadFixture;
begin
  Sizes := [10, 30];
  for N in Sizes do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(N);
      Report('item-tree-cold', N, Fixture.MeasureItemTree(False), Fixture);
      Assert.AreEqual(4 * N, Fixture.Touched, 'entries and files read');
    finally
      Fixture.Free;
    end;
  end;
end;

procedure TDesktopLoadStatementTests.BaselineItemTreeWarm;
var
  Sizes: TArray<Integer>;
  N: Integer;
  Fixture: TDesktopLoadFixture;
begin
  Sizes := [10, 30];
  for N in Sizes do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(N);
      Report('item-tree-warm', N, Fixture.MeasureItemTree(True), Fixture);
      Assert.AreEqual(4 * N, Fixture.Touched, 'entries and files read');
    finally
      Fixture.Free;
    end;
  end;
end;

procedure FreeTagDictionary(var Dict: TDictionary<Integer, TTags>);
var
  Pair: TPair<Integer, TTags>;
begin
  if Dict = nil then
    Exit;
  for Pair in Dict do
    Pair.Value.Free;
  FreeAndNil(Dict);
end;

function SameTagList(A, B: TTags): Boolean;
var
  I: Integer;
begin
  Result := A.Count = B.Count;
  if Result then
    for I := 0 to A.Count - 1 do
      if A[I] <> B[I] then
        Exit(False);
end;

procedure TDesktopLoadStatementTests.CheckLinkCounts(Fixture: TDesktopLoadFixture;
  Data: TDataModel; ForeignReadable: Boolean);
var
  Ids: TArray<Integer>;
  Counts: TDictionary<Integer, Integer>;
  Id, I: Integer;
begin
  if ForeignReadable then
    Data.ItemLinks.SetAccessFilter([Fixture.ProjectAId, Fixture.ProjectBId], False)
  else
    Data.ItemLinks.SetAccessFilter([Fixture.ProjectAId], False);
  Ids := Fixture.ItemIds + [Fixture.ForeignItemId, Fixture.MissingItemId];
  Counts := Data.ItemLinks.GetLinkCounts(Ids);
  try
    Assert.AreEqual(Length(Ids), Counts.Count, 'one entry per id');
    for Id in Ids do
      Assert.AreEqual(Data.ItemLinks.GetLinkCount(Id), Counts[Id],
        'batch link count of item ' + IntToStr(Id));
    for I := 0 to High(Fixture.ItemIds) do
      Assert.AreEqual(Fixture.ExpectedLinkCount(I, ForeignReadable),
        Counts[Fixture.ItemIds[I]], 'expected link count of FA item ' + IntToStr(I));
  finally
    Counts.Free;
  end;
end;

procedure TDesktopLoadStatementTests.BatchTagsEqualPerItem;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Ids: TArray<Integer>;
  Batch: TDictionary<Integer, TTags>;
  Single: TTags;
  Id: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Ids := Fixture.ItemIds + [Fixture.ForeignItemId, Fixture.MissingItemId];
      Batch := Data.Tags.GetTagsForItems(Ids);
      try
        Assert.AreEqual(Length(Ids), Batch.Count, 'one entry per id');
        for Id in Ids do
        begin
          Single := Data.Tags.GetTagsForItem(Id);
          try
            Assert.IsTrue(SameTagList(Single, Batch[Id]),
              'same tag objects in the same order for item ' + IntToStr(Id));
          finally
            Single.Free;
          end;
        end;
        Assert.AreEqual<Integer>(2, Batch[Fixture.ItemIds[0]].Count, 'item 0 holds two tags');
      finally
        FreeTagDictionary(Batch);
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TDesktopLoadStatementTests.BatchLinkCountsEqualPerItem;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      CheckLinkCounts(Fixture, Data, True);
      CheckLinkCounts(Fixture, Data, False);
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TDesktopLoadStatementTests.LinkCountsSelfAndDuplicateLinks;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Types: TList<TLinkType>;
  LinkType: TLinkType;
  Counts: TDictionary<Integer, Integer>;
  Pairs: array[0..3] of array[0..1] of Integer;
  Link: TItemLink;
  I, Id: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Types := Data.Manager.Find<TLinkType>.List;
      try
        LinkType := Types[0];
      finally
        Types.Free;
      end;
      Pairs[0][0] := Fixture.ItemIds[5];  Pairs[0][1] := Fixture.ItemIds[5];
      Pairs[1][0] := Fixture.ItemIds[6];  Pairs[1][1] := Fixture.ItemIds[7];
      Pairs[2][0] := Fixture.ItemIds[7];  Pairs[2][1] := Fixture.ItemIds[6];
      Pairs[3][0] := Fixture.ItemIds[6];  Pairs[3][1] := Fixture.ItemIds[7];
      for I := 0 to High(Pairs) do
      begin
        Link := TItemLink.Create;
        Link.SourceItemId := Pairs[I][0];
        Link.TargetItemId := Pairs[I][1];
        Link.LinkType := LinkType;
        Link.Label_ := 'synthetic';
        Link.CreatedBy := Data.User.Id;
        Link.CreatedDate := Now;
        Data.Manager.Save(Link);
      end;
      Data.Manager.Flush;
      Counts := Data.ItemLinks.GetLinkCounts(Fixture.ItemIds);
      try
        for Id in Fixture.ItemIds do
          Assert.AreEqual(Data.ItemLinks.GetLinkCount(Id), Counts[Id],
            'batch link count of item ' + IntToStr(Id));
        Assert.AreEqual(3, Counts[Fixture.ItemIds[6]], 'three links on one pair');
        Assert.AreEqual(3, Counts[Fixture.ItemIds[7]], 'three links on one pair');
        Assert.AreEqual(2, Counts[Fixture.ItemIds[5]], 'a self-link counts at both ends');
      finally
        Counts.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TDesktopLoadStatementTests.CommentCountsUnchanged;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  I, Expected: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Data.Comments.AddComment(Fixture.ItemIds[1], Data.User.Id, 'Synthetic', 'a');
      Data.Comments.AddComment(Fixture.ItemIds[1], Data.User.Id, 'Synthetic', 'b');
      Vm.LoadItemData;
      for I := 0 to High(Fixture.ItemIds) do
      begin
        if I = 1 then
          Expected := 2
        else if I mod 2 = 0 then
          Expected := 1
        else
          Expected := 0;
        Assert.AreEqual(Expected, Vm.GetCommentCount(Fixture.ItemIds[I]),
          'comment count of FA item ' + IntToStr(I));
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TDesktopLoadStatementTests.ItemsNoQueryAfterLoad;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Rows: TItems;
  Pass: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Fixture.Counter.Clear;
      for Pass := 1 to 2 do
      begin
        Rows := Vm.Items;
        try
          Assert.AreEqual<Integer>(10, Rows.Count, 'items of the folder');
        finally
          Rows.Free;
        end;
      end;
      Assert.AreEqual(0, Fixture.Counter.Count, 'Items after LoadItemData');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TDesktopLoadStatementTests.ItemsAfterSetLocationReloads;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Rows: TItems;
  Item: TItem;
  Expected: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Vm.SetLocation(Fixture.ProjectAId, Fixture.FolderA2Id, paReadWrite);
      Rows := Vm.Items;
      try
        Assert.AreEqual(Length(Fixture.FolderA2ItemIds), Rows.Count,
          'items of the second folder');
        for Item in Rows do
        begin
          Expected := 0;
          for var Id in Fixture.FolderA2ItemIds do
            if Id = Item.Id then
              Inc(Expected);
          Assert.AreEqual(1, Expected, 'item ' + IntToStr(Item.Id) + ' belongs to the second folder');
        end;
      finally
        Rows.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TDesktopLoadStatementTests.ItemTreeFixedStatements;
const
  Tables: array[0..3] of string = ('ItemTags', 'Tags', 'ItemLinks', 'Comments');
var
  Small: array[0..3] of Integer;
  Sizes: TArray<Integer>;
  Fixture: TDesktopLoadFixture;
  N, I: Integer;
begin
  Sizes := [10, 30];
  for N in Sizes do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(N);
      Fixture.MeasureItemTree(False);
      for I := 0 to High(Tables) do
        if N = 10 then
          Small[I] := Fixture.Counter.CountMatching(Tables[I])
        else
          Assert.AreEqual(Small[I], Fixture.Counter.CountMatching(Tables[I]),
            Tables[I] + ' statements at N=30 against N=10');
      if N = 10 then
      begin
        Assert.IsTrue(Small[0] > 0, 'ItemTags is read');
        Assert.IsTrue(Small[2] > 0, 'ItemLinks is read');
        Assert.IsTrue(Small[3] > 0, 'Comments is read');
      end;
    finally
      Fixture.Free;
    end;
  end;
end;

procedure TDesktopLoadStatementTests.ChunkingOver500;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  All, Head, Tail: TArray<Integer>;
  FullLinks, HeadLinks, TailLinks: TDictionary<Integer, Integer>;
  FullTags, HeadTags, TailTags: TDictionary<Integer, TTags>;
  I, Id, Expected: Integer;
  Part: TTags;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Data.ItemLinks.SetAccessFilter([Fixture.ProjectAId, Fixture.ProjectBId], False);
      SetLength(All, 501);
      for I := 0 to 8 do
        All[I] := Fixture.ItemIds[I + 1];
      for I := 9 to 499 do
        All[I] := 900000000 + I;
      All[500] := Fixture.ItemIds[0];
      Head := Copy(All, 0, 500);
      Tail := Copy(All, 500, 1);

      FullLinks := Data.ItemLinks.GetLinkCounts(All);
      HeadLinks := Data.ItemLinks.GetLinkCounts(Head);
      TailLinks := Data.ItemLinks.GetLinkCounts(Tail);
      FullTags := Data.Tags.GetTagsForItems(All);
      HeadTags := Data.Tags.GetTagsForItems(Head);
      TailTags := Data.Tags.GetTagsForItems(Tail);
      try
        Assert.AreEqual<Integer>(501, FullLinks.Count, 'link entries');
        Assert.AreEqual<Integer>(501, FullTags.Count, 'tag entries');
        for Id in All do
        begin
          if not HeadLinks.TryGetValue(Id, Expected) then
            Expected := TailLinks[Id];
          Assert.AreEqual(Expected, FullLinks[Id], 'link count of ' + IntToStr(Id));
          if not HeadTags.TryGetValue(Id, Part) then
            Part := TailTags[Id];
          Assert.IsTrue(SameTagList(Part, FullTags[Id]), 'tags of ' + IntToStr(Id));
        end;
        Assert.AreEqual(3, FullLinks[Fixture.ItemIds[0]], 'item 0 in the last chunk');
        Assert.AreEqual<Integer>(2, FullTags[Fixture.ItemIds[0]].Count, 'item 0 tags in the last chunk');
      finally
        FreeTagDictionary(FullTags);
        FreeTagDictionary(HeadTags);
        FreeTagDictionary(TailTags);
        FullLinks.Free;
        HeadLinks.Free;
        TailLinks.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TDesktopLoadStatementTests.RefreshTagsAfterBatch;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  ItemId, RemovedTagId: Integer;
  Direct: TTags;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      ItemId := Fixture.ItemIds[0];
      Vm.LoadItemData;
      Assert.AreEqual<Integer>(2, Vm.GetTagsForItem(ItemId).Count, 'tags before removal');
      RemovedTagId := Vm.GetTagsForItem(ItemId)[1].Id;
      Data.Tags.UnassignTag(ItemId, RemovedTagId);
      Vm.RefreshTagsForItem(ItemId);
      Direct := Data.Tags.GetTagsForItem(ItemId);
      try
        Assert.AreEqual<Integer>(1, Vm.GetTagsForItem(ItemId).Count, 'tags after refresh');
        Assert.IsTrue(SameTagList(Direct, Vm.GetTagsForItem(ItemId)), 'refresh result');
      finally
        Direct.Free;
      end;
      Vm.LoadItemData;
      Direct := Data.Tags.GetTagsForItem(ItemId);
      try
        Assert.AreEqual<Integer>(1, Vm.GetTagsForItem(ItemId).Count, 'tags after reload');
        Assert.IsTrue(SameTagList(Direct, Vm.GetTagsForItem(ItemId)), 'reload result');
      finally
        Direct.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

function Objects(Rows: TLabEntries): TArray<TObject>; overload;
var
  I: Integer;
begin
  SetLength(Result, Rows.Count);
  for I := 0 to Rows.Count - 1 do
    Result[I] := Rows[I];
end;

function Objects(Rows: TFiles): TArray<TObject>; overload;
var
  I: Integer;
begin
  SetLength(Result, Rows.Count);
  for I := 0 to Rows.Count - 1 do
    Result[I] := Rows[I];
end;

function Objects(Rows: TValues): TArray<TObject>; overload;
var
  I: Integer;
begin
  SetLength(Result, Rows.Count);
  for I := 0 to Rows.Count - 1 do
    Result[I] := Rows[I];
end;

procedure CheckSame(const Expected, Actual: TArray<TObject>; const What: string);
var
  I: Integer;
begin
  Assert.AreEqual<NativeInt>(Length(Expected), Length(Actual), What + ': count');
  for I := 0 to High(Expected) do
    Assert.AreSame(Expected[I], Actual[I], What + ': object ' + IntToStr(I));
end;

procedure CheckLookupsEqualLazy(Vm: TItemTreeVM; Items: TItems);
var
  Item: TItem;
  I: Integer;
  What: string;
  Lookup: TArray<TObject>;
begin
  for Item in Items do
  begin
    What := 'item ' + IntToStr(Item.Id);
    Lookup := Objects(Vm.EntriesOf(Item));
    CheckSame(Objects(Item.Entries), Lookup, What + ' entries');
    for I := 1 to High(Lookup) do
      Assert.IsTrue(TLabEntry(Lookup[I]).Id > TLabEntry(Lookup[I - 1]).Id,
        What + ' entries ascend');
    Lookup := Objects(Vm.FilesOf(Item));
    CheckSame(Objects(Item.Files), Lookup, What + ' files');
    for I := 1 to High(Lookup) do
      Assert.IsTrue(unit_Item.TFile(Lookup[I]).Id > unit_Item.TFile(Lookup[I - 1]).Id,
        What + ' files ascend');
    Lookup := Objects(Vm.ValuesOf(Item));
    CheckSame(Objects(Item.Values), Lookup, What + ' values');
    for I := 1 to High(Lookup) do
      Assert.IsTrue(unit_Item.TValue(Lookup[I]).Id > unit_Item.TValue(Lookup[I - 1]).Id,
        What + ' values ascend');
  end;
end;

function ChildCount(Vm: TItemTreeVM; Item: TItem): Integer;
begin
  Result := Vm.EntriesOf(Item).Count + Vm.FilesOf(Item).Count +
    Vm.ValuesOf(Item).Count;
end;

function LookupChildren(Vm: TItemTreeVM; Items: TItems): TList<TObject>;
var
  Item: TItem;
  Child: TObject;
begin
  Result := TList<TObject>.Create;
  for Item in Items do
  begin
    for Child in Objects(Vm.EntriesOf(Item)) do
      Result.Add(Child);
    for Child in Objects(Vm.FilesOf(Item)) do
      Result.Add(Child);
    for Child in Objects(Vm.ValuesOf(Item)) do
      Result.Add(Child);
  end;
end;

{$WARN SYMBOL_PLATFORM OFF}
function AllocatedBytes: NativeInt;
var
  State: TMemoryManagerState;
  Small: TSmallBlockTypeState;
begin
  GetMemoryManagerState(State);
  Result := State.TotalAllocatedMediumBlockSize + State.TotalAllocatedLargeBlockSize;
  for Small in State.SmallBlockTypeStates do
    Inc(Result, NativeInt(Small.UseableBlockSize) * NativeInt(Small.AllocatedBlockCount));
end;
{$WARN SYMBOL_PLATFORM ON}

procedure TItemTreeLookupTests.AddLateFile(Fixture: TDesktopLoadFixture;
  ItemId: Integer);
var
  Writer: TDataModel;
  Item: TItem;
  Types: TList<TFileType>;
begin
  Writer := Fixture.NewDataModel;
  try
    Types := Writer.Manager.Find<TFileType>.List;
    try
      Item := Writer.Manager.Find<TItem>(ItemId);
      Assert.IsNotNull(Writer.Items.AddFile(Types[0], 'late.txt', Writer.User.Id,
        Item), 'late file added');
    finally
      Types.Free;
    end;
  finally
    Writer.Free;
  end;
end;

procedure TItemTreeLookupTests.ReplaceThroughSecondManager(
  Fixture: TDesktopLoadFixture);
var
  Writer: TDataModel;
  Id: Integer;
  Item: TItem;
  AFile: unit_Item.TFile;
  Row: unit_Item.TValue;
  Entry: TLabEntry;
begin
  Writer := Fixture.NewDataModel;
  try
    for Id in Fixture.ItemIds do
    begin
      Item := Writer.Manager.Find<TItem>(Id);
      for AFile in Item.Files do
      begin
        AFile.Title := 'replaced-' + IntToStr(AFile.Id);
        AFile.Hash := 'replaced-hash';
      end;
      for Row in Item.Values do
        Row.Value := Row.Value + 100;
      for Entry in Item.Entries do
        Entry.Title := 'replaced';
    end;
    Writer.Manager.Flush;
  finally
    Writer.Free;
  end;
end;

function TItemTreeLookupTests.EvictScenario(Fixture: TDesktopLoadFixture): Integer;
var
  Manager: TObjectManager;
  Items: TItemModel;
  Authors: TAuthorModel;
  History: TUserHistoryModel;
  Signatures: TSignatureModel;
  Comments: TCommentModel;
  Tags: TTagModel;
  Links: TItemLinkModel;
  Vm: TItemTreeVM;
  Held: TItems;
  Item: TItem;
begin
  Result := 0;
  Manager := TObjectManager.Create(Fixture.Notebook.Connection);
  try
    Items := TItemModel.Create(Manager);
    Authors := TAuthorModel.Create(Manager, Fixture.Notebook.Principal.Id);
    History := TUserHistoryModel.Create(Manager);
    Signatures := TSignatureModel.Create(Manager);
    Comments := TCommentModel.Create(Manager);
    Tags := TTagModel.Create(Manager);
    Links := TItemLinkModel.Create(Manager);
    Vm := TItemTreeVM.Create(Items, Authors, History, Signatures, Comments,
      Tags, Links, Fixture.Notebook.AccessPolicy);
    try
      Vm.SetLocation(Fixture.ProjectAId, Fixture.FolderAId, paReadWrite);
      Vm.LoadItemData;
      Held := Vm.Items;
      try
        for Item in Held do
          Inc(Result, ChildCount(Vm, Item));
        Vm.EvictCache;
        for Item in Held do
        begin
          Assert.IsFalse(Manager.IsAttached(Item), 'item evicted');
          Item.Free;
        end;
      finally
        Held.Free;
      end;
    finally
      Vm.Free;
      Links.Free;
      Tags.Free;
      Comments.Free;
      Signatures.Free;
      History.Free;
      Authors.Free;
      Items.Free;
    end;
  finally
    Manager.Free;
  end;
end;

procedure TItemTreeLookupTests.StatementsAreEqualAtNAnd3N;
const
  Phases: array[0..3] of string = ('cold', 'warm', 'filter', 'paint');
  Sizes: array[0..1] of Integer = (10, 30);
var
  Totals: array[0..3, 0..1] of Integer;
  Breakdowns: array[0..3, 0..1] of string;
  Fixture: TDesktopLoadFixture;
  P, S: Integer;
  Expected: Integer;
begin
  for S := 0 to 1 do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(Sizes[S]);
      for P := 0 to 3 do
      begin
        Totals[P, S] := Fixture.MeasureItemTreePhase(Phases[P]);
        Breakdowns[P, S] := Fixture.Breakdown;
        TDUnitX.CurrentRunner.Log(TLogLevel.Information,
          Format('item-tree-%s N=%d: %d statements (%s)',
            [Phases[P], Sizes[S], Totals[P, S], Breakdowns[P, S]]));
        case P of
          0, 1: Expected := 4 * Sizes[S];
          2: Expected := 0;
        else
          Expected := 2 * Sizes[S];
        end;
        Assert.AreEqual(Expected, Fixture.Touched, Phases[P] + ' rows touched');
      end;
    finally
      Fixture.Free;
    end;
  end;
  for P := 0 to 3 do
  begin
    Assert.AreEqual(Totals[P, 0], Totals[P, 1],
      Format('%s: N=10 %d statements (%s), N=30 %d statements (%s)',
        [Phases[P], Totals[P, 0], Breakdowns[P, 0], Totals[P, 1], Breakdowns[P, 1]]));
    Assert.AreEqual(Breakdowns[P, 0], Breakdowns[P, 1], Phases[P] + ' per table');
  end;
end;

procedure TItemTreeLookupTests.LookupsReadNoStatementAfterLoad;
const
  Tables: array[0..2] of string = ('LabEntries', 'Files', 'DataValues');
  Sizes: array[0..1] of Integer = (10, 30);
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  Item: TItem;
  Small: array[0..2] of Integer;
  S, T, Total: Integer;
begin
  for S := 0 to 1 do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(Sizes[S]);
      Fixture.CreateItemTreeVm(Data, Vm);
      try
        Fixture.Counter.Clear;
        Vm.LoadItemData;
        for T := 0 to High(Tables) do
        begin
          Assert.IsTrue(Fixture.Counter.CountMatching(Tables[T]) > 0,
            Tables[T] + ' is read by LoadItemData');
          if S = 0 then
            Small[T] := Fixture.Counter.CountMatching(Tables[T])
          else
            Assert.AreEqual(Small[T], Fixture.Counter.CountMatching(Tables[T]),
              Tables[T] + ' statements at N=30 against N=10');
        end;
        Items := Vm.Items;
        try
          Fixture.Counter.Clear;
          Total := 0;
          for Item in Items do
            Inc(Total, ChildCount(Vm, Item));
          Assert.AreEqual(6 * Sizes[S], Total, 'children read through the lookups');
          Assert.AreEqual(0, Fixture.Counter.Count, 'statements after LoadItemData');
        finally
          Items.Free;
        end;
      finally
        Vm.Free;
        Data.Free;
      end;
    finally
      Fixture.Free;
    end;
  end;
end;

procedure TItemTreeLookupTests.LookupsAreTheObjectsOfTheLazyListsInOrder;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  Item: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    AddLateFile(Fixture, Fixture.ItemIds[0]);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        Assert.AreEqual<NativeInt>(10, Items.Count, 'items of the folder');
        CheckLookupsEqualLazy(Vm, Items);
        for Item in Items do
          if Item.Id = Fixture.ItemIds[0] then
            Assert.AreEqual<NativeInt>(3, Vm.FilesOf(Item).Count,
              'the late file is the last file of the first item');
      finally
        Items.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.LookupsAcrossTheChunkBoundary;
const
  Positions: array[0..3] of Integer = (0, 499, 500, 504);
var
  Fixture: TDesktopLoadFixture;
  Data, Bulk: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  Item: TItem;
  Detached: TItem;
  Ids: TArray<Integer>;
  I, P, Original: Integer;
  Held: Boolean;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Bulk := Fixture.NewDataModel;
    try
      Bulk.Items.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
      for I := 1 to 495 do
      begin
        Detached := Bulk.Items.AddItem(TItemType.Other, 'Bulk ' + IntToStr(I),
          TItemLevel.Proc, 0, '', nil, nil, Bulk.User.Id);
        Detached.Free;
      end;
    finally
      Bulk.Free;
    end;
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Items := Vm.Items;
      try
        Assert.AreEqual<NativeInt>(505, Items.Count, 'items of the folder');
        SetLength(Ids, Items.Count);
        for I := 0 to Items.Count - 1 do
          Ids[I] := Items[I].Id;
      finally
        Items.Free;
      end;
      for P in Positions do
        AddLateFile(Fixture, Ids[P]);
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        for I := 0 to High(Ids) do
          Assert.AreEqual(Ids[I], Items[I].Id, 'the order of the items is stable');
        CheckLookupsEqualLazy(Vm, Items);
        for P in Positions do
          Assert.IsTrue(Vm.FilesOf(Items[P]).Count >= 1,
            'the item at position ' + IntToStr(P) + ' has its file');
        for I := 0 to Items.Count - 1 do
        begin
          Item := Items[I];
          Held := False;
          for Original in Fixture.ItemIds do
            if Original = Item.Id then
              Held := True;
          for P in Positions do
            if P = I then
              Held := True;
          if not Held then
            Assert.AreEqual<NativeInt>(0, Vm.FilesOf(Item).Count,
              'files of the bulk item ' + IntToStr(I));
        end;
      finally
        Items.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.FilterReadsThroughTheLookups;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  MatchedIds: TList<Integer>;

  function Matches(const Text: string): Integer;
  var
    Row: TItem;
  begin
    Vm.FilterText := Text;
    MatchedIds.Clear;
    for Row in Items do
      if Vm.ItemMatchesFilter(Row) then
        MatchedIds.Add(Row.Id);
    Result := MatchedIds.Count;
  end;

begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(10);
    Fixture.CreateItemTreeVm(Data, Vm);
    MatchedIds := TList<Integer>.Create;
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        Fixture.Counter.Clear;
        Assert.AreEqual(10, Matches(''), 'no filter');
        Assert.AreEqual(10, Matches('first.txt'), 'file title');
        Assert.AreEqual(1, Matches('Protocol 3'), 'protocol title');
        Assert.AreEqual(Fixture.ItemIds[2], MatchedIds[0], 'protocol 3 belongs to item 3');
        Assert.AreEqual(1, Matches('Entry 4'), 'note title');
        Assert.AreEqual(Fixture.ItemIds[3], MatchedIds[0], 'entry 4 belongs to item 4');
        Assert.AreEqual(1, Matches('Item 7'), 'item title');
        Assert.AreEqual(Fixture.ItemIds[6], MatchedIds[0], 'item 7');
        Assert.AreEqual(0, Matches('no-such-text'), 'no match');
        Assert.AreEqual(0, Fixture.Counter.Count, 'statements of the filter');
      finally
        Items.Free;
      end;
    finally
      MatchedIds.Free;
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.MissAfterDoChangedFallsBackToTheLazyList;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  First, Second: TItem;
  FirstId, SecondId: Integer;
  Types: TList<TValueType>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        First := Items[0];
        FirstId := First.Id;
        SecondId := Items[1].Id;
      finally
        Items.Free;
      end;
      Types := Data.Manager.Find<TValueType>.List;
      try
        Vm.AddValue(Types[0], TRecType.EXP_CONDITION, 3.5, First, 0, 'late',
          TValueSourceInfo.Unknown);
      finally
        Types.Free;
      end;
      First := Data.Manager.Find<TItem>(FirstId);
      Second := Data.Manager.Find<TItem>(SecondId);
      Assert.AreEqual<NativeInt>(3, Vm.ValuesOf(First).Count, 'values of the changed item');
      Assert.AreEqual<NativeInt>(2, Vm.FilesOf(First).Count, 'files of the changed item');
      Assert.AreEqual<NativeInt>(2, Vm.EntriesOf(First).Count, 'entries of the changed item');
      Assert.AreEqual<NativeInt>(2, Vm.ValuesOf(Second).Count, 'values of an untouched item');
      Assert.AreEqual<NativeInt>(2, Vm.FilesOf(Second).Count, 'files of an untouched item');
      Assert.AreEqual<NativeInt>(2, Vm.EntriesOf(Second).Count, 'entries of an untouched item');
      Vm.LoadItemData;
      Assert.AreEqual<NativeInt>(3, Vm.ValuesOf(First).Count, 'values after the next load');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.MissForAnItemOutsideTheLookupFallsBack;
var
  Fixture: TDesktopLoadFixture;
  Data, Writer: TDataModel;
  Vm: TItemTreeVM;
  Detached, Added: TItem;
  AddedId: Integer;
  Types: TList<TFileType>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Writer := Fixture.NewDataModel;
      try
        Writer.Items.AssignProject(Fixture.ProjectAId, Fixture.FolderAId);
        Detached := Writer.Items.AddItem(TItemType.Other, 'Added late',
          TItemLevel.Proc, 0, '', nil, nil, Writer.User.Id);
        AddedId := Detached.Id;
        Detached.Free;
        Added := Writer.Manager.Find<TItem>(AddedId);
        Types := Writer.Manager.Find<TFileType>.List;
        try
          Assert.IsNotNull(Writer.Items.AddFile(Types[0], 'only.txt',
            Writer.User.Id, Added), 'file added');
        finally
          Types.Free;
        end;
      finally
        Writer.Free;
      end;
      Added := Data.Manager.Find<TItem>(AddedId);
      Assert.AreEqual<NativeInt>(1, Vm.FilesOf(Added).Count, 'files of an item outside the lookup');
      Assert.AreEqual<NativeInt>(0, Vm.ValuesOf(Added).Count, 'values of an item outside the lookup');
      Assert.AreEqual<NativeInt>(0, Vm.EntriesOf(Added).Count, 'entries of an item outside the lookup');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.MissAfterSetLocationFallsBack;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  First: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        First := Items[0];
      finally
        Items.Free;
      end;
      AddLateValue(Fixture, First.Id);
      Vm.SetLocation(Fixture.ProjectAId, Fixture.FolderA2Id, paReadWrite);
      Assert.AreEqual(7, ChildCount(Vm, First),
        'children of an item of the previous folder, with the value added after the load');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.AddLateValue(Fixture: TDesktopLoadFixture;
  ItemId: Integer);
var
  Writer: TDataModel;
  Item: TItem;
  Types: TList<TValueType>;
begin
  Writer := Fixture.NewDataModel;
  try
    Types := Writer.Manager.Find<TValueType>.List;
    try
      Item := Writer.Manager.Find<TItem>(ItemId);
      Writer.Items.AddValue(Types[0], TRecType.EXP_CONDITION, 9.5,
        Writer.User.Id, Item, 0, 'late', TValueSourceInfo.Unknown);
    finally
      Types.Free;
    end;
  finally
    Writer.Free;
  end;
end;

procedure TItemTreeLookupTests.ModelDeleteAfterLoadLeavesNoFreedObjectInThePaint;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  First: TItem;
  Victim, Row: unit_Item.TValue;
  Sum: Double;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        First := Items[0];
      finally
        Items.Free;
      end;
      Victim := Vm.ValuesOf(First)[0];
      Data.Items.RemoveValue(Victim, First, Data.User.Id);
      Assert.AreSame(First.Values, Vm.ValuesOf(First), 'the paint reads the own list');
      Assert.AreEqual<NativeInt>(1, Vm.ValuesOf(First).Count, 'values after the delete');
      Sum := 0;
      for Row in Vm.ValuesOf(First) do
        Sum := Sum + Row.Value;
      Assert.AreEqual<Double>(2, Sum, 'the remaining value');
      CheckSame(Objects(First.Values), Objects(Vm.ValuesOf(First)), 'shown values');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.ModelAddAfterLoadShowsAtPaint;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  First: TItem;
  Types: TList<TValueType>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        First := Items[0];
      finally
        Items.Free;
      end;
      Types := Data.Manager.Find<TValueType>.List;
      try
        Data.Items.AddValue(Types[0], TRecType.EXP_CONDITION, 3.5, Data.User.Id,
          First, 0, 'late', TValueSourceInfo.Unknown);
      finally
        Types.Free;
      end;
      Assert.AreEqual<NativeInt>(3, Vm.ValuesOf(First).Count, 'values at paint');
      CheckSame(Objects(First.Values), Objects(Vm.ValuesOf(First)), 'shown values');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.EvictCacheAfterAModelDeleteTouchesNoFreedObject;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Held: TItems;
  Item: TItem;
  First: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Held := Vm.Items;
      try
        First := Held[0];
        Data.Items.RemoveValue(Vm.ValuesOf(First)[0], First, Data.User.Id);
        Vm.EvictCache;
        for Item in Held do
          Item.Free;
      finally
        Held.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.LoadedListIsReadBeforeTheLookupAndKeepsTheOthersBatched;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  First, Second: TItem;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        First := Items[0];
        Second := Items[1];
      finally
        Items.Free;
      end;
      Assert.AreEqual<NativeInt>(2, First.Files.Count, 'file list of the first item loaded');
      Fixture.Counter.Clear;
      Assert.AreSame(First.Files, Vm.FilesOf(First), 'loaded list of the first item');
      Assert.AreEqual<NativeInt>(2, Vm.FilesOf(Second).Count, 'lookup of the second item');
      Assert.AreEqual(0, Fixture.Counter.Count, 'statements');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.EvictCacheEvictsTheOwnerOfAMovedItem;
var
  Fixture: TDesktopLoadFixture;
  Data, Writer: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  X, Moved, Again: TItem;
  XId: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        X := Items[0];
      finally
        Items.Free;
      end;
      XId := X.Id;
      Assert.AreEqual<NativeInt>(2, X.Files.Count, 'files of X');
      Assert.AreEqual<NativeInt>(2, X.Values.Count, 'values of X');
      Writer := Fixture.NewDataModel;
      try
        Moved := Writer.Manager.Find<TItem>(XId);
        Moved.FolderID := Fixture.FolderA2Id;
        Writer.Manager.Flush;
      finally
        Writer.Free;
      end;
      Vm.EvictCache;
      Assert.IsFalse(Data.Manager.IsAttached(X), 'X is evicted with its children');
      Vm.SetLocation(Fixture.ProjectAId, Fixture.FolderA2Id, paReadWrite);
      Vm.LoadItemData;
      Data.Manager.Flush;
      Again := Data.Manager.Find<TItem>(XId);
      Assert.AreNotSame(X, Again, 'X is read again');
      Assert.AreEqual<NativeInt>(2, Vm.FilesOf(Again).Count, 'files of X in the new folder');
      X.Free;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.EvictCacheAfterDoChangedWithoutRefillStillEvictsTheChildren;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Items: TItems;
  First, Second: TItem;
  SecondId: Integer;
  Types: TList<TValueType>;
  AFile: unit_Item.TFile;
  Checked: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Items := Vm.Items;
      try
        First := Items[0];
        SecondId := Items[1].Id;
      finally
        Items.Free;
      end;
      Types := Data.Manager.Find<TValueType>.List;
      try
        Vm.AddValue(Types[0], TRecType.EXP_CONDITION, 3.5, First, 0, 'late',
          TValueSourceInfo.Unknown);
      finally
        Types.Free;
      end;
      ReplaceThroughSecondManager(Fixture);
      Vm.EvictCache;
      Vm.LoadItemData;
      Second := Data.Manager.Find<TItem>(SecondId);
      Checked := 0;
      for AFile in Vm.FilesOf(Second) do
      begin
        Assert.AreEqual('replaced-' + IntToStr(AFile.Id), AFile.Title, 'file title after the refill');
        Inc(Checked);
      end;
      Assert.AreEqual(2, Checked, 'files checked');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.EvictedItemPaintsAndFiltersBeforeTheNextLoad;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Held: TItems;
  Item: TItem;
  Matched: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Held := Vm.Items;
      try
        Vm.EvictCache;
        for Item in Held do
        begin
          Assert.IsFalse(Data.Manager.IsAttached(Item), 'item evicted');
          Assert.AreEqual<NativeInt>(2, Vm.EntriesOf(Item).Count, 'entries of an evicted item');
          Assert.AreEqual<NativeInt>(2, Vm.FilesOf(Item).Count, 'files of an evicted item');
          Assert.AreEqual<NativeInt>(2, Vm.ValuesOf(Item).Count, 'values of an evicted item');
        end;
        Vm.FilterText := 'second.txt';
        Matched := 0;
        for Item in Held do
          if Vm.ItemMatchesFilter(Item) then
            Inc(Matched);
        Assert.AreEqual(4, Matched, 'file title of an evicted item');
        Vm.FilterText := 'Protocol 2';
        Matched := 0;
        for Item in Held do
          if Vm.ItemMatchesFilter(Item) then
            Inc(Matched);
        Assert.AreEqual(1, Matched, 'protocol title of an evicted item');
        for Item in Held do
          Item.Free;
      finally
        Held.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.EvictCacheDetachesTheLookupChildren;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Held: TItems;
  Children: TList<TObject>;
  Child: TObject;
  Item: TItem;
  OldFiles, NewFiles: TArray<TObject>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Held := Vm.Items;
      try
        Children := LookupChildren(Vm, Held);
        try
          Assert.AreEqual<NativeInt>(24, Children.Count, 'children held by the lookups');
          for Child in Children do
            Assert.IsTrue(Data.Manager.IsAttached(Child), 'child attached before EvictCache');
          OldFiles := Objects(Vm.FilesOf(Held[0]));
          Vm.EvictCache;
          for Child in Children do
            Assert.IsFalse(Data.Manager.IsAttached(Child), 'child attached after EvictCache');
        finally
          Children.Free;
        end;
        for Item in Held do
          Item.Free;
      finally
        Held.Free;
      end;
      Vm.LoadItemData;
      Held := Vm.Items;
      try
        for Item in Held do
          if Item.Id = Fixture.ItemIds[0] then
            NewFiles := Objects(Vm.FilesOf(Item));
        Assert.AreEqual<NativeInt>(2, Length(NewFiles), 'files after the refill');
        Assert.AreNotSame(OldFiles[0], NewFiles[0], 'a refill reads new objects');
      finally
        Held.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.EvictCacheGivesFreshDataAfterAReplaceThroughASecondManager;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TItemTreeVM;
  Held: TItems;
  Item: TItem;
  AFile: unit_Item.TFile;
  Row: unit_Item.TValue;
  Entry: TLabEntry;
  Checked: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Fixture.CreateItemTreeVm(Data, Vm);
    try
      Vm.LoadItemData;
      Held := Vm.Items;
      try
        for Item in Held do
          Assert.AreEqual(6, ChildCount(Vm, Item), 'children before the replace');
        ReplaceThroughSecondManager(Fixture);
        Vm.EvictCache;
        for Item in Held do
          Item.Free;
      finally
        Held.Free;
      end;
      Vm.LoadItemData;
      Held := Vm.Items;
      try
        Checked := 0;
        for Item in Held do
        begin
          for AFile in Vm.FilesOf(Item) do
          begin
            Assert.AreEqual('replaced-' + IntToStr(AFile.Id), AFile.Title, 'file title');
            Assert.AreEqual('replaced-hash', AFile.Hash, 'file hash');
            Inc(Checked);
          end;
          for Row in Vm.ValuesOf(Item) do
          begin
            Assert.IsTrue(Row.Value > 100, 'value ' + FloatToStr(Row.Value));
            Inc(Checked);
          end;
          for Entry in Vm.EntriesOf(Item) do
          begin
            Assert.AreEqual('replaced', Entry.Title, 'entry title');
            Inc(Checked);
          end;
        end;
        Assert.AreEqual(24, Checked, 'children checked');
      finally
        Held.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TItemTreeLookupTests.EvictCacheLeavesNothingBehind;
var
  Fixture: TDesktopLoadFixture;
  Before: NativeInt;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Assert.AreEqual(24, EvictScenario(Fixture), 'children read in the first run');
    Fixture.Counter.Clear;
    Before := AllocatedBytes;
    Assert.AreEqual(24, EvictScenario(Fixture), 'children read in the second run');
    Fixture.Counter.Clear;
    Assert.AreEqual<NativeInt>(0, AllocatedBytes - Before,
      'bytes left after EvictCache and freeing the evicted items');
  finally
    Fixture.Free;
  end;
end;


function ObjectsOf(Rows: TFoldersList): TArray<TObject>;
var
  I: Integer;
begin
  SetLength(Result, Rows.Count);
  for I := 0 to Rows.Count - 1 do
    Result[I] := Rows[I];
end;

function TitlesOf(Rows: TFoldersList): string;
var
  Folder: TFolder;
begin
  Result := '|';
  for Folder in Rows do
    Result := Result + Folder.Title + '|';
end;

function ProjectById(Rows: TList<TProject>; Id: Integer): TProject;
var
  Project: TProject;
begin
  Result := nil;
  for Project in Rows do
    if Project.Id = Id then
      Exit(Project);
end;

procedure TProjectTreeLookupTests.AddExtraProjects(Fixture: TDesktopLoadFixture;
  Count: Integer);
var
  Writer: TDataModel;
  K: Integer;
  Project: TProject;
begin
  Writer := Fixture.NewDataModel;
  try
    for K := 1 to Count do
    begin
      Project := Writer.Projects.AddProject('Extra ' + IntToStr(K), '', Writer.User);
      Writer.Projects.AddFolder('Zeta ' + IntToStr(K), '', Project.Id, 0);
      Writer.Projects.AddFolder('Omega ' + IntToStr(K), '', Project.Id, 0);
    end;
  finally
    Writer.Free;
  end;
end;

procedure TProjectTreeLookupTests.CreateProjectVm(Fixture: TDesktopLoadFixture;
  out Data: TDataModel; out Vm: TProjectTreeVM);
begin
  Vm := nil;
  Data := Fixture.NewDataModel;
  try
    Vm := TProjectTreeVM.Create(Data.Projects, Data.Folders, Data.Favorites,
      Data.Authors, Data.History, Data.Items, Data.ProjectGroups);
    Vm.TreeState := Data.TreeState;
  except
    FreeAndNil(Vm);
    FreeAndNil(Data);
    raise;
  end;
end;

procedure TProjectTreeLookupTests.AddFolderThroughSecondManager(
  Fixture: TDesktopLoadFixture; ProjectId: Integer; const Title: string);
var
  Writer: TDataModel;
begin
  Writer := Fixture.NewDataModel;
  try
    Writer.Projects.AddFolder(Title, '', ProjectId, 0);
  finally
    Writer.Free;
  end;
end;

function TProjectTreeLookupTests.FolderStatementsOfTheFill(
  Fixture: TDesktopLoadFixture; Vm: TProjectTreeVM; out Visible: Integer): Integer;
var
  Rows: TList<TProject>;
  Groups: TProjectGroupList;
  Folders: TList<TFolder>;
  Project: TProject;
begin
  Fixture.Counter.Clear;
  Rows := Vm.GetProjects(0);
  try
    Groups := Vm.GetGroups(0);
    Groups.Free;
    for Project in Rows do
    begin
      Folders := Vm.GetSortedFolders(Project);
      Folders.Free;
    end;
    Visible := Rows.Count;
  finally
    Rows.Free;
  end;
  Result := Fixture.Counter.CountMatching('Folders');
end;

procedure TProjectTreeLookupTests.FolderStatementsAreConstantAtTwoAndSixProjects;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  I: Integer;
  Counts, Visible: array[0..1] of Integer;
begin
  for I := 0 to 1 do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(4);
      AddExtraProjects(Fixture, 1 + I * 4);
      CreateProjectVm(Fixture, Data, Vm);
      try
        Counts[I] := FolderStatementsOfTheFill(Fixture, Vm, Visible[I]);
        TDUnitX.CurrentRunner.Log(TLogLevel.Information,
          Format('project-tree visible=%d: %d Folders statements, %d statements in all',
            [Visible[I], Counts[I], Fixture.Counter.Count]));
      finally
        Vm.Free;
        Data.Free;
      end;
    finally
      Fixture.Free;
    end;
  end;
  Assert.AreEqual(2, Visible[0], 'visible projects, small tree');
  Assert.AreEqual(6, Visible[1], 'visible projects, large tree');
  Assert.AreEqual(2, Counts[0], 'Folders statements at 2 projects');
  Assert.AreEqual(2, Counts[1], 'Folders statements at 6 projects');
end;

procedure TProjectTreeLookupTests.LookupIsTheFoldersOfEachProjectInOrder;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Project: TProject;
  Lookup: TArray<TArray<TObject>>;
  Sorted: TList<TFolder>;
  I: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddExtraProjects(Fixture, 5);
    CreateProjectVm(Fixture, Data, Vm);
    try
      Rows := Vm.GetProjects(0);
      try
        Assert.AreEqual<NativeInt>(6, Rows.Count, 'visible projects');
        SetLength(Lookup, Rows.Count);
        for I := 0 to Rows.Count - 1 do
        begin
          Assert.IsFalse(Rows[I].FoldersLoaded, 'folders not loaded by the fill');
          Lookup[I] := ObjectsOf(Vm.FoldersOf(Rows[I]));
        end;
        for I := 0 to Rows.Count - 1 do
        begin
          Project := Rows[I];
          CheckSame(ObjectsOf(Project.Folders), Lookup[I],
            'project ' + IntToStr(Project.Id));
          Assert.IsTrue(Length(Lookup[I]) > 0, 'folders of project ' + IntToStr(Project.Id));
        end;
        Assert.AreEqual<NativeInt>(2, Length(Lookup[Rows.IndexOf(ProjectById(Rows,
          Fixture.ProjectAId))]), 'folders of the first project');
        for I := 0 to Rows.Count - 1 do
        begin
          Sorted := Vm.GetSortedFolders(Rows[I]);
          try
            CheckSame(ObjectsOf(Rows[I].Folders), ObjectsOf(Sorted),
              'sorted folders of project ' + IntToStr(Rows[I].Id));
          finally
            Sorted.Free;
          end;
        end;
      finally
        Rows.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.DeletingAFolderTheLookupHoldsReadsNoFreedFolder;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  ProjectA: TProject;
  Folder: TFolder;
  EmptyId: Integer;
  Sorted: TList<TFolder>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddFolderThroughSecondManager(Fixture, Fixture.ProjectAId, 'Empty');
    CreateProjectVm(Fixture, Data, Vm);
    try
      Rows := Vm.GetProjects(0);
      try
        ProjectA := ProjectById(Rows, Fixture.ProjectAId);
        Assert.IsFalse(ProjectA.FoldersLoaded, 'list not loaded after the fill');
        Assert.AreEqual<NativeInt>(3, Vm.FoldersOf(ProjectA).Count, 'folders from the lookup');
        EmptyId := 0;
        for Folder in Vm.FoldersOf(ProjectA) do
          if Folder.Title = 'Empty' then
            EmptyId := Folder.Id;
        Assert.IsTrue(EmptyId > 0, 'the lookup holds the empty folder');

        Assert.IsTrue(Data.Folders.DeleteFolder(EmptyId, ProjectA.Id, Data.User.Id),
          'folder deleted');
        Assert.IsTrue(ProjectA.FoldersLoaded, 'the delete loads the project''s own list');
        Assert.AreSame(ProjectA.Folders, Vm.FoldersOf(ProjectA), 'own list after a delete');
        Assert.AreEqual<NativeInt>(2, Vm.FoldersOf(ProjectA).Count, 'folders after a delete');
        Assert.IsTrue(Pos('|Empty|', TitlesOf(Vm.FoldersOf(ProjectA))) = 0, 'deleted folder gone');
        Sorted := Vm.GetSortedFolders(ProjectA);
        try
          Assert.AreEqual<NativeInt>(2, Sorted.Count, 'sorted folders after a delete');
        finally
          Sorted.Free;
        end;
      finally
        Rows.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.LookupAcrossTheChunkBoundary;
const
  Extra = 500;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Lookup, SortedLookup: TArray<TArray<TObject>>;
  Sorted: TList<TFolder>;
  I, Total: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddExtraProjects(Fixture, Extra);
    CreateProjectVm(Fixture, Data, Vm);
    try
      Rows := Vm.GetProjects(0);
      try
        Assert.AreEqual<NativeInt>(Extra + 1, Rows.Count, 'visible projects, over one chunk');
        SetLength(Lookup, Rows.Count);
        SetLength(SortedLookup, Rows.Count);
        Total := 0;
        for I := 0 to Rows.Count - 1 do
        begin
          Assert.IsFalse(Rows[I].FoldersLoaded, 'folders not loaded by the fill');
          Lookup[I] := ObjectsOf(Vm.FoldersOf(Rows[I]));
          Sorted := Vm.GetSortedFolders(Rows[I]);
          try
            SortedLookup[I] := ObjectsOf(Sorted);
          finally
            Sorted.Free;
          end;
          Assert.AreEqual<NativeInt>(2, Length(Lookup[I]), 'folders of project ' + IntToStr(Rows[I].Id));
          Inc(Total, Length(Lookup[I]));
        end;
        Assert.AreEqual(2 * (Extra + 1), Total, 'folders over more than one chunk');
        for I := 0 to Rows.Count - 1 do
        begin
          CheckSame(ObjectsOf(Rows[I].Folders), Lookup[I], 'project ' + IntToStr(Rows[I].Id));
          Sorted := Vm.GetSortedFolders(Rows[I]);
          try
            CheckSame(ObjectsOf(Sorted), SortedLookup[I],
              'sorted folders of project ' + IntToStr(Rows[I].Id));
          finally
            Sorted.Free;
          end;
        end;
      finally
        Rows.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.FilterReadsThroughTheLookup;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Folders: TList<TFolder>;
  AfterFill: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddExtraProjects(Fixture, 5);
    CreateProjectVm(Fixture, Data, Vm);
    try
      Vm.FilterText := 'Zeta 2';
      Fixture.Counter.Clear;
      Rows := Vm.GetProjects(0);
      try
        AfterFill := Fixture.Counter.CountMatching('Folders');
        Assert.AreEqual<NativeInt>(1, Rows.Count, 'projects that pass the filter');
        Assert.AreEqual('Extra 2', Rows[0].Title, 'project of the matching folder');
        Assert.AreEqual(2, AfterFill, 'Folders statements of the filter at 6 projects');
        Folders := Vm.GetSortedFolders(Rows[0]);
        try
          Assert.AreEqual<NativeInt>(2, Folders.Count, 'folders of the matching project');
        finally
          Folders.Free;
        end;
        Assert.AreEqual(AfterFill, Fixture.Counter.CountMatching('Folders'),
          'GetSortedFolders after the fill');
      finally
        Rows.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.LoadedOwnListWinsOverTheLookup;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  ProjectA: TProject;
  Folder, Late: TFolder;
  Sorted: TList<TFolder>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    CreateProjectVm(Fixture, Data, Vm);
    try
      Rows := Vm.GetProjects(0);
      try
        ProjectA := ProjectById(Rows, Fixture.ProjectAId);
        Assert.IsFalse(ProjectA.FoldersLoaded, 'list not loaded after the fill');

        Data.Projects.AddFolder('Late', '', ProjectA.Id, 0);
        Assert.AreSame(ProjectA.Folders, Vm.FoldersOf(ProjectA), 'own list after an add');
        Assert.IsTrue(Pos('|Late|', TitlesOf(Vm.FoldersOf(ProjectA))) > 0, 'added folder shows');
        Sorted := Vm.GetSortedFolders(ProjectA);
        try
          Assert.AreEqual<NativeInt>(3, Sorted.Count, 'sorted folders after an add');
        finally
          Sorted.Free;
        end;

        Folder := Vm.FoldersOf(ProjectA)[0];
        Folder.Title := 'Renamed';
        Assert.IsTrue(Data.Folders.Update(Folder, Data.User.Id), 'folder renamed');
        Assert.IsTrue(Pos('|Renamed|', TitlesOf(Vm.FoldersOf(ProjectA))) > 0, 'rename shows');

        Late := nil;
        for Folder in Vm.FoldersOf(ProjectA) do
          if Folder.Title = 'Late' then
            Late := Folder;
        Assert.IsNotNull(Late, 'late folder');
        Assert.IsTrue(Data.Folders.DeleteFolder(Late.Id, ProjectA.Id, Data.User.Id),
          'late folder deleted');
        Assert.AreEqual<NativeInt>(2, Vm.FoldersOf(ProjectA).Count, 'folders after a delete');
        Assert.IsTrue(Pos('|Late|', TitlesOf(Vm.FoldersOf(ProjectA))) = 0, 'deleted folder gone');
        Sorted := Vm.GetSortedFolders(ProjectA);
        try
          Assert.AreEqual<NativeInt>(2, Sorted.Count, 'sorted folders after a delete');
        finally
          Sorted.Free;
        end;
      finally
        Rows.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.EvictedProjectIsFoundAgainBeforeItsFoldersAreRead;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Projects: TList<TProject>;
  Folders: TList<TFolder>;
  HeldProjects: TArray<TProject>;
  HeldFolders: TArray<TFolder>;
  Expected: TDictionary<Integer, Integer>;
  Project: TProject;
  Folder: TFolder;
  Sorted: TList<TFolder>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddExtraProjects(Fixture, 2);
    CreateProjectVm(Fixture, Data, Vm);
    Expected := TDictionary<Integer, Integer>.Create;
    try
      Rows := Vm.GetProjects(0);
      try
        for Project in Rows do
          Expected.Add(Project.Id, Vm.FoldersOf(Project).Count);
        Assert.AreEqual<NativeInt>(2, Expected[Fixture.ProjectAId],
          'folders of the first project');
        Assert.AreEqual<NativeInt>(2, ProjectById(Rows, Fixture.ProjectAId).Folders.Count,
          'the first project now has its list loaded');
      finally
        Rows.Free;
      end;
      Projects := Data.Manager.Find<TProject>.List;
      Folders := Data.Manager.Find<TFolder>.List;
      try
        HeldProjects := Projects.ToArray;
        HeldFolders := Folders.ToArray;
      finally
        Projects.Free;
        Folders.Free;
      end;
      Vm.EvictCache;
      for Project in HeldProjects do
      begin
        Assert.IsFalse(Data.Manager.IsAttached(Project), 'project evicted');
        if not Expected.ContainsKey(Project.Id) then
          Continue;
        Assert.AreEqual<NativeInt>(Expected[Project.Id], Vm.FoldersOf(Project).Count,
          'folders of an evicted project ' + IntToStr(Project.Id));
        for Folder in Vm.FoldersOf(Project) do
          Assert.IsTrue(Data.Manager.IsAttached(Folder),
            'folder of an evicted project is a live object');
        Sorted := Vm.GetSortedFolders(Project);
        try
          Assert.AreEqual<NativeInt>(Expected[Project.Id], Sorted.Count,
            'sorted folders of an evicted project ' + IntToStr(Project.Id));
        finally
          Sorted.Free;
        end;
      end;
      for Project in HeldProjects do
        Project.Free;
      for Folder in HeldFolders do
        Folder.Free;
    finally
      Expected.Free;
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.EvictCacheDropsTheLookup;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Projects: TList<TProject>;
  Folders: TList<TFolder>;
  HeldProjects: TArray<TProject>;
  HeldFolders: TArray<TFolder>;
  Project: TProject;
  Folder: TFolder;
  Sorted: TList<TFolder>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    CreateProjectVm(Fixture, Data, Vm);
    try
      Rows := Vm.GetProjects(0);
      Rows.Free;
      AddFolderThroughSecondManager(Fixture, Fixture.ProjectAId, 'Late');
      Projects := Data.Manager.Find<TProject>.List;
      Folders := Data.Manager.Find<TFolder>.List;
      try
        HeldProjects := Projects.ToArray;
        HeldFolders := Folders.ToArray;
      finally
        Projects.Free;
        Folders.Free;
      end;
      Vm.EvictCache;
      Sorted := Vm.GetSortedFolders(Data.Manager.Find<TProject>(Fixture.ProjectAId));
      try
        Assert.AreEqual<NativeInt>(3, Sorted.Count, 'folders read after EvictCache');
      finally
        Sorted.Free;
      end;
      for Project in HeldProjects do
        Project.Free;
      for Folder in HeldFolders do
        Folder.Free;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.DoChangedDropsTheLookup;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Ids: TArray<Integer>;
  Sorted: TList<TFolder>;
  I: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    CreateProjectVm(Fixture, Data, Vm);
    try
      Rows := Vm.GetProjects(0);
      try
        SetLength(Ids, Rows.Count);
        for I := 0 to Rows.Count - 1 do
          Ids[I] := Rows[I].Id;
      finally
        Rows.Free;
      end;
      AddFolderThroughSecondManager(Fixture, Fixture.ProjectAId, 'Late');
      Vm.ReorderProjects(Ids);
      Sorted := Vm.GetSortedFolders(Data.Manager.Find<TProject>(Fixture.ProjectAId));
      try
        Assert.AreEqual<NativeInt>(3, Sorted.Count, 'folders read after DoChanged');
      finally
        Sorted.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.ANewFillRefreshesTheLookup;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Sorted: TList<TFolder>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    CreateProjectVm(Fixture, Data, Vm);
    try
      Rows := Vm.GetProjects(0);
      Rows.Free;
      AddFolderThroughSecondManager(Fixture, Fixture.ProjectAId, 'Late');
      Rows := Vm.GetProjects(0);
      try
        Sorted := Vm.GetSortedFolders(ProjectById(Rows, Fixture.ProjectAId));
        try
          Assert.AreEqual<NativeInt>(3, Sorted.Count, 'folders after a second fill');
        finally
          Sorted.Free;
        end;
      finally
        Rows.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

function TProjectTreeLookupTests.ProjectScenario(Fixture: TDesktopLoadFixture): Integer;
var
  Manager: TObjectManager;
  Projects: TProjectsModel;
  Folders: TFolderModel;
  Favorites: TFavoritesModel;
  Authors: TAuthorModel;
  History: TUserHistoryModel;
  Items: TItemModel;
  Groups: TProjectGroupModel;
  Vm: TProjectTreeVM;
  Rows: TList<TProject>;
  Project: TProject;
  Prior: Boolean;
begin
  Result := 0;
  Prior := unit_Project.ManagerShuttingDown;
  unit_Project.ManagerShuttingDown := False;
  try
    Manager := TObjectManager.Create(Fixture.Notebook.Connection);
    try
      Projects := TProjectsModel.Create(Manager, Fixture.Notebook.AccessPolicy);
      Folders := TFolderModel.Create(Manager);
      Favorites := TFavoritesModel.Create(Manager);
      Authors := TAuthorModel.Create(Manager, Fixture.Notebook.Principal.Id);
      History := TUserHistoryModel.Create(Manager);
      Items := TItemModel.Create(Manager);
      Groups := TProjectGroupModel.Create(Manager);
      Vm := TProjectTreeVM.Create(Projects, Folders, Favorites, Authors,
        History, Items, Groups);
      try
        Rows := Vm.GetProjects(0);
        try
          for Project in Rows do
            Inc(Result, Vm.FoldersOf(Project).Count);
        finally
          Rows.Free;
        end;
      finally
        Vm.Free;
        Groups.Free;
        Items.Free;
        History.Free;
        Authors.Free;
        Favorites.Free;
        Folders.Free;
        Projects.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    unit_Project.ManagerShuttingDown := Prior;
  end;
end;

procedure TProjectTreeLookupTests.LookupLeavesNothingBehind;
var
  Fixture: TDesktopLoadFixture;
  Before: NativeInt;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    Assert.AreEqual(2, ProjectScenario(Fixture), 'folders read in the first run');
    Fixture.Counter.Clear;
    Before := AllocatedBytes;
    Assert.AreEqual(2, ProjectScenario(Fixture), 'folders read in the second run');
    Fixture.Counter.Clear;
    Assert.AreEqual<NativeInt>(0, AllocatedBytes - Before,
      'bytes left after the VM and the model are freed');
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.AddOwners(Fixture: TDesktopLoadFixture;
  Count: Integer);
var
  Writer: TDataModel;
  Owner: TUser;
  K, P: Integer;
  Project: TProject;
begin
  Writer := Fixture.NewDataModel;
  try
    for K := 1 to Count do
    begin
      Owner := TUser.Create;
      Owner.Username := 'owner-' + IntToStr(K);
      Owner.FirstName := 'Synthetic';
      Owner.LastName := 'Owner ' + IntToStr(K);
      Owner.Password := Writer.User.Password;
      Owner.Role := dbUser;
      Owner.CreatedDate := Now;
      Writer.Manager.Save(Owner);
      Writer.Manager.Flush;
      Writer.ProjectGroups.AddGroup('Group ' + IntToStr(K), Owner.Id);
      for P := 1 to 2 do
      begin
        Project := Writer.Projects.AddProject(
          Format('Owner %d project %d', [K, P]), '', Owner);
        Writer.Projects.AddFolder('Zeta', '', Project.Id, 0);
        Writer.Projects.AddFolder('Alpha', '', Project.Id, 0);
      end;
    end;
  finally
    Writer.Free;
  end;
end;

procedure TProjectTreeLookupTests.CreateSupervisorVm(Fixture: TDesktopLoadFixture;
  out Data: TDataModel; out Vm: TProjectTreeVM);
begin
  Vm := nil;
  Data := TDataModel.Create(Fixture.Notebook.Connection,
    Fixture.Notebook.Principal.Id,
    TSupervisorPolicy.Create(Fixture.Notebook.AccessPolicy),
    Fixture.Notebook.Storage);
  try
    Vm := TProjectTreeVM.Create(Data.Projects, Data.Folders, Data.Favorites,
      Data.Authors, Data.History, Data.Items, Data.ProjectGroups);
    Vm.TreeState := Data.TreeState;
    Assert.IsTrue(Vm.IsSupervisorMode, 'supervisor mode');
  except
    FreeAndNil(Vm);
    FreeAndNil(Data);
    raise;
  end;
end;

function TProjectTreeLookupTests.SupervisorFill(Fixture: TDesktopLoadFixture;
  Vm: TProjectTreeVM; out Owners, Projects, Groups: Integer): Integer;
var
  Tree: TOwnerTree;
  User: TUser;
  Project: TProject;
  Folders: TList<TFolder>;
begin
  Projects := 0;
  Groups := 0;
  Fixture.Counter.Clear;
  Tree := Vm.LoadOwnerTree;
  Assert.IsNotNull(Tree, 'supervisor with several owners gets owner nodes');
  try
    Owners := Tree.Users.Count;
    for User in Tree.Users do
    begin
      Inc(Groups, Tree.Groups[User.Id].Count);
      for Project in Tree.Projects[User.Id] do
      begin
        Inc(Projects);
        Folders := Vm.GetSortedFolders(Project);
        Folders.Free;
      end;
    end;
  finally
    Tree.Free;
  end;
  Result := Fixture.Counter.Count;
end;

procedure TProjectTreeLookupTests.SupervisorStatementsAreConstantAtTwoAndSixOwners;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  I: Integer;
  Counts, Owners, Projects, Groups: array[0..1] of Integer;
begin
  for I := 0 to 1 do
  begin
    Fixture := TDesktopLoadFixture.Create;
    try
      Fixture.Build(4);
      AddOwners(Fixture, 2 + I * 4);
      CreateSupervisorVm(Fixture, Data, Vm);
      try
        Counts[I] := SupervisorFill(Fixture, Vm, Owners[I], Projects[I], Groups[I]);
        TDUnitX.CurrentRunner.Log(TLogLevel.Information,
          Format('supervisor tree owners=%d projects=%d: %d statements, %d Folders',
            [Owners[I], Projects[I], Counts[I], Fixture.Counter.CountMatching('Folders')]));
      finally
        Vm.Free;
        Data.Free;
      end;
    finally
      Fixture.Free;
    end;
  end;
  Assert.AreEqual(4, Owners[1] - Owners[0], 'owner nodes added');
  Assert.AreEqual(8, Projects[1] - Projects[0], 'projects added');
  Assert.AreEqual(4, Groups[1] - Groups[0], 'groups added');
  Assert.AreEqual(Counts[0], Counts[1], 'statements at 2 and at 6 owners');
end;

procedure TProjectTreeLookupTests.OwnerGroupsAreTheProjectsOfEachOwnerInOrder;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Writer: TDataModel;
  Empty: TUser;
  EmptyId, I: Integer;
  Users: TList<TUser>;
  Ids: TArray<Integer>;
  ByOwner: TObjectDictionary<Integer, TList<TProject>>;
  Expected, Single: TList<TProject>;
  Total: Integer;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddOwners(Fixture, 2);
    Writer := Fixture.NewDataModel;
    try
      Empty := TUser.Create;
      Empty.Username := 'owner-without-projects';
      Empty.FirstName := 'Synthetic';
      Empty.LastName := 'Empty';
      Empty.Password := Writer.User.Password;
      Empty.Role := dbUser;
      Empty.CreatedDate := Now;
      Writer.Manager.Save(Empty);
      Writer.Manager.Flush;
      EmptyId := Empty.Id;
    finally
      Writer.Free;
    end;
    CreateSupervisorVm(Fixture, Data, Vm);
    try
      Users := Vm.GetUsers;
      try
        SetLength(Ids, Users.Count);
        for I := 0 to Users.Count - 1 do
          Ids[I] := Users[I].Id;
      finally
        Users.Free;
      end;
      Assert.AreEqual<NativeInt>(4, Length(Ids), 'principal, 2 owners, the empty owner');
      ByOwner := Vm.GetProjectsByOwner(Ids);
      try
        Assert.AreEqual<NativeInt>(0, ByOwner[EmptyId].Count, 'empty owner keeps an empty group');
        Total := 0;
        for I := 0 to High(Ids) do
        begin
          Expected := Data.Manager.Find<TProject>
            .Where(Linq['Owner.Id'] = Ids[I])
            .OrderBy('SortOrder').OrderBy('ID').List;
          Single := Vm.GetProjects(Ids[I]);
          try
            Assert.AreEqual<NativeInt>(Expected.Count, ByOwner[Ids[I]].Count, 'group size');
            Assert.AreEqual<NativeInt>(Expected.Count, Single.Count, 'GetProjects size');
            for var J := 0 to Expected.Count - 1 do
            begin
              Assert.AreEqual(Expected[J].Id, ByOwner[Ids[I]][J].Id, 'group order');
              Assert.AreEqual(Expected[J].Id, Single[J].Id, 'GetProjects order');
            end;
            Inc(Total, Expected.Count);
          finally
            Single.Free;
            Expected.Free;
          end;
        end;
        Assert.AreEqual(5, Total, 'Project A and 2 projects of each owner');
      finally
        ByOwner.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.OwnerGroupsKeepOnlyTheProjectWithAMatchingFolder;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Target: TList<TProject>;
  TargetId, TargetOwnerId, I: Integer;
  Users: TList<TUser>;
  Ids: TArray<Integer>;
  ByOwner: TObjectDictionary<Integer, TList<TProject>>;
  Single: TList<TProject>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddOwners(Fixture, 2);
    CreateSupervisorVm(Fixture, Data, Vm);
    try
      Target := Data.Manager.Find<TProject>
        .Where(Linq['Title'] = 'Owner 1 project 2').List;
      try
        Assert.AreEqual<NativeInt>(1, Target.Count, 'target project');
        TargetId := Target[0].Id;
        TargetOwnerId := Target[0].Owner.Id;
      finally
        Target.Free;
      end;
      AddFolderThroughSecondManager(Fixture, TargetId, 'Needle folder');
      Vm.EvictCache;
      Vm.FilterText := 'needle';
      Users := Vm.GetUsers;
      try
        SetLength(Ids, Users.Count);
        for I := 0 to Users.Count - 1 do
          Ids[I] := Users[I].Id;
      finally
        Users.Free;
      end;
      ByOwner := Vm.GetProjectsByOwner(Ids);
      try
        for I := 0 to High(Ids) do
        begin
          Single := Vm.GetProjects(Ids[I]);
          try
            if Ids[I] = TargetOwnerId then
            begin
              Assert.AreEqual<NativeInt>(1, ByOwner[Ids[I]].Count, 'target owner group');
              Assert.AreEqual(TargetId, ByOwner[Ids[I]][0].Id, 'project with the folder');
              Assert.AreEqual<NativeInt>(1, Single.Count, 'target owner GetProjects');
              Assert.AreEqual(TargetId, Single[0].Id, 'GetProjects project');
            end
            else
            begin
              Assert.AreEqual<NativeInt>(0, ByOwner[Ids[I]].Count, 'other owner group');
              Assert.AreEqual<NativeInt>(0, Single.Count, 'other owner GetProjects');
            end;
          finally
            Single.Free;
          end;
        end;
      finally
        ByOwner.Free;
      end;
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

function SortedIds(const Ids: TArray<Integer>): TArray<Integer>;
begin
  Result := Copy(Ids);
  TArray.Sort<Integer>(Result);
end;

function SameIds(const A, B: TArray<Integer>): Boolean;
var
  SortedA, SortedB: TArray<Integer>;
  I: Integer;
begin
  SortedA := SortedIds(A);
  SortedB := SortedIds(B);
  Result := Length(SortedA) = Length(SortedB);
  if Result then
    for I := 0 to High(SortedA) do
      if SortedA[I] <> SortedB[I] then
        Exit(False);
end;

function HasId(const Ids: TArray<Integer>; Id: Integer): Boolean;
var
  Each: Integer;
begin
  for Each in Ids do
    if Each = Id then
      Exit(True);
  Result := False;
end;

function TProjectTreeLookupTests.TreeProjectIds(Vm: TProjectTreeVM): TArray<Integer>;
var
  Tree: TOwnerTree;
  Own: TList<TProject>;
  Project: TProject;
  User: TUser;
begin
  Result := nil;
  Tree := Vm.LoadOwnerTree;
  if not Assigned(Tree) then
  begin
    Own := Vm.GetProjects(0);
    try
      for Project in Own do
        Result := Result + [Project.Id];
    finally
      Own.Free;
    end;
    Exit;
  end;
  try
    for User in Tree.Users do
      for Project in Tree.Projects[User.Id] do
        Result := Result + [Project.Id];
  finally
    Tree.Free;
  end;
end;

procedure TProjectTreeLookupTests.ShownProjectsAreTheProjectsOfTheTree;
var
  Fixture: TDesktopLoadFixture;
  Data, Writer: TDataModel;
  Vm: TProjectTreeVM;
  Admin, Retired: TUser;
  Found: TList<TProject>;
  AdminProjectId, RetiredProjectId, ArchivedProjectId: Integer;
  Shown: TArray<Integer>;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    AddOwners(Fixture, 2);
    Writer := Fixture.NewDataModel;
    try
      Admin := TUser.Create;
      Admin.Username := 'other-admin';
      Admin.FirstName := 'Synthetic';
      Admin.LastName := 'Admin';
      Admin.Password := Writer.User.Password;
      Admin.Role := dbAdmin;
      Admin.CreatedDate := Now;
      Writer.Manager.Save(Admin);
      Retired := TUser.Create;
      Retired.Username := 'archived-owner';
      Retired.FirstName := 'Synthetic';
      Retired.LastName := 'Archived';
      Retired.Password := Writer.User.Password;
      Retired.Role := dbUser;
      Retired.CreatedDate := Now;
      Writer.Manager.Save(Retired);
      Writer.Manager.Flush;
      AdminProjectId := Writer.Projects.AddProject('Admin project', '', Admin).Id;
      RetiredProjectId := Writer.Projects.AddProject('Archived owner project', '', Retired).Id;
      Retired := Writer.Manager.Find<TUser>(Retired.Id);
      Retired.IsArchived := True;
      Found := Writer.Manager.Find<TProject>
        .Where(Linq['Title'] = 'Owner 1 project 1').List;
      try
        Assert.AreEqual<NativeInt>(1, Found.Count, 'project to archive');
        ArchivedProjectId := Found[0].Id;
        Found[0].IsArchived := True;
      finally
        Found.Free;
      end;
      Writer.Manager.Flush;
    finally
      Writer.Free;
    end;
    CreateSupervisorVm(Fixture, Data, Vm);
    try
      Shown := Vm.ShownProjectIds;
      Assert.IsTrue(SameIds(TreeProjectIds(Vm), Shown), 'search projects are the tree projects');
      Assert.IsFalse(HasId(Shown, AdminProjectId), 'project of another Admin');
      Assert.IsFalse(HasId(Shown, RetiredProjectId), 'project of an archived owner');
      Assert.IsFalse(HasId(Shown, ArchivedProjectId), 'archived project');

      Vm.FilterText := 'no project matches this';
      Assert.IsTrue(SameIds(Shown, Vm.ShownProjectIds), 'the panel filter does not narrow the search');
      Vm.FilterText := '';

      Vm.ShowArchived := True;
      Shown := Vm.ShownProjectIds;
      Assert.IsTrue(SameIds(TreeProjectIds(Vm), Shown), 'with Show Archived');
      Assert.IsTrue(HasId(Shown, RetiredProjectId), 'archived owner shown');
      Assert.IsTrue(HasId(Shown, ArchivedProjectId), 'archived project shown');
      Assert.IsFalse(HasId(Shown, AdminProjectId), 'another Admin stays hidden');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

procedure TProjectTreeLookupTests.OwnerNodesNeedASecondOwner;
var
  Fixture: TDesktopLoadFixture;
  Data: TDataModel;
  Vm: TProjectTreeVM;
  Users: TList<TUser>;
  Tree: TOwnerTree;
begin
  Fixture := TDesktopLoadFixture.Create;
  try
    Fixture.Build(4);
    CreateSupervisorVm(Fixture, Data, Vm);
    try
      Users := Vm.GetUsers;
      try
        Assert.AreEqual<NativeInt>(1, Users.Count, 'only the supervisor');
      finally
        Users.Free;
      end;
      Users := Vm.OwnerNodes;
      try
        Assert.AreEqual<NativeInt>(0, Users.Count, 'one user: no owner nodes');
      finally
        Users.Free;
      end;
      Assert.IsNull(Vm.LoadOwnerTree, 'one user: the tree lists the projects directly');
      Assert.IsTrue(SameIds(TreeProjectIds(Vm), Vm.ShownProjectIds), 'search follows the flat tree');
    finally
      Vm.Free;
      Data.Free;
    end;

    AddOwners(Fixture, 1);
    CreateSupervisorVm(Fixture, Data, Vm);
    try
      Tree := Vm.LoadOwnerTree;
      try
        Assert.IsNotNull(Tree, 'two users: owner nodes');
        Assert.AreEqual<NativeInt>(2, Tree.Users.Count, 'the supervisor and the owner');
        Assert.AreEqual<NativeInt>(2, Tree.Projects.Count, 'a project group per owner');
        Assert.AreEqual<NativeInt>(2, Tree.Groups.Count, 'a group list per owner');
      finally
        Tree.Free;
      end;
      Assert.IsTrue(SameIds(TreeProjectIds(Vm), Vm.ShownProjectIds), 'search follows the owner tree');
    finally
      Vm.Free;
      Data.Free;
    end;
  finally
    Fixture.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDesktopLoadStatementTests);
  TDUnitX.RegisterTestFixture(TItemTreeLookupTests);
  TDUnitX.RegisterTestFixture(TProjectTreeLookupTests);
end.
