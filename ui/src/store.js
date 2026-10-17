// Tiny global store: one immutable state object, setState merges, useStore subscribes.
import { useEffect, useRef, useState } from 'preact/hooks';

let state = {
  site: null,
  build: { build_id: null, building: false, error: null, last_build_ms: null },
  dismissedError: null,
  seenBuildId: null,
  saving: 0,
  mode: 'edit', // 'edit' | 'nav'
  inspectorOpen: true,
  currentUrl: '/',
  page: null,
  pageStatus: 'loading', // loading | ok | untracked | external
  selection: null,
  git: null, // { git, branch, files }
  toasts: [],
  // modal state
  bodyEditor: false,
  newDoc: null, // { collection, label }
  changesOpen: false,
  media: null, // { resolve }
  dialog: null, // { kind, text, initial, resolve, ... }
  chooser: null, // { x, y, title, items:[{label, detail, onPick}] }
};

const listeners = new Set();

export const getState = () => state;

export function setState(patch) {
  state = { ...state, ...(typeof patch === 'function' ? patch(state) : patch) };
  listeners.forEach((fn) => fn());
}

export function useStore(selector) {
  const [value, setValue] = useState(() => selector(state));
  const sel = useRef(selector);
  sel.current = selector;
  useEffect(() => {
    const fn = () => {
      const next = sel.current(state);
      setValue((prev) => (Object.is(prev, next) ? prev : next));
    };
    fn();
    listeners.add(fn);
    return () => listeners.delete(fn);
  }, []);
  return value;
}
