# Project status

_Last updated: 2026-11-09. Read this first when picking the project back up, then update it at the end of each session._

## Where we are

Stages 1–5 are done, tested on screen, committed and pushed to https://github.com/lucalevi/TheShortsEditor (public, branch `main`):

| Stage | What | Session |
|---|---|---|
| 1 | Foundation: import, viewer, magnetic timeline, framing, playback, undo | 2026-11-07 |
| 2 | Auto-captions | 2026-11-08 |
| 3 | Export to a YouTube-ready MP4, with pre-export checks | 2026-11-08 |
| 4 | Remove Pauses (silence removal) | 2026-11-08 |
| 5 | Titles (text overlay for the hook) | 2026-11-09 |

**Pick up here:** stage 6, **Audio** (see "What's next"): clip volume, fades, a background-music lane with ducking under speech, loudness normalisation on export, and the "music on a Short over 1:00" export check.

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
  - Drawn by a custom video compositor (`ShortsCompositor`), the same path for preview and export.
- **Export** (toolbar button, File ▸ Export Short… ⌘E): a sheet runs checks first, then a save panel, progress with Stop (removes the partial file), and "Show in Finder".
  - One preset: MP4, H.264 High 1080×1920 30 fps ~12 Mbps, key frame at least every 0.5 s, BT.709, AAC-LC 48 kHz stereo 320 kbps (Apple's AAC maximum; YouTube suggests 384), fast start. Verified with `ffprobe`.
  - Checks (warn, never block): over 3:00, silent first second (measured from the audio), no sound, no captions, captions hidden.
  - Written with `AVAssetReader` + `AVAssetWriter` from the same compositor as the preview, so captions are in the file.
- **Remove Pauses** (toolbar button, Clip ▸ Remove Pauses…): measures each file's loudness per frame, suggests what counts as quiet from the sound itself, and marks the parts to cut in red on the timeline. Two sliders ("What counts as a pause", "Room around words"), a summary ("Cuts 0:05.2 in 4 places, new length…"), "Play Without Pauses" (playback skips the cuts), then one undoable edit. Quiet at the very start/end of a clip is cut completely. Captions follow the cuts.
- **Titles** (toolbar **Title**, Text ▸ Add Title ⌘T): text over the video, e.g. the hook.
  - Added at the playhead for 3 s (starts earlier near the end), selected, with its text ready to type. Return saves.
  - 5 styles: Bold (white, black outline), Label (black on white line boxes), Marker (black on yellow), Dark Box, Simple (shadow). Appears with Pop (grows in with a little bounce), Fade (in and out), or None. Long text wraps by itself.
  - Position: Top / Middle / Bottom, or drag it up and down in the viewer (click selects, double-click edits the words). It may go anywhere on the canvas; the inspector and the export checks warn when part of it is where YouTube covers the video.
  - A titles lane above the clips: click to select, drag to move, drag the right edge to change the length; right-click for Start at Playhead / Delete. ⌫ deletes the selected title.
  - Titles belong to the timeline, not to a file: they stay at their time when clips change. Past the end of the Short they are cut or not shown (dimmed in the lane, with an export tip).
  - Drawn by `ShortsCompositor` under the captions (`TitleRenderer`), so they're in the export.
- The old Captions menu is now **Text** (Add Title + the caption items).
- 80 automated tests (`make test`, about a minute): timeline, caption, pause and export-check logic; framing math; rendering checked pixel by pixel (orientation, every caption style); export checked for codec, size, AAC and fast start; per-frame sound levels; and a real transcription of speech made with `say`.

Verified on screen: import, Finder open (launch and while running), select, framing switch, split, delete, undo (fixed 2026-11-08, see below), Space play/pause, ruler scrub, closing the window quits. Captions: make, style and position switches, editing a line, jumping from the timeline lane, split/delete with captions following, undo of all of these. Export: checks sheet, save panel, progress, finished state, output checked with ffprobe. Remove Pauses: detection on a sample with known pauses, sliders, preview playback, apply, undo. Titles: add (⌘T) with text ready to type, typing + Return, style switch, undo/redo, drag in the viewer into the covered area (warning in inspector and export sheet), Top preset, move and lengthen on the timeline, ⌫ delete.
**Not yet verified on screen:** J/K/L reverse and fast playback, the clip right-click menu, the title right-click menu, the title length stepper, timeline zoom, drag-and-drop from Finder. The Pop and Fade animations are checked by render tests, not by eye during playback.

## Decisions already made (don't re-ask)

- macOS 26+, Apple Silicon. SwiftUI app with AppKit where needed. XcodeGen project.
- Personal tool first; a shareable **.dmg** later. Opening it without warnings on other Macs needs a paid Apple Developer ID (99 USD/yr), which is still to be decided when sharing starts.
- Caption languages: **English, Italian, German, French**. All four are available in Apple's on-device `SpeechTranscriber` (checked on this Mac).
- Support all kinds of footage, with **very friendly, intuitive UX** as the top requirement.
- Repo is public on GitHub.

## What's next, in order

The P0 list from `research/shorts-editor-research.md` §5. Each stage ends with tests and an on-screen check.

1. ~~Auto-captions~~ (done)
2. ~~Export~~ (done). Still to add with later stages: the "music on a Short over 1:00" check (needs the music lane, step 5), loudness normalisation (step 5).
3. ~~Remove silences~~ (done, as "Remove Pauses").
4. ~~Text overlay~~ (done, as "Titles", stage 5), with the "text where YouTube covers it" export check.
5. **Audio** ← next (stage 6): clip volume, fades, a background-music lane with automatic ducking under speech, loudness normalisation on export.
6. **Save/open projects**: a project file with autosave, security-scoped bookmarks to media, and relinking of missing media. Today the project lives only in memory, so **quitting loses the edit**.
7. Then P1 from the research: editing by deleting words in the transcript, keyframes/punch-in zoom, auto-reframe of horizontal footage (Vision), speed, loop preview, brand kit.

## Open questions for the user

- Should the editor link exported Shorts to `channel_lab` plans (`~/Documents/Programming/YouTube`)? Recommended: not now; maybe later.

## Known limitations / tech debt

- Undo was silently broken before 2026-11-08: opening files from Finder briefly creates a second window, and the model had attached to its undo manager. Now the model asks its window (re-set each time the window becomes active) for the undo manager at every edit.
- Captions: a whole source file is transcribed even if only part of it is used (fine for Short-length clips, slow for long ones). Lines are grouped by length/pauses/sentence ends; there's no manual "split this caption here" yet. No caption dragging in the viewer (Top/Middle/Bottom only). The test sample is a synthetic voice, so accuracy on real, noisy recordings is untested.
- Export: the MP4 has edit lists (from B-frames and AAC priming, standard for AVFoundation and iPhone files). YouTube's encoding page says "no edit lists"; untested whether it matters. If an upload ever misbehaves, try `AVVideoAllowFrameReorderingKey: false`. "Closed GOP" isn't verified either (VideoToolbox key frames are normally IDR).
- Test fixtures with sound must mark the audio input finished as soon as the last chunk is in; otherwise `AVAssetWriter` stalls the video waiting for more audio.
- Remove Pauses: the shortest pause cut is fixed at 0.3 s (not a slider). Detection is by loudness only, so steady background music or noise above the threshold isn't seen as a pause; lowering "What counts as a pause" is the fix. Clips whose file has no sound are left alone.
- Playback times from AVPlayer are in nanoseconds; compare them with model times only after `snappedToFrame()` (a skip loop came from this).
- The Highlight style's green box can blend into green backgrounds.
- Titles: the text is saved when editing ends (Return or clicking away), so the viewer updates then, not while typing. No snapping when dragging on the timeline. Overlapping titles share one lane row and are drawn on top of each other. One font (the system font) for all styles; no colour picker.
- SwiftUI text fields hand the old value back to their binding as focus leaves. Editing fields that save on end (caption lines, title text) only accept changes while focused; otherwise what was typed is lost.
- No project saving yet (see step 6).
- Only video files can be imported (no audio-only files or images yet).
- `SafeZone` margins are approximate (no official YouTube overlay found).
- Moving clips by dragging on the timeline isn't implemented (right-click Move Earlier/Later only).
- The timeline shows one thumbnail per clip, not a filmstrip.

## How to test on screen

The terminal needs **Screen Recording** and **Accessibility** permission (both granted on this Mac).

```
make build
Tools/uitest/make-samples.sh                       # test clips into Tools/uitest/.samples (incl. talking-sample.mp4 for captions, pauses-sample.mp4 for Remove Pauses)
open -a "$PWD/build/Build/Products/Debug/Shorts Editor.app" Tools/uitest/.samples/*.mp4
Tools/uitest/ui.sh shot start                      # screenshot → Tools/uitest/.shots/start.png
Tools/uitest/ui.sh click 470 621                   # real click, window-relative points
Tools/uitest/ui.sh key b ; Tools/uitest/ui.sh code 49   # B, then Space
```

Menu items can be clicked by name, e.g. `osascript -e 'tell application "System Events" to tell process "Shorts Editor" to click menu item "Remove Pauses…" of menu "Clip" of menu bar 1'`. In the Save panel, ⌘⇧G then a path and Return picks the folder.

To check undo: `osascript -e 'tell application "System Events" to tell process "Shorts Editor" to get enabled of menu item 1 of menu "Edit" of menu bar 1'`. To see `NSLog` output, run the binary in `Contents/MacOS` directly (the unified log didn't show it).

Notes: System Events' `click at` doesn't trigger SwiftUI taps, which is why `ui.sh` posts real mouse events. Screenshots are 2× on the Retina display and 1× on the external one. Give the window a second or two after `activate` when it's on another Space.
