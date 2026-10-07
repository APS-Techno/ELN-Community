unit unit_ImagePlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore,
  frame_ImageViewer;

type

  TELNImageViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IStatefulViewer)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function LoadFromStream(Stream: TMemoryStream): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function SaveState: string;
    procedure RestoreState(const AState: string);
  end;

  procedure Register;
  procedure UnRegister;

implementation

uses
  Winapi.Wincodec;

var
  APlugin: TELNImageViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNImageViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNImageViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeImageViewer.Create(nil);
end;

function TELNImageViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.png;.bmp;.jpg;.jpeg;.tif;.tiff';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNImageViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
var
  WIC: TWICImage;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  // WIC detects the format from the content, not the extension, so a
  // mislabeled file (e.g. a BMP saved as .jpg) still renders.
  WIC := TWICImage.Create;
  try
    WIC.LoadFromFile(AFileName);
    TframeImageViewer(FFrame).Image.Picture.Assign(WIC);
  finally
    WIC.Free;
  end;

  TframeImageViewer(FFrame).ImageLoaded;
  Result := True;
end;

function TELNImageViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
var
  WIC: TWICImage;
begin
  Result := False;
  if not Assigned(Stream) then
    Exit;

  Stream.Position := 0;
  WIC := TWICImage.Create;
  try
    WIC.LoadFromStream(Stream);
    TframeImageViewer(FFrame).Image.Picture.Assign(WIC);
  finally
    WIC.Free;
  end;

  TframeImageViewer(FFrame).ImageLoaded;
  Result := True;
end;

function TELNImageViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeImageViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNImageViewerPlugin.SaveState: string;
begin
  Result := TframeImageViewer(FFrame).SaveState;
end;

procedure TELNImageViewerPlugin.RestoreState(const AState: string);
begin
  TframeImageViewer(FFrame).RestoreState(AState);
end;

end.
