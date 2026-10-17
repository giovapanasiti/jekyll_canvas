.PHONY: app install test ui install-linux uninstall-linux

APP := dist/Jekyll Canvas.app

ui:
	@if [ -d ui/node_modules ]; then npm --prefix ui run build; else echo "ui/node_modules missing: skipping UI build"; fi

app: ui
	desktop/build.sh

install: app
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/Jekyll Canvas.app"
	cp -R "$(APP)" "$(HOME)/Applications/"

test:
	cd engine && bundle exec rake test

# Linux (Omarchy): engine + launcher + desktop entry, no npm needed (engine/public is committed).
DATA ?= $${XDG_DATA_HOME:-$$HOME/.local/share}
BIN  ?= $$HOME/.local/bin

install-linux:
	rm -rf "$(DATA)/jekyll-canvas/engine"
	mkdir -p "$(DATA)/jekyll-canvas/engine" "$(BIN)" "$(DATA)/icons/hicolor/scalable/apps" "$(DATA)/applications"
	tar -C engine --exclude=./test --exclude=./Gemfile.lock --exclude=./.bundle --exclude=./script -cf - . \
		| tar -C "$(DATA)/jekyll-canvas/engine" -xf -
	install -m 755 linux/jekyll-canvas "$(BIN)/jekyll-canvas"
	install -m 644 linux/jekyll-canvas.svg "$(DATA)/icons/hicolor/scalable/apps/jekyll-canvas.svg"
	bin="$$(cd "$(BIN)" && pwd -P)/jekyll-canvas"; \
	icon="$$(cd "$(DATA)" && pwd -P)/icons/hicolor/scalable/apps/jekyll-canvas.svg"; \
	sed -e "s|@BIN@|$$bin|g" -e "s|@ICON@|$$icon|g" linux/jekyll-canvas.desktop \
		> "$(DATA)/applications/jekyll-canvas.desktop"
	-update-desktop-database "$(DATA)/applications" 2>/dev/null
	-gtk-update-icon-cache -f -t "$(DATA)/icons/hicolor" 2>/dev/null
	@echo "Installed. Launch 'Jekyll Canvas' from walker, or run: jekyll-canvas ~/path/to/site"

uninstall-linux:
	rm -rf "$(DATA)/jekyll-canvas/engine"
	-rmdir "$(DATA)/jekyll-canvas" 2>/dev/null
	rm -f "$(BIN)/jekyll-canvas"
	rm -f "$(DATA)/icons/hicolor/scalable/apps/jekyll-canvas.svg"
	rm -f "$(DATA)/applications/jekyll-canvas.desktop"
	-update-desktop-database "$(DATA)/applications" 2>/dev/null
	-gtk-update-icon-cache -f -t "$(DATA)/icons/hicolor" 2>/dev/null
