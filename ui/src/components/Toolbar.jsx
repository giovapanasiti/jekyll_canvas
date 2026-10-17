import { useEffect, useState } from 'preact/hooks';
import { useStore, setState } from '../store.js';
import { overlay } from '../overlay/index.js';
import { api } from '../api.js';
import { refreshGit, toast } from '../actions.js';
import { IconBack, IconForward, IconReload, IconPanel } from './icons.jsx';
import { normUrl } from '../util.js';

function BuildStatus() {
  const build = useStore((s) => s.build);
  const saving = useStore((s) => s.saving);
  const offline = useStore((s) => s.offline);
  let cls = '', label = 'Pronto', title = build.last_build_ms ? `Ultima build: ${build.last_build_ms} ms` : '';
  if (offline) { cls = 'error'; label = 'Offline'; title = 'Motore non raggiungibile'; }
  else if (build.building || saving > 0) { cls = 'building'; label = 'Compilazione…'; }
  else if (build.error) { cls = 'error'; label = 'Errore'; title = build.error; }
  return (
    <span class="status" title={title}>
      <span class={`dot ${cls}`} />
      {label}
    </span>
  );
}

export function Toolbar() {
  const site = useStore((s) => s.site);
  const currentUrl = useStore((s) => s.currentUrl);
  const page = useStore((s) => s.page);
  const mode = useStore((s) => s.mode);
  const inspectorOpen = useStore((s) => s.inspectorOpen);
  const git = useStore((s) => s.git);
  const [draft, setDraft] = useState(currentUrl);
  useEffect(() => setDraft(currentUrl), [currentUrl]);

  const rebuild = async () => {
    try {
      await api.rebuild();
      overlay.reload();
      refreshGit();
    } catch (e) {
      toast(e.message, 'error');
    }
  };
  const changes = git && git.git ? git.files.length : null;

  return (
    <header class="toolbar">
      <div class="brand" title={site?.root || ''}>
        <i class="logo" />
        <span>{site?.name || 'Jekyll Canvas'}</span>
      </div>
      <span class="sep" />
      <button class="icon-btn" title="Indietro" onClick={() => overlay.back()}><IconBack /></button>
      <button class="icon-btn" title="Avanti" onClick={() => overlay.forward()}><IconForward /></button>
      <button class="icon-btn" title="Ricarica (ricompila)" onClick={rebuild}><IconReload /></button>
      <input
        class="url" type="text" spellcheck={false} value={draft}
        onInput={(e) => setDraft(e.currentTarget.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') overlay.navigate(draft.startsWith('/') ? draft : normUrl('/' + draft));
          if (e.key === 'Escape') setDraft(currentUrl);
        }}
      />
      {page?.translations?.length > 1 && (
        <div class="seg" title="Lingua">
          {page.translations.map((t) => (
            <button
              key={t.lang} class={t.lang === page.lang ? 'active' : ''}
              onClick={() => overlay.navigate(t.url)}
            >
              {t.lang.toUpperCase()}
            </button>
          ))}
        </div>
      )}
      <div class="seg" title="Cmd+E">
        <button class={mode === 'edit' ? 'active' : ''} onClick={() => setState({ mode: 'edit' })}>✎ Modifica</button>
        <button class={mode === 'nav' ? 'active' : ''} onClick={() => setState({ mode: 'nav' })}>Naviga</button>
      </div>
      <BuildStatus />
      {changes !== null && (
        <button class="btn" onClick={() => setState({ changesOpen: true })}>
          Modifiche ({changes})
        </button>
      )}
      <button
        class={`icon-btn ${inspectorOpen ? 'on' : ''}`} title="Pannello ispettore"
        onClick={() => setState({ inspectorOpen: !inspectorOpen })}
      >
        <IconPanel />
      </button>
    </header>
  );
}
