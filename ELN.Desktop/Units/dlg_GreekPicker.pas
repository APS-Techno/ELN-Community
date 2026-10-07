unit dlg_GreekPicker;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.Buttons, Vcl.ExtCtrls, Vcl.Graphics;

type
  TdlgGreekPicker = class(TForm)
  private
    FSelectedChar: string;
    procedure CharButtonClick(Sender: TObject);
    procedure BuildGrid;
    function Sc(Value: Integer): Integer;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    class function Pick(AnchorControl: TControl): string;
  end;

implementation

const
  Cols = 12;

  LowerGreek: array[0..23] of Char = (
    #$03B1, #$03B2, #$03B3, #$03B4, #$03B5, #$03B6,
    #$03B7, #$03B8, #$03B9, #$03BA, #$03BB, #$03BC,
    #$03BD, #$03BE, #$03BF, #$03C0, #$03C1, #$03C3,
    #$03C4, #$03C5, #$03C6, #$03C7, #$03C8, #$03C9
  );

  UpperGreek: array[0..23] of Char = (
    #$0391, #$0392, #$0393, #$0394, #$0395, #$0396,
    #$0397, #$0398, #$0399, #$039A, #$039B, #$039C,
    #$039D, #$039E, #$039F, #$03A0, #$03A1, #$03A3,
    #$03A4, #$03A5, #$03A6, #$03A7, #$03A8, #$03A9
  );

{ TdlgGreekPicker }

class function TdlgGreekPicker.Pick(AnchorControl: TControl): string;
var
  Dlg: TdlgGreekPicker;
  Pt: TPoint;
  Mon: TMonitor;
  R: TRect;
begin
  Result := '';
  Dlg := TdlgGreekPicker.CreateNew(Application);
  try
    Dlg.KeyPreview := True;
    Dlg.BuildGrid;

    // Position below the anchor control
    Pt := AnchorControl.ClientToScreen(Point(0, AnchorControl.Height));
    Dlg.Left := Pt.X;
    Dlg.Top := Pt.Y;

    // Keep on screen
    Mon := Screen.MonitorFromPoint(Pt);
    R := Mon.WorkareaRect;
    if Dlg.Left + Dlg.Width > R.Right then
      Dlg.Left := R.Right - Dlg.Width;
    if Dlg.Top + Dlg.Height > R.Bottom then
    begin
      Pt := AnchorControl.ClientToScreen(Point(0, 0));
      Dlg.Top := Pt.Y - Dlg.Height;
    end;

    if Dlg.ShowModal = mrOk then
      Result := Dlg.FSelectedChar;
  finally
    Dlg.Free;
  end;
end;

procedure TdlgGreekPicker.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP or WS_BORDER;
  Params.ExStyle := WS_EX_TOOLWINDOW;
end;

procedure TdlgGreekPicker.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    ModalResult := mrCancel
  else
    inherited;
end;

function TdlgGreekPicker.Sc(Value: Integer): Integer;
begin
  Result := MulDiv(Value, CurrentPPI, 96);
end;

procedure TdlgGreekPicker.BuildGrid;
var
  BtnSize, Gap, X, Y, I, TotalW: Integer;

  procedure AddButton(const Ch: string);
  var
    Btn: TSpeedButton;
  begin
    if X + BtnSize > TotalW then
    begin
      X := Gap;
      Y := Y + BtnSize + Gap;
    end;
    Btn := TSpeedButton.Create(Self);
    Btn.Parent := Self;
    Btn.SetBounds(X, Y, BtnSize, BtnSize);
    Btn.Caption := Ch;
    Btn.Flat := True;
    Btn.Font.Name := 'Segoe UI';
    Btn.Font.Size := 11;
    Btn.OnClick := CharButtonClick;
    X := X + BtnSize + Gap;
  end;

  procedure AddSeparator;
  var
    Sep: TBevel;
  begin
    if X > Gap then
      Y := Y + BtnSize + Gap;
    Sep := TBevel.Create(Self);
    Sep.Parent := Self;
    Sep.SetBounds(Gap, Y, TotalW - 2 * Gap, 2);
    Sep.Shape := bsBottomLine;
    Y := Y + Gap + 2;
    X := Gap;
  end;

begin
  BtnSize := Sc(28);
  Gap := Sc(3);
  TotalW := Cols * (BtnSize + Gap) + Gap;

  X := Gap;
  Y := Gap;

  // Lowercase Greek
  for I := 0 to High(LowerGreek) do
    AddButton(LowerGreek[I]);

  AddSeparator;

  // Uppercase Greek
  for I := 0 to High(UpperGreek) do
    AddButton(UpperGreek[I]);

  AddSeparator;

  // Common scientific symbols
  AddButton(#$00B5);        // µ
  AddButton(#$00B0);        // °
  AddButton(#$00B1);        // ±
  AddButton(#$00C5);        // Å
  AddButton(#$00B2);        // ²
  AddButton(#$00B3);        // ³
  AddButton(#$207B#$00B9);  // ⁻¹

  if X > Gap then
    Y := Y + BtnSize + Gap;

  ClientWidth := TotalW;
  ClientHeight := Y;
end;

procedure TdlgGreekPicker.CharButtonClick(Sender: TObject);
begin
  FSelectedChar := TSpeedButton(Sender).Caption;
  ModalResult := mrOk;
end;

end.
