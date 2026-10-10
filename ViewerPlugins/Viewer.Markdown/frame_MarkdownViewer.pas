unit frame_MarkdownViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.JSON,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.Edge,
  RzPanel, RzButton, RzCommon,
  WebView2;

type
  TframeMarkdownViewer = class(TFrame)
  private
    FBrowser: TEdgeBrowser;
    FWebViewReady: Boolean;
    FShellLoaded: Boolean;
    FPendingMarkdown: string;
    FPendingBaseHref: string;
    FHasPendingRender: Boolean;
    FToolBar:        TRzToolbar;
    FBtnEdit:        TRzToolButton;
    FToolBarHidden: Boolean;
    FContextLocal:   string;
    FContextItemId:  Integer;
    FContextFileId:  Int64;
    // The file:/// base href of the current attachment directory (with trailing
    // slash). Persisted so HandleNavigationStarting can confine file: clicks to
    // this folder. Unlike FPendingBaseHref, it is NOT cleared after InjectRender.
    FBaseHrefUrl:    string;
    // WebView2 CapturePreview is asynchronous; these carry the result of the
    // in-flight capture from HandleCaptureCompleted back to CaptureBitmap.
    FCaptureStream:  TMemoryStream;
    FCaptureDone:    Boolean;
    FCaptureResult:  HRESULT;
    procedure BuildToolBar;
    procedure DoEditClick(Sender: TObject);
    procedure EnsureBrowser;
    procedure HandleWebViewCreated(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure HandleNavigationCompleted(Sender: TCustomEdgeBrowser;
      IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure HandleNavigationStarting(Sender: TCustomEdgeBrowser;
      Args: TNavigationStartingEventArgs);
    procedure HandleCaptureCompleted(Sender: TCustomEdgeBrowser;
      AResult: HRESULT);
    function GetContentRendered: Boolean;
    procedure ShowToast(const AMessage: string);
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
    function ShellUrl: string;
    procedure InjectRender;
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    procedure RenderMarkdown(const AMarkdown, ABaseHrefUrl: string);
    procedure SetEditContext(const ALocalPath: string; AItemId: Integer; AFileId: Int64);
    procedure HideToolBar;
    function CaptureBitmap(MaxW, MaxH: Integer): TBitmap;
    // True only once the shell has loaded AND the pending markdown has been
    // injected — i.e. there is real content on screen worth capturing.
    property ContentRendered: Boolean read GetContentRendered;
  end;

implementation

uses
  System.IOUtils, System.StrUtils, System.NetEncoding,
  Winapi.ActiveX, Winapi.ShellAPI,
  Vcl.Imaging.PngImage,
  unit_ELNPreviewUtils,
  unit_ELNPluginCore,
  unit_ELNThemeHelper,
  unit_MarkdownLinkRewriter,
  unit_MarkdownAttachmentResolver;

{$R *.dfm}

// Canonicalize a file: URL for prefix comparison: percent-decode and lowercase
// so two URLs match regardless of whether the browser encoded spaces/parens
// (e.g. '%20') while our ToFileUrl builder left them literal. Same decode is
// applied to both sides, so the comparison stays consistent.
function NormalizeFileUrl(const AUrl: string): string;
begin
  Result := LowerCase(TNetEncoding.URL.Decode(
    StringReplace(StringReplace(AUrl, '\', '/', [rfReplaceAll]),
      '+', '%2B', [rfReplaceAll])));
end;


procedure TframeMarkdownViewer.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  // Raize toolbar layout needs an actual parent chain. A frame is constructed
  // before its host assigns Parent, so do not build these controls in Create.
  if (AParent <> nil) and (FToolBar = nil) and
    not (csDestroying in ComponentState) then
    BuildToolBar;
end;

procedure TframeMarkdownViewer.BuildToolBar;
begin
  FToolBar := TRzToolbar.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Align  := alBottom;
  FToolBar.Height := 28;
  FToolBar.BorderOuter := fsFlatRounded;
  FToolBar.ShowDivider := True;

  FBtnEdit := TRzToolButton.Create(Self);
  FBtnEdit.Parent              := FToolBar;
  FBtnEdit.Caption             := 'Edit';
  FBtnEdit.UseToolbarShowCaption := False;
  FBtnEdit.ShowCaption         := True;
  FBtnEdit.Hint                := 'Open this file in the markdown editor';
  FBtnEdit.OnClick             := DoEditClick;
  FBtnEdit.Visible             := Assigned(MarkdownEditorLauncher);
  FToolBar.Visible := not FToolBarHidden;
end;

procedure TframeMarkdownViewer.SetEditContext(const ALocalPath: string;
  AItemId: Integer; AFileId: Int64);
begin
  FContextLocal  := ALocalPath;
  FContextItemId := AItemId;
  FContextFileId := AFileId;
  // Re-evaluate edit-button visibility (Editor.Markdown might've loaded since
  // the constructor ran).
  if Assigned(FBtnEdit) then
    FBtnEdit.Visible := Assigned(MarkdownEditorLauncher);
end;

procedure TframeMarkdownViewer.HideToolBar;
begin
  FToolBarHidden := True;
  if Assigned(FToolBar) then
    FToolBar.Visible := False;
end;

procedure TframeMarkdownViewer.DoEditClick(Sender: TObject);
var
  SourcePath: string;
  SourceItemId: Integer;
  SourceFileId: Int64;
begin
  if not Assigned(MarkdownEditorLauncher) then Exit;
  if FContextLocal = '' then Exit;
  SourcePath := FContextLocal;
  SourceItemId := FContextItemId;
  SourceFileId := FContextFileId;
  MarkdownEditorLauncher.LaunchEditor(
    SourcePath,
    SourceItemId,
    SourceFileId,
    procedure(NewBody: string)
    var
      Rendered, BaseHref, Dir: string;
      Files: TArray<string>;
    begin
      if (FContextLocal <> SourcePath) or (FContextItemId <> SourceItemId) or
        (FContextFileId <> SourceFileId) then Exit;
      Dir := ExtractFilePath(SourcePath);
      Files := nil;
      if (SourceItemId > 0) and Assigned(ElnFileEnumerator) then
        Files := ElnFileEnumerator.EnsureItemFilesInDir(SourceItemId, Dir);
      Rendered := RewriteAttachmentRefs(NewBody, Dir, Files);
      Rendered := RewriteElnLinks(Rendered);
      BaseHref := MarkdownFileUrl(IncludeTrailingPathDelimiter(Dir));
      // Enumeration can pump messages in a remote host.
      if (FContextLocal <> SourcePath) or (FContextItemId <> SourceItemId) or
        (FContextFileId <> SourceFileId) then Exit;
      RenderMarkdown(Rendered, BaseHref);
    end);
end;

function JsonEncodeString(const S: string): string;
var
  JS: TJSONString;
begin
  JS := TJSONString.Create(S);
  try
    Result := JS.ToJSON;
  finally
    JS.Free;
  end;
end;

function TframeMarkdownViewer.ShellUrl: string;
var
  Dir, ShellPath: string;
begin
  Dir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Plugins\MarkdownViewer');
  ShellPath := TPath.Combine(Dir, 'shell.html');
  if not TFile.Exists(ShellPath) then
  begin
    OutputDebugString(PChar('[MarkdownViewer] shell.html not found: ' + ShellPath));
    raise EFileNotFoundException.Create('Markdown viewer asset missing: ' + ShellPath);
  end;
  Result := MarkdownFileUrl(ShellPath);
end;

procedure TframeMarkdownViewer.EnsureBrowser;
var
  EdgePath, DataFolder: string;
begin
  if FBrowser <> nil then Exit;
  EdgePath := FindWebView2RuntimeFolder;
  DataFolder := TPath.Combine(TPath.GetTempPath, 'ELN_MarkdownViewer_WebView2');
  FBrowser := TEdgeBrowser.Create(Self);
  if EdgePath <> '' then
    FBrowser.BrowserExecutableFolder := EdgePath;
  FBrowser.UserDataFolder := DataFolder;
  FBrowser.OnCreateWebViewCompleted := HandleWebViewCreated;
  FBrowser.OnNavigationCompleted := HandleNavigationCompleted;
  FBrowser.OnNavigationStarting := HandleNavigationStarting;
  FBrowser.OnCapturePreviewCompleted := HandleCaptureCompleted;
  Self.HandleNeeded;
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.HandleNeeded;
  if Showing then
    FBrowser.CreateWebView;
end;

procedure TframeMarkdownViewer.CMShowingChanged(var Message: TMessage);
begin
  inherited;
  if Showing and (FBrowser <> nil) and not FWebViewReady then
    FBrowser.CreateWebView;
end;

procedure TframeMarkdownViewer.HandleWebViewCreated(
  Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  // A failed environment creation otherwise leaves a silently blank panel —
  // e.g. hr=80070032 when the folder points at a stable Edge browser install.
  if not Succeeded(AResult) then
    OutputDebugString(PChar(Format('[MarkdownViewer] WebView2 creation failed hr=%.8x folder=%s',
      [AResult, FBrowser.BrowserExecutableFolder])));
  FWebViewReady := Succeeded(AResult);
  if FWebViewReady then
    ApplyBrowserColorScheme(FBrowser.DefaultInterface);
  if FWebViewReady and FHasPendingRender then
    FBrowser.Navigate(ShellUrl);
end;

procedure TframeMarkdownViewer.HandleNavigationCompleted(
  Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
  WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
var
  Source: PWideChar;
  CurrentUrl: string;
begin
  if not IsSuccess then Exit;
  Source := nil;
  if (FBrowser.DefaultInterface = nil) or
    Failed(FBrowser.DefaultInterface.Get_Source(Source)) then Exit;
  try
    CurrentUrl := string(Source);
  finally
    CoTaskMemFree(Source);
  end;
  // An attachment document is not our rendering shell.
  FShellLoaded := IsMarkdownShellUrl(CurrentUrl, ShellUrl);
  if FShellLoaded and FHasPendingRender then
    InjectRender;
end;

procedure TframeMarkdownViewer.HandleNavigationStarting(
  Sender: TCustomEdgeBrowser;
  Args: TNavigationStartingEventArgs);
var
  UriPtr: PWideChar;
  Uri: string;
begin
  if Args = nil then Exit;

  UriPtr := nil;
  if Succeeded(Args.ArgsInterface.Get_uri(UriPtr)) and (UriPtr <> nil) then
  try
    Uri := string(UriPtr);
  finally
    CoTaskMemFree(UriPtr);
  end;

  if Uri = '' then Exit;

  if StartsText('eln://', Uri) then
  begin
    Args.ArgsInterface.Set_Cancel(1);    // literal 1, not Integer(True)
    OutputDebugString(PChar('[MarkdownViewer] ELN link clicked: ' + Uri));
    if Assigned(ElnLinkHandler) then
    begin
      if not ElnLinkHandler.HandleLink(Uri) then
        ShowToast('Could not resolve: ' + Uri);
    end
    else
      ShowToast('Clicked: ' + Uri);
  end
  else if StartsText('http://', Uri) or StartsText('https://', Uri) or
          StartsText('mailto:', Uri) then
  begin
    // External links must not hijack the in-app WebView — cancel the in-place
    // navigation and hand the URL to the OS default handler instead.
    Args.ArgsInterface.Set_Cancel(1);
    ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);
  end
  else if StartsText('file:', Uri) then
  begin
    if IsMarkdownShellUrl(Uri, ShellUrl) then Exit;
    // Attachment pages may be viewed, but never count as the rendering shell.
    // The next RenderMarkdown call reloads shell.html before injecting content.
    if (FBaseHrefUrl = '') or
       not StartsText(NormalizeFileUrl(FBaseHrefUrl), NormalizeFileUrl(Uri)) then
    begin
      Args.ArgsInterface.Set_Cancel(1);
      OutputDebugString(PChar('[MarkdownViewer] Blocked file navigation outside attachment dir: ' + Uri));
      ShowToast('Blocked link outside the attachment folder');
    end
    else
      FShellLoaded := False;
  end
  else
    Args.ArgsInterface.Set_Cancel(1);
end;

procedure TframeMarkdownViewer.ShowToast(const AMessage: string);
var
  Script: string;
begin
  if not FShellLoaded then Exit;
  Script :=
    '(function(){' +
    '  if (!document.body) return;' +
    '  var t = document.createElement("div");' +
    '  t.style.cssText = "position:fixed;top:12px;right:12px;background:#323232;color:#fff;' +
    '    padding:8px 16px;border-radius:4px;z-index:9999;font-family:Segoe UI,sans-serif;' +
    '    font-size:13px;box-shadow:0 2px 8px rgba(0,0,0,.3);opacity:0;transition:opacity .25s;";' +
    '  t.textContent = ' + JsonEncodeString(AMessage) + ';' +
    '  document.body.appendChild(t);' +
    '  requestAnimationFrame(function(){ t.style.opacity = "0.95"; });' +
    '  setTimeout(function(){ t.style.opacity = "0"; setTimeout(function(){ t.remove(); }, 300); }, 2500);' +
    '})();';
  FBrowser.ExecuteScript(Script);
end;

procedure TframeMarkdownViewer.InjectRender;
var
  Script: string;
begin
  Script := Format('window.renderMarkdown(%s, %s);',
    [JsonEncodeString(FPendingMarkdown), JsonEncodeString(FPendingBaseHref)]);
  FBrowser.ExecuteScript(Script);
  FPendingMarkdown := '';
  FPendingBaseHref := '';
  FHasPendingRender := False;
end;

procedure TframeMarkdownViewer.RenderMarkdown(const AMarkdown, ABaseHrefUrl: string);
begin
  FPendingMarkdown := AMarkdown;
  FPendingBaseHref := ABaseHrefUrl;
  FBaseHrefUrl     := ABaseHrefUrl;
  FHasPendingRender := True;
  EnsureBrowser;
  if not FWebViewReady then Exit;         // Will continue via HandleWebViewCreated
  if FShellLoaded then InjectRender
  else FBrowser.Navigate(ShellUrl);
end;

procedure TframeMarkdownViewer.HandleCaptureCompleted(
  Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  FCaptureResult := AResult;
  FCaptureDone := True;
end;

function TframeMarkdownViewer.GetContentRendered: Boolean;
begin
  Result := FWebViewReady and FShellLoaded and not FHasPendingRender;
end;

function TframeMarkdownViewer.CaptureBitmap(MaxW, MaxH: Integer): TBitmap;
const
  TimeoutMs = 5000;
var
  Png: TPngImage;
  StartTick: Cardinal;
begin
  Result := nil;
  if (FBrowser = nil) or not GetContentRendered then Exit;
  // A capture is already in flight (re-entered via ProcessMessages below);
  // bail out rather than trample its stream.
  if FCaptureStream <> nil then Exit;

  FCaptureStream := TMemoryStream.Create;
  try
    FCaptureDone := False;
    FCaptureResult := E_FAIL;

    try
      FBrowser.CapturePreview(FCaptureStream);
    except
      Exit;
    end;

    StartTick := GetTickCount;
    while (not FCaptureDone) and (GetTickCount - StartTick < TimeoutMs) do
    begin
      Application.ProcessMessages;
      Sleep(10);
    end;

    if (not FCaptureDone) or not Succeeded(FCaptureResult) or
       (FCaptureStream.Size = 0) then
      Exit;

    FCaptureStream.Position := 0;
    Png := TPngImage.Create;
    try
      Png.LoadFromStream(FCaptureStream);
      Result := CreateScaledPreview(Png, MaxW, MaxH);
    finally
      Png.Free;
    end;
  finally
    FreeAndNil(FCaptureStream);
  end;
end;

end.
