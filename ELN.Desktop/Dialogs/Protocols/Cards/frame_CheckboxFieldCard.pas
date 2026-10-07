unit frame_CheckboxFieldCard;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Samples.Spin,
  RzLabel, RzEdit,
  unit_TemplateSchema, unit_TemplateCard, Vcl.Mask;

type
  TfrCheckboxFieldCard = class(TFrame, ITemplateCard)
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
    procedure ControlChange(Sender: TObject);
    procedure cmbTypeChange(Sender: TObject);
  private
    FUpdating: Boolean;
    FOnChanged: TNotifyEvent;
    FOnFieldTypeChanged: TFieldTypeChangedEvent;
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

constructor TfrCheckboxFieldCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  PopulateFieldTypeCombo(cmbType.Items);
  PopulateAutoFillCombo(cmbAutoFill.Items);
end;

procedure TfrCheckboxFieldCard.LoadFromNode(SN: TSchemaNode);
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
  finally
    FUpdating := False;
  end;
end;

procedure TfrCheckboxFieldCard.SaveToNode(SN: TSchemaNode);
begin
  if (SN = nil) or (SN.Kind <> snkField) then Exit;
  SN.FieldName := edtName.Text;
  SN.FieldLabel := edtLabel.Text;
  SN.FieldType := cmbType.Text;
  SN.AutoFill := cmbAutoFill.Text;
  SN.Flex := spnFlex.Value;
end;

procedure TfrCheckboxFieldCard.SetOnChanged(AHandler: TNotifyEvent);
begin
  FOnChanged := AHandler;
end;

procedure TfrCheckboxFieldCard.SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
begin
  FOnFieldTypeChanged := AHandler;
end;

function TfrCheckboxFieldCard.AsControl: TWinControl;
begin
  Result := Self;
end;

procedure TfrCheckboxFieldCard.ControlChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TfrCheckboxFieldCard.cmbTypeChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
  if Assigned(FOnFieldTypeChanged) then FOnFieldTypeChanged(Self, cmbType.Text);
end;

end.
