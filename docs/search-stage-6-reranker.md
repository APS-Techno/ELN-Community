# Semantic search, stage 6: reranker gate

This document records the second reranker study. The first study is in `docs/search-stage-5-reranker.md`. It used the 0:1:1 hybrid search that stage 5 later withdrew, and the stage 5 held-out file that was read many times. This study uses the stage 6 default hybrid search, the stage 6 corpus, the dev file for the choice, and `eval-heldout-2.json` for the one decision run. No reranker code is in the Delphi product. The owner decides the next step (see "Owner questions").

## Decision

**The decision rule passes. The adoption is not decided.** Two owner answers are open: the rule result, and the terms of the training data (see "Licence and data terms").

| Held-out 2 (37 judged queries) | Hybrid (stage 6 default) | `mmarco` 8-bit ONNX, `pure@20`, with context |
| --- | --- | --- |
| nDCG@10 | 0.716 | 0.748 |
| R@10 | 0.696 | 0.727 |
| R@5 | 0.662 | 0.727 |
| MRR | 0.771 | 0.825 |
| Irr@5 | 2 | 0 |
| Better / worse queries | - | 9 / 3 |
| Rule | - | passes |

Two things need attention before an adoption:

- The cost is high for real passages. A rerank of 20 groups with 3 passages each (60 pairs) takes 1.3 s at 300 tokens and 2.0 s at 400 tokens (16 cores, default threads). The budget of 1500 ms in the plan does not hold for the worst case (see "Latency").
- The reranker harms `short` queries. The query "py" falls from nDCG@10 1.000 to 0.174.

## Read this first

The corpus and the queries are synthetic and small (149 items, 53 judged dev queries, 37 judged held-out 2 queries). One query moves a mean by about 0.03. This is not a benchmark. The passages of the corpus are short (median about 16 tokens). All quality numbers use these short passages. The latency numbers use synthetic long passages (see "Latency").

## Method

1. The harness export. `SearchHarness --eval FILE --modes hybrid --context none --export-candidates FILE --per-query FILE` writes, for each query, the top 20 item groups of the stage 6 default hybrid search (list weights 1:1:1, context mode `none`, `DefaultPassageContextMode = pcmNone`). A group has the item id and up to 3 passages (key, field, text). The file also lists the item ids after rank 20 (`tail`). The harness change of this task adds one field to each exported passage: `context`. It is the context line that `BuildPassageContext` gives to the passage in mode `full` (for example `Multilayer deposition > Mo/Si production runs | Item: ... | Synthesis | Magnetron sputtering`). The hybrid ranking in the file does not change: the context is only added to the exported data. The harness reads the corpus a second time in mode `full` for this field.
2. The study script `tools/search-reference/rerank_study.py` scores each pair (query, passage input) with the cross-encoder. The score of a group is the largest score of its passages. A raw logit is not a probability. The script uses it only for the order, and there is no threshold.
3. Two inputs for the reranker were measured (ruling R1 of the plan): `none` = passage text only, and `full` = context line, a line feed, and the passage text (`--context full`). The format is the same as the embedding input of the passages (`Context + #10 + Text`).
4. Settings: depth 10 and 20 (the first D groups of the hybrid list are reordered; the groups after D keep their order) and fusion `pure` (order by the reranker score only) or `rrf2` (order by `1 / (60 + hybrid rank) + 2 / (60 + reranker rank)`). There are 4 settings and 2 inputs: 8 configurations. The `rrf1` fusion of stage 5 is not in this study.
5. The metrics, the parity check against the harness per-query file, and the rule are the same as in stage 5. The rule: nDCG@10 rises, R@10 does not fall, better minus worse queries is at least 3, Irr@5 does not rise. The script rebuilds the hybrid order from the export. It stops if one query differs from `--per-query` of the harness.
6. The configuration with the best dev nDCG@10, among those with a dev R@10 not below the hybrid search, goes to held-out 2 once. The script refuses to run held-out 2 without `--config`, and refuses a second run (`--allow-repeat` overrides it; it was not used).

Model: `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1`, file `onnx/model_quint8_avx2.onnx` (8-bit, 118.6 MB, ONNX Runtime 1.31.1). The 32-bit PyTorch model (torch 2.14.1+cpu) was run on dev as a reference. The model files are in `%LOCALAPPDATA%\APS-ELN\search-reference\rerank-models`. The candidate files and the score caches are in `%LOCALAPPDATA%\APS-ELN\search-reference\rerank6`. Machine: AMD Ryzen 9 9950X3D, 16 cores, 32 logical processors.

Check of the hybrid reference: the export of `eval-dev.json` gives the dev row of `docs/search-stage-6.md` (53 judged, R@5 0.615, R@10 0.703, MRR 0.737, nDCG@10 0.653, Irr@5 6). The export of `eval-heldout-2.json` gives the held-out 2 row (37 judged, R@5 0.662, R@10 0.696, MRR 0.771, nDCG@10 0.716, Irr@5 2).

## Dev results (53 judged queries)

Hybrid reference: R@5 0.615, R@10 0.703, MRR 0.737, nDCG@10 0.653, Irr@5 6. "Better / worse" counts the queries whose nDCG@10 changes by more than 0.00001.

### 8-bit ONNX, input `none` (text only)

| Setting | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse | Rule |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pure@10` | 0.653 | 0.703 | 0.776 | 0.686 | 3 | 12 / 12 | fails (better minus worse) |
| `pure@20` | 0.676 | 0.702 | 0.799 | 0.708 | 1 | 15 / 13 | fails (R@10 falls; better minus worse) |
| `rrf2@10` | 0.663 | 0.703 | 0.805 | 0.705 | 5 | 16 / 5 | passes |
| `rrf2@20` | 0.686 | 0.722 | 0.819 | 0.721 | 2 | 19 / 5 | passes |

### 8-bit ONNX, input `full` (context and text)

| Setting | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse | Rule |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pure@10` | 0.684 | 0.703 | 0.822 | 0.718 | 4 | 17 / 4 | passes |
| `pure@20` | 0.723 | 0.733 | 0.856 | 0.755 | 5 | 19 / 4 | passes, best |
| `rrf2@10` | 0.690 | 0.703 | 0.825 | 0.712 | 5 | 19 / 3 | passes |
| `rrf2@20` | 0.717 | 0.740 | 0.844 | 0.736 | 5 | 22 / 3 | passes |

### 32-bit PyTorch (reference)

| Input | Setting | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `none` | `pure@20` | 0.684 | 0.706 | 0.787 | 0.701 | 1 | 15 / 14 |
| `none` | `rrf2@20` | 0.690 | 0.722 | 0.805 | 0.714 | 2 | 17 / 7 |
| `full` | `pure@20` | 0.723 | 0.727 | 0.844 | 0.747 | 5 | 21 / 6 |
| `full` | `rrf2@20` | 0.717 | 0.733 | 0.856 | 0.744 | 5 | 22 / 4 |

The 32-bit model has the same order of the settings. The best configuration is the same (`full`, `pure@20`).

### What the dev results show

- The context in the reranker input helps. For every setting, nDCG@10 is higher with `full` than with `none` (for the 8-bit model: +0.032, +0.047, +0.007, +0.015 for `pure@10`, `pure@20`, `rrf2@10`, `rrf2@20`). The gain is mostly in `cross-language`, `status` and `context` queries.
- The hard-negative queries get worse with context, in comparison with the no-context input. Irr@5 on dev is 5 with `full pure@20` and 2 with `none rrf2@20`. The hybrid search has 6, so both inputs are below the hybrid value. The context line gives the reranker words (project and folder names) that the irrelevant items share with the query only by chance. This is a reading of the numbers, not a tested cause.
- Best configuration on dev: input `full`, `pure@20`, nDCG@10 0.755. The R@10 does not fall (0.733). This is the configuration of the one held-out 2 run. By ruling R1, Task 9 takes the input with context.

### nDCG@10 by kind on dev (hybrid to `full pure@20`)

| Kind | Hybrid | `full pure@20` |
| --- | --- | --- |
| exact | 0.998 | 0.999 |
| paraphrase | 0.767 | 0.764 |
| russian | 0.804 | 0.804 |
| cross-language | 0.162 | 0.603 |
| negated | 0.727 | 0.755 |
| status | 0.512 | 0.755 |
| short | 0.974 | 0.928 |
| mixed | 0.957 | 0.957 |
| context | 0.409 | 0.522 |

Dev `hard-negative` Irr@5: 6 to 5.

## Held-out 2 (decision), one run

Configuration: 8-bit model, input `full`, `pure@20`. This is the only configuration that was run on `eval-heldout-2.json`. The harness export of the file (the hybrid reference) is a harness run with the same numbers as run 4 in `docs/search-stage-6.md`. The reranker evaluation is one more use of the file, and the score log of the script has one line for it.

| Condition | Hybrid | `full pure@20` | Result |
| --- | --- | --- | --- |
| nDCG@10 rises | 0.716 | 0.748 | Yes |
| R@10 does not fall | 0.696 | 0.727 | Yes |
| Better minus worse is at least 3 | - | 9 - 3 = 6 | Yes |
| Irr@5 does not rise | 2 | 0 | Yes |

Other numbers: R@5 0.662 to 0.727, MRR 0.771 to 0.825.

**Rule outcome: passes.**

nDCG@10 by kind (hybrid to `full pure@20`):

| Kind | Hybrid | `full pure@20` |
| --- | --- | --- |
| exact | 1.000 | 1.000 |
| paraphrase | 0.910 | 0.848 |
| russian | 0.913 | 0.913 |
| cross-language | 0.000 | 0.200 |
| negated | 0.599 | 0.667 |
| status | 0.942 | 0.942 |
| short | 1.000 | 0.174 |
| mixed | 1.000 | 1.000 |
| context | 0.639 | 0.771 |

Hard-negative Irr@5: 2 to 0 (k26 and k27, one each).

Queries that changed (nDCG@10, hybrid to `full pure@20`):

| Query | Kind | Change |
| --- | --- | --- |
| k05 safe way to transport liquefied cryogenic gas in the lab | paraphrase | worse, 1.000 to 0.631 |
| k06 how clean must the air of the work area be | paraphrase | worse, 1.000 to 0.631 |
| k08 in what order should the parameters of a many-layer stack be fitted | paraphrase | better, 0.631 to 1.000 |
| k19 рентгенофлуоресцентный контроль состава слоёв | cross-language | better, 0.000 to 1.000 |
| k20 composition methods that cannot resolve single layers | negated | better, 0.798 to 1.000 |
| k29 py | short | worse, 1.000 to 0.174 |
| k32, k33, k35, k37, k39, k40 | context | all better (0.080 to 0.275, 0.626 to 0.906, 0.726 to 0.847, 0.138 to 0.275, 0.830 to 0.983, 0.521 to 0.826) |

The three worse queries are all `paraphrase` or `short`. The six better `context` queries are the six that the context in the embedding input also changed in stage 6 task 2. Here they all get better and none gets worse. The cross-language kind is still weak (0.200).

## Latency

The numbers are for the chosen configuration: 8-bit ONNX, input `full`, one session, 16 cores. Python and ONNX Runtime 1.31.1 measured them, not the Delphi build. Median of the 57 dev queries, after a warm-up pass.

### Passages of the corpus (short, median about 16 tokens)

| Work | Default threads |
| --- | --- |
| 20 pairs (first passage of the top 20 groups), with context | 78 ms |
| All passages of the top 20 groups (27 to 42 pairs), with context | 118 ms |
| Same, input `none` (for comparison) | 50 ms and 76 ms |

The working set after the load is 696 MB (244 MB before), the peak is 772 MB with context.

### Passages with real length

The corpus has no passage of 300 to 400 tokens. These passages are synthetic: the text of all corpus passages was joined, cut by token count, and decoded again, with the first non-empty context line of the query prefixed (up to 240 characters). The numbers are therefore only an estimate of real notebook passages (up to 1200 characters, about 300 to 400 tokens).

| Pairs | Passage text | Default threads: median / p95 | 4 threads: median / p95 |
| --- | --- | --- | --- |
| 20 | about 300 tokens | 407 ms / 459 ms | 590 ms / 659 ms |
| 20 | about 400 tokens | 654 ms / 714 ms | 880 ms / 961 ms |
| 60 | about 300 tokens | 1258 ms / 1405 ms | 1769 ms / 1948 ms |
| 60 | about 400 tokens | 2043 ms / 2199 ms | 2679 ms / 2891 ms |

Sixty pairs is the worst case (20 groups with 3 passages). With one passage for each group (20 pairs), the cost fits in 1500 ms. With 3 passages of 300 tokens it is at the limit on this machine, with the default threads. It is over the limit with 400 tokens or with 4 threads. A slower machine needs more time. If Task 9 keeps all 3 passages, a time budget that returns the hybrid order (the plan already requires this) will fire often on real passages. The cost of the quality gain is a decision for the owner. A cheaper variant (one passage for each group, or a shorter depth) was not measured on quality in this study.

## Licence and data terms

These are facts and quotes only. They are not legal advice. The owner decides.

- Model. `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1`. The model card says `license: apache-2.0` (read from the local copy of `README.md`, revision `1427fd652930e4ba29e8149678df786c240d8825`). The card lists `datasets: unicamp-dl/mmarco` and the base model `nreimers/mMiniLMv2-L12-H384-distilled-from-XLMR-Large`. The ONNX file is `onnx/model_quint8_avx2.onnx` of the same revision. The repository has no separate licence file.
- Training data. The model card says: "This model was trained on the MMARCO dataset. It is a machine translated version of MS MARCO using Google Translate. It was translated to 14 languages." The mMARCO dataset card (`https://huggingface.co/datasets/unicamp-dl/mmarco`, revision `6d039c4638c0ba3e46a9cb7b498b145e7edc6230`, read on 2026-10-29) says: "mMARCO is a multilingual version of the MS MARCO passage ranking dataset", and under "Licensing Information": "This dataset is released under Apache license 2.0".
- MS MARCO terms. Text of the section "Terms and Conditions" on `https://microsoft.github.io/msmarco/` (fetched on 2026-10-29):

> The MS MARCO datasets are intended for non-commercial research purposes only to promote advancement in the field of artificial intelligence and related areas, and is made available free of charge without extending any license or other intellectual property rights. The dataset is provided "as is" without warranty and usage of the data has risks since we may not own the underlying rights in the documents. We are not be liable for any damages related to use of the dataset. Feedback is voluntarily given and can be used as we see fit. Upon violation of any of these terms, your rights to use the dataset will end automatically.
>
> If you encounter any difficulties with accessing the dataset, please do not hesitate to inform us at ms-marco@microsoft.com. We are committed to ensuring that you have seamless access to all necessary resources and will promptly address any issues you may experience. Please contact us if you own any of the documents made available but do not want them in this dataset. We will remove the data accordingly. If you have questions about use of the dataset or any research outputs in your products or services, we encourage you to undertake your own independent legal review. For other questions, please feel free to contact us.

- The two statements differ in what they cover. The model card and the mMARCO card state Apache-2.0. The MS MARCO page states non-commercial research purposes for the MS MARCO datasets. This study does not decide how these statements apply to a model trained on a translation of MS MARCO, or to the Commercial edition.
- Distribution. This study did not check whether the model file may be redistributed from another place.

## Owner questions

1. Rule result: the rule passes on held-out 2 for `mmarco` 8-bit, input with context, `pure@20`. Do you accept this result as the decision to build the reranker in tasks 7 to 9?
2. Training data terms: the text above. Do you accept the use of this model in the Community edition, and in the Commercial edition?

Tasks 7 to 9 run only on a "yes" to both.

## Owner decision

The owner decided after this gate:

- The licence and the data terms are accepted, for the Community edition and for the Commercial edition.
- The reranker is built with `pure@20` and context in the input. It is not built with `rrf2@20`.
- Only the best passage of each group is scored (20 pairs for each query), to fit the budget of 1500 ms. The best passage is the first passage of the group in the hybrid order.

Dev measurement of this configuration (8-bit model, input `full`, `pure@20`, one passage for each group). It was run on the dev queries only. The Task 6 study did not run held-out 2 for it. The Task 9 implementation ran held-out 2 one time with the shipped code (see "Held-out 2 for the shipped configuration").

| Scoring of a group | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse |
| --- | --- | --- | --- | --- | --- | --- |
| Hybrid | 0.615 | 0.703 | 0.737 | 0.653 | 6 | - |
| All passages (up to 3), the configuration of the held-out 2 run | 0.723 | 0.733 | 0.856 | 0.755 | 5 | 19 / 4 |
| Best passage only | 0.694 | 0.733 | 0.853 | 0.742 | 4 | 18 / 7 |

nDCG@10 by kind on dev (hybrid, all passages, best passage only): `short` 0.974, 0.928, 0.917. `context` 0.409, 0.522, 0.529. `exact` 0.998, 0.999, 0.983. `russian` 0.804, 0.804, 0.779. `cross-language` 0.162, 0.603, 0.557. `status` 0.512, 0.755, 0.729. Irr@5 of the `hard-negative` queries: 6, 5, 4.

Latency of 20 pairs, 8-bit model, input `full`, default threads, synthetic passages (see "Passages with real length"): 421 ms at about 300 tokens (p95 470 ms) and 660 ms at about 400 tokens (p95 720 ms). With the short passages of the corpus: 80 ms.

Stop rule R6 of the plan: stop when dev nDCG@10 is below 0.745 (0.755 minus 0.01) or dev Irr@5 is above 5. The best passage only has nDCG@10 0.742 and Irr@5 4. The nDCG@10 is 0.003 below the limit, so the rule says STOP. The Irr@5 is inside the limit. This is a result for the controller and the owner. The doc does not change the rule.

### Held-out 2 for the shipped configuration

The shipped configuration is the best passage only. The Task 9 run is `SearchHarness --eval eval-heldout-2.json --modes hybrid,rerank --context none` (Win64 Debug, batch size 1). It is one run. It is reported here and was not used to choose anything.

| Held-out 2 (37 judged queries) | Hybrid | All passages (study run, not shipped) | Best passage only (shipped) |
| --- | --- | --- | --- |
| nDCG@10 | 0.716 | 0.748 | 0.725 |
| R@10 | 0.696 | 0.727 | 0.727 |
| R@5 | 0.662 | 0.727 | 0.691 |
| MRR | 0.771 | 0.825 | 0.795 |
| Irr@5 | 2 | 0 | 0 |
| Better / worse queries | - | 9 / 3 | not computed |

The shipped gain in nDCG@10 is +0.009. The gain of the study configuration is +0.032. One query moves a mean by about 0.03, so +0.009 is smaller than the change of one query.

nDCG@10 by kind, hybrid to shipped: `paraphrase` 0.910 to 0.795, `status` 0.942 to 0.819, `short` 1.000 to 0.119, `cross-language` 0.000 to 0.200, `negated` 0.599 to 0.640, `context` 0.639 to 0.768. `exact`, `russian` and `mixed` do not change. The query k29 "py" is the only `short` query. It falls from 1.000 to 0.119 (0.174 in the study run).

The decision rule of the plan has four conditions. nDCG@10 rises (0.716 to 0.725), R@10 does not fall (0.696 to 0.727) and Irr@5 does not rise (2 to 0). The fourth condition, better minus worse queries at least 3, was not computed. The run did not write a per-query file, and the run is not repeated. The table by kind shows at least 3 kinds with worse queries and at least 3 kinds with better queries, but this does not give the counts. The result for the shipped configuration therefore does not show that the rule passes. It shows a gain that is within the change of one query.

## Limits of this result

- 53 and 37 judged queries on a corpus of 149 items. The held-out 2 gain of the study configuration (0.032 nDCG@10) is the size of the change of one query. The better minus worse count (9 / 3) is the stronger evidence for that configuration. The shipped configuration (best passage only) gains 0.009 on held-out 2, which is less than the change of one query, and its count is not computed.
- The dev choice was made on 8 configurations. The held-out 2 improvement for `full pure@20` is smaller than the dev improvement (0.102 on dev, 0.032 on held-out 2). For the shipped configuration the numbers are 0.089 on dev and 0.009 on held-out 2.
- `short` queries: dev d43 "Ni" falls 0.995 to 0.791 and d44 "Cr" 0.926 to 0.919, held-out 2 k29 "py" falls 1.000 to 0.174. A cross-encoder gives low scores to a bare token. A rule "do not rerank a query with one short token" was not tested.
- The hard-negative result is not stable: Irr@5 on dev with the chosen configuration is 5 (hybrid 6), on held-out 2 it is 0 (hybrid 2). There is no threshold, so the reranker only reorders.
- The corpus passages are short. The context line is up to 240 characters. On long real passages it is a smaller part of the input, and the quality gain from context may be different. This was not tested.
- The 8-bit file was not checked on a CPU without AVX2.

## Files

| File | Content |
| --- | --- |
| `ELN.Community.Tests/SearchHarness.dpr` | `--export-candidates` writes the field `context` (mode `full`) for every exported passage. |
| `tools/search-reference/rerank_study.py` | The commands `dev`, `heldout`, `heldout-2`, `onnx` and `latency`. New options: `--context none\|full`, `--fusions`, `--pairs`, `--passages all\|first`, `--allow-repeat`. The `latency` command (PyTorch) ignores `--context` and prints a warning. A held-out run of the log has the split name in its second column. |

How to repeat the study:

```powershell
SearchHarness.exe --eval eval-dev.json --modes hybrid --context none --export-candidates cand-dev.json --per-query hybrid-dev.tsv
python rerank_study.py onnx --model <model folder> --tag mmarco-int8 --onnx <onnx file> --context none --write-scores dev
python rerank_study.py dev --model <model folder> --tag mmarco-int8 --context none --fusions pure rrf2
python rerank_study.py onnx --model <model folder> --tag mmarco-int8 --onnx <onnx file> --context full --write-scores dev
python rerank_study.py dev --model <model folder> --tag mmarco-int8 --context full --fusions pure rrf2
python rerank_study.py dev --model <model folder> --tag mmarco-int8 --context full --fusions pure --passages first
SearchHarness.exe --eval eval-heldout-2.json --modes hybrid --context none --export-candidates cand-heldout-2.json --per-query hybrid-heldout-2.tsv
python rerank_study.py onnx --model <model folder> --tag mmarco-int8 --onnx <onnx file> --context full --write-scores heldout-2
python rerank_study.py heldout-2 --model <model folder> --tag mmarco-int8 --context full --config pure@20
python rerank_study.py onnx --model <model folder> --tag mmarco-int8 --onnx <onnx file> --context full --long-tokens 300 400 --pairs 60
```

The candidate files, the model files and the score caches are not in the repository.
