unit unit_DepositionPlugin;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, Vcl.Forms, Vcl.Graphics,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_DepoPairing, unit_LogFile,
  unit_DepositionData, frame_DepositionViewer;

type
  TELNDepositionViewerPlugin = class(TELNBaseViewerPlugin, IPreviewProvider,
    IStatefulViewer, IItemContextAware, IColumnarDataProvider,
    IKeyValueProvider, IDetailedInfoProvider, IReaderIdentity)
  private
    FLogFile: TLogFile;
    FSnapshot: TDepoSnapshot;
    FHasLog, FHasSnapshot: Boolean;
    FItemId: Integer;
    FFileId: Int64;
    function Viewer: TframeDepositionViewer;
    function CandidateNames(const Dir: string): TArray<string>;
    procedure EnsureSiblingsOnDisk(const Dir: string);
    function LoadTsvFile(const Path: string): Boolean;
    procedure FindPartnerJson(const TsvPath: string);
    procedure FindPartnerTsv(const JsonPath, JsonText: string);
    function SnapshotOrNil: TDepoSnapshot;
    function LogOrNil: TLogFile;
  protected
    function CreateViewerFrame: TFrame; override;
    function GetParams: TPluginParams; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function LoadFromFile(const AFileName: string): Boolean; override;
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
    function SaveState: string;
    procedure RestoreState(const AState: string);
    procedure SetItemContext(ItemId: Integer; FileId: Int64);
    function GetTotalRows: Integer;
    function GetTimeAxisIndex: Integer;
    function GetTimeSpan(out StartTime, EndTime: string): Boolean;
    function GetSchema: TArray<TColumnSchema>;
    function ResolveColumnName(const Name: string;
      out Indices: TArray<Integer>): Boolean;
    function GetData(const Req: TColumnarRequest): TArray<TArray<TColumnPoint>>;
    function GetStats(const Cols: TArray<Integer>): TArray<TColumnStats>;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

procedure Register;
procedure UnRegister;

implementation

uses
  System.JSON;

var
  APlugin: TELNDepositionViewerPlugin;

{$R *.DFM}

procedure Register;
begin
  APlugin := TELNDepositionViewerPlugin.Create(nil);
  RegisterViewerPlugin(APlugin);
end;

procedure UnRegister;
begin
  APlugin.Free;
end;

function TELNDepositionViewerPlugin.GetReaderId: string;
begin
  Result := 'aps.deposition';
end;

function TELNDepositionViewerPlugin.GetReaderVersion: string;
begin
  Result := '1';
end;

constructor TELNDepositionViewerPlugin.Create(AOwner: TComponent);
begin
  inherited;
  FLogFile := TLogFile.Create;
  FSnapshot := TDepoSnapshot.Create;
end;

destructor TELNDepositionViewerPlugin.Destroy;
begin
  FSnapshot.Free;
  FLogFile.Free;
  inherited;
end;

function TELNDepositionViewerPlugin.Viewer: TframeDepositionViewer;
begin
  Result := TframeDepositionViewer(FFrame);
end;

function TELNDepositionViewerPlugin.CreateViewerFrame: TFrame;
begin
  Result := TframeDepositionViewer.Create(nil);
end;

function TELNDepositionViewerPlugin.GetParams: TPluginParams;
begin
  Result.Ext     := '.tsv;.depo.json';
  Result.PType   := ptFile;
  Result.IntOpen := True;
  Result.AcceptsPartialLoad := False;
end;

procedure TELNDepositionViewerPlugin.SetItemContext(ItemId: Integer; FileId: Int64);
begin
  FItemId := ItemId;
  FFileId := FileId;
end;

// Attachment names for the current item ("[ID]name.ext"), or - when there is
// no item context (PluginTestApp, unknown item) - names in the local folder.
function TELNDepositionViewerPlugin.CandidateNames(const Dir: string): TArray<string>;
var
  Paths: TArray<string>;
  I: Integer;
begin
  if (FItemId > 0) and Assigned(ElnFileEnumerator) then
    Exit(ElnFileEnumerator.GetItemFiles(FItemId));
  Paths := TDirectory.GetFiles(Dir);
  SetLength(Result, Length(Paths));
  for I := 0 to High(Paths) do
    Result[I] := ExtractFileName(Paths[I]);
end;

procedure TELNDepositionViewerPlugin.EnsureSiblingsOnDisk(const Dir: string);
begin
  if (FItemId > 0) and Assigned(ElnFileEnumerator) then
    ElnFileEnumerator.EnsureItemFilesInDir(FItemId, Dir);
end;

function TELNDepositionViewerPlugin.LoadTsvFile(const Path: string): Boolean;
begin
  Result := FLogFile.LoadFromFile(Path);
  if Result then
    FLogFile.ClampDenormals;
end;

procedure TELNDepositionViewerPlugin.FindPartnerJson(const TsvPath: string);
var
  Dir, TsvName, Text: string;
  N: string;
  JsonNames: TArray<string>;
begin
  Dir := ExtractFilePath(TsvPath);
  TsvName := ExtractFileName(TsvPath);

  JsonNames := nil;
  for N in CandidateNames(Dir) do
    if IsDepoJsonName(N) then
      JsonNames := JsonNames + [N];
  if Length(JsonNames) = 0 then Exit;

  EnsureSiblingsOnDisk(Dir);
  for N in JsonNames do
  begin
    if not FileExists(TPath.Combine(Dir, N)) then Continue;
    try
      Text := TFile.ReadAllText(TPath.Combine(Dir, N), TEncoding.UTF8);
    except
      Continue;
    end;
    if IsJsonForTsv(Text, N, TsvName) and FSnapshot.LoadFromText(Text) then
    begin
      FHasSnapshot := True;
      Exit;
    end;
  end;
end;

procedure TELNDepositionViewerPlugin.FindPartnerTsv(const JsonPath, JsonText: string);
var
  Dir, Partner, PartnerPath: string;
begin
  Dir := ExtractFilePath(JsonPath);
  Partner := FindPairedTsv(JsonText, ExtractFileName(JsonPath),
    CandidateNames(Dir));
  if Partner = '' then Exit;

  EnsureSiblingsOnDisk(Dir);
  PartnerPath := TPath.Combine(Dir, ExtractFileName(Partner));
  if FileExists(PartnerPath) then
    FHasLog := LoadTsvFile(PartnerPath);
end;

function TELNDepositionViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
var
  Ext, Text, Pretty: string;
  JVal: System.JSON.TJSONValue;
begin
  FHasLog := False;
  FHasSnapshot := False;
  Ext := LowerCase(ExtractFileExt(AFileName));

  if Ext = '.tsv' then
  begin
    FHasLog := LoadTsvFile(AFileName);
    if not FHasLog then
    begin
      try
        Viewer.DisplayRawText(TFile.ReadAllText(AFileName));
      except
        Viewer.DisplayRawText('Cannot read ' + AFileName);
      end;
      Exit(True);
    end;
    FindPartnerJson(AFileName);
    Result := Viewer.DisplayRun(FLogFile, SnapshotOrNil);
    Exit;
  end;

  try
    Text := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    Viewer.DisplayRawText('Cannot read ' + AFileName);
    Exit(True);
  end;

  if not FSnapshot.LoadFromText(Text) then
  begin
    Pretty := Text;
    JVal := System.JSON.TJSONObject.ParseJSONValue(Text);
    if Assigned(JVal) then
    try
      Pretty := JVal.Format(2);
    finally
      JVal.Free;
    end;
    Viewer.DisplayRawText(Pretty);
    Exit(True);
  end;

  FHasSnapshot := True;
  FindPartnerTsv(AFileName, Text);
  Result := Viewer.DisplayRun(LogOrNil, FSnapshot);
end;

function TELNDepositionViewerPlugin.SnapshotOrNil: TDepoSnapshot;
begin
  if FHasSnapshot then Result := FSnapshot else Result := nil;
end;

function TELNDepositionViewerPlugin.LogOrNil: TLogFile;
begin
  if FHasLog then Result := FLogFile else Result := nil;
end;

function TELNDepositionViewerPlugin.GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
begin
  Result := Viewer.GetPreviewBitmap(MaxWidth, MaxHeight);
end;

function TELNDepositionViewerPlugin.SaveState: string;
begin
  Result := Viewer.SaveState;
end;

procedure TELNDepositionViewerPlugin.RestoreState(const AState: string);
begin
  Viewer.RestoreState(AState);
end;

function TELNDepositionViewerPlugin.GetTotalRows: Integer;
begin
  if FHasLog then Result := FLogFile.GetTotalRows else Result := 0;
end;

function TELNDepositionViewerPlugin.GetTimeAxisIndex: Integer;
begin
  if FHasLog then Result := FLogFile.GetTimeAxisIndex else Result := -1;
end;

function TELNDepositionViewerPlugin.GetTimeSpan(out StartTime, EndTime: string): Boolean;
begin
  if FHasLog then
    Result := FLogFile.GetTimeSpan(StartTime, EndTime)
  else
  begin
    StartTime := '';
    EndTime := '';
    Result := False;
  end;
end;

function TELNDepositionViewerPlugin.GetSchema: TArray<TColumnSchema>;
begin
  if FHasLog then Result := FLogFile.GetSchema else Result := nil;
end;

function TELNDepositionViewerPlugin.ResolveColumnName(const Name: string;
  out Indices: TArray<Integer>): Boolean;
begin
  if FHasLog then
    Result := FLogFile.ResolveColumnName(Name, Indices)
  else
  begin
    SetLength(Indices, 0);
    Result := False;
  end;
end;

function TELNDepositionViewerPlugin.GetData(const Req: TColumnarRequest): TArray<TArray<TColumnPoint>>;
begin
  if FHasLog then Result := FLogFile.GetData(Req) else Result := nil;
end;

function TELNDepositionViewerPlugin.GetStats(const Cols: TArray<Integer>): TArray<TColumnStats>;
begin
  if FHasLog then Result := FLogFile.GetStats(Cols) else Result := nil;
end;

function TELNDepositionViewerPlugin.GetKeyValues: TArray<TPluginKeyValue>;
begin
  if FHasSnapshot then
    Result := FSnapshot.BuildKeyValues
  else
    Result := nil;
end;

function TELNDepositionViewerPlugin.GetDetailedInfo: string;
var
  J, JLog: TJSONObject;
  StartT, EndT: string;
begin
  if FHasSnapshot then
    J := FSnapshot.BuildDetailedJson
  else
    J := TJSONObject.Create;
  try
    if FHasLog then
    begin
      JLog := TJSONObject.Create;
      JLog.AddPair('rows', TJSONNumber.Create(FLogFile.GetTotalRows));
      JLog.AddPair('columns', TJSONNumber.Create(FLogFile.ColumnCount));
      if FLogFile.GetTimeSpan(StartT, EndT) then
      begin
        JLog.AddPair('timeStart', StartT);
        JLog.AddPair('timeEnd', EndT);
      end;
      J.AddPair('log', JLog);
    end;
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

end.
