"""Generate tokenizer and embedding reference fixtures from upstream tools.

Run once, outside the Delphi build, to refresh the fixtures under
ELN.Community.Tests/Fixtures/Search. See docs/search-embedding-foundation.md.
"""
import argparse
import hashlib
import json
import os
import platform
import sys

import numpy as np
import onnxruntime
import sentencepiece
import tokenizers
from tokenizers import Tokenizer

TOKENIZER_CASES = [
    ("empty", ""),
    ("ascii_word", "hello"),
    ("ascii_sentence", "Magnetron sputtering of a Mo/Si multilayer at 2.0 mTorr."),
    ("russian_sentence", "Плёнка потемнела и местами отслоилась от подложки."),
    ("mixed_ru_en", "XRR показала шероховатость 0,4 nm на интерфейсе Mo/Si."),
    ("query_prefix", "query: how hard is the coating"),
    ("passage_prefix", "passage: Nanoindentation with a Berkovich tip gave 17.5 GPa."),
    ("leading_trailing_spaces", "   spaced text   "),
    ("multiple_spaces", "a  b   c    d"),
    ("tabs_newlines", "line one\tcol\r\nline two\nline three"),
    ("nbsp_and_thin_space", "10\u00a0nm and 5\u2009K"),
    ("decomposed_cyrillic", "\u0438\u0306 \u0435\u0308\u0436"),
    ("decomposed_latin", "cafe\u0301 nai\u0308ve"),
    ("fullwidth", "\uff28\uff45\uff4c\uff4c\uff4f \uff11\uff12\uff13"),
    ("ligature_and_superscript", "\ufb01lm 10\u00b3 cm\u00b2 TiO\u2082"),
    ("units_and_symbols", "\u00b5m, \u00b1 0.1 \u00b0C, 5 \u00c5, \u2264 3 \u03a9"),
    ("greek_and_cjk", "\u03b1-Al\u2082O\u2083 \u6c27\u5316\u94dd \u30c1\u30bf\u30f3"),
    ("zero_width_and_soft_hyphen", "multi\u00adlayer zero\u200bwidth"),
    ("control_chars", "bell\u0007here and\u0001there"),
    ("special_token_literal", "strike <s>old</s> text"),
    ("mask_literal", "fill <mask> here"),
    ("unknown_char", "private \ue000 use and \U00020000 ext-b"),
    ("emoji_zwj", "team \U0001f469\u200d\U0001f52c ok \U0001f44d\U0001f3fd"),
    ("flags", "flags \U0001f1fa\U0001f1e6\U0001f1e9\U0001f1ea"),
    ("identifiers", "SMP-2024-017 run#42 file_v2.xrdml C:\\data\\x.csv"),
    ("numbers", "1.5e-3 2,5 -40 3/4 100%"),
    ("url_email", "https://example.org/a?b=1 user@example.org"),
    ("korean", "\ud55c\uad6d\uc5b4 \u1100\u1161\u11a8"),
    ("arabic_combining", "\u0645\u064e\u0631\u0652\u062d\u064e\u0628\u064b\u0627"),
    ("devanagari", "\u0928\u092e\u0938\u094d\u0924\u0947"),
    ("control_only", "\u0007\u0001"),
    ("special_only", "<s>"),
    ("special_adjacent", "text<s>x</s>y"),
    ("combining_after_control", "a\t\u0301b \u0301c"),
    ("ascii_two_marks", "o\u0302\u0301 u\u0308\u0304"),
    ("greek_with_tonos_decomposed", "\u03b1\u0301\u03bb\u03c6\u03b1"),
    ("variation_selector", "1\ufe0f x\u200d y\u200cz"),
    ("hebrew_points", "\u05e9\u05c1\u05b8\u05dc\u05d5\u05b9\u05dd"),
    ("long_word_no_spaces", "Pneumonoultramicroscopicsilicovolcanoconiosis" * 3),
    ("only_spaces", "     "),
]

EMBEDDING_TEXTS = [
    "query: film delaminates and corrodes after storage in air",
    "query: деградация покрытия во влажной атмосфере",
    "query: SMP-2024-017",
    "passage: After six weeks in humid air the coating turned hazy and started to peel at the edges.",
    "passage: Через месяц хранения на воздухе плёнка потемнела и местами отслоилась от подложки.",
    "passage: Plain",
    "passage: " + " ".join(["The multilayer period was checked by X-ray reflectivity."] * 4),
]

TRUNCATED_TEXT = "passage: " + "".join(["Thin film deposition parameters were recorded. "] * 120)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def spm_ids(sp, text):
    ids = []
    for piece_id in sp.encode(text):
        ids.append(3 if piece_id == sp.unk_id() else piece_id + 1)
    return [0] + ids + [2]


def mean_pool_normalize(hidden, mask):
    m = mask[..., None].astype(np.float32)
    summed = (hidden * m).sum(axis=1)
    counts = np.clip(m.sum(axis=1), 1e-9, None)
    pooled = summed / counts
    return pooled / np.linalg.norm(pooled, axis=1, keepdims=True)


def save_model(graph, path):
    import onnx
    from onnx import helper

    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    onnx.save(model, path)
    return onnx.__version__


def write_incompatible_models(out_dir):
    from onnx import TensorProto, helper

    float_ids = helper.make_graph(
        [helper.make_node("Identity", ["input_ids"], ["last_hidden_state"])],
        "incompatible",
        [helper.make_tensor_value_info("input_ids", TensorProto.FLOAT, ["batch", "tokens"])],
        [helper.make_tensor_value_info("last_hidden_state", TensorProto.FLOAT, ["batch", "tokens"])])
    save_model(float_ids, os.path.join(out_dir, "incompatible_model.onnx"))
    no_inputs = helper.make_graph(
        [helper.make_node("Constant", [], ["last_hidden_state"], value=helper.make_tensor(
            "value", TensorProto.FLOAT, [1, 1, 384], [0.0] * 384))],
        "no_inputs",
        [],
        [helper.make_tensor_value_info("last_hidden_state", TensorProto.FLOAT, [1, 1, 384])])
    return save_model(no_inputs, os.path.join(out_dir, "zero_input_model.onnx"))



def torch_vectors(torch_dir, tok, texts):
    import torch
    from transformers import AutoModel

    model = AutoModel.from_pretrained(torch_dir)
    model.eval()
    out = []
    with torch.no_grad():
        for text in texts:
            enc = tok.encode(text)
            ids = torch.tensor([enc.ids], dtype=torch.long)
            mask = torch.tensor([enc.attention_mask], dtype=torch.long)
            hidden = model(input_ids=ids, attention_mask=mask,
                           token_type_ids=torch.zeros_like(ids)).last_hidden_state.numpy()
            out.append(mean_pool_normalize(hidden, mask.numpy())[0])
    return out, torch.__version__


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--torch-dir")
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    tokenizer_path = os.path.join(args.model_dir, "tokenizer.json")
    model_path = os.path.join(args.model_dir, "model.onnx")
    spm_path = os.path.join(args.model_dir, "sentencepiece.bpe.model")
    tok = Tokenizer.from_file(tokenizer_path)
    sp = sentencepiece.SentencePieceProcessor(model_file=spm_path)

    long_text = " ".join(["Thin film deposition parameters were recorded for every run."] * 60)
    cases = []
    for name, text in TOKENIZER_CASES + [("overlength_600_words", long_text)]:
        enc = tok.encode(text)
        reference = spm_ids(sp, text)
        cases.append({
            "name": name,
            "text": text,
            "ids": enc.ids,
            "attention_mask": enc.attention_mask,
            "sentencepiece_ids": reference,
            "sentencepiece_agrees": reference == enc.ids,
        })

    batch_texts = ["query: short", "passage: a somewhat longer passage about XRR fitting"]
    padded = Tokenizer.from_file(tokenizer_path)
    padded.enable_padding(pad_id=1, pad_token="<pad>")
    batch = [{"text": t, "ids": e.ids, "attention_mask": e.attention_mask}
             for t, e in zip(batch_texts, padded.encode_batch(batch_texts))]

    provenance = {
        "generator": "tools/search-reference/generate_reference_fixtures.py",
        "python": platform.python_version(),
        "tokenizers": tokenizers.__version__,
        "sentencepiece": sentencepiece.__version__,
        "onnxruntime": onnxruntime.__version__,
        "numpy": np.__version__,
        "tokenizer_json_sha256": sha256_file(tokenizer_path),
        "sentencepiece_model_sha256": sha256_file(spm_path),
        "model_onnx_sha256": sha256_file(model_path),
    }

    with open(os.path.join(args.out_dir, "tokenizer_reference.json"), "w", encoding="utf-8", newline="\r\n") as f:
        json.dump({"provenance": provenance, "max_tokens": 512, "cases": cases, "padded_batch": batch},
                  f, ensure_ascii=False, indent=1)

    session = onnxruntime.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    vectors = []
    for text in EMBEDDING_TEXTS:
        enc = tok.encode(text)
        ids = np.array([enc.ids], dtype=np.int64)
        mask = np.array([enc.attention_mask], dtype=np.int64)
        hidden = session.run(["last_hidden_state"], {
            "input_ids": ids, "attention_mask": mask, "token_type_ids": np.zeros_like(ids)})[0]
        vectors.append(mean_pool_normalize(hidden, mask)[0])

    truncating = Tokenizer.from_file(tokenizer_path)
    truncating.enable_truncation(max_length=512)
    enc = truncating.encode(TRUNCATED_TEXT)
    ids = np.array([enc.ids], dtype=np.int64)
    mask = np.array([enc.attention_mask], dtype=np.int64)
    hidden = session.run(["last_hidden_state"], {
        "input_ids": ids, "attention_mask": mask, "token_type_ids": np.zeros_like(ids)})[0]
    truncated = {
        "text": TRUNCATED_TEXT,
        "source_token_count": len(tok.encode(TRUNCATED_TEXT).ids),
        "token_count": len(enc.ids),
        "vector": [round(float(x), 7) for x in mean_pool_normalize(hidden, mask)[0]],
    }

    torch_check = None
    if args.torch_dir:
        tvecs, torch_version = torch_vectors(args.torch_dir, tok, EMBEDDING_TEXTS)
        diffs = [float(np.max(np.abs(a - b))) for a, b in zip(vectors, tvecs)]
        cosines = [float(np.dot(a, b)) for a, b in zip(vectors, tvecs)]
        torch_check = {
            "torch": torch_version,
            "weights_sha256": sha256_file(os.path.join(args.torch_dir, "model.safetensors")),
            "max_abs_diff_per_text": diffs,
            "cosine_per_text": cosines,
        }

    with open(os.path.join(args.out_dir, "embedding_reference.json"), "w", encoding="utf-8", newline="\r\n") as f:
        json.dump({
            "provenance": provenance,
            "pooling": "mean over attention_mask, then L2 normalization",
            "dimension": int(vectors[0].shape[0]),
            "torch_cross_check": torch_check,
            "cases": [{"text": t, "vector": [round(float(x), 7) for x in v]}
                      for t, v in zip(EMBEDDING_TEXTS, vectors)],
            "truncated_case": truncated,
        }, f, ensure_ascii=False, indent=1)

    onnx_version = write_incompatible_models(args.out_dir)
    print("incompatible models written with onnx", onnx_version)
    disagree = [c["name"] for c in cases if not c["sentencepiece_agrees"]]
    print("cases", len(cases), "sentencepiece disagreements", disagree)
    if torch_check:
        print("torch max abs diff", max(torch_check["max_abs_diff_per_text"]))


if __name__ == "__main__":
    sys.exit(main())
