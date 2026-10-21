(function (root) {
  'use strict';

  const WEIGHT_TITLE = 8;
  const WEIGHT_HEADING = 5;
  const WEIGHT_KEYWORD = 4;
  const WEIGHT_BODY = 1;
  const PHRASE_BONUS = 3;
  const WORD_CHAR = /[\p{L}\p{N}]/u;

  function normalize(text) {
    return String(text || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
  }

  function tokenize(text) {
    return normalize(text).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  }

  function queryTerms(query) {
    const terms = tokenize(query);
    return terms.join('').length >= 2 ? terms : [];
  }

  function termMatches(token, term, isLast) {
    return isLast ? token.startsWith(term) : token === term;
  }

  function fieldHas(tokens, term, isLast) {
    return tokens.some((token) => termMatches(token, term, isLast));
  }

  function hasPhrase(tokens, terms) {
    if (terms.length < 2) return false;
    const last = terms.length - 1;
    for (let i = 0; i + last < tokens.length; i++) {
      let all = true;
      for (let k = 0; k <= last && all; k++) all = termMatches(tokens[i + k], terms[k], k === last);
      if (all) return true;
    }
    return false;
  }

  function scoreSection(fields, terms) {
    let score = 0;
    const last = terms.length - 1;
    for (let t = 0; t <= last; t++) {
      let best = 0;
      for (const [tokens, weight] of fields) {
        if (weight > best && fieldHas(tokens, terms[t], t === last)) best = weight;
      }
      if (best === 0) return 0;
      score += best;
    }
    return score;
  }

  function search(index, query, limit = 30) {
    const terms = queryTerms(query);
    if (!index || terms.length === 0) return [];
    const found = [];
    index.sections.forEach((section, order) => {
      const page = index.pages[section.page] || { title: '' };
      const heading = tokenize(section.title);
      const body = tokenize(section.text);
      const fields = [
        [tokenize(page.title), WEIGHT_TITLE],
        [heading, WEIGHT_HEADING],
        [tokenize((section.keywords || []).join(' ')), WEIGHT_KEYWORD],
        [body, WEIGHT_BODY]
      ];
      let score = scoreSection(fields, terms);
      if (score === 0) return;
      if (hasPhrase(heading, terms) || hasPhrase(body, terms)) score += PHRASE_BONUS;
      found.push({ order, section, score });
    });
    found.sort((a, b) => b.score - a.score || a.order - b.order);
    return found.slice(0, limit).map(({ section, score }) => ({
      page: section.page,
      anchor: section.anchor,
      title: section.title,
      path: section.path,
      score,
      snippet: snippet(section.text || section.title, terms)
    }));
  }

  function groupByPage(results) {
    const groups = [];
    const byPage = new Map();
    for (const result of results) {
      let group = byPage.get(result.page);
      if (!group) {
        group = { page: result.page, title: result.path[0], results: [] };
        byPage.set(result.page, group);
        groups.push(group);
      }
      group.results.push(result);
    }
    return groups;
  }

  function foldedWithMap(text) {
    let folded = '';
    const map = [];
    let offset = 0;
    for (const ch of text) {
      const f = normalize(ch);
      for (let i = 0; i < f.length; i++) map.push({ start: offset, end: offset + ch.length });
      folded += f;
      offset += ch.length;
    }
    return { folded, map };
  }

  function findMatches(text, terms) {
    const source = String(text || '');
    if (!terms || terms.length === 0) return [];
    const { folded, map } = foldedWithMap(source);
    const last = terms.length - 1;
    const ranges = [];
    let i = 0;
    while (i < folded.length) {
      if (!WORD_CHAR.test(folded[i])) { i++; continue; }
      let j = i;
      while (j < folded.length && WORD_CHAR.test(folded[j])) j++;
      const word = folded.slice(i, j);
      let length = 0;
      for (let t = 0; t <= last; t++) {
        if (termMatches(word, terms[t], t === last)) length = Math.max(length, t === last ? terms[t].length : word.length);
      }
      if (length > 0) ranges.push({ start: map[i].start, end: map[i + length - 1].end });
      i = j;
    }
    return ranges;
  }

  function snippet(text, terms, width = 160) {
    const source = String(text || '');
    const matches = findMatches(source, terms);
    let start = 0;
    if (matches.length > 0 && matches[0].start > 60) {
      start = matches[0].start - 60;
      const space = source.indexOf(' ', start);
      if (space >= 0 && space < matches[0].start) start = space + 1;
    }
    let end = Math.min(source.length, start + width);
    if (end < source.length) {
      const space = source.lastIndexOf(' ', end);
      if (space > start && (matches.length === 0 || space >= matches[0].end)) end = space;
    }
    const segments = [];
    let cursor = start;
    for (const m of matches) {
      if (m.end <= start || m.start >= end) continue;
      const s = Math.max(m.start, start);
      const e = Math.min(m.end, end);
      if (s > cursor) segments.push({ text: source.slice(cursor, s), hit: false });
      segments.push({ text: source.slice(s, e), hit: true });
      cursor = e;
    }
    if (cursor < end) segments.push({ text: source.slice(cursor, end), hit: false });
    if (start > 0) {
      if (segments.length === 0 || segments[0].hit) segments.unshift({ text: '…', hit: false });
      else segments[0].text = '…' + segments[0].text;
    }
    if (end < source.length) {
      const tail = segments[segments.length - 1];
      if (!tail || tail.hit) segments.push({ text: '…', hit: false });
      else tail.text += '…';
    }
    return segments;
  }

  function suggestPages(index, query, limit = 3) {
    const terms = tokenize(query);
    if (!index || terms.length === 0) return [];
    const suggestions = [];
    for (const group of index.groups) {
      for (const file of group.pages) {
        const page = index.pages[file];
        if (!page) continue;
        const words = tokenize(page.title);
        if (terms.some((term) => words.some((word) => word.startsWith(term)))) {
          suggestions.push({ page: file, title: page.title });
          if (suggestions.length >= limit) return suggestions;
        }
      }
    }
    return suggestions;
  }

  const api = { normalize, tokenize, search, groupByPage, findMatches, snippet, suggestPages };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.HelpSearch = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
