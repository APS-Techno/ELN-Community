unit unit_TemplateSchema;

interface

uses
  System.Generics.Collections;

type
  TSchemaNodeKind = (snkSection, snkRow, snkField);

  TFieldOption = record
    Value: string;
    Label_: string;
  end;

  TSchemaNode = class
  public
    Kind: TSchemaNodeKind;
    SectionTitle: string;
    FieldName: string;
    FieldLabel: string;
    FieldType: string;
    Placeholder: string;
    AutoFill: string;
    Flex: Integer;
    RowCount: Integer;
    Options: TList<TFieldOption>;
    constructor Create(AKind: TSchemaNodeKind);
    destructor Destroy; override;
    function DisplayText: string;
  end;

implementation

uses
  System.SysUtils;


constructor TSchemaNode.Create(AKind: TSchemaNodeKind);
begin
  inherited Create;
  Kind := AKind;
  Flex := 1;
  RowCount := 3;
  FieldType := 'text';
  Options := TList<TFieldOption>.Create;
end;

destructor TSchemaNode.Destroy;
begin
  FreeAndNil(Options);
  inherited;
end;

function TSchemaNode.DisplayText: string;
begin
  case Kind of
    snkSection: Result := SectionTitle;
    snkRow:     Result := 'Row';
    snkField:   Result := FieldName + ' (' + FieldType + ')';
  end;
end;

end.
