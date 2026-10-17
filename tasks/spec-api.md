# Jekyll Canvas — engine HTTP API (frozen contract between engine and UI)

Read `docs/design.md` first for context.

Engine binds `127.0.0.1:<port>`. On ready it prints exactly one line to STDOUT and flushes:

```
JEKYLL_CANVAS_READY http://127.0.0.1:<port>/__jc/?token=<token>
```

`<token>` is a random hex string (32 chars) generated at boot. Every `/__jc/api/*` request
must send header `X-JC-Token: <token>`; otherwise 403 `{"error":"forbidden"}`. The UI reads
the token from its own URL query string. Static UI files (`/__jc/`, `/__jc/assets/*`) and
site files do not need the token.

All API bodies are JSON (`Content-Type: application/json`), except media upload
(multipart). Errors: HTTP 4xx/5xx with `{"ok":false,"error":"<message>","code":"<code>"}`.
Codes: `forbidden`, `not_found`, `invalid`, `conflict`, `build_failed`, `git_failed`.

Paths called `file` are always relative to the site root, with `/` separators (e.g.
`_data/i18n/it.yml`, `_projects/it/frame.md`, `about.html`). The engine rejects any path
that resolves outside the root, inside `.git/`, or inside the build cache.

URLs called `url` are served URL paths, language-prefixed for non-default languages
(`/`, `/it/`, `/services/`, `/it/servizi/`, `/blog/my-post/`). The engine normalises
`/it/servizi` → `/it/servizi/` and `/index.html` → `/`.

Lines are 1-based. Character offsets (`start`, `end`) are 0-based indexes into the file
content as a Ruby/JS string of characters (not bytes), `end` exclusive.

---

## GET /__jc/api/state

```json
{ "build_id": 7, "building": false, "error": null, "last_build_ms": 1240 }
```
`build_id` increments after every successful build (edit, external change, manual).
`error` is the last build error message (string) when the last build failed; the previous
good build keeps being served.

## POST /__jc/api/rebuild
Forces a rebuild. Response like `/state` plus `"ok": true`.

## GET /__jc/api/site

```json
{
  "root": "/Users/x/site", "name": "nuovo_sito_mdg", "title": "Monte del Gallo",
  "languages": ["en","it"], "default_lang": "en", "git": true,
  "groups": [
    { "id": "pages", "label": "Pagine", "collection": null, "can_create": false,
      "items": [ { "file": "about.html", "title": "About", "lang": "en", "url": "/about/" } ] },
    { "id": "posts", "label": "Articoli", "collection": "posts", "can_create": true, "items": [] },
    { "id": "projects", "label": "Projects", "collection": "projects", "can_create": true, "items": [] }
  ]
}
```
- `pages` = rendered pages whose output is `.html` (excluding pages with a `redirect` key
  or under directories excluded from localization like `redirects/`), sorted by url.
- One group per collection with `output: true` (posts first, sorted by date desc; other
  collections sorted by `order` then title). `label` = collection label humanised, `posts`
  → "Articoli".
- Each item appears once per language it is rendered in. Items without `lang` (single-source
  pages) appear once per language with the corresponding url; `lang` is the language of
  that rendering.

## GET /__jc/api/page?url=/it/servizi/

```json
{
  "url": "/it/servizi/", "lang": "it",
  "file": "it/servizi.html", "kind": "page", "collection": null,
  "format": "html",
  "title": "Servizi",
  "front_matter": { "raw": "layout: default\ntitle: Servizi\n", "data": { "layout": "default", "title": "Servizi" } },
  "body_start_line": 7,
  "body": "...file body after front matter...",
  "strings": [
    { "id": "s1", "value": "Costruiamo prodotti AI",
      "file": "_data/i18n/it.yml", "keypath": ["home","hero","title"],
      "source": "data", "editable": true,
      "siblings": [ { "lang": "en", "file": "_data/i18n/en.yml", "keypath": ["home","hero","title"], "value": "We build AI products" } ] }
  ],
  "layouts": ["_layouts/page.html", "_layouts/default.html"],
  "includes": ["_includes/head.html", "_includes/header.html"],
  "translations": [ { "lang": "en", "url": "/services/", "file": "services.html" }, { "lang": "it", "url": "/it/servizi/", "file": "it/servizi.html" } ]
}
```
- `kind`: `page` | `document` (collection items and posts). `format`: `markdown` when the
  source extension is a Markdown one (`.md`, `.markdown`), else `html`.
- `front_matter` is `null` when the file has none. `data` is the file's own front matter
  (no defaults merged).
- `strings`: every String looked up by Liquid while rendering this page that comes from a
  `_data` file or from front matter literally present in a file, de-duplicated by
  (file, keypath). `source`: `data` | `front_matter`. `editable` is false for JSON/CSV data
  files. Values of these keys are never included: `layout`, `lang`, `page_id`, `permalink`,
  `lang-exclusive`, `redirect_from`, `published`, `sitemap`, `rendered_lang`, `date`.
  Values shorter than 2 characters are not included.
- `siblings` (other-language versions of the same string), computed by these rules:
  (a) the data file path has a segment equal to a site language (`_data/i18n/en.yml`,
  `_data/en/strings.yml`) → same keypath in the file with that segment swapped;
  (b) a keypath segment equals a site language (`nav.yml` `[3,"en"]`) → same file, segment
  swapped; (c) front matter of a file with `page_id` → the file with the same `page_id` in
  another language, same keypath. Only String values that exist are listed.
- `translations`: one entry per language the page is rendered in (single-source pages get
  one per site language).
- 404 `not_found` for unknown urls.

## GET /__jc/api/md-block?file=_posts/x.md&line=12

`line` is the file line found in a `data-jc-line` attribute of the rendered page. Returns the
top-level Markdown block containing that line:
```json
{ "file": "_posts/x.md", "start_line": 12, "end_line": 14, "type": "p", "header_level": null,
  "markdown": "First line of paragraph\nsecond line" }
```
`type`: `p`, `header`, `ul`, `ol`, `blockquote`, `codeblock`, `html_element`, `table`, `hr`,
`math`, `dl`, `other`. `markdown` is the exact source lines `start_line..end_line` joined by
`\n` (no trailing newline).

In the rendered HTML, top-level blocks of the current page's own Markdown body carry
`data-jc-line="<file line>"` (excerpts and other documents' content never do).

## POST /__jc/api/locate

Request `{ "url": "/about/", "text": "We are a small team" }`. Searches the page's own
source file (body only), its layouts and the includes it rendered for the text, with
whitespace runs matching any whitespace and HTML entities matching their characters
(`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`, `&apos;`, `&nbsp;`, numeric entities, typographic
apostrophes/quotes are NOT equivalent). Matches overlapping a `{{ … }}` or `{% … %}` span
are discarded.
```json
{ "candidates": [ { "file": "about.html", "start": 1032, "end": 1051, "line": 41,
    "old_text": "We are a small team", "snippet": "…<p>We are a small team that…" } ] }
```
`old_text` is the exact source substring `start...end`. Empty array when not found.

## POST /__jc/api/edit

Body is one operation. On success the engine writes the file, rebuilds, and responds
`{ "ok": true, "build_id": 8, "build_ms": 1100, "error": null }` (`error` set if the build
after the write failed; the write is kept). On failure nothing is written.

1. YAML value (data file or front matter of a page/document):
   `{ "op": "yaml", "file": "_data/i18n/it.yml", "keypath": ["home","hero","title"], "old": "Vecchio", "new": "Nuovo" }`
   - `new`: string, number, boolean, null, or array of scalars.
   - If the file is not a `.yml`/`.yaml` data file, the file's front matter is edited.
   - The current value at keypath must equal `old` (deep equality), else 409 `conflict`.
     If `old` is omitted and the key does not exist, the key is added to the parent
     mapping (parent must exist and be a mapping).
   - Only the bytes of that value change (see spec-engine.md YAML editor rules).
2. Literal text:
   `{ "op": "literal", "file": "about.html", "start": 1032, "end": 1051, "old_text": "We are a small team", "new_text": "We are a team" }`
   - `file[start...end]` must equal `old_text`, else 409. Replaced by `new_text` with `&`, `<`,
     `>` HTML-escaped.
3. Markdown block:
   `{ "op": "md_block", "file": "_posts/x.md", "start_line": 12, "end_line": 14, "old_markdown": "…", "new_markdown": "…" }`
   - Lines must equal `old_markdown` exactly, else 409. `new_markdown` may be several
     lines; an empty `new_markdown` deletes the block and one adjacent blank line.
4. Whole body:
   `{ "op": "body", "file": "_posts/x.md", "old_body": "…", "new_body": "…" }`
   - `old_body` optional; if present must equal the current body, else 409. The body is
     written with exactly one trailing newline.
5. Whole front matter:
   `{ "op": "front_matter_raw", "file": "_posts/x.md", "new_yaml": "title: X\n" }`
   - Must parse to a Hash, else 422 `invalid`.

## POST /__jc/api/new

Request `{ "collection": "posts", "lang": "it", "title": "Il mio post", "slug": null, "date": "2026-10-17" }`
→ `{ "ok": true, "file": "_posts/it/2026-10-17-il-mio-post.md", "url": "/it/blog/il-mio-post/" }`
(see spec-engine.md for the template rules). 409 if the file exists.

## GET /__jc/api/file?file=about.html
`{ "file": "about.html", "content": "…" }`

## GET /__jc/api/media
`{ "uploads_dir": "assets/img/uploads", "data": [ { "src": "/assets/img/blog/x.webp", "file": "assets/img/blog/x.webp", "name": "x.webp", "size": 12345, "mtime": 1760700000 } ] }`
Images (`png jpg jpeg webp gif svg avif`) anywhere in the source tree except `_site`,
dot-dirs, `node_modules`, `vendor`, the destination and excluded dirs; newest first.

## POST /__jc/api/media (multipart, field `file`)
Saves into `uploads_dir` (default `assets/img/uploads`, overridable by `uploads_dir` in
`.jekyll-canvas.yml` at the site root) with a sanitised unique filename, rebuilds,
returns `{ "ok": true, "src": "/assets/img/uploads/photo.webp", "file": "assets/img/uploads/photo.webp" }`.

## Git
- `GET /__jc/api/git/status` → `{ "git": true, "branch": "main", "files": [ { "path": "_data/i18n/it.yml", "status": "M" } ] }`
  (`status` is the porcelain XY collapsed: `M`, `A`, `D`, `R`, `??`). `{ "git": false }`
  when the site is not in a git work tree.
- `GET /__jc/api/git/diff?file=…` → `{ "diff": "<unified diff>" }` (untracked: diff vs
  /dev/null).
- `POST /__jc/api/git/discard` `{ "file": "…" }` → restore from HEAD (untracked: delete the
  file), then rebuild. `{ "ok": true }`.
- `POST /__jc/api/git/commit` `{ "message": "…", "files": ["…"] }` → stage the listed files
  (all changed files if omitted) and commit with the repository's own git identity.
  `{ "ok": true, "sha": "abc1234" }`.

## Site files
Any other path is served from the build destination: exact file, else `<path>/index.html`,
else `<path>.html`; otherwise `404.html` with status 404. `Cache-Control: no-store`.
