# Semantic Search Stage 3: Hosts, Model Download and Win64 Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make stage 2 hybrid search usable: an optional in-app model download, background indexing and a "meaning" mode in the Desktop search dialog, a `search_semantic` MCP tool, and a Win64 installer.

**Architecture:** A shared JSON manifest describes the external artifacts; a Delphi verifier and downloader install them into the per-user artifact folder. A `TSemanticSearchService` in `ELN.Search` owns the store, a lazily loaded embedder, the indexer and the searcher, and serializes all use with one lock. Hosts read passages on their own thread (the ORM is not thread-safe) and hand a snapshot to the service: the Desktop embeds on a worker thread, MCP syncs inline under a time budget. Resumable sync (stage 2) makes both partial runs safe.

**Tech Stack:** Delphi 13 Win64, VCL, `System.Net.HttpClient` (`THTTPClient`, system proxy), `System.Zip`, `System.Hash`, stage 2 units, DUnitX, Inno Setup, PowerShell 7.

**Spec:** `docs/search-index-stage-2.md` ("Limitations", decision criterion) and `docs/search-embedding-foundation.md` ("Next steps" items 6-7). Owner decisions of 2026-10-28: model is an **optional in-app download**; the installer **moves to Win64**; viewer-extracted text is **stage 4**.

## Global Constraints

- Search is Win64 only. Do not build or run search targets for Win32. After Task 8 the installer is Win64 only.
- The model and ONNX Runtime are never bundled in the installer or committed. They come from the URLs and SHA-256 values in the manifest into `%LOCALAPPDATA%\APS-ELN\search-artifacts` (override: environment variable `ELN_SEARCH_ARTIFACTS`), the same root as `TE5EmbedderConfig.DefaultArtifactRoot`.
- A file is used only after its size and SHA-256 match the manifest. A partial or wrong file is never left under its final name.
- Hosts never write to the notebook for search. Store path stays `ChangeFileExt(DatabasePath, '') + '.search.sqlite'`.
- `TObjectManager` is used only on the thread that owns it. Worker threads touch only the service (store, embedder), never the ORM or VCL controls.
- Keyword search (`TSearchModel`, MCP `search`) keeps working unchanged without the artifacts.
- `ELN.Search` units stay free of Aurelius entities, `ELN.Model`, VCL and plugin units.
- Commercial: do not edit its `Community/` pin. Shared `ELN.MCPServer` changes must leave Commercial behavior unchanged when the new context field is nil.
- Comments denied by default; CRLF + UTF-8 BOM for `.pas`/`.dpr`/`.dfm`; docs and Help in ASD-STE100; paired `.pas`/`.dfm`, controls in DFM.
- Commits: local commits per task on a feature branch; no push without the user's approval.

## Review Focus

1. **Notebook closed, switched or app closed while a sync runs** — no access violation, the worker stops within one embed batch, the store closes, and the next notebook gets its own service. Tests in Task 4; manual check in Task 5.
2. **Desktop and MCP sync the same store at the same time** (two processes, WAL) — no `SQLITE_BUSY` error to the user inside the busy timeout, no duplicate or lost passages. Test in Task 3.
3. **Interrupted, corrupt or proxy-blocked download** — status stays "not installed", no file under its final name with wrong bytes, a retry completes. Tests in Task 2.
4. **Pasted long text as query (> 512 tokens)** — results from the word and trigram lists, no error. Test in Task 3.
5. **Scoped MCP session** (`ScopedProjects` non-empty) — no hit outside the scope; `project_id` outside the scope is refused. Test in Task 7.

---

### Task 1: Shared artifact manifest and verifier

**Files:**
- Create: `ELN.Search/search-artifacts.json` (content of `tools/search-artifacts.psd1`, same keys, plus `"ManifestVersion": 1`)
- Delete: `tools/search-artifacts.psd1`
- Modify: `tools/Get-SearchArtifacts.ps1` (read the JSON with `ConvertFrom-Json`; behavior unchanged)
- Create: `ELN.Search/unit_SearchArtifacts.pas`
- Create: `ELN.Community.Tests/test_SearchArtifacts.pas`; Modify: `SearchIndexTests.dpr`, `CommunityStorageTests.dproj`

**Interfaces:**
- Produces:
```pascal
type
  ESearchArtifactError = class(Exception);
  TArtifactFile = record
    RelativePath: string;      // under the artifact root, '\' separators
    Size: Int64;
    Sha256: string;            // uppercase hex
  end;
  TArtifactArchive = record Url, Name: string; Size: Int64; Sha256: string; end;
  TSearchArtifactManifest = record
    ModelFolder, ModelBaseUrl, RuntimeFolder: string;
    ModelFiles, RuntimeFiles: TArray<TArtifactFile>;   // RelativePath includes folder
    RuntimeArchive: TArtifactArchive;
    TotalDownloadBytes: Int64;                           // model files + archive
    class function LoadFromFile(const Path: string): TSearchArtifactManifest; static;
    class function DefaultPath: string; static;          // ExtractFilePath(ParamStr(0)) + 'search-artifacts.json'
  end;
  TArtifactState = (asReady, asMissing, asWrongSize, asWrongHash);
  TArtifactCheck = record State: TArtifactState; FirstProblem: string; end;
function CheckSearchArtifacts(const Manifest: TSearchArtifactManifest; const Root: string;
  VerifyHashes: Boolean): TArtifactCheck;
function SearchArtifactRoot: string;   // ELN_SEARCH_ARTIFACTS or TE5EmbedderConfig.DefaultArtifactRoot
```
  Runtime file paths in the manifest are inside the zip (`onnxruntime-win-x64-1.31.1\lib\onnxruntime.dll`); the installed path is `<RuntimeFolder>\<file name>` exactly as `Get-SearchArtifacts.ps1` writes them today — read the script and keep the same layout.

- [ ] **Step 1: Failing tests** (`TSearchArtifactTests`, fixture folder built in a temp dir with small fake files and a test manifest written by the test): `LoadsRepositoryManifest` (loads `ELN.Search/search-artifacts.json`: 6 model files, `model.onnx` size 470268510, runtime archive size 82929944, `TotalDownloadBytes` = sum); `ReadyWhenAllMatch`; `MissingFileReported` (`FirstProblem` names the file); `WrongSizeReported`; `WrongHashOnlyWhenVerifying` (same size, other bytes: `VerifyHashes=False` → `asReady`, `True` → `asWrongHash`); `RejectsMalformedManifest` (missing key / negative size / non-hex hash → `ESearchArtifactError`); `EnvOverridesRoot`.
- [ ] **Step 2:** `pwsh -NoProfile -File tools/build-community.ps1 -Target SearchIndexTests -Platform Win64 -RunTests` → FAIL (unit missing).
- [ ] **Step 3:** Implement. Hashing with `THashSHA2.GetHashStringFromStream` over a buffered file stream.
- [ ] **Step 4:** Same command → PASS. Also `pwsh -NoProfile -File tools/Get-SearchArtifacts.ps1 -VerifyOnly` → reports all artifacts verified on this workstation.
- [ ] **Step 5:** Commit.

### Task 2: Artifact installer (download, verify, extract)

**Files:**
- Create: `ELN.Search/unit_SearchArtifactInstall.pas`
- Modify: `test_SearchArtifacts.pas`

**Interfaces:**
- Consumes: Task 1.
- Produces:
```pascal
type
  IArtifactFetcher = interface
    procedure Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck);   // writes bytes to TargetPath, raises on HTTP error
  end;
  THttpArtifactFetcher = class(TInterfacedObject, IArtifactFetcher);  // THTTPClient, system proxy, follows redirects
  TInstallProgress = reference to procedure(DoneBytes, TotalBytes: Int64; const CurrentFile: string);
procedure InstallSearchArtifacts(const Manifest: TSearchArtifactManifest; const Root: string;
  const Fetcher: IArtifactFetcher; const Progress: TInstallProgress; const Cancelled: TCancelCheck);
```
  Per file: skip if already size+hash valid; else fetch to `<final>.part`, check size and SHA-256, then `TFile.Move` over the final name (delete old first). Runtime: fetch the archive to `<Root>\<RuntimeFolder>\<archive>.part`, verify, extract only the manifest's runtime files with `TZipFile` to `.part` names, verify each, rename, delete the archive. On any error or cancel: delete every `.part`, re-raise (`EOperationCancelled` for cancel). End with `CheckSearchArtifacts(..., True)`; raise `ESearchArtifactError` unless `asReady`.

- [ ] **Step 1: Failing tests** with `TFolderFetcher` (test double copying from a fixture folder by URL file name; optional "corrupt", "fail after N bytes" and "count calls" modes) and a small test zip built in the test: `InstallsAllAndReportsReady`; `SecondRunFetchesNothing` (call count 0); `CorruptDownloadLeavesNoFinalFile` (final name absent, no `.part`, `ESearchArtifactError` naming the file); `FailureMidwayThenRetryCompletes`; `CancelLeavesNoPartFiles` (`EOperationCancelled`); `ExtractsOnlyListedRuntimeFiles` (an extra zip entry is not written); `ProgressReachesTotal` (last `DoneBytes` = `TotalDownloadBytes` of the test manifest).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS. Manual check of `THttpArtifactFetcher` (not a unit test, network): a throwaway console program or harness option downloads `config.json` only into a temp root and its hash matches; delete the throwaway afterwards and record the output in the report.
- [ ] **Step 5:** Commit.

### Task 3: Store busy timeout, long queries, passage snapshot

**Files:**
- Modify: `ELN.Search/unit_SearchIndexStore.pas` (`PRAGMA busy_timeout = 10000` after open)
- Modify: `ELN.Search/unit_HybridSearch.pas` (on `ETextTooLong` from `EncodeQuery`: no vector list, the word and trigram lists still run)
- Modify: `ELN.Search/unit_SearchPassages.pas` (add `TPassageSnapshotSource`)
- Modify: `test_SearchIndex.pas`

**Interfaces:**
- Produces:
```pascal
type
  TPassageSnapshotSource = class(TInterfacedObject, ISearchDocumentSource)
    constructor Create(const Passages: TSearchPassages);   // ReadPassages returns them; IsItemLive raises ENotSupportedException
  end;
const
  StoreBusyTimeoutMs = 10000;
```

- [ ] **Step 1: Failing tests:** `LongQueryUsesTextLists` (fake embedder raising `ETextTooLong` for queries over 100 chars; a 2000-char query containing an indexed word → hit with `Sources = [hsWords]`, no exception); `TwoStoresSyncSameFile` (two `TSearchIndexStore` instances on one path, each in its own `TThread`, each runs `TSearchIndexer.Sync` with the fake embedder over the same 70 passages → both finish without exception; catalog has exactly 70 keys; `SELECT COUNT(*) FROM passages` = 70); `SnapshotSourceFeedsIndexer` (sync from a snapshot equals sync from the provider: same catalog keys and hashes).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit.

### Task 4: Semantic search service

**Files:**
- Create: `ELN.Search/unit_SemanticSearchService.pas`
- Create: `ELN.Community.Tests/test_SemanticSearchService.pas`; Modify: `SearchIndexTests.dpr`, `CommunityStorageTests.dproj`

**Interfaces:**
- Consumes: Tasks 1-3, `TSearchIndexStore`, `TSearchIndexer`, `THybridSearcher`, `ITextEmbedder`.
- Produces:
```pascal
type
  ESemanticSearchUnavailable = class(Exception);
  TEmbedderFactory = reference to function: ITextEmbedder;
  TServiceState = (ssIdle, ssSyncing, ssFailed);
  TServiceStatus = record
    State: TServiceState;
    IndexedPassages: Integer;
    PendingPassages: Integer;      // from the last sync that did not finish
    LastError: string;
    LastSync: TSyncStats;
  end;
  TSyncOutcome = record Stats: TSyncStats; Complete: Boolean; end;
  TSemanticSearchService = class
    constructor Create(const StorePath: string; const EmbedderFactory: TEmbedderFactory;
      const LiveSource: ISearchDocumentSource);           // LiveSource used only for IsItemLive, on the caller's thread
    destructor Destroy; override;                         // cancels and waits for the worker
    procedure StartSync(const Passages: TSearchPassages; const OnProgress: TSyncProgress;
      const OnDone: TProc<TServiceStatus>);              // worker thread; callbacks via TThread.Queue; ignored while ssSyncing
    function SyncNow(const Passages: TSearchPassages; DeadlineMs: Cardinal): TSyncOutcome; // caller thread; stops at the batch after the deadline
    procedure CancelSync;
    function Search(const Query: string; const VisibleProjectIds: TArray<Integer>; TopK: Integer): TArray<THybridHit>;
    function Status: TServiceStatus;
  end;
```
  The embedder and store open on first `StartSync`, `SyncNow` or `Search` (the factory runs once; its exception becomes `ESemanticSearchUnavailable` with the message, and `Status.State = ssFailed`). One `TCriticalSection` guards store, embedder, indexer and searcher; the worker takes it per embed batch (the indexer's `Cancelled` callback is where the worker releases and re-takes it) so `Search` waits at most one batch. After a sync the searcher reloads under the lock. `Search` during a sync uses the index as it is.

- [ ] **Step 1: Failing tests** (fake embedder from `test_SearchIndex.pas`, extended with an optional per-batch delay): `SearchWhileSyncing` (start sync of 200 passages with 20 ms/batch delay, run 10 searches meanwhile → no exception, each returns ≤ TopK hits, max search wait < 500 ms); `DestroyDuringSyncStopsWorker` (free the service 50 ms after `StartSync` → returns within 1 s, no leak reported by FastMM, store file reopens cleanly); `SecondStartSyncIgnoredWhileRunning`; `OnDoneQueuedOnMainThread` (callback runs inside `CheckSynchronize` loop, `TThread.CurrentThread.ThreadID = MainThreadID`); `SyncNowRespectsDeadline` (deadline 50 ms with 20 ms/batch over 200 passages → `Complete = False`, `PendingPassages > 0`; next `SyncNow` with large deadline → `Complete = True`); `FactoryFailureMakesUnavailable` (factory raises → `Search` raises `ESemanticSearchUnavailable`, `Status.State = ssFailed`, `LastError` = factory message).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS, with FastMM leak report clean.
- [ ] **Step 5:** Commit.

### Task 5: Desktop lifecycle and "Semantic Search Setup" dialog

**Files:**
- Create: `ELN.Desktop/Dialogs/Search/dlg_SearchSetup.pas` + `.dfm`
- Modify: `ELN.Community.Desktop/frm_CommunityMain.pas` + `.dfm` (menu item, `FSemanticSearch: TSemanticSearchService` field; create in `BindNotebook` (lines ~435-479) when artifacts are `asReady` by size check; free in `ReleaseNotebook` (lines ~526-544) before `FreeAndNil(Model)`; start a sync after bind)
- Modify: `ELN.Community.Desktop/ELNCommunity.dproj` (add `..\ELN.Search` to the unit search path and `DCCReference`s for the stage 2/3 search units and `unit_SearchDocumentProvider`)

**Interfaces:**
- Consumes: Tasks 1, 2, 4; `TNotebookDocumentProvider.Create(Model.Manager, Model.Storage)` read on the UI thread for the snapshot; `TE5TextEmbedder.Create(TE5EmbedderConfig.FromArtifactRoot(SearchArtifactRoot))` as factory.
- Produces: `TfrmCommunityMain.SemanticSearch: TSemanticSearchService` (nil when not installed or no notebook) and `procedure TfrmCommunityMain.RefreshSemanticIndex;` (reads the snapshot on the UI thread, calls `StartSync`; no-op when nil or syncing).

Dialog `TdlgSearchSetup` (modal, opened by **Tools → Semantic Search Setup...**): shows state (Not installed / Installed / Checking), download size from `TotalDownloadBytes` in MB, target folder, model license line ("intfloat/multilingual-e5-small, MIT; ONNX Runtime 1.31.1, MIT"); buttons **Download and Install**, **Verify**, **Remove**, **Cancel**/**Close**; a progress bar and current-file label. Install runs on a worker thread (pattern of `frame_FileSystemBrowser.pas:162-196`: request object with lock, `TThread.Queue`, cancel flag); closing the dialog cancels and waits. After success the main form creates the service and starts a sync. **Remove** first frees the service, then deletes the artifact folder.

- [ ] **Step 1:** Implement the dialog and main form wiring. No permanent unit test (UI); the service behavior is covered by Task 4.
- [ ] **Step 2:** Build: `pwsh -NoProfile -File tools/build-community.ps1 -Target CommunityDesktop -Platform Win64` → 0 errors, 0 new warnings.
- [ ] **Step 3: Smoke run** on a synthetic notebook (create with `TLocalNotebook.CreateNew` through the Desktop **File → New Notebook**, add 3 items): with artifacts present, open the notebook → status bar or dialog shows indexed passages; **Remove** then **Download and Install** with the real network (or `ELN_SEARCH_ARTIFACTS` pointed to a temp folder) → completes and verifies; cancel a download midway → no `.part` files remain; switch notebook during a sync and close the app during a sync → no error dialog, process exits. Record screenshots or observed text in the report.
- [ ] **Step 4:** Commit.

### Task 6: Desktop search dialog "Meaning" mode

**Files:**
- Modify: `ELN.Desktop/Dialogs/Search/dlg_Search.pas` + `.dfm`
- Modify: `ELN.Community.Desktop/frm_CommunityMain.pas` (pass the service and visible project IDs to `TdlgSearch.Execute`; call `RefreshSemanticIndex` when the dialog opens)

**Interfaces:**
- Consumes: Task 5 `SemanticSearch`, `RefreshSemanticIndex`; `Model.Access.VisibleProjectIds(Model.Manager, Model.User)` (caller frees).
- Produces: `class procedure TdlgSearch.Execute(NavigateProc; const Semantic: TSemanticSearchService; const VisibleProjectIds: TArray<Integer>)`; Semantic may be nil.

Behavior: checkbox **Search by meaning** (`chkMeaning`) under the edit box; enabled only when `Semantic` is not nil; state saved with `SaveUIValue('Search', 'ByMeaning', 0|1)`. When checked, **Search** calls `Semantic.Search(edSearch.Text, VisibleProjectIds, 50)` and fills the same `ListView`: ID = `ItemId`; Type = field name ("Title", "Description", "Properties", "Tags", "Entry title", "Protocol form", "Value description", "File name", "File text"); Name = item title (read on the UI thread for the hit's `ItemId`); Location = project path (existing `BuildProjectPath` logic, reuse — do not copy); Matched In = snippet. A label under the list shows the index status ("Indexed 1234 passages" / "Indexing… 40 %" / "Semantic search is not installed — Tools → Semantic Search Setup"). Unchecked: unchanged keyword path. **Go to Item** works for both.

- [ ] **Step 1:** Implement. If `BuildProjectPath` is private in `TSearchModel`, expose it as a public class or helper function used by both (no copy).
- [ ] **Step 2:** Build `CommunityDesktop` Win64 → 0 errors; run `DesktopRegressionTests` and `NotebookTests` → PASS (dialog and search model regressions).
- [ ] **Step 3: Smoke run:** synthetic notebook with an item described "film delaminates after storage in humid air"; query "coating peels off in moisture" by meaning → that item in the top 3; same query unchecked → keyword results (likely none), no error; pasted 3000-character query by meaning → results, no error; double-click navigates. Record observations.
- [ ] **Step 4:** Commit.

### Task 7: MCP `search_semantic` tool

**Files:**
- Modify: `ELN.MCPServer/unit_MCPTools.pas` (`TToolContext.SemanticSearch: TSemanticSearchService`, nil by default)
- Modify: `ELN.MCPServer/unit_ToolsNavigation.pas` (handler + registration next to `HandleSearch`, lines ~562-611)
- Modify: `ELN.Community.MCP/unit_CommunityMCPHost.pas` (create the service when artifacts are `asReady`, set the field at lines ~128-136, free on exit)
- Modify: the MCP test unit that covers navigation tools (find it with the existing `search` tool tests) or create `ELN.Community.Tests/test_SemanticSearchTool.pas` in the same target as those tests

**Interfaces:**
- Consumes: Task 4 `SyncNow`, `Search`; `unit_ToolScope.pas` `IsScopeActive`, `IsProjectVisible`, `RequireProjectRead`.
- Produces: tool `search_semantic`, scoping `tscProjectScoped`. Arguments: `query` (string, required), `top_k` (integer 1-50, default 10), `project_id` (integer, optional; `RequireProjectRead` first). Before searching: `SyncNow(snapshot, 20000)` with the snapshot read from `Context.Manager` on the request thread. Result JSON:
```json
{"hits":[{"item_id":0,"project_id":0,"file_id":0,"field":"description","score":0.0,"sources":["vector","words"],"snippet":""}],
 "index":{"complete":true,"indexed_passages":0,"pending_passages":0}}
```
  Visible IDs = `AccessPolicy.VisibleProjectIds` ∩ `ScopedProjects` (when active) ∩ `[project_id]` (when given); every hit passes `IsProjectVisible`. Field names are lowercase snake case of the Desktop names. When `SemanticSearch` is nil: tool error `semantic_search_unavailable` with the text "Semantic search is not installed. Install it in ELN Community: Tools > Semantic Search Setup. Use the search tool for keyword search."

- [ ] **Step 1: Failing tests** (fake embedder service injected into a test `TToolContext`): `ReturnsHitsWithIndexStatus`; `ScopedSessionNeverLeaks` (scope = P1; text matching only P2 → no P2 hit; `project_id` = P2 → out-of-scope error); `UnavailableWhenNoService`; `IncompleteIndexReported` (fake embedder 20 ms/batch, deadline forced small via a test seam on the handler constant → `"complete": false`, second call completes); `ListedInToolsList` (`tools/list` contains `search_semantic` with the schema).
- [ ] **Step 2:** Run the owning test target → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS; build `CommunityMCP` Win64; smoke: run `ELNCommunityMCP.exe` on a synthetic notebook, send `tools/call search_semantic` over stdio, observe hits and `"complete": true` on the second call.
- [ ] **Step 5:** Commit.

### Task 8: Win64 installer

**Files:**
- Modify: `Installer/Stage-Runtime.ps1` (`ValidateSet('Win64')`, default `Win64`; Delphi runtime BPLs from `bin64` (sibling of the `bin` that holds `rsvars.bat`); stage `ELN.Search/search-artifacts.json` to `Program/search-artifacts.json`)
- Modify: `tools/build-installer.ps1` (`ValidateSet('Win64')`, default `Win64`)
- Modify: `Installer/ELNCommunitySetup.iss` (`ArchitecturesAllowed=x64compatible`, `ArchitecturesInstallIn64BitMode=x64compatible`, `OutputDir=..\_OUT\Installer\Win64\Release\Output`)
- Modify: `Installer/Test-StageRuntime.ps1` (fixtures and expectations for Win64 and the manifest)
- Modify: `installer-runtime` example/README config notes: `SQLiteRuntime` and `RuntimeBplRoot` must be the Win64 files
- Modify: `THIRD-PARTY-NOTICES.md` (section "Optional downloaded components": ONNX Runtime 1.31.1, MIT, its `LICENSE` and `ThirdPartyNotices.txt` are downloaded beside it; intfloat/multilingual-e5-small revision `614241f6…`, MIT)

- [ ] **Step 1:** Update `Test-StageRuntime.ps1` first (expects Win64 paths and `Program/search-artifacts.json`) → run `pwsh -NoProfile -File Installer/Test-StageRuntime.ps1` → FAIL.
- [ ] **Step 2:** Implement the script, `.iss` and notices changes.
- [ ] **Step 3:** `Test-StageRuntime.ps1` → PASS.
- [ ] **Step 4:** `pwsh -NoProfile -File tools/build-installer.ps1` → setup exe in `_OUT/Installer/Win64/Release/Output`. Probe the staged DLL: `SearchHarness.exe --fts5 --sqlite <stage>\Program\sqlite3.dll` → `ENABLE_FTS5 = 1`.
- [ ] **Step 5: Smoke:** install into a temp `{localappdata}` path on this machine (`/DIR=` silent install), start the app, open **Tools → Semantic Search Setup...** → shows "Not installed" or "Installed" consistent with the artifact folder; uninstall. Record output.
- [ ] **Step 6:** Commit.

### Task 9: Documentation and Help

**Files:**
- Create: `docs/search-stage-3.md` (service and threading model, download and verification, Desktop flow, MCP tool contract, installer change, Win32 removal, limitations: no viewer text (stage 4), first sync time unknown until the owner measurement, memory ≈ 1 GB per process that loads the model (Desktop and MCP each))
- Modify: `docs/search-index-stage-2.md` (Limitations: long-query and Win32 items now point to stage 3 behavior), `docs/search-embedding-foundation.md` (Next steps 6-7 done; 8 = viewer text, stage 4)
- Modify: `ELN.Desktop/Assets/Runtime/Help/Search.html` (new section "Search by meaning": setup, what it covers, that it is local and offline after download, that results are ranked and always show something), `MCP.html` (tool count +1, `search_semantic` paragraph), `Troubleshooting.html` (rows: download fails behind a proxy; "Semantic search is not installed"), `README.md` (Win64 installer, search artifacts)

- [ ] **Step 1:** Write the docs and Help pages.
- [ ] **Step 2:** Rebuild the Help index through the Desktop build (`tools/Build-HelpIndex.ps1` runs during staging) and open **Help → Contents**, search "meaning" → finds the new section.
- [ ] **Step 3:** Full verification: `SearchIndexTests`, `SearchTests`, `NotebookTests`, `DesktopRegressionTests`, the MCP test target from Task 7, all Win64 → PASS.
- [ ] **Step 4:** Commit.

## Open item outside this plan

The real-notebook measurement of stage 2 is still pending. If it fails the decision criterion (warm query ≥ 100 ms or memory growth ≥ 200 MB), an approximate index becomes its own stage before release.
