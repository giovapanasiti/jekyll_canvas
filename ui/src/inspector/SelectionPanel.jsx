import { useEffect, useState } from 'preact/hooks';
import { applyEdit, openCode, pickMedia, toast } from '../actions.js';
import { isMod, joinKeypath } from '../util.js';
import { useStore } from '../store.js';

function Source({ file, keypath, line }) {
  return (
    <div class="source mono" title={file}>
      {file}{keypath ? <> › {joinKeypath(keypath)}</> : null}{line ? `:${line}` : ''}
    </div>
  );
}

function OpenInCode({ file, line }) {
  return (
    <button class="btn sm" style="margin-top:6px" onClick={() => openCode(file, line)}>Apri nel codice</button>
  );
}

function SaveArea({ value, onSave, mono, rows = 4, disabled, label = 'Salva', note }) {
  const [v, setV] = useState(value);
  const [busy, setBusy] = useState(false);
  useEffect(() => setV(value), [value]);
  const save = async () => {
    if (busy || v === value) return;
    setBusy(true);
    try { await onSave(v); } catch { /* toast already shown */ }
    setBusy(false);
  };
  return (
    <div>
      <textarea
        class={mono ? 'mono' : ''} rows={rows} value={v} disabled={disabled} spellcheck={!mono}
        onInput={(e) => setV(e.currentTarget.value)}
        onKeyDown={(e) => { if (isMod(e) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); } }}
      />
      <div class="row" style="margin-top:6px">
        <button class="btn primary sm" disabled={disabled || busy || v === value} onClick={save}>
          {busy ? <span class="spinner" /> : label}
        </button>
        {note && <span class="muted">{note}</span>}
      </div>
    </div>
  );
}

const saveYaml = (file, keypath, old) => (next) => applyEdit({ op: 'yaml', file, keypath, old, new: next });

function StringPanel({ sel }) {
  return (
    <>
      <div class="kind">Testo da {sel.source === 'front_matter' ? 'front matter' : 'file dati'}</div>
      <Source file={sel.file} keypath={sel.keypath} />
      <SaveArea
        value={sel.value} disabled={!sel.editable} rows={3}
        onSave={saveYaml(sel.file, sel.keypath, sel.value)}
        note={sel.editable ? null : 'File non modificabile'}
      />
      <OpenInCode file={sel.file} />
      {sel.siblings.length > 0 && (
        <>
          <h5>Altre lingue</h5>
          {sel.siblings.map((s) => (
            <div class="sibling" key={s.lang + s.file}>
              <div class="sib-head"><span class="badge">{s.lang}</span><Source file={s.file} keypath={s.keypath} /></div>
              <SaveArea value={s.value} rows={3} onSave={saveYaml(s.file, s.keypath, s.value)} />
            </div>
          ))}
        </>
      )}
    </>
  );
}

function MdPanel({ sel }) {
  if (sel.loading) return <div class="muted"><span class="spinner" /> Carico il blocco…</div>;
  const b = sel.block;
  const inline = b.type === 'p' || b.type === 'header';
  return (
    <>
      <div class="kind">Blocco Markdown · {b.type}{b.header_level ? ` h${b.header_level}` : ''}</div>
      <Source file={b.file} line={b.start_line === b.end_line ? b.start_line : `${b.start_line}-${b.end_line}`} />
      {inline && <div class="muted hint">Modifica direttamente nell'anteprima (Cmd+Invio per salvare) oppure qui sotto.</div>}
      <SaveArea
        value={b.markdown} mono rows={Math.min(14, Math.max(5, b.markdown.split('\n').length + 1))}
        onSave={(next) => applyEdit({
          op: 'md_block', file: b.file, start_line: b.start_line, end_line: b.end_line,
          old_markdown: b.markdown, new_markdown: next,
        })}
      />
      <OpenInCode file={b.file} line={b.start_line} />
    </>
  );
}

function LiteralPanel({ sel }) {
  if (sel.loading) return <div class="muted"><span class="spinner" /> Cerco nei sorgenti…</div>;
  const c = sel.candidate;
  return (
    <>
      <div class="kind">Testo nel sorgente</div>
      <Source file={c.file} line={c.line} />
      <pre class="snippet mono">{c.snippet}</pre>
      <OpenInCode file={c.file} line={c.line} />
    </>
  );
}

function UntracedPanel({ sel, page }) {
  return (
    <>
      <div class="kind warn">Testo non trovato nei sorgenti</div>
      <p class="muted" style="margin:4px 0 8px">«{sel.text}» è probabilmente calcolato. File coinvolti in questa pagina:</p>
      <ul class="files mono">
        {[page?.file, ...(page?.layouts || []), ...(page?.includes || [])].filter(Boolean).map((f) => <li key={f}>{f}</li>)}
      </ul>
    </>
  );
}

function ImagePanel({ sel }) {
  const srcT = sel.attrs.find((a) => a.attr === 'src');
  const altT = sel.attrs.find((a) => a.attr === 'alt');
  return (
    <>
      <div class="kind">Immagine</div>
      <div class="image-preview"><img src={sel.srcUrl || sel.src} alt="" /></div>
      <div class="source mono">{sel.src}</div>
      {srcT ? (
        <>
          <Source file={srcT.file} keypath={srcT.keypath} />
          <button
            class="btn sm" disabled={!srcT.editable}
            onClick={async () => {
              const src = await pickMedia();
              if (src) saveYaml(srcT.file, srcT.keypath, srcT.value)(src).catch(() => {});
            }}
          >
            Cambia immagine…
          </button>
        </>
      ) : <p class="muted">Il percorso dell'immagine non proviene da front matter o dati.</p>}
      {altT ? (
        <>
          <h5>Testo alternativo (alt)</h5>
          <Source file={altT.file} keypath={altT.keypath} />
          <SaveArea value={altT.value} rows={2} disabled={!altT.editable} onSave={saveYaml(altT.file, altT.keypath, altT.value)} />
        </>
      ) : sel.alt ? <p class="muted">alt: «{sel.alt}» (non modificabile da qui)</p> : null}
    </>
  );
}

export function SelectionPanel() {
  const sel = useStore((s) => s.selection);
  const page = useStore((s) => s.page);
  if (!sel) return null;
  let body = null;
  if (sel.kind === 'string') body = <StringPanel sel={sel} />;
  else if (sel.kind === 'md') body = <MdPanel sel={sel} key={sel.block ? `${sel.block.file}:${sel.block.start_line}:${sel.block.markdown}` : 'l'} />;
  else if (sel.kind === 'literal') body = <LiteralPanel sel={sel} />;
  else if (sel.kind === 'untraced') body = <UntracedPanel sel={sel} page={page} />;
  else if (sel.kind === 'image') body = <ImagePanel sel={sel} />;
  return (
    <section class="panel selection">
      <h4>Selezione</h4>
      {body}
    </section>
  );
}
