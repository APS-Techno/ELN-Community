unit unit_FilePlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms,
  unit_ELNPluginCore,
  frame_FileViewer;

type

  TELNFileViewerPlugin = class(TELNBaseViewerPlugin)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNFileViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNFileViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNFileViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeFileViewer.Create(nil);
end;

function TELNFileViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNFileViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  TframeFileViewer(FFrame).JamFilePreview.Path := AFileName;
  Result := True;
end;

end.
