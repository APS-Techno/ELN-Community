unit unit_VK4Plugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_VK4Viewer;

type

  TELNVK4ViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
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
  APlugin: TELNVK4ViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNVK4ViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNVK4ViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.vk4';
end;

function TELNVK4ViewerPlugin.GetReaderVersion: string;
begin
  Result := '2';
end;

function TELNVK4ViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeVK4Viewer.Create(nil);
end;

function TELNVK4ViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.vk4';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNVK4ViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    TframeVK4Viewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      TframeVK4Viewer(FFrame).ShowError(E.Message);
  end;
end;

function TELNVK4ViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeVK4Viewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNVK4ViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeVK4Viewer(FFrame).GetKeyValues;
end;

function TELNVK4ViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeVK4Viewer(FFrame).GetDetailedInfo;
end;

function TELNVK4ViewerPlugin.SaveState: string;
begin
  Result := TframeVK4Viewer(FFrame).SaveState;
end;

procedure TELNVK4ViewerPlugin.RestoreState(const AState: string);
begin
  TframeVK4Viewer(FFrame).RestoreState(AState);
end;

end.
