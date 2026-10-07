unit frame_SectionCard;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  RzLabel, RzEdit,
  unit_TemplateSchema, unit_TemplateCard;

type
  TfrSectionCard = class(TFrame, ITemplateCard)
    lblTitle: TRzLabel;
    edtTitle: TRzEdit;
    procedure edtTitleChange(Sender: TObject);
  private
    FUpdating: Boolean;
    FOnChanged: TNotifyEvent;
  public
    procedure LoadFromNode(SN: TSchemaNode);
    procedure SaveToNode(SN: TSchemaNode);
    procedure SetOnChanged(AHandler: TNotifyEvent);
    procedure SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
    function AsControl: TWinControl;
  end;

implementation

{$R *.dfm}

procedure TfrSectionCard.LoadFromNode(SN: TSchemaNode);
begin
  FUpdating := True;
  try
    if (SN <> nil) and (SN.Kind = snkSection) then
      edtTitle.Text := SN.SectionTitle
    else
      edtTitle.Text := '';
  finally
    FUpdating := False;
  end;
end;

procedure TfrSectionCard.SaveToNode(SN: TSchemaNode);
begin
  if (SN <> nil) and (SN.Kind = snkSection) then
    SN.SectionTitle := edtTitle.Text;
end;

procedure TfrSectionCard.SetOnChanged(AHandler: TNotifyEvent);
begin
  FOnChanged := AHandler;
end;

procedure TfrSectionCard.SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
begin
  // not used by section card
end;

function TfrSectionCard.AsControl: TWinControl;
begin
  Result := Self;
end;

procedure TfrSectionCard.edtTitleChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

end.
