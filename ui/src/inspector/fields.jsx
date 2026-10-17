import { useEffect, useState } from 'preact/hooks';
import { IconLeft, IconRight, IconClose } from '../components/icons.jsx';

// Textarea/input that reports a change on blur only when the value differs.
export function TextField({ value, onCommit, multiline, mono, placeholder }) {
  const [v, setV] = useState(value ?? '');
  useEffect(() => setV(value ?? ''), [value]);
  const commit = () => { if (v !== (value ?? '')) onCommit(v); };
  const props = {
    value: v, placeholder, class: mono ? 'mono' : '',
    onInput: (e) => setV(e.currentTarget.value),
    onBlur: commit,
  };
  if (multiline) return <textarea rows={Math.min(8, Math.max(3, String(v).split('\n').length))} {...props} />;
  return (
    <input
      type="text" {...props}
      onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur(); }}
    />
  );
}

export function NumberField({ value, onCommit }) {
  const [v, setV] = useState(String(value));
  useEffect(() => setV(String(value)), [value]);
  const commit = () => {
    const n = Number(v);
    if (v.trim() === '' || Number.isNaN(n)) { setV(String(value)); return; }
    if (n !== value) onCommit(n);
  };
  return (
    <input
      type="number" value={v} onInput={(e) => setV(e.currentTarget.value)} onBlur={commit}
      onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur(); }}
    />
  );
}

export function ChipList({ value, onCommit }) {
  const [draft, setDraft] = useState('');
  const set = (arr) => onCommit(arr);
  const add = () => {
    const t = draft.trim();
    if (!t) return;
    setDraft('');
    set([...value, t]);
  };
  const move = (i, d) => {
    const arr = [...value];
    const j = i + d;
    if (j < 0 || j >= arr.length) return;
    [arr[i], arr[j]] = [arr[j], arr[i]];
    set(arr);
  };
  return (
    <div class="chips">
      {value.map((c, i) => (
        <span class="chip" key={i + String(c)}>
          <button title="Sposta prima" onClick={() => move(i, -1)}><IconLeft /></button>
          <span>{String(c)}</span>
          <button title="Sposta dopo" onClick={() => move(i, 1)}><IconRight /></button>
          <button title="Rimuovi" onClick={() => set(value.filter((_, k) => k !== i))}><IconClose /></button>
        </span>
      ))}
      <input
        type="text" class="chip-input" placeholder="+ aggiungi" value={draft}
        onInput={(e) => setDraft(e.currentTarget.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); add(); } }}
        onBlur={add}
      />
    </div>
  );
}
