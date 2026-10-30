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
    PluginClass: TComponentClass;
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
    NoteCard: TCard;
    NoteContent: TRichEdit;
    PreviewHost: TPanel;
    procedure btnOpenClick(Sender: TObject);
    procedure btnExtractValuesClick(Sender: TObject);
    procedure btnResetViewClick(Sender: TObject);
    procedure btnUpdateFileClick(Sender: TObject);
    procedure btnUpdatePreviewClick(Sender: TObject);
    procedure upfPluginManagerPackageOnLoadError(Sender: TObject; AFilename, AMsg:
        string);
    procedure upfPluginManagerPluginRegistered(Sender, APlugin: TObject);
    procedure upfPluginManagerAfterPackageLoaded(Sender: TObject; AFilename: string);
  private
    Frames: array of TViewerFrameRec;
    BlankCard: TCard;
    FDashboard: TFrame;
    FCurrentFilePath: string;
    FPreviewLoadError: string;
    FOnUpdateFile: TNotifyEvent;
    FOnUpdatePreview: TNotifyEvent;
    FOnExtractValues: TNotifyEvent;
    FCurrentFileId: Int64;
    FCurrentItemId: Integer;

    procedure AddCard(APlugin: IViewerPlugin);
    procedure AddFrame(APlugin: IViewerPlugin; ACard: TCard);
    procedure HideDownloadProgress;
    function GetActivePlugin: IViewerPlugin;
    procedure ApplyHostToolbarPolicy(APlugin: IViewerPlugin);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    procedure Init(const APluginsDir: string = '');
    procedure DisplayFile(const FileName: string; AFileId: Int64 = 0);
    function IsFileDisplayed(FileId: Int64): Boolean;
    // The plugin contract has no dirty query. Confirm before replacing loaded
    // viewer content, and require separate editors to be resolved by the user.
    function ConfirmFileReload(FileId: Int64; DiscardDraft: Boolean): Boolean;
    procedure DisplayNote(const Title, Text: string);
    procedure DisplayProtocol(const Title, ProtocolType, Status, CreatedDate,
      ModifiedDate, FormData, TemplateHtml,
      EquipModel, EquipManufacturer, EquipLocation: string);
    function FindPlugin(const AFileNameOrExt: string): IViewerPlugin;
    function LoadPreviewPlugin(const FileName: string; ItemId: Integer; FileId: Int64;
      AOwner: TComponent): IViewerPlugin;
    property PreviewLoadError: string read FPreviewLoadError;
    destructor Destroy; override;
    procedure Clear;
    procedure ResetSession;
    procedure ShowFileButtons(AVisible: Boolean);
    procedure SetDashboard(ADashboard: TFrame);
    procedure ShowDashboard;
    procedure ShowHypotheses(AProjectId, AHypothesisId: Integer);
    function HypothesesShowing: Boolean;
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
  Vcl.Imaging.pngimage, 
  unit_DataModel,
  unit_Item,
  unit_Helpers,
  unit_ViewerExtMatch,
  unit_ViewerState,
  unit_ElnAnalysisSettings;


procedure TframeContentViewer.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // The embedded native page control requests a handle while its DFM streams,
  // before the caller can assign this frame's Parent. Use the supplied host,
  // rather than requiring an application window (absent in a console host).
  if Parent = nil then
    if ParentWindow <> 0 then
      Params.WndParent := ParentWindow
    else if Owner is TWinControl then
      Params.WndParent := TWinControl(Owner).Handle;
end;

destructor TframeContentViewer.Destroy;
var
  I: Integer;
begin
  SetLength(Frames, 0);
  // Do NOT call upfPluginManager.UnloadPlugins here.
  // Unloading BPLs during Application shutdown invalidates VMTs of
  // plugin-created objects that may still be referenced by VCL infrastructure,
  // causing _BeforeDestruction AV in DoneApplication.DestroyComponents.
  // Clear module handles so the plugin manager destructor also skips UnloadPackage.
  // Process exit automatically unloads all loaded packages.
  // DFM construction can fail before its final component, the manager, exists.
  // Do not replace that original exception with a destructor access violation.
  if Assigned(upfPluginManager) and Assigned(upfPluginManager.Packages) then
    for I := 0 to upfPluginManager.Packages.Count - 1 do
      upfPluginManager.Packages.HModules[I] := 0;
  inherited;
end;

procedure TframeContentViewer.DisplayFile(const FileName: string;
  AFileId: Int64);
var
  I, BestIdx, BestScore, Score: Integer;
  Rec: TViewerFrameRec;
  Found: Boolean;
  Stateful: IStatefulViewer;
  State: TViewerState;
  FileEnt: unit_Item.TFile;
  Ctx: IItemContextAware;

  procedure LoadReader(const Plugin: IViewerPlugin);
  var
    Analysis: IAnalysisKeyValueProvider;
    Detail: string;
  begin
    try
      if Plugin.LoadFromFile(FileName) then
        Exit;
      Detail := '';
      if Supports(Plugin, IAnalysisKeyValueProvider, Analysis) then
        Detail := Analysis.GetLoadError;
      if Detail = '' then
        Detail := 'The reader rejected the file.';
      raise EReadError.CreateFmt('%s could not open "%s": %s',
        [Plugin.Caption, FileName, Detail]);
    except
      FCurrentFileId := 0;
      FCurrentItemId := 0;
      FCurrentFilePath := '';
      Cards.ActiveCard := BlankCard;
      ShowFileButtons(False);
      raise;
    end;
  end;

begin
  // Save current plugin state before switching (uses OLD FCurrentFileId)
  SaveCurrentState;

  FCurrentFileId := AFileId;

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

    LoadReader(Rec.Frame);
    if Cards.ActiveCard <> Rec.Tab then
      Cards.ActiveCard := Rec.Tab;
    Found := True;

    ApplyHostToolbarPolicy(Rec.Frame);

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

    if (AFileId > 0) and Assigned(Model) then
    begin
      try
        AttachAnalysisContext(Rec.Frame, FileName, AFileId);
      except
        on E: Exception do
          OutputDebugString(PChar('Analysis context error: ' + E.Message));
      end;
    end;
  end;
  if not Found then
    for Rec in Frames do
      if (Rec.Params.PType = ptFile) and (Rec.Params.Ext = '') then
      begin
        if Supports(Rec.Frame, IItemContextAware, Ctx) then
          Ctx.SetItemContext(FCurrentItemId, FCurrentFileId);

        LoadReader(Rec.Frame);
        if Cards.ActiveCard <> Rec.Tab then
          Cards.ActiveCard := Rec.Tab;
        Found := True;

        ApplyHostToolbarPolicy(Rec.Frame);

        Break;
      end;

  FCurrentFilePath := FileName;
  if not Found then
  begin
    ButtonsPanel.Visible := True;
    ShowFileButtons(True);
    Cards.ActiveCard := BlankCard;
  end;
end;

procedure TframeContentViewer.DisplayNote(const Title, Text: string);
var
  Stream: TStringStream;
begin
  Clear;
  ShowFileButtons(False);
  HideDownloadProgress;
  NoteContent.Clear;
  Stream := TStringStream.Create(Text);
  try
    NoteContent.Lines.LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
  NoteContent.SelStart := 0;
  Cards.ActiveCard := NoteCard;
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
  upfPluginManager.OnAfterPackageLoaded := upfPluginManagerAfterPackageLoaded;
  upfPluginManager.LoadPlugins;

  Cards.ActiveCard := BlankCard;
end;

procedure TframeContentViewer.upfPluginManagerAfterPackageLoaded(Sender: TObject;
    AFilename: string);
begin
  RegisterLoadedPackageUnits(AFilename);
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
    if APlugin is TComponent then
      Frames[High(Frames)].PluginClass := TComponentClass(APlugin.ClassType);
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
  Rec.PluginClass := nil;
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
  FCurrentFilePath := '';
  HideDownloadProgress;
  ShowFileButtons(False);
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
      ShowFileButtons(False);
      Break;
    end;
  end;
end;

function TframeContentViewer.LoadPreviewPlugin(const FileName: string;
  ItemId: Integer; FileId: Int64; AOwner: TComponent): IViewerPlugin;
var
  Source: IViewerPlugin;
  Rec: TViewerFrameRec;
  Instance: TComponent;
  Context: IItemContextAware;
  Analysis: IAnalysisKeyValueProvider;
begin
  Result := nil;
  FPreviewLoadError := '';
  if not Assigned(AOwner) then
    raise EArgumentNilException.Create('Preview owner is required');
  Source := FindPlugin(FileName);
  if not Assigned(Source) then Exit;
  for Rec in Frames do
    if (Rec.Frame = Source) and Assigned(Rec.PluginClass) then
    begin
      // Never load preview bytes into the registered, interactive instance.
      Instance := Rec.PluginClass.Create(AOwner);
      if not Supports(Instance, IViewerPlugin, Result) then Exit;
      Result.Frame.Parent := PreviewHost;
      if Supports(Result, IItemContextAware, Context) then
        Context.SetItemContext(ItemId, FileId);
      if not Result.LoadFromFile(FileName) then
      begin
        if Supports(Result, IAnalysisKeyValueProvider, Analysis) then
          FPreviewLoadError := Analysis.GetLoadError;
        Result := nil;
      end;
      Exit;
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

function TframeContentViewer.IsFileDisplayed(FileId: Int64): Boolean;
begin
  Result := (FileId > 0) and (FCurrentFileId = FileId) and
    (FCurrentFilePath <> '');
end;

function TframeContentViewer.ConfirmFileReload(FileId: Int64;
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
  ButtonsPanel.Visible := False;       
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
  FileId: Int64;
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
