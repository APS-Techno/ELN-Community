unit unit_ProcessLogPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_ProcessLogData, frame_ProcessLogViewer;

type
  TELNProcessLogViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IKeyValueProvider, IDetailedInfoProvider, IReaderIdentity)
  private
    FLog: TProcessLogData;
    FLoaded: Boolean;
    function Viewer: TframeProcessLogViewer;
    procedure Display(Lines: TStrings; const Caption: string);
    function LoadLines(Lines: TStrings; const Caption: string): Boolean;
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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

uses
  System.JSON, unit_ELNThemeHelper;

var
  APlugin: TELNProcessLogViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNProcessLogViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

constructor TELNProcessLogViewerPlugin.Create(AOwner: TComponent);
begin
  inherited;
  FLog := TProcessLogData.Create;
end;

destructor TELNProcessLogViewerPlugin.Destroy;
begin
  FLog.Free;
  inherited;
end;

function TELNProcessLogViewerPlugin.Viewer: TframeProcessLogViewer;
begin
  Result := TframeProcessLogViewer(FFrame);
end;

function TELNProcessLogViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeProcessLogViewer.Create(nil);
end;

function TELNProcessLogViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.process.log';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNProcessLogViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.process-log';
end;

function TELNProcessLogViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

procedure TELNProcessLogViewerPlugin.Display(Lines: TStrings; const Caption: string);
begin
  if not Assigned(FFrame) then
    Exit;
  Viewer.lblTitle.Caption := Caption;
  Viewer.Editor.Lines.Assign(Lines);
  if ThemePluginsEnabled then
  begin
    Viewer.Editor.Color := ThemePanelColor;
    Viewer.Editor.Font.Color := ThemeTextColor;
    Viewer.Editor.Gutter.Color := ThemePanelColor;
    Viewer.Editor.Gutter.Font.Color := ThemeTextColor;
  end;
end;

function TELNProcessLogViewerPlugin.LoadLines(Lines: TStrings;
  const Caption: string): Boolean;
var
  Title: string;
begin
  FLoaded := FLog.LoadFromLines(Lines);
  Title := Caption;
  if FLoaded and (FLog.RecipeName <> '') then
    Title := Format('%s - %s  (%s)', [FLog.RecipeName,
      ProcessOutcomeName(FLog.Outcome), Caption]);
  Display(Lines, Title);
  Result := True;
end;

function TELNProcessLogViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
var
  Lines: TStringList;
begin
  Result := False;
  FLoaded := False;
  if not FileExists(AFileName) then
    Exit;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName);
    except
      Exit;
    end;
    Result := LoadLines(Lines, ExtractFileName(AFileName));
  finally
    Lines.Free;
  end;
end;

function TELNProcessLogViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
var
  Lines: TStringList;
begin
  Result := False;
  FLoaded := False;
  if not Assigned(Stream) then
    Exit;
  Lines := TStringList.Create;
  try
    Stream.Position := 0;
    Lines.LoadFromStream(Stream);
    Result := LoadLines(Lines, '');
  finally
    Lines.Free;
  end;
end;

function TELNProcessLogViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := Viewer.GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNProcessLogViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  if FLoaded then
    Result := FLog.BuildKeyValues
  else
    Result := nil;
end;

function TELNProcessLogViewerPlugin.GetDetailedInfo: string;
var
  J: TJSONObject;
begin
  if not FLoaded then
    Exit('');
  J := FLog.BuildDetailedJson;
  try
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

end.
