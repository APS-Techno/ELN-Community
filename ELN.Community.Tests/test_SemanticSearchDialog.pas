unit test_SemanticSearchDialog;

interface

uses
  DUnitX.TestFramework, unit_LocalNotebook, unit_SemanticSearchApi, dlg_Search,
  test_SearchDoubles;

type
  [TestFixture]
  TSemanticSearchDialogTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProjectId, FItemId: Integer;
    FFake: TFakeSemanticSearch;
    FFakeRef: ISemanticSearch;
    procedure Navigate(Sender: TObject; ProjectId, FolderId, ItemId: Integer);
    function Open: TdlgSearch;
    procedure SearchFor(Dialog: TdlgSearch; const Query: string);
    procedure WaitForDelivery(Dialog: TdlgSearch);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsTheResultsAndTheRerankedFlag;
    [Test]
    procedure SearchRunsOffTheMainThreadWithTheDialogRequest;
    [Test]
    procedure UnavailableErrorIsShown;
    [Test]
    procedure StatusLineFollowsTheInterface;
    [Test]
    procedure ReleaseSemanticWaitsAndDropsTheResult;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Diagnostics, Vcl.Forms,
  unit_Project, unit_Item, unit_ItemTypes, unit_DataModel;

const
  Password = 'Synthetic-Desktop-Regression-Only!';
  SearchingText = 'Searching' + #$2026;

procedure TSemanticSearchDialogTests.Setup;
var
  Project: TProject;
  Detached: TItem;
begin
  Assert.IsNull(Model, 'Fixture must not replace a live desktop model');
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SearchDialog-' + TGUID.NewGuid.ToString);
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Model := TDataModel.Create(FNotebook.Connection, FNotebook.Principal.Id,
    FNotebook.AccessPolicy, FNotebook.Storage);
  Project := Model.Projects.AddProject('Synthetic project', '', Model.User);
  FProjectId := Project.Id;
  Model.Items.AssignProject(Project.Id, 0);
  Detached := Model.Items.AddItem(TItemType.Specimen, 'Annealed multilayer', TItemLevel.Item, 0, '',
    nil, nil, Model.User.Id);
  try
    FItemId := Detached.Id;
  finally
    Detached.Free;
  end;
  FFake := TFakeSemanticSearch.Create;
  FFakeRef := FFake;
end;

procedure TSemanticSearchDialogTests.TearDown;
begin
  TdlgSearch.CloseInstance;
  FFakeRef := nil;
  FFake := nil;
  FreeAndNil(Model);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TSemanticSearchDialogTests.Navigate(Sender: TObject; ProjectId, FolderId, ItemId: Integer);
begin
end;

function TSemanticSearchDialogTests.Open: TdlgSearch;
var
  I: Integer;
begin
  TdlgSearch.Execute(Navigate, FFakeRef, [FProjectId]);
  Result := nil;
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I] is TdlgSearch then
      Result := TdlgSearch(Screen.Forms[I]);
  Assert.IsNotNull(Result, 'The dialog is open');
end;

procedure TSemanticSearchDialogTests.SearchFor(Dialog: TdlgSearch; const Query: string);
begin
  Dialog.chkMeaning.Checked := True;
  Dialog.edSearch.Text := Query;
  Dialog.btnSearchClick(Dialog.btnSearch);
end;

procedure TSemanticSearchDialogTests.WaitForDelivery(Dialog: TdlgSearch);
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  while (Dialog.lblCount.Caption = SearchingText) and (Watch.ElapsedMilliseconds < 10000) do
    CheckSynchronize(10);
  Assert.AreNotEqual(SearchingText, Dialog.lblCount.Caption, 'The result arrived');
end;

procedure TSemanticSearchDialogTests.ShowsTheResultsAndTheRerankedFlag;
var
  Dialog: TdlgSearch;
begin
  FFake.Reranker := True;
  FFake.Outcome.Groups := [FakeGroup(FItemId, FProjectId, 'annealing changed the roughness')];
  FFake.Outcome.Reranked := True;
  Dialog := Open;
  SearchFor(Dialog, 'annealing');
  WaitForDelivery(Dialog);
  Assert.AreEqual(1, Dialog.ListView.Items.Count);
  Assert.AreEqual(IntToStr(FItemId), Dialog.ListView.Items[0].Caption);
  Assert.AreEqual('Description', Dialog.ListView.Items[0].SubItems[0]);
  Assert.AreEqual('Annealed multilayer', Dialog.ListView.Items[0].SubItems[1]);
  Assert.AreEqual('annealing changed the roughness', Dialog.ListView.Items[0].SubItems[3]);
  Assert.AreEqual('1 result(s), reranked', Dialog.lblCount.Caption);
  Assert.IsTrue(FFake.Requests[0].Rerank, 'The check box asks for the rerank');
end;

procedure TSemanticSearchDialogTests.SearchRunsOffTheMainThreadWithTheDialogRequest;
var
  Dialog: TdlgSearch;
  Request: TSemanticSearchRequest;
begin
  Dialog := Open;
  Assert.IsFalse(Dialog.chkRerank.Enabled, 'No reranker, no check box');
  Dialog.cbItemType.ItemIndex := 1;
  SearchFor(Dialog, 'annealing');
  WaitForDelivery(Dialog);
  Assert.AreEqual('0 result(s)', Dialog.lblCount.Caption);
  Assert.AreEqual<NativeInt>(1, Length(FFake.Requests));
  Request := FFake.Requests[0];
  Assert.AreEqual('annealing', Request.Query);
  Assert.AreEqual(50, Request.TopK);
  Assert.IsFalse(Request.Rerank);
  Assert.AreEqual<NativeInt>(1, Length(Request.VisibleProjectIds));
  Assert.AreEqual(FProjectId, Request.VisibleProjectIds[0]);
  Assert.AreEqual<NativeInt>(1, Length(Request.Filter.ItemTypes));
  Assert.AreEqual(Dialog.cbItemType.Items[1], Request.Filter.ItemTypes[0]);
  Assert.AreNotEqual<TThreadID>(MainThreadID, FFake.SearchThreads[0], 'The search runs on a worker thread');
end;

procedure TSemanticSearchDialogTests.UnavailableErrorIsShown;
var
  Dialog: TdlgSearch;
begin
  FFake.Failure := 'search server is down';
  Dialog := Open;
  SearchFor(Dialog, 'annealing');
  WaitForDelivery(Dialog);
  Assert.AreEqual('search server is down', Dialog.lblStatus.Caption);
  Assert.AreEqual('', Dialog.lblCount.Caption);
  Assert.AreEqual(0, Dialog.ListView.Items.Count);
end;

procedure TSemanticSearchDialogTests.StatusLineFollowsTheInterface;
var
  Dialog: TdlgSearch;
begin
  FFake.Current.State := ssSyncing;
  FFake.Current.Phase := spExtracting;
  FFake.Current.FilesDone := 2;
  FFake.Current.FilesTotal := 5;
  Dialog := Open;
  Assert.AreEqual('Reading files' + #$2026 + ' 2/5', Dialog.lblStatus.Caption);
  FFake.Current := Default(TSemanticSearchStatus);
  FFake.Current.IndexedPassages := 7;
  Dialog.tmrStatusTimer(Dialog.tmrStatus);
  Assert.AreEqual('Indexed 7 passages', Dialog.lblStatus.Caption);
  FFake.Current.State := ssFailed;
  FFake.Current.LastError := 'disk full';
  Dialog.tmrStatusTimer(Dialog.tmrStatus);
  Assert.AreEqual('Indexing failed: disk full', Dialog.lblStatus.Caption);
end;

procedure TSemanticSearchDialogTests.ReleaseSemanticWaitsAndDropsTheResult;
var
  Dialog: TdlgSearch;
begin
  FFake.DelayMs := 300;
  FFake.Outcome.Groups := [FakeGroup(FItemId, FProjectId, 'late result')];
  Dialog := Open;
  SearchFor(Dialog, 'annealing');
  TdlgSearch.ReleaseSemantic;
  Assert.AreEqual(1, FFake.Finished, 'The release waits for the running search');
  CheckSynchronize(50);
  Assert.AreEqual(0, Dialog.ListView.Items.Count, 'A released search shows no result');
  Assert.AreEqual('', Dialog.lblCount.Caption);
  Assert.IsFalse(Dialog.chkMeaning.Enabled);
end;

initialization
  TDUnitX.RegisterTestFixture(TSemanticSearchDialogTests);

end.
