# Semantic search, stage 5: reranker study

This study asks one question. Does a cross-encoder reranker, applied to the top 20 item groups of the hybrid search, raise nDCG@10 on the held-out queries enough to justify its cost? The study ran in Python. No reranker code is in the Delphi product. See `docs/search-stage-5.md` for the corpus, the queries, the metrics and the hybrid baseline.

**Baseline of the numbers.** All numbers below were measured on the first 40 queries of each query file, against a hybrid search with the words list at weight 0 (lists 0:1:1, the setting that the first tuning round adopted). The second tuning round added `short` and `mixed` queries to both files and returned the default to all weights 1 (see `docs/search-stage-5.md`, "Short and mixed queries"). The reranker study was not run again. Its "hybrid" columns and the candidate files describe the 0:1:1 hybrid search on 40 queries per file. The default hybrid search now has other values, so these results need a new run before a decision uses them.

## Decision

**Adopt (owner decision needed, separate plan).** The model is `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1`, in its 8-bit ONNX form (118.6 MB), with the fusion `rrf2@20` (defined below). The other model, `BAAI/bge-reranker-v2-m3`, is not adopted.

| Held-out (36 judged queries) | Hybrid (Task 3) | `mmarco`, 32-bit | `mmarco`, 8-bit ONNX | `bge-reranker-v2-m3` |
| --- | --- | --- | --- | --- |
| nDCG@10 | 0.743 | 0.843 | 0.831 | 0.853 |
| R@10 | 0.796 | 0.824 | 0.810 | 0.824 |
| R@5 | 0.755 | 0.782 | 0.796 | 0.759 |
| MRR | 0.783 | 0.877 | 0.863 | 0.903 |
| Irr@5 | 4 | 4 | 3 | 5 |
| Better / worse queries | - | 10 / 3 | 9 / 4 | 10 / 3 |
| Task 3 rule | - | passes | passes | fails (Irr@5 rises) |

The 8-bit model costs about 119 MB of download and about 450 MB of extra memory. It adds about 50 ms to a search with short passages, and about 260 ms with passages of 256 tokens (16 cores). Read "Cost" and "Limits" before you decide. The decision rests on a small synthetic corpus. It needs a check on a copy of a real notebook before the reranker becomes a default.

## Read this first

The corpus and the queries are synthetic, and small (149 items, 36 judged queries in each file). This is not a benchmark. One query moves a mean by about 0.03. The passages of this corpus are short (median 16 tokens, longest 67 tokens). The passages of a real notebook are longer (up to 1200 characters). All cost numbers below are for short passages, unless a row says other.

## Method

1. `SearchHarness --eval FILE --modes hybrid --export-candidates FILE` writes, for each query, the top 20 item groups of the default hybrid search. A group has the item id, the score of the group and up to 3 passages (key, field and the text). The passage text comes from the evaluation passages of the harness, not from the index store. The file also lists the item ids after rank 20 (`tail`), so that MRR and the metrics keep the exact rank of every item.
2. `tools/search-reference/rerank_study.py` reads this file and the query file. It scores the pair (query, passage) for every passage of every group. The score of a group is the largest score of its passages. A cross-encoder gives a raw logit. The script uses it only to order groups. It is not a probability, and there is no threshold.
3. The script computes R@5, R@10, MRR, nDCG@10 and Irr@5 with the same definitions as `ELN.Search/unit_SearchMetrics.pas`. It first checks that the hybrid order that it rebuilds from the export has the same per-query nDCG@10 as `--per-query` of the harness.
4. The script compares each query with the hybrid order. A query is better or worse when its nDCG@10 changes by more than 0.00001. It applies the Task 3 rule: held-out nDCG@10 rises, R@10 does not fall, better minus worse is at least 3, Irr@5 does not rise.

The family of settings was fixed before the first run. Each setting reorders the first D groups of the hybrid list (D is 10 or 20). The groups after D keep their hybrid order.

| Name | Order of the first D groups |
| --- | --- |
| `pure@D` | By the reranker score only. |
| `rrf1@D` | By `1 / (60 + hybrid rank) + 1 / (60 + reranker rank)`. |
| `rrf2@D` | By `1 / (60 + hybrid rank) + 2 / (60 + reranker rank)`. |

Rules of the study (the same as Task 3):

- A setting is chosen on the dev queries only. For each model, the setting with the best dev nDCG@10 among the settings whose dev R@10 does not fall is run on the held-out queries. Each other setting is not run on the held-out queries. The script refuses to run a held-out query set without an explicit `--config`.
- Every held-out run is written to `heldout-runs.log` in the work folder. There are three runs, listed in "Held-out runs".

Both models have a license that allows redistribution as a download. The model card of each model says `license: apache-2.0` (read on 2026-10-29, revisions `1427fd652930e4ba29e8149678df786c240d8825` for `mmarco` and `953dc6f6f85a1b2dbfca4c34a2796e7dde08d41e` for `bge`). Neither repository has a separate license file. The `mmarco` model was trained on mMARCO, a machine-translated MS MARCO. Ask the owner to confirm that the terms of this training data allow the intended use before adoption. This study did not check them.

The model files are in `%LOCALAPPDATA%\APS-ELN\search-reference\rerank-models`, not in the repository. The python environment is `%LOCALAPPDATA%\Temp\eln-ref-venv` (torch 2.14.1+cpu, transformers 5.21.0, onnxruntime 1.31.1). Machine: AMD Ryzen 9 9950X3D, 16 cores, 32 logical processors.

## Results on the dev queries

Hybrid reference on dev: R@5 0.662, R@10 0.708, MRR 0.808, nDCG@10 0.694, Irr@5 7. The column "Better / worse" counts the 36 judged dev queries.

### `mmarco` (32-bit, PyTorch)

| Setting | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse | Rule |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pure@10` | 0.681 | 0.708 | 0.769 | 0.692 | 3 | 8 / 8 | fails (nDCG@10 does not rise) |
| `pure@20` | 0.736 | 0.745 | 0.775 | 0.736 | 4 | 10 / 7 | passes |
| `rrf1@10` | 0.699 | 0.708 | 0.813 | 0.707 | 6 | 7 / 2 | passes |
| `rrf1@20` | 0.713 | 0.757 | 0.834 | 0.751 | 6 | 10 / 2 | passes |
| `rrf2@10` | 0.699 | 0.708 | 0.857 | 0.742 | 5 | 9 / 3 | passes |
| `rrf2@20` | 0.736 | 0.764 | 0.821 | 0.759 | 4 | 12 / 4 | passes, best |

### `bge-reranker-v2-m3` (32-bit, PyTorch)

| Setting | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse | Rule |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pure@10` | 0.657 | 0.708 | 0.834 | 0.725 | 7 | 8 / 5 | passes |
| `pure@20` | 0.704 | 0.771 | 0.860 | 0.779 | 6 | 13 / 3 | passes, best |
| `rrf1@10` | 0.708 | 0.708 | 0.860 | 0.727 | 8 | 7 / 2 | fails (Irr@5 rises) |
| `rrf1@20` | 0.713 | 0.755 | 0.855 | 0.755 | 7 | 11 / 2 | passes |
| `rrf2@10` | 0.694 | 0.708 | 0.842 | 0.721 | 7 | 8 / 4 | passes |
| `rrf2@20` | 0.715 | 0.755 | 0.849 | 0.754 | 7 | 12 / 3 | passes |

### `mmarco` (8-bit ONNX, `onnx/model_quint8_avx2.onnx`)

This is the file that a Delphi port would ship. It was checked on the dev queries with the same family of settings. The best setting is the same as for the 32-bit model.

| Setting | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse | Rule |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pure@10` | 0.690 | 0.708 | 0.765 | 0.694 | 3 | 7 / 7 | fails (nDCG@10 does not rise) |
| `pure@20` | 0.736 | 0.755 | 0.780 | 0.740 | 4 | 10 / 7 | passes |
| `rrf1@10` | 0.699 | 0.708 | 0.816 | 0.711 | 6 | 7 / 2 | passes |
| `rrf1@20` | 0.713 | 0.757 | 0.805 | 0.731 | 6 | 10 / 2 | passes |
| `rrf2@10` | 0.699 | 0.708 | 0.857 | 0.745 | 4 | 8 / 2 | passes |
| `rrf2@20` | 0.729 | 0.755 | 0.830 | 0.762 | 5 | 11 / 3 | passes, best |

Choice on dev: `rrf2@20` for `mmarco`, and `pure@20` for `bge-reranker-v2-m3`. A deeper rerank (20) is better than 10 for every setting. Mixing the hybrid rank in (`rrf`) helps `mmarco` and does not help `bge`.

## Held-out runs

Three runs of the held-out queries, in this order. Each run uses one setting that was chosen on dev. Hybrid reference: R@5 0.755, R@10 0.796, MRR 0.783, nDCG@10 0.743, Irr@5 4.

| Run | Model and setting | R@5 | R@10 | MRR | nDCG@10 | Irr@5 | Better / worse | Irr@5 fewer / more queries | Rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `mmarco` 32-bit, `rrf2@20` | 0.782 | 0.824 | 0.877 | 0.843 | 4 | 10 / 3 | 1 / 1 | passes |
| 2 | `bge-reranker-v2-m3`, `pure@20` | 0.759 | 0.824 | 0.903 | 0.853 | 5 | 10 / 3 | 0 / 1 | fails: Irr@5 rises from 4 to 5 |
| 3 | `mmarco` 8-bit ONNX, `rrf2@20` | 0.796 | 0.810 | 0.863 | 0.831 | 3 | 9 / 4 | 2 / 1 | passes |

Run 3 uses the file that a port would ship. It is the same setting as run 1, on the 8-bit model. It is a check of the quantization and not a new choice.

### nDCG@10 by kind (held-out)

| Kind | Hybrid | Run 1 (`mmarco`) | Run 2 (`bge`) |
| --- | --- | --- | --- |
| exact | 0.966 | 1.000 | 0.889 |
| paraphrase | 0.817 | 0.908 | 0.947 |
| russian | 0.884 | 0.884 | 0.884 |
| cross-language | 0.381 | 0.741 | 0.817 |
| negated | 0.699 | 0.699 | 0.699 |
| status | 0.814 | 0.763 | 0.786 |

- The gain comes mostly from `cross-language` queries. This is the kind where the hybrid search is weakest. In run 1, seven of the eight queries get better.
- `bge` lowers `exact` queries (code `XRR-2231`: nDCG@10 1.000 to 0.333). `mmarco` does not lower them. A possible reason, not tested: a large model gives low scores to a bare code.
- `status` queries get worse in both runs (h36 "proposed purchases that were not yet ordered"). The cross-encoder does not read "not yet" better than the hybrid search.
- `negated` and `russian` queries do not change on the held-out queries. On dev, `negated` rises (0.654 to 0.789).
- The hard-negative queries do not improve in a stable way. Irr@5 on the held-out queries is 4 for the hybrid search, and 4, 5 and 3 for the three runs. On dev it is 7 for the hybrid search, and 4 (`mmarco` 32-bit), 6 (`bge`) and 5 (`mmarco` 8-bit) for the chosen settings. There is no threshold, so a reranker does not remove the listed irrelevant items. It only reorders them.

## Cost

All timings: CPU, no GPU, 40 dev queries, a warm-up pass first. The harness hybrid search takes 4.4 ms on average (query embedding included).

| | `mmarco` 32-bit (PyTorch) | `mmarco` 8-bit (ONNX Runtime 1.31.1) | `bge-reranker-v2-m3` 32-bit (PyTorch) |
| --- | --- | --- | --- |
| Model file | 470.6 MB (`model.safetensors`) | 118.6 MB (`onnx/model_quint8_avx2.onnx`) | 2271 MB (`model.safetensors`) |
| Parameters | about 118 M | about 118 M | about 568 M |
| Load time (process with libraries loaded) | 2.3 s | 1.7 s | 3.4 s |
| Working set after load | 1069 MB (225 MB before) | 695 MB (242 MB before) | 2787 MB (226 MB before) |
| Peak working set | 1352 MB | 744 MB | 2952 MB |
| 20 pairs, median (first passage of the top 20 groups), default threads | 91 ms | 48 ms | 872 ms |
| 20 pairs, median, 4 threads | 264 ms | 90 ms | 3200 ms |
| All passages of the top 20 groups (27 to 42 pairs), median, default threads | 134 ms | 73 ms | 1352 ms |
| All passages, median, 4 threads | 420 ms | 142 ms | 5133 ms |

The 8-bit ONNX numbers are for short passages. The next table uses 20 pairs whose passages have a fixed length (text of the corpus cut at a token count), 8-bit ONNX.

| Passage length | Default threads (median) | 4 threads (median) |
| --- | --- | --- |
| about 16 tokens (the corpus) | 48 ms | 90 ms |
| 128 tokens | 107 ms | 212 ms |
| 256 tokens | 258 ms | 512 ms |
| 512 tokens (the model limit) | 822 ms | 1347 ms |

A passage in a real notebook has up to 1200 characters, which is about 300 to 400 tokens. A rerank of 20 groups, with one passage for each group, then costs 0.25 to 0.8 s on this machine with the default threads, and 0.5 to 1.3 s with 4 threads (see the table above). A slower machine takes more time. The `bge` model is too slow and too large for a desktop search (0.9 s on a fast machine for short passages only). It does not pass the rule. It is not adopted. There is no ONNX file for it in its repository. This study did not export one.

The reranker adds a second ONNX session, and the e5 embedder stays. The memory of the 32-bit `mmarco` model (about 470 MB) is as large as the e5 model. The 8-bit file is 4 times smaller.

## What a Delphi port needs

- Pair input. The model reads `<s> query </s></s> passage </s>`. In ids: `[BosId] + EncodeContent(query) + [EosId, EosId] + EncodeContent(passage) + [EosId]`. This is the XLM-R pair template (`TemplateProcessing` in the `tokenizer.json` of both models). The script checked it against the HuggingFace tokenizer on 1600 pairs for each model, with no difference. `TUnigramTokenizer` has only `Encode` and `EncodeContent`. A port adds a pair function (`EncodePair`), and a truncation rule for a total of 512 tokens (the HuggingFace default is `longest_first`; for this use, cut the passage).
- Tokenizer files. The model has the same `sentencepiece.bpe.model` as `multilingual-e5-small` (same SHA-256). `EncodeContent` of the e5 `tokenizer.json` (read with the HuggingFace `tokenizers` library) gives the same ids as the tokenizer of both reranker models on 534 query and passage texts (0 differences). The `tokenizer.json` of `mmarco` has another normalizer (a single `Precompiled`) and another pre-tokenizer (`Sequence` of `WhitespaceSplit` and `Metaspace`). `TUnigramTokenizer.CreateFromFile` refuses both. A port reuses the e5 tokenizer files and downloads no tokenizer.
- Model inputs and output. Inputs: `input_ids` and `attention_mask`, both int64, shape `[batch, length]`, no `token_type_ids`. The padding id is 1. Output: `logits`, float32, shape `[batch, 1]`. The score is the raw logit. Use it for the order only.
- Manifest. A new entry in `search-artifacts.json` for one file (`onnx/model_quint8_avx2.onnx`, 118,620,016 bytes) with its SHA-256, the revision and the license. The setup dialog and the installer need a second optional model. The study did not check the 8-bit file on a CPU without AVX2.
- Search service. The reranker runs after the live visibility check and after grouping, on the first 20 groups, with the stored passage text of up to 3 passages for each group. It adds no field of a hidden item. The fusion is `rrf2@20`: for the first 20 groups, order by `1 / (60 + hybrid rank) + 2 / (60 + reranker rank)`.
- Cost control. The rerank is slow on long passages. Run it off the UI thread, with the cancel check that the search already has. Show the hybrid result first, and then the reranked result, or make the reranker an option that is off by default. The latency table above is the input for this choice.

## Limits of this result

- 36 judged queries in each file, on a corpus of 149 items. For the 8-bit model that is adopted, the held-out gain is 0.088 nDCG@10 and the dev gain is 0.068. For the 32-bit model they are 0.100 and 0.065. The gains have the same direction and the same cause (`cross-language` and `paraphrase` queries). A real notebook can give another result.
- The relevant items of the `cross-language` queries have no twin in the query language. A real notebook often has twins (a Russian and an English title). The gain there can be smaller.
- The passages are short. A cross-encoder reads the query and the passage together. A long passage is a different test, with a different cost.
- The corpus has no long query and no query in a third language. mMARCO has 14 languages. The corpus uses English and Russian only.
- The group has at most 3 passages, and they are the passages that the fusion found, not all passages of the item. A reranker that sees the title of the item with each passage can give a different result. It was not tested.
- The 8-bit model was checked only as a second view of the same chosen setting. One more setting was not chosen on it.
- The exact queries are not hurt by `mmarco`. A rule "do not rerank a query that has a digit and no space" was not tested and is not needed for this model.

## Files

| File | Content |
| --- | --- |
| `ELN.Community.Tests/SearchHarness.dpr` | The option `--export-candidates FILE` of `--eval`. |
| `tools/search-reference/rerank_study.py` | The study script (`dev`, `heldout`, `latency`, `onnx` commands). |

How to repeat the study (the venv and the model folders are in `%LOCALAPPDATA%`):

```powershell
SearchHarness.exe --eval eval-dev.json --modes hybrid --export-candidates cand-dev.json --per-query hybrid-dev.tsv
SearchHarness.exe --eval eval-heldout.json --modes hybrid --export-candidates cand-heldout.json --per-query hybrid-heldout.tsv
python rerank_study.py dev --model <model folder> --tag mmarco
python rerank_study.py heldout --model <model folder> --tag mmarco --config rrf2@20
python rerank_study.py latency --model <model folder> --tag mmarco --threads 4
python rerank_study.py onnx --model <model folder> --tag mmarco-int8 --onnx <onnx file> --long-tokens 128 256 512
```

The candidate files, the model files and the score caches stay in `%LOCALAPPDATA%\APS-ELN\search-reference`. They are not in the repository.
