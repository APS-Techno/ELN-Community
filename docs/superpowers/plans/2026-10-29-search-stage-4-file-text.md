# Semantic Search Stage 4: Attachment Text (PDF, Office, HTML, Structured Text) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Index the text of PDF, Word, PowerPoint, Excel, HTML, JSON, XML, CSV and RTF attachments, extracted headlessly on the sync thread, cached per file content, and identical in the Desktop and MCP hosts.

**Architecture:** Viewer plugins do not extract text (scout 2026-10-29: PDF/HTML render in WebView2, Office embeds OLE, all need a VCL frame on the UI thread), so stage 4 adds headless extractors in `ELN.Search`. The notebook provider no longer reads file bytes; it emits a file list. The sync thread reads bytes through a thread-safe reader, hashes them, takes text from a `file_text` cache in the search store or extracts it, and turns it into `pfFileText` passages. PDFium joins the optional download.

**Tech Stack:** Delphi 13 Win64, `System.Zip`, `System.ZLib` (gzip), PDFium (bblanchon/pdfium-binaries `chromium/8125`, `pdfium-win-x64.tgz`), stage 1-3 units, DUnitX.

**Spec:** `docs/search-stage-3.md` ("Limitations": no viewer text), `docs/search-index-stage-2.md` (passages, store, reconcile). Owner decisions 2026-10-29: PDF through **PDFium in the optional download**; formats **docx/pptx/xlsx, html/htm, json/xml/csv, rtf**; viewer metadata JSON is **not** indexed.

## Global Constraints

- Extraction is headless and runs off the UI thread: no viewer plugins, no VCL, no COM/MSXML (COM needs per-thread init; use a small own XML text scanner).
- One extraction path for both hosts. For the same file bytes and extractor version, Desktop and MCP produce the same text, so the hosts never re-embed each other's passages.
- The notebook is never written. The provider does not read file bytes any more; `.md`/`.txt` move into the new pipeline (no second path).
- Limits (named constants): file bytes read ≤ `FileTextMaxBytes = 64 MB`; extracted text kept ≤ `FileTextMaxChars = 200000` characters per file; OpenXML: total uncompressed XML read ≤ `OpenXmlMaxUncompressed = 256 MB` and entry count ≤ `OpenXmlMaxEntries = 10000` (zip bomb guard); PDF pages read ≤ `PdfMaxPages = 2000`.
- A file that fails to extract (corrupt, encrypted, over limits, unknown) gives no text passage and never stops a sync; the failure kind is kept in the cache so it is not retried until the bytes or the extractor version change.
- PDFium: x64 only, loaded dynamically from `<artifact root>\pdfium\bin\pdfium.dll`; all PDFium calls in a process go through one lock (PDFium is not thread-safe).
- Search remains Win64 only. `ELN.Search` stays free of Aurelius entities, `ELN.Model`, VCL and plugin units.
- Do not touch APS-ELN-Commercial.
- Comments denied by default; CRLF + UTF-8 BOM for `.pas`/`.dpr`/`.dfm`; docs and Help in ASD-STE100.
- Local commits per task on a feature branch; no push without the user's approval.

## Review Focus

1. **Hostile or broken files** (zip bomb `.docx`, corrupt or encrypted PDF, 500 MB file, binary renamed `.json`, deeply nested HTML) — skipped with a recorded reason, bounded time and memory, no crash, sync continues. Tests in Tasks 2, 3.
2. **File changed or deleted after indexing** — new bytes give new text; deleted files lose their passages; a cached failure is retried after the bytes change. Tests in Task 4.
3. **Desktop and MCP index the same notebook** — identical `pfFileText` passages and hashes, no ping-pong re-embedding. Test in Task 4 (two pipelines, same store, second sync embeds 0).
4. **Cancel during a long extraction** (2000-page PDF, large xlsx) — sync stops within one page / one zip entry. Tests in Tasks 2, 4.
5. **Existing installs without PDFium** — Setup shows "not installed", one **Download and Install** fetches only PDFium (other files verified and skipped); search keeps working without PDF text until then. Tests in Task 1, smoke in Task 5.

---

### Task 1: PDFium in the manifest and `.tgz` support in the installer

**Files:**
- Modify: `ELN.Search/search-artifacts.json` (`ManifestVersion` 2; replace the single runtime archive by a list `Archives` with entries for ONNX Runtime and PDFium)
- Modify: `ELN.Search/unit_SearchArtifacts.pas`, `ELN.Search/unit_SearchArtifactInstall.pas`, `tools/Get-SearchArtifacts.ps1`
- Create: `ELN.Search/unit_TarGz.pas`
- Modify: `ELN.Community.Tests/test_SearchArtifacts.pas`, `THIRD-PARTY-NOTICES.md`

**Interfaces:**
- Produces:
```pascal
type
  TArtifactArchiveKind = (akZip, akTarGz);
  TArtifactArchive = record
    Name, Url, Folder: string; Size: Int64; Sha256: string; Kind: TArtifactArchiveKind;
    Files: TArray<TArtifactFile>;     // RelativePath = Folder + '\' + path inside archive
  end;
  TSearchArtifactManifest = record
    ...existing model fields...
    Archives: TArray<TArtifactArchive>;
    function PdfiumLibraryPath(const Root: string): string;
  end;
procedure ExtractTarGzEntries(const ArchivePath: string; const Wanted: TArray<string>;
  const TargetOf: TFunc<string, string>; const Cancelled: TCancelCheck);   // ustar + GNU long names, regular files only
```
  PDFium archive: `https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/8125/pdfium-win-x64.tgz`, size `3904987`, SHA-256 `9A964261760CFF52570AABF038AB346D3A5034DD8B30D0D5FE8861235D356B8B`, folder `pdfium`, files `bin\pdfium.dll` and `LICENSE` plus every file under `licenses\` in the archive. Download the archive once with `curl` to read the exact inner sizes and SHA-256 values into the manifest. `RuntimeFolder`/`RuntimeArchive` callers move to `Archives` (clean cutover; Desktop and MCP readiness use `CheckSearchArtifacts`, which now covers all archives).

- [ ] **Step 1: Failing tests:** `LoadsManifestV2` (two archives, PDFium kind `akTarGz`, `TotalDownloadBytes` includes 3904987); `TarGzExtractsListedFilesOnly` (test builds a `.tgz` with `System.ZLib` gzip of a hand-built ustar stream: 3 files, one with a > 100-char name using a GNU `L` entry; only 2 wanted are written, bytes equal); `TarGzRejectsTraversal` (entry `../x` with wanted list containing it → `ESearchArtifactError`, nothing written outside root); `TarGzTruncatedArchiveFails`; `InstallSkipsValidFilesAndFetchesOnlyMissingArchive` (folder fetcher: model and ORT already valid, PDFium missing → only the PDFium archive fetched); `CancelDuringTarExtraction`.
- [ ] **Step 2:** `pwsh -NoProfile -File tools/build-community.ps1 -Target SearchIndexTests -Platform Win64 -RunTests` → FAIL.
- [ ] **Step 3:** Implement. Gzip via `TZDecompressionStream` with `WindowBits = 15 + 16`; tar headers in 512-byte blocks, size field octal, skip non-regular entries.
- [ ] **Step 4:** Run → PASS. `tools/Get-SearchArtifacts.ps1` handles `.tgz` with `tar.exe -xzf` (built into Windows 10+) and `-VerifyOnly` reports all files; real run on this workstation installs PDFium beside the existing artifacts.
- [ ] **Step 5:** Commit (`THIRD-PARTY-NOTICES.md`: PDFium, BSD-3-Clause/Apache-2.0 per the archive `LICENSE` and `licenses\`, downloaded beside the DLL).

### Task 2: PDFium binding and PDF text extractor

**Files:**
- Create: `ELN.Search/unit_PdfiumApi.pas` (dynamic binding: `FPDF_InitLibraryWithConfig`, `FPDF_DestroyLibrary`, `FPDF_LoadMemDocument64`, `FPDF_GetLastError`, `FPDF_GetPageCount`, `FPDF_LoadPage`, `FPDF_ClosePage`, `FPDF_CloseDocument`, `FPDFText_LoadPage`, `FPDFText_ClosePage`, `FPDFText_CountChars`, `FPDFText_GetText`)
- Create: `ELN.Search/unit_TextExtractors.pas` (shared types; PDF extractor lives here or in `unit_PdfTextExtractor.pas` if the unit grows past ~400 lines)
- Create: `ELN.Community.Tests/test_TextExtractors.pas`; register in `SearchIndexTests.dpr` and `CommunityStorageTests.dproj`

**Interfaces:**
- Produces:
```pascal
type
  TExtractOutcome = (eoText, eoNoText, eoUnsupported, eoTooLarge, eoEncrypted, eoCorrupt, eoLimitReached);
  TExtractResult = record
    Outcome: TExtractOutcome;   // eoLimitReached still carries the text up to the limit
    Text: string;
    Detail: string;             // short reason, no file content
  end;
  ITextExtractor = interface
    function Id: string;        // e.g. 'pdfium-text'
    function Version: Integer;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
  end;
  TPdfTextExtractor = class(TInterfacedObject, ITextExtractor)
    constructor Create(const LibraryPath: string);   // load on first Extract; missing DLL → every Extract returns eoUnsupported with Detail 'PDFium not installed'
  end;
const
  FileTextMaxBytes = 64 * 1024 * 1024;
  FileTextMaxChars = 200000;
  PdfMaxPages = 2000;
```
  Pages are joined with `#10#10`; text is normalized (CRLF → LF, NUL removed, runs of whitespace inside a line collapsed). `FPDF_ERR_PASSWORD` → `eoEncrypted`; other load errors → `eoCorrupt`. Cancel is checked before each page. A process-wide `TCriticalSection` wraps every PDFium call; the library initializes once per process and is never unloaded before process exit.

- [ ] **Step 1: Failing tests** (fixture PDFs built as strings in the test: a 2-page text PDF with Latin and Cyrillic (`/ToUnicode` CMap or standard encoding for Latin + a Type0 font is heavy — use a Latin-only text PDF for the hand-built fixture and add a committed small PDF made with any PDF writer for Cyrillic under `ELN.Community.Tests/Fixtures/Search/Files/`); an encrypted PDF fixture (committed, generated once with `qpdf --encrypt` or Python `pypdf`, documented in the fixture README); random bytes; truncated PDF): `ExtractsTwoPages`, `ExtractsCyrillic`, `EncryptedReported`, `GarbageIsCorrupt`, `TruncatedDoesNotCrash`, `MissingLibraryIsUnsupported`, `CancelStopsBeforeNextPage` (cancel after first page → `EOperationCancelled`), `ConcurrentExtractsAreSerialized` (4 threads × 10 extracts → all equal results, no AV), `CharLimitApplied` (limit lowered via a test seam → `eoLimitReached`, length = limit). Tests needing the DLL fail with the path when it is missing (stage 1 rule).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit.

### Task 3: OpenXML, HTML, JSON, XML, CSV, RTF and plain-text extractors

**Files:**
- Modify: `ELN.Search/unit_TextExtractors.pas` (or create `unit_TextExtractorsOffice.pas` / `unit_XmlTextScanner.pas` to keep units focused)
- Modify: `ELN.Community.Tests/test_TextExtractors.pas`

**Interfaces:**
- Produces:
```pascal
type
  TTextExtractorRegistry = class
    constructor Create(const PdfiumLibraryPath: string);
    function ForExtension(const Ext: string): ITextExtractor;   // nil when not supported; Ext lowercase with dot
    function Identity: string;                                   // all ids+versions, sorted; part of the cache key
  end;
const
  OpenXmlMaxUncompressed = 256 * 1024 * 1024;
  OpenXmlMaxEntries = 10000;
```
  Extensions: `.pdf`; `.docx` (`word/document.xml` + headers/footers/footnotes; `w:t` text, `w:tab` → tab, `w:p`/`w:br` → line break); `.pptx` (`ppt/slides/slideN.xml` in slide number order + notes; `a:t`, paragraphs → line breaks); `.xlsx` (shared strings + inline strings + cell values of every sheet in workbook order, cells tab-separated, rows line-separated; no formulas); `.html`/`.htm` (drop `script`/`style`/comments, block tags → line breaks, decode named and numeric entities, charset from BOM or `<meta charset>`, default UTF-8 with ANSI fallback); `.json` (all string values and object keys in document order, one per line; invalid JSON → `eoCorrupt`); `.xml` (text nodes and attribute values); `.csv` (as text, `;`/`,` kept); `.rtf` (strip control words and groups `\*`, `fonttbl`, `colortbl`, `stylesheet`, `info`, `pict`; decode `\'hh` with `\ansicpg`, `\uN`); `.md`/`.txt` (UTF-8 with ANSI fallback, same as stage 2). Binary sniff: a text format whose first 8 KB contain NUL bytes (outside UTF-16 BOM) → `eoUnsupported`. Zip guard: count entries and sum of `UncompressedSize`, and stop reading at the limit even if headers lie.

- [ ] **Step 1: Failing tests** (fixtures created in the test with `TZipFile` and string literals; no Office needed): per format one positive test with exact expected text (including a Cyrillic word and an entity/escape), plus `DocxZipBombRejected` (entry claiming 1 GB, or 20000 entries → `eoTooLarge`, returns in < 2 s), `XlsxSharedStringsAndNumbers`, `PptxSlideOrderNumeric` (slide10 after slide2), `HtmlSkipsScriptAndStyle`, `HtmlDeepNestingNoStackOverflow` (100000 nested `div`), `JsonInvalidIsCorrupt`, `RtfUnicodeAndCodepage`, `BinaryRenamedJsonUnsupported`, `RegistryUnknownExtensionNil`, `RegistryIdentityStable` (same string on two instances), `ExtractionIsDeterministic` (each extractor twice on the same bytes → equal text).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. XML scanning is an iterative state machine (no recursion), handles CDATA, the five predefined entities and numeric references, ignores DTDs.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit.

### Task 4: Extraction pipeline, `file_text` cache and provider cutover

**Files:**
- Modify: `ELN.Search/unit_SearchIndexStore.pas` (schema version 2: table `file_text(file_id INTEGER, content_md5 TEXT, extractor TEXT, outcome INTEGER, detail TEXT, text TEXT, PRIMARY KEY(file_id))`; methods below)
- Create: `ELN.Search/unit_FileTextStage.pas`
- Modify: `ELN.Search/unit_SearchPassages.pas` (`TSearchSnapshot`, `TFileTextRequest`, `IFileContentReader`)
- Modify: `ELN.Model/unit_SearchDocumentProvider.pas` (emit `TFileTextRequest` for every live file with a supported or `.md`/`.txt` extension; stop reading bytes; `ReadSnapshot` replaces `ReadPassages` for hosts)
- Modify: `ELN.Search/unit_SemanticSearchService.pas` (`StartSync`/`SyncNow` take `TSearchSnapshot` and `IFileContentReader`; extraction runs on the sync thread under the same batch/lock rules: the lock is not held while extracting)
- Modify: tests in `test_SearchIndex.pas`, `test_SemanticSearchService.pas`

**Interfaces:**
- Produces:
```pascal
type
  TFileTextRequest = record FileId: Int64; ItemId, ProjectId: Integer; Ext, RelativePath: string; end;
  TSearchSnapshot = record Passages: TSearchPassages; Files: TArray<TFileTextRequest>; end;
  IFileContentReader = interface       // must be safe to call from a worker thread
    function ReadFile(const RelativePath: string; MaxBytes: Int64; out Bytes: TBytes): Boolean;  // False = missing or larger than MaxBytes
  end;
  TStorageFileReader = class(TInterfacedObject, IFileContentReader)   // in ELN.Model; wraps INotebookStorage
    constructor Create(const Storage: INotebookStorage);
  end;
  TFileTextStage = class
    constructor Create(Store: TSearchIndexStore; Registry: TTextExtractorRegistry);
    function BuildFilePassages(const Files: TArray<TFileTextRequest>; const Reader: IFileContentReader;
      const Cancelled: TCancelCheck; const Progress: TSyncProgress): TSearchPassages;
  end;
// TSearchIndexStore additions:
//   function ReadFileText(FileId: Int64; out Md5, Extractor: string; out Outcome: TExtractOutcome; out Text: string): Boolean;
//   procedure WriteFileText(FileId: Int64; const Md5, Extractor: string; Outcome: TExtractOutcome; const Detail, Text: string);
//   procedure DeleteFileTextExcept(const LiveFileIds: TArray<Int64>);
const
  SearchIndexSchemaVersion = '2';
```
  Per file: read bytes (≤ `FileTextMaxBytes`, else cached `eoTooLarge` keyed by the reader's size info), MD5 of the bytes; cache hit when `content_md5` and `extractor` (= `Registry.Identity`-derived id+version of the chosen extractor) match → reuse text/outcome; else extract and write the cache row. Text outcomes become passages exactly like stage 2 `pfFileText` (fold, chunk, key `file:<id>:text#<n>`). Cache rows of files no longer in the snapshot are deleted. `TStorageFileReader` thread safety: `TLocalNotebookStorage.ReadBytes` must not touch shared mutable state — verify, and if it does, guard it in the reader (not by changing storage semantics).

- [ ] **Step 1: Failing tests:** `ProviderEmitsFileRequestsAndReadsNoBytes` (provider with a storage double that raises on `ReadBytes` → snapshot succeeds); `FileTextCachedByContent` (second sync: extractor double counts 0 calls); `ChangedBytesReExtract`; `DeletedFileLosesPassagesAndCacheRow`; `CachedFailureRetriedAfterBytesChange`; `ExtractorVersionBumpReExtracts`; `TwoPipelinesSameStoreNoReembed` (pipeline A syncs; pipeline B with its own registry and reader instances syncs the same snapshot → embedded 0); `CancelDuringExtraction` (extractor double sleeps 50 ms per file, cancel after 2 files → `EOperationCancelled`, next sync completes); `StorageReaderFromWorkerThread` (8 threads read 50 files each through `TStorageFileReader` on a real local notebook → all bytes correct); `SchemaV1StoreRebuilds` (open a v1 store → reset, sync completes). Update service tests to the new signatures.
- [ ] **Step 2:** Run `SearchIndexTests` → FAIL.
- [ ] **Step 3:** Implement. Remove the old byte-reading code from the provider and stage-2 constants that only it used.
- [ ] **Step 4:** Run `SearchIndexTests` → PASS.
- [ ] **Step 5:** Commit.

### Task 5: Host wiring and smoke

**Files:**
- Modify: `ELN.Community.Desktop/frm_CommunityMain.pas` (`RefreshSemanticIndex` uses `ReadSnapshot` + `TStorageFileReader`)
- Modify: `ELN.MCPServer/unit_ToolsNavigation.pas` (`search_semantic` uses `ReadSnapshot` + `TStorageFileReader`; deadline also stops extraction)
- Modify: `ELN.Search/unit_SemanticSearchService.pas` factory/readiness if PDFium readiness needs it (`SearchArtifactsReady` covers all archives after Task 1)
- Modify: `ELN.Desktop/Dialogs/Search/dlg_Search.pas` only if a new field label is needed (the field stays `pfFileText`, "File text")
- Modify: MCP tests in `test_SemanticSearchTool.pas`

- [ ] **Step 1:** Update MCP tests (fake extractor registry seam) → RED on the new behavior: `FileTextFoundThroughMcp` (a `.docx` attachment's text is found by `search_semantic`).
- [ ] **Step 2:** Implement wiring.
- [ ] **Step 3:** Run `SearchIndexTests`, `DesktopRegressionTests`, `AuthorizationTests` (Win64) → PASS; build `CommunityDesktop`, `CommunityMCP`.
- [ ] **Step 4: Smoke** on a synthetic notebook with attachments: a real text PDF (any public-domain paper PDF downloaded to a temp folder), a `.docx` and `.xlsx` created with the test helpers, an `.html` page, an encrypted PDF. Desktop: Setup shows "Not installed" until PDFium is installed, then **Download and Install** fetches only PDFium (observe the progress file name); search by meaning finds a sentence from the PDF and from the docx; the encrypted PDF gives no error. MCP: `search_semantic` returns the same top hit for the same query, and a following Desktop sync embeds 0 passages. Record timings: first sync time for the PDF, second sync time.
- [ ] **Step 5:** Commit.

### Task 6: Documentation and Help

**Files:**
- Create: `docs/search-stage-4.md` (pipeline, cache, extractor list and limits, PDFium source and license, outcomes, why no viewer plugins, measured timings from Task 5)
- Modify: `docs/search-stage-3.md`, `docs/search-index-stage-2.md` (file text section now points to stage 4), `README.md`, `ELN.Desktop/Assets/Runtime/Help/Search.html` (what file types are searched, limits, encrypted files skipped), `Troubleshooting.html` (row: "A PDF is not found by meaning" → encrypted, scanned image without text, over 64 MB, PDFium not installed), `MCP.html` if the tool text changes

- [ ] **Step 1:** Write.
- [ ] **Step 2:** Rebuild the Help index (`tools/Build-HelpIndex.ps1` on a temp copy) and run the Help search JS: "PDF" finds the new section.
- [ ] **Step 3:** Full verification: `SearchIndexTests`, `SearchTests`, `NotebookTests`, `DesktopRegressionTests`, `AuthorizationTests`, `Installer/Test-StageRuntime.ps1` (Win64) → PASS.
- [ ] **Step 4:** Commit.

## Out of scope

Scanned PDFs (no OCR), legacy `.doc`/`.xls`/`.ppt`, viewer metadata JSON, Commercial.
