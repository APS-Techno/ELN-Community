unit dlg_FileMulti;

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.ComCtrls,
  RzCommon, RzPanel, RzButton, RzEdit, RzLabel, RzCmboBx, RzRadChk, RzListVw,
  unit_FileType, dlg_File;

type
  TdlgFileMulti = class(TForm)
    pnlBottom: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    pnlMain: TRzPanel;
    lvFiles: TRzListView;
    pnlNaming: TRzPanel;
    rbOriginalNames: TRzRadioButton;
    rbPrefixNames: TRzRadioButton;
    edPrefix: TRzEdit;
    lblPreview: TRzLabel;
    pnlType: TRzPanel;
    lblType: TRzLabel;
    cbFileType: TRzComboBox;
    lblError: TRzLabel;
    procedure rbOriginalNamesClick(Sender: TObject);
    procedure rbPrefixNamesClick(Sender: TObject);
    procedure edPrefixChange(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure lvFilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure cbFileTypeChange(Sender: TObject);
  private
    FAllFileTypes: TFileTypes;
    FFiles: TFileInfoArray;
    FOriginalNames: TArray<string>;
    FUpdatingType: Boolean;
    FInvalidIndex: Integer;
    procedure PopulateList;
    procedure UpdateDisplayNames;
    procedure UpdateTypeEditor;
    function GetFiles: TFileInfoArray;
  public
    destructor Destroy; override;
    procedure Initialize(const AInitialFiles: TFileInfoArray; AAllFileTypes: TFileTypes);
    function ValidateSelection(out AError: string): Boolean;
    property Files: TFileInfoArray read GetFiles;
  end;

function ShowFileMultiConfirmDialog(const AInitialFiles: TFileInfoArray;
  AAllFileTypes: TFileTypes; var AFiles: TFileInfoArray): Boolean;

implementation

uses
  System.IOUtils, unit_FileSelection;

{$R *.dfm}

function ShowFileMultiConfirmDialog(const AInitialFiles: TFileInfoArray;
  AAllFileTypes: TFileTypes; var AFiles: TFileInfoArray): Boolean;
var
  Dialog: TdlgFileMulti;
begin
  Result := False;
  Dialog := TdlgFileMulti.Create(Application.MainForm);
  try
    Dialog.Initialize(AInitialFiles, AAllFileTypes);
    if Dialog.ShowModal = mrOk then
    begin
      AFiles := Dialog.Files;
      Result := Length(AFiles) > 0;
    end;
  finally
    Dialog.Free;
  end;
end;

destructor TdlgFileMulti.Destroy;
begin
  FreeAndNil(FAllFileTypes);
  inherited;
end;

procedure TdlgFileMulti.Initialize(const AInitialFiles: TFileInfoArray;
  AAllFileTypes: TFileTypes);
var
  FT: TFileType;
  I: Integer;
begin
  FreeAndNil(FAllFileTypes);
  FAllFileTypes := TFileTypes.Create;
  FUpdatingType := True;
  try
    cbFileType.Items.Clear;
    cbFileType.Items.Add('(Choose a file type)');
    if Assigned(AAllFileTypes) then
      for FT in AAllFileTypes do
        if Assigned(FT) then
        begin
          FAllFileTypes.Add(FT);
          cbFileType.Items.AddObject(FT.Description + ' (' + FT.Ext + ')', FT);
        end;
  finally
    FUpdatingType := False;
  end;
  FFiles := Copy(AInitialFiles);
  SetLength(FOriginalNames, Length(FFiles));
  for I := 0 to High(FFiles) do
  begin
    if not FAllFileTypes.Contains(FFiles[I].FileType) then
      FFiles[I].FileType := ResolveFileType(FFiles[I].SourcePath, FAllFileTypes);
    if FFiles[I].Name = '' then
      FFiles[I].Name := TPath.GetFileNameWithoutExtension(FFiles[I].SourcePath);
    FOriginalNames[I] := FFiles[I].Name;
  end;
  lblError.Caption := '';
  PopulateList;
  rbOriginalNames.Checked := True;
  rbPrefixNames.Checked := False;
  edPrefix.Enabled := False;
  UpdateDisplayNames;
  if lvFiles.Items.Count > 0 then lvFiles.Items[0].Selected := True;
  UpdateTypeEditor;
  btnSave.Enabled := Length(FFiles) > 0;
end;

procedure TdlgFileMulti.PopulateList;
var
  I: Integer;
  Item: TListItem;
begin
  lvFiles.Items.BeginUpdate;
  try
    lvFiles.Items.Clear;
    for I := 0 to High(FFiles) do
    begin
      Item := lvFiles.Items.Add;
      Item.Caption := IntToStr(I + 1);
      Item.SubItems.Add(ExtractFileName(FFiles[I].SourcePath));
      Item.SubItems.Add(FFiles[I].Name);
      if Assigned(FFiles[I].FileType) then
        Item.SubItems.Add(FFiles[I].FileType.Description)
      else
        Item.SubItems.Add('(unknown)');
    end;
  finally
    lvFiles.Items.EndUpdate;
  end;
  Caption := Format('Files to attach (%d)', [Length(FFiles)]);
end;

procedure TdlgFileMulti.UpdateDisplayNames;
var
  I: Integer;
  Prefix: string;
begin
  Prefix := Trim(edPrefix.Text);
  if Prefix = '' then Prefix := 'File';
  lvFiles.Items.BeginUpdate;
  try
    for I := 0 to High(FFiles) do
    begin
      if rbOriginalNames.Checked then FFiles[I].Name := FOriginalNames[I]
      else FFiles[I].Name := Format('%s_%3.3d', [Prefix, I + 1]);
      lvFiles.Items[I].SubItems[1] := FFiles[I].Name;
    end;
  finally
    lvFiles.Items.EndUpdate;
  end;
  if rbPrefixNames.Checked and (Length(FFiles) > 0) then
    lblPreview.Caption := Format('Preview: %s ... %s',
      [FFiles[0].Name, FFiles[High(FFiles)].Name])
  else lblPreview.Caption := '';
  lblError.Caption := '';
end;

procedure TdlgFileMulti.UpdateTypeEditor;
var
  I, Index: Integer;
begin
  FUpdatingType := True;
  try
    cbFileType.Enabled := Assigned(lvFiles.Selected) and (FAllFileTypes.Count > 0);
    cbFileType.ItemIndex := 0;
    if not Assigned(lvFiles.Selected) then Exit;
    I := lvFiles.Selected.Index;
    if (I < 0) or (I >= Length(FFiles)) then Exit;
    Index := cbFileType.Items.IndexOfObject(FFiles[I].FileType);
    if Index >= 0 then cbFileType.ItemIndex := Index;
  finally
    FUpdatingType := False;
  end;
end;

procedure TdlgFileMulti.lvFilesSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
begin
  if Assigned(FAllFileTypes) then UpdateTypeEditor;
end;

procedure TdlgFileMulti.cbFileTypeChange(Sender: TObject);
var
  I: Integer;
begin
  if FUpdatingType or not Assigned(lvFiles.Selected) then Exit;
  I := lvFiles.Selected.Index;
  if (I < 0) or (I >= Length(FFiles)) then Exit;
  FFiles[I].FileType := nil;
  if cbFileType.ItemIndex > 0 then
    FFiles[I].FileType := TFileType(cbFileType.Items.Objects[cbFileType.ItemIndex]);
  if Assigned(FFiles[I].FileType) then
    lvFiles.Items[I].SubItems[2] := FFiles[I].FileType.Description
  else lvFiles.Items[I].SubItems[2] := '(unknown)';
  lblError.Caption := '';
end;

procedure TdlgFileMulti.rbOriginalNamesClick(Sender: TObject);
begin
  edPrefix.Enabled := False;
  UpdateDisplayNames;
end;

procedure TdlgFileMulti.rbPrefixNamesClick(Sender: TObject);
begin
  edPrefix.Enabled := True;
  edPrefix.SetFocus;
  UpdateDisplayNames;
end;

procedure TdlgFileMulti.edPrefixChange(Sender: TObject);
begin
  if rbPrefixNames.Checked then UpdateDisplayNames;
end;

function TdlgFileMulti.ValidateSelection(out AError: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  FInvalidIndex := -1;
  AError := '';
  if Length(FFiles) = 0 then
  begin
    AError := 'No source files selected.';
    Exit;
  end;
  for I := 0 to High(FFiles) do
    if not ValidateFileSelection(FFiles[I].SourcePath, FFiles[I].Name,
      FFiles[I].FileType, AError) then
    begin
      FInvalidIndex := I;
      Exit;
    end;
  Result := True;
end;

procedure TdlgFileMulti.btnSaveClick(Sender: TObject);
var
  Error: string;
begin
  if ValidateSelection(Error) then
    ModalResult := mrOk
  else
  begin
    lblError.Caption := Error;
    lblError.Hint := Error;
    if FInvalidIndex >= 0 then
    begin
      lvFiles.Items[FInvalidIndex].Selected := True;
      lvFiles.Items[FInvalidIndex].MakeVisible(False);
      if cbFileType.Enabled then cbFileType.SetFocus;
    end;
  end;
end;

function TdlgFileMulti.GetFiles: TFileInfoArray;
begin
  Result := Copy(FFiles);
end;

end.
