# Spec — code editor for templates and page sources

Read `docs/design.md`, `tasks/spec-api.md`, `tasks/spec-engine.md`, `tasks/spec-ui.md` for
context. This adds a source-code editor (HTML + Liquid, also YAML/Markdown/SCSS by
extension) for layouts, includes and any page source, next to the visual editing.

Decided by Giovanni: a code editor (not GrapesJS). The file must stay exactly as written.

## Engine (additions to the frozen API — additive only)

1. `GET /__jc/api/site` gains:
   ```json
   "templates": {
     "layouts":  ["_layouts/default.html", "_layouts/project.html"],
     "includes": ["_includes/head.html", "_includes/home/hero.html"]
   }
   ```
   Files under the configured `layouts_dir` / `includes_dir` (defaults `_layouts`,
   `_includes`), recursive, sorted, text files only, excluding dotfiles.
2. `GET /__jc/api/file?file=…` (exists) also returns `"mtime"` (integer seconds) and
   `"language"`: `liquid-html` for `.html/.htm/.liquid/.xml`, `markdown` for `.md/.markdown`,
   `yaml` for `.yml/.yaml`, `scss` for `.scss/.sass/.css`, `javascript` for `.js`, `json` for
   `.json`, else `text`. Refuses binary files (NUL byte in the first 8 KB) with 422 `invalid`.
3. New edit op (in `edits.rb`):
   ```json
   { "op": "file", "file": "_layouts/default.html", "old_content": "…", "new_content": "…", "force": false }
   ```
   - `old_content` must equal the current file content, else 409 `conflict`.
   - Allowed: any existing text file inside the root (same path safety as other ops; never
     `.git/`, the cache, `_site`); refuses binary files. Creating new files is not allowed.
   - Liquid check unless `force: true`: for files whose language is `liquid-html` or
     `markdown`, split off front matter, parse the body with `Liquid::Template.parse(body,
     error_mode: :strict, line_numbers: true)` (Jekyll's tags/blocks are registered in the
     process after the first build). On `Liquid::SyntaxError` respond 422 with
     `code: "liquid_syntax"`, `error: <message>`, `line: <line number or null>` and write
     nothing. Front matter of such files must parse as a YAML Hash, else 422
     `code: "invalid"`.
   - On success: write the exact `new_content` (no newline normalisation), rebuild,
     respond like other ops (`{ok, build_id, build_ms, error}`; `error` set when the build
     after the write failed — the write is kept so the user can fix it).
4. Tests: op `file` happy path; conflict; liquid syntax error (e.g. unclosed `{% if %}`)
   → 422 with line and file unchanged; `force: true` writes anyway; binary refused; path
   outside root refused; `/site` templates list on the fixture; `/file` language + mtime.

Update `tasks/spec-api.md` with these additions (keep the rest untouched).

## UI

Libraries: `codemirror` (basic setup), `@codemirror/lang-liquid` (with its HTML base),
`@codemirror/lang-markdown`, `@codemirror/lang-yaml`, `@codemirror/lang-css`,
`@codemirror/lang-javascript`, `@codemirror/lang-json`, `@codemirror/theme-one-dark`.
Most are already in `node_modules` as Crepe dependencies — add them explicitly to
`package.json` pinned to the versions already installed (don't introduce a second copy
of `@codemirror/state`/`view`; run `npm ls @codemirror/state` and make sure it is
deduped).

1. **Code editor modal** `src/editors/CodeEditor.jsx`, full screen like the Body editor:
   - Left column (220px): "File della pagina" (page source file, its layouts, its includes,
     from the current page data) and "Tutti i template" (from `/site.templates`, grouped
     Layout / Include, with a filter box). Current file highlighted; files with unsaved
     changes marked with a dot.
   - Header: file path, language label, "Salva" (Cmd+S), "Chiudi" (confirm via the existing
     in-app confirm dialog if any open file is dirty).
   - Editor: CodeMirror 6 with line numbers, folding, bracket matching, search (Cmd+F),
     undo history per file, one-dark theme matching the app chrome, tab size 2, language by
     the engine's `language` (`liquid-html` → lang-liquid with HTML base).
   - Multiple files can be open in the session (switching keeps each file's buffer, cursor
     and history); saving saves the current file with `op:"file"` and `old_content` = the
     content loaded (or last saved).
   - 409 → in-app dialog "Il file è cambiato fuori dall'editor" with "Ricarica" (discard
     local buffer, reload) and "Sovrascrivi" (re-fetch to get current content as
     `old_content`, then save the buffer).
   - 422 `liquid_syntax` → red bar above the editor with the message, a "Vai alla riga N"
     link that moves the cursor, and "Salva comunque" (same op with `force:true`).
   - Successful save → toast "Salvato", the preview reloads (existing reload flow keeps
     scroll), git status refresh. Build error after save → existing error banner.
   - Opening at a line: `openCode(file, line?)` scrolls to and selects that line.
2. **Entry points**:
   - Inspector › Pagina: layouts/includes list items become clickable (open the code editor
     on that file); add button "Modifica sorgente" (opens the page's own file).
   - Inspector › Selezione: for literal targets "Apri nel codice" (file + line of the
     candidate); for markdown blocks "Apri nel codice" (page file, start_line); for string
     targets "Apri nel codice" opens the data file (line unknown → top; good enough).
   - Sidebar: a collapsible group "Template" at the bottom listing layouts and includes
     (filtered by the existing search box); clicking opens the code editor on that file
     (does not navigate the preview).
   - Toolbar: no change. Keyboard: Cmd+Shift+E opens the code editor on the current page's
     source.
3. Italian copy, same dark tokens. Build with `npm run build` (writes `engine/public`).

## Done when

- `cd engine && bundle exec rake test` green (with the new tests).
- `cd ui && npm run build` succeeds; `npm ls @codemirror/state` shows a single version.
- Manually on a `git clone` of `~/Projects/mdg/nuovo_sito_mdg` in the scratchpad (never the
  original): via curl, op `file` on `_includes/footer.html` changing one word → `git diff`
  shows exactly that change and `build_id` increments; an unclosed `{% if %}` → 422
  `liquid_syntax` with a line number and no change on disk.
