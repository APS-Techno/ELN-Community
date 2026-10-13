unit frame_JSONViewer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  SynEditHighlighter, SynHighlighterJSON, SynEdit, RzLabel, Vcl.ExtCtrls,
  RzPanel,
  unit_ELNPluginCore, unit_ELNPluginTypes;

type

  TframeJSONViewer = class(TFrame)
    Editor: TSynEdit;
    Syn: TSynJSONSyn;
    RzPanel1: TRzPanel;
    lblTitle: TRzLabel;
  public
    procedure DisplayJson(const ATitle, AText: string);
    function GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
  end;

implementation

uses
  System.JSON, System.StrUtils,
  unit_ELNThemeHelper, unit_ELNPreviewUtils;

{$R *.dfm}


procedure TframeJSONViewer.DisplayJson(const ATitle, AText: string);
var
  JVal: TJSONValue;
  Body: string;
begin
  lblTitle.Caption := ATitle;

  Body := AText;
  JVal := TJSONObject.ParseJSONValue(AText);
  if Assigned(JVal) then
  try
    // A machine-emitted one-liner is unreadable; anything already spread over
    // lines was formatted deliberately, so leave it alone.
    if Pos(#10, Trim(AText)) = 0 then
      Body := JVal.Format(2);
  finally
    JVal.Free;
  end;

  // The DFM sets UseCodeFolding, but SynEdit silently drops it while the
  // Highlighter reference is still an unresolved DFM fixup, so re-arm it here.
  Editor.UseCodeFolding := True;
  Editor.Lines.Text := Body;

  if ThemePluginsEnabled then
  begin
    Editor.Color := ThemePanelColor;
    Editor.Font.Color := ThemeTextColor;
    Editor.Gutter.Color := ThemePanelColor;
    Editor.Gutter.Font.Color := ThemeTextColor;
  end;
end;

function TframeJSONViewer.GetPreviewBitmap(MaxW, MaxH: Integer): TBitmap;
var
  Large: TBitmap;
  i, Y, LineH, MaxLines: Integer;
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
    for i := 0 to MaxLines - 1 do
    begin
      Large.Canvas.TextOut(4, Y, Editor.Lines[i]);
      Y := Y + LineH;
    end;

    Result := CreateScaledPreview(Large, MaxW, MaxH);
  finally
    Large.Free;
  end;
end;

end.
