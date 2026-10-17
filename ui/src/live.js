// Polls /state; reloads the preview when the build changed for a reason other than our own save.
import { api } from './api.js';
import { getState, setState } from './store.js';
import { refreshGit, refreshSite, reloadPreview } from './actions.js';

let timer = null;
let busy = false;

async function tick() {
  if (busy) return;
  busy = true;
  try {
    const st = await api.state();
    const prev = getState();
    setState({ build: st, offline: false });
    if (prev.seenBuildId == null) {
      setState({ seenBuildId: st.build_id });
    } else if (st.build_id !== prev.seenBuildId && prev.saving === 0) {
      setState({ seenBuildId: st.build_id });
      reloadPreview();
      refreshSite();
      refreshGit();
    }
  } catch {
    setState({ offline: true });
  } finally {
    busy = false;
  }
}

export function startLive(intervalMs = 1500) {
  if (timer) return;
  tick();
  timer = setInterval(tick, intervalMs);
}

export function stopLive() {
  clearInterval(timer);
  timer = null;
}
