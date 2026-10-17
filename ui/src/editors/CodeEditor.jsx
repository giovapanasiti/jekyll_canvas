import { useEffect, useRef, useState } from 'preact/hooks';
import { basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { indentUnit } from '@codemirror/language';
import { indentWithTab } from '@codemirror/commands';
import { oneDark } from '@codemirror/theme-one-dark';
import { liquid } from '@codemirror/lang-liquid';
import { markdown } from '@codemirror/lang-markdown';
import { yaml } from '@codemirror/lang-yaml';
import { css } from '@codemirror/lang-css';
import { javascript } from '@codemirror/lang-javascript';
import { json } from '@codemirror/lang-json';
import { api } from '../api.js';
import { useStore, setState, getState } from '../store.js';
import { applyEdit, confirmDialog, toast } from '../actions.js';
import { isMod } from '../util.js';
import { IconClose } from '../components/icons.jsx';
import { Modal } from '../components/Modal.jsx';

const LANGUAGES = {
  'liquid-html': { label: 'HTML + Liquid', ext: () => liquid() },
  markdown: { label: 'Markdown', ext: () => markdown() },
  yaml: { label: 'YAML', ext: () => yaml() },
  scss: { label: 'SCSS / CSS', ext: () => css() },
  javascript: { label: 'JavaScript', ext: () => javascript() },
  json: { label: 'JSON', ext: () => json() },
  text: { label: 'Testo', ext: () => [] },
};
const languageOf = (id) => LANGUAGES[id] || LANGUAGES.text;

// One-dark syntax colours on the app's own surfaces.
const chrome = EditorView.theme({
  '&': { height: '100%', backgroundColor: 'var(--bg)', fontSize: '13px' },
  '&.cm-focused': { outline: 'none' },
  '.cm-scroller': { fontFamily: 'var(--mono)', lineHeight: '1.6' },
  '.cm-gutters': { backgroundColor: 'var(--surface)', color: 'var(--muted)', borderRight: '1px solid var(--border)' },
  '.cm-activeLine': { backgroundColor: 'rgba(255,255,255,.04)' },
  '.cm-activeLineGutter': { backgroundColor: 'rgba(255,255,255,.07)' },
  '.cm-panels': { backgroundColor: 'var(--surface)', color: 'var(--text)', borderColor: 'var(--border)' },
  '.cm-tooltip': { backgroundColor: 'var(--surface-2)', borderColor: 'var(--border)' },
}, { dark: true });

const baseName = (file) => file.slice(file.indexOf('/') + 1);

export function CodeEditorHost() {
  const request = useStore((s) => s.codeEditor);
  if (!request) return null;
  return <CodeEditor request={request} />;
}

function CodeEditor({ request }) {
  const page = useStore((s) => s.page);
  const site = useStore((s) => s.site);
  const host = useRef(null);
  const view = useRef(null);
  const entries = useRef(new Map()); // file -> { file, language, loaded, mtime, state, dirty, bar }
  const currentRef = useRef(null);
  const openSeq = useRef(0);
  const busyRef = useRef(false);
  const [current, setCurrent] = useState(null);
  const [loading, setLoading] = useState(null);
  const [busy, setBusy] = useState(false);
  const [conflict, setConflict] = useState(null); // file name
  const [filter, setFilter] = useState('');
  const [, bump] = useState(0);
  const rerender = () => bump((n) => n + 1);

  const makeState = (doc, language) => EditorState.create({
    doc,
    extensions: [
      basicSetup,
      keymap.of([indentWithTab]),
      EditorState.tabSize.of(2),
      indentUnit.of('  '),
      oneDark,
      chrome,
      languageOf(language).ext(),
      EditorView.updateListener.of((u) => {
        if (!u.docChanged) return;
        const entry = currentRef.current;
        if (!entry) return;
        const doc = u.state.doc;
        const dirty = doc.length !== entry.loaded.length || doc.toString() !== entry.loaded;
        if (dirty !== entry.dirty) { entry.dirty = dirty; rerender(); }
      }),
    ],
  });

  const goToLine = (line) => {
    const v = view.current;
    const n = Math.min(Math.max(1, Number(line) || 1), v.state.doc.lines);
    const ln = v.state.doc.line(n);
    v.dispatch({ selection: { anchor: ln.from, head: ln.to }, effects: EditorView.scrollIntoView(ln.from, { y: 'center' }) });
    v.focus();
  };

  const show = (entry, line) => {
    const v = view.current;
    const prev = currentRef.current;
    if (prev !== entry) {
      if (prev) prev.state = v.state;
      v.setState(entry.state);
      currentRef.current = entry;
      setCurrent(entry.file);
    }
    if (line) goToLine(line);
    v.focus();
  };

  const open = async (file, line = null) => {
    const seq = ++openSeq.current;
    let entry = entries.current.get(file);
    if (!entry) {
      setLoading(file);
      try {
        const res = await api.file(file);
        entry = {
          file, language: res.language, loaded: res.content, mtime: res.mtime,
          state: makeState(res.content, res.language), dirty: false, bar: null,
        };
        entries.current.set(file, entry);
      } catch (e) {
        toast(`${file}: ${e.message}`, 'error');
        if (!entries.current.size) setState({ codeEditor: null });
        return;
      } finally {
        if (seq === openSeq.current) setLoading(null);
      }
    }
    if (seq === openSeq.current) show(entry, line);
  };

  useEffect(() => {
    view.current = new EditorView({ state: EditorState.create({ doc: '' }), parent: host.current });
    return () => { view.current.destroy(); view.current = null; };
  }, []);

  useEffect(() => { open(request.file, request.line); }, [request.nonce]);

  const docOf = (entry) => (entry === currentRef.current ? view.current.state.doc : entry.state.doc).toString();
  const dirtyFiles = () => [...entries.current.values()].filter((e) => e.dirty).map((e) => e.file);

  const save = async (force = false) => {
    const entry = currentRef.current;
    if (!entry || busyRef.current) return;
    const content = docOf(entry);
    busyRef.current = true;
    setBusy(true);
    try {
      const res = await applyEdit(
        { op: 'file', file: entry.file, old_content: entry.loaded, new_content: content, force },
        { handle: ['conflict', 'liquid_syntax'] },
      );
      entry.loaded = content;
      entry.dirty = docOf(entry) !== content;
      entry.bar = res.error ? { kind: 'build', message: res.error } : null;
      toast('Salvato', 'ok');
    } catch (e) {
      if (e.code === 'conflict') setConflict(entry.file);
      else if (e.code === 'liquid_syntax') entry.bar = { kind: 'liquid', message: e.message, line: e.line };
      // other errors: toast already shown by applyEdit
    }
    busyRef.current = false;
    setBusy(false);
  };

  const refetch = async (file) => {
    const res = await api.file(file);
    const entry = entries.current.get(file);
    entry.loaded = res.content;
    entry.mtime = res.mtime;
    return { entry, res };
  };

  const reloadFile = async () => {
    const file = conflict;
    setConflict(null);
    try {
      const { entry, res } = await refetch(file);
      entry.state = makeState(res.content, res.language);
      entry.dirty = false;
      entry.bar = null;
      if (entry === currentRef.current) view.current.setState(entry.state);
      rerender();
    } catch (e) {
      toast(e.message, 'error');
    }
  };

  const overwriteFile = async () => {
    const file = conflict;
    setConflict(null);
    try {
      await refetch(file); // current disk content becomes old_content
    } catch (e) {
      toast(e.message, 'error');
      return;
    }
    save();
  };

  const close = async () => {
    if (dirtyFiles().length && !(await confirmDialog('Ci sono modifiche non salvate. Chiudere comunque?', { okLabel: 'Chiudi senza salvare', danger: true }))) return;
    setState({ codeEditor: null });
  };

  useEffect(() => {
    const onKey = (e) => {
      if (conflict) return;
      if (isMod(e) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); }
      else if (e.key === 'Escape') {
        const s = getState();
        if (e.defaultPrevented || s.dialog || s.media || s.chooser) return; // editor panels and dialogs handle their own Escape
        e.preventDefault();
        close();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const entry = current ? entries.current.get(current) : null;
  const q = filter.trim().toLowerCase();
  const match = (f) => !q || f.toLowerCase().includes(q);
  const pageFiles = page
    ? [...new Set([page.file, ...(page.layouts || []), ...(page.includes || [])])]
    : [];
  const pageKind = (f) => (f === page.file ? 'pagina' : (page.layouts || []).includes(f) ? 'layout' : 'include');

  const fileButton = (file, label, badge) => {
    const e = entries.current.get(file);
    return (
      <button
        key={file} class={`ce-item ${file === current ? 'active' : ''}`} title={file}
        onClick={() => open(file)}
      >
        <span class="ce-name mono">{label}</span>
        {badge && <span class="badge">{badge}</span>}
        {e?.dirty && <span class="ce-dot" title="Modifiche non salvate" />}
      </button>
    );
  };

  const templates = site?.templates;
  const layouts = (templates?.layouts || []).filter(match);
  const includes = (templates?.includes || []).filter(match);

  return (
    <div class="code-editor">
      <header class="be-head">
        <div class="grow">
          <div class="mono be-file">{entry ? entry.file : request.file}</div>
        </div>
        {entry && <span class="badge">{languageOf(entry.language).label}</span>}
        <button class="btn primary" disabled={busy || !entry} onClick={() => save()}>
          {busy ? <span class="spinner" /> : 'Salva'}
        </button>
        <button class="btn" onClick={close}>
          <IconClose style="width:14px;height:14px;fill:none;stroke:currentColor;stroke-width:2" /> Chiudi
        </button>
      </header>
      <div class="ce-main">
        <aside class="ce-files">
          {pageFiles.length > 0 && (
            <>
              <h5>File della pagina</h5>
              {pageFiles.map((f) => fileButton(f, f, pageKind(f)))}
            </>
          )}
          <h5>Tutti i template</h5>
          <input
            type="search" placeholder="Filtra…" value={filter} class="ce-filter"
            onInput={(ev) => setFilter(ev.currentTarget.value)}
          />
          {layouts.length > 0 && <div class="ce-sub">Layout</div>}
          {layouts.map((f) => fileButton(f, baseName(f)))}
          {includes.length > 0 && <div class="ce-sub">Include</div>}
          {includes.map((f) => fileButton(f, baseName(f)))}
          {!layouts.length && !includes.length && <div class="muted" style="padding:4px 12px">Nessun template</div>}
        </aside>
        <div class="ce-pane">
          {entry?.bar && (
            <div class="ce-bar" role="alert">
              <span class="grow">
                {entry.bar.kind === 'liquid' ? `Errore Liquid: ${entry.bar.message}` : `Salvato, ma la compilazione è fallita: ${entry.bar.message}`}
              </span>
              {entry.bar.kind === 'liquid' && entry.bar.line && (
                <button class="btn sm" onClick={() => goToLine(entry.bar.line)}>Vai alla riga {entry.bar.line}</button>
              )}
              {entry.bar.kind === 'liquid' && (
                <button class="btn sm" disabled={busy} onClick={() => save(true)}>Salva comunque</button>
              )}
              <button class="icon-btn" title="Chiudi avviso" onClick={() => { entry.bar = null; rerender(); }}><IconClose /></button>
            </div>
          )}
          <div class="ce-host" ref={host} />
          {loading && <div class="ce-loading muted"><span class="spinner" /> Carico {loading}…</div>}
        </div>
      </div>
      {conflict && (
        <Modal
          title="Il file è cambiato fuori dall'editor"
          className="small" onClose={() => setConflict(null)}
          footer={(
            <>
              <button class="btn" onClick={() => setConflict(null)}>Annulla</button>
              <button class="btn" onClick={reloadFile}>Ricarica</button>
              <button class="btn danger" onClick={overwriteFile}>Sovrascrivi</button>
            </>
          )}
        >
          <p style="margin:0">
            <span class="mono">{conflict}</span> è stato modificato dopo l'apertura.
            «Ricarica» scarta le tue modifiche, «Sovrascrivi» salva il tuo testo sopra la versione attuale.
          </p>
        </Modal>
      )}
    </div>
  );
}
