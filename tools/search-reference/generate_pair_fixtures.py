"""Generate the cross-encoder pair fixtures from upstream tools.

Run once, outside the Delphi build, to refresh the fixtures under
ELN.Community.Tests/Fixtures/Search:
  pair_reference.json            pair ids and reference logits
  crossencoder_wrong_shape.onnx  logits has shape [batch, 2]
  crossencoder_token_count.onnx  logits is the token count of each row, shape [batch, 1]

The pair ids come from the HuggingFace tokenizers library with the e5
tokenizer.json (the reranker reuses it). The logits come from Python ONNX
Runtime on the 8-bit reranker file, with the 10 pairs in one batch that is
padded to its longest row, the same batch that the Delphi test builds.
"""
import argparse
import hashlib
import json
import os
import platform
import sys

import numpy as np
import onnxruntime
import tokenizers
from tokenizers import Tokenizer

MAX_TOKENS = 512
QUERY_MAX_TOKENS = 64
PAD_ID = 1

SENTENCE_EN = "Thin film deposition parameters were recorded for every run. "
SENTENCE_RU = "Параметры осаждения тонкой плёнки записывали для каждого запуска. "
CONTEXT = "Multilayer deposition > Mo/Si production runs | Item: SMP-2024-017 | Synthesis | Magnetron sputtering"

LONG_QUERY = " ".join(
    "Which coating survived the humid storage test without any visible delamination, and what roughness "
    "did the X-ray reflectivity fit give for the Mo/Si interfaces after the heat treatment step number %d?" % n
    for n in range(1, 4))

PAIRS = [
    ("en_short", "how hard is the coating", "Nanoindentation with a Berkovich tip gave 17.5 GPa."),
    ("en_paraphrase", "film delaminates after storage in air",
     "After six weeks in humid air the coating turned hazy and started to peel at the edges."),
    ("ru_short", "деградация покрытия во влажной атмосфере",
     "Через месяц хранения на воздухе плёнка потемнела и местами отслоилась от подложки."),
    ("cross_ru_query_en_passage", "шероховатость границы раздела",
     "XRR gave an interface roughness of 0.4 nm for the Mo/Si multilayer."),
    ("cross_en_query_ru_passage", "interface roughness of the multilayer",
     "XRR показала шероховатость 0,4 nm на интерфейсе Mo/Si после отжига."),
    ("code_query", "SMP-2024-017", "Sample SMP-2024-017 was sputtered at 2.0 mTorr argon pressure."),
    ("context_prefixed", "magnetron sputtering pressure",
     CONTEXT + "\n" + "The argon pressure was held at 2.0 mTorr during the whole run."),
    ("context_prefixed_ru", "давление при напылении", CONTEXT + "\n" + "Давление аргона 2,0 мТорр поддерживали весь запуск."),
    ("empty_passage", "anything", ""),
    ("single_word", "py", "Python scripts were used for the XRR fit."),
    ("special_token_literal", "strike <s>old</s> text", "fill <mask> here and </s> there"),
    ("mixed_ru_en", "XRR fit Mo/Si", "Подгонка XRR для Mo/Si: толщина периода 7,0 nm, gamma 0,4."),
    ("numbers", "1.5e-3 mbar", "The base pressure was 1.5e-3 mbar, 2,5 sccm Ar, -40 V bias, 100% duty."),
    ("newlines", "line one", "line one\nline two\r\nline three\tcol"),
    ("spaces", "   spaced query   ", "a  b   c    d"),
    ("nbsp", "10\u00a0nm film", "A 10\u00a0nm and 5\u2009K reading was noted."),
    ("greek_cjk", "\u03b1-Al\u2082O\u2083", "\u6c27\u5316\u94dd and \u30c1\u30bf\u30f3 films"),
    ("emoji", "team \U0001f469\u200d\U0001f52c", "ok \U0001f44d\U0001f3fd flags \U0001f1fa\U0001f1e6"),
    ("unknown_chars", "private \ue000 use", "and \U00020000 ext-b"),
    ("long_word", "Pneumonoultramicroscopicsilicovolcanoconiosis", "Pneumonoultramicroscopicsilicovolcanoconiosis" * 3),
    ("negated", "coating that did not delaminate", "No delamination was seen after the humid storage test."),
    ("units_query", "hardness above 10 GPa", "Nanoindentation hardness was 17.5 GPa, reduced modulus 210 GPa."),
    ("ru_negated", "покрытие без отслоения", "После хранения отслоения плёнки не обнаружено, поверхность гладкая."),
    ("ru_code", "XRR-2231", "Отчёт XRR-2231: период 7,0 nm, шероховатость 0,4 nm."),
    ("ru_query_ru_passage_unrelated", "твёрдость покрытия", "Оптимизация схемы питания магнетрона не требовалась."),
    ("en_unrelated", "how hard is the coating", "The cleanroom was closed for maintenance on Friday."),
    ("three_languages", "dureza del recubrimiento", "Nanoindentation with a Berkovich tip gave 17.5 GPa."),
]


LOGIT_QUERY = "how hard is the coating"
LOGIT_PASSAGES = [
    "Nanoindentation with a Berkovich tip gave 17.5 GPa.",
    "After six weeks in humid air the coating turned hazy and started to peel at the edges.",
    "Через месяц хранения на воздухе плёнка потемнела и местами отслоилась от подложки.",
    "Твёрдость покрытия по Берковичу составила 17,5 ГПа.",
    CONTEXT + "\n" + "Vickers hardness HV 1800 was measured on the Mo/Si coating.",
    "The cleanroom was closed for maintenance on Friday.",
    "XRR gave an interface roughness of 0.4 nm for the Mo/Si multilayer.",
    "",
    "Hardness  and   modulus were taken from 12 indents at 5 mN.   ",
    "Thin film deposition parameters were recorded for every run. " * 120,
]


def build_long(sentence, count):
    return (sentence * count).strip()


def fit_passage(tok, query_ids, target_total):
    """Passage text whose full pair has exactly target_total tokens before truncation."""
    want = target_total - 4 - len(query_ids)
    words = SENTENCE_EN.split()
    text_words = []
    while True:
        text_words.append(words[len(text_words) % len(words)])
        ids = tok.encode(" ".join(text_words), add_special_tokens=False).ids
        if len(ids) >= want:
            break
    text = " ".join(text_words)
    while len(tok.encode(text, add_special_tokens=False).ids) > want:
        text = text.rsplit(" ", 1)[0]
    return text


def content_ids(tok, text):
    ids = tok.encode(text, add_special_tokens=False).ids
    if ids and ids[-1] == tok.token_to_id("\u2581"):
        ids = ids[:-1]
    return ids


def ref_pair(tok, query, passage):
    a = content_ids(tok, query)
    b = content_ids(tok, passage)
    a = a[:QUERY_MAX_TOKENS]
    b = b[:max(0, MAX_TOKENS - 4 - len(a))]
    return [0] + a + [2, 2] + b + [2], len(a), len(b)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def pad_batch(rows):
    width = max(len(r) for r in rows)
    ids = np.full((len(rows), width), PAD_ID, dtype=np.int64)
    mask = np.zeros((len(rows), width), dtype=np.int64)
    for i, r in enumerate(rows):
        ids[i, :len(r)] = r
        mask[i, :len(r)] = 1
    return ids, mask


def save_model(graph, path):
    import onnx
    from onnx import helper

    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    onnx.save(model, path)
    return onnx.__version__


def write_synthetic_models(out_dir):
    from onnx import TensorProto, helper

    def graph(name, out_dim):
        nodes = [
            helper.make_node("Cast", ["attention_mask"], ["mask_f"], to=TensorProto.FLOAT),
            helper.make_node("ReduceSum", ["mask_f", "axes"], ["count"], keepdims=1),
        ]
        if out_dim == 1:
            nodes.append(helper.make_node("Identity", ["count"], ["logits"]))
        else:
            nodes.append(helper.make_node("Concat", ["count", "count"], ["logits"], axis=1))
        return helper.make_graph(
            nodes, name,
            [helper.make_tensor_value_info("input_ids", TensorProto.INT64, ["batch", "tokens"]),
             helper.make_tensor_value_info("attention_mask", TensorProto.INT64, ["batch", "tokens"])],
            [helper.make_tensor_value_info("logits", TensorProto.FLOAT, ["batch", out_dim])],
            initializer=[helper.make_tensor("axes", TensorProto.INT64, [1], [1])])

    save_model(graph("wrong_shape", 2), os.path.join(out_dir, "crossencoder_wrong_shape.onnx"))
    return save_model(graph("token_count", 1), os.path.join(out_dir, "crossencoder_token_count.onnx"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokenizer", required=True, help="e5 tokenizer.json")
    parser.add_argument("--model", required=True, help="onnx/model_quint8_avx2.onnx of the reranker")
    parser.add_argument("--hf-reranker-dir", help="reranker folder with its own tokenizer.json, for a cross-check")
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    tok = Tokenizer.from_file(args.tokenizer)
    native = Tokenizer.from_file(args.tokenizer)
    native.enable_truncation(max_length=MAX_TOKENS, strategy="only_second")
    hf_reranker = None
    if args.hf_reranker_dir:
        from transformers import AutoTokenizer
        hf_reranker = AutoTokenizer.from_pretrained(args.hf_reranker_dir)

    pairs = [dict(name=n, query=q, passage=p) for n, q, p in PAIRS]

    query = "interface roughness of the multilayer"
    qids = tok.encode(query, add_special_tokens=False).ids
    for total in (511, 512, 513):
        text = fit_passage(tok, qids, total)
        pairs.append(dict(name="boundary_%d" % total, query=query, passage=text))
    pairs.append(dict(name="long_passage_en", query="how hard is the coating",
                      passage=build_long(SENTENCE_EN, 120)))
    pairs.append(dict(name="long_passage_ru", query="шероховатость границы раздела",
                      passage=build_long(SENTENCE_RU, 120)))
    pairs.append(dict(name="long_passage_with_context", query="magnetron sputtering pressure",
                      passage=CONTEXT + "\n" + build_long(SENTENCE_EN, 150)))
    pairs.append(dict(name="long_query_cut_to_64", query=LONG_QUERY, passage="Short passage about roughness."))
    pairs.append(dict(name="long_query_long_passage", query=LONG_QUERY, passage=build_long(SENTENCE_EN, 200)))
    pairs.append(dict(name="query_exactly_64_tokens", query=None, passage=build_long(SENTENCE_EN, 120)))
    pairs.append(dict(name="query_65_tokens", query=None, passage=build_long(SENTENCE_EN, 120)))
    pairs.append(dict(name="ru_long_passage_ru_query", query="отслоение покрытия после хранения",
                      passage=build_long(SENTENCE_RU, 80)))
    pairs.append(dict(name="ru_context_prefixed", query="шероховатость на интерфейсе",
                      passage="Мультислои > Mo/Si | Образец SMP-2024-017 | XRR\n" + build_long(SENTENCE_RU, 3)))
    pairs.append(dict(name="code_query_with_context", query="XRR-2231",
                      passage=CONTEXT + "\n" + "Report XRR-2231 lists the fitted period 7.0 nm."))

    words = SENTENCE_EN.split()
    for pair in pairs:
        if pair["name"] in ("query_exactly_64_tokens", "query_65_tokens"):
            want = 64 if pair["name"] == "query_exactly_64_tokens" else 65
            text_words = []
            while len(tok.encode(" ".join(text_words), add_special_tokens=False).ids) < want:
                text_words.append(words[len(text_words) % len(words)])
            if len(tok.encode(" ".join(text_words), add_special_tokens=False).ids) > want:
                text_words.pop()
                while len(tok.encode(" ".join(text_words), add_special_tokens=False).ids) < want:
                    text_words.append("a")
            pair["query"] = " ".join(text_words)
            got = len(tok.encode(pair["query"], add_special_tokens=False).ids)
            assert got == want, (pair["name"], got)

    assert len(pairs) == 40, len(pairs)

    cases = []
    native_checked = hf_checked = 0
    for pair in pairs:
        ids, a_len, b_len = ref_pair(tok, pair["query"], pair["passage"])
        entry = {"name": pair["name"], "query": pair["query"], "passage": pair["passage"], "ids": ids,
                 "query_tokens": a_len, "passage_tokens": b_len}
        if len(content_ids(tok, pair["query"])) <= QUERY_MAX_TOKENS:
            if pair["query"] == pair["query"].rstrip() and pair["passage"] == pair["passage"].rstrip():
                assert native.encode(pair["query"], pair["passage"]).ids == ids, ("native pair mismatch", pair["name"])
                native_checked += 1
            if hf_reranker is not None and pair["name"] not in ("special_token_literal", "empty_passage"):
                enc = hf_reranker(pair["query"], pair["passage"], truncation="only_second",
                                  max_length=MAX_TOKENS)["input_ids"]
                assert enc == ids, ("reranker tokenizer mismatch", pair["name"])
                hf_checked += 1
        cases.append(entry)

    group = {"query": LOGIT_QUERY, "passages": LOGIT_PASSAGES}
    rows = [ref_pair(tok, LOGIT_QUERY, text)[0] for text in LOGIT_PASSAGES]
    session = onnxruntime.InferenceSession(args.model, providers=["CPUExecutionProvider"])
    names = [i.name for i in session.get_inputs()]
    assert names == ["input_ids", "attention_mask"], names
    ids, mask = pad_batch(rows)
    batch = session.run(["logits"], {"input_ids": ids, "attention_mask": mask})[0]
    assert batch.shape == (len(rows), 1), batch.shape
    single = []
    for row in rows:
        i1, m1 = pad_batch([row])
        single.append(float(session.run(["logits"], {"input_ids": i1, "attention_mask": m1})[0][0, 0]))
    group["logits"] = [float(v) for v in batch[:, 0]]
    single_diff = max(abs(a - b) for a, b in zip(single, group["logits"]))

    provenance = {
        "generator": "tools/search-reference/generate_pair_fixtures.py",
        "python": platform.python_version(),
        "tokenizers": tokenizers.__version__,
        "onnxruntime": onnxruntime.__version__,
        "numpy": np.__version__,
        "tokenizer_json_sha256": sha256_file(args.tokenizer),
        "reranker_onnx_sha256": sha256_file(args.model),
        "trailing_whitespace": "a final lone U+2581 token (trailing whitespace) is dropped, as in the reranker tokenizer",
        "pair_template": "[0] + query[:64] + [2, 2] + passage[:512-4-len(query)] + [2]",
        "logit_batch": "the passages of logit_group in file order, one batch padded to the longest row with id %d" % PAD_ID,
        "max_abs_diff_batch_vs_single": single_diff,
    }
    with open(os.path.join(args.out_dir, "pair_reference.json"), "w", encoding="utf-8", newline="\r\n") as f:
        json.dump({"provenance": provenance, "max_tokens": MAX_TOKENS, "query_max_tokens": QUERY_MAX_TOKENS,
                   "cases": cases, "logit_group": group}, f, ensure_ascii=False, indent=1)

    onnx_version = write_synthetic_models(args.out_dir)
    print("pairs", len(cases), "native pair checks", native_checked, "reranker tokenizer checks", hf_checked)
    print("logits", [round(v, 5) for v in group["logits"]])
    print("max abs diff batch vs single", single_diff)
    print("synthetic models written with onnx", onnx_version)


if __name__ == "__main__":
    sys.exit(main())
