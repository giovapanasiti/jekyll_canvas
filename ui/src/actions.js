// App-level actions shared by components and the overlay.
import { api } from './api.js';
import { getState, setState } from './store.js';

let toastSeq = 0;
export function toast(text, kind = 'info') {
  const id = ++toastSeq;
  setState((s) => ({ toasts: [...s.toasts, { id, text, kind }] }));
  setTimeout(() => dismissToast(id), kind === 'error' ? 7000 : 3500);
}
export const dismissToast = (id) =>
  setState((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }));

// Registered by the overlay to avoid an import cycle.
let reloader = () => {};
export const setReloader = (fn) => { reloader = fn; };
export const reloadPreview = () => reloader();
let navigator = () => {};
export const setNavigator = (fn) => { navigator = fn; };

export async function refreshSite() {
  try {
    setState({ site: await api.site() });
  } catch (e) {
    toast(`Sito: ${e.message}`, 'error');
  }
}

export async function refreshGit() {
  try {
    setState({ git: await api.gitStatus() });
  } catch {
    setState({ git: { git: false, files: [] } });
  }
}

// Sends one edit op. Reloads the preview on success; handles conflicts and errors.
// Throws on failure so callers can keep their editing UI open.
// `handle` lists error codes the caller reports itself (no toast, no preview reload).
export async function applyEdit(op, { reload = true, handle = [] } = {}) {
  setState((s) => ({ saving: s.saving + 1 }));
  try {
    const res = await api.edit(op);
    setState((s) => ({
      seenBuildId: res.build_id ?? s.seenBuildId,
      build: { ...s.build, build_id: res.build_id ?? s.build.build_id, error: res.error || null },
    }));
    if (res.error) toast('Salvato, ma la compilazione è fallita', 'warn');
    if (reload) reloadPreview();
    refreshGit();
    refreshSite();
    return res;
  } catch (e) {
    if (handle.includes(e.code)) {
      // the caller shows its own message
    } else if (e.code === 'conflict') {
      toast('Il file è cambiato, ricarico', 'warn');
      reloadPreview();
    } else {
      toast(e.message, 'error');
    }
    throw e;
  } finally {
    setState((s) => ({ saving: s.saving - 1 }));
  }
}

// Opens the code editor on `file`, optionally at a 1-based `line`.
let codeSeq = 0;
export function openCode(file, line = null) {
  if (!file) return;
  setState({ codeEditor: { file, line, nonce: ++codeSeq } });
}

// Moves an article (post or collection document) to the system Trash after a confirmation.
// `discard` warns that unsaved editor changes are lost. Resolves true when the file was trashed.
let dropSeq = 0;
export async function deleteDocument({ file, title, discard = false }) {
  const text = `Eliminare "${title || file}"?\n${file}\n\n`
    + 'Il file viene spostato nel Cestino; le immagini non vengono toccate. '
    + 'Puoi anche ripristinarlo da Modifiche → Annulla finché non fai commit.'
    + (discard ? '\n\nLe modifiche non salvate nell\'editor andranno perse.' : '');
  if (!(await confirmDialog(text, { okLabel: 'Sposta nel Cestino', danger: true }))) return false;
  let res;
  setState((s) => ({ saving: s.saving + 1 }));
  try {
    res = await api.deleteDoc(file);
  } catch (e) {
    toast(e.message, 'error');
    return false;
  } finally {
    setState((s) => ({ saving: s.saving - 1 }));
  }
  setState((s) => ({
    seenBuildId: res.build_id ?? s.seenBuildId,
    build: { ...s.build, build_id: res.build_id ?? s.build.build_id, error: res.error || null },
  }));
  toast('Spostato nel Cestino', 'ok');
  if (res.error) toast('Eliminato, ma la compilazione è fallita', 'warn');
  const { page, site } = getState();
  const shown = page?.file === file;
  if (shown && getState().bodyEditor) setState({ bodyEditor: false });
  if (getState().codeEditor) setState({ codeDrop: { file, nonce: ++dropSeq } });
  if (shown) {
    const lang = page.lang;
    navigator(!lang || lang === site?.default_lang ? '/' : `/${lang}/`);
  } else {
    reloadPreview();
  }
  refreshSite();
  refreshGit();
  return true;
}

// --- dialogs rendered in-app (WKWebView may not implement window.confirm/prompt) ---
export function confirmDialog(text, { okLabel = 'OK', danger = false } = {}) {
  return new Promise((resolve) =>
    setState({ dialog: { kind: 'confirm', text, okLabel, danger, resolve } }));
}
export function promptDialog(text, initial = '') {
  return new Promise((resolve) =>
    setState({ dialog: { kind: 'prompt', text, initial, resolve } }));
}
export function pickMedia() {
  return new Promise((resolve) => setState({ media: { resolve } }));
}
export function showChooser(chooser) { setState({ chooser }); }
export function closeChooser() {
  const c = getState().chooser;
  if (!c) return;
  setState({ chooser: null });
  c.onClose?.();
}
