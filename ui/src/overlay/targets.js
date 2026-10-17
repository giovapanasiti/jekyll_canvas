// Builds the map of editable string targets (text nodes and attributes) for a rendered page.
import { normalize, normalizeMap, rawRange } from '../util.js';

const SKIP_SELECTOR = 'script, style, noscript, template, svg, [data-jc-ui]';
export const ATTRS = ['alt', 'title', 'placeholder', 'aria-label', 'src', 'href', 'content'];
const WORD = /[\p{L}\p{N}_]/u;

function wordBoundary(text, start, end) {
  const before = start === 0 ? '' : text[start - 1];
  const after = end >= text.length ? '' : text[end];
  return !(before && WORD.test(before)) && !(after && WORD.test(after));
}

function matchNode(norm, strings) {
  const found = [];
  for (const s of strings) {
    const nv = s.nv;
    let from = 0;
    for (;;) {
      const idx = norm.text.indexOf(nv, from);
      if (idx < 0) break;
      from = idx + nv.length;
      const end = idx + nv.length;
      const whole = norm.text.length === nv.length;
      // Single words (often lookup keys like nav `key: software`) only match a whole text node.
      const multiWord = /\s/.test(nv);
      const ok = whole || (multiWord && wordBoundary(norm.text, idx, end) && nv.length >= 6);
      if (!ok) continue;
      if (found.some((f) => idx < f.nEnd && end > f.nStart)) continue;
      const r = rawRange(norm, idx, end);
      found.push({ str: s.str, nStart: idx, nEnd: end, rawStart: r.start, rawEnd: r.end });
    }
  }
  return found.sort((a, b) => a.rawStart - b.rawStart);
}

export function buildTargets(doc, page) {
  const text = new Map(); // Text node -> [{str, rawStart, rawEnd}]
  const attrs = new Map(); // Element -> [{attr, str}]
  const strings = (page.strings || [])
    .map((str) => ({ str, nv: normalize(str.value ?? '') }))
    .filter((s) => s.nv.length >= 2)
    .sort((a, b) => b.nv.length - a.nv.length);
  if (!doc.body) return { text, attrs };

  if (strings.length) {
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const parent = node.parentElement;
      if (!parent || parent.closest(SKIP_SELECTOR)) continue;
      const norm = normalizeMap(node.data);
      if (!norm.text) continue;
      const hits = matchNode(norm, strings);
      if (hits.length) text.set(node, hits);
    }
    const byValue = new Map();
    for (const s of strings) if (!byValue.has(s.nv)) byValue.set(s.nv, s.str);
    const sel = ATTRS.map((a) => `[${a}]`).join(',');
    doc.querySelectorAll(sel).forEach((el) => {
      if (el.closest('[data-jc-ui]')) return;
      for (const attr of ATTRS) {
        if (attr === 'content' && el.tagName !== 'META') continue;
        const v = el.getAttribute(attr);
        if (v == null) continue;
        const str = byValue.get(normalize(v));
        if (str) {
          if (!attrs.has(el)) attrs.set(el, []);
          attrs.get(el).push({ attr, str });
        }
      }
    });
  }
  return { text, attrs };
}

// First visible text node of `el` under the pointer (direct children only).
export function textNodeAtPoint(el, x, y) {
  const doc = el.ownerDocument;
  const nodes = [...el.childNodes].filter((n) => n.nodeType === 3 && n.data.trim());
  if (!nodes.length) return null;
  const range = doc.createRange();
  for (const n of nodes) {
    range.selectNodeContents(n);
    for (const r of range.getClientRects()) {
      if (x >= r.left - 2 && x <= r.right + 2 && y >= r.top - 2 && y <= r.bottom + 2) return n;
    }
  }
  return nodes[0];
}

// Offset inside `node` under the pointer, or null.
export function caretOffsetAt(doc, node, x, y) {
  let c = null;
  if (doc.caretRangeFromPoint) {
    const r = doc.caretRangeFromPoint(x, y);
    if (r) c = { node: r.startContainer, offset: r.startOffset };
  } else if (doc.caretPositionFromPoint) {
    const p = doc.caretPositionFromPoint(x, y);
    if (p) c = { node: p.offsetNode, offset: p.offset };
  }
  return c && c.node === node ? c.offset : null;
}
