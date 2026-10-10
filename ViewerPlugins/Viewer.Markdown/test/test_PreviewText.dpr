program test_PreviewText;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  unit_MarkdownPreviewText in '..\unit_MarkdownPreviewText.pas';

var
  Failures: Integer = 0;

procedure AssertEq(const ATestName, AExpected, AActual: string);
begin
  if AExpected = AActual then
    Writeln('PASS ', ATestName)
  else
  begin
    Inc(Failures);
    Writeln('FAIL ', ATestName);
    Writeln('  expected: ', AExpected);
    Writeln('  actual:   ', AActual);
  end;
end;

procedure AssertEqI(const ATestName: string; AExpected, AActual: Integer);
begin
  AssertEq(ATestName, IntToStr(AExpected), IntToStr(AActual));
end;

function StyleName(AStyle: TPreviewLineStyle): string;
begin
  case AStyle of
    plsBody:   Result := 'body';
    plsH1:     Result := 'h1';
    plsH2:     Result := 'h2';
    plsH3:     Result := 'h3';
    plsBullet: Result := 'bullet';
    plsQuote:  Result := 'quote';
    plsCode:   Result := 'code';
    plsRule:   Result := 'rule';
    plsBlank:  Result := 'blank';
  else
    Result := '?';
  end;
end;

function Flatten(const AMarkdown: string; AMaxLines: Integer = 50): string;
var
  Lines: TArray<TPreviewLine>;
  I: Integer;
begin
  Result := '';
  Lines := BuildPreviewLines(AMarkdown, AMaxLines);
  for I := 0 to High(Lines) do
  begin
    if I > 0 then
      Result := Result + ';';
    Result := Result + StyleName(Lines[I].Style) + '|' + Lines[I].Text;
    if Lines[I].Indent > 0 then
      Result := Result + '@' + IntToStr(Lines[I].Indent);
  end;
end;

function LF(const AParts: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := Low(AParts) to High(AParts) do
  begin
    if I > Low(AParts) then
      Result := Result + sLineBreak;
    Result := Result + AParts[I];
  end;
end;

begin

  AssertEq('StripsBold', 'hello world',
    StripInlineMarkup('**hello** world'));

  AssertEq('StripsItalicAsterisk', 'hello world',
    StripInlineMarkup('*hello* world'));

  AssertEq('StripsInlineCode', 'run make all now',
    StripInlineMarkup('run `make all` now'));

  AssertEq('StripsStrikethrough', 'gone',
    StripInlineMarkup('~~gone~~'));

  AssertEq('KeepsUnderscoresForSnakeCase', 'atom_style full',
    StripInlineMarkup('atom_style full'));

  AssertEq('FlattensLinkToText', 'see the docs here',
    StripInlineMarkup('see [the docs](https://example.com) here'));

  AssertEq('FlattensImageToAltText', 'XRR scan',
    StripInlineMarkup('![XRR scan](scan.png)'));

  AssertEq('NamesUnlabelledImage', '[image]',
    StripInlineMarkup('![](scan.png)'));

  AssertEq('FlattensReferenceLink', 'the docs',
    StripInlineMarkup('[the docs][ref1]'));

  AssertEq('UnwrapsElnWikiLink', 'item:534',
    StripInlineMarkup('[[item:534]]'));

  AssertEq('UnwrapsSpecimenWikiLink', 'see specimen:WB4C-001 now',
    StripInlineMarkup('see [[specimen:WB4C-001]] now'));

  AssertEq('StripsHtmlTags', 'bold bit',
    StripInlineMarkup('<span class="x">bold bit</span>'));

  AssertEq('KeepsLessThanInProse', 'a < b and c > d',
    StripInlineMarkup('a < b and c > d'));

  AssertEq('CollapsesWhitespaceRuns', 'a b c',
    StripInlineMarkup('a    b'#9'c'));

  AssertEq('LeavesPlainTextAlone', 'plain sentence.',
    StripInlineMarkup('plain sentence.'));


  AssertEq('ClassifiesAtxHeadings',
    'h1|Title;h2|Section;h3|Sub;h3|Deeper',
    Flatten(LF(['# Title', '## Section', '### Sub', '#### Deeper'])));

  AssertEq('StripsClosingHashes', 'h2|Section',
    Flatten('## Section ##'));

  AssertEq('HashWithoutSpaceIsNotAHeading', 'body|#tag',
    Flatten('#tag'));

  AssertEq('ClassifiesUnorderedBullets',
    'bullet|- one;bullet|- two',
    Flatten(LF(['- one', '* two'])));

  AssertEq('KeepsOrderedMarkers',
    'bullet|1. first;bullet|2. second',
    Flatten(LF(['1. first', '2) second'])));

  AssertEq('TracksNestedListIndent',
    'bullet|- top;bullet|- nested@1',
    Flatten(LF(['- top', '  - nested'])));

  AssertEq('ClassifiesBlockquote', 'quote|note this',
    Flatten('> note this'));

  AssertEq('ClassifiesHorizontalRule',
    'h1|A;rule|;h1|B',
    Flatten(LF(['# A', '---', '# B'])));

  AssertEq('KeepsFencedCodeVerbatim',
    'code|x = a_b * 2;code|y = **x',
    Flatten(LF(['```python', 'x = a_b * 2', 'y = **x', '```'])));

  AssertEq('DropsTableSeparatorRow',
    'body|| a | b |;body|| 1 | 2 |',
    Flatten(LF(['| a | b |', '|---|---|', '| 1 | 2 |'])));


  AssertEq('CollapsesBlankRuns',
    'h1|Title;blank|;body|body text',
    Flatten(LF(['# Title', '', '', '', 'body text'])));

  AssertEq('DropsLeadingBlanks', 'h1|Title',
    Flatten(LF(['', '', '# Title'])));

  AssertEq('DropsTrailingBlanks', 'h1|Title',
    Flatten(LF(['# Title', '', ''])));

  AssertEq('SkipsYamlFrontMatter',
    'h1|Real Title',
    Flatten(LF(['---', 'title: Meta', 'tags: [a, b]', '---', '# Real Title'])));

  AssertEq('LeadingRuleWithoutCloseIsNotFrontMatter',
    'rule|;h1|Title',
    Flatten(LF(['---', '# Title'])));


  AssertEqI('RespectsMaxLines', 2,
    Length(BuildPreviewLines(LF(['a', 'b', 'c', 'd']), 2)));

  AssertEqI('EmptyInputYieldsNoLines', 0,
    Length(BuildPreviewLines('', 50)));

  AssertEqI('ZeroMaxLinesYieldsNoLines', 0,
    Length(BuildPreviewLines('# Title', 0)));

  AssertEqI('TruncatesVeryLongLine', MaxPreviewLineChars + 3,
    Length(BuildPreviewLines(StringOfChar('x', 1000), 5)[0].Text));

  Writeln('');
  if Failures > 0 then
  begin
    Writeln('FAILED: ', Failures);
    Halt(1);
  end;
  Writeln('ALL PASS');
end.
