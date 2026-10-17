import { useEffect, useRef, useState } from 'preact/hooks';
import { Crepe } from '@milkdown/crepe';
import { remarkStringifyOptionsCtx } from '@milkdown/kit/core';
import '@milkdown/crepe/theme/common/style.css';
import '@milkdown/crepe/theme/frame-dark.css';
import { api } from '../api.js';
import { useStore, setState, getState } from '../store.js';
import { applyEdit, confirmDialog, deleteDocument, toast } from '../actions.js';
import { isMod } from '../util.js';
import { IconClose, IconTrash } from '../components/icons.jsx';

// WYSIWYG pane: owns one Crepe instance; reports every markdown change.
function VisualPane({ initial, onChange, onReady }) {
  const root = useRef(null);
  useEffect(() => {
    let crepe = new Crepe({
      root: root.current,
      defaultValue: initial,
      featureConfigs: {
        [Crepe.Feature.Placeholder]: { text: 'Scrivi qui il testo…' },
        [Crepe.Feature.ImageBlock]: {
          onUpload: async (file) => (await api.upload(file)).src,
        },
      },
    });
    // Match the house style of hand-written Jekyll Markdown to keep diffs small.
    crepe.editor.config((ctx) => {
      ctx.update(remarkStringifyOptionsCtx, (prev) => ({ ...prev, bullet: '-', emphasis: '*', strong: '*', rule: '-' }));
    });
    crepe.on((l) => l.markdownUpdated((_ctx, md) => onChange(md)));
    let alive = true;
    crepe.create().then(() => {
      if (alive) onReady(crepe.getMarkdown());
    }).catch((e) => toast(`Editor: ${e.message}`, 'error'));
    return () => {
      alive = false;
      try { onChange(crepe.getMarkdown()); } catch { /* not created yet */ }
      crepe.destroy().catch(() => {});
      crepe = null;
    };
  }, []);
  return <div class="visual" ref={root} />;
}

export function BodyEditor() {
  const open = useStore((s) => s.bodyEditor);
  const page = useStore((s) => s.page);
  if (!open || !page) return null;
  return <Editor page={page} />;
}

function Editor({ page }) {
  const [mode, setMode] = useState('visual'); // visual | source
  const [text, setText] = useState(page.body);
  const textRef = useRef(page.body);
  const baseline = useRef(null); // markdown as first serialised by the editor
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);

  const update = (md) => {
    textRef.current = md;
    if (baseline.current != null) setDirty(md !== baseline.current);
  };
  const onReady = (md) => {
    if (baseline.current == null) baseline.current = md;
    textRef.current = md;
    setDirty(md !== baseline.current);
  };

  const switchTo = (next) => {
    if (next === mode) return;
    if (mode === 'visual') setText(textRef.current); // flushed by VisualPane cleanup
    setMode(next);
  };
  // After the visual pane unmounts its cleanup has pushed the latest markdown to textRef.
  useEffect(() => { if (mode === 'source') setText(textRef.current); }, [mode]);

  const close = async () => {
    if (dirty && !(await confirmDialog('Ci sono modifiche non salvate. Chiudere comunque?', { okLabel: 'Chiudi senza salvare', danger: true }))) return;
    setState({ bodyEditor: false });
  };

  const save = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const body = mode === 'source' ? text : textRef.current;
      await applyEdit({ op: 'body', file: page.file, old_body: page.body, new_body: body });
      toast('Testo salvato', 'ok');
      setState({ bodyEditor: false });
    } catch { /* toast shown */ }
    setBusy(false);
  };

  useEffect(() => {
    const onKey = (e) => {
      if (isMod(e) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); }
      else if (e.key === 'Escape') {
        const s = getState();
        if (s.dialog || s.media || s.chooser) return; // those handle their own Escape
        e.preventDefault();
        close();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <div class="body-editor">
      <header class="be-head">
        <div class="grow">
          <div class="mono be-file">{page.file}</div>
          <div class="muted be-note">Salvando, la formattazione Markdown del corpo può essere normalizzata.</div>
        </div>
        <div class="seg">
          <button class={mode === 'visual' ? 'active' : ''} onClick={() => switchTo('visual')}>Visuale</button>
          <button class={mode === 'source' ? 'active' : ''} onClick={() => switchTo('source')}>Sorgente</button>
        </div>
        <button class="btn primary" disabled={busy} onClick={save}>{busy ? <span class="spinner" /> : 'Salva'}</button>
        {page.kind === 'document' && (
          <button class="btn danger" disabled={busy} onClick={() => deleteDocument({ file: page.file, title: page.title, discard: dirty })}>
            <IconTrash /> Elimina
          </button>
        )}
        <button class="btn" onClick={close}><IconClose style="width:14px;height:14px;fill:none;stroke:currentColor;stroke-width:2" /> Chiudi</button>
      </header>
      <div class="be-body">
        {mode === 'visual' ? (
          <VisualPane key="v" initial={text} onChange={update} onReady={onReady} />
        ) : (
          <textarea
            class="source-area mono" value={text} spellcheck={false}
            onInput={(e) => {
              setText(e.currentTarget.value);
              textRef.current = e.currentTarget.value;
              setDirty(baseline.current != null ? e.currentTarget.value !== baseline.current : e.currentTarget.value !== page.body);
            }}
          />
        )}
      </div>
    </div>
  );
}
