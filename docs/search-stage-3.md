# Semantic search, stage 3: hosts

Stage 3 connects the search foundation (stage 1) and the index (stage 2) to the hosts: Desktop, the MCP server and the installer. See `docs/search-embedding-foundation.md` and `docs/search-index-stage-2.md`.

## Artifacts

The embedding model, ONNX Runtime, PDFium and the optional reranker model are not in the installer and not in the repository. A host downloads them one time.

- `ELN.Search/search-artifacts.json` (version 3) is the manifest. It lists `Models` (the E5 embedder, and the optional reranker, each with a `Role`, a license and a revision) and a list `Archives` (ONNX Runtime as `zip`, PDFium as `tar.gz`). Each file has its URL, size and SHA-256. A manifest of another version is refused with an error message. The build stages the manifest beside the executables.
- `unit_SearchArtifacts` reads the manifest and verifies files. A file is used only when its size and SHA-256 match. A partial or wrong file never has its final name. One rule applies in the library, in the installer, in the script and in the Setup dialog: the required parts (the E5 model and ONNX Runtime) decide if search can start. The optional parts (PDFium and the reranker model) are downloaded with the other parts, and the dialog shows the state of each part. A missing optional part never makes the dialog say "Not installed".
- `unit_SearchArtifactInstall` downloads the files. It uses the proxy from `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY`; if they are not set, it uses the system proxy. It writes `.part` files and resumes with HTTP Range. After a network error, it tries again up to 5 times, with waits of 1 to 16 seconds. The connect time limit is 30 seconds. The receive time limit is 120 seconds. A cancel request closes the open connection, so a stopped transfer ends in about 1 second.
- `tools/Get-SearchArtifacts.ps1` reads the same JSON for developer and test machines.
- The default folder is `%LOCALAPPDATA%\APS-ELN\search-artifacts`. The variable `ELN_SEARCH_ARTIFACTS` overrides it. The download is about 666 MB (697,877,392 bytes). It is the sum of the sizes in the manifest. 549 MB are required parts and 117 MB are optional parts. `unit_TarGz` extracts only the listed files from the `.tgz` archive.

## Index store

The store file is `ChangeFileExt(DatabasePath, '') + '.search.sqlite'`. Hosts never write to the notebook for search.

- `busy_timeout` is 10 seconds. Writers use `BEGIN IMMEDIATE`. The journal mode is WAL. Desktop and the MCP server can use the same file.
- The store opens in one atomic step. If the schema is not compatible, the tables are made again. If the file is not a SQLite file, it is deleted and made again.

## Service and threads

`unit_SemanticSearchService` is the one object that a host uses.

- The embedder and the store load on first use.
- One lock protects them. After each committed batch, the sync worker gives the lock back. A search waits for at most one batch.
- `StartSync` runs a worker thread. The worker touches only the service (store and embedder), never the ORM or VCL controls. Its callbacks go to the UI through `TThread.Queue` behind a gate, so a callback cannot run after the host is closed.
- `SyncNow` runs on the caller thread with a deadline. The MCP server uses it.
- If the factory fails, the failure is kept. The service does not try again in the same process.
- `TObjectManager` is used only on the thread that owns it. The document provider reads passages on that thread.

## Desktop

- **Tools > Semantic Search Setup...** has **Download and Install**, **Verify** and **Remove**.
- When a notebook opens and the artifacts are ready (a size check), Desktop creates the service and starts a sync. It starts a sync again when the Search dialog opens.
- The Search dialog has the check box **Search by meaning**. The program saves it in the settings. The dialog has a status line and the result columns.
- Passages are read on the UI thread. A large notebook can make the window pause for a short time.

## MCP tool

`search_semantic` takes `query`, `top_k` (1 to 50, default 10) and `project_id`. It is registered with `tscProjectScoped`. Each call brings the index up to date for a bounded time, then searches. The file phase takes up to the deadline (20 seconds). If it hits the deadline, the embedding phase gets up to one more deadline. A call can take up to about 40 seconds.

The result has an `index` object with `complete`, `indexed_passages`, `pending_passages` and `files_pending` (files not yet read), and `groups`: one group for each item (see `docs/search-stage-5.md`). The `score` of a group is a rank-fusion value, for ordering only. It is not a probability or a relevance percentage. When `complete` is false, the client calls the tool again. The live `tools/list` count is 69 (the number of `Registry.Register` calls in `ELN.MCPServer`).

Errors:

- The artifacts are not installed: the message says that semantic search is not installed.
- The model or store cannot start: `could not start: <cause> [semantic_search_unavailable]`.

The keyword tool `search` does not change and does not need the artifacts.

## Installer and platform

- Community Desktop, the MCP server and the installer are Win64 only. The installer is x64 (`ArchitecturesInstallIn64BitMode`). Existing per-user installs upgrade in place.
- The Win32 search targets are removed. The 32-bit `sqlite3.dll` has no FTS5, and there is no 32-bit ONNX Runtime.
- The installer puts `search-artifacts.json` beside the executables. The model and ONNX Runtime come from the download.

## Long queries

When a query has more than 512 tokens, the hybrid searcher skips the vector list. The word and trigram lists still run, so the search returns word hits and raises no error.

## Memory

Each process that loads the model uses about 1 GB. This value is an estimate. The owner measurement is pending. Desktop and the MCP server each load their own copy.

## Limitations

- File text (PDF, Office, HTML, JSON, XML, CSV, RTF, `.md`, `.txt`) is read since stage 4; see `docs/search-stage-4.md`. Viewer plugins are not used.
- The first sync time on a real notebook is not known. The owner measurement from stage 2 is still pending. If a warm query takes 100 ms or more, or the memory grows by 200 MB or more, an approximate index becomes its own stage before release.
- Cross-lingual retrieval is weak for short text.
- The index is a copy of the notebook text next to the notebook. Protect it like the notebook.
- The Desktop sync reads passages on the UI thread.
