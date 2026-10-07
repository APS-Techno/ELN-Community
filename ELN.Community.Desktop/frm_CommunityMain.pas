unit frm_CommunityMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Generics.Collections, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Menus, Vcl.Dialogs, RzCommon, RzPanel, RzSplit, RzStatus,
  frame_ProjectsPanel, frame_ItemTree, frame_ContentViewer, frame_Dashboard,
  unit_ELNThumbnailList, unit_PreviewMessages, unit_LocalNotebook,
  unit_NotebookSettings, unit_ELNPluginCore;

type
  TWorkingFile = record
    Path: string;
  end;

  TfrmCommunityMain = class(TForm)
    MainMenu: TMainMenu;
    miFile: TMenuItem;
    miNew: TMenuItem;
    miOpen: TMenuItem;
    miCloseNotebook: TMenuItem;
    miImport: TMenuItem;
    miExport: TMenuItem;
    miReport: TMenuItem;
    miExit: TMenuItem;
    miProject: TMenuItem;
    miNewProject: TMenuItem;
    miNewGroup: TMenuItem;
    miNewFolder: TMenuItem;
    miTopicWiki: TMenuItem;
    miEditProject: TMenuItem;
    miArchive: TMenuItem;
    miHypotheses: TMenuItem;
    miDeleteProject: TMenuItem;
    miRefreshProjects: TMenuItem;
    miArchived: TMenuItem;
    miItem: TMenuItem;
    miProcedure: TMenuItem;
    miSpecimen: TMenuItem;
    miAction: TMenuItem;
    miFromTemplate: TMenuItem;
    miAddFile: TMenuItem;
    miAddNote: TMenuItem;
    miAddProtocol: TMenuItem;
    miAddValue: TMenuItem;
    miEditItem: TMenuItem;
    miDuplicate: TMenuItem;
    miLinks: TMenuItem;
    miDeleteItem: TMenuItem;
    miRefreshItems: TMenuItem;
    miData: TMenuItem;
    miFileTypes: TMenuItem;
    miEquipmentTypes: TMenuItem;
    miEquipment: TMenuItem;
    miActionTypes: TMenuItem;
    miValueTypes: TMenuItem;
    miLinkTypes: TMenuItem;
    miTemplates: TMenuItem;
    miExperimentTemplates: TMenuItem;
    miTags: TMenuItem;
    miTools: TMenuItem;
    miSearch: TMenuItem;
    miGoTo: TMenuItem;
    miDashboard: TMenuItem;
    miAnalysis: TMenuItem;
    miUnits: TMenuItem;
    miReview: TMenuItem;
    miAudit: TMenuItem;
    miAuditRules: TMenuItem;
    miCompleteness: TMenuItem;
    miRecycle: TMenuItem;
    miSaveDraft: TMenuItem;
    miReloadDraft: TMenuItem;
    miPreferences: TMenuItem;
    miHelp: TMenuItem;
    miContents: TMenuItem;
    miShortcuts: TMenuItem;
    miAbout: TMenuItem;
    StatusBar: TRzStatusBar;
    StatusNotebook: TRzStatusPane;
    StatusFile: TRzStatusPane;
    spMain: TRzSplitter;
    spCenter: TRzSplitter;
    spRight: TRzSplitter;
    frmProjects: TframeProjectTree;
    frmItems: TframeItemTree;
    frmContentViewer: TframeContentViewer;
    frmDashboard: TframeDashboard;
    FileThumbnailList: TELNThumbnailList;
    pnlWelcome: TRzPanel;
    lblWelcome: TLabel;
    btnNew: TButton;
    btnOpen: TButton;
    OpenNotebookDialog: TOpenDialog;
    NewNotebookDialog: TSaveDialog;
    StorageDialog: TFileOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormAfterMonitorDpiChanged(Sender: TObject; OldDPI, NewDPI: Integer);
    procedure NewNotebookClick(Sender: TObject);
    procedure OpenNotebookClick(Sender: TObject);
    procedure CloseNotebookClick(Sender: TObject);
    procedure ExitClick(Sender: TObject);
    procedure CommandClick(Sender: TObject);
    procedure PreferencesClick(Sender: TObject);
  private
    FNotebook: TLocalNotebook;
    FSettings: TNotebookSettings;
    FWorkingRoot: string;
    FDatabasePath: string;
    FStorageRoot: string;
    FStartupNotebook: string;
    FStartupStorage: string;
    FPluginsPath: string;
    FFiles: TDictionary<Integer, TWorkingFile>;
    FCurrentFileId: Integer;
    FStarted: Boolean;
    FClosing: Boolean;
    FEditorCloseEvent: TCloseEvent;
    FEditorCloseAccepted: Boolean;
    FEditorCloseFree: Boolean;
    procedure EditorClosing(Sender: TObject; var Action: TCloseAction);
    procedure SetNotebookUI(Opened: Boolean);
    procedure WireCommands;
    procedure BindNotebook(Notebook: TLocalNotebook; const DatabasePath, StorageRoot: string;
      Fresh: Boolean);
    procedure ReleaseNotebook;
    function PrepareFile(FileId: Integer): string;
    procedure DisplayFile(FileId: Integer);
    procedure OpenFile(FileId: Integer);
    function SaveDraft(FileId: Integer): Boolean;
    function FinishEditorsAndDrafts: Boolean;
    procedure ReloadDraft(FileId: Integer);
    function RefreshChangedFile(FileId: Integer; ExplicitReload: Boolean): Boolean;
    procedure InitializeCatalogs(Fresh: Boolean);
    procedure ApplyAppearance;
    procedure NavigateItem(Sender: TObject; ProjectId, FolderId, ItemId: Integer);
    procedure OpenHypotheses(Sender: TObject; ProjectId, HypothesisId: Integer);
    procedure RunsChanged(Sender: TObject);
    procedure DecisionsChanged(Sender: TObject);
    procedure ImportPackage;
    procedure RetainedWorkingFiles;
    procedure WMImageClick(var Msg: TMessage); message WM_ELN_IMAGECLICK;
    procedure WMImageDblClick(var Msg: TMessage); message WM_ELN_IMAGEDBLCLICK;
    procedure WMImageContext(var Msg: TMessage); message WM_ELN_IMAGECONTEXT;
    procedure WMFileSelected(var Msg: TMessage); message WM_ELN_FILESELECTED;
    procedure WMFileChanged(var Msg: TMessage); message WM_ELN_FILECHANGED;
  end;

var
  frmCommunityMain: TfrmCommunityMain;

implementation

{$R *.dfm}

uses
  System.IOUtils, System.UITypes, Winapi.ShellAPI, Vcl.Themes, Vcl.ActnList,
  IdHashMessageDigest, unit_DataModel, unit_Item, unit_User, unit_ValueTypeCategories,
  unit_LocalElnFileService, unit_ElnFileEnumerator, unit_ElnLinkHandler,
  dm_TreeImages, unit_TreeAppearance, unit_TreeLook, unit_ELNThemeHelper,
  unit_ServiceImport, unit_FileTypeIconSeeder, unit_PackageImport, unit_ConflictHandler, dlg_Conflict,
  frm_LocalProfile, frm_CommunityPreferences,
  editor_FileTypes, editor_EquipmentTypes, editor_Equipment, editor_ActionTypes,
  editor_ValueTypes, editor_LinkTypes, editor_ProtocolTemplates,
  dlg_PackageImport, dlg_ProtocolReview, dlg_AuditLog, dlg_AuditRuleEditor,
  dlg_AuditReport, dlg_ExperimentTemplate, dlg_RecycleBin, dlg_TagManager,
  dlg_Search, dlg_GoToItem, dlg_UnitConverter, dlg_HelpViewer, dlg_About,
  frm_Analysis;

function GetExeVersion: string;
var
  Size, Handle: DWORD;
  Buffer: TBytes;
  FixedInfo: PVSFixedFileInfo;
  InfoLen: UINT;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(Application.ExeName), Handle);
  if Size = 0 then Exit;
  SetLength(Buffer, Size);
  if not GetFileVersionInfo(PChar(Application.ExeName), Handle, Size, @Buffer[0]) then Exit;
  if VerQueryValue(@Buffer[0], '\', Pointer(FixedInfo), InfoLen) then
    Result := Format('%d.%d.%d.%d', [
      HiWord(FixedInfo.dwFileVersionMS), LoWord(FixedInfo.dwFileVersionMS),
      HiWord(FixedInfo.dwFileVersionLS), LoWord(FixedInfo.dwFileVersionLS)]);
end;

function WorkingHash(const Path: string): string;
var
  Stream: TFileStream;
  Hash: TIdHashMessageDigest5;
begin
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    Hash := TIdHashMessageDigest5.Create;
    try
      Result := Hash.HashStreamAsHex(Stream);
    finally
      Hash.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TfrmCommunityMain.FormCreate(Sender: TObject);
var
  ConfigPath: string;
  I: Integer;
  Key, Value: string;
begin
  FFiles := TDictionary<Integer, TWorkingFile>.Create;
  ConfigPath := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),
    'ELN Community\desktop.ini');
  I := 1;
  while I <= ParamCount do
  begin
    Key := ParamStr(I);
    if not ((Key = '--notebook') or (Key = '--storage') or
      (Key = '--config') or (Key = '--plugins')) then
      raise EArgumentException.Create('Unknown Community argument: ' + Key);
    Inc(I);
    if (I > ParamCount) or (Copy(ParamStr(I), 1, 2) = '--') then
      raise EArgumentException.Create('Missing value for ' + Key);
    Value := TPath.GetFullPath(ParamStr(I));
    if Key = '--notebook' then FStartupNotebook := Value
    else if Key = '--storage' then FStartupStorage := Value
    else if Key = '--config' then ConfigPath := Value
    else FPluginsPath := Value;
    Inc(I);
  end;
  if (FStartupNotebook = '') <> (FStartupStorage = '') then
    raise EArgumentException.Create('--notebook and --storage must be supplied together');
  ForceDirectories(ExtractFilePath(ConfigPath));
  TNotebookSettings.SetConfigFile(ConfigPath);
  FSettings := TNotebookSettings.Create(ConfigPath);
  if FPluginsPath = '' then FPluginsPath := FSettings.PluginsDir;
  if FPluginsPath = '' then FPluginsPath := ExtractFilePath(Application.ExeName) + 'Plugins';
  ThemePluginsEnabled := FSettings.DarkCharts;
  Appearance.Load(FSettings);
  dmTreeImages.ApplyThemeIcons;
  dmTreeImages.LoadGlyph(frmItems.btnClearSearch.Glyph, 'Clear', 24);
  dmTreeImages.LoadGlyph(frmProjects.btnClearSearch.Glyph, 'Clear', 24);
  dmTreeImages.LoadGlyph(frmDashboard.btnRefresh.Glyph, 'Refresh', 32);
  frmContentViewer.Init(FPluginsPath);
  frmContentViewer.SetDashboard(frmDashboard);
  frmDashboard.Visible := True;
  frmDashboard.OnNavigateItem := NavigateItem;
  frmDashboard.OnOpenHypothesis := OpenHypotheses;
  frmProjects.OnAuditNavigate := NavigateItem;
  frmProjects.OnOpenHypotheses := OpenHypotheses;
  frmItems.OnNavigateItem := NavigateItem;
  frmItems.OnOpenHypotheses := OpenHypotheses;
  frmItems.OnPrepareFile := PrepareFile;
  frmItems.OnHypothesisDecisionsChanged := DecisionsChanged;
  frmContentViewer.frmHypotheses.OnNavigateItem := NavigateItem;
  frmContentViewer.frmHypotheses.OnRunsChanged := RunsChanged;
  frmContentViewer.frmHypotheses.OnDecisionsChanged := DecisionsChanged;
  frmContentViewer.frmHypotheses.OnGetSelectedItemId := frmItems.SelectedItemId;
  TConflictHandler.OnConflict := function(const Text: string): TConflictResolution
    begin Result := ShowConflictDialog(Text); end;
  spMain.Percent := FSettings.LoadUIValue('CommunityMain', 'ProjectsPercent', spMain.Percent);
  spCenter.Percent := FSettings.LoadUIValue('CommunityMain', 'ItemsPercent', spCenter.Percent);
  spRight.Percent := FSettings.LoadUIValue('CommunityMain', 'ViewerPercent', spRight.Percent);
  SetNotebookUI(False);
  ApplyAppearance;
end;

procedure TfrmCommunityMain.FormShow(Sender: TObject);
var
  Notebook: TLocalNotebook;
begin
  if FStarted then Exit;
  FStarted := True;
  if FStartupNotebook = '' then Exit;
  Notebook := TLocalNotebook.Open(FStartupNotebook, FStartupStorage);
  try
    BindNotebook(Notebook, FStartupNotebook, FStartupStorage, False);
    Notebook := nil;
  finally
    Notebook.Free;
  end;
end;

procedure TfrmCommunityMain.SetNotebookUI(Opened: Boolean);
begin
  spMain.Visible := Opened;
  pnlWelcome.Visible := not Opened;
  miCloseNotebook.Enabled := Opened;
  miImport.Enabled := Opened;
  miExport.Enabled := Opened;
  miReport.Enabled := Opened;
  miProject.Enabled := Opened;
  miItem.Enabled := Opened;
  miData.Enabled := Opened;
  miSearch.Enabled := Opened;
  miGoTo.Enabled := Opened;
  miDashboard.Enabled := Opened;
  miAnalysis.Enabled := Opened;
  miUnits.Enabled := Opened;
  miReview.Enabled := Opened;
  miAudit.Enabled := Opened;
  miAuditRules.Enabled := Opened;
  miCompleteness.Enabled := Opened;
  miRecycle.Enabled := Opened;
  miSaveDraft.Enabled := Opened and FFiles.ContainsKey(FCurrentFileId);
  miReloadDraft.Enabled := miSaveDraft.Enabled;
  if not Opened then
  begin
    Caption := 'ELN Community';
    StatusNotebook.Caption := 'No notebook open';
    StatusFile.Caption := '';
  end;
end;

procedure TfrmCommunityMain.WireCommands;

  procedure WireMenu(mi: TMenuItem; act: TAction);
  var
    LImageIndex: Integer;
    LImageName: string;
  begin
    LImageIndex := mi.ImageIndex;
    LImageName := mi.ImageName;
    mi.Action := act;
    mi.ImageIndex := LImageIndex;
    mi.ImageName := LImageName;
  end;

begin
  WireMenu(miNewProject, frmProjects.actNewProject);
  WireMenu(miNewGroup, frmProjects.actNewGroup);
  WireMenu(miNewFolder, frmProjects.actNewFolder);
  WireMenu(miTopicWiki, frmProjects.actNewTopicWiki);
  WireMenu(miEditProject, frmProjects.actEdit);
  WireMenu(miArchive, frmProjects.actArchive);
  WireMenu(miHypotheses, frmProjects.actHypotheses);
  WireMenu(miDeleteProject, frmProjects.actDelete);
  WireMenu(miRefreshProjects, frmProjects.actRefresh);
  WireMenu(miArchived, frmProjects.actShowArchived);
  WireMenu(miProcedure, frmItems.actNewProc);
  WireMenu(miSpecimen, frmItems.actNewItem);
  WireMenu(miAction, frmItems.actNewAction);
  WireMenu(miFromTemplate, frmItems.actNewFromTemplate);
  WireMenu(miAddFile, frmItems.actAddFile);
  WireMenu(miAddNote, frmItems.actAddNote);
  WireMenu(miAddProtocol, frmItems.actAddProtocol);
  WireMenu(miAddValue, frmItems.actAddValue);
  WireMenu(miEditItem, frmItems.actEdit);
  WireMenu(miDuplicate, frmItems.actDuplicate);
  WireMenu(miLinks, frmItems.actLinks);
  WireMenu(miDeleteItem, frmItems.actDelete);
  WireMenu(miRefreshItems, frmItems.actRefresh);
  WireMenu(miExport, frmItems.actExport);
  WireMenu(miReport, frmItems.actReport);
end;

procedure TfrmCommunityMain.BindNotebook(Notebook: TLocalNotebook;
  const DatabasePath, StorageRoot: string; Fresh: Boolean);
var
  Id: TGUID;
begin
  FNotebook := Notebook;
  FDatabasePath := TPath.GetFullPath(DatabasePath);
  FStorageRoot := TPath.GetFullPath(StorageRoot);
  try
    Model := TDataModel.Create(Notebook.Connection, Notebook.Principal.Id,
      Notebook.AccessPolicy, Notebook.Storage);
    FSettings.StorageRoot := IncludeTrailingPathDelimiter(FStorageRoot);
    InitializeCatalogs(Fresh);
    Model.History.LoadHistory(Model.User.Id);
    Model.TreeState.Load(Model.User.Id);
    CreateGUID(Id);
    FWorkingRoot := TPath.Combine(TPath.GetTempPath, 'ELNCommunity-' + GUIDToString(Id));
    ForceDirectories(FWorkingRoot);
    InstallLocalElnFileService(Model.Manager, Model.User.Id, Notebook.AccessPolicy,
      Model.Storage, FStorageRoot, FWorkingRoot);
    InstallElnFileEnumerator;
    InstallElnLinkHandler(procedure(ProjectId, FolderId, ItemId: Integer)
      begin NavigateItem(Self, ProjectId, FolderId, ItemId); end);
    frmProjects.Init;
    frmItems.Init(FileThumbnailList, frmContentViewer, spRight);
    frmItems.SetShowItemIDs(FSettings.ShowItemIDs);
    WireCommands;
    frmDashboard.LoadData(Model.User.Role);
    SetNotebookUI(True);
    miData.Enabled := Model.Access.CanEditReferenceData(Model.Manager, Model.User);
    Caption := 'ELN Community - ' + ExtractFileName(FDatabasePath);
    StatusNotebook.Caption := Model.User.FirstName + ' ' + Model.User.LastName +
      ' | ' + FDatabasePath;
    ApplyAppearance;
    frmProjects.RestoreLastSelection;
    if FSettings.ShowDashboard then frmContentViewer.ShowDashboard;
  except
    // The caller still owns the notebook if binding fails.
    FNotebook := nil;
    ReleaseNotebook;
    raise;
  end;
end;

procedure TfrmCommunityMain.InitializeCatalogs(Fresh: Boolean);
var
  Importer: TServiceImporter;
  ImportResult: TImportResult;
  I: Integer;
  TemplatesDir, TemplatePath, Path, Warnings: string;
begin
  ResetValueTypeCategories;
  if Fresh then
  begin
    Importer := TServiceImporter.Create(Model.Manager, Model.User.Id);
    try
      ImportResult := Importer.ImportAll(ExtractFilePath(Application.ExeName) + 'CSV');
      try
        if not ImportResult.Success then
          raise Exception.Create('Scientific catalog import failed. The new notebook is retained; use the reference-data editors to inspect it.');
        for I := Low(ImportResult.Results) to High(ImportResult.Results) do
          if ImportResult.Results[I].Errors > 0 then
            raise Exception.CreateFmt('Scientific catalog %s has %d import errors. The new notebook is retained.',
              [ImportResult.Results[I].EntityName, ImportResult.Results[I].Errors]);
      finally
        for I := Low(ImportResult.Results) to High(ImportResult.Results) do
          ImportResult.Results[I].ErrorMessages.Free;
      end;
    finally
      Importer.Free;
    end;
    Model.LinkTypes.CreateDefaultData;
    TFileTypeIconSeeder.SeedIcons(Model.FileTypes);
  end;
  Model.ValueTypes.LoadCategories(Fresh);
  if Fresh then
  begin
    TemplatesDir := FSettings.TemplatesDir;
    if TemplatesDir = '' then TemplatesDir := ExtractFilePath(Application.ExeName) + 'ProtocolTemplates';
    Model.Templates.CreateDefaultTemplates(TemplatesDir, Model.User.Id);
    Model.Templates.UpdateTemplateCategories(TemplatesDir);
    Path := ExtractFilePath(Application.ExeName) + 'ExperimentTemplates';
    if TDirectory.Exists(Path) then
      for TemplatePath in TDirectory.GetFiles(Path, '*.elntemplate') do
        Model.ExperimentTemplates.ImportTemplateFromFile(TemplatePath, Model.User.Id, Warnings);
  end;
end;

procedure TfrmCommunityMain.ReleaseNotebook;
begin
  frmContentViewer.ResetSession;
  frmDashboard.ClearEntities;
  frmItems.ResetSession;
  frmProjects.ResetSession;
  UninstallElnLinkHandler;
  UninstallElnFileEnumerator;
  UninstallLocalElnFileService;
  FCurrentFileId := 0;
  FFiles.Clear;
  FreeAndNil(Model);
  FreeAndNil(FNotebook);
  RetainedWorkingFiles;
  FWorkingRoot := '';
  FDatabasePath := '';
  FStorageRoot := '';
  SetNotebookUI(False);
end;

procedure TfrmCommunityMain.RetainedWorkingFiles;
begin
  if (FWorkingRoot <> '') and TDirectory.Exists(FWorkingRoot) then
    MessageDlg('Working copies and any recovery backups are retained at:' +
      sLineBreak + FWorkingRoot + sLineBreak +
      'These are separate from notebook attachments. Keep this directory if you need to recover an editor draft.',
      mtInformation, [mbOK], 0);
end;

function TfrmCommunityMain.PrepareFile(FileId: Integer): string;
var
  Working: TWorkingFile;
begin
  Result := PrepareLocalElnFile(FileId);
  Working.Path := Result;
  FFiles.AddOrSetValue(FileId, Working);
end;

procedure TfrmCommunityMain.DisplayFile(FileId: Integer);
var
  Path: string;
begin
  if not Assigned(Model) or (FileId <= 0) then Exit;
  Path := PrepareFile(FileId);
  FCurrentFileId := FileId;
  miSaveDraft.Enabled := True;
  miReloadDraft.Enabled := True;
  frmContentViewer.DisplayFile(Path, FileId);
  StatusFile.Caption := Path;
end;

procedure TfrmCommunityMain.OpenFile(FileId: Integer);
var
  Path: string;
  Plugin: IViewerPlugin;
  Code: NativeInt;
begin
  if not Assigned(Model) or (FileId <= 0) then Exit;
  Path := PrepareFile(FileId);
  FCurrentFileId := FileId;
  miSaveDraft.Enabled := True;
  miReloadDraft.Enabled := True;
  StatusFile.Caption := Path;
  if SameText(ExtractFileExt(Path), '.md') and Assigned(MarkdownEditorLauncher) then
  begin
    MarkdownEditorLauncher.LaunchEditor(Path, Model.GetFileItemId(FileId), FileId,
      procedure(Body: string)
      begin
        if not FClosing and Assigned(Model) then DisplayFile(FileId);
      end);
    Exit;
  end;
  Plugin := frmContentViewer.FindPlugin(Path);
  if Assigned(Plugin) and Plugin.Params.IntOpen then
  begin
    DisplayFile(FileId);
    Exit;
  end;
  Code := NativeInt(ShellExecute(Handle, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL));
  if Code <= 32 then
    raise Exception.Create('Windows could not open the attachment. Choose an application for ' + ExtractFileExt(Path));
end;

function TfrmCommunityMain.SaveDraft(FileId: Integer): Boolean;
var
  Working: TWorkingFile;
  ErrorText: string;
  SaveResult: TSaveResult;
  Choice: Integer;
begin
  Result := True;
  if not FFiles.TryGetValue(FileId, Working) then Exit;
  if SameText(GetLocalElnOpenHash(FileId), WorkingHash(Working.Path)) then Exit;
  SaveResult := ElnFileService.SaveLocalFile(FileId, Working.Path, ErrorText);
  if SaveResult = srConflict then
  begin
    Choice := MessageDlg('The notebook attachment changed after this draft was opened.' +
      sLineBreak + 'Yes: save this draft over the current attachment.' +
      sLineBreak + 'No: reload the current attachment and discard this draft.' +
      sLineBreak + 'Cancel: keep the draft without saving.', mtWarning, [mbYes, mbNo, mbCancel], 0);
    if Choice = mrYes then
      SaveResult := ElnFileService.SaveLocalFileForce(FileId, Working.Path, ErrorText)
    else if Choice = mrNo then
      Exit(RefreshChangedFile(FileId, True));
  end;
  Result := SaveResult = srOk;
  if Result then
  begin
    if FCurrentFileId = FileId then DisplayFile(FileId);
  end
  else if SaveResult = srError then
    MessageDlg(ErrorText + sLineBreak + 'Draft and recovery files remain at ' + FWorkingRoot,
      mtError, [mbOK], 0);
end;

function TfrmCommunityMain.RefreshChangedFile(FileId: Integer;
  ExplicitReload: Boolean): Boolean;
var
  Working: TWorkingFile;
  Path, ErrorText: string;
  Dirty: Boolean;
  SaveResult: TSaveResult;
begin
  Result := False;
  if not Assigned(Model) or not FFiles.TryGetValue(FileId, Working) then Exit;
  try
    Dirty := not SameText(GetLocalElnOpenHash(FileId), WorkingHash(Working.Path));
    if not frmContentViewer.ConfirmFileReload(FileId, ExplicitReload or Dirty) then Exit;
    SaveResult := RefreshLocalElnFile(FileId, ExplicitReload or Dirty, Path, ErrorText);
    if SaveResult <> srOk then
    begin
      MessageDlg(ErrorText + sLineBreak + 'The draft remains at ' + Working.Path,
        mtError, [mbOK], 0);
      Exit;
    end;
    Working.Path := Path;
    FFiles.AddOrSetValue(FileId, Working);
    if frmContentViewer.IsFileDisplayed(FileId) then DisplayFile(FileId);
    Result := True;
  except
    on E: Exception do
      MessageDlg(E.Message + sLineBreak + 'Draft and recovery files remain at ' + FWorkingRoot,
        mtError, [mbOK], 0);
  end;
end;

procedure TfrmCommunityMain.ReloadDraft(FileId: Integer);
begin
  RefreshChangedFile(FileId, True);
end;

procedure TfrmCommunityMain.EditorClosing(Sender: TObject; var Action: TCloseAction);
begin
  if Assigned(FEditorCloseEvent) then FEditorCloseEvent(Sender, Action);
  FEditorCloseAccepted := Action in [caHide, caFree];
  FEditorCloseFree := Action = caFree;
  // Make release synchronous after Close returns. The plugin's original
  // handler still removes its window from its own registry first.
  if FEditorCloseFree then Action := caHide;
end;

function TfrmCommunityMain.FinishEditorsAndDrafts: Boolean;
var
  Forms: TArray<TForm>;
  Form: TForm;
  Pair: TPair<Integer, TWorkingFile>;
  Choice, I: Integer;
begin
  Result := False;
  SetLength(Forms, Screen.FormCount);
  for I := 0 to Screen.FormCount - 1 do Forms[I] := Screen.Forms[I];
  for Form in Forms do
    if (Form <> Self) and Form.Visible then
    begin
      FEditorCloseEvent := Form.OnClose;
      FEditorCloseAccepted := False;
      FEditorCloseFree := False;
      Form.OnClose := EditorClosing;
      try
        Form.Close;
      finally
        Form.OnClose := FEditorCloseEvent;
        FEditorCloseEvent := nil;
      end;
      if not FEditorCloseAccepted then Exit;
      if FEditorCloseFree then Form.Free;
    end;
  if Assigned(Model) then
    for Pair in FFiles.ToArray do
      if not SameText(GetLocalElnOpenHash(Pair.Key), WorkingHash(Pair.Value.Path)) then
      begin
        Choice := MessageDlg('Save changes from this attachment working copy?' +
          sLineBreak + Pair.Value.Path + sLineBreak +
          'If you choose No, the draft remains in the working directory.',
          mtConfirmation, [mbYes, mbNo, mbCancel], 0);
        if Choice = mrCancel then Exit;
        if (Choice = mrYes) and not SaveDraft(Pair.Key) then Exit;
      end;
  if Assigned(Model) then
  begin
    frmContentViewer.SaveCurrentState;
    Model.History.SaveHistory;
    Model.TreeState.Flush;
  end;
  Result := True;
end;

procedure TfrmCommunityMain.NewNotebookClick(Sender: TObject);
var
  Notebook: TLocalNotebook;
  FirstName, LastName, Password, StorageRoot: string;
  Manifest: TImportManifest;
  Importer: TServiceImporter;
  I: Integer;
begin
  if not NewNotebookDialog.Execute then Exit;
  StorageDialog.Title := 'Choose a separate, empty attachment directory';
  if not StorageDialog.Execute then Exit;
  StorageRoot := StorageDialog.FileName;
  if Length(TDirectory.GetFileSystemEntries(StorageRoot)) <> 0 then
    raise EArgumentException.Create('A new notebook requires an empty attachment directory. Existing files are never deleted or reused.');
  if not TdlgLocalProfile.Execute(FirstName, LastName, Password) then Exit;
  try
    // Check required shipped catalogs before creating any notebook bytes.
    Importer := TServiceImporter.Create(nil, 0);
    try
      Manifest := Importer.ScanFolder(ExtractFilePath(Application.ExeName) + 'CSV');
      for I := Low(Manifest.Files) to High(Manifest.Files) do
        if not Manifest.Files[I].Found then
          raise EFileNotFoundException.Create('Missing scientific catalog: ' + Manifest.Files[I].FileName);
    finally
      Importer.Free;
    end;
    if not FinishEditorsAndDrafts then Exit;
    Notebook := TLocalNotebook.CreateNew(NewNotebookDialog.FileName, StorageRoot,
      FirstName, LastName, Password);
    try
      ReleaseNotebook;
      BindNotebook(Notebook, NewNotebookDialog.FileName, StorageRoot, True);
      Notebook := nil;
    finally
      Notebook.Free;
    end;
  finally
    Password := '';
  end;
end;

procedure TfrmCommunityMain.OpenNotebookClick(Sender: TObject);
var
  Notebook: TLocalNotebook;
  StorageRoot: string;
begin
  if not OpenNotebookDialog.Execute then Exit;
  StorageDialog.Title := 'Choose this notebook''s attachment directory';
  if not StorageDialog.Execute then Exit;
  StorageRoot := StorageDialog.FileName;
  if SameText(TPath.GetFullPath(OpenNotebookDialog.FileName), FDatabasePath) then
  begin
    if not SameText(TPath.GetFullPath(StorageRoot), FStorageRoot) then
      raise EArgumentException.Create('Close this notebook before changing its attachment directory');
    Exit;
  end;
  // Validate the candidate before interrupting the active notebook.
  Notebook := TLocalNotebook.Open(OpenNotebookDialog.FileName, StorageRoot);
  try
    if not FinishEditorsAndDrafts then Exit;
    ReleaseNotebook;
    BindNotebook(Notebook, OpenNotebookDialog.FileName, StorageRoot, False);
    Notebook := nil;
  finally
    Notebook.Free;
  end;
end;

procedure TfrmCommunityMain.CloseNotebookClick(Sender: TObject);
begin
  if FinishEditorsAndDrafts then ReleaseNotebook;
end;

procedure TfrmCommunityMain.ExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmCommunityMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FinishEditorsAndDrafts;
  if CanClose then FClosing := True;
end;

procedure TfrmCommunityMain.FormDestroy(Sender: TObject);
begin
  FClosing := True;
  if Assigned(FSettings) then
  begin
    FSettings.SaveUIValue('CommunityMain', 'ProjectsPercent', spMain.Percent);
    FSettings.SaveUIValue('CommunityMain', 'ItemsPercent', spCenter.Percent);
    FSettings.SaveUIValue('CommunityMain', 'ViewerPercent', spRight.Percent);
  end;
  if Assigned(FFiles) then ReleaseNotebook;
  TConflictHandler.OnConflict := nil;
  FreeAndNil(FFiles);
  FreeAndNil(FSettings);
end;

procedure TfrmCommunityMain.NavigateItem(Sender: TObject; ProjectId, FolderId, ItemId: Integer);
begin
  if not Assigned(Model) then Exit;
  if FolderId > 0 then frmProjects.SelectFolder(FolderId)
  else frmProjects.SelectProject(ProjectId);
  if ItemId > 0 then frmItems.SelectItem(ItemId);
end;

procedure TfrmCommunityMain.OpenHypotheses(Sender: TObject; ProjectId, HypothesisId: Integer);
begin
  frmContentViewer.ShowHypotheses(ProjectId, HypothesisId);
end;

procedure TfrmCommunityMain.RunsChanged(Sender: TObject);
begin
  frmItems.RefreshKeepView;
  DecisionsChanged(Sender);
end;

procedure TfrmCommunityMain.DecisionsChanged(Sender: TObject);
begin
  frmDashboard.RefreshApprovals;
  frmProjects.RefreshHypothesisBadges;
end;

procedure TfrmCommunityMain.ImportPackage;
var
  Path: string;
  Importer: TELNPackageImporter;
  ImportResult: TELNPackageImportResult;
begin
  if not TdlgPackageImport.Execute(Path) then Exit;
  Importer := TELNPackageImporter.Create(Model.Manager);
  try
    ImportResult := Importer.ImportPackage(Path, Model.LastProject, Model.LastFolder, Model.User.Id);
    if not ImportResult.Success then raise Exception.Create(ImportResult.ErrorMessage);
    frmProjects.Init;
    WireCommands;
    MessageDlg(Format('Imported %d items and %d templates.',
      [ImportResult.ItemCount, ImportResult.TemplateCount]), mtInformation, [mbOK], 0);
  finally
    Importer.Free;
  end;
end;

procedure TfrmCommunityMain.CommandClick(Sender: TObject);
var
  Command: Integer;
  HtmlPlugin: IViewerPlugin;
begin
  Command := (Sender as TMenuItem).Tag;
  HtmlPlugin := frmContentViewer.FindPlugin('.html');
  if (Command < 90) and not Assigned(Model) then Exit;
  case Command of
    1: ImportPackage;
    10: edFileTypes.Show(Model.FileTypes.Dataset);
    11: edEquipmentTypes.Show(Model.EquipmentTypes.Dataset);
    12: edEquipment.ShowEditor(Model.Equipments.Dataset, Model.EquipmentTypes.Dataset);
    13: edActionTypes.ShowEditor(Model.ActionTypes.Dataset, Model.EquipmentTypes.Dataset, Model.FileTypes.Dataset);
    14: edValueTypes.Show(Model.ValueTypes.Dataset);
    15: edLinkTypes.Show(Model.LinkTypes.Dataset);
    16: TedTemplates.ShowManager(HtmlPlugin);
    17: TdlgExperimentTemplate.ManageTemplates;
    18: if TdlgTagManager.ShowTagEditor then frmItems.btnRefreshClick(Self);
    20: TdlgSearch.Execute(NavigateItem);
    21: TdlgGoToItem.Execute;
    22: begin frmDashboard.LoadData(Model.User.Role); frmContentViewer.ShowDashboard; end;
    23: begin
      if Model.LastProject <= 0 then raise Exception.Create('Select a project first');
      TfrmAnalysis.Execute(Model.LastProject, Model.LastFolder);
    end;
    24: TdlgUnitConverter.ShowConverter;
    25: TdlgProtocolReview.ShowQueue(frmContentViewer.FindPlugin('.protocol'));
    26: TdlgAuditLog.ShowLog;
    27: TdlgAuditRuleEditor.Execute;
    28: begin
      if Model.LastProject <= 0 then raise Exception.Create('Select a project first');
      TdlgAuditReport.Execute(Model.LastProject, Model.LastFolder, NavigateItem);
    end;
    29: if TdlgRecycleBin.ShowRecycleBin then begin frmProjects.Init; WireCommands; end;
    30: SaveDraft(FCurrentFileId);
    31: ReloadDraft(FCurrentFileId);
    90: TdlgHelpViewer.ShowHelp(ExtractFilePath(Application.ExeName) + 'Help\Index.html', HtmlPlugin, 'Community notebook help');
    91: TdlgHelpViewer.ShowHelp(ExtractFilePath(Application.ExeName) + 'Help\Shortcuts.html', HtmlPlugin, 'Keyboard shortcuts');
    92: TdlgAbout.ShowAbout(GetExeVersion, 2026);
  end;
end;

procedure TfrmCommunityMain.PreferencesClick(Sender: TObject);
var
  ScaleIndex: Integer;
  ScaleText: string;
begin
  if TdlgCommunityPreferences.Execute(FSettings) then
  begin
    TStyleManager.TrySetStyle(FSettings.VCLTheme);
    ThemePluginsEnabled := FSettings.DarkCharts;
    dmTreeImages.ApplyThemeIcons;
    ApplyAppearance;
    frmItems.SetShowItemIDs(FSettings.ShowItemIDs);
    ScaleText := IntToStr(FSettings.DashboardScale) + '%';
    ScaleIndex := frmDashboard.cbScale.Items.IndexOf(ScaleText);
    if ScaleIndex < 0 then ScaleIndex := frmDashboard.cbScale.Items.Add(ScaleText);
    frmDashboard.cbScale.ItemIndex := ScaleIndex;
    frmDashboard.cbScaleChange(frmDashboard.cbScale);
    if not SameText(FPluginsPath, FSettings.PluginsDir) then
      MessageDlg('The plugin-directory change takes effect on the next launch.', mtInformation, [mbOK], 0);
  end;
end;

procedure TfrmCommunityMain.ApplyAppearance;
begin
  dmTreeImages.ScaleForDPI(CurrentPPI);
  frmItems.ScaleForDPI;
  frmProjects.ScaleForDPI;
  TTreeLook.ApplyAll;
  frmItems.RefreshInfoColors;
end;

procedure TfrmCommunityMain.FormAfterMonitorDpiChanged(Sender: TObject; OldDPI, NewDPI: Integer);
begin
  ApplyAppearance;
end;

procedure TfrmCommunityMain.WMImageClick(var Msg: TMessage);
begin
  if not Assigned(Model) then Exit;
  FileThumbnailList.Select(Msg.WParam);
  frmItems.SelectFile(Msg.WParam);
  DisplayFile(Msg.WParam);
end;

procedure TfrmCommunityMain.WMImageDblClick(var Msg: TMessage);
begin
  OpenFile(Msg.WParam);
end;

procedure TfrmCommunityMain.WMImageContext(var Msg: TMessage);
begin
  if not Assigned(Model) then Exit;
  FileThumbnailList.Select(Msg.WParam);
  frmItems.ShowFilePopup(Msg.WParam);
end;

procedure TfrmCommunityMain.WMFileSelected(var Msg: TMessage);
begin
  FCurrentFileId := Msg.WParam;
  miSaveDraft.Enabled := Assigned(Model) and FFiles.ContainsKey(FCurrentFileId);
  miReloadDraft.Enabled := miSaveDraft.Enabled;
  if FCurrentFileId <= 0 then StatusFile.Caption := ''
  else if Assigned(Model) then StatusFile.Caption := Model.GetFileName(FCurrentFileId);
end;

procedure TfrmCommunityMain.WMFileChanged(var Msg: TMessage);
begin
  if Assigned(Model) and (Integer(Msg.WParam) > 0) then
    RefreshChangedFile(Msg.WParam, False);
end;

end.
