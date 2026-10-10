unit dlg_SignatureView;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel, Vcl.Mask;

type
  TdlgSignatureView = class(TForm)
    pnlBottom: TRzPanel;
    btnClose: TRzBitBtn;
    btnVerify: TRzBitBtn;
    pnlMain: TRzPanel;
    lblSignedBy: TRzLabel;
    edSignedBy: TRzEdit;
    lblDate: TRzLabel;
    edDate: TRzEdit;
    lblMeaning: TRzLabel;
    edMeaning: TRzEdit;
    lblComment: TRzLabel;
    edComment: TRzMemo;
    lblHash: TRzLabel;
    edHash: TRzEdit;
    lblIntegrity: TRzLabel;
    edIntegrity: TRzEdit;
    procedure btnVerifyClick(Sender: TObject);
  private
    FItemId: Integer;
  end;

  procedure ShowSignatureView(ItemId: Integer);

implementation

uses
  unit_DataModel,
  unit_Signature, unit_SignatureModel,
  unit_AuditLog,
  unit_TimeHelper;

{$R *.dfm}

procedure ShowSignatureView(ItemId: Integer);
var
  Dlg: TdlgSignatureView;
  Sig: unit_Signature.TSignature;
begin
  Sig := Model.Signatures.GetSignature(ItemId);
  if not Assigned(Sig) then
  begin
    MessageDlg('No signature found for this item.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Dlg := TdlgSignatureView.Create(Application.MainForm);
  try
    Dlg.FItemId := ItemId;
    Dlg.edSignedBy.Text := Sig.UserName;
    Dlg.edDate.Text := DateTimeToStr(FromUTC(Sig.SignedDate));
    Dlg.edMeaning.Text := Sig.Meaning;
    Dlg.edComment.Text := Sig.Comment;
    Dlg.edHash.Text := Sig.ContentHash;
    Dlg.edIntegrity.Text := '(click Verify Now)';
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;


procedure TdlgSignatureView.btnVerifyClick(Sender: TObject);
begin
  case Model.Signatures.GetIntegrityState(FItemId) of
    sisVerified:
      begin
        edIntegrity.Text := 'VERIFIED - Content matches signature';
        edIntegrity.Font.Color := clGreen;
      end;
    sisMismatch:
      begin
        edIntegrity.Text := 'MISMATCH - Content does not match signature';
        edIntegrity.Font.Color := clRed;
        Model.RecordAudit(unit_AuditLog.aetSignature, FItemId,
          unit_AuditLog.aoUpdate, 'Integrity check FAILED for item');
      end;
    sisLegacyUnverifiable:
      begin
        edIntegrity.Text := 'Legacy signature; integrity cannot be verified';
        edIntegrity.Font.Color := clWindowText;
      end;
    sisUnsigned:
      begin
        edIntegrity.Text := 'No signature';
        edIntegrity.Font.Color := clWindowText;
      end;
  end;
end;

end.
