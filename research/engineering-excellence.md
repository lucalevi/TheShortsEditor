# Engineering excellence: taking Shorts Editor from "works well" to "outstanding"

_Research and audit, 2026-11-14. Baseline: commit `8870268` on `main`._

This document does two jobs:

1. **The standard.** It says what "outstanding" means for a professional Mac video editor, using
   Final Cut Pro as the reference and Apple's own platform guidance as the rulebook.
2. **The audit.** It measures the current code against that standard. Each gap comes with evidence
   (file and line), why it matters, what to do about it, and a priority.

The roadmap in §6 orders the work. §7 is a "definition of done" checklist that every future
change should meet, so the quality doesn't drift back.

---

## 1. What "outstanding" means here

A professional editor such as Final Cut Pro is judged on six things, in this order. Features come
last because users forgive a missing feature but not a lost edit or a stuttering timeline.

| # | Quality | What the user feels | What the engineering needs |
|---|---|---|---|
| 1 | **Trust** | "My work is never lost or damaged." | Durable saves, crash-safe writes, backups, versioned file format with migrations, no silent data loss |
| 2 | **Responsiveness** | "It never beachballs; scrubbing is instant." | Nothing slow on the main thread, measured performance budgets, incremental work, background tasks with progress |
| 3 | **Correctness** | "What I export looks exactly like what I saw, and like my footage." | Colour management, HDR, frame-exact timing, tests that check pixels and samples |
| 4 | **Platform fit** | "It feels like a real Mac app." | Human Interface Guidelines, accessibility, localization, standard menus/windows/documents, Settings, Help |
| 5 | **Maintainability** | (Users never see this, but it sets how fast and safely we can improve.) | Clear module boundaries, small types, dependency injection, automated checks (CI, lint, format), docs |
| 6 | **Shipping** | "It installs cleanly, updates itself, and problems get fixed." | Developer ID signing, notarization, updates, crash and hang reports, versioning, release notes |

Reference sources used throughout:

- Apple Human Interface Guidelines (macOS), Accessibility, and Localization documentation.
- Swift API Design Guidelines, the Swift 6 concurrency model, and Swift Testing.
- AVFoundation's HDR editing guidance (WWDC20 session 10009, "Edit and play back HDR video with
  AVFoundation"; Apple's Dolby Vision integration guide).
- Final Cut Pro's user guide on libraries, backups, background tasks and generated media.
- Established general practice: the test pyramid, continuous integration, semantic versioning,
  "make illegal states unrepresentable", single responsibility.

---

## 2. Where we already are strong

These are real strengths. The plan below builds on them rather than replacing them.

- **A pure, value-type model** (`EditorCore`): no AVFoundation, `Sendable`, unit tested. This is
  the same shape as the best editors: model separate from rendering.
- **One edit path.** Every edit goes through `EditorModel.apply(_:_:)`, which gives undo for free
  and keeps the project value as the single source of truth.
- **One compositor for preview, thumbnails and export**, so "what you see is what you export".
- **Tests: 436 Swift Testing tests in 74 suites, all passing** (`make test`, about 80 s on
  2026-11-14), including render tests that generate their own fixtures and
  check pixels, and export tests that check the written file.
- **Swift 6 strict concurrency** is on, with heavy work marked `@concurrent`.
- **Documentation habit:** about 2,300 `///` doc comments; `CLAUDE.md` and `STATUS.md` explain the
  architecture and state.
- **Sandboxed, hardened runtime**, with security-scoped bookmarks for media.
- **Signposts** already exist for frame drawing and composition builds.
- **Missing media never breaks playback** (black or silence and a report).
- Plain-language UI text, consistent with the product goal.

The codebase is about 31,000 lines of Swift: App 15,100, EditorCore 9,800, RenderEngine 5,800,
Transcription 370, tests 8,200.

---

## 3. Audit findings by area

Priorities: **P0** = can lose or damage user work, or ship wrong pictures; fix first.
**P1** = clearly below professional standard; fix in the next passes.
**P2** = polish that separates "very good" from "outstanding".

### 3.1 Trust: saving, file format, data integrity

**F1. Corrupt or unknown fields are silently dropped, then the loss is saved (P0).**
`Clip.init(from:)` uses `try?` for many fields (`Timeline.swift`, from about line 247:
`voiceEffect`, `equalizer`, `transitionOut`, `look`, `speedCurve`, `animationIn/Out`, `effects`,
`cutout`, `backgroundColor`). If one of these fails to decode (a bug, a newer enum case, a hand-
edited file), the clip quietly falls back to the default. The next autosave, one second later,
writes the damaged version over the good file. The user loses colour grades or effects and is
never told.
*Standard:* decoding must either succeed or fail loudly; data that can't be understood is kept,
not discarded.
*Do:* replace `try?` with `try` in all model decoders. For forward compatibility of enums, decode
unknown cases into an explicit `.unknown(rawValue)` that is written back unchanged. Before
overwriting a file that was read with any repair, keep a backup (see F4).
*Done 2026-11-14, with one change of plan:* instead of `.unknown(raw)` cases (which would touch every
`switch` over every enum), a file with an unknown value refuses to open with a clear message
(`ReadError.unknownValue`, "made with a newer version, update the app; the file wasn't changed"). A
file that never opens is never saved over, so nothing is lost; this is also what Final Cut Pro does
with newer libraries. Verified first against every golden version and all 31 Shorts in the real
library.

**F2. Decode errors are flattened to "unreadable" (P1).**
`ProjectFile.decode` (`ProjectFile.swift:60-64`) catches every error and throws
`ReadError.unreadable`. The `DecodingError` (which key, which path) is lost, so we can't diagnose a
user's broken file.
*Do:* keep the underlying error in the case (`unreadable(underlying:)`) and log its coding path.

**F3. No tests against real old files (P0).**
The format is at version 8, with hand-written decoders full of defaults, but
`ProjectFileTests` only round-trips a project made by the current code. Nothing proves a version 2,
5 or 7 file still opens the same way.
*Standard:* every format version that ever shipped has a frozen fixture file and a test that
opens it and checks the result ("golden files").
*Do:* add `Tests/EditorCoreTests/Fixtures/v2.shortsproject … v8.shortsproject` (written once from
old commits or by hand) and a test per version. Add a test that sets **every** field of `Clip`,
`Project`, `TextOverlay` etc. to a non-default value and round-trips it, so a field forgotten in a
hand-written `encode` is caught. Consider synthesized `Codable` plus a small migration step per
version, instead of 35-key hand-written coders that need three edits per new field.

**F4. No backups and no version history (P1).**
Final Cut Pro backs up the library database automatically (Apple: "Back up Final Cut Pro";
backups contain the project data only, not media). We overwrite one file every second
(`EditorModel+Library.swift`, `saveNow`). One bad write, one bad decode (F1), one bug in an edit,
and there is nothing to go back to once the app is closed (undo doesn't survive relaunch).
*Do:* keep rolling backups of each Short's project file (for example the last 10, plus one per
day for a week) in `Application Support/Shorts Editor/Backups/<id>/`. Add File ▸ Revert To ▸ …
listing them. Project files are small, so this costs almost nothing.

**F5. Non-atomic fallback write (P1).**
`ProjectStore.write` (`ProjectStore.swift:44-50`) falls back to a plain, non-atomic write if the
atomic one fails. A crash or full disk in the middle leaves a half-written file, and that is the
only copy.
*Do:* for files in the library (our own container) the atomic write always works, so never fall
back there. For "Save a Copy" outside the container, use `NSFileCoordinator` and
`FileManager.replaceItemAt`, or write to the user-chosen URL directly but only after a successful
atomic write to the library copy.

**F6. Saving and loading the library run on the main thread (P1).**
`saveNow` encodes the whole project as pretty-printed, key-sorted JSON and writes it on the main
actor, every second while editing. `ProjectStore.libraryEntries()` reads and fully decodes
**every** Short (including all transcripts) on the main thread to show the home window. Both
grow with project size and library size and will cause hitches and beachballs.
*Do:* encode on the main actor (the value is a snapshot) but write on a background task; drop
`.prettyPrinted` for library files (keep it for "Save a Copy" if wanted). Store a tiny summary
(name, dates, duration, clip count) in a sidecar or the file header so the home window doesn't
decode whole projects.

**F7. Deleting a Short can't be undone in the app (P2).** `ProjectStore.delete` trashes the file
but there's no Undo in the app. Make it an undoable action on the home window.

### 3.2 Correctness of pictures and sound

**F8. No colour management; HDR footage is not handled deliberately (P0).**
The compositor and look renderer use `CIContext(options: [.workingColorSpace: NSNull(),
.outputColorSpace: NSNull()])` (`ShortsCompositor.swift:172`, `LookRenderer.swift:91`, and four
more), ask for 8-bit `32BGRA` source frames, set no colour properties on the video composition,
and don't declare `supportsHDRSourceFrames`. Export tags the file as Rec. 709
(`Exporter.swift:155`).
iPhones have recorded HDR (HLG / Dolby Vision) by default since the iPhone 12, so this is the
**most common footage** a Shorts creator will import. Today the HDR-to-SDR conversion is left to
whatever AVFoundation does implicitly, filters and colour adjustments run on non-linear values,
and title/caption colours (drawn in sRGB) are mixed into video values with no conversion.
Apple's guidance (WWDC20 10009 and the Dolby Vision guide) is: a custom compositor that edits HDR
must declare `supportsHDRSourceFrames`, work in a 10-bit or float pixel format, and set the
composition's colour primaries / transfer function explicitly.
*Do (two stages):*
1. **Correct SDR output from HDR input.** Set the video composition's colour properties to Rec. 709
   explicitly, add HLG and Dolby Vision test fixtures (a few frames are enough), and verify that
   exported pictures from HDR clips match a reference (no washed-out or clipped highlights). Give
   the Core Image context a real working colour space (linear Rec. 709 / extended linear sRGB) so
   looks, blurs and blends behave consistently, and convert overlays (titles, captions, stickers)
   from sRGB properly.
2. **Optional HDR output** later (YouTube accepts HDR Shorts): 10-bit HEVC, Rec. 2020 / HLG,
   `supportsHDRSourceFrames = true`, half-float pixel buffers.

**F9. 8-bit pipeline (P2).** With colour grading, filters and blurs on 8-bit BGRA buffers,
gradients band. Professional editors process in 16-bit float. Move the compositor's working
buffers to `kCVPixelFormatType_64RGBAHalf` (or let Core Image work in float with 8-bit only at the
edges), and measure the cost with the existing signposts.

**F10. Edge cases of real-world media (P1).** Tests use generated fixtures (good), but none cover:
variable frame rate (screen recordings, many phone clips), 60/120/240 fps sources, 25 fps, rotated
footage with odd sizes, 4K HEVC, 10-bit, audio at 44.1 kHz vs 48 kHz, mono vs stereo, files
with no audio track, very long files. Add a small "media matrix" of fixtures and run the
composition + export tests over all of them.

### 3.3 Responsiveness and performance

**F11. The whole composition is rebuilt after every edit (P1).**
`projectDidChange()` cancels and re-runs `CompositionBuilder.build` and swaps in a new
`AVPlayerItem` for every edit. This is simple and correct (good), but cost grows with project
complexity, and swapping the item interrupts playback and drops caches. Final Cut Pro keeps
playing while you edit.
*Do:* first **measure**: add a performance budget (for example, a rebuild for a 3-minute Short
with 60 clips, B-roll, captions and music must finish under 50 ms on the minimum supported Mac)
as a test that runs in CI, not only with `SHORTS_BENCH=1`. Then optimise where the numbers say:
cache per-clip work keyed by the clip value, reuse the `AVPlayerItem` when only compositor
instructions change (for instance, title text or a look), and debounce rebuilds during rapid
edits.

**F12. No measured budgets or hang detection (P1).** Signposts exist but nothing fails when things
get slower. Use `XCTMetric`/`measure` or Swift Testing time limits for: composition build, frame
draw time at 1080×1920, project save, library listing with 200 Shorts, opening a project with
30 minutes of transcripts. Add MetricKit (see F21) to catch hangs on real machines.

**F13. Undo history is unbounded (P2).** Each step keeps a full `Project` snapshot. Copy-on-write
shares unchanged arrays, so this is usually fine, but large changes (Magic Short, transcripts) are
kept forever. Set `undoManager.levelsOfUndo` to a sensible limit (for example 200) and check
memory with Instruments after a long session.

### 3.4 Architecture and maintainability

**F14. `EditorModel` is a "god object" (P1).**
One class plus 19 extension files holds about 450 stored or computed properties and about 320
functions: the project, the player, playback, skimming, selection, import, captions,
transcription jobs, translation, voice-over recording, export, Magic Short, templates, library,
progress dictionaries for eight kinds of background work, alerts, tips and UI state such as which
sheet is open. Every view receives the whole model. This is the main thing that makes the app
layer hard to test (it has no tests at all; see F17) and hard to change safely.
*Standard:* single responsibility; views depend on the smallest interface they need.
*Do (step by step, no big rewrite):*
- `DocumentController` (or keep the name `EditorModel`): project, `apply`, undo, saving. Small.
- `PlaybackController`: the `AVPlayer`, seek, play/pause, shuttle, skimming, loop, play range.
- `BackgroundTasks`: one place for all long jobs (voice cleaning, reversing, cut-outs, steadying,
  smoothing, beat finding, captions, export) with a uniform `Job` type: id, title, progress,
  cancel, error. This also gives us a Final Cut-style **Background Tasks window** (⌘9) for free,
  instead of eight separate progress dictionaries.
- `LibraryModel` for the home window.
- Feature models (captions, Magic Short, templates) that take the document controller as a
  dependency.
Each becomes `@Observable` and is injected through the SwiftUI environment, so views only see what
they use.

**F15. Process-wide mutable state (P1).** `LivePreview` (`ShortsCompositor.swift:88`) is a global
set of mutexes keyed by clip id; `ProjectStore.bookmarks`, `AudioProbe.measured`,
`Stabilizer.known` are static mutable caches. This rules out two Shorts open in two windows
(a standard Mac expectation), makes tests depend on order, and hides data flow.
*Do:* make the live preview state a value carried by the composition instructions or owned by one
compositor instance per player; make caches instances owned by the document or app, injected where
needed.

**F16. Names that describe history instead of meaning (P2).** `Batch2Inspectors.swift`,
`EditorModel+Batch2.swift`, `SecondBatchTests.swift`, `SecondBatchRenderTests.swift` describe
*when* code was written, not *what* it does. `EditorModel+Batch2` contains speed, voice
clean-up, sounds, text styles, voice-overs, reframing and split screen. Split and rename by
feature (`SpeedInspector.swift`, `EditorModel+Voice.swift`, `SpeedTests.swift` …).

**F17. Large public surface (P2).** `EditorCore` has about 1,280 `public` declarations; much of it is
only used inside the module or by tests (which already use `@testable`). Make things `internal` by
default and expose only what the app uses; this keeps the model's contract small and lets us
change internals freely.

### 3.5 Testing

**F18. The app target has no automated tests (P1).** 15,000 lines (`EditorModel`, import, undo,
saving, keyboard handling, menus) are tested only by hand-driven screen checks. After F14, the
controllers become testable with a fake player and an in-memory store.
*Do:*
- Unit tests for the app's controllers (an `AppTests` target in `project.yml`).
- An **XCUITest** target for the critical paths: import → edit → undo/redo → export; open a
  project with missing media; autosave survives a forced quit. These replace much of the manual
  `Tools/uitest` flow and run in CI.
- **Snapshot tests** of the compositor output for representative projects (one golden PNG per
  case, compared with a tolerance), so any change in the picture shows up as a reviewable diff.
- Coverage reporting (`swift test --enable-code-coverage`) with a floor that only goes up.

**F19. Performance tests are opt-in only (P2).** `PerformanceTests` run only with
`SHORTS_BENCH=1`; run them in CI on a schedule and track the numbers.

**F20. Concurrency stress (P2).** Add tests that cancel builds, exports and background jobs at random
points, and that edit while jobs are running, under the Thread Sanitizer (`swift test --sanitize=thread`).

### 3.6 Errors, logging and diagnostics

**F21. No logging, no crash or hang reports (P1).**
There is no `os.Logger` anywhere and one stray `print` (`App/Storage.swift:40`). There are 146 `try?`
that discard errors, many for good reasons (optional thumbnails), but some on paths that matter
(creating library folders, bookmarks, poster writing, copying media in `EditorModel+Batch2.swift:384`).
When a user reports "my clip is black" we have nothing to look at.
*Standard:* every subsystem logs through `Logger(subsystem:category:)` with privacy-aware
interpolation; failures that are ignored are still logged at `.error`/`.fault`.
*Do:* add `Logger` categories (`file`, `import`, `render`, `export`, `audio`, `captions`, `jobs`);
replace `try?` on important paths with `do/catch` that logs; add **MetricKit** (`MXMetricManager`)
to collect crash, hang and disk-write diagnostics; add a Help ▸ "Report a Problem…" item that
gathers the log (`OSLogStore`) and the project's structure (without media) into a file the user
can send.

**F22. Errors are strings (P2).** `ExportPhase.failed(String)` and `AlertMessage(title:message:)`
lose the error's type and recovery options. Use typed errors (`LocalizedError` with
`recoverySuggestion`) and present them with recovery buttons ("Find Missing File…", "Free Up
Space…", "Try Again").

### 3.7 Resource management

**F23. Security-scoped access is started and never stopped (P1).**
`importFiles` (`EditorModel.swift:428`) and `ProjectStore.readFile` (`ProjectStore.swift:73`)
call `startAccessingSecurityScopedResource()` for every media file and never balance it
(9 starts, 6 stops in the app). The system has a limited number of these per process; a long
session opening many Shorts will eventually fail to open files, and access to Shorts that were
closed is never released.
*Do:* a small `MediaAccess` object owned by the open document that starts access when a Short is
opened and stops all of it when the Short is closed (and reference-counts shared files).

**F24. Generated media (P2).** We already clean Caches at launch (good). Add a Final Cut-style
"Delete Generated Files" per Short and show what each Short's generated files cost in Settings ▸
Storage (partly there).

### 3.8 Platform fit: accessibility, localization, Mac conventions

**F25. Accessibility of custom views (P1).**
There are 73 accessibility modifiers in the app, a good start, but the timeline, viewer handles
and volume lines are custom drawn (`Canvas`, gestures) and largely invisible to VoiceOver and Full
Keyboard Access. Apple's HIG requires every control to have a label, value and actions.
*Do:* make each clip, title, sound and the playhead an accessibility element with
label ("Clip 3, talk.mov, 4.2 seconds"), value, and custom actions (Split, Delete, Trim Start,
Move Left/Right). Check with the Accessibility Inspector and an audit test
(`XCUIApplication().performAccessibilityAudit()` in the UI tests). Respect Reduce Motion,
Increase Contrast and Differentiate Without Color (important: the owner uses a black-and-white
screen filter, so state must never be shown by colour alone).

**F26. No localization infrastructure (P1).**
There is no String Catalog. SwiftUI `Text("…")` literals are localizable automatically, but the
many strings built in the model and `EditorModel` (alerts, action names such as
`"Delete \(items.count) Items"`, captions job texts, `Sidebar` raw values) are plain `String`s and
won't be translated. Plurals are hand-built (`count == 1 ? … : …`).
*Do:* add `Localizable.xcstrings` (Xcode extracts strings at build time); use
`String(localized:)` / `LocalizedStringResource` for strings created outside views; use the
catalog's plural variations; never use display text as raw values or keys. Format all times,
numbers and file sizes with `FormatStyle`. Italian is the natural first extra language (the
captions already support it).

**F27. Mac conventions (P2).** Compared with Final Cut Pro and other first-class Mac apps:
- **App icon**: there is no asset catalog or icon.
- **Help**: no Help book or in-app help (FCP has a full user guide under Help).
- **Multiple windows**: one Short at a time (blocked by F15).
- **State restoration**: reopening the app should bring back the open Short, playhead, zoom and
  panels.
- **Quick Look / Spotlight** for `.shortsproject` (a thumbnail extension using the saved poster).
- **Settings** scene exists; check every preference is there rather than only in menus.

### 3.9 Tooling and process

**F28. No continuous integration (P1).** `CLAUDE.md` says "there is no CI, so run it before every
commit". That depends on memory. A GitHub Actions workflow existed and was removed on 2026-11-13 because
GitHub's hosted macOS runners only have Xcode 26, whose compiler rejects code Xcode 27 accepts.
Options, in order of preference: (a) a **self-hosted runner on this Mac** (Xcode 27 is already
installed; GitHub's runner app runs as a background service), (b) a local `git pre-push` hook that
runs `make check` (tests + Debug and Release builds + lint) and refuses the push on failure,
(c) hosted runners again once they offer Xcode 27. Whichever is used: `make test`,
`make build` (Debug **and Release**), warnings treated as errors; performance and UI tests nightly.
Doing (b) immediately costs nothing and can be combined with (a).

**F29. No linter or formatter (P2).** Add `swift-format` (ships with the Swift 6 toolchain) with a
checked-in configuration, plus SwiftLint for rules such as "no `try?` on model decode", "no
`print`", file and type length limits. Run both in CI and in a pre-commit hook.

**F30. Build settings (P2).** Turn on "Treat warnings as errors" in CI, the Address and Thread
sanitizers in a test run, and Xcode's static analyzer. (Corrected 2026-11-14: `SWIFT_VERSION: "6.0"`
in `project.yml` is the Swift *language mode* and `swift-tools-version: 6.2` in `Package.swift` is
the *package manifest* version, so they were never mismatched; `project.yml` now says `"6"` for
clarity.) The Release build had 9 warnings, one of them a real bug: in `CaptionTextField` a cast the
compiler reported as "always fails", which an optimised build may drop (⌘↩ and click-outside).

**F31. `STATUS.md` is 537 lines (P2).** It has become a journal. Keep it short (state, next steps,
open questions), move history into `CHANGELOG.md` and decisions into short Architecture Decision
Records (`docs/adr/0001-value-type-project.md`, …). Generate API docs with DocC from the existing
`///` comments.

### 3.10 Shipping

**F32. Distribution (P1 before any public release).** Today: ad hoc signing, version 0.1.0,
build 1. Needed: Developer ID signing, **notarization** (`notarytool`) and stapling, a signed
`.dmg`, an update mechanism (Sparkle, or the Mac App Store), semantic versions with an automated
build number, release notes, and a **privacy manifest** (`PrivacyInfo.xcprivacy`; the app uses
`UserDefaults`, a required-reason API, and file timestamps). A scripted `make release` that does all
of it so a release is one command.

---

## 4. Benchmark against Final Cut Pro

| Area | Final Cut Pro | Shorts Editor today | Gap |
|---|---|---|---|
| Saving | Continuous save + automatic library backups | Autosave each second, no backups | F4, F5 |
| File format | Versioned library, upgraded with a prompt and a backup of the old one | Versioned JSON, defaults on read, no old-file tests, silent drops | F1–F3 |
| Background work | One Background Tasks window, all jobs pausable/cancellable | Eight separate progress states in the model | F14 |
| Playback while editing | Keeps playing; renders in the background | New player item per edit | F11 |
| Colour | Wide-gamut, HDR, 16-bit float pipeline, colour space per library | No colour management, 8-bit | F8, F9 |
| Media | Proxies, optimized media, any frame rate | Plays originals; frame-rate matrix untested | F10 |
| Accessibility | VoiceOver across timeline | Partial | F25 |
| Languages | Many | English only, no catalog | F26 |
| Diagnostics | Crash reporting, logs | None | F21 |
| Distribution | Signed, notarized, updates | Ad hoc | F32 |
| Interchange | FCPXML import/export | SRT for captions | (feature, not quality: later) |

---

## 5. What we deliberately keep

Some choices look unusual but are right for this product and should stay:

- **Snapshot undo of a value-type project** instead of command objects: simpler and safer. Just bound
  it (F13).
- **A library in Application Support rather than free-floating documents**: right for the iMovie-like
  audience. Add backups (F4) rather than switching to `NSDocument`.
- **Rebuilding from the model** as the edit model: keep it as the correctness baseline; optimise
  underneath it (F11), never by mutating AVFoundation objects.
- **Fixed 1080×1920, 30 fps canvas**: a product decision, not a gap.

---

## 6. Roadmap

Each phase is a few sessions, ends with `make test` green, a commit and an update of `STATUS.md`.

**Phase 1: Safety net (do first; makes everything after it safe).**
CI: a `make check` pre-push hook, then a self-hosted runner (F28); swift-format + SwiftLint (F29); Logger categories and removal of the
`print` (F21, first half); golden project files per format version + "every field round-trips" test (F3).

**Phase 2: Never lose work.**
Remove `try?` from model decoders with explicit unknown cases (F1); keep decode errors (F2); rolling
backups and File ▸ Revert To (F4); atomic writes only (F5); save and library listing off the main
thread with a lightweight summary (F6).

**Phase 3: Correct pictures.**
HLG / Dolby Vision / 10-bit / VFR / 60 fps fixture matrix (F10); explicit colour management and
correct HDR→SDR (F8); float working buffers measured for cost (F9).

**Phase 4: Architecture.**
Split `EditorModel` (F14), starting with `BackgroundTasks` (which also gives the Background Tasks
window) and `PlaybackController`; remove global state (F15); balance security-scoped access (F23);
rename the "Batch2" files (F16); trim `public` (F17).

**Phase 5: Tests for the app.**
App unit tests and an XCUITest target with the critical paths and an accessibility audit (F18);
compositor snapshot tests; coverage floor; nightly performance and sanitizer runs (F12, F19, F20).

**Phase 6: Responsiveness.**
Performance budgets enforced in CI (F12); incremental rebuilds / item reuse where measurements show
need (F11); bounded undo (F13).

**Phase 7: Platform fit.**
Accessibility of the timeline and viewer (F25); String Catalog + Italian (F26); app icon, Help, state
restoration, Quick Look, multiple windows (F27); typed errors with recovery (F22).

**Phase 8: Ship.**
Developer ID, notarization, `.dmg`, Sparkle, privacy manifest, MetricKit, Report a Problem,
CHANGELOG and ADRs, DocC (F21 second half, F31, F32).

---

## 7. Definition of done for every future change

A change is finished only when:

- [ ] `make test` passes locally **and** in CI; no new warnings.
- [ ] swift-format and SwiftLint are clean.
- [ ] New model fields: encoded, decoded **without `try?`**, covered by the every-field round-trip
      test, and the format version and golden files updated if the format changed.
- [ ] Nothing that can take more than ~16 ms runs on the main actor; long work goes through
      `BackgroundTasks` with progress and cancel.
- [ ] Failures are logged with `Logger`; errors shown to the user say what to do next.
- [ ] New controls have accessibility labels/values/actions and don't rely on colour alone.
- [ ] User-facing strings are localizable (in views, or `String(localized:)` elsewhere).
- [ ] Pictures: a render or snapshot test; sound: a sample-level test.
- [ ] Files and types stay small and named by what they do; no new global mutable state.
- [ ] `STATUS.md` updated briefly; the decision recorded in an ADR if it was a real choice.

---

## Sources

- Apple, WWDC20 session 10009, "Edit and play back HDR video with AVFoundation":
  https://developer.apple.com/wwdc20/10009
- Apple, "Incorporating HDR video with Dolby Vision into your apps":
  https://developer.apple.com/av-foundation/Incorporating-HDR-video-with-Dolby-Vision-into-your-apps.pdf
- Apple, `AVVideoCompositing` reference:
  https://developer.apple.com/documentation/avfoundation/avvideocompositing
- Apple Developer Forums, "Transparent overlay changes color in HDR video":
  https://developer.apple.com/forums/thread/772904
- Apple Support, "Back up Final Cut Pro": https://support.apple.com/en-us/HT203010
- Apple, Final Cut Pro User Guide for Mac: https://support.apple.com/guide/final-cut-pro/ver0be4a6320/mac
- Apple, "Localizing and varying text with a string catalog":
  https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
- Apple, WWDC23 session 10155, "Discover String Catalogs": https://developer.apple.com/wwdc23/10155
- Privacy manifest and required-reason APIs (UserDefaults category CA92.1; confirm against Apple's
  "Describing use of required reason API" page before shipping):
  https://support.singular.net/hc/en-us/articles/24045392537243
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Swift API Design Guidelines: https://www.swift.org/documentation/api-design-guidelines/
