
unit dlg_Action;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, RzRadGrp, RzLstBox, Vcl.Mask,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel, Vcl.ValEdit,
  unit_DlgConstants, unit_ItemTypes, unit_Item,
  unit_ActionType, unit_ValueType, unit_ActionDialogVM, Vcl.Grids;

type
  TdlgAction = class(TForm)
    RzPanel2: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    RzPanel1: TRzPanel;
    RzLabel1: TRzLabel;
    RzLabel2: TRzLabel;
    RzLabel3: TRzLabel;
    RzLabel4: TRzLabel;
    RzLabel6: TRzLabel;
    rgLevel: TRzRadioGroup;
    lbItemType: TRzListBox;
    lbActionType: TRzListBox;
    lbEquipment: TRzListBox;
    edTitle: TRzEdit;
    edComment: TRzEdit;
    lblValues: TRzLabel;
    lbValues: TRzListBox;
    btnAddValue: TRzButton;
    btnEditValue: TRzButton;
    btnDeleteValue: TRzButton;
    btnAddActionType: TRzButton;
    btnAddEquipment: TRzButton;
    lblProperties: TRzLabel;
    btnAddProp: TRzButton;
    btnRemoveProp: TRzButton;
    vleProps: TValueListEditor;
    procedure rgLevelClick(Sender: TObject);
    procedure lbActionTypeClick(Sender: TObject);
    procedure lbItemTypeClick(Sender: TObject);
    procedure lbEquipmentClick(Sender: TObject);
    procedure btnAddValueClick(Sender: TObject);
    procedure btnEditValueClick(Sender: TObject);
    procedure btnDeleteValueClick(Sender: TObject);
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
    procedure SyncControlsFromVM(Sender: TObject);
    procedure RebuildLevelRadioGroup;
    procedure RebuildItemTypeList;
    procedure RebuildActionTypeList;
    procedure RebuildEquipmentList;
    procedure RebuildValuesList;
    procedure RebuildPropertiesGrid;
    procedure CollectPropertiesJSON;
  public
    destructor Destroy; override;
  end;

  function ShowActionDialog(const Mode: TDlgMode; var Item: TItem;
    AllowedLevels: TItemLevels): boolean;
  function ShowQuickActionType(AItemType: TItemType;
    out ATitle: string; out AKind: TActionKind): Boolean;
  function ShowQuickEquipment(out AModel, AManufacturer, ALocation: string): Boolean;

implementation

uses
  unit_DataModel,
  System.Rtti,
  System.JSON,
  unit_DialogHelper,
  dlg_Value;

{$R *.dfm}

function ShowActionDialog(const Mode: TDlgMode; var Item: TItem;
  AllowedLevels: TItemLevels): boolean;
var
  ItemRef: TItem;
begin
  ItemRef := Item;

  Result := ExecuteDialog(TdlgAction,
    procedure(Dialog: TForm)
    var
      D: TdlgAction;
    begin
      D := TdlgAction(Dialog);
      D.FVM := TActionDialogVM.Create(
        Model.ActionTypes, Model.Equipments, Model.Items, Model.User.Id);
      D.FVM.OnChanged := D.SyncControlsFromVM;

      case Mode of
        dmNew:
          begin
            D.Caption := 'Add new action';
            D.FVM.LoadForNew(AllowedLevels);
          end;
        dmEdit:
          begin
            D.Caption := 'Edit action';
            D.FVM.LoadForEdit(ItemRef, AllowedLevels);
          end;
      end;

      D.SyncControlsFromVM(nil);
    end,
    procedure(Dialog: TForm)
    var
      D: TdlgAction;
    begin
      D := TdlgAction(Dialog);
      D.FVM.Title := D.edTitle.Text;
      D.FVM.Description := D.edComment.Text;
      D.CollectPropertiesJSON;
      D.FVM.ApplyTo(ItemRef);
      FreeAndNil(D.FVM);
    end
  );
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
end;


procedure TdlgAction.SyncControlsFromVM(Sender: TObject);
begin
  FSyncing := True;
  try
  RebuildLevelRadioGroup;
  rgLevel.Enabled := False;

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

  lblValues.Visible := FVM.ShowValues;
  lbValues.Visible := FVM.ShowValues;
  btnAddValue.Visible := FVM.ShowValues;
  btnEditValue.Visible := FVM.ShowValues;
  btnDeleteValue.Visible := FVM.ShowValues;
  if FVM.ShowValues then
    RebuildValuesList;

  btnSave.Enabled := FVM.CanSave;
  finally
    FSyncing := False;
  end;
end;

procedure TdlgAction.RebuildLevelRadioGroup;
begin
  rgLevel.Items.Clear;
  if TItemLevel.Proc in FVM.AllowedLevels then
    rgLevel.Items.AddObject('Proc', TObject(Ord(TItemLevel.Proc)));
  if TItemLevel.Action in FVM.AllowedLevels then
    rgLevel.Items.AddObject('Action', TObject(Ord(TItemLevel.Action)));

  rgLevel.ItemIndex := -1;
  var I: Integer;
  for I := 0 to rgLevel.Items.Count - 1 do
    if TItemLevel(Integer(rgLevel.Items.Objects[I])) = FVM.Level then
    begin
      rgLevel.ItemIndex := I;
      Break;
    end;
end;

procedure TdlgAction.RebuildItemTypeList;
var
  I: Integer;
begin
  lbItemType.Items.Clear;
  for I := 0 to High(FVM.ItemTypes) do
    lbItemType.Items.AddObject(
      TRttiEnumerationType.GetName(FVM.ItemTypes[I]),
      TObject(Ord(FVM.ItemTypes[I])));
  lbItemType.ItemIndex := FVM.SelectedItemTypeIndex;
end;

procedure TdlgAction.RebuildActionTypeList;
var
  I: Integer;
begin
  lbActionType.Items.Clear;
  for I := 0 to FVM.ActionTypes.Count - 1 do
    lbActionType.Items.Add(FVM.ActionTypes[I].Title);
  lbActionType.ItemIndex := FVM.SelectedActionTypeIndex;
end;

procedure TdlgAction.RebuildEquipmentList;
var
  I: Integer;
begin
  lbEquipment.Items.Clear;
  for I := 0 to FVM.Equipments.Count - 1 do
    lbEquipment.Items.Add(FVM.Equipments[I].Model);
  lbEquipment.ItemIndex := FVM.SelectedEquipmentIndex;
end;

procedure TdlgAction.RebuildValuesList;
var
  I: Integer;
begin
  lbValues.Items.Clear;
  if FVM.ShowValues and Assigned(FVM.Item) then
    for I := 0 to High(FVM.ValuesDisplay) do
      lbValues.Items.AddObject(FVM.ValuesDisplay[I], FVM.Item.Values[I]);
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


procedure TdlgAction.rgLevelClick(Sender: TObject);
begin
  if rgLevel.ItemIndex >= 0 then
    FVM.SetLevel(TItemLevel(Integer(rgLevel.Items.Objects[rgLevel.ItemIndex])));
end;

procedure TdlgAction.lbItemTypeClick(Sender: TObject);
begin
  FVM.SetItemTypeIndex(lbItemType.ItemIndex);
end;

procedure TdlgAction.lbActionTypeClick(Sender: TObject);
begin
  FVM.SetActionTypeIndex(lbActionType.ItemIndex);
end;

procedure TdlgAction.lbEquipmentClick(Sender: TObject);
begin
  FVM.SetEquipmentIndex(lbEquipment.ItemIndex);
end;

procedure TdlgAction.btnAddValueClick(Sender: TObject);
var
  NewValue: unit_Item.TValue;
begin
  if not FVM.ShowValues then Exit;

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
  Idx: Integer;
  Val: unit_Item.TValue;
  Before: TValueFields;
begin
  Idx := lbValues.ItemIndex;
  if (Idx < 0) or not FVM.ShowValues then Exit;

  Val := unit_Item.TValue(lbValues.Items.Objects[Idx]);
  Before := TValueFields.Read(Val);
  if ShowValueDialog(dmEdit, Val) then
    FVM.ValueEdited(Val, Before);
end;

procedure TdlgAction.btnDeleteValueClick(Sender: TObject);
begin
  if (lbValues.ItemIndex < 0) or not FVM.ShowValues then Exit;

  if MessageDlg('Delete this value?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    FVM.DeleteValue(lbValues.ItemIndex);
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
