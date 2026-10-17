import { useState } from 'preact/hooks';
import { useStore, setState } from '../store.js';
import { api } from '../api.js';
import { refreshGit, refreshSite, toast } from '../actions.js';
import { overlay } from '../overlay/index.js';
import { slugify, todayISO } from '../util.js';
import { Modal } from './Modal.jsx';

export function NewDocDialog() {
  const nd = useStore((s) => s.newDoc);
  const site = useStore((s) => s.site);
  if (!nd || !site) return null;
  return <Form nd={nd} site={site} />;
}

function Form({ nd, site }) {
  const multi = site.languages.length > 1;
  const [title, setTitle] = useState('');
  const [slug, setSlug] = useState('');
  const [slugTouched, setSlugTouched] = useState(false);
  const [lang, setLang] = useState(site.languages.includes(nd.lang) ? nd.lang : site.default_lang);
  const [date, setDate] = useState(todayISO());
  const [busy, setBusy] = useState(false);
  const isPost = nd.collection === 'posts';
  const close = () => setState({ newDoc: null });

  const submit = async (e) => {
    e?.preventDefault();
    if (!title.trim() || busy) return;
    setBusy(true);
    try {
      const res = await api.newDoc({
        collection: nd.collection, lang, title: title.trim(),
        slug: (slugTouched ? slug : slugify(title)) || null,
        date: isPost ? date : null,
      });
      close();
      refreshSite();
      refreshGit();
      toast('Documento creato', 'ok');
      overlay.openBodyAfterLoad = true;
      overlay.navigate(res.url);
    } catch (err) {
      toast(err.message, 'error');
      setBusy(false);
    }
  };

  return (
    <Modal
      title={`Nuovo documento · ${nd.label}`} onClose={close} className="small"
      footer={(
        <>
          <button class="btn" onClick={close}>Annulla</button>
          <button class="btn primary" disabled={!title.trim() || busy} onClick={submit}>
            {busy ? <span class="spinner" /> : 'Crea'}
          </button>
        </>
      )}
    >
      <form class="form" onSubmit={submit}>
        <label>Titolo
          <input type="text" value={title} required onInput={(e) => setTitle(e.currentTarget.value)} />
        </label>
        {multi && (
          <label>Lingua
            <select value={lang} onChange={(e) => setLang(e.currentTarget.value)}>
              {site.languages.map((l) => <option key={l} value={l}>{l.toUpperCase()}</option>)}
            </select>
          </label>
        )}
        <label>Slug
          <input
            type="text" class="mono" value={slugTouched ? slug : slugify(title)}
            onInput={(e) => { setSlugTouched(true); setSlug(e.currentTarget.value); }}
          />
        </label>
        {isPost && (
          <label>Data
            <input type="text" value={date} placeholder="AAAA-MM-GG" onInput={(e) => setDate(e.currentTarget.value)} />
          </label>
        )}
        <button type="submit" hidden />
      </form>
    </Modal>
  );
}
