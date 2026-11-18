# Project status

_Last updated: 2026-11-18. The current state only: read it first when picking the project back up, and update it at the end of each session. What was done and found, session by session, is in `CHANGELOG.md`; why the code is the way it is, in `docs/adr/`._

## Where we are

Shorts Editor is feature-complete for its plan: the P0 list, roadmap features 1–12, the iMovie list (stages A–F) and the CapCut list (stages G–L) are built, tested and checked on screen. The engineering-excellence plan (`research/engineering-excellence.md`) is done for phases 1–7 (safety net, never lose work, correct pictures, architecture, tests for the app, responsiveness, platform fit), except F26 (Italian), which the user postponed. Phase 8 (ship) is under way.

**New direction (2026-11-18, later):** the user wants the app to be as easy as iMovie with no learning. Usability audit: `research/usability-audit.md` (findings U1–U21, rules R1–R8 from web research, order of work in §5). **Step 1 (Mac habits) is built, checked on screen, `make check` green, not yet committed:** Cut/Copy/Paste/Duplicate of timeline items (`EditorCore/Clipboard.swift`, `App/EditorModel+Clipboard.swift`; Edit menu routes to text while typing), right-click menus, ⌥-drag to copy (titles, B-roll, sounds), Escape deselects, pinch to zoom the timeline, and the title-box bug (U11: stale skim time after a drag). Pinch couldn't be tried with synthetic events (no trackpad gesture); it needs a real trackpad. **Next: step 2, sound waves on the music and bigger waves (U7–U9).**

**Before that (2026-11-18):** F24 and F31 of Phase 8 are done (below), `make check` green, checked on screen, committed and pushed (cfd0389). **F32 is built** (below): `make release` makes `build/dist/Shorts-Editor-0.1.0.dmg`, checked (built before the new red icon: remake it before publishing); Check for Updates… works. **Version: 0.1.0 (a beta), not to be published yet (user, 2026-11-18). Next: publish when the user says (`make publish` remakes the `.dmg`); F26 (Italian) whenever wanted.** F21's second half (Report a Problem…) is skipped by the user.

Repository: https://github.com/lucalevi/TheShortsEditor (public, branch `main`).

## Phase 8: ship

- [x] F32 (2026-11-18, not yet published) **without a Developer ID** (user, 2026-11-18; `docs/adr/0011-no-developer-id.md`): ad hoc signed app in a `.dmg` (drag to Applications, a "How to open" note inside) attached to a GitHub Release; first-launch instructions (macOS 15+ removed Control-click ▸ Open: open once, then System Settings ▸ Privacy & Security ▸ Open Anyway; or `xattr -dr com.apple.quarantine`); semantic versions with an automated build number; release notes from `CHANGELOG.md`; Shorts Editor ▸ Check for Updates… (`App/UpdateChecker.swift`) asks GitHub's API, only when chosen, and links to the download (no Sparkle); `make release` builds the `.dmg`, `make publish` also tags and makes the GitHub Release. No notarization, no privacy manifest (only the App Store needs one). Release notes for the first version: `docs/releases/0.1.0.md`.
- [ ] F21 (second half) Help ▸ Report a Problem… (log + project structure, no media): **skipped by the user (2026-11-18)**: one person can't take in and fix bug reports as they come. MetricKit hang/crash reports are already kept (`App/HangReports.swift`, Phase 6), so this can be added later if wanted.
- [x] F31 (2026-11-18) `STATUS.md` kept to the current state; history in `CHANGELOG.md`; decisions as ADRs in `docs/adr/` (10); DocC catalogs for EditorCore and RenderEngine, `make docs` (all three libraries, no new dependency: `xcodebuild docbuild`)
- [x] F24 (2026-11-18) **Delete Generated Files…** on each Short in All Shorts (⋯ and right-click): the copies made for that Short alone, with their size, after asking; kept when another Short uses them; refused while the Short is open. Settings ▸ Storage lists each Short's own copies with Delete… Checked on screen. Found on the way: Settings was taller than a laptop's screen (Storage out of reach); it scrolls now.

Phases 1–7 and their checklists: `CHANGELOG.md`. F26 (String Catalog and Italian), postponed by the user on 2026-11-17, is sized and planned there (Phase 7 checklist).

## Waiting on the user

- **Screen Recording for Xcode's test runner** (System Settings ▸ Privacy & Security): the accessibility audit UI test (`TEST_RUNNER_SHORTS_UI_AUDIT=1 make uitest`) fails before auditing without it.
- **F26 (Italian):** when wanted.
- **F21 Report a Problem…:** skipped; only if the user asks for it.
- **First release:** 0.1.0 (beta), published only when the user says so.

## Open questions for the user

- Should the editor link exported Shorts to `channel_lab` plans (`~/Documents/Programming/YouTube`)? Recommended: not now; maybe later.

## Decisions already made (don't re-ask)

- macOS 26+, Apple Silicon. SwiftUI app with AppKit where needed. XcodeGen project.
- Personal tool first; a shareable **.dmg** on GitHub Releases later. **No paid Apple Developer ID (user, 2026-11-18):** the app stays ad hoc signed and people open it past the "unknown developer" warning with written instructions (ADR 0011).
- Caption languages: **English, Italian, German, French**. All four are available in Apple's on-device `SpeechTranscriber` (checked on this Mac).
- Support all kinds of footage, with **very friendly, intuitive UX** as the top requirement.
- Repo is public on GitHub.
- **Direction (2026-11-12): iMovie's look and feel, CapCut's features.** New features come from the CapCut list (stages G–L), shaped to iMovie's grammar.
- **Quality (2026-11-14): professional, Final Cut Pro-level engineering before more features.** Work follows `research/engineering-excellence.md` (phases 1–8); every change meets its definition of done (§7). Kept on purpose (§5): snapshot undo of a value-type project, the library in Application Support (not `NSDocument`), rebuilding from the model, the fixed 1080×1920 30 fps canvas.
- Architecture decisions: `docs/adr/` (value-type project, one compositor, CMTime, captions per source file, the library instead of NSDocument, strict decoding, made copies, transitions keep the length, one colour pipeline, no blocking on shared threads).

## Loose ends

- **Open bug (cosmetic):** in the B-roll inspector the whole page sometimes shifts ~7 pt left (the right edge clipped, the Effects grid gets a 4th column) after a layout change, e.g. choosing a shape or switching an effect between Whole clip and At the start/end; selecting the item again lays it out correctly. Seen with a landscape B-roll (`broll-sample`). Tried and dropped: pinning the scroll content's width, letting the sliders shrink, drawing tile pictures as overlays. Next idea: find which row reports ~306 pt (temporary `onGeometryChange` logging per section).
- **Not yet verified on screen:** Stage C length slider/freeze buttons/right-click menus, Stage E trimmer and slow-motion switch and its Photos tab, Stage F Use Selected and dropping on a shot, Library Save a Copy…/Open…, deleting several media files (each stage's list is in `CHANGELOG.md`). Then whole-Short "golden" export tests.
- Exports aren't yet confirmed by an actual YouTube upload.
- `make app-test` once failed with "The test runner hung before establishing connection" (2026-11-18) while the app itself launched fine: `killall testmanagerd` fixed it.

## Known limitations / tech debt

The engineering-quality debt (silent decode fallbacks, no backups, no colour management, `EditorModel` size, no logging, no app tests, no localization…) was planned in `research/engineering-excellence.md` and is done (see `CHANGELOG.md`); the items below are product limitations.


- Undo was silently broken before 2026-11-08: opening files from Finder briefly creates a second window, and the model had attached to its undo manager. Now the model asks its window (re-set each time the window becomes active) for the undo manager at every edit.
- Captions: a whole source file is transcribed even if only part of it is used (fine for Short-length clips, slow for long ones). Lines are grouped by length/pauses/sentence ends, plus the user's splits and joins. Captions move only up/down as a whole (no per-caption position). The test sample is a synthetic voice, so accuracy on real, noisy recordings is untested.
- Export: since 2026-11-13 there are no B-frames, so the video's edit list is a plain one (starts at 0) and GOPs are exactly 15 frames, all IDR (closed). The sound's edit list (AAC priming) stays, as in every AAC file. Not yet confirmed by an actual YouTube upload.
- Test fixtures with sound must mark the audio input finished as soon as the last chunk is in; otherwise `AVAssetWriter` stalls the video waiting for more audio.
- Remove Pauses: detection is by loudness (of the whole sound, or of the voice alone with "Listen to the voice only", which separates each file once). Clips whose file has no sound are left alone. Magic Short still uses the whole sound.
- Playback times from AVPlayer are in nanoseconds; compare them with model times only after `snappedToFrame()` (a skip loop came from this).
- The Highlight style's green box can blend into green backgrounds.
- Effects: one of each kind per clip; no keyframing of strength; Light Leak drifts on a fixed 4 s cycle; Mirror copies the left half only. The new sounds are synthesized and were only measured, not judged by ear.
- Stickers are titles underneath: they share the titles lane and the export check for covered titles. Following is 2-D only (no scale/rotation following) and stops where the subject is lost or the clip changes. Spoken voice-overs stay in Application Support until moved to the Trash from Settings ▸ Storage.
- Titles: the text is saved when editing ends (Return or clicking away); the viewer shows it while typing (`LivePreview`), but quitting while typing loses it.
- SwiftUI text fields hand the old value back to their binding as focus leaves. Editing fields that save on end (caption lines, title text) only accept changes while focused; otherwise what was typed is lost.
- Saving: one window, one Short at a time (no DocumentGroup: the single-window model, shared `EditorModel` and Finder media import made a custom store simpler). No versions browser and no "Revert". Media bookmarks are app-scoped, so a project copied to another Mac (or user) needs Find Missing Files… there. Writing tries an atomic write first and falls back to a plain one if the sandbox refuses the temporary file. In an Open panel a folder has to be *selected* (not just opened) for "Use" to work, as everywhere in macOS. `screencapture` of the app window misses separate windows (Open panel, alerts): capture their region (`System Events … get {position, size} of windows`).
- Only the main song has beats, looping and a style mood; more songs go on the sounds lane (lowered under speech like the song when "Lower while people talk" is on). Animated GIFs show their first frame only.
- B-roll sound isn't counted as speech for ducking. Voice-overs count as speech for their whole length (not by loudness).
- Without Apple Intelligence, key words and emoji are picked by simple rules ("welcome"/"showing" can be picked; small emoji dictionary) and fillers are sounds only. With it, the model may pick more key words than one in seven, and its emoji can be literal (💅 for "trucco", Italian for both "trick" and "make-up").
- Stage G: captions are translated a sentence at a time and the translation is shared out over the sentence's captions by length, so with a different word order a caption's second line may not match its own words exactly. Language detection listens to the first heard file only and tries at most 4 languages; a language whose speech model isn't on the Mac is only tried when it is the Mac's own. Words in voice-overs and B-roll can't be cut from the Script panel. Splitting a caption doesn't split the clip; joins work only within one clip or sound. Caption edges don't snap. A muted clip's spoken captions are hidden (they come back when it is unmuted).
- Voice clean-up copies are kept in Caches and remade if missing; a project opened on another Mac re-cleans when the toggle is switched off and on.
- Speed curves are six fixed shapes (no custom curve); they play in 3-frame steps and their sound in ≥ 0.2 s stretches (slightly out of step inside a stretch). The filmstrip of a curved clip is drawn at its average speed. Smooth slow-motion copies stay in Caches (removed at launch once no Short has used them for a week) and are remade when the clip's slowest speed changes the factor.
- Split screen: halves (top, bottom, left, right) and thirds (top, bottom), one B-roll per edge. The viewer's selection box shows the whole filled picture, not just its part of the split.
- Live preview while dragging a picture redraws the frame by seeking to the same time; during playback it isn't shown (dragging pauses).
- Keyframes animate placement only (not opacity or volume). The handles' corner squares are kept inside the viewer, so on a picture bigger than the screen they sit at the edge, not at the true corner.
- Filmstrip and waveform are drawn per clip with Canvas; very long clips at high zoom draw many stills (no tiling yet).
- Synthetic clicks (`ui.sh`) can leave a SwiftUI pop-up menu open, which blocks Apple events to the app (osascript times out after 2 minutes). Press Escape (`ui.sh code 53`) after using a pop-up.
- Audio: beat finding assumes one steady tempo (songs that speed up or swing drift off the grid; Add/Remove Beat fixes single beats). Cut to the Beat only shortens/lengthens clips, it doesn't split long ones into beat-length pieces.
- Volume line: points move up/down only (not sideways). B-roll has fades and effects in the inspector but no line on its timeline block. "Too loud" uses per-frame RMS (−6 dBFS), not true peaks, so it's a hint. Voice effects are synthesized by me and were never judged by ear; Robot is ring modulation + a short comb, not a vocoder. Processed copies are stereo, play from file time 0 (a video whose sound starts later than its picture would drift slightly, same as voice clean-up), and the echo/reverb tail is cut at the end of the file. Speech for ducking is found by loudness, so a clip with constant loud sound (e.g. its own music) counts as speech throughout. Volume sliders apply when released (no live preview while dragging). AVFoundation's audio mix does boost above 100% (checked: linear in float).
- Photos: only the newest 600 items of a kind are listed (no albums, no search, no scrolling further). Copies of library items stay in `Application Support/Shorts Editor/From Photos` (Settings ▸ Storage moves unused ones to the Trash). Live Photos are used as stills. No dragging from the Photos grid.
- Clip trimmer: no sound waveform, and sound items can't be opened in it. Markers can't be added to a clip in Media (only on the timeline).
- Looks: colour maths works on stored video values, not linear light, so Light and Warmth act a little differently from a photo app. The lookup table is 32 points a side (smooth gradients are fine in tests; extreme Noir contrast may band slightly). Glow (Dreamy) uses `CIBloom` and is the slowest filter. Filter tiles are remade when the clip, its sliders or the playhead (every half second) change.
- Stabilize: whole files are measured (a long file takes a while; progress is shown). Only shifts are corrected, not rotation or rolling shutter. A freeze frame of a steadied clip isn't steadied, so it can jump by the clip's zoom. Paths are per file in Caches; another Mac measures again.
- Live previews (dragging pictures, colour sliders) redraw by seeking; the paused player didn't always redraw on a seek to the very same time, so seeks now alternate by a millisecond.
- Transitions: the sound crossfades only where both clips play their own sound at an even speed with no fade of their own at the cut, and their files have half a transition of sound to spare (else it cuts). Only between main clips (not at the start or end of the Short, not on B-roll). Without spare footage a clip is held on its first/last picture during its half. The white band over a transition on the timeline is faint.
- Backwards copies are H.264 at up to 1920 px on the long side; they are listed in Media, stay in Application Support when no longer used (Settings ▸ Storage moves them to the Trash), and for files over a minute hold only the clip's part ± 3 s (the clip can't be trimmed out further). Backwards speech has no captions.
- Gradual speed changes move the picture only: the sound changes speed at the cut, so it is up to a few frames out of step with the picture inside the half-second change, and in step again after it. Captions and keyframes there are timed as if the change were at the cut.
- Slow-motion footage always starts at ¼ speed (no setting yet; press 1× to undo). Instant Replay adds no "Replay" label; there is no Rewind.
- `MusicTrack` is a type in Apple's AudioToolbox, hence the model's name `BackgroundMusic`.
- `SafeZone` margins are approximate (no official YouTube overlay found).


- Stage F: the style music is synthesized (simple instruments, one 16-bar loop per mood) and has only been measured, not judged by ear. Magic Short keeps the *start* of a long video when fitting a length (it doesn't search for the best part), and the hook title is the first sentence (rules, no language model). Pauses are cut only in clips with words in their transcript, so with captions in the wrong language nothing is cut. Storyboard shots can't be added, renamed or reordered; a shot's clip is found by its id, so a clip split later still fills the shot with its first part.

## How to test on screen

The terminal needs **Screen Recording** and **Accessibility** permission (both granted on this Mac).

```
make build
Tools/uitest/make-samples.sh                       # test clips into Tools/uitest/.samples (incl. talking-sample.mp4 for captions, pauses-sample.mp4 for Remove Pauses)
open -a "$PWD/build/Build/Products/Debug/Shorts Editor.app" Tools/uitest/.samples/*.mp4
Tools/uitest/ui.sh shot start                      # screenshot → Tools/uitest/.shots/start.png
Tools/uitest/ui.sh click 470 621                   # real click, window-relative points
Tools/uitest/ui.sh rclick 120 290                  # right-click; a click on a context-menu item doesn't register, so pick it with the arrow keys + Return (key code 125, 36)
Tools/uitest/ui.sh key b ; Tools/uitest/ui.sh code 49   # B, then Space
```

Menu items can be clicked by name, e.g. `osascript -e 'tell application "System Events" to tell process "Shorts Editor" to click menu item "Remove Pauses…" of menu "Clip" of menu bar 1'`. In the Save panel, ⌘⇧G then a path and Return picks the folder.

To check undo: `osascript -e 'tell application "System Events" to tell process "Shorts Editor" to get enabled of menu item 1 of menu "Edit" of menu bar 1'`. To see `NSLog` output, run the binary in `Contents/MacOS` directly (the unified log didn't show it).

Notes: System Events' `click at` doesn't trigger SwiftUI taps, which is why `ui.sh` posts real mouse events. Screenshots are 2× on the Retina display and 1× on the external one. Give the window a second or two after `activate` when it's on another Space.

While a pop-up menu or a modal panel is open, `ui.sh` hangs (its osascript calls wait). Send keys with `Tools/uitest/.bin/mouse key CODE` directly, start menu-item clicks that open a panel in the background (`(osascript … &)`), and capture the Open/Save panel by its own window number (`CGWindowListCopyWindowInfo`, owner "Shorts Editor", the smaller window; `screencapture -l <number>`). Click in it with `.bin/mouse click` at the panel's screen position plus the point.
