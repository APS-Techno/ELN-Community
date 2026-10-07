unit dlg_UnitConverter;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls,
  RzCommon, RzLabel, RzButton, RzPanel, RzEdit,
  unit_UnitConverter;

type
  TdlgUnitConverter = class(TForm)
    lblCategory: TRzLabel;
    cmbCategory: TComboBox;
    edFrom:    TRzEdit;
    cmbFrom:   TComboBox;
    lblEquals: TRzLabel;
    edTo:      TRzEdit;
    cmbTo:     TComboBox;
    pnlBottom: TRzPanel;
    btnApply:  TRzButton;
    btnClose:  TRzButton;
    procedure cmbCategoryChange(Sender: TObject);
    procedure edFromChange(Sender: TObject);
    procedure edToChange(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
  private
    FUpdating:     Boolean;
    FApplyMode:    Boolean;
    FResultValue:  Double;
    FResultUnit:   string;

    procedure PopulateCategories;
    procedure PopulateUnits;
    procedure ConvertForward;
    procedure ConvertReverse;
  public
    class procedure ShowConverter;
    class function ConvertValue(const CurrentUnit: string;
      CurrentValue: Double; out ResultValue: Double;
      out ResultUnit: string): Boolean;
  end;

implementation

{$R *.dfm}

{ TdlgUnitConverter }

procedure TdlgUnitConverter.PopulateCategories;
var
  Cats: TArray<string>;
  Cat:  string;
begin
  cmbCategory.Items.BeginUpdate;
  try
    cmbCategory.Items.Clear;
    Cats := TUnitConverter.GetCategories;
    for Cat in Cats do
      cmbCategory.Items.Add(Cat);
    if cmbCategory.Items.Count > 0 then
      cmbCategory.ItemIndex := 0;
  finally
    cmbCategory.Items.EndUpdate;
  end;
end;

procedure TdlgUnitConverter.PopulateUnits;
var
  Units: TArray<string>;
  U:     string;
  Cat:   string;
begin
  if cmbCategory.ItemIndex < 0 then
    Exit;

  Cat := cmbCategory.Items[cmbCategory.ItemIndex];
  Units := TUnitConverter.GetUnits(Cat);

  cmbFrom.Items.BeginUpdate;
  cmbTo.Items.BeginUpdate;
  try
    cmbFrom.Items.Clear;
    cmbTo.Items.Clear;
    for U in Units do
    begin
      cmbFrom.Items.Add(U);
      cmbTo.Items.Add(U);
    end;
    if cmbFrom.Items.Count > 0 then
      cmbFrom.ItemIndex := 0;
    if cmbTo.Items.Count > 1 then
      cmbTo.ItemIndex := 1
    else if cmbTo.Items.Count > 0 then
      cmbTo.ItemIndex := 0;
  finally
    cmbFrom.Items.EndUpdate;
    cmbTo.Items.EndUpdate;
  end;
end;

procedure TdlgUnitConverter.ConvertForward;
var
  V:        Double;
  FromUnit: string;
  ToUnit:   string;
begin
  if FUpdating then
    Exit;
  if (cmbFrom.ItemIndex < 0) or (cmbTo.ItemIndex < 0) then
    Exit;
  if Trim(edFrom.Text) = '' then
  begin
    edTo.Text := '';
    Exit;
  end;
  if not TryStrToFloat(edFrom.Text, V) then
  begin
    edTo.Text := '';
    Exit;
  end;

  FromUnit := cmbFrom.Items[cmbFrom.ItemIndex];
  ToUnit   := cmbTo.Items[cmbTo.ItemIndex];

  FUpdating := True;
  try
    edTo.Text := FloatToStrF(
      TUnitConverter.Convert(V, FromUnit, ToUnit),
      ffGeneral, 10, 6);
  except
    edTo.Text := '';
  end;
  FUpdating := False;
end;

procedure TdlgUnitConverter.ConvertReverse;
var
  V:        Double;
  FromUnit: string;
  ToUnit:   string;
begin
  if FUpdating then
    Exit;
  if (cmbFrom.ItemIndex < 0) or (cmbTo.ItemIndex < 0) then
    Exit;
  if Trim(edTo.Text) = '' then
  begin
    edFrom.Text := '';
    Exit;
  end;
  if not TryStrToFloat(edTo.Text, V) then
  begin
    edFrom.Text := '';
    Exit;
  end;

  FromUnit := cmbTo.Items[cmbTo.ItemIndex];   // reverse: To becomes the source
  ToUnit   := cmbFrom.Items[cmbFrom.ItemIndex];

  FUpdating := True;
  try
    edFrom.Text := FloatToStrF(
      TUnitConverter.Convert(V, FromUnit, ToUnit),
      ffGeneral, 10, 6);
  except
    edFrom.Text := '';
  end;
  FUpdating := False;
end;

{ Event handlers }

procedure TdlgUnitConverter.cmbCategoryChange(Sender: TObject);
begin
  FUpdating := True;
  try
    PopulateUnits;
    edFrom.Text := '';
    edTo.Text   := '';
  finally
    FUpdating := False;
  end;
end;

procedure TdlgUnitConverter.edFromChange(Sender: TObject);
begin
  ConvertForward;
end;

procedure TdlgUnitConverter.edToChange(Sender: TObject);
begin
  ConvertReverse;
end;

procedure TdlgUnitConverter.btnApplyClick(Sender: TObject);
var
  V: Double;
begin
  if (cmbTo.ItemIndex < 0) or not TryStrToFloat(edTo.Text, V) then
    Exit;
  FResultValue := V;
  FResultUnit  := cmbTo.Items[cmbTo.ItemIndex];
  ModalResult  := mrOk;
end;

{ Public class methods }

class procedure TdlgUnitConverter.ShowConverter;
var
  Dialog: TdlgUnitConverter;
begin
  Dialog := TdlgUnitConverter.Create(nil);
  try
    Dialog.PopulateCategories;
    Dialog.PopulateUnits;
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

class function TdlgUnitConverter.ConvertValue(const CurrentUnit: string;
  CurrentValue: Double; out ResultValue: Double;
  out ResultUnit: string): Boolean;
var
  Dialog: TdlgUnitConverter;
  Cat:    string;
  I:      Integer;
begin
  Result := False;
  ResultValue := CurrentValue;
  ResultUnit  := CurrentUnit;

  Dialog := TdlgUnitConverter.Create(nil);
  try
    Dialog.PopulateCategories;

    // Pre-select the category that matches CurrentUnit
    Cat := TUnitConverter.GetCategoryForUnit(CurrentUnit);
    if Cat <> '' then
    begin
      for I := 0 to Dialog.cmbCategory.Items.Count - 1 do
        if Dialog.cmbCategory.Items[I] = Cat then
        begin
          Dialog.cmbCategory.ItemIndex := I;
          Break;
        end;
    end;

    Dialog.PopulateUnits;

    // Pre-select CurrentUnit in cmbFrom
    if CurrentUnit <> '' then
    begin
      for I := 0 to Dialog.cmbFrom.Items.Count - 1 do
        if Dialog.cmbFrom.Items[I] = CurrentUnit then
        begin
          Dialog.cmbFrom.ItemIndex := I;
          Break;
        end;
    end;

    // Pre-fill the From value and run an initial conversion
    Dialog.edFrom.Text := FloatToStrF(CurrentValue, ffGeneral, 10, 6);
    Dialog.ConvertForward;

    // Show Apply button in apply mode
    Dialog.FApplyMode := True;
    Dialog.btnApply.Visible := True;

    if Dialog.ShowModal = mrOk then
    begin
      ResultValue := Dialog.FResultValue;
      ResultUnit  := Dialog.FResultUnit;
      Result := True;
    end;
  finally
    Dialog.Free;
  end;
end;

end.
