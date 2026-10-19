unit unit_ZRWViewerPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_ZRWViewer, unit_ZRWAnalysis;

type

  TELNZRWViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IKeyValueProvider, IAnalysisKeyValueProvider, IDetailedInfoProvider,
    IStatefulViewer, IReaderIdentity)
  private
    FLoadError: string;
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    procedure SetAnalysisContext(const Context: TAnalysisContext);
    function GetAnalysisSnapshot(const KeyName: string): string;
    function GetAnalysisStatus: string;
    function GetLoadError: string;
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
  APlugin: TELNZRWViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNZRWViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNZRWViewerPlugin.GetReaderId: string;
begin
  Result := ZRWReaderId;
end;

function TELNZRWViewerPlugin.GetReaderVersion: string;
begin
  Result := ZRWReaderVersion;
end;

function TELNZRWViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeZRWViewer.Create(nil);
end;

function TELNZRWViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.zrw;.zrv';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNZRWViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  FLoadError := '';
  if not FileExists(AFileName) then
  begin
    FLoadError := 'File not found: ' + AFileName;
    Exit;
  end;

  try
    TframeZRWViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      FLoadError := E.Message;
  end;
end;

function TELNZRWViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeZRWViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNZRWViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeZRWViewer(FFrame).GetKeyValues;
end;

procedure TELNZRWViewerPlugin.SetAnalysisContext(const Context: TAnalysisContext);
begin
  TframeZRWViewer(FFrame).SetAnalysisContext(Context);
end;

function TELNZRWViewerPlugin.GetAnalysisSnapshot(const KeyName: string): string;
begin
  Result := TframeZRWViewer(FFrame).GetAnalysisSnapshot(KeyName);
end;

function TELNZRWViewerPlugin.GetAnalysisStatus: string;
begin
  Result := TframeZRWViewer(FFrame).GetAnalysisStatus;
end;

function TELNZRWViewerPlugin.GetLoadError: string;
begin
  Result := FLoadError;
end;

function TELNZRWViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeZRWViewer(FFrame).GetDetailedInfo;
end;

function TELNZRWViewerPlugin.SaveState: string;
begin
  Result := SaveChartState(TframeZRWViewer(FFrame).Chart);
end;

procedure TELNZRWViewerPlugin.RestoreState(const AState: string);
begin
  RestoreChartState(TframeZRWViewer(FFrame).Chart, AState);
end;

end.
