# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TheShortsEditor ("Shorts Editor") is a native macOS 26+ video editor for **YouTube Shorts only**: a CapCut-like app with the ~20% of features that make ~80% of a good Short. Being very friendly and intuitive is the top requirement. Research is in `research/shorts-editor-research.md`. **`STATUS.md` holds the current state: what's done, what's next, open questions, and how to test on screen.** Read it at the start of a session and update it at the end.

## Building

Requires Xcode 26+ and XcodeGen (`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml` and gitignored. Edit `project.yml`, never the project itself.

```
make test     # EditorCore + RenderEngine + Transcription tests (swift test)
make build    # xcodegen + xcodebuild Debug into ./build (no tests)
make run      # build, then launch build/Build/Products/Debug/Shorts Editor.app
make open     # open in Xcode

# single test or suite (Swift Testing), from Packages/EditorCore
swift test --filter "TimelineTests/splitSnapsToWholeFrames"
swift test --filter CompositionBuilderTests
```

There is no linter. Tests live only in the package. The app target has none; check app behaviour on screen with `Tools/uitest` (see `STATUS.md`). Render tests write their own fixture videos, optionally with a tone (`Tests/RenderEngineTests/Fixture.swift`), and check pixels, so they need no media files. Export tests check the written file (codec, size, AAC, fast start). The app is signed ad hoc ("Sign to Run Locally"); there is no Developer ID yet.

## Architecture

- `Packages/EditorCore`, a Swift package with three libraries:
  - `EditorCore`: the pure value-type model (`Project`, `MediaAsset`, `Timeline`, `Clip`, `Framing`, `SafeZone`, captions in `Captions.swift`). No AVFoundation. All edit logic lives here and is unit tested.
  - `RenderEngine`: `MediaProbe` (reads files), `CompositionBuilder` (Project → AVComposition + AVVideoComposition) and `ShortsCompositor`, the custom video compositor that draws every frame (clip placed on the canvas with Core Image, then captions drawn by `CaptionRenderer` with Core Text). Preview, thumbnails and export all go through it, so new visual features (text, zoom, reframe) belong there. `Exporter` writes the MP4 (AVAssetReader → AVAssetWriter, YouTube's recommended settings) and `AudioProbe` measures sound levels (per-frame levels of a file feed `SilencePlan` in EditorCore). Main-actor by default; the compositor and renderer are `nonisolated` because AVFoundation calls them on its own queues.
  - `Transcription`: `Transcriber`, on-device speech to text with Apple's `SpeechAnalyzer`/`SpeechTranscriber`, giving timed words.
- `App/`: the SwiftUI app. `EditorModel` owns the project, the player and undo. Views are in `App/Views`.

How an edit flows: view or menu → `EditorModel.apply(name) { project in … }` (calls into `EditorCore` mutations) → old value registered with the window's `UndoManager` → `projectDidChange()` cancels any in-flight rebuild, runs `CompositionBuilder.build`, and swaps a new `AVPlayerItem` into the player at the same playhead time. A new feature (captions, text, audio) is usually: model types and pure logic in `EditorCore` with tests, rendering in `CompositionBuilder`, UI plus an `EditorModel` method in the app.

Concurrency: Swift 6 strict mode. `RenderEngine`, its tests and the app default to `MainActor` isolation with `NonisolatedNonsendingByDefault` (set in `Package.swift` and `project.yml`), because AVFoundation types aren't Sendable. `EditorCore` stays nonisolated and Sendable. Render tests use `@preconcurrency import AVFoundation`.

## Conventions that matter

- **The project value is the source of truth.** Every edit goes through `EditorModel.apply(_:_:)`, which snapshots the old value for undo and rebuilds the player item from scratch. Never mutate AVFoundation objects to make an edit.
- **Captions are stored per source file** (`Project.transcripts[assetID]`, words in the file's own time), never per timeline position. `CaptionLayout.pages` maps them onto the timeline, so captions follow split/delete/move with no extra code.
- **Undo goes to the window's own undo manager**, looked up at each edit (`EditorModel.window`). Don't use SwiftUI's `@Environment(\.undoManager)`: opening files from Finder briefly creates a second window, and the environment value ended up pointing at an undo manager Edit ▸ Undo never uses.
- **Time is `CMTime`, never `Double` seconds**, in the model. Edits snap to whole frames (`snappedToFrame`). `CMTime` isn't Codable here, so model types encode it through `StoredTime`.
- The canvas is fixed at 1080×1920, 30 fps, with a 3:00 maximum. These are constants on `Project`, not settings.
- Use the macOS 26 `AVVideoComposition.Configuration` APIs. The `AVMutableVideoComposition*` classes are deprecated.
- Every keyboard shortcut is defined in `EditorCommands` so it also appears in a menu. Single keys without modifiers (Space, J/K/L, B, arrows, Delete) are also handled in `EditorKeys`, because a focused control otherwise takes them before the menu does.
- Files opened from Finder or the Dock are imported by `AppDelegate.application(_:open:)`. The `WindowGroup`'s `handlesExternalEvents` settings exist only so exactly one window gets created and reused. `onOpenURL` drops files when several are opened at once, and a plain `Window` scene isn't created when the app is launched by opening files.
- User-facing text is plain language without editing jargon ("Fill screen" / "Show all", not "aspect fill").
- The app is sandboxed. File access comes from drag-and-drop or the Open panel (security-scoped URLs).
