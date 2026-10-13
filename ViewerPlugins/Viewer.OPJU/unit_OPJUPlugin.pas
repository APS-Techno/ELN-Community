unit unit_OPJUPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore,
  frame_OPJUViewer;

type

  TELNOPJUViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNOPJUViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNOPJUViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNOPJUViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeOPJUViewer.Create(nil);
end;

function TELNOPJUViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.opju';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNOPJUViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  // OPJU frame parses embedded PNGs via TPngImage.LoadFromStream which can
  // raise on malformed payloads. Without this guard the exception propagates
  // past the plugin boundary and terminates the host application.
  try
    TframeOPJUViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

function TELNOPJUViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeOPJUViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

end.
