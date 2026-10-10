unit dlg_Sign;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel, Vcl.Mask;

type
  TdlgSign = class(TForm)
    pnlBottom: TRzPanel;
    btnSign: TRzBitBtn;
    btnCancel: TRzBitBtn;
    pnlMain: TRzPanel;
    lblItemTitle: TRzLabel;
    edItemTitle: TRzEdit;
    lblMeaning: TRzLabel;
    cbMeaning: TComboBox;
    lblComment: TRzLabel;
    edComment: TRzMemo;
    lblPassword: TRzLabel;
    edPassword: TRzEdit;
    lblWarning: TRzLabel;
    procedure btnSignClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    procedure ValidateInput;
  end;

  function ShowSignDialog(var Meaning, Comment, Password: string;
    const ItemTitle: string): Boolean;

implementation

uses
  unit_DialogHelper;

{$R *.dfm}

function ShowSignDialog(var Meaning, Comment, Password: string;
  const ItemTitle: string): Boolean;
var
  MeaningRef, CommentRef, PasswordRef: string;
begin
  MeaningRef := Meaning;
  CommentRef := Comment;
  PasswordRef := Password;

  Result := ExecuteDialog(TdlgSign,
    procedure(Dialog: TForm)
    var
      D: TdlgSign;
    begin
      D := TdlgSign(Dialog);
      D.edItemTitle.Text := ItemTitle;
      D.cbMeaning.ItemIndex := 0;
      D.edComment.Text := '';
      D.edPassword.Text := '';
    end,
    procedure(Dialog: TForm)
    var
      D: TdlgSign;
    begin
      D := TdlgSign(Dialog);
      MeaningRef := D.cbMeaning.Text;
      CommentRef := D.edComment.Text;
      PasswordRef := D.edPassword.Text;
    end
  );

  if Result then
  begin
    Meaning := MeaningRef;
    Comment := CommentRef;
    Password := PasswordRef;
  end;
end;


procedure TdlgSign.FormCreate(Sender: TObject);
begin
  cbMeaning.Items.Clear;
  cbMeaning.Items.Add('Authored');
  cbMeaning.Items.Add('Reviewed');
  cbMeaning.Items.Add('Approved');
  cbMeaning.Items.Add('Witnessed');
  cbMeaning.ItemIndex := 0;

  edPassword.PasswordChar := '*';
  edItemTitle.ReadOnly := True;
  edItemTitle.Color := clBtnFace;
end;

procedure TdlgSign.btnSignClick(Sender: TObject);
begin
  ValidateInput;
end;

procedure TdlgSign.ValidateInput;
begin
  if cbMeaning.ItemIndex < 0 then
  begin
    MessageDlg('Please select a signature meaning.', mtWarning, [mbOK], 0);
    cbMeaning.SetFocus;
    Exit;
  end;
  if Trim(edPassword.Text) = '' then
  begin
    MessageDlg('Please enter your password to sign.', mtWarning, [mbOK], 0);
    edPassword.SetFocus;
    Exit;
  end;
  ModalResult := mrOk;
end;

end.
