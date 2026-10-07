unit unit_NotebookSettings;

interface

uses
  System.SysUtils, System.IOUtils, System.Classes, System.IniFiles,
  System.Win.Registry, Winapi.Windows;

type
  TPreviewScope = (psCurrentItem, psItemAndChildren, psEntireProc, psSiblingFiles);

  ISettingsWorker = interface
    ['{D7E3F1A2-4B8C-4D6E-9F0A-1C2D3E4F5A6B}']
    procedure WriteValue(const Name: string; Val: Integer); overload;
    procedure WriteValue(const Name: string; Val: string); overload;
    function ReadValue(const Name: string; Default: Integer): Integer; overload;
    function ReadValue(const Name: string; Default: string): string; overload;
    procedure UpdateValue(const Name: string; Val: string);
  end;

  TRegWorker = class(TInterfacedObject, ISettingsWorker)
  private
    FRegistry: TRegistry;
  public
    constructor Create(const RegistryKey: string);
    destructor Destroy; override;
    procedure WriteValue(const Name: string; Val: Integer); overload;
    procedure WriteValue(const Name: string; Val: string); overload;
    function ReadValue(const Name: string; Default: Integer): Integer; overload;
    function ReadValue(const Name: string; Default: string): string; overload;
    procedure UpdateValue(const Name: string; Val: string);
  end;

  TIniWorker = class(TInterfacedObject, ISettingsWorker)
  private
    FIni: TIniFile;
    FSection: string;
  public
    constructor Create(const FileName: string; const Section: string = 'Settings');
    destructor Destroy; override;
    procedure WriteValue(const Name: string; Val: Integer); overload;
    procedure WriteValue(const Name: string; Val: string); overload;
    function ReadValue(const Name: string; Default: Integer): Integer; overload;
    function ReadValue(const Name: string; Default: string): string; overload;
    procedure UpdateValue(const Name: string; Val: string);
  end;

  TNotebookSettings = class
  private
    class var FGlobalConfigFile: string;
    class var FRegistryKey: string;
    class var FDefaultStorageRoot: string;
    function GetStorageRoot: string;
    procedure SetStorageRoot(const Value: string);
    function GetVCLTheme: string;
    procedure SetVCLTheme(const Value: string);
    function GetTemplatesDir: string;
    procedure SetTemplatesDir(const Value: string);
    function GetPluginsDir: string;
    procedure SetPluginsDir(const Value: string);
    function GetShowDashboard: Boolean;
    procedure SetShowDashboard(const Value: Boolean);
    function GetDashboardScale: Integer;
    procedure SetDashboardScale(const Value: Integer);
    function GetDarkCharts: Boolean;
    procedure SetDarkCharts(const Value: Boolean);
    function GetReportLogoPath: string;
    procedure SetReportLogoPath(const Value: string);
    function GetShowItemIDs: Boolean;
    procedure SetShowItemIDs(const Value: Boolean);
    function GetTreeScale: Integer;
    procedure SetTreeScale(const Value: Integer);
    function GetTreeSpacing: Integer;
    procedure SetTreeSpacing(const Value: Integer);
    function GetTreeTint: Integer;
    procedure SetTreeTint(const Value: Integer);
    function GetTreeColors: string;
    procedure SetTreeColors(const Value: string);
    function GetGoToItemHistory: string;
    procedure SetGoToItemHistory(const Value: string);
    function GetPreviewScope: TPreviewScope;
    procedure SetPreviewScope(const Value: TPreviewScope);
  protected
    FWorker: ISettingsWorker;
  public
    class procedure SetConfigFile(const Path: string);
    class procedure SetDefaults(const RegistryKey, StorageRoot: string);
    constructor Create; overload;
    constructor Create(const IniFilePath: string); overload;
    destructor Destroy; override;
    property StorageRoot: string read GetStorageRoot write SetStorageRoot;
    property VCLTheme: string read GetVCLTheme write SetVCLTheme;
    property TemplatesDir: string read GetTemplatesDir write SetTemplatesDir;
    property PluginsDir: string read GetPluginsDir write SetPluginsDir;
    property ShowDashboard: Boolean read GetShowDashboard write SetShowDashboard;
    property DashboardScale: Integer read GetDashboardScale write SetDashboardScale;
    property DarkCharts: Boolean read GetDarkCharts write SetDarkCharts;
    property ReportLogoPath: string read GetReportLogoPath write SetReportLogoPath;
    property ShowItemIDs: Boolean read GetShowItemIDs write SetShowItemIDs;
    property TreeScale: Integer read GetTreeScale write SetTreeScale;
    property TreeSpacing: Integer read GetTreeSpacing write SetTreeSpacing;
    property TreeTint: Integer read GetTreeTint write SetTreeTint;
    property TreeColors: string read GetTreeColors write SetTreeColors;
    property GoToItemHistory: string read GetGoToItemHistory write SetGoToItemHistory;
    property PreviewScope: TPreviewScope read GetPreviewScope write SetPreviewScope;
    procedure SaveUIValue(const Section, Key: string; Value: Integer);
    function LoadUIValue(const Section, Key: string; Default: Integer): Integer;
    procedure SaveUIString(const Section, Key, Value: string);
    function LoadUIString(const Section, Key, Default: string): string;
  end;

const
  PreviewScopeNames: array[TPreviewScope] of string = (
    'Current item', 'Item and children', 'Entire procedure', 'Sibling files only');

implementation

constructor TRegWorker.Create(const RegistryKey: string);
begin
  inherited Create;
  FRegistry := TRegistry.Create;
  FRegistry.RootKey := HKEY_CURRENT_USER;
  if not FRegistry.OpenKey(RegistryKey, True) then
    raise EInOutError.Create('Could not open notebook preferences');
end;

destructor TRegWorker.Destroy;
begin
  FreeAndNil(FRegistry);
  inherited Destroy;
end;

function TRegWorker.ReadValue(const Name: string; Default: string): string;
begin
  if FRegistry.ValueExists(Name) then
    Result := FRegistry.ReadString(Name)
  else
    Result := Default;
end;

function TRegWorker.ReadValue(const Name: string; Default: Integer): Integer;
begin
  if FRegistry.ValueExists(Name) then
    Result := FRegistry.ReadInteger(Name)
  else
    Result := Default;
end;

procedure TRegWorker.WriteValue(const Name: string; Val: Integer);
begin
  FRegistry.WriteInteger(Name, Val);
end;

procedure TRegWorker.WriteValue(const Name: string; Val: string);
begin
  FRegistry.WriteString(Name, Val);
end;

procedure TRegWorker.UpdateValue(const Name: string; Val: string);
begin
  if not FRegistry.ValueExists(Name) then
    FRegistry.WriteString(Name, Val)
  else if FRegistry.ReadString(Name) <> Val then
    FRegistry.WriteString(Name, Val);
end;

constructor TIniWorker.Create(const FileName, Section: string);
var
  Directory: string;
begin
  inherited Create;
  Directory := ExtractFileDir(FileName);
  if (Directory <> '') and not ForceDirectories(Directory) then
    raise EInOutError.Create('Could not create notebook preferences directory');
  FIni := TIniFile.Create(FileName);
  FSection := Section;
end;

destructor TIniWorker.Destroy;
begin
  FreeAndNil(FIni);
  inherited Destroy;
end;

procedure TIniWorker.WriteValue(const Name: string; Val: Integer);
begin
  FIni.WriteInteger(FSection, Name, Val);
end;

procedure TIniWorker.WriteValue(const Name: string; Val: string);
begin
  FIni.WriteString(FSection, Name, Val);
end;

function TIniWorker.ReadValue(const Name: string; Default: Integer): Integer;
begin
  Result := FIni.ReadInteger(FSection, Name, Default);
end;

function TIniWorker.ReadValue(const Name: string; Default: string): string;
begin
  Result := FIni.ReadString(FSection, Name, Default);
end;

procedure TIniWorker.UpdateValue(const Name: string; Val: string);
begin
  if FIni.ReadString(FSection, Name, '') <> Val then
    FIni.WriteString(FSection, Name, Val);
end;

class procedure TNotebookSettings.SetConfigFile(const Path: string);
begin
  FGlobalConfigFile := Path;
end;

class procedure TNotebookSettings.SetDefaults(const RegistryKey, StorageRoot: string);
begin
  FRegistryKey := RegistryKey;
  FDefaultStorageRoot := StorageRoot;
end;

constructor TNotebookSettings.Create;
begin
  inherited Create;
  if FGlobalConfigFile <> '' then
    FWorker := TIniWorker.Create(FGlobalConfigFile)
  else
    FWorker := TRegWorker.Create(FRegistryKey);
end;

constructor TNotebookSettings.Create(const IniFilePath: string);
begin
  inherited Create;
  FWorker := TIniWorker.Create(IniFilePath);
end;

destructor TNotebookSettings.Destroy;
begin
  FWorker := nil;
  inherited Destroy;
end;

function TNotebookSettings.GetStorageRoot: string;
begin
  Result := FWorker.ReadValue('StorageRoot', '');
  if Result = '' then
    Result := FDefaultStorageRoot;
end;

procedure TNotebookSettings.SetStorageRoot(const Value: string);
begin
  FWorker.WriteValue('StorageRoot', Value);
end;

function TNotebookSettings.GetVCLTheme: string;
begin
  Result := FWorker.ReadValue('VCLTheme', '');
end;

procedure TNotebookSettings.SetVCLTheme(const Value: string);
begin
  FWorker.UpdateValue('VCLTheme', Value);
end;

function TNotebookSettings.GetTemplatesDir: string;
begin
  Result := FWorker.ReadValue('TemplatesDir', '');
end;

procedure TNotebookSettings.SetTemplatesDir(const Value: string);
begin
  FWorker.UpdateValue('TemplatesDir', Value);
end;

function TNotebookSettings.GetPluginsDir: string;
begin
  Result := FWorker.ReadValue('PluginsDir', '');
end;

procedure TNotebookSettings.SetPluginsDir(const Value: string);
begin
  FWorker.UpdateValue('PluginsDir', Value);
end;

function TNotebookSettings.GetShowDashboard: Boolean;
begin
  Result := FWorker.ReadValue('ShowDashboard', 0) <> 0;
end;

procedure TNotebookSettings.SetShowDashboard(const Value: Boolean);
begin
  FWorker.WriteValue('ShowDashboard', Ord(Value));
end;

function TNotebookSettings.GetDashboardScale: Integer;
begin
  Result := FWorker.ReadValue('DashboardScale', 100);
end;

procedure TNotebookSettings.SetDashboardScale(const Value: Integer);
begin
  FWorker.WriteValue('DashboardScale', Value);
end;

function TNotebookSettings.GetDarkCharts: Boolean;
begin
  Result := FWorker.ReadValue('DarkCharts', 0) = 1;
end;

procedure TNotebookSettings.SetDarkCharts(const Value: Boolean);
begin
  FWorker.WriteValue('DarkCharts', Ord(Value));
end;

function TNotebookSettings.GetReportLogoPath: string;
begin
  Result := FWorker.ReadValue('ReportLogoPath', '');
end;

procedure TNotebookSettings.SetReportLogoPath(const Value: string);
begin
  FWorker.WriteValue('ReportLogoPath', Value);
end;

function TNotebookSettings.GetShowItemIDs: Boolean;
begin
  Result := FWorker.ReadValue('ShowItemIDs', 0) <> 0;
end;

procedure TNotebookSettings.SetShowItemIDs(const Value: Boolean);
begin
  FWorker.WriteValue('ShowItemIDs', Ord(Value));
end;

function TNotebookSettings.GetTreeScale: Integer;
begin
  Result := FWorker.ReadValue('TreeScale', 100);
end;

procedure TNotebookSettings.SetTreeScale(const Value: Integer);
begin
  FWorker.WriteValue('TreeScale', Value);
end;

function TNotebookSettings.GetTreeSpacing: Integer;
begin
  Result := FWorker.ReadValue('TreeSpacing', 1);
end;

procedure TNotebookSettings.SetTreeSpacing(const Value: Integer);
begin
  FWorker.WriteValue('TreeSpacing', Value);
end;

function TNotebookSettings.GetTreeTint: Integer;
begin
  Result := FWorker.ReadValue('TreeTint', 2);
end;

procedure TNotebookSettings.SetTreeTint(const Value: Integer);
begin
  FWorker.WriteValue('TreeTint', Value);
end;

function TNotebookSettings.GetTreeColors: string;
begin
  Result := FWorker.ReadValue('TreeColors', '');
end;

procedure TNotebookSettings.SetTreeColors(const Value: string);
begin
  FWorker.WriteValue('TreeColors', Value);
end;

function TNotebookSettings.GetGoToItemHistory: string;
begin
  Result := FWorker.ReadValue('GoToItemHistory', '');
end;

procedure TNotebookSettings.SetGoToItemHistory(const Value: string);
begin
  FWorker.UpdateValue('GoToItemHistory', Value);
end;

function TNotebookSettings.GetPreviewScope: TPreviewScope;
var
  Value: Integer;
begin
  Value := FWorker.ReadValue('PreviewScope', Ord(psCurrentItem));
  if (Value >= Ord(Low(TPreviewScope))) and (Value <= Ord(High(TPreviewScope))) then
    Result := TPreviewScope(Value)
  else
    Result := psCurrentItem;
end;

procedure TNotebookSettings.SetPreviewScope(const Value: TPreviewScope);
begin
  FWorker.WriteValue('PreviewScope', Ord(Value));
end;

procedure TNotebookSettings.SaveUIValue(const Section, Key: string; Value: Integer);
begin
  FWorker.WriteValue(Section + '.' + Key, Value);
end;

function TNotebookSettings.LoadUIValue(const Section, Key: string; Default: Integer): Integer;
begin
  Result := FWorker.ReadValue(Section + '.' + Key, Default);
end;

procedure TNotebookSettings.SaveUIString(const Section, Key, Value: string);
begin
  FWorker.UpdateValue(Section + '.' + Key, Value);
end;

function TNotebookSettings.LoadUIString(const Section, Key, Default: string): string;
begin
  Result := FWorker.ReadValue(Section + '.' + Key, Default);
end;

initialization
  TNotebookSettings.SetDefaults('Software\APS ELN Community\Settings',
    TPath.Combine(TPath.GetDocumentsPath, 'ELNCommunity\'));
end.
