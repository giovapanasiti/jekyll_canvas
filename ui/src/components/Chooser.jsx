import { useEffect } from 'preact/hooks';
import { useStore } from '../store.js';
import { closeChooser } from '../actions.js';

// Small popover to pick between several candidate sources/strings.
export function Chooser() {
  const c = useStore((s) => s.chooser);
  useEffect(() => {
    if (!c) return;
    const onKey = (e) => { if (e.key === 'Escape') closeChooser(); };
    const onDown = (e) => { if (!e.target.closest?.('.chooser')) closeChooser(); };
    window.addEventListener('keydown', onKey);
    window.addEventListener('mousedown', onDown);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('mousedown', onDown);
    };
  }, [c]);
  if (!c) return null;
  const left = Math.min(c.x, window.innerWidth - 360);
  const top = Math.min(c.y + 8, window.innerHeight - 240);
  return (
    <div class="chooser" style={{ left: `${Math.max(8, left)}px`, top: `${Math.max(8, top)}px` }}>
      <div class="chooser-title">{c.title}</div>
      {c.items.map((item, i) => (
        <button
          key={i} class="chooser-item"
          onClick={() => { const pick = item.onPick; c.onClose = null; closeChooser(); pick(); }}
        >
          <span class="chooser-label">{item.label}</span>
          {item.detail && <span class="chooser-detail mono">{item.detail}</span>}
        </button>
      ))}
    </div>
  );
}
