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
  - `EditorCore`: the pure value-type model (`Project`, `MediaAsset` (videos, pictures, sound), `Timeline`, `Clip`, `Framing`, `Placement`/keyframes/motion presets in `Placement.swift`, trimming/B-roll overlays/snapping/row packing in `Editing.swift`, `SafeZone`, captions in `Captions.swift`, titles in `Titles.swift`, music, ducking and the loudness meter in `Audio.swift`, the file format in `ProjectFile.swift`). No AVFoundation. All edit logic lives here and is unit tested.
  - `RenderEngine`: `MediaProbe` (reads files), `CompositionBuilder` (Project → AVComposition + AVVideoComposition) and `ShortsCompositor`, the custom video compositor that draws every frame (layers: the main clip placed on the canvas with Core Image over a blurred copy of itself or black, then B-roll overlays, then titles drawn by `TitleRenderer` and captions by `CaptionRenderer`, both with Core Text; pictures come from `StillImages`). Preview, thumbnails and export all go through it, so new visual features (text, zoom, reframe) belong there. Sound goes through the `AVAudioMix` the builder makes (clip volumes, the music's volume curve, an overall gain). `Exporter` writes the MP4 (AVAssetReader → AVAssetWriter, YouTube's recommended settings), first measuring loudness to bring it to −14 LUFS. `AudioProbe` measures sound (per-frame levels of a file feed `SilencePlan` and ducking, cached in `LevelCache`; the mixed Short's peak and loudness). Main-actor by default; the compositor and renderer are `nonisolated` because AVFoundation calls them on its own queues.
  - Also in `EditorCore`: `TextLook.swift` (title looks, saved styles), `Script.swift` (edit by text, filler words, key words, emoji), `Layouts.swift` (split-screen regions, picture-in-picture corners, `Reframe` keyframes); `SoundClip`/`Project.sounds` in `Editing.swift`. In `RenderEngine`: `SoundLibrary.swift` (synthesized effects), `VoiceCleaner.swift` (AUSoundIsolation, offline), `Reframer.swift` (Vision).
  - `Transcription`: `Transcriber`, on-device speech to text with Apple's `SpeechAnalyzer`/`SpeechTranscriber`, giving timed words.
- `App/`: the SwiftUI app. `EditorModel` owns the project, the player, undo and saving (autosave a second after each change). `ProjectStore` reads/writes `.shortsproject` files with security-scoped bookmarks for media and keeps the library of Shorts (`Application Support/Shorts Editor/Shorts/<id>.shortsproject` + `<id>.jpg` poster). The window shows either `HomeView` (every Short, like iMovie's Projects) or `EditorView`, by `EditorModel.screen`. Views are in `App/Views`.

How an edit flows: view or menu → `EditorModel.apply(name) { project in … }` (calls into `EditorCore` mutations) → old value registered with the window's `UndoManager` → `projectDidChange()` cancels any in-flight rebuild, runs `CompositionBuilder.build`, and swaps a new `AVPlayerItem` into the player at the same playhead time. A new feature (captions, text, audio) is usually: model types and pure logic in `EditorCore` with tests, rendering in `CompositionBuilder`, UI plus an `EditorModel` method in the app.

Concurrency: Swift 6 strict mode. `RenderEngine`, its tests and the app default to `MainActor` isolation with `NonisolatedNonsendingByDefault` (set in `Package.swift` and `project.yml`), because AVFoundation types aren't Sendable. `EditorCore` stays nonisolated and Sendable. Render tests use `@preconcurrency import AVFoundation`.

## Conventions that matter

- **The project value is the source of truth.** Every edit goes through `EditorModel.apply(_:_:)`, which snapshots the old value for undo and rebuilds the player item from scratch. Never mutate AVFoundation objects to make an edit.
- **Placement and keyframes sit on top of framing.** A clip's picture is framed (Fill/Show all), then moved/scaled/turned by its `Placement`. Keyframe times are in the source file's time, so motion survives split/trim/Remove Pauses. While a picture is dragged in the viewer, `LivePreview` shows it without rebuilding; the rebuild after the edit clears it.
- **B-roll (`Project.overlays`), titles and sounds are timed on the timeline, but follow their clip**: `EditorModel.apply` calls `Project.followClips(from:)` after every edit, which keeps each item (with `followsClip`) on the same moment of the main clip under its start. Edits never need to move items themselves. Each row of overlapping overlays gets its own composition track.
- iMovie's grammar (ranges, insert/replace, drop actions, copy/paste/reset settings, edit points) is in `EditorCore/Grammar.swift`; skimming, loop, full-screen preview and tips in `App/EditorModel+Grammar.swift`. Punctuation shortcuts are matched by character in `EditorKeys` (keyboard layouts differ).
- **Speed:** `Clip.duration` is the timeline length; map source ↔ timeline only through `sourceTime(atOffset:)`, `timelineOffset(ofSourceTime:)` and `timelineDuration(ofSource:)`.
- **Title style vs look:** set a title's style with `applyStyle(_:)` (it rewrites `look`); assigning `style` alone leaves the look unchanged.
- Use `CMTime.clamped(_:_:)`, not `CMTimeClampToRange`: the latter returns an invalid time for an empty range.
- **Captions are stored per source file** (`Project.transcripts[assetID]`, words in the file's own time), never per timeline position. `CaptionLayout.pages` maps them onto the timeline, so captions follow split/delete/move with no extra code.
- **Undo goes to the window's own undo manager**, looked up at each edit (`EditorModel.window`). Don't use SwiftUI's `@Environment(\.undoManager)`: opening files from Finder briefly creates a second window, and the environment value ended up pointing at an undo manager Edit ▸ Undo never uses.
- **Time is `CMTime`, never `Double` seconds**, in the model. Edits snap to whole frames (`snappedToFrame`). `CMTime` isn't Codable here, so model types encode it through `StoredTime`.
- The canvas is fixed at 1080×1920, 30 fps, with a 3:00 maximum. These are constants on `Project`, not settings.
- Use the macOS 26 `AVVideoComposition.Configuration` APIs. The `AVMutableVideoComposition*` classes are deprecated.
- Every keyboard shortcut is defined in `EditorCommands` so it also appears in a menu. Single keys without modifiers (Space, J/K/L, B, arrows, Delete) are also handled in `EditorKeys`, because a focused control otherwise takes them before the menu does.
- Files opened from Finder or the Dock are imported by `AppDelegate.application(_:open:)`. The `WindowGroup`'s `handlesExternalEvents` settings exist only so exactly one window gets created and reused. `onOpenURL` drops files when several are opened at once, and a plain `Window` scene isn't created when the app is launched by opening files.
- User-facing text is plain language without editing jargon ("Fill screen" / "Show all", not "aspect fill").
- The app is sandboxed. File access comes from drag-and-drop or the Open panel (security-scoped URLs), and across launches from the bookmarks saved in the project file. Missing media must never break playback: `CompositionBuilder` puts black/silence in its place and reports `missingAssets`.
