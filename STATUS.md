# Project status

_Last updated: 2026-11-08. Read this first when picking the project back up, then update it at the end of each session._

## Where we are

**Stage 1 (foundation) is done** and pushed to https://github.com/lucalevi/TheShortsEditor (public).
**Stage 2 (auto-captions) is done**, tested on screen and pushed.

What works today:
- Import videos by drag-and-drop (Media list, viewer, timeline), with **Import…** / **Choose Videos…**, or from Finder (Open With / Dock icon). Files go onto the timeline in order, and the same file is never imported twice.
- 9:16 viewer (1080×1920, 30 fps) with a toggle for the dimmed areas YouTube's interface covers (`SafeZone`).
- Magnetic timeline: click a clip to select it and move the playhead there, drag the ruler to scrub, split (**B**), delete with the gap closing (**⌫**), move earlier/later (right-click), zoom.
- Per-clip framing: **Fill screen** / **Show all**. Vertical footage defaults to fill, horizontal to show all.
- Playback: Space, J/K/L, ←/→ frame step, Home/End. Undo/redo for every edit (⌘Z).
- Length against the 3:00 Shorts limit (inspector + red marker on the timeline).
- **Auto-captions** (Captions tab in the left panel, toolbar button, Captions menu):
  - On-device transcription with word timings (`SpeechAnalyzer`), English/Italian/German/French. Downloads the language model the first time, with progress and Cancel.
  - Transcripts are stored per source file, so captions follow split/delete/move automatically. "Update Captions" appears when clips have no captions in the chosen language yet.
  - 5 styles: Bold (current word yellow), Highlight (box behind the current word), One Word, Subtitles (dark box), Simple (shadow). The punchy styles pop in and stay on one line (shrinking a little if needed). Position: Top / Middle / Bottom, always clear of YouTube's overlay areas.
  - Editable list of caption lines (click the words, Return to save). A captions lane under the clips on the timeline; click a caption to jump there.
  - Drawn by a custom video compositor (`ShortsCompositor`), the same path for preview and (future) export.
- 45 automated tests (`make test`): timeline and caption logic, framing math, rendering checked pixel by pixel (including orientation and every caption style), and a real transcription of speech made with `say`.

Verified on screen: import, Finder open (launch and while running), select, framing switch, split, delete, undo (fixed 2026-11-08, see below), Space play/pause, ruler scrub, closing the window quits. Captions: make, style and position switches, editing a line, jumping from the timeline lane, split/delete with captions following, undo of all of these.
**Not yet verified on screen:** J/K/L reverse and fast playback, the clip right-click menu, timeline zoom, drag-and-drop from Finder.

## Decisions already made (don't re-ask)

- macOS 26+, Apple Silicon. SwiftUI app with AppKit where needed. XcodeGen project.
- Personal tool first; a shareable **.dmg** later. Opening it without warnings on other Macs needs a paid Apple Developer ID (99 USD/yr), which is still to be decided when sharing starts.
- Caption languages: **English, Italian, German, French**. All four are available in Apple's on-device `SpeechTranscriber` (checked on this Mac).
- Support all kinds of footage, with **very friendly, intuitive UX** as the top requirement.
- Repo is public on GitHub.

## What's next, in order

The P0 list from `research/shorts-editor-research.md` §5. Each stage ends with tests and an on-screen check.

1. ~~Auto-captions~~ (done)
2. **Export** ← next. `PlayableComposition` already holds everything an `AVAssetExportSession`/`AVAssetWriter` needs; the custom compositor draws captions in export too.: one YouTube-Shorts preset (H.264/HEVC MP4 1080×1920, AAC 48 kHz, Fast Start) with progress. Verify the output with `ffprobe`. Pre-export checks: over 3:00, music on a Short over 1:00 (Content ID block risk), text outside the safe zone, silent first second.
3. **Remove silences**: threshold + padding slider with a preview, applied as normal undoable cuts.
4. **Text overlay** for the hook title (a few styles, fade/pop-in).
5. **Audio**: clip volume, fades, a background-music lane with automatic ducking under speech, loudness normalisation on export.
6. **Save/open projects**: a project file with autosave, security-scoped bookmarks to media, and relinking of missing media. Today the project lives only in memory, so **quitting loses the edit**.
7. Then P1 from the research: editing by deleting words in the transcript, keyframes/punch-in zoom, auto-reframe of horizontal footage (Vision), speed, loop preview, brand kit.

## Open questions for the user

- Should the editor link exported Shorts to `channel_lab` plans (`~/Documents/Programming/YouTube`)? Recommended: not now; maybe later.

## Known limitations / tech debt

- Undo was silently broken before 2026-11-08: opening files from Finder briefly creates a second window, and the model had attached to its undo manager. Now the model asks its window (re-set each time the window becomes active) for the undo manager at every edit.
- Captions: a whole source file is transcribed even if only part of it is used (fine for Short-length clips, slow for long ones). Lines are grouped by length/pauses/sentence ends; there's no manual "split this caption here" yet. No caption dragging in the viewer (Top/Middle/Bottom only). The test sample is a synthetic voice, so accuracy on real, noisy recordings is untested.
- The Highlight style's green box can blend into green backgrounds.
- No project saving yet (see step 6).
- Only video files can be imported (no audio-only files or images yet).
- `SafeZone` margins are approximate (no official YouTube overlay found).
- Moving clips by dragging on the timeline isn't implemented (right-click Move Earlier/Later only).
- The timeline shows one thumbnail per clip, not a filmstrip.

## How to test on screen

The terminal needs **Screen Recording** and **Accessibility** permission (both granted on this Mac).

```
make build
Tools/uitest/make-samples.sh                       # test clips into Tools/uitest/.samples (incl. talking-sample.mp4 for captions)
open -a "$PWD/build/Build/Products/Debug/Shorts Editor.app" Tools/uitest/.samples/*.mp4
Tools/uitest/ui.sh shot start                      # screenshot → Tools/uitest/.shots/start.png
Tools/uitest/ui.sh click 470 621                   # real click, window-relative points
Tools/uitest/ui.sh key b ; Tools/uitest/ui.sh code 49   # B, then Space
```

To check undo: `osascript -e 'tell application "System Events" to tell process "Shorts Editor" to get enabled of menu item 1 of menu "Edit" of menu bar 1'`. To see `NSLog` output, run the binary in `Contents/MacOS` directly (the unified log didn't show it).

Notes: System Events' `click at` doesn't trigger SwiftUI taps, which is why `ui.sh` posts real mouse events. Screenshots are 2× on the Retina display and 1× on the external one. Give the window a second or two after `activate` when it's on another Space.
