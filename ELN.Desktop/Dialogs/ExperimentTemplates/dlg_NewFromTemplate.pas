unit dlg_NewFromTemplate;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.TypInfo, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  Vcl.Graphics,
  VirtualTrees, VirtualTrees.Types, VirtualTrees.BaseTree,
  RzCommon, RzPanel, RzButton, RzLabel, RzEdit,
  unit_Item, unit_ItemTypes, VirtualTrees.BaseAncestorVCL,
  VirtualTrees.AncestorVCL, Vcl.Mask;

type
  PPreviewNodeData = ^TPreviewNodeData;
  TPreviewNodeData = record
    Title: string;
    Level: TItemLevel;
    ItemType: TItemType;
    IsFolder: Boolean;
    ActionTypeName: string;
    EquipmentName: string;
  end;

  TdlgNewFromTemplate = class(TForm)
    pnlBottom: TRzPanel;
    btnCancel: TRzButton;
    btnCreate: TRzButton;
    pnlLeft: TRzPanel;
    scrTemplates: TScrollBox;
    spltMain: TSplitter;
    pnlRight: TRzPanel;
    pnlTitleBar: TRzPanel;
    lblTitle: TRzLabel;
    edtTitle: TRzEdit;
    vstPreview: TVirtualStringTree;
    procedure btnCreateClick(Sender: TObject);
    procedure vstPreviewGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure vstPreviewGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure vstPreviewFreeNode(Sender: TBaseVirtualTree;
      Node: PVirtualNode);
  private
    FSelectedTemplateId: Integer;
    FSelectedPanel: TRzPanel;
    procedure LoadTemplates;
    procedure LoadPreview(TemplateId: Integer);
    procedure LoadPreviewNode(ParentNode: PVirtualNode; JsonArr: TJSONArray);
    procedure ResolveActionTypeInfo(ActionTypeId: Integer;
      out ATName, EquipName: string);
    procedure TemplatePanelClick(Sender: TObject);
    procedure TemplatePanelDblClick(Sender: TObject);
  public
    class function Execute(ProjectId, FolderId, UserId: Integer;
      out NewItem: TItem; out TemplateName: string): Boolean;
  end;

implementation

uses
  unit_ExperimentTemplate,
  unit_ActionType,
  unit_Equipment,
  unit_DataModel;

{$R *.dfm}

{ TdlgNewFromTemplate }

procedure TdlgNewFromTemplate.LoadTemplates;
var
  Templates: TExperimentTemplates;
  Template: TExperimentTemplate;
  Groups: TDictionary<string, TGroupBox>;
  GroupBox: TGroupBox;
  Panel: TRzPanel;
  lblName, lblDesc: TLabel;
  Category: string;
  SortedKeys: TList<string>;
  Key: string;
  PPI: Integer;

  function Scale(Value: Integer): Integer;
  begin
    Result := MulDiv(Value, PPI, 96);
  end;

begin
  PPI := Self.CurrentPPI;
  Templates := Model.ExperimentTemplates.GetAllTemplates;
  Groups := TDictionary<string, TGroupBox>.Create;
  try
    // First pass: create group boxes
    for Template in Templates do
    begin
      Category := Trim(Template.Category);
      if Category = '' then
        Category := '(Uncategorized)';
      if not Groups.ContainsKey(Category) then
      begin
        GroupBox := TGroupBox.Create(scrTemplates);
        GroupBox.Parent := scrTemplates;
        GroupBox.Align := alTop;
        GroupBox.Caption := ' ' + Category + ' ';
        GroupBox.Height := Scale(24);
        GroupBox.ParentFont := True;
        GroupBox.AlignWithMargins := True;
        Groups.Add(Category, GroupBox);
      end;
    end;

    // Sort categories, put (Uncategorized) last
    SortedKeys := TList<string>.Create;
    try
      for Key in Groups.Keys do
        if Key <> '(Uncategorized)' then
          SortedKeys.Add(Key);
      SortedKeys.Sort;
      if Groups.ContainsKey('(Uncategorized)') then
        SortedKeys.Add('(Uncategorized)');

      // Set Top order by reverse-inserting (alTop stacks from bottom)
      for var i := SortedKeys.Count - 1 downto 0 do
        Groups[SortedKeys[i]].Top := 0;
    finally
      SortedKeys.Free;
    end;

    // Second pass: add template panels to their groups
    for Template in Templates do
    begin
      Category := Trim(Template.Category);
      if Category = '' then
        Category := '(Uncategorized)';
      GroupBox := Groups[Category];

      Panel := TRzPanel.Create(GroupBox);
      Panel.Parent := GroupBox;
      Panel.Align := alTop;
      Panel.Height := Scale(44);
      Panel.BorderOuter := fsNone;
      Panel.Color := clWindow;
      Panel.Cursor := crHandPoint;
      Panel.Tag := Template.Id;
      Panel.OnClick := TemplatePanelClick;
      Panel.OnDblClick := TemplatePanelDblClick;
      Panel.Top := GroupBox.Height; // stack at bottom within group

      lblName := TLabel.Create(Panel);
      lblName.Parent := Panel;
      lblName.Left := Scale(8);
      lblName.Top := Scale(4);
      lblName.Caption := Template.Name;
      lblName.Font.Style := [fsBold];
      lblName.OnClick := TemplatePanelClick;
      lblName.OnDblClick := TemplatePanelDblClick;

      if Template.Description <> '' then
      begin
        lblDesc := TLabel.Create(Panel);
        lblDesc.Parent := Panel;
        lblDesc.Left := Scale(8);
        lblDesc.Top := Scale(22);
        lblDesc.Caption := Template.Description;
        lblDesc.Font.Color := clGray;
        lblDesc.OnClick := TemplatePanelClick;
        lblDesc.OnDblClick := TemplatePanelDblClick;
        Panel.Height := Scale(44);
      end
      else
        Panel.Height := Scale(28);

      GroupBox.Height := GroupBox.Height + Panel.Height;
    end;
  finally
    Groups.Free;
    Templates.Free;
  end;
end;

procedure TdlgNewFromTemplate.LoadPreview(TemplateId: Integer);
var
  Template: TExperimentTemplate;
  RootJSON, RootObj: TJSONObject;
  Node: PVirtualNode;
  Data: PPreviewNodeData;
  ActionTypeId: Integer;
  ATName, EquipName: string;
  ChildrenArr: TJSONArray;
  RootLevel: TItemLevel;
  IsFolder: Boolean;
begin
  vstPreview.Clear;
  Template := Model.ExperimentTemplates.GetTemplate(TemplateId);
  if not Assigned(Template) then Exit;

  RootJSON := TJSONObject.ParseJSONValue(Template.StructureJSON) as TJSONObject;
  if not Assigned(RootJSON) then Exit;
  try
    IsFolder := False;
    if RootJSON.TryGetValue<TJSONObject>('folder', RootObj) then
    begin
      IsFolder := True;
      RootLevel := TItemLevel.Item;  // placeholder; IsFolder drives display
    end
    else if RootJSON.TryGetValue<TJSONObject>('proc', RootObj) then
      RootLevel := TItemLevel.Proc
    else if RootJSON.TryGetValue<TJSONObject>('item', RootObj) then
      RootLevel := TItemLevel.Item
    else
      Exit;

    ActionTypeId := RootObj.GetValue<Integer>('actionTypeId', 0);
    ResolveActionTypeInfo(ActionTypeId, ATName, EquipName);

    vstPreview.BeginUpdate;
    try
      Node := vstPreview.AddChild(nil);
      Data := PPreviewNodeData(vstPreview.GetNodeData(Node));
      Data^.Title := RootObj.GetValue<string>('title', Template.Name);
      Data^.Level := RootLevel;
      Data^.ItemType := TItemType(RootObj.GetValue<Integer>('type', Ord(TItemType.Other)));
      Data^.IsFolder := IsFolder;
      Data^.ActionTypeName := ATName;
      Data^.EquipmentName := EquipName;

      if RootObj.TryGetValue<TJSONArray>('children', ChildrenArr) then
        LoadPreviewNode(Node, ChildrenArr);
    finally
      vstPreview.EndUpdate;
    end;

    vstPreview.FullExpand;
  finally
    RootJSON.Free;
  end;
end;

procedure TdlgNewFromTemplate.LoadPreviewNode(ParentNode: PVirtualNode;
  JsonArr: TJSONArray);
var
  i: Integer;
  ChildObj, Inner: TJSONObject;

  procedure AddItemNode(Obj: TJSONObject; DefaultLevel: TItemLevel);
  var
    Node: PVirtualNode;
    Data: PPreviewNodeData;
    ActionTypeId: Integer;
    ATName, EquipName: string;
    SubChildren: TJSONArray;
  begin
    ActionTypeId := Obj.GetValue<Integer>('actionTypeId', 0);
    ResolveActionTypeInfo(ActionTypeId, ATName, EquipName);
    Node := vstPreview.AddChild(ParentNode);
    Data := PPreviewNodeData(vstPreview.GetNodeData(Node));
    Data^.Title := Obj.GetValue<string>('title', 'Untitled');
    Data^.Level := TItemLevel(Obj.GetValue<Integer>('level', Ord(DefaultLevel)));
    Data^.ItemType := TItemType(Obj.GetValue<Integer>('type', Ord(TItemType.Other)));
    Data^.IsFolder := False;
    Data^.ActionTypeName := ATName;
    Data^.EquipmentName := EquipName;
    if Obj.TryGetValue<TJSONArray>('children', SubChildren) then
      LoadPreviewNode(Node, SubChildren);
  end;

  procedure AddFolderNode(Obj: TJSONObject);
  var
    Node: PVirtualNode;
    Data: PPreviewNodeData;
    SubChildren: TJSONArray;
  begin
    Node := vstPreview.AddChild(ParentNode);
    Data := PPreviewNodeData(vstPreview.GetNodeData(Node));
    Data^.Title := Obj.GetValue<string>('title', 'Folder');
    Data^.Level := TItemLevel.Item;  // placeholder; display uses IsFolder
    Data^.ItemType := TItemType.Other;
    Data^.IsFolder := True;
    Data^.ActionTypeName := '';
    Data^.EquipmentName := '';
    if Obj.TryGetValue<TJSONArray>('children', SubChildren) then
      LoadPreviewNode(Node, SubChildren);
  end;

begin
  for i := 0 to JsonArr.Count - 1 do
  begin
    ChildObj := JsonArr.Items[i] as TJSONObject;
    if ChildObj.TryGetValue<TJSONObject>('folder', Inner) then
      AddFolderNode(Inner)
    else if ChildObj.TryGetValue<TJSONObject>('item', Inner) then
      AddItemNode(Inner, TItemLevel.Item)
    else if ChildObj.TryGetValue<TJSONObject>('proc', Inner) then
      AddItemNode(Inner, TItemLevel.Proc)
    else
      AddItemNode(ChildObj, TItemLevel.Item);  // v1 back-compat
  end;
end;

procedure TdlgNewFromTemplate.ResolveActionTypeInfo(ActionTypeId: Integer;
  out ATName, EquipName: string);
var
  AT: TActionType;
  Equip: TEquipment;
begin
  ATName := '';
  EquipName := '';
  if ActionTypeId <= 0 then Exit;
  AT := Model.ActionTypes.GetType(ActionTypeId);
  if not Assigned(AT) then Exit;
  ATName := AT.Title;
  Equip := AT.Equipment;
  if Assigned(Equip) then
  begin
    EquipName := Equip.Model;
    if Equip.Manufacturer <> '' then
      EquipName := EquipName + ' (' + Equip.Manufacturer + ')';
  end;
end;

procedure TdlgNewFromTemplate.TemplatePanelClick(Sender: TObject);
var
  Panel: TRzPanel;
begin
  // Resolve to parent panel if sender is a child label
  if Sender is TRzPanel then
    Panel := TRzPanel(Sender)
  else if (Sender is TControl) and (TControl(Sender).Parent is TRzPanel) then
    Panel := TRzPanel(TControl(Sender).Parent)
  else
    Exit;

  // Deselect previous
  if Assigned(FSelectedPanel) then
    FSelectedPanel.Color := clWindow;

  // Select new
  FSelectedPanel := Panel;
  FSelectedPanel.Color := $00FFE0C0; // light highlight
  FSelectedTemplateId := Panel.Tag;
  LoadPreview(FSelectedTemplateId);

  // Set default title from template's root proc title
  if vstPreview.RootNodeCount > 0 then
  begin
    var Data := PPreviewNodeData(vstPreview.GetNodeData(vstPreview.GetFirst));
    edtTitle.Text := Data^.Title;
  end;
end;

procedure TdlgNewFromTemplate.TemplatePanelDblClick(Sender: TObject);
begin
  TemplatePanelClick(Sender);
  if FSelectedTemplateId > 0 then
    btnCreateClick(Sender);
end;

procedure TdlgNewFromTemplate.vstPreviewGetNodeDataSize(
  Sender: TBaseVirtualTree; var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TPreviewNodeData);
end;

procedure TdlgNewFromTemplate.vstPreviewGetCellText(
  Sender: TCustomVirtualStringTree; var E: TVSTGetCellTextEventArgs);
var
  Data: PPreviewNodeData;
  LevelStr: string;
begin
  Data := PPreviewNodeData(Sender.GetNodeData(E.Node));
  if not Assigned(Data) then Exit;

  if Data^.IsFolder then
  begin
    E.CellText := 'Folder: ' + Data^.Title;
    Exit;
  end;

  LevelStr := GetEnumName(TypeInfo(TItemLevel), Ord(Data^.Level));

  if Data^.EquipmentName <> '' then
    E.CellText := LevelStr + ': ' + Data^.Title + ' (' + Data^.EquipmentName + ')'
  else if Data^.ActionTypeName <> '' then
    E.CellText := LevelStr + ': ' + Data^.Title + ' [' + Data^.ActionTypeName + ']'
  else
    E.CellText := LevelStr + ': ' + Data^.Title;
end;

procedure TdlgNewFromTemplate.vstPreviewFreeNode(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
var
  Data: PPreviewNodeData;
begin
  Data := PPreviewNodeData(Sender.GetNodeData(Node));
  if Assigned(Data) then
    Finalize(Data^);
end;

procedure TdlgNewFromTemplate.btnCreateClick(Sender: TObject);
begin
  if FSelectedTemplateId <= 0 then
  begin
    MessageDlg('Please select a template first.', mtWarning, [mbOK], 0);
    ModalResult := mrNone;
    Exit;
  end;
  if Trim(edtTitle.Text) = '' then
  begin
    MessageDlg('Please enter an experiment title.', mtWarning, [mbOK], 0);
    ModalResult := mrNone;
    Exit;
  end;
  ModalResult := mrOk;
end;

class function TdlgNewFromTemplate.Execute(ProjectId, FolderId, UserId: Integer;
  out NewItem: TItem; out TemplateName: string): Boolean;
var
  Dlg: TdlgNewFromTemplate;
  Template: TExperimentTemplate;
begin
  Result := False;
  NewItem := nil;
  TemplateName := '';
  Dlg := TdlgNewFromTemplate.Create(Application);
  try
    Dlg.LoadTemplates;
    if Dlg.ShowModal = mrOk then
    begin
      Template := Model.ExperimentTemplates.GetTemplate(Dlg.FSelectedTemplateId);
      if Assigned(Template) then
        TemplateName := Template.Name;
      NewItem := Model.ExperimentTemplates.ApplyTemplate(
        Dlg.FSelectedTemplateId, ProjectId, FolderId, UserId,
        Trim(Dlg.edtTitle.Text));
      Result := Assigned(NewItem);
    end;
  finally
    Dlg.Free;
  end;
end;

end.
