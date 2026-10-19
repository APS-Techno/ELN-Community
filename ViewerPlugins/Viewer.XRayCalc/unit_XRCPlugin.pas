unit unit_XRCPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_XRCViewer;

type

  TXRCViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
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
  APlugin: TXRCViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TXRCViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TXRCViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.xrcx';
end;

function TXRCViewerPlugin.GetReaderVersion: string;
begin
  Result := '2';
end;

function TXRCViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeXRCViewer.Create(nil);
end;

function TXRCViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.xrcx';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TXRCViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  TframeXRCViewer(FFrame).LoadCurves(AFileName);
  Result := True;
end;

function TXRCViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeXRCViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TXRCViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeXRCViewer(FFrame).GetKeyValues;
end;

function TXRCViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeXRCViewer(FFrame).GetDetailedInfo;
end;

function TXRCViewerPlugin.SaveState: string;
begin
  Result := SaveChartState(TframeXRCViewer(FFrame).Chart);
end;

procedure TXRCViewerPlugin.RestoreState(const AState: string);
begin
  RestoreChartState(TframeXRCViewer(FFrame).Chart, AState);
end;

end.
