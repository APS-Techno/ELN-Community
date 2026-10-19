unit dlg_File;

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Controls, Vcl.Forms,
  RzCommon, RzCmboBx, RzEdit, RzLabel, RzButton, RzPanel,
  unit_FileType, unit_ActionType, frame_FileSystemBrowser;

type
  TFileInfo = record
    SourcePath: string;
    Name: string;
    FileType: TFileType;
  end;
  TFileInfoArray = TArray<TFileInfo>;

  TdlgFile = class(TForm)
    pnlBottom: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    lblStatus: TRzLabel;
    pnlMetadata: TRzPanel;
    pnlFilter: TRzPanel;
    lblFilter: TRzLabel;
    cbFilter: TRzComboBox;
    lblActionType: TRzLabel;
    lblName: TRzLabel;
    lblFileType: TRzLabel;
    lblMulti: TRzLabel;
    cbActionType: TRzComboBox;
    cbFileType: TRzComboBox;
    edName: TRzEdit;
    Browser: TframeFileSystemBrowser;
    procedure cbActionTypeChange(Sender: TObject);
    procedure cbFilterChange(Sender: TObject);
    procedure cbFileTypeChange(Sender: TObject);
    procedure edNameChange(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    class var FLastDir: string;
    var FActionTypeList: TActionTypes;
    FAllFileTypes, FRelevantTypes: TFileTypes;
    FFilterMasks: TStringList;
    FActionFileTypes: TFunc<Integer, TFileTypes>;
    FSelectedFileType: TFileType;
    FSelectedSource, FValidationError: string;
    FFiles: TFileInfoArray;
    FAllowMulti, FInitializing, FStarting: Boolean;
    FStartupFolders: TArray<string>;
    FStartupIndex: Integer;
    procedure UpdateFilter;
    procedure BuildFilter;
    procedure SelectionChanged(Sender: TObject);
    procedure NavigationStatusChanged(Sender: TObject);
    procedure UpdateSelectionUI;
    procedure StartNextFolder;
    function GetFiles: TFileInfoArray;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Initialize(AFileTypes: TFileTypes; AActionTypes: TActionTypes;
      AActionType: TActionType; AMultiSelect: Boolean;
      const AActionFileTypes: TFunc<Integer, TFileTypes>);
    procedure StartBrowsing(const AFolder: string = '');
    procedure RememberDirectory;
    function TryGetSelection(out AFiles: TFileInfoArray; out AError: string): Boolean;
    function FilesForReview: TFileInfoArray;
    property SelectedFileType: TFileType read FSelectedFileType;
    property Files: TFileInfoArray read GetFiles;
  end;

function ShowFileDialog(var AFileType: TFileType; var AName: string;
  var ASourcePath: string; AActionType: TActionType = nil): Boolean;
function ShowFileDialogMulti(var AFiles: TFileInfoArray;
  AActionType: TActionType = nil): Boolean;

implementation

uses
  System.IOUtils, Winapi.KnownFolders, unit_DataModel, unit_NotebookSettings,
  unit_DepoPairing, unit_FileSelection, dlg_FileMulti;

{$R *.dfm}

function TypeMask(AType: TFileType): string;
var
  Raw, Token: string;
begin
  Result := '';
  for Raw in AType.Ext.Split([';']) do
  begin
    Token := Trim(Raw);
    if Token = '' then Continue;
    if Result <> '' then Result := Result + ';';
    Result := Result + '*' + Token;
  end;
end;

function CreateModelDialog(AActionType: TActionType; AMulti: Boolean): TdlgFile;
var
  FileTypes: TFileTypes;
  ActionTypes: TActionTypes;
begin
  Result := TdlgFile.Create(Application.MainForm);
  try
    FileTypes := Model.FileTypes.GetFileTypes;
    try
      ActionTypes := Model.ActionTypes.GetTypes;
      try
        Result.Initialize(FileTypes, ActionTypes, AActionType, AMulti,
          function(ActionTypeID: Integer): TFileTypes
          begin
            Result := Model.ActionTypes.GetFileTypes(ActionTypeID);
          end);
      finally
        ActionTypes.Free;
      end;
    finally
      FileTypes.Free;
    end;
    Result.StartBrowsing;
  except
    Result.Free;
    raise;
  end;
end;

function ShowFileDialog(var AFileType: TFileType; var AName: string;
  var ASourcePath: string; AActionType: TActionType): Boolean;
var
  Dialog: TdlgFile;
  Selected: TFileInfoArray;
begin
  Result := False;
  Dialog := CreateModelDialog(AActionType, False);
  try
    if Dialog.ShowModal = mrOk then
    begin
      Selected := Dialog.Files;
      if Length(Selected) = 1 then
      begin
        AFileType := Selected[0].FileType;
        AName := Selected[0].Name;
        ASourcePath := Selected[0].SourcePath;
        Result := True;
      end;
    end;
  finally
    try
      Dialog.RememberDirectory;
    finally
      Dialog.Free;
    end;
  end;
end;

function ShowFileDialogMulti(var AFiles: TFileInfoArray;
  AActionType: TActionType): Boolean;
var
  Dialog: TdlgFile;
  Selected, Confirmed: TFileInfoArray;
begin
  Result := False;
  Dialog := CreateModelDialog(AActionType, True);
  try
    if Dialog.ShowModal <> mrOk then Exit;
    Selected := Dialog.FilesForReview;
    if Length(Selected) > 1 then
    begin
      if not ShowFileMultiConfirmDialog(Selected, Dialog.FAllFileTypes, Confirmed) then Exit;
      AFiles := Confirmed;
      Result := True;
    end
    else if Length(Selected) = 1 then
    begin
      AFiles := Selected;
      Result := True;
    end;
  finally
    try
      Dialog.RememberDirectory;
    finally
      Dialog.Free;
    end;
  end;
end;

constructor TdlgFile.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFilterMasks := TStringList.Create;
  Browser.lblStatus.Visible := False;
  Browser.OnSelectionChanged := SelectionChanged;
  Browser.OnStatusChanged := NavigationStatusChanged;
  Browser.OnDirectoryChanged := NavigationStatusChanged;
end;

destructor TdlgFile.Destroy;
begin
  FActionFileTypes := nil;
  FFilterMasks.Free;
  FRelevantTypes.Free;
  FAllFileTypes.Free;
  FActionTypeList.Free;
  inherited;
end;

procedure TdlgFile.Initialize(AFileTypes: TFileTypes; AActionTypes: TActionTypes;
  AActionType: TActionType; AMultiSelect: Boolean;
  const AActionFileTypes: TFunc<Integer, TFileTypes>);
var
  FT: TFileType;
  AT: TActionType;
  I: Integer;
begin
  FInitializing := True;
  try
    FreeAndNil(FAllFileTypes);
    FreeAndNil(FActionTypeList);
    FAllFileTypes := TFileTypes.Create;
    FActionTypeList := TActionTypes.Create;
    FAllowMulti := AMultiSelect;
    Browser.lvFiles.MultiSelect := AMultiSelect;
    FActionFileTypes := AActionFileTypes;
    cbFileType.Items.Clear;
    cbFileType.Items.Add('(Choose a file type)');
    if Assigned(AFileTypes) then
      for FT in AFileTypes do
        if Assigned(FT) then
        begin
          FAllFileTypes.Add(FT);
          cbFileType.Items.AddObject(FT.Description + ' (' + FT.Ext + ')', FT);
        end;
    cbActionType.Items.Clear;
    if Assigned(AActionTypes) then
      for AT in AActionTypes do
        if Assigned(AT) then
        begin
          FActionTypeList.Add(AT);
          cbActionType.Items.Add(AT.Title);
        end;
    cbActionType.Enabled := cbActionType.Items.Count > 0;
    cbActionType.ItemIndex := -1;
    if Assigned(AActionType) then
      for I := 0 to FActionTypeList.Count - 1 do
        if FActionTypeList[I].Id = AActionType.Id then
        begin
          cbActionType.ItemIndex := I;
          Break;
        end;
    if (cbActionType.ItemIndex < 0) and (cbActionType.Items.Count > 0) then
      cbActionType.ItemIndex := 0;
  finally
    FInitializing := False;
  end;
  UpdateFilter;
  SelectionChanged(Self);
end;

procedure TdlgFile.UpdateFilter;
var
  Linked, Relevant: TFileTypes;
begin
  Linked := nil;
  try
    if Assigned(FActionFileTypes) and (cbActionType.ItemIndex >= 0) then
      Linked := FActionFileTypes(FActionTypeList[cbActionType.ItemIndex].Id);
    Relevant := CollectRelevantFileTypes(FAllFileTypes, Linked);
    FRelevantTypes.Free;
    FRelevantTypes := Relevant;
  finally
    Linked.Free;
  end;
  BuildFilter;
end;

procedure TdlgFile.BuildFilter;
var
  FT: TFileType;
  Mask, UnionMask: string;
begin
  FFilterMasks.Clear;
  cbFilter.Items.Clear;
  UnionMask := '';
  for FT in FRelevantTypes do
  begin
    Mask := TypeMask(FT);
    if Mask = '' then Continue;
    if UnionMask <> '' then UnionMask := UnionMask + ';';
    UnionMask := UnionMask + Mask;
  end;
  if UnionMask <> '' then
  begin
    cbFilter.Items.Add('Relevant file types (' + UnionMask + ')');
    FFilterMasks.Add(UnionMask);
    for FT in FRelevantTypes do
    begin
      Mask := TypeMask(FT);
      if Mask = '' then Continue;
      cbFilter.Items.Add(FT.Description + ' (' + Mask + ')');
      FFilterMasks.Add(Mask);
    end;
  end;
  cbFilter.Items.Add('All files (*.*)');
  FFilterMasks.Add('*.*');
  cbFilter.ItemIndex := 0;
  Browser.SetFilter(FFilterMasks[0]);
end;

procedure TdlgFile.cbActionTypeChange(Sender: TObject);
begin
  if FInitializing then Exit;
  Browser.lvFiles.ClearSelection;
  FSelectedSource := '';
  FValidationError := '';
  UpdateFilter;
  SelectionChanged(Self);
end;

procedure TdlgFile.cbFilterChange(Sender: TObject);
begin
  if FInitializing or (cbFilter.ItemIndex < 0) then Exit;
  Browser.lvFiles.ClearSelection;
  FValidationError := '';
  Browser.SetFilter(FFilterMasks[cbFilter.ItemIndex]);
end;

procedure TdlgFile.SelectionChanged(Sender: TObject);
var
  Paths: TArray<string>;
  Index: Integer;
begin
  Paths := Browser.SelectedPaths;
  if Length(Paths) = 1 then
  begin
    if not SameText(FSelectedSource, Paths[0]) then
    begin
      FSelectedSource := Paths[0];
      FSelectedFileType := ResolveFileType(Paths[0], FAllFileTypes);
      Index := cbFileType.Items.IndexOfObject(FSelectedFileType);
      if Index < 0 then Index := 0;
      cbFileType.ItemIndex := Index;
      edName.Text := SuggestedAttachmentName(Paths[0], FSelectedFileType);
      FValidationError := '';
    end;
  end
  else
  begin
    FSelectedSource := '';
    FSelectedFileType := nil;
    cbFileType.ItemIndex := 0;
    edName.Text := '';
    FValidationError := '';
  end;
  UpdateSelectionUI;
end;

procedure TdlgFile.cbFileTypeChange(Sender: TObject);
begin
  if FInitializing then Exit;
  FSelectedFileType := nil;
  if cbFileType.ItemIndex > 0 then
    FSelectedFileType := TFileType(cbFileType.Items.Objects[cbFileType.ItemIndex]);
  FValidationError := '';
  UpdateSelectionUI;
end;

procedure TdlgFile.edNameChange(Sender: TObject);
begin
  if FInitializing then Exit;
  FValidationError := '';
  UpdateSelectionUI;
end;

procedure TdlgFile.UpdateSelectionUI;
var
  Count: Integer;
  Single: Boolean;
begin
  Count := Length(Browser.SelectedPaths);
  Single := Count = 1;
  edName.Enabled := Single and not Browser.Loading;
  cbFileType.Enabled := edName.Enabled;
  lblMulti.Visible := Count > 1;
  lblMulti.Caption := Format('%d files selected; review names and types before attachment.', [Count]);
  if Count > 1 then btnSave.Caption := 'Review files'
  else btnSave.Caption := 'Attach';
  btnSave.Enabled := not Browser.Loading and (Count > 0) and
    ((FAllowMulti and (Count > 1)) or (Single and Assigned(FSelectedFileType) and (Trim(edName.Text) <> '')));
  if FValidationError <> '' then lblStatus.Caption := FValidationError
  else if Browser.Loading or (Browser.LastError <> '') then lblStatus.Caption := Browser.StatusText
  else if Single and not Assigned(FSelectedFileType) then lblStatus.Caption := 'Choose an attachment file type.'
  else if Single and (Trim(edName.Text) = '') then lblStatus.Caption := 'Enter a display name.'
  else lblStatus.Caption := Format('%d file(s) selected', [Count]);
  lblStatus.Hint := lblStatus.Caption;
end;

function TdlgFile.TryGetSelection(out AFiles: TFileInfoArray;
  out AError: string): Boolean;
var
  Paths: TArray<string>;
  I: Integer;
begin
  Result := False;
  AFiles := nil;
  AError := '';
  Paths := Browser.SelectedPaths;
  if Browser.Loading then AError := 'Wait for folder loading to finish.'
  else if Length(Paths) = 0 then AError := 'Select a source file.'
  else if not FAllowMulti and (Length(Paths) <> 1) then AError := 'Select exactly one source file.';
  if AError <> '' then Exit;
  SetLength(AFiles, Length(Paths));
  for I := 0 to High(Paths) do
  begin
    AFiles[I].SourcePath := Paths[I];
    AFiles[I].FileType := ResolveFileType(Paths[I], FAllFileTypes);
    AFiles[I].Name := SuggestedAttachmentName(Paths[I], AFiles[I].FileType);
    if Length(Paths) = 1 then
    begin
      AFiles[I].Name := Trim(edName.Text);
      AFiles[I].FileType := FSelectedFileType;
      if not ValidateFileSelection(Paths[I], AFiles[I].Name, AFiles[I].FileType, AError) then Exit;
    end
    else if not FileExists(Paths[I]) then
    begin
      AError := Format('Source file does not exist: %s', [Paths[I]]);
      Exit;
    end;
  end;
  Result := True;
end;

procedure TdlgFile.btnSaveClick(Sender: TObject);
var
  Selected: TFileInfoArray;
begin
  if not TryGetSelection(Selected, FValidationError) then
  begin
    UpdateSelectionUI;
    Exit;
  end;
  FFiles := Selected;
  ModalResult := mrOk;
end;

function TdlgFile.GetFiles: TFileInfoArray;
begin
  Result := Copy(FFiles);
end;

function TdlgFile.FilesForReview: TFileInfoArray;
var
  Paths, Initial: TStringList;
  I, Index: Integer;
begin
  Result := Copy(FFiles);
  if not FAllowMulti then Exit;
  Paths := TStringList.Create;
  Initial := TStringList.Create;
  try
    Paths.CaseSensitive := False;
    Initial.CaseSensitive := False;
    for I := 0 to High(FFiles) do
    begin
      Paths.Add(FFiles[I].SourcePath);
      Initial.AddObject(FFiles[I].SourcePath, TObject(NativeInt(I + 1)));
    end;
    Initial.Sorted := True;
    ExpandDepoPairs(Paths);
    SetLength(Result, Paths.Count);
    for I := 0 to Paths.Count - 1 do
    begin
      Index := Initial.IndexOf(Paths[I]);
      if Index >= 0 then
        Result[I] := FFiles[NativeInt(Initial.Objects[Index]) - 1]
      else
      begin
        Result[I].SourcePath := Paths[I];
        Result[I].FileType := ResolveFileType(Paths[I], FAllFileTypes);
        Result[I].Name := SuggestedAttachmentName(Paths[I], Result[I].FileType);
      end;
    end;
  finally
    Initial.Free;
    Paths.Free;
  end;
end;

procedure TdlgFile.StartBrowsing(const AFolder: string);
var
  Settings: TNotebookSettings;
  Preferred: string;
begin
  Preferred := AFolder;
  if Preferred = '' then
  begin
    if FLastDir = '' then
    begin
      Settings := TNotebookSettings.Create;
      try
        FLastDir := Settings.LoadUIString('AddFile', 'LastDir', '');
      finally
        Settings.Free;
      end;
    end;
    Preferred := FLastDir;
  end;
  FStartupFolders := TArray<string>.Create(Preferred,
    BrowserKnownFolder(FOLDERID_Documents), BrowserKnownFolder(FOLDERID_Profile));
  FStartupIndex := 0;
  FStarting := True;
  StartNextFolder;
end;

procedure TdlgFile.StartNextFolder;
var
  Path: string;
  I: Integer;
  Duplicate: Boolean;
begin
  while FStartupIndex < Length(FStartupFolders) do
  begin
    Path := FStartupFolders[FStartupIndex];
    Duplicate := False;
    for I := 0 to FStartupIndex - 1 do
      if SameText(Path, FStartupFolders[I]) then Duplicate := True;
    Inc(FStartupIndex);
    if (Path <> '') and not Duplicate then
    begin
      Browser.Navigate(Path);
      Exit;
    end;
  end;
  FStarting := False;
  UpdateSelectionUI;
end;

procedure TdlgFile.NavigationStatusChanged(Sender: TObject);
begin
  if FStarting and not Browser.Loading then
  begin
    if (Browser.CurrentDirectory = '') and (Browser.LastError <> '') then
      StartNextFolder
    else
      FStarting := False;
  end;
  UpdateSelectionUI;
end;

procedure TdlgFile.RememberDirectory;
var
  Settings: TNotebookSettings;
begin
  if Browser.CurrentDirectory = '' then Exit;
  FLastDir := Browser.CurrentDirectory;
  Settings := TNotebookSettings.Create;
  try
    Settings.SaveUIString('AddFile', 'LastDir', FLastDir);
  finally
    Settings.Free;
  end;
end;

end.
