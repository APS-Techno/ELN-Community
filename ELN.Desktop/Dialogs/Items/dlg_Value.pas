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
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FValueTypes: TList<TValueType>;
    FFilteredIndices: TArray<Integer>;
    procedure PopulateValueTypes;
    procedure UpdateBaseValueHint;
    function GetSelectedValueType: TValueType;
    function TryReadValue(out ValueType: TValueType; out Value: Double): Boolean;
    function TryReadInput(out ValueType: TValueType;
      out Value, Tolerance: Double): Boolean;
  public
    destructor Destroy; override;
    // Owns the list, not the managed value-type entities.
    procedure LoadValueTypes(ValueTypes: TList<TValueType>);
    procedure ApplyTo(Value: TValue);
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
    procedure(Dialog: TForm)
    var
      D: TdlgValue;
      I: Integer;
    begin
      D := TdlgValue(Dialog);

      D.LoadValueTypes(Model.ValueTypes.GetTypes);

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

            if Assigned(ValueRef.ValueType) and
               (ValueRef.ValueType.CatID >= 0) and
               (ValueRef.ValueType.CatID < ValueTypeCategories.Count) then
              D.lbCategory.ItemIndex := ValueRef.ValueType.CatID + 1
            else
              D.lbCategory.ItemIndex := 0;

            D.PopulateValueTypes;

            D.lbValueType.ItemIndex := -1;
            if Assigned(ValueRef.ValueType) then
              for I := 0 to High(D.FFilteredIndices) do
                if D.FValueTypes[D.FFilteredIndices[I]].Id = ValueRef.ValueType.Id then
                begin
                  D.lbValueType.ItemIndex := I;
                  Break;
                end;

            D.rgRecType.ItemIndex := Ord(ValueRef.RecType);

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
    procedure(Dialog: TForm)
    begin
      TdlgValue(Dialog).ApplyTo(ValueRef);
    end
  );
end;


destructor TdlgValue.Destroy;
begin
  FValueTypes.Free;
  inherited;
end;

procedure TdlgValue.LoadValueTypes(ValueTypes: TList<TValueType>);
var
  I: Integer;
begin
  FValueTypes.Free;
  FValueTypes := ValueTypes;
  lbCategory.Items.Clear;
  lbCategory.Items.Add('(All)');
  for I := 0 to ValueTypeCategories.Count - 1 do
    lbCategory.Items.Add(ValueTypeCategories[I]);
  lbCategory.ItemIndex := 0;
  PopulateValueTypes;
end;

function TdlgValue.TryReadValue(out ValueType: TValueType;
  out Value: Double): Boolean;
begin
  Result := False;
  ValueType := GetSelectedValueType;
  if not Assigned(ValueType) then
  begin
    lblBaseValue.Caption := 'Please select a value type.';
    Exit;
  end;
  if not ParseSIInput(edValue.Text, ValueType.Units, Value) then
  begin
    lblBaseValue.Caption := 'Enter a valid number in units compatible with ' +
      ValueType.Units + '.';
    Exit;
  end;
  Result := True;
end;

function TdlgValue.TryReadInput(out ValueType: TValueType;
  out Value, Tolerance: Double): Boolean;
begin
  Result := TryReadValue(ValueType, Value);
  if not Result then Exit;
  Tolerance := 0;
  if (Trim(edTolerance.Text) <> '') and
     not TryStrToFloat(edTolerance.Text, Tolerance) then
  begin
    lblBaseValue.Caption := 'Enter a valid tolerance, or leave it blank.';
    Exit(False);
  end;
end;

procedure TdlgValue.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  ValueType: TValueType;
  Value, Tolerance: Double;
begin
  if ModalResult = mrOk then
    CanClose := TryReadInput(ValueType, Value, Tolerance)
  else
    CanClose := True;
end;

procedure TdlgValue.ApplyTo(Value: TValue);
var
  ValueType: TValueType;
  ParsedValue, ParsedTolerance: Double;
begin
  // Parse everything before changing even one property of a managed record.
  if not TryReadInput(ValueType, ParsedValue, ParsedTolerance) then
    raise EConvertError.Create(lblBaseValue.Caption);
  Value.ValueType := ValueType;
  Value.RecType := TRecType(rgRecType.ItemIndex);
  Value.Value := ParsedValue;
  Value.Tol := ParsedTolerance;
  Value.Description := edDescription.Text;
end;

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
    FilterCatID := -1  
  else
    FilterCatID := CatIdx - 1;  

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
  if not TryReadValue(VT, CurrentVal) then
    Exit;
  CurrentUnit := VT.Units;

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
