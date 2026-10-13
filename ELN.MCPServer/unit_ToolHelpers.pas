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

end.
