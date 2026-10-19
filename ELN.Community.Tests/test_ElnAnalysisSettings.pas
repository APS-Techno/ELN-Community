unit test_ElnAnalysisSettings;

interface

uses
  DUnitX.TestFramework, unit_LocalNotebook, unit_Item, unit_ELNPluginCore;

type
  [TestFixture]
  TElnAnalysisSettingsTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FItem: TItem;
    FFile: unit_Item.TFile;
    FPrevious: IElnAnalysisSettings;
    FStoragePath: string;
    function StoredSelection: string;
    function OpenViewer(const Name: string; out Path: string): TObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure FirstApplyIsStoredAndSurvivesReopen;
    [Test] procedure SecondViewerWithStaleExpectationConflictsAndReloads;
    [Test] procedure ReplacedFileBytesMakeApplyReportHashMismatch;
    [Test] procedure ReplacedFileMakesReopenedSelectionStale;
    [Test] procedure CurrentUserIdIsTheNotebookUser;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, Vcl.Forms,
  unit_Project, unit_ItemTypes, unit_FileType, unit_DataModel,
  unit_AnalysisSettingsModel, unit_ZRWPlateau, unit_ZRWViewerPlugin,
  frame_ZRWViewer, dlg_ExtractValues, unit_ElnAnalysisSettings,
  test_ZRWExtraction;

const
  Password = 'Synthetic-Analysis-Settings-Only!';

procedure TElnAnalysisSettingsTests.Setup;
var
  Id: TGUID;
  Project: TProject;
  Detached: TItem;
  FileType: TFileType;
begin
  Assert.IsNull(Model, 'Fixture must not replace a live desktop model');
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-AnalysisAdapter-' + GUIDToString(Id));
  ForceDirectories(FRoot);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Model := TDataModel.Create(FNotebook.Connection, FNotebook.Principal.Id,
    FNotebook.AccessPolicy, FNotebook.Storage);
  Project := Model.Projects.AddProject('Synthetic project', '', Model.User);
  Model.Items.AssignProject(Project.Id, 0);
  Detached := Model.Items.AddItem(TItemType.Other, 'Synthetic procedure',
    TItemLevel.Proc, 0, '', nil, nil, Model.User.Id);
  FItem := Model.Manager.Find<TItem>(Detached.Id);
  Detached.Free;
  FileType := TFileType.Create;
  FileType.Ext := '.zrw';
  FileType.Description := 'Synthetic ZRW';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  FFile := Model.Items.AddFile(FileType, 'friction', Model.User.Id, FItem);
  FStoragePath := Model.GetFileName(FFile.Id);
  FNotebook.Storage.WriteBytes(FStoragePath, SyntheticZrwBytes);
  FPrevious := ElnAnalysisSettings;
  InstallElnAnalysisSettings;
end;

procedure TElnAnalysisSettingsTests.TearDown;
begin
  ElnAnalysisSettings := FPrevious;
  FPrevious := nil;
  FreeAndNil(Model);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TElnAnalysisSettingsTests.StoredSelection: string;
var
  Settings: TAnalysisSettingsModel;
begin
  Settings := TAnalysisSettingsModel.Create(Model.Manager);
  try
    if not Settings.LoadSelection('aps.zrw', FFile.Id, Result) then
      Result := '';
  finally
    Settings.Free;
  end;
end;

function TElnAnalysisSettingsTests.OpenViewer(const Name: string;
  out Path: string): TObject;
var
  Plugin: TELNZRWViewerPlugin;
begin
  Path := TPath.Combine(FRoot, Name + '.zrw');
  FNotebook.Storage.CopyOut(FStoragePath, Path);
  Plugin := TELNZRWViewerPlugin.Create(nil);
  Assert.IsTrue(Plugin.LoadFromFile(Path));
  Assert.IsTrue(AttachAnalysisContext(Plugin, Path, FFile.Id) <> nil);
  Result := Plugin;
end;

procedure TElnAnalysisSettingsTests.FirstApplyIsStoredAndSurvivesReopen;
var
  First, Second: TELNZRWViewerPlugin;
  PathA, PathB: string;
  Stored: TZRWSelection;
begin
  First := OpenViewer('first', PathA) as TELNZRWViewerPlugin;
  try
    TframeZRWViewer(First.Frame).SetDraftBounds(20, 60, False);
    TframeZRWViewer(First.Frame).ApplySelection;
    Assert.IsTrue(Pos('Applied as revision 1', TframeZRWViewer(First.Frame).lblWarnings.Caption) > 0,
      TframeZRWViewer(First.Frame).lblWarnings.Caption);
  finally
    First.Free;
  end;
  Assert.IsTrue(TryParseSelection(StoredSelection, Stored), 'The selection must be stored');
  Assert.IsTrue(Stored.Mode = zsmManual);
  Assert.AreEqual<Double>(20, Stored.Interval.StartCycle);
  Assert.AreEqual<Double>(60, Stored.Interval.EndCycle);
  Assert.AreEqual(1, Stored.Revision);
  Assert.AreEqual(Model.User.Id, Stored.AppliedBy);
  Assert.AreEqual(TAnalysisSettingsModel.ContentHash(PathA), Stored.FileHash);

  Second := OpenViewer('second', PathB) as TELNZRWViewerPlugin;
  try
    Assert.AreEqual('20', TframeZRWViewer(Second.Frame).edStart.Text);
    Assert.AreEqual('60', TframeZRWViewer(Second.Frame).edEnd.Text);
    Assert.IsTrue(TframeZRWViewer(Second.Frame).btnManual.Down);
    Assert.IsTrue(Pos('applied, revision 1', TframeZRWViewer(Second.Frame).lblStats.Caption) > 0,
      TframeZRWViewer(Second.Frame).lblStats.Caption);
  finally
    Second.Free;
  end;
end;

procedure TElnAnalysisSettingsTests.SecondViewerWithStaleExpectationConflictsAndReloads;
var
  A, B: TELNZRWViewerPlugin;
  PathA, PathB, Winner: string;
  Stored: TZRWSelection;
begin
  A := OpenViewer('a', PathA) as TELNZRWViewerPlugin;
  B := OpenViewer('b', PathB) as TELNZRWViewerPlugin;
  try
    TframeZRWViewer(A.Frame).SetDraftBounds(20, 60, False);
    TframeZRWViewer(A.Frame).ApplySelection;
    Winner := StoredSelection;

    TframeZRWViewer(B.Frame).SetDraftBounds(30, 70, False);
    TframeZRWViewer(B.Frame).ApplySelection;
    Assert.AreEqual(Winner, StoredSelection, 'A conflicting apply must not overwrite');
    Assert.AreEqual('30', TframeZRWViewer(B.Frame).edStart.Text, 'The draft is kept');
    Assert.IsTrue(TframeZRWViewer(B.Frame).btnReload.Enabled);

    TframeZRWViewer(B.Frame).ReloadSelection;
    Assert.AreEqual('20', TframeZRWViewer(B.Frame).edStart.Text);
    Assert.AreEqual('60', TframeZRWViewer(B.Frame).edEnd.Text);
    TframeZRWViewer(B.Frame).SetDraftBounds(30, 70, False);
    TframeZRWViewer(B.Frame).ApplySelection;
    Assert.IsTrue(TryParseSelection(StoredSelection, Stored));
    Assert.AreEqual(2, Stored.Revision);
    Assert.AreEqual<Double>(30, Stored.Interval.StartCycle);
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TElnAnalysisSettingsTests.ReplacedFileBytesMakeApplyReportHashMismatch;
var
  Viewer: TELNZRWViewerPlugin;
  Path, Before: string;
begin
  Viewer := OpenViewer('old', Path) as TELNZRWViewerPlugin;
  try
    FNotebook.Storage.WriteBytes(FStoragePath, SyntheticZrwBytes(False));
    TframeZRWViewer(Viewer.Frame).SetDraftBounds(20, 60, False);
    Before := StoredSelection;
    TframeZRWViewer(Viewer.Frame).ApplySelection;
    Assert.IsTrue(Pos('differs', TframeZRWViewer(Viewer.Frame).lblWarnings.Caption) > 0,
      TframeZRWViewer(Viewer.Frame).lblWarnings.Caption);
    Assert.AreEqual(Before, StoredSelection);
    Assert.AreEqual('', StoredSelection, 'No selection is stored for old bytes');
  finally
    Viewer.Free;
  end;
end;

procedure TElnAnalysisSettingsTests.ReplacedFileMakesReopenedSelectionStale;
var
  First, Second: TELNZRWViewerPlugin;
  PathA, PathB: string;
begin
  First := OpenViewer('before', PathA) as TELNZRWViewerPlugin;
  try
    TframeZRWViewer(First.Frame).SetDraftBounds(20, 60, False);
    TframeZRWViewer(First.Frame).ApplySelection;
  finally
    First.Free;
  end;
  FNotebook.Storage.WriteBytes(FStoragePath, SyntheticZrwBytes(False));
  Second := OpenViewer('after', PathB) as TELNZRWViewerPlugin;
  try
    Assert.IsTrue(Pos('Stale', TframeZRWViewer(Second.Frame).lblStats.Caption) > 0,
      TframeZRWViewer(Second.Frame).lblStats.Caption);
    Assert.AreEqual('20', TframeZRWViewer(Second.Frame).edStart.Text);
    Assert.AreEqual('60', TframeZRWViewer(Second.Frame).edEnd.Text);
    Assert.AreEqual('stale_selection', Second.GetAnalysisStatus);
  finally
    Second.Free;
  end;
end;

procedure TElnAnalysisSettingsTests.CurrentUserIdIsTheNotebookUser;
begin
  Assert.AreEqual(Model.User.Id, ElnAnalysisSettings.CurrentUserId);
end;

initialization
  TDUnitX.RegisterTestFixture(TElnAnalysisSettingsTests);

end.
