unit dlg_ItemPicker;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  VirtualTrees, VirtualTrees.Types, VirtualTrees.BaseTree,
  VirtualTrees.BaseAncestorVCL, VirtualTrees.AncestorVCL,
  unit_Item, unit_Project, unit_ItemTypes, unit_User;

type
  TPickerNodeKind = (nkProject, nkItem);

  PPickerNodeData = ^TPickerNodeData;
  TPickerNodeData = record
    Kind: TPickerNodeKind;
    Id: Integer;
    ProjectId: Integer;
    FolderId: Integer;
    Title: string;
    Level: TItemLevel;
  end;

  TDuplicateResult = record
    ProjectId: Integer;
    FolderId: Integer;
    ParentItemId: Integer;
    LinkToOriginal: Boolean;
  end;

  TdlgItemPicker = class(TForm)
    Tree: TVirtualStringTree;
    cbLink: TCheckBox;
    btnOK: TButton;
    btnCancel: TButton;
    procedure TreeGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure TreeChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure cbLinkClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
  private
    FCurrentItemId: Integer;
    FDuplicateMode: Boolean;
    procedure ApplyMode;
    function AccessibleProjects: TList<TProject>;
    procedure LoadTree;
    procedure LoadTreeHierarchical;
    procedure UpdateOKState;
    function IsSelectableNode(Data: PPickerNodeData): Boolean;
  public
    class function Execute(CurrentItemId: Integer;
      out TargetItemId: Integer; out ATargetTitle: string): Boolean;
    class function ExecuteDuplicate(CurrentItemId: Integer;
      out Dest: TDuplicateResult): Boolean;
  end;

implementation

uses
  Aurelius.Criteria.Linq,
  Aurelius.Engine.ObjectManager,
  unit_ELNDB_Dictionary,
  unit_ProjectModel,
  unit_DataModel;

{$R *.dfm}


procedure TdlgItemPicker.ApplyMode;
begin
  if FDuplicateMode then
  begin
    Caption := 'Duplicate Item — Select Destination';
    btnOK.Caption := 'Duplicate';
    cbLink.Visible := True;
  end
  else
  begin
    Caption := 'Select Item to Link';
    btnOK.Caption := 'Next...';
    cbLink.Visible := False;
  end;
end;

// Caller owns the returned list.
function TdlgItemPicker.AccessibleProjects: TList<TProject>;
var
  ProjDic: TProjectDictionary;
begin
  if Model.Access.CanBrowseAllProjects(Model.Manager, Model.User) then
  begin
    ProjDic := TProjectDictionary.Create;
    try
      Result := Model.Manager.Find<TProject>
        .Where(ProjDic.IsArchived = False)
        .OrderBy(ProjDic.Title)
        .List;
    finally
      ProjDic.Free;
    end;
  end
  else
    Result := Model.Projects.List;
end;

procedure TdlgItemPicker.LoadTree;
var
  Projects: TList<TProject>;
  Proj: TProject;
  Items: TItems;
  Item: TItem;
  ProjNode, ItemNode: PVirtualNode;
  ProjData, ItemData: PPickerNodeData;
  ItemDic: TItemDictionary;
begin
  Tree.BeginUpdate;
  try
    Tree.Clear;
    Projects := AccessibleProjects;
    ItemDic := TItemDictionary.Create;
    try
      for Proj in Projects do
      begin
        if Proj.IsArchived then Continue;
        if FDuplicateMode and
           not Model.Access.CanWrite(Model.Manager, Model.User, Proj.Id) then Continue;

        ProjNode := Tree.AddChild(nil);
        ProjData := Tree.GetNodeData(ProjNode);
        ProjData.Kind := nkProject;
        ProjData.Id := Proj.Id;
        ProjData.ProjectId := Proj.Id;
        ProjData.FolderId := 0;
        ProjData.Title := Proj.Title;

        Items := Model.Manager.Find<TItem>
          .Where(
            (ItemDic.ProjectID = Proj.Id) and
            (ItemDic.IsDeleted = False))
          .OrderBy(ItemDic.Title)
          .List;
        try
          for Item in Items do
          begin
            if Item.Id = FCurrentItemId then Continue;

            ItemNode := Tree.AddChild(ProjNode);
            ItemData := Tree.GetNodeData(ItemNode);
            ItemData.Kind := nkItem;
            ItemData.Id := Item.Id;
            ItemData.ProjectId := Proj.Id;
            ItemData.FolderId := Item.FolderID;
            ItemData.Title := Item.Title;
            ItemData.Level := Item.Level;
          end;
        finally
          Items.Free;
        end;
      end;
    finally
      ItemDic.Free;
      Projects.Free;
    end;
  finally
    Tree.EndUpdate;
  end;
end;

procedure TdlgItemPicker.LoadTreeHierarchical;
var
  Projects: TList<TProject>;
  Proj: TProject;
  Items: TItems;
  Item: TItem;
  ProjNode, ItemNode: PVirtualNode;
  ProjData, ItemData: PPickerNodeData;
  ItemDic: TItemDictionary;
  NodeMap: TDictionary<Integer, PVirtualNode>;
  I: Integer;
begin
  Tree.BeginUpdate;
  try
    Tree.Clear;
    Projects := AccessibleProjects;
    ItemDic := TItemDictionary.Create;
    NodeMap := TDictionary<Integer, PVirtualNode>.Create;
    try
      for Proj in Projects do
      begin
        if Proj.IsArchived then Continue;
        if FDuplicateMode and
           not Model.Access.CanWrite(Model.Manager, Model.User, Proj.Id) then Continue;

        ProjNode := Tree.AddChild(nil);
        ProjData := Tree.GetNodeData(ProjNode);
        ProjData.Kind := nkProject;
        ProjData.Id := Proj.Id;
        ProjData.ProjectId := Proj.Id;
        ProjData.FolderId := 0;
        ProjData.Title := Proj.Title;

        Items := Model.Manager.Find<TItem>
          .Where(
            (ItemDic.ProjectID = Proj.Id) and
            (ItemDic.IsDeleted = False))
          .OrderBy(ItemDic.SortOrder)
          .List;
        try
          for Item in Items do
          begin
            if Item.Id = FCurrentItemId then Continue;
            if Item.Level = TItemLevel.Folder then Continue;

            ItemNode := Tree.AddChild(ProjNode);
            ItemData := Tree.GetNodeData(ItemNode);
            ItemData.Kind := nkItem;
            ItemData.Id := Item.Id;
            ItemData.ProjectId := Proj.Id;
            ItemData.FolderId := Item.FolderID;
            ItemData.Title := Item.Title;
            ItemData.Level := Item.Level;
            NodeMap.Add(Item.Id, ItemNode);
          end;

          for I := 0 to Items.Count - 1 do
          begin
            if Items[I].Id = FCurrentItemId then Continue;
            if Items[I].Level = TItemLevel.Folder then Continue;
            if (Items[I].Parent > 0) and NodeMap.ContainsKey(Items[I].Id) and
               NodeMap.ContainsKey(Items[I].Parent) then
            begin
              Tree.MoveTo(NodeMap[Items[I].Id], NodeMap[Items[I].Parent],
                amAddChildLast, False);
            end;
          end;
        finally
          Items.Free;
        end;
      end;
    finally
      NodeMap.Free;
      ItemDic.Free;
      Projects.Free;
    end;
  finally
    Tree.EndUpdate;
  end;
end;

procedure TdlgItemPicker.TreeGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TPickerNodeData);
end;

procedure TdlgItemPicker.TreeGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
var
  Data: PPickerNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if Assigned(Data) then
    CellText := Data.Title;
end;

procedure TdlgItemPicker.TreeChange(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
begin
  UpdateOKState;
end;

procedure TdlgItemPicker.cbLinkClick(Sender: TObject);
begin
  UpdateOKState;
end;

function TdlgItemPicker.IsSelectableNode(Data: PPickerNodeData): Boolean;
begin
  if not Assigned(Data) then
    Exit(False);

  if FDuplicateMode then
  begin
    if Data.Kind = nkProject then
      Result := True
    else
      Result := Data.Level in [TItemLevel.Proc, TItemLevel.Action];
  end
  else
    Result := Data.Kind = nkItem;
end;

procedure TdlgItemPicker.UpdateOKState;
var
  Node: PVirtualNode;
  Data: PPickerNodeData;
begin
  Node := Tree.GetFirstSelected;
  if Assigned(Node) then
  begin
    Data := Tree.GetNodeData(Node);
    btnOK.Enabled := IsSelectableNode(Data);
  end
  else
    btnOK.Enabled := False;
end;

procedure TdlgItemPicker.btnOKClick(Sender: TObject);
begin
  if btnOK.Enabled then
    ModalResult := mrOK;
end;

class function TdlgItemPicker.Execute(CurrentItemId: Integer;
  out TargetItemId: Integer; out ATargetTitle: string): Boolean;
var
  Dlg: TdlgItemPicker;
  Node: PVirtualNode;
  Data: PPickerNodeData;
begin
  Result := False;
  TargetItemId := 0;
  ATargetTitle := '';
  Dlg := TdlgItemPicker.Create(Application);
  try
    Dlg.FCurrentItemId := CurrentItemId;
    Dlg.FDuplicateMode := False;
    Dlg.ApplyMode;
    Dlg.LoadTree;
    if Dlg.ShowModal = mrOK then
    begin
      Node := Dlg.Tree.GetFirstSelected;
      if Assigned(Node) then
      begin
        Data := Dlg.Tree.GetNodeData(Node);
        if Assigned(Data) and (Data.Kind = nkItem) then
        begin
          TargetItemId := Data.Id;
          ATargetTitle := Data.Title;
          Result := True;
        end;
      end;
    end;
  finally
    Dlg.Free;
  end;
end;

class function TdlgItemPicker.ExecuteDuplicate(CurrentItemId: Integer;
  out Dest: TDuplicateResult): Boolean;
var
  Dlg: TdlgItemPicker;
  Node: PVirtualNode;
  Data: PPickerNodeData;
begin
  Result := False;
  Dlg := TdlgItemPicker.Create(Application);
  try
    Dlg.FCurrentItemId := CurrentItemId;
    Dlg.FDuplicateMode := True;
    Dlg.ApplyMode;
    Dlg.LoadTreeHierarchical;
    if Dlg.ShowModal = mrOK then
    begin
      Node := Dlg.Tree.GetFirstSelected;
      if Assigned(Node) then
      begin
        Data := Dlg.Tree.GetNodeData(Node);
        if Assigned(Data) and Dlg.IsSelectableNode(Data) then
        begin
          Dest.LinkToOriginal := Dlg.cbLink.Checked;
          if Data.Kind = nkProject then
          begin
            Dest.ProjectId := Data.ProjectId;
            Dest.FolderId := 0;
            Dest.ParentItemId := 0;
          end
          else
          begin
            Dest.ProjectId := Data.ProjectId;
            Dest.FolderId := Data.FolderId;
            if Dest.FolderId < 0 then
              Dest.FolderId := 0;
            Dest.ParentItemId := Data.Id;
          end;
          Result := True;
        end;
      end;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
