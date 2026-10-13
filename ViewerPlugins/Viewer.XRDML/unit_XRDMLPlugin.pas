unit unit_XRDMLPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_XRDMLViewer;

type

  TELNXRDMLViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
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
  APlugin: TELNXRDMLViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNXRDMLViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNXRDMLViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.xrdml';
end;

function TELNXRDMLViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TELNXRDMLViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeXRDMLViewer.Create(nil);
end;

function TELNXRDMLViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.xrdml';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNXRDMLViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    TframeXRDMLViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

function TELNXRDMLViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeXRDMLViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNXRDMLViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeXRDMLViewer(FFrame).GetKeyValues;
end;

function TELNXRDMLViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeXRDMLViewer(FFrame).GetDetailedInfo;
end;

function TELNXRDMLViewerPlugin.SaveState: string;
begin
  Result := SaveChartState(TframeXRDMLViewer(FFrame).Chart);
end;

procedure TELNXRDMLViewerPlugin.RestoreState(const AState: string);
begin
  RestoreChartState(TframeXRDMLViewer(FFrame).Chart, AState);
end;

end.
