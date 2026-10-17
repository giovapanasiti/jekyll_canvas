export const normalize = (s) => String(s).replace(/\s+/g, ' ').trim();

// Normalised text plus, for each normalised char, its index in the raw string.
export function normalizeMap(raw) {
  let text = '';
  const map = [];
  let pendingSpace = false;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    if (/\s/.test(ch)) {
      pendingSpace = text.length > 0;
      continue;
    }
    if (pendingSpace) {
      text += ' ';
      map.push(i - 1);
      pendingSpace = false;
    }
    text += ch;
    map.push(i);
  }
  return { text, map };
}

// Raw [start, end) of the normalised range [nStart, nEnd).
export function rawRange(nm, nStart, nEnd) {
  return { start: nm.map[nStart], end: nm.map[nEnd - 1] + 1 };
}

export function normUrl(u) {
  if (!u) return '/';
  let p = u.split('#')[0].split('?')[0];
  if (p === '/index.html') return '/';
  p = p.replace(/index\.html$/, '');
  if (!p.endsWith('/') && !/\.[a-z0-9]+$/i.test(p)) p += '/';
  return p;
}

export const keyOf = (file, keypath) => file + '\u0000' + JSON.stringify(keypath);

export const joinKeypath = (kp) => kp.map(String).join(' › ');

export function slugify(s) {
  return String(s)
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export const isImagePath = (v) => typeof v === 'string' && /\.(png|jpe?g|webp|gif|svg|avif)$/i.test(v.trim());

export const todayISO = () => new Date().toISOString().slice(0, 10);

export const isMac = /Mac|iPhone|iPad/.test(navigator.platform || '');
export const isMod = (e) => (isMac ? e.metaKey : e.ctrlKey);
