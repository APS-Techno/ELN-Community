unit frame_RowCard;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  RzLabel,
  unit_TemplateSchema, unit_TemplateCard;

type
  TfrRowCard = class(TFrame, ITemplateCard)
    lblInfo: TRzLabel;
  public
    procedure LoadFromNode(SN: TSchemaNode);
    procedure SaveToNode(SN: TSchemaNode);
    procedure SetOnChanged(AHandler: TNotifyEvent);
    procedure SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
    function AsControl: TWinControl;
    procedure SetInfo(const Caption: string);
  end;

implementation

{$R *.dfm}

procedure TfrRowCard.LoadFromNode(SN: TSchemaNode);
begin
  // No-op: the row card displays Node.Count, which TSchemaNode does not know.
  // The host must call SetInfo after LoadFromNode.
end;

procedure TfrRowCard.SaveToNode(SN: TSchemaNode);
begin
end;

procedure TfrRowCard.SetOnChanged(AHandler: TNotifyEvent);
begin
end;

procedure TfrRowCard.SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
begin
end;

function TfrRowCard.AsControl: TWinControl;
begin
  Result := Self;
end;

procedure TfrRowCard.SetInfo(const Caption: string);
begin
  lblInfo.Caption := Caption;
end;

end.
