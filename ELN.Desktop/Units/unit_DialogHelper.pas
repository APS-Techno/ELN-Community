unit unit_DialogHelper;

interface

uses
  System.SysUtils,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.Dialogs;

/// <summary>
/// Helper functions to execute modal dialogs with automatic
/// resource management (Create/try/finally/Free pattern).
/// Eliminates boilerplate code in dialog functions.
/// </summary>

type
  /// <summary>
  /// Procedure type for setting up and extracting dialog values
  /// </summary>
  TDialogProc = reference to procedure(Dialog: TForm);

/// <summary>
/// Generic helper function to execute a modal dialog with automatic
/// resource management.
/// </summary>
/// <param name="DialogClass">The dialog form class to instantiate</param>
/// <param name="SetupProc">Anonymous method to setup dialog before showing</param>
/// <param name="ExtractProc">Anonymous method to extract values after OK clicked</param>
/// <returns>True if user clicked OK, False if cancelled</returns>
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
    // Execute setup procedure
    if Assigned(SetupProc) then
      SetupProc(Dialog);

    // Show modal and process result
    if Dialog.ShowModal = mrOk then
    begin
      // Execute extract procedure
      if Assigned(ExtractProc) then
        ExtractProc(Dialog);
      Result := True;
    end;
  finally
    Dialog.Free;
  end;
end;

end.
