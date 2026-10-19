unit dlg_BatchSummary;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Types,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzCommon, RzPanel, RzLabel, RzButton,
  unit_ItemTreeBatch;

type
  TdlgBatchSummary = class(TForm)
    pnlBottom: TRzPanel;
    pnlMain: TRzPanel;
    lblMessage: TRzLabel;
    memDetails: TMemo;
    btnOk: TRzBitBtn;
    btnCancel: TRzBitBtn;
  private
    procedure Setup(const ACaption, AMessage, ADetails, AOkCaption: string;
      AShowCancel: Boolean);
  public
    class function Confirm(const ACaption, AQuestion: string;
      const Skips: TArray<TBatchSkip>; const AOkCaption: string): Boolean; static;
    class procedure Report(const ACaption: string; Done: Integer;
      const Skips, Failures: TArray<TBatchSkip>;
      const ResultText: string = ''); static;
  end;

implementation

{$R *.dfm}

procedure TdlgBatchSummary.Setup(const ACaption, AMessage, ADetails,
  AOkCaption: string; AShowCancel: Boolean);
var
  R: TRect;
begin
  Caption := ACaption;
  lblMessage.Caption := AMessage;
  Canvas.Font.Assign(lblMessage.Font);
  R := Rect(0, 0, lblMessage.Width, 0);
  DrawText(Canvas.Handle, PChar(AMessage), -1, R,
    DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  if R.Bottom > lblMessage.Height then
    lblMessage.Height := R.Bottom;
  btnOk.Caption := AOkCaption;
  btnCancel.Visible := AShowCancel;
  memDetails.Text := ADetails;
  memDetails.Visible := ADetails <> '';
  if not memDetails.Visible then
    ClientHeight := pnlBottom.Height + pnlBottom.Margins.Top + pnlBottom.Margins.Bottom +
      lblMessage.Height + lblMessage.Margins.Top + lblMessage.Margins.Bottom +
      pnlMain.Margins.Top + 2 * (lblMessage.Left);
end;

class function TdlgBatchSummary.Confirm(const ACaption, AQuestion: string;
  const Skips: TArray<TBatchSkip>; const AOkCaption: string): Boolean;
var
  Dlg: TdlgBatchSummary;
begin
  Dlg := TdlgBatchSummary.Create(Application);
  try
    Dlg.Setup(ACaption, AQuestion, TItemTreeBatch.FormatSkips(Skips), AOkCaption, True);
    Result := Dlg.ShowModal = mrOk;
  finally
    Dlg.Free;
  end;
end;

class procedure TdlgBatchSummary.Report(const ACaption: string; Done: Integer;
  const Skips, Failures: TArray<TBatchSkip>; const ResultText: string);
var
  Dlg: TdlgBatchSummary;
  All: TArray<TBatchSkip>;
  Summary: string;
  I: Integer;
begin
  SetLength(All, Length(Skips) + Length(Failures));
  for I := 0 to High(Skips) do
    All[I] := Skips[I];
  for I := 0 to High(Failures) do
    All[Length(Skips) + I] := Failures[I];
  Dlg := TdlgBatchSummary.Create(Application);
  try
    Summary := Format('%d done, %d skipped, %d failed.',
      [Done, Length(Skips), Length(Failures)]);
    if ResultText <> '' then
      Summary := ResultText + sLineBreak + Summary;
    Dlg.Setup(ACaption, Summary, TItemTreeBatch.FormatSkips(All), 'OK', False);
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
