unit unit_JSONPlugin;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_JSONViewer;

type

  TELNJSONViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function LoadFromStream(Stream: TMemoryStream): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNJSONViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNJSONViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNJSONViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeJSONViewer.Create(nil);
end;

function TELNJSONViewerPlugin.GetParams: TPluginParams;
begin
  // '.depo.json' is claimed by Viewer.Deposition and outscores this token,
  // so deposition snapshots never reach here. See unit_ViewerExtMatch.
  Result.Ext     := '.json';
  Result.PType   := ptFile;
  Result.IntOpen := True;
  Result.AcceptsPartialLoad := False;
end;

function TELNJSONViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
var
  Text: string;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    Text := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    TframeJSONViewer(FFrame).DisplayJson(ExtractFileName(AFileName),
      'Cannot read ' + AFileName);
    Exit(True);
  end;

  TframeJSONViewer(FFrame).DisplayJson(ExtractFileName(AFileName), Text);
  Result := True;
end;

function TELNJSONViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeJSONViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNJSONViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
var
  SL: TStringList;
begin
  Result := False;
  if not Assigned(Stream) then
    Exit;

  SL := TStringList.Create;
  try
    Stream.Position := 0;
    SL.LoadFromStream(Stream, TEncoding.UTF8);
    TframeJSONViewer(FFrame).DisplayJson('', SL.Text);
  finally
    SL.Free;
  end;
  Result := True;
end;

end.
