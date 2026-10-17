# Jekyll Canvas

Local Mac app to edit a Jekyll site visually, writing every change back to the exact
source it came from. Design: `docs/design.md`. Specs: `tasks/`.

## Use

1. `make app` (builds the UI, the Swift shell, bundles the engine) → `dist/Jekyll Canvas.app`.
   `make install` copies it to `~/Applications`.
2. Open the app, "Apri cartella…", pick a Jekyll site. The site must build with
   `bundle exec jekyll build` (the engine runs inside the site's own bundle; nothing is
   added to its Gemfile and nothing is written in the folder except the files you edit).
3. In **Modifica** mode hover the page: indigo = text from `_data`/front matter, green =
   Markdown block of the page body, grey dashed = text searched in the HTML source on click.
   Click and type; Enter (Cmd+Enter for Markdown paragraphs) saves, Esc cancels.
4. Right panel: source of the selection and its other-language versions, page info, front
   matter form, "Modifica testo completo" (WYSIWYG Markdown editor for the body).
5. "+" next to a collection in the sidebar creates a new post/item and opens the editor.
6. "Modifiche" shows git status, diffs, per-file discard and commit.

Cmd+click follows links while editing; **Naviga** mode turns editing off. Cmd+E toggles.

## Linux (Omarchy)

Runs the same engine in a Chromium app window (`chromium --app=URL`), no Swift shell.

Requirements: Ruby managed by `mise` (or asdf/rbenv/system), Bundler, a Chromium-family
browser (Chromium, Chrome, Brave, Edge; override with `JEKYLL_CANVAS_BROWSER`), optionally
`zenity` (or `kdialog`) for the folder picker. The site must build with `bundle exec jekyll build`.

```sh
make install-linux      # engine -> ~/.local/share/jekyll-canvas/engine, launcher -> ~/.local/bin,
                        # desktop entry + icon -> ~/.local/share (no npm needed)
```

Launch "Jekyll Canvas" from walker (it offers recent sites and "Altra cartella…"), or from a
terminal: `jekyll-canvas ~/path/to/site`. The launcher also runs straight from a checkout:
`linux/jekyll-canvas ~/path/to/site`. Closing the window stops the engine.

Hyprland window rule (the app window has class `JekyllCanvas`), e.g. in `hyprland.conf`:

```
windowrulev2 = size 1400 900, class:^(JekyllCanvas)$
windowrulev2 = center, class:^(JekyllCanvas)$
```

(Hyprland 0.53+ renamed the syntax: `windowrule = size 1400 900, match:class ^(JekyllCanvas)$`.)

Logs: `~/.local/state/jekyll-canvas/logs/<site>.log`. Recent sites:
`~/.config/jekyll-canvas/recents`. Browser profile: `~/.local/state/jekyll-canvas/browser-profile/`.
If start-up fails, a notification points at the log; "Could not find ..." usually means
`bundle install` is needed in the site folder.

Uninstall: `make uninstall-linux` (add `DATA=` / `BIN=` if you installed elsewhere).

## Develop

- Engine: `cd engine && bundle install && bundle exec rake test`. Run it on a site without
  the app: `cd SITE && bundle exec ruby -I/path/to/engine/lib /path/to/engine/exe/jekyll-canvas-server --site . --open`.
  `engine/script/smoke-mdg.sh` runs it on a throwaway clone of the Monte del Gallo site.
- UI: `cd ui && npm install && npm run build` (outputs to `engine/public`, committed).
  `JC_ENGINE_PORT=<port> npm run dev` for hot reload against a running engine;
  `node dev/stub-server.mjs` runs the UI against a fake engine.
- App: `desktop/build.sh`. `JEKYLL_CANVAS_ENGINE=<engine dir>` uses a development engine;
  `JEKYLL_CANVAS_OPEN=<site>` opens a site at launch.

## Known limitations (v1)

- No structural editing (moving/adding sections) and no AI panel yet: phase 2 (see design).
- Text built from several pieces (counts, years, `capture`) can't be edited in place; the
  app says so and lists the page's files.
- Inline Markdown edits go through HTML → Markdown conversion, so a paragraph you edit may
  get slightly different escaping; the whole-body editor normalises the body's formatting.
- Changes to a site's `_plugins/*.rb` need the site window to be reopened.
