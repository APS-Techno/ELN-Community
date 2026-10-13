unit unit_HTMLPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms,
  unit_ELNPluginCore,
  frame_HTMLViewer;

type

  TELNHTMLViewerPlugin = class(TELNBaseViewerPlugin, IReaderIdentity)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function LoadFromStream(Stream: TMemoryStream): Boolean; override;
    procedure DisplayText(const Caption, Text: string); override;
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNHTMLViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNHTMLViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNHTMLViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.html';
end;

function TELNHTMLViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TELNHTMLViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeHTMLViewer.Create(nil);
end;

function TELNHTMLViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.html;.htm';
  Result.PType   := ptFile;
  Result.IntOpen := False;
  Result.AcceptsPartialLoad := True;
end;

function TELNHTMLViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  TframeHTMLViewer(FFrame).LoadFile(AFileName);
  Result := True;
end;

function TELNHTMLViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
var
  HTML: string;
  Bytes: TBytes;
begin
  Result := False;
  if not Assigned(Stream) then
    Exit;

  Stream.Position := 0;
  SetLength(Bytes, Stream.Size);
  Stream.ReadBuffer(Bytes[0], Stream.Size);
  HTML := TEncoding.UTF8.GetString(Bytes);
  TframeHTMLViewer(FFrame).LoadHTML(HTML);
  Result := True;
end;

procedure TELNHTMLViewerPlugin.DisplayText(const Caption, Text: string);
begin
  TframeHTMLViewer(FFrame).LoadHTML(Text);
end;

end.
