# Semantic search, stage 6: evaluation corpus with context, and a new held-out set

Stage 6 adds object context to the search. Context is the folder path, the item type and level, the action type and the parent item. Before the code changes, the evaluation data must be able to test context. This document describes the changed corpus, the new query kind `context`, the new held-out file and the baseline numbers. Later tasks of stage 6 (context in the embedding input, filters, reranker) use these numbers. See `docs/search-stage-5.md` for the metrics, the modes and the options of `SearchHarness`.

## Read this first

The corpus and the queries are synthetic. All items, folders, sample codes, file names and numbers are invented. No real project, person or measurement is in them. The corpus is small (149 items, 481 passages). The query files have 57 and 40 queries. Of these, 53 and 37 have a relevant item. This is not a benchmark. It cannot say how good the search is on a real notebook. A difference of a few points on 37 queries is noise.

## Files

| File | Content |
| --- | --- |
| `ELN.Community.Tests/Fixtures/Search/eval-corpus.json` | 5 projects, 35 folders, 149 items. The 149 items and their texts are the same as in stage 5. Each item has new fields (see below). |
| `ELN.Community.Tests/Fixtures/Search/eval-dev.json` | 57 queries: the 48 queries of stage 5, and 9 new queries of kind `context` (d49 to d57). Tune on these. |
| `ELN.Community.Tests/Fixtures/Search/eval-heldout.json` | The 48 held-out queries of stage 5. This file did not change. It is now a regression set. Do not use it to make a decision. |
| `ELN.Community.Tests/Fixtures/Search/eval-heldout-2.json` | 40 new queries (k01 to k40). Use them to decide. They have no grade 2 item and no information need in common with the other two files. |

## New corpus fields

The field names follow the entities in `ELN.Domain` (`TItem`, `TItemLevel`, `TItemType`, `TActionType`, `TFolder`).

| Field | Where | Meaning |
| --- | --- | --- |
| `folders` | top level | List of `id`, `project`, `parent`, `title`. `parent` is 0 for a top folder. A folder and its parent are in the same project. Folder ids (1001 to 5006) are not item ids. |
| `folder` | item | Id of the folder that holds the item. The folder is in the project of the item. |
| `level` | item | `Proc`, `Item` or `Action`. The value `Folder` is allowed, but no item has it, because the folders are in the `folders` list. |
| `type` | item | A name of `TItemType`: `Synthesis`, `Treatment`, `Measurement`, `Testing`, `Characterization`, `Computing`, `Specimen`, `Model`, `Other` or `Wiki`. |
| `action_type` | item | The title of the action type, for example `X-ray reflectometry`. There are 45 titles. |
| `parent` | item | For an `Action`: the id of a `Proc` item in the same project and the same folder. For all other items: 0. |

Numbers: 35 folders (7 in project 1, 7 in project 2, 9 in project 3, 6 in project 4, 6 in project 5). Every project has folders that are two levels deep. The items are 80 `Proc`, 57 `Item` and 12 `Action`. The 12 actions have 7 parent procs.

The corpus has no new items. The reason: a new passage changes the global statistics (the number of rows and the mean length) of the words list. Any one new item changed the order of the words list for dev query d08 in a test run. The stage 6 requirement is that the dev result of the 48 old queries does not change. An unchanged item set is the only way to keep this.

## Query kind `context`

A `context` query needs object context that is not in the matched passage. Each query has two parts. One part is the topic, which is in the passage text. The other part is the context, which is only in a title, a folder name, a parent item or a project name. Two sources of context are used:

- The folder. An item matches a folder name when its folder, or one folder above it, has that name.
- The parent. An `Action` matches the title of its parent `Proc`.

Judgment rule, written before any search run: grade 2 is an item that has the topic and the context. Grade 1 is an item that has the context and a topic that is related. The parent proc of a graded action has grade 1. A review pass over all items of the context folder (including its sub-folders) was made for every held-out 2 `context` query. An item that has the topic but not the context has no grade. Thus a search without context has to guess between the items of the same topic. The queries use the fields of the items, not only their texts.

Two examples:

- d50, "problems during the MS-0417 reflectometry measurement". Items 33, 34 and 52 are actions of the proc "XRR scan of MS-0417". The code is only in the title of the parent.
- k32, "analysis after annealing in the W/B4C stacks folder". Item 76 is in the folder "W/B4C stacks". Its text does not say "W/B4C".

A check of the 18 queries (all grade 2 items): all 18 have at least one context word that is not in any text of the item, except d49. Query d49 follows the example of the plan: the code is in the title of item 30, and the curve is in its file text. At the level of the item, d49 has no word of context that is missing from the text.

## The held-out file 2

The 40 queries were written and judged before any search run. They do not use the queries or the topics of the other two files.

The judgments were corrected in two rounds after reviews, before any selection and before any change of the search. The first review found three faults. (1) Query k23: item 48 is only planned, not prepared, so it has grade 1 now (item 25 stays grade 2). (2) The parent rule was applied in k34 but not in k32 and k33. Now the parent proc of the graded action has grade 1 in all `context` queries (items 66 and 60). (3) Four `context` queries (old k34, k35, k36, k39) had only one item with the topic in the corpus, so the topic alone found it. They were replaced by queries whose topic has at least two items, and the context must choose between them. Query k40 was replaced for the same reason, and k32 and k33 were rewritten. After this correction the judgments of `eval-heldout-2.json` are frozen. The same parent rule was added to dev query d50 (item 30, grade 1). The second review found grade 1 items that were missing under the rule "context plus related topic". They were added: 61 and 81 in k33, 84 in k35, 99 in k36, 13 in k37, 141 and 142 in k39, and 97 in k40. This is the last change of the judgments.

| Kind | Queries | Judged |
| --- | --- | --- |
| `exact` | 4 | 4 |
| `paraphrase` | 6 | 6 |
| `russian` | 4 | 4 |
| `cross-language` | 5 | 5 |
| `negated` | 3 | 3 |
| `status` | 3 | 3 |
| `hard-negative` | 3 | 0 |
| `short` | 1 | 1 |
| `mixed` | 2 | 2 |
| `context` | 9 | 9 |

The file has one `short` query ("py", a file extension). The corpus has no other 2-character word whose items are free of the judgments of the other two files.

### Context queries and competing items

For each `context` query the table lists the items that have the topic but not the context, and the items that the context chooses. A search without context cannot tell them apart by the topic. Item numbers: the grade 2 item, the grade 1 items, and the competing items (no grade, because they are in another folder or have another parent).

| Query | Grade 2 | Grade 1 | Context field that chooses | Competing items (topic without the context) |
| --- | --- | --- | --- | --- |
| k32 analysis after annealing in the W/B4C stacks folder | 76 | 66 (parent) | folder `Annealing / W/B4C stacks` | 78 (EDS after annealing, folder Mo/Si stacks), 43 (TEM), 47 (XRF) |
| k33 analysis after annealing in the Mo/Si stacks folder | 78 | 60 (parent), 61, 81 | folder `Annealing / Mo/Si stacks` | 76 (microscopy after annealing, folder W/B4C stacks), 43, 47 |
| k34 measurements on substrates in the stock and purchases folder | 91 | | folder `Stock and purchases` | 35 (AFM of substrates), 107 (stress of substrates), 114 (contact angle), 92 (quartz substrates) |
| k35 interdiffusion in the models and summaries folder | 77 | 87, 84 | folder `Models and summaries` | 11 (interdiffusion of Mo/Si, folder Mo/Si production runs) |
| k36 cathode in the vacuum system folder | 110 | 99 | folder `Vacuum system` | 13 (erosion of the Mo cathode, folder Targets and cathodes) |
| k37 preparation before use in the targets and cathodes folder | 27 | 13 | folder `Chamber and power / Targets and cathodes` | 109 (storage of targets before installation), 110 (installation checklist), 89 and 90 (preparation of substrates) |
| k38 thermal stress on glass in the software and modelling folder | 146 | | folder `Software and modelling` | 107 (stress of glass substrates), 82 (thermal shock of glass), 4 (stress in films) |
| k39 instruction kept in the publications and data rules folder | 145 | 142, 141 | folder `Publications and data rules` | 100 (safety instruction, folder Cleaning and handling), 95 (cryopump procedure) |
| k40 contamination found in the vacuum system folder | 96 | 97 | folder `Vacuum system` | 113 (dust, folder Cleaning and handling), 68 (carbon contamination of a Ru cap) |

Dev `context` queries are not in this table. Their needs and competing items follow the same rule.

### Overlap check

The check is a Python script over the three query files. It was run after the files were written. It compares the grade 2 items, the grade 1 items and the query texts of each pair of files, and it lists the grades across the files.

| Pair | Grade 2 items in common | Query texts in common | Grade 2 against grade 1 | Grade 1 items in common |
| --- | --- | --- | --- | --- |
| dev and held-out | none | none | dev grade 2 in held-out grade 1: 67, 98. Dev grade 1 in held-out grade 2: 22, 29, 50, 60 | 57, 67, 106 |
| dev and held-out 2 | none | none | dev grade 2 in held-out 2 grade 1: 61, 66, 84 | 60, 66, 84 |
| held-out and held-out 2 | none | none | held-out grade 2 in held-out 2 grade 1: 60, 81, 97, 99, 142. Held-out grade 1 in held-out 2 grade 2: 77, 91, 96, 110, 145 | 13, 81 |

The pair "dev and held-out" is the result of stage 5. The nine new dev queries add no overlap with the old held-out file: their grade 2 items are 20, 30, 33, 34, 36, 37, 42, 52, 85, 93, 103, 114 and 116, and none of them is in a held-out list. Items 36, 52 and 114 were grade 1 items of dev before. The held-out 2 file uses 35 different grade 2 items. No one of them is a grade 2 item of the dev file or the old held-out file. Some of them are grade 1 items there, and some grade 2 items there are grade 1 items here (the table). The binding rule is: no shared grade 2 item and no shared information need. The information needs were compared by reading: no need of the held-out 2 file is the need of another file.

## How to run

The search artifacts must be installed (`%LOCALAPPDATA%\APS-ELN\search-artifacts`).

```powershell
pwsh -NoProfile -File tools/build-community.ps1 -Target SearchHarness -Configuration Release
_OUT\SearchHarness\Win64\Release\SearchHarness.exe --eval eval-dev.json
_OUT\SearchHarness\Win64\Release\SearchHarness.exe --eval eval-heldout-2.json
```

`--eval` takes a path or the name of a file in the fixture folder. The runner reads the new corpus fields at the start of `--eval`. It checks them and stops with an error text if one field is wrong: a folder that is not in the project of the item, an unknown level or type, a missing action type, or an action without a parent proc. It then prints one line that starts with `Context fields:`. A corpus file without the `folders` list (for example an old one) runs as before and prints no such line. The search uses the fields only when `--context item` or `--context full` is set (see "Task 2").

### Parity check

The corpus change must not change the dev result of the old queries. The check uses the per-query output of the old build and of the new build:

```powershell
SearchHarness_before.exe --eval eval-dev.json --per-query before.tsv
SearchHarness.exe --eval eval-dev.json --per-query after.tsv
```

`before.tsv` has 192 rows (48 queries, 4 modes). `after.tsv` has 228 rows. The rows of the new queries d49 to d57 are removed from `after.tsv` (`grep -v -P '\td(49|5[0-7])\t'`). The header line is removed from both files. Then `diff` shows no difference: the 192 rows are identical, to six decimals. The per-query file of `eval-heldout.json` is identical byte for byte before and after the change.

## Baseline

Machine: AMD Ryzen 9 9950X3D, 32 logical processors, Win64 Release, multilingual-e5-small, default tuning (all list weights 1). The held-out 2 file was run three times: on the first judgments, after the first correction and after the second correction (the frozen judgments, shown below). No decision was made on any run. The old held-out file was not read for any decision.

### Dev queries

```text
Evaluation corpus eval-corpus.json: 149 items in 5 projects, 481 passages embedded in 1.4 s
  pfItemTitle          149
  pfItemDescription    149
  pfItemTags           149
  pfFileName           17
  pfFileText           17
Context fields: 35 folders, folder paths up to 2 levels deep, items by level: Proc 80 Item 57 Action 12 Folder 0
Query file eval-dev.json: 57 queries, 4 without a relevant item (excluded from the means)

Mode: hybrid
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  6      6   0.958   1.000   1.000    0.998      -      4.2      4.4
paraphrase             8      8   0.646   0.708   0.891    0.767      -      4.3      4.6
russian                6      6   0.694   0.694   0.917    0.804      -      4.8      5.6
cross-language         8      8   0.375   0.375   0.115    0.162      -      4.6      5.5
negated                4      4   0.667   0.792   0.781    0.727      -      4.7      5.2
status                 4      4   0.438   0.771   0.813    0.512      -      4.7      5.0
hard-negative          4      0       -       -       -        -      6      4.7      5.3
short                  4      4   0.767   0.950   1.000    0.974      -      3.0      3.5
mixed                  4      4   0.875   0.875   1.000    0.957      -      3.4      3.6
context                9      9   0.393   0.541   0.574    0.409      -      5.3      6.1
all                   57     53   0.615   0.703   0.737    0.653      6      4.5      5.6
```

### Held-out queries 2

Run on the corrected and frozen judgments (second correction).

```text
Query file eval-heldout-2.json: 40 queries, 3 without a relevant item (excluded from the means)

Mode: hybrid
kind             queries judged     R@5    R@10     MRR  nDCG@10  Irr@5  mean ms   p95 ms
exact                  4      4   1.000   1.000   1.000    1.000      -      3.5      4.0
paraphrase             6      6   0.917   0.917   0.917    0.910      -      4.8      5.3
russian                4      4   0.750   0.750   1.000    0.913      -      4.6      4.9
cross-language         5      5   0.000   0.000   0.021    0.000      -      5.9      6.8
negated                3      3   0.500   0.667   0.667    0.599      -      4.8      5.5
status                 3      3   0.833   0.833   1.000    0.942      -      4.2      4.5
hard-negative          3      0       -       -       -        -      2      3.7      4.0
short                  1      1   1.000   1.000   1.000    1.000      -      3.0      3.0
mixed                  2      2   1.000   1.000   1.000    1.000      -      3.3      3.4
context                9      9   0.556   0.639   0.770    0.639      -      4.8      5.9
all                   40     37   0.662   0.696   0.771    0.716      2      4.6      5.9
```

The first run (before any correction) gave `hybrid` all-row nDCG@10 0.664, R@10 0.689 and `context` nDCG@10 0.450. The run after the first correction gave 0.729, 0.730 and 0.692. The last changes come only from the added grade 1 items in k33, k35, k36, k37, k39 and k40. The other 34 queries have the same per-query values as in the run before the second correction.

### All modes (row "all")

| File | Mode | R@5 | R@10 | MRR | nDCG@10 | Irr@5 |
| --- | --- | --- | --- | --- | --- | --- |
| dev | words | 0.536 | 0.608 | 0.675 | 0.595 | 6 |
| dev | trigram | 0.108 | 0.113 | 0.113 | 0.113 | 0 |
| dev | vector | 0.637 | 0.689 | 0.809 | 0.690 | 7 |
| dev | hybrid | 0.615 | 0.703 | 0.737 | 0.653 | 6 |
| held-out 2 | words | 0.595 | 0.655 | 0.614 | 0.619 | 2 |
| held-out 2 | trigram | 0.108 | 0.108 | 0.108 | 0.108 | 0 |
| held-out 2 | vector | 0.655 | 0.714 | 0.695 | 0.662 | 2 |
| held-out 2 | hybrid | 0.662 | 0.696 | 0.771 | 0.716 | 2 |

### What the baseline shows

- The `context` kind is below the mean of all kinds in `hybrid` on both files: dev 0.409 against 0.653, held-out 2 0.639 against 0.716. On dev only `cross-language` (0.162) and `status` (0.512) are lower. On held-out 2 the kinds `cross-language` (0.000) and `negated` (0.599) are lower. This gap is what context in the embedding input has to close.
- Two of the nine held-out 2 `context` queries (k34, k38) already have nDCG@10 1.0 in `hybrid` before any context is used. The headroom of the kind on held-out 2 is mostly in k32 (0.08), k37 (0.14) and k40 (0.52). With 9 queries, the kind can show only a large change.
- On the `context` kind of held-out 2, `vector` has the higher nDCG@10 than `words` (0.578 against 0.442), and `hybrid` is the highest (0.639). With 9 queries, this is not a difference.
- The `cross-language` kind of held-out 2 is 0 for `hybrid`. The five relevant items are not in the first 10 for any of the five queries. The kind is the weakest kind in stage 5 too (dev 0.162, held-out 0.172).
- The dev numbers of the 48 old queries are the same as in stage 5. The `all` row changed only because of the 9 new queries.
- These are observations on 37 and 53 judged queries. They are inputs for the next tasks, not conclusions.

## Use of the files in stage 6

- Tune only on `eval-dev.json`.
- Decide on `eval-heldout-2.json`. The rule of stage 5 is the same: nDCG@10 rises, R@10 does not fall, the queries that get better outnumber the queries that get worse by at least 3, and Irr@5 does not rise.
- The judgments and the queries of `eval-heldout-2.json` are frozen. Do not edit them after a run. Write each run of this file in the stage 6 documents. Runs made: 5. Runs 1 to 3 (first judgments, after the first correction, after the second correction) were made before any change of the search. Run 4 is the reference run of task 2 (`--context none`, the same numbers as the baseline). Run 5 is the one run of the best dev variant of task 2 (`--context full`). Only run 5 was used for a decision (see "Task 2").

## Task 2: context in the embedding input

### What is built

A passage can now carry a context. The context is a short line of text. The embedder reads the context together with the passage text. The full text index (words and trigrams) and the stored `passages.text` do not get the context. A word that is only in a project title does not find the passage with the word list.

| Part | Place |
| --- | --- |
| `BuildPassageContext`, `PassageContextFor`, `TPassageContextParts`, `TPassageContextMode` | `ELN.Search/unit_PassageContext.pas` |
| `TSearchPassage.Context`, `PassageContentHash`, `PassageEmbedText`, `TFileTextRequest.Context` | `ELN.Search/unit_SearchPassages.pas` |
| Embedding input of a pending passage | `ELN.Search/unit_SearchIndexer.pas` (`PassageEmbedText`) |
| File text passages get the context of their item | `ELN.Search/unit_FileTextStage.pas` (`Request.Context`) |
| The provider reads project titles, the folder chain, the item type, the action type and the parent title | `ELN.Model/unit_SearchDocumentProvider.pas` |
| `--context none|item|full` and `--rename-project ID` | `ELN.Community.Tests/SearchHarness.dpr` |

Format of the context, for example: `Thermal stability > Annealing > W/B4C stacks | Item: Reflectivity recording | Measurement | X-ray reflectometry | Parent: XRR scan of MS-0417`.

- Parts, in this order: the path (project title, then the folders from the top one down), `Item: <title>`, the item type (a name of `TItemType`), the action type title, `Parent: <title>`.
- A passage of the field `pfItemTitle` has no `Item:` part, because the passage text is the title.
- A part that is empty is not written. Line breaks and tabs in a part become one space.
- Each part has at most 80 characters. The whole context has at most 240 characters. A cut never splits a surrogate pair.
- The hash of a passage is SHA-256 of `Context + #10 + Text`. The embedding input is `Context + #10 + Text`, and the embedder puts `passage: ` before it. When the context is empty, the hash and the embedding input are the same as in stage 5.
- The context modes: `none` (no context), `item` (project title and item title) and `full` (all parts).
- The item level (`Proc`, `Item`, `Action`) is not a part of the context. The type name and the `Parent:` part carry the structure.

The provider default is one constant: `DefaultPassageContextMode` in `ELN.Search/unit_PassageContext.pas`. The constructor `TNotebookDocumentProvider.Create(Manager, ContextMode)` uses it when the caller gives no mode. The harness flag `--context` uses it too. The value is `pcmNone` (see the decision below). The task that wires the search into the hosts reads this constant.

How a folder is linked to its project: `TFolder` has no `ProjectID` property. The link is the column `ProjectID` of the table `Folders`. The entity `TProject` sets it through `FFolders` (a many-valued association with the foreign join column `ProjectID`). The provider does not need the link. An item has `ProjectID` and `FolderID`, and the folders of a chain are in one project. The provider reads all folders (`Id`, `ParentFolderID`, `Title`) and walks `ParentFolderID` up to a value of 0 or less (a legacy top folder has -1). The walk stops after as many steps as there are folders, so a loop in bad data does not run for ever.

### Tests

`ELN.Community.Tests/test_PassageContext.pas` (target `SearchIndexTests`): the format, the omission of the item title, the cuts at 80 and 240 characters, the empty parts, the three modes, the hash and the embedding input (also with an empty context), the context of a provider on a synthetic notebook (folder path, action type, parent, file text requests), the hashes after a project rename, the sync after a rename (only that project is embedded again, and the sync can be cancelled), and a search of the full text index for a word that is only in a project title (no hit).

### Measurement

Corpus, machine and options are the same as in the baseline. The numbers are the `hybrid` mode. Dev has 53 judged queries, held-out 2 has 37. "Better" and "worse" count the queries whose nDCG@10 changes by more than 0.00001 against `--context none`.

#### Dev (tuning)

| Variant | nDCG@10 | R@10 | R@5 | MRR | Irr@5 | Better / worse | nDCG@10 of the `context` kind |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `none` | 0.653 | 0.703 | 0.615 | 0.737 | 6 | | 0.409 |
| `item` | 0.670 | 0.725 | 0.620 | 0.756 | 5 | 11 / 8 | 0.459 |
| `full` | 0.697 | 0.753 | 0.647 | 0.790 | 6 | 14 / 9 | 0.584 |

`full` has the best dev nDCG@10. It is the only variant that was run on held-out 2. The dev result is not clean. The `context` kind has 6 queries better and 1 worse. Queries of other kinds get worse too: d01 (`exact`) 0.987 to 0.942, d33 (`status`) 0.748 to 0.399, d42 and d43 (`short`) 0.973 to 0.914 and 0.995 to 0.958.

#### Held-out 2 (decision), one run of `full`

| Variant | nDCG@10 | R@10 | R@5 | MRR | Irr@5 | Better / worse | nDCG@10 of the `context` kind |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `none` (reference) | 0.716 | 0.696 | 0.662 | 0.771 | 2 | | 0.639 |
| `full` | 0.728 | 0.705 | 0.682 | 0.780 | 3 | 6 / 2 | 0.726 |

Queries that changed (nDCG@10, `none` to `full`): k08 (`paraphrase`) 0.631 to 0.500, k20 (`negated`) 0.798 to 0.605, k32 0.080 to 0.138, k33 0.626 to 0.890, k35 0.726 to 0.803, k37 0.138 to 0.174, k39 0.830 to 0.879, k40 0.521 to 0.826 (the last six are `context` queries). The hard-negative query k27 changed from Irr@5 1 to Irr@5 2.

#### Decision rule

| Condition | Result |
| --- | --- |
| nDCG@10 rises | Yes: 0.716 to 0.728 |
| R@10 does not fall | Yes: 0.696 to 0.705 |
| Better minus worse is at least 3 | Yes: 6 - 2 = 4 |
| Irr@5 does not rise | No: 2 to 3 (query k27) |

Decision: `full` is rejected. The default stays `none` (`DefaultPassageContextMode = pcmNone`). The code stays. Reason: the `context` kind gets better (6 queries better, 0 worse), but two queries of other kinds (k08, k20) get worse, and one hard-negative query puts one more irrelevant item in the first 5. The rule does not allow a rise of Irr@5. The held-out 2 file was not used to try `item`. Only the variant with the best dev result was run.

#### Regression set (stage 5 held-out, report only)

The stage 5 held-out file is a regression set. It was not used to choose a variant. `hybrid`, 44 judged queries:

| Variant | nDCG@10 | R@10 | Irr@5 | Better / worse |
| --- | --- | --- | --- | --- |
| `none` | 0.741 | 0.767 | 4 | |
| `full` | 0.760 | 0.792 | 5 | 12 / 5 |

The hard-negative queries show the same effect as on held-out 2: one more irrelevant item in the first 5 with `full`.

### Cuts at 512 tokens

The embedder cuts a passage that is longer than 512 tokens, and the sync counts this (`TSyncStats.Truncated`). The harness prints the counter after the first sync. On the corpus: 0 of 481 passages without context, 0 of 481 with `item`, 0 of 481 with `full`. The corpus passages are short. The counter does not say how the context changes the cuts on a long real text. A passage of 1200 characters can get up to 240 characters of context. Use the counter of a real sync to see this.

### Rename of a project

A project rename changes the context of every passage of that project, and only of that project. The sync embeds these passages again. It does not touch the passages of other projects. The harness measures this with `--rename-project ID`: it syncs the corpus with the new title and prints the counts. Release build, `full`, the same machine:

| Renamed project | Passages of the project | Embedded again | Not changed | Time |
| --- | --- | --- | --- | --- |
| 1 | 97 of 481 | 97 | 384 | 0.42 s |
| 3 | 91 of 481 | 91 | 390 | 0.38 s |

The time for the first sync of all 481 passages with `full` was 1.9 s. The embedding is done in batches of 32 passages, and the sync checks the cancel flag before each batch. A test cancels the sync of a rename after the first batch. The passages that were done stay in the index, and the next sync does the rest.

These are numbers of a small synthetic corpus. They do not say how long the rename of a project takes in a real notebook.

### How to run

```powershell
SearchHarness.exe --eval eval-dev.json --context full --per-query full.tsv
SearchHarness.exe --eval eval-dev.json --context full --modes hybrid --compare none.tsv
SearchHarness.exe --eval eval-dev.json --context full --modes hybrid --rename-project 1
```

`--context` takes `none`, `item` or `full`. The default is `DefaultPassageContextMode`. A mode other than `none` needs a corpus with the `folders` list. `--rename-project` needs a mode other than `none`.

## Task 3: allowed item set

### What is built

`THybridSearchOptions.ItemFilter` (type `TItemFilter`, unit `unit_VectorSearch`) limits a search to a set of items. The filter has two fields: `Active` and `ItemIds`. When `Active` is `False`, the filter does nothing and `ItemIds` is ignored. This is the default. When `Active` is `True` and `ItemIds` is empty, the search returns no group.

The filter is an input of each of the three lists. It is applied inside the list, before the cut to `CandidatesPerList`:

| List | How the filter is applied |
| --- | --- |
| Vector | `TExactVectorIndex.Search` skips each entry whose item is not in the set. `TExactVectorIndex.Add` now takes the item id of the entry (`Add(SourceId, Scope, ItemId, Vector)`). |
| Words, trigram | `MatchWords` and `MatchTrigrams` add `AND p.item_id IN (SELECT value FROM json_each(?4))` to the query. They add it only when the filter is active. The query text of an inactive filter is the same as before. |

A strict filter therefore finds an item whose passages are below the 50th place of a list without the filter. The filter is not applied after the cut.

The filter never gives more access. The project scope (`VisibleProjectIds`) and the live check of each item are applied as before. An allowed item in a project that is not visible is not returned.

The store has a new index, `passages_item` on `passages(item_id)`. It is created with `CREATE INDEX IF NOT EXISTS` each time a store is opened. An existing store gets the index without a reset. `SearchIndexSchemaVersion` stays `2`.

The old signatures are removed. Each caller (tests, `SearchHarness`) passes the new parameters. A caller without a filter passes `Default(TItemFilter)`.

### Tests

`ELN.Community.Tests/test_SearchIndex.pas` (target `SearchIndexTests`):

- `THybridSearchTests`: the default filter is not active; an allowed item that is below the cut in all three lists is found with the filter and not found without it; an active filter without ids gives no group; an allowed item in a project that is not visible is not returned, and it is returned when its project is visible; an inactive filter with ids gives the same groups and scores as the default.
- `TSearchIndexStoreTests`: the filter limits the words and the trigram list; the rank counts the filtered list; the filter is applied before `Limit`; the filter follows an item that `UpdateCoordinates` moved; the index `passages_item` is created again on an existing store without a reset.

`ELN.Community.Tests/test_SearchEmbedding.pas` (target `SearchTests`, `TExactVectorIndexTests`): the filter is applied before `TopK`; an active filter without ids gives no result; an inactive filter ignores the ids; the filter stays inside the eligible scopes.

### Parity check

The inactive filter must not change the dev result. `SearchHarness --eval eval-dev.json --compare` against the per-query file of the build before this task: all 53 judged queries are the same, all 4 hard-negative queries have the same Irr@5, and the two per-query files are byte-identical.

## Task 4: resolution of the structured filter

`ELN.Model/unit_SemanticSearchFilter.pas` turns a structured filter into a `TItemFilter` (see Task 3). The function is `ResolveSemanticFilter(Manager, VisibleProjectIds, Filter)`. The filter is a parameter. Nothing reads a filter from the query text.

`TItemFilter.Only(Ids)` creates an active filter with the given item ids. `TExactVectorIndex.Search` creates its set of allowed items only when the filter is active.

### Fields of `TSemanticSearchFilter`

| Field | Meaning |
| --- | --- |
| `FolderId` | A folder of a visible project. The filter includes the folder and all its subfolders. `0` means no folder filter. |
| `ItemTypes` | Names of `TItemType` (for example `Specimen`). The names are not case sensitive. |
| `Levels` | Names of `TItemLevel` (`Proc`, `Item`, `Action`, `Folder`). |
| `ActionTypeId` | The action type of the item. `0` means no filter. |
| `DateField`, `DateFrom`, `DateTo` | The created date or the modified date of the item, in UTC. Both limits are whole days. `DateTo` includes the whole last day. A limit of `0` is open. An item without a modified date does not match a modified-date filter. |
| `Values` | Value constraints. Each constraint needs one `TValue` of the item. All constraints must be true (AND). |

A value constraint has a value type (title or symbol, as in `query_values`), optional `Min` and `Max` (both limits are included), a unit, and an optional record type (`EXP_CONDITION`, `TEST_RESULT`). The stored number of a `TValue` is in the `Units` of its value type. The limits are converted into these units with `TUnitConverter.TryFactor`. A unit with an offset (for example the degree Celsius) is converted with `TUnitConverter.Convert`. An empty unit means that the limits are already in the units of the value type. If several value types have the same title, the constraint is tested for each of them.

### Errors

`ESemanticFilterError` has a message for the user. It is raised for an unknown or invisible folder (one text for both), an unknown value type, an unknown unit, a unit of another dimension than the value type, an unknown item type, level or record type, a minimum above the maximum, and a start date after the end date. A unit error is never an empty result.

### Access

Every query is limited to `VisibleProjectIds` in the query itself, and it skips deleted items. The allowed set is always a subset of the items of the visible projects. With a folder, the query uses only the project of the folder. A filter that matches nothing gives an active filter without ids, that is, no group. An empty filter (`IsEmpty`) gives an inactive filter and runs no query. Long id lists are split into groups of 400 for SQLite.

### Tests

`ELN.Community.Tests/test_SemanticSearchFilter.pas` is part of `SearchIndexTests`. It uses the synthetic notebook of `TNotebookFixture` with a second project that is not visible. `ValueIsStoredInTheTypeUnits` checks with the drift check that a reader value of 12 GPa is stored as 12000 in a value type in MPa.

## Task 5: filters in the hosts

Both hosts use `ResolveSemanticFilter` (Task 4) and pass the result to the search in `THybridSearchOptions.ItemFilter` (Task 3). The filter is applied before the candidate cut.

### Service

`TSemanticSearchService.Search(Query, VisibleProjectIds, TopK, Options)` takes the options of `THybridSearcher.Search`. The old signature without `Options` is removed. A caller without a filter passes `THybridSearchOptions.Default`.

`ELN.Model/unit_SemanticSearchFilter.pas` has a new function, `DescribeValueConstraints(Manager, Constraints)`. It returns one `TAppliedLimit` for each value type that a constraint matches: the type, the unit of the type, the limits after the unit conversion, the record type and the unit that the caller requested. The MCP tool uses it for `filters_applied`.

### MCP tool

`search_semantic` has these new optional parameters:

| Parameter | Meaning |
| --- | --- |
| `folder_id` | A folder of a project that the caller can read. The filter includes the subfolders. |
| `item_types` | Array of item type names. |
| `levels` | Array of `Proc`, `Item`, `Action`, `Folder`. |
| `action_type_id` | The action type of the item. |
| `date_field` | `created` (default when a date is given) or `modified`. |
| `date_from`, `date_to` | ISO 8601 dates (`yyyy-mm-dd`). Both days are included. The day is the literal day of the text; there is no time zone conversion, and item dates are compared in UTC. A text with a time part (`T`, a space or a colon) is refused. |
| `values` | Array of `{value_type, min, max, unit, rec_type}`. `min` and `max` are inclusive. All entries must match. |

A parameter of the wrong type, an invalid date, an unknown `date_field`, a `folder_id` or `action_type_id` below 1, and a `values` entry without `value_type` return an error. The text of an `ESemanticFilterError` is the text of the error that the tool returns. A hidden folder and a missing folder have the same text.

The tool reads the filter before the short-query check, and it resolves the filter before the index update. An error therefore does not start an update. A call without a filter parameter returns the same result as in stage 5. It has no `filters_applied`.

When a filter is used, the result has `filters_applied`: `folder_id`, `item_types`, `levels`, `action_type_id`, `date_field`, `date_from`, `date_to` (as `yyyy-mm-dd`) and `values`. Each entry of `values` is one matched value type: `value_type`, `value_type_id`, `unit` (the unit of the type), `min` and `max` (converted into that unit), `rec_type` and `requested_unit`. An agent can see what the tool enforced. For example, `"min": 10, "unit": "GPa"` for a value type in MPa gives `"min": 10000` and `"unit": "MPa"`.

### Desktop dialog

The Search dialog has a filter row under the search box with a project list, an item type list and two date pickers with a check box (**Created** from and to). The controls are in the DFM. They are disabled when **Search by meaning** is off, and the text search ignores them. The project list shows the projects of `VisibleProjectIds` with their titles. A project selection replaces the list of visible projects in the query, so it cannot widen access. The dialog shows an `ESemanticFilterError` in the status line. The dialog does not have value filters. They need a value type list with units, which is a separate design. The minimum width of the dialog is now 560 pixels.

The days of the **Created** filter are UTC days, as in the MCP tool. The dialog does not convert them to the local time zone (ruling of the final review). The filters keep their values when the window is opened again, and the project list is rebuilt only when the list of visible projects changes.

### Tests

`ELN.Community.Tests/test_SemanticSearchTool.pas` (target `DesktopRegressionTests`): each parameter narrows the groups (folder, item types, levels, action type, created and modified dates, values); a value limit in GPa is converted for a value type in MPa and `filters_applied` shows the converted limit; an unknown unit and a unit of another dimension return the text of the filter error; a hidden folder and a missing folder return the same text; wrong parameters return errors; no filter parameter returns every item and no `filters_applied`; the schema lists the parameters.

## Task 9: reranking in the search and the hosts

The reranker is optional. Without its files, the search is the hybrid search of stage 6 and every result has `reranked` false. The configuration is the owner decision in `docs/search-stage-6-reranker.md`: the model `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1` (8-bit ONNX), fusion `pure@20`, context in the input, and only the best passage of each group. The plan text `rrf2@20` is replaced by `pure@20`.

### What is built

| Part | Content |
| --- | --- |
| `THybridSearchOptions.RerankDepth` | Default 20 (`DefaultRerankDepth`). 0 turns the reranker off for a call. The service reads it. `THybridSearcher.Search` does not. |
| `THybridSearcher.RerankInputs(Groups, Depth)` | One text for each of the first `Depth` groups: the context line, a line feed and the full text of the first passage of the group. The first passage is the best passage in the hybrid order. A group without a stored context has the passage text only. |
| `ApplyRerankScores(Groups, Scores)` | Fusion `pure`. The first groups are sorted by the score of the reranker, largest first. An equal score keeps the hybrid order. The groups after them keep their hybrid order and follow them. |
| `unit_CrossEncoder` | `CrossEncoderInstalled(Root)`, `CrossEncoderFactory(Root)` and the type `TCrossEncoderFactory`. The one-argument `CreateCrossEncoder` is removed. `CreateCrossEncoder(Root, Manifest)` stays. The default batch size is now 1 (see "Batch size"). |
| Store table `item_context` | `item_context(item_id INTEGER PRIMARY KEY, parts TEXT)`. `parts` is the context of the item as JSON (`PassageContextPartsToJson`). The table is created with `IF NOT EXISTS`. The schema version does not change, so an existing index is not rebuilt. |
| `TSearchSnapshot.ItemContexts` | One entry (item id and the JSON) for each live item. `TNotebookDocumentProvider` now always reads the full parts (folder path, item type, action type, parent). The embedding input still follows `DefaultPassageContextMode` (`none`), so no hash and no vector changes. |
| `TSemanticSearchService` | The constructor has a new parameter, `RerankerFactory` (nil means no reranker). `Search` returns `TSemanticSearchResult` (`Groups`, `Reranked`). `StartSearch` runs the same work on a thread. `RerankerAvailable` and `RerankBudgetMs` (default 1500) are new. `CreateDeliveryGate` is new. |
| `TMainThreadSearchSource` (`ELN.Desktop/Units`) | A wrapper for the live check. It runs the inner source on the main thread. |

Every sync writes the entries of `ItemContexts` into `item_context`. Only the rows that changed are written. A rename of a project changes the rows of its items, so the next rerank uses the new name. The rename does not re-embed anything (the embedding context is `none`).

### How a search runs

1. The service takes its lock. It runs the hybrid search with a depth of the larger value of `TopK` and `RerankDepth`. It reads the input texts of the first 20 groups from the store. Then it releases the lock.
2. It takes the own lock of the reranker. The first use loads the model. It scores the 20 inputs with the query. It does not hold the service lock, so a sync that starts during a rerank is not blocked. A test starts a sync while a fake reranker waits, and the sync finishes.
3. The result is the reordered list, cut to `TopK`, with `Reranked` true.

The hybrid search checks that each item is live and visible before the reranker sees it. The reranker only changes the order of these groups. It cannot add a group.

The service returns the hybrid order and `Reranked` false when one of these happens: no reranker factory, `RerankDepth` is 0, fewer than two groups, the model cannot load (the service then stops trying), the scoring raises an error, the scoring is not finished after the budget of 1500 ms, or the scoring returns after the budget. The budget starts after the model is loaded. The cancel check runs before each pair, so the scoring stops soon after the budget. A new `StartSearch` also cancels a rerank that is still running for an older search.

The reranker is not freed before the service. The model uses about 180 MB after the load and about 40 MB more while it scores 400-token pairs (measured, Release build, batch size 1).

### Batch size (ruling R8)

The 8-bit model quantizes the activations of a whole batch. A pair therefore scores a little differently in a different batch (Task 8 measured up to 0.8 logits). A batch of one pair gives the same score in every call. The measurement uses `SearchHarness --rerank-latency` (Release, Win64, AMD Ryzen 9 9950X3D, default threads, 20 pairs, a context line of 150 characters and corpus text, nine timed runs after one warm-up call):

| Tokens for each pair (average) | Batch size | Median | Min and max | Working set after the runs |
| --- | --- | --- | --- | --- |
| 309 | 1 | 334 ms | 331 and 342 ms | 205 MB |
| 309 | 20 | 374 ms | 360 and 407 ms | 676 MB |
| 409 | 1 | 422 ms | 411 and 427 ms | 221 MB |
| 409 | 20 | 601 ms | 595 and 678 ms | 979 MB |

Batch size 1 fits the budget of 1500 ms with a wide margin, is faster than batch size 20, uses less memory, and gives scores that do not depend on the other pairs. The default is 1. The test `ScoresDoNotDependOnTheOtherPairs` checks that. The reference test `LogitsMatchReference` sets the batch size to the size of the reference group (10 pairs in one batch), because the reference was made in one batch.

### Parity gate

The harness has a new mode `rerank`. It runs the hybrid search, takes `RerankInputs` of the first 20 groups from a store with the `item_context` rows of the corpus, and scores them with the real model. It uses the same functions as the service. It runs only when `--modes` names it.

```powershell
SearchHarness.exe --eval eval-dev.json --modes hybrid,rerank --context none
SearchHarness.exe --eval eval-heldout-2.json --modes hybrid,rerank --context none
```

Dev (53 judged queries), Win64 Debug build, batch size 1:

| Row | R@5 | R@10 | MRR | nDCG@10 | Irr@5 |
| --- | --- | --- | --- | --- | --- |
| Hybrid | 0.615 | 0.703 | 0.737 | 0.653 | 6 |
| Study, `pure@20`, context, best passage only (Python, batch 16) | 0.694 | 0.733 | 0.853 | 0.742 | 4 |
| Delphi, batch size 1 | 0.691 | 0.723 | 0.849 | 0.735 | 4 |
| Delphi, batch size 20 (first run, not kept) | 0.685 | 0.733 | 0.841 | 0.738 | 4 |

The gate is a dev nDCG@10 within 0.01 of 0.742. The Delphi value 0.735 passes (difference 0.007). The numbers differ from the study because the 8-bit scores depend on the batch, and the study scored all queries in batches of 16. The decision is not made again on these numbers.

Held-out 2 has no study number for the best-passage configuration. The Task 9 run is one run. It is reported, not used for a choice: hybrid nDCG@10 0.716, R@10 0.696, Irr@5 2; all passages (the study run, not shipped) nDCG@10 0.748; shipped best passage only nDCG@10 0.725, R@10 0.727, Irr@5 0. The shipped gain is +0.009, which is less than the change of one query (about 0.03). The query k29 "py" falls from 1.000 to 0.119. The better and worse query counts of the shipped configuration were not computed, because the run did not write a per-query file. The result therefore does not show that the decision rule passes. See "Held-out 2 for the shipped configuration" in `docs/search-stage-6-reranker.md`. This was one more read of `eval-heldout-2.json` (the study of Task 6 and the baseline runs read it before).

### MCP tool

The result of `search_semantic` has `reranked` (true or false). A call with a query shorter than two characters returns `reranked` false. The description of the tool names the field and says that `score` is the hybrid score and does not follow the reranked order. The MCP host passes the reranker factory only when `CrossEncoderInstalled` is true.

### Desktop dialog

- The check box **Rerank results** is next to **Search by meaning**. It is on by default when the reranker is installed, and it is saved in the section `Search` of the UI settings (`Rerank`). It is disabled when search by meaning is off or when the reranker is not available.
- A search by meaning runs on a worker thread (`TSemanticSearchService.StartSearch`). The count shows `Searching...` until the results arrive. The result is delivered with `TThread.Queue` behind a delivery gate. When a new query starts, or when the dialog is released or destroyed, an older result is ignored. The history, the selection and the navigation are unchanged.
- The filter, the Aurelius manager and the item list stay on the main thread. The live check of the search runs on the worker thread, but `TMainThreadSearchSource` runs it on the main thread with `TThread.Synchronize`. The main thread never waits for the worker without processing these calls (`TThread.WaitFor` on the main thread does). The count shows `reranked` after the number of results when the model order was used.

### Tests

- `test_SemanticSearchService.pas` (target `SearchIndexTests`): a fake reranker that reverses the order changes the first 20 groups and not the groups 21 and later; `TopK` below the depth still reorders the first 20; a short list is reordered fully; no reranker, depth 0, one group, a load failure, a scoring error, a slow reranker that stops when asked, and a slow reranker that does not stop all return the hybrid order with `Reranked` false; a load failure is not tried again; a sync that starts during a rerank finishes; a dead item is not in the list and not in the reranker input; the input is the context line, a line feed and the best passage of the group, one input for each group; the context rows are replaced at each sync; `StartSearch` delivers on the main thread, reports the failure text, drops the delivery after the service is freed, and is cancelled by a newer search; the live checks of a search started with `StartSearch` run on the main thread.
- `test_PassageContext.pas`: the JSON of the context parts, malformed JSON, the item context rows of the provider in each mode, and the rows of the store after a reopen and after a replace.
- `test_SemanticSearchTool.pas` (target `DesktopRegressionTests`): `reranked` is false without a reranker and for a short query, true with a reranker that reverses the order, false with a failing reranker, and the description names the field.
- `test_SearchEmbedding.pas` (target `SearchTests`): batch size one and the independence of the pairs.

### Limits

- The context rows are written by the sync. A notebook that was synced before this change has no rows until the next sync. The rerank then uses the passage text only for these items.
- The rerank uses the first passage of each group. The Task 6 study found that scoring all passages is a little better (dev nDCG@10 0.755 against 0.742, held-out 2 0.748 against 0.725), and the owner chose the best passage for speed. The reranker is on by default, and the held-out 2 gain of the shipped setting is small.
- A short query can fall in rank after the rerank (`py` in held-out 2). The dialog lets the user switch the reranker off. The MCP tool does not have a parameter for this.
- The first rerank after the start loads the model. This takes about 0.6 s in the harness, and it is not part of the budget.
- Two searches that rerank at the same time wait for each other at the reranker, because the model has one lock. The budget does not include the wait.
- The Desktop was compiled but not started.
