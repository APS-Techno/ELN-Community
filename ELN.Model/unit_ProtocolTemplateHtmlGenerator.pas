unit unit_ProtocolTemplateHtmlGenerator;

interface

type
  TTemplateHtmlGenerator = class
  public
    class function GenerateHtml(const FormSchemaJson: string): string;
    class function ValidateSchema(const FormSchemaJson: string): string;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.RegularExpressions;

const
  CSS_TEMPLATE =
    'body{font-family:''Segoe UI'',Arial,sans-serif;margin:20px;color:#222;font-size:13px;background:#fff;}' +
    'h2{margin:0 0 4px 0;font-size:18px;font-weight:600;color:{{ACCENT}};}' +
    '.subtitle{color:#777;font-size:11px;margin-bottom:16px;border-bottom:2px solid {{ACCENT}};padding-bottom:8px;}' +
    'fieldset{border:1px solid #ddd;border-radius:4px;padding:12px 16px;margin-bottom:14px;}' +
    'legend{font-weight:600;font-size:13px;color:{{ACCENT}};padding:0 6px;}' +
    'label{display:block;margin:8px 0 3px 0;font-weight:600;font-size:12px;color:#555;}' +
    'input,select,textarea{width:100%;padding:5px 8px;border:1px solid #ccc;border-radius:3px;' +
    'font-size:13px;box-sizing:border-box;font-family:inherit;}' +
    'input:focus,select:focus,textarea:focus{border-color:{{ACCENT}};outline:none;' +
    'box-shadow:0 0 3px rgba(0,0,0,0.15);}' +
    '.row{display:flex;gap:12px;}.col{flex:1;}' +
    '.cb-group{display:flex;flex-wrap:wrap;gap:8px 18px;margin-top:4px;}' +
    '.cb-group label{display:inline-flex;align-items:center;gap:4px;font-weight:normal;margin:0;}' +
    '.cb-group input[type=checkbox]{width:auto;}' +
    'input[type=checkbox]:not(.cb-group input){width:auto;margin-right:6px;}' +
    '.rt-wrap{border:1px solid #ccc;border-radius:3px;margin-top:2px;}' +
    '.rt-bar{display:flex;gap:2px;padding:3px 4px;border-bottom:1px solid #ccc;background:#f7f7f7;flex-wrap:wrap;}' +
    '.rt-bar button{border:1px solid #bbb;background:#fff;border-radius:2px;' +
    'width:26px;height:24px;cursor:pointer;font-size:12px;font-family:inherit;padding:0;line-height:24px;}' +
    '.rt-bar button:hover{background:#e8e8e8;}' +
    '.rt-editor{min-height:80px;padding:6px 8px;outline:none;font-size:13px;font-family:inherit;}' +
    '.rt-editor:focus{box-shadow:0 0 3px rgba(0,0,0,0.15);}' +
    '.rt-disabled .rt-bar{display:none;}' +
    '.rt-disabled .rt-editor{background:#f5f5f5;cursor:default;}';

  DEFAULT_ACCENT = '#4a90d9';

// HTML-escape text and double-quoted attribute values. Schemas can arrive from
// untrusted .eln package imports, so every interpolated field must pass through
// this before reaching the WebView. (& must be replaced first.)
function HtmlEsc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

// accentColor is spliced into a <style> block, where HTML-escaping does NOT
// help ('</style>' would still break out). Allow only hex colours and CSS
// colour keywords (alphanumerics + '#'), plus a strict rgb()/rgba()/hsl()/
// hsla() functional form; anything else falls back to default.
function SanitizeColor(const S: string): string;
var
  C: Char;
  Simple: Boolean;
begin
  if (Length(S) = 0) or (Length(S) > 32) then Exit(DEFAULT_ACCENT);

  Simple := True;
  for C in S do
    if not CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '#']) then
    begin
      Simple := False;
      Break;
    end;
  if Simple then Exit(S);

  // Functional notation: rgb()/rgba()/hsl()/hsla(). Only digits, dot, comma,
  // percent and whitespace are permitted between the parentheses, so the value
  // cannot contain a quote, ';', '}' or '<' and therefore cannot break out of
  // the CSS declaration or the surrounding <style> block. Anything else falls
  // back to the default accent.
  if TRegEx.IsMatch(S, '^(?:rgb|rgba|hsl|hsla)\(\s*[0-9.,%\s]+\)$',
       [roIgnoreCase]) then
    Exit(S);

  Result := DEFAULT_ACCENT;
end;

class function TTemplateHtmlGenerator.ValidateSchema(const FormSchemaJson: string): string;
var
  JsonVal: TJSONValue;
  Root: TJSONObject;
  Sections, Rows, Fields, Opts: TJSONArray;
  I, J, K, L: Integer;
  Section, Row, Field: TJSONObject;
  OptsVal: TJSONValue;
  FieldType: string;
begin
  Result := '';

  if Trim(FormSchemaJson) = '' then
  begin
    Result := 'Schema is empty';
    Exit;
  end;

  try
    JsonVal := TJSONObject.ParseJSONValue(FormSchemaJson);
  except
    on E: Exception do
    begin
      Result := 'Invalid JSON: ' + E.Message;
      Exit;
    end;
  end;

  if not Assigned(JsonVal) then
  begin
    Result := 'Invalid JSON';
    Exit;
  end;

  try
    if not (JsonVal is TJSONObject) then
    begin
      Result := 'Root must be a JSON object';
      Exit;
    end;

    Root := TJSONObject(JsonVal);

    if Root.GetValue('sections') = nil then
    begin
      Result := 'Missing "sections" array';
      Exit;
    end;

    if not (Root.GetValue('sections') is TJSONArray) then
    begin
      Result := '"sections" must be an array';
      Exit;
    end;

    Sections := TJSONArray(Root.GetValue('sections'));
    for I := 0 to Sections.Count - 1 do
    begin
      if not (Sections.Items[I] is TJSONObject) then
      begin
        Result := Format('sections[%d] must be an object', [I]);
        Exit;
      end;

      Section := TJSONObject(Sections.Items[I]);

      if Section.GetValue('rows') = nil then
      begin
        Result := Format('sections[%d]: missing "rows"', [I]);
        Exit;
      end;

      if not (Section.GetValue('rows') is TJSONArray) then
      begin
        Result := Format('sections[%d]: "rows" must be an array', [I]);
        Exit;
      end;

      Rows := TJSONArray(Section.GetValue('rows'));
      for J := 0 to Rows.Count - 1 do
      begin
        if not (Rows.Items[J] is TJSONObject) then
        begin
          Result := Format('sections[%d].rows[%d] must be an object', [I, J]);
          Exit;
        end;

        Row := TJSONObject(Rows.Items[J]);

        if Row.GetValue('fields') = nil then
        begin
          Result := Format('sections[%d].rows[%d]: missing "fields"', [I, J]);
          Exit;
        end;

        if not (Row.GetValue('fields') is TJSONArray) then
        begin
          Result := Format('sections[%d].rows[%d]: "fields" must be an array', [I, J]);
          Exit;
        end;

        Fields := TJSONArray(Row.GetValue('fields'));
        for K := 0 to Fields.Count - 1 do
        begin
          if not (Fields.Items[K] is TJSONObject) then
          begin
            Result := Format('sections[%d].rows[%d].fields[%d] must be an object', [I, J, K]);
            Exit;
          end;

          Field := TJSONObject(Fields.Items[K]);

          if Field.GetValue('name') = nil then
          begin
            Result := Format('sections[%d].rows[%d].fields[%d]: missing "name"', [I, J, K]);
            Exit;
          end;

          if Field.GetValue('type') = nil then
          begin
            Result := Format('sections[%d].rows[%d].fields[%d]: missing "type"', [I, J, K]);
            Exit;
          end;

          FieldType := Field.GetValue('type').Value;
          if (FieldType <> 'text') and (FieldType <> 'number') and (FieldType <> 'date') and
             (FieldType <> 'select') and (FieldType <> 'textarea') and
             (FieldType <> 'checkbox') and (FieldType <> 'checkbox-group') and
             (FieldType <> 'richtext') then
          begin
            Result := Format('sections[%d].rows[%d].fields[%d]: unknown type "%s"', [I, J, K, FieldType]);
            Exit;
          end;

          // Options: validate only that each entry is an object. Individual
          // keys (label/value/name) are intentionally NOT required — GenerateHtml
          // defaults them (label<-value/name, value/name<-''), so an option
          // missing them still renders. Requiring them here would reject
          // templates that imported and displayed fine before this validator
          // existed (the generator is the tolerance contract; match it).
          if (FieldType = 'select') or (FieldType = 'checkbox-group') then
          begin
            OptsVal := Field.GetValue('options');
            if (OptsVal <> nil) and (OptsVal is TJSONArray) then
            begin
              Opts := TJSONArray(OptsVal);
              for L := 0 to Opts.Count - 1 do
                if not (Opts.Items[L] is TJSONObject) then
                begin
                  Result := Format('sections[%d].rows[%d].fields[%d].options[%d] must be an object', [I, J, K, L]);
                  Exit;
                end;
            end;
          end;
        end;
      end;
    end;
  finally
    JsonVal.Free;
  end;
end;

class function TTemplateHtmlGenerator.GenerateHtml(const FormSchemaJson: string): string;
var
  JsonVal: TJSONValue;
  Root: TJSONObject;
  Sections, Rows, Fields, Options: TJSONArray;
  Section, Row, Field, Option: TJSONObject;
  I, J, K, L, RowsAttr: Integer;
  Title, AccentColor, Css: string;
  SB: TStringBuilder;
  FieldName, FieldType, FieldLabel, Placeholder, FlexStr: string;
  FieldCount: Integer;
begin
  Result := '';

  JsonVal := TJSONObject.ParseJSONValue(FormSchemaJson);
  if not Assigned(JsonVal) then Exit;

  try
    if not (JsonVal is TJSONObject) then Exit;
    Root := TJSONObject(JsonVal);

    Title := '';
    if Root.GetValue('title') <> nil then
      Title := Root.GetValue('title').Value;

    AccentColor := DEFAULT_ACCENT;
    if Root.GetValue('accentColor') <> nil then
      AccentColor := SanitizeColor(Root.GetValue('accentColor').Value);

    Css := StringReplace(CSS_TEMPLATE, '{{ACCENT}}', AccentColor, [rfReplaceAll]);

    SB := TStringBuilder.Create;
    try
      SB.Append('<!DOCTYPE html><html><head><meta charset="UTF-8"><style>');
      SB.Append(Css);
      SB.Append('</style><script>function execCmd(c){document.execCommand(c,false,null);}</script></head><body>');

      if Title <> '' then
      begin
        SB.Append('<h2>');
        SB.Append(HtmlEsc(Title));
        SB.Append('</h2>');
      end;

      // A missing or non-array "sections" is not fatal — emit the (possibly
      // title-only) document rather than AV on a bad hard-cast.
      if not (Root.GetValue('sections') is TJSONArray) then
      begin
        SB.Append('</body></html>');
        Result := SB.ToString;
        Exit;
      end;

      Sections := TJSONArray(Root.GetValue('sections'));
      for I := 0 to Sections.Count - 1 do
      begin
        if not (Sections.Items[I] is TJSONObject) then Continue;
        Section := TJSONObject(Sections.Items[I]);

        SB.Append('<fieldset>');
        if Section.GetValue('title') <> nil then
        begin
          SB.Append('<legend>');
          SB.Append(HtmlEsc(Section.GetValue('title').Value));
          SB.Append('</legend>');
        end;

        if not (Section.GetValue('rows') is TJSONArray) then
        begin
          SB.Append('</fieldset>');
          Continue;
        end;

        Rows := TJSONArray(Section.GetValue('rows'));
        for J := 0 to Rows.Count - 1 do
        begin
          if not (Rows.Items[J] is TJSONObject) then Continue;
          Row := TJSONObject(Rows.Items[J]);
          if not (Row.GetValue('fields') is TJSONArray) then Continue;
          Fields := TJSONArray(Row.GetValue('fields'));
          FieldCount := Fields.Count;

          if FieldCount > 1 then
            SB.Append('<div class="row">');

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

            Placeholder := '';
            if Field.GetValue('placeholder') <> nil then
              Placeholder := Field.GetValue('placeholder').Value;

            // Escape everything that gets emitted (text or attribute value).
            // FieldType is left raw here because it drives the branch
            // comparisons below; it is escaped at its single output point.
            FieldName := HtmlEsc(FieldName);
            FieldLabel := HtmlEsc(FieldLabel);
            Placeholder := HtmlEsc(Placeholder);

            if FieldCount > 1 then
            begin
              FlexStr := '';
              if (Field.GetValue('flex') <> nil) then
              begin
                if Field.GetValue('flex') is TJSONNumber then
                begin
                  if TJSONNumber(Field.GetValue('flex')).AsInt > 1 then
                    FlexStr := Format(' style="flex:%d"', [TJSONNumber(Field.GetValue('flex')).AsInt]);
                end;
              end;
              SB.Append('<div class="col"' + FlexStr + '>');
            end;

            if FieldType = 'textarea' then
            begin
              SB.Append('<label>');
              SB.Append(FieldLabel);
              SB.Append('</label>');

              RowsAttr := 3;
              if (Field.GetValue('rows') <> nil) and (Field.GetValue('rows') is TJSONNumber) then
                RowsAttr := TJSONNumber(Field.GetValue('rows')).AsInt;

              SB.AppendFormat('<textarea name="%s" rows="%d" placeholder="%s"></textarea>',
                [FieldName, RowsAttr, Placeholder]);
            end
            else if FieldType = 'select' then
            begin
              SB.Append('<label>');
              SB.Append(FieldLabel);
              SB.Append('</label>');
              SB.AppendFormat('<select name="%s">', [FieldName]);

              if (Field.GetValue('options') <> nil) and (Field.GetValue('options') is TJSONArray) then
              begin
                Options := TJSONArray(Field.GetValue('options'));
                for L := 0 to Options.Count - 1 do
                begin
                  if Options.Items[L] is TJSONObject then
                  begin
                    Option := TJSONObject(Options.Items[L]);
                    var OptVal := '';
                    if Option.GetValue('value') <> nil then
                      OptVal := Option.GetValue('value').Value;
                    var OptLabel := OptVal;
                    if Option.GetValue('label') <> nil then
                      OptLabel := Option.GetValue('label').Value;
                    SB.AppendFormat('<option value="%s">%s</option>',
                      [HtmlEsc(OptVal), HtmlEsc(OptLabel)]);
                  end;
                end;
              end;

              SB.Append('</select>');
            end
            else if FieldType = 'checkbox' then
            begin
              SB.Append('<label>');
              SB.AppendFormat('<input type="checkbox" name="%s"> %s', [FieldName, FieldLabel]);
              SB.Append('</label>');
            end
            else if FieldType = 'richtext' then
            begin
              SB.Append('<label>');
              SB.Append(FieldLabel);
              SB.Append('</label>');

              RowsAttr := 0;
              if (Field.GetValue('rows') <> nil) and (Field.GetValue('rows') is TJSONNumber) then
                RowsAttr := TJSONNumber(Field.GetValue('rows')).AsInt * 24;
              if RowsAttr < 80 then
                RowsAttr := 80;

              SB.Append('<div class="rt-wrap">');
              SB.Append('<div class="rt-bar">');
              SB.Append('<button type="button" onclick="execCmd(''bold'')" title="Bold"><b>B</b></button>');
              SB.Append('<button type="button" onclick="execCmd(''italic'')" title="Italic"><i>I</i></button>');
              SB.Append('<button type="button" onclick="execCmd(''underline'')" title="Underline"><u>U</u></button>');
              SB.Append('<button type="button" onclick="execCmd(''strikeThrough'')" title="Strikethrough"><s>S</s></button>');
              SB.Append('<button type="button" onclick="execCmd(''subscript'')" title="Subscript">X<sub>2</sub></button>');
              SB.Append('<button type="button" onclick="execCmd(''superscript'')" title="Superscript">X<sup>2</sup></button>');
              SB.Append('<button type="button" onclick="execCmd(''insertUnorderedList'')" title="Bullet list">&#8226;</button>');
              SB.Append('<button type="button" onclick="execCmd(''insertOrderedList'')" title="Numbered list">1.</button>');
              SB.Append('<button type="button" onclick="execCmd(''removeFormat'')" title="Clear formatting">&#10005;</button>');
              SB.Append('</div>');
              SB.AppendFormat('<div class="rt-editor" contenteditable="true" data-name="%s" style="min-height:%dpx"></div>',
                [FieldName, RowsAttr]);
              SB.Append('</div>');
            end
            else if FieldType = 'checkbox-group' then
            begin
              SB.Append('<label>');
              SB.Append(FieldLabel);
              SB.Append('</label>');
              SB.Append('<div class="cb-group">');

              if (Field.GetValue('options') <> nil) and (Field.GetValue('options') is TJSONArray) then
              begin
                Options := TJSONArray(Field.GetValue('options'));
                for L := 0 to Options.Count - 1 do
                begin
                  if Options.Items[L] is TJSONObject then
                  begin
                    Option := TJSONObject(Options.Items[L]);
                    var OptName := '';
                    if Option.GetValue('name') <> nil then
                      OptName := Option.GetValue('name').Value;
                    var OptLabel := OptName;
                    if Option.GetValue('label') <> nil then
                      OptLabel := Option.GetValue('label').Value;
                    SB.AppendFormat('<label><input type="checkbox" name="%s"> %s</label>',
                      [HtmlEsc(OptName), HtmlEsc(OptLabel)]);
                  end;
                end;
              end;

              SB.Append('</div>');
            end
            else
            begin
              SB.Append('<label>');
              SB.Append(FieldLabel);
              SB.Append('</label>');
              SB.AppendFormat('<input type="%s" name="%s" placeholder="%s">',
                [HtmlEsc(FieldType), FieldName, Placeholder]);
            end;

            if FieldCount > 1 then
              SB.Append('</div>');
          end;

          if FieldCount > 1 then
            SB.Append('</div>');
        end;

        SB.Append('</fieldset>');
      end;

      SB.Append('</body></html>');
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  finally
    JsonVal.Free;
  end;
end;

end.
