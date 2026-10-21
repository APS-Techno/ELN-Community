'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const HelpSearch = require('../ELN.Desktop/Assets/Runtime/Help/help-search.js');

function makeIndex(pages) {
  const index = { product: 'Test Help', home: 'Index.html', groups: [{ id: 'g', title: 'G', pages: [] }], pages: {}, sections: [] };
  for (const page of pages) {
    index.groups[0].pages.push(page.file);
    index.pages[page.file] = { title: page.title, summary: '', icon: '', group: 'g', listed: true, sections: [] };
    for (const section of page.sections) {
      const level = section.level || 2;
      if (level > 1) index.pages[page.file].sections.push({ anchor: section.anchor, title: section.title, level });
      index.sections.push({
        page: page.file,
        anchor: section.anchor || '',
        title: section.title || page.title,
        level,
        path: level > 1 ? [page.title, section.title] : [page.title],
        text: section.text || '',
        keywords: section.keywords || []
      });
    }
  }
  return index;
}

const keys = (results) => results.map((r) => r.page + '#' + r.anchor);

test('andMatchingRequiresAllWords', () => {
  const index = makeIndex([{ file: 'A.html', title: 'Alpha', sections: [
    { anchor: 'one', title: 'One', text: 'derived only here' },
    { anchor: 'two', title: 'Two', text: 'a derived value is computed' }
  ] }]);
  assert.deepEqual(keys(HelpSearch.search(index, 'derived value')), ['A.html#two']);
});

test('lastWordIsPrefix', () => {
  const index = makeIndex([{ file: 'V.html', title: 'Numbers', sections: [
    { anchor: 'derived', title: 'Derived values', text: 'computed from inputs' }
  ] }]);
  assert.deepEqual(keys(HelpSearch.search(index, 'deriv')), ['V.html#derived']);
  assert.deepEqual(HelpSearch.search(index, 'deriv value'), []);
});

test('titleOutranksHeadingOutranksKeywordOutranksBody', () => {
  const index = makeIndex([
    { file: 'Body.html', title: 'P1', sections: [{ anchor: 'b', title: 'S', text: 'zebra' }] },
    { file: 'Kw.html', title: 'P2', sections: [{ anchor: 'k', title: 'S', text: '', keywords: ['zebra'] }] },
    { file: 'Head.html', title: 'P3', sections: [{ anchor: 'h', title: 'Zebra', text: '' }] },
    { file: 'Title.html', title: 'Zebra', sections: [{ anchor: 't', title: 'S', text: '' }] }
  ]);
  const results = HelpSearch.search(index, 'zebra');
  assert.deepEqual(keys(results), ['Title.html#t', 'Head.html#h', 'Kw.html#k', 'Body.html#b']);
  assert.deepEqual(results.map((r) => r.score), [8, 5, 4, 1]);
});

test('phraseBonus', () => {
  const index = makeIndex([{ file: 'A.html', title: 'P', sections: [
    { anchor: 'apart', title: 'S', text: 'unit of the converter' },
    { anchor: 'adjacent', title: 'S', text: 'the unit converter' }
  ] }]);
  const results = HelpSearch.search(index, 'unit converter');
  assert.deepEqual(keys(results), ['A.html#adjacent', 'A.html#apart']);
  assert.equal(results[0].score - results[1].score, 3);
});

test('tiesKeepIndexOrder', () => {
  const index = makeIndex([
    { file: 'A.html', title: 'P', sections: [{ anchor: 'x', title: 'S', text: 'tag' }, { anchor: 'y', title: 'S', text: 'tag' }] },
    { file: 'B.html', title: 'Q', sections: [{ anchor: 'z', title: 'S', text: 'tag' }] }
  ]);
  assert.deepEqual(keys(HelpSearch.search(index, 'tag')), ['A.html#x', 'A.html#y', 'B.html#z']);
});

test('accentsAndPunctuation', () => {
  const index = makeIndex([{ file: 'A.html', title: 'P', sections: [
    { anchor: 'r', title: 'S', text: 'Write a Résumé here' },
    { anchor: 'k', title: 'S', text: 'Press Ctrl + F to search' }
  ] }]);
  assert.deepEqual(keys(HelpSearch.search(index, 'resume')), ['A.html#r']);
  assert.deepEqual(keys(HelpSearch.search(index, 'ctrl+f')), ['A.html#k']);
});

test('singleCharacterQueryReturnsNothing', () => {
  const index = makeIndex([{ file: 'A.html', title: 'P', sections: [{ anchor: 'a', title: 'S', text: 'a b c' }] }]);
  assert.deepEqual(HelpSearch.search(index, 'a'), []);
  assert.deepEqual(HelpSearch.search(index, '  '), []);
});

test('resultCapIs30', () => {
  const sections = [];
  for (let i = 0; i < 40; i++) sections.push({ anchor: 's' + i, title: 'S', text: 'common' });
  const index = makeIndex([{ file: 'A.html', title: 'P', sections }]);
  assert.equal(HelpSearch.search(index, 'common').length, 30);
  assert.equal(HelpSearch.search(index, 'common', 5).length, 5);
});

test('specialCharactersAreLiteral', () => {
  const index = makeIndex([{ file: 'A.html', title: 'P', sections: [
    { anchor: 'i', title: 'S', text: 'an img tag' },
    { anchor: 'j', title: 'S', text: 'imaginary' }
  ] }]);
  for (const query of ['<img src=x>', '(', '*', '\\', '[', '(a)*[']) {
    assert.doesNotThrow(() => HelpSearch.search(index, query));
  }
  assert.deepEqual(keys(HelpSearch.search(index, '<img')), ['A.html#i']);
  assert.deepEqual(keys(HelpSearch.search(index, '<img x')), []);
});

test('findMatchesUsesOriginalOffsets', () => {
  assert.deepEqual(HelpSearch.findMatches('Résumé of values', ['resume', 'val']), [{ start: 0, end: 6 }, { start: 10, end: 13 }]);
});

test('snippetMarksHitsAndEllipsis', () => {
  const text = 'x'.repeat(300) + ' needle ' + 'y '.repeat(200);
  const segments = HelpSearch.snippet(text, ['needle'], 160);
  assert.equal(segments[0].text.startsWith('…'), true);
  assert.equal(segments.some((s) => s.hit && s.text === 'needle'), true);
  const visible = segments.map((s) => s.text).join('').length;
  assert.equal(visible <= 162, true);
});

test('groupByPageOrdersByBestScore', () => {
  const index = makeIndex([
    { file: 'A.html', title: 'Plain', sections: [{ anchor: 'a', title: 'S', text: 'word' }] },
    { file: 'B.html', title: 'Word', sections: [{ anchor: 'b', title: 'S', text: 'word' }] }
  ]);
  const groups = HelpSearch.groupByPage(HelpSearch.search(index, 'word'));
  assert.deepEqual(groups.map((g) => g.page), ['B.html', 'A.html']);
  assert.equal(groups[0].title, 'Word');
});

test('suggestPagesMatchesAnyTitleWord', () => {
  const index = makeIndex([
    { file: 'A.html', title: 'Values and units', sections: [{ anchor: '', level: 1, title: 'Values and units', text: '' }] },
    { file: 'B.html', title: 'Files', sections: [{ anchor: '', level: 1, title: 'Files', text: '' }] },
    { file: 'C.html', title: 'Unit converter', sections: [{ anchor: '', level: 1, title: 'Unit converter', text: '' }] }
  ]);
  assert.deepEqual(HelpSearch.search(index, 'unit zzz'), []);
  assert.deepEqual(HelpSearch.suggestPages(index, 'unit zzz'), [{ page: 'A.html', title: 'Values and units' }, { page: 'C.html', title: 'Unit converter' }]);
});
