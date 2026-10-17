import { render } from 'preact';
import './styles/tokens.css';
import './styles/base.css';
import './styles/layout.css';
import './styles/panels.css';
import './styles/modals.css';
import './styles/editor.css';
import { App } from './components/App.jsx';

render(<App />, document.getElementById('app'));
