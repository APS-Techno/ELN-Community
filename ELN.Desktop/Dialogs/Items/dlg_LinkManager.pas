unit dlg_LinkManager;


interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Dialogs,
  unit_ItemLinkModel;

type
  TdlgLinkManager = class(TForm)
    lvLinks: TListView;
    btnAdd: TButton;
    btnEdit: TButton;
    btnRemove: TButton;
    btnOpen: TButton;
    btnClose: TButton;
    procedure btnAddClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnRemoveClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure lvLinksDblClick(Sender: TObject);
    procedure lvLinksSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
  private
    FItemId: Integer;
    FProjectId: Integer;
    FItemTitle: string;
    FCanWrite: Boolean;
    FLinks: TArray<TItemLinkInfo>;
    FOnNavigate: TProc<Integer, Integer>;
    procedure LoadLinks;
    procedure UpdateButtonState;
    function SelectedIndex: Integer;
  public
    class procedure ShowLinks(ItemId, AProjectId: Integer;
      const ItemTitle: string; OnNavigate: TProc<Integer, Integer>);
  end;

implementation

uses
  unit_DataModel,
  dlg_ItemPicker,
  dlg_LinkRelation,
  unit_TimeHelper;

{$R *.dfm}


procedure TdlgLinkManager.LoadLinks;
var
  Info: TItemLinkInfo;
  LI: TListItem;
begin
  lvLinks.Items.BeginUpdate;
  try
    lvLinks.Items.Clear;
    FLinks := Model.ItemLinks.GetLinksForItem(FItemId);
    for Info in FLinks do
    begin
      LI := lvLinks.Items.Add;
      // The relation as read from THIS item's end, so it matches the inline
      // list and never reads backwards. The arrow says which end this item is:
      // -> this item points at the other, <- the other points at this one.
      if Info.IsSource then
        LI.Caption := #$2192 + '  ' + Info.RelationText
      else
        LI.Caption := #$2190 + '  ' + Info.RelationText;
      LI.SubItems.Add(Info.LinkedItemTitle);
      LI.SubItems.Add(Info.LinkedProjectName);
      LI.SubItems.Add(Info.Notes);
      LI.SubItems.Add(DateToStr(FromUTC(Info.CreatedDate)));
      LI.Data := Pointer(Info.LinkId);
    end;
  finally
    lvLinks.Items.EndUpdate;
  end;
  UpdateButtonState;
end;

function TdlgLinkManager.SelectedIndex: Integer;
begin
  if Assigned(lvLinks.Selected) then
    Result := lvLinks.Selected.Index
  else
    Result := -1;
end;

procedure TdlgLinkManager.UpdateButtonState;
var
  HasSel: Boolean;
begin
  FCanWrite := Model.Access.CanWrite(Model.Manager, Model.User, FProjectId);
  HasSel := (SelectedIndex >= 0) and (SelectedIndex < Length(FLinks));

  btnAdd.Enabled := FCanWrite;
  btnEdit.Enabled := FCanWrite and HasSel;
  btnRemove.Enabled := FCanWrite and HasSel;
  btnOpen.Enabled := HasSel;
end;

procedure TdlgLinkManager.lvLinksSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  UpdateButtonState;
end;

procedure TdlgLinkManager.btnAddClick(Sender: TObject);
var
  TargetItemId, SourceId, DestId: Integer;
  TargetTitle: string;
  Res: TLinkRelationResult;
begin
  if not TdlgItemPicker.Execute(FItemId, TargetItemId, TargetTitle) then Exit;

  Res := Default(TLinkRelationResult);
  if not TdlgLinkRelation.Execute(FItemTitle, TargetTitle, Res) then Exit;

  if Res.IsForward then
  begin
    SourceId := FItemId;
    DestId := TargetItemId;
  end
  else
  begin
    SourceId := TargetItemId;
    DestId := FItemId;
  end;

  if not Model.Access.CanWrite(Model.Manager, Model.User, FProjectId) then Exit;
  if Model.ItemLinks.AddLink(SourceId, DestId, Res.LinkTypeId, Res.Notes,
       Model.User.Id) = nil then
    MessageDlg('These items are already linked.', mtInformation, [mbOK], 0)
  else
    LoadLinks;
end;

procedure TdlgLinkManager.btnEditClick(Sender: TObject);
var
  Idx: Integer;
  Res: TLinkRelationResult;
begin
  Idx := SelectedIndex;
  if (Idx < 0) or (Idx >= Length(FLinks)) then Exit;

  Res := Default(TLinkRelationResult);
  Res.LinkTypeId := FLinks[Idx].LinkTypeId;
  Res.IsForward := FLinks[Idx].IsSource;
  Res.Notes := FLinks[Idx].Notes;

  if not TdlgLinkRelation.Execute(FItemTitle, FLinks[Idx].LinkedItemTitle, Res) then
    Exit;

  if not Model.Access.CanWrite(Model.Manager, Model.User, FProjectId) then Exit;
  Model.ItemLinks.UpdateLink(FLinks[Idx].LinkId, Res.LinkTypeId, Res.Notes);
  LoadLinks;
end;

procedure TdlgLinkManager.btnRemoveClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := SelectedIndex;
  if (Idx < 0) or (Idx >= Length(FLinks)) then Exit;

  if MessageDlg('Remove this link?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    if not Model.Access.CanWrite(Model.Manager, Model.User, FProjectId) then Exit;
    Model.ItemLinks.RemoveLink(FLinks[Idx].LinkId);
    LoadLinks;
  end;
end;

procedure TdlgLinkManager.btnOpenClick(Sender: TObject);
begin
  lvLinksDblClick(Sender);
end;

procedure TdlgLinkManager.lvLinksDblClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := SelectedIndex;
  if (Idx < 0) or (Idx >= Length(FLinks)) then Exit;
  if not Assigned(FOnNavigate) then Exit;

  Close;
  FOnNavigate(FLinks[Idx].LinkedItemId, FLinks[Idx].LinkedItemProjectId);
end;

class procedure TdlgLinkManager.ShowLinks(ItemId, AProjectId: Integer;
  const ItemTitle: string; OnNavigate: TProc<Integer, Integer>);
var
  Dlg: TdlgLinkManager;
begin
  Dlg := TdlgLinkManager.Create(Application);
  try
    Dlg.FItemId := ItemId;
    Dlg.FProjectId := AProjectId;
    Dlg.FItemTitle := ItemTitle;
    Dlg.FOnNavigate := OnNavigate;
    Dlg.FCanWrite :=
      Model.Access.CanWrite(Model.Manager, Model.User, AProjectId);
    Dlg.Caption := 'Links - ' + ItemTitle;
    Dlg.LoadLinks;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
