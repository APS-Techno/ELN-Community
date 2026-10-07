unit unit_MarkdownPreviewText;

{
  Flattens raw markdown into a short list of classified display lines for the
  thumbnail renderer.

  This is deliberately NOT a markdown parser: the thumbnail only has to be
  recognisable at 400x300, so block kinds are classified by their line prefix
  and inline markup is stripped rather than interpreted. Kept free of
  Vcl.Graphics so it can be unit-tested from a console harness — the drawing
  lives in unit_MarkdownPreviewRender.
}

interface

uses
  System.SysUtils, System.Classes;

type
  TPreviewLineStyle = (plsBody, plsH1, plsH2, plsH3, plsBullet, plsQuote,
    plsCode, plsRule, plsBlank);

  TPreviewLine = record
    Text:   string;
    Style:  TPreviewLineStyle;
    Indent: Integer;   // list nesting depth, 0 for everything else
  end;

const
  { Long lines are clipped by the renderer anyway; cap them so a minified or
    single-line document can't build a multi-megabyte string per line. }
  MaxPreviewLineChars = 300;
  MaxPreviewIndent    = 3;

function BuildPreviewLines(const AMarkdown: string;
  AMaxLines: Integer): TArray<TPreviewLine>;

{ Exposed for testing. }
function StripInlineMarkup(const ALine: string): string;

implementation

{ Index of the AClose that balances the AOpen at AStart, or 0 if unbalanced. }
function FindMatching(const S: string; AStart: Integer;
  AOpen, AClose: Char): Integer;
var
  I, Depth: Integer;
begin
  Result := 0;
  Depth := 0;
  for I := AStart to Length(S) do
  begin
    if S[I] = AOpen then
      Inc(Depth)
    else if S[I] = AClose then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(I);
    end;
  end;
end;

{ '[text](url)' -> 'text', '![alt](url)' -> 'alt', '[[item:5]]' -> 'item:5'. }
function FlattenLinks(const ALine: string): string;
var
  SB: TStringBuilder;
  I, BOpen, BClose, TOpen, TClose: Integer;
  IsImage: Boolean;
  Inner: string;
begin
  SB := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(ALine) do
    begin
      IsImage := (ALine[I] = '!') and (I < Length(ALine)) and (ALine[I + 1] = '[');
      if IsImage or (ALine[I] = '[') then
      begin
        if IsImage then
          BOpen := I + 1
        else
          BOpen := I;
        BClose := FindMatching(ALine, BOpen, '[', ']');
        if BClose > 0 then
        begin
          Inner := Copy(ALine, BOpen + 1, BClose - BOpen - 1);

          { Drop a trailing '(url)' target or '[ref]' label so only the visible
            text survives. }
          TClose := BClose;
          TOpen := BClose + 1;
          if TOpen <= Length(ALine) then
          begin
            if ALine[TOpen] = '(' then
              TClose := FindMatching(ALine, TOpen, '(', ')')
            else if ALine[TOpen] = '[' then
              TClose := FindMatching(ALine, TOpen, '[', ']');
            if TClose = 0 then
              TClose := BClose;
          end;

          { '[[item:5]]' arrives here as Inner='[item:5]' — unwrap the inner
            pair so ELN wiki links read as plain text. }
          if (Length(Inner) >= 2) and (Inner[1] = '[') and
             (Inner[Length(Inner)] = ']') then
            Inner := Copy(Inner, 2, Length(Inner) - 2);

          if IsImage and (Trim(Inner) = '') then
            Inner := '[image]';

          SB.Append(Inner);
          I := TClose + 1;
          Continue;
        end;
      end;
      SB.Append(ALine[I]);
      Inc(I);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ Underscores are left alone on purpose: snake_case identifiers are far more
  common in lab notes than '_emphasis_'. }
function StripEmphasis(const ALine: string): string;
begin
  Result := StringReplace(ALine, '**', '', [rfReplaceAll]);
  Result := StringReplace(Result, '~~', '', [rfReplaceAll]);
  Result := StringReplace(Result, '`', '', [rfReplaceAll]);
  Result := StringReplace(Result, '*', '', [rfReplaceAll]);
end;

function StripHtmlTags(const ALine: string): string;
var
  SB: TStringBuilder;
  I, J: Integer;
begin
  SB := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(ALine) do
    begin
      { Only a '<' followed by a tag name, '/' or '!' opens a tag — otherwise
        'a < b' would swallow the rest of the line. }
      if (ALine[I] = '<') and (I < Length(ALine)) and
         CharInSet(ALine[I + 1], ['a'..'z', 'A'..'Z', '/', '!']) then
      begin
        J := I + 1;
        while (J <= Length(ALine)) and (ALine[J] <> '>') do
          Inc(J);
        if J <= Length(ALine) then
        begin
          I := J + 1;
          Continue;
        end;
      end;
      SB.Append(ALine[I]);
      Inc(I);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CollapseSpaces(const ALine: string): string;
var
  SB: TStringBuilder;
  I: Integer;
  WasSpace: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    WasSpace := False;
    for I := 1 to Length(ALine) do
    begin
      if CharInSet(ALine[I], [' ', #9]) then
      begin
        if not WasSpace then
          SB.Append(' ');
        WasSpace := True;
      end
      else
      begin
        SB.Append(ALine[I]);
        WasSpace := False;
      end;
    end;
    Result := Trim(SB.ToString);
  finally
    SB.Free;
  end;
end;

function StripInlineMarkup(const ALine: string): string;
begin
  Result := CollapseSpaces(StripHtmlTags(StripEmphasis(FlattenLinks(ALine))));
end;

function IsFence(const ATrimmed: string): Boolean;
begin
  Result := ATrimmed.StartsWith('```') or ATrimmed.StartsWith('~~~');
end;

{ '---', '***', '___' (3 or more of a single char) — a thematic break. }
function IsRule(const ATrimmed: string): Boolean;
var
  I: Integer;
  C: Char;
begin
  Result := False;
  if Length(ATrimmed) < 3 then
    Exit;
  C := ATrimmed[1];
  if not CharInSet(C, ['-', '*', '_']) then
    Exit;
  for I := 2 to Length(ATrimmed) do
    if ATrimmed[I] <> C then
      Exit;
  Result := True;
end;

{ '|---|:--:|' — pure noise in a thumbnail. Assumes IsRule was checked first. }
function IsTableSeparator(const ATrimmed: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Length(ATrimmed) < 3) or (Pos('-', ATrimmed) = 0) then
    Exit;
  for I := 1 to Length(ATrimmed) do
    if not CharInSet(ATrimmed[I], ['|', '-', ':', ' ']) then
      Exit;
  Result := True;
end;

function ParseListMarker(const ALine: string; out AIndent: Integer;
  out AMarker, AContent: string): Boolean;
var
  I, Start: Integer;
begin
  Result := False;
  AIndent := 0;
  AMarker := '';
  AContent := '';

  I := 1;
  while (I <= Length(ALine)) and CharInSet(ALine[I], [' ', #9]) do
  begin
    if ALine[I] = #9 then
      Inc(AIndent, 4)
    else
      Inc(AIndent);
    Inc(I);
  end;
  if I > Length(ALine) then
    Exit;

  Start := I;
  if CharInSet(ALine[I], ['-', '*', '+']) then
  begin
    if (I >= Length(ALine)) or not CharInSet(ALine[I + 1], [' ', #9]) then
      Exit;
    AMarker := '-';
    Inc(I, 2);
  end
  else if CharInSet(ALine[I], ['0'..'9']) then
  begin
    while (I <= Length(ALine)) and CharInSet(ALine[I], ['0'..'9']) do
      Inc(I);
    if (I > Length(ALine)) or not CharInSet(ALine[I], ['.', ')']) then
      Exit;
    AMarker := Copy(ALine, Start, I - Start) + '.';
    Inc(I);
    if (I > Length(ALine)) or not CharInSet(ALine[I], [' ', #9]) then
      Exit;
    Inc(I);
  end
  else
    Exit;

  AContent := Copy(ALine, I, MaxInt);
  Result := True;
end;

function BuildPreviewLines(const AMarkdown: string;
  AMaxLines: Integer): TArray<TPreviewLine>;
var
  Src: TStringList;
  Res: TArray<TPreviewLine>;
  Count, I, J, Hashes, Ind: Integer;
  Raw, T, Marker, Content: string;
  InFence: Boolean;

  procedure Add(const AText: string; AStyle: TPreviewLineStyle; AIndent: Integer);
  var
    S: string;
  begin
    if Count >= AMaxLines then
      Exit;
    { Never lead with vertical space and never stack two blanks. }
    if (AStyle = plsBlank) and
       ((Count = 0) or (Res[Count - 1].Style = plsBlank)) then
      Exit;
    S := AText;
    if Length(S) > MaxPreviewLineChars then
      S := Copy(S, 1, MaxPreviewLineChars) + '...';
    Res[Count].Text := S;
    Res[Count].Style := AStyle;
    Res[Count].Indent := AIndent;
    Inc(Count);
  end;

begin
  Result := nil;
  if (AMaxLines <= 0) or (AMarkdown = '') then
    Exit;

  SetLength(Res, AMaxLines);
  Count := 0;
  InFence := False;

  Src := TStringList.Create;
  try
    Src.Text := AMarkdown;

    { YAML front matter: a leading '---' fence. Skipped wholesale — it is
      metadata, not page content. The closing delimiter must actually exist,
      otherwise a document that simply opens with a horizontal rule would be
      consumed in its entirety and preview as blank. }
    I := 0;
    J := 0;
    while (J < Src.Count) and (Trim(Src[J]) = '') do
      Inc(J);
    if (J < Src.Count) and (Trim(Src[J]) = '---') then
    begin
      Inc(J);
      while (J < Src.Count) and (Trim(Src[J]) <> '---') and
            (Trim(Src[J]) <> '...') do
        Inc(J);
      if J < Src.Count then
        I := J + 1;
    end;

    while (I < Src.Count) and (Count < AMaxLines) do
    begin
      Raw := Src[I];
      Inc(I);
      T := Trim(Raw);

      if IsFence(T) then
      begin
        InFence := not InFence;
        Continue;
      end;

      if InFence then
      begin
        { Verbatim, minus leading indentation so short snippets stay legible. }
        Add(TrimLeft(TrimRight(Raw)), plsCode, 0);
        Continue;
      end;

      if T = '' then
      begin
        Add('', plsBlank, 0);
        Continue;
      end;

      if IsRule(T) then
      begin
        Add('', plsRule, 0);
        Continue;
      end;

      if IsTableSeparator(T) then
        Continue;

      if T.StartsWith('#') then
      begin
        Hashes := 0;
        while (Hashes < Length(T)) and (T[Hashes + 1] = '#') do
          Inc(Hashes);
        { '#' with no space after it is not a heading (e.g. a '#tag'). }
        if (Hashes <= 6) and (Hashes < Length(T)) and
           CharInSet(T[Hashes + 1], [' ', #9]) then
        begin
          Content := StripInlineMarkup(Copy(T, Hashes + 1, MaxInt));
          { Trailing closing hashes are optional syntax: '## Title ##'. }
          while (Content <> '') and (Content[Length(Content)] = '#') do
            Content := TrimRight(Copy(Content, 1, Length(Content) - 1));
          case Hashes of
            1: Add(Content, plsH1, 0);
            2: Add(Content, plsH2, 0);
          else
            Add(Content, plsH3, 0);
          end;
          Continue;
        end;
      end;

      if T.StartsWith('>') then
      begin
        Content := T;
        while (Content <> '') and CharInSet(Content[1], ['>', ' ']) do
          Content := Copy(Content, 2, MaxInt);
        Add(StripInlineMarkup(Content), plsQuote, 0);
        Continue;
      end;

      if ParseListMarker(Raw, Ind, Marker, Content) then
      begin
        Ind := Ind div 2;
        if Ind > MaxPreviewIndent then
          Ind := MaxPreviewIndent;
        Add(Marker + ' ' + StripInlineMarkup(Content), plsBullet, Ind);
        Continue;
      end;

      Add(StripInlineMarkup(Raw), plsBody, 0);
    end;
  finally
    Src.Free;
  end;

  { Drop a trailing blank so the block doesn't end on empty space. }
  while (Count > 0) and (Res[Count - 1].Style = plsBlank) do
    Dec(Count);

  SetLength(Res, Count);
  Result := Res;
end;

end.
