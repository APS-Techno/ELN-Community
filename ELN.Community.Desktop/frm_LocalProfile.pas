unit frm_LocalProfile;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TdlgLocalProfile = class(TForm)
    lblIntroduction: TLabel;
    lblFirstName: TLabel;
    edtFirstName: TEdit;
    lblLastName: TLabel;
    edtLastName: TEdit;
    lblSigningPassword: TLabel;
    edtSigningPassword: TEdit;
    lblConfirmation: TLabel;
    edtConfirmation: TEdit;
    lblPasswordHelp: TLabel;
    lblValidation: TLabel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    function ValidateProfile: Boolean;
    procedure ShowValidation(const MessageText: string; Control: TEdit);
  public
    destructor Destroy; override;
    class function Execute(out FirstName, LastName,
      SigningPassword: string): Boolean; static;
  end;

implementation

{$R *.dfm}

class function TdlgLocalProfile.Execute(out FirstName, LastName,
  SigningPassword: string): Boolean;
var
  Dialog: TdlgLocalProfile;
begin
  FirstName := '';
  LastName := '';
  SigningPassword := '';
  Result := False;
  Dialog := TdlgLocalProfile.Create(nil);
  try
    if Dialog.ShowModal <> mrOk then
      Exit;
    FirstName := Trim(Dialog.edtFirstName.Text);
    LastName := Trim(Dialog.edtLastName.Text);
    SigningPassword := Dialog.edtSigningPassword.Text;
    Result := True;
  finally
    Dialog.Free;
  end;
end;

destructor TdlgLocalProfile.Destroy;
begin
  try
    if Assigned(edtFirstName) then
      edtFirstName.Clear;
    if Assigned(edtLastName) then
      edtLastName.Clear;
    if Assigned(edtSigningPassword) then
      edtSigningPassword.Clear;
    if Assigned(edtConfirmation) then
      edtConfirmation.Clear;
  finally
    inherited Destroy;
  end;
end;

procedure TdlgLocalProfile.ShowValidation(const MessageText: string;
  Control: TEdit);
begin
  lblValidation.Caption := MessageText;
  Control.SetFocus;
  Control.SelectAll;
end;

function TdlgLocalProfile.ValidateProfile: Boolean;
begin
  Result := False;
  if Trim(edtFirstName.Text) = '' then
  begin
    ShowValidation('Enter your first name.', edtFirstName);
    Exit;
  end;
  if Trim(edtLastName.Text) = '' then
  begin
    ShowValidation('Enter your last name.', edtLastName);
    Exit;
  end;
  if Trim(edtSigningPassword.Text) = '' then
  begin
    ShowValidation('Enter a signing password.', edtSigningPassword);
    Exit;
  end;
  if edtConfirmation.Text <> edtSigningPassword.Text then
  begin
    ShowValidation('The passwords must match exactly.', edtConfirmation);
    Exit;
  end;
  lblValidation.Caption := '';
  Result := True;
end;

procedure TdlgLocalProfile.FormCloseQuery(Sender: TObject;
  var CanClose: Boolean);
begin
  CanClose := True;
  if ModalResult = mrOk then
    CanClose := ValidateProfile;
end;

end.
