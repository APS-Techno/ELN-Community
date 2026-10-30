# Semantic Search Stage 2: Notebook Index and Hybrid Retrieval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a Community notebook into a rebuildable, access-filtered hybrid search index (vectors + FTS5 words + FTS5 trigrams) that a host can query, without changing the notebook schema, the Desktop or MCP.

**Architecture:** A read-only document provider in `ELN.Model` turns notebook rows into keyed passages with content hashes. A neutral store in `ELN.Search` keeps passages, float32 vectors and two FTS5 tables in a separate SQLite file. A reconciling indexer embeds only new or changed passages. A hybrid searcher fuses vector, word and trigram rankings with reciprocal rank fusion, filters by visible projects and revalidates each hit against the live notebook.

**Tech Stack:** Delphi 13 (Studio 37.0), TMS Aurelius (notebook reads), raw SQLite through `Aurelius.Drivers.SQLite.Import` (`f_sqlite3_*`, the same import `SearchHarness --fts5` uses), stage 1 `ITextEmbedder` and `TExactVectorIndex`, DUnitX.

**Spec:** `docs/search-embedding-foundation.md`, section "Next steps (proposal)", items 1-5. Items 6 (hosts) and 7 (installer) are stage 3.

## Scope decisions (differ from the proposal)

- **No AuditLog cursor.** Evidence (code survey 2026-10-28): tag assign/unassign and tag rename (`unit_TagModel.pas:137-169`), comments, item links, package import (`unit_PackageImport.pas`), protocol template import, `UpdateFile` title/hash writes (`unit_ItemModel.pas:823`) and per-item purge (`unit_RecycleBinModel.pas:395` writes one row with EntityId 0) write no audit row. `AuditLog` has no project column. A cursor would miss changes silently. Sync is a full reconcile: the provider re-reads all passage texts (cheap SQL), compares SHA-256 hashes, and embeds only the difference (the expensive part). Adding audit rows to those paths is out of scope.
- **Attachment text only for `.md` and `.txt`**, read through `INotebookStorage.ReadBytes`. Viewer extraction (`TPluginHost.ExtractDetailedInfo`) needs VCL and BPL plugins (`ELN.MCPServer/unit_PluginHost.pas`), so it moves to stage 3 behind the provider's file-text interface.
- **Protocol `FormData` is indexed.** `TSearchModel` never reads it; it is the largest scientific text field.

## Global Constraints

- `ELN.Search` units stay free of Aurelius entities, `ELN.Model`, VCL and plugin units. Only `ELN.Model/unit_SearchDocumentProvider.pas` touches domain classes.
- Notebook is opened read-only by the indexer: no `Save`, `Flush`, `Update` or `RecordAudit` call.
- Search database path: `ChangeFileExt(DatabasePath, '') + '.search.sqlite'`. It must not use the suffixes `-journal`, `-wal`, `-shm` of the notebook (`TLocalNotebook.CheckNoSidecars`).
- Vector BLOB: `Dimension` x little-endian IEEE float32, no header.
- FTS word table: `tokenize='unicode61 remove_diacritics 2'`; trigram table: `tokenize='trigram'`. Indexed text and query text both get `ё`→`е` and `Ё`→`Е` folding (FTS5 probe result in the spec).
- No fixed score threshold (spec: E5 scores lie in a narrow band).
- Comments denied by default; CRLF + UTF-8 BOM for `.pas`/`.dpr`; Win64 Debug first via `tools/build-community.ps1`.
- No commit or push without the user's approval; the "Commit" steps below stage explicit paths and wait for that approval.

## Review Focus

1. **Item moved to the recycle bin or to another project after indexing** — the hit must disappear (revalidation) before the next sync, and sync must delete or re-scope its passages. Test in Task 5 and Task 4.
2. **Project owned by another principal in the same notebook file** — no passage from it may reach results, also through the FTS paths. Test in Task 5.
3. **FTS5 query syntax in user text** (`"`, `*`, `-`, `NEAR`, `AND`, unbalanced quotes, `SMP-2024-017`) — must not raise; treated as plain words/phrase. Test in Task 3.
4. **Embedder identity change or a corrupt/foreign search file** — full rebuild, never mixed vectors. Test in Task 3 and Task 4.
5. **Cancellation mid-sync** — store stays consistent; the next sync completes the work without duplicates. Test in Task 4.

---

### Task 1: Passage model and text chunker

**Files:**
- Create: `ELN.Search/unit_SearchPassages.pas`
- Create: `ELN.Community.Tests/test_SearchIndex.pas` (fixture `TPassageChunkerTests`)
- Create: `ELN.Community.Tests/SearchIndexTests.dpr`
- Modify: `ELN.Community.Tests/CommunityStorageTests.dproj` (MainSource item group for `SearchIndexTests.dpr`, pattern of `SearchTests.dpr` at lines 97-99)
- Modify: `tools/build-community.ps1` (add `SearchIndexTests` to `-Target` ValidateSet and `$sourceName`; do **not** add it to the TMS exclusion list, it needs Aurelius)

**Interfaces:**
- Produces:
```pascal
type
  TPassageField = (pfItemTitle, pfItemDescription, pfItemProperties, pfItemTags,
    pfEntryTitle, pfProtocolForm, pfValueDescription, pfFileName, pfFileText);
  TSearchPassage = record
    Key: string;          // '<kind>:<id>:<field>#<chunk>', e.g. 'item:12:description#0'
    ProjectId: Integer;
    ItemId: Integer;
    FileId: Int64;        // 0 when not a file passage
    Field: TPassageField;
    Text: string;
    ContentHash: string;  // uppercase hex SHA-256 of UTF-8 Text
  end;
  TSearchPassages = TArray<TSearchPassage>;
function FoldSearchText(const S: string): string;                       // ё/Ё folding only
function ChunkText(const Text: string; MaxChars, OverlapChars: Integer): TArray<string>;
function PassageHash(const Text: string): string;
const
  PassageMaxChars = 1200;
  PassageOverlapChars = 150;
```

- [ ] **Step 1: Write failing tests** in `TPassageChunkerTests`: `ShortTextIsOneChunk` (`'abc'` → `['abc']`); `EmptyOrBlankGivesNoChunks` (`''`, `'  '#13#10` → length 0); `SplitsAtParagraphThenSentence` (3 paragraphs of 700 chars → 3 chunks, none > 1200, each starts at a paragraph start); `HardSplitWithOverlap` (one 3000-char word → chunks of ≤1200, consecutive chunks share exactly 150 chars); `NoSurrogateSplit` (emoji at position 1199 stays whole); `HashIsStable` (`PassageHash('Плёнка')` equals the SHA-256 of its UTF-8 bytes, computed with `THashSHA2` in the test); `FoldsYo` (`FoldSearchText('Ёлка плёнка')` = `'Елка пленка'`).
- [ ] **Step 2: Build and run, expect compile failure**
  Run: `pwsh tools/build-community.ps1 -Target SearchIndexTests -RunTests`
  Expected: FAIL, `unit_SearchPassages` not found.
- [ ] **Step 3: Implement** the unit. Chunk priority: blank line, then line break, then `. `/`! `/`? `, then space, then hard cut; overlap applies only to the hard and space cuts. Trim chunks; drop empty ones.
- [ ] **Step 4: Run** same command. Expected: all `TPassageChunkerTests` PASS.
- [ ] **Step 5: Commit** (after approval) `ELN.Search/unit_SearchPassages.pas`, the test unit, dpr, dproj, build script.

### Task 2: Notebook document provider

**Files:**
- Create: `ELN.Model/unit_SearchDocumentProvider.pas`
- Modify: `ELN.Community.Tests/test_SearchIndex.pas` (fixture `TDocumentProviderTests`), `SearchIndexTests.dpr`

**Interfaces:**
- Consumes: Task 1 types; `TObjectManager`; `INotebookStorage.ReadBytes(RelativePath): TBytes`; relative path as built by `TDataModel.GetFilePathDAV` (`ELN.Model/unit_DataModel.pas:147`) — reuse its helper (`AttachmentRelativePath`, `ELN.Model/unit_FilePaths.pas:8`), do not duplicate it.
- Produces:
```pascal
type
  ISearchDocumentSource = interface
    function ReadPassages(const Cancelled: TCancelCheck): TSearchPassages;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean; // exists and not IsDeleted
  end;
  TNotebookDocumentProvider = class(TInterfacedObject, ISearchDocumentSource)
    constructor Create(Manager: TObjectManager; const Storage: INotebookStorage);
  end;
const
  FileTextExtensions: array[0..1] of string = ('.md', '.txt');
  FileTextMaxBytes = 2 * 1024 * 1024;
```
  Put `ISearchDocumentSource` in `ELN.Search/unit_SearchPassages.pas` so `ELN.Search` does not depend on `ELN.Model`.

Field mapping (all rows with `TItem.IsDeleted = False` only, every project; access is applied at query time):

|Field|Source|Key kind/id|
|---|---|---|
|pfItemTitle, pfItemDescription, pfItemProperties|`TItem.Title/Description/Properties`|`item:<ItemId>`|
|pfItemTags|tag names joined by `', '` via `TItemTag`→`TTag`|`item:<ItemId>`|
|pfEntryTitle|`TLabEntry.Title`|`entry:<EntryId>`|
|pfProtocolForm|`TProtocol.FormData` (as stored)|`entry:<EntryId>`|
|pfValueDescription|`TValue.Description`|`value:<ValueId>`|
|pfFileName|`TFile.FullName`|`file:<FileId>`|
|pfFileText|UTF-8 bytes of `.md`/`.txt` ≤ `FileTextMaxBytes`; missing bytes → skipped, no raise|`file:<FileId>`|

Text is folded with `FoldSearchText` and chunked with `ChunkText`; empty fields give no passage. Read with Aurelius criteria in bulk (one query per entity class, no per-item lazy loads).

- [ ] **Step 1: Write failing tests.** Fixture setup: `TLocalNotebook.CreateNew` in a temp folder (pattern `test_ItemTreeBatch.pas:63`), principal A; create project P1 with item I1 (title `'Mo/Si multilayer'`, description 2600 chars), a protocol entry with `FormData` `'{"substrate":"Si wafer"}'`, a value with description `'period thickness'`, tag `'XRR'`, a `.md` attachment `'# Notes'#10'плёнка отслоилась'`, a `.pdf` attachment; item I2 in the recycle bin. Tests: `ReadsAllFieldKinds` (keys `item:I1:title#0`, `item:I1:tags#0`, `entry:E:form#0`, `value:V:description#0`, `file:F:name#0`, `file:F:text#0` exist, each with ProjectId = P1 and ItemId = I1); `LongDescriptionChunked` (`item:I1:description#0..#2`); `DeletedItemExcluded` (no key with I2); `PdfHasNameOnly` (no `file:<pdf>:text`); `MissingAttachmentBytesSkipped` (delete the md bytes from storage → no `file:F:text`, no exception); `TextIsFolded` (md passage contains `'пленка'`); `IsItemLiveReportsProjectAndBin` (I1 → True, P1; I2 → False; unknown id → False); `ProviderDoesNotWrite` (max `AuditLog.Id` and file modified time of the notebook unchanged after `ReadPassages`).
- [ ] **Step 2: Run** `pwsh tools/build-community.ps1 -Target SearchIndexTests -RunTests`. Expected: FAIL (unit missing).
- [ ] **Step 3: Implement** `TNotebookDocumentProvider`. Check `Cancelled` between entity classes.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** (after approval).

### Task 3: Search store

**Files:**
- Create: `ELN.Search/unit_SearchIndexStore.pas`
- Modify: `test_SearchIndex.pas` (fixture `TSearchIndexStoreTests`), `SearchIndexTests.dpr`

**Interfaces:**
- Consumes: Task 1 types; `Aurelius.Drivers.SQLite.Import`.
- Produces:
```pascal
type
  ESearchIndexError = class(Exception);
  TStoredPassage = record
    Key: string; ProjectId, ItemId: Integer; FileId: Int64;
    Field: TPassageField; ContentHash: string;
  end;
  TTextHit = record Key: string; Rank: Integer; end;
  TSearchIndexStore = class
    constructor Open(const Path, EmbedderIdentity: string; Dimension: Integer);
    // creates; or wipes all rows when schema_version, identity or dimension differ, or the file is not a valid store
    property WasReset: Boolean;
    function ReadCatalog: TDictionary<string, TStoredPassage>;          // caller frees
    procedure BeginBatch; procedure CommitBatch; procedure RollbackBatch;
    procedure Upsert(const P: TSearchPassage; const Vector: TEmbeddingVector);
    procedure UpdateCoordinates(const P: TSearchPassage);                 // same hash, moved item/project
    procedure Delete(const Key: string);
    procedure LoadVectors(Index: TExactVectorIndex);                       // SourceId = Key, Scope = IntToStr(ProjectId)
    function MatchWords(const Query: string; const ProjectIds: TArray<Integer>; Limit: Integer): TArray<TTextHit>;
    function MatchTrigrams(const Query: string; const ProjectIds: TArray<Integer>; Limit: Integer): TArray<TTextHit>;
    function PassageText(const Key: string): string;
  end;
const
  SearchIndexSchemaVersion = '1';
```
  Schema: `meta(key TEXT PRIMARY KEY, value TEXT)` with `schema_version`, `embedder_identity`, `dimension`; `passages(id INTEGER PRIMARY KEY, key TEXT UNIQUE NOT NULL, project_id INTEGER, item_id INTEGER, file_id INTEGER, field INTEGER, text TEXT, content_hash TEXT, vector BLOB)`; `passages_words` and `passages_tri` as external-content FTS5 tables over `passages(text)` kept in sync by `AFTER INSERT/UPDATE/DELETE` triggers. Journal mode WAL on the search file only.

- [ ] **Step 1: Write failing tests:** `CreatesAndReopens` (upsert 3, reopen same identity → `WasReset=False`, catalog 3); `IdentityChangeResets` (reopen with other identity → `WasReset=True`, catalog 0); `DimensionChangeResets`; `ForeignFileResets` (path holds 100 random bytes → `WasReset=True`, usable store; a SQLite file with an unrelated table → same); `VectorRoundTrip` (upsert a 384 vector, `LoadVectors` → search returns key with score 1.0 ± 1e-6); `UpsertReplacesAndFtsFollows` (change text of key → `MatchWords` finds new word, not old); `DeleteRemovesFromFts`; `WordsRespectProjects` (same word in project 1 and 2, filter `[1]` → only project-1 key; filter `[]` → empty); `YoFolding` (stored `'пленка'`, query `'плёнка'` → hit); `TrigramFindsIdentifierFragment` (`'SMP-2024-017'` stored, query `'2024-01'` → hit; query of 2 chars → empty, no raise); `QuerySyntaxIsInert` (queries `'"'`, `'a AND'`, `'NEAR(x'`, `'*'`, `'-x'`, `'SMP-2024-017'` → no exception); `RollbackLeavesPriorState`.
- [ ] **Step 2: Run.** Expected: FAIL (unit missing).
- [ ] **Step 3: Implement.** Query safety: split folded query into tokens on whitespace, wrap each in double quotes with inner `"` doubled, join with `OR` for words; whole query as one quoted phrase for trigrams. Rank by `bm25()`. Prepared statements with bound parameters; project filter as `project_id IN (SELECT value FROM json_each(?))`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** (after approval).

### Task 4: Reconciling indexer

**Files:**
- Create: `ELN.Search/unit_SearchIndexer.pas`
- Modify: `test_SearchIndex.pas` (fixture `TSearchIndexerTests`, uses a deterministic fake embedder), `SearchIndexTests.dpr`

**Interfaces:**
- Consumes: `ISearchDocumentSource`, `TSearchIndexStore`, `ITextEmbedder`.
- Produces:
```pascal
type
  TSyncStats = record Added, Changed, Moved, Removed, Unchanged, Truncated: Integer; Elapsed: Double; end;
  TSyncProgress = reference to procedure(Done, Total: Integer);
  TSearchIndexer = class
    constructor Create(const Source: ISearchDocumentSource; Store: TSearchIndexStore; const Embedder: ITextEmbedder);
    function Sync(const Cancelled: TCancelCheck = nil; const Progress: TSyncProgress = nil): TSyncStats;
  end;
const
  SyncEmbedBatch = 32;
```
  Algorithm: read passages and catalog; keys absent from source → `Delete`; same hash but other ProjectId/ItemId/FileId → `UpdateCoordinates`; new or changed hash → embed in batches of `SyncEmbedBatch` with `olTruncate` (count `Truncated`), each batch in its own `BeginBatch/CommitBatch`. Deletes and moves run in one batch before embedding. `EOperationCancelled` propagates after rolling back the open batch.

Test double `TFakeEmbedder` (in the test unit): identity `'fake-1'`, dimension 8, vector from a hash of the text, L2-normalized; counts passages it encoded.

- [ ] **Step 1: Write failing tests** (notebook fixture from Task 2): `FirstSyncAddsAll` (Added = passage count, fake count = same); `SecondSyncEmbedsNothing` (Unchanged = all, fake count 0); `EditedDescriptionReembedsOnlyIt` (change I1 description chunk 1 → Changed = 1); `TagAssignWithoutAuditIsSeen` (assign tag via `TTagModel` → `item:I1:tags#0` changed); `RecycledItemRemoved` (move I1 to bin → all I1 keys removed); `ProjectMoveUpdatesScope` (move item to project P2 → Moved > 0, fake count 0, `LoadVectors` scope `'P2'`); `CancelMidSyncThenResume` (cancel after first batch of 70 passages → exception, store holds exactly 32 new keys; next sync adds the rest, total = 70, no duplicates); `IdentityChangeRebuilds` (reopen store with `'fake-2'` → next sync Added = all).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** (after approval).

### Task 5: Hybrid searcher with access filter

**Files:**
- Create: `ELN.Search/unit_HybridSearch.pas`
- Modify: `test_SearchIndex.pas` (fixtures `THybridSearchTests` with fake embedder, `TRealModelSearchTests` with `TE5TextEmbedder`), `SearchIndexTests.dpr`

**Interfaces:**
- Consumes: Tasks 3-4; `ISearchDocumentSource.IsItemLive`.
- Produces:
```pascal
type
  TSearchHitSource = (hsVector, hsWords, hsTrigram);
  THybridHit = record
    Key: string; ItemId, ProjectId: Integer; FileId: Int64; Field: TPassageField;
    Score: Double;                     // RRF sum
    Sources: set of TSearchHitSource;
    Snippet: string;                   // first 200 chars of passage text
  end;
  THybridSearcher = class
    constructor Create(Store: TSearchIndexStore; const Embedder: ITextEmbedder;
      const Source: ISearchDocumentSource);
    procedure Reload;                  // after Sync
    function Search(const Query: string; const VisibleProjectIds: TArray<Integer>;
      TopK: Integer): TArray<THybridHit>;
  end;
const
  RrfK = 60;
  CandidatesPerList = 50;
```
  The caller passes `VisibleProjectIds` from `IProjectAccessPolicy.VisibleProjectIds` (owner frees the dictionary). Each list contributes `1 / (RrfK + rank)` (rank from 1). Order: score desc, then Key asc. Revalidation: drop a hit when `IsItemLive` is False or its live ProjectId is not in `VisibleProjectIds`. Query shorter than 2 chars after trim → empty result. Trigram list runs only for queries of ≥ 3 chars.

- [ ] **Step 1: Write failing tests.** `THybridSearchTests`: `OtherOwnerProjectNeverReturned` (second principal's project written directly through the manager in the same file; query matching only its text by word, trigram and vector → 0 hits); `EmptyVisibleSetGivesNothing`; `StaleHitDroppedBeforeSync` (index, then recycle I1, search without sync → no I1 hit); `MovedToInvisibleProjectDropped`; `FusionOrdersAndTiesByKey` (store with controlled ranks → expected order, `Sources` sets match); `ShortQueryEmpty` (`'a'`, `' '`). `TRealModelSearchTests` (needs artifacts, fails with the path when missing, as stage 1): `IdentifierFoundByTrigram` (`'SMP-2024-017'` → first hit's Sources contains `hsTrigram`, and the hit is the item whose title holds that id, ahead of `SMP-2024-031`); `CrossLingualFindsProtocolForm` (Russian query `'подложка кремниевая пластина'` → the protocol form passage in top 3).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** (after approval).

### Task 6: Harness notebook mode and documentation

**Files:**
- Modify: `ELN.Community.Tests/SearchHarness.dpr` (new options `--notebook <db> [--storage <dir>] [--query <text>]`)
- Create: `docs/search-index-stage-2.md`
- Modify: `docs/search-embedding-foundation.md` (Next steps: mark 1-5 done, link new doc, record the no-cursor decision), `README.md:47-48,76` (new target `SearchIndexTests`)

**Interfaces:**
- Consumes: Tasks 2-5. The harness opens the notebook with `TLocalNotebook.Open` (never `CreateNew`/`Upgrade`) and works on the path given; the docs tell the user to pass a **copy** of a real notebook.

- [ ] **Step 1: Implement** the mode: print passage count by field, first-sync time and passages/s, second-sync time (must report 0 embedded), store file size, private memory after sync, and for `--query` the top 10 hits with score, Sources, ItemId, Field and snippet, plus median of 20 warm query latencies.
- [ ] **Step 2: Run on the synthetic fixture.**
  Run: `pwsh tools/build-community.ps1 -Target SearchHarness -Configuration Release` then `_OUT\SearchHarness\Win64\Release\SearchHarness.exe --notebook <fixture copy> --query "Mo/Si"`.
  Expected: second sync "embedded 0"; hits printed; exit 0.
- [ ] **Step 3: Owner measurement** on a copy of a real notebook (spec item 5). Record numbers in `docs/search-index-stage-2.md`: passages, first sync time, store size, memory, warm query median. Decide there whether exact search is enough (criterion: warm query median < 100 ms and memory growth < 200 MB) or an approximate index is needed in stage 3.
- [ ] **Step 4: Write `docs/search-index-stage-2.md`** (ASD-STE100): repository map, store schema, reconcile algorithm and why no audit cursor (with the evidence list above), access model, RRF constants, measurements, limitations (no viewer text, no audit, single-threaded per embedder, whole-notebook read per sync).
- [ ] **Step 5: Full verification.**
  Run: `pwsh tools/build-community.ps1 -Target SearchIndexTests -RunTests`, `-Target SearchTests -RunTests`, `-Target NotebookTests -RunTests`, then `-Platform Win32` for `SearchIndexTests`.
  Expected: all PASS.
- [ ] **Step 6: Commit** (after approval).

## Stage 3 (not in this plan)

Desktop entry in `dlg_Search` with background sync (`frame_FileSystemBrowser` pattern), `search_semantic` MCP tool (`tscProjectScoped`, revalidate with `IsProjectVisible`), viewer text through `TPluginHost` behind `ISearchDocumentSource`, installer payload (`onnxruntime.dll`, providers DLL, model, notices, FTS5-capable `sqlite3.dll` beside the executable), optional audit rows for the unaudited paths if sync time on real notebooks requires a cursor.
