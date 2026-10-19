unit unit_MitFilePlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_MitFileViewer, unit_MitAnalysis;

type

  TELNMitFileViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
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
  APlugin: TELNMitFileViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNMitFileViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNMitFileViewerPlugin.GetReaderId: string;
begin
  Result := MitReaderId;
end;

function TELNMitFileViewerPlugin.GetReaderVersion: string;
begin
  Result := MitReaderVersion;
end;

function TELNMitFileViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeMitFileViewer.Create(nil);
end;

function TELNMitFileViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.mit';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNMitFileViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  FLoadError := '';
  if not FileExists(AFileName) then
  begin
    FLoadError := 'File not found: ' + AFileName;
    Exit;
  end;

  try
    TframeMitFileViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      FLoadError := E.Message;
  end;
end;

function TELNMitFileViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeMitFileViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNMitFileViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeMitFileViewer(FFrame).GetKeyValues;
end;

procedure TELNMitFileViewerPlugin.SetAnalysisContext(const Context: TAnalysisContext);
begin
  TframeMitFileViewer(FFrame).SetAnalysisContext(Context);
end;

function TELNMitFileViewerPlugin.GetAnalysisSnapshot(const KeyName: string): string;
begin
  Result := TframeMitFileViewer(FFrame).GetAnalysisSnapshot(KeyName);
end;

function TELNMitFileViewerPlugin.GetAnalysisStatus: string;
begin
  Result := TframeMitFileViewer(FFrame).GetAnalysisStatus;
end;

function TELNMitFileViewerPlugin.GetLoadError: string;
begin
  Result := FLoadError;
end;

function TELNMitFileViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeMitFileViewer(FFrame).GetDetailedInfo;
end;

function TELNMitFileViewerPlugin.SaveState: string;
begin
  Result := TframeMitFileViewer(FFrame).SaveState;
end;

procedure TELNMitFileViewerPlugin.RestoreState(const AState: string);
begin
  TframeMitFileViewer(FFrame).RestoreState(AState);
end;

end.
