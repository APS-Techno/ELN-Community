unit unit_ELNPluginCore;

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.Graphics,
  upfIntf, upfVisualClasses,
  unit_ELNPluginTypes;

type

  TELNPluginType = (ptFile, ptOLE, ptText);

  TPluginParams = record
      PType: TELNPluginType;
        Ext: string;
    IntOpen: boolean;
    AcceptsPartialLoad: boolean;
  end;

  IViewerPlugin = interface
  ['{D57F8054-26B6-4FBB-9EFE-6B3C71D5CC17}']
    function GetFrame    : TFrame;
    function GetCaption  : string;
    function GetParams   : TPluginParams;
    function LoadFromFile(const AFileName: string): Boolean;
    function LoadFromStream(Stream: TMemoryStream): Boolean;

    procedure DisplayText(const Caption, Text: string);

    property Frame    : TFrame read GetFrame;
    property Caption  : string read GetCaption;
    property Params   : TPluginParams read GetParams;
  end;

  IPreviewProvider = interface
  ['{F4A2C8E1-7B3D-4A5F-9E6C-1D8B0F2A3E47}']
    function GetPreview(MaxWidth, MaxHeight: Integer): TBitmap;
  end;

  IKeyValueProvider = interface
  ['{B7E3A1D4-9F2C-4E8B-A6D1-3C5F0E7B2A94}']
    function GetKeyValues: TArray<TPluginKeyValue>;
  end;

  // A stored value records this identity. Change the version whenever
  // GetKeyValues can return different output for the same file.
  IReaderIdentity = interface
  ['{1A4C4149-8A73-4355-B709-50728537973A}']
    function GetReaderId: string;
    function GetReaderVersion: string;
  end;

  IDetailedInfoProvider = interface
  ['{E1C4D8F2-5A3B-47E9-B0F6-8D2E1A9C3B75}']
    function GetDetailedInfo: string;
  end;

  IStatefulViewer = interface
  ['{C8F2D4A1-3E5B-47F9-A1D6-9B4E0C7F2D83}']
    function SaveState: string;
    procedure RestoreState(const AState: string);
  end;

  IProtocolEditor = interface
  ['{A83B1F09-5C4E-4D2A-B7F1-8E6D3C9A2B05}']
    procedure LoadTemplate(const TemplateHtml: string; const FormData: string);
    procedure LoadFreeText(const FormData: string);
    function  GetFormData: string;
    procedure SetReadOnly(Value: Boolean);
    function  GetReadOnly: Boolean;
    procedure PrepareForReparent;
    // Fires once on the first user edit, not on programmatic form loading.
    procedure SetOnDirty(const AHandler: TNotifyEvent);
    property  ReadOnly: Boolean read GetReadOnly write SetReadOnly;
  end;

  IElnLinkHandler = interface
  ['{6A0F2D7C-1E4B-4C3F-9B2D-7E5A8F1C0931}']
    function HandleLink(const Url: string): Boolean;
  end;

  // Bare "[ID]name.ext" names are authoritative even when sibling files have
  // not been downloaded. EnsureItemFilesInDir also makes them available locally.
  IElnFileEnumerator = interface
  ['{8B3D5F2A-9C1E-4D7B-A0F8-2E6C4A1D9B73}']
    function GetItemFiles(ItemId: Integer): TArray<string>;
    function EnsureItemFilesInDir(ItemId: Integer;
      const TargetDir: string): TArray<string>;
  end;

  TSaveResult = (srOk, srConflict, srError);

  // Plugin -> Host: save the (already locally-modified) file back to the
  // server, and upload pasted/dropped attachments. The host owns WebDAV;
  // the plugin only edits the local file the host placed for it.
  IElnFileService = interface
  ['{67D322FB-63D8-482E-9D9D-DF5185834D22}']
    // Return the complete, version-bound editable working copy for this file.
    // Never return a partial preview. Reopening must retain an existing draft.
    function PrepareLocalFile(FileId: Int64): string;
    // Uses the working copy's captured version; srConflict preserves the draft.
    function SaveLocalFile(FileId: Int64; const LocalPath: string;
                           out ErrorMsg: string): TSaveResult;
    // Same as SaveLocalFile but bypasses If-Match (user picked
    // "Save Anyway" after a conflict).
    function SaveLocalFileForce(FileId: Int64; const LocalPath: string;
                                out ErrorMsg: string): TSaveResult;
    // Replaces the local working copy with the current stored version.
    function ReloadLocalFile(FileId: Int64; const LocalPath: string;
                             out ErrorMsg: string): Boolean;
    // Upload an attachment for paste/drop. Returns the bare server filename
    // (the resolver adds the [ID] prefix at render time). Raises on failure.
    function UploadAttachment(ItemId: Integer;
                              const LocalPath, SuggestedName: string): string;
  end;

  IMarkdownEditorLauncher = interface
  ['{F997ADDA-0A60-45D3-ACFD-F33A1C12125E}']
    // OnSaved receives the new body only after a successful save.
    procedure LaunchEditor(const LocalPath: string;
                           ItemId: Integer; FileId: Int64;
                           OnSaved: TProc<string>);
  end;

  // The host must set context BEFORE LoadFromFile for initial attachment routing.
  IItemContextAware = interface
  ['{713CE1D0-1C35-4755-9CDD-5B75F894C2B4}']
    procedure SetItemContext(ItemId: Integer; FileId: Int64);
  end;

  TColumnDType = (cdNumeric, cdText);

  TColumnarMode = (cmRaw, cmDownsample, cmStats);

  TColumnSchema = record
    Index: Integer;
    Name:  string;
    Units: string;
    DType: TColumnDType;
  end;

  TColumnPoint = record
    Row:       Integer;
    Time:      string;
    Value:     Double;
    TextValue: string;
  end;

  TColumnStats = record
    DType: TColumnDType;
    MinV, MaxV, Mean, StdDev, FirstV, LastV: Double;
    MinRow, MaxRow, NonZeroCount, RowCount: Integer;
    MinTime, MaxTime: string;
    DistinctCount: Integer;
    FirstText, LastText: string;
  end;

  TColumnarRequest = record
    Mode:          TColumnarMode;
    Columns:       TArray<Integer>;
    MaxRows:       Integer;               // downsample only; <2 falls back to 500
    RowStart:      Integer;               // -1 = from beginning
    RowEnd:        Integer;               // -1 = to end (exclusive)
    TimeAxisIndex: Integer;               // -1 = no time axis
  end;

  IColumnarDataProvider = interface
  ['{C1A4B8E2-7D3F-4E5A-9C6B-1F2D8E0A3B47}']
    function GetTotalRows: Integer;
    function GetTimeAxisIndex: Integer;
    function GetTimeSpan(out StartTime, EndTime: string): Boolean;
    function GetSchema: TArray<TColumnSchema>;
    // Returns False if no column matches Name; True if one or more found.
    // Out Indices: zero-length only when Result is False; length 1 = unique
    // match; length > 1 = ambiguous (caller decides how to handle).
    function ResolveColumnName(const Name: string;
      out Indices: TArray<Integer>): Boolean;
    // Out: one inner array per requested column, in request order.
    function GetData(const Req: TColumnarRequest): TArray<TArray<TColumnPoint>>;
    function GetStats(const Cols: TArray<Integer>): TArray<TColumnStats>;
  end;

  // Plugin -> Host: opt out of the host's standard ButtonsPanel toolbar.
  // Plugins that don't implement this interface get the toolbar (current
  // behavior). A plugin that implements it and returns False causes the host
  // to hide ButtonsPanel entirely while this plugin is active.
  IHostToolbarAware = interface
  ['{C86FFECE-A319-4C17-ADB7-645823B35FD1}']
    function ShowHostToolbar: Boolean;
  end;

  TELNBaseViewerPlugin = class(TupfVisualPlugin, IViewerPlugin)
    procedure upfVisualPluginCreate(Sender: TObject);
    procedure upfVisualPluginDestroy(Sender: TObject);
  protected
    FFrame: TFrame;
    function CreateViewerFrame: TFrame; virtual; abstract;
    function GetFrame: TFrame;
    function GetCaption: string;
    function GetParams: TPluginParams; virtual; abstract;
  public
    function LoadFromFile(const AFileName: string): Boolean; virtual;
    function LoadFromStream(Stream: TMemoryStream): Boolean; virtual;
    procedure DisplayText(const Caption, Text: string); virtual;
    property Frame: TFrame read GetFrame;
    property Caption: string read GetCaption;
    property Params: TPluginParams read GetParams;
  end;

procedure RegisterViewerPlugin(APlugin: TupfVisualPlugin);

const
  READER_VERSION_UNKNOWN = 'unknown';

procedure ReaderIdentityOf(const Plugin: IViewerPlugin;
  out ReaderId, ReaderVersion: string);

function SaveChartState(Chart: TObject): string;
procedure RestoreChartState(Chart: TObject; const AState: string);

var
  // Single host-supplied link handler shared across all plugins. Lives in the
  // ELNPluginCore BPL so the host EXE and every plugin BPL see the same
  // instance. Nil until the host registers itself.
  ElnLinkHandler: IElnLinkHandler;
  ElnFileService:         IElnFileService;
  MarkdownEditorLauncher: IMarkdownEditorLauncher;
  ElnFileEnumerator:      IElnFileEnumerator;

implementation

uses
  System.JSON, VCLTee.Chart;


procedure TELNBaseViewerPlugin.upfVisualPluginCreate(Sender: TObject);
begin
  FFrame := CreateViewerFrame;
end;

procedure TELNBaseViewerPlugin.upfVisualPluginDestroy(Sender: TObject);
begin
  FFrame.Free;
end;

function TELNBaseViewerPlugin.GetFrame: TFrame;
begin
  Result := FFrame;
end;

function TELNBaseViewerPlugin.GetCaption: string;
begin
  Result := PluginName;
end;

function TELNBaseViewerPlugin.LoadFromFile(const AFileName: string): Boolean;
begin
  Result := False;
end;

function TELNBaseViewerPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
begin
  Result := False;
end;

procedure TELNBaseViewerPlugin.DisplayText(const Caption, Text: string);
begin
end;

procedure RegisterViewerPlugin(APlugin: TupfVisualPlugin);
var
  AppSvc: IupfCommandServices;
  J: Integer;
begin
  if Assigned(ApplicationServices) then
  begin
    AppSvc := ApplicationServices as IupfCommandServices;
    AppSvc.RegisterPlugin(APlugin);
    for J := 0 to APlugin.Commands.Count - 1 do
      AppSvc.RegisterCommand(APlugin, APlugin.Commands[J]);
  end;
end;

procedure ReaderIdentityOf(const Plugin: IViewerPlugin;
  out ReaderId, ReaderVersion: string);
var
  Identity: IReaderIdentity;
begin
  if Supports(Plugin, IReaderIdentity, Identity) then
  begin
    ReaderId := Identity.GetReaderId;
    ReaderVersion := Identity.GetReaderVersion;
  end
  else
  begin
    ReaderId := Plugin.Caption;
    ReaderVersion := READER_VERSION_UNKNOWN;
  end;
end;

function SaveChartState(Chart: TObject): string;
var
  C: TChart;
  JObj: TJSONObject;
begin
  Result := '';
  if not (Chart is TChart) then Exit;
  C := TChart(Chart);
  if C.SeriesCount = 0 then Exit;

  JObj := TJSONObject.Create;
  try
    JObj.AddPair('v', TJSONNumber.Create(1));
    JObj.AddPair('xMin', TJSONNumber.Create(C.BottomAxis.Minimum));
    JObj.AddPair('xMax', TJSONNumber.Create(C.BottomAxis.Maximum));
    JObj.AddPair('yMin', TJSONNumber.Create(C.LeftAxis.Minimum));
    JObj.AddPair('yMax', TJSONNumber.Create(C.LeftAxis.Maximum));
    JObj.AddPair('xAuto', TJSONBool.Create(C.BottomAxis.Automatic));
    JObj.AddPair('yAuto', TJSONBool.Create(C.LeftAxis.Automatic));
    Result := JObj.ToJSON;
  finally
    JObj.Free;
  end;
end;

procedure RestoreChartState(Chart: TObject; const AState: string);
var
  C: TChart;
  JObj: TJSONObject;
  JVal: TJSONValue;
begin
  if not (Chart is TChart) then Exit;
  C := TChart(Chart);

  try
    JObj := TJSONObject.ParseJSONValue(AState) as TJSONObject;
  except
    Exit;
  end;
  if not Assigned(JObj) then Exit;

  try
    JVal := JObj.GetValue('xAuto');
    if Assigned(JVal) and (JVal is TJSONBool) and (JVal as TJSONBool).AsBoolean then
      C.BottomAxis.Automatic := True
    else
    begin
      C.BottomAxis.Automatic := False;
      C.BottomAxis.Minimum := JObj.GetValue<Double>('xMin', C.BottomAxis.Minimum);
      C.BottomAxis.Maximum := JObj.GetValue<Double>('xMax', C.BottomAxis.Maximum);
    end;

    JVal := JObj.GetValue('yAuto');
    if Assigned(JVal) and (JVal is TJSONBool) and (JVal as TJSONBool).AsBoolean then
      C.LeftAxis.Automatic := True
    else
    begin
      C.LeftAxis.Automatic := False;
      C.LeftAxis.Minimum := JObj.GetValue<Double>('yMin', C.LeftAxis.Minimum);
      C.LeftAxis.Maximum := JObj.GetValue<Double>('yMax', C.LeftAxis.Maximum);
    end;
  finally
    JObj.Free;
  end;
end;

end.
