import { useState } from 'preact/hooks';
import { useStore, setState } from '../store.js';
import { overlay } from '../overlay/index.js';
import { openCode } from '../actions.js';
import { normUrl } from '../util.js';
import { IconPlus } from './icons.jsx';

function Group({ group, query, currentUrl, multiLang, currentLang }) {
  const [open, setOpen] = useState(true);
  const q = query.trim().toLowerCase();
  const items = q
    ? group.items.filter((i) => `${i.title} ${i.file}`.toLowerCase().includes(q))
    : group.items;
  if (q && !items.length) return null;
  const cur = normUrl(currentUrl);
  return (
    <section>
      <div class="group-head" onClick={() => setOpen(!open)}>
        <span class={`chev ${open || q ? 'open' : ''}`}>›</span>
        <span class="grow">{group.label}<span class="count">{group.items.length}</span></span>
        {group.can_create && (
          <button
            class="icon-btn" title={`Nuovo (${group.label})`} style="width:22px;height:22px"
            onClick={(e) => {
              e.stopPropagation();
              setState({ newDoc: { collection: group.collection, label: group.label, lang: currentLang } });
            }}
          >
            <IconPlus />
          </button>
        )}
      </div>
      {(open || q) && items.map((item) => (
        <div
          key={item.file + item.url}
          class={`item ${normUrl(item.url) === cur ? 'active' : ''}`}
          title={item.file}
          onClick={() => overlay.navigate(item.url)}
        >
          <span class="title">{item.title || item.file}</span>
          {multiLang && item.lang && <span class="badge">{item.lang}</span>}
        </div>
      ))}
    </section>
  );
}

// Layouts and includes; clicking opens the code editor and leaves the preview where it is.
function TemplateGroup({ templates, query }) {
  const [open, setOpen] = useState(false);
  const q = query.trim().toLowerCase();
  const pick = (files) => (q ? files.filter((f) => f.toLowerCase().includes(q)) : files);
  const layouts = pick(templates?.layouts || []);
  const includes = pick(templates?.includes || []);
  const total = (templates?.layouts?.length || 0) + (templates?.includes?.length || 0);
  if (!total || (q && !layouts.length && !includes.length)) return null;
  const list = (label, files) => files.length > 0 && (
    <>
      <div class="sub-head">{label}</div>
      {files.map((f) => (
        <div key={f} class="item" title={f} onClick={() => openCode(f)}>
          <span class="title mono">{f.slice(f.indexOf('/') + 1)}</span>
        </div>
      ))}
    </>
  );
  return (
    <section>
      <div class="group-head" onClick={() => setOpen(!open)}>
        <span class={`chev ${open || q ? 'open' : ''}`}>›</span>
        <span class="grow">Template<span class="count">{total}</span></span>
      </div>
      {(open || q) && <>{list('Layout', layouts)}{list('Include', includes)}</>}
    </section>
  );
}

export function Sidebar() {
  const site = useStore((s) => s.site);
  const currentUrl = useStore((s) => s.currentUrl);
  const page = useStore((s) => s.page);
  const [query, setQuery] = useState('');
  return (
    <aside class="sidebar">
      <div class="search">
        <input type="search" placeholder="Cerca pagine…" value={query} onInput={(e) => setQuery(e.currentTarget.value)} />
      </div>
      <div class="groups">
        {!site && <div class="muted" style="padding:12px">Caricamento…</div>}
        {site?.groups.map((g) => (
          <Group
            key={g.id} group={g} query={query} currentUrl={currentUrl}
            multiLang={site.languages.length > 1} currentLang={page?.lang || site.default_lang}
          />
        ))}
        {site && <TemplateGroup templates={site.templates} query={query} />}
      </div>
    </aside>
  );
}
