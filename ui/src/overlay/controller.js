// Drives the site iframe: loads page data, builds targets, hover/click editing.
import { api } from '../api.js';
import { getState, setState } from '../store.js';
import {
  applyEdit, closeChooser, promptDialog, setReloader, showChooser, toast,
} from '../actions.js';
import { keyOf, normalize, normalizeMap, rawRange, isMod } from '../util.js';
import { injectStyle } from './style.js';
import { buildTargets, caretOffsetAt, textNodeAtPoint } from './targets.js';
import { startInlineEdit } from './inline-edit.js';
import { startMdEdit } from './md-edit.js';

const EMPTY = { text: new Map(), attrs: new Map() };
const inUi = (el) => !!(el && el.closest && el.closest('[data-jc-ui]'));

export class OverlayController {
  iframe = null;
  doc = null;
  page = null;
  targets = EMPTY;
  hoverEl = null;
  selEl = null;
  active = null; // running inline/markdown edit session
  pendingScroll = null;
  loadSeq = 0;
  clickSeq = 0;
  openBodyAfterLoad = false; // set after creating a document

  attach(iframe) {
    this.iframe = iframe;
    iframe.addEventListener('load', () => this.onLoad());
    setReloader(() => this.reload());
    iframe.src = getState().currentUrl; // set after the load listener exists
  }

  // --- navigation ---------------------------------------------------------
  navigate(url) {
    try { this.iframe.contentWindow.location.assign(url); } catch { this.iframe.src = url; }
  }
  back() { try { this.iframe.contentWindow.history.back(); } catch { /* cross-origin */ } }
  forward() { try { this.iframe.contentWindow.history.forward(); } catch { /* cross-origin */ } }
  reload() {
    if (!this.iframe) return;
    try {
      const w = this.iframe.contentWindow;
      this.pendingScroll = { x: w.scrollX, y: w.scrollY };
      w.location.reload();
    } catch {
      this.iframe.src = this.iframe.src;
    }
  }

  // --- load ---------------------------------------------------------------
  async onLoad() {
    const seq = ++this.loadSeq;
    this.active = null;
    this.hoverEl = null;
    this.selEl = null;
    this.targets = EMPTY;
    this.page = null;
    closeChooser();

    let win, doc, path;
    try {
      win = this.iframe.contentWindow;
      doc = win.document;
      path = win.location.pathname;
      void doc.body;
    } catch {
      this.doc = null;
      setState({ pageStatus: 'external', page: null, selection: null });
      return;
    }
    if (win.location.href === 'about:blank') return;
    this.doc = doc;
    setState({ currentUrl: path, pageStatus: 'loading' });

    const scroll = this.pendingScroll;
    this.pendingScroll = null;
    if (scroll) {
      win.scrollTo(scroll.x, scroll.y);
      requestAnimationFrame(() => win.scrollTo(scroll.x, scroll.y));
      setTimeout(() => win.scrollTo(scroll.x, scroll.y), 200);
    }
    injectStyle(doc);
    this.bindListeners(doc);

    let page = null;
    try {
      page = await api.page(path);
    } catch (e) {
      if (e.code !== 'not_found') toast(`Pagina: ${e.message}`, 'error');
    }
    if (seq !== this.loadSeq) return;
    this.page = page;
    this.targets = page ? buildTargets(doc, page) : EMPTY;
    setState({ page, pageStatus: page ? 'ok' : 'untracked' });
    this.reselect();
    this.applyMode();
    if (this.openBodyAfterLoad) {
      this.openBodyAfterLoad = false;
      if (page && page.format === 'markdown') setState({ bodyEditor: true });
    }
  }

  // Keep a string selection across reloads (re-resolved by file + key path).
  reselect() {
    const sel = getState().selection;
    if (!sel || sel.kind !== 'string' || !this.page) { this.setSelection(null); return; }
    const str = this.page.strings.find((s) => keyOf(s.file, s.keypath) === keyOf(sel.file, sel.keypath));
    if (!str) { this.setSelection(null); return; }
    let el = null;
    for (const [node, hits] of this.targets.text) {
      if (hits.some((h) => h.str === str)) { el = node.parentElement; break; }
    }
    this.setSelection(this.stringSelection(str), el);
  }

  // --- listeners ----------------------------------------------------------
  bindListeners(doc) {
    const edit = (fn) => (e) => { if (this.canEdit()) fn(e); };
    doc.addEventListener('mouseover', edit((e) => this.onOver(e)), true);
    doc.addEventListener('mouseout', edit((e) => { if (!e.relatedTarget) this.setHover(null); }), true);
    doc.addEventListener('click', edit((e) => this.onClick(e)), true);
    doc.addEventListener('submit', edit((e) => e.preventDefault()), true);
    doc.addEventListener('keydown', (e) => {
      if (isMod(e) && e.key.toLowerCase() === 'e') {
        e.preventDefault();
        setState((s) => ({ mode: s.mode === 'edit' ? 'nav' : 'edit' }));
      }
    }, true);
  }

  canEdit() { return getState().mode === 'edit' && !!this.page; }

  applyMode() {
    if (getState().mode !== 'edit') {
      this.cancelActive();
      this.setHover(null);
    }
  }

  cancelActive() {
    if (this.active && !this.active.isSaving()) this.active.cancel();
  }

  // --- hit testing --------------------------------------------------------
  resolve(el, x, y) {
    if (!el || el.nodeType !== 1 || inUi(el)) return null;
    const node = textNodeAtPoint(el, x, y);
    if (node) {
      const hits = this.targets.text.get(node);
      if (hits?.length) return { type: 'string', node, hits, outlineEl: node.parentElement };
    }
    if (el.tagName === 'IMG' && this.targets.attrs.has(el)) {
      return { type: 'image', el, outlineEl: el };
    }
    if (this.page.format === 'markdown') {
      const md = el.closest('[data-jc-line]');
      if (md) return { type: 'md', el: md, outlineEl: md };
    }
    if (node) return { type: 'literal', node, outlineEl: node.parentElement };
    return null;
  }

  setHover(hit) {
    if (this.hoverEl) this.hoverEl.removeAttribute('data-jc-hover');
    this.hoverEl = null;
    if (hit && !this.active) {
      hit.outlineEl.setAttribute('data-jc-hover', hit.type);
      this.hoverEl = hit.outlineEl;
    }
  }

  onOver(e) {
    if (this.active) return;
    this.setHover(this.resolve(e.target, e.clientX, e.clientY));
  }

  async onClick(e) {
    if (inUi(e.target)) { e.preventDefault(); return; }
    if (e.metaKey || e.ctrlKey) return; // Cmd+click follows the link
    e.preventDefault();
    e.stopPropagation();
    if (this.active) return; // blur of the running edit commits it
    closeChooser();
    const hit = this.resolve(e.target, e.clientX, e.clientY);
    if (!hit) { this.setSelection(null); return; }
    this.setHover(null);
    const seq = ++this.clickSeq;
    const at = this.toTop(e.clientX, e.clientY);
    try {
      if (hit.type === 'string') await this.activateString(hit, e, at);
      else if (hit.type === 'image') this.activateImage(hit.el);
      else if (hit.type === 'md') await this.activateMarkdown(hit.el, seq);
      else await this.activateLiteral(hit, seq, at);
    } catch (err) {
      if (err?.code !== 'conflict') toast(err.message || String(err), 'error');
    }
  }

  // iframe viewport coordinates -> position inside the preview container
  toTop(x, y) {
    const r = this.iframe.getBoundingClientRect();
    return { x: r.left + x, y: r.top + y };
  }

  // --- selection ----------------------------------------------------------
  setSelection(selection, el = null) {
    if (this.selEl) this.selEl.removeAttribute('data-jc-selected');
    this.selEl = el;
    if (el) el.setAttribute('data-jc-selected', '');
    setState({ selection });
  }

  stringSelection(str) {
    return {
      kind: 'string', file: str.file, keypath: str.keypath, value: str.value,
      editable: str.editable, source: str.source, siblings: str.siblings || [],
    };
  }

  // --- string targets -----------------------------------------------------
  async activateString(hit, e, at) {
    let chosen = hit.hits[0];
    if (hit.hits.length > 1) {
      const off = caretOffsetAt(this.doc, hit.node, e.clientX, e.clientY);
      const byCaret = off == null ? null
        : hit.hits.find((h) => off >= h.rawStart && off <= h.rawEnd);
      if (byCaret) chosen = byCaret;
      else chosen = await new Promise((resolve) => showChooser({
        ...at, title: 'Quale testo?',
        items: hit.hits.map((h) => ({ label: h.str.value, detail: `${h.str.file} › ${h.str.keypath.join(' › ')}`, onPick: () => resolve(h) })),
        onClose: () => resolve(null),
      }));
      if (!chosen) return;
    }
    const { str } = chosen;
    this.setSelection(this.stringSelection(str), hit.node.parentElement);
    if (!str.editable) { toast('Questo file dati non è modificabile da qui', 'warn'); return; }
    const norm = normalizeMap(hit.node.data);
    const r = rawRange(norm, chosen.nStart, chosen.nEnd);
    this.beginInline({
      node: hit.node, rawStart: r.start, rawEnd: r.end, initial: normalize(str.value),
      onSave: (text) => applyEdit({
        op: 'yaml', file: str.file, keypath: str.keypath, old: str.value,
        new: text + (str.value.match(/\n*$/)?.[0] || ''),
      }),
    });
  }

  beginInline(opts) {
    this.setHover(null);
    this.active = startInlineEdit({
      doc: this.doc,
      ...opts,
      onEnd: (restored) => {
        this.active = null;
        if (restored) this.targets = this.page ? buildTargets(this.doc, this.page) : EMPTY;
      },
    });
  }

  // --- images -------------------------------------------------------------
  activateImage(el) {
    const attrs = this.targets.attrs.get(el) || [];
    this.setSelection({
      kind: 'image',
      src: el.getAttribute('src') || '',
      srcUrl: el.src || '', // absolute, for the preview thumbnail
      alt: el.getAttribute('alt') || '',
      attrs: attrs.map((a) => ({
        attr: a.attr, file: a.str.file, keypath: a.str.keypath, value: a.str.value,
        editable: a.str.editable, siblings: a.str.siblings || [],
      })),
    }, el);
    if (!getState().inspectorOpen) setState({ inspectorOpen: true });
  }

  // --- markdown blocks ----------------------------------------------------
  async activateMarkdown(el, seq) {
    const line = Number(el.getAttribute('data-jc-line'));
    const file = this.page.file;
    this.setSelection({ kind: 'md', file, line, loading: true }, el);
    const block = await api.mdBlock(file, line);
    if (seq !== this.clickSeq) return;
    this.setSelection({ kind: 'md', file, line, block }, el);
    if (block.type !== 'p' && block.type !== 'header') {
      if (!getState().inspectorOpen) setState({ inspectorOpen: true });
      return;
    }
    this.setHover(null);
    this.active = startMdEdit({
      doc: this.doc, el, block,
      askLink: () => promptDialog('URL del link', 'https://'),
      onSave: (markdown) => applyEdit({
        op: 'md_block', file, start_line: block.start_line, end_line: block.end_line,
        old_markdown: block.markdown, new_markdown: markdown,
      }),
      onEnd: () => { this.active = null; },
    });
  }

  // --- literal text -------------------------------------------------------
  async activateLiteral(hit, seq, at) {
    const norm = normalizeMap(hit.node.data);
    if (!norm.text) return;
    this.setSelection({ kind: 'literal', text: norm.text, loading: true }, hit.node.parentElement);
    const { candidates } = await api.locate(this.page.url, norm.text);
    if (seq !== this.clickSeq) return;
    if (!candidates.length) {
      toast('Testo non trovato nei sorgenti (probabilmente calcolato)', 'warn');
      this.setSelection({ kind: 'untraced', text: norm.text }, hit.node.parentElement);
      if (!getState().inspectorOpen) setState({ inspectorOpen: true });
      return;
    }
    let cand = candidates[0];
    if (candidates.length > 1) {
      cand = await new Promise((resolve) => showChooser({
        ...at, title: 'Più sorgenti trovati',
        items: candidates.map((c) => ({ label: `${c.file}:${c.line}`, detail: c.snippet, onPick: () => resolve(c) })),
        onClose: () => resolve(null),
      }));
      if (!cand) return;
    }
    this.setSelection({ kind: 'literal', text: norm.text, candidate: cand }, hit.node.parentElement);
    const r = rawRange(norm, 0, norm.text.length);
    this.beginInline({
      node: hit.node, rawStart: r.start, rawEnd: r.end, initial: norm.text,
      onSave: (text) => applyEdit({
        op: 'literal', file: cand.file, start: cand.start, end: cand.end,
        old_text: cand.old_text, new_text: text,
      }),
    });
  }
}
