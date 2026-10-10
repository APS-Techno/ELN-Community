unit frame_RichtextFieldCard;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Samples.Spin,
  RzLabel, RzEdit,
  unit_TemplateSchema, unit_TemplateCard;

type
  TfrRichtextFieldCard = class(TFrame, ITemplateCard)
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
    lblRows: TRzLabel;
    spnRows: TSpinEdit;
    procedure ControlChange(Sender: TObject);
    procedure cmbTypeChange(Sender: TObject);
  private
    FUpdating: Boolean;
    FInitialized: Boolean;
    FOnChanged: TNotifyEvent;
    FOnFieldTypeChanged: TFieldTypeChangedEvent;
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    procedure LoadFromNode(SN: TSchemaNode);
    procedure SaveToNode(SN: TSchemaNode);
    procedure SetOnChanged(AHandler: TNotifyEvent);
    procedure SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
    function AsControl: TWinControl;
  end;

implementation

{$R *.dfm}

procedure TfrRichtextFieldCard.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if (AParent = nil) or FInitialized then Exit;
  // Combo-box item access needs the frame's real parent window.
  PopulateFieldTypeCombo(cmbType.Items);
  PopulateAutoFillCombo(cmbAutoFill.Items);
  FInitialized := True;
end;

procedure TfrRichtextFieldCard.LoadFromNode(SN: TSchemaNode);
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
    spnRows.Value := SN.RowCount;
  finally
    FUpdating := False;
  end;
end;

procedure TfrRichtextFieldCard.SaveToNode(SN: TSchemaNode);
begin
  if (SN = nil) or (SN.Kind <> snkField) then Exit;
  SN.FieldName := edtName.Text;
  SN.FieldLabel := edtLabel.Text;
  SN.FieldType := cmbType.Text;
  SN.AutoFill := cmbAutoFill.Text;
  SN.Flex := spnFlex.Value;
  SN.RowCount := spnRows.Value;
end;

procedure TfrRichtextFieldCard.SetOnChanged(AHandler: TNotifyEvent);
begin
  FOnChanged := AHandler;
end;

procedure TfrRichtextFieldCard.SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
begin
  FOnFieldTypeChanged := AHandler;
end;

function TfrRichtextFieldCard.AsControl: TWinControl;
begin
  Result := Self;
end;

procedure TfrRichtextFieldCard.ControlChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TfrRichtextFieldCard.cmbTypeChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
  if Assigned(FOnFieldTypeChanged) then FOnFieldTypeChanged(Self, cmbType.Text);
end;

end.
