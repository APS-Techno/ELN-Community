unit dlg_HypothesisPick;

{ Proposed hypotheses accept References only; Runs require approval. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ExtCtrls, RzPanel, RzCommon,
  unit_Hypothesis, unit_HypothesisModel, unit_HypothesesVM;

type
  TdlgHypothesisPick = class(TForm)
    lblHint: TLabel;
    lstHypotheses: TListBox;
    rgRole: TRadioGroup;
    pnlButtons: TRzPanel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure lstHypothesesClick(Sender: TObject);
    procedure lstHypothesesDblClick(Sender: TObject);
  private
    FChoices: TArray<THypothesisSummary>;
    procedure UpdateRoleForSelection;
  public
    class function Execute(const AChoices: TArray<THypothesisSummary>;
      out AHypothesisId: Integer; out ARole: THypothesisRunRole;
      const AHint: string = ''): Boolean; static;
  end;

implementation

{$R *.dfm}

uses
  Vcl.Dialogs;

procedure TdlgHypothesisPick.UpdateRoleForSelection;
var
  Idx: Integer;
  ApprovedNow: Boolean;
begin
  Idx := lstHypotheses.ItemIndex;
  ApprovedNow := (Idx >= 0) and (Idx <= High(FChoices)) and
    (FChoices[Idx].Status = hsApproved);
  rgRole.Buttons[0].Enabled := ApprovedNow;    
  if not ApprovedNow then
    rgRole.ItemIndex := 1;                     
end;

procedure TdlgHypothesisPick.lstHypothesesClick(Sender: TObject);
begin
  UpdateRoleForSelection;
end;

procedure TdlgHypothesisPick.lstHypothesesDblClick(Sender: TObject);
begin
  if lstHypotheses.ItemIndex >= 0 then
    ModalResult := mrOk;
end;

class function TdlgHypothesisPick.Execute(const AChoices: TArray<THypothesisSummary>;
  out AHypothesisId: Integer; out ARole: THypothesisRunRole;
  const AHint: string): Boolean;
var
  Dlg: TdlgHypothesisPick;
  S: THypothesisSummary;
begin
  AHypothesisId := 0;
  ARole := hrrRun;
  if Length(AChoices) = 0 then
  begin
    MessageDlg('There is no hypothesis in this project you can attach to.',
      mtInformation, [mbOK], 0);
    Exit(False);
  end;
  Dlg := TdlgHypothesisPick.Create(Application);
  try
    Dlg.FChoices := AChoices;
    if AHint <> '' then
      Dlg.lblHint.Caption := AHint;
    for S in AChoices do
      Dlg.lstHypotheses.Items.AddObject(Format('#%d  %s  (%s)',
        [S.Id, S.Title, THypothesesVM.StatusCaption(S)]), TObject(NativeInt(S.Id)));
    Dlg.lstHypotheses.ItemIndex := 0;
    Dlg.UpdateRoleForSelection;
    Result := (Dlg.ShowModal = mrOk) and (Dlg.lstHypotheses.ItemIndex >= 0);
    if Result then
    begin
      AHypothesisId := Integer(NativeInt(
        Dlg.lstHypotheses.Items.Objects[Dlg.lstHypotheses.ItemIndex]));
      ARole := THypothesisRunRole(Dlg.rgRole.ItemIndex);
    end;
  finally
    Dlg.Free;
  end;
end;

end.
