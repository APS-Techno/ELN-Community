unit frame_RecipeViewer;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  SynEditHighlighter, SynHighlighterGeneral, SynEdit, RzLabel, RzPanel;

type
  TframeRecipeViewer = class(TFrame)
    Editor: TSynEdit;
    Syn: TSynGeneralSyn;
    pnlHeader: TRzPanel;
    lblTitle: TRzLabel;
  public
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
  end;

implementation

uses
  unit_ELNPreviewUtils, unit_ELNThemeHelper;

{$R *.dfm}

function TframeRecipeViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
  I, Y, LineH, MaxLines: Integer;
begin
  Result := nil;
  if Editor.Lines.Count = 0 then
    Exit;

  Large := TBitmap.Create;
  try
    Large.PixelFormat := pf32bit;
    Large.SetSize(800, 600);
    Large.Canvas.Brush.Color := ThemePanelColor;
    Large.Canvas.FillRect(Rect(0, 0, 800, 600));
    Large.Canvas.Font.Name := Editor.Font.Name;
    Large.Canvas.Font.Size := Editor.Font.Size;
    Large.Canvas.Font.Color := ThemeTextColor;

    LineH := Large.Canvas.TextHeight('Wg') + 2;
    MaxLines := 600 div LineH;
    if MaxLines > Editor.Lines.Count then
      MaxLines := Editor.Lines.Count;

    Y := 4;
    for I := 0 to MaxLines - 1 do
    begin
      Large.Canvas.TextOut(4, Y, Editor.Lines[I]);
      Y := Y + LineH;
    end;

    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

end.
