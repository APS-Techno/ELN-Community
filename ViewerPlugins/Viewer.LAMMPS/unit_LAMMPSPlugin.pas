unit unit_LAMMPSPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  frame_LAMMPSViewer;

type

  TELNLAMMPSViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
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
  APlugin: TELNLAMMPSViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNLAMMPSViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNLAMMPSViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.lammps';
end;

function TELNLAMMPSViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

function TELNLAMMPSViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeLAMMPSViewer.Create(nil);
end;

function TELNLAMMPSViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.lmpin;.dump;.data;.lammps';
  Result.PType   := ptFile;
  Result.IntOpen := False;
  Result.AcceptsPartialLoad := True;
end;

function TELNLAMMPSViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  try
    TframeLAMMPSViewer(FFrame).LoadFromFile(AFileName);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

function TELNLAMMPSViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeLAMMPSViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNLAMMPSViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeLAMMPSViewer(FFrame).GetKeyValues;
end;

function TELNLAMMPSViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeLAMMPSViewer(FFrame).GetDetailedInfo;
end;

function TELNLAMMPSViewerPlugin.SaveState: string;
begin
  Result := TframeLAMMPSViewer(FFrame).SaveState;
end;

procedure TELNLAMMPSViewerPlugin.RestoreState(const AState: string);
begin
  TframeLAMMPSViewer(FFrame).RestoreState(AState);
end;

end.
