.PHONY: project open test build screenshots

project:
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	xcodegen generate

open: project
	open Mailmeg.xcodeproj

test:
	swift test --package-path MailmegKit

build: project
	xcodebuild -project Mailmeg.xcodeproj -scheme Mailmeg -configuration Release -derivedDataPath build build
	@echo "App: build/Build/Products/Release/MailMeG.app"

# Website screenshots of the demo mailbox (DE/EN, light/dark) in Retina resolution.
# Takes over mouse and keyboard for about two minutes.
screenshots: project
	rm -rf build/Screenshots.xcresult build/ScreenshotExport
	xcodebuild test -project Mailmeg.xcodeproj -scheme Mailmeg -destination 'platform=macOS' -derivedDataPath build \
		-resultBundlePath build/Screenshots.xcresult -only-testing:MailmegUITests/LandingPageScreenshots CODE_SIGN_IDENTITY=-
	xcrun xcresulttool export attachments --path build/Screenshots.xcresult --output-path build/ScreenshotExport
	python3 Design/collect_screenshots.py build/ScreenshotExport Design/Screenshots
