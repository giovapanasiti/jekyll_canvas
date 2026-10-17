# Spec — Ruby engine (`engine/`)

Read `docs/design.md` and `tasks/spec-api.md` first. This file adds implementation rules.

## Runtime constraints

- Runs as `bundle exec ruby -I<engine>/lib <engine>/exe/jekyll-canvas-server --site <path>`
  from the site directory, i.e. inside the SITE's bundle. Therefore the engine may only
  `require` stdlib/default gems plus what every Jekyll 4.x bundle contains: `jekyll`,
  `liquid`, `kramdown`, `webrick`, `psych`, `json`, `securerandom`, `digest`, `open3`,
  `fileutils`, `set`, `uri`. No nokogiri, no rack, no other gems.
- Ruby ≥ 3.1. Jekyll 4.x. Must work with and without jekyll-polyglot.
- `exe/jekyll-canvas-server` options: `--site PATH` (default cwd), `--port N` (default 0 =
  random free port), `--cache-dir PATH` (default `~/Library/Caches/JekyllCanvas/<sha1 of
  realpath of site>[0,12]`), `--open` (open the editor URL with `open` after ready, for the
  dev CLI). Logs go to STDERR. Ready line per spec-api.md goes to STDOUT.
- Never write inside the site folder except the files an API call explicitly edits,
  creates, uploads or discards. Build overrides: `destination` = `<cache>/site`,
  `disable_disk_cache: true`, `incremental: false`, `watch: false`, `livereload: false`,
  `parallel_localization: false`, `quiet: true`, `show_drafts: false`.
- Build in-process: create a fresh `Jekyll::Site.new(Jekyll.configuration(overrides))` for
  each build and call `process`. One global `Mutex` serialises builds and edits. On
  exception keep the previous records/destination (build into a temp dir and swap with
  `FileUtils.mv`/rename on success, so a failed build never leaves a half-written site), store the
  error message in state.
- Engine dev setup: `engine/Gemfile` with `jekyll ~> 4.4`, `jekyll-polyglot ~> 1.14`,
  `webrick`, `minitest`, `kramdown-parser-gfm`. Tests: `cd engine && bundle exec rake test`
  (Rakefile with `Rake::TestTask`, test files `test/**/*_test.rb`).

## Files

```
engine/
  Gemfile, Rakefile, README.md
  exe/jekyll-canvas-server
  lib/jekyll_canvas.rb            # requires everything below
  lib/jekyll_canvas/{version,cli,paths,front_matter,yaml_editor,markdown_blocks,
                     tracer,records,builder,locator,new_document,media,git,watcher,server}.rb
  public/index.html               # placeholder; the UI build (ui/) overwrites public/
  test/fixtures/site/…            # small bilingual polyglot site (see Tests)
  test/*_test.rb
```

## Tracer (`tracer.rb`, `records.rb`)

- Register hooks once at load (guard against double registration):
  - `:site, :post_read` → build the identity index for this pass:
    `@index = {}.compare_by_identity` mapping each leaf `String` object to
    `{file:, keypath:, source:}`.
    - Data: walk the `_data` dir (respect `site.config['data_dir']`); for each
      `.yml/.yaml/.json/.csv/.tsv` file compute its key prefix (subdirs + basename without
      extension, as Jekyll's DataReader does: sanitized names) and walk
      `site.data.dig(*prefix)`; Hash keys and Array indexes form the keypath.
    - Front matter: for every `site.pages` entry and every document of every collection
      (incl. posts), read the file's own front matter keys (parse the raw front matter with
      `SafeYAML`/Psych safe_load with permitted Date/Time classes); for each top-level key present
      in the file, walk `doc.data[key]` (Jekyll's objects, for identity) with keypath
      starting at `[key]`.
  - `[:pages, :documents], :pre_render` → set current record target (thread-local) to the
    doc; record layouts chain (`doc.data['layout']` → `site.layouts[name]`, follow each
    layout's `data['layout']`), file, kind, collection, lang (`site.active_lang`), url.
  - `[:pages, :documents], :post_render` → finalise the record, clear target.
- Prepend to `Liquid::VariableLookup#evaluate`: call super; if a target is active and the
  result is a String present in the index, add it to the target's strings (dedupe by
  file+keypath). Also record the String elements when the result is an Array of Strings.
- Prepend to `Jekyll::Tags::IncludeTag#render` (and `OptimizedIncludeTag`,
  `IncludeRelativeTag` if defined): record the resolved include file (relative path) on the
  active target.
- Prepend to the kramdown HTML converter used by Jekyll (`Kramdown::Converter::Html#convert`):
  when a thread-local "md target" is active and `el.type != :root` and `el` is a direct
  child of root (check via a parent pointer you set, or by converting root children in a
  wrapper), and `el.options[:location]` is set, add attribute
  `data-jc-line = body_start_line + location - 1` to the element (`el.attr`), for element
  types that render attributes (p, header, ul, ol, blockquote, codeblock, table, hr,
  html_element, dl, math). The "md target" is set by prepending `Jekyll::Renderer#convert`
  (or the markdown converter call inside it) only when the renderer's document is the
  record target and is NOT a `Jekyll::Excerpt`.
  Verify with a test that line numbers equal file lines (front matter offset).
- Records keyed by served url path: default language → `doc.url`; other languages →
  `"/#{lang}#{doc.url}"`. Polyglot's `site.active_lang` gives the pass language; without
  polyglot there is a single language (`site.config['lang'] || 'en'`).
- `translations`: docs with the same `page_id` (polyglot `permalink_lang` if present), or
  for docs without `lang` one entry per language with the prefixed url.
- `siblings`: rules in spec-api.md, computed when serving `/page` (read the sibling values
  from the current files with Psych, not from the build).

## Front matter (`front_matter.rb`)

Split a file into `front_matter_raw`, `body`, `body_start_line`, and character offsets of
the YAML region, using Jekyll's regexp semantics
(`/\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)/m`). Body = everything after the closing line.

## YAML editor (`yaml_editor.rb`) — the most important piece, test it hard

API: `YamlEditor.set(source_string, keypath, new_value, old: <optional>) → new_source_string`
and `YamlEditor.get(source, keypath)`. Works on a YAML document string (whole data file or
front matter region).

- Parse with `Psych.parse(source)` to get the node tree with `start_line/start_column/
  end_line/end_column` (0-based). Convert line/col to character offsets in `source`.
- Walk the keypath (mapping keys compared as strings; integers index sequences). Aliases
  and merge keys (`<<`) on the path → raise `Unsupported`.
- Scalar replacement keeps the original style when possible:
  - PLAIN → plain if the new value is a single line, has no leading/trailing spaces, does
    not start with any of `-?:,[]{}#&*!|>'"%@`` ` ``, contains no `: ` or ` #`, does not end
    with `:`, and would not load as a non-string (`true/false/yes/no/on/off/null/~`, numbers,
    dates — check by `Psych.safe_load(candidate)` returning the same String). Otherwise
    double-quoted.
  - SINGLE_QUOTED → single-quoted (`'` doubled) if single line, else double-quoted.
  - DOUBLE_QUOTED → double-quoted (escape `\` `"` and control chars, `\n` for newlines).
  - LITERAL (`|`) / FOLDED (`>`) → keep the block style and the content indentation of the
    original (indent = original content lines' indent; if the original was empty use the
    parent's indent + 2). Header: `|` if the value ends with `\n` (single trailing newline),
    `|-` if it ends without, `|+` if it ends with several. For FOLDED write each value line
    as its own paragraph (join lines with a blank line) so folding reproduces it.
  - Non-string new values (numbers, booleans, null) are written as plain YAML literals.
- Sequence of scalars replacement: if the original node is a flow sequence, write a flow
  sequence (`[a, "b c", 1]`, each item rendered with the plain/double-quoted rules); if
  block, rewrite its lines at the original indentation (`- item`), preserving the line
  prefix of the first item.
- Add key: append `key: value` as the last entry of the parent mapping, at the indentation
  of its existing keys (or parent indent + 2 if empty). Empty-flow parent `{}` → raise
  `Unsupported`.
- Verification (always): `Psych.safe_load(new_source, permitted_classes: [Date, Time], aliases: true)` must equal the
  original loaded structure with only that keypath changed. If not, retry once forcing
  double-quoted style; if still not equal raise `VerificationFailed`. Nothing is written on
  failure.
- Preserve everything else byte-for-byte (comments, blank lines, key order, line endings).
  Tests must assert the diff touches only the expected line(s), across: plain, quoted,
  single-quoted, block literal/folded, values with `: `, `#`, quotes, unicode (Italian
  accents, emoji), leading `*`/`&`, numeric-looking strings ("2026", "1.0"), multi-line
  replacements, nested sequences of mappings (`items[2].title`), keys with comments on the
  same line (`title: Foo # note` → comment kept), CRLF files.

## Markdown blocks (`markdown_blocks.rb`)

`MarkdownBlocks.blocks(body, kramdown_options) → [{start_line:, end_line:, type:, header_level:}]`
with lines relative to the body (1-based); parse with
`Kramdown::Document.new(body, options)` using the site's kramdown config (input from
`site.config['kramdown']['input']`, default `GFM`). Each root child with a `:location`
starts a block; a block ends at the line before the next block start, minus trailing
blank lines; skip `:blank` elements. `block_at(body, line)` returns the block containing
that line. The API converts to file lines with `body_start_line`.

## Locator (`locator.rb`)

Implements `/locate` per spec-api.md. Build a regex from the text: trim, split on
whitespace, escape each token, join with `\s+`; inside tokens make `&`, `<`, `>`, `"`, `'`
and non-breaking space also match their entity forms (named + numeric decimal/hex).
Search scope: the page's body region of its own file (only when `format == html`), each
layout file, each recorded include file. Compute Liquid spans (`{{…}}`, `{%…%}`) per file
and discard overlapping matches. Return all matches with line numbers.

## New document (`new_document.rb`)

- `slug`: given or derived from title (transliterate accents to ASCII, lowercase, non
  alnum → `-`, squeeze, trim).
- Template: the newest existing document of the same collection with the same `lang`
  (fallback: any language; fallback: empty). Copy its top-level front matter keys in
  order; values: `title` = title; `lang` = lang (only if the template had `lang`);
  `date` = date (posts, or if the template had `date`); `layout` kept; `lang-exclusive` =
  `[lang]` if the template had it; `page_id` = slug if the template had it; `categories`/
  `tags` kept as `[]`; booleans → false; other strings → `""`; arrays → `[]`; hashes →
  same keys with blank values (one level).
- Directory: same directory as the template (so `_projects/it/` for an Italian project when
  that's where Italian ones live; `_posts/` for posts). Posts filename
  `YYYY-MM-DD-slug.md`; others `slug.md`. Body: `\nScrivi qui il testo.\n`.
- Write the front matter with `YAML.dump`-free hand rendering that uses the scalar rules
  above so the file looks hand-written (`key: value`, lists as `[]` or block lists).
- Rebuild, find the record for the new file in the requested lang, return its url.

## Media (`media.rb`), Git (`git.rb`), Watcher (`watcher.rb`)

- Media per spec-api.md. Upload: parse WEBrick multipart (`req.query['file']` gives a
  `WEBrick::HTTPUtils::FormData` with `filename`), sanitise name (ASCII, lowercase, `-`),
  avoid overwrite by suffixing `-2`, `-3`.
- Git: shell out with `Open3.capture3('git', '-C', root, …)` (arrays, never a shell
  string). Discard: `git restore --source=HEAD --staged --worktree -- <file>`; untracked →
  `File.delete`. Commit: `git add -- <files>` then `git commit -m <message> -- <files>`.
- Watcher: background thread polling every 1 s the mtimes of all files under the source
  (excluding destination, cache dir, `_site`, `.git`, `.jekyll-cache`, `.sass-cache`,
  `node_modules`, `vendor`, `.bundle`, and Jekyll `exclude` entries). On change not caused
  by the engine's own write (ignore paths written in the last 2 s by the API), rebuild.

## Server (`server.rb`)

WEBrick bound to `127.0.0.1`, `AccessLog: []`, logger to STDERR at WARN. Routes per
spec-api.md. `/__jc/` and `/__jc/assets/*` served from `engine/public/` (index.html for
`/__jc/`). Graceful shutdown on INT/TERM (stop watcher, shutdown server, exit 0).

## Tests (must pass)

- Fixture site `test/fixtures/site`: `_config.yml` with polyglot (`languages: [en, it]`,
  `default_lang: en`), `_data/i18n/en.yml` + `it.yml` (nested keys, a list of items, a
  block scalar, a comment), `_data/nav.yml` with `en:`/`it:` leaves, `_layouts/default.html`
  using `t = site.data.i18n[site.active_lang]`, `_includes/header.html` with a hardcoded
  string and a loop over nav, a single-source `index.html` with i18n strings and
  `{% include header.html %}`, a paired `about.html` (`lang: en`, `page_id: about`) +
  `it/chi-siamo.html` (`lang: it`, `page_id: about`) with hand-written paragraphs, a
  collection `projects` with `_projects/alpha.md` (en) and `_projects/it/alfa.md` (it) with
  front matter (`title`, `summary`, `stack: [Ruby, Rails]`, `cover`) and Markdown body
  (heading, paragraphs, a list, a raw `<figure>` block), and 2 posts.
- Unit tests: yaml_editor (all cases above), front_matter, markdown_blocks, locator,
  new_document slug/template.
- Integration test: boot the builder on a temp copy of the fixture, assert records for `/`
  and `/it/` contain the expected i18n strings with correct file/keypath; `/projects/alpha/`
  strings include `summary` from front matter and `data-jc-line` attributes in the built
  HTML match file lines; perform each edit op through the server (real HTTP on a random
  port, with token) and assert file contents and that `build_id` increments; assert the
  fixture copy contains no new files after a build (`git status` clean or dir listing
  unchanged) except edited ones.
- Smoke script `engine/script/smoke-mdg.sh`: `git clone` the reference site
  `~/Projects/mdg/nuovo_sito_mdg` into a temp dir (never touch the original), run the
  server there, curl `/__jc/api/site`, `/__jc/api/page?url=/` and `/__jc/api/page?url=/it/`,
  print counts, stop the server.
