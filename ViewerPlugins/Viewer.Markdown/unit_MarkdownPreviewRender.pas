unit unit_MarkdownPreviewRender;

{ The batch preview queue does not pump messages between loading and capture,
  so WebView2 has no rendered page. Render source text for that path. }

interface

uses
  Vcl.Graphics;

function RenderMarkdownPreview(const AMarkdown: string;
  MaxW, MaxH: Integer): TBitmap;

implementation

uses
  System.SysUtils, System.Types,
  Winapi.Windows,
  unit_MarkdownPreviewText,
  unit_ELNThemeHelper,
  unit_ELNPreviewUtils;

const
  { Draw large and downsample with WIC to avoid hinting text at thumbnail size. }
  CanvasW    = 800;
  CanvasH    = 600;
  MarginPx   = 28;
  IndentPx   = 22;
  LineGapPx  = 4;
  BlankGapPx = 10;
  RuleGapPx  = 16;
  MaxLines   = 120;

  BodyFont = 'Segoe UI';
  CodeFont = 'Consolas';

procedure ApplyStyle(ACanvas: TCanvas; AStyle: TPreviewLineStyle; AFg: TColor);
begin
  ACanvas.Font.Name := BodyFont;
  ACanvas.Font.Color := AFg;
  ACanvas.Font.Style := [];
  case AStyle of
    plsH1:
      begin
        ACanvas.Font.Size := 26;
        ACanvas.Font.Style := [fsBold];
      end;
    plsH2:
      begin
        ACanvas.Font.Size := 20;
        ACanvas.Font.Style := [fsBold];
      end;
    plsH3:
      begin
        ACanvas.Font.Size := 16;
        ACanvas.Font.Style := [fsBold];
      end;
    plsCode:
      begin
        ACanvas.Font.Name := CodeFont;
        ACanvas.Font.Size := 12;
      end;
    plsQuote:
      begin
        ACanvas.Font.Size := 13;
        ACanvas.Font.Style := [fsItalic];
      end;
  else
    ACanvas.Font.Size := 13;
  end;
end;

{ Return type and locals are qualified: Winapi.Windows also declares a TBitmap
  (the GDI BITMAP record) and, being used later, it wins the name here. }
function RenderMarkdownPreview(const AMarkdown: string;
  MaxW, MaxH: Integer): Vcl.Graphics.TBitmap;
const
  DrawFlags = DT_WORDBREAK or DT_NOPREFIX or DT_EXPANDTABS;
var
  Lines: TArray<TPreviewLine>;
  Large: Vcl.Graphics.TBitmap;
  I, X, Y, TextH, Right: Integer;
  R: TRect;
  Fg, Bg: TColor;
  L: TPreviewLine;
begin
  Result := nil;
  if (MaxW <= 0) or (MaxH <= 0) then
    Exit;

  Lines := BuildPreviewLines(AMarkdown, MaxLines);
  if Length(Lines) = 0 then
    Exit;

  Bg := ThemePanelColor;
  Fg := ThemeTextColor;
  Right := CanvasW - MarginPx;

  Large := Vcl.Graphics.TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(CanvasW, CanvasH);
    Large.Canvas.Brush.Style := bsSolid;
    Large.Canvas.Brush.Color := Bg;
    Large.Canvas.FillRect(Rect(0, 0, CanvasW, CanvasH));

    Y := MarginPx;
    for I := 0 to High(Lines) do
    begin
      if Y >= CanvasH - MarginPx then
        Break;

      L := Lines[I];

      if L.Style = plsBlank then
      begin
        Inc(Y, BlankGapPx);
        Continue;
      end;

      if L.Style = plsRule then
      begin
        Large.Canvas.Pen.Color := ThemeGridColor;
        Large.Canvas.Pen.Width := 2;
        Large.Canvas.MoveTo(MarginPx, Y + RuleGapPx div 2);
        Large.Canvas.LineTo(Right, Y + RuleGapPx div 2);
        Inc(Y, RuleGapPx);
        Continue;
      end;

      if L.Text = '' then
      begin
        Inc(Y, BlankGapPx);
        Continue;
      end;

      X := MarginPx + L.Indent * IndentPx;
      if L.Style = plsQuote then
        Inc(X, 12);

      ApplyStyle(Large.Canvas, L.Style, Fg);

      { Measure first so the code/quote decorations can be sized to the wrapped
        block before the text is painted over them. }
      R := Rect(X, Y, Right, CanvasH);
      TextH := Winapi.Windows.DrawText(Large.Canvas.Handle, PChar(L.Text), -1, R,
        DrawFlags or DT_CALCRECT);
      if TextH <= 0 then
      begin
        Inc(Y, BlankGapPx);
        Continue;
      end;

      { Stop before a line that won't fit rather than painting its code/quote
        decoration under text the bottom margin then clips away. The I > 0 guard
        keeps a single over-tall first line visible instead of rendering blank. }
      if (I > 0) and (Y + TextH > CanvasH - MarginPx) then
        Break;

      case L.Style of
        plsCode:
          begin
            Large.Canvas.Brush.Style := bsSolid;
            Large.Canvas.Brush.Color := ThemeWallColor;
            Large.Canvas.FillRect(Rect(MarginPx, Y - 2, Right, Y + TextH + 2));
          end;
        plsQuote:
          begin
            Large.Canvas.Brush.Style := bsSolid;
            Large.Canvas.Brush.Color := ThemeGridColor;
            Large.Canvas.FillRect(Rect(MarginPx, Y, MarginPx + 3, Y + TextH));
          end;
      end;

      Large.Canvas.Brush.Style := bsClear;
      R := Rect(X, Y, Right, CanvasH - MarginPx);
      Winapi.Windows.DrawText(Large.Canvas.Handle, PChar(L.Text), -1, R, DrawFlags);

      Inc(Y, TextH + LineGapPx);
    end;

    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

end.
