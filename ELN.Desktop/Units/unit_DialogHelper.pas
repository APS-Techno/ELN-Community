unit unit_DialogHelper;

interface

uses
  System.SysUtils,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.Dialogs;


type
  TDialogProc = reference to procedure(Dialog: TForm);

function ExecuteDialog(
  DialogClass: TFormClass;
  SetupProc: TDialogProc;
  ExtractProc: TDialogProc = nil): Boolean;

implementation

function ExecuteDialog(
  DialogClass: TFormClass;
  SetupProc: TDialogProc;
  ExtractProc: TDialogProc): Boolean;
var
  Dialog: TForm;
begin
  Result := False;
  Dialog := DialogClass.Create(Application.MainForm);
  try
    if Assigned(SetupProc) then
      SetupProc(Dialog);

    if Dialog.ShowModal = mrOk then
    begin
      if Assigned(ExtractProc) then
        ExtractProc(Dialog);
      Result := True;
    end;
  finally
    Dialog.Free;
  end;
end;

end.
