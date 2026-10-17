import { useState } from 'preact/hooks';
import { setState } from '../store.js';
import { deleteDocument, openCode } from '../actions.js';
import { overlay } from '../overlay/index.js';
import { IconTrash } from '../components/icons.jsx';

function FileList({ title, files }) {
  const [open, setOpen] = useState(false);
  if (!files?.length) return null;
  return (
    <div>
      <button class="link" onClick={() => setOpen(!open)}>{open ? '▾' : '▸'} {title} ({files.length})</button>
      {open && (
        <ul class="files mono">
          {files.map((f) => (
            <li key={f}><button class="link file-link" title="Apri nel codice" onClick={() => openCode(f)}>{f}</button></li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function PagePanel({ page }) {
  return (
    <section class="panel">
      <h4>Pagina</h4>
      <div class="source mono">{page.file}</div>
      <dl class="meta">
        <dt>Tipo</dt><dd>{page.kind}{page.collection ? ` · ${page.collection}` : ''}</dd>
        <dt>Lingua</dt><dd>{page.lang}</dd>
        <dt>Formato</dt><dd>{page.format}</dd>
      </dl>
      <FileList title="Layout" files={page.layouts} />
      <FileList title="Include" files={page.includes} />
      {page.translations?.length > 1 && (
        <div class="row wrap" style="margin-top:8px">
          {page.translations.filter((t) => t.lang !== page.lang).map((t) => (
            <button key={t.lang} class="btn sm" title={t.file} onClick={() => overlay.navigate(t.url)}>
              Apri traduzione {t.lang.toUpperCase()}
            </button>
          ))}
        </div>
      )}
      <button class="btn" style="margin-top:8px;width:100%" title="Cmd+Shift+E" onClick={() => openCode(page.file)}>
        Modifica sorgente
      </button>
      {page.format === 'markdown' && (
        <button class="btn primary" style="margin-top:8px;width:100%" onClick={() => setState({ bodyEditor: true })}>
          Modifica testo completo
        </button>
      )}
      {page.kind === 'document' && (
        <button
          class="btn danger" style="margin-top:8px;width:100%"
          onClick={() => deleteDocument({ file: page.file, title: page.title })}
        >
          <IconTrash /> Elimina…
        </button>
      )}
    </section>
  );
}
