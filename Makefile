.PHONY: app install test ui

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
