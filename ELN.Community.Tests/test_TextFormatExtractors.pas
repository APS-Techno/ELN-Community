unit test_TextFormatExtractors;

interface

uses
  System.SysUtils, System.Classes, System.Zip, System.Generics.Collections, DUnitX.TestFramework,
  unit_TextExtractors, unit_TextStreamDecoder;

type
  [TestFixture]
  TTextFormatExtractorTests = class
  private
    FRegistryPdfPath: string;
    function Run(const Ext: string; const Bytes: TBytes): TExtractResult;
    function RunText(const Ext, Text: string): TExtractResult;
  public
    [Setup]
    procedure Setup;
    [Test]
    procedure DocxText;
    [Test]
    procedure DocxHeadersFooterAfterBody;
    [Test]
    procedure DocxMissingDocumentIsCorrupt;
    [Test]
    procedure DocxZipBombRejected;
    [Test]
    procedure DocxTooManyEntriesRejected;
    [Test]
    procedure DocxLyingHeaderStopsAtLimit;
    [Test]
    procedure DocxGarbageIsCorrupt;
    [Test]
    procedure EncryptedOfficeFileReported;
    [Test]
    procedure LegacyOfficeFileUnsupported;
    [Test]
    procedure PptxSlideOrderNumeric;
    [Test]
    procedure XlsxSharedStringsAndNumbers;
    [Test]
    procedure HtmlText;
    [Test]
    procedure HtmlSkipsScriptAndStyle;
    [Test]
    procedure HtmlDeepNestingNoStackOverflow;
    [Test]
    procedure HtmlCharsetFromMeta;
    [Test]
    procedure JsonText;
    [Test]
    procedure JsonInvalidIsCorrupt;
    [Test]
    procedure JsonSurrogateEscape;
    [Test]
    procedure XmlText;
    [Test]
    procedure XmlWithoutElementsIsCorrupt;
    [Test]
    procedure CsvText;
    [Test]
    procedure PlainTextUtf8AndBom;
    [Test]
    procedure PlainTextInvalidUtf8FallsBack;
    [Test]
    procedure RtfUnicodeAndCodepage;
    [Test]
    procedure RtfNotRtfIsCorrupt;
    [Test]
    procedure RtfDeepNestingNoStackOverflow;
    [Test]
    procedure BinaryRenamedJsonUnsupported;
    [Test]
    procedure TooLargeIsReported;
    [Test]
    procedure CharLimitNeverSplitsSurrogatePair;
    [Test]
    procedure CharLimitKeepsCompletePair;
    [Test]
    procedure SinkSharesNormalization;
    [Test]
    procedure CancelRaisesCancelled;
    [Test]
    procedure RegistryUnknownExtensionNil;
    [Test]
    procedure RegistryKnownExtensions;
    [Test]
    procedure RegistryIdentityStable;
    [Test]
    procedure ExtractionIsDeterministic;
{$IFDEF MSWINDOWS}
    [Test]
    procedure XlsxWorkbookSheetBombRejected;
    [Test]
    procedure XlsxSharedStringsBombRejected;
{$ENDIF}
    [Test]
    procedure XlsxWorkbookAttributeBomb;
{$IFDEF MSWINDOWS}
    [Test]
    procedure XlsxUnclosedValueIsCapped;
{$ENDIF}
    [Test]
    procedure LimitedTextHasNoTrailingBreak;
    [Test]
    procedure JsonEmptyValuesAddNoLines;
    [Test]
    procedure HtmlUtf16MetaWithoutBomReadsAsUtf8;
    [Test]
    procedure Utf8DecoderRejectsLeadBytesAboveF4;
  end;

implementation

uses
  System.Math, System.Diagnostics, System.IOUtils, unit_TextExtractorRegistry, unit_OfficeTextExtractors,
  unit_MarkupTextExtractors, unit_JsonTextExtractor;

const
  WordNs = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
  DrawNs = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' +
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
  SheetNs = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  Utf8Decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

function WordDoc(const Body: string): string;
begin
  Result := Utf8Decl + '<w:document ' + WordNs + '><w:body>' + Body + '</w:body></w:document>';
end;

function WordPara(const Text: string): string;
begin
  Result := '<w:p><w:r><w:t>' + Text + '</w:t></w:r></w:p>';
end;

function SlideDoc(const Paragraphs: array of string): string;
var
  S: string;
begin
  Result := Utf8Decl + '<p:sld ' + DrawNs + '><p:cSld><p:spTree><p:sp><p:txBody>';
  for S in Paragraphs do
    Result := Result + '<a:p><a:r><a:t>' + S + '</a:t></a:r></a:p>';
  Result := Result + '</p:txBody></p:sp></p:spTree></p:cSld></p:sld>';
end;

function BuildZip(const Names, Contents: array of string; Compression: TZipCompression = zcDeflate): TBytes;
var
  Stream: TMemoryStream;
  Zip: TZipFile;
  I: Integer;
begin
  Stream := TMemoryStream.Create;
  try
    Zip := TZipFile.Create;
    try
      Zip.Open(Stream, zmWrite);
      for I := 0 to High(Names) do
        Zip.Add(TEncoding.UTF8.GetBytes(Contents[I]), Names[I], Compression);
      Zip.Close;
    finally
      Zip.Free;
    end;
    SetLength(Result, Stream.Size);
    Move(Stream.Memory^, Result[0], Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure PatchCentralUncompressedSize(var Bytes: TBytes; const EntryName: string; NewSize: Cardinal);
var
  I, NameLen: Integer;
begin
  for I := 0 to Length(Bytes) - 47 do
    if (Bytes[I] = $50) and (Bytes[I + 1] = $4B) and (Bytes[I + 2] = 1) and (Bytes[I + 3] = 2) then
    begin
      NameLen := Bytes[I + 28] or (Bytes[I + 29] shl 8);
      if TEncoding.UTF8.GetString(Bytes, I + 46, NameLen) = EntryName then
      begin
        Move(NewSize, Bytes[I + 24], SizeOf(NewSize));
        Exit;
      end;
    end;
  raise Exception.Create('central directory entry not found: ' + EntryName);
end;

function Utf8(const Text: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(Text);
end;

procedure TTextFormatExtractorTests.Setup;
begin
  FRegistryPdfPath := TPath.Combine(TPath.GetTempPath, TGUID.NewGuid.ToString + '\pdfium.dll');
end;

function TTextFormatExtractorTests.Run(const Ext: string; const Bytes: TBytes): TExtractResult;
var
  Registry: TTextExtractorRegistry;
  Extractor: ITextExtractor;
begin
  Registry := TTextExtractorRegistry.Create(FRegistryPdfPath);
  try
    Extractor := Registry.ForExtension(Ext);
    Assert.IsNotNull(Extractor, 'extractor for ' + Ext);
    Result := Extractor.Extract(Bytes, nil);
  finally
    Registry.Free;
  end;
end;

function TTextFormatExtractorTests.RunText(const Ext, Text: string): TExtractResult;
begin
  Result := Run(Ext, Utf8(Text));
end;

procedure TTextFormatExtractorTests.DocxText;
var
  R: TExtractResult;
begin
  R := Run('.docx', BuildZip(['word/document.xml'],
    [WordDoc('<w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:tab/><w:t xml:space="preserve"> Привет &amp; мир</w:t></w:r></w:p>' +
      '<w:p><w:r><w:t>Second</w:t><w:br/><w:t>line</w:t></w:r></w:p>' +
      '<mc:AlternateContent xmlns:mc="m"><mc:Choice><w:p><w:r><w:t>Chosen</w:t></w:r></w:p></mc:Choice>' +
      '<mc:Fallback><w:p><w:r><w:t>Duplicate</w:t></w:r></w:p></mc:Fallback></mc:AlternateContent>' +
      '<w:p><w:r><w:delText>Removed</w:delText><w:instrText>FIELD</w:instrText></w:r></w:p>')]));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Hello'#9'Привет & мир'#10'Second'#10'line'#10'Chosen', R.Text);
end;

procedure TTextFormatExtractorTests.DocxHeadersFooterAfterBody;
var
  R: TExtractResult;
begin
  R := Run('.docx', BuildZip(
    ['word/footer1.xml', 'word/header10.xml', 'word/document.xml', 'word/header2.xml', 'word/footnotes.xml'],
    [WordDoc(WordPara('Footer')), WordDoc(WordPara('Header ten')), WordDoc(WordPara('Body')),
     WordDoc(WordPara('Header two')), WordDoc(WordPara('Note'))]));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Body'#10#10'Note'#10#10'Header two'#10#10'Header ten'#10#10'Footer', R.Text);
end;

procedure TTextFormatExtractorTests.DocxMissingDocumentIsCorrupt;
begin
  Assert.AreEqual(Ord(eoCorrupt), Ord(Run('.docx', BuildZip(['word/other.xml'], [WordDoc(WordPara('x'))])).Outcome));
end;

procedure TTextFormatExtractorTests.DocxZipBombRejected;
var
  Bytes: TBytes;
  Watch: TStopwatch;
  R: TExtractResult;
begin
  Bytes := BuildZip(['word/document.xml'], [WordDoc(WordPara('Hello'))]);
  PatchCentralUncompressedSize(Bytes, 'word/document.xml', $40000000);
  Watch := TStopwatch.StartNew;
  R := Run('.docx', Bytes);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'took ' + Watch.ElapsedMilliseconds.ToString + ' ms');
  Assert.AreEqual(Ord(eoTooLarge), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('', R.Text);
end;

procedure TTextFormatExtractorTests.DocxTooManyEntriesRejected;
var
  Names, Contents: TArray<string>;
  Bytes: TBytes;
  Watch: TStopwatch;
  R: TExtractResult;
  I: Integer;
begin
  SetLength(Names, 20001);
  SetLength(Contents, 20001);
  Names[0] := 'word/document.xml';
  Contents[0] := WordDoc(WordPara('Hello'));
  for I := 1 to 20000 do
  begin
    Names[I] := 'media/f' + IntToStr(I) + '.bin';
    Contents[I] := 'x';
  end;
  Bytes := BuildZip(Names, Contents, zcStored);
  Watch := TStopwatch.StartNew;
  R := Run('.docx', Bytes);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'took ' + Watch.ElapsedMilliseconds.ToString + ' ms');
  Assert.AreEqual(Ord(eoTooLarge), Ord(R.Outcome), R.Detail);
end;

procedure TTextFormatExtractorTests.DocxLyingHeaderStopsAtLimit;
var
  Body: TStringBuilder;
  Bytes: TBytes;
  Extractor: TDocxTextExtractor;
  Holder: ITextExtractor;
  R: TExtractResult;
  I: Integer;
begin
  Body := TStringBuilder.Create;
  try
    for I := 1 to 40000 do
      Body.Append(WordPara('word'));
    Bytes := BuildZip(['word/document.xml'], [WordDoc(Body.ToString)]);
  finally
    Body.Free;
  end;
  PatchCentralUncompressedSize(Bytes, 'word/document.xml', 100);
  Extractor := TDocxTextExtractor.Create;
  Holder := Extractor;
  Extractor.MaxUncompressed := 256 * 1024;
  R := Holder.Extract(Bytes, nil);
  Assert.AreEqual(Ord(eoTooLarge), Ord(R.Outcome), R.Detail);
end;

procedure TTextFormatExtractorTests.DocxGarbageIsCorrupt;
var
  Bytes: TBytes;
  I: Integer;
begin
  SetLength(Bytes, 2048);
  RandSeed := 777;
  for I := 0 to High(Bytes) do
    Bytes[I] := Random(256);
  Bytes[0] := $50;
  Bytes[1] := $4B;
  Assert.AreEqual(Ord(eoCorrupt), Ord(Run('.docx', Bytes).Outcome));
  Assert.AreEqual(Ord(eoCorrupt), Ord(Run('.xlsx', nil).Outcome));
end;

procedure TTextFormatExtractorTests.EncryptedOfficeFileReported;
var
  Bytes: TBytes;
  Marker: TBytes;
begin
  Bytes := TBytes.Create($D0, $CF, $11, $E0, $A1, $B1, $1A, $E1, 0, 0, 0, 0);
  Marker := TEncoding.Unicode.GetBytes('EncryptedPackage');
  Bytes := Bytes + Marker + TBytes.Create(0, 0);
  Assert.AreEqual(Ord(eoEncrypted), Ord(Run('.docx', Bytes).Outcome));
end;

procedure TTextFormatExtractorTests.LegacyOfficeFileUnsupported;
var
  Bytes: TBytes;
begin
  Bytes := TBytes.Create($D0, $CF, $11, $E0, $A1, $B1, $1A, $E1, 0, 0, 0, 0, 1, 2, 3);
  Assert.AreEqual(Ord(eoUnsupported), Ord(Run('.xlsx', Bytes).Outcome));
end;

procedure TTextFormatExtractorTests.PptxSlideOrderNumeric;
var
  R: TExtractResult;
begin
  R := Run('.pptx', BuildZip(
    ['ppt/slides/slide10.xml', 'ppt/slides/slide2.xml', 'ppt/slides/slide1.xml', 'ppt/notesSlides/notesSlide1.xml',
     'ppt/slideLayouts/slideLayout1.xml'],
    [SlideDoc(['Ten']), SlideDoc(['Two', 'Привет &amp; мир']), SlideDoc(['One']), SlideDoc(['Speaker note']),
     SlideDoc(['Layout text'])]));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('One'#10#10'Two'#10'Привет & мир'#10#10'Ten'#10#10'Speaker note', R.Text);
end;

procedure TTextFormatExtractorTests.XlsxSharedStringsAndNumbers;
const
  RelsNs = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';
var
  R: TExtractResult;
begin
  R := Run('.xlsx', BuildZip(
    ['xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/sharedStrings.xml', 'xl/worksheets/sheet1.xml',
     'xl/worksheets/sheet2.xml'],
    [Utf8Decl + '<workbook ' + SheetNs + ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
       '<sheets><sheet name="Second" sheetId="2" r:id="rId2"/><sheet name="First" sheetId="1" r:id="rId1"/></sheets></workbook>',
     Utf8Decl + '<Relationships ' + RelsNs + '><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>' +
       '<Relationship Id="rId2" Type="worksheet" Target="/xl/worksheets/sheet2.xml"/></Relationships>',
     Utf8Decl + '<sst ' + SheetNs + '><si><t>Alpha</t></si><si><r><t>Be</t></r><r><t>ta</t></r></si>' +
       '<si><t>Рефлектометрия</t><rPh sb="0" eb="1"><t>PHONETIC</t></rPh></si></sst>',
     Utf8Decl + '<worksheet ' + SheetNs + '><sheetData>' +
       '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>3.14</v></c><c r="C1" t="inlineStr"><is><t>inline</t></is></c>' +
       '<c r="D1" t="b"><v>1</v></c></row>' +
       '<row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><f>A1+1</f><v>42</v></c><c r="C2" t="e"><v>#DIV/0!</v></c></row>' +
       '</sheetData></worksheet>',
     Utf8Decl + '<worksheet ' + SheetNs + '><sheetData><row r="1"><c r="A1" t="s"><v>2</v></c></row></sheetData></worksheet>']));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Рефлектометрия'#10#10'Alpha'#9'3.14'#9'inline'#9'TRUE'#10'Beta'#9'42', R.Text);
end;

procedure TTextFormatExtractorTests.HtmlText;
var
  R: TExtractResult;
begin
  R := RunText('.html', '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Doc</title>' +
    '<style>body{color:red}</style></head><body><!-- hidden --><p>Hello &amp; world &#1055;&#x440;&eacute; &unknown;</p>' +
    '<div>Second<br>line</div><table><tr><td>A</td><td>B</td></tr></table></body></html>');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Doc'#10'Hello & world Прé &unknown;'#10'Second'#10'line'#10'A'#9'B', R.Text);
end;

procedure TTextFormatExtractorTests.HtmlSkipsScriptAndStyle;
var
  R: TExtractResult;
begin
  R := RunText('.htm', '<p>Before</p><SCRIPT type="text/javascript">var s = "</p><p>fake</p>"; if (a < b) {}</SCRIPT>' +
    '<style>p { content: "<b>" }</style><p>After</p>');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Before'#10'After', R.Text);
end;

procedure TTextFormatExtractorTests.HtmlDeepNestingNoStackOverflow;
var
  Html: TStringBuilder;
  I: Integer;
  R: TExtractResult;
begin
  Html := TStringBuilder.Create;
  try
    for I := 1 to 100000 do
      Html.Append('<div>');
    Html.Append('deep');
    R := RunText('.html', Html.ToString);
  finally
    Html.Free;
  end;
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('deep', R.Text);
end;

procedure TTextFormatExtractorTests.HtmlCharsetFromMeta;
var
  Bytes: TBytes;
  Enc: TEncoding;
  R: TExtractResult;
begin
  Enc := TEncoding.GetEncoding(1251);
  try
    Bytes := Utf8('<html><head><meta http-equiv="Content-Type" content="text/html; charset=windows-1251"></head><body>') +
      Enc.GetBytes('Привет') + Utf8('</body></html>');
  finally
    Enc.Free;
  end;
  R := Run('.html', Bytes);
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Привет', R.Text);
end;

procedure TTextFormatExtractorTests.JsonText;
var
  R: TExtractResult;
begin
  R := RunText('.json', '{"name":"Образец","list":["a\u0041","tab\t\"q\""],"n":-12.5e3,"ok":true,"nested":{"k":null,"e":[]}}');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('name'#10'Образец'#10'list'#10'aA'#10'tab "q"'#10'n'#10'ok'#10'nested'#10'k'#10'e', R.Text);
end;

procedure TTextFormatExtractorTests.JsonInvalidIsCorrupt;
var
  Text: string;
begin
  for Text in ['{"a": }', '{"a":1,}', '[1,2', '  ', '{"a" 1}', '[1 2]', '{"a":01}', '"open', '{} extra', '{"a":tru}',
    '["bad \x escape"]'] do
    Assert.AreEqual(Ord(eoCorrupt), Ord(RunText('.json', Text).Outcome), Text);
end;

procedure TTextFormatExtractorTests.JsonSurrogateEscape;
var
  R: TExtractResult;
begin
  R := RunText('.json', '["\ud83d\ude00 ok"]');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual(#$D83D#$DE00' ok', R.Text);
end;

procedure TTextFormatExtractorTests.XmlText;
var
  R: TExtractResult;
begin
  R := RunText('.xml', Utf8Decl + '<!DOCTYPE r [<!ENTITY x "y>">]><root id="r1"><a>Привет &amp; &#x41;</a>' +
    '<![CDATA[<raw> & text]]><b note=''n&lt;1''/><!-- skipped --></root>');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('r1'#10'Привет & A'#10'<raw> & text'#10'n<1', R.Text);
end;

procedure TTextFormatExtractorTests.XmlWithoutElementsIsCorrupt;
begin
  Assert.AreEqual(Ord(eoCorrupt), Ord(RunText('.xml', 'just words').Outcome));
end;

procedure TTextFormatExtractorTests.CsvText;
var
  R: TExtractResult;
begin
  R := RunText('.csv', 'name;value,x'#13#10'a;"b,c"'#13#10'Привет;1');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('name;value,x'#10'a;"b,c"'#10'Привет;1', R.Text);
end;

procedure TTextFormatExtractorTests.PlainTextUtf8AndBom;
var
  R: TExtractResult;
begin
  R := RunText('.txt', 'Рентген  и'#9'свет');
  Assert.AreEqual('Рентген и свет', R.Text);
  R := Run('.md', TBytes.Create($EF, $BB, $BF) + Utf8('# Заголовок'));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('# Заголовок', R.Text);
  R := Run('.txt', TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes('Wide текст'));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Wide текст', R.Text);
  Assert.AreEqual(Ord(eoNoText), Ord(Run('.txt', Utf8('  '#13#10)).Outcome));
end;

procedure TTextFormatExtractorTests.PlainTextInvalidUtf8FallsBack;
var
  R: TExtractResult;
begin
  R := Run('.txt', TBytes.Create(Ord('a'), $FF, $FE, Ord('b')));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual(TEncoding.ANSI.GetString(TBytes.Create(Ord('a'), $FF, $FE, Ord('b'))), R.Text);
end;

procedure TTextFormatExtractorTests.RtfUnicodeAndCodepage;
var
  R: TExtractResult;
begin
  R := RunText('.rtf', '{\rtf1\ansi\ansicpg1251\deff0{\fonttbl{\f0 Arial;}}{\colortbl;\red0\green0\blue0;}' +
    '{\*\generator Test;}{\info{\title Hidden}}{\pict\wmetafile8 0102030405}\pard Hello \u1055?\u1088?\''e8\''e2\''e5\''f2 ' +
    '\''f2\''e5\''f1\''f2\par Second\tab line\line end \{x\}\u-10179?\u-8704?}');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Hello Привет тест'#10'Second'#9'line'#10'end {x}' + #$D83D#$DE00, R.Text);
end;

procedure TTextFormatExtractorTests.RtfNotRtfIsCorrupt;
begin
  Assert.AreEqual(Ord(eoCorrupt), Ord(RunText('.rtf', 'plain words').Outcome));
end;

procedure TTextFormatExtractorTests.RtfDeepNestingNoStackOverflow;
var
  Rtf: TStringBuilder;
  R: TExtractResult;
begin
  Rtf := TStringBuilder.Create;
  try
    Rtf.Append('{\rtf1').Append('{', 100000).Append('deep').Append('}', 100000).Append('}');
    R := RunText('.rtf', Rtf.ToString);
  finally
    Rtf.Free;
  end;
  Assert.AreEqual('deep', R.Text);
end;

procedure TTextFormatExtractorTests.BinaryRenamedJsonUnsupported;
var
  Bytes: TBytes;
  I: Integer;
  Ext: string;
begin
  SetLength(Bytes, 4096);
  for I := 0 to High(Bytes) do
    Bytes[I] := I mod 7;
  for Ext in ['.json', '.xml', '.html', '.csv', '.rtf', '.txt', '.md'] do
    Assert.AreEqual(Ord(eoUnsupported), Ord(Run(Ext, Bytes).Outcome), Ext);
end;

procedure TTextFormatExtractorTests.TooLargeIsReported;
var
  Bytes: TBytes;
  Ext: string;
begin
  SetLength(Bytes, FileTextMaxBytes + 1);
  for Ext in ['.docx', '.txt', '.json'] do
    Assert.AreEqual(Ord(eoTooLarge), Ord(Run(Ext, Bytes).Outcome), Ext);
end;

procedure TTextFormatExtractorTests.CharLimitNeverSplitsSurrogatePair;
var
  Limited: TPlainTextExtractor;
  Holder: ITextExtractor;
  R: TExtractResult;
begin
  Limited := TPlainTextExtractor.Create('plain-text');
  Holder := Limited;
  Limited.MaxChars := 3;
  R := Holder.Extract(Utf8('ab' + #$D83D#$DE00 + 'cd'), nil);
  Assert.AreEqual(Ord(eoLimitReached), Ord(R.Outcome));
  Assert.AreEqual('ab', R.Text);
end;

procedure TTextFormatExtractorTests.CharLimitKeepsCompletePair;
var
  Limited: TJsonTextExtractor;
  Holder: ITextExtractor;
  R: TExtractResult;
begin
  Limited := TJsonTextExtractor.Create;
  Holder := Limited;
  Limited.MaxChars := 4;
  R := Holder.Extract(Utf8('["ab' + #$D83D#$DE00 + 'cd"]'), nil);
  Assert.AreEqual(Ord(eoLimitReached), Ord(R.Outcome));
  Assert.AreEqual('ab' + #$D83D#$DE00, R.Text);
  Limited.MaxChars := 5;
  Assert.AreEqual(Ord(eoText), Ord(Holder.Extract(Utf8('["ab' + #$D83D#$DE00 + 'c"]'), nil).Outcome));
end;

procedure TTextFormatExtractorTests.SinkSharesNormalization;
var
  Sink: TTextSink;
begin
  Sink := TTextSink.Create(100);
  try
    Sink.Append('  one  two ');
    Sink.Tab;
    Sink.Append('three');
    Sink.LineBreak;
    Sink.LineBreak;
    Sink.Append('four '#13#10'five');
    Sink.EndBlock;
    Sink.Append(#10#10' six ');
    Assert.AreEqual('one two'#9'three'#10#10'four'#10'five'#10#10'six', Sink.ToResult.Text);
  finally
    Sink.Free;
  end;
end;

procedure TTextFormatExtractorTests.CancelRaisesCancelled;
var
  Extractor: ITextExtractor;
begin
  Extractor := TJsonTextExtractor.Create;
  Assert.WillRaise(
    procedure
    begin
      Extractor.Extract(Utf8('["a"]'),
        function: Boolean
        begin
          Result := True;
        end);
    end, EOperationCancelled);
end;

procedure TTextFormatExtractorTests.RegistryUnknownExtensionNil;
var
  Registry: TTextExtractorRegistry;
begin
  Registry := TTextExtractorRegistry.Create(FRegistryPdfPath);
  try
    Assert.IsNull(Registry.ForExtension('.exe'));
    Assert.IsNull(Registry.ForExtension(''));
    Assert.IsNull(Registry.ForExtension('.doc'));
  finally
    Registry.Free;
  end;
end;

procedure TTextFormatExtractorTests.RegistryKnownExtensions;
const
  Expected: array[0..14, 0..1] of string = (
    ('.pdf', 'pdfium-text'), ('.docx', 'docx-text'), ('.pptx', 'pptx-text'), ('.xlsx', 'xlsx-text'),
    ('.html', 'html-text'), ('.htm', 'html-text'), ('.json', 'json-text'), ('.xml', 'xml-text'),
    ('.csv', 'csv-text'), ('.rtf', 'rtf-text'), ('.md', 'plain-text'), ('.txt', 'plain-text'),
    ('.PDF', 'pdfium-text'), ('.Docx', 'docx-text'), ('.HTM', 'html-text'));
var
  Registry: TTextExtractorRegistry;
  I: Integer;
  Extractor: ITextExtractor;
begin
  Registry := TTextExtractorRegistry.Create(FRegistryPdfPath);
  try
    for I := 0 to High(Expected) do
    begin
      Extractor := Registry.ForExtension(Expected[I, 0]);
      Assert.IsNotNull(Extractor, Expected[I, 0]);
      Assert.AreEqual(Expected[I, 1], Extractor.Id);
      Assert.AreEqual(1, Extractor.Version);
    end;
  finally
    Registry.Free;
  end;
end;

procedure TTextFormatExtractorTests.RegistryIdentityStable;
var
  A, B: TTextExtractorRegistry;
begin
  A := TTextExtractorRegistry.Create(FRegistryPdfPath);
  B := TTextExtractorRegistry.Create(FRegistryPdfPath + 'x');
  try
    Assert.AreEqual(A.Identity, B.Identity);
    Assert.AreEqual('csv-text:1;docx-text:1;html-text:1;json-text:1;pdfium-text:1;plain-text:1;pptx-text:1;rtf-text:1;' +
      'xlsx-text:1;xml-text:1', A.Identity);
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TTextFormatExtractorTests.ExtractionIsDeterministic;
var
  Samples: TArray<TPair<string, TBytes>>;
  Sample: TPair<string, TBytes>;
  First, Second: TExtractResult;
begin
  Samples := [
    TPair<string, TBytes>.Create('.docx', BuildZip(['word/document.xml'], [WordDoc(WordPara('Hello') + WordPara('мир'))])),
    TPair<string, TBytes>.Create('.pptx', BuildZip(['ppt/slides/slide1.xml', 'ppt/slides/slide3.xml'],
      [SlideDoc(['One']), SlideDoc(['Three'])])),
    TPair<string, TBytes>.Create('.xlsx', BuildZip(['xl/worksheets/sheet1.xml'],
      [Utf8Decl + '<worksheet ' + SheetNs + '><sheetData><row><c t="inlineStr"><is><t>x</t></is></c><c><v>1</v></c></row></sheetData></worksheet>'])),
    TPair<string, TBytes>.Create('.html', Utf8('<p>a</p><p>b &amp; c</p>')),
    TPair<string, TBytes>.Create('.json', Utf8('{"a":["b","c"]}')),
    TPair<string, TBytes>.Create('.xml', Utf8('<r a="1"><b>2</b></r>')),
    TPair<string, TBytes>.Create('.csv', Utf8('a;b'#10'c;d')),
    TPair<string, TBytes>.Create('.rtf', Utf8('{\rtf1 hello\par world}')),
    TPair<string, TBytes>.Create('.md', Utf8('# title')),
    TPair<string, TBytes>.Create('.txt', Utf8('plain  text'))];
  for Sample in Samples do
  begin
    First := Run(Sample.Key, Sample.Value);
    Second := Run(Sample.Key, Sample.Value);
    Assert.AreEqual(Ord(eoText), Ord(First.Outcome), Sample.Key + ': ' + First.Detail);
    Assert.AreEqual(Ord(First.Outcome), Ord(Second.Outcome), Sample.Key);
    Assert.AreEqual(First.Text, Second.Text, Sample.Key);
  end;
end;

{$IFDEF MSWINDOWS}
function AllocatedBytes: Int64;
var
  State: TMemoryManagerState;
  Small: TSmallBlockTypeState;
begin
  GetMemoryManagerState(State);
  Result := State.TotalAllocatedMediumBlockSize + State.TotalAllocatedLargeBlockSize;
  for Small in State.SmallBlockTypeStates do
    Inc(Result, Int64(Small.AllocatedBlockCount) * Small.UseableBlockSize);
end;

procedure ExpectBombRejected(const Bytes: TBytes);
const
  PeakGrowthLimit = 48 * 1024 * 1024;
var
  Extractor: ITextExtractor;
  Base, Peak: Int64;
  Watch: TStopwatch;
  R: TExtractResult;
begin
  Extractor := TXlsxTextExtractor.Create;
  Base := AllocatedBytes;
  Peak := 0;
  Watch := TStopwatch.StartNew;
  R := Extractor.Extract(Bytes,
    function: Boolean
    begin
      Peak := Max(Peak, AllocatedBytes - Base);
      Result := False;
    end);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, 'took ' + Watch.ElapsedMilliseconds.ToString + ' ms');
  Assert.AreEqual(Ord(eoTooLarge), Ord(R.Outcome), R.Detail);
  Assert.IsTrue(Peak < PeakGrowthLimit, 'peak growth ' + Peak.ToString + ' bytes');
end;

procedure TTextFormatExtractorTests.XlsxWorkbookSheetBombRejected;
const
  RelsNs = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';
var
  Sheets: TStringBuilder;
  Workbook: string;
  Bytes: TBytes;
  I: Integer;
begin
  Sheets := TStringBuilder.Create;
  try
    for I := 1 to 2000000 do
      Sheets.Append('<sheet/>');
    Workbook := Utf8Decl + '<workbook ' + SheetNs + '><sheets>' + Sheets.ToString + '</sheets></workbook>';
  finally
    Sheets.Free;
  end;
  Bytes := BuildZip(['xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/worksheets/sheet1.xml'],
    [Workbook, Utf8Decl + '<Relationships ' + RelsNs + '/>', Utf8Decl + '<worksheet ' + SheetNs + '/>']);
  Workbook := '';
  ExpectBombRejected(Bytes);
end;

procedure TTextFormatExtractorTests.XlsxSharedStringsBombRejected;
var
  Items: TStringBuilder;
  Strings: string;
  Bytes: TBytes;
  I: Integer;
begin
  Items := TStringBuilder.Create;
  try
    for I := 1 to 5000000 do
      Items.Append('<si/>');
    Strings := Utf8Decl + '<sst ' + SheetNs + '>' + Items.ToString + '</sst>';
  finally
    Items.Free;
  end;
  Bytes := BuildZip(['xl/sharedStrings.xml', 'xl/worksheets/sheet1.xml'],
    [Strings, Utf8Decl + '<worksheet ' + SheetNs + '/>']);
  Strings := '';
  ExpectBombRejected(Bytes);
end;
{$ENDIF}

procedure TTextFormatExtractorTests.XlsxWorkbookAttributeBomb;
const
  RelsNs = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"';
  AttributeCount = 200000;
var
  Attributes: TStringBuilder;
  Workbook, Rels: string;
  Bytes: TBytes;
  Extractor: ITextExtractor;
  Watch: TStopwatch;
  R: TExtractResult;
  I: Integer;
begin
  Attributes := TStringBuilder.Create;
  try
    for I := 1 to AttributeCount do
      Attributes.Append(' a').Append(I).Append('="v"');
    Workbook := Utf8Decl + '<workbook ' + SheetNs + '><sheets><sheet' + Attributes.ToString +
      '/></sheets></workbook>';
    Rels := Utf8Decl + '<Relationships ' + RelsNs + '><Relationship' + Attributes.ToString + '/></Relationships>';
  finally
    Attributes.Free;
  end;
  Bytes := BuildZip(['xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/worksheets/sheet1.xml'],
    [Workbook, Rels, Utf8Decl + '<worksheet ' + SheetNs + '><sheetData><row><c t="inlineStr"><is><t>alive</t></is></c></row></sheetData></worksheet>']);
  Extractor := TXlsxTextExtractor.Create;
  Watch := TStopwatch.StartNew;
  R := Extractor.Extract(Bytes, nil);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, 'took ' + Watch.ElapsedMilliseconds.ToString + ' ms');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('alive', R.Text);
end;

{$IFDEF MSWINDOWS}
procedure TTextFormatExtractorTests.XlsxUnclosedValueIsCapped;
const
  PeakGrowthLimit = 80 * 1024 * 1024;
var
  Sheet: string;
  Bytes: TBytes;
  Extractor: ITextExtractor;
  Base, Peak: Int64;
  R: TExtractResult;
begin
  Sheet := Utf8Decl + '<worksheet ' + SheetNs + '><sheetData><row><c><v>' +
    StringOfChar('9', 50 * 1024 * 1024);
  Bytes := BuildZip(['xl/worksheets/sheet1.xml'], [Sheet]);
  Sheet := '';
  Extractor := TXlsxTextExtractor.Create;
  Base := AllocatedBytes;
  Peak := 0;
  R := Extractor.Extract(Bytes,
    function: Boolean
    begin
      Peak := Max(Peak, AllocatedBytes - Base);
      Result := False;
    end);
  Assert.IsTrue(R.Outcome in [eoNoText, eoCorrupt, eoText, eoLimitReached], 'outcome ' + IntToStr(Ord(R.Outcome)));
  Assert.IsTrue(Peak < PeakGrowthLimit, 'peak growth ' + Peak.ToString + ' bytes');
end;
{$ENDIF}

procedure TTextFormatExtractorTests.LimitedTextHasNoTrailingBreak;
var
  Limited: TPlainTextExtractor;
  Holder: ITextExtractor;
  R: TExtractResult;
begin
  Limited := TPlainTextExtractor.Create('plain-text');
  Holder := Limited;
  Limited.MaxChars := 3;
  R := Holder.Extract(Utf8('ab'#10'cd'), nil);
  Assert.AreEqual(Ord(eoLimitReached), Ord(R.Outcome));
  Assert.AreEqual('ab', R.Text);
  Limited.MaxChars := 3;
  R := Holder.Extract(Utf8('ab '#9'cd'), nil);
  Assert.AreEqual('ab', R.Text);
end;

procedure TTextFormatExtractorTests.JsonEmptyValuesAddNoLines;
var
  R: TExtractResult;
begin
  R := RunText('.json', '["a","","   ","b",{"":"c"}]');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('a'#10'b'#10'c', R.Text);
end;

procedure TTextFormatExtractorTests.HtmlUtf16MetaWithoutBomReadsAsUtf8;
var
  R: TExtractResult;
begin
  R := RunText('.html', '<meta charset="utf-16"><p>Привет</p>');
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Привет', R.Text);
end;

procedure TTextFormatExtractorTests.Utf8DecoderRejectsLeadBytesAboveF4;
var
  Decoder: TTextStreamDecoder;
  Bytes: TBytes;
begin
  Bytes := TBytes.Create(Ord('a'), $F5, $80, $80, $80, $C0, $80, Ord('b'));
  Decoder := TTextStreamDecoder.Create;
  try
    Assert.AreEqual('a'#$FFFD#$FFFD#$FFFD#$FFFD#$FFFD#$FFFD'b', Decoder.Decode(Bytes, Length(Bytes), True));
  finally
    Decoder.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextFormatExtractorTests);

end.
