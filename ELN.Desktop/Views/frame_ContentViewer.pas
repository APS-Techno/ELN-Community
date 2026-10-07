unit frame_ContentViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls, RzEdit, RzPanel, RzButton, RzLabel,
  upfManager, unit_ELNPluginCore, Vcl.WinXPanels, dm_TreeImages,
  frame_Hypotheses;

type
  TViewerFrameRec = record
    Frame: IViewerPlugin;
    Params : TPluginParams;
    Tab  : TCard;
  end;

  TframeContentViewer = class(TFrame)
    Cards: TCardPanel;
    ButtonsPanel: TRzPanel;
    btnUpdateFile: TRzBitBtn;
    btnUpdatePreview: TRzBitBtn;
    btnOpen: TRzBitBtn;
    btnExtractValues: TRzBitBtn;
    btnResetView: TRzBitBtn;
    upfPluginManager: TupfPluginManager;
    Card1: TCard;
    pnlDownload: TPanel;
    lblDownload: TLabel;
    barDownload: TProgressBar;
    HypothesesCard: TCard;
    frmHypotheses: TframeHypotheses;
    procedure btnOpenClick(Sender: TObject);
    procedure btnExtractValuesClick(Sender: TObject);
    procedure btnResetViewClick(Sender: TObject);
    procedure btnUpdateFileClick(Sender: TObject);
    procedure btnUpdatePreviewClick(Sender: TObject);
    procedure upfPluginManagerPackageOnLoadError(Sender: TObject; AFilename, AMsg:
        string);
    procedure upfPluginManagerPluginRegistered(Sender, APlugin: TObject);
  private
    { Private declarations }
    Frames: array of TViewerFrameRec;
    BlankCard: TCard;
    FDashboard: TFrame;
    FCurrentFilePath: string;
    FOnUpdateFile: TNotifyEvent;
    FOnUpdatePreview: TNotifyEvent;
    FOnExtractValues: TNotifyEvent;
    FCurrentFileId: Integer;
    FCurrentItemId: Integer;

    procedure AddCard(APlugin: IViewerPlugin);
    procedure AddFrame(APlugin: IViewerPlugin; ACard: TCard);
    procedure HideDownloadProgress;
    function GetActivePlugin: IViewerPlugin;
    procedure ApplyHostToolbarPolicy(APlugin: IViewerPlugin);
  public
    { Public declarations }
    procedure Init(const APluginsDir: string = '');
    procedure DisplayFile(const FileName: string; AFileId: Integer = 0);
    function IsFileDisplayed(FileId: Integer): Boolean;
    // The plugin contract has no dirty query. Confirm before replacing loaded
    // viewer content, and require separate editors to be resolved by the user.
    function ConfirmFileReload(FileId: Integer; DiscardDraft: Boolean): Boolean;
    procedure DisplayNote(const Title, Text: string);
    procedure DisplayProtocol(const Title, ProtocolType, Status, CreatedDate,
      ModifiedDate, FormData, TemplateHtml,
      EquipModel, EquipManufacturer, EquipLocation: string);
    function FindPlugin(const AFileNameOrExt: string): IViewerPlugin;
    destructor Destroy; override;
    procedure Clear;
    procedure ResetSession;
    procedure ShowFileButtons(AVisible: Boolean);
    procedure SetDashboard(ADashboard: TFrame);
    procedure ShowDashboard;
    /// <summary>Shows the Hypotheses view for a project, selecting
    /// AHypothesisId when it is not 0.</summary>
    procedure ShowHypotheses(AProjectId, AHypothesisId: Integer);
    /// <summary>True while the Hypotheses view is the visible card.</summary>
    function HypothesesShowing: Boolean;
    /// <summary>Brings the Hypotheses view back without reloading it (after
    /// something else, e.g. an item-tree refresh, replaced the card).</summary>
    procedure ReturnToHypotheses;
    /// <summary>Before logout frees Model: frees the view's VM and leaves
    /// the card if it is showing.</summary>
    procedure ResetHypotheses;
    procedure ShowDownloadProgress(const AFileName: string);
    procedure UpdateDownloadProgress(Percent: Integer);
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function PluginCount: Integer;
    function GetPluginDiagnostics: TArray<string>;
    property OnUpdateFile: TNotifyEvent read FOnUpdateFile write FOnUpdateFile;
    property OnUpdatePreview: TNotifyEvent read FOnUpdatePreview write FOnUpdatePreview;
    property OnExtractValues: TNotifyEvent read FOnExtractValues write FOnExtractValues;
    procedure SaveCurrentState;
    procedure ResetViewerState;
  end;

implementation

{$R *.dfm}

uses
  Winapi.ShellAPI,
  Vcl.Imaging.pngimage, // Required for TPngImage
  unit_DataModel,
  unit_Item,
  unit_Helpers,
  unit_ViewerExtMatch,
  unit_ViewerState;

{ TframeContentViewer }

destructor TframeContentViewer.Destroy;
var
  I: Integer;
begin
  // Release interface references to plugin objects
  SetLength(Frames, 0);
  // Do NOT call upfPluginManager.UnloadPlugins here.
  // Unloading BPLs during Application shutdown invalidates VMTs of
  // plugin-created objects that may still be referenced by VCL infrastructure,
  // causing _BeforeDestruction AV in DoneApplication.DestroyComponents.
  // Clear module handles so the plugin manager destructor also skips UnloadPackage.
  // Process exit automatically unloads all loaded packages.
  for I := 0 to upfPluginManager.Packages.Count - 1 do
    upfPluginManager.Packages.HModules[I] := 0;
  inherited;
end;

procedure TframeContentViewer.DisplayFile(const FileName: string;
  AFileId: Integer);
var
  I, BestIdx, BestScore, Score: Integer;
  Rec: TViewerFrameRec;
  Found: Boolean;
  Stateful: IStatefulViewer;
  State: TViewerState;
  FileEnt: unit_Item.TFile;
  Ctx: IItemContextAware;
begin
  // Save current plugin state before switching (uses OLD FCurrentFileId)
  SaveCurrentState;

  // Now update to new file ID
  FCurrentFileId := AFileId;

  // Resolve owning item ID for plugins that implement IItemContextAware.
  // Lookup is best-effort — failure leaves FCurrentItemId = 0, which is the
  // documented "unknown" sentinel for SetItemContext.
  FCurrentItemId := 0;
  if (AFileId > 0) and Assigned(Model) and Assigned(Model.Manager) then
  begin
    try
      FileEnt := Model.Manager.Find<unit_Item.TFile>(AFileId);
      if Assigned(FileEnt) and Assigned(FileEnt.Item) then
        FCurrentItemId := FileEnt.Item.Id;
    except
      on E: Exception do
        OutputDebugString(PChar('Resolve owning item error: ' + E.Message));
    end;
  end;

  HideDownloadProgress;
  FCurrentFilePath := FileName;
  // Highest score wins, so a compound extension ('.depo.json') beats the
  // generic one ('.json') regardless of BPL load order.
  BestIdx   := -1;
  BestScore := 0;
  for I := 0 to High(Frames) do
  begin
    Score := ExtMatchScore(FileName, Frames[I].Params.Ext);
    if Score > BestScore then
    begin
      BestScore := Score;
      BestIdx   := I;
    end;
  end;

  Found := False;
  if BestIdx >= 0 then
  begin
    Rec := Frames[BestIdx];

    // Set routing context BEFORE LoadFromFile so plugins can use it during
    // initial render (e.g. Viewer.Markdown queries IElnFileEnumerator for
    // sibling files keyed on ItemId).
    if Supports(Rec.Frame, IItemContextAware, Ctx) then
      Ctx.SetItemContext(FCurrentItemId, FCurrentFileId);

    Rec.Frame.LoadFromFile(FileName);
    if Cards.ActiveCard <> Rec.Tab then
      Cards.ActiveCard := Rec.Tab;
    Found := True;

    // Toolbar visibility: plugins implementing IHostToolbarAware may
    // suppress ButtonsPanel. Default (no interface) keeps it visible.
    ApplyHostToolbarPolicy(Rec.Frame);

    // Restore state for new file
    if (AFileId > 0) and Assigned(Model) and
       Supports(Rec.Frame, IStatefulViewer, Stateful) then
    begin
      try
        State := Model.ViewerStates.GetState(Model.User.Id, AFileId);
        if Assigned(State) then
          Stateful.RestoreState(State.StateData);
      except
        on E: Exception do
          OutputDebugString(PChar('ViewerState restore error: ' + E.Message));
      end;
    end;
  end;
  // Fallback: try the FileViewer plugin (shell preview, Ext = '')
  if not Found then
    for Rec in Frames do
      if (Rec.Params.PType = ptFile) and (Rec.Params.Ext = '') then
      begin
        if Supports(Rec.Frame, IItemContextAware, Ctx) then
          Ctx.SetItemContext(FCurrentItemId, FCurrentFileId);

        Rec.Frame.LoadFromFile(FileName);
        if Cards.ActiveCard <> Rec.Tab then
          Cards.ActiveCard := Rec.Tab;
        Found := True;

        ApplyHostToolbarPolicy(Rec.Frame);

        Break;
      end;

  if not Found then
  begin
    ButtonsPanel.Visible := True;
    // No viewer matched, but the file is still open: re-assert the buttons.
    // ShowDownloadProgress hid them, and without this the panel comes back
    // empty - so "Update Preview" is missing for exactly those file types that
    // have no plugin. Same reason ApplyHostToolbarPolicy re-asserts them.
    ShowFileButtons(True);
    Cards.ActiveCard := BlankCard;
  end;
end;

procedure TframeContentViewer.DisplayNote(const Title, Text: string);
var
  Rec : TViewerFrameRec;
begin
  SaveCurrentState;
  FCurrentFileId := 0;
  FCurrentItemId := 0;
  ButtonsPanel.Visible := True;
  Cards.ActiveCard := BlankCard;
  for Rec in Frames do
  begin
    if Rec.Params.PType = ptText then
    begin
      Rec.Frame.DisplayText(Title, Text);
      Cards.ActiveCard := Rec.Tab;
      ApplyHostToolbarPolicy(Rec.Frame);
      Break;
    end;
  end;
end;

procedure TframeContentViewer.Init(const APluginsDir: string);
var
  PluginsDir: string;
begin
  BlankCard := TCard.Create(Cards);
  BlankCard.Parent := Cards;

  if APluginsDir <> '' then
    PluginsDir := IncludeTrailingPathDelimiter(APluginsDir)
  else
    PluginsDir := IncludeTrailingPathDelimiter(
      ExtractFilePath(Application.ExeName) + 'Plugins');

  upfPluginManager.PluginFolder := PluginsDir;
  // Plugin BPLs that depend on other plugin BPLs (e.g. Editor.Markdown
  // requires Viewer.Markdown for the preview-pane frame) need Plugins\ on
  // the DLL search path; otherwise Windows can't resolve the inter-plugin
  // dependency and LoadPackage fails silently with "missing module".
  SetDllDirectory(PChar(ExcludeTrailingPathDelimiter(PluginsDir)));
  upfPluginManager.LoadPlugins;

  Cards.ActiveCard := BlankCard;
end;

procedure TframeContentViewer.upfPluginManagerPackageOnLoadError(Sender: TObject;
    AFilename, AMsg: string);
begin
  OutputDebugString(PChar('Plugin load error: ' + AFilename + ' - ' + AMsg));
end;

procedure TframeContentViewer.upfPluginManagerPluginRegistered(Sender, APlugin:
    TObject);
var
  ATabSheetPlugin: IViewerPlugin;
begin
  if Supports(APlugin, IViewerPlugin, ATabSheetPlugin) then
  begin
    AddCard(ATabsheetPlugin);
    ATabSheetPlugin := nil;
  end;
end;

procedure TframeContentViewer.AddFrame(APlugin: IViewerPlugin; ACard: TCard);
var
  Rec: TViewerFrameRec;
begin
  Rec.Frame  := APlugin;
  Rec.Tab    := ACard;
  Rec.Params := APlugin.Params;
  Frames := Frames + [Rec];
end;

procedure TframeContentViewer.Clear;
begin
  SaveCurrentState;
  FCurrentFileId := 0;
  FCurrentItemId := 0;
  HideDownloadProgress;
  FCurrentFilePath := '';
  ButtonsPanel.Visible := True;
  Cards.ActiveCard := BlankCard;
end;

procedure TframeContentViewer.ResetSession;
var
  Rec: TViewerFrameRec;
  Context: IItemContextAware;
begin
  // Preserve the old notebook's viewer state before detaching its identities.
  Clear;
  ResetHypotheses;
  for Rec in Frames do
    if Supports(Rec.Frame, IItemContextAware, Context) then
      Context.SetItemContext(0, 0);
  FOnUpdateFile := nil;
  FOnUpdatePreview := nil;
  FOnExtractValues := nil;
  ShowFileButtons(False);
  ButtonsPanel.Visible := False;
end;

procedure TframeContentViewer.DisplayProtocol(const Title, ProtocolType, Status,
  CreatedDate, ModifiedDate, FormData, TemplateHtml,
  EquipModel, EquipManufacturer, EquipLocation: string);
var
  Rec: TViewerFrameRec;
  Encoded: string;
begin
  SaveCurrentState;
  FCurrentFileId := 0;
  FCurrentItemId := 0;
  // Encode fields with #1 separator for the Protocol Viewer plugin
  Encoded := ProtocolType + #1 + Status + #1 + CreatedDate + #1 +
             ModifiedDate + #1 + FormData + #1 + TemplateHtml + #1 +
             EquipModel + #1 + EquipManufacturer + #1 + EquipLocation;

  ButtonsPanel.Visible := True;
  Cards.ActiveCard := BlankCard;
  for Rec in Frames do
  begin
    if Rec.Params.Ext = '.protocol' then
    begin
      Rec.Frame.DisplayText(Title, Encoded);
      Cards.ActiveCard := Rec.Tab;
      ApplyHostToolbarPolicy(Rec.Frame);
      Break;
    end;
  end;
end;

function TframeContentViewer.FindPlugin(const AFileNameOrExt: string): IViewerPlugin;
var
  I, BestIdx, BestScore, Score: Integer;
begin
  Result    := nil;
  BestIdx   := -1;
  BestScore := 0;
  for I := 0 to High(Frames) do
  begin
    Score := ExtMatchScore(AFileNameOrExt, Frames[I].Params.Ext);
    if Score > BestScore then
    begin
      BestScore := Score;
      BestIdx   := I;
    end;
  end;
  if BestIdx >= 0 then
    Result := Frames[BestIdx].Frame;
end;

function TframeContentViewer.GetActivePlugin: IViewerPlugin;
var
  Rec: TViewerFrameRec;
begin
  Result := nil;
  if Cards.ActiveCard = BlankCard then
    Exit;
  for Rec in Frames do
    if Rec.Tab = Cards.ActiveCard then
      Exit(Rec.Frame);
end;

function TframeContentViewer.IsFileDisplayed(FileId: Integer): Boolean;
begin
  Result := (FileId > 0) and (FCurrentFileId = FileId) and
    (FCurrentFilePath <> '');
end;

function TframeContentViewer.ConfirmFileReload(FileId: Integer;
  DiscardDraft: Boolean): Boolean;
var
  I: Integer;
  Host: TCustomForm;
begin
  Result := False;
  Host := GetParentForm(Self);
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I].Visible and (Screen.Forms[I] <> Host) then
    begin
      MessageDlg('Close separate editor windows before reloading this attachment.' +
        sLineBreak + 'Use the editor''s Save, Discard or Cancel choice to resolve its edits.' +
        sLineBreak + 'The working draft and loaded viewer have not been replaced.',
        mtWarning, [mbOK], 0);
      Exit;
    end;
  if DiscardDraft or (IsFileDisplayed(FileId) and (GetActivePlugin <> nil)) then
    if MessageDlg('Reload the current notebook attachment?' +
      sLineBreak + 'Yes: discard the working draft and any unsaved viewer edits, then reload.' +
      sLineBreak + 'No or Cancel: keep the draft and loaded viewer unchanged.',
      mtWarning, [mbYes, mbNo, mbCancel], 0) <> mrYes then
      Exit;
  Result := True;
end;

procedure TframeContentViewer.ApplyHostToolbarPolicy(APlugin: IViewerPlugin);
var
  ToolbarAware: IHostToolbarAware;
  Show: Boolean;
begin
  if (APlugin <> nil) and Supports(APlugin, IHostToolbarAware, ToolbarAware) then
    Show := ToolbarAware.ShowHostToolbar
  else
    Show := True;
  ButtonsPanel.Visible := Show;
  if Show then
    // Re-assert button visibility too: ShowDashboard / ShowDownloadProgress
    // call ShowFileButtons(False), and that state would otherwise persist
    // into the next plugin activation as a panel-with-no-buttons.
    ShowFileButtons(True);
end;

procedure TframeContentViewer.AddCard(APlugin: IViewerPlugin);
var
  Card : TCard;
begin
  Card := TCard.Create(Cards);
  Card.Parent := Cards;
  APlugin.Frame.Parent := Card;
  APlugin.Frame.Align := alClient;

  AddFrame(APlugin, Card);
end;

procedure TframeContentViewer.btnOpenClick(Sender: TObject);
begin
  // SimpleShellExecute auto-quotes paths with spaces and consistently passes
  // a parent window handle — matches every other ShellExecute call site in
  // the app instead of bypassing the wrapper.
  if (FCurrentFilePath <> '') and FileExists(FCurrentFilePath) then
    SimpleShellExecute(Handle, FCurrentFilePath);
end;

procedure TframeContentViewer.btnExtractValuesClick(Sender: TObject);
begin
  if Assigned(FOnExtractValues) then
    FOnExtractValues(Sender);
end;

procedure TframeContentViewer.btnResetViewClick(Sender: TObject);
begin
  ResetViewerState;
end;

procedure TframeContentViewer.btnUpdateFileClick(Sender: TObject);
begin
  if Assigned(FOnUpdateFile) then
    FOnUpdateFile(Sender);
end;

procedure TframeContentViewer.btnUpdatePreviewClick(Sender: TObject);
begin
  if Assigned(FOnUpdatePreview) then
    FOnUpdatePreview(Sender);
end;

function TframeContentViewer.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
var
  Plugin: IViewerPlugin;
  PreviewProvider: IPreviewProvider;
begin
  Result := nil;
  Plugin := GetActivePlugin;
  if Assigned(Plugin) and
     Supports(Plugin, IPreviewProvider, PreviewProvider) then
    Result := PreviewProvider.GetPreview(MaxWidth, MaxHeight);
end;

procedure TframeContentViewer.ShowFileButtons(AVisible: Boolean);
begin
  btnOpen.Visible := AVisible;
  btnUpdateFile.Visible := AVisible;
  btnUpdatePreview.Visible := AVisible;
  btnExtractValues.Visible := AVisible;
  btnResetView.Visible := AVisible;
end;

procedure TframeContentViewer.SetDashboard(ADashboard: TFrame);
begin
  FDashboard := ADashboard;
  FDashboard.Parent := BlankCard;
  FDashboard.Align := alClient;
end;

function TframeContentViewer.PluginCount: Integer;
begin
  Result := Length(Frames);
end;

procedure TframeContentViewer.ShowDashboard;
begin
  SaveCurrentState;
  FCurrentFileId := 0;
  FCurrentItemId := 0;
  HideDownloadProgress;
  ShowFileButtons(False);
  ButtonsPanel.Visible := True;
  Cards.ActiveCard := BlankCard;
end;

procedure TframeContentViewer.ShowHypotheses(AProjectId, AHypothesisId: Integer);
begin
  SaveCurrentState;
  FCurrentFileId := 0;
  FCurrentItemId := 0;
  FCurrentFilePath := '';
  HideDownloadProgress;
  ShowFileButtons(False);
  ButtonsPanel.Visible := False;       // file buttons make no sense here
  frmHypotheses.OpenProject(AProjectId, AHypothesisId);
  Cards.ActiveCard := HypothesesCard;
end;

function TframeContentViewer.HypothesesShowing: Boolean;
begin
  Result := Cards.ActiveCard = HypothesesCard;
end;

procedure TframeContentViewer.ReturnToHypotheses;
begin
  SaveCurrentState;
  FCurrentFileId := 0;
  FCurrentItemId := 0;
  FCurrentFilePath := '';
  HideDownloadProgress;
  ShowFileButtons(False);
  ButtonsPanel.Visible := False;
  Cards.ActiveCard := HypothesesCard;
end;

procedure TframeContentViewer.ResetHypotheses;
begin
  frmHypotheses.ResetSession;
  if HypothesesShowing then
    Clear;
end;

procedure TframeContentViewer.ShowDownloadProgress(const AFileName: string);
begin
  lblDownload.Caption := 'Downloading ' + ExtractFileName(AFileName) + '...';
  barDownload.Position := 0;
  ShowFileButtons(False);
  ButtonsPanel.Visible := True;
  pnlDownload.Visible := True;
  pnlDownload.BringToFront;
end;

procedure TframeContentViewer.HideDownloadProgress;
begin
  pnlDownload.Visible := False;
end;

procedure TframeContentViewer.UpdateDownloadProgress(Percent: Integer);
begin
  if Percent < 0 then Percent := 0;
  if Percent > 100 then Percent := 100;
  barDownload.Position := Percent;
end;

function TframeContentViewer.GetPluginDiagnostics: TArray<string>;
var
  I: Integer;
  Rec: TViewerFrameRec;
  S: string;
begin
  SetLength(Result, Length(Frames));
  for I := 0 to High(Frames) do
  begin
    Rec := Frames[I];
    S := Rec.Frame.Caption + ': ' + Rec.Params.Ext;
    Result[I] := S;
  end;
end;

procedure TframeContentViewer.ResetViewerState;
var
  FileId: Integer;
begin
  if FCurrentFileId <= 0 then
    Exit;
  if not Assigned(Model) then
    Exit;

  FileId := FCurrentFileId;
  try
    Model.ViewerStates.DeleteForFile(FileId);
  except
    on E: Exception do
      OutputDebugString(PChar('ViewerState reset error: ' + E.Message));
  end;

  // Reload the file without state restoration
  if FCurrentFilePath <> '' then
  begin
    FCurrentFileId := 0;  // Prevent SaveCurrentState from re-saving
    DisplayFile(FCurrentFilePath, FileId);
  end;
end;

procedure TframeContentViewer.SaveCurrentState;
var
  Plugin: IViewerPlugin;
  Stateful: IStatefulViewer;
  StateJson: string;
begin
  if FCurrentFileId <= 0 then
    Exit;
  Plugin := GetActivePlugin;
  if not Assigned(Plugin) then
    Exit;
  if not Supports(Plugin, IStatefulViewer, Stateful) then
    Exit;
  StateJson := Stateful.SaveState;
  if StateJson = '' then
    Exit;
  try
    Model.ViewerStates.SaveOrUpdate(
      Model.User.Id, FCurrentFileId, Plugin.Caption, StateJson);
  except
    on E: Exception do
      OutputDebugString(PChar('ViewerState save error: ' + E.Message));
  end;
end;

end.
