# Semantic Search Stage 6: Context, Structured Filters, Reranker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each passage compact object context for the embedder, add explicit structured filters (folder, item type, level, action type, date, numeric value with units) to semantic search, and add the cross-encoder reranker if it still wins on the final pipeline.

**Architecture:** Three phases in this order, because each later phase is measured on the result of the earlier one. Phase A changes the embedding input only (context is not stored in the FTS text). Phase B resolves all filters in `ELN.Model` into one allowed item set, which `ELN.Search` applies before ranking (vector, words and trigram lists). Phase C starts with a gate: the reranker study runs again on the Phase A pipeline with a fresh held-out set, and the owner rules on the mMARCO training-data terms; only then is the reranker built.

**Tech Stack:** Delphi 13 Win64, stage 1-5 units, TMS Aurelius, DUnitX, ONNX Runtime 1.31.1, Python reference venv (study only).

**Spec:** Project brief `D:\MultilayerLab\Projects\ELN-RAG\Plans\eln-search-project-brief.md` (sections A "compact object context", B "Structured filtering", "Numerical comparisons use typed values and canonical-unit conversion", "Guessed constraints must not silently become mandatory filters"). Prior stages: `docs/search-index-stage-2.md`, `docs/search-stage-3.md`, `docs/search-stage-4.md`, `docs/search-stage-5.md`, `docs/search-stage-5-reranker.md`. Research notes: `local://stage6-scout-context.md`, `local://stage6-scout-filters.md`, `local://stage6-scout-rerank-portability.md` (session artifacts; facts are copied into this plan where needed).

## Global Constraints

- Every stage 5 constraint stays: no score is a probability; no fixed relevance threshold; access gate = `VisibleProjectIds` plus the live check; `ELN.Search` free of Aurelius entities, `ELN.Model`, VCL and plugin units; Win64 build; notebook never written; synthetic data only (owner decisions 2026-10-29: synthetic only, no notebook copy).
- **Portability (new):** the next stage ports search to a Linux Docker container on the NAS. New code in `ELN.Search` and `ELN.Model` uses no `Winapi.*`, no VCL, no Windows paths (use `TPath.Combine`), no COM. Do not port existing Windows code in this stage.
- Filters are explicit parameters only. Nothing parses a filter out of the query text. A filter never widens access: the allowed item set is always a subset of the items in `VisibleProjectIds`. An unknown or invisible folder, value type or unit gives the same error text as a missing one.
- Evaluation: tuning on `eval-dev.json`; decisions on a new `eval-heldout-2.json` (the stage 5 held-out file was read 12 times and is now a regression set only). Decision rule unchanged: held-out nDCG@10 rises, R@10 does not drop, better-minus-worse queries >= 3, Irr@5 does not rise.
- No new runtime dependency besides the reranker model files. Python only in `tools/search-reference/`.
- Comments denied by default; CRLF + UTF-8 BOM for new `.pas`/`.dpr`/`.dfm`; keep the encoding of edited files; docs and Help in ASD-STE100.
- Feature branch `search-stage-6`; local commits per task; no push and no Commercial change without the owner.

## Review Focus

1. **Filter leaks a hidden project** - a folder id, item type or value constraint that only matches items in an invisible project returns no group and the "not found" text. Test in Task 4.
2. **Filter starves the result** - a strict filter with matches outside the top 50 candidates still returns them (pre-filter, not post-filter). Test in Task 3.
3. **Unit mismatch** - "hardness > 10 GPa" against a type stored in MPa converts the threshold; a cross-dimension unit (GPa against a length type) is an error, not an empty result. Test in Task 4.
4. **Rename storm** - renaming a project re-embeds only that project's passages and the sync stays cancelable. Test in Task 2.
5. **Reranker missing or slow** - without the reranker files, or past its time budget, search returns the hybrid order and says so; the Desktop window does not freeze. Tests in Task 9.

---

## Phase A: context

### Task 1: Evaluation corpus v2 and a fresh held-out set

**Files:**
- Modify: `ELN.Community.Tests/Fixtures/Search/eval-corpus.json` (add `folders` [id, project, parent, title]; per item `folder`, `level` (Proc/Item/Action/Folder), `type`, `action_type`, `parent`)
- Modify: `ELN.Community.Tests/Fixtures/Search/eval-dev.json` (add ~10 queries of kind `context`)
- Create: `ELN.Community.Tests/Fixtures/Search/eval-heldout-2.json` (~40 queries, all kinds incl. `context`, no overlap of need or grade-2 items with dev or the old held-out)
- Modify: `ELN.Community.Tests/SearchHarness.dpr` (eval provider reads the new fields; `--eval` accepts `eval-heldout-2.json`)

**Interfaces:**
- Produces: corpus fields above; query kind `context` = the answer needs object context that is not in the matched passage (e.g. "XRR result of sample MS-0417" where the code is only in the item title and the curve is described in a file passage; "annealing steps in the Mo/Si deposition folder").

- [ ] Step 1: Extend the corpus. Every item gets a folder (2-level nesting in at least two projects), level and type; Action items get a parent Proc. Existing item ids, texts and judgments do not change.
- [ ] Step 2: Write the `context` queries and `eval-heldout-2.json`; judge on item text and the new fields before any run; run the Task 1 overlap check of stage 5 against dev and `eval-heldout.json`.
- [ ] Step 3: Harness parity: the eval provider sets the new fields; with no context feature yet, dev numbers for the old queries are unchanged (diff the per-query output).
- [ ] Step 4: Record the baseline (dev, `eval-heldout-2.json`) in `docs/search-stage-6.md`. Commit.

### Task 2: Context in the embedding input

**Files:**
- Create: `ELN.Search/unit_PassageContext.pas`
- Modify: `ELN.Search/unit_SearchPassages.pas` (`TSearchPassage.Context: string`; hash), `ELN.Search/unit_SearchIndexer.pas` and `ELN.Search/unit_TextEmbedder.pas` call site (embed input), `ELN.Search/unit_FileTextStage.pas` (file-text passages get the item's context)
- Modify: `ELN.Model/unit_SearchDocumentProvider.pas` (load project titles, folders, item level/type/action type/parent title)
- Modify: `ELN.Community.Tests/SearchHarness.dpr` (same builder); tests in `ELN.Community.Tests/test_SearchIndex.pas`

**Interfaces:**
- Produces: `TPassageContextParts = record ProjectTitle: string; FolderPath: TArray<string>; ItemTitle, ItemKind, ParentTitle, ActionType: string; end;` and `function BuildPassageContext(const Parts: TPassageContextParts; Field: TPassageField): string;` in `unit_PassageContext`. `TSearchPassage.ContentHash` = SHA-256 of `Context + #10 + Text`. Embed input = `'passage: ' + Context + #10 + Text` when `Context <> ''`. FTS text and `passages.text` stay the chunk text only (no project-title noise in BM25).
- Consumes: stage 5 `THybridSearchOptions`, harness `--eval`.

- [ ] Step 1: Failing tests: `BuildPassageContext` output for a description passage (`Project > Folder > Sub | Item: <title> | Specimen | Parent: <title>`); the item title is left out for `pfItemTitle` passages; each part is cut to 80 characters and the whole context to 240 characters; empty parts are omitted; a project rename changes the hash of that project's passages only; FTS `MatchWords` for a word that is only in the project title does not hit the passage.
- [ ] Step 2: Implement. Folder path walks `TFolder.ParentFolderID` to the top; first verify how `TFolder` links to its project (no `ProjectID` column was seen in `unit_Project.pas:138-199`) and record the answer in the report.
- [ ] Step 3: Measure on dev with the harness, three variants behind a harness flag `--context none|item|full` (`item` = project + item title; `full` = all parts). Held-out (`eval-heldout-2.json`) once for the dev-best variant. Adopt it as the provider default only if it passes the decision rule against `none`; otherwise the default is `none` and the code stays for the reranker study input. Record re-embed time for one project rename on the corpus.
- [ ] Step 4: Run `SearchIndexTests`, `SearchTests`, `DesktopRegressionTests`. Commit.

## Phase B: structured filters

### Task 3: Allowed item set in `ELN.Search`

**Files:**
- Modify: `ELN.Search/unit_HybridSearch.pas` (`THybridSearchOptions.ItemFilter`), `ELN.Search/unit_VectorSearch.pas` (item allow-set), `ELN.Search/unit_SearchIndexStore.pas` (`MatchWords`/`MatchTrigrams` item clause; `CREATE INDEX IF NOT EXISTS passages_item ON passages(item_id)`)
- Test: `ELN.Community.Tests/test_SearchIndex.pas`

**Interfaces:**
- Produces: `TItemFilter = record Active: Boolean; ItemIds: TArray<Integer>; end;` (`Active = False` means no restriction; `Active = True` with no ids returns no group), field `ItemFilter` in `THybridSearchOptions` (default inactive). `TExactVectorIndex.Add(SourceId, Scope: string; ItemId: Integer; Vector)` and `Search(Query, TopK, EligibleScopes, const AllowedItems: TItemFilter)`. SQL clause `AND p.item_id IN (SELECT value FROM json_each(?n))` only when active.
- Ruling: the new SQL index is additive and created with `IF NOT EXISTS`; it does not raise `SearchIndexSchemaVersion`.

- [ ] Step 1: Failing tests: an allowed item whose passages rank below 50 in all three lists without the filter is returned with the filter; `Active` with an empty set returns nil; an allowed item in an invisible project is not returned; the inactive filter gives byte-identical results to stage 5 (`--compare` on dev).
- [ ] Step 2: Implement; the filter applies inside each list before its `CandidatesPerList` cut.
- [ ] Step 3: Run `SearchIndexTests`, `SearchTests`. Commit.

### Task 4: Filter resolution in `ELN.Model`

**Files:**
- Create: `ELN.Model/unit_SemanticSearchFilter.pas`
- Test: `ELN.Community.Tests/test_SemanticSearchFilter.pas` (register in `SearchIndexTests.dpr` or the suite that builds `ELN.Model` units with a synthetic notebook; follow `ELN.Community.Tests/AGENTS.md`)

**Interfaces:**
- Produces:
  - `TValueConstraint = record ValueType: string; Min, Max: Nullable<Double>; UnitSymbol: string; RecType: string; end;` (`ValueType` = title or symbol, as `query_values`; `RecType` '' = any)
  - `TSemanticSearchFilter = record FolderId: Integer; ItemTypes: TArray<string>; Levels: TArray<string>; ActionTypeId: Integer; DateField: (sdfNone, sdfCreated, sdfModified); DateFrom, DateTo: TDateTime; Values: TArray<TValueConstraint>; function IsEmpty: Boolean; end;`
  - `function ResolveSemanticFilter(Manager: TObjectManager; const VisibleProjectIds: TArray<Integer>; const Filter: TSemanticSearchFilter): TItemFilter;` raises `ESemanticFilterError` with a user-facing message.
- Rules: `FolderId` includes its subfolders and must belong to a visible project; dates are item dates in UTC, `DateTo` inclusive to the end of that day; several value constraints combine with AND, each satisfied by at least one `TValue` of the item; the threshold is converted to the value type's `Units` with `TUnitConverter.TryFactor`; a unit of another dimension or an unknown unit raises; offset units (°C) convert with `TUnitConverter.Convert`, not a factor. `IsEmpty` filter returns an inactive `TItemFilter` (no ORM query).

- [ ] Step 1: Confirm with a test that `TValue.Value` is stored in the value type's `Units` (stage 5 scout could not confirm); if not, stop and report.
- [ ] Step 2: Failing tests on a synthetic notebook: folder subtree; folder in an invisible project gives the not-found error; item type and level; action type; created and modified date ranges with the inclusive end day; "Hardness > 10 GPa" against a type in MPa matches 12000 MPa and not 9000 MPa; GPa against a length type raises; °C threshold against a K type; two constraints AND; empty filter gives an inactive filter.
- [ ] Step 3: Implement with Aurelius criteria, restricted to `VisibleProjectIds` in the query itself.
- [ ] Step 4: Run the suite. Commit.

### Task 5: Filters in the hosts

**Files:**
- Modify: `ELN.MCPServer/unit_ToolsNavigation.pas` (`search_semantic` schema and handler)
- Modify: `ELN.Desktop/Dialogs/Search/dlg_Search.pas` + `.dfm` (filter row: project, item type, created date from/to; DFM controls only, `AlignWithMargins`)
- Modify: `ELN.Search/unit_SemanticSearchService.pas` (pass options through)
- Modify: Help `Search.html`, `MCP.html`; `docs/search-stage-6.md`
- Test: `ELN.Community.Tests/test_SemanticSearchTool.pas`

**Interfaces:**
- MCP parameters (all optional): `folder_id`, `item_types` (array), `levels` (array), `action_type_id`, `date_field` (`created`|`modified`), `date_from`, `date_to` (ISO 8601 date), `values` (array of `{value_type, min, max, unit, rec_type}`). Output adds `filters_applied` (echo of the resolved filter) so an agent sees what was enforced.
- Ruling: the Desktop dialog gets project, item type and created-date filters; value filters are MCP-only in this stage (they need a value-type picker with units, which is a separate UI design).

- [ ] Step 1: Failing tool tests: each parameter narrows the groups; an invalid unit returns the `ESemanticFilterError` text; `filters_applied` echoes the converted threshold; no parameter gives the stage 5 result.
- [ ] Step 2: Implement MCP, then Desktop. Desktop filter controls are disabled when **Search by meaning** is off.
- [ ] Step 3: Help and docs. Run `SearchIndexTests`, `DesktopRegressionTests`, Help index check. Commit.

## Phase C: reranker

### Task 6: Reranker gate (study re-run and owner decision)

**Files:**
- Modify: `tools/search-reference/rerank_study.py` (read `eval-heldout-2.json`), `docs/search-stage-5-reranker.md` → new section or `docs/search-stage-6-reranker.md`

- [ ] Step 1: Export candidates with the stage 6 default (Phase A result, weights 1:1:1) and re-run the study for `mmarco-mMiniLMv2` int8 `rrf2@20` and depth 10/20 on dev; held-out-2 once for the dev-best.
- [ ] Step 2: Record the result and the decision rule outcome.
- [ ] Step 3: **Stop and ask the owner** with two questions: (a) the rule result, (b) the mMARCO training-data terms (MS MARCO is published for non-commercial research use; the model card says Apache-2.0), which matter for the Commercial edition. Tasks 7-9 run only on a "yes" to both. A "no" ends Phase C with the doc as the result.

### Task 7: Manifest v3 with optional models and one optional rule

**Files:**
- Modify: `ELN.Search/search-artifacts.json` (`ManifestVersion` 3; `Models[]` with `Role` (`embedder`|`reranker`) and `Optional`), `ELN.Search/unit_SearchArtifacts.pas`, `ELN.Search/unit_SearchArtifactInstall.pas`, `tools/Get-SearchArtifacts.ps1`, `ELN.Desktop/Dialogs/Search/dlg_SearchSetup.pas` + `.dfm`
- Test: `ELN.Community.Tests/test_SearchArtifacts.pas`

**Interfaces:**
- Produces: `function SearchArtifactsReadyAt(const Root: string): Boolean;` unchanged meaning (required parts only); new `function OptionalPartReady(const Manifest: TSearchArtifactManifest; const Root, Name: string): Boolean;`. One rule everywhere: required parts gate search; optional parts (PDFium, reranker) are downloaded by **Download and Install**, verified, shown per row in the dialog, and never make the dialog say "Not installed" when the required parts are ready. This also fixes the stage 4 inconsistency (dialog and installer treat PDFium as required).
- Reranker files: `onnx/model_quint8_avx2.onnx` (118,620,016 bytes) and its config, folder separate from e5; the e5 `tokenizer.json` is reused (study: same sentencepiece model, identical ids on 534 texts).

- [ ] Step 1: Failing tests: v3 manifest parses; an install with e5 and ORT but no PDFium and no reranker is "ready (optional parts missing)"; the installer downloads optional parts and verifies hashes; a v2 manifest is rejected with a clear message (the manifest ships with the program, so no migration).
- [ ] Step 2: Implement library, script, dialog rows (state per part, license shown from the manifest `License`).
- [ ] Step 3: Run `SearchIndexTests`, `DesktopRegressionTests`. Commit.

### Task 8: Pair encoding and the cross-encoder

**Files:**
- Modify: `ELN.Search/unit_UnigramTokenizer.pas` (`EncodePair`)
- Create: `ELN.Search/unit_CrossEncoder.pas`
- Create: `tools/search-reference/generate_pair_fixtures.py`, `ELN.Community.Tests/Fixtures/Search/pair_reference.json`
- Test: `ELN.Community.Tests/test_SearchEmbedding.pas` (`SearchTests`)

**Interfaces:**
- Produces: `function TUnigramTokenizer.EncodePair(const A, B: string; MaxTokens: Integer): TArray<Int64>;` = `[Bos] + A + [Eos, Eos] + B + [Eos]`, truncating B only (A is cut to 64 tokens first if needed). `ICrossEncoder = interface function Score(const Query: string; const Passages: TArray<string>; const Cancelled: TCancelCheck): TArray<Single>; function Identity: string; end;` and `function CreateCrossEncoder(const ArtifactRoot: string): ICrossEncoder;` (validates inputs `input_ids`, `attention_mask` int64 and output `logits` float `[batch,1]`; batch 20; checks `Cancelled` between batches; own `TOrtSession`).

- [ ] Step 1: Generate `pair_reference.json` with HF tokenizers (ids for 40 pairs incl. Russian, truncation cases) and reference logits from Python ORT for 10 pairs.
- [ ] Step 2: Failing tests: pair ids equal the reference; truncation keeps the query; logits within 1e-4 of the reference; a model with a wrong output shape is refused; cancel stops between batches.
- [ ] Step 3: Implement. Run `SearchTests`. Commit.

### Task 9: Reranking in search, hosts, docs

**Files:**
- Modify: `ELN.Search/unit_HybridSearch.pas` (candidate depth, rerank fusion), `ELN.Search/unit_SemanticSearchService.pas` (reranker load, lock, budget), `ELN.Desktop/Dialogs/Search/dlg_Search.pas` (search off the UI thread), `ELN.MCPServer/unit_ToolsNavigation.pas` (`reranked` flag in output), Help `Search.html`, `MCP.html`, `docs/search-stage-6.md`
- Test: `ELN.Community.Tests/test_SemanticSearchService.pas`, `test_SemanticSearchTool.pas`

**Interfaces:**
- Produces: `THybridSearchOptions.RerankDepth: Integer` (0 = off, default 20 when a reranker is loaded) and fusion `1/(60+hybrid rank) + 2/(60+reranker rank)` over the top `RerankDepth` groups (study setting `rrf2@20`); groups past the depth keep their order after them. Reranker input per group = context + best passage full text (`FStore.PassageText`), max over its kept passages.
- Ruling: the service collects candidate texts under its lock, releases it, and runs the cross-encoder under its own lock, so a sync is not blocked by a rerank. Budget 1500 ms per query; past it, or on any reranker error, the hybrid order is returned with `reranked = false`. Desktop runs search on a worker thread with "Searching..." status and the existing `TThread.Queue` gate.
- A setting **Rerank results** (default on when installed) in the Search dialog.

- [ ] Step 1: Failing tests: with a fake `ICrossEncoder` that reverses order, the top 20 reorder by the fusion formula and groups 21+ keep their order; no reranker gives the stage 6 hybrid result and `reranked = false`; a slow fake past the budget returns hybrid order; a sync started during a rerank finishes without waiting for it; access: a reranked list contains only groups that passed the live check.
- [ ] Step 2: Implement service, searcher, MCP, Desktop.
- [ ] Step 3: Help/docs; harness `--eval` with the real reranker on dev and held-out-2 equals the Task 6 study numbers within 0.01 nDCG@10.
- [ ] Step 4: Full verification: `SearchTests`, `SearchIndexTests`, `StorageTests`, `DesktopRegressionTests`, Help index check; build `CommunityDesktop`, `CommunityMCP`. Smoke on a synthetic temp notebook (stage 5 ruling R4): one filtered query and one reranked query via MCP, one via Desktop if launched by the owner. Commit.

## Out of scope

- Linux port (next stage). This stage only avoids new Windows dependencies.
- Parsing filters from free text; a query language.
- Value-filter UI in the Desktop dialog.
- OCR, old binary Office formats, image or curve similarity, generated answers.
