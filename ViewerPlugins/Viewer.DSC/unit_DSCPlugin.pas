unit unit_DSCPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ELNThemeHelper,
  frame_DSCViewer;

type

  TELNDSCViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IKeyValueProvider, IDetailedInfoProvider, IReaderIdentity)
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    function LoadFromFile(const AFileName: string): Boolean; override;
    function LoadFromStream(Stream: TMemoryStream): Boolean; override;
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
  APlugin: TELNDSCViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNDSCViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNDSCViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.dsc';
end;

function TELNDSCViewerPlugin.GetReaderVersion: string;
begin
  Result := '2';
end;

function TELNDSCViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeDSCViewer.Create(nil);
end;

function TELNDSCViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.dsc';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNDSCViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;

  TframeDSCViewer(FFrame).lblTitle.Caption := ExtractFileName(AFileName);
  TframeDSCViewer(FFrame).Editor.Lines.LoadFromFile(AFileName);

  if ThemePluginsEnabled then
  begin
    TframeDSCViewer(FFrame).Editor.Color := ThemePanelColor;
    TframeDSCViewer(FFrame).Editor.Font.Color := ThemeTextColor;
    TframeDSCViewer(FFrame).Editor.Gutter.Color := ThemePanelColor;
    TframeDSCViewer(FFrame).Editor.Gutter.Font.Color := ThemeTextColor;
  end;

  Result := True;
end;

function TELNDSCViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
begin
  Result := False;
  if not Assigned(Stream) then
    Exit;

  TframeDSCViewer(FFrame).Editor.Lines.LoadFromStream(Stream);
  Result := True;
end;

function TELNDSCViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := TframeDSCViewer(FFrame).GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNDSCViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  Result := TframeDSCViewer(FFrame).GetKeyValues;
end;

function TELNDSCViewerPlugin.GetDetailedInfo: string;
begin
  Result := TframeDSCViewer(FFrame).GetDetailedInfo;
end;

end.
