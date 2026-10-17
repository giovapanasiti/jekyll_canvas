import { useState } from 'preact/hooks';
import { applyEdit, pickMedia, toast } from '../actions.js';
import { isImagePath, isMod } from '../util.js';
import { ChipList, NumberField, TextField } from './fields.jsx';

const isScalar = (v) => v === null || ['string', 'number', 'boolean'].includes(typeof v);

function Field({ page, name, value }) {
  const save = (next) =>
    applyEdit({ op: 'yaml', file: page.file, keypath: [name], old: value, new: next }).catch(() => {});

  let control;
  if (typeof value === 'boolean') {
    control = <label class="check"><input type="checkbox" checked={value} onChange={(e) => save(e.currentTarget.checked)} /> {String(value)}</label>;
  } else if (typeof value === 'number') {
    control = <NumberField value={value} onCommit={save} />;
  } else if (typeof value === 'string' && isImagePath(value)) {
    control = (
      <div class="image-field">
        <img src={value} alt="" />
        <div class="grow">
          <TextField value={value} mono onCommit={save} />
          <button
            class="btn sm" style="margin-top:6px"
            onClick={async () => { const src = await pickMedia(); if (src) save(src); }}
          >
            Cambia…
          </button>
        </div>
      </div>
    );
  } else if (typeof value === 'string') {
    control = <TextField value={value} multiline={value.length > 80 || value.includes('\n')} onCommit={save} />;
  } else if (Array.isArray(value) && value.every(isScalar)) {
    control = <ChipList value={value} onCommit={save} />;
  } else if (value === null) {
    control = <TextField value="" placeholder="(vuoto)" onCommit={save} />;
  } else {
    control = <pre class="json">{JSON.stringify(value, null, 2)}</pre>;
  }
  return (
    <div class="field">
      <label class="field-label mono">{name}</label>
      {control}
    </div>
  );
}

function RawEditor({ page }) {
  const [text, setText] = useState(page.front_matter.raw);
  const [busy, setBusy] = useState(false);
  const save = async () => {
    setBusy(true);
    try {
      await applyEdit({ op: 'front_matter_raw', file: page.file, new_yaml: text.endsWith('\n') ? text : text + '\n' });
      toast('Front matter salvato', 'ok');
    } catch { /* toast shown by applyEdit */ }
    setBusy(false);
  };
  return (
    <div>
      <textarea
        class="mono" rows={10} value={text} spellcheck={false}
        onInput={(e) => setText(e.currentTarget.value)}
        onKeyDown={(e) => { if (isMod(e) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); } }}
      />
      <div class="row" style="margin-top:6px">
        <button class="btn primary sm" disabled={busy || text === page.front_matter.raw} onClick={save}>Salva</button>
        <span class="muted">Cmd+S</span>
      </div>
    </div>
  );
}

export function FrontMatter({ page }) {
  const [raw, setRaw] = useState(false);
  if (!page.front_matter) return null;
  const data = page.front_matter.data || {};
  return (
    <section class="panel">
      <h4>Front matter</h4>
      {Object.keys(data).map((k) => <Field key={k + page.file} page={page} name={k} value={data[k]} />)}
      <button class="btn sm" onClick={() => setRaw(!raw)}>{raw ? 'Nascondi YAML' : 'Modifica YAML'}</button>
      {raw && <div style="margin-top:8px"><RawEditor page={page} /></div>}
    </section>
  );
}
