program test_MarkdownFormatting;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  unit_MarkdownFormatting in '..\unit_MarkdownFormatting.pas';

var
  Failures: Integer = 0;

procedure AssertEq(const ATestName, AExpected, AActual: string); overload;
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

procedure AssertEq(const ATestName: string; AExpected, AActual: Integer); overload;
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

begin
  AssertEq(
    'WrapBold',
    '**hello**',
    WrapSelection('hello', 1, 5, '**', '**').NewText);

  AssertEq(
    'WrapEmptyAtStart_Text',
    '****',
    WrapSelection('', 1, 0, '**', '**').NewText);
  AssertEq(
    'WrapEmptyAtStart_SelStart',
    3,
    WrapSelection('', 1, 0, '**', '**').NewSelStart);

  AssertEq(
    'WrapEmptyMiddle_Text',
    'abc**def',
    WrapSelection('abcdef', 4, 0, '*', '*').NewText);
  AssertEq(
    'WrapEmptyMiddle_SelStart',
    5,
    WrapSelection('abcdef', 4, 0, '*', '*').NewSelStart);

  AssertEq(
    'WrapMultiline',
    '**foo'#13#10'bar**',
    WrapSelection('foo'#13#10'bar', 1, 8, '**', '**').NewText);

  AssertEq(
    'UnwrapWhenAlreadyWrappedExactly',
    'hello',
    WrapSelection('**hello**', 3, 5, '**', '**').NewText);

  AssertEq(
    'IdempotentToggleEmptyOnEmpty',
    '',
    WrapSelection('****', 3, 0, '**', '**').NewText);

  AssertEq(
    'WrapItalicSingleStar',
    '*hello*',
    WrapSelection('hello', 1, 5, '*', '*').NewText);

  AssertEq(
    'WrapInlineCode',
    '`hello`',
    WrapSelection('hello', 1, 5, '`', '`').NewText);

  AssertEq(
    'PrefixSingleLineBullet',
    '- one',
    PrefixLines('one', 1, 3, '- ').NewText);

  AssertEq(
    'PrefixMultilineBullet',
    '- one'#13#10'- two',
    PrefixLines('one'#13#10'two', 1, 7, '- ').NewText);

  AssertEq(
    'StripExistingPrefix',
    'one'#13#10'two',
    PrefixLines('- one'#13#10'- two', 1, 11, '- ').NewText);

  AssertEq(
    'MixedPrefixOnlyAddsToBare',
    'one'#13#10'- two',
    PrefixLines('- one'#13#10'two', 1, 9, '- ').NewText);

  AssertEq(
    'PrefixBlockQuote',
    '> hello',
    PrefixLines('hello', 1, 5, '> ').NewText);

  AssertEq(
    'AddH1',
    '# hello',
    MakeHeading('hello', 1, 1).NewText);

  AssertEq(
    'AddH3',
    '### hello',
    MakeHeading('hello', 1, 3).NewText);

  AssertEq(
    'StripExistingThenAddH2',
    '## hello',
    MakeHeading('# hello', 1, 2).NewText);

  AssertEq(
    'Level0Strips',
    'hello',
    MakeHeading('### hello', 1, 0).NewText);

  AssertEq(
    'IdempotentSameLevelTogglesOff',
    'hello',
    MakeHeading('## hello', 1, 2).NewText);

  AssertEq(
    'WorksOnMultilineDocument',
    'alpha'#13#10'# beta',
    MakeHeading('alpha'#13#10'beta', 8, 1).NewText);

  Writeln('');
  if Failures > 0 then
  begin
    Writeln('FAILED: ', Failures);
    Halt(1);
  end;
  Writeln('ALL PASS');
end.
