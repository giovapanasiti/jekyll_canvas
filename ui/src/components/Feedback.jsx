import { useEffect, useRef } from 'preact/hooks';
import { useStore, setState } from '../store.js';
import { dismissToast } from '../actions.js';
import { Modal } from './Modal.jsx';

export function Toasts() {
  const toasts = useStore((s) => s.toasts);
  return (
    <div class="toasts">
      {toasts.map((t) => (
        <div key={t.id} class={`toast ${t.kind}`} onClick={() => dismissToast(t.id)}>{t.text}</div>
      ))}
    </div>
  );
}

export function ErrorBanner() {
  const error = useStore((s) => s.build.error);
  const dismissed = useStore((s) => s.dismissedError);
  if (!error || error === dismissed) return null;
  return (
    <div class="banner" role="alert">
      <pre>{error}</pre>
      <button class="btn sm" onClick={() => setState({ dismissedError: error })}>Chiudi</button>
    </div>
  );
}

// In-app replacement for window.confirm / window.prompt.
export function DialogHost() {
  const dialog = useStore((s) => s.dialog);
  const input = useRef(null);
  useEffect(() => { if (dialog?.kind === 'prompt') input.current?.select(); }, [dialog]);
  if (!dialog) return null;
  const done = (value) => { setState({ dialog: null }); dialog.resolve(value); };
  const isPrompt = dialog.kind === 'prompt';
  return (
    <Modal
      title={isPrompt ? dialog.text : 'Conferma'}
      onClose={() => done(isPrompt ? null : false)}
      className="small"
      footer={(
        <>
          <button class="btn" onClick={() => done(isPrompt ? null : false)}>{isPrompt ? 'Annulla' : 'Indietro'}</button>
          <button
            class={`btn ${dialog.danger ? 'danger' : 'primary'}`}
            onClick={() => done(isPrompt ? input.current.value : true)}
          >
            {dialog.okLabel || 'OK'}
          </button>
        </>
      )}
    >
      {isPrompt ? (
        <input
          ref={input} type="text" defaultValue={dialog.initial}
          onKeyDown={(e) => { if (e.key === 'Enter') done(e.currentTarget.value); }}
        />
      ) : (
        <p style="margin:0">{dialog.text}</p>
      )}
    </Modal>
  );
}
