unit dlg_Value;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Mask,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel, RzRadGrp,
  System.Generics.Collections,
  unit_DlgConstants, unit_ItemTypes, unit_Item, unit_ValueType;

type
  TdlgValue = class(TForm)
    RzPanel2: TRzPanel;
    btnSave: TRzBitBtn;
    btnCancel: TRzBitBtn;
    RzPanel1: TRzPanel;
    lblCategory: TRzLabel;
    lblValueType: TRzLabel;
    lblRecType: TRzLabel;
    lblValue: TRzLabel;
    lblTolerance: TRzLabel;
    lblBaseValue: TRzLabel;
    lblDescription: TRzLabel;
    lbCategory: TListBox;
    lbValueType: TListBox;
    rgRecType: TRzRadioGroup;
    edValue: TRzEdit;
    edTolerance: TRzEdit;
    edDescription: TRzEdit;
    btnConvert: TRzButton;
    procedure btnConvertClick(Sender: TObject);
    procedure lbCategoryClick(Sender: TObject);
    procedure lbValueTypeClick(Sender: TObject);
    procedure edValueChange(Sender: TObject);
  private
    FValueTypes: TList<TValueType>;
    FFilteredIndices: TArray<Integer>;
    procedure PopulateValueTypes;
    procedure UpdateBaseValueHint;
    function GetSelectedValueType: TValueType;
  public
  end;

  function ShowValueDialog(const Mode: TDlgMode; var AValue: TValue): Boolean;

implementation

uses
  unit_DataModel,
  unit_DialogHelper,
  unit_UnitConverter,
  unit_ValueTypeModel,
  unit_ValueTypeCategories,
  dlg_UnitConverter;

{$R *.dfm}

function ShowValueDialog(const Mode: TDlgMode; var AValue: TValue): Boolean;
var
  ValueRef: TValue;
begin
  ValueRef := AValue;

  Result := ExecuteDialog(TdlgValue,
    // Setup
    procedure(Dialog: TForm)
    var
      D: TdlgValue;
      I: Integer;
    begin
      D := TdlgValue(Dialog);

      D.FValueTypes := Model.ValueTypes.GetTypes;

      // Populate categories
      D.lbCategory.Items.Clear;
      D.lbCategory.Items.Add('(All)');
      for I := 0 to ValueTypeCategories.Count - 1 do
        D.lbCategory.Items.Add(ValueTypeCategories[I]);

      case Mode of
        dmNew:
          begin
            D.Caption := 'Add Value';
            D.lbCategory.ItemIndex := 0;
            D.PopulateValueTypes;
            if D.lbValueType.Items.Count > 0 then
              D.lbValueType.ItemIndex := 0;
            D.rgRecType.ItemIndex := 0;
            D.edValue.Text := '';
            D.edTolerance.Text := '';
            D.edDescription.Text := '';
          end;
        dmEdit:
          begin
            D.Caption := 'Edit Value';

            // Auto-select category from current ValueType
            if Assigned(ValueRef.ValueType) and
               (ValueRef.ValueType.CatID >= 0) and
               (ValueRef.ValueType.CatID < ValueTypeCategories.Count) then
              D.lbCategory.ItemIndex := ValueRef.ValueType.CatID + 1
            else
              D.lbCategory.ItemIndex := 0;

            D.PopulateValueTypes;

            // Select the value type within filtered list
            D.lbValueType.ItemIndex := -1;
            if Assigned(ValueRef.ValueType) then
              for I := 0 to High(D.FFilteredIndices) do
                if D.FValueTypes[D.FFilteredIndices[I]].Id = ValueRef.ValueType.Id then
                begin
                  D.lbValueType.ItemIndex := I;
                  Break;
                end;

            D.rgRecType.ItemIndex := Ord(ValueRef.RecType);

            // Show value in natural form (e.g., "20 nm" instead of "2E-8")
            if Assigned(ValueRef.ValueType) and (ValueRef.ValueType.Units <> '') then
              D.edValue.Text := FormatSIValue(ValueRef.Value, ValueRef.ValueType.Units)
            else
              D.edValue.Text := FloatToStr(ValueRef.Value);

            D.edTolerance.Text := FloatToStr(ValueRef.Tol);
            D.edDescription.Text := ValueRef.Description;
          end;
      end;

      D.UpdateBaseValueHint;
    end,
    // Extract
    procedure(Dialog: TForm)
    var
      D: TdlgValue;
      VT: TValueType;
      BaseVal: Double;
    begin
      D := TdlgValue(Dialog);

      VT := D.GetSelectedValueType;
      if Assigned(VT) then
        ValueRef.ValueType := VT;

      ValueRef.RecType := TRecType(D.rgRecType.ItemIndex);

      // Parse value with unit conversion (e.g., "20 nm" -> 2e-8)
      if Assigned(VT) and ParseSIInput(D.edValue.Text, VT.Units, BaseVal) then
        ValueRef.Value := BaseVal
      else
        ValueRef.Value := StrToFloatDef(D.edValue.Text, 0);

      ValueRef.Tol := StrToFloatDef(D.edTolerance.Text, 0);
      ValueRef.Description := D.edDescription.Text;
    end
  );
end;

{ TdlgValue }

procedure TdlgValue.PopulateValueTypes;
var
  VT: TValueType;
  I, CatIdx, FilterCatID: Integer;
begin
  if FValueTypes = nil then
    Exit;

  lbValueType.Items.Clear;
  SetLength(FFilteredIndices, 0);

  CatIdx := lbCategory.ItemIndex;
  if CatIdx <= 0 then
    FilterCatID := -1  // "(All)" -- show all types
  else
    FilterCatID := CatIdx - 1;  // offset by 1 for "(All)" at index 0

  for I := 0 to FValueTypes.Count - 1 do
  begin
    VT := FValueTypes[I];
    if (FilterCatID >= 0) and (VT.CatID <> FilterCatID) then
      Continue;

    lbValueType.Items.Add(VT.Symbol + ' '#$2014' ' + VT.Title + ' (' + VT.Units + ')');
    SetLength(FFilteredIndices, Length(FFilteredIndices) + 1);
    FFilteredIndices[High(FFilteredIndices)] := I;
  end;

  if lbValueType.Items.Count > 0 then
    lbValueType.ItemIndex := 0;
end;

procedure TdlgValue.UpdateBaseValueHint;
var
  VT: TValueType;
  BaseVal: Double;
begin
  VT := GetSelectedValueType;
  if (VT = nil) or (Trim(edValue.Text) = '') then
  begin
    lblBaseValue.Caption := '';
    Exit;
  end;

  if ParseSIInput(edValue.Text, VT.Units, BaseVal) then
    lblBaseValue.Caption := '= ' + FormatSIValue(BaseVal, VT.Units)
  else
    lblBaseValue.Caption := '';
end;

function TdlgValue.GetSelectedValueType: TValueType;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := lbValueType.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FFilteredIndices)) then
    Result := FValueTypes[FFilteredIndices[Idx]];
end;

procedure TdlgValue.lbCategoryClick(Sender: TObject);
begin
  PopulateValueTypes;
  UpdateBaseValueHint;
end;

procedure TdlgValue.lbValueTypeClick(Sender: TObject);
begin
  UpdateBaseValueHint;
end;

procedure TdlgValue.edValueChange(Sender: TObject);
begin
  UpdateBaseValueHint;
end;

procedure TdlgValue.btnConvertClick(Sender: TObject);
var
  VT: TValueType;
  CurrentVal, ResultVal: Double;
  CurrentUnit, ResultUnit: string;
begin
  VT := GetSelectedValueType;
  if VT = nil then
  begin
    MessageDlg('Please select a value type first.', mtWarning, [mbOK], 0);
    Exit;
  end;

  CurrentUnit := VT.Units;

  // Parse current input (may contain units like "20 nm")
  if not ParseSIInput(edValue.Text, CurrentUnit, CurrentVal) then
    CurrentVal := StrToFloatDef(edValue.Text, 0);

  if TdlgUnitConverter.ConvertValue(CurrentUnit, CurrentVal,
    ResultVal, ResultUnit) then
  begin
    if ResultUnit = CurrentUnit then
      edValue.Text := FloatToStrF(ResultVal, ffGeneral, 10, 6)
    else
      edValue.Text := FloatToStrF(ResultVal, ffGeneral, 10, 6) + ' ' + ResultUnit;
  end;
end;

end.
