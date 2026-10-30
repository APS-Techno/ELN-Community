# Semantic search index (stage 2)

Status: stage 2 of the hybrid search work. This stage gives a rebuildable search index for one notebook, an indexer, a hybrid searcher and a harness mode. It does not change the notebook schema, the Desktop search dialog or the MCP tools. Stage 1 is in `docs/search-embedding-foundation.md`.

## Repository map

| Unit | Content |
| --- | --- |
| `ELN.Search/unit_SearchPassages.pas` | `TSearchPassage`, `TPassageField`, `ISearchDocumentSource`, `ChunkText`, `PassageHash`, `FoldSearchText`. |
| `ELN.Model/unit_SearchDocumentProvider.pas` | `TNotebookDocumentProvider.Create(Manager, Storage)`: read-only bulk reader. It is the only search unit that touches domain classes. |
| `ELN.Search/unit_SearchIndexStore.pas` | `TSearchIndexStore.Open(Path, Identity, Dimension)`: SQLite file with passages, vectors and two FTS5 tables. |
| `ELN.Search/unit_SearchIndexer.pas` | `TSearchIndexer.Sync` returns `TSyncStats`. |
| `ELN.Search/unit_HybridSearch.pas` | `THybridSearcher.Create(Store, Embedder, Source)`, `Reload`, `Search(Query, VisibleProjectIds, TopK, Options)` returns item groups (`THybridGroup`, see `docs/search-stage-5.md`). |
| `ELN.Community.Tests/test_SearchIndex.pas`, `SearchIndexTests.dpr` | DUnitX tests (target `SearchIndexTests`). |
| `ELN.Community.Tests/SearchHarness.dpr` | Console harness. Option `--notebook` runs the index on a notebook copy. |

`unit_SearchDocumentProvider` is not in `ELN.Model.dpk`. A registration there would pull `ELN.Search` and ONNX Runtime into the Model package. A host compiles the unit from source.

## Passages

A passage is one field of one item, split into chunks of at most 1200 characters with 150 characters of overlap. The key has the form `<kind>:<id>:<field>#<chunk>`, for example `item:12:description#0`. The fields are:

| Field | Source |
| --- | --- |
| `pfItemTitle`, `pfItemDescription`, `pfItemProperties` | Item |
| `pfItemTags` | Tags of the item |
| `pfEntryTitle` | Lab entries |
| `pfProtocolForm` | `FormData` of protocols. `TSearchModel` never reads it. It is the largest scientific text field. |
| `pfValueDescription` | Value descriptions |
| `pfFileName` | File name (title and extension) |
| `pfFileText` | Text of `.md` and `.txt` attachments up to 2 MB, read with `INotebookStorage.ReadBytes`. A file that is not valid UTF-8 is decoded with the ANSI code page of the machine. |

Deleted items (`IsDeleted`) give no passage. A passage stores the SHA-256 of its UTF-8 text. Since stage 6, a passage can carry a context, and then the hash is the SHA-256 of the context, a line feed and the text; with an empty context the hash is the same as before (see `docs/search-stage-6.md`). Indexed text and query text both get the folding of `ё` to `е` (and `Ё` to `Е`), because the FTS5 `remove_diacritics` option does not fold Cyrillic.

## Store schema

The store is a separate SQLite file next to the notebook: `ChangeFileExt(DatabasePath, '') + '.search.sqlite'`. It does not use the sidecar suffixes of the notebook. The file can be deleted at any time. The next sync rebuilds it.

| Table | Content |
| --- | --- |
| `meta` | `schema_version`, `embedder_identity`, `dimension`. |
| `passages` | `id`, `key` (unique), `project_id`, `item_id`, `file_id`, `field`, `text`, `content_hash`, `vector` (BLOB: 384 little-endian float32, no header). |
| `passages_words` | FTS5, external content, `unicode61 remove_diacritics 2`. |
| `passages_tri` | FTS5, external content, `trigram`. |

Triggers on `passages` keep both FTS5 tables current. `Open` deletes and recreates the file when the schema version, the embedder identity or the dimension differ, or when the file is not a valid store. `WasReset` reports this. Vectors from two embedder identities never mix.

## Reconcile algorithm and the decision not to use an audit cursor

`Sync` is a full reconcile:

1. The provider reads all passages with their text and hashes. This is cheap SQL plus file reads.
2. The store returns its catalog (key, coordinates, hash).
3. A key that is not in the catalog is **added**. A key with a different hash is **changed**. A key with the same hash and different project, item or file is **moved** (coordinates update, no embedding). A catalog key that is not in the source is **removed**.
4. Removals and moves are one transaction. Added and changed passages are embedded in batches of 32 and written in one transaction per batch. The embedding is the expensive step, and only the difference is embedded.
5. A cancel callback is checked before each batch. A cancelled sync leaves a consistent store. The next sync does the remaining work without duplicates.

The stage 1 proposal was to read `AuditLog` rows after a stored cursor. The code survey of 2026-10-28 shows that this misses changes:

- Tag assign, unassign and rename (`unit_TagModel.pas:137-169`), comments, item links, package import (`unit_PackageImport.pas`) and protocol template import write no audit row.
- `UpdateFile` title and hash writes (`unit_ItemModel.pas:823`) write no audit row.
- Purge of one item (`unit_RecycleBinModel.pas:395`) writes one row with `EntityId` 0.
- `AuditLog` has no project column.

A cursor would miss these changes without any error. Adding audit rows to these paths is out of scope. If sync time on real notebooks is too long, stage 3 can add audit rows to the unaudited paths and then use a cursor.

## Access model

- The indexer opens the notebook read-only. It calls no `Save`, `Flush`, `Update` or `RecordAudit`. A test checks that the audit log and the notebook file are not changed.
- The index contains passages of all projects in the notebook file. Access is applied at query time.
- `Search` takes the visible project IDs from the caller (`IProjectAccessPolicy.VisibleProjectIds`). The vector search gets these IDs as the eligible scopes, and both FTS5 queries filter on `project_id`.
- Every fused hit is revalidated with `ISearchDocumentSource.IsItemLive`: the item must still exist, must not be in the recycle bin, and its **current** project must be visible. A hit for an item that moved or was deleted after the last sync is dropped. The `ProjectId` of a returned hit is the current project, not the indexed one.
- The index is a copy of notebook text on disk. It has the same sensitivity as the notebook and it needs the same file protection.

## Retrieval

`Search` makes three ranked lists, each with at most 50 candidates (`DefaultCandidatesPerList`, `THybridSearchOptions.CandidatesPerList`):

1. Exact cosine search over the passage vectors in the eligible projects.
2. FTS5 word match with BM25 order.
3. FTS5 trigram match (query of 3 characters or more) for identifiers and file names.

The lists are fused with weighted reciprocal rank fusion: `score = field weight * sum over lists of list weight / (60 + rank)` (`DefaultRrfK = 60`). The default list and field weights are all 1, so the formula is the plain `sum over lists of 1 / (60 + rank)`. The order of equal scores is described in `docs/search-stage-5.md` ("Tuning"): by the rank in a weight-0 list, then by passage key (group: `ItemId`). A hit has `Sources` (a set of `hsVector`, `hsWords`, `hsTrigram`), `ItemId`, `ProjectId`, `FileId`, `Field` and a snippet of up to 200 characters. A query with fewer than 2 characters, an empty visible set or `TopK < 1` gives an empty result.

The query text is never passed to FTS5 as syntax. The characters `"`, `*`, `-` and the words `NEAR`, `AND` are plain text. Control characters (below U+0020, except tab, line feed and carriage return) are removed from the query before it is quoted. There is no fixed score threshold: E5 scores lie in a narrow band, and a query with no relevant passage still gets hits.

After a `Sync`, call `THybridSearcher.Reload`. The searcher holds the vectors and the catalog in memory from the last `Create` or `Reload`.

## Harness

```powershell
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchHarness -Configuration Release
_OUT\SearchHarness\Win64\Release\SearchHarness.exe --notebook <COPY>\notebook.sqlite [--storage <COPY>\files] [--query "<text>"]
```

**Pass a copy of a notebook, never the original.** The harness opens the file with `TLocalNotebook.Open` (never `CreateNew` or `Upgrade`) and writes `<name>.search.sqlite` next to it. It prints:

- passage count in total and by field;
- first sync: time, embedded count, passages per second;
- second sync: time and embedded count (must be 0);
- store size (database file plus WAL file);
- private memory (`PagefileUsage`) at the baseline, after sync, after loading the index and after the queries, with the growth since the baseline. The baseline is taken after the embedder is loaded and after one warm-up batch (`SyncEmbedBatch` = 32 passages of 1200 characters, `olTruncate`), and before the provider and the store open. The warm-up fills the ONNX Runtime memory arena. Thus the growth shows the notebook reader, the store, the vectors and the searcher, and it does not show ONNX;
- with `--query`: the top 10 hits (score, `Sources`, `ItemId`, `Field`, snippet) and the median of 20 warm query latencies.

Without `--storage`, the attachment root saved in the notebook is used. A copy of the database made without the attachments gives no `pfFileText` passages.

## Measurements

### Synthetic fixture (not a real notebook)

This is the 12-passage notebook of the `SearchIndexTests` fixture, copied to a temporary folder. It checks that the harness works. It does not show how the index behaves on real data. Machine: AMD Ryzen 9 9950X3D, 32 logical processors. Win64 Release harness, ONNX Runtime 1.31.1 CPU, 2026-10-28.

| Measurement | Synthetic result |
| --- | --- |
| Passages | 12 (title 1, description 3, properties 1, tags 1, entry title 1, protocol form 1, value description 1, file name 2, file text 1) |
| First sync | 0.2 s, 12 embedded, 62.9 passages/s (too small to give a rate) |
| Second sync | 0.00 s, embedded 0, unchanged 12 |
| Store size | 0.14 MB (all in the WAL file) |
| Private memory | baseline 1055 MB after the warm-up batch (492 MB after the model load); growth since the baseline 0 MB after sync, after loading the index and after the queries |
| Warm query `Mo/Si` (hybrid, 20 runs) | median 2.4 ms, max 3.0 ms |

The growth is below 1 MB because the index of 12 passages is small. The ONNX memory is in the baseline: one full warm-up batch raises the private memory by 563 MB over the value after the model load. Read the 0 MB as the lower bound of the growth on a real notebook. A passage batch with more padded tokens than the warm-up batch can still enlarge the arena in a real run. In that case the growth includes this ONNX part.

### Real notebook (owner action)

Not measured yet. The owner makes a copy of a real notebook and its attachments, runs the command in the section "Harness" with a typical query, for example `--query "Mo/Si"`, and enters the numbers here.

| Measurement | Real notebook |
| --- | --- |
| Passages (total) | not measured yet |
| Passages by field | not measured yet |
| First sync time and passages/s | not measured yet |
| Second sync (embedded must be 0) | not measured yet |
| Store size | not measured yet |
| Private memory after sync and growth | not measured yet |
| Warm query median | not measured yet |

Decision criterion: **exact search is enough** if the warm query median is less than 100 ms **and** the memory growth is less than 200 MB. If not, stage 3 needs an approximate index. Record the decision under the table.

## Limitations

- File text: since stage 4, the attachment text comes from headless extractors with a `file_text` cache, not from viewer plugins; see `docs/search-stage-4.md`. The provider reads no file bytes.
- No audit cursor. Each sync reads the whole notebook (all passage texts and files), then compares hashes. The time of one sync grows with the size of the notebook even when nothing changed.
- One thread per embedder. There is no locking in `TE5TextEmbedder`. `Sync` and `Search` must not run at the same time with the same embedder.
- `Search` raises `ETextTooLong` when the query has more than 512 tokens, because queries are never truncated. Since stage 3, the hybrid searcher catches this error. It skips the vector list and uses only the word and trigram lists; see `docs/search-stage-3.md`.
- Cross-lingual retrieval is weak for short text. The test `CrossLingualFindsProtocolForm` uses a bilingual fixture. A pure Russian query against an English-only short form ranked 12 to 19 of about 35 passages.
- `unit_SearchDocumentProvider` is not in `ELN.Model.dpk` (see the repository map). A host compiles it from source.
- The index stores a copy of the notebook text. A host must put it in a place with the same protection as the notebook.
- Search is Win64 only. The 32-bit `sqlite3.dll` that Aurelius loads has no FTS5, and there is no 32-bit ONNX Runtime. Do not build or run the search targets for Win32. Stage 3 removes Win32 from Desktop, the MCP server and the installer; see `docs/search-stage-3.md`.
- Only the fp32 model and the CPU provider are supported (see stage 1).

## Tests

```powershell
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchIndexTests -Platform Win64 -RunTests
```

`SearchIndexTests` builds a new GUID-rooted synthetic notebook for each test. The tests that use the real E5 model need the external search artifacts (see stage 1).
