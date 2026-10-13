unit unit_ColumnarDataPlugin;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore,
  unit_LogFile,
  frame_ColumnarDataViewer;

type

  TELNColumnarDataViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IStatefulViewer, IDetailedInfoProvider, IColumnarDataProvider, IReaderIdentity)
  private
    FTable: TLogFile;
    procedure LoadTable(const AFileName: string);
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function GetDetailedInfo: string;
    function SaveState: string;
    procedure RestoreState(const AState: string);
    function GetTotalRows: Integer;
    function GetTimeAxisIndex: Integer;
    function GetTimeSpan(out StartTime, EndTime: string): Boolean;
    function GetSchema: TArray<TColumnSchema>;
    function ResolveColumnName(const Name: string;
      out Indices: TArray<Integer>): Boolean;
    function GetData(const Req: TColumnarRequest): TArray<TArray<TColumnPoint>>;
    function GetStats(const Cols: TArray<Integer>): TArray<TColumnStats>;
    function GetReaderId: string;
    function GetReaderVersion: string;
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

function TELNColumnarDataViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.columnar-data';
end;

function TELNColumnarDataViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

constructor TELNColumnarDataViewerPlugin.Create(AOwner: TComponent);
begin
  inherited;
  FTable := TLogFile.Create;
end;

destructor TELNColumnarDataViewerPlugin.Destroy;
begin
  FTable.Free;
  inherited;
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

procedure TELNColumnarDataViewerPlugin.LoadTable(const AFileName: string);
var
  Frame: TframeColumnarDataViewer;
  Names: TArray<string>;
  Columns: TArray<TLogColumn>;
  I: Integer;
begin
  Frame := TframeColumnarDataViewer(FFrame);
  if Frame.IsTabular then
    Names := Frame.TableNames;
  SetLength(Columns, Length(Names));
  for I := 0 to High(Names) do
    Columns[I].Name := Names[I];
  // The chart parses cells with the active locale; columnar data must agree.
  FTable.LoadTable(AFileName, Columns, Frame.TableRows, FormatSettings);
end;

function TELNColumnarDataViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
  FTable.LoadTable(AFileName, nil, nil, FormatSettings);
  if not FileExists(AFileName) then
    Exit;

  try
    TframeColumnarDataViewer(FFrame).LoadFromFile(AFileName);
    LoadTable(AFileName);
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

function TELNColumnarDataViewerPlugin.GetTotalRows: Integer;
begin
  Result := FTable.GetTotalRows;
end;

function TELNColumnarDataViewerPlugin.GetTimeAxisIndex: Integer;
begin
  Result := FTable.GetTimeAxisIndex;
end;

function TELNColumnarDataViewerPlugin.GetTimeSpan(out StartTime, EndTime: string): Boolean;
begin
  Result := FTable.GetTimeSpan(StartTime, EndTime);
end;

function TELNColumnarDataViewerPlugin.GetSchema: TArray<TColumnSchema>;
begin
  Result := FTable.GetSchema;
end;

function TELNColumnarDataViewerPlugin.ResolveColumnName(const Name: string;
  out Indices: TArray<Integer>): Boolean;
begin
  Result := FTable.ResolveColumnName(Name, Indices);
end;

function TELNColumnarDataViewerPlugin.GetData(
  const Req: TColumnarRequest): TArray<TArray<TColumnPoint>>;
begin
  Result := FTable.GetData(Req);
end;

function TELNColumnarDataViewerPlugin.GetStats(
  const Cols: TArray<Integer>): TArray<TColumnStats>;
begin
  Result := FTable.GetStats(Cols);
end;

end.
