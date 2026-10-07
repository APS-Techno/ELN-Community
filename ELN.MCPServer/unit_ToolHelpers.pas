unit unit_ToolHelpers;

// Small helpers shared by the MCP tool units: emitting eln:// URLs on
// item-shaped JSON responses, and length-checking strings before they
// reach a bounded database column.

interface

uses
  unit_Item;

const
  // Every Title/Description column the MCP write tools touch is VARCHAR(255)
  // -- Aurelius' default width, because the domain declares these columns
  // without an explicit length. The live MySQL/MariaDB server runs in
  // STRICT_TRANS_TABLES, so an over-long value is a hard error (1406), not a
  // silent truncation. SQLite does not enforce VARCHAR widths at all, which is
  // why the test suite never saw this until it hit production.
  MAX_TITLE_LEN = 255;
  MAX_DESC_LEN  = 255;

function MakeElnItemUrl(Item: TItem): string;

// Raises if AValue is longer than AMax. The exception is deliberately the base
// Exception class and nothing derived from it: unit_MCPDiag.ClientErrorMessage
// forwards the message verbatim only on an exact class match, so a descendant
// would reach the client as the useless generic "Tool execution failed".
procedure CheckMaxLen(const AValue, AFieldName: string; AMax: Integer);

implementation

uses
  System.SysUtils, System.NetEncoding, unit_ItemTypes;

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

procedure CheckMaxLen(const AValue, AFieldName: string; AMax: Integer);
begin
  if Length(AValue) > AMax then
    raise Exception.CreateFmt(
      '%s is %d characters; the maximum is %d. Shorten it and retry.',
      [AFieldName, Length(AValue), AMax]);
end;

end.
