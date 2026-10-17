import { useStore } from '../store.js';
import { SelectionPanel } from './SelectionPanel.jsx';
import { PagePanel } from './PagePanel.jsx';
import { FrontMatter } from './FrontMatter.jsx';

export function Inspector() {
  const open = useStore((s) => s.inspectorOpen);
  const page = useStore((s) => s.page);
  const status = useStore((s) => s.pageStatus);
  return (
    <aside class={`inspector ${open ? '' : 'hidden'}`}>
      <SelectionPanel />
      {status === 'untracked' && (
        <section class="panel"><h4>Pagina</h4><p class="muted">Pagina non tracciata: la modifica è disabilitata.</p></section>
      )}
      {status === 'external' && (
        <section class="panel"><h4>Pagina</h4><p class="muted">Pagina esterna al sito: la modifica è disabilitata.</p></section>
      )}
      {status === 'loading' && <section class="panel"><span class="spinner" /></section>}
      {page && <PagePanel page={page} />}
      {page && <FrontMatter page={page} />}
    </aside>
  );
}
