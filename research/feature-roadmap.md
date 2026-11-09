# Feature roadmap: from good Shorts editor to CapCut substitute

_Written 2026-11-09. Distilled from `capcut-reverse-engineering.md` (what CapCut has), `shorts-creator-tools-research.md` (what creators use, gap table §5) and `shorts-editor-research.md` (YouTube's rules). This is the build list. **Building starts only when the user asks.**_

---

## 1. What "substitute" means

A creator can stop opening CapCut when every Short they make can be finished in Shorts Editor, at least as fast. In the research, almost every Short is one of these:

| Kind of Short | Share of the work it needs |
|---|---|
| **Talking head** (tips, story, opinion) | cut pauses and filler words, punch-in zooms, captions, hook title, B-roll, music low |
| **Footage + voice or text** (vlog, travel, faceless, like your own CapCut Short) | horizontal footage made vertical (blurred background or reframe), images, own fonts, music, speed |
| **Two videos at once** (reaction, gameplay, before/after) | a second video track, a top/bottom layout |

So the target is: **those three kinds, end to end, with no CapCut feature missed.** Anything that doesn't serve one of them is in the "not building" list (§5).

**Already done** (stages 1–7): import, magnetic timeline, multi-select, Fill/Show all, auto-captions (5 styles), titles (5 styles), Remove Pauses, clip volume, music with ducking and fades, −14 LUFS, YouTube-ready export with checks, save/autosave/missing media.

---

## 2. The 20%: twelve features

Ranked by how much of the result each delivers. Each one is something a CapCut user would miss within the first few Shorts, and almost all can run on the Mac with Apple frameworks (no cloud, no credits).

| # | Feature | Why it's in the 20% | Serves |
|---|---|---|---|
| 1 | **Hands-on timeline**: drag clips to reorder, drag edges to trim, snapping, trim to playhead (Q/W), filmstrip + sound waveform on clips | The basic expectation of any editor. Without it the app feels like a tool, not an editor. Everything else is used through it. | All |
| 2 | **Second video track** (overlay): B-roll, picture-in-picture, images on top, with its own length/position | CapCut's "Overlay" is one of its four most-used core tools. B-roll every few seconds is the main retention technique after cuts. | All |
| 3 | **Images as clips** (JPEG, PNG, HEIC, AVIF, WebP) with an optional slow zoom | Used in your own CapCut Short. Needed for faceless Shorts, screenshots, proof shots. | Footage, faceless |
| 4 | **Framing in the viewer**: drag to move, pinch/drag corners to resize, rotate; **blurred background** behind "Show all"; **punch-in** (one click, ~120%), with "alternate on every cut" | Blurred background is what you did in CapCut. Punch-in on alternate cuts is the standard way to hide jump cuts in talking heads. Direct dragging is how CapCut feels. | All |
| 5 | **Zoom and move over time** (keyframes underneath, presets on top): "Zoom in on this moment", "Slow push in", "Pan left/right", "Shake" | Zooming on a key word is the second most cited emphasis technique. Presets keep it one click; keyframes come free for position/scale/opacity/volume. | Talking head, footage |
| 6 | **Speed**: per clip 0.25×–4× with voice pitch kept, presets (0.5×, 1.5×, 2×), "smooth slow motion" later | Speeding up dull parts and slow-mo for impact are in every Shorts guide. CapCut's Speed tab is one of its main tabs. | All |
| 7 | **Text you can design**: your own and installed fonts, colour, outline, shadow, background box, size, free X/Y placement, several texts at once on their own rows, more animations (typewriter, slide, zoom), **saved styles** (brand kit) | Text is CapCut's most-used tool. Your Short used EB Garamond with an outline plus a second text (call to action). Saved styles make every Short look like your channel. | All |
| 8 | **Captions that pop**: highlight key words (automatic with Apple's on-device language model, or click a word), font/colour/size per style, drag to any position, emoji option, word-by-word animations | Captions are the #1 AI feature in CapCut. Keyword colour and emojis are what makes the current trend look (Submagic/Hormozi style). | All |
| 9 | **Edit by text**: the transcript as a document; delete words or sentences to cut the video; one click **removes filler words** ("um", "uh", "ehm", "cioè", "äh", "euh"…) and repeated takes | The fastest way to cut a talking head, and a CapCut highlight feature. Transcripts and word timings already exist, so this is mostly UI. | Talking head |
| 10 | **Sound layer**: a sound effects lane (drop any sound anywhere, own volume), a small built-in set of royalty-free effects (whoosh, pop, ding, riser, click, swoosh), **voice-over recording** at the playhead, **voice clean-up** (Apple Voice Isolation) on clips | Sound effects on text and cuts are standard in Shorts. Voice-over is needed for faceless Shorts. Most creators record with cheap mics, so clean-up is a big quality jump. | All |
| 11 | **Auto reframe**: horizontal footage becomes vertical by following the face or subject (Vision), smoothed, with a manual override | Long-form clips and podcasts are a big source of Shorts. CapCut does this locally; so can we. | Talking head, footage |
| 12 | **Layouts**: top/bottom split and picture-in-picture corner, one click, built on the second video track | Reaction, gameplay, before/after and comparison Shorts all use them. | Two videos |

Why these twelve and not others: they cover the three kinds of Short completely and include CapCut's most-used tools (Text, Overlay, Auto captions, Extract audio → sound layer, AutoCut → edit by text/Remove Pauses). The rest of CapCut's list is either rarely used for Shorts or cloud AI that is a separate product.

---

**Progress:** features 1–5 built on 2026-11-09 (one batch, see `STATUS.md`). Next: 6–12, when the user asks.

## 3. Build order

Grouped into stages the size we've been doing (each: model + tests in EditorCore, rendering in RenderEngine, UI, then an on-screen check). Each stage leaves the app better on its own.

| Stage | Contents (feature #) | Done when… | Size |
|---|---|---|---|
| **8. Timeline you can touch** | #1 | Clips can be reordered and trimmed by dragging, with snapping to the playhead, other edges and titles; Q/W work; clips show a filmstrip and waveform; all undoable. | M |
| **9. Framing** | #4, #3 | A clip can be moved/resized/rotated in the viewer with handles and guides; "Show all" offers Black / Blurred / Colour background; one-click punch-in and "alternate on cuts"; images import and play as clips. | M |
| **10. Text design** | #7 | Titles take any font (installed or imported into the project), colour, outline, shadow, box, size; drag anywhere; several rows of titles; 3 more animations; styles can be saved and reused across Shorts. | M |
| **11. Captions that pop** | #8 | Key words highlighted automatically or by clicking; caption font/colour/size; drag caption position; emoji option; per-word pop animation. | M |
| **12. Edit by text** | #9 | A transcript view where deleting words cuts the video (one undo step), filler words and repeated takes are found and removed in one click, in the 4 caption languages. | M |
| **13. Sound layer** | #10 | Sound effects lane with a built-in set and own files; voice-over recording with a countdown; voice clean-up switch per clip; ducking also lowers music under voice-over. | M |
| **14. Second video track** | #2, #12 | B-roll/overlay clips on a track above the main one, with position/size/opacity; top/bottom and corner layouts in one click. | L |
| **15. Speed and motion** | #6, #5 | Per-clip speed with pitch kept (captions and pauses follow); zoom/pan/shake presets; keyframes for position, scale, opacity and volume with ease in/out. | L |
| **16. Auto reframe** | #11 | "Follow the subject" on any horizontal clip, smoothed, with a strength setting and manual correction. | M |

Order rationale: 8 makes every later stage easier to use; 9–10 close the gaps visible in your own CapCut Short; 11–13 are the biggest retention wins and reuse existing pieces (captions, transcripts, audio mix); 14–15 change the timeline and composition model the most, so they come once the rest is stable; 16 builds on 9's transform and 15's motion.

---

## 4. Next 20% (after the twelve)

Worth doing once stages 8–16 are in, roughly in this order:
1. **Markers and beats**: M to mark, beat detection on the music, snap cuts to beats.
2. **Looks**: 8–10 filter presets and basic adjustments (exposure, contrast, saturation, warmth) with Core Image; apply to all.
3. **A few quick transitions** (cross dissolve, zoom, whip, flash) and **effects** (shake, flash, blur).
4. **Loop preview** of the end→start join; **cover frame** picker on export.
5. **Long video → Shorts**: transcript + on-device language model suggests 30–60 s moments; each becomes a Short with captions and reframe.
6. **Remove background** (Vision person segmentation) for green-screen-style reactions.
7. Text to speech (system voices), stickers/arrows/emoji, templates (save a Short's structure), copy/paste clip settings, SRT import/export, freeze frame, reverse, stabilize.

---

## 5. Not building

| CapCut feature | Why not |
|---|---|
| AI avatars, lip sync, dubbing/translation, script-to-video, generative video/backgrounds/music/stickers | Cloud and paid, a different product, often watermarked "AI generated" |
| Retouch/beauty, relight, eye contact, body effects | Low value for most Shorts, heavy models |
| Asset store (hundreds of effects, stickers, templates, music library) | Breadth, not impact; licensing; YouTube's own audio library is the safe music source |
| Several timelines, compound clips, groups, multi-cam | Too complex for a 3-minute vertical video |
| Aspect ratios other than 9:16, 4K/8K, ProRes, 60 fps, HDR | Decided: fixed 1080×1920 30 fps for YouTube Shorts |
| LUTs, curves, HSL, colour wheels, scopes | Pro grading; filters + basic adjustments cover Shorts |
| Accounts, cloud drafts, team spaces | Personal Mac tool |

---

## 6. Rules that apply to every feature

These are what make it "staggering" rather than just complete, and where CapCut is weak:
- **One click with a good default, details on demand.** Every feature works with one click (punch-in, blurred background, remove filler words, clean up voice); sliders are there for those who want them.
- **On the Mac, free, no uploads.** Vision, Speech, Core Image, AVFoundation, Apple's on-device language model and sound isolation. No credits, no waiting in a queue.
- **Shorts-aware.** Every feature knows about the 3:00 limit, the areas YouTube covers, sound-off viewers and the first seconds (warnings, safe placement, defaults).
- **Native Mac.** Every command in a menu with its shortcut, undo for everything, media that survives being moved, plain words (no "linkage", "adsorb", "compound clip").
- **Everything follows edits.** Captions, titles, sound effects, zooms and B-roll stay attached to what they belong to when clips are split, trimmed, moved or sped up, as captions already do.
