unit dlg_EvidencePick;

{
  Cites evidence for the selected hypothesis: whole item, a file, or a value
  (Task 7, spec 10).

  Pre-flight C6/C7: the left list is built from THypothesesVM.EvidenceSources,
  never from Detail.Runs directly - it already carries only readable, live
  run/reference items plus their live descendants, indented by depth, and
  the right list from EvidenceChoicesFor's live queries (never TItem.Files/
  Values, which a long-lived TObjectManager loads once and never updates).
  An unreadable foreign item is never offered here (C7): EvidenceSources
  omits it entirely, so there is no title to leak.

  Lives in ELN.Desktop\Dialogs\Hypotheses: allowed to name the view model
  (unit_HypothesesVM), never the gate model.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.StrUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzPanel, RzCommon,
  unit_HypothesesVM;

type
  TdlgEvidencePick = class(TForm)
    lstItems: TListBox;
    lstChoices: TListBox;
    pnlBottom: TRzPanel;
    lblNote: TLabel;
    edNote: TEdit;
    btnOK: TButton;
    btnCancel: TButton;
    procedure lstItemsClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
  private
    FVM: THypothesesVM;
    FChoices: TArray<TEvidenceChoice>;
  public
    class function Execute(AVM: THypothesesVM; out AChoice: TEvidenceChoice;
      out ANote: string): Boolean; static;
  end;

implementation

{$R *.dfm}

const
  INDENT_UNIT = '    ';  // 4 spaces per depth level, one indent per generation

procedure TdlgEvidencePick.lstItemsClick(Sender: TObject);
var
  C: TEvidenceChoice;
begin
  lstChoices.Items.Clear;
  if lstItems.ItemIndex < 0 then Exit;
  FChoices := FVM.EvidenceChoicesFor(
    Integer(NativeInt(lstItems.Items.Objects[lstItems.ItemIndex])));
  for C in FChoices do
    lstChoices.Items.Add(C.Caption);
  if lstChoices.Items.Count > 0 then
    lstChoices.ItemIndex := 0;
end;

procedure TdlgEvidencePick.btnOKClick(Sender: TObject);
begin
  if lstChoices.ItemIndex < 0 then
  begin
    MessageDlg('Choose what to cite.', mtWarning, [mbOK], 0);
    Exit;
  end;
  ModalResult := mrOk;
end;

class function TdlgEvidencePick.Execute(AVM: THypothesesVM;
  out AChoice: TEvidenceChoice; out ANote: string): Boolean;
var
  Dlg: TdlgEvidencePick;
  Sources: TArray<TEvidenceSource>;
  S: TEvidenceSource;
begin
  AChoice := Default(TEvidenceChoice);
  ANote := '';
  Sources := AVM.EvidenceSources;
  if Length(Sources) = 0 then
  begin
    MessageDlg('Attach a run or reference item first; evidence is cited from ' +
      'those items.', mtInformation, [mbOK], 0);
    Exit(False);
  end;
  Dlg := TdlgEvidencePick.Create(Application);
  try
    Dlg.FVM := AVM;
    for S in Sources do
      Dlg.lstItems.Items.AddObject(DupeString(INDENT_UNIT, S.Depth) + S.Caption,
        TObject(NativeInt(S.ItemId)));
    if Dlg.lstItems.Items.Count > 0 then
    begin
      Dlg.lstItems.ItemIndex := 0;
      Dlg.lstItemsClick(nil);
    end;
    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      AChoice := Dlg.FChoices[Dlg.lstChoices.ItemIndex];
      ANote := Dlg.edNote.Text;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
