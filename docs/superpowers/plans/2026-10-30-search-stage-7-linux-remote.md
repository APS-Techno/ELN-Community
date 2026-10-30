# Semantic Search Stage 7: Linux64 Search Core and Remote Search Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the search core (`ELN.Search`, the provider and the filter in `ELN.Model`) build and pass its tests on Linux64, and let hosts use semantic search through one interface that has a local implementation and an HTTP client implementation, so a host can query a search server instead of a local index.

**Architecture:** Platform loaders move behind one small unit with a Windows and a POSIX branch; artifact paths and the manifest become per-platform. A new interface `ISemanticSearch` covers what the Desktop dialog and the MCP tool use today; `TSemanticSearchService` implements it, and `TRemoteSemanticSearch` implements it over HTTPS with a bearer token supplied by the host. The live access check gets a per-search source so a multi-threaded server can give each request its own database session. The server and its authentication are not part of this repository.

**Tech Stack:** Delphi 13 (Win64 and Linux64), ONNX Runtime 1.31.1, PDFium chromium/8125, SQLite with FTS5/trigram/JSON, TMS Aurelius, DUnitX, `System.Net.HttpClient`.

**Spec:** Stage docs `docs/search-stage-3.md` to `docs/search-stage-6.md`. Research notes: `local://stage7-scout-linux.md`, `local://stage7-scout-clients.md` (session artifacts; facts copied here where needed).

## Global Constraints

- All stage 5 and 6 constraints stay: no score is a probability; no relevance threshold; access gate = visible projects plus the live check; filters never widen access; `ELN.Search` free of Aurelius entities, `ELN.Model`, VCL and plugin units; notebook never written; synthetic data only.
- Windows behaviour and results do not change: every existing Win64 suite stays green, and `SearchHarness --eval` on `eval-dev.json` gives the same per-query output as before (`--compare`).
- One loader convention: `{$IFDEF MSWINDOWS}` / `{$IFDEF POSIX}` branches inside one platform unit. No `Winapi.*` or `Posix.*` use outside it in `ELN.Search`.
- Paths: `TPath.Combine` and `PathDelim`; manifest file names use `/` and are normalised on load.
- The remote client carries no credential logic: the host supplies the base URL, a token callback and an optional certificate pin.
- Comments denied by default; CRLF + UTF-8 BOM for new `.pas`/`.dpr`; keep the encoding of edited files; docs and Help in ASD-STE100.
- Feature branch `search-stage-7`; local commits per task; no push without the owner.
- Installing the Delphi Linux64 platform, the TMS Linux64 packages and a WSL Ubuntu 22.04 distribution on this PC is authorized by the owner (2026-10-30). Nothing else is installed globally.

## Review Focus

1. **Admin sees nothing or crashes** - an access policy that returns `nil` ("all projects") must give all projects, not an access violation or an empty result. Test in Task 1.
2. **Wrong library loaded on Linux** - a missing or wrong-architecture `.so` gives a clear "not installed" error, never a crash. Test in Task 3.
3. **Remote server down or slow** - the client returns a clear error within its timeout; the Desktop and MCP do not hang. Test in Task 6.
4. **Remote result widens access** - the client never adds or keeps a group for a project outside the caller's visible set, even if a faulty server returns one. Test in Task 6.
5. **Cross-thread database session** - on a multi-threaded server, a live check never uses another thread's session. Test in Task 5.

---

### Task 1: "All projects" from the access policy

**Files:**
- Create: `ELN.Model/unit_SearchVisibility.pas`
- Modify: `ELN.MCPServer/unit_ToolsNavigation.pas` (`SemanticVisibleIds`), `ELN.Community.Desktop/frm_CommunityMain.pas` (visible ids for the Search dialog)
- Test: `ELN.Community.Tests/test_SemanticSearchTool.pas`, a new case in the suite that holds `test_SemanticSearchFilter.pas`

**Interfaces:**
- Produces: `function SearchVisibleProjectIds(Manager: TObjectManager; const Policy: IProjectAccessPolicy; User: TUser): TArray<Integer>;` - a `nil` dictionary from the policy means all non-deleted projects (one query); an empty dictionary means none.

- [ ] Step 1: Failing tests: a fake policy that returns `nil` gives every project id to `search_semantic` and to the filter resolver; an empty dictionary gives no group; the existing local policy gives the same result as before.
- [ ] Step 2: Implement and use it in both call sites (no second copy).
- [ ] Step 3: Run `SearchIndexTests`, `DesktopRegressionTests`. Commit.

### Task 2: Linux64 toolchain and a Linux test runner

**Files:**
- Modify: `tools/build-community.ps1` (`-Platform Linux64` for `SearchTests`, `SearchIndexTests`, `SearchHarness` only)
- Create: `tools/run-linux-tests.ps1` (copy an ELF and its `.so` files into the WSL distro and run it; return its exit code)
- Modify: `README.md` (Linux64 prerequisites and commands)

- [ ] Step 1: Install the Delphi 13 Linux64 platform (RAD Studio platform manager), build the TMS BCL and Aurelius Linux64 packages, and install WSL with Ubuntu 22.04. Record versions in the report.
- [ ] Step 2: In WSL, record `sqlite3` version and compile options (`select sqlite_version(); pragma compile_options;`) and `lscpu | grep avx2`. If JSON functions or FTS5 are missing in Ubuntu 22.04's `libsqlite3-0`, stop and report (the server image would then need another SQLite).
- [ ] Step 3: Make the three targets compile for Linux64 with the Task 3 stubs absent (expected to fail on `Winapi`); record the compile errors as the Task 3 work list. Commit the script changes.

### Task 3: Portable native loaders and per-platform artifacts

**Files:**
- Create: `ELN.Search/unit_NativeLibrary.pas`
- Modify: `ELN.Search/unit_OnnxRuntimeApi.pas`, `ELN.Search/unit_PdfiumApi.pas`, `ELN.Search/unit_SearchArtifacts.pas`, `ELN.Search/unit_SearchArtifactInstall.pas`, `ELN.Search/unit_TextEmbedder.pas`, `ELN.Search/unit_SearchIndexStore.pas`
- Create: `ELN.Search/search-artifacts-linux.json`
- Test: `ELN.Community.Tests/test_SearchArtifacts.pas`, `test_SearchEmbedding.pas`

**Interfaces:**
- Produces: `function LoadNativeLibrary(const Path: string): NativeUInt;` `function NativeSymbol(Handle: NativeUInt; const Name: string): Pointer;` `procedure FreeNativeLibrary(Handle: NativeUInt);` `function NativeLoadError: string;` in `unit_NativeLibrary` (Windows: `LoadLibraryEx` with altered search path; POSIX: `dlopen(RTLD_NOW or RTLD_LOCAL)`). ORT model paths go to `CreateSession` as UTF-16 on Windows and UTF-8 on POSIX. `TSearchArtifactManifest.DefaultPath` picks `search-artifacts.json` (Windows) or `search-artifacts-linux.json` (Linux). Default artifact root: `%LOCALAPPDATA%\APS-ELN\search-artifacts` on Windows, `$XDG_DATA_HOME/APS-ELN/search-artifacts` or `~/.local/share/...` on Linux; `ELN_SEARCH_ARTIFACTS` overrides both. On Linux the store sets `SQLiteLibraryName := 'libsqlite3.so.0'` unless `ELN_SQLITE_LIBRARY` is set.
- Linux manifest: same models; archives `onnxruntime-linux-x64-1.31.1.tgz` (11,413,655 B, sha256 `c849e36a1ef3e22d4ff217b9d1ce4a3cf5b9467b975610913ae959ad5b16bdc9`) and `pdfium-linux-x64.tgz` chromium/8125 (3,828,800 B, sha256 `e1c3ce6e270cb5e0c20816b379ad9f2c1309972697c505f508de92bf5e7d6659`); member names, per-file sizes and hashes from `tar -tzf` and extraction (record them; the scout only inferred `lib/libonnxruntime.so.1.31.1` and `lib/libpdfium.so`).

- [ ] Step 1: Failing tests (both platforms): manifest with `/` and `\` names resolves to the same paths; a missing library gives the "not installed" error text, not an exception class from the OS; the Linux manifest parses and its part names match the Windows one except the archives.
- [ ] Step 2: Implement; remove `Winapi.Windows` from both API units.
- [ ] Step 3: Linux: `tools/Get-SearchArtifacts.ps1 -Manifest ELN.Search/search-artifacts-linux.json` (or the program installer) fills an artifact root in WSL; `SearchTests` and `SearchIndexTests` pass on Linux64 through `tools/run-linux-tests.ps1`; `SearchHarness --fts5` passes there. Tests that need Windows-only fixtures are skipped on Linux by an explicit platform guard, and the report lists them.
- [ ] Step 4: Windows: all suites pass; `--eval` dev `--compare` is identical. Commit.

### Task 4: `ISemanticSearch` and the local implementation

**Files:**
- Create: `ELN.Search/unit_SemanticSearchApi.pas`, `ELN.Search/unit_LocalSemanticSearch.pas`
- Modify: `ELN.Model/unit_SemanticSearchFilter.pas` (filter records move to `unit_SemanticSearchApi`; the resolver stays here)
- Modify: `ELN.Search/unit_SemanticSearchService.pas`, `ELN.Desktop/Dialogs/Search/dlg_Search.pas`, `ELN.MCPServer/unit_MCPTools.pas` (`TToolContext.SemanticSearch` type), `ELN.MCPServer/unit_ToolsNavigation.pas`, `ELN.Community.Desktop/frm_CommunityMain.pas`, `ELN.Community.MCP/unit_CommunityMCPHost.pas`
- Test: `test_SemanticSearchService.pas`, `test_SemanticSearchTool.pas`

**Interfaces:**
- Produces in `unit_SemanticSearchApi` (no ELN.Model dependency): `TSemanticSearchStatus` and `TSemanticSearchResult` (moved from the service unit); `TValueConstraint`, `TSemanticSearchFilter`, `TSemanticDateField` (moved from `unit_SemanticSearchFilter`; replace `Nullable<Double>` with `HasMin, HasMax: Boolean; Min, Max: Double` so the unit needs no TMS BCL type); `TSemanticSearchRequest = record Query: string; VisibleProjectIds: TArray<Integer>; TopK: Integer; Filter: TSemanticSearchFilter; Rerank: Boolean; end;` and
  `ISemanticSearch = interface function Search(const Request: TSemanticSearchRequest; const Cancelled: TCancelCheck): TSemanticSearchResult; function Status: TSemanticSearchStatus; function RerankerAvailable: Boolean; function IsRemote: Boolean; end;`
- Produces in `unit_LocalSemanticSearch`: `TLocalSemanticSearch.Create(Service: TSemanticSearchService; const ResolveFilter: TFunc<TSemanticSearchFilter, TArray<Integer>, TItemFilter>)` implementing `ISemanticSearch` (`IsRemote = False`). The host injects the resolver (it wraps `ResolveSemanticFilter` with the host's own manager), so `ELN.Search` stays free of `ELN.Model`. `ESemanticFilterError` keeps its message through the interface.
- The local sync methods (`StartSync`, `SyncNow`) stay on `TSemanticSearchService` only; hosts that sync locally keep the class, consumers (dialog, tool) take the interface. The MCP tool calls `SyncNow` only when the context has a local service; a remote search never triggers a sync.

- [ ] Step 1: Failing tests: the tool and the dialog work with a fake `ISemanticSearch` (results, `reranked`, unavailable error, status line); the tool does not call any sync for a remote fake.
- [ ] Step 2: Implement; clean cutover of all call sites; lifetimes stay host-owned (the interface wrapper does not free the service).
- [ ] Step 3: Run `SearchIndexTests`, `DesktopRegressionTests`; Windows `--eval` dev identical. Commit.

### Task 5: Per-search live source for multi-threaded servers

**Files:**
- Modify: `ELN.Search/unit_SemanticSearchService.pas`, `ELN.Search/unit_HybridSearch.pas`
- Test: `test_SemanticSearchService.pas`

**Interfaces:**
- Produces: `THybridSearchOptions.LiveSource: ISearchDocumentSource` (nil = the service's own source). The service uses it for `IsItemLive` in that one search only. A server passes a source bound to the request's own database session.

- [ ] Step 1: Failing tests: two threads search at the same time, each with its own recording source; each live check lands on the source of its own search; a nil `LiveSource` keeps today's behaviour.
- [ ] Step 2: Implement. Run `SearchIndexTests` (Win64 and Linux64). Commit.

### Task 6: `TRemoteSemanticSearch` (HTTP client) and the JSON contract

**Files:**
- Create: `ELN.Search/unit_RemoteSemanticSearch.pas`, `docs/search-remote-api.md`
- Test: `ELN.Community.Tests/test_RemoteSemanticSearch.pas` (local loopback server in the test with `TIdHTTPServer` or a fake transport interface; no network)

**Interfaces:**
- Contract (in `docs/search-remote-api.md`): `POST {base}/search/semantic` with `Authorization: Bearer <token>`, body `{query, top_k, filters{...same names as the MCP tool...}, rerank}`; response `{groups:[{item_id, project_id, score, sources, passages:[{field, file_id, snippet, score}]}], reranked, index:{complete, indexed_passages, pending_passages, files_pending}, filters_applied}`; `GET {base}/search/status`. Errors as `{code, message}` with HTTP 400/401/403/503. Filters are resolved by the server.
- Produces: `TRemoteSemanticSearch.Create(const BaseUrl: string; const GetToken: TFunc<string>; const CertSha256: string; TimeoutMs: Integer)` implementing `ISemanticSearch` (`IsRemote = True`). TLS: when `CertSha256` is set, the server certificate must match that SHA-256 fingerprint (self-signed LAN servers); otherwise normal validation. A 401 calls `GetToken` once more and retries once.
- The client drops any returned group whose `project_id` is not in `VisibleProjectIds` and records the count in the status.
- The client sends `Request.Filter` as the JSON `filters` object; the server resolves it. `filters_applied` from the server is returned to the caller unchanged.

- [ ] Step 1: Failing tests against a loopback fake server: happy path maps every field; 401 then success refreshes the token once; 503 and timeout give `ESemanticSearchUnavailable` within `TimeoutMs` + 1 s; a wrong pinned fingerprint fails before any body is sent; a group outside the visible set is dropped.
- [ ] Step 2: Implement with `THTTPClient` (portable). Run the tests on Win64 and Linux64. Commit.

### Task 7: Docs, Help and full verification

**Files:**
- Modify: `docs/search-stage-7.md` (new), `README.md`, Help only if a user-visible Community behaviour changed (expected: none)

- [ ] Step 1: Write `docs/search-stage-7.md`: platform layer, Linux artifacts and SQLite facts measured in Task 2, the interface, the remote contract, the live-source rule, Linux test procedure.
- [ ] Step 2: Full Windows verification (`SearchTests`, `SearchIndexTests`, `StorageTests`, `DesktopRegressionTests`, Help checks; build `CommunityDesktop`, `CommunityMCP`) and Linux64 (`SearchTests`, `SearchIndexTests`, `SearchHarness --fts5`, `--eval` dev on Linux equals Windows within 0.005 nDCG@10).
- [ ] Step 3: Final review, then ask the owner before merge and push.

## Out of scope

- The search server, its authentication and deployment (not part of this repository).
- Porting the Community Desktop or the Community MCP host to Linux (plugin host, local notebook storage stay Windows-only).
- New ranking work.
