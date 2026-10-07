unit unit_ColumnarDataPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore,
  frame_ColumnarDataViewer;

type

  TELNColumnarDataViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IStatefulViewer, IDetailedInfoProvider)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function GetDetailedInfo: string;
    function SaveState: string;
    procedure RestoreState(const AState: string);
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNColumnarDataViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNColumnarDataViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNColumnarDataViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeColumnarDataViewer.Create(nil);
end;

function TELNColumnarDataViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.dat;.csv;.txt;.ascii';
  Result.PType   := ptFile;
  Result.IntOpen := False;
  Result.AcceptsPartialLoad := True;
end;

function TELNColumnarDataViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    TframeColumnarDataViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

function TELNColumnarDataViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeColumnarDataViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNColumnarDataViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeColumnarDataViewer(FFrame).GetDetailedInfo;
end;

function TELNColumnarDataViewerPlugin.SaveState: string;
begin
  Result := SaveChartState(TframeColumnarDataViewer(FFrame).Chart);
end;

procedure TELNColumnarDataViewerPlugin.RestoreState(const AState: string);
begin
  RestoreChartState(TframeColumnarDataViewer(FFrame).Chart, AState);
end;

end.
