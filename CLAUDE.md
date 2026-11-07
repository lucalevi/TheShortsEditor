# CLAUDE.md

## What this is

TheShortsEditor ("Shorts Editor") is a native macOS 26+ video editor for **YouTube Shorts only**: a CapCut-like app with the ~20% of features that make ~80% of a good Short. Being very friendly and intuitive is the top requirement. Research and the decisions made so far are in `research/shorts-editor-research.md`.

## Building

Requires Xcode 26+ and XcodeGen (`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml` and gitignored. Edit `project.yml`, never the project itself.

```
make test     # EditorCore + RenderEngine tests (swift test)
make run      # generate project, build Debug into ./build, launch
make open     # open in Xcode
```

## Architecture

- `Packages/EditorCore`, a Swift package with two libraries:
  - `EditorCore`: the pure value-type model (`Project`, `MediaAsset`, `Timeline`, `Clip`, `Framing`, `SafeZone`). No AVFoundation. All edit logic lives here and is unit tested.
  - `RenderEngine`: `MediaProbe` (reads files) and `CompositionBuilder` (Project → AVComposition + AVVideoComposition). Main-actor by default.
- `App/`: the SwiftUI app. `EditorModel` owns the project, the player and undo. Views are in `App/Views`.

## Conventions that matter

- **The project value is the source of truth.** Every edit goes through `EditorModel.apply(_:_:)`, which snapshots the old value for undo and rebuilds the player item from scratch. Never mutate AVFoundation objects to make an edit.
- **Time is `CMTime`, never `Double` seconds**, in the model. Edits snap to whole frames (`snappedToFrame`). `CMTime` isn't Codable here, so model types encode it through `StoredTime`.
- The canvas is fixed at 1080×1920, 30 fps, with a 3:00 maximum. These are constants on `Project`, not settings.
- Use the macOS 26 `AVVideoComposition.Configuration` APIs. The `AVMutableVideoComposition*` classes are deprecated.
- Every keyboard shortcut is defined in `EditorCommands` so it also appears in a menu. Single keys without modifiers (Space, J/K/L, B, arrows, Delete) are also handled in `EditorKeys`, because a focused control otherwise takes them before the menu does.
- Files opened from Finder or the Dock are imported by `AppDelegate.application(_:open:)`. The `WindowGroup`'s `handlesExternalEvents` settings exist only so exactly one window gets created and reused. `onOpenURL` drops files when several are opened at once, and a plain `Window` scene isn't created when the app is launched by opening files.
- User-facing text is plain language without editing jargon ("Fill screen" / "Show all", not "aspect fill").
- The app is sandboxed. File access comes from drag-and-drop or the Open panel (security-scoped URLs).
