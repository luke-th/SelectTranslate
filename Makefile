APP = build/SelectTranslate.app

.PHONY: build app run install icon dmg clean

build:
	swift build

app:
	./scripts/build-app.sh

run: app
	open $(APP)

install: app
	rm -rf /Applications/SelectTranslate.app
	cp -R $(APP) /Applications/
	@echo "Installed to /Applications/SelectTranslate.app"

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

dmg:
	./scripts/make-dmg.sh

clean:
	rm -rf .build build
