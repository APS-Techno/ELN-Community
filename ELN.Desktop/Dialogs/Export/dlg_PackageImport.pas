unit dlg_PackageImport;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzButton, RzPanel, RzEdit, Vcl.Mask;

type
  TdlgPackageImport = class(TForm)
    pnlBottom: TRzPanel;
    btnImport: TRzButton;
    btnCancel: TRzButton;
    pnlMain: TRzPanel;
    lblFile: TLabel;
    edtFile: TRzEdit;
    btnBrowse: TRzButton;
    lblPreview: TLabel;
    mmoPreview: TMemo;
    OpenDialog: TOpenDialog;
    procedure btnBrowseClick(Sender: TObject);
    procedure btnImportClick(Sender: TObject);
  private
    FFilePath: string;
  public
    class function Execute(out FilePath: string): Boolean;
  end;

implementation

{$R *.dfm}

uses
  unit_DataModel,
  unit_PackageImport;


class function TdlgPackageImport.Execute(out FilePath: string): Boolean;
var
  Dialog: TdlgPackageImport;
begin
  Result := False;
  FilePath := '';

  Dialog := TdlgPackageImport.Create(nil);
  try
    if Dialog.ShowModal = mrOk then
    begin
      FilePath := Dialog.FFilePath;
      Result := FilePath <> '';
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgPackageImport.btnBrowseClick(Sender: TObject);
var
  Importer: TELNPackageImporter;
  Preview: string;
begin
  if OpenDialog.Execute then
  begin
    FFilePath := OpenDialog.FileName;
    edtFile.Text := FFilePath;

    Importer := TELNPackageImporter.Create(nil);
    try
      Preview := Importer.PreviewPackage(FFilePath);
      mmoPreview.Text := Preview;
    finally
      Importer.Free;
    end;
  end;
end;

procedure TdlgPackageImport.btnImportClick(Sender: TObject);
begin
  if Trim(edtFile.Text) = '' then
  begin
    MessageDlg('Please select a package file to import.', mtError, [mbOK], 0);
    Exit;
  end;

  if not FileExists(edtFile.Text) then
  begin
    MessageDlg('File not found.', mtError, [mbOK], 0);
    Exit;
  end;

  FFilePath := edtFile.Text;
  ModalResult := mrOk;
end;

end.
