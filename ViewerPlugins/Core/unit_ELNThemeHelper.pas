unit unit_ELNThemeHelper;

interface

uses
  Vcl.Graphics, Vcl.Themes, Vcl.Controls, Vcl.ComCtrls,
  VCLTee.Chart, VCLTee.TeEngine, VCLTee.Series;

var
  ThemePluginsEnabled: Boolean = False;

function IsDarkTheme: Boolean;
function ThemePanelColor: TColor;
function ThemeTextColor: TColor;
function ThemeGridColor: TColor;
function ThemeWallColor: TColor;

procedure ApplyChartTheme(AChart: TChart);
procedure ApplyRichEditTheme(ARichEdit: TCustomRichEdit);

// Aligns a WebView2 browser's preferred color scheme with the active VCL
// theme. Pass the browser's DefaultInterface (ICoreWebView2, typed as IUnknown
// to keep this unit free of a Vcl.Edge dependency). Without this, WebView2
// defaults to AUTO and follows the Windows *system* dark-mode setting, so its
// scrollbars and built-in PDF chrome render dark even when ELN runs the light
// theme. Call from each viewer's OnCreateWebViewCompleted handler.
procedure ApplyBrowserColorScheme(const AWebView: IUnknown);

// Locates the newest installed WebView2 *runtime* folder, for pinning
// TEdgeBrowser.BrowserExecutableFolder. Edge 151 renamed the runtime's browser
// exe from msedge.exe to msedgewebview2.exe, so both names are probed. Only
// EdgeWebView runtime installs qualify: pointing the property at a stable Edge
// *browser* install is rejected by the WebView2 loader ("CoreWebView2Environment
// can't use stable Microsoft Edge install", hr=80070032) and leaves the viewer
// permanently blank. Returns '' when no runtime folder is found — callers must
// then leave BrowserExecutableFolder empty so the loader auto-detects the
// evergreen runtime (which also covers per-user installs these fixed paths
// cannot see).
function FindWebView2RuntimeFolder: string;

implementation

uses
  System.SysUtils, System.Math, System.IOUtils, Winapi.Windows, Winapi.WebView2;

type
  TRichEditAccess = class(TCustomRichEdit);

const
  CDarkSeriesColors: array[0..7] of TColor = (
    $CC9933,   // muted steel blue
    $4466DD,   // muted red-orange
    $55BB55,   // muted green
    $CC77AA,   // muted mauve
    $44AABB,   // muted teal
    $6688CC,   // muted slate blue
    $88BBDD,   // muted sand
    $AA88CC    // muted lavender
  );

  CLightSeriesColors: array[0..7] of TColor = (
    clNavy, clRed, clGreen, clPurple,
    clTeal, clMaroon, clOlive, clFuchsia
  );

function Luminance(C: TColor): Double;
var
  R, G, B: Byte;
begin
  C := ColorToRGB(C);
  R := GetRValue(C);
  G := GetGValue(C);
  B := GetBValue(C);
  Result := 0.299 * R + 0.587 * G + 0.114 * B;
end;

function IsDarkTheme: Boolean;
begin
  Result := Luminance(
    TStyleManager.ActiveStyle.GetStyleColor(scPanel)) < 128;
end;

function ThemePanelColor: TColor;
begin
  Result := ColorToRGB(
    TStyleManager.ActiveStyle.GetStyleColor(scPanel));
end;

function ThemeTextColor: TColor;
begin
  Result := ColorToRGB(
    TStyleManager.ActiveStyle.GetStyleFontColor(sfWindowTextNormal));
end;

function ThemeGridColor: TColor;
begin
  if IsDarkTheme then
    Result := $555555
  else
    Result := clSilver;
end;

function ThemeWallColor: TColor;
var
  Panel: TColor;
  R, G, B: Byte;
  Delta: Integer;
begin
  Panel := ThemePanelColor;
  R := GetRValue(Panel);
  G := GetGValue(Panel);
  B := GetBValue(Panel);
  if IsDarkTheme then
    Delta := 30
  else
    Delta := -10;
  R := EnsureRange(R + Delta, 0, 255);
  G := EnsureRange(G + Delta, 0, 255);
  B := EnsureRange(B + Delta, 0, 255);
  Result := RGB(R, G, B);
end;

procedure ApplyChartTheme(AChart: TChart);
var
  Dark: Boolean;
  BgColor, TxtColor, GridClr, WallClr: TColor;
  I: Integer;
  Colors: array[0..7] of TColor;
begin
  if not ThemePluginsEnabled then
    Exit;

  Dark := IsDarkTheme;
  BgColor := ThemePanelColor;
  TxtColor := ThemeTextColor;
  GridClr := ThemeGridColor;
  WallClr := ThemeWallColor;

  if Dark then
    Move(CDarkSeriesColors, Colors, SizeOf(Colors))
  else
    Move(CLightSeriesColors, Colors, SizeOf(Colors));

  AChart.Color := BgColor;
  AChart.BackColor := BgColor;
  AChart.BackWall.Color := WallClr;
  AChart.BackWall.Brush.Color := WallClr;
  AChart.BackWall.Pen.Color := GridClr;

  // Axes
  AChart.BottomAxis.Axis.Color := TxtColor;
  AChart.BottomAxis.LabelsFont.Color := TxtColor;
  AChart.BottomAxis.Title.Font.Color := TxtColor;
  AChart.BottomAxis.Grid.Color := GridClr;
  AChart.BottomAxis.TicksInner.Color := TxtColor;
  AChart.BottomAxis.Ticks.Color := TxtColor;
  AChart.BottomAxis.MinorTicks.Color := TxtColor;

  AChart.LeftAxis.Axis.Color := TxtColor;
  AChart.LeftAxis.LabelsFont.Color := TxtColor;
  AChart.LeftAxis.Title.Font.Color := TxtColor;
  AChart.LeftAxis.Grid.Color := GridClr;
  AChart.LeftAxis.TicksInner.Color := TxtColor;
  AChart.LeftAxis.Ticks.Color := TxtColor;
  AChart.LeftAxis.MinorTicks.Color := TxtColor;

  AChart.RightAxis.Axis.Color := TxtColor;
  AChart.RightAxis.LabelsFont.Color := TxtColor;
  AChart.RightAxis.Title.Font.Color := TxtColor;
  AChart.RightAxis.Grid.Color := GridClr;

  AChart.TopAxis.Axis.Color := TxtColor;
  AChart.TopAxis.LabelsFont.Color := TxtColor;

  // Legend
  AChart.Legend.Color := BgColor;
  AChart.Legend.Font.Color := TxtColor;
  AChart.Legend.Frame.Color := GridClr;

  // Title
  AChart.Title.Font.Color := TxtColor;

  // Frame
  AChart.BevelOuter := bvNone;

  // Series colors
  for I := 0 to AChart.SeriesCount - 1 do
  begin
    if AChart.Series[I] is TFastLineSeries then
      TFastLineSeries(AChart.Series[I]).LinePen.Color :=
        Colors[I mod Length(Colors)]
    else if AChart.Series[I] is TLineSeries then
      TLineSeries(AChart.Series[I]).LinePen.Color :=
        Colors[I mod Length(Colors)]
    else if AChart.Series[I] is TPointSeries then
      TPointSeries(AChart.Series[I]).Pointer.Brush.Color :=
        Colors[I mod Length(Colors)]
    else
      AChart.Series[I].Color := Colors[I mod Length(Colors)];
  end;
end;

procedure ApplyRichEditTheme(ARichEdit: TCustomRichEdit);
begin
  if not ThemePluginsEnabled then
    Exit;

  TRichEditAccess(ARichEdit).Color := ThemePanelColor;
  TRichEditAccess(ARichEdit).Font.Color := ThemeTextColor;
end;

// Numeric compare of dotted version strings ('151.0.4129.101' > '151.0.4129.93');
// lexical ordering gets this wrong. Non-numeric parts compare as -1.
function CompareVersions(const A, B: string): Integer;
var
  PA, PB: TArray<string>;
  I, VA, VB: Integer;
begin
  PA := A.Split(['.']);
  PB := B.Split(['.']);
  for I := 0 to Max(High(PA), High(PB)) do
  begin
    if I <= High(PA) then VA := StrToIntDef(PA[I], -1) else VA := 0;
    if I <= High(PB) then VB := StrToIntDef(PB[I], -1) else VB := 0;
    if VA <> VB then Exit(Sign(VA - VB));
  end;
  Result := 0;
end;

function FindWebView2RuntimeFolder: string;
const
  CRuntimeRoots: array[0..1] of string = (
    'C:\Program Files (x86)\Microsoft\EdgeWebView\Application',
    'C:\Program Files\Microsoft\EdgeWebView\Application');
  CRuntimeExes: array[0..1] of string = ('msedgewebview2.exe', 'msedge.exe');
var
  Root, Dir, Exe, DirName, BestName: string;
  HasExe: Boolean;
begin
  Result := '';
  BestName := '';
  for Root in CRuntimeRoots do
  begin
    if not TDirectory.Exists(Root) then Continue;
    for Dir in TDirectory.GetDirectories(Root) do
    begin
      HasExe := False;
      for Exe in CRuntimeExes do
        if TFile.Exists(TPath.Combine(Dir, Exe)) then
        begin
          HasExe := True;
          Break;
        end;
      if not HasExe then Continue;
      DirName := ExtractFileName(ExcludeTrailingPathDelimiter(Dir));
      // The updater can leave a gutted older version dir behind; prefer the
      // newest dir that still carries the runtime exe.
      if (Result = '') or (CompareVersions(DirName, BestName) > 0) then
      begin
        Result := Dir;
        BestName := DirName;
      end;
    end;
  end;
end;

procedure ApplyBrowserColorScheme(const AWebView: IUnknown);
var
  WV13: ICoreWebView2_13;
  Profile: ICoreWebView2Profile;
  Scheme: COREWEBVIEW2_PREFERRED_COLOR_SCHEME;
begin
  // Unlike the chart/richedit helpers, this is NOT gated on
  // ThemePluginsEnabled: the browser's color scheme must always track the
  // active VCL style so scrollbars never mismatch the app's light/dark theme.
  if AWebView = nil then
    Exit;
  // ICoreWebView2_13 (Get_Profile) requires a reasonably recent WebView2
  // runtime; if unavailable there is nothing to configure, so bail quietly.
  if not Supports(AWebView, ICoreWebView2_13, WV13) then
    Exit;
  if not Succeeded(WV13.Get_Profile(Profile)) or (Profile = nil) then
    Exit;

  if IsDarkTheme then
    Scheme := COREWEBVIEW2_PREFERRED_COLOR_SCHEME_DARK
  else
    Scheme := COREWEBVIEW2_PREFERRED_COLOR_SCHEME_LIGHT;
  Profile.Set_PreferredColorScheme(Scheme);
end;

end.
