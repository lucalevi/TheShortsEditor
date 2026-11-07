# TheShortsEditor — Research

_Research date: 2026-11-07. Scope: a macOS-only GUI editor for **YouTube Shorts only**, CapCut-like, covering the ~20% of features that produce ~80% of a successful Short._

Sources are listed at the end. Where sources disagree or a claim could not be confirmed from an official source, it is marked **(unverified)**. Re-check those before building anything that depends on an exact number.

---

## 1. The Pareto question, answered up front

A successful Short is mostly decided by five things. Almost every feature worth building serves one of them:

| # | What wins a Short | Why | Editor features that serve it |
|---|---|---|---|
| 1 | **A hook in the first frame / 1–3 s** | Viewers swipe instantly. Guides consistently say: no intro, no "hey guys", the first frame *is* the hook. | Fast trim of the head, "cut the first N seconds" review, hook text overlay, thumbnail-style first frame |
| 2 | **Pacing with no dead air** | Retention curves drop at pauses and slow stretches. | Silence/filler removal, split/ripple-delete, jump cuts, speed changes |
| 3 | **Burned-in captions** | A large share of viewing is sound-off, and an audio-only hook loses those viewers. | Auto-captions with word timing, styled "karaoke" highlight, editable transcript |
| 4 | **Correct vertical framing** | 9:16 at 1080×1920. Key content has to stay clear of the YouTube UI overlays. | 9:16 canvas, safe-zone overlay, reframe/crop with keyframes, auto-reframe |
| 5 | **Clean audio and music that won't get blocked** | Bad audio kills retention, and Shorts over 60 s with *any* Content ID claim are blocked. | Voice level/normalization, music ducking, music-length warning, loudness-normalized export |

Everything else (transitions packs, 3D effects, LUT grading, multicam, Fusion-style compositing) is the "80% of features that produce 20% of the result" and should be deferred or skipped.

---

## 2. YouTube Shorts platform constraints (the spec the editor must enforce)

| Constraint | Value | Confidence |
|---|---|---|
| Max length | **3 minutes (180 s)**, for uploads since 15 Oct 2024 | Official (Google support) |
| Aspect ratio | **9:16** vertical (1:1 square also qualifies) | High: consistent across sources |
| Resolution | **1080×1920** recommended, 720×1280 minimum | High. Max upload resolution is disputed (1080p vs 4K) **(unverified)** |
| Music + length | A Short **over 1 minute with any active Content ID claim is blocked** (including claims set only to monetize, and manual claims) | Official |
| Shorts Audio Library | Most tracks usable for **up to 90 s** in a 3-min Short. Some are limited to 60 s or 30 s | Official |
| Container | MP4, moov atom at front (Fast Start), no edit lists | Official (encoding settings page) |
| Video codec | H.264, progressive, high profile, 4:2:0, closed GOP of half the frame rate | Official |
| 1080p bitrate | ~10 Mbps at standard frame rate (≤30 fps), ~15 Mbps at high frame rate | Official ("for reference", not a limit) |
| Audio | AAC-LC, 48 kHz, stereo ~384 kbps recommended | Official |
| Loudness | Around **−14 LUFS** integrated is the common target | **(unverified)**: third-party only, YouTube normalizes playback |
| Safe zone | Keep text and faces central. Top ~200 px and bottom ~480 px are covered by UI, plus a right-side action column | **(unverified)**: figures vary by guide; use Google's official overlay if one can be found |

**Implications for the editor**
- The project canvas is fixed at 1080×1920 (no aspect-ratio menu needed, which simplifies a lot).
- Show a **hard timeline limit at 3:00** and a **warning at 1:00** when a non-library/copyrighted music track is present.
- Show a **toggleable safe-zone overlay** in the viewer.
- Export has **one preset that matches YouTube's recommendation**, plus maybe a "high quality" variant. No codec matrix.

---

## 3. What creators say drives retention (and what that means for features)

Mostly from creator-marketing blogs, so treat the numbers as rough. The *direction* is consistent across sources.

- **Hook:** cut the first 2–3 seconds of preamble. A visual hook beats a verbal intro. The hook must match the payoff.
- **Captions:** hard-coded captions visible from frame 1 are repeatedly recommended for sound-off viewers. One claimed lift of 25–40% **(unverified)**.
- **Looping:** short Shorts that loop seamlessly can exceed 100% retention (replays). The editor can help by **previewing the end→start transition in a loop**.
- **Length:** the suggested sweet spot varies (20–35 s, 15–50 s). There is no official target.
- **Diagnosis:** find the first steep drop in the Studio retention curve and change one variable at a time. This already exists in `channel_lab` (retention-cliff detection), which is a natural integration point later.

---

## 4. The reference tools — what each contributes

### 4.1 CapCut (Desktop for Mac)
The closest model for UX and feature set. Free core, Pro subscription for AI features, credits and premium templates.

| Feature | Notes |
|---|---|
| **Auto captions** | Captions → Auto captions → pick language → Generate. Large library of animated caption styles. Accuracy drops with poor audio. Free-tier limits disputed. |
| **Templates** | Caption and effect templates aimed at Shorts/Reels/TikTok. One source ranks Auto Captions, Templates, Background Removal and Beat Sync as the most used features **(unverified, low-authority source)**. |
| **AutoCut / remove silences** | Trims dead air and splits scenes. |
| **Auto reframe** | Keeps the subject centered when changing aspect ratio. |
| **Beat sync** | Places cuts on music beats. Guides advise manual review. |
| **Speed / Curve speed** | Speed ramps with presets (Hero, Bullet, Jump Cut, Flash In/Out). |
| **Keyframes** | Position/scale/rotation/opacity animation. |
| **Background removal** | AI cutout (Pro). Chroma key as a free alternative. |
| **Text to speech / AI voice** | Voiceover generation. |
| **Stickers, effects, transitions, filters** | Large asset libraries. Mostly breadth rather than impact. |

**What to copy:** a single-window layout (media/assets left, viewer centre, inspector right, timeline bottom), one-click AI helpers, caption styles as presets.
**What not to copy:** asset-store breadth, cloud and credit model, account requirements.

### 4.2 Final Cut Pro 11 (Apple, native macOS)
The model for **Mac-native quality, performance and editing ergonomics**.

| Feature | Notes |
|---|---|
| **Magnetic Timeline** | Trackless editing. Clips ripple and close gaps automatically. Connected clips (titles, B-roll, music) attach to the primary storyline and move with it. Excellent fit for Shorts, where the A-roll is a single talking/main storyline. |
| **Transcribe to Captions** (new in 11) | On-device transcription into timeline captions. Requires macOS Sequoia. |
| **Smart Conform** | Auto-reframes to vertical/square by tracking the subject. |
| **Magnetic Mask** (new in 11) | Isolates people/objects without green screen. |
| **Skimming, J/K/L, blade, ripple** | Keyboard-driven speed. |

**What to copy:** primary storyline + connected clips model, keyboard-first editing (J/K/L, I/O, B for blade, ⌫ ripple delete), smooth playback via AVFoundation/Metal, Apple-native look.

### 4.3 DaVinci Resolve 20 (Cut page)
The model for **speed workflows and transcript-based editing**.

| Feature | Notes |
|---|---|
| **Cut page** | A streamlined page for fast-turnaround edits. Proof that a reduced UI is a valid product. |
| **Text-based editing / transcripts** | Edit the video by deleting words in the transcript. |
| **AI IntelliScript** (Studio) | Builds a timeline from a script by matching takes. |
| **AI subtitles + animated subtitles** | Native karaoke-style captions in v20 (no Fusion template needed). Studio vs free split disputed. |
| **Smart Reframe** | Listed as a Resolve tool. Version availability unconfirmed. |
| **Voice isolation, audio ducking** | Fairlight tools. |

**What to copy:** **transcript editing** (delete a sentence in text → the clip is cut), the "reduced page" philosophy.
**What not to copy:** the page-switching complexity, node-based colour and compositing.

### 4.4 Feature matrix — consensus "must-haves"

| Capability | CapCut | FCP 11 | Resolve 20 | → TheShortsEditor |
|---|:-:|:-:|:-:|---|
| Auto captions with word timing | ✅ | ✅ | ✅ | **P0** |
| Animated caption styles | ✅ | ~ | ✅ | **P0** |
| Split / trim / ripple delete | ✅ | ✅ | ✅ | **P0** |
| Silence / dead-air removal | ✅ | ~ (plugins) | ✅ | **P0** |
| Vertical reframe (manual + auto) | ✅ | ✅ | ✅ | **P0 manual, P1 auto** |
| Text overlays / titles | ✅ | ✅ | ✅ | **P0** |
| Music track + ducking | ✅ | ✅ | ✅ | **P0** |
| Transcript-based editing | ~ | ~ | ✅ | **P1** (very high leverage) |
| Keyframes (pos/scale/opacity) | ✅ | ✅ | ✅ | **P1** |
| Speed change / ramps | ✅ | ✅ | ✅ | **P1 constant, P2 ramps** |
| Beat sync | ✅ | ~ | ~ | **P2** |
| Background removal / person mask | ✅ (Pro) | ✅ | ✅ | **P2** |
| TTS voiceover | ✅ | ✗ | ✅ | **P3 / maybe never** |
| Large stickers/effects/transitions library | ✅ | ✅ | ✅ | **Skip** (a few basic transitions only) |
| Multicam, colour nodes, Fusion, 3D | ✗/✅ | ✅ | ✅ | **Skip** |

---

## 5. Proposed feature set (the "20%")

### P0 — MVP: can make and publish a good Short end to end
1. **Project = one Short**, fixed 1080×1920 canvas, 30 fps default (60 fps optional), 3:00 hard cap.
2. **Import** video/audio/images via drag-and-drop (MOV, MP4, HEVC, ProRes from iPhone/camera). iPhone vertical and horizontal footage both handled.
3. **Viewer** with play/pause, J/K/L, frame stepping, **safe-zone overlay**, and a loop-playback toggle.
4. **Timeline**: magnetic primary storyline (A-roll) + connected lanes for B-roll/overlays, text, captions and music. Split (blade), trim, ripple delete, drag-reorder, snapping, zoom.
5. **Fit/fill/crop** for each clip into 9:16 (scale + position).
6. **Auto-captions** (on-device) with word-level timestamps, a transcript editor to fix words, **3–5 caption style presets** (incl. word-by-word highlight), position within the safe zone. Italian + English at minimum.
7. **Remove silences** with a threshold + padding slider, preview, and undoable result.
8. **Text overlay** (hook title) with a handful of styles, plus fade/pop-in.
9. **Audio**: clip volume, fades, background music lane with **auto-ducking under speech**, loudness normalization on export.
10. **Export**: one YouTube-Shorts preset (H.264/HEVC MP4, 1080×1920, AAC 48 kHz, Fast Start), progress bar, background export.
11. **Pre-export checks**: duration > 3:00, music on a > 1:00 Short (Content ID risk), text outside the safe zone, silent first second, low-volume audio.
12. **Undo/redo everywhere**, autosave, crash-safe project files.

### P1 — Makes it noticeably better than "just good enough"
- **Transcript-based editing** (delete words → cut video). Filler-word ("ehm", "cioè", "um") detection.
- **Keyframes** for position/scale/opacity (Ken Burns zoom, punch-in on emphasis).
- **Auto-reframe** of horizontal footage to 9:16 by tracking face/person (Vision), with a smoothed crop path the user can adjust.
- **Punch-in zoom** as a one-click jump-cut helper.
- **Constant speed change** (0.5×–3×) with pitch preservation.
- A small set of transitions (cut, crossfade, zoom/whip). Most Shorts use hard cuts.
- **Loop preview**: play the last second into the first to tune a seamless loop.
- **Brand kit**: saved caption style, fonts, colours, logo/watermark, outro.

### P2 — Nice to have
- Beat detection + snap cuts to beats.
- Speed ramps.
- Person segmentation (background blur/replace).
- Voice isolation / noise reduction.
- Basic colour: exposure/contrast/saturation/temperature + a couple of LUTs.
- Thumbnail/cover frame picker.
- Templates (saved project skeletons: hook → body → CTA).

### Out of scope (deliberately)
Horizontal or long-form editing, multicam, node-based colour, compositing/3D, a stock-asset store, cloud accounts, collaboration, Windows/iOS, direct upload to YouTube (maybe later, via the existing OAuth knowledge from `channel_lab`).

---

## 6. macOS technology mapping

| Need | Apple framework / approach | Notes |
|---|---|---|
| App/UI | **SwiftUI** (+ AppKit where needed: timeline canvas, key handling, NSView-backed player) | SwiftUI alone struggles with a high-performance, densely interactive timeline. Plan an AppKit or Canvas/Metal-backed timeline view. |
| Edit model → playback | **AVFoundation**: `AVMutableComposition` (tracks/time ranges), `AVVideoComposition` (layer instructions), `AVPlayer` | Rebuild the composition from the app's own model, never treat AVFoundation objects as the source of truth. |
| Effects / text / captions rendering | **Custom compositor** (`AVVideoCompositing`) with **Core Image / Metal** | The same render path for preview and export guarantees WYSIWYG. Apple's AVCustomEdit sample is the reference pattern. |
| Export | `AVAssetWriter` (full control over bitrate, Fast Start) or `AVAssetExportSession` | `AVAssetWriter` is needed to hit YouTube's recommended settings precisely. |
| Transcription | **SpeechAnalyzer / SpeechTranscriber** (macOS 26, on-device, word timestamps) | Verified 2026-11-07 on the dev Mac (macOS 27.2): `SpeechTranscriber.supportedLocales` includes en-*, it-IT/CH, de-DE/AT/CH, fr-FR/BE/CA/CH. |
| Silence detection | Audio RMS/energy analysis via `AVAssetReader` + Accelerate (vDSP), or `SpeechDetector` VAD | Simple, deterministic, fast. |
| Auto-reframe | **Vision**: face rectangles, person segmentation, saliency, and object tracking | Smoothing the crop path (e.g. a critically damped spring or a Kalman filter) is the real work. |
| Beat detection | Accelerate FFT onset detection | P2. |
| Audio mixing / ducking | `AVAudioMix` with volume ramps, or `AVAudioEngine` for live preview effects | Loudness measurement (EBU R128) has to be implemented or taken from a library. |
| Persistence | Codable project document (`FileDocument`/`ReferenceFileDocument`, a package bundle) | Media referenced by bookmark, not copied (optionally a "consolidate" step). |

**Minimum macOS target:** a decision for you. macOS 26 unlocks SpeechAnalyzer and the newest SwiftUI. Supporting macOS 15 means a different transcription engine. Apple Silicon only is a reasonable simplification.

---

## 7. Good practices for building an excellent editor like this

### 7.1 Architecture
- **Non-destructive, model-first.** The project is a pure value-type model (clips, time ranges, effects, captions, keyframes). AVFoundation objects are *derived* from it on change. Source media is never modified.
- **Rational time everywhere.** Use `CMTime` (or an integer frame/rational type) in the model, never `Double` seconds, to avoid drift and off-by-one-frame bugs.
- **One render path.** Preview and export share the same compositor so what you see is what you export.
- **Command pattern for every edit.** Each edit is a reversible command → reliable undo/redo, a testable edit log, and possible macro/"auto-edit" features (silence removal = a batch of commands).
- **Structured concurrency.** Heavy work (transcription, waveform, thumbnails, silence analysis, export) runs off the main thread in cancellable tasks with progress. The UI never blocks.
- **Caching:** waveform peaks, filmstrip thumbnails and transcripts are cached per media file (keyed by a content hash) so reopening a project is instant.
- **Modular packages:** `EditorCore` (model + commands, no UI, fully unit-tested), `RenderEngine` (AVFoundation/Metal), `Analysis` (speech, silence, vision), `App` (SwiftUI/AppKit). The core can then be tested without a GUI.

### 7.2 UX
- **Opinionated defaults:** the app already knows the target (a Short), so there are no format dialogs. Open → drop clips → edit → export.
- **Keyboard-first** with FCP/CapCut-familiar shortcuts (Space, J/K/L, I/O, B/⌘B split, ⌫ ripple delete, ⌘Z), all discoverable in menus.
- **Follow the Apple Human Interface Guidelines:** native menus, settings window, toolbar, dark mode, full-screen, standard document behaviour (autosave, versions, recent files).
- **AI as a suggestion, never a black box:** silence removal, captions and auto-reframe show a preview and produce normal, editable timeline items. Everything is undoable.
- **Honest warnings** (in the `channel_lab` spirit): flag Content ID risk, safe-zone violations and a weak first second, but never block the user.
- **Accessibility:** VoiceOver labels on controls, keyboard navigation, sufficient contrast, respect Reduce Motion.

### 7.3 Performance
- Target **real-time 1080×1920 playback with captions + 2 overlays** on a base M1. Measure it from day one.
- Use HEVC/H.264 hardware decode via VideoToolbox (the default with AVFoundation). Consider proxy generation only if real-world footage (4K HEVC 10-bit) stutters.
- Use Instruments (Time Profiler, Metal System Trace) and add signposts (`os_signpost`) around render and analysis.

### 7.4 Reliability and data safety
- Autosave + atomic writes. The project file should never be corrupted by a crash mid-save.
- Security-scoped bookmarks to media so projects survive app restarts in the sandbox. Handle "media offline" gracefully (relink).
- Versioned project format with migrations from the first release.

### 7.5 Quality
- **Unit tests** for `EditorCore` (time math, ripple logic, command undo/redo, caption chunking, silence detection on fixture audio).
- **Golden-frame render tests:** render specific frames of a fixture project and compare against reference images with a tolerance.
- **Export validation tests:** check the output with `AVAsset`/`ffprobe` for resolution, fps, codec, Fast Start and duration.
- A UI test smoke path: open → import → caption → export.
- CI on GitHub Actions macOS runners. SwiftLint + swift-format.

### 7.6 Distribution, privacy, legal
- **App Sandbox + Hardened Runtime**, signed with a Developer ID and **notarized** (outside the App Store) or shipped through the Mac App Store.
- **On-device by default:** no account and no upload of user footage. This is a real differentiator against CapCut.
- Fonts and any bundled music/sounds must be properly licensed for redistribution and for use in published videos. Prefer open-licence fonts (SIL OFL).
- **Don't clone CapCut's branding, assets or look.** Take inspiration from workflows, not from trade dress.

---

## 8. Decisions (2026-11-07)

1. **Minimum macOS: 26**, Apple Silicon only. On-device `SpeechAnalyzer` for transcription.
2. **Distribution:** a personal tool first; later a **.dmg** to share. Sharing without Gatekeeper warnings needs a paid Apple Developer account (Developer ID signing + notarization). Until then, recipients must right-click → Open / allow in System Settings.
3. **Caption languages:** English, Italian, German, French (all supported on-device, verified).
4. **Footage:** varied, so support talking-head, B-roll and music-driven Shorts. **Ease of use is a top requirement**: every feature must be reachable without knowing editing jargon, with sensible defaults and one-click actions.
5. **`channel_lab` integration:** _pending_.
6. **UI:** SwiftUI app with an AppKit/Metal-backed timeline and player view where SwiftUI is too slow.

---

## Sources

**YouTube (official)**
- [Understand three-minute YouTube Shorts — Google Support](https://support.google.com/youtube/answer/15424877?hl=en)
- [Manage Shorts as a rights holder — Google Support](https://support.google.com/youtube/answer/13053317)
- [YouTube recommended upload encoding settings — Google Support](https://support.google.com/youtube/answer/1722171?hl=en)
- [Video and audio formatting specifications — Google Support](https://support.google.com/youtube/answer/4603579?hl=en)

**YouTube Shorts specs and retention (third-party)**
- [Hopper HQ — YouTube Shorts dimensions](https://www.hopperhq.com/blog/youtube-shorts-dimensions/)
- [Recast Studio — Shorts size](https://recast.studio/blog/youtube-shorts-dimension)
- [PostEverywhere — Shorts aspect ratio & safe zones](https://posteverywhere.ai/blog/youtube-shorts-aspect-ratio)
- [Postlink — Shorts size and safe zones](https://postlinkapp.com/blog/youtube-shorts-size-and-dimensions)
- [Somake — Shorts aspect ratio](https://www.somake.ai/blog/youtube-shorts-aspect-ratio)
- [Shortimize — Shorts retention rate](https://www.shortimize.com/blog/youtube-shorts-retention-rate)
- [Aibrify — Shorts retention curve playbook](https://aibrify.com/blog/youtube-shorts-retention-curve-playbook)
- [TubeAnalytics — Shorts retention guide](https://www.tubeanalytics.net/blog/youtube-shorts-retention-guide)
- [Toptal — Shorts length](https://www.toptal.com/creator/post/youtube-shorts-length)
- [Subscribr — Shorts copyright guide](https://subscribr.ai/p/youtube-shorts-copyright-guide)

**CapCut**
- [CapCut for Mac (official)](https://www.capcut.com/resource/download-capcut-for-mac)
- [CapCut — AutoCut (official)](https://www.capcut.com/resource/autocut-for-videos)
- [Primal Video — CapCut desktop tutorial 2026](https://primalvideo.com/guides/capcut-for-pc-mac-tutorial/)
- [Typito — CapCut auto captions](https://typito.com/blog/capcut-auto-captions-add-subtitles-in-capcut/)
- [BIGVU — CapCut Desktop review 2026](https://bigvu.tv/blog/capcut-desktop-review-2026-features-pricing-smart-alternatives/)
- [Pixflow — AI captions in Premiere, CapCut, Resolve](https://pixflow.net/blog/ai-automatic-captions-subtitles/)
- [Epidemic Sound — What is CapCut](https://www.epidemicsound.com/blog/what-is-capcut/)
- [FreeAcademy — CapCut AI features 2026](https://freeacademy.ai/blog/capcut-ai-features-complete-guide-review-2026)
- [Edit with Zakir — CapCut hidden features 2026](https://edit-with-zakir.blogspot.com/2026/05/hidden-features-of-capcut-you-never.html)
- [CapCut features (third-party ranking)](https://capcut-site.pages.dev/capcut-features)

**Final Cut Pro**
- [Apple Newsroom — Final Cut Pro 11](https://www.apple.com/newsroom/2024/11/final-cut-pro-11-begins-a-new-chapter-for-video-editing-on-mac/)
- [9to5Mac — Final Cut Pro 11 released](https://9to5mac.com/2024/11/13/apple-releases-final-cut-pro-11-with-spatial-video-editing-ai-captions-and-more/)
- [CineD — FCP 11 Magnetic Mask & Transcribe to Captions](https://www.cined.com/final-cut-pro-11-introduced-magnetic-mask-transcribe-to-captions-more/)

**DaVinci Resolve**
- [Blackmagic — DaVinci Resolve 20 New Features Guide (PDF)](https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_20_New_Features_Guide.pdf?_v=1745391610000)
- [Blackmagic Design announces DaVinci Resolve 20](https://secure.businesswire.com/news/home/20250404998243/en/Blackmagic-Design-Announces-DaVinci-Resolve-20)
- [Envato — Everything new in Resolve 20](https://elements.envato.com/learn/davinci-resolve-20)
- [Blitzcut — Resolve text-based editing](https://blitzcutai.com/blog/davinci-resolve-text-based-editing)
- [HeyEddie — AI tools in Resolve 21](https://www.heyeddie.ai/learn/davinci-resolve/21/ai-tools-in-davinci-resolve)

**Apple developer technologies**
- [WWDC25 — SpeechAnalyzer (session 277)](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Addpipe — A quick look at SpeechAnalyzer](https://blog.addpipe.com/apple-speechanalyzer-api/)
- [Apple — AVCustomEdit sample (custom compositor)](https://developer.apple.com/library/archive/samplecode/AVCustomEdit/Listings/ReadMe_md.html)
- [WWDC20 — Edit and play back HDR video with AVFoundation](https://developer.apple.com/videos/play/wwdc2020/10009)
- [Apple — Applying matte effects to people (Vision)](https://developer.apple.com/documentation/vision/applying-matte-effects-to-people-in-images-and-video.md)
- [auto-vertical-reframe (reference logic, Python)](https://github.com/KazKozDev/auto-vertical-reframe)
