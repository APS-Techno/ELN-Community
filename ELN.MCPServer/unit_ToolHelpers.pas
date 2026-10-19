unit unit_ToolHelpers;


interface

uses
  System.JSON,
  Aurelius.Types.Nullable,
  unit_Item;

const
  // Aurelius defaults these columns to VARCHAR(255). Strict MySQL rejects
  // longer strings, while SQLite does not enforce the width.
  MAX_TITLE_LEN = 255;
  MAX_DESC_LEN  = 255;

function MakeElnItemUrl(Item: TItem): string;

function ValueSourceJSON(Value: TValue): TJSONObject;
function NullableNumJSON(const Value: Nullable<Double>): TJSONValue;

function GetOptAnalysisSnapshot(const Params: TJSONObject;
  out Json: string): Boolean;
function AnalysisSnapshotValue(const Json: string): TJSONValue;

// Raises if AValue is longer than AMax. The exception is deliberately the base
// Exception class and nothing derived from it: unit_MCPDiag.ClientErrorMessage
// forwards the message verbatim only on an exact class match, so a descendant
// would reach the client as the useless generic "Tool execution failed".
procedure CheckMaxLen(const AValue, AFieldName: string; AMax: Integer);

implementation

uses
  System.SysUtils, System.NetEncoding, unit_ItemTypes, unit_ValueSource,
  unit_JSONCompact;

function MakeElnItemUrl(Item: TItem): string;
begin
  if Item = nil then
  begin
    Result := '';
    Exit;
  end;

  if Item.Type_ = TItemType.Specimen then
    Result := 'eln://specimen/' + TNetEncoding.URL.Encode(Item.Title)
  else
    Result := 'eln://item/' + IntToStr(Item.Id);
end;

function ValueSourceJSON(Value: TValue): TJSONObject;
var
  Source: TValueSourceInfo;
  Inputs: TJSONArray;
  Link: TDerivedValueInput;
  Entry: TJSONObject;
begin
  Source := ReadSource(Value);
  Result := TJSONObject.Create;
  Result.AddPair('kind', SourceKindName(Source.Kind));
  if Source.FileId > 0 then
    Result.AddPair('file_id', TJSONNumber.Create(Source.FileId));
  if Source.ReaderId <> '' then
    Result.AddPair('reader_id', Source.ReaderId);
  if Source.ReaderVersion <> '' then
    Result.AddPair('reader_version', Source.ReaderVersion);
  if Source.KeyName <> '' then
    Result.AddPair('key_name', Source.KeyName);
  if Source.Note <> '' then
    Result.AddPair('note', Source.Note);
  if Source.ReaderUnits.HasValue then
    Result.AddPair('reader_units', Source.ReaderUnits.Value);
  if Source.ConversionFactor.HasValue then
    Result.AddPair('conversion_factor', TJSONNumber.Create(Source.ConversionFactor.Value));
  if Source.Kind = vskDerived then
  begin
    Result.AddPair('formula_id', Source.FormulaId);
    Result.AddPair('formula_version', TJSONNumber.Create(Source.FormulaVersion));
    Inputs := TJSONArray.Create;
    Result.AddPair('inputs', Inputs);
    for Link in Value.DerivedInputs do
    begin
      Entry := TJSONObject.Create;
      Inputs.AddElement(Entry);
      Entry.AddPair('role', Link.Role);
      Entry.AddPair('value_id', TJSONNumber.Create(Link.InputValueId));
      Entry.AddPair('used_value', TJSONNumber.Create(Link.InputValue));
    end;
  end;
end;

function NullableNumJSON(const Value: Nullable<Double>): TJSONValue;
begin
  if Value.HasValue then
    Result := SmartNum(Value.Value)
  else
    Result := TJSONNull.Create;
end;

procedure CheckMaxLen(const AValue, AFieldName: string; AMax: Integer);
begin
  if Length(AValue) > AMax then
    raise Exception.CreateFmt(
      '%s is %d characters; the maximum is %d. Shorten it and retry.',
      [AFieldName, Length(AValue), AMax]);
end;

function GetOptAnalysisSnapshot(const Params: TJSONObject;
  out Json: string): Boolean;
var
  Field: TJSONValue;
begin
  Json := '';
  Field := nil;
  if Params <> nil then
    Field := Params.FindValue('analysis_snapshot');
  Result := (Field <> nil) and not (Field is TJSONNull);
  if not Result then
    Exit;
  if Field is TJSONObject then
    Json := Field.ToJSON
  else if Field is TJSONString then
    Json := Field.Value
  else
    raise Exception.Create('analysis_snapshot must be a JSON object or a ' +
      'string holding one JSON object.');
end;

function AnalysisSnapshotValue(const Json: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(Json);
  if not (Result is TJSONObject) then
  begin
    Result.Free;
    Result := TJSONString.Create(Json);
  end;
end;

end.
