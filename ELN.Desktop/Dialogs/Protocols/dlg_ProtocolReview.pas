unit dlg_ProtocolReview;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls,
  RzPanel, RzButton,
  unit_ELNPluginCore,
  unit_Protocol,
  unit_Item;

type
  TFilterMode = (fmInReview, fmRejected, fmAll);

  TdlgProtocolReview = class(TForm)
    pnlTop: TPanel;
    lblFilter: TLabel;
    cmbFilter: TComboBox;
    btnRefresh: TRzButton;
    pnlLeft: TPanel;
    ListView: TListView;
    Splitter1: TSplitter;
    pnlPreview: TPanel;
    pnlBottom: TRzPanel;
    btnApprove: TRzButton;
    btnReject: TRzButton;
    btnView: TRzButton;
    btnClose: TRzButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure cmbFilterChange(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnApproveClick(Sender: TObject);
    procedure btnRejectClick(Sender: TObject);
    procedure btnViewClick(Sender: TObject);
    procedure ListViewSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
  private
    FProtocols: TList<TProtocol>;
    FPlugin: IViewerPlugin;
    FOldParent: TWinControl;
    procedure RefreshList;
    procedure UpdateButtons;
    procedure ShowPreview;
    function GetSelectedProtocol: TProtocol;
    function CanTransition(Protocol: TProtocol; ATo: TValidationStatus): Boolean;
  public
    class procedure ShowQueue(const APlugin: IViewerPlugin);
  end;

implementation

{$R *.dfm}

uses
  System.TypInfo,
  unit_DataModel,
  unit_User,
  unit_Template,
  editor_Protocols,
  unit_NotebookSettings,
  unit_TimeHelper;

const
  StatusDisplayNames: array[TValidationStatus] of string = (
    'Draft', 'In Review', 'Approved', 'Rejected'
  );

{ TdlgProtocolReview }

class procedure TdlgProtocolReview.ShowQueue(const APlugin: IViewerPlugin);
var
  Dialog: TdlgProtocolReview;
  Editor: IProtocolEditor;
begin
  Dialog := TdlgProtocolReview.Create(Application);
  try
    Dialog.FPlugin := APlugin;
    if Assigned(APlugin) then
    begin
      if Supports(APlugin, IProtocolEditor, Editor) then
        Editor.PrepareForReparent;
      Dialog.FOldParent := APlugin.Frame.Parent;
      APlugin.Frame.Parent := Dialog.pnlPreview;
      APlugin.Frame.Align := alClient;
    end;
    Dialog.RefreshList;
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgProtocolReview.FormCreate(Sender: TObject);
var
  LSettings: TNotebookSettings;
begin
  FProtocols := nil;

  LSettings := TNotebookSettings.Create;
  try
    pnlLeft.Width := LSettings.LoadUIValue('dlgProtocolReview', 'pnlLeft', pnlLeft.Width);
  finally
    LSettings.Free;
  end;

  cmbFilter.Items.Add('In Review');
  cmbFilter.Items.Add('Rejected');
  cmbFilter.Items.Add('All');
  cmbFilter.ItemIndex := 0;

end;

procedure TdlgProtocolReview.FormDestroy(Sender: TObject);
var
  LSettings: TNotebookSettings;
begin
  LSettings := TNotebookSettings.Create;
  try
    LSettings.SaveUIValue('dlgProtocolReview', 'pnlLeft', pnlLeft.Width);
  finally
    LSettings.Free;
  end;

  // Return frame to ContentViewer's card
  if Assigned(FPlugin) then
  begin
    var Editor: IProtocolEditor;
    if Supports(FPlugin, IProtocolEditor, Editor) then
      Editor.PrepareForReparent;
    FPlugin.Frame.Parent := FOldParent;
  end;
  FPlugin := nil;
  FreeAndNil(FProtocols);
end;

procedure TdlgProtocolReview.RefreshList;
var
  Protocol: TProtocol;
  ListItem: TListItem;
  Item: TItem;
  User: TUser;
  SelectedIdx: Integer;
  FilterMode: TFilterMode;
  FilteredProtocols: TList<TProtocol>;
begin
  SelectedIdx := -1;
  if ListView.Selected <> nil then
    SelectedIdx := ListView.Selected.Index;

  ListView.Items.BeginUpdate;
  try
    ListView.Items.Clear;
    FreeAndNil(FProtocols);

    FilterMode := TFilterMode(cmbFilter.ItemIndex);

    case FilterMode of
      fmInReview:
        FProtocols := Model.ProtocolStatus.GetProtocolsByStatus(vsInReview);
      fmRejected:
        FProtocols := Model.ProtocolStatus.GetProtocolsByStatus(vsRejected);
      fmAll:
      begin
        // Merge InReview + Rejected lists
        FProtocols := Model.ProtocolStatus.GetProtocolsByStatus(vsInReview);
        FilteredProtocols := Model.ProtocolStatus.GetProtocolsByStatus(vsRejected);
        try
          for Protocol in FilteredProtocols do
            FProtocols.Add(Protocol);
        finally
          FilteredProtocols.Free;
        end;
      end;
    end;

    for Protocol in FProtocols do
    begin
      ListItem := ListView.Items.Add;
      ListItem.Caption := Protocol.Title;
      ListItem.Data := Protocol;

      // Look up parent Item via Entries association
      Item := Model.Items.GetItemForEntry(Protocol.Id);
      if Assigned(Item) then
        ListItem.SubItems.Add(Item.Title)
      else
        ListItem.SubItems.Add('');

      // Look up creator
      if Protocol.CreatedBy.HasValue then
      begin
        User := Model.Authors.GetUser(Protocol.CreatedBy.Value);
        if Assigned(User) then
          ListItem.SubItems.Add(User.FirstName + ' ' + User.LastName)
        else
          ListItem.SubItems.Add('User #' + IntToStr(Protocol.CreatedBy.Value));
      end
      else
        ListItem.SubItems.Add('');
    end;

    // Restore selection
    if (SelectedIdx >= 0) and (SelectedIdx < ListView.Items.Count) then
      ListView.Items[SelectedIdx].Selected := True
    else if ListView.Items.Count > 0 then
      ListView.Items[0].Selected := True;
  finally
    ListView.Items.EndUpdate;
  end;

  UpdateButtons;
end;

procedure TdlgProtocolReview.ShowPreview;
var
  Protocol: TProtocol;
  ProtocolTypeStr, StatusStr, ModifiedStr, TemplateHtml: string;
  Template: TTemplate;
  Encoded: string;
begin
  Protocol := GetSelectedProtocol;
  if not Assigned(Protocol) or not Assigned(FPlugin) then
    Exit;

  if Protocol.ProtocolType.HasValue then
    ProtocolTypeStr := GetEnumName(TypeInfo(TProtocolType), Ord(Protocol.ProtocolType.Value))
  else
    ProtocolTypeStr := 'Not specified';

  StatusStr := StatusDisplayNames[Protocol.ValidationStatus];

  if Protocol.ModifiedDate.HasValue then
    ModifiedStr := DateToStr(FromUTC(Protocol.ModifiedDate.Value))
  else
    ModifiedStr := '';

  TemplateHtml := '';
  if Protocol.TemplateId.HasValue then
  begin
    Template := Model.Templates.GetTemplateById(Protocol.TemplateId.Value);
    if Assigned(Template) then
      TemplateHtml := Model.Templates.GetTemplateHtml(Template);
  end;

  Encoded := ProtocolTypeStr + #1 + StatusStr + #1 +
             DateToStr(FromUTC(Protocol.CreatedDate)) + #1 +
             ModifiedStr + #1 +
             Protocol.FormData + #1 +
             TemplateHtml + #1 +
             Protocol.EquipModel + #1 +
             Protocol.EquipManufacturer + #1 +
             Protocol.EquipLocation;

  FPlugin.DisplayText(Protocol.Title, Encoded);
end;

procedure TdlgProtocolReview.UpdateButtons;
var
  Protocol: TProtocol;
  HasSelection: Boolean;
begin
  Protocol := GetSelectedProtocol;
  HasSelection := Assigned(Protocol);

  btnView.Enabled := HasSelection;
  btnApprove.Enabled := CanTransition(Protocol, vsApproved);
  btnReject.Enabled := CanTransition(Protocol, vsRejected);
end;

function TdlgProtocolReview.CanTransition(Protocol: TProtocol;
  ATo: TValidationStatus): Boolean;
var
  ProjectId, AuthorId: Integer;
begin
  Result := False;
  if Protocol = nil then
    Exit;
  if not Model.ProtocolStatus.TryGetAccessContext(Protocol.Id, ProjectId, AuthorId) then
    Exit;
  Result := Model.ProtocolStatus.CanTransition(Protocol.ValidationStatus, ATo,
    Model.User, ProjectId, AuthorId);
end;

function TdlgProtocolReview.GetSelectedProtocol: TProtocol;
begin
  if Assigned(ListView.Selected) then
    Result := TProtocol(ListView.Selected.Data)
  else
    Result := nil;
end;

procedure TdlgProtocolReview.cmbFilterChange(Sender: TObject);
begin
  RefreshList;
end;

procedure TdlgProtocolReview.btnRefreshClick(Sender: TObject);
begin
  RefreshList;
end;

procedure TdlgProtocolReview.btnApproveClick(Sender: TObject);
var
  Protocol: TProtocol;
  OldStatus: TValidationStatus;
  ExpectedVersion: Integer;
begin
  Protocol := GetSelectedProtocol;
  if not Assigned(Protocol) then Exit;
  if not CanTransition(Protocol, vsApproved) then Exit;
  OldStatus := Protocol.ValidationStatus;
  ExpectedVersion := Protocol.Version;

  if MessageDlg('Approve this protocol?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  try
    Model.ProtocolStatus.Transition(Model.User, Protocol.Id,
      ExpectedVersion, OldStatus, vsApproved, '');
  except
    on E: Exception do
    begin
      try
        Model.Manager.Refresh(Protocol);
      except
      end;
      raise;
    end;
  end;
  Model.Manager.Refresh(Protocol);

  RefreshList;
end;

procedure TdlgProtocolReview.btnRejectClick(Sender: TObject);
var
  Protocol: TProtocol;
  OldStatus: TValidationStatus;
  Comment: string;
  ExpectedVersion: Integer;
begin
  Protocol := GetSelectedProtocol;
  if not Assigned(Protocol) then Exit;
  if not CanTransition(Protocol, vsRejected) then Exit;
  OldStatus := Protocol.ValidationStatus;
  ExpectedVersion := Protocol.Version;

  Comment := '';
  if not InputQuery('Reject Protocol', 'Reason for rejection:', Comment) then
    Exit;

  try
    Model.ProtocolStatus.Transition(Model.User, Protocol.Id,
      ExpectedVersion, OldStatus, vsRejected, Comment);
  except
    on E: Exception do
    begin
      try
        Model.Manager.Refresh(Protocol);
      except
      end;
      raise;
    end;
  end;
  Model.Manager.Refresh(Protocol);

  RefreshList;
end;

procedure TdlgProtocolReview.btnViewClick(Sender: TObject);
var
  Protocol: TProtocol;
begin
  Protocol := GetSelectedProtocol;
  if not Assigned(Protocol) then Exit;

  TedProtocols.ShowEditor(Protocol, FPlugin);

  RefreshList;
end;

procedure TdlgProtocolReview.ListViewSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
  if Selected then
    ShowPreview;
end;

end.
