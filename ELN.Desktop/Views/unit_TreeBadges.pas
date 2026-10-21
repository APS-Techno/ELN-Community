unit unit_TreeBadges;

{ Use the tree monitor DPI, not Screen.PixelsPerInch, for badge sizes. }

interface

uses
  Winapi.Windows, System.Types, Vcl.Graphics, VirtualTrees, VirtualTrees.Types;

const
  BADGE_TEAL    = TColor($008D8B0F);   
  BADGE_PLUM    = TColor($00A34F8E);   
  BADGE_RED     = TColor($001823B4);   
  BADGE_SLATE   = TColor($007C6B5B);   
  BADGE_VIOLET  = TColor($00955B6B);   
  BADGE_BLUE    = TColor($00D96F1E);   

type
  TBadgeColors = record
    Fill: TColor;
    Text: TColor;
  end;

function MixColor(A, B: TColor; T: Double): TColor;
/// WCAG relative luminance, 0 (black) .. 1 (white).
function RelativeLuminance(C: TColor): Double;
/// WCAG contrast ratio, 1 .. 21.
function ContrastRatio(A, B: TColor): Double;
/// Tinted fill and label colour for ABase on ABackground. The label is pushed
/// darker (light background) or lighter (dark background) until it reaches a
/// 4.5:1 contrast against the fill, or as far as it can go.
function BadgeColors(ABase, ABackground: TColor): TBadgeColors;

function TreeRowBackground(ATree: TBaseVirtualTree; ANode: PVirtualNode): TColor;

/// True when a node the user can see is expanded. Expanded nodes hidden under
/// a collapsed parent do not count - FullCollapse can leave those behind.
function TreeHasVisibleExpanded(ATree: TBaseVirtualTree): Boolean;

const
  TREE_ACTION_COLLAPSE = 0;
  TREE_ACTION_EXPAND   = 1;
  TREE_ACTION_FOCUS    = 2;
  TREE_ACTION_COUNT    = 3;

function TreeActionButtonRect(const ACell: TRect; APPI, AIndex: Integer): TRect;
function TreeActionAt(const ACell: TRect; APPI: Integer; const P: TPoint): Integer;
procedure DrawTreeActions(ACanvas: TCanvas; const ACell: TRect; APPI: Integer;
  ABackground: TColor; AHot: Integer);

type
  /// Draws soft-pill badges on one canvas for one paint call. Create it,
  /// draw, free it: the destructor restores the canvas font, brush and pen.
  TBadgePainter = class
  private
    FCanvas: TCanvas;
    FPPI: Integer;
    FBackground: TColor;
    FSavedFont: TFont;
    FBadgeFont: TFont;
    FSavedBrushColor, FSavedPenColor: TColor;
    FSavedBrushStyle: TBrushStyle;
    FSavedPenWidth: Integer;
    FPadX, FPadY, FGap: Integer;
    function PillHeight: Integer;
    procedure Paint(const R: TRect; const AText: string; ABase: TColor);
  public
    constructor Create(ACanvas: TCanvas; ABaseFont: TFont; APPI: Integer;
      ABackground: TColor);
    destructor Destroy; override;
    function Width(const AText: string): Integer;
    property Gap: Integer read FGap;
    /// Draws at X, vertically centred in ACell; returns the pill's right
    /// edge. Draws nothing and returns X when the pill would pass ALimit.
    function DrawAt(X: Integer; const ACell: TRect; const AText: string;
      ABase: TColor; ALimit: Integer = MaxInt): Integer;
    function DrawRightAligned(ARight: Integer; const ACell: TRect;
      const AText: string; ABase: TColor): Integer;
  end;

implementation

uses
  System.SysUtils, System.Math, Vcl.Themes,
  Winapi.GDIPAPI, Winapi.GDIPOBJ;

function Channels(C: TColor; out R, G, B: Byte): TColor;
begin
  Result := ColorToRGB(C);
  R := GetRValue(Result);
  G := GetGValue(Result);
  B := GetBValue(Result);
end;

function MixColor(A, B: TColor; T: Double): TColor;
var
  Ar, Ag, Ab, Br, Bg, Bb: Byte;
begin
  T := EnsureRange(T, 0, 1);
  Channels(A, Ar, Ag, Ab);
  Channels(B, Br, Bg, Bb);
  Result := RGB(
    Round(Ar + (Br - Ar) * T),
    Round(Ag + (Bg - Ag) * T),
    Round(Ab + (Bb - Ab) * T));
end;

function RelativeLuminance(C: TColor): Double;

  function Lin(V: Byte): Double;
  var
    S: Double;
  begin
    S := V / 255;
    if S <= 0.03928 then
      Result := S / 12.92
    else
      Result := Power((S + 0.055) / 1.055, 2.4);
  end;

var
  R, G, B: Byte;
begin
  Channels(C, R, G, B);
  Result := 0.2126 * Lin(R) + 0.7152 * Lin(G) + 0.0722 * Lin(B);
end;

function ContrastRatio(A, B: TColor): Double;
var
  LA, LB: Double;
begin
  LA := RelativeLuminance(A);
  LB := RelativeLuminance(B);
  Result := (Max(LA, LB) + 0.05) / (Min(LA, LB) + 0.05);
end;

function BadgeColors(ABase, ABackground: TColor): TBadgeColors;
const
  MIN_CONTRAST = 4.5;
var
  Dark: Boolean;
  Toward: TColor;
  T: Double;
begin
  Dark := RelativeLuminance(ABackground) < 0.3;
  if Dark then
  begin
    Result.Fill := MixColor(ABackground, ABase, 0.30);
    Toward := clWhite;
    T := 0.45;
  end
  else
  begin
    Result.Fill := MixColor(ABackground, ABase, 0.16);
    Toward := clBlack;
    T := 0.25;
  end;
  Result.Text := MixColor(ABase, Toward, T);
  while (ContrastRatio(Result.Text, Result.Fill) < MIN_CONTRAST) and (T < 0.95) do
  begin
    T := T + 0.1;
    Result.Text := MixColor(ABase, Toward, T);
  end;
end;

function TreeRowBackground(ATree: TBaseVirtualTree; ANode: PVirtualNode): TColor;
var
  VST: TVirtualStringTree;
begin
  VST := ATree as TVirtualStringTree;
  if Assigned(ANode) and (vsSelected in ANode.States) then
  begin
    if VST.Focused then
      Result := VST.Colors.FocusedSelectionColor
    else
      Result := VST.Colors.UnfocusedSelectionColor;
  end
  else
    Result := VST.Color;
  Result := StyleServices.GetSystemColor(Result);
end;

function TreeHasVisibleExpanded(ATree: TBaseVirtualTree): Boolean;
var
  N: PVirtualNode;
begin
  N := ATree.GetFirstVisible;
  while Assigned(N) do
  begin
    if ATree.Expanded[N] and ATree.HasChildren[N] then
      Exit(True);
    N := ATree.GetNextVisible(N);
  end;
  Result := False;
end;

function GPColor(C: TColor; Alpha: Byte = 255): TGPColor;
begin
  C := ColorToRGB(C);
  Result := MakeColor(Alpha, GetRValue(C), GetGValue(C), GetBValue(C));
end;

/// Rounded-rectangle path; D is the corner diameter. Caller frees.
function RoundRectPath(L, T, W, H, D: Single): TGPGraphicsPath;
begin
  D := Min(D, Min(W, H));
  Result := TGPGraphicsPath.Create;
  Result.AddArc(L, T, D, D, 180, 90);
  Result.AddArc(L + W - D, T, D, D, 270, 90);
  Result.AddArc(L + W - D, T + H - D, D, D, 0, 90);
  Result.AddArc(L, T + H - D, D, D, 90, 90);
  Result.CloseFigure;
end;

procedure FillRoundRect(G: TGPGraphics; const R: TRect; D: Single; C: TColor;
  Alpha: Byte = 255);
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
begin
  Path := RoundRectPath(R.Left, R.Top, R.Width, R.Height, D);
  try
    Brush := TGPSolidBrush.Create(GPColor(C, Alpha));
    try
      G.FillPath(Brush, Path);
    finally
      Brush.Free;
    end;
  finally
    Path.Free;
  end;
end;

function TreeActionButtonRect(const ACell: TRect; APPI, AIndex: Integer): TRect;
var
  S, Pad, Spacing, Right, Y: Integer;
begin
  if APPI <= 0 then
    APPI := 96;
  Pad := Max(1, MulDiv(1, APPI, 96));
  Spacing := MulDiv(2, APPI, 96);
  S := Min(MulDiv(22, APPI, 96), ACell.Height - 2 * Pad);
  Y := ACell.Top + (ACell.Height - S) div 2;
  Right := ACell.Right - MulDiv(6, APPI, 96)
    - (TREE_ACTION_COUNT - 1 - AIndex) * (S + Spacing);
  Result := Rect(Right - S, Y, Right, Y + S);
end;

function TreeActionAt(const ACell: TRect; APPI: Integer; const P: TPoint): Integer;
var
  I: Integer;
begin
  for I := 0 to TREE_ACTION_COUNT - 1 do
    if TreeActionButtonRect(ACell, APPI, I).Contains(P) then
      Exit(I);
  Result := -1;
end;

procedure DrawTreeActions(ACanvas: TCanvas; const ACell: TRect; APPI: Integer;
  ABackground: TColor; AHot: Integer);
const
  DARK_GLYPH = TColor($001F1F1F);
var
  Fg: TColor;
  G: TGPGraphics;
  Pen: TGPPen;
  Brush: TGPSolidBrush;
  Area, B: TRect;
  I: Integer;
  U, Cx, Cy: Single;

  procedure Chevron(Y, Dy: Single);
  var
    Pts: array[0..2] of TGPPointF;
  begin
    Pts[0] := MakePoint(Cx - 3.5 * U, Y);
    Pts[1] := MakePoint(Cx, Y + Dy * 3 * U);
    Pts[2] := MakePoint(Cx + 3.5 * U, Y);
    G.DrawLines(Pen, PGPPointF(@Pts[0]), 3);
  end;

begin
  if APPI <= 0 then
    APPI := 96;
  U := APPI / 96;
  if ContrastRatio(clWhite, ABackground) >= ContrastRatio(DARK_GLYPH, ABackground) then
    Fg := clWhite
  else
    Fg := DARK_GLYPH;

  Area := TreeActionButtonRect(ACell, APPI, 0);
  Area.Right := TreeActionButtonRect(ACell, APPI, TREE_ACTION_COUNT - 1).Right;
  Area.Left := Area.Left - MulDiv(4, APPI, 96);
  Area.Top := ACell.Top;
  Area.Bottom := ACell.Bottom;

  G := TGPGraphics.Create(ACanvas.Handle);
  try
    Brush := TGPSolidBrush.Create(GPColor(ABackground));
    try
      G.FillRectangle(Brush, Area.Left, Area.Top, Area.Width, Area.Height);
    finally
      Brush.Free;
    end;

    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetPixelOffsetMode(PixelOffsetModeHalf);
    Pen := TGPPen.Create(GPColor(Fg, 235), Max(1, Round(1.25 * U)));
    Brush := TGPSolidBrush.Create(GPColor(Fg, 235));
    try
      Pen.SetLineJoin(LineJoinRound);
      Pen.SetStartCap(LineCapRound);
      Pen.SetEndCap(LineCapRound);
      for I := 0 to TREE_ACTION_COUNT - 1 do
      begin
        B := TreeActionButtonRect(ACell, APPI, I);
        if I = AHot then
          FillRoundRect(G, B, 8 * U, Fg, 40);

        Cx := B.Left + B.Width / 2;
        Cy := B.Top + B.Height / 2;
        case I of
          TREE_ACTION_COLLAPSE:
            begin
              Chevron(Cy - 5.5 * U, 1);
              Chevron(Cy + 5.5 * U, -1);
            end;
          TREE_ACTION_EXPAND:
            begin
              Chevron(Cy - 1.5 * U, -1);
              Chevron(Cy + 1.5 * U, 1);
            end;
          TREE_ACTION_FOCUS:
            begin
              G.DrawEllipse(Pen, Cx - 5 * U, Cy - 5 * U, 10 * U, 10 * U);
              G.FillEllipse(Brush, Cx - 1.75 * U, Cy - 1.75 * U, 3.5 * U, 3.5 * U);
            end;
        end;
      end;
    finally
      Brush.Free;
      Pen.Free;
    end;
  finally
    G.Free;
  end;
end;


constructor TBadgePainter.Create(ACanvas: TCanvas; ABaseFont: TFont;
  APPI: Integer; ABackground: TColor);
begin
  inherited Create;
  FCanvas := ACanvas;
  FPPI := APPI;
  if FPPI <= 0 then
    FPPI := 96;
  FBackground := ABackground;

  FSavedFont := TFont.Create;
  FSavedFont.Assign(FCanvas.Font);
  FSavedBrushColor := FCanvas.Brush.Color;
  FSavedBrushStyle := FCanvas.Brush.Style;
  FSavedPenColor := FCanvas.Pen.Color;
  FSavedPenWidth := FCanvas.Pen.Width;

  // A semibold step smaller than the tree font. Height is in pixels and the
  // tree font is already scaled for its monitor, so this follows the DPI.
  // Re-applied on every call: the caller may draw its own text in between.
  FBadgeFont := TFont.Create;
  FBadgeFont.Assign(ABaseFont);
  FBadgeFont.Height := Round(ABaseFont.Height * 0.86);
  if SameText(ABaseFont.Name, 'Segoe UI') then
  begin
    FBadgeFont.Name := 'Segoe UI Semibold';
    FBadgeFont.Style := [];
  end
  else
    FBadgeFont.Style := [fsBold];

  FPadX := MulDiv(6, FPPI, 96);
  FPadY := MulDiv(2, FPPI, 96);
  FGap := MulDiv(5, FPPI, 96);
end;

destructor TBadgePainter.Destroy;
begin
  FBadgeFont.Free;
  if Assigned(FSavedFont) then
  begin
    FCanvas.Font.Assign(FSavedFont);
    FSavedFont.Free;
  end;
  FCanvas.Brush.Color := FSavedBrushColor;
  FCanvas.Brush.Style := FSavedBrushStyle;
  FCanvas.Pen.Color := FSavedPenColor;
  FCanvas.Pen.Width := FSavedPenWidth;
  inherited;
end;

function TBadgePainter.PillHeight: Integer;
begin
  FCanvas.Font.Assign(FBadgeFont);
  Result := FCanvas.TextHeight('Tg') + 2 * FPadY;
end;

function TBadgePainter.Width(const AText: string): Integer;
var
  H: Integer;
begin
  H := PillHeight;   
  Result := Max(FCanvas.TextWidth(AText) + 2 * FPadX, H);
end;

procedure TBadgePainter.Paint(const R: TRect; const AText: string; ABase: TColor);
var
  Colors: TBadgeColors;
  G: TGPGraphics;
  TextR: TRect;
begin
  Colors := BadgeColors(ABase, FBackground);

  G := TGPGraphics.Create(FCanvas.Handle);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetPixelOffsetMode(PixelOffsetModeHalf);
    FillRoundRect(G, R, 2 * MulDiv(4, FPPI, 96), Colors.Fill);
  finally
    G.Free;   // flushes to the DC before the GDI text below
  end;

  // GDI text keeps ClearType; it blends over the opaque fill just drawn.
  FCanvas.Font.Assign(FBadgeFont);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Font.Color := Colors.Text;
  TextR := R;
  Winapi.Windows.DrawTextW(FCanvas.Handle, PWideChar(AText), Length(AText),
    TextR, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

function TBadgePainter.DrawAt(X: Integer; const ACell: TRect;
  const AText: string; ABase: TColor; ALimit: Integer): Integer;
var
  W, H, Y: Integer;
begin
  W := Width(AText);
  if X + W > ALimit then
    Exit(X);
  H := Min(PillHeight, ACell.Height - 2);
  Y := ACell.Top + (ACell.Height - H) div 2;
  Paint(Rect(X, Y, X + W, Y + H), AText, ABase);
  Result := X + W;
end;

function TBadgePainter.DrawRightAligned(ARight: Integer; const ACell: TRect;
  const AText: string; ABase: TColor): Integer;
var
  W: Integer;
begin
  W := Width(AText);
  Result := ARight - W;
  DrawAt(Result, ACell, AText, ABase);
end;

end.
