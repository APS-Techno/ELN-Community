unit dlg_FileEdit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzLabel, RzButton, RzPanel, RzEdit, Vcl.Mask;

type
  TdlgFileEdit = class(TForm)
    pnlBottom: TRzPanel;
    btnOK: TRzButton;
    btnCancel: TRzButton;
    pnlMain: TRzPanel;
    lblTitle: TRzLabel;
    edtTitle: TRzEdit;
    lblDescription: TRzLabel;
    edtDescription: TRzMemo;
    procedure btnOKClick(Sender: TObject);
  end;

  function ShowFileEditDialog(const CurrentTitle, CurrentDescription: string;
    out NewTitle, NewDescription: string): Boolean;

implementation

{$R *.dfm}

function ShowFileEditDialog(const CurrentTitle, CurrentDescription: string;
  out NewTitle, NewDescription: string): Boolean;
var
  Dialog: TdlgFileEdit;
begin
  NewTitle := CurrentTitle;
  NewDescription := CurrentDescription;
  Dialog := TdlgFileEdit.Create(nil);
  try
    Dialog.edtTitle.Text := CurrentTitle;
    Dialog.edtDescription.Lines.Text := CurrentDescription;

    Result := Dialog.ShowModal = mrOk;

    if Result then
    begin
      NewTitle := Dialog.edtTitle.Text;
      NewDescription := Trim(Dialog.edtDescription.Lines.Text);
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgFileEdit.btnOKClick(Sender: TObject);
begin
  if Trim(edtTitle.Text) = '' then
  begin
    MessageDlg('File title cannot be empty.', mtError, [mbOK], 0);
    edtTitle.SetFocus;
    Exit;
  end;
  ModalResult := mrOk;
end;

end.
