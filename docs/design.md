# Jekyll Canvas — design

Date: 2026-10-17. Author: Giovanni Panasiti.

## Intent

A local Mac app that opens any Jekyll site folder and lets me edit what I see on the
rendered page, writing each change back to the exact source it came from (front matter,
Markdown body, `_data` YAML, literal text in HTML pages, includes and layouts), plus write
new posts and collection items with a rich Markdown editor. The editing experience should
feel like ActiveCanvas (same visual language, same "edit the page, not the code" idea);
reusing its GrapesJS editor is a bonus, not a requirement.

Only user: me (a developer who knows Jekyll and git). That means no auth, no roles, git
is the safety net and history, and the UI can show technical details (file paths, key
paths) instead of hiding them.

Reference site used to validate the design: `~/Projects/mdg/nuovo_sito_mdg` (bilingual
EN/IT via jekyll-polyglot, collections, i18n in `_data/i18n/*.yml`, paired per-language
files linked by `page_id`). It is only ever read; tests run on a `git clone` copy.

## Goals (v1)

1. Dock app: pick a folder (or a recent one), see the real site rendered, navigate it.
2. Click any visible text and edit it inline; the change is written to the right file,
   touching only the edited bytes (no YAML reformatting, comments and key order kept).
3. Markdown bodies: edit paragraphs/headings inline; other blocks via a source popover;
   whole body via a WYSIWYG Markdown editor.
4. Front matter of the current page editable as a form; image fields with a media picker.
5. Create new posts / collection items (per language) and write them in the WYSIWYG
   editor; output is a clean `.md` file with front matter.
6. Bilingual awareness: for i18n strings and `page_id` pairs, show and edit the other
   language next to the current one; language switch in the toolbar.
7. Changes panel: git status, per-file diff, discard a file, commit.
8. Picks up edits made outside the app (VS Code) and refreshes the preview.

## Non-goals (v1)

- Structural page building (moving/adding sections, drag-and-drop blocks). Phase 2: a
  "builder mode" for hand-written HTML pages reusing the ActiveCanvas GrapesJS shell
  and its Liquid chips (extended to protect `{% %}` and includes).
- AI writing assistant. Phase 2: port `ai_panel.js` (SSE contract `chunk`/`error`).
- Editing layouts/includes structure, SCSS, `_config.yml`.
- Deploying/publishing; multi-user; Windows/Linux.
- Generating image variants or site-specific scripts (MdG's `make-image-variants.rb`).

## Anti-goals (failure even if it "works")

- Rewriting a whole file to change one string (noisy diffs, lost comments/formatting).
- Writing anywhere in the site folder other than the edited source files (no `_site`,
  no `.jekyll-cache`, no editor metadata files).
- Silently editing the wrong source when a text is ambiguous: ask instead.
- Requiring changes to the site's Gemfile or config to use the tool.

## Architecture (decided)

```
Jekyll Canvas.app (Swift, WKWebView)
  └─ spawns, per opened site:  zsh -lc 'cd SITE && bundle exec ruby -I ENGINE/lib ENGINE/exe/jekyll-canvas-server'
       Ruby engine (runs inside the site's own bundle: same Jekyll, same plugins)
         ├─ builds the site in-process into ~/Library/Caches/JekyllCanvas/<hash>/site
         │   with instrumentation hooks (source tracing)
         ├─ WEBrick on 127.0.0.1:<random>
         │    /__jc/          editor UI (static, built from ui/ with Vite + Preact)
         │    /__jc/api/*     JSON API (page targets, edits, new docs, media, git)
         │    /*              the built site (served from the cache dir)
         └─ polls the source tree for external changes and rebuilds
```

- **Why Swift instead of Tauri/Electron** (my call): Rust is not installed, Swift/Xcode is;
  a native shell is ~300 lines with no dependencies and builds with `swiftc`.
- **Why the engine in Ruby inside the site's bundle** (my call): source tracing needs to
  watch Jekyll/Liquid while rendering; running in the site's bundle guarantees the preview
  equals the production build. The engine is put on the load path with `-I`, so the
  site's Gemfile is never touched. Engine dependencies are limited to what every Jekyll 4
  bundle has: jekyll, liquid, kramdown, webrick, psych, json (no nokogiri).
- **Same origin**: the UI and the preview iframe are both served by the engine, so the UI
  reaches into the iframe DOM directly; no script is injected into the site's HTML.
- Polyglot is forced to `parallel_localization: false` so every language renders in the
  engine process (forked children would lose the tracing data).
- Login shell (`zsh -lc`) because a Dock app gets a bare PATH (rbenv/asdf/mise need it).

## Source tracing (decided)

Three complementary mechanisms, all computed per rendered page (key = served URL path,
e.g. `/it/servizi/`):

1. **Traced strings (data and front matter)** — after each language pass reads the site,
   build an identity index (`Hash#compare_by_identity`) of every leaf String in
   `site.data` (mapped to its `_data` file + key path) and in each document's/page's
   front matter (only keys literally present in the file). A prepended
   `Liquid::VariableLookup#evaluate` records every looked-up String that is in the index
   while a given page renders. Filters don't matter: recording happens at lookup. The UI
   then finds those values in the page's DOM text nodes and attributes.
2. **Markdown blocks** — while converting the current document's body (not excerpts),
   a prepended kramdown HTML converter adds `data-jc-line="<file line>"` to top-level
   block elements. Block ranges are recomputed server-side from a kramdown parse.
3. **Literal text** — anything else (hand-written HTML pages, text hardcoded in includes
   and layouts) is located lazily on click: whitespace-normalised, entity-aware search in
   the page's own source, its layout chain and the includes it rendered (recorded by a
   prepended include tag). Matches overlapping `{{ }}`/`{% %}` are discarded.

Ambiguity (same text from several sources): the UI shows a picker with file/key paths.
Not found (computed text like counts or years): the UI says so and offers the page's
files.

## Writing back (decided)

- **YAML (data files and front matter)**: parse with Psych to get node positions, replace
  only the scalar's byte range, keeping its quoting style when the new value allows it
  (plain → quoted if needed; block `|`/`>` kept as block with the same indent). After
  writing, re-parse and verify the whole document equals the expected structure; if not,
  retry with double quotes; if still not, refuse. Sequences of scalars can be replaced
  (block or flow style kept); new keys are appended to the mapping.
- **Markdown block**: replace exactly that block's lines. Inline edits of paragraphs and
  headings are converted HTML → Markdown in the UI (Turndown), keeping the heading's `#`
  prefix and any kramdown IAL suffix from the source.
- **Whole body**: replaced as a whole (the editor warns that formatting of the body may
  be normalised).
- **Literal text**: the matched range is replaced by the HTML-escaped new text.
- Every edit carries the old text; the server verifies the source still contains it at
  that place (otherwise 409 and the UI reloads the page data).
- Each edit triggers a rebuild (~1–2 s on the reference site); edits and builds are
  serialised by one mutex. Build errors keep the last good build and show a banner.

## UI (decided)

Visual language of the ActiveCanvas editor: dark chrome (`#252526`/`#2d2d2d`/`#3d3d3d`),
indigo accent `#6366f1`, system font, SF Mono for code. Layout: top toolbar (site name,
URL, language switch, build status, Changes button), left sidebar (pages, collections,
posts, search, "+ new"), center preview iframe with hover outlines on editable text,
right inspector (source of the selection, other-language value, front matter form, body
editor button). Italian UI copy.

Libraries (my call): Preact + Vite for the UI, `@milkdown/crepe` for WYSIWYG Markdown,
`turndown` for inline HTML → Markdown.

## Left to the builder

Exact component structure, CSS details, polling intervals, icon. Detailed contracts are
in `tasks/spec-engine.md`, `tasks/spec-ui.md`, `tasks/spec-desktop.md`.

## Calls I made without asking

- Swift shell instead of Tauri (no Rust toolchain).
- v1 scope: content editing first; builder mode (GrapesJS) and AI as phase 2.
- Git as the only history (no in-app versions).
- Uploads go to `assets/img/uploads/` unless `.jekyll-canvas.yml` sets `uploads_dir`.
- New documents copy the front matter keys of the newest sibling in the same collection
  and language, with blank values.
