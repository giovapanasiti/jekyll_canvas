# Spec — macOS app shell (`desktop/`)

Read `docs/design.md` first. The app is a thin native shell: it picks a site folder,
starts the Ruby engine for it, and shows the editor UI the engine serves in a WKWebView.

## Build

- Swift 6 toolchain via `swiftc` (Xcode is installed; no Xcode project, no SwiftPM
  dependencies). Target `arm64-apple-macos13.0`. AppKit + WebKit only.
- `desktop/build.sh` (bash, `set -euo pipefail`):
  1. compile `desktop/Sources/*.swift` → `dist/Jekyll Canvas.app/Contents/MacOS/JekyllCanvas`
     (run with Swift 5 language mode `-swift-version 5` if strict concurrency gets in the
     way);
  2. write `Contents/Info.plist` (from `desktop/Info.plist`: bundle id
     `com.giovannipanasiti.jekyllcanvas`, name "Jekyll Canvas", `LSMinimumSystemVersion`
     13.0, `NSHighResolutionCapable`, `CFBundleIconFile` AppIcon, version 0.1.0);
  3. copy `engine/` into `Contents/Resources/engine/` excluding `test/`, `Gemfile.lock`,
     `.bundle/`, `script/`;
  4. generate `Contents/Resources/AppIcon.icns` from `desktop/icon/make_icon.swift` (a small
     Swift script that draws a 1024px icon with CoreGraphics: rounded square, indigo
     `#6366f1` → `#4f46e5` gradient, a white stylised brush/pen glyph or the letters "JC")
     using `sips` + `iconutil`;
  5. ad-hoc sign: `codesign --force --deep -s - "dist/Jekyll Canvas.app"`.
- Root `Makefile` targets: `app` (build UI if `ui/node_modules` exists → `npm --prefix ui
  run build`, then `desktop/build.sh`), `install` (copy the app to `~/Applications`),
  `test` (engine tests).

## Behaviour

- **Welcome window** (shown at launch and when no site window is open): title "Jekyll
  Canvas", big "Apri cartella…" button (NSOpenPanel, directories only), list of recent
  sites (name + path, double-click opens, max 10, stored in UserDefaults; remove missing
  ones). Validation: folder must contain `_config.yml` or `_config.yaml` or `_config.toml`,
  else an alert "Questa cartella non sembra un sito Jekyll".
- **Site window** (one per opened site; reopening an already open site focuses its window):
  title = folder name, size 1440×900 (min 1000×640), remembers frame per site path.
  Shows a native loading view ("Avvio di <nome>…", spinner, scrolling log text view) while
  the engine starts, then swaps in the WKWebView loading the ready URL.
- **Engine process**: `Process` with executable `/bin/zsh`, arguments `["-lc", script]`,
  environment = current env plus `JC_SITE=<path>`, `JC_ENGINE=<engine dir>`; script:
  ```
  cd "$JC_SITE" || exit 2
  if [ -f Gemfile ]; then exec bundle exec ruby -I"$JC_ENGINE/lib" "$JC_ENGINE/exe/jekyll-canvas-server" --site "$JC_SITE"
  else exec ruby -I"$JC_ENGINE/lib" "$JC_ENGINE/exe/jekyll-canvas-server" --site "$JC_SITE"; fi
  ```
  Engine dir = `Bundle.main.resourcePath + "/engine"`, overridable with env var
  `JEKYLL_CANVAS_ENGINE` (for development). Read STDOUT line by line; the line starting with
  `JEKYLL_CANVAS_READY ` carries the URL. Append STDOUT/STDERR to the loading view log (and
  keep the last 500 lines for the error view). Timeout 90 s → error view.
- **Error view**: if the process exits before ready or times out: message "Impossibile
  avviare il sito", the log, a hint "Prova `bundle install` nella cartella del sito" when
  the log mentions `Bundler` / `Could not find`, buttons "Riprova" and "Apri nel Terminale"
  (opens Terminal.app at the folder via `NSWorkspace` / `open -a Terminal <path>`).
- **Lifecycle**: closing a site window sends SIGTERM to the process (then SIGKILL after 3 s
  if still alive). Quitting the app terminates all engines. If an engine dies while the
  window is open, show the error view with "Riprova".
- **WKWebView**: `isInspectable = true` (when available); WKUIDelegate implements
  `runOpenPanelWith` (file uploads, `allowsMultipleSelection` from parameters), JavaScript
  `alert`, `confirm` and `prompt` panels as NSAlerts; navigation delegate opens any URL whose
  host is not `127.0.0.1`/`localhost` (or `target=_blank` new-window requests) in the default
  browser via `NSWorkspace.shared.open` and cancels it in the webview.
- **Menus**: App (About Jekyll Canvas, Hide, Quit ⌘Q); File (Apri cartella… ⌘O, Apri recenti ▸,
  Mostra nel Finder ⇧⌘R, Chiudi finestra ⌘W); Edit (Undo ⌘Z, Redo ⇧⌘Z, Cut, Copy, Paste,
  Select All — standard selectors with nil target so the WKWebView receives them; this is
  required for text editing to work); View (Ricarica ⌘R → webView.reload, Strumenti
  sviluppatore ⌥⌘I if possible); Window (Minimize, Zoom).
- No sandbox, no notarisation.

## Done when

`make app` (or `desktop/build.sh` alone when the UI is already built) produces
`dist/Jekyll Canvas.app` that launches, shows the welcome window, and with a stub engine
(set `JEKYLL_CANVAS_ENGINE` to a dir containing `exe/jekyll-canvas-server` that prints a
ready line pointing to a simple local HTTP server) loads the URL in the webview. Verify
compile + launch from the command line (`open "dist/Jekyll Canvas.app"`, check the
process is running, then quit it with `osascript -e 'quit app "Jekyll Canvas"'`).
