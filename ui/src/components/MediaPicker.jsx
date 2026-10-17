import { useEffect, useRef, useState } from 'preact/hooks';
import { useStore, setState } from '../store.js';
import { api } from '../api.js';
import { toast } from '../actions.js';
import { Modal } from './Modal.jsx';

export function MediaPicker() {
  const media = useStore((s) => s.media);
  if (!media) return null;
  return <Picker resolve={media.resolve} />;
}

function Picker({ resolve }) {
  const [items, setItems] = useState(null);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [drag, setDrag] = useState(false);
  const file = useRef(null);
  const close = (src = null) => { setState({ media: null }); resolve(src); };

  useEffect(() => {
    api.media().then((r) => setItems(r.data)).catch((e) => { toast(e.message, 'error'); setItems([]); });
  }, []);

  const upload = async (f) => {
    if (!f) return;
    setBusy(true);
    try {
      const r = await api.upload(f);
      toast('Immagine caricata', 'ok');
      close(r.src);
    } catch (e) {
      toast(e.message, 'error');
      setBusy(false);
    }
  };

  const q = query.trim().toLowerCase();
  const shown = (items || []).filter((i) => !q || i.name.toLowerCase().includes(q) || i.file.toLowerCase().includes(q));
  return (
    <Modal
      title="Libreria immagini" wide onClose={() => close()} className={drag ? 'dropping' : ''}
      footer={(
        <>
          <span class="muted grow">Trascina un file qui per caricarlo</span>
          <input ref={file} type="file" accept="image/*" hidden onChange={(e) => upload(e.currentTarget.files[0])} />
          <button class="btn primary" disabled={busy} onClick={() => file.current.click()}>
            {busy ? <span class="spinner" /> : 'Carica…'}
          </button>
        </>
      )}
    >
      <div
        class="media"
        onDragOver={(e) => { e.preventDefault(); setDrag(true); }}
        onDragLeave={() => setDrag(false)}
        onDrop={(e) => { e.preventDefault(); setDrag(false); upload(e.dataTransfer.files[0]); }}
      >
        <input type="search" placeholder="Cerca per nome…" value={query} onInput={(e) => setQuery(e.currentTarget.value)} />
        {items === null && <p class="muted">Caricamento…</p>}
        {items && !shown.length && <p class="muted">Nessuna immagine.</p>}
        <div class="media-grid">
          {shown.map((i) => (
            <button key={i.file} class="media-item" title={i.file} onClick={() => close(i.src)}>
              <span class="thumb"><img src={i.src} alt="" loading="lazy" /></span>
              <span class="name">{i.name}</span>
            </button>
          ))}
        </div>
      </div>
    </Modal>
  );
}
