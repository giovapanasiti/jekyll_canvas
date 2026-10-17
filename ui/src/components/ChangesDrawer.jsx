import { useEffect, useState } from 'preact/hooks';
import { useStore, setState, getState } from '../store.js';
import { api } from '../api.js';
import { confirmDialog, refreshGit, refreshSite, reloadPreview, toast } from '../actions.js';
import { IconClose } from './icons.jsx';

const STATUS_LABEL = { M: 'Modificato', A: 'Aggiunto', D: 'Eliminato', R: 'Rinominato', '??': 'Nuovo' };

function Diff({ text }) {
  return (
    <pre class="diff">
      {text.split('\n').map((l, i) => {
        let cls = '';
        if (l.startsWith('+++') || l.startsWith('---') || l.startsWith('diff ') || l.startsWith('index ')) cls = 'meta';
        else if (l.startsWith('@@')) cls = 'hunk';
        else if (l.startsWith('+')) cls = 'add';
        else if (l.startsWith('-')) cls = 'del';
        return <div key={i} class={cls}>{l || ' '}</div>;
      })}
    </pre>
  );
}

export function ChangesDrawer() {
  const open = useStore((s) => s.changesOpen);
  const git = useStore((s) => s.git);
  const [unchecked, setUnchecked] = useState({});
  const [current, setCurrent] = useState(null);
  const [diff, setDiff] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const files = git?.files || [];

  useEffect(() => { if (open) refreshGit(); }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e) => {
      if (e.key === 'Escape' && !getState().dialog) setState({ changesOpen: false });
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  useEffect(() => {
    if (!open || !current) return;
    if (!files.some((f) => f.path === current)) { setCurrent(null); return; }
    let live = true;
    api.gitDiff(current)
      .then((r) => live && setDiff(r.diff))
      .catch((e) => live && setDiff(`# ${e.message}`));
    return () => { live = false; };
  }, [open, current, git]);

  if (!open) return null;
  const close = () => setState({ changesOpen: false });
  const checked = files.filter((f) => !unchecked[f.path]).map((f) => f.path);

  const discard = async (path) => {
    if (!(await confirmDialog(`Annullare le modifiche a ${path}?`, { okLabel: 'Annulla modifiche', danger: true }))) return;
    try {
      await api.gitDiscard(path);
      reloadPreview();
      refreshGit();
      refreshSite();
    } catch (e) { toast(e.message, 'error'); }
  };

  const commit = async () => {
    if (!message.trim() || !checked.length) return;
    setBusy(true);
    try {
      const r = await api.gitCommit(message.trim(), checked);
      toast(`Commit ${r.sha || ''} creato`, 'ok');
      setMessage('');
      setCurrent(null);
      await refreshGit();
    } catch (e) { toast(e.message, 'error'); }
    setBusy(false);
  };

  return (
    <div class="drawer-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) close(); }}>
      <aside class="drawer">
        <header class="modal-head">
          <h3>Modifiche {git?.branch && <span class="badge">{git.branch}</span>}</h3>
          <button class="icon-btn" onClick={close} title="Chiudi"><IconClose /></button>
        </header>
        <div class="drawer-files">
          {!files.length && <p class="muted pad">Nessuna modifica.</p>}
          {files.map((f) => (
            <div key={f.path} class={`change ${current === f.path ? 'active' : ''}`}>
              <input
                type="checkbox" checked={!unchecked[f.path]}
                onChange={(e) => setUnchecked({ ...unchecked, [f.path]: !e.currentTarget.checked })}
              />
              <span class={`st st-${f.status.replace('?', 'q')}`} title={STATUS_LABEL[f.status] || f.status}>{f.status}</span>
              <button class="path mono" onClick={() => setCurrent(f.path)}>{f.path}</button>
              <button class="btn sm danger" onClick={() => discard(f.path)}>Annulla</button>
            </div>
          ))}
        </div>
        <div class="drawer-diff">
          {current ? <Diff text={diff} /> : <p class="muted pad">Seleziona un file per vedere le differenze.</p>}
        </div>
        <footer class="drawer-foot">
          <input
            type="text" placeholder="Messaggio di commit" value={message}
            onInput={(e) => setMessage(e.currentTarget.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') commit(); }}
          />
          <button class="btn primary" disabled={busy || !message.trim() || !checked.length} onClick={commit}>
            {busy ? <span class="spinner" /> : `Commit (${checked.length})`}
          </button>
        </footer>
      </aside>
    </div>
  );
}
