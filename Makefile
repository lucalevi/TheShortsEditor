APP := build/Build/Products/Debug/Shorts Editor.app
SOURCES := App AppTests AppUITests Packages/EditorCore/Package.swift Packages/EditorCore/Sources Packages/EditorCore/Tests Tools
XCODEBUILD := xcodebuild -project TheShortsEditor.xcodeproj -scheme TheShortsEditor -quiet
# Warnings fail the build in `check` (and so in CI and the pre-push hook).
STRICT := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES

LIBRARY := $(HOME)/Library/Containers/com.lucalevi.TheShortsEditor/Data/Library/Application Support/Shorts Editor/Shorts

.PHONY: project open build release run test app-test uitest coverage-raise bench nightly check check-library publish docs format format-check lint lint-baseline tsan asan analyze hooks clean help

help:               ## List the targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | expand -t 20

project:            ## Generate TheShortsEditor.xcodeproj from project.yml
	xcodegen generate --quiet

open: project       ## Open the project in Xcode
	open TheShortsEditor.xcodeproj

build: project      ## Build the Debug app into ./build
	$(XCODEBUILD) -configuration Debug -derivedDataPath build build

# Sharing (F32, ADR 0011): ad hoc signed, no Developer ID. Version: MARKETING_VERSION in project.yml;
# release notes: docs/releases/<version>.md.
release:            ## The shareable .dmg (and its SHA-256) of the Release app into build/dist
	Tools/release/release.sh

publish:            ## `release`, then tag v<version> and make the GitHub Release with the .dmg (main pushed, tree clean)
	Tools/release/release.sh --publish

run: build          ## Build and launch the app
	open "$(APP)"

test:               ## Run the EditorCore, RenderEngine and Transcription tests
	cd Packages/EditorCore && swift test

# The app's tests run inside the app, with a library and settings of their own (AppEnvironment).
APP_RESULTS := build/AppTests.xcresult
DESTINATION := -destination 'platform=macOS,arch=arm64'

app-test: project   ## Run the app tests (AppTests), with coverage
	rm -rf "$(APP_RESULTS)"
	$(XCODEBUILD) -configuration Debug -derivedDataPath build $(DESTINATION) -resultBundlePath "$(APP_RESULTS)" $(STRICT) test

# Drives the real app (AppUITests). macOS asks for Automation Mode; to run without the prompt:
# `sudo automationmodetool enable-automationmode-without-authentication` (once per Mac).
uitest: project     ## Run the UI tests: add, edit, undo, export, missing media, forced quit, accessibility
	xcodebuild -project TheShortsEditor.xcodeproj -scheme AppUITests -quiet -derivedDataPath build $(DESTINATION) test

coverage-raise:     ## After `make check`: save today's coverage as the new floor (it only goes up)
	Tools/coverage/check.py package --raise
	Tools/coverage/check.py app "$(APP_RESULTS)" --raise

# Speed (F19): every measurement is added to Tools/bench/history.csv with the commit and Mac model.
bench:              ## Performance tests and budgets; numbers added to Tools/bench/history.csv and compared
	cd Packages/EditorCore && SHORTS_BENCH=1 SHORTS_BUDGETS_ALONE=1 SHORTS_BENCH_LOG="$(CURDIR)/Tools/bench/history.csv" \
		SHORTS_BENCH_COMMIT="$$(git rev-parse --short HEAD)$$(git diff --quiet || echo +)" SHORTS_BENCH_MACHINE="$$(sysctl -n hw.model | tr , -)" \
		swift test --filter 'PerformanceTests|BudgetTests'
	@Tools/bench/compare.py Tools/bench/history.csv

nightly:            ## The scheduled run: benchmarks, then the tests under both sanitizers
	$(MAKE) bench
	$(MAKE) tsan
	$(MAKE) asan

# Everything CI and the pre-push hook run. Fails on a formatting difference, a new lint violation,
# a failing test, coverage below its floor or a compiler warning.
check: format-check lint ## Format, lint, all tests with coverage floors, both builds, all strict
	cd Packages/EditorCore && swift test -Xswiftc -warnings-as-errors --enable-code-coverage
	Tools/coverage/check.py package
	@# Timing budgets that need the process to themselves (same flags: nothing is rebuilt).
	cd Packages/EditorCore && SHORTS_BUDGETS_ALONE=1 swift test -Xswiftc -warnings-as-errors --enable-code-coverage --filter RenderBudgetTests
	$(MAKE) app-test
	Tools/coverage/check.py app "$(APP_RESULTS)"
	$(XCODEBUILD) -configuration Release -derivedDataPath build/release $(STRICT) build

check-library:      ## Read every Short in this Mac's library with today's code (read-only); before changing how files are read
	cd Packages/EditorCore && SHORTS_LIBRARY="$(LIBRARY)" swift test --filter LibraryCompatibilityTests

docs:               ## API documentation (DocC) of EditorCore, RenderEngine and Transcription into build/docs
	rm -rf build/docs && mkdir -p build/docs
	cd Packages/EditorCore && for lib in EditorCore RenderEngine Transcription; do \
		xcodebuild docbuild -scheme $$lib -destination 'generic/platform=macOS' -derivedDataPath ../../build/docs-dd -quiet || exit 1; \
		cp -R ../../build/docs-dd/Build/Products/Debug/$$lib.doccarchive ../../build/docs/; \
	done
	@echo "Open with: open build/docs/EditorCore.doccarchive (Xcode's documentation window)"

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
	cd Packages/EditorCore && SHORTS_NO_BUDGETS=1 swift test --sanitize=thread --scratch-path .build-tsan $(SLOW_TESTS)

asan:               ## Tests under the Address Sanitizer
	cd Packages/EditorCore && SHORTS_NO_BUDGETS=1 swift test --sanitize=address --scratch-path .build-asan $(SLOW_TESTS)

analyze: project    ## Xcode's static analyzer on the app
	$(XCODEBUILD) -configuration Debug -derivedDataPath build analyze

hooks:              ## Use the repository's git hooks (pre-push runs `make check`)
	git config core.hooksPath Tools/hooks

clean:
	rm -rf build Packages/EditorCore/.build Packages/EditorCore/.build-tsan Packages/EditorCore/.build-asan
