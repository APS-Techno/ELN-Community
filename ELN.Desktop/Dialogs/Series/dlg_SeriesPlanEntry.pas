unit dlg_SeriesPlanEntry;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzPanel, RzCommon,
  Aurelius.Engine.ObjectManager,
  unit_ValueType,
  unit_SeriesTable;

type
  TSeriesEntryKind = (sekFactor, sekFixed, sekResponse);

  TdlgSeriesPlanEntry = class(TForm)
    lblCategory: TLabel;
    lbCategory: TListBox;
    lblType: TLabel;
    lbType: TListBox;
    lblEntryLabel: TLabel;
    edEntryLabel: TEdit;
    lblFirst: TLabel;
    edFirst: TEdit;
    lblSecond: TLabel;
    edSecond: TEdit;
    lblConversion: TLabel;
    lblHint: TLabel;
    pnlButtons: TRzPanel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure btnOKClick(Sender: TObject);
    procedure lbCategoryClick(Sender: TObject);
    procedure lbTypeClick(Sender: TObject);
    procedure NumberChange(Sender: TObject);
  private
    FKind: TSeriesEntryKind;
    FTypes: TList<TValueType>;
    FTypeIds: TList<Integer>;
    FFirst, FSecond: Double;
    FHasFirst, FHasSecond: Boolean;
    FFirstCaption, FSecondCaption: string;
    procedure Prepare(AManager: TObjectManager; AKind: TSeriesEntryKind;
      const AUsed: TArray<Integer>; ATypeId: Integer);
    procedure PopulateTypes(ASelectId: Integer);
    procedure UpdateUnits;
    procedure UpdateConversion;
    function ReadNumber(AEdit: TEdit; ALabel: TLabel; ARequired, ADifference: Boolean;
      out AValue: Double; out AHasValue: Boolean): Boolean;
    function SelectedTypeId: Integer;
    function SelectedUnits: string;
  public
    destructor Destroy; override;
    class function ExecuteFactor(AManager: TObjectManager;
      const AUsed: TArray<Integer>; ALabelOnly: Boolean;
      var AFactor: TSeriesFactorSpec): Boolean; static;
    class function ExecuteFixed(AManager: TObjectManager;
      const AUsed: TArray<Integer>; var AFixed: TSeriesFixedSpec): Boolean; static;
    class function ExecuteResponse(AManager: TObjectManager;
      const AUsed: TArray<Integer>; var AResponse: TSeriesResponseSpec): Boolean; static;
  end;

implementation

{$R *.dfm}

uses
  System.Generics.Defaults,
  Aurelius.Types.Nullable,
  unit_ValueTypeCategories,
  unit_UnitConverter,
  unit_SeriesPlanInput;

destructor TdlgSeriesPlanEntry.Destroy;
begin
  FTypeIds.Free;
  FTypes.Free;
  inherited;
end;

function TdlgSeriesPlanEntry.SelectedTypeId: Integer;
begin
  if (lbType.ItemIndex >= 0) and (lbType.ItemIndex < FTypeIds.Count) then
    Result := FTypeIds[lbType.ItemIndex]
  else
    Result := 0;
end;

function TdlgSeriesPlanEntry.SelectedUnits: string;
var
  T: TValueType;
  Id: Integer;
begin
  Result := '';
  Id := SelectedTypeId;
  for T in FTypes do
    if T.Id = Id then
      Exit(T.Units);
end;

function OtherUnitExample(const AUnits: string): string;
var
  U: string;
begin
  Result := '';
  if (AUnits = '') or not TUnitConverter.UnitExists(AUnits) then
    Exit;
  for U in TUnitConverter.GetUnits(TUnitConverter.GetCategoryForUnit(AUnits)) do
    if U <> AUnits then
      Exit(U);
end;

procedure TdlgSeriesPlanEntry.UpdateUnits;
var
  Units: string;
begin
  Units := SelectedUnits;
  if Units = '' then
  begin
    lblFirst.Caption := FFirstCaption;
    lblSecond.Caption := FSecondCaption;
  end
  else
  begin
    lblFirst.Caption := FFirstCaption + ', ' + Units;
    lblSecond.Caption := FSecondCaption + ', ' + Units;
  end;
  UpdateConversion;
end;

procedure TdlgSeriesPlanEntry.UpdateConversion;
var
  Units, Example, Text: string;

  procedure Describe(AEdit: TEdit; const ACaption: string; ADifference: Boolean);
  var
    Value: Double;
    Error, Part: string;
  begin
    if not PlanQuantityHasOtherUnit(AEdit.Text, Units, FormatSettings) then
      Exit;
    if TryParsePlanQuantity(AEdit.Text, Units, ADifference, FormatSettings, Value, Error) then
      Part := Format('%s = %s %s', [ACaption.Replace(' (optional)', ''),
        SeriesNumberText(Value), Units])
    else
      Part := Error;
    if Text <> '' then
      Text := Text + sLineBreak;
    Text := Text + Part;
  end;

begin
  if FKind = sekResponse then
    Exit;
  Units := SelectedUnits;
  Text := '';
  Describe(edFirst, FFirstCaption, False);
  Describe(edSecond, FSecondCaption, FKind = sekFixed);
  if (Text = '') and (Units <> '') then
  begin
    Example := OtherUnitExample(Units);
    if Example <> '' then
      Text := Format('Numbers are in %s. You can also type another unit, ' +
        'for example 2 %s.', [Units, Example]);
  end;
  lblConversion.Caption := Text;
end;

procedure TdlgSeriesPlanEntry.lbTypeClick(Sender: TObject);
begin
  UpdateUnits;
end;

procedure TdlgSeriesPlanEntry.NumberChange(Sender: TObject);
begin
  UpdateConversion;
end;

procedure TdlgSeriesPlanEntry.PopulateTypes(ASelectId: Integer);
var
  T: TValueType;
  Text: string;
  CatId: Integer;
begin
  CatId := lbCategory.ItemIndex - 1;
  lbType.Items.BeginUpdate;
  try
    lbType.Items.Clear;
    FTypeIds.Clear;
    for T in FTypes do
    begin
      if (CatId >= 0) and (T.CatID <> CatId) then
        Continue;
      Text := T.Symbol + ' '#$2014' ' + T.Title;
      if T.Units <> '' then
        Text := Text + ' (' + T.Units + ')';
      lbType.Items.Add(Text);
      FTypeIds.Add(T.Id);
    end;
  finally
    lbType.Items.EndUpdate;
  end;
  lbType.ItemIndex := FTypeIds.IndexOf(ASelectId);
  if (lbType.ItemIndex < 0) and (lbType.Items.Count > 0) then
    lbType.ItemIndex := 0;
  UpdateUnits;
end;

procedure TdlgSeriesPlanEntry.lbCategoryClick(Sender: TObject);
begin
  PopulateTypes(SelectedTypeId);
end;

procedure TdlgSeriesPlanEntry.Prepare(AManager: TObjectManager;
  AKind: TSeriesEntryKind; const AUsed: TArray<Integer>; ATypeId: Integer);
var
  T: TValueType;
  I, Id: Integer;
  Skip: Boolean;
begin
  FKind := AKind;
  FTypeIds := TList<Integer>.Create;
  case AKind of
    sekFactor:
      begin
        Caption := 'Factor';
        lblFirst.Caption := 'Range minimum (optional)';
        lblSecond.Caption := 'Range maximum (optional)';
        lblHint.Caption := 'A factor is a parameter you vary. Points outside ' +
          'the range are refused. The label says which parameter it is, for ' +
          'example "Mo layer".';
      end;
    sekFixed:
      begin
        Caption := 'Fixed condition';
        lblFirst.Caption := 'Value';
        lblSecond.Caption := 'Tolerance (optional)';
        lblHint.Caption := 'A fixed condition is held constant. A deposition ' +
          'that differs by more than the tolerance is flagged. The label says ' +
          'which parameter it is, for example "Mo target".';
      end;
    sekResponse:
      begin
        Caption := 'Response';
        lblHint.Caption := 'A response is a result you measure on each point. ' +
          'The label says which result it is, for example "Total stack".';
        lblHint.Top := lblFirst.Top;
      end;
  end;
  FFirstCaption := lblFirst.Caption;
  FSecondCaption := lblSecond.Caption;
  lblFirst.Visible := AKind <> sekResponse;
  edFirst.Visible := AKind <> sekResponse;
  lblSecond.Visible := AKind <> sekResponse;
  edSecond.Visible := AKind <> sekResponse;
  lblConversion.Visible := AKind <> sekResponse;

  FTypes := AManager.Find<TValueType>.List;
  for I := FTypes.Count - 1 downto 0 do
  begin
    Skip := False;
    for Id in AUsed do
      if Id = FTypes[I].Id then
        Skip := True;
    if Skip then
      FTypes.Delete(I);
  end;
  FTypes.Sort(TComparer<TValueType>.Construct(
    function(const A, B: TValueType): Integer
    begin
      Result := CompareText(A.Title, B.Title);
    end));

  lbCategory.Items.Add('(All)');
  for I := 0 to ValueTypeCategories.Count - 1 do
    lbCategory.Items.Add(ValueTypeCategories[I]);
  lbCategory.ItemIndex := 0;
  for T in FTypes do
    if (T.Id = ATypeId) and (T.CatID >= 0) and
       (T.CatID < ValueTypeCategories.Count) then
      lbCategory.ItemIndex := T.CatID + 1;
  PopulateTypes(ATypeId);
end;

function TdlgSeriesPlanEntry.ReadNumber(AEdit: TEdit; ALabel: TLabel;
  ARequired, ADifference: Boolean; out AValue: Double; out AHasValue: Boolean): Boolean;
var
  Error: string;
begin
  AValue := 0;
  AHasValue := Trim(AEdit.Text) <> '';
  Result := True;
  if not AHasValue then
  begin
    if ARequired then
    begin
      MessageDlg(Format('Enter a number for "%s".', [ALabel.Caption]),
        mtWarning, [mbOK], 0);
      AEdit.SetFocus;
      Result := False;
    end;
    Exit;
  end;
  if not TryParsePlanQuantity(AEdit.Text, SelectedUnits, ADifference, FormatSettings,
    AValue, Error) then
  begin
    MessageDlg(Error, mtWarning, [mbOK], 0);
    AEdit.SetFocus;
    Result := False;
  end;
end;

procedure TdlgSeriesPlanEntry.btnOKClick(Sender: TObject);
begin
  if SelectedTypeId = 0 then
  begin
    MessageDlg('Pick a value type.', mtWarning, [mbOK], 0);
    lbType.SetFocus;
    Exit;
  end;
  if FKind <> sekResponse then
  begin
    if not ReadNumber(edFirst, lblFirst, FKind = sekFixed, False, FFirst, FHasFirst) then
      Exit;
    if not ReadNumber(edSecond, lblSecond, False, FKind = sekFixed, FSecond,
      FHasSecond) then
      Exit;
    if (FKind = sekFactor) and FHasFirst and FHasSecond and (FFirst > FSecond) then
    begin
      MessageDlg('The range minimum is above the maximum.', mtWarning, [mbOK], 0);
      edFirst.SetFocus;
      Exit;
    end;
    if (FKind = sekFixed) and FHasSecond and (FSecond < 0) then
    begin
      MessageDlg('The tolerance must be 0 or more.', mtWarning, [mbOK], 0);
      edSecond.SetFocus;
      Exit;
    end;
  end;
  ModalResult := mrOk;
end;

class function TdlgSeriesPlanEntry.ExecuteFactor(AManager: TObjectManager;
  const AUsed: TArray<Integer>; ALabelOnly: Boolean;
  var AFactor: TSeriesFactorSpec): Boolean;
var
  Dlg: TdlgSeriesPlanEntry;
begin
  Dlg := TdlgSeriesPlanEntry.Create(Application);
  try
    Dlg.Prepare(AManager, sekFactor, AUsed, AFactor.ValueTypeId);
    Dlg.edEntryLabel.Text := AFactor.EntryLabel;
    if AFactor.RangeMin.HasValue then
      Dlg.edFirst.Text := SeriesNumberText(AFactor.RangeMin.Value);
    if AFactor.RangeMax.HasValue then
      Dlg.edSecond.Text := SeriesNumberText(AFactor.RangeMax.Value);
    if ALabelOnly then
    begin
      Dlg.lbCategory.Enabled := False;
      Dlg.lbType.Enabled := False;
      Dlg.edFirst.Enabled := False;
      Dlg.edSecond.Enabled := False;
      Dlg.lblHint.Caption := 'The series has points, so only the label can change.';
    end;
    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      AFactor.ValueTypeId := Dlg.SelectedTypeId;
      AFactor.EntryLabel := Trim(Dlg.edEntryLabel.Text);
      if Dlg.FHasFirst then
        AFactor.RangeMin := Dlg.FFirst
      else
        AFactor.RangeMin := SNull;
      if Dlg.FHasSecond then
        AFactor.RangeMax := Dlg.FSecond
      else
        AFactor.RangeMax := SNull;
    end;
  finally
    Dlg.Free;
  end;
end;

class function TdlgSeriesPlanEntry.ExecuteFixed(AManager: TObjectManager;
  const AUsed: TArray<Integer>; var AFixed: TSeriesFixedSpec): Boolean;
var
  Dlg: TdlgSeriesPlanEntry;
begin
  Dlg := TdlgSeriesPlanEntry.Create(Application);
  try
    Dlg.Prepare(AManager, sekFixed, AUsed, AFixed.ValueTypeId);
    Dlg.edEntryLabel.Text := AFixed.EntryLabel;
    if AFixed.ValueTypeId <> 0 then
    begin
      Dlg.edFirst.Text := SeriesNumberText(AFixed.Value);
      if AFixed.Tol > 0 then
        Dlg.edSecond.Text := SeriesNumberText(AFixed.Tol);
    end;
    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      AFixed.ValueTypeId := Dlg.SelectedTypeId;
      AFixed.EntryLabel := Trim(Dlg.edEntryLabel.Text);
      AFixed.Value := Dlg.FFirst;
      if Dlg.FHasSecond then
        AFixed.Tol := Dlg.FSecond
      else
        AFixed.Tol := 0;
    end;
  finally
    Dlg.Free;
  end;
end;

class function TdlgSeriesPlanEntry.ExecuteResponse(AManager: TObjectManager;
  const AUsed: TArray<Integer>; var AResponse: TSeriesResponseSpec): Boolean;
var
  Dlg: TdlgSeriesPlanEntry;
begin
  Dlg := TdlgSeriesPlanEntry.Create(Application);
  try
    Dlg.Prepare(AManager, sekResponse, AUsed, AResponse.ValueTypeId);
    Dlg.edEntryLabel.Text := AResponse.EntryLabel;
    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      AResponse.ValueTypeId := Dlg.SelectedTypeId;
      AResponse.EntryLabel := Trim(Dlg.edEntryLabel.Text);
    end;
  finally
    Dlg.Free;
  end;
end;

end.
