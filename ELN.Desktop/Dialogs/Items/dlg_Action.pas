
unit dlg_Action;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, RzCmboBx, Vcl.ComCtrls, Vcl.Mask,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel, Vcl.ValEdit,
  unit_DlgConstants, unit_ItemTypes, unit_Item,
  unit_ActionType, unit_ValueType, unit_ActionDialogVM, Vcl.Grids;

type
  TdlgAction = class(TForm)
    RzPanel2: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    RzPanel1: TRzPanel;
    lblTitle: TRzLabel;
    lblItemType: TRzLabel;
    lblActionType: TRzLabel;
    lblEquipment: TRzLabel;
    lblDescription: TRzLabel;
    cbItemType: TRzComboBox;
    cbActionType: TRzComboBox;
    cbEquipment: TRzComboBox;
    edTitle: TRzEdit;
    edComment: TRzEdit;
    btnAddActionType: TRzButton;
    btnAddEquipment: TRzButton;
    pcDetails: TPageControl;
    tsValues: TTabSheet;
    pnlValueButtons: TRzPanel;
    btnAddValue: TRzButton;
    btnEditValue: TRzButton;
    btnDeleteValue: TRzButton;
    pnlValueSource: TRzPanel;
    lblValueSource: TLabel;
    btnGoToFile: TRzButton;
    lvValues: TListView;
    tsProperties: TTabSheet;
    pnlPropButtons: TRzPanel;
    btnAddProp: TRzButton;
    btnRemoveProp: TRzButton;
    vleProps: TValueListEditor;
    procedure cbItemTypeChange(Sender: TObject);
    procedure cbActionTypeChange(Sender: TObject);
    procedure cbEquipmentChange(Sender: TObject);
    procedure btnAddValueClick(Sender: TObject);
    procedure btnEditValueClick(Sender: TObject);
    procedure btnDeleteValueClick(Sender: TObject);
    procedure lvValuesSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure lvValuesDblClick(Sender: TObject);
    procedure lvValuesKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure btnGoToFileClick(Sender: TObject);
    procedure btnAddActionTypeClick(Sender: TObject);
    procedure btnAddEquipmentClick(Sender: TObject);
    procedure btnAddPropClick(Sender: TObject);
    procedure btnRemovePropClick(Sender: TObject);
    procedure TextChanged(Sender: TObject);
    procedure PropertiesChanged(Sender: TObject; ACol, ARow: Integer;
      const Value: string);
  private
    FVM: TActionDialogVM;
    FSyncing: Boolean;
    FNavigateFileId: Int64;
    procedure SyncControlsFromVM(Sender: TObject);
    procedure RebuildItemTypeList;
    procedure RebuildActionTypeList;
    procedure RebuildEquipmentList;
    procedure RebuildValuesList;
    procedure UpdateValueSource;
    procedure UpdateTabCaptions;
    function SelectedValue: unit_Item.TValue;
    procedure RebuildPropertiesGrid;
    procedure CollectPropertiesJSON;
  public
    destructor Destroy; override;
  end;

  function ShowActionDialog(const Mode: TDlgMode; var Item: TItem;
    AllowedLevels: TItemLevels): boolean; overload;
  function ShowActionDialog(const Mode: TDlgMode; var Item: TItem;
    AllowedLevels: TItemLevels; out NavigateFileId: Int64): boolean; overload;
  function ShowQuickActionType(AItemType: TItemType;
    out ATitle: string; out AKind: TActionKind): Boolean;
  function ShowQuickEquipment(out AModel, AManufacturer, ALocation: string): Boolean;

implementation

uses
  unit_DataModel,
  System.Rtti,
  System.JSON,
  unit_DialogHelper,
  unit_ValueSource,
  dlg_Value;

{$R *.dfm}

function ShowActionDialog(const Mode: TDlgMode; var Item: TItem;
  AllowedLevels: TItemLevels; out NavigateFileId: Int64): boolean;
var
  ItemRef: TItem;
  Nav: Int64;
begin
  ItemRef := Item;
  Nav := 0;

  Result := ExecuteDialog(TdlgAction,
    procedure(Dialog: TForm)
    var
      D: TdlgAction;
      Noun: string;
    begin
      D := TdlgAction(Dialog);
      D.FVM := TActionDialogVM.Create(
        Model.ActionTypes, Model.Equipments, Model.Items, Model.User.Id);
      D.FVM.OnChanged := D.SyncControlsFromVM;

      case Mode of
        dmNew: D.FVM.LoadForNew(AllowedLevels);
        dmEdit: D.FVM.LoadForEdit(ItemRef, AllowedLevels);
      end;

      if D.FVM.Level = TItemLevel.Proc then
        Noun := 'procedure'
      else
        Noun := 'action';
      if Mode = dmNew then
        D.Caption := 'Add new ' + Noun
      else
        D.Caption := 'Edit ' + Noun;

      D.SyncControlsFromVM(nil);
    end,
    procedure(Dialog: TForm)
    var
      D: TdlgAction;
    begin
      D := TdlgAction(Dialog);
      D.FVM.Title := D.edTitle.Text;
      D.FVM.Description := D.edComment.Text;
      if D.FNavigateFileId > 0 then
        Nav := D.FNavigateFileId
      else
      begin
        D.CollectPropertiesJSON;
        D.FVM.ApplyTo(ItemRef);
      end;
      FreeAndNil(D.FVM);
    end
  );
  Result := Result and (Nav = 0);
  NavigateFileId := Nav;
end;
function ShowActionDialog(const Mode: TDlgMode; var Item: TItem;
  AllowedLevels: TItemLevels): boolean;
var
  Ignored: Int64;
begin
  Result := ShowActionDialog(Mode, Item, AllowedLevels, Ignored);
end;

destructor TdlgAction.Destroy;
begin
  FVM.Free;
  inherited;
end;

procedure TdlgAction.TextChanged(Sender: TObject);
begin
  if FSyncing or not Assigned(FVM) then Exit;
  FVM.Title := edTitle.Text;
  FVM.Description := edComment.Text;
  btnSave.Enabled := FVM.CanSave;
end;

procedure TdlgAction.PropertiesChanged(Sender: TObject; ACol, ARow: Integer;
  const Value: string);
begin
  if FSyncing or not Assigned(FVM) then Exit;
  CollectPropertiesJSON;
  UpdateTabCaptions;
end;


procedure TdlgAction.SyncControlsFromVM(Sender: TObject);
begin
  FSyncing := True;
  try
  RebuildItemTypeList;
  RebuildActionTypeList;
  btnAddActionType.Enabled := FVM.CanAddActionType;

  RebuildEquipmentList;
  btnAddEquipment.Enabled := FVM.CanAddEquipment;

  if edTitle.Text <> FVM.Title then
    edTitle.Text := FVM.Title;
  if edComment.Text <> FVM.Description then
    edComment.Text := FVM.Description;

  RebuildPropertiesGrid;
  RebuildValuesList;
  UpdateTabCaptions;

  btnSave.Enabled := FVM.CanSave;
  finally
    FSyncing := False;
  end;
end;

procedure TdlgAction.RebuildItemTypeList;
var
  I: Integer;
begin
  cbItemType.Items.BeginUpdate;
  try
    cbItemType.Items.Clear;
    for I := 0 to High(FVM.ItemTypes) do
      cbItemType.Items.AddObject(
        TRttiEnumerationType.GetName(FVM.ItemTypes[I]),
        TObject(Ord(FVM.ItemTypes[I])));
  finally
    cbItemType.Items.EndUpdate;
  end;
  cbItemType.ItemIndex := FVM.SelectedItemTypeIndex;
end;

procedure TdlgAction.RebuildActionTypeList;
var
  I: Integer;
begin
  cbActionType.Items.BeginUpdate;
  try
    cbActionType.Items.Clear;
    for I := 0 to FVM.ActionTypes.Count - 1 do
      cbActionType.Items.Add(FVM.ActionTypes[I].Title);
  finally
    cbActionType.Items.EndUpdate;
  end;
  cbActionType.ItemIndex := FVM.SelectedActionTypeIndex;
  cbActionType.Enabled := cbActionType.Items.Count > 0;
end;

procedure TdlgAction.RebuildEquipmentList;
var
  I: Integer;
begin
  cbEquipment.Items.BeginUpdate;
  try
    cbEquipment.Items.Clear;
    for I := 0 to FVM.Equipments.Count - 1 do
      cbEquipment.Items.Add(FVM.Equipments[I].Model);
  finally
    cbEquipment.Items.EndUpdate;
  end;
  cbEquipment.ItemIndex := FVM.SelectedEquipmentIndex;
  cbEquipment.Enabled := cbEquipment.Items.Count > 0;
end;

function TdlgAction.SelectedValue: unit_Item.TValue;
begin
  if Assigned(lvValues.Selected) then
    Result := unit_Item.TValue(lvValues.Selected.Data)
  else
    Result := nil;
end;

procedure TdlgAction.RebuildValuesList;
var
  I, PrevIndex: Integer;
  Row: TListItem;
begin
  if Assigned(lvValues.Selected) then
    PrevIndex := lvValues.Selected.Index
  else
    PrevIndex := -1;
  lvValues.Items.BeginUpdate;
  try
    lvValues.Items.Clear;
    if Assigned(FVM.Item) then
      for I := 0 to High(FVM.ValueRows) do
      begin
        Row := lvValues.Items.Add;
        Row.Caption := FVM.ValueRows[I].Quantity;
        Row.SubItems.Add(FVM.ValueRows[I].Value);
        Row.SubItems.Add(FVM.ValueRows[I].Kind);
        Row.SubItems.Add(FVM.ValueRows[I].Note);
        Row.Data := FVM.Item.Values[I];
      end;
    if (PrevIndex >= 0) and (PrevIndex < lvValues.Items.Count) then
      lvValues.ItemIndex := PrevIndex;
  finally
    lvValues.Items.EndUpdate;
  end;
  UpdateValueSource;
end;

procedure TdlgAction.UpdateValueSource;
var
  Val: unit_Item.TValue;
  Src: TValueSourceInfo;
  FileText: string;
begin
  Val := SelectedValue;
  btnEditValue.Enabled := Assigned(Val);
  btnDeleteValue.Enabled := Assigned(Val);
  btnGoToFile.Enabled := False;
  if not Assigned(Val) then
  begin
    lblValueSource.Caption := '';
    lblValueSource.Hint := '';
    Exit;
  end;
  Src := ReadSource(Val);
  lblValueSource.Hint := DescribeValueSource(Src, SourceFileName(Src.FileId));
  if Src.Kind = vskReader then
  begin
    FileText := SourceFileName(Src.FileId);
    if FileText = '' then
      FileText := Format('file %d', [Src.FileId]);
    lblValueSource.Caption := Format('Reader %s v%s, "%s", %s',
      [Src.ReaderId, Src.ReaderVersion, Src.KeyName, FileText]);
  end
  else
    lblValueSource.Caption := lblValueSource.Hint;
  btnGoToFile.Enabled := Src.FileId > 0;
end;
procedure TdlgAction.btnGoToFileClick(Sender: TObject);
var
  Val: unit_Item.TValue;
  Src: TValueSourceInfo;
begin
  Val := SelectedValue;
  if not Assigned(Val) then Exit;
  Src := ReadSource(Val);
  if Src.FileId <= 0 then Exit;
  if MessageDlg('Unsaved changes in this dialog will be discarded. Go to the file?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FNavigateFileId := Src.FileId;
  ModalResult := mrOk;
end;

procedure TdlgAction.RebuildPropertiesGrid;
var
  JSONObj: TJSONObject;
  I: Integer;
begin
  vleProps.Strings.Clear;
  if FVM.Properties <> '' then
  begin
    JSONObj := TJSONObject.ParseJSONValue(FVM.Properties) as TJSONObject;
    if Assigned(JSONObj) then
    try
      for I := 0 to JSONObj.Count - 1 do
        vleProps.InsertRow(
          JSONObj.Pairs[I].JsonString.Value,
          JSONObj.Pairs[I].JsonValue.Value, True);
    finally
      JSONObj.Free;
    end;
  end;
end;

procedure TdlgAction.CollectPropertiesJSON;
var
  JSONObj: TJSONObject;
  I: Integer;
  Key: string;
begin
  JSONObj := TJSONObject.Create;
  try
    for I := 0 to vleProps.Strings.Count - 1 do
    begin
      Key := vleProps.Strings.Names[I];
      if Key <> '' then
        JSONObj.AddPair(Key, vleProps.Strings.ValueFromIndex[I]);
    end;
    if JSONObj.Count > 0 then
      FVM.Properties := JSONObj.ToString
    else
      FVM.Properties := '';
  finally
    JSONObj.Free;
  end;
end;

procedure TdlgAction.UpdateTabCaptions;
var
  I, PropCount: Integer;
begin
  tsValues.Caption := Format('Values (%d)', [lvValues.Items.Count]);
  PropCount := 0;
  for I := 0 to vleProps.Strings.Count - 1 do
    if vleProps.Strings.Names[I] <> '' then
      Inc(PropCount);
  tsProperties.Caption := Format('Properties (%d)', [PropCount]);
end;


procedure TdlgAction.cbItemTypeChange(Sender: TObject);
begin
  if FSyncing then Exit;
  FVM.SetItemTypeIndex(cbItemType.ItemIndex);
end;

procedure TdlgAction.cbActionTypeChange(Sender: TObject);
begin
  if FSyncing then Exit;
  FVM.SetActionTypeIndex(cbActionType.ItemIndex);
end;

procedure TdlgAction.cbEquipmentChange(Sender: TObject);
begin
  if FSyncing then Exit;
  FVM.SetEquipmentIndex(cbEquipment.ItemIndex);
end;

procedure TdlgAction.lvValuesSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  if FSyncing then Exit;
  UpdateValueSource;
end;

procedure TdlgAction.lvValuesDblClick(Sender: TObject);
begin
  if Assigned(lvValues.Selected) then
    btnEditValueClick(Sender);
end;

procedure TdlgAction.lvValuesKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_DELETE) and Assigned(lvValues.Selected) then
  begin
    btnDeleteValueClick(Sender);
    Key := 0;
  end;
end;

procedure TdlgAction.btnAddValueClick(Sender: TObject);
var
  NewValue: unit_Item.TValue;
begin
  NewValue := unit_Item.TValue.Create;
  try
    if ShowValueDialog(dmNew, NewValue) then
      FVM.AddValue(NewValue.ValueType, NewValue.RecType, NewValue.Value,
        NewValue.Tol, NewValue.Description);
  finally
    NewValue.Free;
  end;
end;

procedure TdlgAction.btnEditValueClick(Sender: TObject);
var
  Val: unit_Item.TValue;
  Before: TValueFields;
begin
  Val := SelectedValue;
  if not Assigned(Val) then Exit;

  Before := TValueFields.Read(Val);
  if ShowValueDialog(dmEdit, Val) then
    FVM.ValueEdited(Val, Before);
end;

procedure TdlgAction.btnDeleteValueClick(Sender: TObject);
var
  Idx: Integer;
begin
  if not Assigned(lvValues.Selected) then Exit;
  Idx := lvValues.Selected.Index;

  if MessageDlg('Delete this value?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    FVM.DeleteValue(Idx);
end;


type
  TRequiredEdits = class(TComponent)
  private
    FEdits: TArray<TEdit>;
    FOk: TButton;
    procedure EditChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; const AEdits: TArray<TEdit>;
      AOk: TButton); reintroduce;
  end;

constructor TRequiredEdits.Create(AOwner: TComponent; const AEdits: TArray<TEdit>;
  AOk: TButton);
var
  Edit: TEdit;
begin
  inherited Create(AOwner);
  FEdits := AEdits;
  FOk := AOk;
  for Edit in FEdits do
    Edit.OnChange := EditChange;
  EditChange(nil);
end;

procedure TRequiredEdits.EditChange(Sender: TObject);
var
  Edit: TEdit;
begin
  for Edit in FEdits do
    if Trim(Edit.Text) = '' then
    begin
      FOk.Enabled := False;
      Exit;
    end;
  FOk.Enabled := True;
end;

function ShowQuickActionType(AItemType: TItemType;
  out ATitle: string; out AKind: TActionKind): Boolean;
var
  Frm: TForm;
  edTitle: TEdit;
  cbKind: TComboBox;
  lbl: TLabel;
  btnOk, btnCancel: TButton;
  Kind: TActionKind;
  ppi: Integer;

  function S(V: Integer): Integer;
  begin
    Result := MulDiv(V, ppi, 96);
  end;

begin
  Result := False;
  ppi := Screen.PixelsPerInch;
  Frm := TForm.CreateNew(Application);
  try
    Frm.Caption := 'Add Action Type';
    Frm.BorderStyle := bsDialog;
    Frm.Position := poMainFormCenter;
    Frm.ClientWidth := S(320);
    Frm.ClientHeight := S(160);
    Frm.Font.Name := 'Segoe UI';
    Frm.Font.Size := 9;

    lbl := TLabel.Create(Frm);
    lbl.Parent := Frm;
    lbl.SetBounds(S(12), S(12), S(60), S(20));
    lbl.Caption := 'Title:';

    edTitle := TEdit.Create(Frm);
    edTitle.Parent := Frm;
    edTitle.SetBounds(S(12), S(32), S(296), S(24));

    lbl := TLabel.Create(Frm);
    lbl.Parent := Frm;
    lbl.SetBounds(S(12), S(66), S(60), S(20));
    lbl.Caption := 'Kind:';

    cbKind := TComboBox.Create(Frm);
    cbKind.Parent := Frm;
    cbKind.SetBounds(S(12), S(86), S(296), S(24));
    cbKind.Style := csDropDownList;
    for Kind := Low(TActionKind) to High(TActionKind) do
      cbKind.Items.Add(TRttiEnumerationType.GetName(Kind));

    case AItemType of
      TItemType.Synthesis:        cbKind.ItemIndex := Ord(TActionKind.Synthesys);
      TItemType.Measurement:      cbKind.ItemIndex := Ord(TActionKind.Measurement);
      TItemType.Testing:          cbKind.ItemIndex := Ord(TActionKind.Testing);
      TItemType.Characterization: cbKind.ItemIndex := Ord(TActionKind.Analysis);
      TItemType.Computing:        cbKind.ItemIndex := Ord(TActionKind.Simulation);
    else
      cbKind.ItemIndex := Ord(TActionKind.Other);
    end;

    btnOk := TButton.Create(Frm);
    btnOk.Parent := Frm;
    btnOk.Caption := 'OK';
    btnOk.ModalResult := mrOk;
    btnOk.Default := True;
    btnOk.SetBounds(S(148), S(126), S(80), S(28));

    btnCancel := TButton.Create(Frm);
    btnCancel.Parent := Frm;
    btnCancel.Caption := 'Cancel';
    btnCancel.ModalResult := mrCancel;
    btnCancel.Cancel := True;
    btnCancel.SetBounds(S(232), S(126), S(80), S(28));

    lbl := TLabel.Create(Frm);
    lbl.Parent := Frm;
    lbl.SetBounds(S(12), S(132), S(130), S(20));
    lbl.Caption := 'Title is required.';

    TRequiredEdits.Create(Frm, [edTitle], btnOk);

    if Frm.ShowModal = mrOk then
    begin
      ATitle := Trim(edTitle.Text);
      AKind := TActionKind(cbKind.ItemIndex);
      Result := True;
    end;
  finally
    Frm.Free;
  end;
end;

function ShowQuickEquipment(out AModel, AManufacturer, ALocation: string): Boolean;
var
  Frm: TForm;
  edModel, edMfr, edLoc: TEdit;
  lbl: TLabel;
  btnOk, btnCancel: TButton;
  ppi: Integer;

  function S(V: Integer): Integer;
  begin
    Result := MulDiv(V, ppi, 96);
  end;

begin
  Result := False;
  ppi := Screen.PixelsPerInch;
  Frm := TForm.CreateNew(Application);
  try
    Frm.Caption := 'Add Equipment';
    Frm.BorderStyle := bsDialog;
    Frm.Position := poMainFormCenter;
    Frm.ClientWidth := S(320);
    Frm.ClientHeight := S(210);
    Frm.Font.Name := 'Segoe UI';
    Frm.Font.Size := 9;

    lbl := TLabel.Create(Frm);
    lbl.Parent := Frm;
    lbl.SetBounds(S(12), S(12), S(100), S(20));
    lbl.Caption := 'Model:';

    edModel := TEdit.Create(Frm);
    edModel.Parent := Frm;
    edModel.SetBounds(S(12), S(32), S(296), S(24));

    lbl := TLabel.Create(Frm);
    lbl.Parent := Frm;
    lbl.SetBounds(S(12), S(64), S(100), S(20));
    lbl.Caption := 'Manufacturer:';

    edMfr := TEdit.Create(Frm);
    edMfr.Parent := Frm;
    edMfr.SetBounds(S(12), S(84), S(296), S(24));

    lbl := TLabel.Create(Frm);
    lbl.Parent := Frm;
    lbl.SetBounds(S(12), S(116), S(100), S(20));
    lbl.Caption := 'Location:';

    edLoc := TEdit.Create(Frm);
    edLoc.Parent := Frm;
    edLoc.SetBounds(S(12), S(136), S(296), S(24));

    btnOk := TButton.Create(Frm);
    btnOk.Parent := Frm;
    btnOk.Caption := 'OK';
    btnOk.ModalResult := mrOk;
    btnOk.Default := True;
    btnOk.SetBounds(S(148), S(176), S(80), S(28));

    btnCancel := TButton.Create(Frm);
    btnCancel.Parent := Frm;
    btnCancel.Caption := 'Cancel';
    btnCancel.ModalResult := mrCancel;
    btnCancel.Cancel := True;
    btnCancel.SetBounds(S(232), S(176), S(80), S(28));

    lbl := TLabel.Create(Frm);
    lbl.Parent := Frm;
    lbl.SetBounds(S(12), S(182), S(130), S(20));
    lbl.Caption := 'All fields are required.';

    TRequiredEdits.Create(Frm, [edModel, edMfr, edLoc], btnOk);

    if Frm.ShowModal = mrOk then
    begin
      AModel := Trim(edModel.Text);
      AManufacturer := Trim(edMfr.Text);
      ALocation := Trim(edLoc.Text);
      Result := True;
    end;
  finally
    Frm.Free;
  end;
end;

procedure TdlgAction.btnAddActionTypeClick(Sender: TObject);
var
  ATitle: string;
  AKind: TActionKind;
begin
  if not FVM.CanAddActionType then Exit;

  if ShowQuickActionType(FVM.GetSelectedItemType, ATitle, AKind) then
    FVM.AddActionType(ATitle, AKind);
end;

procedure TdlgAction.btnAddEquipmentClick(Sender: TObject);
var
  AModel, AManufacturer, ALocation: string;
begin
  if not FVM.CanAddEquipment then Exit;

  if ShowQuickEquipment(AModel, AManufacturer, ALocation) then
    FVM.AddEquipment(AModel, AManufacturer, ALocation);
end;

procedure TdlgAction.btnAddPropClick(Sender: TObject);
begin
  vleProps.InsertRow('', '', True);
  CollectPropertiesJSON;
end;

procedure TdlgAction.btnRemovePropClick(Sender: TObject);
begin
  if (vleProps.Strings.Count > 0) and (vleProps.Row >= 1) then
    vleProps.DeleteRow(vleProps.Row);
  CollectPropertiesJSON;
end;

end.
