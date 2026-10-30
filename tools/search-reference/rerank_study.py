import argparse
import hashlib
import ctypes
import json
import math
import os
import statistics
import sys
import time
from ctypes import wintypes

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FIXTURES = os.path.join(ROOT, 'ELN.Community.Tests', 'Fixtures', 'Search')
WORK = os.path.join(os.environ.get('LOCALAPPDATA', '.'), 'APS-ELN', 'search-reference', 'rerank')
MODELS = os.path.join(os.environ.get('LOCALAPPDATA', '.'), 'APS-ELN', 'search-reference', 'rerank-models')

RRF_K = 60
TOLERANCE = 1e-5
DEPTHS = (10, 20)
FAMILY = (('pure', None), ('rrf1', 1.0), ('rrf2', 2.0))
CONFIGS = ['%s@%d' % (name, depth) for name, _ in FAMILY for depth in DEPTHS]


def gain(grade):
    return 2 ** grade - 1


def discount(rank):
    return 1 / math.log2(rank + 1)


def grade_of(relevant, item):
    return relevant.get(item, 0)


def recall_at(ranked, relevant, k):
    total = sum(1 for g in relevant.values() if g > 0)
    if total == 0:
        return math.nan
    found = sum(1 for item in ranked[:k] if grade_of(relevant, item) > 0)
    return found / total


def reciprocal_rank(ranked, relevant):
    if not any(g > 0 for g in relevant.values()):
        return math.nan
    for i, item in enumerate(ranked):
        if grade_of(relevant, item) > 0:
            return 1 / (i + 1)
    return 0.0


def ndcg_at(ranked, relevant, k):
    if not any(g > 0 for g in relevant.values()):
        return math.nan
    dcg = sum(gain(grade_of(relevant, item)) * discount(i + 1) for i, item in enumerate(ranked[:k]))
    grades = sorted((g for g in relevant.values() if g > 0), reverse=True)
    ideal = sum(gain(g) * discount(i + 1) for i, g in enumerate(grades[:k]))
    return dcg / ideal


def count_at(ranked, items, k):
    return sum(1 for item in ranked[:k] if item in items)


def load_queries(path):
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    result = {}
    for q in data['queries']:
        result[q['id']] = {
            'kind': q['kind'],
            'text': q['text'],
            'relevant': {int(r['item']): int(r['grade']) for r in q.get('relevant', [])},
            'irrelevant': set(int(i) for i in q.get('irrelevant', [])),
        }
    return result


def load_candidates(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)['queries']


class Scorer:
    def __init__(self, model_dir, threads=None):
        import torch
        from transformers import AutoModelForSequenceClassification, AutoTokenizer
        self.torch = torch
        if threads:
            torch.set_num_threads(threads)
        self.tokenizer = AutoTokenizer.from_pretrained(model_dir)
        self.model = AutoModelForSequenceClassification.from_pretrained(model_dir)
        self.model.eval()
        self.batch = 16

    def score(self, query, passages):
        out = []
        with self.torch.inference_mode():
            for start in range(0, len(passages), self.batch):
                part = passages[start:start + self.batch]
                enc = self.tokenizer([query] * len(part), part, padding=True, truncation=True,
                                     max_length=512, return_tensors='pt')
                logits = self.model(**enc).logits
                out.extend(float(v) for v in logits.reshape(len(part), -1)[:, 0])
        return out


def passage_text(passage, context):
    if context == 'full' and passage.get('context'):
        return passage['context'] + '\n' + passage['text']
    return passage['text']


def score_candidates(scorer, candidates, context='none'):
    scores = {}
    for entry in candidates:
        texts = []
        index = []
        for gi, group in enumerate(entry['groups']):
            for pi, passage in enumerate(group['passages']):
                texts.append(passage_text(passage, context))
                index.append((gi, pi))
        values = scorer.score(entry['text'], texts)
        per_group = [[] for _ in entry['groups']]
        for (gi, _), value in zip(index, values):
            per_group[gi].append(value)
        scores[entry['id']] = per_group
    return scores


def hybrid_order(entry):
    return [g['item'] for g in entry['groups']] + list(entry['tail'])


def reorder(entry, group_scores, config):
    name, depth_text = config.split('@')
    depth = int(depth_text)
    weight = dict(FAMILY)[name]
    groups = entry['groups']
    depth = min(depth, len(groups))
    top = list(range(depth))
    by_score = sorted(top, key=lambda i: (-group_scores[i], i))
    if weight is None:
        order = by_score
    else:
        rerank_rank = {i: r + 1 for r, i in enumerate(by_score)}
        fused = {i: 1 / (RRF_K + i + 1) + weight / (RRF_K + rerank_rank[i]) for i in top}
        order = sorted(top, key=lambda i: (-fused[i], i))
    items = [groups[i]['item'] for i in order]
    items += [g['item'] for g in groups[depth:]]
    items += list(entry['tail'])
    return items


class Totals:
    def __init__(self):
        self.ndcg, self.r10, self.r5, self.mrr = [], [], [], []
        self.irr = 0
        self.irr_queries = 0

    def add(self, ranked, query):
        rel = query['relevant']
        for sink, value in ((self.ndcg, ndcg_at(ranked, rel, 10)), (self.r10, recall_at(ranked, rel, 10)),
                            (self.r5, recall_at(ranked, rel, 5)), (self.mrr, reciprocal_rank(ranked, rel))):
            if not math.isnan(value):
                sink.append(value)
        if query['irrelevant']:
            self.irr_queries += 1
            self.irr += count_at(ranked, query['irrelevant'], 5)

    def row(self):
        def mean(v):
            return sum(v) / len(v) if v else math.nan
        return {'ndcg10': mean(self.ndcg), 'r10': mean(self.r10), 'r5': mean(self.r5),
                'mrr': mean(self.mrr), 'irr5': self.irr, 'judged': len(self.ndcg)}


def evaluate(candidates, queries, orders):
    total = Totals()
    kinds = {}
    per_query = {}
    for entry in candidates:
        query = queries[entry['id']]
        ranked = orders[entry['id']]
        total.add(ranked, query)
        kinds.setdefault(query['kind'], Totals()).add(ranked, query)
        per_query[entry['id']] = {
            'kind': query['kind'],
            'ndcg10': ndcg_at(ranked, query['relevant'], 10),
            'irr5': count_at(ranked, query['irrelevant'], 5) if query['irrelevant'] else None,
            'top': ranked[:10],
        }
    return total.row(), {k: v.row() for k, v in kinds.items()}, per_query


def compare(base, other):
    better = worse = same = 0
    irr_fewer = irr_more = 0
    changes = []
    for qid, b in base.items():
        o = other[qid]
        if not math.isnan(b['ndcg10']):
            if o['ndcg10'] > b['ndcg10'] + TOLERANCE:
                better += 1
                changes.append((qid, b['kind'], 'better', b['ndcg10'], o['ndcg10']))
            elif o['ndcg10'] < b['ndcg10'] - TOLERANCE:
                worse += 1
                changes.append((qid, b['kind'], 'worse', b['ndcg10'], o['ndcg10']))
            else:
                same += 1
        if b['irr5'] is not None:
            if o['irr5'] < b['irr5']:
                irr_fewer += 1
                changes.append((qid, b['kind'], 'irr fewer', b['irr5'], o['irr5']))
            elif o['irr5'] > b['irr5']:
                irr_more += 1
                changes.append((qid, b['kind'], 'irr more', b['irr5'], o['irr5']))
    return {'better': better, 'worse': worse, 'same': same, 'irr_fewer': irr_fewer, 'irr_more': irr_more}, changes


def fmt(value):
    return '-' if value is None or (isinstance(value, float) and math.isnan(value)) else '%.3f' % value


def print_row(label, row):
    print('%-14s %6s %6s %6s %6s %6s %6s' % (label, row['judged'], fmt(row['r5']), fmt(row['r10']),
                                             fmt(row['mrr']), fmt(row['ndcg10']), row['irr5']))


def print_header():
    print('%-14s %6s %6s %6s %6s %6s %6s' % ('config', 'judged', 'R@5', 'R@10', 'MRR', 'nDCG@10', 'Irr@5'))


def decision(base_row, row, cmp):
    checks = {
        'nDCG@10 rises': row['ndcg10'] > base_row['ndcg10'] + TOLERANCE,
        'R@10 does not fall': row['r10'] >= base_row['r10'] - TOLERANCE,
        'better - worse >= 3': cmp['better'] - cmp['worse'] >= 3,
        'Irr@5 does not rise': row['irr5'] <= base_row['irr5'],
    }
    return all(checks.values()), checks


def read_tsv_means(path):
    rows = {}
    with open(path, encoding='utf-8-sig') as f:
        next(f)
        for line in f:
            p = line.rstrip('\n').split('\t')
            rows[p[1]] = math.nan if p[3] == '-' else float(p[3])
    return rows


def heldout_runs(args, split):
    path = os.path.join(args.work, 'heldout-runs.log')
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8') as f:
        return [line for line in f if line.split('\t')[1:2] == [split]]


def score_tag(args):
    return args.tag + ('-ctx' if args.context == 'full' else '')


def scores_path(args, tag, split):
    with open(os.path.join(args.work, 'cand-%s.json' % split), 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()[:12]
    return os.path.join(args.work, 'scores-%s-%s-%s.json' % (tag, split, digest))


def cached_scores(args, split, candidates, tag):
    path = scores_path(args, tag, split)
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    scorer = Scorer(args.model)
    started = time.perf_counter()
    scores = score_candidates(scorer, candidates, args.context)
    print('scored %s %s in %.1f s' % (tag, split, time.perf_counter() - started))
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(scores, f)
    return scores


def group_scores_of(scores, qid, passages='all'):
    if passages == 'first':
        return [values[0] for values in scores[qid]]
    return [max(values) for values in scores[qid]]


def run_study(args, split):
    candidates = load_candidates(os.path.join(args.work, 'cand-%s.json' % split))
    queries = load_queries(os.path.join(FIXTURES, 'eval-%s.json' % split))
    tag = score_tag(args)
    hybrid_orders = {e['id']: hybrid_order(e) for e in candidates}
    base_row, base_kinds, base_pq = evaluate(candidates, queries, hybrid_orders)
    tsv = os.path.join(args.work, 'hybrid-%s.tsv' % split)
    if not os.path.exists(tsv):
        raise SystemExit('missing %s: export it with SearchHarness --per-query' % tsv)
    expected = read_tsv_means(tsv)
    for qid, pq in base_pq.items():
        if abs(pq['ndcg10'] - expected[qid]) > 1e-5 and not (math.isnan(pq['ndcg10']) and math.isnan(expected[qid])):
            raise SystemExit('hybrid order of %s does not match %s' % (qid, tsv))
    if split.startswith('heldout'):
        if not args.config or args.config not in CONFIGS:
            raise SystemExit('%s needs --config from %s' % (split, CONFIGS))
        configs = [args.config]
        if split == 'heldout-2' and not args.allow_repeat and heldout_runs(args, split):
            raise SystemExit('heldout-2 was already run (see heldout-runs.log); --allow-repeat to run again')
    else:
        configs = [c for c in CONFIGS if c.split('@')[0] in args.fusions]
    scores = cached_scores(args, split, candidates, tag)
    print('Split %s, model %s, %d queries' % (split, tag, len(candidates)))
    print_header()
    print_row('hybrid', base_row)
    results = {}
    for config in configs:
        orders = {e['id']: reorder(e, group_scores_of(scores, e['id'], args.passages), config)
                  for e in candidates}
        row, kinds, pq = evaluate(candidates, queries, orders)
        cmp, changes = compare(base_pq, pq)
        results[config] = (row, kinds, pq, cmp, changes)
        print_row(config, row)
    print()
    print('%-14s %7s %7s %6s %9s %9s  %s' % ('config', 'better', 'worse', 'same', 'irr fewer', 'irr more', 'verdict'))
    for config in configs:
        row, kinds, pq, cmp, changes = results[config]
        ok, checks = decision(base_row, row, cmp)
        failed = [name for name, passed in checks.items() if not passed]
        print('%-14s %7d %7d %6d %9d %9d  %s' % (config, cmp['better'], cmp['worse'], cmp['same'],
                                                cmp['irr_fewer'], cmp['irr_more'],
                                                'PASS' if ok else 'fail: ' + '; '.join(failed)))
    if split == 'dev':
        best = max((c for c in configs if results[c][0]['r10'] >= base_row['r10'] - TOLERANCE),
                   key=lambda c: results[c][0]['ndcg10'], default=None)
        print('\nBest dev config with R@10 not below hybrid: %s' % best)
        shown = best or configs[0]
    else:
        shown = configs[0]
        with open(os.path.join(args.work, 'heldout-runs.log'), 'a', encoding='utf-8') as log:
            row = results[shown][0]
            log.write('%s\t%s\t%s\t%s\tndcg10=%.4f r10=%.4f r5=%.4f mrr=%.4f irr5=%d\n' % (
                time.strftime('%Y-%m-%d %H:%M:%S'), split, tag, shown, row['ndcg10'], row['r10'], row['r5'],
                row['mrr'], row['irr5']))
    row, kinds, pq, cmp, changes = results[shown]
    print('\nPer kind for %s (hybrid -> %s), nDCG@10 and Irr@5' % (shown, shown))
    for kind in base_kinds:
        print('%-14s %6s -> %6s   irr %s -> %s' % (kind, fmt(base_kinds[kind]['ndcg10']),
                                                   fmt(kinds[kind]['ndcg10']),
                                                   base_kinds[kind]['irr5'], kinds[kind]['irr5']))
    print('\nChanged queries for %s' % shown)
    for qid, kind, what, old, new in changes:
        print('  %-5s %-15s %-9s %s -> %s  %s' % (qid, kind, what, fmt(old), fmt(new), queries[qid]['text']))
    if args.per_query:
        with open(args.per_query, 'w', encoding='utf-8') as f:
            f.write('id\tkind\tndcg10\tirr5\n')
            for qid, item in pq.items():
                f.write('%s\t%s\t%s\t%s\n' % (qid, item['kind'], fmt(item['ndcg10']), item['irr5']))


class MemoryCounters(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD),
                ('PeakWorkingSetSize', ctypes.c_size_t), ('WorkingSetSize', ctypes.c_size_t),
                ('QuotaPeakPagedPoolUsage', ctypes.c_size_t), ('QuotaPagedPoolUsage', ctypes.c_size_t),
                ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t), ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                ('PagefileUsage', ctypes.c_size_t), ('PeakPagefileUsage', ctypes.c_size_t)]


def memory_mb():
    counters = MemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    kernel = ctypes.WinDLL('kernel32')
    psapi = ctypes.WinDLL('psapi')
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(MemoryCounters), wintypes.DWORD]
    if not psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(), ctypes.byref(counters), counters.cb):
        raise OSError('GetProcessMemoryInfo failed')
    return counters.WorkingSetSize / 2 ** 20, counters.PeakWorkingSetSize / 2 ** 20, counters.PeakPagefileUsage / 2 ** 20


def run_latency(args):
    candidates = load_candidates(os.path.join(args.work, 'cand-dev.json'))
    print('model %s, threads %s' % (args.tag, args.threads or 'default'))
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer
    before = memory_mb()
    started = time.perf_counter()
    scorer = Scorer(args.model, args.threads)
    load_s = time.perf_counter() - started
    after = memory_mb()
    print('torch threads %d' % torch.get_num_threads())
    print('load %.2f s, working set %.0f MB before, %.0f MB after load' % (load_s, before[0], after[0]))
    scorer.score('warm up', ['warm up text'] * 20)
    best_pairs, all_pairs = [], []
    for entry in candidates:
        query = entry['text']
        first = [g['passages'][0]['text'] for g in entry['groups'][:20]]
        every = [p['text'] for g in entry['groups'][:20] for p in g['passages']]
        started = time.perf_counter()
        scorer.score(query, first)
        best_pairs.append((time.perf_counter() - started) * 1000)
        started = time.perf_counter()
        scorer.score(query, every)
        all_pairs.append((time.perf_counter() - started) * 1000)
    pair_counts = [sum(len(g['passages']) for g in e['groups'][:20]) for e in candidates]
    peak = memory_mb()
    print('20 pairs (first passage of the top 20 groups): median %.0f ms, p95 %.0f ms, max %.0f ms' % (
        statistics.median(best_pairs), sorted(best_pairs)[int(0.95 * len(best_pairs)) - 1], max(best_pairs)))
    print('all passages of the top 20 groups (%d to %d pairs, median %d): median %.0f ms, p95 %.0f ms, max %.0f ms' % (
        min(pair_counts), max(pair_counts), statistics.median(pair_counts), statistics.median(all_pairs),
        sorted(all_pairs)[int(0.95 * len(all_pairs)) - 1], max(all_pairs)))
    print('working set now %.0f MB, peak working set %.0f MB, peak commit %.0f MB' % (peak[0], peak[1], peak[2]))


def run_onnx(args):
    import numpy as np
    import onnxruntime as ort
    from transformers import AutoTokenizer
    candidates = load_candidates(os.path.join(args.work, 'cand-dev.json'))
    before = memory_mb()
    started = time.perf_counter()
    options = ort.SessionOptions()
    if args.threads:
        options.intra_op_num_threads = args.threads
    session = ort.InferenceSession(args.onnx, options, providers=['CPUExecutionProvider'])
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    load_s = time.perf_counter() - started
    after = memory_mb()
    names = [i.name for i in session.get_inputs()]
    print('onnx %s inputs %s outputs %s' % (os.path.basename(args.onnx), names,
                                            [(o.name, o.shape) for o in session.get_outputs()]))
    print('load %.2f s, working set %.0f MB before, %.0f MB after load' % (load_s, before[0], after[0]))

    def score(query, passages):
        out = []
        for start in range(0, len(passages), 16):
            part = passages[start:start + 16]
            enc = tokenizer([query] * len(part), part, padding=True, truncation=True, max_length=512,
                            return_tensors='np')
            feed = {n: enc[n].astype(np.int64) for n in names}
            out.extend(float(v) for v in session.run(None, feed)[0].reshape(len(part), -1)[:, 0])
        return out

    score('warm up', ['warm up text'] * 20)
    times = []
    for entry in candidates:
        first = [passage_text(g['passages'][0], args.context) for g in entry['groups'][:20]]
        started = time.perf_counter()
        score(entry['text'], first)
        times.append((time.perf_counter() - started) * 1000)
    peak = memory_mb()
    print('20 pairs: median %.0f ms, p95 %.0f ms, max %.0f ms' % (
        statistics.median(times), sorted(times)[int(0.95 * len(times)) - 1], max(times)))
    print('working set now %.0f MB, peak working set %.0f MB' % (peak[0], peak[1]))
    times = []
    for entry in candidates:
        every = [passage_text(p, args.context) for g in entry['groups'][:20] for p in g['passages']]
        started = time.perf_counter()
        score(entry['text'], every)
        times.append((time.perf_counter() - started) * 1000)
    print('all passages of the top 20 groups: median %.0f ms, p95 %.0f ms, max %.0f ms' % (
        statistics.median(times), sorted(times)[int(0.95 * len(times)) - 1], max(times)))
    for tokens in args.long_tokens:
        pool = tokenizer(' '.join(p['text'] for e in candidates for g in e['groups'] for p in g['passages']),
                         add_special_tokens=False)['input_ids']
        times = []
        for number, entry in enumerate(candidates):
            start = (number * 997) % (len(pool) - args.pairs * tokens)
            prefix = ''
            if args.context == 'full':
                prefix = next((p['context'] for g in entry['groups'] for p in g['passages'] if p.get('context')), '')
                prefix += '\n'
            long_passages = [prefix + tokenizer.decode(pool[start + i * tokens:start + (i + 1) * tokens])
                             for i in range(args.pairs)]
            started = time.perf_counter()
            score(entry['text'], long_passages)
            times.append((time.perf_counter() - started) * 1000)
        print('%d pairs with passages of about %d tokens (context %s): median %.0f ms, p95 %.0f ms, max %.0f ms' % (
            args.pairs, tokens, args.context, statistics.median(times),
            sorted(times)[int(0.95 * len(times)) - 1], max(times)))
    for split in args.write_scores:
        split_candidates = load_candidates(os.path.join(args.work, 'cand-%s.json' % split))
        scores = {}
        for entry in split_candidates:
            per_group = []
            for group in entry['groups']:
                per_group.append(score(entry['text'], [passage_text(p, args.context) for p in group['passages']]))
            scores[entry['id']] = per_group
        with open(scores_path(args, score_tag(args), split), 'w', encoding='utf-8') as f:
            json.dump(scores, f)
        print('wrote scores for %s' % split)


def main():
    parser = argparse.ArgumentParser(description='Cross-encoder rerank study over the exported hybrid candidates')
    parser.add_argument('command', choices=['dev', 'heldout', 'heldout-2', 'latency', 'onnx'])
    parser.add_argument('--model', required=True, help='local model directory')
    parser.add_argument('--tag', required=True, help='short model name used for the score cache')
    parser.add_argument('--work', default=WORK)
    parser.add_argument('--config', help='heldout: the one configuration chosen on dev, for example pure@20')
    parser.add_argument('--per-query', help='write the nDCG@10 and Irr@5 of each query of the shown configuration')
    parser.add_argument('--threads', type=int, default=0)
    parser.add_argument('--onnx', help='onnx command: model file')
    parser.add_argument('--write-scores', nargs='*', default=[], choices=['dev', 'heldout', 'heldout-2'],
                        help='onnx command: score the candidates of these splits into the score cache of --tag')
    parser.add_argument('--long-tokens', type=int, nargs='*', default=[],
                        help='onnx command: also time pairs whose passages have about this many tokens')
    parser.add_argument('--pairs', type=int, default=20, help='onnx command: pairs for --long-tokens')
    parser.add_argument('--context', choices=['none', 'full'], default='none',
                        help='reranker input: passage text only, or the exported context line + newline + text')
    parser.add_argument('--fusions', nargs='*', default=[name for name, _ in FAMILY],
                        help='dev: the fusions to run, for example pure rrf2')
    parser.add_argument('--allow-repeat', action='store_true', help='heldout-2: run again although the log has a run')
    parser.add_argument('--passages', choices=['all', 'first'], default='all',
                        help='dev, heldout: score of a group = the largest score of its passages (all), or the score of the '
                             'first exported passage, the best by hybrid order (first)')
    args = parser.parse_args()
    if args.command == 'latency' and args.context != 'none':
        print('warning: the latency command (PyTorch) ignores --context; use the onnx command with --long-tokens')
    if args.command in ('dev', 'heldout', 'heldout-2'):
        run_study(args, args.command)
    elif args.command == 'latency':
        run_latency(args)
    else:
        run_onnx(args)


if __name__ == '__main__':
    sys.exit(main())
