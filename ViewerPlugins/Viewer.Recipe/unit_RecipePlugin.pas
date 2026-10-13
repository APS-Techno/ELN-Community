unit unit_RecipePlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes,
  unit_RecipeData, frame_RecipeViewer;

type
  TELNRecipeViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IKeyValueProvider, IDetailedInfoProvider, IReaderIdentity)
  private
    FRecipe: TRecipeData;
    FLoaded: Boolean;
    function Viewer: TframeRecipeViewer;
    procedure Display(const Text, Caption: string);
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
  System.IOUtils, System.JSON, unit_ELNThemeHelper;

var
  APlugin: TELNRecipeViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNRecipeViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

constructor TELNRecipeViewerPlugin.Create(AOwner: TComponent);
begin
  inherited;
  FRecipe := TRecipeData.Create;
end;

destructor TELNRecipeViewerPlugin.Destroy;
begin
  FRecipe.Free;
  inherited;
end;

function TELNRecipeViewerPlugin.Viewer: TframeRecipeViewer;
begin
  Result := TframeRecipeViewer(FFrame);
end;

function TELNRecipeViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeRecipeViewer.Create(nil);
end;

function TELNRecipeViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.rcpx';
  Result.PType   := ptFile;
  Result.IntOpen := False;
end;

function TELNRecipeViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.recipe';
end;

function TELNRecipeViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

procedure TELNRecipeViewerPlugin.Display(const Text, Caption: string);
begin
  if not Assigned(FFrame) then
    Exit;
  Viewer.lblTitle.Caption := Caption;
  Viewer.Editor.Lines.Text := Text;
  if ThemePluginsEnabled then
  begin
    Viewer.Editor.Color := ThemePanelColor;
    Viewer.Editor.Font.Color := ThemeTextColor;
    Viewer.Editor.Gutter.Color := ThemePanelColor;
    Viewer.Editor.Gutter.Font.Color := ThemeTextColor;
  end;
end;

function TELNRecipeViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
var
  Text, Caption: string;
begin
  Result := False;
  FLoaded := False;
  if not FileExists(AFileName) then
    Exit;
  try
    Text := TFile.ReadAllText(AFileName);
  except
    Exit;
  end;
  FLoaded := FRecipe.LoadFromText(Text);
  Caption := ExtractFileName(AFileName);
  if FLoaded and (FRecipe.Title <> '') then
    Caption := FRecipe.Title + '  (' + Caption + ')';
  Display(Text, Caption);
  Result := True;
end;

function TELNRecipeViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
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
    FLoaded := FRecipe.LoadFromText(Lines.Text);
    Display(Lines.Text, FRecipe.Title);
  finally
    Lines.Free;
  end;
  Result := True;
end;

function TELNRecipeViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := Viewer.GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNRecipeViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  if FLoaded then
    Result := FRecipe.BuildKeyValues
  else
    Result := nil;
end;

function TELNRecipeViewerPlugin.GetDetailedInfo: string;
var
  J: TJSONObject;
begin
  if not FLoaded then
    Exit('');
  J := FRecipe.BuildDetailedJson;
  try
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

end.
