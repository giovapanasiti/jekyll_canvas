// Stand-in for the Ruby engine: implements tasks/spec-api.md against a tiny in-memory
// "Jekyll site" so the UI can be exercised without Ruby.
//   node ui/dev/stub-server.mjs           (port: JC_STUB_PORT, default 4010)
// Serves the built UI from engine/public at /__jc/ (run `npm run build` first).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.resolve(HERE, '../../engine/public');
const PORT = Number(process.env.JC_STUB_PORT || 4010);
const TOKEN = process.env.JC_STUB_TOKEN || crypto.randomBytes(16).toString('hex');
const LANGS = ['en', 'it'];
const DEFAULT_LANG = 'en';

// ---------------------------------------------------------------- site sources
const files = new Map(Object.entries({
  '_data/i18n/en.yml': `nav:
  home: Home
  blog: Blog
home:
  hero:
    title: We build careful software
    lead: A small studio crafting websites and tools that last.
    alt: Studio workspace
  cta: Read the blog
`,
  '_data/i18n/it.yml': `nav:
  home: Home
  blog: Blog
home:
  hero:
    title: Costruiamo software curato
    lead: Un piccolo studio che crea siti e strumenti fatti per durare.
    alt: Spazio di lavoro dello studio
  cta: Leggi il blog
`,
  '_layouts/default.html': `<!doctype html>
<html lang="{{ page.lang }}">
<head>
<meta charset="utf-8">
<title>{{ page.title }} - Stub Studio</title>
<style>
  body { font: 17px/1.6 Georgia, serif; margin: 0; color: #222; }
  nav { display: flex; gap: 20px; padding: 14px 40px; background: #f3f0ea; font-family: system-ui; }
  nav a { color: #333; text-decoration: none; }
  nav .sw { margin-left: auto; }
  main { max-width: 760px; margin: 40px auto; padding: 0 24px; }
  footer { padding: 24px 40px; background: #222; color: #ddd; font-family: system-ui; font-size: 14px; }
  .btn { display: inline-block; background: #6366f1; color: #fff; padding: 8px 16px; border-radius: 6px; text-decoration: none; }
  img { max-width: 100%; border-radius: 8px; }
  pre { background: #f4f4f4; padding: 12px; overflow: auto; }
  .meta { color: #888; font-family: system-ui; font-size: 14px; }
</style>
</head>
<body>
{% include header.html %}
<main>
{{ content }}
</main>
{% include footer.html %}
</body>
</html>
`,
  '_layouts/post.html': `---
layout: default
---
<article>
  <h1>{{ page.title }}</h1>
  <p class="meta">Published {{ page.date }}</p>
  <img src="{{ page.image }}" alt="{{ page.title }}">
  {{ content }}
</article>
`,
  '_includes/header.html': `<nav>
  <a href="{{ site.home }}">{{ t.nav.home }}</a>
  <a href="{{ site.blog }}">{{ t.nav.blog }}</a>
  <a href="{{ site.about }}">About</a>
  <a class="sw" href="{{ switch.url }}">{{ switch.label }}</a>
</nav>
`,
  '_includes/footer.html': `<footer>
  <p>We are a small team building careful software.</p>
  <p>Visitors today: {{ counter }}</p>
</footer>
`,
  'index.html': `---
layout: default
title: Home
hero_image: /assets/img/stub/one.svg
---
<section class="hero">
  <h1>{{ t.home.hero.title }}</h1>
  <p class="lead">{{ t.home.hero.lead }}</p>
  <img src="{{ page.hero_image }}" alt="{{ t.home.hero.alt }}">
  <p>This sentence is written directly in the page.</p>
  <p><a class="btn" href="{{ site.blog }}">{{ t.home.cta }}</a></p>
</section>
`,
  'about.html': `---
layout: default
title: About
---
<h1>About us</h1>
<p>We are a small team building careful software.</p>
<p>Our studio is based in a quiet town &amp; we answer every email.</p>
`,
  '_posts/en/2026-10-01-hello.md': `---
layout: post
title: Hello world
date: 2026-10-01
page_id: hello
tags: [news, studio]
image: /assets/img/stub/two.svg
draft: false
order: 3
---
## A first heading

This is the **first** paragraph of the post, with a [link](/about/) and \`code\`.

Second paragraph
that spans two lines.

- one
- two

\`\`\`js
console.log("hi")
\`\`\`

> A quoted line.
`,
  '_posts/it/2026-10-01-ciao.md': `---
layout: post
title: Ciao mondo
date: 2026-10-01
page_id: hello
tags: [novità, studio]
image: /assets/img/stub/two.svg
draft: false
order: 3
---
## Un primo titolo

Questo è il **primo** paragrafo dell'articolo.

Un secondo paragrafo.
`,
}));
const original = new Map(files); // "HEAD"

const svg = (bg, label) => Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360"><rect width="640" height="360" fill="${bg}"/><text x="320" y="190" font-family="sans-serif" font-size="48" fill="#fff" text-anchor="middle">${label}</text></svg>`);
const media = new Map([
  ['assets/img/stub/one.svg', { buf: svg('#6366f1', 'One'), type: 'image/svg+xml', mtime: 1760700000 }],
  ['assets/img/stub/two.svg', { buf: svg('#0ea5e9', 'Two'), type: 'image/svg+xml', mtime: 1760700100 }],
  ['assets/img/stub/three.svg', { buf: svg('#22c55e', 'Three'), type: 'image/svg+xml', mtime: 1760700200 }],
]);
const originalMedia = new Set(media.keys());

let buildId = 1;
let lastBuildMs = 312;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- YAML subset
// Handles `key: value` maps nested by indentation and flow arrays; enough for the fixtures.
function parseScalar(raw) {
  const v = raw.trim();
  if (v === '' || v === '~' || v === 'null') return null;
  if (/^".*"$/.test(v)) { try { return JSON.parse(v); } catch { return v.slice(1, -1); } }
  if (/^'.*'$/.test(v)) return v.slice(1, -1).replace(/''/g, "'");
  if (v === 'true') return true;
  if (v === 'false') return false;
  if (/^-?\d+(\.\d+)?$/.test(v)) return Number(v);
  if (v.startsWith('[') && v.endsWith(']')) {
    const inner = v.slice(1, -1).trim();
    return inner ? inner.split(',').map(parseScalar) : [];
  }
  return v;
}

function parseYaml(text) {
  const data = {};
  const entries = []; // { keypath, line, vs, ve } (line is 0-based inside text)
  const stack = [{ indent: -1, obj: data, keypath: [] }];
  const lines = text.split('\n');
  lines.forEach((ln, i) => {
    const m = ln.match(/^(\s*)([A-Za-z0-9_-]+):(?:\s+(.*?))?\s*$/);
    if (!m || ln.trim().startsWith('#')) return;
    const indent = m[1].length;
    while (stack.length > 1 && stack[stack.length - 1].indent >= indent) stack.pop();
    const parent = stack[stack.length - 1];
    const key = m[2];
    const keypath = [...parent.keypath, key];
    if (m[3] === undefined || m[3] === '') {
      const next = lines[i + 1] || '';
      if (/^\s+[A-Za-z0-9_-]+:/.test(next) && next.match(/^\s*/)[0].length > indent) {
        parent.obj[key] = {};
        stack.push({ indent, obj: parent.obj[key], keypath });
        return;
      }
      parent.obj[key] = null;
      return;
    }
    const vs = ln.indexOf(m[3], m[1].length + key.length + 1);
    entries.push({ keypath, line: i, vs, ve: vs + m[3].length });
    parent.obj[key] = parseScalar(m[3]);
  });
  return { data, entries };
}

function quote(s) {
  if (/^[A-Za-z0-9][A-Za-z0-9 ._\/-]*$/.test(s) && !/^(true|false|null|~|-?\d+(\.\d+)?)$/.test(s) && !/ $/.test(s)) return s;
  return JSON.stringify(s);
}
function serialise(v) {
  if (Array.isArray(v)) return `[${v.map(serialise).join(', ')}]`;
  if (typeof v === 'string') return quote(v);
  if (v === null) return 'null';
  return String(v);
}

const get = (obj, kp) => kp.reduce((o, k) => (o == null ? undefined : o[k]), obj);
const deepEq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---------------------------------------------------------------- file helpers
function splitFm(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!m) return { raw: null, data: null, bodyOffset: 0, body: text, bodyStartLine: 1, fmEnd: 0 };
  const raw = m[1] + '\n';
  const bodyOffset = m[0].length;
  return {
    raw, data: parseYaml(raw).data, bodyOffset, fmEnd: bodyOffset,
    body: text.slice(bodyOffset), bodyStartLine: m[0].split('\n').length - (m[0].endsWith('\n') ? 1 : 0) + 1,
  };
}
const isMd = (f) => /\.(md|markdown)$/.test(f);
const lineOf = (text, offset) => text.slice(0, offset).split('\n').length;

// ---------------------------------------------------------------- routing / rendering
function docUrl(file) {
  const lang = file.includes('/it/') ? 'it' : 'en';
  const slug = path.basename(file).replace(/^\d{4}-\d{2}-\d{2}-/, '').replace(/\.md$/, '');
  return { lang, url: `${lang === DEFAULT_LANG ? '' : '/' + lang}/blog/${slug}/` };
}
const prefix = (lang) => (lang === DEFAULT_LANG ? '' : `/${lang}`);

function routes() {
  const out = [];
  for (const file of ['index.html', 'about.html']) {
    if (!files.has(file)) continue;
    for (const lang of LANGS) {
      const base = file === 'index.html' ? '/' : '/about/';
      out.push({ file, lang, kind: 'page', collection: null, url: prefix(lang) + base });
    }
  }
  for (const file of files.keys()) {
    if (!file.startsWith('_posts/')) continue;
    const { lang, url } = docUrl(file);
    out.push({ file, lang, kind: 'document', collection: 'posts', url });
  }
  return out;
}
const normUrl = (u) => {
  let p = (u || '/').split('?')[0].split('#')[0];
  p = p.replace(/index\.html$/, '');
  if (!p.endsWith('/') && !/\.[a-z0-9]+$/i.test(p)) p += '/';
  return p || '/';
};
const findRoute = (url) => routes().find((r) => r.url === normUrl(url));

const NO_STRINGS = new Set(['layout', 'lang', 'page_id', 'permalink', 'lang-exclusive', 'redirect_from', 'published', 'sitemap', 'rendered_lang', 'date']);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function siblingsFor(file, keypath, value, source) {
  const out = [];
  if (source === 'data') {
    const seg = file.split('/').find((s) => LANGS.includes(s.replace(/\.yml$/, '')));
    if (!seg) return out;
    const cur = seg.replace(/\.yml$/, '');
    for (const l of LANGS) {
      if (l === cur) continue;
      const f = file.replace(seg, seg.endsWith('.yml') ? `${l}.yml` : l);
      const v = files.has(f) ? get(parseYaml(files.get(f)).data, keypath) : undefined;
      if (typeof v === 'string') out.push({ lang: l, file: f, keypath, value: v });
    }
  } else {
    const pid = splitFm(files.get(file) || '').data?.page_id;
    if (!pid) return out;
    for (const [f, text] of files) {
      if (f === file || !f.startsWith('_posts/')) continue;
      const fm = splitFm(text).data;
      if (fm?.page_id !== pid) continue;
      const v = get(fm, keypath);
      if (typeof v === 'string') out.push({ lang: docUrl(f).lang, file: f, keypath, value: v });
    }
  }
  return out;
}

function renderMarkdownInline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
}

// Top-level blocks of a Markdown body with their 1-based file lines.
function mdBlocks(body, startLine) {
  const lines = body.split('\n');
  const blocks = [];
  let i = 0;
  while (i < lines.length) {
    if (!lines[i].trim()) { i++; continue; }
    const start = i;
    let type = 'p';
    let level = null;
    if (/^```/.test(lines[i])) {
      type = 'codeblock';
      i++;
      while (i < lines.length && !/^```/.test(lines[i])) i++;
      i++;
    } else if (/^#{1,6}\s/.test(lines[i])) {
      type = 'header'; level = lines[i].match(/^#+/)[0].length; i++;
    } else {
      const kind = /^[-*]\s/.test(lines[i]) ? 'ul' : /^\d+\.\s/.test(lines[i]) ? 'ol' : /^>\s?/.test(lines[i]) ? 'blockquote' : 'p';
      type = kind;
      while (i < lines.length && lines[i].trim()) i++;
    }
    const end = Math.min(i, lines.length) - 1;
    blocks.push({
      start_line: startLine + start, end_line: startLine + end, type, header_level: level,
      markdown: lines.slice(start, end + 1).join('\n'),
    });
  }
  return blocks;
}

function renderMarkdown(body, startLine) {
  return mdBlocks(body, startLine).map((b) => {
    const a = `data-jc-line="${b.start_line}"`;
    const md = b.markdown;
    switch (b.type) {
      case 'header': return `<h${b.header_level} ${a}>${renderMarkdownInline(md.replace(/^#+\s*/, ''))}</h${b.header_level}>`;
      case 'ul': return `<ul ${a}>${md.split('\n').map((l) => `<li>${renderMarkdownInline(l.replace(/^[-*]\s/, ''))}</li>`).join('')}</ul>`;
      case 'ol': return `<ol ${a}>${md.split('\n').map((l) => `<li>${renderMarkdownInline(l.replace(/^\d+\.\s/, ''))}</li>`).join('')}</ol>`;
      case 'blockquote': return `<blockquote ${a}>${renderMarkdownInline(md.replace(/^>\s?/gm, ''))}</blockquote>`;
      case 'codeblock': return `<pre ${a}><code>${esc(md.split('\n').slice(1, -1).join('\n'))}</code></pre>`;
      default: return `<p ${a}>${renderMarkdownInline(md)}</p>`;
    }
  }).join('\n');
}

function render(route) {
  const strings = new Map(); // dedupe key -> string entry
  const includes = [];
  const layouts = [];
  const text = files.get(route.file);
  const fm = splitFm(text);
  const fmData = fm.data || {};
  const i18nFile = `_data/i18n/${route.lang}.yml`;
  const i18n = parseYaml(files.get(i18nFile) || '').data;
  const other = LANGS.find((l) => l !== route.lang);
  const otherRoute = translations(route).find((t) => t.lang === other);
  const ctx = {
    page: { ...fmData, lang: route.lang },
    site: { home: prefix(route.lang) + '/', blog: prefix(route.lang) + '/blog/hello/', about: prefix(route.lang) + '/about/' },
    switch: { url: otherRoute?.url || '/', label: other.toUpperCase() },
    counter: String(1000 + Math.floor(Math.random() * 90)),
  };

  const record = (file, keypath, value, source) => {
    if (typeof value !== 'string' || value.length < 2) return;
    const key = file + JSON.stringify(keypath);
    if (strings.has(key)) return;
    strings.set(key, {
      id: `s${strings.size + 1}`, value, file, keypath, source,
      editable: true, siblings: siblingsFor(file, keypath, value, source),
    });
  };

  const lookup = (expr, content) => {
    const [root, ...rest] = expr.split('.');
    if (root === 'content') return content;
    if (root === 't') {
      const v = get(i18n, rest);
      record(i18nFile, rest, v, 'data');
      return v;
    }
    if (root === 'page') {
      const v = ctx.page[rest[0]];
      if (rest.length === 1 && Object.prototype.hasOwnProperty.call(fmData, rest[0]) && !NO_STRINGS.has(rest[0])) {
        record(route.file, rest, v, 'front_matter');
      }
      return Array.isArray(v) ? v.join(', ') : v;
    }
    return ctx[root] ? get(ctx[root], rest) : '';
  };

  const liquid = (src, content = '') => src
    .replace(/\{%\s*include\s+([\w.-]+)\s*%\}/g, (_, name) => {
      const f = `_includes/${name}`;
      if (!files.has(f)) return '';
      if (!includes.includes(f)) includes.push(f);
      return liquid(files.get(f), content);
    })
    .replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, expr) => {
      const v = lookup(expr, content);
      if (expr === 'content') return v;
      return v == null ? '' : esc(v);
    });

  let html = isMd(route.file) ? renderMarkdown(fm.body, fm.bodyStartLine) : fm.body;
  html = liquid(html);
  let layout = fmData.layout;
  while (layout) {
    const f = `_layouts/${layout}.html`;
    if (!files.has(f)) break;
    layouts.push(f);
    const lfm = splitFm(files.get(f));
    html = liquid(lfm.body, html);
    layout = lfm.data?.layout;
  }
  html = html.replace(/<img src=""[^>]*>/g, '');
  return { html, strings: [...strings.values()], layouts, includes };
}

function translations(route) {
  const all = routes();
  if (route.kind === 'page') {
    return all.filter((r) => r.file === route.file).map((r) => ({ lang: r.lang, url: r.url, file: r.file }));
  }
  const pid = splitFm(files.get(route.file)).data?.page_id;
  return all
    .filter((r) => r.kind === 'document' && (r.file === route.file || (pid && splitFm(files.get(r.file)).data?.page_id === pid)))
    .map((r) => ({ lang: r.lang, url: r.url, file: r.file }));
}

function pageJson(route) {
  const text = files.get(route.file);
  const fm = splitFm(text);
  const r = render(route);
  return {
    url: route.url, lang: route.lang, file: route.file, kind: route.kind, collection: route.collection,
    format: isMd(route.file) ? 'markdown' : 'html',
    title: fm.data?.title || route.file,
    front_matter: fm.raw == null ? null : { raw: fm.raw, data: fm.data },
    body_start_line: fm.bodyStartLine, body: fm.body,
    strings: r.strings, layouts: r.layouts, includes: r.includes,
    translations: translations(route),
  };
}

// ---------------------------------------------------------------- edits
class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}

function editYaml(op) {
  const text = files.get(op.file);
  if (text == null) throw new ApiError(404, 'not_found', `File non trovato: ${op.file}`);
  const isData = /\.ya?ml$/.test(op.file);
  const fm = isData ? { raw: text, bodyOffset: 0 } : splitFm(text);
  if (fm.raw == null) throw new ApiError(422, 'invalid', 'Il file non ha front matter');
  const region = isData ? text : fm.raw;
  const { data, entries } = parseYaml(region);
  const cur = get(data, op.keypath);
  if ('old' in op) {
    if (!deepEq(cur, op.old)) throw new ApiError(409, 'conflict', 'Il valore corrente è diverso');
  } else if (cur !== undefined) {
    throw new ApiError(409, 'conflict', 'La chiave esiste già');
  }
  const entry = entries.find((e) => deepEq(e.keypath, op.keypath));
  let next;
  if (entry) {
    const lines = region.split('\n');
    const ln = lines[entry.line];
    lines[entry.line] = ln.slice(0, entry.vs) + serialise(op.new) + ln.slice(entry.ve);
    next = lines.join('\n');
  } else {
    next = region.replace(/\n*$/, '\n') + `${op.keypath.join('.')}: ${serialise(op.new)}\n`;
  }
  files.set(op.file, isData ? next : text.slice(0, 4) + next.replace(/\n$/, '') + text.slice(4 + fm.raw.length - 1));
}

function editOp(op) {
  switch (op.op) {
    case 'yaml': editYaml(op); break;
    case 'literal': {
      const text = files.get(op.file);
      if (text == null) throw new ApiError(404, 'not_found', 'File non trovato');
      if (text.slice(op.start, op.end) !== op.old_text) throw new ApiError(409, 'conflict', 'Il testo è cambiato');
      files.set(op.file, text.slice(0, op.start) + esc(op.new_text).replace(/&quot;/g, '"') + text.slice(op.end));
      break;
    }
    case 'md_block': {
      const text = files.get(op.file);
      if (text == null) throw new ApiError(404, 'not_found', 'File non trovato');
      const lines = text.split('\n');
      const cur = lines.slice(op.start_line - 1, op.end_line).join('\n');
      if (cur !== op.old_markdown) throw new ApiError(409, 'conflict', 'Il blocco è cambiato');
      const repl = op.new_markdown === '' ? [] : op.new_markdown.split('\n');
      let count = op.end_line - op.start_line + 1;
      let from = op.start_line - 1;
      if (!repl.length && lines[op.end_line] === '') count++;
      lines.splice(from, count, ...repl);
      files.set(op.file, lines.join('\n'));
      break;
    }
    case 'body': {
      const text = files.get(op.file);
      if (text == null) throw new ApiError(404, 'not_found', 'File non trovato');
      const fm = splitFm(text);
      if ('old_body' in op && op.old_body !== fm.body) throw new ApiError(409, 'conflict', 'Il testo è cambiato');
      files.set(op.file, text.slice(0, fm.bodyOffset) + op.new_body.replace(/\n*$/, '\n'));
      break;
    }
    case 'front_matter_raw': {
      const text = files.get(op.file);
      if (text == null) throw new ApiError(404, 'not_found', 'File non trovato');
      const bad = op.new_yaml.split('\n').find((l) => l.trim() && !l.trim().startsWith('#') && !/^\s*[A-Za-z0-9_-]+:/.test(l) && !/^\s*-\s/.test(l));
      if (bad) throw new ApiError(422, 'invalid', `YAML non valido: ${bad}`);
      const fm = splitFm(text);
      files.set(op.file, `---\n${op.new_yaml.replace(/\n*$/, '\n')}---\n${fm.body}`);
      break;
    }
    default: throw new ApiError(422, 'invalid', `Operazione sconosciuta: ${op.op}`);
  }
}

// ---------------------------------------------------------------- locate
function locate(url, needle) {
  const route = findRoute(url);
  if (!route) throw new ApiError(404, 'not_found', 'Pagina sconosciuta');
  const r = render(route);
  const pattern = [...needle].map((ch) => {
    if (/\s/.test(ch)) return '\\s+';
    if (ch === '&') return '(?:&amp;|&#38;)';
    if (ch === '<') return '&lt;';
    if (ch === '>') return '&gt;';
    if (ch === '"') return '(?:"|&quot;|&#34;)';
    return ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }).join('').replace(/(\\s\+)+/g, '\\s+');
  const candidates = [];
  const spans = (t) => [...t.matchAll(/\{\{[\s\S]*?\}\}|\{%[\s\S]*?%\}/g)].map((m) => [m.index, m.index + m[0].length]);
  const sources = [route.file, ...r.layouts, ...r.includes];
  for (const f of sources) {
    const t = files.get(f);
    const from = f === route.file ? splitFm(t).bodyOffset : 0;
    const sp = spans(t);
    const re = new RegExp(pattern, 'g');
    re.lastIndex = from;
    for (let m = re.exec(t); m; m = re.exec(t)) {
      const s = m.index, e = s + m[0].length;
      if (sp.some(([a, b]) => s < b && e > a)) continue;
      candidates.push({
        file: f, start: s, end: e, line: lineOf(t, s), old_text: m[0],
        snippet: `…${t.slice(Math.max(0, s - 24), s)}${m[0]}${t.slice(e, e + 24)}…`.replace(/\n/g, ' '),
      });
    }
  }
  return { candidates };
}

// ---------------------------------------------------------------- git simulation
function gitStatus() {
  const out = [];
  for (const [p, t] of files) {
    if (!original.has(p)) out.push({ path: p, status: '??' });
    else if (original.get(p) !== t) out.push({ path: p, status: 'M' });
  }
  for (const p of media.keys()) if (!originalMedia.has(p)) out.push({ path: p, status: '??' });
  return out;
}

function lineDiff(a, b) {
  const x = a.split('\n'), y = b.split('\n');
  const dp = Array.from({ length: x.length + 1 }, () => new Array(y.length + 1).fill(0));
  for (let i = x.length - 1; i >= 0; i--) {
    for (let j = y.length - 1; j >= 0; j--) {
      dp[i][j] = x[i] === y[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  const out = [];
  let i = 0, j = 0;
  while (i < x.length && j < y.length) {
    if (x[i] === y[j]) { out.push(' ' + x[i]); i++; j++; }
    else if (dp[i + 1][j] >= dp[i][j + 1]) out.push('-' + x[i++]);
    else out.push('+' + y[j++]);
  }
  while (i < x.length) out.push('-' + x[i++]);
  while (j < y.length) out.push('+' + y[j++]);
  return out.join('\n');
}

// ---------------------------------------------------------------- HTTP
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css',
  '.svg': 'image/svg+xml', '.json': 'application/json', '.png': 'image/png', '.woff2': 'font/woff2',
  '.ico': 'image/x-icon', '.map': 'application/json',
};

function send(res, status, body, headers = {}) {
  const isBuf = Buffer.isBuffer(body);
  const payload = isBuf || typeof body === 'string' ? body : JSON.stringify(body);
  res.writeHead(status, {
    'Cache-Control': 'no-store',
    ...(isBuf || typeof body === 'string' ? {} : { 'Content-Type': 'application/json' }),
    ...headers,
  });
  res.end(payload);
}

const readBody = (req) => new Promise((resolve) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => resolve(Buffer.concat(chunks)));
});

function parseMultipart(buf, contentType) {
  const boundary = '--' + /boundary=(.+)$/.exec(contentType || '')?.[1];
  const start = buf.indexOf(boundary);
  if (start < 0) return null;
  const headEnd = buf.indexOf('\r\n\r\n', start);
  const head = buf.slice(start, headEnd).toString('utf8');
  const name = /filename="([^"]*)"/.exec(head)?.[1] || 'upload';
  const type = /Content-Type:\s*([^\r\n]+)/i.exec(head)?.[1] || 'application/octet-stream';
  const dataEnd = buf.indexOf('\r\n' + boundary, headEnd + 4);
  return { name, type, data: buf.slice(headEnd + 4, dataEnd < 0 ? buf.length : dataEnd) };
}

function siteJson() {
  const rs = routes();
  const title = (r) => splitFm(files.get(r.file)).data?.title || r.file;
  const pages = rs.filter((r) => r.kind === 'page').sort((a, b) => a.url.localeCompare(b.url));
  const posts = rs.filter((r) => r.kind === 'document')
    .sort((a, b) => String(splitFm(files.get(b.file)).data?.date).localeCompare(String(splitFm(files.get(a.file)).data?.date)));
  const item = (r) => ({ file: r.file, title: title(r), lang: r.lang, url: r.url });
  return {
    root: '/stub/site', name: 'stub-site', title: 'Stub Studio', languages: LANGS, default_lang: DEFAULT_LANG, git: true,
    groups: [
      { id: 'pages', label: 'Pagine', collection: null, can_create: false, items: pages.map(item) },
      { id: 'posts', label: 'Articoli', collection: 'posts', can_create: true, items: posts.map(item) },
    ],
  };
}

const stateJson = () => ({ build_id: buildId, building: false, error: null, last_build_ms: lastBuildMs });
const bump = async () => { buildId++; await sleep(120); lastBuildMs = 120 + Math.floor(Math.random() * 200); };

async function api(req, res, url) {
  const route = url.pathname.replace('/__jc/api', '');
  const q = Object.fromEntries(url.searchParams);
  const method = req.method;
  const raw = method === 'POST' ? await readBody(req) : null;
  const json = () => { try { return JSON.parse(raw.toString() || '{}'); } catch { throw new ApiError(422, 'invalid', 'JSON non valido'); } };

  if (method === 'GET' && route === '/state') return send(res, 200, stateJson());
  if (method === 'POST' && route === '/rebuild') { await bump(); return send(res, 200, { ok: true, ...stateJson() }); }
  if (method === 'POST' && route === '/_stub/external') { buildId++; return send(res, 200, { ok: true, ...stateJson() }); }
  if (method === 'GET' && route === '/site') return send(res, 200, siteJson());
  if (method === 'GET' && route === '/page') {
    const r = findRoute(q.url);
    if (!r) throw new ApiError(404, 'not_found', 'Pagina non trovata');
    return send(res, 200, pageJson(r));
  }
  if (method === 'GET' && route === '/md-block') {
    const t = files.get(q.file);
    if (t == null) throw new ApiError(404, 'not_found', 'File non trovato');
    const fm = splitFm(t);
    const line = Number(q.line);
    const b = mdBlocks(fm.body, fm.bodyStartLine).find((x) => line >= x.start_line && line <= x.end_line);
    if (!b) throw new ApiError(404, 'not_found', 'Blocco non trovato');
    return send(res, 200, { file: q.file, ...b });
  }
  if (method === 'POST' && route === '/locate') { const b = json(); return send(res, 200, locate(b.url, b.text)); }
  if (method === 'POST' && route === '/edit') {
    const op = json();
    editOp(op);
    await bump();
    return send(res, 200, { ok: true, build_id: buildId, build_ms: lastBuildMs, error: null });
  }
  if (method === 'POST' && route === '/new') {
    const b = json();
    if (b.collection !== 'posts') throw new ApiError(422, 'invalid', 'Collezione sconosciuta');
    const slug = b.slug || b.title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    const date = b.date || new Date().toISOString().slice(0, 10);
    const file = `_posts/${b.lang}/${date}-${slug}.md`;
    if (files.has(file)) throw new ApiError(409, 'conflict', 'Il file esiste già');
    files.set(file, `---\nlayout: post\ntitle: ${quote(b.title)}\ndate: ${date}\npage_id: ${slug}\ntags: []\nimage: ""\ndraft: false\norder: 0\n---\n`);
    await bump();
    return send(res, 200, { ok: true, file, url: docUrl(file).url });
  }
  if (method === 'GET' && route === '/file') {
    if (!files.has(q.file)) throw new ApiError(404, 'not_found', 'File non trovato');
    return send(res, 200, { file: q.file, content: files.get(q.file) });
  }
  if (method === 'GET' && route === '/media') {
    const data = [...media.entries()].map(([file, m]) => ({
      src: '/' + file, file, name: path.basename(file), size: m.buf.length, mtime: m.mtime,
    })).sort((a, b) => b.mtime - a.mtime);
    return send(res, 200, { uploads_dir: 'assets/img/uploads', data });
  }
  if (method === 'POST' && route === '/media') {
    const part = parseMultipart(raw, req.headers['content-type']);
    if (!part) throw new ApiError(422, 'invalid', 'Upload non valido');
    const base = part.name.replace(/[^A-Za-z0-9._-]/g, '-');
    let file = `assets/img/uploads/${base}`;
    for (let n = 2; media.has(file); n++) file = `assets/img/uploads/${n}-${base}`;
    media.set(file, { buf: part.data, type: part.type, mtime: Math.floor(Date.now() / 1000) });
    await bump();
    return send(res, 200, { ok: true, src: '/' + file, file });
  }
  if (method === 'GET' && route === '/git/status') return send(res, 200, { git: true, branch: 'main', files: gitStatus() });
  if (method === 'GET' && route === '/git/diff') {
    const cur = files.get(q.file);
    if (cur == null) throw new ApiError(404, 'not_found', 'Nessun diff disponibile');
    const old = original.get(q.file) ?? '';
    const head = `diff --git a/${q.file} b/${q.file}\n--- ${original.has(q.file) ? 'a/' + q.file : '/dev/null'}\n+++ b/${q.file}\n@@ @@\n`;
    return send(res, 200, { diff: head + lineDiff(old, cur) });
  }
  if (method === 'POST' && route === '/git/discard') {
    const { file } = json();
    if (original.has(file)) files.set(file, original.get(file));
    else { files.delete(file); media.delete(file); }
    await bump();
    return send(res, 200, { ok: true });
  }
  if (method === 'POST' && route === '/git/commit') {
    const { message, files: list } = json();
    if (!message) throw new ApiError(422, 'invalid', 'Messaggio mancante');
    const targets = list || gitStatus().map((f) => f.path);
    for (const f of targets) { if (files.has(f)) original.set(f, files.get(f)); if (media.has(f)) originalMedia.add(f); }
    return send(res, 200, { ok: true, sha: crypto.randomBytes(4).toString('hex').slice(0, 7) });
  }
  throw new ApiError(404, 'not_found', `Endpoint sconosciuto: ${method} ${route}`);
}

function serveStatic(res, urlPath) {
  let rel = urlPath.replace(/^\/__jc\/?/, '') || 'index.html';
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.resolve(PUBLIC, rel);
  if (!file.startsWith(PUBLIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    return send(res, 404, 'UI non compilata: esegui `npm run build` in ui/', { 'Content-Type': 'text/plain; charset=utf-8' });
  }
  return send(res, 200, fs.readFileSync(file), { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
}

function serveSite(res, urlPath) {
  const asset = media.get(decodeURIComponent(urlPath).replace(/^\//, ''));
  if (asset) return send(res, 200, asset.buf, { 'Content-Type': asset.type });
  const route = findRoute(urlPath);
  if (route) return send(res, 200, render(route).html, { 'Content-Type': 'text/html; charset=utf-8' });
  return send(res, 404, '<!doctype html><title>404</title><h1>404 - Not found</h1>', { 'Content-Type': 'text/html; charset=utf-8' });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (url.pathname === '/__jc') { res.writeHead(302, { Location: '/__jc/' + url.search }); return res.end(); }
    if (url.pathname.startsWith('/__jc/api/')) {
      if (req.headers['x-jc-token'] !== TOKEN) return send(res, 403, { ok: false, error: 'forbidden', code: 'forbidden' });
      return await api(req, res, url);
    }
    if (url.pathname.startsWith('/__jc/')) return serveStatic(res, url.pathname);
    return serveSite(res, url.pathname);
  } catch (e) {
    if (e instanceof ApiError) return send(res, e.status, { ok: false, error: e.message, code: e.code });
    console.error(e);
    return send(res, 500, { ok: false, error: String(e.message || e), code: 'build_failed' });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`JEKYLL_CANVAS_READY http://127.0.0.1:${PORT}/__jc/?token=${TOKEN}`);
});
