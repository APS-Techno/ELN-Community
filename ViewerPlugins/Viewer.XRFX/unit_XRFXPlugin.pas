unit unit_XRFXPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_XRFXViewer;

type

  TELNXRFXViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IKeyValueProvider, IDetailedInfoProvider, IStatefulViewer, IReaderIdentity)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
    function SaveState: string;
    procedure RestoreState(const AState: string);
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNXRFXViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNXRFXViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNXRFXViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.xrfx';
end;

function TELNXRFXViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TELNXRFXViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeXRFXViewer.Create(nil);
end;

function TELNXRFXViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.xrfx';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNXRFXViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    TframeXRFXViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

function TELNXRFXViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeXRFXViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNXRFXViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeXRFXViewer(FFrame).GetKeyValues;
end;

function TELNXRFXViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeXRFXViewer(FFrame).GetDetailedInfo;
end;

function TELNXRFXViewerPlugin.SaveState: string;
begin
  Result := SaveChartState(TframeXRFXViewer(FFrame).chrtCurves);
end;

procedure TELNXRFXViewerPlugin.RestoreState(const AState: string);
begin
  RestoreChartState(TframeXRFXViewer(FFrame).chrtCurves, AState);
end;

end.
