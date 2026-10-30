# Semantic Search Stage 5: Evaluation, Grouped Results, Evidence-Based Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure the quality of the search (words only, vector only, hybrid), group the hits per item with context, and change a ranking parameter only when the measurement shows a gain on queries that were not used for tuning.

**Architecture:** Stage 5 is the "evidence-based improvements" step of the project brief (section "Staged delivery", item 4). Stages 1-4 gave the pipeline: `THybridSearcher` fuses three lists (`hsVector`, `hsWords`, `hsTrigram`) with RRF (`RrfK = 60`, `CandidatesPerList = 50`), cuts the fused list to `TopK` passages and returns one `THybridHit` per passage. The per-list ranks are folded into the fused score in `AddRank` and are not kept. There is no metric code. The harness corpus mode (`RunQueries`) is vector only (`TExactVectorIndex` over 24 single-text documents, 14 queries, hit in top k); the hybrid path runs only in `--notebook` mode. Stage 5 adds (1) a structured evaluation corpus and a metric runner on the real hybrid path, (2) item-level grouping inside the searcher, (3) tuning of the fusion constants, and (4) a gated reranker study. No new HTTP service, no generative model.

**Tech Stack:** Delphi 13 Win64, stage 1-4 units, DUnitX, `SearchHarness.dpr`, synthetic fixtures in `ELN.Community.Tests/Fixtures/Search`.

**Spec:** `docs/search-index-stage-2.md` (passages, RRF), `docs/search-stage-3.md` (service, MCP tool), `docs/search-stage-4.md` (file text). Brief: `D:\MultilayerLab\Projects\ELN-RAG\Plans\eln-search-project-brief.md` (sections "Useful retrieval results", "Evaluation").

## Global Constraints

- Do not call a score a probability. Do not add a fixed relevance threshold (project brief; stage 1 measurement: out-of-scope queries score 0.74-0.76).
- Query sets: a **dev** set for tuning and a separate **held-out** set that is read only for the final comparison. A constant changes only when the held-out result agrees with the dev result. A tiny synthetic corpus is not a representative benchmark; every report says so.
- Access control does not change. `VisibleProjectIds` and the live visibility check in `THybridSearcher.Search` stay the only gate. Grouping and context run after the gate and add no field of a hidden item.
- The index schema does not change unless a task says so. A schema change raises the schema version (the store then makes the tables again).
- The notebook is never written. A real notebook is used only as an owner-approved **copy**.
- `ELN.Search` stays free of Aurelius entities, `ELN.Model`, VCL and plugin units. `ISearchDocumentSource` (`unit_SearchPassages.pas`) does not change. Item titles and project paths are resolved by the hosts, as the Desktop dialog does today (`Model.Manager.Find<TItem>`, `Model.Search.BuildProjectPath`).
- Search stays Win64 only. Do not touch APS-ELN-Commercial.
- Comments denied by default; CRLF + UTF-8 BOM for `.pas`/`.dpr`/`.dfm`; docs and Help in ASD-STE100.
- Local commits per task on a feature branch `search-stage-5`; no push without the user's approval.

## Review Focus

1. **A query set that cannot discriminate** (words-only already at the ceiling, or the held-out set was used for tuning) - dev and held-out files are separate, and the baseline report shows per-kind results for each mode. If words-only reaches Recall@10 = 1.0 on a kind, that kind does not count for tuning.
2. **Grouping hides evidence** - a query that needs two passages of one item still returns both; the group score does not drop an item that only the words list found.
3. **Restricted projects** - the group and its context never name an item of a project outside `VisibleProjectIds`; an item that became invisible between index and query is removed before grouping.
4. **Tuned constants overfit** - each changed constant has a table row for dev and held-out, before and after.
5. **Reranker cost** - the added model size, load time, per-query latency and memory are measured before any decision.

---

### Task 1: Evaluation corpus, metrics and runner

**Files:**
- Create: `ELN.Community.Tests/Fixtures/Search/eval-corpus.json` (about 150 synthetic items in 4-5 projects; each item has title, description, tags and optional file text, so the passages have different `TPassageField` values like a real notebook)
- Create: `ELN.Community.Tests/Fixtures/Search/eval-dev.json`, `eval-heldout.json` (relevance on item ids, grade 1 or 2)
- Create: `ELN.Search/unit_SearchMetrics.pas` (Recall@k, MRR, nDCG@k on ranked item ids; pure functions)
- Create: `ELN.Community.Tests/test_SearchMetrics.pas`; register in `SearchIndexTests.dpr`
- Modify: `ELN.Community.Tests/SearchHarness.dpr` (option `--eval DEV_OR_HELDOUT_FILE` with `--eval-corpus FILE`; the corpus goes through `TPassageSnapshotSource` into a temporary `TSearchIndexStore`, and the queries run through `THybridSearcher`; output table)
- Modify: `ELN.Search/unit_HybridSearch.pas` (a list-set option on `Search`: any subset of `hsVector`, `hsWords`, `hsTrigram`; the default is all three and gives the same result as today)

The existing `corpus.json` and `RunQueries` stay as the stage 1 embedder smoke test.

**Query kinds** (from the brief): exact code or file name, paraphrase, Russian and English, cross-language (Russian query, English item and the reverse), a negated query, proposed versus completed work, a hard negative. Restricted projects and stale sources are correctness, not ranking; they stay in the existing `test_SearchIndex` tests and are not in the query sets.

- [ ] Step 1: Write failing tests for the metrics: hand-computed Recall@k, MRR and nDCG@k; a query with no relevant item (excluded from the mean, counted in the report); k larger than the list; graded relevance.
- [ ] Step 2: Implement `unit_SearchMetrics`.
- [ ] Step 3: Write the corpus and the two query files. Dev about 40 queries, held-out about 40 queries, no query and no paraphrase of a query in both. Relevance is judged on the item text before any run.
- [ ] Step 4: Add the list-set option and the runner. The runner prints, per mode (words, trigram, vector, hybrid) and per query kind: Recall@5, Recall@10, MRR, nDCG@10, mean and p95 latency. Item rank = rank of the first passage of that item.
- [ ] Step 5: Run the baseline on dev and held-out and keep the numbers in `docs/search-stage-5.md`. Commit.

### Task 2: Item-level result groups with context

**Files:**
- Modify: `ELN.Search/unit_HybridSearch.pas` (`Search` returns `TArray<THybridGroup>`: ItemId, ProjectId, FileId of the best passage, best score, sources, at most 3 `THybridHit` passages)
- Modify: `ELN.Search/unit_SemanticSearchService.pas` (`Search` passes the groups through; no second method)
- Modify: `ELN.MCPServer/unit_ToolsNavigation.pas` (`search_semantic` returns `groups`; each group has `item_id`, `item_title`, `project_id`, `project_path`, `score`, and `passages` with `field`, `file_id`, `snippet`, `score`)
- Modify: `ELN.Desktop/Dialogs/Search/dlg_Search.pas` (one row per group; the best passage gives the field and the snippet)
- Modify: `ELN.Community.Tests/SearchHarness.dpr` (`--notebook` output and the Task 1 runner use the groups)
- Modify tests: `test_SearchIndex.pas`, `test_SemanticSearchService.pas`, `test_SemanticSearchTool.pas`

**Rules:** the grouping runs inside `THybridSearcher.Search`, after the live visibility check and **before** the cut to `TopK`; `TopK` counts groups. Today the cut is at passage level, so grouping after it would return fewer than `TopK` items. Group score = best passage score. A group keeps at most 3 passages, in fused order. Group order = best score, then `ItemId`. The `search_semantic` result changes in one step (clean cutover, no flat-result switch); the tool description says so.

- [ ] Step 1: Failing tests: two passages of one item give one group with both passages; `top_k` = 2 with three passages of item A ranked first gives two groups (A and the next item); an item that becomes invisible is not in any group; an item found only by the words list keeps its group.
- [ ] Step 2: Implement the grouping in `THybridSearcher` and update every caller (`unit_SemanticSearchService`, `dlg_Search`, `unit_ToolsNavigation`, `SearchHarness`).
- [ ] Step 3: MCP: resolve `item_title` and `project_path` in the tool, as other navigation tools do. Update the tool description and the tool tests.
- [ ] Step 4: Desktop: grouped rows. Navigation does not change (`btnGoTo` and double click go to project, folder and item).
- [ ] Step 5: Re-run the Task 1 baseline; item-level metrics must not change, because item rank already used the first passage. Run `SearchIndexTests`, `DesktopRegressionTests`. Commit.

### Task 3: Tune with evidence

**Files:**
- Modify: `ELN.Search/unit_HybridSearch.pas` (`RrfK`, `CandidatesPerList`; optional per-list and per-field weights)
- Modify: `docs/search-stage-5.md` (decision table)

Candidates to test, in this order. Each one is one change, one dev run, one held-out run:

1. `RrfK` 20, 60, 100.
2. `CandidatesPerList` 30, 50, 100.
3. List weights (words : trigram : vector). The trigram list exists for identifiers and partial words, so test lowering its weight when a words hit exists.
4. Field weights (title and tags above file text). Stage 4 added `pfFileText`, which can outrank a short title. The Task 1 corpus has these fields, so this can be measured.
5. Query kind handling: a query that looks like an identifier (digits, hyphens, no spaces) gets a higher words weight. The rule must come from a measured gain, not from a guess.

- [ ] Step 1: Make the constants parameters of `THybridSearcher` with the current values as defaults, so the runner can sweep them without a rebuild. No default changes in this step.
- [ ] Step 2: Sweep on dev. Choose the best by nDCG@10, then check Recall@10 does not drop.
- [ ] Step 3: Run the held-out set once per chosen setting. Ranking is deterministic, so repeated runs give the same numbers; compare per query instead. Change a default only when held-out nDCG@10 rises, Recall@10 does not drop, and the number of held-out queries that get better is at least 3 more than the number that get worse. Otherwise keep the default and write down why.
- [ ] Step 4: Record the table. Commit.

### Task 4: Reranker study (decision gate, no code in `master`)

**Files:**
- Create: `docs/search-stage-5-reranker.md` (result of the study)
- The study runs first in Python in the existing reference venv (`%LOCALAPPDATA%\Temp\eln-ref-venv`) on the top 20 groups exported by the Task 1 runner (`--export-candidates FILE`). No reranker code goes into Delphi in this stage. The export option stays only if Task 4 runs.

**Question:** does a cross-encoder reranker over the top 20 of the hybrid list raise nDCG@10 on the held-out set enough to justify its cost?

- [ ] Step 1: Pick one multilingual cross-encoder with a license that allows redistribution as a download (check the license text; record the size). Note the tokenizer: a cross-encoder needs the pair input format, which `unit_UnigramTokenizer` does not have yet; record what a Delphi port would need.
- [ ] Step 2: Measure in Python: model size, load time, memory, latency for 20 pairs on CPU, held-out nDCG@10 and Recall@10 against the Task 3 result, with the same per-query rule as Task 3.
- [ ] Step 3: Write the decision. If the gain is small or the cost is high, stop here and state "not adopted". Adoption needs the owner's decision and becomes a separate plan (manifest entry, setup dialog, service integration).

### Task 5: Hosts, Help and documentation

**Files:**
- Modify: `ELN.Desktop/Assets/Runtime/Help/Search.html`, `MCP.html` (grouped results, the new MCP fields)
- Create: `docs/search-stage-5.md` (metrics, query sets, baseline, tuning table, group shape)
- Modify: `README.md` (test targets and harness options), `docs/search-stage-3.md` (tool fields)
- Run: `pwsh -NoProfile -File tools/Build-HelpIndex.ps1 -HelpRoot ELN.Desktop/Assets/Runtime/Help -FixIds`, `tools/Test-BuildHelpIndex.ps1`

- [ ] Step 1: Write the docs from the measured numbers. Say plainly that the corpus is synthetic and small.
- [ ] Step 2: Full verification: `SearchTests`, `SearchIndexTests`, `StorageTests`, `DesktopRegressionTests`, Help index check. Build `CommunityDesktop` and `CommunityMCP`.
- [ ] Step 3: Smoke on a synthetic notebook in a temporary folder (no real notebook copy is approved): build it from the Task 1 corpus, run the harness `--notebook` with a few queries, and run `search_semantic` through the MCP server on the same notebook. Report latency and one grouped result.
- [ ] Step 4: Final review, then ask the owner before merge and push.

## Out of scope

- OCR, old binary Office files, viewer metadata JSON (stage 4 list).
- Image or curve similarity, generative answers, an approximate vector index.
- Commercial: the pin bump and the `ELN.Search` unit path there need a separate authorization.
- A fixed relevance threshold.

## Owner decisions (2026-10-29)

1. Query sets and the evaluation corpus are fully synthetic. No real project terms.
2. Task 4 (reranker study) stays in stage 5.
3. No notebook copy is approved. All evaluation and smoke tests use synthetic data.
