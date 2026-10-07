unit unit_ReportBuilder;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  unit_Item, unit_ItemTypes, unit_Protocol, unit_LabEntry,
  unit_ValueType, unit_Tag, unit_Comment, unit_Signature,
  unit_Template;

type
  TPaperSize = (psA4, psLetter);

  TReportOptions = record
    IncludeMetadata: Boolean;
    IncludeProtocols: Boolean;
    IncludeValues: Boolean;
    IncludeFiles: Boolean;
    IncludeSignatures: Boolean;
    IncludeComments: Boolean;
    IncludeTags: Boolean;
    PaperSize: TPaperSize;
    LogoPath: string;
    class function Default: TReportOptions; static;
  end;

  TReportItemData = record
    Item: TItem;
    Tags: TTags;
    Comments: TComments;
    Signature: TSignature;
    IntegrityOk: Boolean;
    HasSignature: Boolean;
    Templates: TDictionary<Integer, TTemplate>;
    StorageRoot: string;
  end;

  TReportBuilder = class
  private
    class function HtmlEncode(const S: string): string;
    class function SanitizeColor(const S: string): string;
    class function FormatDT(const DT: TDateTime): string;
    class function GetCss(PaperSize: TPaperSize): string;
    class procedure BuildLogo(SB: TStringBuilder; const LogoPath: string);
    class procedure BuildHeader(SB: TStringBuilder; const Item: TItem; Index: Integer);
    class procedure BuildMetadata(SB: TStringBuilder; const Item: TItem);
    class procedure BuildProtocols(SB: TStringBuilder; const Item: TItem;
      Templates: TDictionary<Integer, TTemplate>);
    class procedure BuildProtocolFormData(SB: TStringBuilder;
      const FormSchemaJson, FormDataJson: string);
    class procedure BuildValues(SB: TStringBuilder; const Item: TItem);
    class procedure BuildFiles(SB: TStringBuilder; const Item: TItem; const StorageRoot: string);
    class procedure BuildTags(SB: TStringBuilder; Tags: TTags);
    class procedure BuildComments(SB: TStringBuilder; Comments: TComments);
    class procedure BuildSignature(SB: TStringBuilder; Sig: TSignature;
      IntegrityOk: Boolean);
  public
    class function BuildReport(const Items: TList<TReportItemData>;
      const Options: TReportOptions): string;
  end;

implementation

uses
  System.JSON, System.TypInfo, System.DateUtils, System.NetEncoding, System.IOUtils,
  unit_TimeHelper;

const
  ACCENT = '#1a5276';

{ TReportOptions }

class function TReportOptions.Default: TReportOptions;
begin
  Result.IncludeMetadata := True;
  Result.IncludeProtocols := True;
  Result.IncludeValues := True;
  Result.IncludeFiles := True;
  Result.IncludeSignatures := True;
  Result.IncludeComments := True;
  Result.IncludeTags := True;
  Result.PaperSize := psA4;
  Result.LogoPath := '';
end;

{ TReportBuilder }

class function TReportBuilder.HtmlEncode(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

class function TReportBuilder.SanitizeColor(const S: string): string;
var
  C: Char;
begin
  // Accept only safe CSS color tokens: hex (#abc / #aabbcc) or a color
  // keyword (letters/digits). Any other character (quote, semicolon, space,
  // parenthesis, etc.) could break out of the style attribute, so reject the
  // whole value and let the caller fall back to the default accent.
  Result := '';
  if S = '' then
    Exit;
  for C in S do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '#']) then
      Exit;
  Result := S;
end;

class function TReportBuilder.FormatDT(const DT: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', FromUTC(DT));
end;

class function TReportBuilder.GetCss(PaperSize: TPaperSize): string;
var
  PageSize: string;
begin
  if PaperSize = psLetter then
    PageSize := 'letter'
  else
    PageSize := 'A4';

  Result :=
    '@page { size: ' + PageSize + '; margin: 15mm 20mm; }' +
    '* { box-sizing: border-box; }' +
    'body { font-family: ''Segoe UI'', Arial, sans-serif; margin: 0; padding: 24px; ' +
      'color: #222; font-size: 13px; background: #fff; }' +
    'h1 { margin: 0 0 4px 0; font-size: 22px; font-weight: 600; color: ' + ACCENT + '; }' +
    'h2 { font-size: 17px; font-weight: 600; color: ' + ACCENT + '; margin: 24px 0 8px 0; ' +
      'padding-top: 8px; border-top: 1px solid #eee; }' +
    'h3 { font-size: 14px; font-weight: 600; color: #2c3e50; margin: 14px 0 6px 0; }' +
    '.subtitle { color: #777; font-size: 11px; margin-bottom: 16px; ' +
      'border-bottom: 2px solid ' + ACCENT + '; padding-bottom: 8px; }' +
    'table { width: 100%; border-collapse: collapse; margin-bottom: 14px; }' +
    'th { text-align: left; font-size: 11px; font-weight: 600; color: #555; ' +
      'text-transform: uppercase; letter-spacing: 0.4px; ' +
      'border-bottom: 2px solid #ddd; padding: 4px 8px 5px 8px; }' +
    'td { padding: 4px 8px; border-bottom: 1px solid #eee; vertical-align: top; font-size: 13px; }' +
    'tr:last-child td { border-bottom: none; }' +
    '.meta-table td:first-child { font-weight: 600; color: #555; width: 160px; }' +
    'fieldset { border: 1px solid #ddd; border-radius: 4px; padding: 10px 14px; margin-bottom: 12px; }' +
    'legend { font-weight: 600; font-size: 13px; color: ' + ACCENT + '; padding: 0 6px; }' +
    '.field-row { display: flex; gap: 12px; margin-bottom: 6px; }' +
    '.field-col { flex: 1; }' +
    '.field-label { font-weight: 600; font-size: 11px; color: #555; margin-bottom: 2px; }' +
    '.field-value { font-size: 13px; padding: 4px 6px; background: #f9f9f9; ' +
      'border: 1px solid #eee; border-radius: 3px; min-height: 22px; }' +
    '.badge { display: inline-block; font-size: 11px; font-weight: 600; ' +
      'padding: 2px 8px; border-radius: 3px; margin-right: 4px; }' +
    '.badge-draft { background: #fff3cd; color: #856404; }' +
    '.badge-inreview { background: #cce5ff; color: #004085; }' +
    '.badge-approved { background: #d4edda; color: #155724; }' +
    '.badge-rejected { background: #f8d7da; color: #721c24; }' +
    '.badge-type { background: #e3f2fd; color: #1565c0; }' +
    '.tag { display: inline-block; font-size: 11px; font-weight: 600; ' +
      'padding: 2px 10px; border-radius: 12px; margin: 2px 4px 2px 0; color: #fff; }' +
    '.comment { background: #f7f9fb; border-left: 3px solid ' + ACCENT + '; ' +
      'padding: 8px 12px; margin-bottom: 8px; }' +
    '.comment-meta { font-size: 11px; color: #777; margin-bottom: 3px; }' +
    '.sig-block { background: #f0f4f8; border: 1px solid #d0d8e0; ' +
      'border-radius: 4px; padding: 12px 16px; margin: 8px 0; }' +
    '.sig-ok { color: #155724; font-weight: 600; }' +
    '.sig-fail { color: #721c24; font-weight: 600; }' +
    '.item-section { page-break-inside: avoid; }' +
    '.page-break { page-break-before: always; }' +
    '.report-footer { margin-top: 24px; padding-top: 8px; border-top: 1px solid #ddd; ' +
      'font-size: 10px; color: #999; text-align: center; }' +
    '.report-logo { margin-bottom: 16px; }' +
    '.report-logo img { max-height: 60px; }' +
    '.toc { page-break-after: always; }' +
    '.toc-list { font-size: 14px; line-height: 2; }' +
    '.toc-list a { color: ' + ACCENT + '; text-decoration: none; }' +
    '.toc-list a:hover { text-decoration: underline; }' +
    '.thumbnail-grid { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 12px; }' +
    '.thumbnail-item { text-align: center; max-width: 200px; }' +
    '.thumbnail-item img { max-width: 200px; max-height: 150px; border: 1px solid #ddd; border-radius: 3px; }' +
    '.thumbnail-caption { font-size: 11px; color: #555; margin-top: 4px; word-break: break-word; }' +
    '@media print { body { padding: 0; } .page-break { page-break-before: always; } }';
end;

class procedure TReportBuilder.BuildLogo(SB: TStringBuilder; const LogoPath: string);
var
  Bytes: TBytes;
  Base64, Mime, Ext: string;
begin
  if (LogoPath = '') or not FileExists(LogoPath) then
    Exit;

  Ext := LowerCase(ExtractFileExt(LogoPath));
  if Ext = '.png' then
    Mime := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
    Mime := 'image/jpeg'
  else if Ext = '.bmp' then
    Mime := 'image/bmp'
  else
    Exit;

  Bytes := System.IOUtils.TFile.ReadAllBytes(LogoPath);
  Base64 := TNetEncoding.Base64.EncodeBytesToString(Bytes);

  SB.Append('<div class="report-logo">');
  SB.Append('<img src="data:').Append(Mime).Append(';base64,').Append(Base64).Append('">');
  SB.Append('</div>');
end;

class procedure TReportBuilder.BuildHeader(SB: TStringBuilder; const Item: TItem; Index: Integer);
var
  LevelStr, TypeStr: string;
begin
  LevelStr := GetEnumName(TypeInfo(TItemLevel), Ord(Item.Level));
  TypeStr := GetEnumName(TypeInfo(TItemType), Ord(Item.Type_));

  SB.Append('<div class="item-section" id="item-').Append(IntToStr(Index)).Append('">');
  SB.Append('<h1>').Append(HtmlEncode(Item.Title)).Append('</h1>');
  SB.Append('<div class="subtitle">');
  SB.Append(HtmlEncode(LevelStr)).Append(' &middot; ').Append(HtmlEncode(TypeStr));
  SB.Append(' &middot; ID: ').Append(IntToStr(Item.Id));
  SB.Append('</div>');
end;

class procedure TReportBuilder.BuildMetadata(SB: TStringBuilder; const Item: TItem);
var
  LevelStr, TypeStr: string;
  JsonVal: TJSONValue;
  JsonObj: TJSONObject;
  Pair: TJSONPair;
begin
  LevelStr := GetEnumName(TypeInfo(TItemLevel), Ord(Item.Level));
  TypeStr := GetEnumName(TypeInfo(TItemType), Ord(Item.Type_));

  SB.Append('<h2>Metadata</h2>');
  SB.Append('<table class="meta-table">');
  SB.Append('<tr><td>Title</td><td>').Append(HtmlEncode(Item.Title)).Append('</td></tr>');
  SB.Append('<tr><td>Level</td><td>').Append(HtmlEncode(LevelStr)).Append('</td></tr>');
  SB.Append('<tr><td>Type</td><td>').Append(HtmlEncode(TypeStr)).Append('</td></tr>');

  if Item.Description <> '' then
    SB.Append('<tr><td>Description</td><td>').Append(HtmlEncode(Item.Description)).Append('</td></tr>');

  SB.Append('<tr><td>Created</td><td>').Append(FormatDT(Item.CreatedDate)).Append('</td></tr>');
  if Item.ModifiedDate.HasValue then
    SB.Append('<tr><td>Modified</td><td>').Append(FormatDT(Item.ModifiedDate.Value)).Append('</td></tr>');

  // Parse Properties JSON key-value pairs
  if Item.Properties <> '' then
  begin
    JsonVal := TJSONObject.ParseJSONValue(Item.Properties);
    if Assigned(JsonVal) and (JsonVal is TJSONObject) then
    begin
      JsonObj := TJSONObject(JsonVal);
      try
        for Pair in JsonObj do
          SB.Append('<tr><td>').Append(HtmlEncode(Pair.JsonString.Value))
            .Append('</td><td>').Append(HtmlEncode(Pair.JsonValue.Value)).Append('</td></tr>');
      finally
        JsonVal.Free;
      end;
    end
    else
      JsonVal.Free;
  end;

  SB.Append('</table>');
end;

class procedure TReportBuilder.BuildProtocols(SB: TStringBuilder; const Item: TItem;
  Templates: TDictionary<Integer, TTemplate>);
var
  Entry: TLabEntry;
  Protocol: TProtocol;
  StatusClass, StatusText, PTypeStr: string;
  Tmpl: TTemplate;
begin
  SB.Append('<h2>Protocols</h2>');

  for Entry in Item.Entries do
  begin
    if not (Entry is TProtocol) then Continue;
    Protocol := TProtocol(Entry);

    SB.Append('<div style="margin-bottom: 14px;">');
    SB.Append('<h3>').Append(HtmlEncode(Protocol.Title)).Append('</h3>');

    // Protocol type badge
    if Protocol.ProtocolType.HasValue then
    begin
      PTypeStr := GetEnumName(TypeInfo(TProtocolType), Ord(Protocol.ProtocolType.Value));
      // Remove 'pt' prefix
      if PTypeStr.StartsWith('pt') then
        PTypeStr := Copy(PTypeStr, 3, Length(PTypeStr));
      SB.Append('<span class="badge badge-type">').Append(HtmlEncode(PTypeStr)).Append('</span>');
    end;

    // Validation status badge
    case Protocol.ValidationStatus of
      vsDraft:    begin StatusClass := 'badge-draft';    StatusText := 'Draft'; end;
      vsInReview: begin StatusClass := 'badge-inreview'; StatusText := 'In Review'; end;
      vsApproved: begin StatusClass := 'badge-approved'; StatusText := 'Approved'; end;
      vsRejected: begin StatusClass := 'badge-rejected'; StatusText := 'Rejected'; end;
    end;
    SB.Append('<span class="badge ').Append(StatusClass).Append('">').Append(StatusText).Append('</span>');

    // Equipment info
    if (Protocol.EquipModel <> '') or (Protocol.EquipManufacturer <> '') or
       (Protocol.EquipLocation <> '') then
    begin
      SB.Append('<div style="font-size:12px; color:#555; margin-top:4px;">');
      if Protocol.EquipModel <> '' then
        SB.Append('Model: ').Append(HtmlEncode(Protocol.EquipModel)).Append(' &middot; ');
      if Protocol.EquipManufacturer <> '' then
        SB.Append('Manufacturer: ').Append(HtmlEncode(Protocol.EquipManufacturer)).Append(' &middot; ');
      if Protocol.EquipLocation <> '' then
        SB.Append('Location: ').Append(HtmlEncode(Protocol.EquipLocation));
      SB.Append('</div>');
    end;

    // Dates
    SB.Append('<div style="font-size:11px; color:#999; margin-top:2px;">');
    SB.Append('Created: ').Append(FormatDT(Protocol.CreatedDate));
    if Protocol.ModifiedDate.HasValue then
      SB.Append(' &middot; Modified: ').Append(FormatDT(Protocol.ModifiedDate.Value));
    SB.Append('</div>');

    // Render form data as read-only fields
    if (Protocol.FormData <> '') and Protocol.TemplateId.HasValue then
    begin
      Tmpl := nil;
      if Assigned(Templates) then
        Templates.TryGetValue(Protocol.TemplateId.Value, Tmpl);
      if Assigned(Tmpl) and (Tmpl.FormSchema <> '') then
        BuildProtocolFormData(SB, Tmpl.FormSchema, Protocol.FormData)
      else
      begin
        // No template available — show raw form data as pre-formatted text
        SB.Append('<div style="margin-top:8px;">');
        SB.Append('<pre style="background:#f5f5f5; padding:8px; border-radius:3px; font-size:12px; overflow:auto;">');
        SB.Append(HtmlEncode(Protocol.FormData));
        SB.Append('</pre></div>');
      end;
    end
    else if Protocol.FormData <> '' then
    begin
      // Free-text protocol (note) — FormData is the content
      SB.Append('<div style="margin-top:8px; padding:8px; background:#f9f9f9; border:1px solid #eee; border-radius:3px;">');
      SB.Append(Protocol.FormData); // Notes store HTML content
      SB.Append('</div>');
    end;

    SB.Append('</div>');
  end;
end;

class procedure TReportBuilder.BuildProtocolFormData(SB: TStringBuilder;
  const FormSchemaJson, FormDataJson: string);
var
  SchemaVal, DataVal: TJSONValue;
  Schema, DataObj: TJSONObject;
  Sections, Rows, Fields, Options: TJSONArray;
  Section, Row, Field, Option: TJSONObject;
  I, J, K, L: Integer;
  FieldName, FieldType, FieldLabel, FieldValue: string;
  FieldCount: Integer;
begin
  SchemaVal := TJSONObject.ParseJSONValue(FormSchemaJson);
  if not Assigned(SchemaVal) then Exit;

  DataVal := TJSONObject.ParseJSONValue(FormDataJson);
  if not Assigned(DataVal) then
  begin
    SchemaVal.Free;
    Exit;
  end;

  try
    if not (SchemaVal is TJSONObject) then Exit;
    if not (DataVal is TJSONObject) then Exit;

    Schema := TJSONObject(SchemaVal);
    DataObj := TJSONObject(DataVal);

    if Schema.GetValue('sections') = nil then Exit;
    Sections := TJSONArray(Schema.GetValue('sections'));

    for I := 0 to Sections.Count - 1 do
    begin
      if not (Sections.Items[I] is TJSONObject) then Continue;
      Section := TJSONObject(Sections.Items[I]);

      SB.Append('<fieldset>');
      if Section.GetValue('title') <> nil then
        SB.Append('<legend>').Append(HtmlEncode(Section.GetValue('title').Value)).Append('</legend>');

      if Section.GetValue('rows') = nil then
      begin
        SB.Append('</fieldset>');
        Continue;
      end;

      Rows := TJSONArray(Section.GetValue('rows'));
      for J := 0 to Rows.Count - 1 do
      begin
        if not (Rows.Items[J] is TJSONObject) then Continue;
        Row := TJSONObject(Rows.Items[J]);

        if Row.GetValue('fields') = nil then Continue;
        Fields := TJSONArray(Row.GetValue('fields'));
        FieldCount := Fields.Count;

        if FieldCount > 1 then
          SB.Append('<div class="field-row">');

        for K := 0 to Fields.Count - 1 do
        begin
          if not (Fields.Items[K] is TJSONObject) then Continue;
          Field := TJSONObject(Fields.Items[K]);

          FieldName := '';
          if Field.GetValue('name') <> nil then
            FieldName := Field.GetValue('name').Value;

          FieldType := 'text';
          if Field.GetValue('type') <> nil then
            FieldType := Field.GetValue('type').Value;

          FieldLabel := FieldName;
          if Field.GetValue('label') <> nil then
            FieldLabel := Field.GetValue('label').Value;

          // Get value from FormData
          FieldValue := '';
          if DataObj.GetValue(FieldName) <> nil then
            FieldValue := DataObj.GetValue(FieldName).Value;

          if FieldCount > 1 then
            SB.Append('<div class="field-col">');

          if FieldType = 'checkbox' then
          begin
            SB.Append('<div class="field-label">').Append(HtmlEncode(FieldLabel)).Append('</div>');
            SB.Append('<div class="field-value">');
            if SameText(FieldValue, 'true') or (FieldValue = '1') then
              SB.Append('&#9745; Yes')
            else
              SB.Append('&#9744; No');
            SB.Append('</div>');
          end
          else if FieldType = 'checkbox-group' then
          begin
            SB.Append('<div class="field-label">').Append(HtmlEncode(FieldLabel)).Append('</div>');
            SB.Append('<div class="field-value">');
            if (Field.GetValue('options') <> nil) and (Field.GetValue('options') is TJSONArray) then
            begin
              Options := TJSONArray(Field.GetValue('options'));
              for L := 0 to Options.Count - 1 do
              begin
                if not (Options.Items[L] is TJSONObject) then Continue;
                Option := TJSONObject(Options.Items[L]);
                var OptName := '';
                if Option.GetValue('name') <> nil then
                  OptName := Option.GetValue('name').Value;
                var OptLabel := OptName;
                if Option.GetValue('label') <> nil then
                  OptLabel := Option.GetValue('label').Value;
                var OptVal := '';
                if DataObj.GetValue(OptName) <> nil then
                  OptVal := DataObj.GetValue(OptName).Value;
                if SameText(OptVal, 'true') or (OptVal = '1') then
                  SB.Append('&#9745; ')
                else
                  SB.Append('&#9744; ');
                SB.Append(HtmlEncode(OptLabel)).Append('&nbsp;&nbsp; ');
              end;
            end;
            SB.Append('</div>');
          end
          else if (FieldType = 'richtext') then
          begin
            SB.Append('<div class="field-label">').Append(HtmlEncode(FieldLabel)).Append('</div>');
            SB.Append('<div class="field-value">');
            SB.Append(FieldValue); // Rich text stores HTML
            SB.Append('</div>');
          end
          else if FieldType = 'select' then
          begin
            SB.Append('<div class="field-label">').Append(HtmlEncode(FieldLabel)).Append('</div>');
            SB.Append('<div class="field-value">');
            // Try to find the display label for the selected value
            var DisplayLabel := FieldValue;
            if (Field.GetValue('options') <> nil) and (Field.GetValue('options') is TJSONArray) then
            begin
              Options := TJSONArray(Field.GetValue('options'));
              for L := 0 to Options.Count - 1 do
              begin
                if (Options.Items[L] is TJSONObject) then
                begin
                  Option := TJSONObject(Options.Items[L]);
                  if (Option.GetValue('value') <> nil) and
                     (Option.GetValue('value').Value = FieldValue) and
                     (Option.GetValue('label') <> nil) then
                  begin
                    DisplayLabel := Option.GetValue('label').Value;
                    Break;
                  end;
                end;
              end;
            end;
            SB.Append(HtmlEncode(DisplayLabel));
            SB.Append('</div>');
          end
          else
          begin
            // text, number, date, textarea
            SB.Append('<div class="field-label">').Append(HtmlEncode(FieldLabel)).Append('</div>');
            SB.Append('<div class="field-value">').Append(HtmlEncode(FieldValue)).Append('</div>');
          end;

          if FieldCount > 1 then
            SB.Append('</div>');
        end;

        if FieldCount > 1 then
          SB.Append('</div>');
      end;

      SB.Append('</fieldset>');
    end;
  finally
    SchemaVal.Free;
    DataVal.Free;
  end;
end;

class procedure TReportBuilder.BuildValues(SB: TStringBuilder; const Item: TItem);
var
  V: TValue;
  RecTypeStr: string;
begin
  SB.Append('<h2>Values</h2>');
  SB.Append('<table>');
  SB.Append('<tr><th>Symbol</th><th>Value</th><th>Units</th><th>Type</th><th>Description</th><th>Date</th></tr>');

  for V in Item.Values do
  begin
    RecTypeStr := GetEnumName(TypeInfo(TRecType), Ord(V.RecType));

    SB.Append('<tr>');
    SB.Append('<td>').Append(HtmlEncode(V.ValueType.Symbol)).Append('</td>');
    SB.Append('<td>');
    SB.Append(HtmlEncode(FloatToStr(V.Value)));
    if V.Tol <> 0 then
      SB.Append(' &plusmn; ').Append(HtmlEncode(FloatToStr(V.Tol)));
    SB.Append('</td>');
    SB.Append('<td>').Append(HtmlEncode(V.ValueType.Units)).Append('</td>');
    SB.Append('<td>').Append(HtmlEncode(RecTypeStr)).Append('</td>');
    SB.Append('<td>').Append(HtmlEncode(V.Description)).Append('</td>');
    SB.Append('<td>').Append(FormatDT(V.CreatedDate)).Append('</td>');
    SB.Append('</tr>');
  end;

  SB.Append('</table>');
end;

class procedure TReportBuilder.BuildFiles(SB: TStringBuilder; const Item: TItem;
  const StorageRoot: string);
var
  F: unit_Item.TFile;
  HasThumbnails: Boolean;
  ThumbSB: TStringBuilder;
  PreviewPath: string;
  Bytes: TBytes;
  B64: string;
begin
  SB.Append('<h2>Files</h2>');
  SB.Append('<table>');
  SB.Append('<tr><th>Title</th><th>Extension</th><th>Hash (MD5)</th><th>Date</th></tr>');

  for F in Item.Files do
  begin
    SB.Append('<tr>');
    SB.Append('<td>').Append(HtmlEncode(F.Title)).Append('</td>');
    SB.Append('<td>').Append(HtmlEncode(F.FileType.Ext)).Append('</td>');
    SB.Append('<td style="font-family:Consolas,monospace; font-size:11px;">').Append(HtmlEncode(F.Hash)).Append('</td>');
    SB.Append('<td>').Append(FormatDT(F.CreatedDate)).Append('</td>');
    SB.Append('</tr>');
  end;

  SB.Append('</table>');

  // Thumbnail grid — embed preview PNGs as base64
  if StorageRoot <> '' then
  begin
    HasThumbnails := False;
    ThumbSB := TStringBuilder.Create;
    try
      for F in Item.Files do
      begin
        PreviewPath := Format('%sPreviews\[1000]\%.*d_%.*d.png',
          [IncludeTrailingPathDelimiter(StorageRoot), 5, Item.Id, 5, F.Id]);
        if FileExists(PreviewPath) then
        begin
          Bytes := System.IOUtils.TFile.ReadAllBytes(PreviewPath);
          B64 := TNetEncoding.Base64.EncodeBytesToString(Bytes);
          ThumbSB.Append('<div class="thumbnail-item">');
          ThumbSB.Append('<img src="data:image/png;base64,').Append(B64).Append('">');
          ThumbSB.Append('<div class="thumbnail-caption">').Append(HtmlEncode(F.Title)).Append('</div>');
          ThumbSB.Append('</div>');
          HasThumbnails := True;
        end;
      end;

      if HasThumbnails then
      begin
        SB.Append('<div class="thumbnail-grid">');
        SB.Append(ThumbSB.ToString);
        SB.Append('</div>');
      end;
    finally
      ThumbSB.Free;
    end;
  end;
end;

class procedure TReportBuilder.BuildTags(SB: TStringBuilder; Tags: TTags);
var
  T: TTag;
  BgColor: string;
begin
  SB.Append('<h2>Tags</h2>');
  SB.Append('<div style="margin-bottom: 12px;">');

  for T in Tags do
  begin
    BgColor := SanitizeColor(T.Color);
    if BgColor = '' then
      BgColor := '#607d8b';
    SB.Append('<span class="tag" style="background:').Append(BgColor).Append(';">');
    SB.Append(HtmlEncode(T.Name));
    SB.Append('</span>');
  end;

  SB.Append('</div>');
end;

class procedure TReportBuilder.BuildComments(SB: TStringBuilder; Comments: TComments);
var
  C: TComment;
begin
  SB.Append('<h2>Comments</h2>');

  for C in Comments do
  begin
    SB.Append('<div class="comment">');
    SB.Append('<div class="comment-meta">');
    SB.Append(HtmlEncode(C.UserName)).Append(' &middot; ').Append(FormatDT(C.CreatedDate));
    SB.Append('</div>');
    SB.Append('<div>').Append(HtmlEncode(C.Text)).Append('</div>');
    SB.Append('</div>');
  end;
end;

class procedure TReportBuilder.BuildSignature(SB: TStringBuilder; Sig: TSignature;
  IntegrityOk: Boolean);
begin
  SB.Append('<h2>Electronic Signature</h2>');
  SB.Append('<div class="sig-block">');
  SB.Append('<table class="meta-table" style="margin:0;">');
  SB.Append('<tr><td>Signed by</td><td>').Append(HtmlEncode(Sig.UserName)).Append('</td></tr>');
  SB.Append('<tr><td>Date</td><td>').Append(FormatDT(Sig.SignedDate)).Append('</td></tr>');
  SB.Append('<tr><td>Meaning</td><td>').Append(HtmlEncode(Sig.Meaning)).Append('</td></tr>');
  if Sig.Comment <> '' then
    SB.Append('<tr><td>Comment</td><td>').Append(HtmlEncode(Sig.Comment)).Append('</td></tr>');
  SB.Append('<tr><td>Content Hash</td><td style="font-family:Consolas,monospace; font-size:11px;">');
  SB.Append(HtmlEncode(Sig.ContentHash)).Append('</td></tr>');
  SB.Append('<tr><td>Integrity</td><td>');
  if IntegrityOk then
    SB.Append('<span class="sig-ok">&#10003; Verified</span>')
  else
    SB.Append('<span class="sig-fail">&#10007; Failed</span>');
  SB.Append('</td></tr>');
  SB.Append('</table>');
  SB.Append('</div>');
end;

class function TReportBuilder.BuildReport(const Items: TList<TReportItemData>;
  const Options: TReportOptions): string;
var
  SB: TStringBuilder;
  I: Integer;
  Data: TReportItemData;
  Item: TItem;
  HasProtocols, HasValues, HasFiles: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('<!DOCTYPE html><html><head>');
    // Strict CSP first in <head>: the report is a static presentational
    // document. default-src 'none' blocks all scripting (inline handlers,
    // <script>, javascript: URLs) AND all external resource loads, so HTML
    // injected via richtext/note fields or tag colors can neither execute nor
    // phone home (no external <img>/<link>/<iframe> tracking beacons or CSS
    // exfiltration from a signed report). Legitimate report content stays
    // intact: all images are embedded as data: URIs and the only CSS is the
    // inline <style> block below.
    SB.Append('<meta http-equiv="Content-Security-Policy" content="default-src ''none''; img-src data:; style-src ''unsafe-inline''; base-uri ''none''; form-action ''none''">');
    SB.Append('<meta charset="UTF-8">');
    SB.Append('<title>ELN Report</title>');
    SB.Append('<style>').Append(GetCss(Options.PaperSize)).Append('</style>');
    SB.Append('</head><body>');

    // Lab logo
    BuildLogo(SB, Options.LogoPath);

    // Table of Contents (only for multi-item reports)
    if Items.Count > 1 then
    begin
      SB.Append('<div class="toc">');
      SB.Append('<h1>Table of Contents</h1>');
      SB.Append('<ol class="toc-list">');
      for I := 0 to Items.Count - 1 do
      begin
        var TocItem := Items[I].Item;
        var LvlStr := GetEnumName(TypeInfo(TItemLevel), Ord(TocItem.Level));
        var TypStr := GetEnumName(TypeInfo(TItemType), Ord(TocItem.Type_));
        SB.Append('<li><a href="#item-').Append(IntToStr(I)).Append('">');
        SB.Append(HtmlEncode(TocItem.Title));
        SB.Append('</a> <span class="badge badge-type">').Append(HtmlEncode(LvlStr));
        SB.Append(' &middot; ').Append(HtmlEncode(TypStr)).Append('</span></li>');
      end;
      SB.Append('</ol>');
      SB.Append('</div>');
      SB.Append('<div class="page-break"></div>');
    end;

    for I := 0 to Items.Count - 1 do
    begin
      Data := Items[I];
      Item := Data.Item;

      // Page break between items (not before the first)
      if I > 0 then
        SB.Append('<div class="page-break"></div>');

      BuildHeader(SB, Item, I);

      if Options.IncludeMetadata then
        BuildMetadata(SB, Item);

      if Options.IncludeProtocols then
      begin
        HasProtocols := False;
        for var Entry in Item.Entries do
          if Entry is TProtocol then
          begin
            HasProtocols := True;
            Break;
          end;
        if HasProtocols then
          BuildProtocols(SB, Item, Data.Templates);
      end;

      if Options.IncludeValues then
      begin
        HasValues := Item.Values.Count > 0;
        if HasValues then
          BuildValues(SB, Item);
      end;

      if Options.IncludeFiles then
      begin
        HasFiles := Item.Files.Count > 0;
        if HasFiles then
          BuildFiles(SB, Item, Data.StorageRoot);
      end;

      if Options.IncludeTags and Assigned(Data.Tags) and (Data.Tags.Count > 0) then
        BuildTags(SB, Data.Tags);

      if Options.IncludeComments and Assigned(Data.Comments) and (Data.Comments.Count > 0) then
        BuildComments(SB, Data.Comments);

      if Options.IncludeSignatures and Data.HasSignature and Assigned(Data.Signature) then
        BuildSignature(SB, Data.Signature, Data.IntegrityOk);

      SB.Append('</div>'); // close item-section from BuildHeader
    end;

    // Footer
    SB.Append('<div class="report-footer">');
    SB.Append('Generated by E-Lab Notebook &middot; ');
    SB.Append(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    SB.Append('</div>');

    SB.Append('</body></html>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
