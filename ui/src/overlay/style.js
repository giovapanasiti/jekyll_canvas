// CSS injected into the site iframe (marked data-jc so it is easy to spot and replace).
export const OVERLAY_CSS = `
[data-jc-hover] { outline-offset: 2px !important; cursor: text !important; }
[data-jc-hover="string"], [data-jc-hover="image"] { outline: 2px solid #6366f1 !important; }
[data-jc-hover="md"] { outline: 2px solid #22c55e !important; }
[data-jc-hover="literal"] { outline: 2px dashed #9ca3af !important; }
[data-jc-selected] { outline: 2px solid #f59e0b !important; outline-offset: 2px !important; }
[data-jc-ui][contenteditable] {
  outline: 2px solid #f59e0b !important; outline-offset: 2px;
  background: rgba(245,158,11,.12) !important; border-radius: 2px;
  white-space: pre-wrap; min-width: 1ch; cursor: text !important;
}
span[data-jc-ui] { display: inline; }
[data-jc-saving]::after {
  content: ""; display: inline-block; width: 10px; height: 10px; margin-left: 6px;
  border: 2px solid #d1d5db; border-top-color: #6366f1; border-radius: 50%;
  animation: jc-spin .7s linear infinite; vertical-align: middle;
}
@keyframes jc-spin { to { transform: rotate(360deg); } }
.jc-mdtb {
  position: absolute; z-index: 2147483647; display: flex; gap: 2px; padding: 3px;
  background: #252526; border: 1px solid #3d3d3d; border-radius: 6px;
  box-shadow: 0 6px 18px rgba(0,0,0,.35); font: 13px system-ui, sans-serif;
}
.jc-mdtb button {
  background: transparent; border: 0; color: #e5e5e5; width: 28px; height: 26px;
  border-radius: 4px; cursor: pointer; font: inherit;
}
.jc-mdtb button:hover { background: #3d3d3d; }
`;

export function injectStyle(doc) {
  doc.querySelectorAll('style[data-jc]').forEach((n) => n.remove());
  const style = doc.createElement('style');
  style.setAttribute('data-jc', '');
  style.textContent = OVERLAY_CSS;
  (doc.head || doc.documentElement).appendChild(style);
}
