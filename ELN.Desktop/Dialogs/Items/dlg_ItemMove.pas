unit dlg_ItemMove;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  VirtualTrees, VirtualTrees.Types, VirtualTrees.BaseTree,
  VirtualTrees.BaseAncestorVCL, VirtualTrees.AncestorVCL,
  unit_Item, unit_ItemTypes;

type
  TMoveNodeKind = (nkRoot, nkItem);

  PMoveNodeData = ^TMoveNodeData;
  TMoveNodeData = record
    Kind: TMoveNodeKind;
    Id: Integer;
    Title: string;
    Level: TItemLevel;
  end;

  TdlgItemMove = class(TForm)
    Tree: TVirtualStringTree;
    btnMove: TButton;
    btnCancel: TButton;
    procedure TreeGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure TreeChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeDblClick(Sender: TObject);
  private
    FSourceItems: TArray<TItem>;
    FAvailableItems: TItems;
    procedure LoadTree;
    procedure UpdateMoveState;
  public
    class function Execute(const SourceItems: TArray<TItem>;
      AvailableItems: TItems; out NewParentId: Integer): Boolean;
  end;

implementation

{$R *.dfm}


class function TdlgItemMove.Execute(const SourceItems: TArray<TItem>;
  AvailableItems: TItems; out NewParentId: Integer): Boolean;
var
  Dlg: TdlgItemMove;
  Node: PVirtualNode;
  Data: PMoveNodeData;
begin
  Result := False;
  NewParentId := -1;
  Dlg := TdlgItemMove.Create(Application);
  try
    Dlg.FSourceItems := SourceItems;
    Dlg.FAvailableItems := AvailableItems;
    if Length(SourceItems) = 1 then
      Dlg.Caption := Format('Move "%s" to...', [SourceItems[0].Title])
    else
      Dlg.Caption := Format('Move %d items to...', [Length(SourceItems)]);
    Dlg.LoadTree;
    Dlg.UpdateMoveState;
    if Dlg.ShowModal <> mrOK then Exit;

    Node := Dlg.Tree.GetFirstSelected;
    if not Assigned(Node) then Exit;
    Data := Dlg.Tree.GetNodeData(Node);
    if not Assigned(Data) then Exit;

    NewParentId := Data.Id;
    Result := True;
  finally
    Dlg.Free;
  end;
end;

procedure TdlgItemMove.LoadTree;
var
  ChildrenByParent: TDictionary<Integer, TList<TItem>>;
  Excluded: TDictionary<Integer, Boolean>;
  RootNode, InitialNode, Walk: PVirtualNode;
  RootData, WalkData: PMoveNodeData;
  ParentList: TList<TItem>;
  Item: TItem;

  procedure CollectExcluded(Id: Integer);
  var
    Children: TList<TItem>;
    Child: TItem;
  begin
    Excluded.AddOrSetValue(Id, True);
    if ChildrenByParent.TryGetValue(Id, Children) then
      for Child in Children do
        CollectExcluded(Child.Id);
  end;

  procedure InsertChildren(ParentItemId: Integer; ParentNode: PVirtualNode);
  var
    Children: TList<TItem>;
    Child: TItem;
    Node: PVirtualNode;
    Data: PMoveNodeData;
  begin
    if not ChildrenByParent.TryGetValue(ParentItemId, Children) then Exit;
    for Child in Children do
    begin
      if Excluded.ContainsKey(Child.Id) then Continue;
      if not (Child.Level in [TItemLevel.Proc, TItemLevel.Item, TItemLevel.Action]) then
        Continue;
      Node := Tree.AddChild(ParentNode);
      Data := Tree.GetNodeData(Node);
      Data.Kind := nkItem;
      Data.Id := Child.Id;
      Data.Title := Child.Title;
      Data.Level := Child.Level;
      InsertChildren(Child.Id, Node);
    end;
  end;

begin
  Tree.BeginUpdate;
  try
    Tree.Clear;

    ChildrenByParent := TDictionary<Integer, TList<TItem>>.Create;
    Excluded := TDictionary<Integer, Boolean>.Create;
    try
      for Item in FAvailableItems do
      begin
        if not ChildrenByParent.TryGetValue(Item.Parent, ParentList) then
        begin
          ParentList := TList<TItem>.Create;
          ChildrenByParent.Add(Item.Parent, ParentList);
        end;
        ParentList.Add(Item);
      end;

      for Item in FSourceItems do
        CollectExcluded(Item.Id);

      RootNode := Tree.AddChild(nil);
      RootData := Tree.GetNodeData(RootNode);
      RootData.Kind := nkRoot;
      RootData.Id := 0;
      RootData.Title := '(Root)';

      InsertChildren(0, RootNode);
    finally
      for ParentList in ChildrenByParent.Values do
        ParentList.Free;
      ChildrenByParent.Free;
      Excluded.Free;
    end;

    Tree.FullExpand;

    InitialNode := Tree.GetFirst;
    if Length(FSourceItems) > 0 then
    begin
      Walk := Tree.GetFirst;
      while Assigned(Walk) do
      begin
        WalkData := Tree.GetNodeData(Walk);
        if Assigned(WalkData) and (WalkData.Id = FSourceItems[0].Parent) then
        begin
          InitialNode := Walk;
          Break;
        end;
        Walk := Tree.GetNext(Walk);
      end;
    end;
    if Assigned(InitialNode) then
    begin
      Tree.FocusedNode := InitialNode;
      Tree.Selected[InitialNode] := True;
      Tree.ScrollIntoView(InitialNode, True);
    end;
  finally
    Tree.EndUpdate;
  end;
end;

procedure TdlgItemMove.TreeGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(TMoveNodeData);
end;

procedure TdlgItemMove.TreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
var
  Data: PMoveNodeData;
begin
  Data := Sender.GetNodeData(Node);
  if Assigned(Data) then
    CellText := Data.Title;
end;

procedure TdlgItemMove.TreeChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
begin
  UpdateMoveState;
end;

procedure TdlgItemMove.TreeDblClick(Sender: TObject);
begin
  if btnMove.Enabled then
    ModalResult := mrOK;
end;

procedure TdlgItemMove.UpdateMoveState;
var
  Node: PVirtualNode;
  Data: PMoveNodeData;
  Item: TItem;
begin
  btnMove.Enabled := False;
  Node := Tree.GetFirstSelected;
  if not Assigned(Node) then Exit;
  Data := Tree.GetNodeData(Node);
  if not Assigned(Data) then Exit;
  for Item in FSourceItems do
    if Item.Parent <> Data.Id then
    begin
      btnMove.Enabled := True;
      Exit;
    end;
end;

end.
