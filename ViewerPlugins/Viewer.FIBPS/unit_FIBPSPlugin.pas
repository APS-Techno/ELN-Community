unit unit_FIBPSPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_FIBPSViewer, unit_FIBPSAnalysis;

type

  TELNFIBPSViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
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
  APlugin: TELNFIBPSViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNFIBPSViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNFIBPSViewerPlugin.GetReaderId: string;
begin
  Result := FIBPSReaderId;
end;

function TELNFIBPSViewerPlugin.GetReaderVersion: string;
begin
  Result := FIBPSReaderVersion;
end;

function TELNFIBPSViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeFIBPSViewer.Create(nil);
end;

function TELNFIBPSViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.fibps';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNFIBPSViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  FLoadError := '';
  if not FileExists(AFileName) then
  begin
    FLoadError := 'File not found: ' + AFileName;
    Exit;
  end;

  try
    TframeFIBPSViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
    begin
      FLoadError := E.Message;
      TframeFIBPSViewer(FFrame).ShowError(E.Message);
    end;
  end;
end;

function TELNFIBPSViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeFIBPSViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNFIBPSViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeFIBPSViewer(FFrame).GetKeyValues;
end;

procedure TELNFIBPSViewerPlugin.SetAnalysisContext(const Context: TAnalysisContext);
begin
  TframeFIBPSViewer(FFrame).SetAnalysisContext(Context);
end;

function TELNFIBPSViewerPlugin.GetAnalysisSnapshot(const KeyName: string): string;
begin
  Result := TframeFIBPSViewer(FFrame).GetAnalysisSnapshot(KeyName);
end;

function TELNFIBPSViewerPlugin.GetAnalysisStatus: string;
begin
  Result := TframeFIBPSViewer(FFrame).GetAnalysisStatus;
end;

function TELNFIBPSViewerPlugin.GetLoadError: string;
begin
  Result := FLoadError;
end;

function TELNFIBPSViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeFIBPSViewer(FFrame).GetDetailedInfo;
end;

function TELNFIBPSViewerPlugin.SaveState: string;
begin
  Result := TframeFIBPSViewer(FFrame).SaveState;
end;

procedure TELNFIBPSViewerPlugin.RestoreState(const AState: string);
begin
  TframeFIBPSViewer(FFrame).RestoreState(AState);
end;

end.
