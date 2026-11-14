APP := build/Build/Products/Debug/Shorts Editor.app
SOURCES := App Packages/EditorCore/Package.swift Packages/EditorCore/Sources Packages/EditorCore/Tests Tools
XCODEBUILD := xcodebuild -project TheShortsEditor.xcodeproj -scheme TheShortsEditor -quiet
# Warnings fail the build in `check` (and so in CI and the pre-push hook).
STRICT := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES

LIBRARY := $(HOME)/Library/Containers/com.lucalevi.TheShortsEditor/Data/Library/Application Support/Shorts Editor/Shorts

.PHONY: project open build release run test check check-library format format-check lint lint-baseline tsan asan analyze hooks clean help

help:               ## List the targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | expand -t 20

project:            ## Generate TheShortsEditor.xcodeproj from project.yml
	xcodegen generate --quiet

open: project       ## Open the project in Xcode
	open TheShortsEditor.xcodeproj

build: project      ## Build the Debug app into ./build
	$(XCODEBUILD) -configuration Debug -derivedDataPath build build

release: project    ## Build the Release app into ./build/release, warnings as errors
	$(XCODEBUILD) -configuration Release -derivedDataPath build/release $(STRICT) build

run: build          ## Build and launch the app
	open "$(APP)"

test:               ## Run the EditorCore, RenderEngine and Transcription tests
	cd Packages/EditorCore && swift test

# Everything CI and the pre-push hook run. Fails on a formatting difference, a new lint violation,
# a failing test or a compiler warning.
check: format-check lint ## Format, lint, tests and both builds, all strict
	cd Packages/EditorCore && swift test -Xswiftc -warnings-as-errors
	$(MAKE) project
	$(XCODEBUILD) -configuration Debug -derivedDataPath build $(STRICT) build
	$(XCODEBUILD) -configuration Release -derivedDataPath build/release $(STRICT) build

check-library:      ## Read every Short in this Mac's library with today's code (read-only); before changing how files are read
	cd Packages/EditorCore && SHORTS_LIBRARY="$(LIBRARY)" swift test --filter LibraryCompatibilityTests

format:             ## Format every Swift file in place (.swift-format)
	swift format --in-place --parallel --recursive $(SOURCES)

format-check:       ## Fail if any Swift file isn't formatted
	swift format lint --strict --parallel --recursive $(SOURCES)

lint:               ## SwiftLint; only violations not in .swiftlint-baseline.json fail
	swiftlint lint --quiet --strict --baseline .swiftlint-baseline.json

lint-baseline:      ## Rewrite the baseline (only after fixing violations, to drop them)
	swiftlint lint --quiet --write-baseline .swiftlint-baseline.json || true

# The sanitizers slow code 5–10×: whole exports and the music maker then pass their time limits
# (60–120 s), so those few run only in `test`/`check`. First TSan run, 2026-11-14: no data races.
SLOW_TESTS := --skip ExporterTests --skip voiceCleanUpKeepsTheTiming --skip musicFileCoversTheLongestShort

tsan:               ## Tests under the Thread Sanitizer
	cd Packages/EditorCore && swift test --sanitize=thread --scratch-path .build-tsan $(SLOW_TESTS)

asan:               ## Tests under the Address Sanitizer
	cd Packages/EditorCore && swift test --sanitize=address --scratch-path .build-asan $(SLOW_TESTS)

analyze: project    ## Xcode's static analyzer on the app
	$(XCODEBUILD) -configuration Debug -derivedDataPath build analyze

hooks:              ## Use the repository's git hooks (pre-push runs `make check`)
	git config core.hooksPath Tools/hooks

clean:
	rm -rf build Packages/EditorCore/.build Packages/EditorCore/.build-tsan Packages/EditorCore/.build-asan
