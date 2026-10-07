unit frame_PDFViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.Edge;

type
  TframePDFViewer = class(TFrame)
  private
    FBrowser: TEdgeBrowser;
    FWebViewReady: Boolean;
    FPendingFile: string;
    FCaptureStream: TMemoryStream;
    FCaptureDone: Boolean;
    FCaptureResult: HRESULT;
    procedure EnsureBrowser;
    procedure HandleWebViewCreated(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure HandleCaptureCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
  public
    procedure LoadFile(const AFileName: string);
    function CaptureBitmap(MaxW, MaxH: Integer): TBitmap;
    property WebViewReady: Boolean read FWebViewReady;
  end;

implementation

uses
  System.IOUtils, System.Math,
  Vcl.Imaging.PngImage, unit_ELNThemeHelper;

{$R *.dfm}

procedure TframePDFViewer.EnsureBrowser;
var
  EdgePath, DataFolder: string;
begin
  if FBrowser <> nil then
    Exit;

  EdgePath := FindWebView2RuntimeFolder;
  DataFolder := TPath.Combine(TPath.GetTempPath, 'ELN_PDFViewer_WebView2');

  FBrowser := TEdgeBrowser.Create(Self);
  if EdgePath <> '' then
    FBrowser.BrowserExecutableFolder := EdgePath;
  FBrowser.UserDataFolder := DataFolder;
  FBrowser.OnCreateWebViewCompleted := HandleWebViewCreated;
  FBrowser.OnCapturePreviewCompleted := HandleCaptureCompleted;

  Self.HandleNeeded;
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.HandleNeeded;

  if Showing then
    FBrowser.CreateWebView;
end;

procedure TframePDFViewer.CMShowingChanged(var Message: TMessage);
begin
  inherited;
  if Showing and (FBrowser <> nil) and not FWebViewReady then
    FBrowser.CreateWebView;
end;

procedure TframePDFViewer.HandleWebViewCreated(
  Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  if not Succeeded(AResult) then
    OutputDebugString(PChar(Format('[PDFViewer] WebView2 creation failed hr=%.8x folder=%s',
      [AResult, FBrowser.BrowserExecutableFolder])));
  FWebViewReady := Succeeded(AResult);
  if FWebViewReady then
    ApplyBrowserColorScheme(FBrowser.DefaultInterface);
  if FWebViewReady and (FPendingFile <> '') then
  begin
    FBrowser.Navigate(FPendingFile);
    FPendingFile := '';
  end;
end;

procedure TframePDFViewer.HandleCaptureCompleted(
  Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  FCaptureResult := AResult;
  FCaptureDone := True;
end;

// Build a file:/// URL from a local path, encoding the characters a browser
// would otherwise misparse: '%' (escape introducer, encoded first), '#'
// (fragment — filenames carry '#N' auto-suffixes), and '?' (query).
function ToFileUrl(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := StringReplace(Result, '%', '%25', [rfReplaceAll]);
  Result := StringReplace(Result, '#', '%23', [rfReplaceAll]);
  Result := StringReplace(Result, '?', '%3F', [rfReplaceAll]);
  Result := 'file:///' + Result;
end;

procedure TframePDFViewer.LoadFile(const AFileName: string);
var
  FileUrl: string;
begin
  EnsureBrowser;
  FileUrl := ToFileUrl(AFileName);
  if FWebViewReady then
    FBrowser.Navigate(FileUrl)
  else
    FPendingFile := FileUrl;
end;

function TframePDFViewer.CaptureBitmap(MaxW, MaxH: Integer): TBitmap;
const
  TimeoutMs = 5000;
var
  Png: TPngImage;
  Full: TBitmap;
  Ratio: Double;
  NewW, NewH: Integer;
  StartTick: Cardinal;
begin
  Result := nil;
  if (FBrowser = nil) or not FWebViewReady then Exit;

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
      Full := TBitmap.Create;
      try
        Full.Assign(Png);

        if (Full.Width = 0) or (Full.Height = 0) then Exit;

        Ratio := Min(MaxW / Full.Width, MaxH / Full.Height);
        if Ratio >= 1.0 then
        begin
          Result := Full;
          Full := nil;
          Exit;
        end;

        NewW := Max(1, Round(Full.Width * Ratio));
        NewH := Max(1, Round(Full.Height * Ratio));
        Result := TBitmap.Create;
        Result.PixelFormat := pf32bit;
        Result.SetSize(NewW, NewH);
        SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
        Result.Canvas.StretchDraw(Rect(0, 0, NewW, NewH), Full);
      finally
        Full.Free;
      end;
    finally
      Png.Free;
    end;
  finally
    FreeAndNil(FCaptureStream);
  end;
end;

end.
