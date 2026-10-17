# Jekyll Canvas engine

Ruby engine that builds a Jekyll site in-process with source tracing and serves a JSON API
(`/__jc/api/*`), the editor UI (`/__jc/`) and the built site (`/`). Contracts: `../tasks/spec-api.md`,
`../tasks/spec-engine.md`; design: `../docs/design.md`.

## Run

Inside the site's own bundle (the engine adds nothing to the site's Gemfile):

    cd /path/to/site
    bundle exec ruby -I/path/to/engine/lib /path/to/engine/exe/jekyll-canvas-server --site .

Options: `--site PATH`, `--port N` (0 = random), `--cache-dir PATH`, `--open`. The single stdout line
`JEKYLL_CANVAS_READY http://127.0.0.1:<port>/__jc/?token=<token>` is printed once the first build is done;
everything else goes to stderr.

## Test

    cd engine && bundle install && bundle exec rake test

`script/smoke-mdg.sh [site]` clones the reference site into a temp dir, runs the engine on the clone and prints
counts (it never touches the original).

## Layout

`lib/jekyll_canvas/` — `yaml_editor` (byte-preserving YAML edits), `tracer` + `records` (Liquid/kramdown/include
tracing), `builder` (in-process build into the cache dir), `edits`, `page_api`, `siblings`, `locator`,
`markdown_blocks`, `new_document`, `media`, `git`, `watcher`, `server`, `cli`.

Limitations: changes to `_plugins/*.rb` need an engine restart; `data-jc-line` is skipped for a Markdown body whose
Liquid changes its line count (the locate fallback still works).
