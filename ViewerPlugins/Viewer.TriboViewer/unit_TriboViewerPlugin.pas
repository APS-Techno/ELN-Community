unit unit_TriboViewerPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_TriboViewer;

type

  TELNTriboViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
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
  APlugin: TELNTriboViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNTriboViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNTriboViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.tribo';
end;

function TELNTriboViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TELNTriboViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeTriboViewer.Create(nil);
end;

function TELNTriboViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.raw';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNTriboViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    TframeTriboViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

function TELNTriboViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeTriboViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNTriboViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeTriboViewer(FFrame).GetKeyValues;
end;

function TELNTriboViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeTriboViewer(FFrame).GetDetailedInfo;
end;

function TELNTriboViewerPlugin.SaveState: string;
begin
  Result := SaveChartState(TframeTriboViewer(FFrame).Chart);
end;

procedure TELNTriboViewerPlugin.RestoreState(const AState: string);
begin
  RestoreChartState(TframeTriboViewer(FFrame).Chart, AState);
end;

end.
