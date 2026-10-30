# Semantic search, stage 5: evaluation

Stage 5 adds a way to measure search quality. It has a small evaluation corpus, two query files, metric functions and a runner in `SearchHarness`. Later tasks of stage 5 (item grouping, ranking changes) use these numbers to decide what to change. See `docs/search-index-stage-2.md` for the index and `docs/search-stage-4.md` for file text.

## Read this first

The corpus and the queries are synthetic. All items, sample codes, file names and numbers are invented. No real project, person or measurement is in them. The corpus is small (149 items, 481 passages). The query files are small (48 queries each, 44 of them with a relevant item). This is not a benchmark. It cannot say how good the search is on a real notebook. It can only show that a change moves the numbers in the same direction on two separate query sets. A difference of a few points on 44 queries is noise.

## Files

| File | Content |
| --- | --- |
| `ELN.Community.Tests/Fixtures/Search/eval-corpus.json` | 5 projects, 149 items. Each item has a title, a description and tags. 17 items also have one file with a file name and a text. |
| `ELN.Community.Tests/Fixtures/Search/eval-dev.json` | 48 queries for development and first checks. |
| `ELN.Community.Tests/Fixtures/Search/eval-heldout.json` | 48 other queries. Do not tune on them. Look at them only to confirm a change that was chosen on the dev queries. |
| `ELN.Search/unit_SearchMetrics.pas` | Pure metric functions. |
| `ELN.Community.Tests/test_SearchMetrics.pas` | Tests of the metric functions (hand-computed values). |

The existing `corpus.json` and the `RunQueries` mode of `SearchHarness` are not changed. They stay as the stage 1 smoke test of the embedder.

The text is a mix of English and Russian (about 40 percent Russian) on thin-film and X-ray optics topics. The items give the passages different fields (`pfItemTitle`, `pfItemDescription`, `pfItemTags`, `pfFileName`, `pfFileText`), like a real notebook. Every item belongs to a project. Item ids and project ids are integers. They are the same numbers as in the passage keys.

Relevance was written together with the item text, before any search run. Each judged query lists the relevant items with grade 2 (the item answers the query) or grade 1 (the item is related). Restricted projects and stale sources are correctness rules, not ranking rules. They stay in the tests of `test_SearchIndex` and are not in the query sets.

## Query kinds

| Kind | What it tests |
| --- | --- |
| `exact` | A sample code, a device code or a file name. |
| `paraphrase` | An English query that uses other words than the item. |
| `russian` | A Russian query. |
| `cross-language` | A Russian query for an English item, or an English query for a Russian item. The relevant item has no twin in the query language. |
| `negated` | A query with "not", "without" or "no". The search does not understand negation. The relevant items say that something did not happen. |
| `status` | Proposed work against completed work. |
| `short` | A query of 2 characters, for example an element symbol or a unit. |
| `mixed` | A rare exact word and other words that are not next to each other in the item text. |
| `hard-negative` | A query about a topic that is not in the corpus. No item is relevant. The query file lists `irrelevant` items, which share words with the query. |

## Metrics

The runner uses the item rank, not the passage rank. It asks the searcher for up to 150 item groups (3 times `CandidatesPerList`, more than the whole fused list can give). The rank of an item is the position of its group. The group of an item is placed by its best passage, which is the first passage of the item in the fused list. Thus the item metrics are the same as before the groups were added, unless two items tie on score.

- `R@5`, `R@10`: the share of the relevant items (grade 1 or 2) that are in the first 5 or 10 items.
- `MRR`: the mean of 1 / (rank of the first relevant item). It is 0 if no relevant item is ranked.
- `nDCG@10`: gain is 2^grade - 1, discount is 1 / log2(rank + 1). The ideal order puts the highest grades first.
- `Irr@5`: for queries that list `irrelevant` items, the count of those items in the first 5. The count is summed over the queries. Lower is better. These queries have no relevant item. They are not in the means of the other columns.
- `queries` is the number of queries. `judged` is the number of queries that have a relevant item and are in the means.
- `mean ms`, `p95 ms`: latency of one search call, including the query embedding for the `vector` and `hybrid` modes. A warm-up search is not counted.

A query without a relevant item gives no value for `R@k`, `MRR` and `nDCG@k`. The mean skips it. The run header says how many such queries there are.

## Modes

`THybridSearcher.Search` has a parameter `Options: THybridSearchOptions`. `Options.Lists` is the set of lists that are fused (`hsVector`, `hsWords`, `hsTrigram`). `THybridSearchOptions.Default` uses all three lists. The record also holds the tuning values (see "Tuning"). The runner calls the searcher four times for each query:

| Mode | Lists |
| --- | --- |
| `words` | `hsWords` |
| `trigram` | `hsTrigram` |
| `vector` | `hsVector` |
| `hybrid` | all three, with the default tuning |

A list that is not in the set is not run at all. The fusion is weighted RRF with `RrfK`. With one list the order is the order of that list.

## Item groups

`THybridSearcher.Search` returns `TArray<THybridGroup>`, one group for each item. The grouping runs after the live visibility check and before the cut to `TopK`. Thus `TopK` counts groups, not passages.

- The group score is the score of the best passage.
- A group keeps at most 3 passages (`MaxGroupPassages`), in fused order. `Sources` is the union of the sources of all passages of the item in the fused list. `FileId` is the file id of the best passage.
- Groups are in the order of best score, then the weight-0 rank of the best passage (see "Tuning"; with the default weights no list has weight 0), then `ItemId`.
- An item that is not live or not in a visible project has no group.

The MCP tool `search_semantic` returns `groups` instead of `hits`. Each group has `item_id`, `item_title`, `project_id`, `project_path`, `score`, `sources` and `passages` (`field`, `file_id`, `snippet`, `score`). The Desktop dialog shows one row for each group. The field and the snippet come from the best passage.

## How to run

The search artifacts must be installed (`%LOCALAPPDATA%\APS-ELN\search-artifacts`). The runner builds a new temporary index store from the corpus, with the real embedder, and deletes it at the end.

```powershell
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchHarness -Configuration Release
_OUT\SearchHarness\Win64\Release\SearchHarness.exe --eval eval-dev.json
_OUT\SearchHarness\Win64\Release\SearchHarness.exe --eval eval-heldout.json
```

`--eval` takes a path or the name of a file in the fixture folder. `--eval-corpus FILE` selects another corpus. The results are the same in Debug and Release. Only the latency changes. The numbers below are from a Release build.

Other `--eval` options make the sweeps in "Tuning" possible without a new build:

| Option | Meaning |
| --- | --- |
| `--modes A,B` | Run only these modes (`words`, `trigram`, `vector`, `hybrid`). |
| `--rrf-k N` | `RrfK` of the fusion. |
| `--candidates N` | `CandidatesPerList`. The runner asks for 3 times this value of item groups. |
| `--list-weight NAME=X` | Weight of a list (`words`, `trigram`, `vector`). Can be repeated. |
| `--field-weight NAME=X` | Weight of a passage field (`ItemTitle`, `ItemDescription`, `ItemTags`, `FileName`, `FileText`, and the other `TPassageField` names without `pf`). Can be repeated. |
| `--per-query FILE` | Write one tab separated line for each mode and query (nDCG@10, R@10, R@5, MRR, Irr@5). |
| `--compare FILE` | Compare each query with a `--per-query` file of an earlier run. The runner prints the number of queries that are better, worse or the same (nDCG@10 changes larger than 0.00001), the same for Irr@5 of the hard-negative queries, and the list of the queries that changed. |
| `--export-candidates FILE` | Write the top 20 item groups of the `hybrid` mode for each query to FILE as JSON: the item id, the group score, up to 3 passages (key, field, text), and the item ids after rank 20. Used by the reranker study (`docs/search-stage-5-reranker.md`). |

## Baseline (before any ranking change)

Machine: AMD Ryzen 9 9950X3D, 32 logical processors, Win64 Release, multilingual-e5-small. The tables use the first 40 queries of each file. The `short` and `mixed` queries were added in the second round of tuning (see "Short and mixed queries").

### Dev queries

```text
Evaluation corpus eval-corpus.json: 149 items in 5 projects, 481 passages embedded in 1.4 s
  pfItemTitle          149
  pfItemDescription    149
  pfItemTags           149
  pfFileName           17
  pfFileText           17
Query file eval-dev.json: 40 queries, 4 without a relevant item (excluded from the means)
Each search returns up to 150 item groups; the item rank is the position of its group.

Mode: words
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   0.958   1.000   1.000    0.998      -      0.1      0.1
paraphrase             8      8   0.573   0.667   0.708    0.629      -      0.4      0.5
russian                6      6   0.611   0.694   0.861    0.762      -      0.2      0.2
cross-language         8      8   0.000   0.000   0.000    0.000      -      0.2      0.5
negated                4      4   0.583   0.792   0.786    0.726      -      0.4      0.5
status                 4      4   0.354   0.500   0.508    0.310      -      0.5      0.6
hard-negative          4      0       -       -       -        -      6      0.3      0.5
all                   40     36   0.493   0.574   0.611    0.548      6      0.3      0.5

Mode: trigram
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   0.958   1.000   1.000    0.998      -      0.2      0.4
paraphrase             8      8   0.000   0.000   0.000    0.000      -      0.2      0.8
russian                6      6   0.000   0.000   0.000    0.000      -      0.2      0.4
cross-language         8      8   0.000   0.000   0.000    0.000      -      0.3      0.8
negated                4      4   0.000   0.000   0.000    0.000      -      0.3      0.3
status                 4      4   0.000   0.000   0.000    0.000      -      0.2      0.3
hard-negative          4      0       -       -       -        -      0      0.2      0.4
all                   40     36   0.160   0.167   0.167    0.166      0      0.2      0.5

Mode: vector
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   0.958   1.000   1.000    0.997      -      4.1      4.6
paraphrase             8      8   0.677   0.677   0.938    0.795      -      4.3      4.7
russian                6      6   0.639   0.694   1.000    0.849      -      4.1      4.7
cross-language         8      8   0.375   0.500   0.321    0.352      -      4.3      4.9
negated                4      4   0.708   0.792   0.750    0.654      -      3.7      4.0
status                 4      4   0.688   0.688   1.000    0.529      -      3.9      4.7
hard-negative          4      0       -       -       -        -      7      4.1      4.6
all                   40     36   0.655   0.708   0.808    0.694      7      4.1      4.7

Mode: hybrid
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   0.958   1.000   1.000    0.998      -      3.8      4.4
paraphrase             8      8   0.646   0.708   0.891    0.767      -      4.9      5.5
russian                6      6   0.694   0.694   0.917    0.804      -      4.2      4.8
cross-language         8      8   0.375   0.375   0.115    0.162      -      5.0      5.6
negated                4      4   0.667   0.792   0.781    0.727      -      4.3      5.1
status                 4      4   0.438   0.771   0.813    0.512      -      4.3      4.6
hard-negative          4      0       -       -       -        -      6      3.9      4.3
all                   40     36   0.625   0.697   0.720    0.644      6      4.4      5.4
```

### Held-out queries

```text
Evaluation corpus eval-corpus.json: 149 items in 5 projects, 481 passages embedded in 1.4 s
  pfItemTitle          149
  pfItemDescription    149
  pfItemTags           149
  pfFileName           17
  pfFileText           17
Query file eval-heldout.json: 40 queries, 4 without a relevant item (excluded from the means)
Each search returns up to 150 item groups; the item rank is the position of its group.

Mode: words
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   1.000   1.000   1.000    0.966      -      0.1      0.1
paraphrase             8      8   0.792   0.792   0.875    0.838      -      0.3      0.5
russian                6      6   0.667   0.667   0.889    0.815      -      0.2      0.2
cross-language         8      8   0.125   0.125   0.188    0.056      -      0.4      0.7
negated                4      4   0.750   0.750   0.750    0.672      -      0.5      0.7
status                 4      4   0.625   0.750   0.760    0.710      -      0.6      0.6
hard-negative          4      0       -       -       -        -      4      0.2      0.5
all                   40     36   0.634   0.648   0.719    0.649      4      0.3      0.7

Mode: trigram
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   1.000   1.000   1.000    0.966      -      0.3      0.6
paraphrase             8      8   0.000   0.000   0.000    0.000      -      0.1      0.6
russian                6      6   0.000   0.000   0.000    0.000      -      0.2      0.5
cross-language         8      8   0.000   0.000   0.000    0.000      -      0.2      0.4
negated                4      4   0.000   0.000   0.000    0.000      -      0.4      0.6
status                 4      4   0.000   0.000   0.000    0.000      -      0.2      0.4
hard-negative          4      0       -       -       -        -      0      0.2      0.3
all                   40     36   0.167   0.167   0.167    0.161      0      0.2      0.6

Mode: vector
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   1.000   1.000   1.000    0.948      -      4.3      4.8
paraphrase             8      8   0.771   0.896   0.806    0.817      -      4.7      5.2
russian                6      6   0.667   0.667   1.000    0.884      -      3.7      4.2
cross-language         8      8   0.688   0.688   0.406    0.381      -      4.0      4.4
negated                4      4   0.750   0.750   0.750    0.699      -      3.7      4.2
status                 4      4   0.625   0.750   0.875    0.814      -      3.6      4.0
hard-negative          4      0       -       -       -        -      4      3.4      3.5
all                   40     36   0.755   0.796   0.783    0.740      4      4.0      5.0

Mode: hybrid
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   1.000   1.000   1.000    0.966      -      3.8      4.4
paraphrase             8      8   0.896   0.896   0.875    0.872      -      4.3      5.1
russian                6      6   0.667   0.667   1.000    0.884      -      4.3      5.3
cross-language         8      8   0.188   0.438   0.224    0.172      -      4.6      5.3
negated                4      4   0.750   0.750   0.750    0.699      -      5.1      5.6
status                 4      4   0.500   0.750   0.781    0.747      -      4.6      5.3
hard-negative          4      0       -       -       -        -      4      3.9      4.4
all                   40     36   0.657   0.741   0.748    0.701      4      4.4      5.3
```

## What the baseline shows

- The `trigram` mode scores 0 on every kind except `exact` (codes and file names).
- `exact` queries are solved by every mode that reads the text.
- `cross-language` is the weakest kind in `hybrid`. On the dev queries `hybrid` has a lower MRR (0.115) than `vector` alone (0.321). On the held-out queries the order of the two modes is the same for MRR (0.224 against 0.406).
- On `hard-negative` queries the `words`, `vector` and `hybrid` modes return some of the listed `irrelevant` items in the first 5. The `trigram` mode returns none. There is no score threshold in the fusion, so a mode that finds any candidate returns it.
- These are observations on 36 judged queries per file. They are inputs for the next tasks, not conclusions.

## Tuning

### Options

`THybridSearchOptions` holds every tuning value. `Default` is the setting that the product uses.

| Field | Default | Meaning |
| --- | --- | --- |
| `RrfK` | 60 | Constant `k` of `1 / (k + rank)`. |
| `CandidatesPerList` | 50 | Number of candidates that each list gives to the fusion. |
| `ListWeights` | 1 for every list | Weight of the `1 / (k + rank)` term of each list. |
| `FieldWeights` | 1 for every field | Factor on the score of a passage, by the field of the passage. |

The score of a passage is `FieldWeight * sum over lists of ListWeight / (RrfK + rank)`. The default weights are all 1. A list with weight 0 still runs (the sweeps use `--list-weight words=0`). A passage that only a weight-0 list found gets the score 0 and stands after all passages with a score above 0. It keeps `hsWords` in `Sources`. Passages with an equal score are ordered by the best rank that they have in a weight-0 list (a passage without such a rank is last), and then by key. Groups use the same order: score, then the weight-0 rank of the best passage, then `ItemId`. Thus words-only items keep the BM25 order of the words list. If every list that has a candidate has weight 0, every score is 0 and the result has the order of the zero-weight list.

### Rules for the decision

- Tune on the dev queries only. Read the held-out queries only for the setting that was chosen on the dev queries. Every held-out run is listed below.
- A family is one sweep of one value. Candidates 1, 2, 4 and 5 are one family each. Candidate 3 has four families: the vector-weight sweep (lists 1:1:x), the words-weight sweep (lists x:1:1), the trigram-weight sweep and the trigram-factor sweep. On the dev queries, the setting of a family with the best nDCG@10 is run on the held-out queries, if its dev R@10 does not fall. If two settings of a family have the same dev nDCG@10, the setting that is closer to the old default is run. The other settings of the family are not run on the held-out queries. Dev Irr@5 does not decide this step. It is shown in the text, as a warning.
- A default changes only if all of these are true on the held-out queries: nDCG@10 rises, R@10 does not fall, the queries that get better outnumber the queries that get worse by at least 3, and Irr@5 does not rise. A query is better or worse when its nDCG@10 changes by more than 0.00001.
- When two candidates pass alone, a combination is a new candidate. It needs a new dev run and a new held-out run.
- There is no relevance threshold. The index schema does not change.

### Candidates and results

Reference values. Dev: nDCG@10 0.644, R@10 0.697, Irr@5 6. Held-out: nDCG@10 0.701, R@10 0.741, Irr@5 4. "Held-out" columns are empty when the setting was not chosen. Better and worse count the 36 judged held-out queries. All values are the `hybrid` mode.

| Candidate | Dev nDCG@10 | Dev R@10 | Held-out nDCG@10 | Held-out R@10 | Better / worse | Held-out Irr@5 | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1. `RrfK` 20 | 0.648 | 0.697 | 0.703 | 0.755 | 1 / 1 | 4 | Rejected: no net gain. |
| 1. `RrfK` 100 | 0.644 | 0.697 | | | | | No dev gain. |
| 2. `CandidatesPerList` 30 | 0.648 | 0.704 | 0.711 | 0.769 | 4 / 0 | 4 | Passes alone. Not adopted: see the combinations. |
| 2. `CandidatesPerList` 100 | 0.645 | 0.697 | | | | | Not the best dev value. |
| 3. Lists words:trigram:vector 1:1:1.25 to 1:1:3 | 0.647 to 0.657 | 0.715 to 0.725 | | | | | Best is 1:1:2 (and 1:1:2.5). |
| 3. Lists 1:1:2 | 0.657 | 0.725 | 0.696 | 0.741 | 2 / 2 | 4 | Rejected: nDCG@10 falls. |
| 3. Lists 1:1:4 | 0.654 | 0.722 | | | | | Not the best dev nDCG@10 of the family (1:1:2 has 0.657). Dev Irr@5 is 7. |
| 3. Trigram weight 0.5, 0.25 or 0 (with vector 1 or 2) | 0.644 or 0.657 | 0.697 or 0.725 | | | | | No change. The trigram list only matters for the exact queries, and they are already solved. |
| 3. Lists 0.4:1:1, 0.33:1:1, 0.25:1:1 | 0.657, 0.650, 0.654 | 0.725, 0.715, 0.722 | | | | | Worse than 0 on dev. |
| 3. Lists 0.1:1:1 | 0.674 | 0.715 | | | | | Not the best dev nDCG@10 of the family (0:1:1 has 0.694). Dev Irr@5 is 8. |
| 3. Lists 0:1:1 | 0.694 | 0.708 | 0.743 | 0.796 | 7 / 2 | 4 | Best dev nDCG@10 of the family, R@10 does not fall (dev Irr@5 is 7). Passed on the first 36 judged held-out queries. Withdrawn in the second round (see "Short and mixed queries"). |
| 3. Trigram factor 0.5, 0.25 or 0 for passages that the words list also found | 0.644 | 0.697 | | | | | No dev gain. |
| 4. `ItemTitle` 1.25, 1.5, 2, 2.5, 3, 4 | 0.635, 0.626, 0.654, 0.622, 0.616, 0.586 | 0.711, 0.711, 0.752, 0.706, 0.699, 0.692 | | | | | Title above the rest does not help. 2 has 9 better and 8 worse queries, and R@5 falls to 0.562. |
| 4. `ItemTags` 1.25, 1.5, 0.75 | 0.621, 0.615, 0.633 | 0.697, 0.697, 0.669 | | | | | Worse. |
| 4. `FileText` 0.5 or 0.75 | 0.644 | 0.697 | | | | | No query changes. The corpus has only 17 file texts. |
| 4. `FileName` 0.75, 1.25 | 0.643, 0.641 | 0.697 | | | | | No gain. |
| 4. `ItemTitle` and `ItemTags` 1.25 or 1.5, `FileText` 0.75 or 0.5 | 0.636 to 0.637 | 0.725 | | | | | Worse. |
| 4. `ItemDescription` 1.25, 0.75, 0.6 | 0.580, 0.637, 0.643 | 0.660, 0.725, 0.725 | | | | | Worse or equal. |
| 4. `ItemDescription` 0.5 | 0.664 | 0.743 | 0.704 | 0.796 | 8 / 4 | 4 | Passes alone. Not adopted: see the combinations. |
| 4. `ItemDescription` 0.4, 0.25, 0.1 | 0.664, 0.662, 0.662 | 0.727, 0.720, 0.720 | | | | | Not better than 0.5. |
| 5. Identifier rule: words weight 2 or 3 for a query with a digit and no space | 0.644 | 0.697 | | | | | No gain. All six exact queries already have nDCG@10 0.998. The rule is not in the code. |

### Combinations

Candidates 2, 3 and 4 passed alone, but they act on the same ranking. Candidate 3 is the largest gain, so the other two were tested on top of it. Held-out better / worse in the last column is against the default before tuning.

| Setting | Dev nDCG@10 | Dev R@10 | Held-out nDCG@10 | Held-out R@10 | Held-out Irr@5 | Better / worse | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Candidates 30 and lists 0:1:1 | 0.694 | 0.708 | 0.743 | 0.796 | 4 | 7 / 2 | Same as lists 0:1:1 alone (no query changes). Candidate 2 is redundant. |
| Lists 0:1:1 and `ItemDescription` 0.5 | 0.708 | 0.727 | 0.713 | 0.782 | 5 | 8 / 7 | Rejected: Irr@5 rises and nDCG@10 is lower than lists 0:1:1 alone. |
| Candidates 30, lists 0:1:1 and `ItemDescription` 0.5 | 0.702 | 0.715 | 0.711 | 0.769 | 5 | 7 / 7 | Rejected for the same reason. |

Held-out runs made (10 runs of `--eval eval-heldout.json`): the default (reference), `RrfK` 20, candidates 30, lists 1:1:2, lists 0:1:1, `ItemDescription` 0.5, the three combinations above, and one run of the final default with all four modes (it gives the same numbers as lists 0:1:1).

### Decision of the first round (withdrawn)

After the first round, the default changed in one place: the words list got weight 0. On the first 36 judged held-out queries this gave nDCG@10 0.701 to 0.743, R@10 0.741 to 0.796, R@5 0.657 to 0.755, MRR 0.748 to 0.783 and Irr@5 4 to 4. Seven queries got better (six `cross-language` and one `status`) and two got worse. On the dev queries Irr@5 rose from 6 to 7, and the `negated` kind fell from nDCG@10 0.727 to 0.654. The rule used the held-out value, so the change passed. `RrfK`, `CandidatesPerList` and the field weights kept their old values. The second round withdrew this change.

### Short and mixed queries (second round)

The first round had no query kind for two cases in which the words list is the only exact signal. The final review found them. The second round adds these kinds to both query files and runs the words-weight family again. The corpus (149 items) did not change. The first-round tables above were measured on the first 40 queries of each file against a default with all weights 1, so they are still valid. The first 36 judged queries of each file give the same numbers as before.

| Kind | What it tests | Queries |
| --- | --- | --- |
| `short` | A query of 2 characters. The trigram list does not run for it (3 characters are the minimum), and the embedding of 2 characters carries little meaning. | dev d41 to d44 (`Ru`, `La`, `Ni`, `Cr`), held-out h41 to h44 (`Ar`, `eV`, `mm`, `Mo`) |
| `mixed` | A rare exact word and other words that are not next to each other in the item text. | dev d45 to d48 (`Cauchy wafers spectra`, `Nevot roughness degrees`, `AXUV compared certificate`, `tooling head recalibrated`), held-out h45 to h48 (`thermocouple oven controller`, `detector hot pixels dynamic`, `tracking partner sealed`, `CCD pitch focus`) |

The queries were judged on the item text before any search run. Rules: for a symbol query, the relevant items are the items about this element. Grade 2 if the symbol is in the title or the tags (for `Mo`: the item is about molybdenum itself, not about a Mo/Si stack). Grade 1 if it is only in the description or the file text. For a unit query (`eV`, `mm`), the item states a value in this unit. Grade 2 if the unit is in the title, and grade 1 if not. For a `mixed` query, grade 2 is the item that has the rare word, and grade 1 is its translation twin.

Overlap check (Python over the two files, as in the first round): no grade 2 item of one file is a grade 2 item of the other file, and no query text is in both files. Grade 1 items that are in both files: 29, 67 and 106 (in new dev queries, and in held-out lists) and 98 (in the new held-out query `Ar`, and a dev grade 2 item of d21). The element symbols of the corpus (Cr/Sc, Ni/C, Ru, La/B) belong to items that dev queries already judge as grade 2. Thus dev took them, and held-out took the other needs that no dev query judges as grade 2. The held-out `short` queries are therefore of another kind (two symbols and two units) than the dev ones (four symbols).

Procedure, fixed before the first run of the second round: (1) a dev sweep of the words weight x in the lists x:1:1; (2) the setting with the best dev nDCG@10 is run once on the held-out queries (a tie goes to the setting that is closer to 1), if its dev R@10 does not fall; (3) it must pass the four-part rule of the first round against the current default 0:1:1 and against the old default 1:1:1 (a setting that equals one of them is compared with the other one); (4) if it fails against 1:1:1, the default is 1:1:1.

Dev sweep (`hybrid`, all 44 judged dev queries):

| Words weight x | nDCG@10 | R@10 | Irr@5 | `short` nDCG@10 | `short` R@10 |
| --- | --- | --- | --- | --- | --- |
| 0 | 0.736 | 0.720 | 7 | 0.891 | 0.667 |
| 0.05 | 0.719 | 0.720 | 8 | 0.891 | 0.667 |
| 0.1 | 0.721 | 0.730 | 8 | 0.904 | 0.717 |
| 0.2 | 0.706 | 0.736 | 8 | 0.911 | 0.717 |
| 0.25 | 0.706 | 0.740 | 7 | 0.923 | 0.767 |
| 0.33 | 0.703 | 0.734 | 6 | 0.928 | 0.767 |
| 0.4 | 0.709 | 0.742 | 6 | 0.928 | 0.767 |
| 0.5 | 0.709 | 0.742 | 6 | 0.928 | 0.767 |
| 0.75 | 0.706 | 0.742 | 6 | 0.928 | 0.767 |
| 1 | 0.703 | 0.736 | 6 | 0.974 | 0.950 |

The best dev nDCG@10 is at x = 0 (the current default). The `short` queries need the weight 1: a smaller weight puts the item behind the vector candidates. The `mixed` queries do not depend on the weight: the vector list finds these items in both settings (dev R@10 0.875, held-out 1.000), so the kind does not support or contradict the weight 0.

Held-out runs of the second round (2 runs of `--eval eval-heldout.json`, in this order, each with all four modes): the current default 0:1:1, and the old default 1:1:1. With the 10 runs of the first round, the held-out queries were run 12 times.

| Setting | nDCG@10 | R@10 | R@5 | MRR | Irr@5 | `short` nDCG@10 | `short` R@10 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0:1:1 | 0.721 | 0.767 | 0.724 | 0.760 | 4 | 0.247 | 0.271 |
| 1:1:1 | 0.741 | 0.767 | 0.684 | 0.794 | 4 | 0.845 | 0.771 |

Setting 0:1:1 against 1:1:1: nDCG@10 falls (0.741 to 0.721), R@10 is the same, Irr@5 is the same, 8 queries get better and 5 get worse. The rule fails on the first part (nDCG@10 must rise). The 8 queries that get better are six `cross-language` queries, one `status` query and `Mo` (h44, by 0.004). The 5 queries that get worse are two `paraphrase` queries (h11, h14) and three `short` queries: h41, h42 and h43 fall from nDCG@10 0.84, 0.70 and 0.91 to 0.05, 0 and 0.

nDCG@10 by kind (dev and held-out, `hybrid`):

| Kind | Dev 0:1:1 | Dev 1:1:1 | Held-out 0:1:1 | Held-out 1:1:1 |
| --- | --- | --- | --- | --- |
| `exact` | 0.999 | 0.998 | 0.966 | 0.966 |
| `paraphrase` | 0.795 | 0.767 | 0.817 | 0.872 |
| `russian` | 0.849 | 0.804 | 0.884 | 0.884 |
| `cross-language` | 0.352 | 0.162 | 0.381 | 0.172 |
| `negated` | 0.654 | 0.727 | 0.699 | 0.699 |
| `status` | 0.529 | 0.512 | 0.814 | 0.747 |
| `short` | 0.891 | 0.974 | 0.247 | 0.845 |
| `mixed` | 0.957 | 0.957 | 1.000 | 1.000 |

### Decision

The default is back to the old setting: all list weights are 1 (`THybridSearchOptions.Default`). The words weight 0 does not pass the rule against 1:1:1 on the extended held-out file. `RrfK`, `CandidatesPerList` and all field weights keep their old values. A small positive weight was not the best dev setting, so it was not run on the held-out queries. No default of stage 5 differs from the setting before stage 5.

The words weight 0 still helps on `cross-language` queries (nDCG@10 0.17 to 0.38 on held-out) and costs on `short` queries. A rule that depends on the query length could keep both gains: the trigram list cannot run for a query of 1 or 2 characters, so the words list could keep the weight 1 for it and get 0 for longer queries. This is a different candidate (query kind handling, candidate 5). It is not tested on the held-out queries and not in the code. A dev-only estimate from the two dev runs (weight 1 for the `short` queries, 0 for the others) gives nDCG@10 0.744 and R@10 0.746. It is an input for a later round, not a result.

### Limits of this result

- The corpus is small and synthetic: 44 judged queries in each file. One query can move a mean by 0.02. The held-out `short` kind has 4 queries and is not the same kind of query as the dev `short` kind. The result says that the words list, as it is built now (OR of all query words, rank only), adds noise on `cross-language` and `paraphrase` queries and is the only signal for a query of 2 characters. It does not say how much a words list is worth in a real notebook.
- The `mixed` kind did not separate the settings. A better test needs a mixed query whose item the vector list misses. The corpus has few such items, and no query was chosen by its run result.
- The words list gives a rank, not a score. A common word at rank 1 gets the same weight as a rare word at rank 1. A better words list (for example AND, or words with a rarity filter) is a different change and is not tested here.
- The old setting of the first round is one option away: `Options.ListWeights[hsWords] := 0`, or `--list-weight words=0` in the runner. The knobs that did not pass in the first round (trigram factor for passages that the words list also found, identifier rule) were in commit `a190fa1` of branch `search-stage-5` and are not in the final code.

### Result on the extended query files

Same machine and build type as the baseline. `hybrid` is the default setting (all list weights 1). Both files have 48 queries and 44 judged queries. The `words`, `trigram` and `vector` modes do not depend on the list weights.

#### Dev queries (`hybrid`)

```text
Mode: hybrid
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   0.958   1.000   1.000    0.998      -      3.5      4.2
paraphrase             8      8   0.646   0.708   0.891    0.767      -      4.8      5.6
russian                6      6   0.694   0.694   0.917    0.804      -      4.1      4.6
cross-language         8      8   0.375   0.375   0.115    0.162      -      4.2      4.9
negated                4      4   0.667   0.792   0.781    0.727      -      4.9      5.3
status                 4      4   0.438   0.771   0.813    0.512      -      4.5      5.0
hard-negative          4      0       -       -       -        -      6      4.8      5.3
short                  4      4   0.767   0.950   1.000    0.974      -      3.1      3.2
mixed                  4      4   0.875   0.875   1.000    0.957      -      3.7      4.0
all                   48     44   0.661   0.736   0.771    0.703      6      4.2      5.3
```

#### Held-out queries (`hybrid`)

```text
Mode: hybrid
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   1.000   1.000   1.000    0.966      -      4.0      4.6
paraphrase             8      8   0.896   0.896   0.875    0.872      -      4.9      5.4
russian                6      6   0.667   0.667   1.000    0.884      -      4.2      4.6
cross-language         8      8   0.188   0.438   0.224    0.172      -      4.4      5.0
negated                4      4   0.750   0.750   0.750    0.699      -      4.3      5.0
status                 4      4   0.500   0.750   0.781    0.747      -      4.6      5.0
hard-negative          4      0       -       -       -        -      4      4.1      4.5
short                  4      4   0.604   0.771   1.000    0.845      -      3.0      3.4
mixed                  4      4   1.000   1.000   1.000    1.000      -      3.7      3.9
all                   48     44   0.684   0.767   0.793    0.741      4      4.2      5.2
```
