# Semantic search foundation (embedding milestone)

Status: first milestone of the hybrid search work. This milestone supplies a native Delphi text-to-embedding pipeline, an exact vector search, a console harness and tests. It does not change the notebook schema, the Desktop search dialog or the MCP tools.

## Repository map

| Area | Path | Relevance |
| --- | --- | --- |
| Current search | `ELN.Model/unit_SearchModel.pas` (`TSearchModel.Search`) | `LIKE '%term%'` on item title, description and properties, entry titles, file names, value descriptions and tags. Access filter through `FAccess.VisibleProjectIds` (`ELN.Model/unit_ProjectAccessPolicy.pas`). A multi-word query falls back to per-word `LIKE` only when the phrase has no hit. |
| Desktop caller | `ELN.Desktop/Dialogs/Search/dlg_Search.pas` | Calls `Model.Search.Search` on the GUI thread. |
| MCP caller | `ELN.MCPServer/unit_ToolsNavigation.pas` (`HandleSearch`, `MakeSearchSchema`) | Registered as `search` with `tscProjectScoped`. Drops hits in projects that are not visible. |
| MCP registration | `ELN.MCPServer/unit_ToolCatalog.pas` (`RegisterAllTools`), `unit_MCPTools.pas` (`TToolContext`, `TToolRegistry.Register`) | A later `search_semantic` tool registers here. |
| Attachment text | `ViewerPlugins/Core/unit_ELNPluginCore.pas` (`IDetailedInfoProvider.GetDetailedInfo`, `IKeyValueProvider`), `ELN.MCPServer/unit_PluginHost.pas` (`TPluginHost.ExtractDetailedInfo`) | Source of file text for a later document provider. Unsupported files return `'{}'`. |
| Change feed candidate | `ELN.Domain/unit_AuditLog.pas` (`TAuditLog`: auto-increment `Id`, `EntityType`, `EntityId`, `Operation` incl. `aoDelete`), `ELN.Model/unit_AuditHelper.pas` (`RecordAudit`) | A monotonic `Id` can act as an index cursor. Not verified: that every mutation path calls `RecordAudit`. |
| SQLite access | `ELN.Community/unit_LocalNotebook.pas` (`TSQLiteNativeConnectionAdapter`), Aurelius `Aurelius.Drivers.SQLite.Import` | Aurelius loads `sqlite3.dll` by name at run time (`SafeLoadLibrary`), or the file in `SQLiteLibraryName`. There is no FireDAC in Community. |
| Threads | `ELN.Desktop/Dialogs/Items/frame_FileSystemBrowser.pas` (anonymous thread, Boolean cancel flag under a critical section) | Only background-work pattern in the shared source. MCP is single-threaded. |
| New code | `ELN.Search/` | Neutral units, RTL and `Winapi.Windows` only. No VCL, no Aurelius. `ELN.Model` requires `vcl` and Aurelius, so it is not the home for this code. |

## Components

| Unit | Content |
| --- | --- |
| `ELN.Search/unit_OnnxRuntimeApi.pas` | Binding to the ONNX Runtime C API. `TOrtRuntime` loads `onnxruntime.dll` from a full path and creates one `OrtEnv`. `TOrtSession` creates a session, reads input and output metadata, and runs int64 inputs to one float output. |
| `ELN.Search/unit_UnigramTokenizer.pas` | `TUnigramTokenizer`: executes the `tokenizer.json` of the model (Precompiled normalizer, space collapse, Metaspace, Unigram Viterbi, special tokens, `<s> A </s>`). It refuses other configurations. |
| `ELN.Search/unit_TextEmbedder.pas` | `ITextEmbedder` (`Identity`, `Dimension`, `MaxTokens`, `EncodeQuery`, `EncodePassages`) and `TE5TextEmbedder`. |
| `ELN.Search/unit_VectorSearch.pas` | `TExactVectorIndex`: exact cosine search over L2-normalized vectors with an explicit eligible-scope set. |
| `ELN.Community.Tests/test_SearchEmbedding.pas`, `SearchTests.dpr` | DUnitX tests (target `SearchTests`). |
| `ELN.Community.Tests/SearchHarness.dpr` | Console harness (target `SearchHarness`). |
| `ELN.Community.Tests/Fixtures/Search/` | Synthetic corpus, reference fixtures, an incompatible model. |
| `ELN.Search/search-artifacts.json`, `ELN.Search/unit_SearchArtifacts.pas`, `tools/Get-SearchArtifacts.ps1` | Artifact manifest, its verifier and the setup script. |
| `tools/search-reference/generate_reference_fixtures.py` | One-time generator of the reference fixtures. It is not a build or runtime dependency. |

### Embedder behavior

- Prefixes: `query: ` for queries, `passage: ` for passages (E5 convention).
- Pooling: mean of `last_hidden_state` over the attention mask, then L2 normalization. Confirmed by `1_Pooling/config.json` of the model (`pooling_mode_mean_tokens: true`).
- Length: 512 tokens including `<s>` and `</s>`. `olReject` raises `ETextTooLong`. `olTruncate` keeps the first 510 content tokens and sets `Truncated`, `TokenCount` and `SourceTokenCount` in the result. Queries always use `olReject`.
- Empty or whitespace-only text raises `ETextEmbedderError` before any inference.
- Batches: passages are padded to the longest row with `<pad>` (id 1) and mask 0. The cancel callback is checked before each batch and raises `EOperationCancelled`.
- Model check at load: inputs must be int64 `input_ids`, `attention_mask` and optional `token_type_ids`. The output `last_hidden_state` must be float `[batch, tokens, hidden_size]`, with `hidden_size` from `config.json`. Missing files raise `ETextEmbedderError` or `EOnnxRuntimeError` with the path.
- Identity string: model revision, model size, tokenizer SHA-256, prefix scheme, pooling, normalization, dimension and token limit. A later index stores it and refuses vectors with a different identity.
- The session loads once per embedder. Releasing the last reference releases the session, the environment and the DLL.

### Tokenizer decisions

- The reference is Hugging Face `tokenizers` executing `tokenizer.json`, because that file is the artifact the embedder reads. The `sentencepiece` library disagrees on 8 of 41 cases (whitespace at the ends, literal special tokens, Hangul jamo, two combining marks on one letter). These are documented differences between the two upstream tools, not defects of this implementation.
- The Precompiled normalizer works on grapheme clusters. A cluster shorter than 6 UTF-8 bytes is looked up as a whole. The Delphi code approximates UAX #29 (CR LF, controls, extend and spacing marks, ZWJ, ZWNJ, part of the Prepend set) with the Delphi RTL Unicode tables, not with the Unicode version of the Rust `unicode-segmentation` crate. The omitted rules (Hangul, regional indicators, emoji sequences) mostly form clusters of 6 bytes or more, which the normalizer treats per code point. A Hangul L V sequence followed by a combining mark is one exception in principle. The omission is not expected to change token IDs for the pinned charsmap; the 41 parity cases check this, but they do not prove it for all input.
- A lone UTF-16 surrogate becomes U+FFFD before normalization. Hugging Face Python refuses such strings.
- Literal `<s>`, `</s>`, `<pad>`, `<unk>` and `<mask>` in the text become special tokens, as in the reference. HTML `<s>` (strikethrough) text is therefore encoded as a control token. A document provider must decide if it escapes such markup.
- Model IDs are the indexes of `model.vocab` in `tokenizer.json` (`<s>`=0, `<pad>`=1, `</s>`=2, `<unk>`=3). The fairseq shift of `sentencepiece.bpe.model` IDs is already applied in that file.

### ONNX Runtime binding decisions

- Own binding, not `onnxpascal` or `TONNXRuntime`. Reasons: `onnxpascal` links `onnxruntime.dll` by name and does not release `OrtStatus` objects on errors; only 31 functions are needed.
- Function-table indexes were computed from `struct OrtApi` in the `onnxruntime_c_api.h` of 1.31.1 and cross-checked against the 1-based indexes of `onnxpascal` (all agree after the offset). The binding requests C API version 31.
- Windows ships `C:\Windows\System32\onnxruntime.dll` (version 1.17, Windows ML). A bare-name load can resolve to it. The binding loads the pinned DLL by full path with `LOAD_WITH_ALTERED_SEARCH_PATH`.
- Ownership: every non-null `OrtStatus` is read and released. Input tensors wrap Delphi arrays (`CreateTensorWithDataAsOrtValue`) and are released after `Run`. The output tensor, type infos and shape infos are released in `finally` blocks. Names from the default allocator are freed with `AllocatorFree`.

## Artifacts

Artifacts stay outside source control, in `%LOCALAPPDATA%\APS-ELN\search-artifacts` or in the folder of `ELN_SEARCH_ARTIFACTS`.

```powershell
pwsh -NoProfile -File tools/Get-SearchArtifacts.ps1             # download and verify
pwsh -NoProfile -File tools/Get-SearchArtifacts.ps1 -VerifyOnly # verify only
```

The script downloads with `curl.exe` (the system proxy settings apply; the owner's workstation used `HTTPS_PROXY`), checks size and SHA-256 of each file against `ELN.Search/search-artifacts.json`, and extracts ONNX Runtime from the verified archive.

| Artifact | Version | Size | SHA-256 | License |
| --- | --- | --- | --- | --- |
| `intfloat/multilingual-e5-small` `onnx/model.onnx` (fp32) | revision `614241f622f53c4eeff9890bdc4f31cfecc418b3` | 470,268,510 | `CA456C06...F1CBA6BC8665` | MIT |
| `onnx/tokenizer.json` | same | 17,082,730 | `0B44A9D7...14EBDF4C39` | MIT |
| `onnx/config.json`, `tokenizer_config.json`, `special_tokens_map.json`, `sentencepiece.bpe.model` | same | see manifest | see manifest | MIT |
| `onnxruntime-win-x64-1.31.1.zip` | 1.31.1, commit `41d4d61f`, C API 31 | 82,929,944 | `5869E26B...F7177AB4B2C` | MIT |
| `onnxruntime.dll` (from the archive) | 1.31.1 | 17,253,728 | `CB2FA518...20492DB0C` | MIT |

Vector dimension 384. Input limit 512 tokens. Required native libraries: `onnxruntime.dll` and `onnxruntime_providers_shared.dll` from the pinned folder. No Python or other runtime is needed. The installer task must decide where these files go and add the ONNX Runtime `ThirdPartyNotices.txt`.

## Build, test and run

```powershell
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchTests -RunTests
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchHarness
_OUT\SearchHarness\Win64\Debug\SearchHarness.exe --verify-reference --bench 4
_OUT\SearchHarness\Win64\Debug\SearchHarness.exe --query "образцы без отжига" --top 3
_OUT\SearchHarness\Win64\Debug\SearchHarness.exe --fts5
```

Add `-Configuration Release` for Release. The search units are Win64 only in practice: there is no 32-bit ONNX Runtime release. `SearchHarness --help` lists the options (`--scope`, `--batch`, `--threads`, `--sqlite`).

### Tests (`SearchTests`, 28 tests)

| Fixture | Checks |
| --- | --- |
| `TTokenizerParityTests` | Token IDs of 41 reference cases (Russian, mixed, decomposed Cyrillic/Latin/Greek, full-width, ligatures, controls, zero-width, literal special tokens, unknown characters, emoji, CJK, Hangul, Arabic, Hebrew, Devanagari, 600-word text). Fixture hash agrees with the loaded `tokenizer.json`. Padded batch IDs and masks. Missing and unsupported tokenizer files. 20000 literal special-token units tokenize in less than 500 ms. |
| `TEmbedderTests` | 7 reference vectors (max abs diff <= 1e-4, cosine >= 0.9999). A truncated 1325-token passage against an HF reference truncated at 512. Padded batch equals single encoding. Dimension and norm. 20 repeated queries identical. Overlength rejected or truncated by policy; the rejection names the passage index. Empty text. Cancellation. Identity string. |
| `TEmbedderArtifactTests` | Missing model folder, missing DLL, incompatible model (float `input_ids`), model without inputs, three create/free cycles with the DLL unloaded after each. |
| `TExactVectorIndexTests` | Ranking and tie break by source id, eligible scopes only, empty scope set, invalid vectors, NaN vectors. |
| `TFixtureRetrievalTests` | A relevant document in the top 3 for each corpus query except the negation and exact-identifier queries, which are measured but not asserted. All hits stay inside the eligible scopes. |

Mutation checks during development: disabling the whole-cluster lookup made 4 tokenizer cases fail; pooling on the first token only made the reference-vector test fail (max abs diff 0.245).

### Reference fixtures and provenance

Generated once with `tools/search-reference/generate_reference_fixtures.py` in a temporary Python 3.13.12 virtual environment outside the repository: `tokenizers` 0.23.3, `sentencepiece` 0.2.2, `onnxruntime` 1.31.1, `numpy` 2.5.4, `onnx` 1.23.2, `torch` 2.14.1+cpu, `transformers` 5.21.0. Downloads used `curl` through the workstation proxy.

- Token IDs: `tokenizers` on the pinned `tokenizer.json`.
- Vectors: Python `onnxruntime` on the pinned `model.onnx`, mean pooling and L2 normalization in numpy.
- Cross-check of the ONNX export: PyTorch with `model.safetensors` of the same revision (SHA-256 `1A55775F...F81C98477`) gives the same vectors (max abs diff 9.7e-8, cosine >= 0.99999988). This check is recorded in `embedding_reference.json` and is independent of the Delphi code.

```powershell
python tools/search-reference/generate_reference_fixtures.py --model-dir <artifacts>\multilingual-e5-small --torch-dir <folder with config.json and model.safetensors> --out-dir ELN.Community.Tests/Fixtures/Search
```

## Results on the owner's workstation (2026-10-28)

Machine: AMD Ryzen 9 9950X3D, 32 logical processors. Win64 Release harness, ONNX Runtime 1.31.1 CPU, fp32 model, default thread count. Corpus: 24 passages (946 tokens) and 14 queries. These numbers describe this corpus and this machine only.

| Measurement | Result |
| --- | --- |
| Tokenizer parity | 41 of 41 cases identical |
| Vector parity | worst max abs diff 7.1e-8 over 7 vectors |
| Model load (tokenizer + session) | 780-810 ms |
| Memory after load | working set 506 MB, private 492 MB, peak working set 869 MB during session creation |
| Passage throughput, 480 passages | batch 1: 220/s; batch 8: 374/s; batch 32: 424/s |
| Memory after 480 passages | batch 8: private 508 MB; batch 32: private 560 MB |
| Warm query (encode + search over 24 vectors) | median 2.9 ms (batch setting 8), max 3.5 ms |
| Relevant document in top 3 | 14 of 14 queries |

Observations:

- E5 scores fall in a narrow band (about 0.74 to 0.91 here). A query with no relevant document in scope (`q-14`) still returns three hits at 0.74 to 0.76. Do not use a fixed score threshold.
- The cross-lingual query `q-02` (Russian, film degradation) ranks a Russian Mo/Si deposition text first; the relevant Russian text is second and the English one is fifth. Shared language pulls scores up.
- The negation query `q-09` found the right document, but that is one sample. Embeddings do not model negation reliably.
- The identifier query `SMP-2024-017` ranked the right document first, but `SMP-2024-031` was a close second (0.836 against 0.827). Exact identifiers need the lexical path.

## FTS5 probe

`SearchHarness --fts5` loads SQLite exactly as Aurelius does and uses a temporary database only.

| Check | Result |
| --- | --- |
| Library loaded on this workstation | `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\sqlite3.dll` (found through `PATH`; a deployed build loads the copy beside the executable) |
| `sqlite_version()` | 3.45.3 |
| `ENABLE_FTS5` | 1 (FTS4: 0) |
| `fts5(..., tokenize='unicode61 remove_diacritics 2')` | works; Cyrillic case folding works (`плёнка` matches `Плёнка`) |
| Same word written with `е` instead of `ё` | no match: `remove_diacritics` applies to Latin script only. Russian `ё`/`е` folding must happen in the indexed text and in the query. |
| `"SMP 2024 017"` phrase | matches; `unicode61` splits identifiers at `-` |
| `fts5(..., tokenize='trigram')`, `"2024-01"` | substring match works |

Integration option: a separate, rebuildable search database (not the notebook) with an FTS5 table (`unicode61 remove_diacritics 2` plus application folding of `ё`) for words and a `trigram` table for identifiers and file names. The installer must ship a `sqlite3.dll` with FTS5 (the Embarcadero 3.45.3 build has it) and the Win64 build must not depend on `PATH`.

## Limitations

- Single-threaded use per embedder instance. No locking inside `TE5TextEmbedder`.
- The tokenizer loads `tokenizer.json` with `System.JSON` (17 MB). Load time is part of the 0.8 s model load.
- Only the CPU execution provider is used. The binding keeps the session options open for later providers.
- Only the fp32 model is supported and tested. Quantized or optimized variants need their own reference fixtures and a new index identity.
- Tests and harness need the external artifacts. Without them the model-dependent tests fail with the missing path; they do not pass silently.

## Next steps

Items 1 to 5 are done in stage 2. See `docs/search-index-stage-2.md`.

1. **Document provider**: done (`TNotebookDocumentProvider`). Attachment text is read by the stage 4 extractors; see `docs/search-stage-4.md`.
2. **Search database**: done (`TSearchIndexStore`). The store is a separate file next to the notebook. It has no audit cursor (see item 3).
3. **Incremental updates**: done as a full reconcile by content hash, with **no `AuditLog` cursor**. The survey shows that tag, comment, link, package import, protocol template import and file title/hash paths write no audit row, that one purge writes a row with `EntityId` 0, and that `AuditLog` has no project column. A cursor would miss changes silently.
4. **Access**: done. The searcher filters candidates with `VisibleProjectIds` and revalidates each hit with `IsItemLive`.
5. **Retrieval**: done (exact cosine, FTS5 words and trigram, RRF with `k = 60`). The measurement on a real notebook copy is an owner action and is recorded in the stage 2 document.
6. **Hosts**: done in stage 3. The `search_semantic` MCP tool and the Desktop Search dialog use `unit_SemanticSearchService`. See `docs/search-stage-3.md`.
7. **Installer**: done in stage 3. The installer is Win64 only. It does not contain the model or ONNX Runtime; they are downloaded and verified against `ELN.Search/search-artifacts.json`.
8. **File text**: done in stage 4 with own headless extractors (no viewer plugins); see `docs/search-stage-4.md`.
