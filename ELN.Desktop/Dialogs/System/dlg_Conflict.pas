unit dlg_Conflict;

interface

uses
  unit_ConflictHandler;

function ShowConflictDialog(const Msg: string): TConflictResolution;

implementation

uses
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Controls, Vcl.Graphics,
  System.SysUtils, System.Classes, Winapi.Windows;

function ShowConflictDialog(const Msg: string): TConflictResolution;
var
  Dlg: TForm;
  lblMessage: TLabel;
  btnReload, btnCancel: TButton;
begin
  Dlg := TForm.CreateNew(Application);
  try
    Dlg.Caption := 'Conflict Detected';
    Dlg.Position := poMainFormCenter;
    Dlg.BorderStyle := bsDialog;
    Dlg.ClientWidth := 400;
    Dlg.ClientHeight := 140;

    lblMessage := TLabel.Create(Dlg);
    lblMessage.Parent := Dlg;
    lblMessage.Left := 20;
    lblMessage.Top := 20;
    lblMessage.Width := 360;
    lblMessage.WordWrap := True;
    lblMessage.Caption :=
      'This record was modified by another user while you were editing it.' +
      sLineBreak + 'Your changes cannot be saved.';

    btnReload := TButton.Create(Dlg);
    btnReload.Parent := Dlg;
    btnReload.Caption := 'Reload and try again';
    btnReload.Width := 150;
    btnReload.Left := 60;
    btnReload.Top := 90;
    btnReload.ModalResult := mrRetry;

    btnCancel := TButton.Create(Dlg);
    btnCancel.Parent := Dlg;
    btnCancel.Caption := 'Cancel';
    btnCancel.Width := 100;
    btnCancel.Left := 230;
    btnCancel.Top := 90;
    btnCancel.ModalResult := mrCancel;
    btnCancel.Cancel := True;

    case Dlg.ShowModal of
      mrRetry: Result := crReload;
    else
      Result := crCancel;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
