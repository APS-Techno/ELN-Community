unit dlg_TagManager;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Dialogs, Vcl.Graphics,
  unit_Tag;

type
  TdlgTagManager = class(TForm)
    pnlTop: TPanel;
    lblTitle: TLabel;
    lvTags: TListView;
    pnlBottom: TPanel;
    btnAddTag: TButton;
    btnEditTag: TButton;
    btnDeleteTag: TButton;
    btnClose: TButton;
    procedure btnAddTagClick(Sender: TObject);
    procedure btnEditTagClick(Sender: TObject);
    procedure btnDeleteTagClick(Sender: TObject);
    procedure lvTagsDblClick(Sender: TObject);
    procedure lvTagsCustomDrawSubItem(Sender: TCustomListView;
      Item: TListItem; SubItem: Integer; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure lvTagsItemChecked(Sender: TObject; Item: TListItem);
  private
    FItemId: Integer;
    FItemTitle: string;
    FChanged: Boolean;
    FLoading: Boolean;
    FAssignMode: Boolean;
    procedure ApplyMode;
    procedure LoadTags;
  public
    class procedure ShowTagManager(ItemId: Integer; const ItemTitle: string);
    class function ShowTagEditor: Boolean;
  end;

implementation

uses
  Winapi.CommCtrl,
  unit_DataModel;

{$R *.dfm}

function HexToColor(const S: string): TColor;
var
  Hex: string;
begin
  Hex := Trim(S);
  if (Length(Hex) > 0) and (Hex[1] = '#') then
    Hex := '$' + Copy(Hex, 2, Length(Hex) - 1);
  if Hex = '' then
    Result := clBlue
  else
    Result := TColor(StrToIntDef(Hex, Integer(clBlue)));
end;

const
  TagPalette: array[0..11] of TColor = (
    $C04000, $2A9F2A, $2222CC, $CC8800,
    $0066CC, $9933CC, $336699, $999900,
    $4466BB, $44AA44, $AA4488, $5588DD
  );

function NextUnusedColor(Tags: TTags): TColor;
var
  i: Integer;
  Tag: TTag;
  C: TColor;
  Used: Boolean;
begin
  for i := Low(TagPalette) to High(TagPalette) do
  begin
    C := TagPalette[i];
    Used := False;
    for Tag in Tags do
      if HexToColor(Tag.Color) = C then
      begin
        Used := True;
        Break;
      end;
    if not Used then
      Exit(C);
  end;
  Result := TagPalette[Tags.Count mod Length(TagPalette)];
end;


type
  TdlgTagInput = class(TForm)
  private
    edtName: TEdit;
    pnlColorSwatch: TPanel;
    FColor: TColor;
    procedure DoPickColor(Sender: TObject);
    procedure DoOK(Sender: TObject);
  public
    class function Execute(var AName: string; var AColor: TColor;
      const ATitle: string; AOwner: TComponent): Boolean;
  end;

procedure TdlgTagInput.DoPickColor(Sender: TObject);
var
  CD: TColorDialog;
begin
  CD := TColorDialog.Create(Self);
  try
    CD.Color := FColor;
    if CD.Execute then
    begin
      FColor := CD.Color;
      pnlColorSwatch.Color := FColor;
    end;
  finally
    CD.Free;
  end;
end;

procedure TdlgTagInput.DoOK(Sender: TObject);
begin
  if Trim(edtName.Text) = '' then
  begin
    edtName.SetFocus;
    Exit;
  end;
  ModalResult := mrOK;
end;

class function TdlgTagInput.Execute(var AName: string; var AColor: TColor;
  const ATitle: string; AOwner: TComponent): Boolean;

  function Sc(V: Integer): Integer;
  begin
    Result := MulDiv(V, Screen.PixelsPerInch, 96);
  end;

var
  Dlg: TdlgTagInput;
  lbl: TLabel;
  btn: TButton;
begin
  Dlg := TdlgTagInput.CreateNew(AOwner);
  try
    Dlg.Caption := ATitle;
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poMainFormCenter;
    Dlg.Width := Sc(300);
    Dlg.Height := Sc(150);
    Dlg.FColor := AColor;

    lbl := TLabel.Create(Dlg);
    lbl.Parent := Dlg;
    lbl.SetBounds(Sc(12), Sc(16), Sc(40), Sc(16));
    lbl.Caption := 'Name:';

    Dlg.edtName := TEdit.Create(Dlg);
    Dlg.edtName.Parent := Dlg;
    Dlg.edtName.SetBounds(Sc(60), Sc(13), Sc(218), Sc(22));
    Dlg.edtName.Text := AName;

    lbl := TLabel.Create(Dlg);
    lbl.Parent := Dlg;
    lbl.SetBounds(Sc(12), Sc(50), Sc(40), Sc(16));
    lbl.Caption := 'Color:';

    Dlg.pnlColorSwatch := TPanel.Create(Dlg);
    Dlg.pnlColorSwatch.Parent := Dlg;
    Dlg.pnlColorSwatch.SetBounds(Sc(60), Sc(46), Sc(30), Sc(24));
    Dlg.pnlColorSwatch.Color := AColor;
    Dlg.pnlColorSwatch.ParentBackground := False;
    Dlg.pnlColorSwatch.BevelOuter := bvLowered;

    btn := TButton.Create(Dlg);
    btn.Parent := Dlg;
    btn.Caption := 'Choose...';
    btn.SetBounds(Sc(100), Sc(46), Sc(80), Sc(24));
    btn.OnClick := Dlg.DoPickColor;

    btn := TButton.Create(Dlg);
    btn.Parent := Dlg;
    btn.Caption := 'OK';
    btn.Default := True;
    btn.SetBounds(Sc(120), Sc(86), Sc(75), Sc(25));
    btn.OnClick := Dlg.DoOK;

    btn := TButton.Create(Dlg);
    btn.Parent := Dlg;
    btn.Caption := 'Cancel';
    btn.Cancel := True;
    btn.ModalResult := mrCancel;
    btn.SetBounds(Sc(202), Sc(86), Sc(75), Sc(25));

    Result := Dlg.ShowModal = mrOK;
    if Result then
    begin
      AName := Trim(Dlg.edtName.Text);
      AColor := Dlg.FColor;
    end;
  finally
    Dlg.Free;
  end;
end;


procedure TdlgTagManager.ApplyMode;
begin
  if FAssignMode then
  begin
    Caption := 'Tags - ' + FItemTitle;
    lblTitle.Caption := 'Check tags to assign to "' + FItemTitle + '"';
  end
  else
  begin
    Caption := 'Tag Editor';
    lblTitle.Caption := 'Manage tags: add, edit, or delete';
  end;
  lvTags.Checkboxes := FAssignMode;
end;

procedure TdlgTagManager.LoadTags;
var
  AllTags, ItemTags: TTags;
  Tag, ItemTag: TTag;
  LI: TListItem;
  IsAssigned: Boolean;
begin
  FLoading := True;
  try
    lvTags.Items.BeginUpdate;
    try
      lvTags.Items.Clear;
      AllTags := Model.Tags.GetAllTags;
      if FAssignMode then
        ItemTags := Model.Tags.GetTagsForItem(FItemId)
      else
        ItemTags := nil;
      try
        for Tag in AllTags do
        begin
          LI := lvTags.Items.Add;
          LI.Caption := Tag.Name;
          LI.SubItems.Add(Tag.Color);
          LI.Data := Pointer(Tag.Id);

          if FAssignMode and Assigned(ItemTags) then
          begin
            IsAssigned := False;
            for ItemTag in ItemTags do
              if ItemTag.Id = Tag.Id then
              begin
                IsAssigned := True;
                Break;
              end;
            LI.Checked := IsAssigned;
          end;
        end;
      finally
        AllTags.Free;
        ItemTags.Free;
      end;
    finally
      lvTags.Items.EndUpdate;
    end;
  finally
    FLoading := False;
  end;
end;

procedure TdlgTagManager.lvTagsCustomDrawSubItem(Sender: TCustomListView;
  Item: TListItem; SubItem: Integer; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  R, SwatchR: TRect;
  C: TColor;
  Inset: Integer;
begin
  if SubItem <> 1 then Exit;

  DefaultDraw := False;

  R.Top := SubItem;
  R.Left := LVIR_BOUNDS;
  SendMessage(lvTags.Handle, LVM_GETSUBITEMRECT, Item.Index, LPARAM(@R));

  if cdsSelected in State then
    lvTags.Canvas.Brush.Color := clHighlight
  else
    lvTags.Canvas.Brush.Color := lvTags.Color;
  lvTags.Canvas.FillRect(R);

  SwatchR := R;
  Inset := MulDiv(4, Screen.PixelsPerInch, 96);
  InflateRect(SwatchR, -Inset, -MulDiv(2, Screen.PixelsPerInch, 96));

  if (Item.SubItems.Count > 0) and (Item.SubItems[0] <> '') then
    C := HexToColor(Item.SubItems[0])
  else
    C := clSilver;

  lvTags.Canvas.Brush.Color := C;
  lvTags.Canvas.Pen.Color := clGray;
  lvTags.Canvas.Rectangle(SwatchR);
end;

procedure TdlgTagManager.lvTagsItemChecked(Sender: TObject; Item: TListItem);
var
  TagId: Integer;
begin
  if FLoading or not FAssignMode then Exit;

  TagId := Integer(Item.Data);
  if Item.Checked then
    Model.Tags.AssignTag(FItemId, TagId)
  else
    Model.Tags.UnassignTag(FItemId, TagId);
  FChanged := True;
end;

procedure TdlgTagManager.btnAddTagClick(Sender: TObject);
var
  TagName, ColorStr: string;
  TagColor: TColor;
  AllTags: TTags;
begin
  TagName := '';
  AllTags := Model.Tags.GetAllTags;
  try
    TagColor := NextUnusedColor(AllTags);
  finally
    AllTags.Free;
  end;
  if not TdlgTagInput.Execute(TagName, TagColor, 'New Tag', Self) then Exit;

  ColorStr := Format('#%.6x', [ColorToRGB(TagColor)]);
  Model.Tags.AddTag(TagName, ColorStr, Model.User.Id);
  FChanged := True;
  LoadTags;
end;

procedure TdlgTagManager.btnEditTagClick(Sender: TObject);
var
  LI: TListItem;
  TagId: Integer;
  Tag: TTag;
  NewName: string;
  TagColor: TColor;
begin
  LI := lvTags.Selected;
  if not Assigned(LI) then Exit;

  TagId := Integer(LI.Data);
  Tag := Model.Tags.GetTag(TagId);
  if not Assigned(Tag) then Exit;

  NewName := Tag.Name;
  TagColor := HexToColor(Tag.Color);
  if not TdlgTagInput.Execute(NewName, TagColor, 'Edit Tag', Self) then Exit;

  Tag.Name := NewName;
  Tag.Color := Format('#%.6x', [ColorToRGB(TagColor)]);
  Model.Tags.UpdateTag(Tag);
  FChanged := True;
  LoadTags;
end;

procedure TdlgTagManager.btnDeleteTagClick(Sender: TObject);
var
  LI: TListItem;
  TagId: Integer;
begin
  LI := lvTags.Selected;
  if not Assigned(LI) then Exit;

  TagId := Integer(LI.Data);
  if MessageDlg('Delete tag "' + LI.Caption + '"? This will remove it from all items.',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    Model.Tags.DeleteTag(TagId);
    FChanged := True;
    LoadTags;
  end;
end;

procedure TdlgTagManager.lvTagsDblClick(Sender: TObject);
begin
  if Assigned(lvTags.Selected) then
    btnEditTagClick(Sender);
end;

class procedure TdlgTagManager.ShowTagManager(ItemId: Integer;
  const ItemTitle: string);
var
  Dlg: TdlgTagManager;
begin
  Dlg := TdlgTagManager.Create(Application);
  try
    Dlg.FItemId := ItemId;
    Dlg.FItemTitle := ItemTitle;
    Dlg.FChanged := False;
    Dlg.FAssignMode := True;
    Dlg.ApplyMode;
    Dlg.LoadTags;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

class function TdlgTagManager.ShowTagEditor: Boolean;
var
  Dlg: TdlgTagManager;
begin
  Dlg := TdlgTagManager.Create(Application);
  try
    Dlg.FItemId := 0;
    Dlg.FItemTitle := '';
    Dlg.FChanged := False;
    Dlg.FAssignMode := False;
    Dlg.ApplyMode;
    Dlg.LoadTags;
    Dlg.ShowModal;
    Result := Dlg.FChanged;
  finally
    Dlg.Free;
  end;
end;

end.
