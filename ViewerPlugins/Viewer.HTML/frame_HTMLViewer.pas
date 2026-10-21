unit frame_HTMLViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.Edge;

type
  TframeHTMLViewer = class(TFrame)
  private
    const WM_DISPLAY_CONTENT = WM_APP + 41;
  private
    FBrowser: TEdgeBrowser;
    FWebViewReady: Boolean;
    FPendingHtml: string;
    FPendingFile: string;
    procedure EnsureBrowser;
    procedure HandleWebViewCreated(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
    procedure WMDisplayContent(var Message: TMessage); message WM_DISPLAY_CONTENT;
  public
    procedure LoadFile(const AFileName: string);
    procedure LoadHTML(const AHTML: string);
  end;

implementation

uses
  System.IOUtils, unit_ELNThemeHelper;

{$R *.dfm}

procedure TframeHTMLViewer.EnsureBrowser;
var
  EdgePath, DataFolder: string;
begin
  if FBrowser <> nil then
    Exit;

  EdgePath := FindWebView2RuntimeFolder;
  DataFolder := TPath.Combine(TPath.GetTempPath, 'ELN_HTMLViewer_WebView2');

  FBrowser := TEdgeBrowser.Create(Self);
  if EdgePath <> '' then
    FBrowser.BrowserExecutableFolder := EdgePath;
  FBrowser.UserDataFolder := DataFolder;
  FBrowser.OnCreateWebViewCompleted := HandleWebViewCreated;

  Self.HandleNeeded;
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.HandleNeeded;

  // If frame is already visible, CMShowingChanged won't fire again,
  // so trigger WebView creation directly
  if Showing then
    FBrowser.CreateWebView;
end;

procedure TframeHTMLViewer.CMShowingChanged(var Message: TMessage);
begin
  inherited;
  if Showing and (FBrowser <> nil) and not FWebViewReady then
    FBrowser.CreateWebView;
end;

procedure TframeHTMLViewer.HandleWebViewCreated(
  Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  if not Succeeded(AResult) then
    OutputDebugString(PChar(Format('[HTMLViewer] WebView2 creation failed hr=%.8x folder=%s',
      [AResult, FBrowser.BrowserExecutableFolder])));
  FWebViewReady := Succeeded(AResult);
  if FWebViewReady then
  begin
    ApplyBrowserColorScheme(FBrowser.DefaultInterface);
    // Vcl.Edge restores its prior URL after this callback returns.
    // Deliver the latest request after that restore, without a timer or retry.
    PostMessage(Handle, WM_DISPLAY_CONTENT, 0, 0);
  end;
end;

procedure TframeHTMLViewer.WMDisplayContent(var Message: TMessage);
begin
  if not FWebViewReady then Exit;
  if FPendingFile <> '' then
    FBrowser.Navigate(FPendingFile)
  else
    FBrowser.NavigateToString(FPendingHtml);
  if FBrowser.Focused then
    FBrowser.SetFocus;
end;

procedure TframeHTMLViewer.LoadFile(const AFileName: string);
begin
  FPendingFile := 'file:///' + StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  FPendingHtml := '';
  EnsureBrowser;
  if FWebViewReady then
    FBrowser.Navigate(FPendingFile);
end;

procedure TframeHTMLViewer.LoadHTML(const AHTML: string);
begin
  FPendingHtml := AHTML;
  FPendingFile := '';
  EnsureBrowser;
  if FWebViewReady then
    FBrowser.NavigateToString(AHTML);
end;

end.
