unit editor_ProtocolTemplates;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls,
  RzButton, RzPanel,
  System.UITypes,
  unit_Template, unit_ELNPluginCore;

type
  TedTemplates = class(TForm)
    pnlBottom: TRzPanel;
    btnAdd: TRzButton;
    btnEdit: TRzButton;
    btnDelete: TRzButton;
    btnDuplicate: TRzButton;
    btnReimport: TRzButton;
    btnClose: TRzButton;
    lstTemplates: TListView;
    chkAllVersions: TCheckBox;
    procedure btnAddClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnDuplicateClick(Sender: TObject);
    procedure btnReimportClick(Sender: TObject);
    procedure chkAllVersionsClick(Sender: TObject);
  private
    FHtmlViewer: IViewerPlugin;
    procedure RefreshList;
    function GetSelectedTemplateId: Integer;
  public
    class procedure ShowManager(const AHtmlViewer: IViewerPlugin);
  end;

implementation

{$R *.dfm}

uses
  unit_DataModel,
  unit_NotebookSettings,
  unit_TemplateTagsModel,
  dlg_ProtocolTemplateEditor,
  dlg_CategorySelect,
  unit_TimeHelper;


class procedure TedTemplates.ShowManager(const AHtmlViewer: IViewerPlugin);
var
  Dialog: TedTemplates;
begin
  Dialog := TedTemplates.Create(nil);
  try
    Dialog.FHtmlViewer := AHtmlViewer;
    Dialog.RefreshList;
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

procedure TedTemplates.RefreshList;
var
  Templates: TTemplates;
  T: TTemplate;
  Item: TListItem;
begin
  lstTemplates.Items.Clear;

  if chkAllVersions.Checked then
    Templates := Model.Templates.GetAllTemplates
  else
    Templates := Model.Templates.GetActiveTemplates;

  try
    for T in Templates do
    begin
      Item := lstTemplates.Items.Add;
      Item.Caption := T.Name;
      Item.SubItems.Add(T.Category);
      Item.SubItems.Add(T.Description);
      Item.SubItems.Add(IntToStr(T.Version));
      if T.IsActive then
        Item.SubItems.Add('Yes')
      else
        Item.SubItems.Add('No');
      Item.SubItems.Add(DateTimeToStr(FromUTC(T.CreatedDate)));
      Item.Data := Pointer(T.Id);
    end;
  finally
    Templates.Free;
  end;
end;

function TedTemplates.GetSelectedTemplateId: Integer;
begin
  if Assigned(lstTemplates.Selected) then
    Result := Integer(lstTemplates.Selected.Data)
  else
    Result := -1;
end;

procedure TedTemplates.btnAddClick(Sender: TObject);
var
  Template: TTemplate;
  Tags: TTemplateTagsSnapshot;
begin
  Template := TTemplate.Create;
  try
    SetLength(Tags.EquipmentTypeIds, 0);
    SetLength(Tags.EquipmentIds, 0);
    if dlg_ProtocolTemplateEditor.TdlgTemplateEditor.Execute(Template, Tags, FHtmlViewer) then
    begin
      Model.Templates.SaveTemplate(Template);
      Model.Templates.SaveTagsFor(Template.Id, Tags);
      RefreshList;
    end;
  except
    Template.Free;
    raise;
  end;
end;

procedure TedTemplates.btnEditClick(Sender: TObject);
var
  Id: Integer;
  Template, Draft: TTemplate;
begin
  Id := GetSelectedTemplateId;
  if Id < 0 then
  begin
    MessageDlg('Please select a template to edit.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Template := Model.Templates.GetTemplateById(Id);
  if not Assigned(Template) then
    Exit;

  var Tags: TTemplateTagsSnapshot := Model.Templates.LoadTagsFor(Template.Id);
  Draft := Model.Templates.CreateDraft(Template.Id);
  try
    if dlg_ProtocolTemplateEditor.TdlgTemplateEditor.Execute(Draft, Tags, FHtmlViewer) then
    begin
      var Persisted := Model.Templates.SaveOrVersion(Template.Id, Draft);
      Model.Templates.SaveTagsFor(Persisted.Id, Tags);
      RefreshList;
    end;
  finally
    Draft.Free;
  end;
end;

procedure TedTemplates.btnDeleteClick(Sender: TObject);
var
  Id: Integer;
  InUse: Boolean;
  Msg: string;
begin
  Id := GetSelectedTemplateId;
  if Id < 0 then
  begin
    MessageDlg('Please select a template to delete.', mtInformation, [mbOK], 0);
    Exit;
  end;

  InUse := Model.Templates.IsTemplateInUse(Id);
  if InUse then
    Msg := 'This template is in use by protocols. It will be deactivated (not deleted). Continue?'
  else
    Msg := 'Are you sure you want to delete this template?';

  if MessageDlg(Msg, mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    Model.Templates.DeleteTemplate(Id);
    RefreshList;
  end;
end;

procedure TedTemplates.btnDuplicateClick(Sender: TObject);
var
  Id: Integer;
  Source, Copy: TTemplate;
begin
  Id := GetSelectedTemplateId;
  if Id < 0 then
  begin
    MessageDlg('Please select a template to duplicate.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Source := Model.Templates.GetTemplateById(Id);
  if not Assigned(Source) then Exit;

  Copy := TTemplate.Create;
  Copy.Name := Source.Name + ' (Copy)';
  Copy.Description := Source.Description;
  Copy.Category := Source.Category;
  Copy.FormSchema := Source.FormSchema;

  try
    var Tags: TTemplateTagsSnapshot := Model.Templates.LoadTagsFor(Source.Id);
    if TdlgTemplateEditor.Execute(Copy, Tags, FHtmlViewer) then
    begin
      Model.Templates.SaveTemplate(Copy);
      Model.Templates.SaveTagsFor(Copy.Id, Tags);
      RefreshList;
    end;
  except
    Copy.Free;
    raise;
  end;
end;

procedure TedTemplates.btnReimportClick(Sender: TObject);
var
  TemplatesDir: string;
  LSettings: TNotebookSettings;
  Categories: TStringList;
  Overwrite: Boolean;
begin
  LSettings := TNotebookSettings.Create;
  try
    TemplatesDir := LSettings.TemplatesDir;
  finally
    LSettings.Free;
  end;
  if TemplatesDir = '' then
    TemplatesDir := ExtractFilePath(Application.ExeName) + 'ProtocolTemplates';

  if not TdlgCategorySelect.Execute(TemplatesDir, Categories, Overwrite) then
    Exit;

  try
    Model.Templates.ReimportTemplates(TemplatesDir, Overwrite, Model.User.Id, Categories);
  finally
    Categories.Free;
  end;

  RefreshList;
  MessageDlg('Templates reimported.', mtInformation, [mbOK], 0);
end;

procedure TedTemplates.chkAllVersionsClick(Sender: TObject);
begin
  RefreshList;
end;

end.
