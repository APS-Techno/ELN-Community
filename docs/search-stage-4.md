# Semantic search, stage 4: attachment text

Stage 4 adds the text of attachments to the search index. Before stage 4, only `.md` and `.txt` files were read. See `docs/search-index-stage-2.md` and `docs/search-stage-3.md`.

## Why no viewer plugins

The first plan was to take the text from the viewer plugins. This does not work. The PDF and HTML viewers draw in WebView2, the Office viewer embeds OLE, and all of them need a VCL frame on the UI thread. Extraction must run off the UI thread and must give the same text in Desktop and in the MCP server. So stage 4 has its own headless extractors in `ELN.Search`. They use no viewer plugin, no VCL and no COM/MSXML. XML is read with a small own scanner (`unit_XmlTextScanner`).

## Pipeline

1. The document provider gives the list of file records. It reads no file bytes.
2. `TFileTextStage` (`unit_FileTextStage`) reads each file through `IFileContentReader`, at most `FileTextMaxBytes` bytes.
3. The registry (`unit_TextExtractorRegistry`) selects the extractor by file extension.
4. The extractor returns a `TExtractResult` (outcome, text, short detail without file content).
5. The stage writes the result to the cache table `file_text`.
6. The text is split into passages (`pfFileText`, field "File text"). The normal embedding phase then embeds the new passages.

Extraction runs on the sync worker thread (Desktop) or on the caller thread of `SyncNow` (MCP). It never runs on the UI thread. The service lock is not held during extraction. It is taken only for the short cache reads and writes, so a search waits for at most one store operation. The notebook is never written.

The Desktop and the MCP server use this one path. For the same bytes and the same extractor version, both give the same text, so one host does not embed the passages of the other host again.

## Extractors

| Extension | Extractor id | Version |
| --- | --- | --- |
| `.pdf` | `pdfium-text` | 1 (`PdfExtractorVersion`) |
| `.docx` | `docx-text` | 1 |
| `.pptx` | `pptx-text` | 1 |
| `.xlsx` | `xlsx-text` | 1 |
| `.html`, `.htm` | `html-text` | 1 |
| `.json` | `json-text` | 1 |
| `.xml` | `xml-text` | 1 |
| `.csv` | `csv-text` | 1 |
| `.rtf` | `rtf-text` | 1 |
| `.md`, `.txt` | `plain-text` | 1 |

The cache key includes the extractor id and the version. A new version of an extractor reads the files again.

## Limits

| Constant | Value | Meaning |
| --- | --- | --- |
| `FileTextMaxBytes` | 64 MB | A larger file is not read (`eoTooLarge`). |
| `FileTextMaxChars` | 200000 | Text kept for one file (`eoLimitReached`). |
| `OpenXmlMaxUncompressed` | 256 MB | Total uncompressed XML read from one Office file. |
| `OpenXmlMaxEntries` | 10000 | Entries in one Office archive. |
| `SharedStringsMaxCount` | 1,000,000 | Shared strings in one workbook. A workbook with more is skipped as a whole. |
| `PdfMaxPages` | 2000 | Pages read from one PDF. |

The OpenXML limits protect against zip bombs.

## Outcomes and cache

`TExtractOutcome` has these values: `eoText`, `eoNoText`, `eoUnsupported`, `eoTooLarge`, `eoEncrypted`, `eoCorrupt`, `eoLimitReached` and `eoExtractorUnavailable`.

- `eoText` and `eoLimitReached` give passages. `eoLimitReached` keeps the text up to the limit.
- The other outcomes give no passage. A file that cannot be read never stops a sync.
- The table `file_text` has one row per file. The key is the content MD5 of the bytes (or `size:N` for a file larger than the read limit, which is not read) and `extractor id:version`. The row keeps the outcome, a short detail and the text.
- The row also keeps the file size and the last-write time (`size`, `last_write`). When the reader gives both values and they are the same as in the row, the file is not read and not hashed. When one of them changes, the program reads the file and compares the MD5. If the MD5 is the same, the row only gets the new size and time. A reader that gives no size and time (for example a remote storage) makes the program read the file in every sync.
- A row is valid while the MD5 and the extractor key are the same. The file is not read again until the size, the last-write time or the extractor version change.
- `eoExtractorUnavailable` (PDFium not installed) is not cached. The next sync tries again.
- An unexpected error during extraction writes no row. The next sync tries again.
- Rows of files that no longer exist are deleted at the end of each file phase.

## PDFium

- Source: `pdfium-win-x64.tgz`, release `chromium/8125` of `bblanchon/pdfium-binaries`. Platform: Windows x64 only.
- License: BSD-3-Clause for PDFium (`licenses\pdfium.txt`). The MIT `LICENSE` in the archive covers the build scripts. The other libraries in the archive keep their own licenses in `licenses\`. See `THIRD-PARTY-NOTICES.md`.
- The archive is in the manifest (`Archives` in `ELN.Search/search-artifacts.json`, manifest version 3). The program downloads it with the model and ONNX Runtime, and extracts only the listed files into `<artifact root>\pdfium`. The DLL is `<artifact root>\pdfium\bin\pdfium.dll`.
- The PDFium archive has `"Optional": true` in the manifest. The hosts start the search service when the model files and ONNX Runtime are valid. They do not check PDFium. The Setup dialog shows PDFium as an optional part. When only optional parts are missing, the dialog shows "Installed (optional parts missing)", and **Download and Install** downloads the missing parts.
- Without PDFium a PDF gives `eoExtractorUnavailable`. It gives no passage and no cache row. When PDFium is installed later, the next sync extracts the PDF.
- The Desktop calls `ReleasePdfiumApi` after it frees the service. This unloads `pdfium.dll`, so the Remove button can delete the folder.
- The program loads the DLL dynamically. All PDFium calls in a process go through one lock, because PDFium is not thread-safe.
- The total download is now 697,877,392 bytes (about 666 MB). It is the sum of the sizes of the model files, the archives and the reranker files in the manifest. It does not count the files inside the archives.

## File phase and deadline

- When the file phase is cancelled (the MCP deadline or the user), the service uses the cached text of the files that were not visited. It does not delete their passages.
- After a deadline cut, the embedding phase still runs with a new time budget. The budget is the same as the deadline. The sync result is not complete.
- After a user cancel, the embedding phase does not run.

## Status in the hosts

- The service status has a phase: `spIdle`, `spExtracting` or `spEmbedding`, with `FilesDone` and `FilesTotal`.
- The Desktop shows `Reading files... N/M` during extraction and `Indexing... N %` during embedding.
- The MCP result `index` object has `files_pending`.
- `IsComplete` is true only when the last sync was complete. A cancel during the last file gives an incomplete state.

## Measured timings

From the Task 5 smoke test: a synthetic notebook in a temp folder, the real E5 model, five files (a real text PDF of 2.2 MB, `.docx`, `.xlsx`, `.html` and an encrypted PDF).

| Step | Time | Passages |
| --- | --- | --- |
| First sync (Desktop-like) | 2848 ms | 49 added |
| Second sync, same bytes (includes model load of a new service) | 1464 ms | 0 embedded |
| Desktop sync after MCP searches, same store | 926 ms | 0 embedded |

The encrypted PDF gave no error. MCP and Desktop gave the same top file and the same scores for all four test queries. These values come from one small notebook. They are not a measurement of a real notebook.

## Out of scope

- OCR. A scanned PDF without text has no passage.
- Old binary Office files (`.doc`, `.xls`, `.ppt`).
- Metadata JSON from the viewers.
- Commercial.
