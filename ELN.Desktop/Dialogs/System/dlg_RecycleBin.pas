unit dlg_RecycleBin;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Dialogs,
  unit_Item;

type
  TdlgRecycleBin = class(TForm)
    pnlTop: TPanel;
    lblTitle: TLabel;
    lvItems: TListView;
    pnlBottom: TPanel;
    btnRestore: TButton;
    btnPurge: TButton;
    btnEmpty: TButton;
    btnClose: TButton;
    procedure btnRestoreClick(Sender: TObject);
    procedure btnPurgeClick(Sender: TObject);
    procedure btnEmptyClick(Sender: TObject);
    procedure lvItemsSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
  private
    FChanged: Boolean;
    procedure LoadItems;
  public
    class function ShowRecycleBin: Boolean;
  end;

implementation

uses
  System.UITypes,
  System.TypInfo,
  unit_ItemTypes,
  unit_DataModel,
  unit_TimeHelper;

{$R *.dfm}

{ TdlgRecycleBin }

procedure TdlgRecycleBin.LoadItems;
var
  Items: TItems;
  Item: TItem;
  LI: TListItem;
  DeletedDateStr: string;
begin
  lvItems.Items.Clear;
  Items := Model.RecycleBin.GetDeletedItems;
  try
    for Item in Items do
    begin
      LI := lvItems.Items.Add;
      LI.Caption := Item.Title;
      LI.SubItems.Add(GetEnumName(TypeInfo(TItemLevel), Ord(Item.Level)));
      if Item.DeletedDate.HasValue then
        DeletedDateStr := FormatDateTime('yyyy-mm-dd hh:nn', FromUTC(Item.DeletedDate.Value))
      else
        DeletedDateStr := '';
      LI.SubItems.Add(DeletedDateStr);
      LI.SubItems.Add(Format('P:%d / F:%d', [Item.ProjectID, Item.FolderID]));
      LI.Data := Pointer(Item.Id);
    end;
  finally
    Items.Free;
  end;

  btnEmpty.Enabled := lvItems.Items.Count > 0;
  btnRestore.Enabled := False;
  btnPurge.Enabled := False;
end;

procedure TdlgRecycleBin.lvItemsSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  btnRestore.Enabled := Selected and Assigned(Item);
  btnPurge.Enabled := Selected and Assigned(Item);
end;

procedure TdlgRecycleBin.btnRestoreClick(Sender: TObject);
var
  LI: TListItem;
  Item: TItem;
  ItemId: Integer;
begin
  LI := lvItems.Selected;
  if not Assigned(LI) then Exit;

  ItemId := Integer(LI.Data);
  Item := Model.Items.GetItem(ItemId);
  if not Assigned(Item) then Exit;

  if Model.RecycleBin.RestoreItem(Item, Model.User.Id) then
  begin
    FChanged := True;
    LoadItems;
  end;
end;

procedure TdlgRecycleBin.btnPurgeClick(Sender: TObject);
var
  LI: TListItem;
  Item: TItem;
  ItemId: Integer;
begin
  LI := lvItems.Selected;
  if not Assigned(LI) then Exit;

  if MessageDlg('Permanently delete this item? This cannot be undone.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  ItemId := Integer(LI.Data);
  Item := Model.Items.GetItem(ItemId);
  if not Assigned(Item) then Exit;

  if Model.RecycleBin.PermanentlyDelete(Item, Model.User.Id) then
  begin
    FChanged := True;
    LoadItems;
  end
  else
  begin
    // Nothing was deleted. The list may be stale: reload it.
    LoadItems;
    MessageDlg('Nothing was deleted: this item (or an item inside it) was ' +
      'restored by someone else meanwhile, or is cited by a hypothesis that ' +
      'is in review or accepted.', mtInformation, [mbOK], 0);
  end;
end;

procedure TdlgRecycleBin.btnEmptyClick(Sender: TObject);
var
  KeptRootCount: Integer;
  Refused: Boolean;
  Ok: Boolean;
begin
  if MessageDlg('Permanently delete ALL items in the recycle bin? This cannot be undone.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Ok := Model.RecycleBin.EmptyBin(Model.User.Id, KeptRootCount, Refused);
  // Reload in both outcomes: even a False result may have purged everything
  // unrelated to the kept (guarded) subtrees (R1).
  FChanged := True;
  LoadItems;
  if Ok then
    Exit;
  if Refused then
    // Race path: between the walk and the purge another session restored a
    // binned item, or moved a hypothesis citing one to review/accepted, and
    // the purge (one transaction) rolled back - nothing at all was deleted.
    MessageDlg('Nothing was deleted: while the bin was being emptied, one ' +
      'of its items was restored, or a hypothesis citing one of them was ' +
      'submitted for review or accepted. Please try again.',
      mtInformation, [mbOK], 0)
  else
    MessageDlg(Format('%d item(s) were kept because a hypothesis in review ' +
      'or accepted cites them.', [KeptRootCount]), mtInformation, [mbOK], 0);
end;

class function TdlgRecycleBin.ShowRecycleBin: Boolean;
var
  Dlg: TdlgRecycleBin;
begin
  Dlg := TdlgRecycleBin.Create(Application);
  try
    Dlg.FChanged := False;
    Dlg.LoadItems;
    Dlg.ShowModal;
    Result := Dlg.FChanged;
  finally
    Dlg.Free;
  end;
end;

end.
