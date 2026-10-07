unit dlg_ExperimentTemplate;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.TypInfo, System.UITypes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  Vcl.Graphics,
  VirtualTrees.BaseAncestorVCL, VirtualTrees.BaseTree, VirtualTrees.AncestorVCL,
  VirtualTrees, VirtualTrees.Types,
  RzPanel, RzLabel, RzButton, RzEdit,
  unit_ExperimentTemplate, unit_ItemTypes, unit_ActionType, Vcl.Mask;

type
  TTemplateMode = (tmManager, tmSelector);

  { Structure tree node data.
    NOTE: Folder nodes (IsFolder=True) are read-only in v1. The editing paths
    (btnAddChildClick, btnDeleteNodeClick, SyncNodeToProps, SyncPropsToNode,
    SaveStructureToJSON, SaveStructureNode) do not handle folder nodes.
    Opening a folder-root template for viewing works, but editing it is
    undefined behavior. }
  PTemplateNodeData = ^TTemplateNodeData;
  TTemplateNodeData = record
    Title: string;
    Level: TItemLevel;
    ItemType: TItemType;
    ActionTypeId: Integer;
    ActionTypeName: string;
    IsFolder: Boolean;
  end;

  { Template list node data }
  TTemplateListNodeKind = (tnkCategory, tnkTemplate);

  PTemplateListNodeData = ^TTemplateListNodeData;
  TTemplateListNodeData = record
    Kind: TTemplateListNodeKind;
    TemplateId: Integer;
    Name: string;
    Category: string;
    Description: string;
  end;

  TdlgExperimentTemplate = class(TForm)
    { Bottom panel }
    pnlBottom: TRzPanel;
    btnCreate: TRzButton;
    btnClose: TRzButton;
    { Left panel -- template list }
    pnlLeft: TRzPanel;
    lblTemplateList: TRzLabel;
    pnlListButtons: TRzPanel;
    btnAdd: TRzButton;
    btnDelete: TRzButton;
    btnDuplicate: TRzButton;
    btnExport: TRzButton;
    btnImport: TRzButton;
    btnBulkImport: TRzButton;
    vstTemplateList: TVirtualStringTree;
    { Splitters }
    spltMain: TSplitter;
    spltRight: TSplitter;
    { Right panel -- properties }
    pnlRight: TRzPanel;
    pnlDetails: TRzPanel;
    lblName: TRzLabel;
    edtName: TRzEdit;
    lblCategory: TRzLabel;
    cmbCategory: TComboBox;
    lblDescription: TRzLabel;
    memDescription: TMemo;
    pnlProps: TRzPanel;
    lblPropTitle: TRzLabel;
    edtNodeTitle: TRzEdit;
    lblPropLevel: TRzLabel;
    lstNodeLevel: TListBox;
    lblPropType: TRzLabel;
    lstNodeType: TListBox;
    lblPropActionType: TRzLabel;
    lstNodeActionType: TListBox;
    pnlSaveBar: TRzPanel;
    btnSave: TRzButton;
    { Center panel -- structure editor }
    pnlCenter: TRzPanel;
    pnlTreeButtons: TRzPanel;
    btnAddChild: TRzButton;
    btnAddSibling: TRzButton;
    btnMoveUp: TRzButton;
    btnMoveDown: TRzButton;
    btnLevelUp: TRzButton;
    btnDeleteNode: TRzButton;
    vstStructure: TVirtualStringTree;
    { Event handlers }
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    { Template list VST events }
    procedure vstTemplateListGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure vstTemplateListGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure vstTemplateListFocusChanged(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Column: TColumnIndex);
    procedure vstTemplateListFocusChanging(Sender: TBaseVirtualTree;
      OldNode, NewNode: PVirtualNode; OldColumn, NewColumn: TColumnIndex;
      var Allowed: Boolean);
    procedure vstTemplateListFreeNode(Sender: TBaseVirtualTree;
      Node: PVirtualNode);
    procedure vstTemplateListPaintText(Sender: TBaseVirtualTree;
      const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType);
    { Structure tree events }
    procedure vstStructureGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure vstStructureGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure vstStructureFocusChanged(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Column: TColumnIndex);
    procedure vstStructureFreeNode(Sender: TBaseVirtualTree;
      Node: PVirtualNode);
    procedure vstStructurePaintText(Sender: TBaseVirtualTree;
      const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType);
    { Template CRUD buttons }
    procedure btnAddClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnDuplicateClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure btnImportClick(Sender: TObject);
    procedure btnBulkImportClick(Sender: TObject);
    { Structure tree buttons }
    procedure btnAddChildClick(Sender: TObject);
    procedure btnAddSiblingClick(Sender: TObject);
    procedure btnDeleteNodeClick(Sender: TObject);
    procedure btnMoveUpClick(Sender: TObject);
    procedure btnMoveDownClick(Sender: TObject);
    procedure btnLevelUpClick(Sender: TObject);
    procedure btnCreateClick(Sender: TObject);
    { Node property changes }
    procedure edtNodeTitleChange(Sender: TObject);
    procedure lstNodeLevelClick(Sender: TObject);
    procedure lstNodeTypeClick(Sender: TObject);
    procedure lstNodeActionTypeClick(Sender: TObject);
    { Details panel changes }
    procedure edtNameChange(Sender: TObject);
    procedure cmbCategoryChange(Sender: TObject);
    procedure memDescriptionChange(Sender: TObject);
  private
    FMode: TTemplateMode;
    FSelectedTemplateId: Integer;
    FUpdatingProps: Boolean;
    FUpdatingDetails: Boolean;
    procedure LoadTemplates;
    procedure LoadStructure(TemplateId: Integer);
    procedure LoadStructureNode(ParentNode: PVirtualNode;
      JsonArr: TJSONArray);
    function SaveStructureToJSON: string;
    procedure SaveStructureNode(Node: PVirtualNode; Arr: TJSONArray);
    procedure SyncPropsToNode;
    procedure SyncNodeToProps;
    procedure SyncDetailsToTemplate;
    procedure SyncTemplateToDetails;
    procedure PopulateActionTypes;
    procedure PopulateCategories;
    procedure SetMode(AMode: TTemplateMode);
    function GetAllowedChildLevel(ParentNode: PVirtualNode): TItemLevel;
    procedure SaveCurrentTemplate;
    procedure AddNewTemplate;
    function GetSelectedTemplateNode: PVirtualNode;
  public
    class function SelectTemplate(out TemplateId: Integer): Boolean;
    class procedure ManageTemplates;
  end;

implementation

{$R *.dfm}

uses
  Vcl.FileCtrl,
  unit_DataModel,
  unit_NotebookSettings;

{ TdlgExperimentTemplate }

procedure TdlgExperimentTemplate.FormCreate(Sender: TObject);
var
  L: TItemLevel;
  T: TItemType;
  LSettings: TNotebookSettings;
begin
  FUpdatingProps := False;
  FUpdatingDetails := False;
  FSelectedTemplateId := 0;

  LSettings := TNotebookSettings.Create;
  try
    pnlLeft.Width := LSettings.LoadUIValue('dlgExperimentTemplate', 'pnlLeft', pnlLeft.Width);
  finally
    LSettings.Free;
  end;

  // Populate Level list -- skip Folder
  lstNodeLevel.Items.Clear;
  for L := Low(TItemLevel) to High(TItemLevel) do
  begin
    if L = TItemLevel.Folder then
      Continue;
    lstNodeLevel.Items.AddObject(
      GetEnumName(TypeInfo(TItemLevel), Ord(L)), TObject(Ord(L)));
  end;

  // Populate Type list -- all TItemType values
  lstNodeType.Items.Clear;
  for T := Low(TItemType) to High(TItemType) do
    lstNodeType.Items.AddObject(
      GetEnumName(TypeInfo(TItemType), Ord(T)), TObject(Ord(T)));

  // Populate Action Type list
  PopulateActionTypes;
end;

procedure TdlgExperimentTemplate.FormDestroy(Sender: TObject);
var
  LSettings: TNotebookSettings;
begin
  LSettings := TNotebookSettings.Create;
  try
    LSettings.SaveUIValue('dlgExperimentTemplate', 'pnlLeft', pnlLeft.Width);
  finally
    LSettings.Free;
  end;
end;

procedure TdlgExperimentTemplate.PopulateActionTypes;
var
  Types: TActionTypes;
  AT: TActionType;
  i: Integer;
begin
  lstNodeActionType.Items.Clear;
  lstNodeActionType.Items.AddObject('(none)', TObject(0));
  Types := Model.ActionTypes.GetTypes;
  try
    for i := 0 to Types.Count - 1 do
    begin
      AT := Types[i];
      lstNodeActionType.Items.AddObject(AT.Title, TObject(AT.Id));
    end;
  finally
    Types.Free;
  end;
end;

{ --- Template list (VirtualStringTree with category grouping) --- }

procedure TdlgExperimentTemplate.LoadTemplates;
var
  Templates: TExperimentTemplates;
  Template: TExperimentTemplate;
  Categories: TStringList;
  CatNode, TplNode: PVirtualNode;
  CatData, TplData: PTemplateListNodeData;
  Cat: string;
  i: Integer;
begin
  vstTemplateList.Clear;
  vstStructure.Clear;
  FSelectedTemplateId := 0;
  SyncNodeToProps;
  SyncTemplateToDetails;

  Templates := Model.ExperimentTemplates.GetAllTemplates;
  try
    // Collect unique categories, sorted
    Categories := TStringList.Create;
    try
      Categories.Sorted := True;
      Categories.Duplicates := dupIgnore;
      for Template in Templates do
      begin
        Cat := Trim(Template.Category);
        if Cat = '' then
          Cat := '(Uncategorized)';
        Categories.Add(Cat);
      end;

      vstTemplateList.BeginUpdate;
      try
        for i := 0 to Categories.Count - 1 do
        begin
          Cat := Categories[i];

          // Create category header node
          CatNode := vstTemplateList.AddChild(nil);
          CatData := vstTemplateList.GetNodeData(CatNode);
          CatData^.Kind := tnkCategory;
          CatData^.TemplateId := 0;
          CatData^.Name := Cat;
          CatData^.Category := Cat;
          CatData^.Description := '';

          // Add template nodes under this category
          for Template in Templates do
          begin
            if Trim(Template.Category) = '' then
            begin
              if Cat <> '(Uncategorized)' then
                Continue;
            end
            else if Trim(Template.Category) <> Cat then
              Continue;

            TplNode := vstTemplateList.AddChild(CatNode);
            TplData := vstTemplateList.GetNodeData(TplNode);
            TplData^.Kind := tnkTemplate;
            TplData^.TemplateId := Template.Id;
            TplData^.Name := Template.Name;
            TplData^.Category := Template.Category;
            TplData^.Description := Template.Description;
          end;
        end;
      finally
        vstTemplateList.EndUpdate;
      end;
    finally
      Categories.Free;
    end;
  finally
    Templates.Free;
  end;

  vstTemplateList.FullExpand;
  PopulateCategories;
end;

procedure TdlgExperimentTemplate.PopulateCategories;
var
  Node: PVirtualNode;
  Data: PTemplateListNodeData;
  CurrentText: string;
begin
  CurrentText := cmbCategory.Text;
  cmbCategory.Items.Clear;

  Node := vstTemplateList.GetFirst;
  while Assigned(Node) do
  begin
    Data := vstTemplateList.GetNodeData(Node);
    if (Data^.Kind = tnkCategory) and (Data^.Name <> '(Uncategorized)') then
      cmbCategory.Items.Add(Data^.Name);
    Node := vstTemplateList.GetNext(Node);
  end;

  cmbCategory.Text := CurrentText;
end;

function TdlgExperimentTemplate.GetSelectedTemplateNode: PVirtualNode;
var
  Node: PVirtualNode;
  Data: PTemplateListNodeData;
begin
  Result := nil;
  Node := vstTemplateList.FocusedNode;
  if not Assigned(Node) then Exit;

  Data := vstTemplateList.GetNodeData(Node);
  if Data^.Kind = tnkTemplate then
    Result := Node;
end;

{ --- Template list VST events --- }

procedure TdlgExperimentTemplate.vstTemplateListGetNodeDataSize(
  Sender: TBaseVirtualTree; var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TTemplateListNodeData);
end;

procedure TdlgExperimentTemplate.vstTemplateListGetCellText(
  Sender: TCustomVirtualStringTree; var E: TVSTGetCellTextEventArgs);
var
  Data: PTemplateListNodeData;
begin
  Data := Sender.GetNodeData(E.Node);
  if not Assigned(Data) then Exit;
  E.CellText := Data^.Name;
end;

procedure TdlgExperimentTemplate.vstTemplateListFocusChanging(
  Sender: TBaseVirtualTree; OldNode, NewNode: PVirtualNode;
  OldColumn, NewColumn: TColumnIndex; var Allowed: Boolean);
var
  Data: PTemplateListNodeData;
begin
  if not Assigned(NewNode) then Exit;
  Data := vstTemplateList.GetNodeData(NewNode);
  Allowed := (Data^.Kind = tnkTemplate);
end;

procedure TdlgExperimentTemplate.vstTemplateListFocusChanged(
  Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex);
var
  Data: PTemplateListNodeData;
begin
  if not Assigned(Node) then
  begin
    FSelectedTemplateId := 0;
    vstStructure.Clear;
    SyncNodeToProps;
    SyncTemplateToDetails;
    Exit;
  end;

  Data := vstTemplateList.GetNodeData(Node);
  if Data^.Kind = tnkTemplate then
  begin
    FSelectedTemplateId := Data^.TemplateId;
    LoadStructure(FSelectedTemplateId);
    SyncTemplateToDetails;
  end;
end;

procedure TdlgExperimentTemplate.vstTemplateListFreeNode(
  Sender: TBaseVirtualTree; Node: PVirtualNode);
var
  Data: PTemplateListNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if Assigned(Data) then
    Finalize(Data^);
end;

procedure TdlgExperimentTemplate.vstTemplateListPaintText(
  Sender: TBaseVirtualTree; const TargetCanvas: TCanvas;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType);
var
  Data: PTemplateListNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data^.Kind of
    tnkCategory:
    begin
      TargetCanvas.Font.Style := [fsBold];
      TargetCanvas.Font.Color := clNavy;
    end;
    tnkTemplate:
    begin
      TargetCanvas.Font.Style := [];
      TargetCanvas.Font.Color := clWindowText;
    end;
  end;
end;

{ --- Details panel sync --- }

procedure TdlgExperimentTemplate.SyncTemplateToDetails;
var
  Node: PVirtualNode;
  Data: PTemplateListNodeData;
  HasTemplate: Boolean;
begin
  FUpdatingDetails := True;
  try
    Node := GetSelectedTemplateNode;
    HasTemplate := Assigned(Node);

    if HasTemplate then
    begin
      Data := vstTemplateList.GetNodeData(Node);
      edtName.Text := Data^.Name;
      cmbCategory.Text := Data^.Category;
      memDescription.Text := Data^.Description;
    end
    else
    begin
      edtName.Text := '';
      cmbCategory.Text := '';
      memDescription.Text := '';
    end;

    edtName.Enabled := HasTemplate and (FMode = tmManager);
    cmbCategory.Enabled := HasTemplate and (FMode = tmManager);
    memDescription.Enabled := HasTemplate and (FMode = tmManager);
  finally
    FUpdatingDetails := False;
  end;
end;

procedure TdlgExperimentTemplate.SyncDetailsToTemplate;
var
  Node: PVirtualNode;
  Data: PTemplateListNodeData;
begin
  if FUpdatingDetails then Exit;

  Node := GetSelectedTemplateNode;
  if not Assigned(Node) then Exit;

  Data := vstTemplateList.GetNodeData(Node);
  Data^.Name := edtName.Text;
  Data^.Category := cmbCategory.Text;
  Data^.Description := memDescription.Text;

  vstTemplateList.InvalidateNode(Node);
end;

procedure TdlgExperimentTemplate.edtNameChange(Sender: TObject);
begin
  if not FUpdatingDetails then
    SyncDetailsToTemplate;
end;

procedure TdlgExperimentTemplate.cmbCategoryChange(Sender: TObject);
begin
  if not FUpdatingDetails then
    SyncDetailsToTemplate;
end;

procedure TdlgExperimentTemplate.memDescriptionChange(Sender: TObject);
begin
  if not FUpdatingDetails then
    SyncDetailsToTemplate;
end;

{ --- Structure tree --- }

procedure TdlgExperimentTemplate.LoadStructure(TemplateId: Integer);
var
  Template: TExperimentTemplate;
  RootJSON: TJSONObject;
  RootObj: TJSONObject;
  ChildrenArr: TJSONArray;
  RootNode: PVirtualNode;
  Data: PTemplateNodeData;
  RootType: Integer;
  ActionTypeId: Integer;
  RootLevel: TItemLevel;
  IsFolder: Boolean;
begin
  vstStructure.Clear;

  Template := Model.ExperimentTemplates.GetTemplate(TemplateId);
  if not Assigned(Template) then Exit;

  if Trim(Template.StructureJSON) = '' then Exit;

  RootJSON := TJSONObject.ParseJSONValue(Template.StructureJSON) as TJSONObject;
  if not Assigned(RootJSON) then Exit;
  try
    // Support "folder", "proc", and "item" root keys
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

    vstStructure.BeginUpdate;
    try
      RootNode := vstStructure.AddChild(nil);
      Data := vstStructure.GetNodeData(RootNode);
      Data^.Title := RootObj.GetValue<string>('title', 'Untitled');
      Data^.Level := RootLevel;
      RootType := RootObj.GetValue<Integer>('type', Ord(TItemType.Other));
      if (RootType >= Ord(Low(TItemType))) and (RootType <= Ord(High(TItemType))) then
        Data^.ItemType := TItemType(RootType)
      else
        Data^.ItemType := TItemType.Other;
      ActionTypeId := RootObj.GetValue<Integer>('actionTypeId', 0);
      Data^.ActionTypeId := ActionTypeId;
      Data^.ActionTypeName := '';
      Data^.IsFolder := IsFolder;

      if RootObj.TryGetValue<TJSONArray>('children', ChildrenArr) then
        LoadStructureNode(RootNode, ChildrenArr);
    finally
      vstStructure.EndUpdate;
    end;
    vstStructure.FullExpand;
  finally
    RootJSON.Free;
  end;
end;

procedure TdlgExperimentTemplate.LoadStructureNode(ParentNode: PVirtualNode;
  JsonArr: TJSONArray);
var
  i: Integer;
  ChildObj, Inner: TJSONObject;

  procedure AddItemNode(Obj: TJSONObject; DefaultLevel: TItemLevel);
  var
    Node: PVirtualNode;
    Data: PTemplateNodeData;
    LevelVal, TypeVal, ActionTypeId: Integer;
    SubChildren: TJSONArray;
  begin
    Node := vstStructure.AddChild(ParentNode);
    Data := vstStructure.GetNodeData(Node);
    Data^.Title := Obj.GetValue<string>('title', 'Untitled');
    LevelVal := Obj.GetValue<Integer>('level', Ord(DefaultLevel));
    if (LevelVal >= Ord(Low(TItemLevel))) and (LevelVal <= Ord(High(TItemLevel))) then
      Data^.Level := TItemLevel(LevelVal)
    else
      Data^.Level := DefaultLevel;
    TypeVal := Obj.GetValue<Integer>('type', Ord(TItemType.Other));
    if (TypeVal >= Ord(Low(TItemType))) and (TypeVal <= Ord(High(TItemType))) then
      Data^.ItemType := TItemType(TypeVal)
    else
      Data^.ItemType := TItemType.Other;
    ActionTypeId := Obj.GetValue<Integer>('actionTypeId', 0);
    Data^.ActionTypeId := ActionTypeId;
    Data^.ActionTypeName := '';
    Data^.IsFolder := False;
    if Obj.TryGetValue<TJSONArray>('children', SubChildren) then
      LoadStructureNode(Node, SubChildren);
  end;

  procedure AddFolderNode(Obj: TJSONObject);
  var
    Node: PVirtualNode;
    Data: PTemplateNodeData;
    SubChildren: TJSONArray;
  begin
    Node := vstStructure.AddChild(ParentNode);
    Data := vstStructure.GetNodeData(Node);
    Data^.Title := Obj.GetValue<string>('title', 'Folder');
    Data^.Level := TItemLevel.Item;  // placeholder; display uses IsFolder
    Data^.ItemType := TItemType.Other;
    Data^.ActionTypeId := 0;
    Data^.ActionTypeName := '';
    Data^.IsFolder := True;
    if Obj.TryGetValue<TJSONArray>('children', SubChildren) then
      LoadStructureNode(Node, SubChildren);
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
      AddItemNode(ChildObj, TItemLevel.Item);  // v1 back-compat (bare object)
  end;
end;

function TdlgExperimentTemplate.SaveStructureToJSON: string;
var
  RootJSON, RootObj: TJSONObject;
  ChildrenArr: TJSONArray;
  RootNode: PVirtualNode;
  Data: PTemplateNodeData;
  FirstChild: PVirtualNode;
  RootKey: string;
begin
  Result := '';
  RootNode := vstStructure.GetFirst;
  if not Assigned(RootNode) then Exit;

  Data := vstStructure.GetNodeData(RootNode);

  RootObj := TJSONObject.Create;
  RootObj.AddPair('title', Data^.Title);
  RootObj.AddPair('type', TJSONNumber.Create(Ord(Data^.ItemType)));
  if Data^.ActionTypeId > 0 then
    RootObj.AddPair('actionTypeId', TJSONNumber.Create(Data^.ActionTypeId));

  ChildrenArr := TJSONArray.Create;
  FirstChild := vstStructure.GetFirstChild(RootNode);
  if Assigned(FirstChild) then
    SaveStructureNode(FirstChild, ChildrenArr);
  RootObj.AddPair('children', ChildrenArr);

  // Use root key based on the root node's level
  if Data^.Level = TItemLevel.Item then
    RootKey := 'item'
  else
    RootKey := 'proc';

  RootJSON := TJSONObject.Create;
  RootJSON.AddPair(RootKey, RootObj);
  try
    Result := RootJSON.Format(2);
  finally
    RootJSON.Free;
  end;
end;

procedure TdlgExperimentTemplate.SaveStructureNode(Node: PVirtualNode;
  Arr: TJSONArray);
var
  Data: PTemplateNodeData;
  Obj: TJSONObject;
  ChildArr: TJSONArray;
  Child: PVirtualNode;
begin
  while Assigned(Node) do
  begin
    Data := vstStructure.GetNodeData(Node);
    Obj := TJSONObject.Create;
    Obj.AddPair('title', Data^.Title);
    Obj.AddPair('level', TJSONNumber.Create(Ord(Data^.Level)));
    Obj.AddPair('type', TJSONNumber.Create(Ord(Data^.ItemType)));
    if Data^.ActionTypeId > 0 then
      Obj.AddPair('actionTypeId', TJSONNumber.Create(Data^.ActionTypeId));

    ChildArr := TJSONArray.Create;
    Child := vstStructure.GetFirstChild(Node);
    if Assigned(Child) then
      SaveStructureNode(Child, ChildArr);
    Obj.AddPair('children', ChildArr);

    Arr.AddElement(Obj);
    Node := vstStructure.GetNextSibling(Node);
  end;
end;

{ --- Structure VTree events --- }

procedure TdlgExperimentTemplate.vstStructureGetNodeDataSize(
  Sender: TBaseVirtualTree; var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TTemplateNodeData);
end;

procedure TdlgExperimentTemplate.vstStructureGetCellText(
  Sender: TCustomVirtualStringTree; var E: TVSTGetCellTextEventArgs);
var
  Data: PTemplateNodeData;
  LevelName, ATName: string;
  i: Integer;
begin
  Data := Sender.GetNodeData(E.Node);
  if not Assigned(Data) then Exit;

  if Data^.IsFolder then
  begin
    E.CellText := 'Folder: ' + Data^.Title;
    Exit;
  end;

  LevelName := GetEnumName(TypeInfo(TItemLevel), Ord(Data^.Level));
  E.CellText := LevelName + ': ' + Data^.Title;

  if Data^.ActionTypeId > 0 then
  begin
    ATName := '';
    for i := 0 to lstNodeActionType.Items.Count - 1 do
      if Integer(lstNodeActionType.Items.Objects[i]) = Data^.ActionTypeId then
      begin
        ATName := lstNodeActionType.Items[i];
        Break;
      end;
    if ATName <> '' then
      E.CellText := E.CellText + ' [' + ATName + ']';
  end;
end;

procedure TdlgExperimentTemplate.vstStructureFreeNode(
  Sender: TBaseVirtualTree; Node: PVirtualNode);
var
  Data: PTemplateNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if Assigned(Data) then
    Finalize(Data^);
end;

procedure TdlgExperimentTemplate.vstStructureFocusChanged(
  Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex);
begin
  SyncNodeToProps;
end;

procedure TdlgExperimentTemplate.vstStructurePaintText(
  Sender: TBaseVirtualTree; const TargetCanvas: TCanvas;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType);
var
  Data: PTemplateNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) then Exit;

  case Data^.Level of
    TItemLevel.Proc:
    begin
      TargetCanvas.Font.Style := [fsBold];
      TargetCanvas.Font.Color := clNavy;
    end;
    TItemLevel.Item:
    begin
      TargetCanvas.Font.Style := [];
      TargetCanvas.Font.Color := clWindowText;
    end;
    TItemLevel.Action:
    begin
      TargetCanvas.Font.Style := [];
      TargetCanvas.Font.Color := $006400; // dark green
    end;
  end;
end;

{ --- Node property panel sync --- }

procedure TdlgExperimentTemplate.SyncNodeToProps;
var
  Node: PVirtualNode;
  Data: PTemplateNodeData;
  i: Integer;
  HasNode: Boolean;
begin
  FUpdatingProps := True;
  try
    Node := vstStructure.FocusedNode;
    HasNode := Assigned(Node);

    if HasNode then
    begin
      Data := vstStructure.GetNodeData(Node);
      edtNodeTitle.Text := Data^.Title;

      // Select Level
      lstNodeLevel.ItemIndex := -1;
      for i := 0 to lstNodeLevel.Items.Count - 1 do
        if Integer(lstNodeLevel.Items.Objects[i]) = Ord(Data^.Level) then
        begin
          lstNodeLevel.ItemIndex := i;
          Break;
        end;

      // Select Type
      lstNodeType.ItemIndex := -1;
      for i := 0 to lstNodeType.Items.Count - 1 do
        if Integer(lstNodeType.Items.Objects[i]) = Ord(Data^.ItemType) then
        begin
          lstNodeType.ItemIndex := i;
          Break;
        end;

      // Select ActionType
      lstNodeActionType.ItemIndex := -1;
      for i := 0 to lstNodeActionType.Items.Count - 1 do
        if Integer(lstNodeActionType.Items.Objects[i]) = Data^.ActionTypeId then
        begin
          lstNodeActionType.ItemIndex := i;
          Break;
        end;
    end
    else
    begin
      edtNodeTitle.Text := '';
      lstNodeLevel.ItemIndex := -1;
      lstNodeType.ItemIndex := -1;
      lstNodeActionType.ItemIndex := -1;
    end;

    // Enable/disable based on mode and selection
    edtNodeTitle.Enabled := HasNode and (FMode = tmManager);
    lstNodeLevel.Enabled := HasNode and (FMode = tmManager);
    lstNodeType.Enabled := HasNode and (FMode = tmManager);
    lstNodeActionType.Enabled := HasNode and (FMode = tmManager);
  finally
    FUpdatingProps := False;
  end;
end;

procedure TdlgExperimentTemplate.SyncPropsToNode;
var
  Node: PVirtualNode;
  Data: PTemplateNodeData;
  Idx: Integer;
begin
  if FUpdatingProps then Exit;

  Node := vstStructure.FocusedNode;
  if not Assigned(Node) then Exit;

  Data := vstStructure.GetNodeData(Node);

  Data^.Title := edtNodeTitle.Text;

  Idx := lstNodeLevel.ItemIndex;
  if Idx >= 0 then
    Data^.Level := TItemLevel(Integer(lstNodeLevel.Items.Objects[Idx]));

  Idx := lstNodeType.ItemIndex;
  if Idx >= 0 then
    Data^.ItemType := TItemType(Integer(lstNodeType.Items.Objects[Idx]));

  Idx := lstNodeActionType.ItemIndex;
  if Idx >= 0 then
  begin
    Data^.ActionTypeId := Integer(lstNodeActionType.Items.Objects[Idx]);
    Data^.ActionTypeName := lstNodeActionType.Items[Idx];
  end
  else
  begin
    Data^.ActionTypeId := 0;
    Data^.ActionTypeName := '';
  end;

  vstStructure.InvalidateNode(Node);
end;

procedure TdlgExperimentTemplate.edtNodeTitleChange(Sender: TObject);
begin
  if not FUpdatingProps then
    SyncPropsToNode;
end;

procedure TdlgExperimentTemplate.lstNodeLevelClick(Sender: TObject);
begin
  if not FUpdatingProps then
    SyncPropsToNode;
end;

procedure TdlgExperimentTemplate.lstNodeTypeClick(Sender: TObject);
begin
  if not FUpdatingProps then
    SyncPropsToNode;
end;

procedure TdlgExperimentTemplate.lstNodeActionTypeClick(Sender: TObject);
begin
  if not FUpdatingProps then
    SyncPropsToNode;
end;

{ --- Tree editing buttons --- }

function TdlgExperimentTemplate.GetAllowedChildLevel(
  ParentNode: PVirtualNode): TItemLevel;
var
  Data: PTemplateNodeData;
begin
  Result := TItemLevel.Item; // default
  if not Assigned(ParentNode) then
    Exit;
  Data := vstStructure.GetNodeData(ParentNode);
  case Data^.Level of
    TItemLevel.Proc: Result := TItemLevel.Item;
    TItemLevel.Item: Result := TItemLevel.Action;
    TItemLevel.Action: Result := TItemLevel.Item;
  else
    Result := TItemLevel.Item;
  end;
end;

procedure TdlgExperimentTemplate.btnAddChildClick(Sender: TObject);
var
  Focused, NewNode: PVirtualNode;
  Data: PTemplateNodeData;
  RootLevel: TItemLevel;
begin
  Focused := vstStructure.FocusedNode;

  // If tree is empty, add root node — let user choose Proc or Item
  if (vstStructure.RootNodeCount = 0) then
  begin
    case MessageDlg('Create root as Procedure or Item (Specimen)?'#13#10#13#10 +
      '[Yes] = Procedure'#13#10 +
      '[No] = Item (Specimen)',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes: RootLevel := TItemLevel.Proc;
      mrNo:  RootLevel := TItemLevel.Item;
    else
      Exit;
    end;

    NewNode := vstStructure.AddChild(nil);
    Data := vstStructure.GetNodeData(NewNode);
    if RootLevel = TItemLevel.Item then
    begin
      Data^.Title := 'New Specimen';
      Data^.Level := TItemLevel.Item;
      Data^.ItemType := TItemType.Specimen;
    end
    else
    begin
      Data^.Title := 'New Procedure';
      Data^.Level := TItemLevel.Proc;
      Data^.ItemType := TItemType.Other;
    end;
    Data^.ActionTypeId := 0;
    Data^.ActionTypeName := '';
    vstStructure.FocusedNode := NewNode;
    vstStructure.Selected[NewNode] := True;
    SyncNodeToProps;
    Exit;
  end;

  if not Assigned(Focused) then Exit;

  NewNode := vstStructure.AddChild(Focused);
  Data := vstStructure.GetNodeData(NewNode);
  Data^.Title := 'New Item';
  Data^.Level := GetAllowedChildLevel(Focused);
  Data^.ItemType := TItemType.Other;
  Data^.ActionTypeId := 0;
  Data^.ActionTypeName := '';

  vstStructure.Expanded[Focused] := True;
  vstStructure.FocusedNode := NewNode;
  vstStructure.Selected[NewNode] := True;
  SyncNodeToProps;
end;

procedure TdlgExperimentTemplate.btnAddSiblingClick(Sender: TObject);
var
  Focused, NewNode, ParentNode: PVirtualNode;
  Data, FocusedData: PTemplateNodeData;
begin
  Focused := vstStructure.FocusedNode;
  if not Assigned(Focused) then Exit;

  ParentNode := vstStructure.NodeParent[Focused];
  if not Assigned(ParentNode) then
  begin
    MessageDlg('Only one root node is allowed per template.', mtInformation, [mbOK], 0);
    Exit;
  end;

  FocusedData := vstStructure.GetNodeData(Focused);
  NewNode := vstStructure.InsertNode(Focused, amInsertAfter);
  Data := vstStructure.GetNodeData(NewNode);
  Data^.Title := 'New Item';
  Data^.Level := FocusedData^.Level;
  Data^.ItemType := TItemType.Other;
  Data^.ActionTypeId := 0;
  Data^.ActionTypeName := '';

  vstStructure.FocusedNode := NewNode;
  vstStructure.Selected[NewNode] := True;
  SyncNodeToProps;
end;

procedure TdlgExperimentTemplate.btnDeleteNodeClick(Sender: TObject);
var
  Focused: PVirtualNode;
begin
  Focused := vstStructure.FocusedNode;
  if not Assigned(Focused) then Exit;

  if MessageDlg('Delete this node and all its children?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    vstStructure.DeleteNode(Focused);
    SyncNodeToProps;
  end;
end;

procedure TdlgExperimentTemplate.btnMoveUpClick(Sender: TObject);
var
  Focused, Prev: PVirtualNode;
begin
  Focused := vstStructure.FocusedNode;
  if not Assigned(Focused) then Exit;

  Prev := vstStructure.GetPreviousSibling(Focused);
  if Assigned(Prev) then
    vstStructure.MoveTo(Focused, Prev, amInsertBefore, False);
end;

procedure TdlgExperimentTemplate.btnMoveDownClick(Sender: TObject);
var
  Focused, Next: PVirtualNode;
begin
  Focused := vstStructure.FocusedNode;
  if not Assigned(Focused) then Exit;

  Next := vstStructure.GetNextSibling(Focused);
  if Assigned(Next) then
    vstStructure.MoveTo(Focused, Next, amInsertAfter, False);
end;

procedure TdlgExperimentTemplate.btnLevelUpClick(Sender: TObject);
var
  Focused, ParentNode, GrandParent: PVirtualNode;
  Data: PTemplateNodeData;
begin
  Focused := vstStructure.FocusedNode;
  if not Assigned(Focused) then Exit;

  ParentNode := vstStructure.NodeParent[Focused];
  if not Assigned(ParentNode) then Exit;

  GrandParent := vstStructure.NodeParent[ParentNode];
  if not Assigned(GrandParent) then Exit;

  // Reparent: move node as sibling after its current parent
  vstStructure.MoveTo(Focused, ParentNode, amInsertAfter, False);

  // Update the node's Level to match its new depth
  Data := vstStructure.GetNodeData(Focused);
  Data^.Level := GetAllowedChildLevel(GrandParent);
  vstStructure.InvalidateNode(Focused);
  SyncNodeToProps;
end;

{ --- Template CRUD buttons --- }

procedure TdlgExperimentTemplate.AddNewTemplate;
var
  Name: string;
  JSON: string;
  RootJSON, RootObj: TJSONObject;
  RootKey: string;
  RootLevel: TItemLevel;
  Node: PVirtualNode;
  Data: PTemplateListNodeData;
begin
  Name := '';
  if not InputQuery('New Template', 'Template name:', Name) or
     (Trim(Name) = '') then
    Exit;

  // Choose root level
  case MessageDlg('Create root as Procedure or Item (Specimen)?'#13#10#13#10 +
    '[Yes] = Procedure'#13#10 +
    '[No] = Item (Specimen)',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: RootLevel := TItemLevel.Proc;
    mrNo:  RootLevel := TItemLevel.Item;
  else
    Exit;
  end;

  if RootLevel = TItemLevel.Item then
    RootKey := 'item'
  else
    RootKey := 'proc';

  RootObj := TJSONObject.Create;
  RootObj.AddPair('title', Trim(Name));
  if RootLevel = TItemLevel.Item then
    RootObj.AddPair('type', TJSONNumber.Create(Ord(TItemType.Specimen)))
  else
    RootObj.AddPair('type', TJSONNumber.Create(Ord(TItemType.Other)));
  RootObj.AddPair('children', TJSONArray.Create);
  RootJSON := TJSONObject.Create;
  try
    RootJSON.AddPair(RootKey, RootObj);
    JSON := RootJSON.ToJSON;
  finally
    RootJSON.Free;
  end;
  Model.ExperimentTemplates.AddTemplate(Trim(Name), '', '', JSON,
    Model.User.Id);
  LoadTemplates;

  // Select the newly added template by name
  Node := vstTemplateList.GetFirst;
  while Assigned(Node) do
  begin
    Data := vstTemplateList.GetNodeData(Node);
    if (Data^.Kind = tnkTemplate) and (Data^.Name = Trim(Name)) then
    begin
      vstTemplateList.FocusedNode := Node;
      vstTemplateList.Selected[Node] := True;
      Break;
    end;
    Node := vstTemplateList.GetNext(Node);
  end;
end;

procedure TdlgExperimentTemplate.btnAddClick(Sender: TObject);
begin
  AddNewTemplate;
end;

procedure TdlgExperimentTemplate.btnDeleteClick(Sender: TObject);
begin
  if FSelectedTemplateId <= 0 then Exit;

  if MessageDlg('Delete this template?', mtConfirmation,
    [mbYes, mbNo], 0) = mrYes then
  begin
    Model.ExperimentTemplates.DeleteTemplate(FSelectedTemplateId);
    FSelectedTemplateId := 0;
    LoadTemplates;
  end;
end;

procedure TdlgExperimentTemplate.btnDuplicateClick(Sender: TObject);
begin
  if FSelectedTemplateId <= 0 then Exit;

  Model.ExperimentTemplates.DuplicateTemplate(FSelectedTemplateId,
    Model.User.Id);
  LoadTemplates;
end;

procedure TdlgExperimentTemplate.btnSaveClick(Sender: TObject);
begin
  SaveCurrentTemplate;
end;

procedure TdlgExperimentTemplate.btnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Node: PVirtualNode;
  Data: PTemplateListNodeData;
begin
  if FSelectedTemplateId <= 0 then Exit;

  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Export Template';
    Dlg.Filter := 'ELN Templates (*.elntemplate)|*.elntemplate';
    Dlg.DefaultExt := 'elntemplate';
    Node := GetSelectedTemplateNode;
    if Assigned(Node) then
    begin
      Data := vstTemplateList.GetNodeData(Node);
      Dlg.FileName := Data^.Name + '.elntemplate';
    end;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if Dlg.Execute then
    begin
      try
        Model.ExperimentTemplates.ExportTemplateToFile(FSelectedTemplateId,
          Dlg.FileName);
        MessageDlg('Template exported successfully.', mtInformation, [mbOK], 0);
      except
        on E: Exception do
          MessageDlg('Export failed: ' + E.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TdlgExperimentTemplate.btnImportClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  Warnings: string;
  Imported: TExperimentTemplate;
  Msg: string;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Import Template';
    Dlg.Filter := 'ELN Templates (*.elntemplate)|*.elntemplate';
    if not Dlg.Execute then Exit;

    try
      Imported := Model.ExperimentTemplates.ImportTemplateFromFile(
        Dlg.FileName, Model.User.Id, Warnings);
      if Assigned(Imported) then
      begin
        Msg := 'Template "' + Imported.Name + '" imported successfully.';
        if Trim(Warnings) <> '' then
          Msg := Msg + #13#10#13#10 + 'Warnings:' + #13#10 + Warnings;
        MessageDlg(Msg, mtInformation, [mbOK], 0);
        LoadTemplates;
      end;
    except
      on E: Exception do
        MessageDlg('Import failed: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TdlgExperimentTemplate.btnBulkImportClick(Sender: TObject);
var
  Dir: string;
  SR: TSearchRec;
  FilePath, Warnings, AllWarnings: string;
  Imported: TExperimentTemplate;
  CountOK, CountFail: Integer;
begin
  Dir := '';
  if not SelectDirectory('Select folder with .elntemplate files', '', Dir) then
    Exit;

  CountOK := 0;
  CountFail := 0;
  AllWarnings := '';

  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.elntemplate', faAnyFile, SR) = 0 then
  try
    repeat
      FilePath := IncludeTrailingPathDelimiter(Dir) + SR.Name;
      try
        Imported := Model.ExperimentTemplates.ImportTemplateFromFile(
          FilePath, Model.User.Id, Warnings);
        if Assigned(Imported) then
        begin
          Inc(CountOK);
          if Trim(Warnings) <> '' then
            AllWarnings := AllWarnings + SR.Name + ': ' + Trim(Warnings) + #13#10;
        end
        else
          Inc(CountFail);
      except
        on E: Exception do
        begin
          Inc(CountFail);
          AllWarnings := AllWarnings + SR.Name + ': ' + E.Message + #13#10;
        end;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;

  if CountOK + CountFail = 0 then
  begin
    MessageDlg('No .elntemplate files found in selected folder.', mtWarning, [mbOK], 0);
    Exit;
  end;

  var Msg := Format('Imported %d template(s), %d failed.', [CountOK, CountFail]);
  if Trim(AllWarnings) <> '' then
    Msg := Msg + #13#10#13#10 + 'Details:' + #13#10 + AllWarnings;
  MessageDlg(Msg, mtInformation, [mbOK], 0);
  LoadTemplates;
end;

procedure TdlgExperimentTemplate.SaveCurrentTemplate;
var
  Template: TExperimentTemplate;
  JSON: string;
  Node: PVirtualNode;
  Data: PTemplateListNodeData;
begin
  if FSelectedTemplateId <= 0 then Exit;

  Template := Model.ExperimentTemplates.GetTemplate(FSelectedTemplateId);
  if not Assigned(Template) then Exit;

  // Save structure if tree has content
  JSON := SaveStructureToJSON;
  if JSON <> '' then
    Template.StructureJSON := JSON;

  // Save metadata from details panel
  Node := GetSelectedTemplateNode;
  if Assigned(Node) then
  begin
    Data := vstTemplateList.GetNodeData(Node);
    Template.Name := Data^.Name;
    Template.Category := Data^.Category;
    Template.Description := Data^.Description;
  end;

  Model.ExperimentTemplates.UpdateTemplate(Template);
end;

procedure TdlgExperimentTemplate.btnCreateClick(Sender: TObject);
begin
  if FSelectedTemplateId <= 0 then
  begin
    MessageDlg('Please select a template first.', mtWarning, [mbOK], 0);
    ModalResult := mrNone;
  end;
end;

{ --- Dual mode --- }

procedure TdlgExperimentTemplate.SetMode(AMode: TTemplateMode);
begin
  FMode := AMode;

  case AMode of
    tmManager:
    begin
      btnCreate.Visible := False;
      btnClose.Caption := 'Close';
      btnClose.ModalResult := mrClose;
      btnSave.Visible := True;
      pnlListButtons.Visible := True;
      pnlDetails.Visible := True;
      pnlTreeButtons.Visible := True;
      Caption := 'Manage Experiment Templates';
    end;
    tmSelector:
    begin
      btnCreate.Visible := True;
      btnClose.Caption := 'Cancel';
      btnClose.ModalResult := mrCancel;
      btnSave.Visible := False;
      pnlListButtons.Visible := False;
      pnlDetails.Visible := False;
      pnlTreeButtons.Visible := False;
      Caption := 'Select Experiment Template';
    end;
  end;
end;

{ --- Class methods --- }

class function TdlgExperimentTemplate.SelectTemplate(
  out TemplateId: Integer): Boolean;
var
  Dlg: TdlgExperimentTemplate;
begin
  Result := False;
  TemplateId := 0;
  Dlg := TdlgExperimentTemplate.Create(Application);
  try
    Dlg.SetMode(tmSelector);
    Dlg.LoadTemplates;
    if Dlg.ShowModal = mrOk then
    begin
      TemplateId := Dlg.FSelectedTemplateId;
      Result := TemplateId > 0;
    end;
  finally
    Dlg.Free;
  end;
end;

class procedure TdlgExperimentTemplate.ManageTemplates;
var
  Dlg: TdlgExperimentTemplate;
begin
  Dlg := TdlgExperimentTemplate.Create(Application);
  try
    Dlg.SetMode(tmManager);
    Dlg.LoadTemplates;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
