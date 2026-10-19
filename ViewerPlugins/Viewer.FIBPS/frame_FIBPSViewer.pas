unit frame_FIBPSViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math,
  System.Types,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Dialogs,
  VclTee.TeeGDIPlus, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzButton,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_FIBPSData, unit_FIBPSAnalysis;

type
  TRGBTripleArray = array[0..0] of TRGBTriple;
  PRGBTripleArray = ^TRGBTripleArray;

  TToolMode = (tmNone, tmProfile, tmDistance, tmRoughness, tmStepHeight, tmWearTrack);

  TStepRegion = record
    XMin, XMax: Double;
    AvgH: Double;
    Count: Integer;
    HasRegion: Boolean;
  end;

  TframeFIBPSViewer = class(TFrame)
    pnlToolbar: TPanel;
    btnProfile: TRzBitBtn;
    btnDistance: TRzBitBtn;
    btnRoughness: TRzBitBtn;
    btnFlatten: TRzBitBtn;
    btnStepHeight: TRzBitBtn;
    btnWearTrack: TRzBitBtn;
    btnCopyData: TRzBitBtn;
    btnCopyImage: TRzBitBtn;
    btnSave: TRzBitBtn;
    Status: TRzStatusBar;
    pnlInfo: TRzPanel;
    ChartProfile: TChart;
    serProfileH: TFastLineSeries;
    serProfileV: TFastLineSeries;
    serWearUpper: TFastLineSeries;
    serWearLower: TFastLineSeries;
    serWearMean: TFastLineSeries;
    SplitterProfile: TSplitter;
    pnlCenter: TPanel;
    pbLegend: TPaintBox;
    ScrollBox: TScrollBox;
    Image: TImage;
    dlgSave: TSaveDialog;
    procedure ScrollBoxResize(Sender: TObject);
    procedure ScrollBoxMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ImageMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ImageMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ImageMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ImageDblClick(Sender: TObject);
    procedure pbLegendPaint(Sender: TObject);
    procedure btnProfileClick(Sender: TObject);
    procedure btnDistanceClick(Sender: TObject);
    procedure btnRoughnessClick(Sender: TObject);
    procedure btnFlattenClick(Sender: TObject);
    procedure btnStepHeightClick(Sender: TObject);
    procedure btnWearTrackClick(Sender: TObject);
    procedure btnCopyDataClick(Sender: TObject);
    procedure btnCopyImageClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FData: TFIBPSData;
    FBitmap: TBitmap;
    FZoom: Double;
    FPalette: array[0..255] of TColor;
    FToolMode: TToolMode;
    FStatusBase: string;
    FCursorPos: TPoint;
    FHasCursor: Boolean;

    FProfileRow: Integer;    // -1 = not set
    FProfileCol: Integer;    // -1 = not set
    FProfileIsVert: Boolean;
    FFlatten: Boolean;

    FDistPtA: TPoint;
    FDistPtB: TPoint;
    FDistHasA: Boolean;
    FDistHasB: Boolean;

    FRoughOrigin: TPoint;
    FRoughDragging: Boolean;
    FRoughRect: TRect;
    FRoughHasRect: Boolean;

    FStepRegionA: TStepRegion;
    FStepRegionB: TStepRegion;
    FStepDragging: Boolean;
    FStepDragStart: Double;

    FStepRes: TFIBPSStepResult;
    FHasStep: Boolean;
    FStepDragTarget: Integer;
    FStepDragNext: Integer;
    FStepDragOrigin: TPoint;
    FWearRes: TFIBPSWearResult;
    FHasWear: Boolean;
    FPlaneA: Double;
    FPlaneB: Double;
    FPlaneC: Double;
    FDispMinH: Single;
    FDispMaxH: Single;
    FPnlMeta: TPanel;
    FLblMeta: TLabel;
    FLoadedPath: string;
    FLoadedHash: string;
    FContext: TAnalysisContext;
    FResolved: TFIBPSStepAnalysis;
    FResolvedValid: Boolean;
    FStepUserSet: Boolean;
    FStepFallback: Boolean;
    FStepOrigin: TFIBPSOrigin;
    function ResolvedStep: TFIBPSStepAnalysis;
    function StepForExtraction(out Analysis: TFIBPSStepAnalysis): Boolean;
    function CanApplyShared: Boolean;
    procedure ApplySharedRegions;

    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    function FormatH(Value: Double): string;
    procedure BuildColorRamp;
    function MapColor(Value, MinVal, MaxVal: Single): TColor;
    procedure RenderBitmap;
    function DisplayHeightAt(X, Y: Integer): Single;
    procedure UpdatePlaneAndRender;
    procedure ShowWearTrackResult;
    procedure ApplyZoom;
    procedure CenterImage;
    function ImagePixToData(ImgX, ImgY: Integer; out DX, DY: Integer): Boolean;
    procedure UpdateStatusCursor(DX, DY: Integer);
    procedure UpdateProfile(Row, Col: Integer);
    procedure RegionDetrend(var YVals: array of Double; const XVals: array of Double; Count: Integer);
    procedure DrawOverlay;
    procedure ShowDistanceResult;
    procedure ShowProfilePanel(AVisible: Boolean);
    procedure CancelTool;
    procedure CalcRoughness(const R: TRect; out Ra, Rq, Rz: Double);
    procedure ChartProfileMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ChartProfileMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ChartProfileAfterDraw(Sender: TObject);
    procedure CalcRegionAverage(XMin, XMax: Double; out AvgH: Double; out Count: Integer);
    procedure ShowStepHeightResult;
    procedure EnsureStepResult;
    procedure HeightDataToText(List: TStringList);
    procedure WearProfileToText(List: TStringList);
    procedure ShowWearProfile;
    procedure ApplyVerticalMargins;
    procedure CreateMetaPanel;
    function FormatRecipeInfo(const R: TFIBPSRecipe): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: string);
    procedure ShowError(const Msg: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
    function GetKeyValues: TArray<TPluginKeyValue>;
    function GetDetailedInfo: string;
    function SaveState: string;
    procedure RestoreState(const AState: string);
    procedure SetAnalysisContext(const Context: TAnalysisContext);
    function GetAnalysisSnapshot(const KeyName: string): string;
    function GetAnalysisStatus: string;
  end;

implementation

uses
  ClipBrd, System.Generics.Collections, System.Hash, System.JSON, Vcl.Imaging.pngimage,
  Winapi.GDIPAPI, Winapi.GDIPOBJ,
  unit_ELNPreviewUtils, unit_ELNThemeHelper, System.DateUtils;

{$R *.dfm}

const
  ZOOM_MIN = 0.25;
  ZOOM_MAX = 8.0;


constructor TframeFIBPSViewer.Create(AOwner: TComponent);
begin
  inherited;
  FData := TFIBPSData.Create;
  FZoom := 1.0;
  FToolMode := tmNone;
  FDistHasA := False;
  FDistHasB := False;
  FRoughDragging := False;
  FRoughHasRect := False;
  FHasCursor := False;
  FProfileRow := -1;
  FProfileCol := -1;
  FProfileIsVert := False;
  FFlatten := False;
  FStepDragging := False;
  FHasStep := False;
  FHasWear := False;
  FStepDragTarget := 0;
  FStepDragNext := 1;
  ChartProfile.OnMouseDown := ChartProfileMouseDown;
  ChartProfile.OnMouseUp := ChartProfileMouseUp;
  ChartProfile.OnAfterDraw := ChartProfileAfterDraw;
  CreateMetaPanel;
  BuildColorRamp;
end;

procedure TframeFIBPSViewer.CreateMetaPanel;
var
  PPI: Integer;

  function S(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, PPI, 96);
  end;

begin
  PPI := CurrentPPI;

  FPnlMeta := TPanel.Create(Self);
  FPnlMeta.Parent := pnlCenter;
  FPnlMeta.Align := alRight;
  FPnlMeta.Width := S(180);
  FPnlMeta.BevelOuter := bvNone;
  FPnlMeta.Visible := False;

  FLblMeta := TLabel.Create(Self);
  FLblMeta.Parent := FPnlMeta;
  FLblMeta.AlignWithMargins := True;
  FLblMeta.Margins.Left := S(8);
  FLblMeta.Margins.Top := S(8);
  FLblMeta.Margins.Right := S(8);
  FLblMeta.Margins.Bottom := S(8);
  FLblMeta.Align := alClient;
  FLblMeta.AutoSize := False;
  FLblMeta.WordWrap := True;
  FLblMeta.Caption := '';
end;

function TframeFIBPSViewer.FormatRecipeInfo(const R: TFIBPSRecipe): string;
var
  SL: TStringList;
  ObjName, MethodName: string;
  Magnification: Double;
begin
  Result := '';
  SL := TStringList.Create;
  try
    if R.TryGetMagnification(Magnification) then
      ObjName := FloatToStr(Magnification, TFormatSettings.Invariant) + 'x'
    else
      ObjName := R.ObjectiveType;
    if ObjName <> '' then
      SL.Add('Objective: ' + ObjName);

    case StrToIntDef(R.AnalysisMethod, -1) of
      0: MethodName := 'VSI';
      1: MethodName := 'VSI (enhanced)';
      2: MethodName := 'PSI';
    else
      MethodName := R.AnalysisMethod;
    end;
    if MethodName <> '' then
      SL.Add('Method: ' + MethodName);

    if R.ScanLengthMicrons <> '' then
      SL.Add('Scan length: ' + R.ScanLengthMicrons + ' '#$B5'm');
    if R.BackscanMicrons <> '' then
      SL.Add('Backscan: ' + R.BackscanMicrons + ' '#$B5'm');
    if R.ScanSpeedPct <> '' then
      SL.Add('Scan speed: ' + R.ScanSpeedPct + '%');
    if R.ScanAverages <> '' then
      SL.Add('Averages: ' + R.ScanAverages);
    if (R.AuthorName <> '') and (R.AuthorName <> 'Unknown') then
      SL.Add('Author: ' + R.AuthorName);

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

destructor TframeFIBPSViewer.Destroy;
begin
  FBitmap.Free;
  FData.Free;
  inherited;
end;


function TframeFIBPSViewer.FormatH(Value: Double): string;
begin
  if Abs(Value) < 1.0 then
    Result := Format('%.2f nm', [Value * 1000])
  else
    Result := Format('%.4f %sm', [Value, #$B5]);
end;


procedure TframeFIBPSViewer.BuildColorRamp;
var
  I, Segment, Pos: Integer;
  R, G, B: Byte;
  T: Single;
begin
  for I := 0 to 255 do
  begin
    Segment := I div 64;
    Pos := I mod 64;
    T := Pos / 64.0;

    case Segment of
      0: begin
        R := 0;
        G := Round(255 * T);
        B := 255;
      end;
      1: begin
        R := 0;
        G := 255;
        B := Round(255 * (1 - T));
      end;
      2: begin
        R := Round(255 * T);
        G := 255;
        B := 0;
      end;
    else
      R := 255;
      G := Round(255 * (1 - T));
      B := 0;
    end;

    FPalette[I] := RGB(R, G, B);
  end;
end;

function TframeFIBPSViewer.MapColor(Value, MinVal, MaxVal: Single): TColor;
var
  Idx: Integer;
begin
  if IsNan(Value) then
    Exit(RGB(64, 64, 64));

  if MaxVal <= MinVal then
    Exit(FPalette[128]);

  Idx := Round(255 * (Value - MinVal) / (MaxVal - MinVal));
  if Idx < 0 then Idx := 0;
  if Idx > 255 then Idx := 255;
  Result := FPalette[Idx];
end;


function TframeFIBPSViewer.DisplayHeightAt(X, Y: Integer): Single;
var
  Z: Single;
begin
  Z := FData.HeightAt(X, Y);
  if IsNan(Z) or (not FFlatten) then
    Exit(Z);
  Result := Z - (FPlaneA * X + FPlaneB * Y + FPlaneC);
end;

procedure TframeFIBPSViewer.UpdatePlaneAndRender;
begin
  if (FToolMode = tmStepHeight) and FHasStep then
  begin
    FPlaneA := FStepRes.PlaneA;
    FPlaneB := FStepRes.PlaneB;
    FPlaneC := FStepRes.PlaneC;
  end
  else if (FToolMode = tmWearTrack) and FHasWear then
  begin
    FPlaneA := FWearRes.PlaneA;
    FPlaneB := FWearRes.PlaneB;
    FPlaneC := FWearRes.PlaneC;
  end
  else if FHasWear then
  begin
    FPlaneA := FWearRes.PlaneA;
    FPlaneB := FWearRes.PlaneB;
    FPlaneC := FWearRes.PlaneC;
  end
  else if FHasStep then
  begin
    FPlaneA := FStepRes.PlaneA;
    FPlaneB := FStepRes.PlaneB;
    FPlaneC := FStepRes.PlaneC;
  end
  else
    FData.CalcGlobalPlane(FPlaneA, FPlaneB, FPlaneC);
  RenderBitmap;
  DrawOverlay;
  pbLegend.Invalidate;
end;

procedure TframeFIBPSViewer.RenderBitmap;
var
  X, Y: Integer;
  Row: PRGBTripleArray;
  C: TColor;
  V, MinV, MaxV: Single;
begin
  FreeAndNil(FBitmap);
  if FData.PixW = 0 then Exit;

  if not FFlatten then
  begin
    FDispMinH := FData.MinH;
    FDispMaxH := FData.MaxH;
  end
  else
  begin
    MinV := MaxSingle;
    MaxV := -MaxSingle;
    for Y := 0 to Integer(FData.PixH) - 1 do
      for X := 0 to Integer(FData.PixW) - 1 do
      begin
        V := DisplayHeightAt(X, Y);
        if not IsNan(V) then
        begin
          if FHasWear and (FWearRes.SpikeLimit > 0) and (V > FWearRes.SpikeLimit) then
            Continue;
          if V < MinV then MinV := V;
          if V > MaxV then MaxV := V;
        end;
      end;
    if MinV <= MaxV then
    begin
      FDispMinH := MinV;
      FDispMaxH := MaxV;
    end
    else
    begin
      FDispMinH := FData.MinH;
      FDispMaxH := FData.MaxH;
    end;
  end;

  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf24bit;
  FBitmap.SetSize(FData.PixW, FData.PixH);

  for Y := 0 to Integer(FData.PixH) - 1 do
  begin
    Row := FBitmap.ScanLine[Y];
    for X := 0 to Integer(FData.PixW) - 1 do
    begin
      C := MapColor(DisplayHeightAt(X, Y), FDispMinH, FDispMaxH);
      {$R-}
      Row^[X].rgbtRed := GetRValue(C);
      Row^[X].rgbtGreen := GetGValue(C);
      Row^[X].rgbtBlue := GetBValue(C);
      {$R+}
    end;
  end;

  Image.Picture.Assign(FBitmap);
end;

procedure TframeFIBPSViewer.ApplyZoom;
var
  W, H: Integer;
begin
  if FBitmap = nil then Exit;
  W := Round(FBitmap.Width * FZoom);
  H := Round(FBitmap.Height * FZoom);
  Image.Width := W;
  Image.Height := H;
  Image.Stretch := FZoom <> 1.0;
  CenterImage;
end;

procedure TframeFIBPSViewer.CenterImage;
var
  X, Y: Integer;
begin
  X := (ScrollBox.ClientWidth - Image.Width) div 2;
  Y := (ScrollBox.ClientHeight - Image.Height) div 2;
  if X < 0 then X := 0;
  if Y < 0 then Y := 0;
  Image.Left := X;
  Image.Top := Y;
end;


function TframeFIBPSViewer.ImagePixToData(ImgX, ImgY: Integer;
  out DX, DY: Integer): Boolean;
begin
  if (FBitmap = nil) or (Image.Width = 0) or (Image.Height = 0) then
    Exit(False);

  DX := Round(ImgX * FBitmap.Width / Image.Width);
  DY := Round(ImgY * FBitmap.Height / Image.Height);

  Result := (DX >= 0) and (DX < Integer(FData.PixW)) and
            (DY >= 0) and (DY < Integer(FData.PixH));
end;


procedure TframeFIBPSViewer.LoadFromFile(const AFileName: string);
var
  MetaText, Hash: string;
begin
  Hash := THashSHA2.GetHashStringFromFile(AFileName);
  // Extract Values reloads the shown file before GetKeyValues; a re-parse
  // would discard the step rectangles the user chose on screen.
  if (FLoadedHash <> '') and SameFileName(AFileName, FLoadedPath) and
    (Hash = FLoadedHash) then
  begin
    FContext := Default(TAnalysisContext);
    FResolvedValid := False;
    Exit;
  end;
  FLoadedHash := '';
  FContext := Default(TAnalysisContext);
  FResolvedValid := False;
  FStepUserSet := False;
  FStepFallback := False;
  FStepOrigin := Default(TFIBPSOrigin);

  // Clear old display state BEFORE parsing so a failed load shows blank
  FreeAndNil(FBitmap);
  Image.Picture.Assign(nil);
  FPnlMeta.Visible := False;
  Status.SimpleCaption := '';
  pnlInfo.Caption := '';

  FData.ParseFromFile(AFileName);

  FZoom := 1.0;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
  FRoughDragging := False;
  FStepDragTarget := 0;
  FStepDragNext := 1;
  FHasCursor := False;
  FProfileRow := -1;
  FProfileCol := -1;
  ShowProfilePanel(False);
  btnProfile.Down := False;
  btnDistance.Down := False;
  btnRoughness.Down := False;
  btnStepHeight.Down := False;
  btnWearTrack.Down := False;

  FHasWear := FData.TryCalcWearTrackEx(FWearRes);
  if FHasWear then
  begin
    FHasStep := False;
    FToolMode := tmWearTrack;
    btnWearTrack.Down := True;
    FFlatten := True;
    btnFlatten.Down := True;
    ShowWearTrackResult;
  end
  else
  begin
    FHasStep := FData.TryCalcStepHeightEx(FStepRes);
    if FHasStep then
    begin
      FToolMode := tmStepHeight;
      btnStepHeight.Down := True;
      FFlatten := True;
      btnFlatten.Down := True;
      ShowStepHeightResult;
    end
    else
    begin
      FToolMode := tmNone;
      FFlatten := False;
      btnFlatten.Down := False;
      pnlInfo.Caption := '';
    end;
  end;

  UpdatePlaneAndRender;
  ApplyZoom;
  ApplyChartTheme(ChartProfile);

  MetaText := FormatRecipeInfo(FData.Recipe);
  if MetaText <> '' then
  begin
    FLblMeta.Caption := MetaText;
    FPnlMeta.Visible := True;
  end
  else
    FPnlMeta.Visible := False;

  FStatusBase := Format('%s  |  %d x %d px  |  %.2f x %.2f %sm  |  Height: %s .. %s',
    [ExtractFileName(AFileName), FData.PixW, FData.PixH,
     FData.PhysW, FData.PhysH, #$B5,
     FormatH(FData.MinH), FormatH(FData.MaxH)]);
  Status.SimpleCaption := FStatusBase;
  FLoadedPath := AFileName;
  FLoadedHash := Hash;
end;

procedure TframeFIBPSViewer.ShowError(const Msg: string);
begin
  Status.SimpleCaption := 'Error: ' + Msg;
end;


function TframeFIBPSViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
begin
  if FBitmap <> nil then
    Result := CreateScaledPreview(FBitmap, MaxW, MaxH)
  else
    Result := nil;
end;


procedure TframeFIBPSViewer.ScrollBoxMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  Factor: Double;
begin
  if WheelDelta > 0 then
    Factor := 1.25
  else
    Factor := 0.8;

  FZoom := FZoom * Factor;
  if FZoom < ZOOM_MIN then FZoom := ZOOM_MIN;
  if FZoom > ZOOM_MAX then FZoom := ZOOM_MAX;

  ApplyZoom;
  Handled := True;
end;

procedure TframeFIBPSViewer.ScrollBoxResize(Sender: TObject);
begin
  if FBitmap <> nil then
    CenterImage;
end;

procedure TframeFIBPSViewer.ImageDblClick(Sender: TObject);
begin
  if (FBitmap <> nil) and (ScrollBox.ClientWidth > 0) and (ScrollBox.ClientHeight > 0) then
  begin
    FZoom := Min(ScrollBox.ClientWidth / FBitmap.Width,
                 ScrollBox.ClientHeight / FBitmap.Height);
    if FZoom < ZOOM_MIN then FZoom := ZOOM_MIN;
    if FZoom > ZOOM_MAX then FZoom := ZOOM_MAX;
  end
  else
    FZoom := 1.0;

  ApplyZoom;
  CancelTool;
end;


procedure TframeFIBPSViewer.ImageMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
begin
  if not ImagePixToData(X, Y, DX, DY) then
    Exit;

  FCursorPos := Point(DX, DY);
  FHasCursor := True;

  UpdateStatusCursor(DX, DY);

  if FRoughDragging then
  begin
    FRoughRect.Right := DX;
    FRoughRect.Bottom := DY;
  end
  else if FStepDragTarget = 1 then
    FStepRes.RectA := Rect(Min(FStepDragOrigin.X, DX), Min(FStepDragOrigin.Y, DY),
      Max(FStepDragOrigin.X, DX), Max(FStepDragOrigin.Y, DY))
  else if FStepDragTarget = 2 then
    FStepRes.RectB := Rect(Min(FStepDragOrigin.X, DX), Min(FStepDragOrigin.Y, DY),
      Max(FStepDragOrigin.X, DX), Max(FStepDragOrigin.Y, DY));

  if FToolMode <> tmNone then
    DrawOverlay;
end;

procedure TframeFIBPSViewer.ImageMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
begin
  if ScrollBox.CanFocus then
    ScrollBox.SetFocus;
  if Button <> mbLeft then Exit;
  if not ImagePixToData(X, Y, DX, DY) then Exit;

  case FToolMode of
    tmProfile:
    begin
      if ssShift in Shift then
      begin
        FProfileCol := DX;
        FProfileRow := -1;
        FProfileIsVert := True;
        UpdateProfile(-1, DX);
      end
      else
      begin
        FProfileRow := DY;
        FProfileCol := -1;
        FProfileIsVert := False;
        UpdateProfile(DY, -1);
      end;
      DrawOverlay;
    end;
    tmDistance:
    begin
      if not FDistHasA then
      begin
        FDistPtA := Point(DX, DY);
        FDistHasA := True;
        FDistHasB := False;
        pnlInfo.Caption := Format('  Point A: (%.2f, %.2f) %sm  H = %s  -  click point B',
          [FData.PhysXAt(DX), FData.PhysYAt(DY), #$B5,
           FormatH(FData.HeightAt(DX, DY))]);
        DrawOverlay;
      end
      else
      begin
        FDistPtB := Point(DX, DY);
        FDistHasB := True;
        ShowDistanceResult;
        DrawOverlay;
      end;
    end;
    tmRoughness:
    begin
      FRoughOrigin := Point(DX, DY);
      FRoughRect := Rect(DX, DY, DX, DY);
      FRoughDragging := True;
      FRoughHasRect := False;
    end;
    tmStepHeight:
    begin
      FStepDragOrigin := Point(DX, DY);
      if FHasStep then
      begin
        if PtInRect(FStepRes.RectA, FStepDragOrigin) then
          FStepDragTarget := 1
        else if PtInRect(FStepRes.RectB, FStepDragOrigin) then
          FStepDragTarget := 2
        else
          FStepDragTarget := FStepDragNext;
      end
      else
        FStepDragTarget := 1;
    end;
  end;
end;

procedure TframeFIBPSViewer.ImageMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
  Ra, Rq, Rz: Double;
  R: TRect;
begin
  if (Button = mbLeft) and FRoughDragging then
  begin
    FRoughDragging := False;
    if ImagePixToData(X, Y, DX, DY) then
    begin
      FRoughRect.Right := DX;
      FRoughRect.Bottom := DY;
    end;

    R := FRoughRect;
    if R.Left > R.Right then
    begin
      DX := R.Left;
      R.Left := R.Right;
      R.Right := DX;
    end;
    if R.Top > R.Bottom then
    begin
      DY := R.Top;
      R.Top := R.Bottom;
      R.Bottom := DY;
    end;
    FRoughRect := R;

    if (R.Right > R.Left) and (R.Bottom > R.Top) then
    begin
      FRoughHasRect := True;
      CalcRoughness(R, Ra, Rq, Rz);
      pnlInfo.Caption := Format('  Roughness:  Ra = %s  |  Rq = %s  |  Rz = %s',
        [FormatH(Ra), FormatH(Rq), FormatH(Rz)]);
    end;
    DrawOverlay;
  end
  else if (Button = mbLeft) and (FStepDragTarget in [1, 2]) then
  begin
    if ImagePixToData(X, Y, DX, DY) then
    begin
      R := Rect(Min(FStepDragOrigin.X, DX), Min(FStepDragOrigin.Y, DY),
        Max(FStepDragOrigin.X, DX), Max(FStepDragOrigin.Y, DY));
      if (R.Right > R.Left + 2) and (R.Bottom > R.Top + 2) then
      begin
        if FStepDragTarget = 1 then
        begin
          FStepRes.RectA := R;
          FStepDragNext := 2;
        end
        else
        begin
          FStepRes.RectB := R;
          FStepDragNext := 1;
        end;
        if FData.CalcStepFromRects(FStepRes.RectA, FStepRes.RectB, FStepRes) then
        begin
          FHasStep := True;
          FStepUserSet := True;
          FStepFallback := False;
          FStepOrigin := Default(TFIBPSOrigin);
          UpdatePlaneAndRender;
          ShowStepHeightResult;
          ApplySharedRegions;
        end;
      end;
    end;
    FStepDragTarget := 0;
    DrawOverlay;
  end;
end;

procedure TframeFIBPSViewer.UpdateStatusCursor(DX, DY: Integer);
var
  H: Single;
begin
  H := DisplayHeightAt(DX, DY);
  if IsNan(H) then
    Status.SimpleCaption := Format('%s  |  (%d, %d) = NaN', [FStatusBase, DX, DY])
  else
    Status.SimpleCaption := Format('%s  |  (%.2f, %.2f) %sm  H = %s',
      [FStatusBase, FData.PhysXAt(DX), FData.PhysYAt(DY), #$B5, FormatH(H)]);
end;


procedure TframeFIBPSViewer.RegionDetrend(var YVals: array of Double;
  const XVals: array of Double; Count: Integer);
var
  I: Integer;
  SumX, SumY, SumXY, SumX2, Slope, Intercept, N: Double;

  function InRegionA(X: Double): Boolean;
  begin
    Result := FStepRegionA.HasRegion
      and (X >= FStepRegionA.XMin) and (X <= FStepRegionA.XMax);
  end;

begin
  // Fit baseline through Region A only (reference plane)
  N := 0; SumX := 0; SumY := 0; SumXY := 0; SumX2 := 0;
  for I := 0 to Count - 1 do
  begin
    if InRegionA(XVals[I]) then
    begin
      N := N + 1;
      SumX := SumX + XVals[I];
      SumY := SumY + YVals[I];
      SumXY := SumXY + XVals[I] * YVals[I];
      SumX2 := SumX2 + XVals[I] * XVals[I];
    end;
  end;
  if N < 2 then Exit;
  if Abs(N * SumX2 - SumX * SumX) < 1E-30 then Exit;
  Slope := (N * SumXY - SumX * SumY) / (N * SumX2 - SumX * SumX);
  Intercept := (SumY - Slope * SumX) / N;
  for I := 0 to Count - 1 do
    YVals[I] := YVals[I] - (Slope * XVals[I] + Intercept);
end;

procedure TframeFIBPSViewer.UpdateProfile(Row, Col: Integer);
var
  I, Count: Integer;
  XArr, YArr: array of Double;
begin
  ChartProfile.AutoRepaint := False;
  try
    serProfileH.Clear;
    serProfileV.Clear;
    serWearMean.Clear;
    serWearUpper.Clear;
    serWearLower.Clear;
    ChartProfile.LeftAxis.Automatic := True;
    ChartProfile.BottomAxis.Automatic := True;

    if Row >= 0 then
    begin
      Count := Integer(FData.PixW);
      SetLength(XArr, Count);
      SetLength(YArr, Count);
      for I := 0 to Count - 1 do
      begin
        XArr[I] := FData.PhysXAt(I);
        YArr[I] := DisplayHeightAt(I, Row);
      end;
      if FFlatten and FStepRegionA.HasRegion then
        RegionDetrend(YArr, XArr, Count);
      for I := 0 to Count - 1 do
        serProfileH.AddXY(XArr[I], YArr[I]);
    end;

    if Col >= 0 then
    begin
      Count := Integer(FData.PixH);
      SetLength(XArr, Count);
      SetLength(YArr, Count);
      for I := 0 to Count - 1 do
      begin
        XArr[I] := FData.PhysYAt(I);
        YArr[I] := DisplayHeightAt(Col, I);
      end;
      if FFlatten and FStepRegionA.HasRegion then
        RegionDetrend(YArr, XArr, Count);
      for I := 0 to Count - 1 do
        serProfileV.AddXY(XArr[I], YArr[I]);
    end;
  finally
    ApplyVerticalMargins;
    ChartProfile.AutoRepaint := True;
    ChartProfile.Repaint;
  end;
end;

procedure TframeFIBPSViewer.ApplyVerticalMargins;
var
  I, J: Integer;
  Y, Lo, Hi, Pad: Double;
begin
  Lo := MaxDouble;
  Hi := -MaxDouble;
  for I := 0 to ChartProfile.SeriesCount - 1 do
    for J := 0 to ChartProfile.Series[I].Count - 1 do
    begin
      Y := ChartProfile.Series[I].YValue[J];
      if IsNan(Y) or IsInfinite(Y) then
        Continue;
      Lo := Min(Lo, Y);
      Hi := Max(Hi, Y);
    end;
  if Lo > Hi then
    Exit;
  Pad := 0.1 * (Hi - Lo);
  if Pad <= 0 then
    Pad := Max(0.1 * Abs(Hi), 1E-3);
  ChartProfile.LeftAxis.SetMinMax(Lo - Pad, Hi + Pad);
end;

procedure TframeFIBPSViewer.ShowProfilePanel(AVisible: Boolean);
begin
  ChartProfile.Visible := AVisible;
  SplitterProfile.Visible := AVisible;
  btnCopyData.Enabled := AVisible;
end;


procedure TframeFIBPSViewer.DrawOverlay;
var
  Tmp: TBitmap;
  Cvs: TCanvas;
  P1, P2: TPoint;
  R: TRect;
  Swap: Integer;
begin
  if FBitmap = nil then Exit;

  // Work on a copy so FBitmap stays clean
  Tmp := TBitmap.Create;
  try
    Tmp.Assign(FBitmap);
    Cvs := Tmp.Canvas;
    Cvs.Pen.Width := 1;
    Cvs.Pen.Style := psSolid;
    Cvs.Pen.Mode := pmCopy;
    Cvs.Brush.Style := bsClear;

    if (FToolMode <> tmNone) and FHasCursor then
    begin
      Cvs.Pen.Color := clWhite;
      Cvs.MoveTo(0, FCursorPos.Y);
      Cvs.LineTo(Tmp.Width, FCursorPos.Y);
      Cvs.MoveTo(FCursorPos.X, 0);
      Cvs.LineTo(FCursorPos.X, Tmp.Height);
    end;

    if FToolMode = tmProfile then
    begin
      Cvs.Pen.Color := clAqua;
      Cvs.Pen.Style := psDash;
      if (FProfileRow >= 0) then
      begin
        Cvs.MoveTo(0, FProfileRow);
        Cvs.LineTo(Tmp.Width, FProfileRow);
      end;
      if (FProfileCol >= 0) then
      begin
        Cvs.MoveTo(FProfileCol, 0);
        Cvs.LineTo(FProfileCol, Tmp.Height);
      end;
      Cvs.Pen.Style := psSolid;
    end;

    if (FToolMode = tmStepHeight) and FHasStep then
    begin
      Cvs.Pen.Width := 2;
      Cvs.Brush.Style := bsClear;
      Cvs.Pen.Color := clAqua;
      Cvs.Rectangle(FStepRes.RectA.Left, FStepRes.RectA.Top,
        FStepRes.RectA.Right, FStepRes.RectA.Bottom);
      Cvs.Pen.Color := $004080FF;
      Cvs.Rectangle(FStepRes.RectB.Left, FStepRes.RectB.Top,
        FStepRes.RectB.Right, FStepRes.RectB.Bottom);
      Cvs.Pen.Width := 1;
    end;

    if (FToolMode = tmWearTrack) and FHasWear then
    begin
      Cvs.Pen.Width := 2;
      Cvs.Pen.Color := clFuchsia;
      Cvs.MoveTo(FWearRes.Edge1Start.X, FWearRes.Edge1Start.Y);
      Cvs.LineTo(FWearRes.Edge1End.X, FWearRes.Edge1End.Y);
      Cvs.MoveTo(FWearRes.Edge2Start.X, FWearRes.Edge2Start.Y);
      Cvs.LineTo(FWearRes.Edge2End.X, FWearRes.Edge2End.Y);
      Cvs.Pen.Width := 1;
    end;

    if FDistHasA then
    begin
      P1 := FDistPtA;
      Cvs.Pen.Color := clLime;
      Cvs.Ellipse(P1.X - 3, P1.Y - 3, P1.X + 4, P1.Y + 4);
    end;
    if FDistHasA and FDistHasB then
    begin
      P1 := FDistPtA;
      P2 := FDistPtB;
      Cvs.Pen.Color := clLime;
      Cvs.MoveTo(P1.X, P1.Y);
      Cvs.LineTo(P2.X, P2.Y);
      Cvs.Ellipse(P2.X - 3, P2.Y - 3, P2.X + 4, P2.Y + 4);
    end;

    if FRoughHasRect or FRoughDragging then
    begin
      R := FRoughRect;
      if R.Left > R.Right then
      begin
        Swap := R.Left;
        R.Left := R.Right;
        R.Right := Swap;
      end;
      if R.Top > R.Bottom then
      begin
        Swap := R.Top;
        R.Top := R.Bottom;
        R.Bottom := Swap;
      end;
      Cvs.Pen.Color := clYellow;
      Cvs.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
    end;

    Image.Picture.Graphic := Tmp;
  finally
    Tmp.Free;
  end;
end;


procedure TframeFIBPSViewer.ShowDistanceResult;
var
  X1, Y1, X2, Y2, H1, H2: Single;
  DXY, DH, D3D: Double;
begin
  X1 := FData.PhysXAt(FDistPtA.X);
  Y1 := FData.PhysYAt(FDistPtA.Y);
  X2 := FData.PhysXAt(FDistPtB.X);
  Y2 := FData.PhysYAt(FDistPtB.Y);
  H1 := FData.HeightAt(FDistPtA.X, FDistPtA.Y);
  H2 := FData.HeightAt(FDistPtB.X, FDistPtB.Y);

  DXY := Sqrt(Sqr(X2 - X1) + Sqr(Y2 - Y1));
  DH := H2 - H1;
  D3D := Sqrt(Sqr(DXY) + Sqr(DH));

  pnlInfo.Caption := Format('  Distance: XY = %s  |  dH = %s  |  3D = %s',
    [FormatH(DXY), FormatH(DH), FormatH(D3D)]);
end;


procedure TframeFIBPSViewer.CalcRoughness(const R: TRect; out Ra, Rq, Rz: Double);
var
  X, Y, N: Integer;
  H, Sum, SumSq, Mean, HMin, HMax: Double;
begin
  Ra := 0; Rq := 0; Rz := 0;
  Sum := 0;
  N := 0;

  for Y := R.Top to R.Bottom do
    for X := R.Left to R.Right do
    begin
      H := FData.HeightAt(X, Y);
      if not IsNan(H) then
      begin
        Sum := Sum + H;
        Inc(N);
      end;
    end;

  if N = 0 then Exit;
  Mean := Sum / N;

  Sum := 0;
  SumSq := 0;
  HMin := MaxDouble;
  HMax := -MaxDouble;
  for Y := R.Top to R.Bottom do
    for X := R.Left to R.Right do
    begin
      H := FData.HeightAt(X, Y);
      if not IsNan(H) then
      begin
        Sum := Sum + Abs(H - Mean);
        SumSq := SumSq + Sqr(H - Mean);
        if H < HMin then HMin := H;
        if H > HMax then HMax := H;
      end;
    end;

  Ra := Sum / N;
  Rq := Sqrt(SumSq / N);
  Rz := HMax - HMin;
end;


procedure TframeFIBPSViewer.pbLegendPaint(Sender: TObject);
var
  Graphics: TGPGraphics;
  Brush: TGPSolidBrush;
  Font: TGPFont;
  FontFamily: TGPFontFamily;
  StringFmt: TGPStringFormat;
  R: TGPRectF;
  GradH, I, Y: Integer;
  C: TColor;
  Idx: Integer;
  LabelText: string;
  Cvs: TCanvas;
begin
  if FData.PixW = 0 then Exit;

  // Draw gradient strip using fast GDI (no per-pixel GDI+ object overhead)
  GradH := pbLegend.Height - 40;
  if GradH < 10 then GradH := 10;

  Cvs := pbLegend.Canvas;
  for I := 0 to GradH - 1 do
  begin
    Idx := Round(255 * (1 - I / GradH));
    if Idx < 0 then Idx := 0;
    if Idx > 255 then Idx := 255;
    C := FPalette[Idx];
    Y := 20 + I;
    Cvs.Pen.Color := C;
    Cvs.MoveTo(4, Y);
    Cvs.LineTo(28, Y);
  end;

  Graphics := TGPGraphics.Create(Cvs.Handle);
  try
    Graphics.SetTextRenderingHint(TextRenderingHintAntiAlias);

    FontFamily := TGPFontFamily.Create('Segoe UI');
    Font := TGPFont.Create(FontFamily, 8, FontStyleRegular, UnitPoint);
    StringFmt := TGPStringFormat.Create;
    StringFmt.SetAlignment(StringAlignmentCenter);

    Brush := TGPSolidBrush.Create(MakeColor(255, 0, 0, 0));
    try
      LabelText := FormatH(FDispMaxH);
      R := MakeRect(0.0, 2.0, pbLegend.Width * 1.0, 16.0);
      Graphics.DrawString(LabelText, Length(LabelText), Font, R, StringFmt, Brush);

      LabelText := FormatH(FDispMinH);
      R := MakeRect(0.0, (20 + GradH + 2) * 1.0, pbLegend.Width * 1.0, 16.0);
      Graphics.DrawString(LabelText, Length(LabelText), Font, R, StringFmt, Brush);
    finally
      Brush.Free;
    end;

    StringFmt.Free;
    Font.Free;
    FontFamily.Free;
  finally
    Graphics.Free;
  end;
end;


procedure TframeFIBPSViewer.CancelTool;
begin
  FToolMode := tmNone;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
  FRoughDragging := False;
  FHasCursor := False;
  FProfileRow := -1;
  FProfileCol := -1;
  FStepRegionA.HasRegion := False;
  FStepRegionB.HasRegion := False;
  FStepDragging := False;
  FStepDragTarget := 0;
  btnProfile.Down := False;
  btnDistance.Down := False;
  btnRoughness.Down := False;
  btnStepHeight.Down := False;
  btnWearTrack.Down := False;
  btnFlatten.Down := False;
  FFlatten := False;
  ChartProfile.AllowZoom := True;
  ShowProfilePanel(False);
  pnlInfo.Caption := '';
  UpdatePlaneAndRender;
end;

procedure TframeFIBPSViewer.CMDialogKey(var Message: TCMDialogKey);
begin
  if (Message.CharCode = VK_ESCAPE) and (FToolMode <> tmNone) then
  begin
    CancelTool;
    Message.Result := 1;
  end
  else
    inherited;
end;


procedure TframeFIBPSViewer.btnProfileClick(Sender: TObject);
begin
  if btnProfile.Down then
  begin
    FToolMode := tmProfile;
    UpdateProfile(-1, -1);
    ShowProfilePanel(True);
  end
  else
  begin
    FToolMode := tmNone;
    FProfileRow := -1;
    FProfileCol := -1;
    ShowProfilePanel(False);
  end;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
  pnlInfo.Caption := '';
  DrawOverlay;
end;

procedure TframeFIBPSViewer.btnDistanceClick(Sender: TObject);
begin
  if btnDistance.Down then
  begin
    FToolMode := tmDistance;
    ShowProfilePanel(False);
  end
  else
    FToolMode := tmNone;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
  pnlInfo.Caption := '';
  DrawOverlay;
end;

procedure TframeFIBPSViewer.btnRoughnessClick(Sender: TObject);
begin
  if btnRoughness.Down then
  begin
    FToolMode := tmRoughness;
    ShowProfilePanel(False);
  end
  else
    FToolMode := tmNone;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
  pnlInfo.Caption := '';
  DrawOverlay;
end;

procedure TframeFIBPSViewer.btnFlattenClick(Sender: TObject);
begin
  FFlatten := btnFlatten.Down;
  UpdatePlaneAndRender;
  if FProfileRow >= 0 then
    UpdateProfile(FProfileRow, -1)
  else if FProfileCol >= 0 then
    UpdateProfile(-1, FProfileCol);
end;

procedure TframeFIBPSViewer.EnsureStepResult;
var
  W, H: Integer;
  RA, RB: TRect;
begin
  if not FHasStep then
    FHasStep := FData.TryCalcStepHeightEx(FStepRes);
  if (not FHasStep) and (FData.PixW >= 16) and (FData.PixH >= 16) then
  begin
    W := Integer(FData.PixW);
    H := Integer(FData.PixH);
    RA := Rect(W div 8, H div 6, (W * 3) div 8, (H * 5) div 6);
    RB := Rect((W * 5) div 8, H div 6, (W * 7) div 8, (H * 5) div 6);
    FHasStep := FData.CalcStepFromRects(RA, RB, FStepRes);
    if FHasStep then
    begin
      FStepUserSet := True;
      FStepFallback := True;
      FStepOrigin := Default(TFIBPSOrigin);
      ApplySharedRegions;
    end;
  end;
end;

procedure TframeFIBPSViewer.btnStepHeightClick(Sender: TObject);
begin
  if btnStepHeight.Down then
  begin
    FToolMode := tmStepHeight;
    ShowProfilePanel(False);
    EnsureStepResult;
    FFlatten := True;
    btnFlatten.Down := True;
    UpdatePlaneAndRender;
    if FHasStep then
      ShowStepHeightResult
    else
      pnlInfo.Caption := '  No two-level step detected  |  Drag on the map to set Rect A and Rect B';
  end
  else
  begin
    FToolMode := tmNone;
    pnlInfo.Caption := '';
    DrawOverlay;
  end;
  FStepDragTarget := 0;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
end;

procedure TframeFIBPSViewer.btnWearTrackClick(Sender: TObject);
begin
  if btnWearTrack.Down then
  begin
    FToolMode := tmWearTrack;
    ShowProfilePanel(False);
    if not FHasWear then
      FHasWear := FData.TryCalcWearTrackEx(FWearRes);
    if FHasWear then
    begin
      FFlatten := True;
      btnFlatten.Down := True;
      UpdatePlaneAndRender;
      ShowWearTrackResult;
    end
    else
    begin
      pnlInfo.Caption := '  No wear groove detected on this surface';
      DrawOverlay;
    end;
  end
  else
  begin
    FToolMode := tmNone;
    pnlInfo.Caption := '';
    ShowProfilePanel(False);
    DrawOverlay;
  end;
  FStepDragTarget := 0;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
end;


procedure TframeFIBPSViewer.ChartProfileMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button <> mbLeft) or not ((FToolMode = tmStepHeight) or FFlatten) then Exit;
  FStepDragStart := ChartProfile.BottomAxis.CalcPosPoint(X);
  FStepDragging := True;
end;

procedure TframeFIBPSViewer.ChartProfileMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  XEnd, XMin, XMax: Double;
begin
  if (Button <> mbLeft) or not FStepDragging then Exit;
  FStepDragging := False;

  XEnd := ChartProfile.BottomAxis.CalcPosPoint(X);
  XMin := Min(FStepDragStart, XEnd);
  XMax := Max(FStepDragStart, XEnd);

  if Abs(XMax - XMin) < 1E-6 then Exit;

  if not FStepRegionA.HasRegion then
  begin
    FStepRegionA.XMin := XMin;
    FStepRegionA.XMax := XMax;
    FStepRegionA.HasRegion := True;
  end
  else if not FStepRegionB.HasRegion then
  begin
    FStepRegionB.XMin := XMin;
    FStepRegionB.XMax := XMax;
    FStepRegionB.HasRegion := True;
  end
  else
  begin
    if FToolMode = tmStepHeight then
    begin
      FStepRegionB.XMin := XMin;
      FStepRegionB.XMax := XMax;
    end
    else
    begin
      FStepRegionB.HasRegion := False;
      FStepRegionA.XMin := XMin;
      FStepRegionA.XMax := XMax;
    end;
  end;

  if FFlatten then
  begin
    if FProfileRow >= 0 then
      UpdateProfile(FProfileRow, -1)
    else if FProfileCol >= 0 then
      UpdateProfile(-1, FProfileCol);
  end;

  if FStepRegionA.HasRegion then
    CalcRegionAverage(FStepRegionA.XMin, FStepRegionA.XMax, FStepRegionA.AvgH, FStepRegionA.Count);
  if FStepRegionA.HasRegion and FStepRegionB.HasRegion then
  begin
    CalcRegionAverage(FStepRegionB.XMin, FStepRegionB.XMax, FStepRegionB.AvgH, FStepRegionB.Count);
    ShowStepHeightResult;
  end
  else if FStepRegionA.HasRegion then
    pnlInfo.Caption := Format('  Region A: %s (n=%d)  '#8212'  now drag Region B',
      [FormatH(FStepRegionA.AvgH), FStepRegionA.Count]);

  ChartProfile.Repaint;
end;

procedure TframeFIBPSViewer.CalcRegionAverage(XMin, XMax: Double;
  out AvgH: Double; out Count: Integer);
var
  I: Integer;
  Ser: TChartSeries;
  Sum: Double;
begin
  AvgH := 0;
  Count := 0;
  Sum := 0;

  if serProfileH.Count > 0 then
    Ser := serProfileH
  else if serProfileV.Count > 0 then
    Ser := serProfileV
  else
    Exit;

  for I := 0 to Ser.Count - 1 do
  begin
    if (Ser.XValue[I] >= XMin) and (Ser.XValue[I] <= XMax) then
    begin
      Sum := Sum + Ser.YValue[I];
      Inc(Count);
    end;
  end;

  if Count > 0 then
    AvgH := Sum / Count;
end;

procedure TframeFIBPSViewer.ShowStepHeightResult;
begin
  if FHasStep then
    pnlInfo.Caption := Format(
      '  Step Height: %s '#177' %s  |  Rect A: %s (n=%d)  |  Rect B: %s (n=%d)  (drag map to adjust)',
      [FormatH(FStepRes.StepHeight), FormatH(FStepRes.StepHeightStd),
       FormatH(FStepRes.MeanA), FStepRes.CountA,
       FormatH(FStepRes.MeanB), FStepRes.CountB])
  else if FStepRegionA.HasRegion and FStepRegionB.HasRegion then
    pnlInfo.Caption := Format('  Step Height: %s  |  Region A: %s (n=%d)  |  Region B: %s (n=%d)',
      [FormatH(Abs(FStepRegionB.AvgH - FStepRegionA.AvgH)),
       FormatH(FStepRegionA.AvgH), FStepRegionA.Count,
       FormatH(FStepRegionB.AvgH), FStepRegionB.Count]);
end;

procedure TframeFIBPSViewer.ShowWearTrackResult;
begin
  if not FHasWear then
    Exit;
  pnlInfo.Caption := Format(
    '  Wear Area: %.2f '#177' %.2f %sm'#178' (SD of %d rows along the track)',
    [FWearRes.WearArea, FWearRes.WearAreaStd, #$B5, FWearRes.RowCount]);
  ShowWearProfile;
end;

procedure TframeFIBPSViewer.ShowWearProfile;
var
  I: Integer;
  M, S: Double;
begin
  ChartProfile.AutoRepaint := False;
  try
    serProfileH.Clear;
    serProfileV.Clear;
    serWearMean.Clear;
    serWearUpper.Clear;
    serWearLower.Clear;
    ChartProfile.LeftAxis.Automatic := True;
    ChartProfile.BottomAxis.Automatic := True;
    for I := 0 to High(FWearRes.ProfileX) do
    begin
      M := FWearRes.ProfileMean[I];
      S := FWearRes.ProfileStd[I];
      if IsNan(M) then
        Continue;
      serWearMean.AddXY(FWearRes.ProfileX[I], M);
      serWearUpper.AddXY(FWearRes.ProfileX[I], M + S);
      serWearLower.AddXY(FWearRes.ProfileX[I], M - S);
    end;
  finally
    ApplyVerticalMargins;
    ChartProfile.AutoRepaint := True;
  end;
  ShowProfilePanel(True);
  ChartProfile.Repaint;
end;

procedure TframeFIBPSViewer.ChartProfileAfterDraw(Sender: TObject);

  procedure DrawRegion(const Rgn: TStepRegion; AColor: TColor);
  var
    X1, X2, YAvg: Integer;
  begin
    if not Rgn.HasRegion then Exit;
    X1 := ChartProfile.BottomAxis.CalcPosValue(Rgn.XMin);
    X2 := ChartProfile.BottomAxis.CalcPosValue(Rgn.XMax);
    YAvg := ChartProfile.LeftAxis.CalcPosValue(Rgn.AvgH);

    with ChartProfile.Canvas do
    begin
      Brush.Color := AColor;
      Brush.Style := bsBDiagonal;
      Pen.Style := psClear;
      Rectangle(Rect(X1, ChartProfile.ChartRect.Top, X2, ChartProfile.ChartRect.Bottom));

      Pen.Style := psSolid;
      Pen.Color := AColor;
      Pen.Width := 2;
      MoveTo(X1, YAvg);
      LineTo(X2, YAvg);
      Pen.Width := 1;

      Brush.Style := bsClear;
      Pen.Style := psDot;
      Rectangle(Rect(X1, ChartProfile.ChartRect.Top, X2, ChartProfile.ChartRect.Bottom));
      Pen.Style := psSolid;
    end;
  end;

begin
  if (FToolMode = tmWearTrack) and FHasWear then
    with ChartProfile.Canvas do
    begin
      Pen.Style := psDash;
      Pen.Color := clFuchsia;
      Pen.Width := 1;
      MoveTo(ChartProfile.BottomAxis.CalcPosValue(FWearRes.Edge1X), ChartProfile.ChartRect.Top);
      LineTo(ChartProfile.BottomAxis.CalcPosValue(FWearRes.Edge1X), ChartProfile.ChartRect.Bottom);
      MoveTo(ChartProfile.BottomAxis.CalcPosValue(FWearRes.Edge2X), ChartProfile.ChartRect.Top);
      LineTo(ChartProfile.BottomAxis.CalcPosValue(FWearRes.Edge2X), ChartProfile.ChartRect.Bottom);
      Pen.Style := psSolid;
    end;
  if (FToolMode <> tmStepHeight) and not FFlatten then Exit;
  DrawRegion(FStepRegionA, clBlue);
  DrawRegion(FStepRegionB, clRed);
end;


procedure TframeFIBPSViewer.HeightDataToText(List: TStringList);
var
  X, Y: Integer;
  Line: string;
begin
  List.Add('# FIBPS Height Data Export');
  List.Add(Format('# File: %s', [ExtractFileName(FData.FileName)]));
  List.Add(Format('# Dimensions: %d x %d px', [FData.PixW, FData.PixH]));
  List.Add(Format('# Physical: %.4f x %.4f um', [FData.PhysW, FData.PhysH]));
  List.Add(Format('# Height range: %.4f .. %.4f um', [FData.MinH, FData.MaxH]));
  List.Add('#');

  Line := 'Y\X';
  for X := 0 to Integer(FData.PixW) - 1 do
    Line := Line + #9 + FloatToStrF(FData.PhysXAt(X), ffFixed, 10, 4);
  List.Add(Line);

  for Y := 0 to Integer(FData.PixH) - 1 do
  begin
    Line := FloatToStrF(FData.PhysYAt(Y), ffFixed, 10, 4);
    for X := 0 to Integer(FData.PixW) - 1 do
      Line := Line + #9 + FloatToStrF(FData.HeightAt(X, Y), ffFixed, 10, 4);
    List.Add(Line);
  end;
end;

procedure TframeFIBPSViewer.WearProfileToText(List: TStringList);
var
  I: Integer;
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Invariant;
  List.Add('# FIBPS Wear Profile Export');
  List.Add(Format('# File: %s', [ExtractFileName(FData.FileName)]));
  List.Add(Format('# Wear area: %.4f +- %.4f um2 (mean and SD of %d row profiles)',
    [FWearRes.WearArea, FWearRes.WearAreaStd, FWearRes.RowCount], FS));
  List.Add(Format('# Groove edges (mid-track): %.4f um, %.4f um',
    [FWearRes.Edge1X, FWearRes.Edge2X], FS));
  List.Add('# Height is relative to the levelled surface outside the groove. Missing');
  List.Add('# pixels are filled linearly along each row before averaging.');
  List.Add('# n_measured = measured pixels in the column, of n_rows.');
  List.Add(Format('# n_rows: %d', [FWearRes.RowCount]));
  List.Add('x_um'#9'mean_um'#9'sd_um'#9'n_measured');
  for I := 0 to High(FWearRes.ProfileX) do
    List.Add(Format('%.4f'#9'%.5f'#9'%.5f'#9'%d', [FWearRes.ProfileX[I],
      FWearRes.ProfileMean[I], FWearRes.ProfileStd[I], FWearRes.ProfileMeasured[I]], FS));
end;

procedure TframeFIBPSViewer.btnCopyImageClick(Sender: TObject);
begin
  if FBitmap <> nil then
    Clipboard.Assign(FBitmap);
end;

procedure TframeFIBPSViewer.btnCopyDataClick(Sender: TObject);
const
  UM = #$00B5'm';
var
  List: TStringList;
  Ser: TChartSeries;
  I: Integer;
  Where: string;

  function Cell(V: Double): string;
  begin
    if IsNan(V) then
      Result := ''
    else
      Result := FloatToStrF(V, ffGeneral, 7, 0);
  end;

begin
  List := TStringList.Create;
  try
    if serWearMean.Count > 0 then
    begin
      List.Add('Position'#9'Mean height'#9'Mean - SD'#9'Mean + SD');
      List.Add(UM + #9 + UM + #9 + UM + #9 + UM);
      List.Add(Format('%s'#9'mean of %d row profiles'#9'SD along the track'#9 +
        'SD along the track', [ExtractFileName(FData.FileName), FWearRes.RowCount]));
      for I := 0 to High(FWearRes.ProfileX) do
        List.Add(Cell(FWearRes.ProfileX[I]) + #9 + Cell(FWearRes.ProfileMean[I]) + #9 +
          Cell(FWearRes.ProfileMean[I] - FWearRes.ProfileStd[I]) + #9 +
          Cell(FWearRes.ProfileMean[I] + FWearRes.ProfileStd[I]));
    end
    else
    begin
      if serProfileH.Count > 0 then
      begin
        Ser := serProfileH;
        Where := Format('row at y = %.2f %s', [FData.PhysYAt(FProfileRow), UM]);
      end
      else if serProfileV.Count > 0 then
      begin
        Ser := serProfileV;
        Where := Format('column at x = %.2f %s', [FData.PhysXAt(FProfileCol), UM]);
      end
      else
        Exit;
      if FFlatten then
        Where := Where + ', flattened';
      List.Add('Position'#9'Height');
      List.Add(UM + #9 + UM);
      List.Add(ExtractFileName(FData.FileName) + #9 + Where);
      for I := 0 to Ser.Count - 1 do
        List.Add(Cell(Ser.XValue[I]) + #9 + Cell(Ser.YValue[I]));
    end;
    Clipboard.AsText := List.Text;
  finally
    List.Free;
  end;
end;

procedure TframeFIBPSViewer.btnSaveClick(Sender: TObject);
var
  Png: TPngImage;
  List: TStringList;
begin
  if not dlgSave.Execute then Exit;

  if dlgSave.FilterIndex = 3 then
  begin
    if not FHasWear then
    begin
      MessageDlg('No wear groove was detected on this surface.', mtInformation, [mbOK], 0);
      Exit;
    end;
    List := TStringList.Create;
    try
      WearProfileToText(List);
      List.SaveToFile(dlgSave.FileName);
    finally
      List.Free;
    end;
  end
  else if dlgSave.FilterIndex = 2 then
  begin
    List := TStringList.Create;
    try
      HeightDataToText(List);
      List.SaveToFile(dlgSave.FileName);
    finally
      List.Free;
    end;
  end
  else
  begin
    if FBitmap = nil then Exit;
    Png := TPngImage.Create;
    try
      Png.Assign(FBitmap);
      Png.SaveToFile(dlgSave.FileName);
    finally
      Png.Free;
    end;
  end;
end;

function TframeFIBPSViewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  R: TFIBPSRecipe;

  procedure Add(const AName: string; AValue: Double; const AUnits: string;
    ARecType: TPluginRecType; AIsKey: Boolean = False);
  begin
    KV.Name := AName;
    KV.Value := AValue;
    KV.Units := AUnits;
    KV.RecType := ARecType;
    KV.IsKey := AIsKey;
    List.Add(KV);
  end;

  function TryStrToVal(const S: string; out V: Double): Boolean;
  var
    Code: Integer;
  begin
    Val(S, V, Code);
    Result := Code = 0;
  end;

var
  V: Double;
  Step: TFIBPSStepAnalysis;
begin
  Result := nil;
  if FData = nil then
    Exit;

  R := FData.Recipe;
  List := TList<TPluginKeyValue>.Create;
  try
    if R.TryGetMagnification(V) then
      Add('Magnification', V, 'x', prCondition, True);
    if TryStrToVal(R.ScanLengthMicrons, V) then
      Add('Scan Range', V, 'um', prCondition, True)
    else
      Add('Scan Range', FData.PhysW, 'um', prCondition, True);

    Add('Scan Width', FData.PhysW, 'um', prCondition);
    Add('Scan Height', FData.PhysH, 'um', prCondition);
    Add('Min Height', FData.MinH, 'um', prResult);
    Add('Max Height', FData.MaxH, 'um', prResult);
    Add('Height Range', FData.MaxH - FData.MinH, 'um', prResult);

    if TryStrToVal(R.BackscanMicrons, V) then
      Add('Backscan', V, 'um', prCondition);
    if TryStrToVal(R.ScanAverages, V) then
      Add('Scan Averages', V, '', prCondition);


    if StepForExtraction(Step) then
    begin
      Add(FIBPSKeyStep, Step.Step.StepHeight, 'um', prResult, True);
      Add(FIBPSKeyStepStd, Step.Step.StepHeightStd, 'um', prResult, False);
    end
    else if FHasWear then
    begin
      Add('Wear Area', FWearRes.WearArea, 'um2', prResult, True);
      Add('Wear Area STD', FWearRes.WearAreaStd, 'um2', prResult, False);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TframeFIBPSViewer.ResolvedStep: TFIBPSStepAnalysis;
begin
  if not FResolvedValid then
  begin
    FResolved := ResolveFIBPSStep(FData, FContext);
    FResolvedValid := True;
  end;
  Result := FResolved;
end;

function TframeFIBPSViewer.StepForExtraction(out Analysis: TFIBPSStepAnalysis): Boolean;
begin
  Analysis := Default(TFIBPSStepAnalysis);
  if FData.PixW = 0 then
    Exit(False);
  if FContext.Kind = ackStoredSnapshot then
  begin
    Analysis := ResolvedStep;
    Exit(Analysis.Available);
  end;
  if (FToolMode = tmStepHeight) and FHasStep and FStepUserSet then
  begin
    Analysis.Available := True;
    Analysis.Mode := fsmRegions;
    Analysis.Step := FStepRes;
    Analysis.Origin := FStepOrigin;
    Exit(True);
  end;
  Analysis := ResolvedStep;
  if not Analysis.Available then
    Exit(False);
  Result := (Analysis.Mode = fsmRegions) or (FToolMode = tmStepHeight) or not FHasWear;
end;

function TframeFIBPSViewer.GetAnalysisSnapshot(const KeyName: string): string;
var
  Analysis: TFIBPSStepAnalysis;
begin
  Result := '';
  if ((KeyName = FIBPSKeyStep) or (KeyName = FIBPSKeyStepStd)) and
    StepForExtraction(Analysis) then
    Result := BuildStepSnapshot(FContext, FData, Analysis);
end;

function TframeFIBPSViewer.GetAnalysisStatus: string;
var
  Analysis: TFIBPSStepAnalysis;
begin
  StepForExtraction(Analysis);
  Result := Analysis.Status;
end;

function TframeFIBPSViewer.CanApplyShared: Boolean;
begin
  Result := Assigned(ElnAnalysisSettings) and (FContext.Kind = ackCurrent) and
    (FContext.FileId > 0) and (FContext.FileHash <> '') and (FData.PixW > 0);
end;

procedure TframeFIBPSViewer.ApplySharedRegions;
var
  Service: IElnAnalysisSettings;
  Regions, Previous: TFIBPSRegions;
  Expected, Current, ApplyId, AppliedAt: string;
  Revision, Attempt: Integer;
begin
  if not (FHasStep and FStepUserSet and CanApplyShared) then
    Exit;
  Service := ElnAnalysisSettings;
  Regions := Default(TFIBPSRegions);
  Regions.RectA := FStepRes.RectA;
  Regions.RectB := FStepRes.RectB;
  Regions.PixW := Integer(FData.PixW);
  Regions.PixH := Integer(FData.PixH);
  Regions.FileHash := FContext.FileHash;
  Expected := FContext.SharedSelection;
  for Attempt := 1 to 2 do
  begin
    if TryParseRegions(Expected, Previous) and Previous.Origin.Present then
      Revision := Previous.Origin.Revision + 1
    else
      Revision := 1;
    ApplyId := TGUID.NewGuid.ToString;
    AppliedAt := FormatDateTime('yyyy-mm-dd"T"hh":"nn":"ss"Z"',
      TTimeZone.Local.ToUniversalTime(Now), TFormatSettings.Invariant);
    case Service.Apply(FContext.FileId, FIBPSReaderId, Expected,
      RegionsToSelectionJson(Regions, Revision, Service.CurrentUserId, ApplyId, AppliedAt),
      Current) of
      aarApplied:
        begin
          FContext.SharedSelection := Current;
          FResolvedValid := False;
          FStepOrigin.Present := True;
          FStepOrigin.Revision := Revision;
          FStepOrigin.ApplyId := ApplyId;
          FStepFallback := False;
          Exit;
        end;
      aarConflict:
        Expected := Current;
    else
      Break;
    end;
  end;
  FStepOrigin := Default(TFIBPSOrigin);
  pnlInfo.Caption := pnlInfo.Caption + '  |  Regions were not saved for this file';
end;

procedure TframeFIBPSViewer.SetAnalysisContext(const Context: TAnalysisContext);
var
  Regions: TFIBPSRegions;
  Res: TFIBPSStepResult;
begin
  FContext := Context;
  FResolvedValid := False;
  if (Context.Kind <> ackCurrent) or (FData.PixW = 0) then
    Exit;
  if (not FStepUserSet or FStepFallback) and (Context.SharedSelection <> '') and
    TryParseRegions(Context.SharedSelection, Regions) and
    ((Regions.FileHash = '') or SameText(Regions.FileHash, Context.FileHash)) and
    RegionsFitMap(Regions, FData) and
    FData.CalcStepFromRects(Regions.RectA, Regions.RectB, Res) then
  begin
    FStepRes := Res;
    FHasStep := True;
    FStepUserSet := False;
    FStepFallback := False;
    FStepOrigin := Regions.Origin;
    if FToolMode = tmStepHeight then
    begin
      UpdatePlaneAndRender;
      ShowStepHeightResult;
    end;
    Exit;
  end;
  if FStepUserSet and not (FStepOrigin.Present and
    TryParseRegions(Context.SharedSelection, Regions) and Regions.Origin.Present and
    (Regions.Origin.ApplyId = FStepOrigin.ApplyId)) then
    ApplySharedRegions;
end;

function TframeFIBPSViewer.GetDetailedInfo: string;
var
  J: TJSONObject;
  R: TFIBPSRecipe;
  WJ: TJSONObject;
  Rows, Row: TJSONArray;
  I: Integer;
begin
  Result := '';
  if FData = nil then
    Exit;

  R := FData.Recipe;
  J := TJSONObject.Create;
  try
    J.AddPair('fileName', ExtractFileName(FData.FileName));
    J.AddPair('pixelWidth', TJSONNumber.Create(Integer(FData.PixW)));
    J.AddPair('pixelHeight', TJSONNumber.Create(Integer(FData.PixH)));
    J.AddPair('physWidth_um', JNum(FData.PhysW));
    J.AddPair('physHeight_um', JNum(FData.PhysH));
    J.AddPair('minHeight_um', JNum(FData.MinH));
    J.AddPair('maxHeight_um', JNum(FData.MaxH));
    J.AddPair('backscanMicrons', R.BackscanMicrons);
    J.AddPair('scanLengthMicrons', R.ScanLengthMicrons);
    J.AddPair('scanSpeedPct', R.ScanSpeedPct);
    J.AddPair('scanAverages', R.ScanAverages);
    J.AddPair('objectiveType', R.ObjectiveType);
    J.AddPair('analysisMethod', R.AnalysisMethod);
    J.AddPair('measPurpose', R.MeasPurpose);
    J.AddPair('authorName', R.AuthorName);
    if FData.PixW > 0 then
      J.AddPair('heightMap', HeightMapJson(FData));
    if FHasWear then
    begin
      WJ := TJSONObject.Create;
      J.AddPair('wearTrack', WJ);
      WJ.AddPair('area_um2', JNum(FWearRes.WearArea));
      WJ.AddPair('areaStd_um2', JNum(FWearRes.WearAreaStd));
      WJ.AddPair('rows', TJSONNumber.Create(FWearRes.RowCount));
      WJ.AddPair('edge1_um', JNum(FWearRes.Edge1X));
      WJ.AddPair('edge2_um', JNum(FWearRes.Edge2X));
      WJ.AddPair('profileColumns', TJSONArray.Create.Add('x_um').Add('mean_um')
        .Add('sd_um').Add('n_measured'));
      Rows := TJSONArray.Create;
      WJ.AddPair('profile', Rows);
      for I := 0 to High(FWearRes.ProfileX) do
      begin
        if IsNan(FWearRes.ProfileMean[I]) then
          Continue;
        Row := TJSONArray.Create;
        Row.AddElement(JNum(FWearRes.ProfileX[I]));
        Row.AddElement(JNum(FWearRes.ProfileMean[I]));
        Row.AddElement(JNum(FWearRes.ProfileStd[I]));
        Row.Add(FWearRes.ProfileMeasured[I]);
        Rows.AddElement(Row);
      end;
    end;
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

function TframeFIBPSViewer.SaveState: string;
var
  JObj: TJSONObject;
begin
  Result := '';
  if not Assigned(FData) then Exit;

  JObj := TJSONObject.Create;
  try
    JObj.AddPair('v', TJSONNumber.Create(2));
    JObj.AddPair('zoom', TJSONNumber.Create(FZoom));
    JObj.AddPair('flatten', TJSONBool.Create(FFlatten));
    JObj.AddPair('tool', TJSONNumber.Create(Ord(FToolMode)));
    JObj.AddPair('profileRow', TJSONNumber.Create(FProfileRow));
    JObj.AddPair('profileCol', TJSONNumber.Create(FProfileCol));
    JObj.AddPair('profileVert', TJSONBool.Create(FProfileIsVert));
    Result := JObj.ToJSON;
  finally
    JObj.Free;
  end;
end;

procedure TframeFIBPSViewer.RestoreState(const AState: string);
var
  JObj: TJSONObject;
  JVal: TJSONValue;
  ToolOrd: Integer;
begin
  if not Assigned(FData) then Exit;

  try
    JObj := TJSONObject.ParseJSONValue(AState) as TJSONObject;
  except
    Exit;
  end;
  if not Assigned(JObj) then Exit;

  try
    JVal := JObj.GetValue('zoom');
    if Assigned(JVal) then
      FZoom := (JVal as TJSONNumber).AsDouble;

    if JObj.GetValue<Integer>('v', 1) >= 2 then
    begin
      JVal := JObj.GetValue('flatten');
      if Assigned(JVal) and (JVal is TJSONBool) then
      begin
        FFlatten := (JVal as TJSONBool).AsBoolean;
        btnFlatten.Down := FFlatten;
      end;

      ToolOrd := JObj.GetValue<Integer>('tool', 0);
      if (ToolOrd >= Ord(Low(TToolMode))) and (ToolOrd <= Ord(High(TToolMode))) then
        FToolMode := TToolMode(ToolOrd);
    end;

    btnProfile.Down := FToolMode = tmProfile;
    btnDistance.Down := FToolMode = tmDistance;
    btnRoughness.Down := FToolMode = tmRoughness;
    btnStepHeight.Down := FToolMode = tmStepHeight;
    btnWearTrack.Down := FToolMode = tmWearTrack;

    FProfileRow := JObj.GetValue<Integer>('profileRow', -1);
    FProfileCol := JObj.GetValue<Integer>('profileCol', -1);
    JVal := JObj.GetValue('profileVert');
    if Assigned(JVal) and (JVal is TJSONBool) then
      FProfileIsVert := (JVal as TJSONBool).AsBoolean;

    if FToolMode = tmStepHeight then
      EnsureStepResult;

    UpdatePlaneAndRender;
    ApplyZoom;

    if FToolMode = tmStepHeight then
      ShowStepHeightResult
    else if FToolMode = tmWearTrack then
      ShowWearTrackResult
    else if (FToolMode = tmProfile) and ((FProfileRow >= 0) or (FProfileCol >= 0)) then
    begin
      UpdateProfile(FProfileRow, FProfileCol);
      ShowProfilePanel(True);
      DrawOverlay;
    end;
  finally
    JObj.Free;
  end;
end;

end.
