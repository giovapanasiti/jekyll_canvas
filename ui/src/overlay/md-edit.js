// In-place editing of a Markdown paragraph/heading block with a mini floating toolbar.
import { htmlToMarkdown } from './md-convert.js';
import { isMod } from '../util.js';

const BUTTONS = [
  { cmd: 'bold', label: 'B', title: 'Grassetto (Cmd+B)', style: 'font-weight:700' },
  { cmd: 'italic', label: 'I', title: 'Corsivo (Cmd+I)', style: 'font-style:italic' },
  { cmd: 'link', label: '↗', title: 'Link (Cmd+K)' },
  { cmd: 'code', label: '&lt;/&gt;', title: 'Codice', style: 'font:11px monospace' },
];

// onSave(newMarkdown) -> Promise; askLink() -> Promise<string|null>
export function startMdEdit({ doc, el, block, onSave, onEnd, askLink }) {
  const win = doc.defaultView;
  const before = el.innerHTML;
  let finished = false;
  let saving = false;
  let suspended = false;

  el.setAttribute('data-jc-ui', '');
  el.removeAttribute('data-jc-hover');
  el.contentEditable = 'true';
  try { doc.execCommand('styleWithCSS', false, false); } catch { /* ignore */ }

  const bar = doc.createElement('div');
  bar.className = 'jc-mdtb';
  bar.setAttribute('data-jc-ui', '');
  bar.innerHTML = BUTTONS.map(
    (b) => `<button type="button" data-cmd="${b.cmd}" title="${b.title}" style="${b.style || ''}">${b.label}</button>`,
  ).join('');
  doc.body.appendChild(bar);
  function placeBar() {
    const r = el.getBoundingClientRect();
    bar.style.top = `${Math.max(4, r.top + win.scrollY - 38)}px`;
    bar.style.left = `${Math.max(4, r.left + win.scrollX)}px`;
  }
  placeBar();
  win.addEventListener('resize', placeBar);

  async function runCommand(cmd) {
    if (cmd === 'bold' || cmd === 'italic') {
      doc.execCommand(cmd);
    } else if (cmd === 'code') {
      const text = String(win.getSelection());
      if (text) {
        const esc = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        doc.execCommand('insertHTML', false, `<code>${esc}</code>`);
      }
    } else if (cmd === 'link') {
      const sel = win.getSelection();
      const saved = sel.rangeCount ? sel.getRangeAt(0).cloneRange() : null;
      suspended = true;
      const url = await askLink();
      suspended = false;
      el.focus();
      if (saved) { sel.removeAllRanges(); sel.addRange(saved); }
      if (url) doc.execCommand('createLink', false, url);
    }
  }

  bar.addEventListener('mousedown', (e) => {
    e.preventDefault(); // keep the selection in the block
    const btn = e.target.closest('button[data-cmd]');
    if (btn) runCommand(btn.dataset.cmd);
  });

  function cleanup() {
    win.removeEventListener('resize', placeBar);
    bar.remove();
    el.removeAttribute('contenteditable');
    el.removeAttribute('data-jc-ui');
    el.removeAttribute('data-jc-saving');
  }
  function end(restore) {
    finished = true;
    if (restore) el.innerHTML = before;
    cleanup();
    onEnd?.(restore);
  }
  const cancel = () => { if (!finished && !saving) end(true); };

  async function commit() {
    if (finished || saving) return;
    if (el.innerHTML === before) return cancel();
    const markdown = htmlToMarkdown(el.innerHTML, block);
    if (markdown === block.markdown) return cancel();
    saving = true;
    el.setAttribute('data-jc-saving', '');
    el.contentEditable = 'false';
    try {
      await onSave(markdown);
      finished = true;
      onEnd?.(false);
    } catch {
      saving = false;
      el.removeAttribute('data-jc-saving');
      el.contentEditable = 'true';
      el.focus();
    }
  }

  el.addEventListener('keydown', (e) => {
    const mod = isMod(e);
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); cancel(); }
    else if (mod && e.key === 'Enter') { e.preventDefault(); commit(); }
    else if (mod && e.key.toLowerCase() === 'b') { e.preventDefault(); runCommand('bold'); }
    else if (mod && e.key.toLowerCase() === 'i') { e.preventDefault(); runCommand('italic'); }
    else if (mod && e.key.toLowerCase() === 'k') { e.preventDefault(); runCommand('link'); }
    else if (e.key === 'Enter' && !mod) {
      e.preventDefault();
      if (block.type === 'header') commit();
      else doc.execCommand('insertLineBreak');
    }
  });
  el.addEventListener('paste', (e) => {
    e.preventDefault();
    doc.execCommand('insertText', false, e.clipboardData.getData('text/plain'));
  });
  el.addEventListener('blur', () => {
    setTimeout(() => { if (!suspended && document.hasFocus()) commit(); }, 0);
  });

  el.focus();
  const range = doc.createRange();
  range.selectNodeContents(el);
  range.collapse(false);
  const sel = win.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  return { el, commit, cancel, isSaving: () => saving };
}
