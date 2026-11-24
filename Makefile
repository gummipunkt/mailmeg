.PHONY: project xcode open test build screenshots

project:
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	xcodegen generate

# The command line tools alone cannot build the app: without Xcode, `open` would only show
# the project folder in the Finder.
xcode:
	@xcodebuild -version >/dev/null 2>&1 || { \
		echo "Xcode is missing or not selected. Install Xcode (App Store or developer.apple.com), open it once,"; \
		echo "then run: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }

open: project xcode
	open Mailmeg.xcodeproj

test:
	swift test --package-path MailmegKit

build: project xcode
	xcodebuild -project Mailmeg.xcodeproj -scheme Mailmeg -configuration Release -derivedDataPath build build
	@echo "App: build/Build/Products/Release/MailMeG.app"

# Website screenshots of the demo mailbox (DE/EN, light/dark) in Retina resolution.
# Takes over mouse and keyboard for about two minutes.
screenshots: project xcode
	rm -rf build/Screenshots.xcresult build/ScreenshotExport
	xcodebuild test -project Mailmeg.xcodeproj -scheme Mailmeg -destination 'platform=macOS' -derivedDataPath build \
		-resultBundlePath build/Screenshots.xcresult -only-testing:MailmegUITests/LandingPageScreenshots CODE_SIGN_IDENTITY=-
	xcrun xcresulttool export attachments --path build/Screenshots.xcresult --output-path build/ScreenshotExport
	python3 Design/collect_screenshots.py build/ScreenshotExport Design/Screenshots
