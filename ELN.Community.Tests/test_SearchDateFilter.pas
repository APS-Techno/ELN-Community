unit test_SearchDateFilter;

interface

uses
  DUnitX.TestFramework, unit_LocalNotebook, unit_SemanticSearchApi, dlg_Search,
  test_SearchDoubles;

type
  [TestFixture]
  TSearchDateFilterTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProjectId: Integer;
    FFake: TFakeSemanticSearch;
    FFakeRef: ISemanticSearch;
    procedure Navigate(Sender: TObject; ProjectId, FolderId, ItemId: Integer);
    function Open: TdlgSearch;
    function Search(Dialog: TdlgSearch): TSemanticSearchRequest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EditingADateDoesNotTurnTheFilterOn;
    [Test]
    procedure TickedDatesFilterAndShowInTheCount;
    [Test]
    procedure ReopeningKeepsAnUntickedFilterOff;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Diagnostics, System.DateUtils,
  Vcl.Forms, unit_Project, unit_DataModel;

const
  Password = 'Synthetic-Desktop-Regression-Only!';
  SearchingText = 'Searching' + #$2026;

procedure TSearchDateFilterTests.Setup;
var
  Project: TProject;
begin
  Assert.IsNull(Model, 'Fixture must not replace a live desktop model');
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-SearchDates-' + TGUID.NewGuid.ToString);
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Model := TDataModel.Create(FNotebook.Connection, FNotebook.Principal.Id,
    FNotebook.AccessPolicy, FNotebook.Storage);
  Project := Model.Projects.AddProject('Synthetic project', '', Model.User);
  FProjectId := Project.Id;
  FFake := TFakeSemanticSearch.Create;
  FFakeRef := FFake;
end;

procedure TSearchDateFilterTests.TearDown;
begin
  TdlgSearch.CloseInstance;
  FFakeRef := nil;
  FFake := nil;
  FreeAndNil(Model);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TSearchDateFilterTests.Navigate(Sender: TObject; ProjectId, FolderId, ItemId: Integer);
begin
end;

function TSearchDateFilterTests.Open: TdlgSearch;
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

function TSearchDateFilterTests.Search(Dialog: TdlgSearch): TSemanticSearchRequest;
var
  Watch: TStopwatch;
  Before: Integer;
begin
  Before := Length(FFake.Requests);
  Dialog.chkMeaning.Checked := True;
  Dialog.edSearch.Text := 'annealing';
  Dialog.btnSearchClick(Dialog.btnSearch);
  Watch := TStopwatch.StartNew;
  while (Dialog.lblCount.Caption = SearchingText) and (Watch.ElapsedMilliseconds < 10000) do
    CheckSynchronize(10);
  Assert.AreNotEqual(SearchingText, Dialog.lblCount.Caption, 'The result arrived');
  Assert.AreEqual<Integer>(Before + 1, Length(FFake.Requests));
  Result := FFake.Requests[High(FFake.Requests)];
end;

procedure TSearchDateFilterTests.EditingADateDoesNotTurnTheFilterOn;
var
  Dialog: TdlgSearch;
  Request: TSemanticSearchRequest;
begin
  Dialog := Open;
  Dialog.dtpFrom.Date := EncodeDate(2026, 11, 1);
  Dialog.dtpTo.Date := EncodeDate(2026, 11, 2);
  Request := Search(Dialog);
  Assert.AreEqual<Integer>(Ord(sdfNone), Ord(Request.Filter.DateField));
  Assert.AreEqual('0 result(s)', Dialog.lblCount.Caption);
end;

procedure TSearchDateFilterTests.TickedDatesFilterAndShowInTheCount;
var
  Dialog: TdlgSearch;
  Request: TSemanticSearchRequest;
begin
  Dialog := Open;
  Dialog.dtpFrom.Date := EncodeDate(2026, 11, 1);
  Dialog.chkDateFrom.Checked := True;
  Request := Search(Dialog);
  Assert.AreEqual<Integer>(Ord(sdfCreated), Ord(Request.Filter.DateField));
  Assert.AreEqual(EncodeDate(2026, 11, 1), Request.Filter.DateFrom);
  Assert.AreEqual<Double>(0, Request.Filter.DateTo);
  Assert.AreEqual('0 result(s), created from ' + DateToStr(EncodeDate(2026, 11, 1)),
    Dialog.lblCount.Caption);
end;

procedure TSearchDateFilterTests.ReopeningKeepsAnUntickedFilterOff;
var
  Dialog: TdlgSearch;
  Request: TSemanticSearchRequest;
begin
  Dialog := Open;
  Dialog.dtpTo.Date := EncodeDate(2026, 11, 2);
  Search(Dialog);
  Dialog := Open;
  Request := Search(Dialog);
  Assert.AreEqual<Integer>(Ord(sdfNone), Ord(Request.Filter.DateField));
end;

initialization
  TDUnitX.RegisterTestFixture(TSearchDateFilterTests);

end.
