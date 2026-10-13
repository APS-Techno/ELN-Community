unit unit_PluginHost;

interface

uses
  System.SysUtils, System.Generics.Collections,
  System.JSON,
  Winapi.Windows,
  Vcl.Forms,
  upfManager, unit_ELNPluginCore, unit_ELNPluginTypes;

type
  TPluginHost = class
  private
    FHiddenForm: TForm;
    FPreviousApplicationHandle: HWND;
    FPluginManager: TupfPluginManager;
    FPlugins: TList<IViewerPlugin>;
    procedure OnPluginRegistered(Sender, APlugin: TObject);
    procedure OnPackageLoadError(Sender: TObject; AFilename, AMsg: string);
    procedure OnAfterPackageLoaded(Sender: TObject; AFilename: string);
  public
    constructor Create(const PluginsDir: string);
    destructor Destroy; override;
    function FindPlugin(const AFileNameOrExt: string): IViewerPlugin;
    function ExtractDetailedInfo(const FilePath, Ext: string): string;
    function ExtractKeyValues(const FilePath, Ext: string): TArray<TPluginKeyValue>;
    function ExtractReaderKeyValues(const FilePath, Ext: string;
      out ReaderId, ReaderVersion: string): TArray<TPluginKeyValue>;
    function ListFileColumns(const FilePath, Ext: string): TJSONObject;
    function GetFileColumns(const FilePath, Ext: string;
                            const Req: TJSONObject): TJSONObject;
  end;

implementation

uses
  System.Math, unit_ViewerExtMatch;

type
  TupfPluginManagerHelper = class(TupfPluginManager);


function DTypeToStr(D: TColumnDType): string;
begin
  if D = cdNumeric then Result := 'numeric' else Result := 'text';
end;

function ParseMode(const S: string; out Mode: TColumnarMode): Boolean;
begin
  Result := True;
  if SameText(S, '') or SameText(S, 'downsample') then Mode := cmDownsample
  else if SameText(S, 'raw')   then Mode := cmRaw
  else if SameText(S, 'stats') then Mode := cmStats
  else Result := False;
end;

function MakeError(const Msg: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('error', Msg);
end;

function IndicesToStr(const Indices: TArray<Integer>): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to Length(Indices) - 1 do
  begin
    if I > 0 then Result := Result + ', ';
    Result := Result + IntToStr(Indices[I]);
  end;
  Result := Result + ']';
end;

function ColumnHeader(const Schema: TColumnSchema): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index', TJSONNumber.Create(Schema.Index));
  Result.AddPair('name',  Schema.Name);
  Result.AddPair('units', Schema.Units);
  Result.AddPair('dtype', DTypeToStr(Schema.DType));
end;

function PointToJSON(const P: TColumnPoint; DType: TColumnDType): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('r', TJSONNumber.Create(P.Row));
  if P.Time <> '' then
    Result.AddPair('t', P.Time);
  if DType = cdText then
    Result.AddPair('txt', P.TextValue)
  else
  begin
    if IsNan(P.Value) then
      Result.AddPair('v', TJSONNull.Create)
    else
      Result.AddPair('v', TJSONNumber.Create(P.Value));
  end;
end;

function ColumnDataToJSON(const Schema: TColumnSchema;
                          const Points: TArray<TColumnPoint>): TJSONObject;
var
  Arr: TJSONArray;
  P: TColumnPoint;
begin
  Result := ColumnHeader(Schema);
  Arr := TJSONArray.Create;
  for P in Points do
    Arr.AddElement(PointToJSON(P, Schema.DType));
  Result.AddPair('points', Arr);
end;

function StatsToJSON(const Schema: TColumnSchema;
                     const S: TColumnStats): TJSONObject;
var
  Inner: TJSONObject;
begin
  Result := ColumnHeader(Schema);
  Inner := TJSONObject.Create;
  if Schema.DType = cdNumeric then
  begin
    Inner.AddPair('min',     TJSONNumber.Create(S.MinV));
    Inner.AddPair('max',     TJSONNumber.Create(S.MaxV));
    Inner.AddPair('mean',    TJSONNumber.Create(S.Mean));
    Inner.AddPair('stddev',  TJSONNumber.Create(S.StdDev));
    Inner.AddPair('first',   TJSONNumber.Create(S.FirstV));
    Inner.AddPair('last',    TJSONNumber.Create(S.LastV));
    Inner.AddPair('min_row', TJSONNumber.Create(S.MinRow));
    if S.MinTime <> '' then Inner.AddPair('min_time', S.MinTime);
    Inner.AddPair('max_row', TJSONNumber.Create(S.MaxRow));
    if S.MaxTime <> '' then Inner.AddPair('max_time', S.MaxTime);
    Inner.AddPair('non_zero_count', TJSONNumber.Create(S.NonZeroCount));
    Inner.AddPair('row_count',      TJSONNumber.Create(S.RowCount));
    Result.AddPair('stats', Inner);
  end
  else
  begin
    Inner.AddPair('first',          S.FirstText);
    Inner.AddPair('last',           S.LastText);
    Inner.AddPair('distinct_count', TJSONNumber.Create(S.DistinctCount));
    Inner.AddPair('row_count',      TJSONNumber.Create(S.RowCount));
    Result.AddPair('text_stats', Inner);
  end;
end;


procedure AddToPath(const Dir: string);
var
  OldPath: string;
begin
  if Dir = '' then Exit;
  OldPath := GetEnvironmentVariable('PATH');
  if Pos(LowerCase(Dir), LowerCase(OldPath)) = 0 then
    SetEnvironmentVariable(PChar('PATH'), PChar(Dir + ';' + OldPath));
end;

constructor TPluginHost.Create(const PluginsDir: string);
var
  LocalAppData: string;
begin
  inherited Create;
  FPreviousApplicationHandle := Application.Handle;
  FPlugins := TList<IViewerPlugin>.Create;

  // BPL plugins depend on Delphi and TMS runtime packages.
  // Add their directories to PATH so LoadPackage can find them.
  AddToPath('C:\Program Files (x86)\Embarcadero\Studio\37.0\bin');
  LocalAppData := GetEnvironmentVariable('LOCALAPPDATA');
  if LocalAppData <> '' then
    AddToPath(IncludeTrailingPathDelimiter(LocalAppData) +
      'tms\.tmssetup\build\bpl\Win32');

  // Inter-plugin BPL dependencies need the DLL search path (e.g. Markdown preview).
  SetDllDirectory(PChar(ExcludeTrailingPathDelimiter(PluginsDir)));

  // Hidden form provides an HWND for plugin frames that need a parent.
  // We must force handle creation so plugin frames can parent themselves.
  FHiddenForm := TForm.CreateNew(nil);
  FHiddenForm.Position := poDesigned;
  FHiddenForm.Left := -32000;
  FHiddenForm.Top := -32000;
  FHiddenForm.Width := 800;
  FHiddenForm.Height := 600;
  FHiddenForm.HandleNeeded;
  FHiddenForm.Show;
  FHiddenForm.Hide;

  // Console applications do not create Application.Handle. Frames streamed
  // before host parenting need this HWND as their fallback parent.
  Application.Handle := FHiddenForm.Handle;

  FPluginManager := TupfPluginManager.Create(FHiddenForm);
  // Loaded is normally called by the DFM streaming system. When creating
  // at runtime we must call it manually so the ApplicationServices global
  // is initialised — otherwise RegisterViewerPlugin silently exits.
  TupfPluginManagerHelper(FPluginManager).Loaded;
  FPluginManager.OnPluginRegistered := OnPluginRegistered;
  FPluginManager.OnPackageOnLoadError := OnPackageLoadError;
  FPluginManager.OnAfterPackageLoaded := OnAfterPackageLoaded;
  FPluginManager.PluginFolder := PluginsDir;

  WriteLn(ErrOutput, 'PluginHost: loading plugins from ' + PluginsDir);
  Flush(ErrOutput);
  try
    FPluginManager.LoadPlugins;
  except
    on E: Exception do
      WriteLn(ErrOutput, 'PluginHost: LoadPlugins exception: ' + E.ClassName + ': ' + E.Message);
  end;
  WriteLn(ErrOutput, 'PluginHost: ' + IntToStr(FPlugins.Count) + ' viewer plugin(s) loaded.');
  Flush(ErrOutput);
end;

destructor TPluginHost.Destroy;
var
  I: Integer;
begin
  // Keep BPLs loaded until process exit: reachable plugin objects and frames
  // still use their VMTs during teardown. Clear references and module handles
  // so the manager destructor cannot unload their code.
  FPlugins.Free;
  FPlugins := nil;

  if Assigned(FPluginManager) then
  begin
    for I := 0 to FPluginManager.Packages.Count - 1 do
      FPluginManager.Packages.HModules[I] := 0;
    FPluginManager.Free;
  end;

  // Destroys the plugin frames still parented here (TWinControl.Destroy
  // frees ALL children, owned or not) - safe, their code is still loaded.
  if Assigned(FHiddenForm) and FHiddenForm.HandleAllocated and
    (Application.Handle = FHiddenForm.Handle) then
    Application.Handle := FPreviousApplicationHandle;
  FHiddenForm.Free;
  inherited Destroy;
end;

procedure TPluginHost.OnPluginRegistered(Sender, APlugin: TObject);
var
  Plugin: IViewerPlugin;
begin
  if Supports(APlugin, IViewerPlugin, Plugin) then
  begin
    if Assigned(Plugin.Frame) then
    begin
      Plugin.Frame.Parent := FHiddenForm;
      Plugin.Frame.Visible := False;
    end;
    FPlugins.Add(Plugin);
    WriteLn(ErrOutput, 'PluginHost: registered plugin "' + Plugin.Caption +
      '" (ext: ' + Plugin.Params.Ext + ')');
  end;
end;

procedure TPluginHost.OnPackageLoadError(Sender: TObject; AFilename, AMsg: string);
begin
  WriteLn(ErrOutput, 'PluginHost ERROR: ' + ExtractFileName(AFilename) + ': ' + AMsg);
  Flush(ErrOutput);
end;

procedure TPluginHost.OnAfterPackageLoaded(Sender: TObject; AFilename: string);
begin
  WriteLn(ErrOutput, 'PluginHost: package loaded: ' + ExtractFileName(AFilename));
  Flush(ErrOutput);
end;

function TPluginHost.FindPlugin(const AFileNameOrExt: string): IViewerPlugin;
var
  P: IViewerPlugin;
  Score, BestScore: Integer;
begin
  // Highest score wins, so '.depo.json' beats '.json'. Accepts either a full
  // file name or a bare extension.
  Result    := nil;
  BestScore := 0;
  for P in FPlugins do
  begin
    Score := ExtMatchScore(AFileNameOrExt, P.Params.Ext);
    if Score > BestScore then
    begin
      BestScore := Score;
      Result    := P;
    end;
  end;
end;

function TPluginHost.ExtractDetailedInfo(const FilePath, Ext: string): string;
var
  Plugin: IViewerPlugin;
  Provider: IDetailedInfoProvider;
begin
  Plugin := FindPlugin(FilePath);
  if Plugin = nil then
    raise Exception.CreateFmt('No plugin found for extension: %s', [Ext]);

  try
    if not Plugin.LoadFromFile(FilePath) then
      raise Exception.Create('The viewer rejected the input file.');
  except
    on E: Exception do
      raise Exception.CreateFmt('Plugin failed to load file "%s": %s',
        [FilePath, E.Message]);
  end;

  if Supports(Plugin, IDetailedInfoProvider, Provider) then
    Result := Provider.GetDetailedInfo
  else
    Result := '{}';
end;

function TPluginHost.ExtractKeyValues(const FilePath, Ext: string): TArray<TPluginKeyValue>;
var
  ReaderId, ReaderVersion: string;
begin
  Result := ExtractReaderKeyValues(FilePath, Ext, ReaderId, ReaderVersion);
end;

function TPluginHost.ExtractReaderKeyValues(const FilePath, Ext: string;
  out ReaderId, ReaderVersion: string): TArray<TPluginKeyValue>;
var
  Plugin: IViewerPlugin;
  Provider: IKeyValueProvider;
begin
  Plugin := FindPlugin(FilePath);
  if Plugin = nil then
    raise Exception.CreateFmt('No plugin found for extension: %s', [Ext]);
  ReaderIdentityOf(Plugin, ReaderId, ReaderVersion);

  try
    if not Plugin.LoadFromFile(FilePath) then
      raise Exception.Create('The viewer rejected the input file.');
  except
    on E: Exception do
      raise Exception.CreateFmt('Plugin failed to load file "%s": %s',
        [FilePath, E.Message]);
  end;

  if Supports(Plugin, IKeyValueProvider, Provider) then
    Result := Provider.GetKeyValues
  else
    Result := nil;
end;

function TPluginHost.ListFileColumns(const FilePath, Ext: string): TJSONObject;
var
  Plugin: IViewerPlugin;
  Provider: IColumnarDataProvider;
  Schema: TArray<TColumnSchema>;
  StartT, EndT: string;
  HasTime: Boolean;
  TimeSpan: TJSONObject;
  ColArr: TJSONArray;
  I: Integer;
begin
  Plugin := FindPlugin(FilePath);
  if Plugin = nil then Exit(MakeError('No plugin found for extension: ' + Ext));

  if not Supports(Plugin, IColumnarDataProvider, Provider) then
    Exit(MakeError('File type not tabular: ' + Ext));

  try
    if not Plugin.LoadFromFile(FilePath) then
      Exit(MakeError('Plugin failed to load file: ' + FilePath));
  except
    on E: Exception do
      Exit(MakeError('Plugin failed to load file: ' + E.Message));
  end;

  Schema := Provider.GetSchema;

  Result := TJSONObject.Create;
  try
    Result.AddPair('extension', Ext);
    Result.AddPair('total_rows', TJSONNumber.Create(Provider.GetTotalRows));

    HasTime := Provider.GetTimeSpan(StartT, EndT);
    if HasTime then
    begin
      TimeSpan := TJSONObject.Create;
      try
        TimeSpan.AddPair('start', StartT);
        TimeSpan.AddPair('end', EndT);
        TimeSpan.AddPair('axis_column', TJSONNumber.Create(Provider.GetTimeAxisIndex));
        Result.AddPair('time_span', TimeSpan);
      except
        TimeSpan.Free;
        raise;
      end;
    end;

    ColArr := TJSONArray.Create;
    for I := 0 to Length(Schema) - 1 do
      ColArr.AddElement(ColumnHeader(Schema[I]));
    Result.AddPair('columns', ColArr);
  except
    Result.Free;
    raise;
  end;
end;

function TPluginHost.GetFileColumns(const FilePath, Ext: string;
                                    const Req: TJSONObject): TJSONObject;
var
  Plugin: IViewerPlugin;
  Provider: IColumnarDataProvider;
  ModeStr: string;
  Mode: TColumnarMode;
  ColumnsVal: TJSONValue;
  ColumnsArr: TJSONArray;
  ResolvedCols: TArray<Integer>;
  Indices: TArray<Integer>;
  RowRangeArr: TJSONArray;
  CR: TColumnarRequest;
  TotalRows, MaxRows, RangeStart, RangeEnd, I: Integer;
  Schema: TArray<TColumnSchema>;
  Stats: TArray<TColumnStats>;
  Data: TArray<TArray<TColumnPoint>>;
  ColVal: TJSONValue;
  AsInt: Integer;
  AsName: string;
  ColArr: TJSONArray;
  RangeArr: TJSONArray;
  IntVal: Int64;
begin
  Plugin := FindPlugin(FilePath);
  if Plugin = nil then Exit(MakeError('No plugin found for extension: ' + Ext));

  if not Supports(Plugin, IColumnarDataProvider, Provider) then
    Exit(MakeError('File type not tabular: ' + Ext));

  try
    if not Plugin.LoadFromFile(FilePath) then
      Exit(MakeError('Plugin failed to load file: ' + FilePath));
  except
    on E: Exception do
      Exit(MakeError('Plugin failed to load file: ' + E.Message));
  end;

  ModeStr := '';
  if Req.FindValue('mode') <> nil then
    ModeStr := Req.GetValue<string>('mode');
  if not ParseMode(ModeStr, Mode) then
    Exit(MakeError('Invalid mode: ' + ModeStr +
                   ' (expected raw, downsample, or stats)'));

  ColumnsVal := Req.FindValue('columns');
  if (ColumnsVal = nil) or not (ColumnsVal is TJSONArray) then
    Exit(MakeError('Missing required parameter: columns (array of int or string)'));
  ColumnsArr := ColumnsVal as TJSONArray;
  if ColumnsArr.Count = 0 then
    Exit(MakeError('columns array is empty'));

  TotalRows := Provider.GetTotalRows;
  Schema := Provider.GetSchema;

  SetLength(ResolvedCols, ColumnsArr.Count);
  for I := 0 to ColumnsArr.Count - 1 do
  begin
    ColVal := ColumnsArr.Items[I];
    if ColVal is TJSONNumber then
    begin
      IntVal := (ColVal as TJSONNumber).AsInt64;
      AsInt := Integer(IntVal);
      if (AsInt < 0) or (AsInt >= Length(Schema)) then
        Exit(MakeError(Format(
          'Column index out of range: %d (max %d)', [AsInt, Length(Schema) - 1])));
      ResolvedCols[I] := AsInt;
    end
    else if ColVal is TJSONString then
    begin
      AsName := (ColVal as TJSONString).Value;
      Provider.ResolveColumnName(AsName, Indices);
      if Length(Indices) = 0 then
        Exit(MakeError('Unknown column name: ' + AsName));
      if Length(Indices) > 1 then
        Exit(MakeError(Format('Ambiguous column name ''%s'' matches indices %s',
          [AsName, IndicesToStr(Indices)])));
      ResolvedCols[I] := Indices[0];
    end
    else
      Exit(MakeError(Format('columns[%d] must be integer index or string name', [I])));
  end;

  MaxRows := 500;
  if Req.FindValue('max_rows') <> nil then
    MaxRows := Req.GetValue<Integer>('max_rows');
  if MaxRows < 2 then
    Exit(MakeError('max_rows must be >= 2'));

  RangeStart := 0;
  RangeEnd := TotalRows;
  if Req.FindValue('row_range') <> nil then
  begin
    RowRangeArr := Req.GetValue<TJSONArray>('row_range');
    if (RowRangeArr = nil) or (RowRangeArr.Count <> 2) then
      Exit(MakeError('row_range must be a 2-element array [start, end]'));
    RangeStart := (RowRangeArr.Items[0] as TJSONNumber).AsInt;
    RangeEnd   := (RowRangeArr.Items[1] as TJSONNumber).AsInt;
    if (RangeStart < 0) or (RangeEnd > TotalRows) or (RangeStart >= RangeEnd) then
      Exit(MakeError(Format(
        'Invalid row_range: [%d, %d] (file has %d rows)',
        [RangeStart, RangeEnd, TotalRows])));
  end;

  Result := TJSONObject.Create;
  try
    case Mode of
      cmStats:
      begin
        Result.AddPair('mode', 'stats');
        Stats := Provider.GetStats(ResolvedCols);
        ColArr := TJSONArray.Create;
        for I := 0 to Length(ResolvedCols) - 1 do
          ColArr.AddElement(StatsToJSON(Schema[ResolvedCols[I]], Stats[I]));
        Result.AddPair('columns', ColArr);
      end;

      cmRaw, cmDownsample:
      begin
        if Mode = cmRaw then Result.AddPair('mode', 'raw')
        else                 Result.AddPair('mode', 'downsample');
        if Mode = cmDownsample then
          Result.AddPair('max_rows', TJSONNumber.Create(MaxRows));
        RangeArr := TJSONArray.Create;
        RangeArr.Add(RangeStart);
        RangeArr.Add(RangeEnd);
        Result.AddPair('row_range', RangeArr);

        CR := Default(TColumnarRequest);
        CR.Mode := Mode;
        CR.Columns := ResolvedCols;
        CR.MaxRows := MaxRows;
        CR.RowStart := RangeStart;
        CR.RowEnd := RangeEnd;
        CR.TimeAxisIndex := Provider.GetTimeAxisIndex;

        Data := Provider.GetData(CR);

        ColArr := TJSONArray.Create;
        for I := 0 to Length(ResolvedCols) - 1 do
          ColArr.AddElement(ColumnDataToJSON(Schema[ResolvedCols[I]], Data[I]));
        Result.AddPair('columns', ColArr);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
