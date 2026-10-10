unit dlg_ProtocolTemplateEditor;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.IOUtils, System.Generics.Collections, System.JSON,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls,
  RzLabel, RzButton, RzPanel, RzEdit, Vcl.Mask,
  SynEdit, SynHighlighterJSON,
  unit_ELNPluginCore,
  unit_Template,
  unit_TemplateTagsModel,
  unit_TemplateSchema,
  unit_TemplateCard,
  frame_SectionCard, frame_RowCard,
  frame_CheckboxFieldCard, frame_TextFieldCard, frame_NumberFieldCard,
  frame_DateFieldCard, frame_TextareaFieldCard, frame_RichtextFieldCard,
  frame_SelectFieldCard, frame_CheckboxGroupFieldCard,
  SynEditHighlighter, SynEditCodeFolding;

type
  TdlgTemplateEditor = class(TForm)
    pnlTop: TRzPanel;
    pnlBottom: TRzPanel;
    pnlTreeCol: TRzPanel;
    pnlPropsCol: TRzPanel;
    pnlPreview: TRzPanel;
    spltMain: TSplitter;
    spltTree: TSplitter;
    lblName: TRzLabel;
    edtName: TRzEdit;
    lblDescription: TRzLabel;
    edtDescription: TRzEdit;
    lblCategory: TRzLabel;
    edtCategory: TRzEdit;
    chkActive: TCheckBox;
    btnPreview: TRzButton;
    btnLoadExample: TRzButton;
    lblTree: TRzLabel;
    tvSchema: TTreeView;
    pnlTreeToolbar: TRzPanel;
    btnAddSection: TRzButton;
    btnAddRow: TRzButton;
    btnAddField: TRzButton;
    btnDeleteSchema: TRzButton;
    btnSchemaUp: TRzButton;
    btnSchemaDown: TRzButton;
    btnJsonToggle: TRzButton;
    synEditor: TSynEdit;
    synJsonHighlighter: TSynJSONSyn;
    lblPropCaption: TRzLabel;
    lblSchemaError: TRzLabel;
    pnlCardHost: TRzPanel;
    lblPreview: TRzLabel;
    btnOK: TRzButton;
    btnCancel: TRzButton;
    btnTags: TRzButton;
    dlgOpenSchema: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnPreviewClick(Sender: TObject);
    procedure btnLoadExampleClick(Sender: TObject);
    procedure tvSchemaChange(Sender: TObject; Node: TTreeNode);
    procedure tvSchemaDeletion(Sender: TObject; Node: TTreeNode);
    procedure btnAddSectionClick(Sender: TObject);
    procedure btnAddRowClick(Sender: TObject);
    procedure btnAddFieldClick(Sender: TObject);
    procedure btnDeleteSchemaClick(Sender: TObject);
    procedure btnSchemaUpClick(Sender: TObject);
    procedure btnSchemaDownClick(Sender: TObject);
    procedure btnJsonToggleClick(Sender: TObject);
    procedure btnTagsClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FHtmlViewer: IViewerPlugin;
    FSavedParent: TWinControl;
    FJsonMode: Boolean;
    FSchemaTitle: string;
    FSchemaAccentColor: string;
    FPreviewTimer: TTimer;
    FCurrentTypeIds: TArray<Integer>;
    FCurrentDeviceIds: TArray<Integer>;
    FCards: TDictionary<string, ITemplateCard>;
    FActiveCard: ITemplateCard;
    FCurrentNode: TTreeNode;
    FCardUpdateQueued: Boolean;
    procedure RefreshTagsButtonCaption;
    function Validate: Boolean;
    procedure PreviewSchema(const SchemaJson: string);
    procedure LoadSchemaToTree(const SchemaJson: string);
    function SaveTreeToJSON: string;
    procedure SyncNodeToProps;
    procedure CreateCards;
    procedure RegisterCard(const Key: string; Card: ITemplateCard);
    procedure ShowCardForNode(Node: TTreeNode);
    procedure HideActiveCard;
    function CardKeyForNode(SN: TSchemaNode): string;
    function CardKeyForField(const AType: string): string;
    procedure OnCardChanged(Sender: TObject);
    procedure OnCardFieldTypeChanged(Sender: TObject; const NewType: string);
    procedure ApplyQueuedCardChange;
    procedure SchedulePreviewUpdate;
    procedure PreviewTimerFire(Sender: TObject);
    function FindParentOfKind(Node: TTreeNode; Kind: TSchemaNodeKind): TTreeNode;
    procedure RenumberRows(SectionNode: TTreeNode);
  public
    class function Execute(Template: TTemplate;
      const AHtmlViewer: IViewerPlugin): Boolean; overload;
    /// The caller must persist the returned tag snapshot after persisting the template.
    class function Execute(Template: TTemplate;
      var Tags: TTemplateTagsSnapshot;
      const AHtmlViewer: IViewerPlugin): Boolean; overload;
  end;

implementation

{$R *.dfm}

uses
  unit_ProtocolTemplateHtmlGenerator,
  unit_NotebookSettings,
  unit_TimeHelper,
  unit_DataModel,
  unit_Equipment, unit_EquipmentType,
  dlg_TemplateEquipmentTags;


class function TdlgTemplateEditor.Execute(Template: TTemplate;
  const AHtmlViewer: IViewerPlugin): Boolean;
var
  Tags: TTemplateTagsSnapshot;
begin
  SetLength(Tags.EquipmentTypeIds, 0);
  SetLength(Tags.EquipmentIds, 0);
  Result := Execute(Template, Tags, AHtmlViewer);
end;

class function TdlgTemplateEditor.Execute(Template: TTemplate;
  var Tags: TTemplateTagsSnapshot; const AHtmlViewer: IViewerPlugin): Boolean;
var
  Dialog: TdlgTemplateEditor;
  Json: string;
begin
  Dialog := TdlgTemplateEditor.Create(nil);
  try
    Dialog.FHtmlViewer := AHtmlViewer;
    if Assigned(Dialog.FHtmlViewer) then
    begin
      Dialog.FSavedParent := Dialog.FHtmlViewer.Frame.Parent;
      Dialog.FHtmlViewer.Frame.Parent := Dialog.pnlPreview;
      Dialog.FHtmlViewer.Frame.Align := alClient;
    end;

    Dialog.edtName.Text        := Template.Name;
    Dialog.edtDescription.Text := Template.Description;
    Dialog.edtCategory.Text    := Template.Category;
    Dialog.chkActive.Checked   := Template.IsActive;

    Dialog.FCurrentTypeIds := Copy(Tags.EquipmentTypeIds);
    Dialog.FCurrentDeviceIds := Copy(Tags.EquipmentIds);
    Dialog.RefreshTagsButtonCaption;

    Dialog.LoadSchemaToTree(Template.FormSchema);
    Dialog.SchedulePreviewUpdate;

    Result := Dialog.ShowModal = mrOk;

    if Result then
    begin
      Template.Name        := Dialog.edtName.Text;
      Template.Description := Dialog.edtDescription.Text;
      Template.Category    := Dialog.edtCategory.Text;
      Template.IsActive    := Dialog.chkActive.Checked;

      if Dialog.FJsonMode then
        Json := Dialog.synEditor.Lines.Text
      else
        Json := Dialog.SaveTreeToJSON;

      Template.FormSchema  := Json;
      Template.ModifiedDate := UTCNow;

      Tags.EquipmentTypeIds := Dialog.FCurrentTypeIds;
      Tags.EquipmentIds := Dialog.FCurrentDeviceIds;
    end;
  finally
    var LSettings := TNotebookSettings.Create;
    try
      LSettings.SaveUIValue('dlgTemplateEditor', 'pnlTreeCol', Dialog.pnlTreeCol.Width);
      LSettings.SaveUIValue('dlgTemplateEditor', 'pnlPropsCol', Dialog.pnlPropsCol.Width);
    finally
      LSettings.Free;
    end;

    Dialog.FActiveCard := nil;

    if Assigned(Dialog.FHtmlViewer) and Assigned(Dialog.FSavedParent) then
    begin
      Dialog.FHtmlViewer.Frame.Parent := Dialog.FSavedParent;
      Dialog.FHtmlViewer.Frame.Align := alClient;
    end;
    Dialog.Free;
  end;
end;

procedure TdlgTemplateEditor.FormCreate(Sender: TObject);
var
  LSettings: TNotebookSettings;
begin
  FJsonMode := False;

  LSettings := TNotebookSettings.Create;
  try
    pnlTreeCol.Width := LSettings.LoadUIValue('dlgTemplateEditor', 'pnlTreeCol', pnlTreeCol.Width);
    pnlPropsCol.Width := LSettings.LoadUIValue('dlgTemplateEditor', 'pnlPropsCol', pnlPropsCol.Width);
  finally
    LSettings.Free;
  end;

  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Interval := 100;
  FPreviewTimer.Enabled := False;
  FPreviewTimer.OnTimer := PreviewTimerFire;

  FCards := TDictionary<string, ITemplateCard>.Create;
  CreateCards;
  ShowCardForNode(nil);
end;

procedure TdlgTemplateEditor.FormDestroy(Sender: TObject);
begin
  // Remove the exact instance method before any controls or cards are freed.
  TThread.RemoveQueuedEvents(nil, ApplyQueuedCardChange);
  FCardUpdateQueued := False;
  FActiveCard := nil;
  FreeAndNil(FCards);
end;


procedure TdlgTemplateEditor.CreateCards;
var
  S: TfrSectionCard;
  R: TfrRowCard;
  Cb: TfrCheckboxFieldCard;
  T: TfrTextFieldCard;
  N: TfrNumberFieldCard;
  D: TfrDateFieldCard;
  Ta: TfrTextareaFieldCard;
  Rt: TfrRichtextFieldCard;
  Sel: TfrSelectFieldCard;
  Cg: TfrCheckboxGroupFieldCard;
begin
  S := TfrSectionCard.Create(Self); S.Parent := pnlCardHost; S.Align := alClient; S.Visible := False;
  RegisterCard('section', S);

  R := TfrRowCard.Create(Self); R.Parent := pnlCardHost; R.Align := alClient; R.Visible := False;
  RegisterCard('row', R);

  Cb := TfrCheckboxFieldCard.Create(Self); Cb.Parent := pnlCardHost; Cb.Align := alClient; Cb.Visible := False;
  RegisterCard('field:checkbox', Cb);

  T := TfrTextFieldCard.Create(Self); T.Parent := pnlCardHost; T.Align := alClient; T.Visible := False;
  RegisterCard('field:text', T);

  N := TfrNumberFieldCard.Create(Self); N.Parent := pnlCardHost; N.Align := alClient; N.Visible := False;
  RegisterCard('field:number', N);

  D := TfrDateFieldCard.Create(Self); D.Parent := pnlCardHost; D.Align := alClient; D.Visible := False;
  RegisterCard('field:date', D);

  Ta := TfrTextareaFieldCard.Create(Self); Ta.Parent := pnlCardHost; Ta.Align := alClient; Ta.Visible := False;
  RegisterCard('field:textarea', Ta);

  Rt := TfrRichtextFieldCard.Create(Self); Rt.Parent := pnlCardHost; Rt.Align := alClient; Rt.Visible := False;
  RegisterCard('field:richtext', Rt);

  Sel := TfrSelectFieldCard.Create(Self); Sel.Parent := pnlCardHost; Sel.Align := alClient; Sel.Visible := False;
  RegisterCard('field:select', Sel);

  Cg := TfrCheckboxGroupFieldCard.Create(Self); Cg.Parent := pnlCardHost; Cg.Align := alClient; Cg.Visible := False;
  RegisterCard('field:checkbox-group', Cg);
end;

procedure TdlgTemplateEditor.RegisterCard(const Key: string; Card: ITemplateCard);
begin
  FCards.Add(Key, Card);
  Card.SetOnChanged(OnCardChanged);
  Card.SetOnFieldTypeChanged(OnCardFieldTypeChanged);
end;

function TdlgTemplateEditor.CardKeyForField(const AType: string): string;
begin
  Result := 'field:' + AType;
  if not FCards.ContainsKey(Result) then
    Result := 'field:text';
end;

function TdlgTemplateEditor.CardKeyForNode(SN: TSchemaNode): string;
begin
  case SN.Kind of
    snkSection: Result := 'section';
    snkRow:     Result := 'row';
    snkField:   Result := CardKeyForField(SN.FieldType);
  else
    Result := '';
  end;
end;

procedure TdlgTemplateEditor.HideActiveCard;
begin
  if FActiveCard <> nil then
  begin
    FActiveCard.AsControl.Visible := False;
    FActiveCard := nil;
  end;
end;

procedure TdlgTemplateEditor.ShowCardForNode(Node: TTreeNode);
var
  SN: TSchemaNode;
  Key: string;
  Card: ITemplateCard;
  RowCard: TfrRowCard;
begin
  FCurrentNode := Node;
  if (Node = nil) or (Node.Data = nil) then
  begin
    HideActiveCard;
    lblPropCaption.Caption := 'Properties:';
    Exit;
  end;

  SN := TSchemaNode(Node.Data);
  Key := CardKeyForNode(SN);
  if (Key = '') or not FCards.TryGetValue(Key, Card) then
  begin
    HideActiveCard;
    lblPropCaption.Caption := 'Properties:';
    Exit;
  end;

  case SN.Kind of
    snkSection: lblPropCaption.Caption := 'Section Properties:';
    snkRow:     lblPropCaption.Caption := 'Row Properties:';
    snkField:   lblPropCaption.Caption := 'Field Properties:';
  end;

  if Card = FActiveCard then
  begin
    Card.LoadFromNode(SN);
  end
  else
  begin
    if FActiveCard <> nil then
      FActiveCard.AsControl.Visible := False;
    Card.LoadFromNode(SN);
    Card.AsControl.Visible := True;
    FActiveCard := Card;
  end;

  if SN.Kind = snkRow then
  begin
    RowCard := Card.AsControl as TfrRowCard;
    RowCard.SetInfo(Format('Row with %d field(s)', [Node.Count]));
  end;
end;

procedure TdlgTemplateEditor.OnCardChanged(Sender: TObject);
var
  SN: TSchemaNode;
begin
  if (FActiveCard = nil) or (FCurrentNode = nil) or (FCurrentNode.Data = nil) then
    Exit;
  SN := TSchemaNode(FCurrentNode.Data);
  FActiveCard.SaveToNode(SN);
  FCurrentNode.Text := SN.DisplayText;
  SchedulePreviewUpdate;
end;

procedure TdlgTemplateEditor.OnCardFieldTypeChanged(Sender: TObject;
  const NewType: string);
begin
  // The event must finish before its card is replaced. An instance method
  // gives destruction an exact queue entry to cancel, without a dangling closure.
  if FCardUpdateQueued then Exit;
  FCardUpdateQueued := True;
  TThread.ForceQueue(nil, ApplyQueuedCardChange);
end;

procedure TdlgTemplateEditor.ApplyQueuedCardChange;
begin
  FCardUpdateQueued := False;
  if FCurrentNode <> nil then
    ShowCardForNode(FCurrentNode);
end;


procedure TdlgTemplateEditor.LoadSchemaToTree(const SchemaJson: string);
var
  JsonVal: TJSONValue;
  Root: TJSONObject;
  Sections, Rows, Fields, Opts: TJSONArray;
  SectionObj, RowObj, FieldObj, OptObj: TJSONObject;
  I, J, K, L: Integer;
  SN: TSchemaNode;
  SecNode, RowNode: TTreeNode;
  Opt: TFieldOption;
  FlexVal: TJSONValue;
  RowsVal: TJSONValue;
begin
  tvSchema.Items.BeginUpdate;
  try
    tvSchema.Items.Clear;
    FSchemaTitle := '';
    FSchemaAccentColor := '#1a5276';

    if Trim(SchemaJson) = '' then
      Exit;

    JsonVal := TJSONObject.ParseJSONValue(SchemaJson);
    if not Assigned(JsonVal) then
      Exit;

    try
      if not (JsonVal is TJSONObject) then
        Exit;

      Root := TJSONObject(JsonVal);

      if Root.GetValue('title') <> nil then
        FSchemaTitle := Root.GetValue('title').Value;
      if Root.GetValue('accentColor') <> nil then
        FSchemaAccentColor := Root.GetValue('accentColor').Value;

      if (Root.GetValue('sections') = nil) or
         not (Root.GetValue('sections') is TJSONArray) then
        Exit;

      Sections := TJSONArray(Root.GetValue('sections'));
      for I := 0 to Sections.Count - 1 do
      begin
        if not (Sections.Items[I] is TJSONObject) then
          Continue;
        SectionObj := TJSONObject(Sections.Items[I]);

        SN := TSchemaNode.Create(snkSection);
        if SectionObj.GetValue('title') <> nil then
          SN.SectionTitle := SectionObj.GetValue('title').Value
        else
          SN.SectionTitle := 'Section ' + IntToStr(I + 1);
        SecNode := tvSchema.Items.AddObject(nil, SN.DisplayText, SN);

        if (SectionObj.GetValue('rows') <> nil) and
           (SectionObj.GetValue('rows') is TJSONArray) then
        begin
          Rows := TJSONArray(SectionObj.GetValue('rows'));
          for J := 0 to Rows.Count - 1 do
          begin
            if not (Rows.Items[J] is TJSONObject) then
              Continue;
            RowObj := TJSONObject(Rows.Items[J]);

            SN := TSchemaNode.Create(snkRow);
            RowNode := tvSchema.Items.AddChildObject(SecNode,
              'Row ' + IntToStr(J + 1), SN);

            if (RowObj.GetValue('fields') <> nil) and
               (RowObj.GetValue('fields') is TJSONArray) then
            begin
              Fields := TJSONArray(RowObj.GetValue('fields'));
              for K := 0 to Fields.Count - 1 do
              begin
                if not (Fields.Items[K] is TJSONObject) then
                  Continue;
                FieldObj := TJSONObject(Fields.Items[K]);

                SN := TSchemaNode.Create(snkField);

                if FieldObj.GetValue('name') <> nil then
                  SN.FieldName := FieldObj.GetValue('name').Value;
                if FieldObj.GetValue('label') <> nil then
                  SN.FieldLabel := FieldObj.GetValue('label').Value;
                if FieldObj.GetValue('type') <> nil then
                  SN.FieldType := FieldObj.GetValue('type').Value;
                if FieldObj.GetValue('placeholder') <> nil then
                  SN.Placeholder := FieldObj.GetValue('placeholder').Value;
                if FieldObj.GetValue('autoFill') <> nil then
                  SN.AutoFill := FieldObj.GetValue('autoFill').Value;

                FlexVal := FieldObj.GetValue('flex');
                if (FlexVal <> nil) and (FlexVal is TJSONNumber) then
                  SN.Flex := TJSONNumber(FlexVal).AsInt
                else
                  SN.Flex := 1;

                RowsVal := FieldObj.GetValue('rows');
                if (RowsVal <> nil) and (RowsVal is TJSONNumber) then
                  SN.RowCount := TJSONNumber(RowsVal).AsInt
                else
                  SN.RowCount := 3;

                if (FieldObj.GetValue('options') <> nil) and
                   (FieldObj.GetValue('options') is TJSONArray) then
                begin
                  Opts := TJSONArray(FieldObj.GetValue('options'));
                  for L := 0 to Opts.Count - 1 do
                  begin
                    if Opts.Items[L] is TJSONObject then
                    begin
                      OptObj := TJSONObject(Opts.Items[L]);
                      Opt.Label_ := '';
                      Opt.Value := '';

                      if SN.FieldType = 'checkbox-group' then
                      begin
                        if OptObj.GetValue('name') <> nil then
                          Opt.Value := OptObj.GetValue('name').Value;
                      end
                      else
                      begin
                        if OptObj.GetValue('value') <> nil then
                          Opt.Value := OptObj.GetValue('value').Value;
                      end;

                      if OptObj.GetValue('label') <> nil then
                        Opt.Label_ := OptObj.GetValue('label').Value;

                      SN.Options.Add(Opt);
                    end;
                  end;
                end;

                tvSchema.Items.AddChildObject(RowNode,
                  SN.DisplayText, SN);
              end;
            end;
          end;
        end;
      end;
    finally
      JsonVal.Free;
    end;
  finally
    tvSchema.Items.EndUpdate;
    tvSchema.FullExpand;
  end;
end;


function TdlgTemplateEditor.SaveTreeToJSON: string;
var
  Root, SectionObj, RowObj, FieldObj, OptObj: TJSONObject;
  SectionsArr, RowsArr, FieldsArr, OptsArr: TJSONArray;
  SecNode, RowNode, FldNode: TTreeNode;
  SN: TSchemaNode;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));

    if FSchemaTitle <> '' then
      Root.AddPair('title', FSchemaTitle)
    else if Trim(edtName.Text) <> '' then
      Root.AddPair('title', Trim(edtName.Text));

    if edtCategory.Text <> '' then
      Root.AddPair('category', edtCategory.Text);

    if FSchemaAccentColor <> '' then
      Root.AddPair('accentColor', FSchemaAccentColor)
    else
      Root.AddPair('accentColor', '#1a5276');

    SectionsArr := TJSONArray.Create;

    SecNode := tvSchema.Items.GetFirstNode;
    while SecNode <> nil do
    begin
      SN := TSchemaNode(SecNode.Data);
      if (SN <> nil) and (SN.Kind = snkSection) then
      begin
        SectionObj := TJSONObject.Create;
        SectionObj.AddPair('title', SN.SectionTitle);

        RowsArr := TJSONArray.Create;

        RowNode := SecNode.getFirstChild;
        while RowNode <> nil do
        begin
          SN := TSchemaNode(RowNode.Data);
          if (SN <> nil) and (SN.Kind = snkRow) then
          begin
            RowObj := TJSONObject.Create;
            FieldsArr := TJSONArray.Create;

            FldNode := RowNode.getFirstChild;
            while FldNode <> nil do
            begin
              SN := TSchemaNode(FldNode.Data);
              if (SN <> nil) and (SN.Kind = snkField) then
              begin
                FieldObj := TJSONObject.Create;
                FieldObj.AddPair('name', SN.FieldName);
                FieldObj.AddPair('type', SN.FieldType);

                if SN.FieldLabel <> '' then
                  FieldObj.AddPair('label', SN.FieldLabel);
                if SN.Placeholder <> '' then
                  FieldObj.AddPair('placeholder', SN.Placeholder);
                if SN.AutoFill <> '' then
                  FieldObj.AddPair('autoFill', SN.AutoFill);
                if SN.Flex > 1 then
                  FieldObj.AddPair('flex', TJSONNumber.Create(SN.Flex));
                if (SN.FieldType = 'textarea') or (SN.FieldType = 'richtext') then
                begin
                  if SN.RowCount <> 3 then
                    FieldObj.AddPair('rows', TJSONNumber.Create(SN.RowCount));
                end;

                if ((SN.FieldType = 'select') or (SN.FieldType = 'checkbox-group'))
                   and (SN.Options.Count > 0) then
                begin
                  OptsArr := TJSONArray.Create;
                  for I := 0 to SN.Options.Count - 1 do
                  begin
                    OptObj := TJSONObject.Create;
                    if SN.FieldType = 'checkbox-group' then
                      OptObj.AddPair('name', SN.Options[I].Value)
                    else
                      OptObj.AddPair('value', SN.Options[I].Value);
                    OptObj.AddPair('label', SN.Options[I].Label_);
                    OptsArr.AddElement(OptObj);
                  end;
                  FieldObj.AddPair('options', OptsArr);
                end;

                FieldsArr.AddElement(FieldObj);
              end;
              FldNode := FldNode.getNextSibling;
            end;

            RowObj.AddPair('fields', FieldsArr);
            RowsArr.AddElement(RowObj);
          end;
          RowNode := RowNode.getNextSibling;
        end;

        SectionObj.AddPair('rows', RowsArr);
        SectionsArr.AddElement(SectionObj);
      end;
      SecNode := SecNode.getNextSibling;
    end;

    Root.AddPair('sections', SectionsArr);
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;


procedure TdlgTemplateEditor.tvSchemaChange(Sender: TObject; Node: TTreeNode);
begin
  SyncNodeToProps;
end;

procedure TdlgTemplateEditor.tvSchemaDeletion(Sender: TObject; Node: TTreeNode);
var
  SN: TSchemaNode;
begin
  if Node.Data <> nil then
  begin
    SN := TSchemaNode(Node.Data);
    Node.Data := nil;
    SN.Free;
  end;
end;

procedure TdlgTemplateEditor.SyncNodeToProps;
begin
  ShowCardForNode(tvSchema.Selected);
end;


procedure TdlgTemplateEditor.btnAddSectionClick(Sender: TObject);
var
  SN: TSchemaNode;
  Node: TTreeNode;
begin
  SN := TSchemaNode.Create(snkSection);
  SN.SectionTitle := 'New Section';
  Node := tvSchema.Items.AddObject(nil, SN.DisplayText, SN);
  tvSchema.Selected := Node;
  SchedulePreviewUpdate;
end;

procedure TdlgTemplateEditor.btnAddRowClick(Sender: TObject);
var
  SN: TSchemaNode;
  ParentNode, Node: TTreeNode;
begin
  ParentNode := FindParentOfKind(tvSchema.Selected, snkSection);
  if ParentNode = nil then
  begin
    MessageDlg('Select a section first.', mtInformation, [mbOK], 0);
    Exit;
  end;

  SN := TSchemaNode.Create(snkRow);
  Node := tvSchema.Items.AddChildObject(ParentNode, 'Row', SN);
  RenumberRows(ParentNode);
  ParentNode.Expand(False);
  tvSchema.Selected := Node;
  SchedulePreviewUpdate;
end;

procedure TdlgTemplateEditor.btnAddFieldClick(Sender: TObject);
var
  SN: TSchemaNode;
  ParentNode, Node: TTreeNode;
begin
  ParentNode := FindParentOfKind(tvSchema.Selected, snkRow);
  if ParentNode = nil then
  begin
    MessageDlg('Select a row first.', mtInformation, [mbOK], 0);
    Exit;
  end;

  SN := TSchemaNode.Create(snkField);
  SN.FieldName := 'newField';
  SN.FieldLabel := 'New Field';
  SN.FieldType := 'text';
  Node := tvSchema.Items.AddChildObject(ParentNode, SN.DisplayText, SN);
  ParentNode.Expand(False);
  tvSchema.Selected := Node;
  SchedulePreviewUpdate;
end;

procedure TdlgTemplateEditor.btnDeleteSchemaClick(Sender: TObject);
var
  Node, ParentNode: TTreeNode;
  SN: TSchemaNode;
begin
  Node := tvSchema.Selected;
  if Node = nil then Exit;

  SN := TSchemaNode(Node.Data);
  if SN = nil then Exit;

  if (SN.Kind = snkSection) and (Node.Count > 0) then
  begin
    if MessageDlg('Delete this section and all its contents?',
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  ParentNode := Node.Parent;
  tvSchema.Items.Delete(Node);

  if (ParentNode <> nil) and (ParentNode.Data <> nil) and
     (TSchemaNode(ParentNode.Data).Kind = snkSection) then
    RenumberRows(ParentNode);

  SchedulePreviewUpdate;
end;

procedure TdlgTemplateEditor.btnSchemaUpClick(Sender: TObject);
var
  Node, Prev: TTreeNode;
begin
  Node := tvSchema.Selected;
  if Node = nil then Exit;

  Prev := Node.getPrevSibling;
  if Prev = nil then Exit;

  Node.MoveTo(Prev, naInsert);
  tvSchema.Selected := Node;

  if (Node.Parent <> nil) and (Node.Data <> nil) and
     (TSchemaNode(Node.Data).Kind = snkRow) then
    RenumberRows(Node.Parent);

  SchedulePreviewUpdate;
end;

procedure TdlgTemplateEditor.btnSchemaDownClick(Sender: TObject);
var
  Node, Next: TTreeNode;
begin
  Node := tvSchema.Selected;
  if Node = nil then Exit;

  Next := Node.getNextSibling;
  if Next = nil then Exit;

  Next.MoveTo(Node, naInsert);
  tvSchema.Selected := Node;

  if (Node.Parent <> nil) and (Node.Data <> nil) and
     (TSchemaNode(Node.Data).Kind = snkRow) then
    RenumberRows(Node.Parent);

  SchedulePreviewUpdate;
end;


procedure TdlgTemplateEditor.btnJsonToggleClick(Sender: TObject);
var
  Json, Err: string;
begin
  if not FJsonMode then
  begin
    Json := SaveTreeToJSON;
    synEditor.Lines.Text := Json;
    tvSchema.Visible := False;
    synEditor.Visible := True;
    pnlPropsCol.Visible := False;
    spltTree.Visible := False;
    btnJsonToggle.Caption := 'Visual';
    FJsonMode := True;

    lblSchemaError.Visible := True;
    Err := TTemplateHtmlGenerator.ValidateSchema(Json);
    if Err = '' then
    begin
      lblSchemaError.Caption := 'Schema OK';
      lblSchemaError.Font.Color := clGreen;
    end
    else
    begin
      lblSchemaError.Caption := Err;
      lblSchemaError.Font.Color := clRed;
    end;
  end
  else
  begin
    Json := synEditor.Lines.Text;
    Err := TTemplateHtmlGenerator.ValidateSchema(Json);
    if Err <> '' then
    begin
      MessageDlg('Cannot switch to visual mode: ' + Err + #13#10 +
        'Fix the JSON first.', mtError, [mbOK], 0);
      Exit;
    end;

    LoadSchemaToTree(Json);
    synEditor.Visible := False;
    tvSchema.Visible := True;
    spltTree.Visible := True;
    pnlPropsCol.Visible := True;
    btnJsonToggle.Caption := 'JSON';
    FJsonMode := False;
    lblSchemaError.Visible := False;
  end;

  SchedulePreviewUpdate;
end;


procedure TdlgTemplateEditor.SchedulePreviewUpdate;
begin
  FPreviewTimer.Enabled := False;
  FPreviewTimer.Enabled := True;
end;

procedure TdlgTemplateEditor.PreviewTimerFire(Sender: TObject);
var
  Json: string;
begin
  FPreviewTimer.Enabled := False;

  if FJsonMode then
  begin
    Json := synEditor.Lines.Text;
    var Err := TTemplateHtmlGenerator.ValidateSchema(Json);
    if Err = '' then
    begin
      lblSchemaError.Caption := 'Schema OK';
      lblSchemaError.Font.Color := clGreen;
    end
    else
    begin
      lblSchemaError.Caption := Err;
      lblSchemaError.Font.Color := clRed;
    end;
  end
  else
    Json := SaveTreeToJSON;

  PreviewSchema(Json);
end;

procedure TdlgTemplateEditor.PreviewSchema(const SchemaJson: string);
var
  Html: string;
begin
  if Assigned(FHtmlViewer) then
  begin
    Html := TTemplateHtmlGenerator.GenerateHtml(SchemaJson);
    if Html <> '' then
      FHtmlViewer.DisplayText('Preview', Html)
    else
      FHtmlViewer.DisplayText('Preview',
        '<html><body><p style="color:#999">Invalid schema - cannot preview</p></body></html>');
  end;
end;

procedure TdlgTemplateEditor.btnPreviewClick(Sender: TObject);
var
  Json: string;
begin
  if FJsonMode then
    Json := synEditor.Lines.Text
  else
    Json := SaveTreeToJSON;
  PreviewSchema(Json);
end;

procedure TdlgTemplateEditor.btnLoadExampleClick(Sender: TObject);
var
  FileName, TemplatesDir: string;
  LSettings: TNotebookSettings;
begin
  LSettings := TNotebookSettings.Create;
  try
    TemplatesDir := LSettings.TemplatesDir;
  finally
    LSettings.Free;
  end;
  if TemplatesDir = '' then
    TemplatesDir := ExtractFilePath(Application.ExeName) + 'ProtocolTemplates';
  if TDirectory.Exists(TemplatesDir) then
    dlgOpenSchema.InitialDir := TemplatesDir;

  if dlgOpenSchema.Execute then
  begin
    FileName := dlgOpenSchema.FileName;
    if Trim(edtName.Text) = '' then
      edtName.Text := ChangeFileExt(ExtractFileName(FileName), '');

    if FJsonMode then
    begin
      synEditor.Lines.Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    end
    else
    begin
      LoadSchemaToTree(TFile.ReadAllText(FileName, TEncoding.UTF8));
    end;

    SchedulePreviewUpdate;
  end;
end;

procedure TdlgTemplateEditor.btnOKClick(Sender: TObject);
begin
  if Validate then
    ModalResult := mrOk;
end;

function TdlgTemplateEditor.Validate: Boolean;
var
  Err, Json: string;
begin
  Result := False;

  if Trim(edtName.Text) = '' then
  begin
    MessageDlg('Template name cannot be empty.', mtError, [mbOK], 0);
    edtName.SetFocus;
    Exit;
  end;

  if FJsonMode then
    Json := synEditor.Lines.Text
  else
    Json := SaveTreeToJSON;

  Err := TTemplateHtmlGenerator.ValidateSchema(Json);
  if Err <> '' then
  begin
    MessageDlg('Invalid schema: ' + Err, mtError, [mbOK], 0);
    Exit;
  end;

  Result := True;
end;


function TdlgTemplateEditor.FindParentOfKind(Node: TTreeNode;
  Kind: TSchemaNodeKind): TTreeNode;
var
  Current: TTreeNode;
begin
  Result := nil;
  Current := Node;
  while Current <> nil do
  begin
    if (Current.Data <> nil) and (TSchemaNode(Current.Data).Kind = Kind) then
    begin
      Result := Current;
      Exit;
    end;
    Current := Current.Parent;
  end;
end;

procedure TdlgTemplateEditor.RenumberRows(SectionNode: TTreeNode);
var
  Child: TTreeNode;
  Idx: Integer;
begin
  if SectionNode = nil then Exit;
  Idx := 1;
  Child := SectionNode.getFirstChild;
  while Child <> nil do
  begin
    if (Child.Data <> nil) and (TSchemaNode(Child.Data).Kind = snkRow) then
    begin
      Child.Text := 'Row ' + IntToStr(Idx);
      Inc(Idx);
    end;
    Child := Child.getNextSibling;
  end;
end;


procedure TdlgTemplateEditor.RefreshTagsButtonCaption;
begin
  if (Length(FCurrentTypeIds) = 0) and (Length(FCurrentDeviceIds) = 0) then
    btnTags.Caption := 'Tags... (none)'
  else
    btnTags.Caption := Format('Tags... (%d types, %d devices)',
      [Length(FCurrentTypeIds), Length(FCurrentDeviceIds)]);
end;

procedure TdlgTemplateEditor.btnTagsClick(Sender: TObject);
var
  Dialog: TdlgTemplateEquipmentTags;
  AllTypes: TList<TEquipmentType>;
  AllDevices: TList<TEquipment>;
begin
  AllTypes := Model.Manager.Find<TEquipmentType>.List;
  try
    AllDevices := Model.Manager.Find<TEquipment>.List;
    try
      Dialog := TdlgTemplateEquipmentTags.Create(Self);
      try
        Dialog.Setup(AllTypes, AllDevices, FCurrentTypeIds, FCurrentDeviceIds);
        if Dialog.ShowModal = mrOk then
        begin
          FCurrentTypeIds := Dialog.ResultTypeIds;
          FCurrentDeviceIds := Dialog.ResultDeviceIds;
          RefreshTagsButtonCaption;
        end;
      finally
        Dialog.Free;
      end;
    finally
      AllDevices.Free;
    end;
  finally
    AllTypes.Free;
  end;
end;

end.
