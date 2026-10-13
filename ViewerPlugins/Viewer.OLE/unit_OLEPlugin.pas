unit unit_OLEPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms,
  unit_ELNPluginCore,
  frame_OLEViewer;

type

  TELNOLEViewerPlugin = class(TELNBaseViewerPlugin)
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
  APlugin: TELNOLEViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNOLEViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNOLEViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeOLEViewer.Create(nil);
end;

function TELNOLEViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.xlsx;.docx;.pptx';
  Result.PType   := ptOLE;
  Result.IntOpen := False;
end;

function TELNOLEViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  TframeOLEViewer(FFrame).LoadOLEFile(AFileName);
  Result := True;
end;

end.
