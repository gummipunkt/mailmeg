.PHONY: project open test build

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
