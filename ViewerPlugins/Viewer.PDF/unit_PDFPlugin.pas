unit unit_PDFPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore,
  frame_PDFViewer;

type

  TELNPDFViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider, IReaderIdentity)
  private
    FFileName: string;
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

  procedure Register;
  procedure UnRegister;

implementation

uses
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj;

var
  APlugin: TELNPDFViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNPDFViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNPDFViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.pdf';
end;

function TELNPDFViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TELNPDFViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframePDFViewer.Create(nil);
end;

function TELNPDFViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.pdf';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNPDFViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  FFileName := AFileName;
  TframePDFViewer(FFrame).LoadFile(AFileName);
  Result := True;
end;

function TELNPDFViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): Vcl.Graphics.TBitmap;
var
  Factory: IShellItemImageFactory;
  HBmp: HBITMAP;
  Size: TSize;
  HR: HRESULT;
begin
  // First try capturing the live WebView2 render — reliable when the viewer
  // is currently showing the PDF (the "Update Preview" button case).
  Result := nil;
  if Assigned(FFrame) and TframePDFViewer(FFrame).WebViewReady then
    Result := TframePDFViewer(FFrame).CaptureBitmap(MaxWidth, MaxHeight);
  if Assigned(Result) then Exit;

  // Fall back to the Windows shell thumbnail for background queue runs where
  // the WebView isn't rendered. Works when a PDF thumbnail handler is
  // registered (Edge/Adobe); returns nil otherwise.
  if (FFileName = '') or not FileExists(FFileName) then
    Exit;

  HR := SHCreateItemFromParsingName(
    PChar(FFileName), nil, IShellItemImageFactory, Factory);
  if not Succeeded(HR) or (Factory = nil) then
    Exit;

  Size.cx := MaxWidth;
  Size.cy := MaxHeight;
  HBmp := 0;
  HR := Factory.GetImage(Size, SIIGBF_THUMBNAILONLY or SIIGBF_BIGGERSIZEOK, HBmp);
  if not Succeeded(HR) or (HBmp = 0) then
    Exit;

  Result := Vcl.Graphics.TBitmap.Create;
  try
    Result.Handle := HBmp;
  except
    FreeAndNil(Result);
    DeleteObject(HBmp);
    raise;
  end;
end;

end.
