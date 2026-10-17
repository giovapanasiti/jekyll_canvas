import { useEffect, useRef } from 'preact/hooks';
import { IconClose } from './icons.jsx';

export function Modal({ title, onClose, children, wide, footer, className = '' }) {
  const body = useRef(null);
  useEffect(() => {
    // Preact does not honour autoFocus: focus the first field explicitly.
    body.current?.querySelector('input:not([type=hidden]):not([type=file]),textarea,select')?.focus();
  }, []);
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); onClose?.(); } };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div class="modal-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose?.(); }}>
      <div class={`modal ${wide ? 'wide' : ''} ${className}`} role="dialog" aria-modal="true">
        <header class="modal-head">
          <h3>{title}</h3>
          <button class="icon-btn" title="Chiudi" onClick={onClose}><IconClose /></button>
        </header>
        <div class="modal-body" ref={body}>{children}</div>
        {footer && <footer class="modal-foot">{footer}</footer>}
      </div>
    </div>
  );
}
