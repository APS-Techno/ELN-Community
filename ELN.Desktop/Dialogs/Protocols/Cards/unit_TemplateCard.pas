unit unit_TemplateCard;

interface

uses
  System.Classes,
  Vcl.Controls,
  unit_TemplateSchema;

type
  TFieldTypeChangedEvent = procedure(Sender: TObject; const NewType: string) of object;

  ITemplateCard = interface
    ['{CAFF21A0-282A-4836-ADB3-5542DD6FE655}']
    procedure LoadFromNode(SN: TSchemaNode);
    procedure SaveToNode(SN: TSchemaNode);
    procedure SetOnChanged(AHandler: TNotifyEvent);
    procedure SetOnFieldTypeChanged(AHandler: TFieldTypeChangedEvent);
    function AsControl: TWinControl;
  end;

const
  FieldTypeItems: array[0..7] of string = (
    'text', 'number', 'date', 'textarea', 'select', 'checkbox',
    'checkbox-group', 'richtext'
  );

  AutoFillItems: array[0..12] of string = (
    '',
    'item.title', 'item.description', 'item.type',
    'actionType.title', 'actionType.description',
    'equipment.model', 'equipment.manufacturer', 'equipment.location',
    'parent.title', 'parent.description',
    'user.name', 'date.today'
  );

procedure PopulateFieldTypeCombo(Items: TStrings);
procedure PopulateAutoFillCombo(Items: TStrings);

implementation

procedure PopulateFieldTypeCombo(Items: TStrings);
var
  I: Integer;
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    for I := Low(FieldTypeItems) to High(FieldTypeItems) do
      Items.Add(FieldTypeItems[I]);
  finally
    Items.EndUpdate;
  end;
end;

procedure PopulateAutoFillCombo(Items: TStrings);
var
  I: Integer;
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    for I := Low(AutoFillItems) to High(AutoFillItems) do
      Items.Add(AutoFillItems[I]);
  finally
    Items.EndUpdate;
  end;
end;

end.
