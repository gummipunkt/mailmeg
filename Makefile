.PHONY: project xcode open test build dmg release screenshots

VERSION := $(shell sed -n 's/^MARKETING_VERSION *= *//p' Config/Mailmeg.xcconfig)

project:
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	xcodegen generate

# Building in the terminal needs Xcode to be the selected developer directory; the command
# line tools alone cannot build the app. (Xcode's own window builds without that.)
xcode:
	@xcodebuild -version >/dev/null 2>&1 || { \
		echo "xcodebuild does not work in the terminal. It says:"; \
		xcodebuild -version 2>&1 | sed 's/^/    /'; \
		echo "Selected developer directory: $$(xcode-select -p 2>&1)"; \
		echo "Installed: $$(ls -d /Applications/Xcode*.app 2>/dev/null | tr '\n' ' ')"; \
		echo "Select Xcode with its real name, e.g.: sudo xcode-select -s /Applications/Xcode.app"; \
		echo "If it asks for the licence: sudo xcodebuild -license accept"; exit 1; }

open: project
	@ls -d /Applications/Xcode*.app >/dev/null 2>&1 || echo "No Xcode found in /Applications: the project will only open in the Finder."
	open Mailmeg.xcodeproj

test:
	swift test --package-path MailmegKit

build: project xcode
	xcodebuild -project Mailmeg.xcodeproj -scheme Mailmeg -configuration Release -derivedDataPath build build
	@echo "App: build/Build/Products/Release/MailMeG.app"

# The same disk image the CI attaches to a release: a universal app (Apple silicon and Intel),
# ad-hoc signed, next to a link to /Applications.
dmg: project xcode
	xcodebuild -project Mailmeg.xcodeproj -scheme Mailmeg -configuration Release \
		-destination 'generic/platform=macOS' -derivedDataPath build ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build
	rm -rf build/dmg build/MailMeG.dmg
	mkdir -p build/dmg
	cp -R build/Build/Products/Release/MailMeG.app build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "MailMeG" -srcfolder build/dmg -ov -format UDZO build/MailMeG.dmg
	@echo "Disk image: build/MailMeG.dmg"

# Publishes build/MailMeG.dmg as GitHub release v<MARKETING_VERSION> with the notes from
# CHANGELOG.md – what the CI does on a push to main. The commit has to be on origin/main.
release: dmg
	@command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh && gh auth login"; exit 1; }
	@git fetch -q origin main
	@test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || { \
		echo "This checkout is not what is on origin/main. Bring the release onto main and push first."; exit 1; }
	python3 Design/release_notes.py $(VERSION) > build/notes.md
	cp build/MailMeG.dmg build/MailMeG-$(VERSION).dmg
	gh release create v$(VERSION) build/MailMeG.dmg build/MailMeG-$(VERSION).dmg \
		--target "$$(git rev-parse HEAD)" --title "MailMeG $(VERSION)" --notes-file build/notes.md --latest

# Website screenshots of the demo mailbox (DE/EN, light/dark) in Retina resolution.
# Takes over mouse and keyboard for about two minutes.
screenshots: project xcode
	rm -rf build/Screenshots.xcresult build/ScreenshotExport
	xcodebuild test -project Mailmeg.xcodeproj -scheme Mailmeg -destination 'platform=macOS' -derivedDataPath build \
		-resultBundlePath build/Screenshots.xcresult -only-testing:MailmegUITests/LandingPageScreenshots CODE_SIGN_IDENTITY=-
	xcrun xcresulttool export attachments --path build/Screenshots.xcresult --output-path build/ScreenshotExport
	python3 Design/collect_screenshots.py build/ScreenshotExport Design/Screenshots
