unit test_SharedViewerRegressions;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSharedViewerRegressions = class
  public
    [Test] procedure ExportPreservesSparseRows;
    [Test] procedure ExportPreservesRepeatedXAndInvalidCells;
    [Test] procedure AttachmentReservedCharactersResolveOnce;
    [Test] procedure AttachmentLiteralPercentIsNotAnEscape;
    [Test] procedure FileUrlEncodesPathSegments;
    [Test] procedure AttachmentPageIsNotTheMarkdownShell;
    [Test] procedure MissingExplicitPartnerRejectsTimestampDecoy;
    [Test] procedure NoExplicitPartnerStillUsesTimestamp;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  unit_ColumnarClassify, unit_MarkdownEditorAttachments,
  unit_MarkdownAttachmentResolver, unit_DepoPairing;

procedure TSharedViewerRegressions.ExportPreservesSparseRows;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := 'x,a,b'#13#10'1,10,100'#13#10'2,,200'#13#10'3,30,300';
    Assert.AreEqual('x'#9'a'#9'b'#13#10'1'#9'10'#9'100'#13#10 +
      '2'#9#9'200'#13#10'3'#9'30'#9'300'#13#10,
      ColumnarTableToText(Lines, ClassifyColumnarText(Lines)));
  finally
    Lines.Free;
  end;
end;

procedure TSharedViewerRegressions.ExportPreservesRepeatedXAndInvalidCells;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := '# comment'#13#10'x,a,b'#13#10'1,10,100'#13#10 +
      '1,bad,200'#13#10'2,30'#13#10'3,,300';
    Assert.AreEqual('x'#9'a'#9'b'#13#10'1'#9'10'#9'100'#13#10 +
      '1'#9'bad'#9'200'#13#10'2'#9'30'#9#13#10'3'#9#9'300'#13#10,
      ColumnarTableToText(Lines, ClassifyColumnarText(Lines)));
  finally
    Lines.Free;
  end;
end;

procedure TSharedViewerRegressions.AttachmentReservedCharactersResolveOnce;
var
  Snippet, Resolved: string;
begin
  Snippet := BuildInsertSnippet('plot#1 (a)+b.png', True);
  Assert.AreEqual('![](plot%231%20%28a%29%2Bb.png)', Snippet);
  Resolved := RewriteAttachmentRefs(Snippet, '', ['[42]plot#1 (a)+b.png']);
  Assert.AreEqual('![](%5B42%5Dplot%231%20%28a%29%2Bb.png)', Resolved);
  Assert.AreEqual(Resolved,
    RewriteAttachmentRefs(Resolved, '', ['[42]plot#1 (a)+b.png']));
end;

procedure TSharedViewerRegressions.AttachmentLiteralPercentIsNotAnEscape;
begin
  Assert.AreEqual('![](%5B42%5Dplot%2523.png)', RewriteAttachmentRefs(
    BuildInsertSnippet('plot%23.png', True), '', ['[42]plot%23.png']));
  Assert.AreEqual('![](%5B42%5Dplot%231.png)', RewriteAttachmentRefs(
    BuildInsertSnippet('[42]plot#1.png', True), '', ['[42]plot#1.png']));
  Assert.AreEqual('![](%5B42%5Dplot%231.png)',
    RewriteAttachmentRefs('![](plot#1.png)', '', ['[42]plot#1.png']));
end;

procedure TSharedViewerRegressions.FileUrlEncodesPathSegments;
begin
  Assert.AreEqual('file:///C:/work%20%231/100%25/%5B42%5Dplot%2B1.png',
    MarkdownFileUrl('C:\work #1\100%\[42]plot+1.png'));
end;

procedure TSharedViewerRegressions.AttachmentPageIsNotTheMarkdownShell;
begin
  Assert.IsTrue(IsMarkdownShellUrl('file:///C:/assets/shell.html#heading',
    'file:///C:/assets/shell.html'));
  Assert.IsFalse(IsMarkdownShellUrl('file:///C:/attachments/page.html',
    'file:///C:/assets/shell.html'));
  Assert.IsFalse(IsMarkdownShellUrl('file:///C:/assets/shell.html.bak',
    'file:///C:/assets/shell.html'));
end;

procedure TSharedViewerRegressions.MissingExplicitPartnerRejectsTimestampDecoy;
begin
  Assert.AreEqual('', FindPairedTsv(
    '{"kind":"deposition-snapshot","outcome":{"dataFile":"missing.tsv"}}',
    'Deposition_test_2026-07-02_13-18-52.depo.json',
    ['2026-07-02_13-18-52_decoy.tsv']));
end;

procedure TSharedViewerRegressions.NoExplicitPartnerStillUsesTimestamp;
begin
  Assert.AreEqual('2026-07-02_13-18-52_run.tsv', FindPairedTsv(
    '{"kind":"deposition-snapshot"}',
    'Deposition_test_2026-07-02_13-18-52.depo.json',
    ['2026-07-02_13-18-52_run.tsv']));
end;

initialization
  TDUnitX.RegisterTestFixture(TSharedViewerRegressions);
end.
