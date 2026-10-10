unit dlg_ReportExport;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.CheckLst, Vcl.Edge,
  RzButton, RzPanel, RzEdit,
  System.Generics.Collections,
  unit_Item, unit_ItemTypes, unit_Template, unit_LabEntry, unit_Protocol,
  unit_Tag, unit_Comment, unit_Signature,
  unit_ReportBuilder, unit_ELNPluginCore, Vcl.Mask;

type
  TdlgReportExport = class(TForm)
    pnlLeft: TRzPanel;
    pnlRight: TRzPanel;
    pnlBottom: TRzPanel;
    spMain: TSplitter;
    lblItems: TLabel;
    clbItems: TCheckListBox;
    gbSections: TGroupBox;
    chkMetadata: TCheckBox;
    chkProtocols: TCheckBox;
    chkValues: TCheckBox;
    chkFiles: TCheckBox;
    chkTags: TCheckBox;
    chkComments: TCheckBox;
    chkSignatures: TCheckBox;
    rgPaper: TRadioGroup;
    lblPath: TLabel;
    edtPath: TRzEdit;
    btnBrowse: TRzButton;
    btnPreview: TRzButton;
    btnExport: TRzButton;
    btnCancel: TRzButton;
    SaveDialog: TSaveDialog;
    procedure btnBrowseClick(Sender: TObject);
    procedure btnPreviewClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FItems: TItems;
    FTemplates: TDictionary<Integer, TTemplate>;
    FHtmlViewer: IViewerPlugin;
    FSavedParent: TWinControl;
    FTempFile: string;
    FWorkingRoot: string;
    FExporting: Boolean;
    procedure CollectTemplates;
    procedure EnsurePreviews;
    function BuildOptions: TReportOptions;
    function BuildReportData: TList<TReportItemData>;
    procedure RefreshPreview;
    function FindEdgeBrowser(AParent: TWinControl): TEdgeBrowser;
    procedure PrintToPdfCompleted(Sender: TCustomEdgeBrowser;
      AErrorCode: HResult; AIsSuccessful: Boolean);
  public
    destructor Destroy; override;
    class function Execute(Item: TItem; AllItems: TItems;
      HtmlViewer: IViewerPlugin; const WorkingRoot: string): Boolean;
  end;

implementation

{$R *.dfm}

uses
  unit_DataModel, unit_NotebookSettings, System.IOUtils;


destructor TdlgReportExport.Destroy;
begin
  if Assigned(FHtmlViewer) and Assigned(FSavedParent) then
  begin
    FHtmlViewer.Frame.Parent := FSavedParent;
    FHtmlViewer.Frame.Align := alClient;
  end;
  FTemplates.Free;
  if (FTempFile <> '') and FileExists(FTempFile) then
    DeleteFile(FTempFile);
  inherited;
end;

class function TdlgReportExport.Execute(Item: TItem; AllItems: TItems;
  HtmlViewer: IViewerPlugin; const WorkingRoot: string): Boolean;

  procedure AddChildren(Dialog: TdlgReportExport; ParentId: Integer;
    AllItems: TItems; Depth: Integer);
  var
    It: TItem;
  begin
    for It in AllItems do
      if It.Parent = ParentId then
      begin
        Dialog.clbItems.Items.AddObject(StringOfChar(' ', Depth * 2) + It.Title, It);
        AddChildren(Dialog, It.Id, AllItems, Depth + 1);
      end;
  end;

var
  Dialog: TdlgReportExport;
  I: Integer;
  It: TItem;
  IsProc: Boolean;
begin
  Dialog := TdlgReportExport.Create(nil);
  try
    Dialog.FItems := AllItems;
    Dialog.FHtmlViewer := HtmlViewer;
    Dialog.FWorkingRoot := IncludeTrailingPathDelimiter(WorkingRoot);
    Dialog.FTemplates := TDictionary<Integer, TTemplate>.Create;
    Dialog.FExporting := False;

    IsProc := Assigned(Item) and (Item.Level = TItemLevel.Proc);

    if IsProc then
    begin
      Dialog.clbItems.Items.AddObject(Item.Title + ' [Proc]', Item);
      AddChildren(Dialog, Item.Id, AllItems, 1);
    end
    else if Assigned(Item) then
      Dialog.clbItems.Items.AddObject(Item.Title, Item)
    else
    begin
      for It in AllItems do
        Dialog.clbItems.Items.AddObject(It.Title, It);
    end;

    for I := 0 to Dialog.clbItems.Count - 1 do
      Dialog.clbItems.Checked[I] := True;

    Dialog.CollectTemplates;

    Dialog.ShowModal;
    Result := True;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgReportExport.FormShow(Sender: TObject);
begin
  // Borrow the viewer supplied by the host.
  if Assigned(FHtmlViewer) then
  begin
    FSavedParent := FHtmlViewer.Frame.Parent;
    FHtmlViewer.Frame.Parent := pnlRight;
    FHtmlViewer.Frame.Align := alClient;
    RefreshPreview;
  end
  else
    MessageDlg('HTML viewer plugin not available.', mtError, [mbOK], 0);
end;

procedure TdlgReportExport.CollectTemplates;
var
  It: TItem;
  Entry: TLabEntry;
  Protocol: TProtocol;
  Tmpl: TTemplate;
  I: Integer;
begin
  for I := 0 to clbItems.Count - 1 do
  begin
    It := TItem(clbItems.Items.Objects[I]);
    for Entry in It.Entries do
    begin
      if not (Entry is TProtocol) then Continue;
      Protocol := TProtocol(Entry);
      if Protocol.TemplateId.HasValue and not FTemplates.ContainsKey(Protocol.TemplateId.Value) then
      begin
        Tmpl := Model.Templates.GetTemplateById(Protocol.TemplateId.Value);
        if Assigned(Tmpl) then
          FTemplates.AddOrSetValue(Protocol.TemplateId.Value, Tmpl);
      end;
    end;
  end;
end;

procedure TdlgReportExport.EnsurePreviews;
var
  I: Integer;
  It: TItem;
  F: unit_Item.TFile;
  PreviewPath, StoragePath: string;
begin
  for I := 0 to clbItems.Count - 1 do
  begin
    if not clbItems.Checked[I] then Continue;
    It := TItem(clbItems.Items.Objects[I]);
    for F in It.Files do
    begin
      StoragePath := Format('previews/[1000]/%.*d_%.*d.png',
        [5, It.Id, 5, F.Id]);
      PreviewPath := FWorkingRoot +
        StringReplace(StoragePath, '/', PathDelim, [rfReplaceAll]);
      // Absence or a failed refresh must not leave a previous report's PNG.
      if FileExists(PreviewPath) and not System.SysUtils.DeleteFile(PreviewPath) then
        RaiseLastOSError;
      if Model.Storage.Exists(StoragePath) then
      begin
        ForceDirectories(ExtractFilePath(PreviewPath));
        try
          Model.Storage.CopyOut(StoragePath, PreviewPath);
        except
          System.SysUtils.DeleteFile(PreviewPath);
          raise;
        end;
      end;
    end;
  end;
end;

function TdlgReportExport.BuildOptions: TReportOptions;
var
  Sett: TNotebookSettings;
begin
  Result.IncludeMetadata := chkMetadata.Checked;
  Result.IncludeProtocols := chkProtocols.Checked;
  Result.IncludeValues := chkValues.Checked;
  Result.IncludeFiles := chkFiles.Checked;
  Result.IncludeTags := chkTags.Checked;
  Result.IncludeComments := chkComments.Checked;
  Result.IncludeSignatures := chkSignatures.Checked;
  if rgPaper.ItemIndex = 1 then
    Result.PaperSize := psLetter
  else
    Result.PaperSize := psA4;
  Sett := TNotebookSettings.Create;
  try
    Result.LogoPath := Sett.ReportLogoPath;
  finally
    Sett.Free;
  end;
end;

function TdlgReportExport.BuildReportData: TList<TReportItemData>;
var
  I: Integer;
  It: TItem;
  Data: TReportItemData;
begin
  Result := TList<TReportItemData>.Create;


  for I := 0 to clbItems.Count - 1 do
  begin
    if not clbItems.Checked[I] then Continue;

    It := TItem(clbItems.Items.Objects[I]);

    Data.Item := It;
    Data.Templates := FTemplates;
    Data.StorageRoot := FWorkingRoot;
    Data.Tags := Model.Tags.GetTagsForItem(It.Id);
    Data.Comments := Model.Comments.GetComments(It.Id);
    Data.Signature := Model.Signatures.GetSignature(It.Id);
    Data.HasSignature := Assigned(Data.Signature);
    Data.IntegrityState := Model.Signatures.GetIntegrityState(It.Id);

    Result.Add(Data);
  end;
end;

procedure TdlgReportExport.RefreshPreview;
var
  ReportData: TList<TReportItemData>;
  Options: TReportOptions;
  Html: string;
  SL: TStringList;
  PreviewId: TGUID;
begin
  if not Assigned(FHtmlViewer) then
  begin
    MessageDlg('HTML viewer plugin not available.', mtError, [mbOK], 0);
    Exit;
  end;

  try
    Options := BuildOptions;
    EnsurePreviews;
    ReportData := BuildReportData;
    try
      if ReportData.Count = 0 then
        Html := '<html><body><p>No items selected.</p></body></html>'
      else
        Html := TReportBuilder.BuildReport(ReportData, Options);
    finally
      ReportData.Free;
    end;

    if FTempFile = '' then
    begin
      ForceDirectories(FWorkingRoot);
      CreateGUID(PreviewId);
      FTempFile := TPath.Combine(FWorkingRoot,
        'report-' + GUIDToString(PreviewId) + '.html');
    end;

    SL := TStringList.Create;
    try
      SL.Text := Html;
      SL.SaveToFile(FTempFile, TEncoding.UTF8);
    finally
      SL.Free;
    end;

    FHtmlViewer.LoadFromFile(FTempFile);
  except
    on E: Exception do
      MessageDlg('Error generating report: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

function TdlgReportExport.FindEdgeBrowser(AParent: TWinControl): TEdgeBrowser;
var
  I: Integer;
  Child: TControl;
begin
  Result := nil;
  for I := 0 to AParent.ControlCount - 1 do
  begin
    Child := AParent.Controls[I];
    if Child is TEdgeBrowser then
      Exit(TEdgeBrowser(Child));
    if Child is TWinControl then
    begin
      Result := FindEdgeBrowser(TWinControl(Child));
      if Assigned(Result) then Exit;
    end;
  end;
end;

procedure TdlgReportExport.btnBrowseClick(Sender: TObject);
begin
  SaveDialog.FileName := 'report.pdf';
  if SaveDialog.Execute then
    edtPath.Text := SaveDialog.FileName;
end;

procedure TdlgReportExport.btnPreviewClick(Sender: TObject);
begin
  RefreshPreview;
end;

procedure TdlgReportExport.btnExportClick(Sender: TObject);
var
  Browser: TEdgeBrowser;
begin
  if Trim(edtPath.Text) = '' then
  begin
    SaveDialog.FileName := 'report.pdf';
    if not SaveDialog.Execute then
      Exit;
    edtPath.Text := SaveDialog.FileName;
  end;

  if FExporting then
  begin
    MessageDlg('Export already in progress.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if not Assigned(FHtmlViewer) then
  begin
    MessageDlg('HTML viewer plugin not available.', mtError, [mbOK], 0);
    Exit;
  end;

  RefreshPreview;

  Browser := FindEdgeBrowser(FHtmlViewer.Frame);
  if not Assigned(Browser) then
  begin
    MessageDlg('Cannot find browser component for PDF export.', mtError, [mbOK], 0);
    Exit;
  end;

  FExporting := True;
  btnExport.Enabled := False;
  Browser.OnPrintToPDFCompleted := PrintToPdfCompleted;
  Browser.PrintToPDF(edtPath.Text, nil);
end;

procedure TdlgReportExport.PrintToPdfCompleted(Sender: TCustomEdgeBrowser;
  AErrorCode: HResult; AIsSuccessful: Boolean);
begin
  FExporting := False;
  btnExport.Enabled := True;

  if AIsSuccessful then
  begin
    MessageDlg(Format('Report exported successfully to:%s%s',
      [sLineBreak, edtPath.Text]), mtInformation, [mbOK], 0);
    ModalResult := mrOk;
  end
  else
    MessageDlg('Failed to export PDF. Please try again.', mtError, [mbOK], 0);
end;

end.
