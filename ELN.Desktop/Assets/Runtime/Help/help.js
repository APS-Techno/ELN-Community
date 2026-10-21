(function () {
  'use strict';

  const NARROW = 720;
  const index = window.HELP_INDEX;
  const search = window.HelpSearch;
  const main = document.querySelector('main');
  if (!main) return;

  function el(tag, attrs, children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (value === undefined || value === null || value === false) continue;
      if (key === 'text') node.textContent = value;
      else if (key === 'className') node.className = value;
      else node.setAttribute(key, value === true ? '' : value);
    }
    for (const child of children || []) if (child) node.append(child);
    return node;
  }

  function notice(text, extra) {
    const box = el('div', { className: 'help-notice', role: 'status' }, [el('span', { text })]);
    if (extra) box.append(' ', extra);
    main.prepend(box);
    return box;
  }

  if (!index || !search) {
    const missing = index ? 'help-search.js' : 'help-index.js';
    const detail = document.getElementById('help-topics') ? ' The topic list cannot be shown.' : ' The text of this page is complete.';
    notice('Help navigation and Help search are unavailable because ' + missing + ' is missing.' + detail);
    return;
  }

  const current = decodeURIComponent(location.pathname.split('/').pop() || index.home);
  const currentKey = Object.keys(index.pages).find((file) => file.toLowerCase() === current.toLowerCase()) || current;
  const currentPage = index.pages[currentKey];
  const listed = [];
  for (const group of index.groups) for (const file of group.pages) listed.push(file);

  if (currentPage) document.title = currentPage.title === index.product ? index.product : currentPage.title + ' — ' + index.product;
  document.body.classList.add('help-shell');

  function pageLink(file, anchor, query) {
    let href = encodeURI(file);
    if (query) href += '?q=' + encodeURIComponent(query);
    if (anchor) href += '#' + encodeURIComponent(anchor);
    return href;
  }

  function buildSectionList(page, file) {
    const list = el('ul', { className: 'help-sections' });
    let lastH2 = null;
    for (const section of page.sections) {
      const item = el('li', {}, [el('a', { href: pageLink(file, section.anchor), text: section.title })]);
      if (section.level === 3 && lastH2) {
        let nested = lastH2.querySelector('ul');
        if (!nested) { nested = el('ul'); lastH2.append(nested); }
        nested.append(item);
      } else {
        list.append(item);
        lastH2 = item;
      }
    }
    return list;
  }

  const toggle = el('button', { type: 'button', className: 'help-toc-toggle', 'aria-expanded': 'false', 'aria-controls': 'help-toc', text: 'Contents' });
  const input = el('input', { id: 'help-search-input', type: 'search', 'aria-label': 'Search Help', placeholder: 'Search Help (/)', autocomplete: 'off', role: 'combobox', 'aria-expanded': 'false', 'aria-controls': 'help-results' });
  const results = el('div', { id: 'help-results', role: 'listbox', 'aria-label': 'Help search results', hidden: true });
  const header = el('header', { className: 'help-bar' }, [
    toggle,
    el('a', { className: 'help-home', href: pageLink(index.home), text: index.product }),
    el('div', { className: 'help-search' }, [input, results])
  ]);

  const tocList = el('ul');
  if (currentPage && !currentPage.listed && currentPage.sections.length && currentKey !== index.home) {
    tocList.append(el('li', { className: 'help-group' }, [
      el('span', { text: currentPage.title }),
      buildSectionList(currentPage, currentKey)
    ]));
  }
  for (const group of index.groups) {
    const pages = el('ul');
    for (const file of group.pages) {
      const page = index.pages[file];
      const isCurrent = file === currentKey;
      const item = el('li', {}, [el('a', { href: pageLink(file), text: page.title, 'aria-current': isCurrent ? 'page' : null })]);
      if (isCurrent && page.sections.length) item.append(buildSectionList(page, file));
      pages.append(item);
    }
    tocList.append(el('li', { className: 'help-group' }, [el('span', { text: group.title }), pages]));
  }
  const toc = el('nav', { id: 'help-toc', className: 'help-toc', 'aria-label': 'Help contents' }, [tocList]);

  document.body.prepend(header, toc);
  const syncBarHeight = () => document.documentElement.style.setProperty('--help-bar-height', header.offsetHeight + 'px');
  syncBarHeight();
  window.addEventListener('resize', syncBarHeight);

  const position = listed.indexOf(currentKey);
  if (position >= 0) {
    const pager = el('nav', { className: 'help-pager', 'aria-label': 'Previous and next pages' });
    const prev = listed[position - 1];
    const next = listed[position + 1];
    pager.append(prev ? el('a', { rel: 'prev', href: pageLink(prev), text: '← ' + index.pages[prev].title }) : el('span'));
    pager.append(next ? el('a', { rel: 'next', href: pageLink(next), text: index.pages[next].title + ' →' }) : el('span'));
    main.append(pager);
  }

  const topics = document.getElementById('help-topics');
  if (topics) {
    for (const group of index.groups) {
      topics.append(el('h3', { text: group.title }));
      const list = el('ul', { className: 'topics' });
      for (const file of group.pages) {
        const page = index.pages[file];
        list.append(el('li', {}, [
          page.icon ? el('img', { className: 'icon-ref', src: page.icon, alt: '' }) : null,
          el('a', { href: pageLink(file), text: page.title }),
          page.summary ? el('p', { text: page.summary }) : null
        ]));
      }
      topics.append(list);
    }
  }

  function setDrawer(open) {
    document.body.classList.toggle('toc-open', open);
    toggle.setAttribute('aria-expanded', String(open));
  }
  toggle.addEventListener('click', () => setDrawer(!document.body.classList.contains('toc-open')));
  toc.addEventListener('click', (event) => { if (event.target.closest('a')) setDrawer(false); });

  let options = [];
  let active = -1;

  function setActive(next) {
    if (options.length === 0) return;
    active = (next + options.length) % options.length;
    options.forEach((option, i) => option.setAttribute('aria-selected', String(i === active)));
    input.setAttribute('aria-activedescendant', options[active].id);
    options[active].scrollIntoView({ block: 'nearest' });
  }

  function hideResults() {
    results.hidden = true;
    results.replaceChildren();
    options = [];
    active = -1;
    input.setAttribute('aria-expanded', 'false');
    input.removeAttribute('aria-activedescendant');
  }

  function renderResults() {
    const query = input.value;
    if (search.tokenize(query).join('').length < 2) { hideResults(); return; }
    const found = search.search(index, query);
    results.replaceChildren();
    options = [];
    active = -1;
    if (found.length === 0) {
      const empty = el('div', { className: 'help-empty' }, [el('p', { text: 'No Help results for "' + query.trim() + '".' })]);
      const suggestions = search.suggestPages(index, query);
      const links = el('p');
      if (suggestions.length) {
        links.append('Try: ');
        suggestions.forEach((s, i) => { if (i) links.append(', '); links.append(el('a', { href: pageLink(s.page), text: s.title })); });
      } else {
        links.append(el('a', { href: pageLink(index.home), text: 'All Help topics' }));
      }
      empty.append(links);
      results.append(empty);
    } else {
      for (const group of search.groupByPage(found)) {
        results.append(el('div', { className: 'help-result-page', text: group.title }));
        for (const result of group.results) {
          const snippet = el('span', { className: 'help-result-snippet' });
          for (const segment of result.snippet) snippet.append(segment.hit ? el('b', { text: segment.text }) : segment.text);
          const option = el('a', {
            id: 'help-result-' + options.length,
            className: 'help-result',
            role: 'option',
            'aria-selected': 'false',
            href: pageLink(result.page, result.anchor, query.trim())
          }, [el('span', { className: 'help-result-path', text: result.path.slice(1).join(' › ') || result.title }), snippet]);
          options.push(option);
          results.append(option);
        }
      }
    }
    results.hidden = false;
    input.setAttribute('aria-expanded', 'true');
  }

  input.addEventListener('input', renderResults);
  input.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown') { event.preventDefault(); setActive(active + 1); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); setActive(active - 1); }
    else if (event.key === 'Enter') {
      const target = options[active >= 0 ? active : 0];
      if (target) { event.preventDefault(); location.href = target.href; }
    } else if (event.key === 'Escape') {
      event.preventDefault();
      if (input.value) { input.value = ''; hideResults(); }
      else setDrawer(false);
    }
  });
  document.addEventListener('click', (event) => { if (!event.target.closest('.help-search')) hideResults(); });
  document.addEventListener('keydown', (event) => {
    const typing = event.target.closest && event.target.closest('input, textarea, select, [contenteditable]');
    if ((event.ctrlKey && !event.altKey && event.key.toLowerCase() === 'f') || (event.key === '/' && !typing && !event.ctrlKey && !event.altKey)) {
      event.preventDefault();
      input.focus();
      input.select();
    } else if (event.key === 'Escape' && !typing) {
      setDrawer(false);
    }
  });

  function highlight(query) {
    const terms = search.tokenize(query);
    if (terms.length === 0) return 0;
    const walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => node.parentElement.closest('script, style, .help-pager, .help-notice') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    let count = 0;
    for (const node of nodes) {
      const ranges = search.findMatches(node.nodeValue, terms);
      for (let i = ranges.length - 1; i >= 0; i--) {
        const range = document.createRange();
        range.setStart(node, ranges[i].start);
        range.setEnd(node, ranges[i].end);
        range.surroundContents(el('mark', { className: 'help-hit' }));
        count++;
      }
    }
    return count;
  }

  const query = new URLSearchParams(location.search).get('q');
  if (query && highlight(query) > 0) {
    const clear = el('button', { type: 'button', text: 'Clear highlights' });
    const box = notice('Highlighted: ' + query, clear);
    clear.addEventListener('click', () => {
      for (const mark of main.querySelectorAll('mark.help-hit')) mark.replaceWith(...mark.childNodes);
      main.normalize();
      box.remove();
      history.replaceState(null, '', location.pathname + location.hash);
    });
  }
  if (location.hash) {
    const target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (target) target.scrollIntoView();
  }
  if (window.innerWidth < NARROW) setDrawer(false);
})();
