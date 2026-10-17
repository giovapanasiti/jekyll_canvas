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
export async function applyEdit(op, { reload = true } = {}) {
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
    if (e.code === 'conflict') {
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
