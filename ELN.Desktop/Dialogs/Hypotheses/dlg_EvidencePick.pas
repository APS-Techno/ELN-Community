unit dlg_EvidencePick;

{ Use live, readable evidence queries, not cached TItem.Files or Values.
  A session-long manager does not refresh those collections, and unreadable titles must not leak. }

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
  INDENT_UNIT = '    ';  

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
