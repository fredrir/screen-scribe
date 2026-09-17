set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
	@just --list

project := "ScreenScribe.xcodeproj"
scheme := "ScreenScribe"
dest := "platform=macOS"
derived_data := "build/xcode"
app_path := "build/xcode/Build/Products/Debug/ScreenScribe.app"

# Build once, launch, and inject Swift changes in-process (no relaunch).
dev:
	@./scripts/dev.sh

# Full rebuild + relaunch
restart:
	@./scripts/relaunch.sh

# Open the project in Xcode.
xcode:
	@open {{project}}

# Type-check with SPM (fast and quiet).
typecheck:
	@swift build

# Pretty, de-verbosed debug build.
build:
	@./scripts/build.sh Debug

# Pretty, de-verbosed release build.
release:
	@./scripts/build.sh Release

# Build then launch the app.
run: build
	@open "{{app_path}}"

# Standalone test suite.
test:
	@./scripts/run-standalone-tests.sh

verify-signing path=app_path:
	@./scripts/verify-release-signing.sh "{{path}}"

clean:
	@rm -rf build .build

appicon:
	@xcrun swift scripts/render-app-icon.swift

# Raw xcodebuild output, used by the VSCode problem matcher.
[private]
build-raw config="Debug":
	@xcodebuild -project {{project}} -scheme {{scheme}} -configuration {{config}} -destination '{{dest}}' -derivedDataPath {{derived_data}} build
