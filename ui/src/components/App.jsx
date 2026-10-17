import { useEffect } from 'preact/hooks';
import { useStore, setState, getState } from '../store.js';
import { openCode, refreshGit, refreshSite } from '../actions.js';
import { startLive } from '../live.js';
import { overlay } from '../overlay/index.js';
import { isMod } from '../util.js';
import { Toolbar } from './Toolbar.jsx';
import { Sidebar } from './Sidebar.jsx';
import { Preview } from './Preview.jsx';
import { Inspector } from '../inspector/Inspector.jsx';
import { ChangesDrawer } from './ChangesDrawer.jsx';
import { NewDocDialog } from './NewDocDialog.jsx';
import { MediaPicker } from './MediaPicker.jsx';
import { BodyEditor } from '../editors/BodyEditor.jsx';
import { CodeEditorHost } from '../editors/CodeEditor.jsx';
import { DialogHost, ErrorBanner, Toasts } from './Feedback.jsx';

export function App() {
  const mode = useStore((s) => s.mode);

  useEffect(() => {
    refreshSite();
    refreshGit();
    startLive();
    const onKey = (e) => {
      if (!isMod(e) || e.key.toLowerCase() !== 'e') return;
      e.preventDefault();
      if (e.shiftKey) openCode(getState().page?.file);
      else setState((s) => ({ mode: s.mode === 'edit' ? 'nav' : 'edit' }));
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => { overlay.applyMode(); }, [mode]);

  return (
    <div class="app">
      <Toolbar />
      <ErrorBanner />
      <div class="main">
        <Sidebar />
        <Preview />
        <Inspector />
      </div>
      <ChangesDrawer />
      <NewDocDialog />
      <BodyEditor />
      <CodeEditorHost />
      <MediaPicker />
      <DialogHost />
      <Toasts />
    </div>
  );
}
