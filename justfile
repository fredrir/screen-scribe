set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
	@just --list

xcode:
	open ScreenScribe.xcodeproj

typecheck:
	swift build

build:
	xcodebuild -project ScreenScribe.xcodeproj -scheme ScreenScribe -configuration Debug -destination 'platform=macOS' -derivedDataPath build/xcode build 2>&1 | xcbeautify

release:
	xcodebuild -project ScreenScribe.xcodeproj -scheme ScreenScribe -configuration Release -destination 'platform=macOS' -derivedDataPath build/xcode build 2>&1 | xcbeautify

app_path := "build/xcode/Build/Products/Debug/ScreenScribe.app"

run: build
	open "{{app_path}}"

restart:
	just build
	-@pkill -x ScreenScribe
	open "{{app_path}}"

watch:
	watchexec -e swift -w ScreenScribe -- just relaunch

test:
	./scripts/run-standalone-tests.sh

verify-signing path=app_path:
	./scripts/verify-release-signing.sh "{{path}}"

clean:
	rm -rf build .build

appicon:
	xcrun swift scripts/render-app-icon.swift
