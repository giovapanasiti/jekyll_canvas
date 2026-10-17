import { useEffect, useRef } from 'preact/hooks';
import { overlay } from '../overlay/index.js';
import { Chooser } from './Chooser.jsx';

export function Preview() {
  const ref = useRef(null);
  useEffect(() => { overlay.attach(ref.current); }, []);
  return (
    <main class="preview">
      <iframe ref={ref} title="Anteprima del sito" />
      <Chooser />
    </main>
  );
}
