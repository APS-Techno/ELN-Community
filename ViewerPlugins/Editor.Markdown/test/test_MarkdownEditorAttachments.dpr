program test_MarkdownEditorAttachments;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.DateUtils,
  unit_MarkdownEditorAttachments in '..\unit_MarkdownEditorAttachments.pas';

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

function B(AValue: Boolean): string;
begin
  Result := BoolToStr(AValue, True);
end;

begin
  // ---- IsImageExt ----
  AssertEq('IsImageExt_PngWithDot',     'True',  B(IsImageExt('.png')));
  AssertEq('IsImageExt_JpgWithoutDot',  'True',  B(IsImageExt('jpg')));
  AssertEq('IsImageExt_JpegMixedCase',  'True',  B(IsImageExt('.JPeg')));
  AssertEq('IsImageExt_GifUpper',       'True',  B(IsImageExt('GIF')));
  AssertEq('IsImageExt_WebpDot',        'True',  B(IsImageExt('.webp')));
  AssertEq('IsImageExt_SvgDot',         'True',  B(IsImageExt('.svg')));
  AssertEq('IsImageExt_BmpDot',         'True',  B(IsImageExt('.bmp')));
  AssertEq('IsImageExt_PdfFalse',       'False', B(IsImageExt('.pdf')));
  AssertEq('IsImageExt_TxtFalse',       'False', B(IsImageExt('.txt')));
  AssertEq('IsImageExt_EmptyFalse',     'False', B(IsImageExt('')));

  // ---- BuildInsertSnippet ----
  AssertEq('SnippetSimpleImage',
    '![](shot.png)',
    BuildInsertSnippet('shot.png', True));

  AssertEq('SnippetImageWithSpaces',
    '![](my%20file.png)',
    BuildInsertSnippet('my file.png', True));

  AssertEq('SnippetImageBrackets',
    '![]([1042]thing.png)',
    BuildInsertSnippet('[1042]thing.png', True));

  AssertEq('SnippetSimpleNonImage',
    '[doc.pdf](doc.pdf)',
    BuildInsertSnippet('doc.pdf', False));

  AssertEq('SnippetNonImageWithSpaces',
    '[my doc.pdf](my%20doc.pdf)',
    BuildInsertSnippet('my doc.pdf', False));

  AssertEq('SnippetEmptyName',
    '![]()',
    BuildInsertSnippet('', True));

  // ---- ClipboardImageFileName ----
  AssertEq('ClipboardName_2026Apr27_153012',
    'paste-20260427-153012.png',
    ClipboardImageFileName(EncodeDateTime(2026, 4, 27, 15, 30, 12, 0)));

  AssertEq('ClipboardName_LeadingZeroes',
    'paste-20260105-090503.png',
    ClipboardImageFileName(EncodeDateTime(2026, 1, 5, 9, 5, 3, 0)));

  Writeln('');
  if Failures > 0 then
  begin
    Writeln('FAILED: ', Failures);
    Halt(1);
  end;
  Writeln('ALL PASS');
end.
