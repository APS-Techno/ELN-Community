# Semantic search, stage 7: Linux64 search core and remote search interface

Stage 7 has two parts. First, the search core (`ELN.Search`, and the provider and the filter in `ELN.Model`) builds and passes its tests on Linux64. Second, the hosts use semantic search through one interface, `ISemanticSearch`. This interface has a local implementation and an HTTP client implementation. Thus a host can send its searches to a search server and not use a local index. The plan is `docs/superpowers/plans/2026-10-30-search-stage-7-linux-remote.md`.

## Read this first

- This repository has no search server. The server, its authentication and its deployment are not part of this repository. This document gives the contract and the rules that a server must obey.
- On Linux, only the search core and its tests are built. The Community Desktop, the Community MCP host, the plugin host and the local notebook storage stay Windows only.
- Windows behaviour and results do not change. `SearchHarness --eval eval-dev.json --compare` gave the same per-query output before and after each task of this stage.
- All test data is synthetic.

## Changes from the plan

The owner decisions and the controller rulings below change the plan text. Where the plan and this list do not agree, this list is correct.

1. **No certificate pin (owner decision, 2026-10-30).** The plan text at line 19 ("an optional certificate pin"), line 114 (`CertSha256` in the constructor, the pin check) and line 118 ("a wrong pinned fingerprint fails before any body is sent") is superseded. The constructor is `TRemoteSemanticSearch.Create(BaseUrl, GetToken, TimeoutMs)`. The client validates the server certificate against the trust store of the operating system. There is no pin and no mode that accepts all certificates. Reason: `System.Net.HttpClient` does not give the DER bytes of the server certificate on Windows or on Linux, so the client cannot compare a fingerprint.
2. **Local notebook storage and its tests stay Windows only (ruling R6).** `unit_LocalNotebook` and `unit_LocalNotebookStorage` use the Windows file API. On Linux64, `SearchIndexTests.dpr` does not compile the test units that need `TLocalNotebook` (see "Tests that do not run on Linux"). The tests that are evidence for Linux (service, hybrid search, store, artifacts, cross-encoder, remote client) do not use `TLocalNotebook`. `SearchHarness --notebook` is Windows only. On Linux, the provider and the filter resolver get no test coverage in this repository.
3. **Larger API of `ISemanticSearch` (rulings on Task 4).** `TLocalSemanticSearch.Create` has a third argument, `DescribeLimits`. `TSemanticSearchResult` has the fields `IndexStatus` and `FiltersApplied`. Reason: the remote client must return the `index` and `filters_applied` values of the server unchanged, so the result type must have them. The asynchronous search moved from `TSemanticSearchService.StartSearch` to `TSemanticSearchRunner`. `TToolContext` has the new field `SemanticIndex`.
4. **The MCP tool validates a filter before a local sync (ruling on Task 4).** In the local-index branch, the tool resolves a non-empty filter first. An invalid filter gives its error before `SyncNow`, as in stage 6. The remote branch does not resolve the filter locally. A valid filter is resolved two times in a local search (only the filter queries).
5. **`project_ids` in the remote request (Task 6, final review).** The request always has the field `project_ids` (the visible set of the caller). The server must intersect it with the projects of the token user and never add a project. A request without `project_ids` gets 400. For an empty visible set, the client sends no request. `docs/search-remote-api.md` gives the exact validation rules of the server.
6. **WinHTTP timeout watchdog (Task 6).** WinHTTP rounds its own time limits up to steps of approximately 4 s (measured: a silent request stopped after about 4 s for limits of 300 ms to 2000 ms). On Windows, the transport therefore starts a watchdog thread for each request. The watchdog cancels the request at the time limit. On Linux, curl obeys its time limit, and no watchdog is used.
7. **Other API additions (Task 6).** `ESemanticSearchAccessDenied` (401 after the retry, and 403) and `TSemanticSearchStatus.DroppedGroups` (the number of groups that the client removed). A 400 response gives `ESemanticFilterError` with the server message.

## Files

| File | Content |
| --- | --- |
| `ELN.Search/unit_NativeLibrary.pas` | New. The platform layer: load a native library, find a symbol, free the library, the load error text, and `HttpDeadlineNeedsCancel`. |
| `ELN.Search/search-artifacts-linux.json` | New. The Linux manifest of the search artifacts. |
| `ELN.Search/unit_SemanticSearchApi.pas` | New. `ISemanticSearch`, the request, result, status and filter records, the exceptions and `TSemanticSearchRunner`. |
| `ELN.Search/unit_LocalSemanticSearch.pas` | New. `TLocalSemanticSearch`, the local implementation of `ISemanticSearch`. |
| `ELN.Search/unit_RemoteSemanticSearch.pas` | New. `TRemoteSemanticSearch`, the HTTP client implementation of `ISemanticSearch`. |
| `ELN.Model/unit_SearchVisibility.pas` | New. `SearchVisibleProjectIds` ("all projects" from the access policy). |
| `docs/search-remote-api.md` | New. The HTTP contract between the client and a search server. |
| `tools/run-linux-tests.ps1` | New. Runs a Linux64 program in WSL. |
| `tools/build-community.ps1` | `-Platform Linux64` for `SearchTests`, `SearchIndexTests` and `SearchHarness`. |
| `ELN.Community.Tests/unit_SearchTestSupport.pas` | New. Fixture and manifest paths, a portable environment helper. |
| `ELN.Community.Tests/test_SearchStore.pas`, `test_PassageContextBuild.pas` | New. Tests moved out of `test_SearchIndex` and `test_PassageContext`, so they run on Linux. |
| `ELN.Community.Tests/test_RemoteSemanticSearch.pas`, `test_SemanticSearchDialog.pas` | New. Tests of the remote client and of the Search dialog with the interface. |

## Platform layer

`unit_NativeLibrary` is the only unit in `ELN.Search` that uses `Winapi.*` or `Posix.*`. It has one `{$IFDEF MSWINDOWS}` branch and one `{$IFDEF POSIX}` branch.

| Function | Windows | Linux |
| --- | --- | --- |
| `LoadNativeLibrary(Path)` | `LoadLibraryEx` with `LOAD_WITH_ALTERED_SEARCH_PATH` | `dlopen(RTLD_NOW or RTLD_LOCAL)` |
| `NativeSymbol(Handle, Name)` | `GetProcAddress` | `dlsym` |
| `FreeNativeLibrary(Handle)` | `FreeLibrary` | `dlclose` |
| `NativeLoadError` | `SysErrorMessage(GetLastError)` | `dlerror` |
| `HttpDeadlineNeedsCancel` | True (WinHTTP, see "Changes from the plan", item 6) | False (curl) |

The load error text is kept for each thread.

ONNX Runtime and PDFium use this unit. A missing or bad library gives a clear error and never an operating system exception:

- ONNX Runtime file missing: `ONNX Runtime is not installed: <path> is missing`.
- ONNX Runtime file that does not load (wrong format or wrong architecture): `ONNX Runtime is not installed correctly: <path> cannot be loaded (<cause>)`.
- PDFium that does not load: `EPdfiumError` with the path and the cause. The extractor changes it to `PDFium not installed`, as before.

The two ONNX Runtime texts are new in stage 7. Before, they were `ONNX Runtime library not found: <path>` and `Cannot load ONNX Runtime library <path>: <cause>`. Both are `EOnnxRuntimeError`, as before. The Help does not quote them. The Help says that the user must read the cause after `could not start`, and this is still correct. Thus no Help change is necessary.

The model path goes to ONNX Runtime as UTF-16 on Windows and as UTF-8 on Linux. A test loads a model from a folder with Cyrillic and accented characters.

Paths use `TPath.Combine` and `PathDelim`. A manifest file name can have `/` or `\`. The loader changes both to `PathDelim`.

On Linux, glibc does not unload `libonnxruntime.so` after `dlclose` while the thread that loaded it is alive (the library has thread-local objects with destructors). The code calls `dlclose`. The test that checks the unload is Windows only.

## Linux artifacts

`TSearchArtifactManifest.DefaultPath` reads `search-artifacts.json` on Windows and `search-artifacts-linux.json` on Linux, from the folder of the program. The Linux manifest has the same models as the Windows manifest. Only the two archives are different:

| Archive | Size | SHA-256 | Files used |
| --- | --- | --- | --- |
| `onnxruntime-linux-x64-1.31.1.tgz` (Microsoft ONNX Runtime GitHub release v1.31.1) | 11,413,655 B | `c849e36a1ef3e22d4ff217b9d1ce4a3cf5b9467b975610913ae959ad5b16bdc9` | `onnxruntime-linux-x64-1.31.1/lib/libonnxruntime.so.1.31.1`, `.../lib/libonnxruntime_providers_shared.so`, `.../LICENSE`, `.../ThirdPartyNotices.txt` |
| `pdfium-linux-x64.tgz` (`bblanchon/pdfium-binaries`, `chromium/8125`) | 3,828,800 B | `e1c3ce6e270cb5e0c20816b379ad9f2c1309972697c505f508de92bf5e7d6659` | `lib/libpdfium.so`, `LICENSE` and the 18 files in `licenses/` |

- All members of the ONNX Runtime archive start with the folder `onnxruntime-linux-x64-1.31.1/`. The PDFium archive has no top folder.
- The archive has two symbolic links (`libonnxruntime.so` and `libonnxruntime.so.1`). The installer extracts only the listed regular files. The program loads the library by its full name `onnxruntime/onnxruntime-linux-x64-1.31.1/lib/libonnxruntime.so.1.31.1`, so it does not need the links.
- The PDFium path is `pdfium/lib/libpdfium.so`.
- Both libraries need only glibc, libstdc++, libgcc_s, libm, libdl, librt and libpthread of Ubuntu 22.04 (measured with `ldd`).
- The full Linux download is 626,284,916 bytes (about 597 MB). Of these, 503,835,209 bytes are required parts and 122,449,707 bytes are optional parts (PDFium and the reranker).

The artifact folder on Linux is `$XDG_DATA_HOME/APS-ELN/search-artifacts`, or `~/.local/share/APS-ELN/search-artifacts` when `XDG_DATA_HOME` is not set. `ELN_SEARCH_ARTIFACTS` overrides the folder on both platforms. The Windows folder is `%LOCALAPPDATA%\APS-ELN\search-artifacts`, as before.

Two ways fill a Linux artifact folder:

- On Windows: `tools/Get-SearchArtifacts.ps1 -Manifest ELN.Search/search-artifacts-linux.json -Destination <folder>` (for example a `\\wsl.localhost\...` path).
- On Linux: the program installer. `SearchHarness --install-artifacts DIR` calls it. In WSL it downloaded and verified both Linux archives in 30 s.

A Linux program that uses the reranker or checks the artifacts reads the manifest beside the program. A server package must thus put `search-artifacts-linux.json` beside the Linux program.

## SQLite on Linux

The Linux programs use the system SQLite. On Linux, the unit initialization of `unit_SearchIndexStore` sets `SQLiteLibraryName` to the value of `ELN_SQLITE_LIBRARY`, or to `libsqlite3.so.0`, if no other code has set it. It does this one time at start, not in `Open`, because several threads can open stores at the same time.

Facts measured in WSL `Ubuntu-22.04` (the same release as the server image):

- `libsqlite3-0` 3.37.2-2ubuntu0.5, `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6`.
- Compile options include `ENABLE_FTS5`, `ENABLE_JSON1`, `ENABLE_MATH_FUNCTIONS` and `THREADSAFE=1`.
- `json_extract`, `json_each`, an FTS5 match and an FTS5 match with the `trigram` tokenizer work.
- `SearchHarness --fts5` loads `/lib/x86_64-linux-gnu/libsqlite3.so.0` and gives the same match rows as Windows (Windows uses its bundled `sqlite3.dll` 3.45.3).
- The CPU of this workstation has AVX2. This is not a fact about the NAS CPU. Check `lscpu` on the NAS.

## The interface `ISemanticSearch`

`unit_SemanticSearchApi` has no `ELN.Model` dependency and no TMS type.

```pascal
TSemanticSearchRequest = record
  Query: string;
  VisibleProjectIds: TArray<Integer>;
  TopK: Integer;
  Filter: TSemanticSearchFilter;
  Rerank: Boolean;
end;

TSemanticSearchResult = record
  Groups: TArray<THybridGroup>;
  Reranked: Boolean;
  IndexStatus: TSemanticSearchStatus;
  FiltersApplied: string;
end;

ISemanticSearch = interface
  function Search(const Request: TSemanticSearchRequest;
    const Cancelled: TCancelCheck): TSemanticSearchResult;
  function Status: TSemanticSearchStatus;
  function RerankerAvailable: Boolean;
  function IsRemote: Boolean;
end;
```

- The unit also has the filter records (`TSemanticSearchFilter`, `TValueConstraint`, `TSemanticDateField`, `TAppliedLimit`), the status (`TSemanticSearchStatus`, the old `TServiceStatus` without `LastSync`, with the new `DroppedGroups`), the exceptions `ESemanticSearchUnavailable`, `ESemanticFilterError` and `ESemanticSearchAccessDenied`, and the name constants `PassageFieldNames` and `HitSourceNames`. The MCP tool and the remote client use the same name constants.
- `TValueConstraint` and `TAppliedLimit` have `HasMin`, `HasMax`, `Min` and `Max`. They do not use `Nullable<Double>`.
- `FiltersApplied` is the JSON object text of the resolved filter. It is empty when the filter is empty.
- `Status` and `RerankerAvailable` run on the UI thread (the status timer of the Search dialog). They return cached state. They never wait for a running search, for a lock that a search holds, or for the network. A test checks this for the local implementation while a search is blocked in a live check.
- `TSemanticSearchRunner.Create(Search)` runs each `Start(Request, OnDone)` on its own thread. It gives the result on the main thread through `TThread.Queue`. A newer `Start` cancels the rerank of an older search. The destructor stops the delivery and waits for the threads.

### Local implementation

`TLocalSemanticSearch.Create(Service, ResolveFilter, DescribeLimits)` (`IsRemote = False`). It does not own or free the service. The host injects the two functions, so `ELN.Search` stays free of `ELN.Model`:

- `SemanticFilterResolver(Manager)` and `ValueLimitDescriber(Manager)` in `ELN.Model/unit_SemanticSearchFilter.pas` give the two functions for one Aurelius manager.
- The Desktop wraps them with `MainThreadFilterResolver` and `MainThreadLimitDescriber` (`ELN.Desktop/Units/unit_MainThreadSearchSource.pas`), because the manager belongs to the main thread.

`Search` sets `RerankDepth := 0` when `Request.Rerank` is false. For a non-empty filter, it calls the resolver, then writes the `filters_applied` text. An `ESemanticFilterError` keeps its class and its message through the interface.

### Hosts

- The Desktop Search dialog takes `ISemanticSearch`: `TdlgSearch.Execute(NavigateProc, Semantic, VisibleProjectIds)`. It owns one `TSemanticSearchRunner` for each binding. `TdlgSearch.ReleaseSemantic` waits for a running search.
- The MCP tool `search_semantic` uses `TToolContext.SemanticSearch: ISemanticSearch`. `TToolContext.SemanticIndex: TSemanticSearchService` is the local index that the tool syncs, or nil. The tool calls `SyncNow` only when `SemanticIndex` is set and the search is not remote. A remote search never starts a sync.
- The sync methods (`StartSync`, `SyncNow`) stay on `TSemanticSearchService`. The hosts keep the service for the sync and own all lifetimes. A host releases the interface before it frees the service.

### "All projects"

`SearchVisibleProjectIds(Manager, Policy, User)` in `ELN.Model/unit_SearchVisibility.pas` changes the visible set of an access policy into the array of the search request. A `nil` dictionary from the policy means all projects: the function returns every project id (one query; archived projects are included, because the local policy also shows them). An empty dictionary means no project. The MCP tool and the Community Desktop use this function. In a search request, `VisibleProjectIds` is always explicit: an empty array means no project. The local search then returns no groups. The remote client returns no groups and sends no request.

## Remote search

`TRemoteSemanticSearch.Create(BaseUrl, GetToken, TimeoutMs)` (`IsRemote = True`). The host gives the base URL, a token function and the time limit. The client has no credential logic. The full contract is in `docs/search-remote-api.md`. In short:

- `POST {base}/search/semantic` with `Authorization: Bearer <token>`, and `GET {base}/search/status`. The JSON names are the names of the MCP tool.
- A 401 response calls `GetToken` one more time and sends the request again, one time. 400 gives `ESemanticFilterError`. 401 after the retry and 403 give `ESemanticSearchAccessDenied`. 503, no answer within `TimeoutMs`, no connection, a certificate that is not trusted, and a response that is not valid give `ESemanticSearchUnavailable`.
- The client removes each group whose `project_id` is not in `VisibleProjectIds`, and adds the count to `DroppedGroups`. The MCP tool and the Desktop dialog also apply their own access checks to each item.
- `Status` and `RerankerAvailable` never use the network. A background thread refreshes the cached status, not more than one time in 10 s.
- The client does not follow redirects, so the token never goes to another host.
- The client validates the server certificate against the trust store of the operating system (Windows: the certificate store; Linux: the CA bundle of curl).

## Live source for servers

`THybridSearchOptions.LiveSource: ISearchDocumentSource`. When it is nil (the default), the search uses the source of the service. When it is set, the live check (`IsItemLive`) of that one search uses it. The source is kept in a local variable of the search, so a second search cannot change it.

Rules for a multi-threaded server:

- A server must use `TSemanticSearchService` with `THybridSearchOptions` directly (ruling R5). `ISemanticSearch` does not have `LiveSource`.
- A server must set `LiveSource` in each search to a source that uses the database session of that request. The live check runs on the thread that calls `Search`, so the session is used only on its own thread.
- A server should give the service a constructor source that raises an exception in `IsItemLive`. Then a search that does not set `LiveSource` fails, and does not use another session.
- The live checks of a search run while the service holds its lock. Two searches do not do live checks at the same time.

## Linux test procedure

Prerequisites (see `README.md`, "Linux64 search targets"): the Delphi 13 Linux platform, the Ubuntu 22.04 SDK sysroot (`LinuxSdkRoot`), the TMS BCL and Aurelius Linux64 DCUs, WSL 2 with the distribution `Ubuntu-22.04`, and the search artifacts in the distribution.

Run these commands from the repository root, in a PowerShell 7 session:

```powershell
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchTests -Platform Linux64 -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchIndexTests -Platform Linux64 -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchHarness -Platform Linux64 -Configuration Release
./tools/run-linux-tests.ps1 -Executable '_OUT/SearchHarness/Linux64/Release/SearchHarness' -Arguments '--fts5' -PathEnvironment @{ ELN_SOURCE_ROOT = '.' }
./tools/run-linux-tests.ps1 -Executable '_OUT/SearchHarness/Linux64/Release/SearchHarness' -Arguments '--eval', 'eval-dev.json', '--eval-corpus', 'eval-corpus.json' -PathEnvironment @{ ELN_SOURCE_ROOT = '.' }
```

- `run-linux-tests.ps1` copies only the program and its `.so` files into a new folder in the distribution. The tests and the harness find the fixtures and the manifests through `ELN_SOURCE_ROOT`. `-RunTests` with Linux64 sets it.
- `--eval` on Linux must give the same values as on Windows. Compare the hybrid row, or give the Windows `--per-query` file to `--compare`.
- Set `ELN_SEARCH_ARCHIVES` to a folder with the two Linux archives to also run `TLinuxArchiveInstallTests` (the program installer on the real archives). Without the variable, this fixture is not registered.

### Tests that do not run on Linux

These units are not compiled into `SearchIndexTests` on Linux64 (`{$IFDEF MSWINDOWS}` in `SearchIndexTests.dpr`), because they need `TLocalNotebook` (ruling R6):

| Unit | Fixtures |
| --- | --- |
| `test_SearchIndex` | `TDocumentProviderTests`, `TSearchIndexerTests`, `TStorageFileReaderTests`, `THybridSearchTests` (the notebook tests), `TRealModelSearchTests` |
| `test_PassageContext` | `TPassageContextProviderTests` |
| `test_SemanticSearchFilter` | `TSemanticSearchFilterTests` |

These single tests are Windows only:

| Test | Reason |
| --- | --- |
| `TSemanticSearchServiceTests.DestroyDuringSyncStopsWorker` | `GetMemoryManagerState` is not available on Linux64 (ruling R7). |
| `TTextFormatExtractorTests.XlsxWorkbookSheetBombRejected`, `XlsxSharedStringsBombRejected`, `XlsxUnclosedValueIsCapped` | `GetMemoryManagerState` (ruling R7). |
| `TWinHttpCancelTests.CancelDuringStalledResponseReturnsPromptly` | WinSock (ruling R7). |
| `TEmbedderArtifactTests.RepeatedCreateAndFreeReleasesRuntime` | glibc keeps `libonnxruntime.so` loaded after `dlclose` (see "Platform layer"). |

The E2250 errors of `Assert.WillRaise` that the first Linux64 compile showed are not a compiler defect. dcclinux64 gives E2250 for each later `WillRaise` call after an earlier error in the same unit. With the earlier errors corrected, all `WillRaise` calls compile without change.

## Verification at the end of stage 7

Results at commit b94bf6b plus the documents of this task (Win64 Debug unless stated):

| Check | Win64 | Linux64 (WSL `Ubuntu-22.04`) |
| --- | --- | --- |
| `SearchTests` | 54 of 54 passed, 0 leaked | 53 of 53 passed, 0 leaked |
| `SearchIndexTests` | 352 of 352 passed, 0 leaked | 268 of 268 passed, 0 leaked |
| `StorageTests` | 13 passed, 0 failed | - |
| `DesktopRegressionTests` | 410 of 410 passed, 0 leaked | - |
| Help checks (`Build-HelpIndex.ps1 -FixIds`, `Test-BuildHelpIndex.ps1`, `node --test tools/help-search.test.js`) | 0 ids added; 23 passed; 13 passed | - |
| `CommunityDesktop`, `CommunityMCP` | build succeeded, 0 errors | - |
| `SearchHarness --fts5` (Release) | - | exit 0; SQLite 3.37.2, `ENABLE_FTS5` 1, trigram works |
| `SearchHarness --eval eval-dev.json --eval-corpus eval-corpus.json` (Release), hybrid row `all` | nDCG@10 0.653, R@10 0.703, MRR 0.737 | nDCG@10 0.653, R@10 0.703, MRR 0.737 |

`--compare` of the Linux run with the Windows `--per-query` file gives 0 better, 0 worse, 53 same and 4 irr same in all four modes. The two per-query files are the same after the removal of the line-end and BOM differences. Only the times are different (hybrid mean 4.1 ms on Windows, 5.6 ms in WSL).

## Limits

- On Linux, the provider, the indexer, the notebook tests of the hybrid search, the filter resolver and the passage context provider have no test in this repository.
- A real TLS validation failure is not tested in this repository. The client changes `ENetHTTPCertificateException` to `ESemanticSearchUnavailable`, and a test checks this with a fake transport. The RTL source shows that both backends raise this exception.
- The live checks of a search run under the service lock. On a server with one database round trip for each item (up to about 150 candidates in a search), the requests and the sync worker wait for each other.
- The destructor of `TRemoteSemanticSearch` waits for a running status request, for not more than `TimeoutMs`.
- `GetToken` runs on the search threads and on the status thread. The host function must be thread-safe.
- `Status` of the remote client is the default (0 passages) until the first status response. The dialog shows "Indexed 0 passages" for a short time.
- On Windows, each real request starts one watchdog thread.
- The Desktop and the MCP host were compiled, but not started.
