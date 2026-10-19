unit frame_VK4Viewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Math,
  System.Types,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Dialogs,
  VclTee.TeeGDIPlus, VCLTee.TeEngine, VCLTee.Series, VCLTee.TeeProcs, VCLTee.Chart,
  RzPanel, RzButton,
  unit_ELNPluginCore, unit_ELNPluginTypes, unit_VK4Data;

type
  TRGBTripleArray = array[0..0] of TRGBTriple;
  PRGBTripleArray = ^TRGBTripleArray;

  TToolMode = (tmNone, tmProfile, tmDistance, tmRoughness);

  TframeVK4Viewer = class(TFrame)
    pnlToolbar: TPanel;
    lblChannel: TLabel;
    cboChannel: TComboBox;
    btnProfile: TRzBitBtn;
    btnDistance: TRzBitBtn;
    btnRoughness: TRzBitBtn;
    btnFlatten: TRzBitBtn;
    btnCopy: TRzBitBtn;
    btnSave: TRzBitBtn;
    Status: TRzStatusBar;
    pnlInfo: TRzPanel;
    ChartProfile: TChart;
    serProfileH: TFastLineSeries;
    serProfileV: TFastLineSeries;
    SplitterProfile: TSplitter;
    pnlCenter: TPanel;
    pbLegend: TPaintBox;
    ScrollBox: TScrollBox;
    Image: TImage;
    dlgSave: TSaveDialog;
    btnFitPage: TRzBitBtn;
    procedure cboChannelChange(Sender: TObject);
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
    procedure btnCopyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnFitPageClick(Sender: TObject);
  private
    FData: TVK4Data;
    FBitmap: TBitmap;
    FZoom: Double;
    FPalette: array[0..255] of TColor;
    FChannel: TVK4Channel;
    FToolMode: TToolMode;
    FStatusBase: string;
    FCursorPos: TPoint;
    FHasCursor: Boolean;
    FFlatten: Boolean;

    FProfileRow: Integer;
    FProfileCol: Integer;
    FProfileIsVert: Boolean;

    FDistPtA: TPoint;
    FDistPtB: TPoint;
    FDistHasA: Boolean;
    FDistHasB: Boolean;

    FRoughOrigin: TPoint;
    FRoughDragging: Boolean;
    FRoughRect: TRect;
    FRoughHasRect: Boolean;

    // Flatten region for profile baseline
    FRegionA: record XMin, XMax, AvgH: Double; Count: Integer; HasRegion: Boolean end;

    FPanning: Boolean;
    FPanStart: TPoint;      // screen coords at drag start
    FScrollStart: TPoint;   // scroll bar positions at drag start
    FFitMode: Boolean;

    FPnlMeta: TPanel;
    FLblMeta: TLabel;

    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    function FormatH(Value: Double): string;
    procedure BuildColorRamp;
    function MapColor(Value, MinVal, MaxVal: Double): TColor;
    function MapGray(Value: Word; MaxVal: Word): TColor;
    procedure RenderBitmap;
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
    procedure PopulateChannels;
    procedure UpdateToolbarState;
    procedure HeightDataToText(List: TStringList);
    procedure CreateMetaPanel;
    function FormatMetaInfo: string;
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
  end;

implementation

uses
  ClipBrd, System.Generics.Collections, System.JSON, Vcl.Imaging.pngimage,
  Winapi.GDIPAPI, Winapi.GDIPOBJ,
  unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}

const
  ZOOM_MIN = 0.25;
  ZOOM_MAX = 8.0;


constructor TframeVK4Viewer.Create(AOwner: TComponent);
begin
  inherited;
  FData := TVK4Data.Create;
  FZoom := 1.0;
  FChannel := vcColorPeak;
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
  FRegionA.HasRegion := False;
  FPanning := False;
  CreateMetaPanel;
  BuildColorRamp;
end;

procedure TframeVK4Viewer.CreateMetaPanel;
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

destructor TframeVK4Viewer.Destroy;
begin
  FBitmap.Free;
  FData.Free;
  inherited;
end;


function TframeVK4Viewer.FormatH(Value: Double): string;
begin
  if Abs(Value) < 1.0 then
    Result := Format('%.2f nm', [Value * 1000])
  else
    Result := Format('%.4f %sm', [Value, #$B5]);
end;


procedure TframeVK4Viewer.BuildColorRamp;
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

function TframeVK4Viewer.MapColor(Value, MinVal, MaxVal: Double): TColor;
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

function TframeVK4Viewer.MapGray(Value: Word; MaxVal: Word): TColor;
var
  G: Byte;
begin
  if MaxVal = 0 then
    G := 128
  else
    G := Round(255 * Value / MaxVal);
  Result := RGB(G, G, G);
end;


procedure TframeVK4Viewer.RenderBitmap;
var
  Img: TVK4ImageData;
  X, Y: Integer;
  Row: PRGBTripleArray;
  C: TColor;
  W, H: Cardinal;
  MaxLight: Word;
  I: Integer;
begin
  FreeAndNil(FBitmap);
  Img := FData.GetImageData(FChannel);
  if not Img.Valid then Exit;

  W := Img.Width;
  H := Img.Height;

  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf24bit;
  FBitmap.SetSize(W, H);

  case FChannel of
    vcColorPeak, vcColorLight:
    begin
      for Y := 0 to Integer(H) - 1 do
      begin
        Row := FBitmap.ScanLine[Y];
        for X := 0 to Integer(W) - 1 do
        begin
          {$R-}
          Row^[X].rgbtRed   := Img.DataRGB[Y * Integer(W) + X].R;
          Row^[X].rgbtGreen := Img.DataRGB[Y * Integer(W) + X].G;
          Row^[X].rgbtBlue  := Img.DataRGB[Y * Integer(W) + X].B;
          {$R+}
        end;
      end;
    end;

    vcHeight:
    begin
      for Y := 0 to Integer(H) - 1 do
      begin
        Row := FBitmap.ScanLine[Y];
        for X := 0 to Integer(W) - 1 do
        begin
          C := MapColor(FData.HeightAt(X, Y), FData.MinHeight, FData.MaxHeight);
          {$R-}
          Row^[X].rgbtRed   := GetRValue(C);
          Row^[X].rgbtGreen := GetGValue(C);
          Row^[X].rgbtBlue  := GetBValue(C);
          {$R+}
        end;
      end;
    end;

    vcLightIntensity:
    begin
      MaxLight := 1;
      for I := 0 to Length(Img.DataU16) - 1 do
        if Img.DataU16[I] > MaxLight then
          MaxLight := Img.DataU16[I];

      for Y := 0 to Integer(H) - 1 do
      begin
        Row := FBitmap.ScanLine[Y];
        for X := 0 to Integer(W) - 1 do
        begin
          C := MapGray(Img.DataU16[Y * Integer(W) + X], MaxLight);
          {$R-}
          Row^[X].rgbtRed   := GetRValue(C);
          Row^[X].rgbtGreen := GetGValue(C);
          Row^[X].rgbtBlue  := GetBValue(C);
          {$R+}
        end;
      end;
    end;
  end;

  Image.Picture.Assign(FBitmap);
end;

procedure TframeVK4Viewer.ApplyZoom;
var
  W, H: Integer;
begin
  if FBitmap = nil then Exit;
  if FFitMode and (ScrollBox.ClientWidth > 0) and (ScrollBox.ClientHeight > 0) then
  begin
    FZoom := Min(ScrollBox.ClientWidth / FBitmap.Width,
                 ScrollBox.ClientHeight / FBitmap.Height);
    if FZoom < ZOOM_MIN then FZoom := ZOOM_MIN;
    if FZoom > ZOOM_MAX then FZoom := ZOOM_MAX;
  end;
  W := Round(FBitmap.Width * FZoom);
  H := Round(FBitmap.Height * FZoom);
  Image.Width := W;
  Image.Height := H;
  Image.Stretch := FZoom <> 1.0;
  CenterImage;
end;

procedure TframeVK4Viewer.CenterImage;
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


procedure TframeVK4Viewer.PopulateChannels;
begin
  cboChannel.Items.Clear;

  if FData.HasChannel(vcColorPeak) then
    cboChannel.Items.AddObject('Color (Peak)', TObject(vcColorPeak));
  if FData.HasChannel(vcColorLight) then
    cboChannel.Items.AddObject('Color (Light)', TObject(vcColorLight));
  if FData.HasChannel(vcHeight) then
    cboChannel.Items.AddObject('Height', TObject(vcHeight));
  if FData.HasChannel(vcLightIntensity) then
    cboChannel.Items.AddObject('Light Intensity', TObject(vcLightIntensity));

  if cboChannel.Items.Count > 0 then
    cboChannel.ItemIndex := 0;
end;

procedure TframeVK4Viewer.cboChannelChange(Sender: TObject);
begin
  if cboChannel.ItemIndex < 0 then Exit;
  FChannel := TVK4Channel(cboChannel.Items.Objects[cboChannel.ItemIndex]);
  UpdateToolbarState;
  RenderBitmap;
  ApplyZoom;
  pbLegend.Invalidate;
end;

procedure TframeVK4Viewer.UpdateToolbarState;
var
  IsHeight: Boolean;
begin
  IsHeight := FChannel = vcHeight;
  btnProfile.Enabled := IsHeight;
  btnDistance.Enabled := IsHeight;
  btnRoughness.Enabled := IsHeight;
  btnFlatten.Enabled := IsHeight;
  pbLegend.Visible := IsHeight or (FChannel = vcLightIntensity);
  if not IsHeight then
    CancelTool;
end;


function TframeVK4Viewer.ImagePixToData(ImgX, ImgY: Integer;
  out DX, DY: Integer): Boolean;
var
  Img: TVK4ImageData;
begin
  if (FBitmap = nil) or (Image.Width = 0) or (Image.Height = 0) then
    Exit(False);

  DX := Round(ImgX * FBitmap.Width / Image.Width);
  DY := Round(ImgY * FBitmap.Height / Image.Height);

  Img := FData.GetImageData(FChannel);
  Result := Img.Valid and (DX >= 0) and (DX < Integer(Img.Width)) and
            (DY >= 0) and (DY < Integer(Img.Height));
end;


procedure SelectChannel(Combo: TComboBox; Ch: TVK4Channel);
var
  I: Integer;
begin
  for I := 0 to Combo.Items.Count - 1 do
    if TVK4Channel(Combo.Items.Objects[I]) = Ch then
    begin
      Combo.ItemIndex := I;
      Exit;
    end;
end;


procedure TframeVK4Viewer.LoadFromFile(const AFileName: string);
var
  MetaText: string;
  W, H: Cardinal;
begin
  FreeAndNil(FBitmap);
  Image.Picture.Assign(nil);
  FPnlMeta.Visible := False;
  Status.SimpleCaption := '';
  pnlInfo.Caption := '';
  cboChannel.Items.Clear;
  CancelTool;

  FData.ParseFromFile(AFileName);

  FZoom := 1.0;
  PopulateChannels;

  if FData.HasChannel(vcColorPeak) then
    FChannel := vcColorPeak
  else if FData.HasChannel(vcHeight) then
    FChannel := vcHeight
  else if FData.HasChannel(vcLightIntensity) then
    FChannel := vcLightIntensity
  else if FData.HasChannel(vcColorLight) then
    FChannel := vcColorLight;

  SelectChannel(cboChannel, FChannel);

  UpdateToolbarState;
  RenderBitmap;
  FFitMode := True;
  ApplyZoom;
  ApplyChartTheme(ChartProfile);

  MetaText := FormatMetaInfo;
  if MetaText <> '' then
  begin
    FLblMeta.Caption := MetaText;
    FPnlMeta.Visible := True;
  end
  else
    FPnlMeta.Visible := False;

  W := FData.ChannelWidth(FChannel);
  H := FData.ChannelHeight(FChannel);
  if FData.HasChannel(vcHeight) then
    FStatusBase := Format('%s  |  %d x %d px  |  %.1f x %.1f %sm  |  H: %s .. %s',
      [ExtractFileName(AFileName), W, H,
       FData.PhysWidth, FData.PhysHeight, #$B5,
       FormatH(FData.MinHeight), FormatH(FData.MaxHeight)])
  else
    FStatusBase := Format('%s  |  %d x %d px  |  %.1f x %.1f %sm',
      [ExtractFileName(AFileName), W, H,
       FData.PhysWidth, FData.PhysHeight, #$B5]);
  Status.SimpleCaption := FStatusBase;

  pbLegend.Invalidate;
end;

procedure TframeVK4Viewer.ShowError(const Msg: string);
begin
  Status.SimpleCaption := 'Error: ' + Msg;
end;

function TframeVK4Viewer.FormatMetaInfo: string;
var
  SL: TStringList;
  S: TVK4Settings;
begin
  Result := '';
  S := FData.Settings;

  SL := TStringList.Create;
  try
    if (S.Year > 0) then
      SL.Add(Format('Date: %d-%02d-%02d %02d:%02d:%02d',
        [S.Year, S.Month, S.Day, S.Hour, S.Minute, S.Second]));

    if FData.LensName <> '' then
      SL.Add('Lens: ' + FData.LensName);
    if S.LensMag > 0 then
      SL.Add(Format('Mag: %dx', [S.LensMag]));
    if S.OpticalZoom > 0 then
      SL.Add(Format('Zoom: %.1fx', [S.OpticalZoom / 10.0]));

    if FData.PixelXum > 0 then
      SL.Add(Format('Pixel: %.4f x %.4f %sm',
        [FData.PixelXum, FData.PixelYum, #$B5]));
    if FData.PhysWidth > 0 then
      SL.Add(Format('Area: %.1f x %.1f %sm',
        [FData.PhysWidth, FData.PhysHeight, #$B5]));

    if FData.HasChannel(vcHeight) then
      SL.Add(Format('Z range: %s', [FormatH(FData.MaxHeight - FData.MinHeight)]));

    if FData.Title <> '' then
      SL.Add('Title: ' + FData.Title);

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;


function TframeVK4Viewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
begin
  if FBitmap <> nil then
    Result := CreateScaledPreview(FBitmap, MaxW, MaxH)
  else
    Result := nil;
end;


procedure TframeVK4Viewer.ScrollBoxMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  Factor: Double;
begin
  if WheelDelta > 0 then
    Factor := 1.25
  else
    Factor := 0.8;

  FFitMode := False;
  FZoom := FZoom * Factor;
  if FZoom < ZOOM_MIN then FZoom := ZOOM_MIN;
  if FZoom > ZOOM_MAX then FZoom := ZOOM_MAX;

  ApplyZoom;
  Handled := True;
end;

procedure TframeVK4Viewer.ScrollBoxResize(Sender: TObject);
begin
  if FBitmap <> nil then
    ApplyZoom;
end;

procedure TframeVK4Viewer.ImageDblClick(Sender: TObject);
begin
  if FFitMode then
  begin
    FFitMode := False;
    FZoom := 1.0;
  end
  else
    FFitMode := True;
  ApplyZoom;
  CancelTool;
end;


procedure TframeVK4Viewer.ImageMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
  ScreenPt: TPoint;
begin
  if FPanning then
  begin
    ScreenPt := Image.ClientToScreen(Point(X, Y));
    ScrollBox.HorzScrollBar.Position := FScrollStart.X - (ScreenPt.X - FPanStart.X);
    ScrollBox.VertScrollBar.Position := FScrollStart.Y - (ScreenPt.Y - FPanStart.Y);
    Exit;
  end;

  if not ImagePixToData(X, Y, DX, DY) then
    Exit;

  FCursorPos := Point(DX, DY);
  FHasCursor := True;

  UpdateStatusCursor(DX, DY);

  if FRoughDragging then
  begin
    FRoughRect.Right := DX;
    FRoughRect.Bottom := DY;
  end;

  if FToolMode <> tmNone then
    DrawOverlay;
end;

procedure TframeVK4Viewer.ImageMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
begin
  if ScrollBox.CanFocus then
    ScrollBox.SetFocus;

  if (Button = mbMiddle) or ((Button = mbLeft) and (FToolMode = tmNone)) then
  begin
    FPanning := True;
    FPanStart := Image.ClientToScreen(Point(X, Y));
    FScrollStart := Point(ScrollBox.HorzScrollBar.Position,
                          ScrollBox.VertScrollBar.Position);
    Image.Cursor := crSizeAll;
    Exit;
  end;

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
  end;
end;

procedure TframeVK4Viewer.ImageMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  DX, DY: Integer;
  Ra, Rq, Rz: Double;
  R: TRect;
begin
  if FPanning then
  begin
    FPanning := False;
    Image.Cursor := crDefault;
    Exit;
  end;

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
      DX := R.Left; R.Left := R.Right; R.Right := DX;
    end;
    if R.Top > R.Bottom then
    begin
      DY := R.Top; R.Top := R.Bottom; R.Bottom := DY;
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
  end;
end;

procedure TframeVK4Viewer.UpdateStatusCursor(DX, DY: Integer);
var
  H: Double;
begin
  case FChannel of
    vcHeight:
    begin
      H := FData.HeightAt(DX, DY);
      if IsNan(H) then
        Status.SimpleCaption := Format('%s  |  (%d, %d) = NaN', [FStatusBase, DX, DY])
      else
        Status.SimpleCaption := Format('%s  |  (%.2f, %.2f) %sm  H = %s',
          [FStatusBase, FData.PhysXAt(DX), FData.PhysYAt(DY), #$B5, FormatH(H)]);
    end;
    vcLightIntensity:
      Status.SimpleCaption := Format('%s  |  (%d, %d)  L = %d',
        [FStatusBase, DX, DY, FData.LightAt(DX, DY)]);
  else
    Status.SimpleCaption := Format('%s  |  (%d, %d)',
      [FStatusBase, DX, DY]);
  end;
end;


procedure TframeVK4Viewer.RegionDetrend(var YVals: array of Double;
  const XVals: array of Double; Count: Integer);
var
  I: Integer;
  SumX, SumY, SumXY, SumX2, Slope, Intercept, N: Double;

  function InRegionA(X: Double): Boolean;
  begin
    Result := FRegionA.HasRegion
      and (X >= FRegionA.XMin) and (X <= FRegionA.XMax);
  end;

begin
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

procedure TframeVK4Viewer.UpdateProfile(Row, Col: Integer);
var
  I, Count: Integer;
  XArr, YArr: array of Double;
  W, H: Cardinal;
begin
  if not FData.HasChannel(vcHeight) then Exit;
  W := FData.ChannelWidth(vcHeight);
  H := FData.ChannelHeight(vcHeight);

  ChartProfile.AutoRepaint := False;
  try
    serProfileH.Clear;
    serProfileV.Clear;
    ChartProfile.LeftAxis.Automatic := True;
    ChartProfile.BottomAxis.Automatic := True;

    if Row >= 0 then
    begin
      Count := Integer(W);
      SetLength(XArr, Count);
      SetLength(YArr, Count);
      for I := 0 to Count - 1 do
      begin
        XArr[I] := FData.PhysXAt(I);
        YArr[I] := FData.HeightAt(I, Row);
      end;
      if FFlatten and FRegionA.HasRegion then
        RegionDetrend(YArr, XArr, Count);
      for I := 0 to Count - 1 do
        serProfileH.AddXY(XArr[I], YArr[I]);
    end;

    if Col >= 0 then
    begin
      Count := Integer(H);
      SetLength(XArr, Count);
      SetLength(YArr, Count);
      for I := 0 to Count - 1 do
      begin
        XArr[I] := FData.PhysYAt(I);
        YArr[I] := FData.HeightAt(Col, I);
      end;
      if FFlatten and FRegionA.HasRegion then
        RegionDetrend(YArr, XArr, Count);
      for I := 0 to Count - 1 do
        serProfileV.AddXY(XArr[I], YArr[I]);
    end;
  finally
    ChartProfile.AutoRepaint := True;
    ChartProfile.Repaint;
  end;
end;

procedure TframeVK4Viewer.ShowProfilePanel(AVisible: Boolean);
begin
  ChartProfile.Visible := AVisible;
  SplitterProfile.Visible := AVisible;
end;


procedure TframeVK4Viewer.DrawOverlay;
var
  Tmp: TBitmap;
  Cvs: TCanvas;
  P1, P2: TPoint;
  R: TRect;
  Swap: Integer;
begin
  if FBitmap = nil then Exit;

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
      if FProfileRow >= 0 then
      begin
        Cvs.MoveTo(0, FProfileRow);
        Cvs.LineTo(Tmp.Width, FProfileRow);
      end;
      if FProfileCol >= 0 then
      begin
        Cvs.MoveTo(FProfileCol, 0);
        Cvs.LineTo(FProfileCol, Tmp.Height);
      end;
      Cvs.Pen.Style := psSolid;
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
      begin Swap := R.Left; R.Left := R.Right; R.Right := Swap; end;
      if R.Top > R.Bottom then
      begin Swap := R.Top; R.Top := R.Bottom; R.Bottom := Swap; end;
      Cvs.Pen.Color := clYellow;
      Cvs.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
    end;

    Image.Picture.Graphic := Tmp;
  finally
    Tmp.Free;
  end;
end;


procedure TframeVK4Viewer.ShowDistanceResult;
var
  X1, Y1, X2, Y2: Double;
  H1, H2, DXY, DH, D3D: Double;
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


procedure TframeVK4Viewer.CalcRoughness(const R: TRect; out Ra, Rq, Rz: Double);
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


procedure TframeVK4Viewer.pbLegendPaint(Sender: TObject);
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
  if (FChannel = vcColorPeak) or (FChannel = vcColorLight) then Exit;

  GradH := pbLegend.Height - 40;
  if GradH < 10 then GradH := 10;

  Cvs := pbLegend.Canvas;
  for I := 0 to GradH - 1 do
  begin
    Idx := Round(255 * (1 - I / GradH));
    if Idx < 0 then Idx := 0;
    if Idx > 255 then Idx := 255;

    if FChannel = vcHeight then
      C := FPalette[Idx]
    else
      C := RGB(Idx, Idx, Idx);

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
      if FChannel = vcHeight then
      begin
        LabelText := FormatH(FData.MaxHeight);
        R := MakeRect(0.0, 2.0, pbLegend.Width * 1.0, 16.0);
        Graphics.DrawString(LabelText, Length(LabelText), Font, R, StringFmt, Brush);
        LabelText := FormatH(FData.MinHeight);
        R := MakeRect(0.0, (20 + GradH + 2) * 1.0, pbLegend.Width * 1.0, 16.0);
        Graphics.DrawString(LabelText, Length(LabelText), Font, R, StringFmt, Brush);
      end
      else
      begin
        LabelText := 'Max';
        R := MakeRect(0.0, 2.0, pbLegend.Width * 1.0, 16.0);
        Graphics.DrawString(LabelText, Length(LabelText), Font, R, StringFmt, Brush);
        LabelText := 'Min';
        R := MakeRect(0.0, (20 + GradH + 2) * 1.0, pbLegend.Width * 1.0, 16.0);
        Graphics.DrawString(LabelText, Length(LabelText), Font, R, StringFmt, Brush);
      end;
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


procedure TframeVK4Viewer.CancelTool;
begin
  FToolMode := tmNone;
  FDistHasA := False;
  FDistHasB := False;
  FRoughHasRect := False;
  FRoughDragging := False;
  FPanning := False;
  FHasCursor := False;
  FProfileRow := -1;
  FProfileCol := -1;
  FRegionA.HasRegion := False;
  FFlatten := False;
  btnProfile.Down := False;
  btnDistance.Down := False;
  btnRoughness.Down := False;
  btnFlatten.Down := False;
  ShowProfilePanel(False);
  pnlInfo.Caption := '';
  if FBitmap <> nil then
    DrawOverlay;
end;

procedure TframeVK4Viewer.CMDialogKey(var Message: TCMDialogKey);
begin
  if (Message.CharCode = VK_ESCAPE) and (FToolMode <> tmNone) then
  begin
    CancelTool;
    Message.Result := 1;
  end
  else
    inherited;
end;


procedure TframeVK4Viewer.btnProfileClick(Sender: TObject);
begin
  if btnProfile.Down then
  begin
    FToolMode := tmProfile;
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

procedure TframeVK4Viewer.btnDistanceClick(Sender: TObject);
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

procedure TframeVK4Viewer.btnRoughnessClick(Sender: TObject);
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

procedure TframeVK4Viewer.btnFlattenClick(Sender: TObject);
begin
  FFlatten := btnFlatten.Down;
  if FProfileRow >= 0 then
    UpdateProfile(FProfileRow, -1)
  else if FProfileCol >= 0 then
    UpdateProfile(-1, FProfileCol);
end;


procedure TframeVK4Viewer.HeightDataToText(List: TStringList);
var
  X, Y: Integer;
  Line: string;
  W, H: Cardinal;
begin
  if not FData.HasChannel(vcHeight) then Exit;
  W := FData.ChannelWidth(vcHeight);
  H := FData.ChannelHeight(vcHeight);

  List.Add('# VK4 Height Data Export');
  List.Add(Format('# File: %s', [ExtractFileName(FData.FileName)]));
  List.Add(Format('# Dimensions: %d x %d px', [W, H]));
  List.Add(Format('# Physical: %.4f x %.4f um', [FData.PhysWidth, FData.PhysHeight]));
  List.Add(Format('# Height range: %.4f .. %.4f um', [FData.MinHeight, FData.MaxHeight]));
  List.Add('#');

  Line := 'Y\X';
  for X := 0 to Integer(W) - 1 do
    Line := Line + #9 + FloatToStrF(FData.PhysXAt(X), ffFixed, 10, 4);
  List.Add(Line);

  for Y := 0 to Integer(H) - 1 do
  begin
    Line := FloatToStrF(FData.PhysYAt(Y), ffFixed, 10, 4);
    for X := 0 to Integer(W) - 1 do
      Line := Line + #9 + FloatToStrF(FData.HeightAt(X, Y), ffFixed, 10, 4);
    List.Add(Line);
  end;
end;

procedure TframeVK4Viewer.btnCopyClick(Sender: TObject);
begin
  if FBitmap <> nil then
    Clipboard.Assign(FBitmap);
end;

procedure TframeVK4Viewer.btnSaveClick(Sender: TObject);
var
  Png: TPngImage;
  List: TStringList;
begin
  if not dlgSave.Execute then Exit;

  if dlgSave.FilterIndex = 2 then
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

procedure TframeVK4Viewer.btnFitPageClick(Sender: TObject);
begin
  FFitMode := True;
  ApplyZoom;
end;


function TframeVK4Viewer.GetKeyValues: TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  KV: TPluginKeyValue;
  S: TVK4Settings;

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

begin
  Result := nil;
  if FData = nil then Exit;

  S := FData.Settings;
  List := TList<TPluginKeyValue>.Create;
  try
    if S.LensMag > 0 then
      Add('Magnification', S.LensMag, 'x', prCondition, True);
    if FData.PhysWidth > 0 then
      Add('Scan Width', FData.PhysWidth, 'um', prCondition, True);
    if FData.PhysHeight > 0 then
      Add('Scan Height', FData.PhysHeight, 'um', prCondition);
    if FData.PixelXum > 0 then
      Add('Pixel Size X', FData.PixelXum, 'um', prCondition);
    if FData.PixelYum > 0 then
      Add('Pixel Size Y', FData.PixelYum, 'um', prCondition);
    if FData.HasChannel(vcHeight) then
    begin
      Add('Min Height', FData.MinHeight, 'um', prResult);
      Add('Max Height', FData.MaxHeight, 'um', prResult);
      Add('Height Range', FData.MaxHeight - FData.MinHeight, 'um', prResult, True);
    end;
    if S.OpticalZoom > 0 then
      Add('Optical Zoom', S.OpticalZoom / 10.0, 'x', prCondition);

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;


function TframeVK4Viewer.GetDetailedInfo: string;
var
  J: TJSONObject;
  S: TVK4Settings;
begin
  Result := '';
  if FData = nil then Exit;

  S := FData.Settings;
  J := TJSONObject.Create;
  try
    J.AddPair('fileName', ExtractFileName(FData.FileName));
    J.AddPair('title', FData.Title);
    J.AddPair('lensName', FData.LensName);
    J.AddPair('measurementDate', Format('%d-%02d-%02d %02d:%02d:%02d',
      [S.Year, S.Month, S.Day, S.Hour, S.Minute, S.Second]));

    if FData.HasChannel(vcHeight) then
    begin
      J.AddPair('heightWidth_px', TJSONNumber.Create(Integer(FData.ChannelWidth(vcHeight))));
      J.AddPair('heightHeight_px', TJSONNumber.Create(Integer(FData.ChannelHeight(vcHeight))));
    end;
    if FData.HasChannel(vcColorPeak) then
    begin
      J.AddPair('colorWidth_px', TJSONNumber.Create(Integer(FData.ChannelWidth(vcColorPeak))));
      J.AddPair('colorHeight_px', TJSONNumber.Create(Integer(FData.ChannelHeight(vcColorPeak))));
    end;

    J.AddPair('physWidth_um', JNum(FData.PhysWidth));
    J.AddPair('physHeight_um', JNum(FData.PhysHeight));
    J.AddPair('pixelX_um', JNum(FData.PixelXum));
    J.AddPair('pixelY_um', JNum(FData.PixelYum));
    J.AddPair('minHeight_um', JNum(FData.MinHeight));
    J.AddPair('maxHeight_um', JNum(FData.MaxHeight));
    J.AddPair('heightRange_um', JNum(FData.MaxHeight - FData.MinHeight));
    J.AddPair('lensMag', TJSONNumber.Create(Integer(S.LensMag)));
    J.AddPair('opticalZoom', JNum(S.OpticalZoom / 10.0));

    J.AddPair('hasColorPeak', TJSONBool.Create(FData.HasChannel(vcColorPeak)));
    J.AddPair('hasColorLight', TJSONBool.Create(FData.HasChannel(vcColorLight)));
    J.AddPair('hasHeight', TJSONBool.Create(FData.HasChannel(vcHeight)));
    J.AddPair('hasLightIntensity', TJSONBool.Create(FData.HasChannel(vcLightIntensity)));

    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;


function TframeVK4Viewer.SaveState: string;
var
  JObj: TJSONObject;
begin
  Result := '';
  if not Assigned(FData) then Exit;

  JObj := TJSONObject.Create;
  try
    JObj.AddPair('v', TJSONNumber.Create(2));
    JObj.AddPair('fitMode', TJSONBool.Create(FFitMode));
    JObj.AddPair('zoom', TJSONNumber.Create(FZoom));
    JObj.AddPair('channel', TJSONNumber.Create(Ord(FChannel)));
    JObj.AddPair('tool', TJSONNumber.Create(Ord(FToolMode)));
    JObj.AddPair('profileRow', TJSONNumber.Create(FProfileRow));
    JObj.AddPair('profileCol', TJSONNumber.Create(FProfileCol));
    JObj.AddPair('flatten', TJSONBool.Create(FFlatten));
    Result := JObj.ToJSON;
  finally
    JObj.Free;
  end;
end;

procedure TframeVK4Viewer.RestoreState(const AState: string);
var
  JObj: TJSONObject;
  JVal: TJSONValue;
  ChOrd, ToolOrd: Integer;
begin
  if not Assigned(FData) then Exit;

  try
    JObj := TJSONObject.ParseJSONValue(AState) as TJSONObject;
  except
    Exit;
  end;
  if not Assigned(JObj) then Exit;

  try
    // Restore fit mode; old states (v1) without fitMode default to True
    JVal := JObj.GetValue('fitMode');
    if Assigned(JVal) and (JVal is TJSONBool) then
      FFitMode := (JVal as TJSONBool).AsBoolean
    else
      FFitMode := True;

    if not FFitMode then
    begin
      JVal := JObj.GetValue('zoom');
      if Assigned(JVal) then
        FZoom := (JVal as TJSONNumber).AsDouble;
    end;

    ChOrd := JObj.GetValue<Integer>('channel', Ord(FChannel));
    if (ChOrd >= Ord(Low(TVK4Channel))) and (ChOrd <= Ord(High(TVK4Channel))) then
    begin
      FChannel := TVK4Channel(ChOrd);
      SelectChannel(cboChannel, FChannel);
      RenderBitmap;
    end;

    ToolOrd := JObj.GetValue<Integer>('tool', 0);
    if (ToolOrd >= Ord(Low(TToolMode))) and (ToolOrd <= Ord(High(TToolMode))) then
      FToolMode := TToolMode(ToolOrd);

    FProfileRow := JObj.GetValue<Integer>('profileRow', -1);
    FProfileCol := JObj.GetValue<Integer>('profileCol', -1);

    JVal := JObj.GetValue('flatten');
    if Assigned(JVal) and (JVal is TJSONBool) then
    begin
      FFlatten := (JVal as TJSONBool).AsBoolean;
      btnFlatten.Down := FFlatten;
    end;

    ApplyZoom;
    UpdateToolbarState;
  finally
    JObj.Free;
  end;
end;

end.
