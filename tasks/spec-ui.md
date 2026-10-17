# Spec — editor UI (`ui/`)

Read `docs/design.md` and `tasks/spec-api.md` first (the API is frozen; do not change it).

## Stack

- Vite + Preact (`@preact/preset-vite`), plain JS (no TypeScript), CSS files (no Tailwind).
- `@milkdown/crepe` (WYSIWYG Markdown, v7) and `turndown` (HTML → Markdown). Pin exact
  versions in package.json; use versions published at least 2 weeks ago.
- `vite.config.js`: `base: '/__jc/'`, build `outDir: '../engine/public'`, `emptyOutDir:
  true`, assets under `assets/`. Dev server proxy: `/__jc/api` and everything not under
  `/__jc/` → `http://127.0.0.1:${JC_ENGINE_PORT}` so `npm run dev` works against a running
  engine (`JC_ENGINE_PORT` env var).
- Scripts: `npm run dev`, `npm run build`. The build output is committed to `engine/public`
  by the coordinator (not by you).
- No external network requests at runtime (no CDNs, no Google Fonts): everything bundled.

## API client (`src/api.js`)

Reads `token` from `location.search` once (keep it in memory and in `sessionStorage` as a
fallback), sends `X-JC-Token` on every `/__jc/api/*` call, JSON in/out, throws an Error
with `code` and `message` on `ok:false`/HTTP errors.

## Layout and look

Visual language of the ActiveCanvas editor: dark chrome. Tokens: `--bg #1e1e1e`,
`--surface #252526`, `--surface-2 #2d2d2d`, `--border #3d3d3d`, `--text #e5e5e5`,
`--muted #9ca3af`, `--primary #6366f1`, `--primary-strong #4f46e5`, `--danger #ef4444`,
`--ok #22c55e`, `--radius 6px`; font `system-ui, -apple-system, sans-serif`, 13px base;
code `"SF Mono", Monaco, monospace`. All UI copy in Italian.

```
┌──────────────────────────── toolbar (44px) ────────────────────────────────────┐
│ ◧ nome-sito │ ‹ › ⟳  /it/servizi/            │ EN IT │ ✎ Modifica │ ● Pronto │ Modifiche (3) │
├──────────┬──────────────────────────────────────────────────────┬──────────────┤
│ sidebar  │                                                      │ inspector    │
│ 260px    │            preview iframe (site)                     │ 340px        │
│ search   │                                                      │ (collapsible)│
│ groups…  │                                                      │              │
└──────────┴──────────────────────────────────────────────────────┴──────────────┘
```

- Toolbar: site name; back/forward/reload for the iframe; current url (editable input,
  Enter navigates); language buttons from the current page's `translations` (active one
  highlighted; click navigates to that url); mode toggle "Modifica" / "Naviga"; build
  status dot (green Pronto / amber "Compilazione…" / red "Errore" with tooltip); "Modifiche
  (n)" opens the Changes drawer (n from git status, hidden if `git:false`).
- Error banner under the toolbar when `/state.error` is set (monospace message, dismissible).
- Sidebar: search box filtering items by title/file; collapsible groups from `/site`; each
  item shows title, small lang badge, and the file path on hover; active item highlighted
  (match current url). Groups with `can_create` show a "+" button → New document dialog.
- Preview iframe fills the center, `src` = site url. Default url `/`.

## Preview overlay (the core) — `src/overlay/`

The iframe is same-origin: access `iframe.contentDocument` after each `load`.

On every iframe load:
1. Read the iframe path (`contentWindow.location.pathname`), update toolbar url, fetch
   `/page?url=…` (ignore 404: show "pagina non tracciata" in the inspector, editing
   disabled).
2. Inject a `<style data-jc>` into the iframe document for outlines:
   hover outline `2px solid` with color by target type (string = `#6366f1`, markdown block
   = `#22c55e`, literal/unknown = `#9ca3af` dashed), `outline-offset: 2px`, `cursor: text`
   in edit mode; selected element outline `#f59e0b`.
3. Build target map:
   - **String targets**: walk text nodes under `body` (skip `script`, `style`, `noscript`,
     `template`, `svg`, and anything inside `[data-jc-ui]`). Normalise text (collapse
     whitespace, trim). For each `strings[]` entry, sorted by value length desc, value
     normalised the same way: match when the text node equals the value, or contains it
     and (value length ≥ 12 or the match is on word boundaries and value length ≥ 4). One
     text node can hold several targets (composite text). Also check attributes `alt`,
     `title`, `placeholder`, `aria-label`, `src`, `href`, `content` (meta) for exact equality
     → attribute targets on that element.
   - **Markdown targets**: elements with `data-jc-line` (only when the page `format` is
     markdown; the closest ancestor with the attribute wins).
   - Everything else with visible text → literal targets resolved lazily via `/locate`.
4. Edit mode on: listen (capture phase) for `mouseover`, `mouseout`, `click` in the iframe.
   Clicks never follow links/submit forms in edit mode (preventDefault), except
   Cmd+click which navigates. Naviga mode: no listeners, links work.

Click behaviour (edit mode):
- **String target text** (the clicked text node holds one or more string targets; if
  several, pick the one under the caret/click point via `caretRangeFromPoint`, else show a
  small chooser): split the text node around the occurrence, wrap it in
  `<span data-jc-ui contenteditable="plaintext-only">`, focus, select all. Enter (without
  Shift) or blur commits; Escape cancels (restore original text). Commit → `POST /edit`
  `{op:"yaml", file, keypath, old: value, new: newText}`. While saving show a small spinner
  badge next to the element. Success → reload the iframe and restore scroll position
  (save `scrollY` before, restore after next load). 409 → toast "Il file è cambiato,
  ricarico" and reload. Other errors → toast with message, keep the edit open.
  Inspector shows the target (see Inspector).
- **Markdown block** (`data-jc-line`): `GET /md-block?file=<page file>&line=N`.
  - If `type` is `p` or `header`: make the element itself `contenteditable="true"` with a
    mini floating toolbar (B, I, link, code) using `document.execCommand` inside the
    iframe; Cmd+B/Cmd+I/Cmd+K shortcuts. Commit on blur or Cmd+Enter; Escape cancels.
    Convert `innerHTML` with Turndown (`headingStyle:'atx'`, `emDelimiter:'*'`,
    `strongDelimiter:'**'`, `codeBlockStyle:'fenced'`, `bulletListMarker:'-'`). For headers
    reuse the original `#…` prefix (or `'#'.repeat(header_level)+' '` for setext) and keep a
    trailing kramdown IAL (`/\s*\{[:#.][^}]*\}\s*$/`) from the original markdown. Send
    `{op:"md_block", file, start_line, end_line, old_markdown: markdown, new_markdown}` (skip
    if unchanged).
  - Other types: open the Inspector "Blocco Markdown" panel with a monospace textarea of
    the block source + Salva / Annulla (same op).
- **Literal text**: `POST /locate {url, text: <text node normalised text>}`.
  - 1 candidate → inline plaintext edit like string targets → `{op:"literal", file, start,
    end, old_text, new_text}`.
  - Several → popover listing candidates (file:line + snippet) to choose, then edit.
  - 0 → toast "Testo non trovato nei sorgenti (probabilmente calcolato)", inspector lists
    the page's file, layouts and includes.
- **Images** (`img` clicked): Inspector shows the image with its `src`/`alt` targets; if
  `src` is a string target (front matter/data) → "Cambia immagine" opens the Media picker →
  `{op:"yaml", …, new: selected src}`; `alt` string target editable in the inspector.

## Inspector (right panel) — `src/inspector/`

Sections, top to bottom:
1. **Selezione** (when something is selected): type label, source path rendered as
   `file › key › path` (monospace) or `file:line`; current value in a textarea with Salva;
   **Altre lingue**: for string targets with `siblings`, one textarea per sibling (label =
   language code) with its own Salva (`op:"yaml"` on the sibling's file/keypath).
2. **Pagina**: file path, kind/collection, language, layouts and includes (collapsible
   list), buttons: "Apri traduzione" per translation, "Modifica testo completo" (markdown
   documents only) → Body editor.
3. **Front matter** (when `front_matter` not null): form generated from
   `front_matter.data` in key order: strings → input (textarea if > 80 chars or contains
   newline); numbers → number input; booleans → checkbox; Date-like strings → text;
   arrays of scalars → chip list editor (add/remove/reorder) saved as an array; values
   that look like image paths (`/\.(png|jpe?g|webp|gif|svg|avif)$/i`) → thumbnail + "Cambia"
   (Media picker) + input; hashes / arrays of hashes → read-only collapsed JSON preview.
   Each field saves on blur/change with `{op:"yaml", file, keypath:[key], old, new}`.
   Below the form: "Modifica YAML" → textarea with `front_matter.raw` + Salva
   (`op:"front_matter_raw"`).

## Body editor (modal, full screen) — `src/editors/BodyEditor.jsx`

Milkdown Crepe initialised with `page.body`; header with file path, toggle
"Visuale / Sorgente" (Sorgente = monospace textarea, switching syncs content), Salva
(`{op:"body", file, old_body: page.body, new_body}`), Chiudi (confirm if dirty). Note under
the header: "Salvando, la formattazione Markdown del corpo può essere normalizzata."
Crepe image upload (`featureConfigs[Crepe.Feature.ImageBlock].onUpload`) → `POST /media`
→ returns `src`. Import Crepe CSS (`@milkdown/crepe/theme/common/style.css` and
`@milkdown/crepe/theme/frame-dark.css` or the dark variant that exists in the pinned
version).

## New document dialog

Fields: Titolo (required), Lingua (select from site languages, default = current page
language; hidden for single-language sites), Slug (auto from title, editable), Data
(posts only, default today). Crea → `POST /new` → navigate iframe to returned url → open
the Body editor for it after the page data loads.

## Media picker (modal)

Grid of thumbnails from `GET /media` with search by name, "Carica…" button (hidden file
input, `POST /media` multipart) and drag-and-drop onto the modal; click selects and closes,
returning `src`.

## Changes drawer

Lists `git/status` files (status letter + path, checkbox each, all checked by default).
Clicking a file shows its diff (`git/diff`) with added/removed line colouring. Per-file
"Annulla" → `confirm('Annullare le modifiche a <file>?')` → `git/discard`. Bottom: commit
message input + "Commit" → `git/commit {message, files: checked}`. Refresh status every
time the drawer opens and after every successful edit.

## Live refresh

Poll `GET /state` every 1.5 s. When `build_id` changes and the change was not caused by
this UI's own save (which already reloads), reload the iframe preserving scroll; update
the status dot; refetch `/site` (sidebar) when `build_id` changes.

## Keyboard

Cmd+S inside editors = Salva; Escape closes modals / cancels inline edits; Cmd+E toggles
Modifica/Naviga.

## Done when

`npm run build` succeeds and writes `engine/public/index.html` + `assets/`. With an engine
running (or a stub — write `ui/dev/stub-server.mjs`, a tiny Node http server implementing
the API with fixture JSON and serving a sample site page with a few `data-jc-line`
elements, so the UI can be exercised without the Ruby engine), the editor loads, the
sidebar lists items, hover outlines appear, and each edit flow sends the documented
request.
