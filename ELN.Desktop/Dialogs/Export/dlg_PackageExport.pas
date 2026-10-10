unit dlg_PackageExport;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.CheckLst,
  RzButton, RzPanel, RzEdit,
  System.Generics.Collections,
  unit_Item, Vcl.Mask;

type
  TdlgPackageExport = class(TForm)
    pnlBottom: TRzPanel;
    btnExport: TRzButton;
    btnCancel: TRzButton;
    pnlMain: TRzPanel;
    lblItems: TLabel;
    clbItems: TCheckListBox;
    lblPath: TLabel;
    edtPath: TRzEdit;
    btnBrowse: TRzButton;
    chkIncludeFiles: TCheckBox;
    chkIncludeHistory: TCheckBox;
    SaveDialog: TSaveDialog;
    procedure btnBrowseClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
  private
    FItems: TItems;
  public
    class function Execute(Items: TItems; out SelectedItems: TItems;
      out ExportPath: string; out IncludeFiles, IncludeHistory: Boolean): Boolean;
  end;

implementation

{$R *.dfm}


class function TdlgPackageExport.Execute(Items: TItems; out SelectedItems: TItems;
  out ExportPath: string; out IncludeFiles, IncludeHistory: Boolean): Boolean;
var
  Dialog: TdlgPackageExport;
  I: Integer;
  Item: TItem;
begin
  Result := False;
  SelectedItems := nil;

  Dialog := TdlgPackageExport.Create(nil);
  try
    Dialog.FItems := Items;

    for Item in Items do
      Dialog.clbItems.Items.AddObject(Item.Title, Item);

    for I := 0 to Dialog.clbItems.Count - 1 do
      Dialog.clbItems.Checked[I] := True;

    Dialog.chkIncludeFiles.Checked := True;
    Dialog.chkIncludeHistory.Checked := True;

    if Dialog.ShowModal = mrOk then
    begin
      SelectedItems := TItems.Create;
      for I := 0 to Dialog.clbItems.Count - 1 do
      begin
        if Dialog.clbItems.Checked[I] then
          SelectedItems.Add(TItem(Dialog.clbItems.Items.Objects[I]));
      end;
      ExportPath := Dialog.edtPath.Text;
      IncludeFiles := Dialog.chkIncludeFiles.Checked;
      IncludeHistory := Dialog.chkIncludeHistory.Checked;
      Result := SelectedItems.Count > 0;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgPackageExport.btnBrowseClick(Sender: TObject);
begin
  SaveDialog.FileName := 'export.elnpkg';
  if SaveDialog.Execute then
    edtPath.Text := SaveDialog.FileName;
end;

procedure TdlgPackageExport.btnExportClick(Sender: TObject);
var
  I: Integer;
  HasChecked: Boolean;
begin
  if Trim(edtPath.Text) = '' then
  begin
    MessageDlg('Please select an export path.', mtError, [mbOK], 0);
    Exit;
  end;

  HasChecked := False;
  for I := 0 to clbItems.Count - 1 do
    if clbItems.Checked[I] then
    begin
      HasChecked := True;
      Break;
    end;

  if not HasChecked then
  begin
    MessageDlg('Please select at least one item to export.', mtError, [mbOK], 0);
    Exit;
  end;

  ModalResult := mrOk;
end;

end.
