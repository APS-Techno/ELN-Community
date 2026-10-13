unit unit_DSRPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms,
  unit_ELNPluginCore,
  frame_DSRViewer;

type

  TELNDSRViewerPlugin = class(TELNBaseViewerPlugin)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function LoadFromStream(Stream: TMemoryStream): Boolean; override;
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNDSRViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNDSRViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNDSRViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeDSRViewer.Create(nil);
end;

function TELNDSRViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.dsr';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNDSRViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    TframeDSRViewer(FFrame).Panel.LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

function TELNDSRViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
var
  S: string;
begin
  Result := False;
  if not Assigned(Stream) then
    Exit;

  Stream.Position := 0;
  SetLength(S, Stream.Size);
  Stream.ReadBuffer(S[1], Stream.Size);
  try
    TframeDSRViewer(FFrame).Panel.LoadFromString(S);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

end.
