unit dlg_CategorySelect;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.CheckLst,
  RzButton, RzPanel, Vcl.ExtCtrls;

type
  TdlgCategorySelect = class(TForm)
    chkCategories: TCheckListBox;
    pnlBottom: TRzPanel;
    btnOK: TRzButton;
    btnCancel: TRzButton;
    btnSelectAll: TRzButton;
    btnSelectNone: TRzButton;
    chkOverwrite: TCheckBox;
    procedure btnSelectAllClick(Sender: TObject);
    procedure btnSelectNoneClick(Sender: TObject);
  private
    procedure SetAllChecked(AChecked: Boolean);
  public
    class function Execute(const TemplatesDir: string;
      out SelectedCategories: TStringList;
      out Overwrite: Boolean): Boolean;
  end;

implementation

{$R *.dfm}

uses
  System.IOUtils;


class function TdlgCategorySelect.Execute(const TemplatesDir: string;
  out SelectedCategories: TStringList; out Overwrite: Boolean): Boolean;
var
  Dlg: TdlgCategorySelect;
  Dirs: TArray<string>;
  DirName: string;
  I: Integer;
begin
  Result := False;
  SelectedCategories := nil;
  Overwrite := False;

  if not TDirectory.Exists(TemplatesDir) then
    Exit;

  Dirs := TDirectory.GetDirectories(TemplatesDir);
  if Length(Dirs) = 0 then
    Exit;

  Dlg := TdlgCategorySelect.Create(nil);
  try
    for DirName in Dirs do
    begin
      I := Dlg.chkCategories.Items.Add(TPath.GetFileName(DirName));
      Dlg.chkCategories.Checked[I] := True;
    end;

    if Dlg.ShowModal = mrOK then
    begin
      SelectedCategories := TStringList.Create;
      for I := 0 to Dlg.chkCategories.Count - 1 do
        if Dlg.chkCategories.Checked[I] then
          SelectedCategories.Add(Dlg.chkCategories.Items[I]);
      Overwrite := Dlg.chkOverwrite.Checked;
      Result := SelectedCategories.Count > 0;
      if not Result then
        FreeAndNil(SelectedCategories);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TdlgCategorySelect.SetAllChecked(AChecked: Boolean);
var
  I: Integer;
begin
  for I := 0 to chkCategories.Count - 1 do
    chkCategories.Checked[I] := AChecked;
end;

procedure TdlgCategorySelect.btnSelectAllClick(Sender: TObject);
begin
  SetAllChecked(True);
end;

procedure TdlgCategorySelect.btnSelectNoneClick(Sender: TObject);
begin
  SetAllChecked(False);
end;

end.
