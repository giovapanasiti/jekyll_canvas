// Inline plain-text editing of a range of a text node (string and literal targets).
import { normalize } from '../util.js';

function setEditable(el, on) {
  if (!on) { el.contentEditable = 'false'; return; }
  try { el.contentEditable = 'plaintext-only'; } catch { /* unsupported value */ }
  if (el.contentEditable !== 'plaintext-only') el.contentEditable = 'true';
}

function selectAll(doc, el) {
  const sel = doc.defaultView.getSelection();
  const range = doc.createRange();
  range.selectNodeContents(el);
  sel.removeAllRanges();
  sel.addRange(range);
}

// onSave(newText) must return a promise; rejection keeps the editor open.
export function startInlineEdit({ doc, node, rawStart, rawEnd, initial, onSave, onEnd }) {
  const mid = rawStart > 0 ? node.splitText(rawStart) : node;
  if (rawEnd - rawStart < mid.data.length) mid.splitText(rawEnd - rawStart);
  const originalText = mid.data;

  const span = doc.createElement('span');
  span.setAttribute('data-jc-ui', '');
  span.textContent = initial;
  mid.parentNode.insertBefore(span, mid);
  mid.remove();
  setEditable(span, true);

  let finished = false;
  let saving = false;

  function end(restore) {
    finished = true;
    if (restore) span.replaceWith(doc.createTextNode(originalText));
    onEnd?.(restore);
  }
  const cancel = () => { if (!finished && !saving) end(true); };

  async function commit() {
    if (finished || saving) return;
    const value = span.textContent.replace(/\n+$/, '');
    if (normalize(value) === normalize(initial)) return cancel();
    saving = true;
    span.setAttribute('data-jc-saving', '');
    setEditable(span, false);
    try {
      await onSave(value);
      finished = true; // the preview reloads after a successful save
      onEnd?.(false);
    } catch {
      saving = false;
      span.removeAttribute('data-jc-saving');
      setEditable(span, true);
      span.focus();
    }
  }

  span.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); commit(); }
    else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); cancel(); }
  });
  span.addEventListener('paste', (e) => {
    if (span.contentEditable === 'plaintext-only') return;
    e.preventDefault();
    doc.execCommand('insertText', false, e.clipboardData.getData('text/plain'));
  });
  span.addEventListener('blur', () => {
    // Ignore blur caused by the whole window losing focus (Cmd+Tab).
    setTimeout(() => { if (document.hasFocus()) commit(); }, 0);
  });

  span.focus();
  selectAll(doc, span);
  return { el: span, commit, cancel, isSaving: () => saving };
}
