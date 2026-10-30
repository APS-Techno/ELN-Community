unit test_TextExtractors;

interface

uses
  System.SysUtils, System.Classes, DUnitX.TestFramework, unit_TextEmbedder, unit_TextExtractors;

type
  [TestFixture]
  TPdfTextExtractorTests = class
  private
    FLibraryPath: string;
    FExtractor: ITextExtractor;
    function Fixture(const Name: string): TBytes;
    function Extract(const Bytes: TBytes): TExtractResult;
  public
    [Setup]
    procedure Setup;
    [Test]
    procedure ExtractsTwoPages;
    [Test]
    procedure ExtractsCyrillic;
    [Test]
    procedure EncryptedReported;
    [Test]
    procedure GarbageIsCorrupt;
    [Test]
    procedure EmptyIsCorrupt;
    [Test]
    procedure TruncatedDoesNotCrash;
    [Test]
    procedure MissingLibraryIsUnsupported;
    [Test]
    procedure CancelStopsBeforeNextPage;
    [Test]
    procedure ConcurrentExtractsAreSerialized;
    [Test]
    procedure CharLimitApplied;
    [Test]
    procedure NormalizesWhitespace;
    [Test]
    procedure IdentifiesItself;
  end;

  [TestFixture]
  TPdfAvailabilityTests = class
  private
    FRoot: string;
    FSourceFolder: string;
    FCopyFolder: string;
    FLibraryPath: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReleaseAllowsDeletingTheLibraryFolder;
    [Test]
    procedure ReleaseWithoutLoadedLibraryIsHarmless;
    [Test]
    procedure MissingPdfiumGivesNoPassageAndNoCacheRowUntilInstalled;
    [Test]
    procedure UnloadableLibraryGivesNotInstalled;
  end;

implementation

uses
  System.IOUtils, unit_SearchArtifacts, unit_PdfiumApi, unit_SearchPassages, unit_SearchIndexStore,
  unit_TextExtractorRegistry, unit_FileTextStage, test_SearchDoubles, unit_SearchTestSupport;

function BuildLatinPdf: TBytes;
const
  PageTexts: array[0..1] of string = ('Reflectivity of multilayer mirrors', 'Interface roughness and layer thickness');
var
  Body: TStringBuilder;
  Offsets: array[0..8] of Integer;
  Stream: string;
  I, XrefAt: Integer;

  procedure AddObject(Index: Integer; const Text: string);
  begin
    Offsets[Index] := Body.Length;
    Body.Append(IntToStr(Index)).Append(' 0 obj'#10).Append(Text).Append(#10'endobj'#10);
  end;

begin
  Body := TStringBuilder.Create;
  try
    Body.Append('%PDF-1.4'#10);
    AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
    AddObject(2, '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>');
    for I := 0 to 1 do
    begin
      Stream := 'BT /F1 18 Tf 72 700 Td (' + PageTexts[I] + ') Tj ET';
      AddObject(3 + I * 2, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents ' +
        IntToStr(4 + I * 2) + ' 0 R /Resources << /Font << /F1 7 0 R >> >> >>');
      AddObject(4 + I * 2, '<< /Length ' + IntToStr(Length(Stream)) + ' >>'#10'stream'#10 + Stream + #10'endstream');
    end;
    AddObject(7, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    XrefAt := Body.Length;
    Body.Append('xref'#10'0 8'#10'0000000000 65535 f '#10);
    for I := 1 to 7 do
      Body.Append(Format('%.10d 00000 n '#10, [Offsets[I]]));
    Body.Append('trailer'#10'<< /Size 8 /Root 1 0 R >>'#10'startxref'#10).Append(IntToStr(XrefAt)).Append(#10'%%EOF'#10);
    Result := TEncoding.ASCII.GetBytes(Body.ToString);
  finally
    Body.Free;
  end;
end;

function FindFixture(const Name: string): string;
begin
  Result := RepoFilePath('ELN.Community.Tests/Fixtures/Search/Files/' + Name);
end;

procedure TPdfTextExtractorTests.Setup;
var
  Manifest: TSearchArtifactManifest;
begin
  FLibraryPath := Manifest.PdfiumLibraryPath(SearchArtifactRoot);
  if not TFile.Exists(FLibraryPath) then
    Assert.Fail('PDFium is not installed at ' + FLibraryPath);
  FExtractor := TPdfTextExtractor.Create(FLibraryPath);
end;

function TPdfTextExtractorTests.Fixture(const Name: string): TBytes;
begin
  Result := TFile.ReadAllBytes(FindFixture(Name));
end;

function TPdfTextExtractorTests.Extract(const Bytes: TBytes): TExtractResult;
begin
  Result := FExtractor.Extract(Bytes, nil);
end;

procedure TPdfTextExtractorTests.ExtractsTwoPages;
var
  R: TExtractResult;
begin
  R := Extract(BuildLatinPdf);
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Reflectivity of multilayer mirrors'#10#10'Interface roughness and layer thickness', R.Text);
end;

procedure TPdfTextExtractorTests.ExtractsCyrillic;
var
  R: TExtractResult;
begin
  R := Extract(Fixture('cyrillic-2pages.pdf'));
  Assert.AreEqual(Ord(eoText), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('Рентгеновская рефлектометрия многослойных зеркал'#10#10'Шероховатость границ раздела и толщина слоёв', R.Text);
end;

procedure TPdfTextExtractorTests.EncryptedReported;
var
  R: TExtractResult;
begin
  R := Extract(Fixture('encrypted.pdf'));
  Assert.AreEqual(Ord(eoEncrypted), Ord(R.Outcome), R.Detail);
  Assert.AreEqual('', R.Text);
end;

procedure TPdfTextExtractorTests.GarbageIsCorrupt;
var
  Bytes: TBytes;
  I: Integer;
  R: TExtractResult;
begin
  SetLength(Bytes, 4096);
  RandSeed := 12345;
  for I := 0 to High(Bytes) do
    Bytes[I] := Random(256);
  R := Extract(Bytes);
  Assert.AreEqual(Ord(eoCorrupt), Ord(R.Outcome), R.Detail);
end;

procedure TPdfTextExtractorTests.EmptyIsCorrupt;
begin
  Assert.AreEqual(Ord(eoCorrupt), Ord(Extract(nil).Outcome));
end;

procedure TPdfTextExtractorTests.TruncatedDoesNotCrash;
var
  Bytes: TBytes;
  R: TExtractResult;
  Cut: Integer;
begin
  Bytes := BuildLatinPdf;
  for Cut in [Length(Bytes) div 2, Length(Bytes) - 40, 20] do
  begin
    R := Extract(Copy(Bytes, 0, Cut));
    Assert.IsTrue(R.Outcome in [eoText, eoNoText, eoCorrupt], 'outcome ' + IntToStr(Ord(R.Outcome)));
  end;
end;

procedure TPdfTextExtractorTests.MissingLibraryIsUnsupported;
var
  Missing: ITextExtractor;
  R: TExtractResult;
begin
  Missing := TPdfTextExtractor.Create(TPath.Combine(TPath.Combine(TPath.GetTempPath, TGUID.NewGuid.ToString),
    'pdfium.dll'));
  R := Missing.Extract(BuildLatinPdf, nil);
  Assert.AreEqual(Ord(eoExtractorUnavailable), Ord(R.Outcome));
  Assert.AreEqual('PDFium not installed', R.Detail);
end;

procedure TPdfTextExtractorTests.CancelStopsBeforeNextPage;
var
  Calls: Integer;
  Bytes: TBytes;
begin
  Calls := 0;
  Bytes := BuildLatinPdf;
  Assert.WillRaise(
    procedure
    begin
      FExtractor.Extract(Bytes,
        function: Boolean
        begin
          Inc(Calls);
          Result := Calls > 1;
        end);
    end, EOperationCancelled);
  Assert.AreEqual(2, Calls);
end;

procedure TPdfTextExtractorTests.ConcurrentExtractsAreSerialized;
const
  ThreadCount = 4;
  Rounds = 10;
var
  Threads: array[0..ThreadCount - 1] of TThread;
  Texts: array[0..ThreadCount - 1, 0..Rounds - 1] of string;
  Failures: array[0..ThreadCount - 1] of string;
  Bytes: TBytes;
  Extractor: ITextExtractor;
  T, R: Integer;
  Expected: string;

  function Worker(Slot: Integer): TProc;
  begin
    Result :=
      procedure
      var
        Round: Integer;
      begin
        try
          for Round := 0 to Rounds - 1 do
            Texts[Slot, Round] := Extractor.Extract(Bytes, nil).Text;
        except
          on E: Exception do
            Failures[Slot] := E.ClassName + ': ' + E.Message;
        end;
      end;
  end;

begin
  Bytes := BuildLatinPdf;
  Extractor := FExtractor;
  Expected := Extractor.Extract(Bytes, nil).Text;
  Assert.IsNotEmpty(Expected);
  for T := 0 to ThreadCount - 1 do
  begin
    Threads[T] := TThread.CreateAnonymousThread(Worker(T));
    Threads[T].FreeOnTerminate := False;
  end;
  for T := 0 to ThreadCount - 1 do
    Threads[T].Start;
  for T := 0 to ThreadCount - 1 do
  begin
    Threads[T].WaitFor;
    Threads[T].Free;
  end;
  for T := 0 to ThreadCount - 1 do
  begin
    Assert.AreEqual('', Failures[T]);
    for R := 0 to Rounds - 1 do
      Assert.AreEqual(Expected, Texts[T, R]);
  end;
end;

procedure TPdfTextExtractorTests.CharLimitApplied;
var
  Limited: TPdfTextExtractor;
  Holder: ITextExtractor;
  R: TExtractResult;
begin
  Limited := TPdfTextExtractor.Create(FLibraryPath);
  Holder := Limited;
  Limited.MaxChars := 10;
  R := Holder.Extract(BuildLatinPdf, nil);
  Assert.AreEqual(Ord(eoLimitReached), Ord(R.Outcome));
  Assert.AreEqual(10, Length(R.Text));
end;

procedure TPdfTextExtractorTests.NormalizesWhitespace;
begin
  Assert.AreEqual('a b'#10'c d'#10#10'e', NormalizeExtractedText('a  '#9'b '#13#10'  c'#0' d'#13#10#13#10'e '));
end;

procedure TPdfTextExtractorTests.IdentifiesItself;
begin
  Assert.AreEqual('pdfium-text', FExtractor.Id);
  Assert.IsTrue(FExtractor.Version >= 1);
end;

procedure TPdfAvailabilityTests.Setup;
var
  Manifest: TSearchArtifactManifest;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'eln-pdfium-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FSourceFolder := TPath.Combine(SearchArtifactRoot, 'pdfium');
  if not TFile.Exists(Manifest.PdfiumLibraryPath(SearchArtifactRoot)) then
    Assert.Fail('PDFium is not installed at ' + FSourceFolder);
  FCopyFolder := TPath.Combine(FRoot, 'pdfium');
  FLibraryPath := Manifest.PdfiumLibraryPath(FRoot);
  ReleasePdfiumApi;
end;

procedure TPdfAvailabilityTests.TearDown;
begin
  ReleasePdfiumApi;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TPdfAvailabilityTests.ReleaseAllowsDeletingTheLibraryFolder;
var
  Extractor: ITextExtractor;
begin
  TDirectory.Copy(FSourceFolder, FCopyFolder);
  Extractor := TPdfTextExtractor.Create(FLibraryPath);
  Assert.AreEqual(Ord(eoText), Ord(Extractor.Extract(BuildLatinPdf, nil).Outcome));
  ReleasePdfiumApi;
  TDirectory.Delete(FCopyFolder, True);
  Assert.IsFalse(TDirectory.Exists(FCopyFolder));
  Assert.AreEqual(Ord(eoExtractorUnavailable), Ord(Extractor.Extract(BuildLatinPdf, nil).Outcome));
end;

procedure TPdfAvailabilityTests.ReleaseWithoutLoadedLibraryIsHarmless;
begin
  ReleasePdfiumApi;
  ReleasePdfiumApi;
  Assert.Pass;
end;

procedure TPdfAvailabilityTests.MissingPdfiumGivesNoPassageAndNoCacheRowUntilInstalled;
var
  Store: TSearchIndexStore;
  Registry: TTextExtractorRegistry;
  Stage: TFileTextStage;
  Reader: TMemoryFileReader;
  ReaderRef: IFileContentReader;
  Files: TArray<TFileTextRequest>;
  Passages: TSearchPassages;
  Md5, Extractor, Text: string;
  Outcome: TExtractOutcome;
begin
  Store := TSearchIndexStore.Open(TPath.Combine(FRoot, 'pdf.sqlite'), 'pdf-test', 8);
  Registry := TTextExtractorRegistry.Create(FLibraryPath);
  Stage := TFileTextStage.Create(Store, Registry);
  Reader := TMemoryFileReader.Create;
  ReaderRef := Reader;
  try
    Reader.Put('doc.pdf', BuildLatinPdf);
    SetLength(Files, 1);
    Files[0].FileId := 7;
    Files[0].ItemId := 1;
    Files[0].ProjectId := 1;
    Files[0].Ext := '.pdf';
    Files[0].RelativePath := 'doc.pdf';
    Passages := Stage.BuildFilePassages(Files, ReaderRef, nil, nil);
    Assert.AreEqual<NativeInt>(0, Length(Passages));
    Assert.IsFalse(Store.ReadFileText(7, Md5, Extractor, Outcome, Text), 'no cache row without PDFium');
    TDirectory.Copy(FSourceFolder, FCopyFolder);
    Passages := Stage.BuildFilePassages(Files, ReaderRef, nil, nil);
    Assert.IsTrue(Length(Passages) > 0, 'the PDF is extracted once PDFium appears');
    Assert.IsTrue(Store.ReadFileText(7, Md5, Extractor, Outcome, Text));
    Assert.AreEqual(Ord(eoText), Ord(Outcome));
  finally
    Stage.Free;
    Registry.Free;
    Store.Free;
  end;
end;

procedure TPdfAvailabilityTests.UnloadableLibraryGivesNotInstalled;
var
  R: TExtractResult;
begin
  TDirectory.CreateDirectory(ExtractFileDir(FLibraryPath));
  TFile.WriteAllBytes(FLibraryPath, TEncoding.ASCII.GetBytes(#127'ELF this is not a library'));
  R := TPdfTextExtractor.Create(FLibraryPath).Extract(BuildLatinPdf, nil);
  Assert.AreEqual(Ord(eoExtractorUnavailable), Ord(R.Outcome));
  Assert.AreEqual('PDFium not installed', R.Detail);
end;

initialization
  TDUnitX.RegisterTestFixture(TPdfTextExtractorTests);
  TDUnitX.RegisterTestFixture(TPdfAvailabilityTests);

end.
