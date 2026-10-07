unit editor_Protocols;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Buttons,
  RzLabel, RzButton, RzPanel, RzEdit, Vcl.Mask,
  System.Generics.Collections, System.Generics.Defaults,
  Aurelius.Types.Nullable,
  unit_Protocol,
  unit_Template,
  unit_ELNPluginCore;

type
  TedProtocols = class(TForm)
    pnlBottom: TRzPanel;
    pnlMain: TRzPanel;
    lblTitle: TRzLabel;
    edtTitle: TRzEdit;
    lblProtocolType: TRzLabel;
    cmbProtocolType: TComboBox;
    lblValidationStatus: TRzLabel;
    cmbValidationStatus: TComboBox;
    lblTemplate: TRzLabel;
    cmbTemplate: TComboBox;
    pnlFormArea: TRzPanel;
    btnHistory: TRzButton;
    btnSave: TRzButton;
    btnCancel: TBitBtn;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure cmbTemplateChange(Sender: TObject);
    procedure btnHistoryClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FEditor: IProtocolEditor;
    FPlugin: IViewerPlugin;
    FOldParent: TWinControl;
    FFormData: string;
    FTemplateList: TList<TTemplate>;
    FProtocol: TProtocol;
    FOriginalStatus: TValidationStatus;
    FStatusValues: TList<TValidationStatus>;
    FReadOnly: Boolean;
    FDirty: Boolean;
    FBaseCaption: string;
    FInitializing: Boolean;  // suppress dirty during programmatic field load

    function ValidateProtocol: Boolean;
    procedure SaveProtocol;
    procedure PopulateTemplates;
    procedure PopulateStatusCombo(Protocol: TProtocol);
    procedure SetReadOnlyMode;
    function GetSelectedTemplate: TTemplate;
    procedure LoadCurrentTemplate;
    procedure SetDirty(Value: Boolean);
    procedure HandleFieldChanged(Sender: TObject);
  public
    destructor Destroy; override;
    class procedure ShowEditor(Protocol: TProtocol; const APlugin: IViewerPlugin);
  end;

implementation

{$R *.dfm}

uses
  System.TypInfo,
  unit_DataModel,
  unit_User,
  unit_ProtocolStatusChange,
  unit_TimeHelper;

const
  StatusDisplayNames: array[TValidationStatus] of string = (
    'Draft', 'In Review', 'Approved', 'Rejected'
  );

{ TedProtocols }

destructor TedProtocols.Destroy;
begin
  // Return shared frame to previous parent, restore read-only
  if Assigned(FPlugin) then
  begin
    FEditor.ReadOnly := True;
    FEditor.PrepareForReparent;
    FPlugin.Frame.Parent := FOldParent;
  end;
  FEditor := nil;
  FPlugin := nil;
  FStatusValues.Free;
  inherited;
end;

procedure TedProtocols.FormCreate(Sender: TObject);
begin
  FStatusValues := TList<TValidationStatus>.Create;

  // Dirty-state plumbing. VCL OnChange handlers cover header fields; the
  // plugin posts a webmessage for the first edit inside the embedded form.
  FBaseCaption := Caption;
  edtTitle.OnChange := HandleFieldChanged;
  cmbProtocolType.OnChange := HandleFieldChanged;
  cmbValidationStatus.OnChange := HandleFieldChanged;
  // cmbTemplate already has cmbTemplateChange wired in the DFM; that handler
  // calls SetDirty(True) explicitly.
  btnSave.Enabled := False;  // armed by first edit
end;

procedure TedProtocols.FormShow(Sender: TObject);
begin
  // Load template after form is visible so the shared Edge browser
  // can navigate reliably (NavigateToString fails while hidden)
  LoadCurrentTemplate;
end;

procedure TedProtocols.btnSaveClick(Sender: TObject);
begin
  SaveProtocol;
end;

procedure TedProtocols.SetDirty(Value: Boolean);
begin
  if FDirty = Value then Exit;
  FDirty := Value;
  if FReadOnly then
  begin
    btnSave.Enabled := False;
    Exit;
  end;
  btnSave.Enabled := FDirty;
  if FDirty then
    Caption := '* ' + FBaseCaption
  else
    Caption := FBaseCaption;
end;

procedure TedProtocols.HandleFieldChanged(Sender: TObject);
begin
  if FInitializing then Exit;
  SetDirty(True);
end;

procedure TedProtocols.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Reply: Integer;
begin
  // Only prompt on user-initiated close (X / Cancel). A successful Save sets
  // ModalResult := mrOk and we let it through silently.
  if FReadOnly or (not FDirty) or (ModalResult = mrOk) then
  begin
    CanClose := True;
    Exit;
  end;

  Reply := MessageDlg('Save changes to this protocol?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  case Reply of
    mrYes:
      begin
        SaveProtocol;
        // SaveProtocol sets ModalResult := mrOk on success and leaves it
        // unset on validation failure / DB failure.
        CanClose := ModalResult = mrOk;
      end;
    mrNo:
      CanClose := True;
  else
    CanClose := False;
  end;
end;

procedure TedProtocols.SaveProtocol;
var
  OldStatus: TValidationStatus;
  Comment: string;
  NewStatus: TValidationStatus;
  ProjectId, AuthorId, ExpectedVersion: Integer;
begin
  if not ValidateProtocol then
    Exit;

  OldStatus := FOriginalStatus;
  NewStatus := OldStatus;
  if (cmbValidationStatus.ItemIndex >= 0) and
     (cmbValidationStatus.ItemIndex < FStatusValues.Count) then
    NewStatus := FStatusValues[cmbValidationStatus.ItemIndex];
  if NewStatus <> OldStatus then
  begin
    if not Model.ProtocolStatus.TryGetAccessContext(FProtocol.Id, ProjectId, AuthorId) or
       not Model.ProtocolStatus.CanTransition(OldStatus, NewStatus, Model.User,
         ProjectId, AuthorId) then
      raise Exception.Create('This protocol status change is not allowed.');
  end;

  FProtocol.Title := edtTitle.Text;
  FProtocol.ProtocolType := TProtocolType(cmbProtocolType.ItemIndex);

  FProtocol.FormData := FEditor.GetFormData;

  // Set TemplateId
  var SelTemplate := GetSelectedTemplate;
  if Assigned(SelTemplate) then
    FProtocol.TemplateId := SelTemplate.Id
  else
    FProtocol.TemplateId := Default(Nullable<Integer>);

  if not Model.Items.UpdateEntry(FProtocol, Model.User.Id) then
    Exit;

  if (FProtocol.Id > 0) and (NewStatus <> OldStatus) then
  begin
    ExpectedVersion := FProtocol.Version;
    Comment := '';
    if NewStatus = vsRejected then
      InputQuery('Status Change', 'Reason for rejection:', Comment);
    try
      Model.ProtocolStatus.Transition(Model.User, FProtocol.Id,
        ExpectedVersion, OldStatus, NewStatus, Comment);
    except
      on E: Exception do
      begin
        try
          Model.Manager.Refresh(FProtocol);
        except
        end;
        raise;
      end;
    end;
    Model.Manager.Refresh(FProtocol);
  end;

  ModalResult := mrOk;
end;

class procedure TedProtocols.ShowEditor(Protocol: TProtocol;
  const APlugin: IViewerPlugin);
var
  Editor: TedProtocols;
  TemplateIdx: Integer;
  I: Integer;
begin
  if not Assigned(APlugin) then
    raise EArgumentNilException.Create('Protocol viewer is required');
  Editor := TedProtocols.Create(nil);
  try
    if not Supports(APlugin, IProtocolEditor, Editor.FEditor) then
      raise EArgumentException.Create('Protocol viewer does not support editing');
    Editor.FPlugin := APlugin;
    Editor.FEditor.PrepareForReparent;
    Editor.FOldParent := APlugin.Frame.Parent;
    APlugin.Frame.Parent := Editor.pnlFormArea;
    APlugin.Frame.Align := alClient;
    Editor.FEditor.ReadOnly := False;
    Editor.FEditor.SetOnDirty(Editor.HandleFieldChanged);
    Editor.FInitializing := True;
    Editor.FProtocol := Protocol;
    Editor.FOriginalStatus := Protocol.ValidationStatus;

    // Load existing protocol data
    Editor.edtTitle.Text := Protocol.Title;

    if Protocol.ProtocolType.HasValue then
      Editor.cmbProtocolType.ItemIndex := Ord(Protocol.ProtocolType.Value)
    else
      Editor.cmbProtocolType.ItemIndex := 0;

    // Store existing form data for later injection
    Editor.FFormData := Protocol.FormData;

    // Populate status combo with allowed transitions
    Editor.PopulateStatusCombo(Protocol);

    // Populate template combobox
    Editor.PopulateTemplates;

    // Select the matching template in combo (search by Object reference)
    TemplateIdx := 0; // Default: "(No template)"
    if Protocol.TemplateId.HasValue then
    begin
      for I := 0 to Editor.cmbTemplate.Items.Count - 1 do
      begin
        if Assigned(Editor.cmbTemplate.Items.Objects[I]) and
           (TTemplate(Editor.cmbTemplate.Items.Objects[I]).Id = Protocol.TemplateId.Value) then
        begin
          TemplateIdx := I;
          Break;
        end;
      end;
    end;
    Editor.cmbTemplate.ItemIndex := TemplateIdx;

    // Template is loaded in FormShow (after form is visible)

    // Set read-only if approved
    if Model.ProtocolStatus.IsProtocolReadOnly(Protocol.ValidationStatus) then
      Editor.SetReadOnlyMode;

    // Show/hide history button based on whether protocol has been saved
    Editor.btnHistory.Visible := Protocol.Id > 0;

    Editor.FInitializing := False;
    Editor.SetDirty(False);  // baseline: nothing edited yet
    Editor.ShowModal;
  finally
    Editor.FTemplateList.Free;
    Editor.Free;
  end;
end;

procedure TedProtocols.PopulateStatusCombo(Protocol: TProtocol);
var
  CurrentStatus: TValidationStatus;
  ProjectId, AuthorId: Integer;
  HasAccessContext: Boolean;
  Allowed: TArray<TValidationStatus>;
  S: TValidationStatus;
begin
  cmbValidationStatus.Items.Clear;
  FStatusValues.Clear;

  CurrentStatus := Protocol.ValidationStatus;
  HasAccessContext := Model.ProtocolStatus.TryGetAccessContext(Protocol.Id, ProjectId, AuthorId);

  // Always include current status as first item
  cmbValidationStatus.Items.Add(StatusDisplayNames[CurrentStatus]);
  FStatusValues.Add(CurrentStatus);

  // Add allowed transitions
  if HasAccessContext then
    Allowed := Model.ProtocolStatus.GetAllowedTransitions(CurrentStatus,
      Model.User, ProjectId, AuthorId)
  else
    Allowed := [];
  for S in Allowed do
  begin
    cmbValidationStatus.Items.Add(StatusDisplayNames[S]);
    FStatusValues.Add(S);
  end;

  cmbValidationStatus.ItemIndex := 0;
end;

procedure TedProtocols.SetReadOnlyMode;
begin
  FReadOnly := True;
  edtTitle.ReadOnly := True;
  cmbProtocolType.Enabled := False;
  cmbValidationStatus.Enabled := False;
  cmbTemplate.Enabled := False;
  FEditor.ReadOnly := True;
  btnSave.Visible := False;
  btnCancel.Caption := 'Close';
  Caption := 'View Protocol (Approved - Read Only)';
end;

procedure TedProtocols.PopulateTemplates;
var
  DisplayName, LastCategory: string;
begin
  cmbTemplate.Items.Clear;
  cmbTemplate.Items.AddObject('(No template)', nil);

  FTemplateList := Model.Templates.GetLatestVersions;
  if not Assigned(FTemplateList) then
  begin
    cmbTemplate.ItemIndex := 0;
    Exit;
  end;

  // Sort by Category then Name
  FTemplateList.Sort(TComparer<TTemplate>.Construct(
    function(const L, R: TTemplate): Integer
    begin
      Result := CompareText(L.Category, R.Category);
      if Result = 0 then
        Result := CompareText(L.Name, R.Name);
    end));

  LastCategory := #1; // sentinel — never matches a real category
  for var T in FTemplateList do
  begin
    if not SameText(T.Category, LastCategory) then
    begin
      LastCategory := T.Category;
      if LastCategory <> '' then
        cmbTemplate.Items.AddObject('--- ' + LastCategory + ' ---', nil)
      else
        cmbTemplate.Items.AddObject('--- Uncategorized ---', nil);
    end;

    if T.Version > 1 then
      DisplayName := Format('   %s (v%d)', [T.Name, T.Version])
    else
      DisplayName := '   ' + T.Name;
    cmbTemplate.Items.AddObject(DisplayName, T);
  end;

  cmbTemplate.ItemIndex := 0;
end;

function TedProtocols.GetSelectedTemplate: TTemplate;
begin
  if (cmbTemplate.ItemIndex > 0) and
     Assigned(cmbTemplate.Items.Objects[cmbTemplate.ItemIndex]) then
    Result := TTemplate(cmbTemplate.Items.Objects[cmbTemplate.ItemIndex])
  else
    Result := nil;
end;

procedure TedProtocols.LoadCurrentTemplate;
var
  Template: TTemplate;
begin
  Template := GetSelectedTemplate;
  if Assigned(Template) then
    FEditor.LoadTemplate(Model.Templates.GetTemplateHtml(Template), FFormData)
  else
    FEditor.LoadFreeText(FFormData);
end;

procedure TedProtocols.cmbTemplateChange(Sender: TObject);
begin
  // Skip category separator lines (Objects = nil, ItemIndex > 0)
  if (cmbTemplate.ItemIndex > 0) and
     not Assigned(cmbTemplate.Items.Objects[cmbTemplate.ItemIndex]) then
  begin
    // Move to next valid template item
    if cmbTemplate.ItemIndex < cmbTemplate.Items.Count - 1 then
      cmbTemplate.ItemIndex := cmbTemplate.ItemIndex + 1
    else
      cmbTemplate.ItemIndex := 0;
    Exit;
  end;
  FFormData := ''; // Clear saved data when changing template
  SetDirty(True);
  LoadCurrentTemplate;
end;

procedure TedProtocols.btnHistoryClick(Sender: TObject);
var
  History: TProtocolStatusChanges;
  Change: TProtocolStatusChange;
  HistoryForm: TForm;
  ListView: TListView;
  Item: TListItem;
begin
  if FProtocol.Id <= 0 then Exit;

  History := Model.ProtocolStatus.GetStatusHistory(FProtocol.Id);
  try
    HistoryForm := TForm.Create(Self);
    try
      HistoryForm.Caption := 'Status History - ' + FProtocol.Title;
      HistoryForm.Width := 700;
      HistoryForm.Height := 400;
      HistoryForm.Position := poMainFormCenter;

      ListView := TListView.Create(HistoryForm);
      ListView.Parent := HistoryForm;
      ListView.Align := alClient;
      ListView.ViewStyle := vsReport;
      ListView.ReadOnly := True;
      ListView.RowSelect := True;

      ListView.Columns.Add.Caption := 'Date';
      ListView.Columns[0].Width := 160;
      ListView.Columns.Add.Caption := 'From';
      ListView.Columns[1].Width := 100;
      ListView.Columns.Add.Caption := 'To';
      ListView.Columns[2].Width := 100;
      ListView.Columns.Add.Caption := 'By (User ID)';
      ListView.Columns[3].Width := 100;
      ListView.Columns.Add.Caption := 'Comment';
      ListView.Columns[4].Width := 200;

      for Change in History do
      begin
        Item := ListView.Items.Add;
        Item.Caption := DateTimeToStr(FromUTC(Change.ChangedDate));
        Item.SubItems.Add(StatusDisplayNames[Change.OldStatus]);
        Item.SubItems.Add(StatusDisplayNames[Change.NewStatus]);
        Item.SubItems.Add(IntToStr(Change.ChangedBy));
        Item.SubItems.Add(Change.Comment);
      end;

      HistoryForm.ShowModal;
    finally
      HistoryForm.Free;
    end;
  finally
    History.Free;
  end;
end;

function TedProtocols.ValidateProtocol: Boolean;
begin
  Result := False;

  if Trim(edtTitle.Text) = '' then
  begin
    MessageDlg('Protocol title cannot be empty.', mtWarning, [mbOK], 0);
    edtTitle.SetFocus;
    Exit;
  end;

  Result := True;
end;

end.
