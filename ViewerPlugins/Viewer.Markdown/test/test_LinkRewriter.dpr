program test_LinkRewriter;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  unit_MarkdownLinkRewriter in '..\unit_MarkdownLinkRewriter.pas';

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

begin
  AssertEq(
    'RewritesItemLink',
    '<a class="eln-link" href="eln://item/534">item:534</a>',
    RewriteElnLinks('[[item:534]]'));

  AssertEq(
    'RewritesSpecimenLink',
    '<a class="eln-link" href="eln://specimen/WB4C-001">specimen:WB4C-001</a>',
    RewriteElnLinks('[[specimen:WB4C-001]]'));

  AssertEq(
    'LeavesPlainMarkdownLinksAlone',
    '[ELN](https://example.com)',
    RewriteElnLinks('[ELN](https://example.com)'));

  AssertEq(
    'IgnoresSingleBrackets',
    '[item:534]',
    RewriteElnLinks('[item:534]'));

  AssertEq(
    'HandlesMultipleLinksInOneLine',
    'a <a class="eln-link" href="eln://item/1">item:1</a> b <a class="eln-link" href="eln://item/2">item:2</a> c',
    RewriteElnLinks('a [[item:1]] b [[item:2]] c'));

  AssertEq(
    'IgnoresUnknownKind',
    '[[project:42]]',
    RewriteElnLinks('[[project:42]]'));

  AssertEq(
    'IgnoresTokensWithWhitespaceInRef',
    '[[item:5 34]]',
    RewriteElnLinks('[[item:5 34]]'));

  AssertEq(
    'IgnoresTokensSpanningLines',
    '[[item:1' + sLineBreak + 'stuff]]',
    RewriteElnLinks('[[item:1' + sLineBreak + 'stuff]]'));

  Writeln('');
  if Failures > 0 then
  begin
    Writeln('FAILED: ', Failures);
    Halt(1);
  end;
  Writeln('ALL PASS');
end.
