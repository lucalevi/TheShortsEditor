# Project status

_Last updated: 2026-11-07. Read this first when picking the project back up, then update it at the end of each session._

## Where we are

**Stage 1 (foundation) is done**, tested on screen, and pushed to https://github.com/lucalevi/TheShortsEditor (public).

What works today:
- Import videos by drag-and-drop (Media list, viewer, timeline), with **Import…** / **Choose Videos…**, or from Finder (Open With / Dock icon). Files go onto the timeline in order, and the same file is never imported twice.
- 9:16 viewer (1080×1920, 30 fps) with a toggle for the dimmed areas YouTube's interface covers (`SafeZone`).
- Magnetic timeline: click a clip to select it and move the playhead there, drag the ruler to scrub, split (**B**), delete with the gap closing (**⌫**), move earlier/later (right-click), zoom.
- Per-clip framing: **Fill screen** / **Show all**. Vertical footage defaults to fill, horizontal to show all.
- Playback: Space, J/K/L, ←/→ frame step, Home/End. Undo/redo for every edit (⌘Z).
- Length against the 3:00 Shorts limit (inspector + red marker on the timeline).
- 22 automated tests (`make test`): timeline logic, framing math, and real rendering checked pixel by pixel.

Verified on screen: import, Finder open (launch and while running), select, framing switch, split, delete, undo, Space play/pause, ruler scrub, closing the window quits.
**Not yet verified on screen:** J/K/L reverse and fast playback, the clip right-click menu, timeline zoom, drag-and-drop from Finder.

## Decisions already made (don't re-ask)

- macOS 26+, Apple Silicon. SwiftUI app with AppKit where needed. XcodeGen project.
- Personal tool first; a shareable **.dmg** later. Opening it without warnings on other Macs needs a paid Apple Developer ID (99 USD/yr), which is still to be decided when sharing starts.
- Caption languages: **English, Italian, German, French**. All four are available in Apple's on-device `SpeechTranscriber` (checked on this Mac).
- Support all kinds of footage, with **very friendly, intuitive UX** as the top requirement.
- Repo is public on GitHub.

## What's next, in order

The P0 list from `research/shorts-editor-research.md` §5. Each stage ends with tests and an on-screen check.

1. **Auto-captions** ← next
   - On-device transcription (`SpeechAnalyzer` / `SpeechTranscriber`) with word timings, language picker (en/it/de/fr).
   - Captions as a new timeline lane, rendered in preview and export through the same path (needs a custom compositor or Core Animation tool on top of `CompositionBuilder`).
   - 3–5 style presets, including word-by-word highlight. Position kept inside the safe zone.
   - Transcript panel to fix words.
2. **Export**: one YouTube-Shorts preset (H.264/HEVC MP4 1080×1920, AAC 48 kHz, Fast Start) with progress. Verify the output with `ffprobe`. Pre-export checks: over 3:00, music on a Short over 1:00 (Content ID block risk), text outside the safe zone, silent first second.
3. **Remove silences**: threshold + padding slider with a preview, applied as normal undoable cuts.
4. **Text overlay** for the hook title (a few styles, fade/pop-in).
5. **Audio**: clip volume, fades, a background-music lane with automatic ducking under speech, loudness normalisation on export.
6. **Save/open projects**: a project file with autosave, security-scoped bookmarks to media, and relinking of missing media. Today the project lives only in memory, so **quitting loses the edit**.
7. Then P1 from the research: editing by deleting words in the transcript, keyframes/punch-in zoom, auto-reframe of horizontal footage (Vision), speed, loop preview, brand kit.

## Open questions for the user

- Should the editor link exported Shorts to `channel_lab` plans (`~/Documents/Programming/YouTube`)? Recommended: not now; maybe later.
- Captions or export first? Captions was the suggestion. The user hadn't chosen when the session ended.

## Known limitations / tech debt

- No project saving yet (see step 6).
- Only video files can be imported (no audio-only files or images yet).
- `SafeZone` margins are approximate (no official YouTube overlay found).
- Moving clips by dragging on the timeline isn't implemented (right-click Move Earlier/Later only).
- The timeline shows one thumbnail per clip, not a filmstrip.

## How to test on screen

The terminal needs **Screen Recording** and **Accessibility** permission (both granted on this Mac).

```
make build
Tools/uitest/make-samples.sh                       # test clips into Tools/uitest/.samples
open -a "$PWD/build/Build/Products/Debug/Shorts Editor.app" Tools/uitest/.samples/*.mp4
Tools/uitest/ui.sh shot start                      # screenshot → Tools/uitest/.shots/start.png
Tools/uitest/ui.sh click 470 621                   # real click, window-relative points
Tools/uitest/ui.sh key b ; Tools/uitest/ui.sh code 49   # B, then Space
```

Notes: System Events' `click at` doesn't trigger SwiftUI taps, which is why `ui.sh` posts real mouse events. Screenshots are 2× on the Retina display and 1× on the external one. Give the window a second or two after `activate` when it's on another Space.
