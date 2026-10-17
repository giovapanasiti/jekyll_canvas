// Thin client for the engine API (tasks/spec-api.md). The token comes from the page URL.
const KEY = 'jc-token';

function readToken() {
  const fromUrl = new URLSearchParams(location.search).get('token');
  try {
    if (fromUrl) sessionStorage.setItem(KEY, fromUrl);
    return fromUrl || sessionStorage.getItem(KEY) || '';
  } catch {
    return fromUrl || '';
  }
}

const token = readToken();
const BASE = '/__jc/api';

async function request(method, path, { query, body, form } = {}) {
  let url = BASE + path;
  if (query) url += '?' + new URLSearchParams(query).toString();
  const headers = { 'X-JC-Token': token };
  let payload;
  if (form) {
    payload = form;
  } else if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  let res;
  try {
    res = await fetch(url, { method, headers, body: payload, cache: 'no-store' });
  } catch (e) {
    throw Object.assign(new Error('Motore non raggiungibile'), { code: 'network' });
  }
  let data = null;
  const text = await res.text();
  try { data = text ? JSON.parse(text) : null; } catch { /* non-JSON error page */ }
  if (!res.ok || (data && data.ok === false)) {
    const message = (data && data.error) || `Errore HTTP ${res.status}`;
    throw Object.assign(new Error(message), {
      code: (data && data.code) || (res.status === 404 ? 'not_found' : 'http'),
      status: res.status,
    });
  }
  return data;
}

const get = (path, query) => request('GET', path, { query });
const post = (path, body) => request('POST', path, { body: body ?? {} });

export const api = {
  state: () => get('/state'),
  rebuild: () => post('/rebuild'),
  site: () => get('/site'),
  page: (url) => get('/page', { url }),
  mdBlock: (file, line) => get('/md-block', { file, line }),
  locate: (url, text) => post('/locate', { url, text }),
  edit: (op) => post('/edit', op),
  newDoc: (payload) => post('/new', payload),
  file: (file) => get('/file', { file }),
  media: () => get('/media'),
  upload: (file) => {
    const form = new FormData();
    form.append('file', file);
    return request('POST', '/media', { form });
  },
  gitStatus: () => get('/git/status'),
  gitDiff: (file) => get('/git/diff', { file }),
  gitDiscard: (file) => post('/git/discard', { file }),
  gitCommit: (message, files) => post('/git/commit', { message, files }),
};
