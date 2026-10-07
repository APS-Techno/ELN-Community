unit frame_SelectFieldCard;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Samples.Spin,
  Vcl.Grids,
  RzLabel, RzEdit, RzButton,
  unit_TemplateSchema, unit_TemplateCard;

type
  TfrSelectFieldCard = class(TFrame, ITemplateCard)
    lblName: TRzLabel;
    edtName: TRzEdit;
    lblLabel: TRzLabel;
    edtLabel: TRzEdit;
    lblType: TRzLabel;
    cmbType: TComboBox;
    lblAutoFill: TRzLabel;
    cmbAutoFill: TComboBox;
    lblFlex: TRzLabel;
    spnFlex: TSpinEdit;
    lblOptions: TRzLabel;
    sgOptions: TStringGrid;
    btnOptAdd: TRzButton;
    btnOptRemove: TRzButton;
    procedure ControlChange(Sender: TObject);
    procedure cmbTypeChange(Sender: TObject);
    procedure sgOptionsSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
    procedure btnOptAddClick(Sender: TObject);
    procedure btnOptRemoveClick(Sender: TObject);
  private
    FUpdating: Boolean;
    FOnChanged: TNotifyEvent;
    FOnFieldTypeChanged: TFieldTypeChangedEvent;
    procedure LoadOptions(SN: TSchemaNode);
    procedure SaveOptions(SN: TSchemaNode);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromNode(SN: TSchemaNode);
    procedure SaveToNode(SN: TSchemaNode);
    procedure SetOnChanged(AHandler: TNotifyEvent);
    procedure SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
    function AsControl: TWinControl;
  end;

implementation

{$R *.dfm}

constructor TfrSelectFieldCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  PopulateFieldTypeCombo(cmbType.Items);
  PopulateAutoFillCombo(cmbAutoFill.Items);

  sgOptions.Cells[0, 0] := 'Value';
  sgOptions.Cells[1, 0] := 'Label';
  sgOptions.ColWidths[0] := 150;
  sgOptions.ColWidths[1] := 150;
end;

procedure TfrSelectFieldCard.LoadFromNode(SN: TSchemaNode);
var
  Idx: Integer;
begin
  if (SN = nil) or (SN.Kind <> snkField) then Exit;
  FUpdating := True;
  try
    edtName.Text := SN.FieldName;
    edtLabel.Text := SN.FieldLabel;
    Idx := cmbType.Items.IndexOf(SN.FieldType);
    if Idx >= 0 then cmbType.ItemIndex := Idx else cmbType.ItemIndex := 0;
    cmbAutoFill.Text := SN.AutoFill;
    spnFlex.Value := SN.Flex;
    LoadOptions(SN);
  finally
    FUpdating := False;
  end;
end;

procedure TfrSelectFieldCard.SaveToNode(SN: TSchemaNode);
begin
  if (SN = nil) or (SN.Kind <> snkField) then Exit;
  SN.FieldName := edtName.Text;
  SN.FieldLabel := edtLabel.Text;
  SN.FieldType := cmbType.Text;
  SN.AutoFill := cmbAutoFill.Text;
  SN.Flex := spnFlex.Value;
  SaveOptions(SN);
end;

procedure TfrSelectFieldCard.LoadOptions(SN: TSchemaNode);
var
  I: Integer;
begin
  sgOptions.RowCount := SN.Options.Count + 1;
  sgOptions.Cells[0, 0] := 'Value';
  sgOptions.Cells[1, 0] := 'Label';
  for I := 0 to SN.Options.Count - 1 do
  begin
    sgOptions.Cells[0, I + 1] := SN.Options[I].Value;
    sgOptions.Cells[1, I + 1] := SN.Options[I].Label_;
  end;
  if SN.Options.Count = 0 then
  begin
    sgOptions.RowCount := 2;
    sgOptions.Cells[0, 1] := '';
    sgOptions.Cells[1, 1] := '';
  end;
end;

procedure TfrSelectFieldCard.SaveOptions(SN: TSchemaNode);
var
  I: Integer;
  Opt: TFieldOption;
begin
  SN.Options.Clear;
  for I := 1 to sgOptions.RowCount - 1 do
  begin
    Opt.Value := Trim(sgOptions.Cells[0, I]);
    Opt.Label_ := Trim(sgOptions.Cells[1, I]);
    if (Opt.Value <> '') or (Opt.Label_ <> '') then
      SN.Options.Add(Opt);
  end;
end;

procedure TfrSelectFieldCard.SetOnChanged(AHandler: TNotifyEvent);
begin
  FOnChanged := AHandler;
end;

procedure TfrSelectFieldCard.SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
begin
  FOnFieldTypeChanged := AHandler;
end;

function TfrSelectFieldCard.AsControl: TWinControl;
begin
  Result := Self;
end;

procedure TfrSelectFieldCard.ControlChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TfrSelectFieldCard.cmbTypeChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
  if Assigned(FOnFieldTypeChanged) then FOnFieldTypeChanged(Self, cmbType.Text);
end;

procedure TfrSelectFieldCard.sgOptionsSetEditText(Sender: TObject;
  ACol, ARow: Integer; const Value: string);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TfrSelectFieldCard.btnOptAddClick(Sender: TObject);
begin
  sgOptions.RowCount := sgOptions.RowCount + 1;
  sgOptions.Cells[0, sgOptions.RowCount - 1] := '';
  sgOptions.Cells[1, sgOptions.RowCount - 1] := '';
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TfrSelectFieldCard.btnOptRemoveClick(Sender: TObject);
begin
  if sgOptions.RowCount > 2 then
  begin
    sgOptions.RowCount := sgOptions.RowCount - 1;
    if Assigned(FOnChanged) then FOnChanged(Self);
  end;
end;

end.
