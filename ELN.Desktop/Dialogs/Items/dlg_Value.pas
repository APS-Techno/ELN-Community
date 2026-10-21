unit dlg_Value;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Mask,
  RzEdit, RzLabel, RzButton, Vcl.ExtCtrls, RzPanel, RzRadGrp,
  System.Generics.Collections,
  unit_DlgConstants, unit_ItemTypes, unit_Item, unit_ValueType, unit_ValueSource;

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
    lblSource: TRzLabel;
    procedure btnConvertClick(Sender: TObject);
    procedure lbCategoryClick(Sender: TObject);
    procedure lbValueTypeClick(Sender: TObject);
    procedure edValueChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FValueTypes: TList<TValueType>;
    FFilteredIndices: TArray<Integer>;
    FToleranceFactor: Double;
    FEditMode: Boolean;
    FLoadedValue: Double;
    FLoadedTolerance: Double;
    FLoadedValueText: string;
    FLoadedToleranceText: string;
    FLoadedUnits: string;
    procedure PopulateValueTypes;
    procedure UpdateBaseValueHint;
    function GetSelectedValueType: TValueType;
    function TryReadValue(out ValueType: TValueType; out Value: Double): Boolean;
    function TryReadInput(out ValueType: TValueType;
      out Value, Tolerance: Double): Boolean;
    function ConfirmIssues(ValueType: TValueType; Value, Tolerance: Double): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Owns the list, not the managed value-type entities.
    procedure LoadValueTypes(ValueTypes: TList<TValueType>);
    procedure LoadValue(Value: TValue; const SourceFileName: string);
    procedure ApplyTo(Value: TValue);
    property ToleranceFactor: Double read FToleranceFactor write FToleranceFactor;
  end;

  TValueIssueConfirmation = reference to function(const Question: string): Boolean;

  function ShowValueDialog(const Mode: TDlgMode; var AValue: TValue): Boolean;
  function DescribeValueSource(const Source: TValueSourceInfo;
    const FileName: string): string;
  function SourceFileName(FileId: Int64): string;

var
  // Replaceable so tests can answer without a modal message box.
  ConfirmValueIssues: TValueIssueConfirmation;

implementation

uses
  unit_DataModel,
  unit_DialogHelper,
  unit_UnitConverter,
  unit_ValueTypeModel,
  unit_ValueTypeCategories,
  unit_ValueChecks,
  dlg_UnitConverter;

{$R *.dfm}

function DefaultConfirmValueIssues(const Question: string): Boolean;
begin
  Result := MessageDlg(Question, mtWarning, [mbYes, mbNo], 0, mbNo) = mrYes;
end;

function DescribeValueSource(const Source: TValueSourceInfo;
  const FileName: string): string;
var
  FileText: string;
begin
  FileText := '';
  if Source.FileId > 0 then
    if FileName <> '' then
      FileText := Format('%s (file %d)', [FileName, Source.FileId])
    else
      FileText := Format('file %d', [Source.FileId]);
  case Source.Kind of
    vskReader:
      Result := Format('Source: reader %s, version %s, key "%s", %s',
        [Source.ReaderId, Source.ReaderVersion, Source.KeyName, FileText]);
    vskManual:
      begin
        Result := 'Source: manual entry';
        if FileText <> '' then
          Result := Result + ', ' + FileText;
        if Source.Note <> '' then
          Result := Result + ' - ' + Source.Note;
      end;
    vskDerived:
      Result := Format('Source: derived by %s version %d',
        [Source.FormulaId, Source.FormulaVersion]);
  else
    Result := 'Source: unknown (recorded before value sources)';
  end;
end;

function DerivedInputsText(Value: TValue): string;
var
  Link: TDerivedValueInput;
begin
  Result := '';
  for Link in Value.DerivedInputs do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format('%s = value %d', [Link.Role, Link.InputValueId]);
  end;
  if Result <> '' then
    Result := ' from ' + Result;
end;

function SourceFileName(FileId: Int64): string;
var
  AFile: unit_Item.TFile;
begin
  Result := '';
  if FileId <= 0 then
    Exit;
  AFile := Model.Manager.Find<unit_Item.TFile>(FileId);
  if Assigned(AFile) then
    Result := AFile.FullName;
end;

function ShowValueDialog(const Mode: TDlgMode; var AValue: TValue): Boolean;
var
  ValueRef: TValue;
begin
  ValueRef := AValue;

  Result := ExecuteDialog(TdlgValue,
    procedure(Dialog: TForm)
    var
      D: TdlgValue;
    begin
      D := TdlgValue(Dialog);

      D.LoadValueTypes(Model.ValueTypes.GetTypes);
      D.ToleranceFactor := LoadToleranceFactor(Model.Manager);

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
            D.lblSource.Caption := 'Source: manual entry';
          end;
        dmEdit:
          begin
            D.Caption := 'Edit Value';
            D.LoadValue(ValueRef,
              SourceFileName(ReadSource(ValueRef).FileId));
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

constructor TdlgValue.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FToleranceFactor := DEFAULT_TOLERANCE_FACTOR;
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

procedure TdlgValue.LoadValue(Value: TValue; const SourceFileName: string);
var
  I: Integer;
begin
  if Assigned(Value.ValueType) and
     (Value.ValueType.CatID >= 0) and
     (Value.ValueType.CatID < ValueTypeCategories.Count) then
    lbCategory.ItemIndex := Value.ValueType.CatID + 1
  else
    lbCategory.ItemIndex := 0;

  PopulateValueTypes;

  lbValueType.ItemIndex := -1;
  if Assigned(Value.ValueType) then
    for I := 0 to High(FFilteredIndices) do
      if FValueTypes[FFilteredIndices[I]].Id = Value.ValueType.Id then
      begin
        lbValueType.ItemIndex := I;
        Break;
      end;

  rgRecType.ItemIndex := Ord(Value.RecType);

  if Assigned(Value.ValueType) and (Value.ValueType.Units <> '') then
  begin
    edValue.Text := FormatSIValue(Value.Value, Value.ValueType.Units);
    FLoadedUnits := Value.ValueType.Units;
  end
  else
  begin
    edValue.Text := FloatToStr(Value.Value);
    FLoadedUnits := '';
  end;

  edTolerance.Text := FloatToStr(Value.Tol);
  edDescription.Text := Value.Description;

  FEditMode := True;
  FLoadedValue := Value.Value;
  FLoadedTolerance := Value.Tol;
  FLoadedValueText := edValue.Text;
  FLoadedToleranceText := edTolerance.Text;
  lblSource.Caption := DescribeValueSource(ReadSource(Value), SourceFileName);
  if Value.EffectiveSourceKind = vskDerived then
    lblSource.Caption := lblSource.Caption + DerivedInputsText(Value) +
      '. Editing the number makes it a manual entry.';
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
  // The edit fields show rounded numbers; untouched text keeps the stored
  // number exactly, so opening and saving neither alters a reader value nor
  // marks it as a hand edit.
  if FEditMode then
  begin
    if (edValue.Text = FLoadedValueText) and
       SameText(ValueType.Units, FLoadedUnits) then
      Value := FLoadedValue;
    if edTolerance.Text = FLoadedToleranceText then
      Tolerance := FLoadedTolerance;
  end;
end;

function TdlgValue.ConfirmIssues(ValueType: TValueType;
  Value, Tolerance: Double): Boolean;
var
  Issues: TValueIssues;
begin
  Issues := CheckValue(ValueType, Value, Tolerance, FToleranceFactor);
  if Issues = [] then
    Exit(True);
  Result := ConfirmValueIssues('Please check this value: ' +
    DescribeValueIssues(Issues, ValueType, Value, Tolerance, FToleranceFactor) +
    '.' + sLineBreak + sLineBreak + 'Store it anyway?');
end;

procedure TdlgValue.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  ValueType: TValueType;
  Value, Tolerance: Double;
begin
  if ModalResult = mrOk then
    CanClose := TryReadInput(ValueType, Value, Tolerance) and
      ConfirmIssues(ValueType, Value, Tolerance)
  else
    CanClose := True;
end;

procedure TdlgValue.ApplyTo(Value: TValue);
var
  ValueType: TValueType;
  ParsedValue, ParsedTolerance: Double;
  NumberChanged: Boolean;
begin
  // Parse everything before changing even one property of a managed record.
  if not TryReadInput(ValueType, ParsedValue, ParsedTolerance) then
    raise EConvertError.Create(lblBaseValue.Caption);
  NumberChanged := FEditMode and
    ((ParsedValue <> Value.Value) or (ParsedTolerance <> Value.Tol));
  Value.ValueType := ValueType;
  Value.RecType := TRecType(rgRecType.ItemIndex);
  Value.Value := ParsedValue;
  Value.Tol := ParsedTolerance;
  Value.Description := edDescription.Text;
  if NumberChanged then
    MarkManualEdit(Value);
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

initialization
  ConfirmValueIssues := DefaultConfirmValueIssues;

end.
