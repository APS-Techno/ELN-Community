unit unit_DM3Plugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_DM3Viewer;

type

  TELNDM3ViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IKeyValueProvider, IDetailedInfoProvider, IReaderIdentity)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

  procedure Register;
  procedure UnRegister;

implementation

var
  APlugin: TELNDM3ViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNDM3ViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNDM3ViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.dm3';
end;

function TELNDM3ViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TELNDM3ViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeDM3Viewer.Create(nil);
end;

function TELNDM3ViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.dm3';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNDM3ViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;
  TframeDM3Viewer(FFrame).LoadFromFile(AFileName);
  Result := True;
end;

function TELNDM3ViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeDM3Viewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNDM3ViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeDM3Viewer(FFrame).GetKeyValues;
end;

function TELNDM3ViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeDM3Viewer(FFrame).GetDetailedInfo;
end;

end.
