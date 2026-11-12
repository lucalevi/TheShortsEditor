# What Shorts creators actually use

_Research date: 2026-11-09. Companion to `capcut/capcut-bundle-analysis.md` (what CapCut has) and `shorts-editor-research.md` (platform rules, first P0 list). This file answers: **which of CapCut's tools matter for YouTube Shorts, and in what order should Shorts Editor get them?**_

**How reliable this is.** No independent, methodologically sound survey of Shorts creators' tools was found. Most 2026 material comes from CapCut's own blog, competing vendors (Opus Clip, Submagic, Splice) or affiliate sites. Below, numbers from such sources are marked **(vendor)** or **(unverified)**. Patterns that many independent guides repeat are treated as reliable; exact percentages are not.

---

## 1. Who uses what

- **CapCut is the default short-form editor.** Every source names it first. Claimed shares range from 54% to 85% of short-form creators, all from unverified or vendor sources (Splice cites "about 68% of professional TikTok creators", Voxbooster 54%). MIDiA Research describes CapCut as dominant among intermediate and advanced creators, fed by TikTok.
- Counter-signal: a creator-gear database found CapCut in only 6 of 221 YouTube creators with verified software (3%). Bigger YouTube channels mostly use Premiere Pro, Final Cut Pro or DaVinci Resolve, and use CapCut-like tools for the Shorts. **(unverified)**
- **AI "clippers" are a second tool category**: Opus Clip (long video → Shorts), Submagic (styled captions, auto zooms, B-roll, sound effects in one pass). Creators often chain them: Opus to find clips, Submagic to polish. **(vendor)**
- **YouTube's own Shorts editor** keeps growing (2025: timeline with zoom/snap, reorder, timed text, music layering, beat sync, AI stickers, templates; "Edit with AI"; 2026: a Gemini chat editor announced that can remove pauses, reorder, sync music and add text, timing unclear). It is phone-only and basic, but sets the floor of what feels "normal".

## 2. Which CapCut features creators use most

The best available usage data is CapCut's own 2025 report (via Advertising Week, platform-wide, not Shorts-specific):

| Most used | Features |
|---|---|
| Core tools | **Text**, **Effects**, **Extract audio**, **Overlay** (picture-in-picture) |
| AI tools | **Auto captions**, **AutoCut**, **Voice filter**, **Text-to-speech** |

Shorts-specific guides add: **Long video to shorts**, **beat sync**, **auto reframe**, **remove background**, **speed ramps**, **keyframe zooms**, **templates**. One older low-authority source ranked Auto captions, Templates, Background removal and Beat sync as the four most used. **(unverified)**

## 3. Editing techniques that keep viewers watching

Repeated across many independent guides (Splice, Opus, Subscribr, Schedulala, NoteLM, Flowshorts and others). These describe *what the editor must make fast*:

| Technique | What creators do | Tool it needs |
|---|---|---|
| **Hook in the first 1–3 s** | No intro. Start mid-action, put a text hook on screen, often a bold claim. | Trim the head fast; title with a "pop" in; a check for a slow start (we have it) |
| **Cut every 2–3 s / frequent visual change** | Static shots lose viewers. Jump cuts, B-roll, angle changes. | Fast split/delete, silence removal, B-roll on a track above |
| **"Covering" jump cuts with a ~20% zoom** | Alternate between normal and punched-in framing on each cut so jump cuts don't look jarring. | **Punch-in zoom per clip** (one click), ideally automatic alternation |
| **Zoom on key words** | Quick zoom-in on a punchline or key word. | Keyframed scale / "zoom in" preset animations |
| **Word-by-word captions** | Large, centre, 1–3 words at a time, current word highlighted; keyword colour; sometimes emojis. Hormozi-style is "approaching saturation" **(vendor)** | Caption styles (we have 5), **keyword highlight**, emoji, custom font/colours |
| **Sound effects, used sparingly** | Whoosh on transitions, pop when text appears, riser before a reveal. | A **sound effects lane** and a small built-in library (or easy drag-in of your own) |
| **Music low under voice** | Rough targets: voice −6 to −3 dB, music −18 to −12 dB, effects −12 to −6 dB **(unverified)** | Ducking (we have it), loudness (we have −14 LUFS) |
| **Seamless loop** | End flows back into the start so rewatches count. | Loop preview of the end→start join |
| **Speed** | Speed up boring parts (1.2–2×), slow-mo for impact, speed ramps. | Per-clip speed with pitch kept, ramps later |
| **Vertical framing of horizontal footage** | Crop to the subject, or fit with a **blurred background**. | Auto reframe (Vision saliency/tracking), **blurred background** |
| **Avoid flashy transitions** | Star wipes etc. look amateur and slow the pace. Hard cuts, sometimes a quick zoom/whip. | Only a handful of quick transitions |

## 4. Common Shorts formats and what each needs

| Format | Typical edit | Features it relies on |
|---|---|---|
| **Talking head** (tips, opinion, story) | Jump cuts, punch-ins, captions, hook title, B-roll, music low | Remove pauses/filler words, punch-in zoom, captions, B-roll overlay |
| **Voice-over on footage / faceless** | Script read over stock, screen recording or B-roll | Voice-over recording, text-to-speech, captions, images |
| **Split screen / reaction / gameplay** | Two videos stacked (top/bottom), or a face over gameplay | **Layouts** (top/bottom split, picture-in-picture), crop per clip |
| **Before/after, transformation, comparison** | Side by side or a reveal, "6 months later" text | Split layout, titles, speed |
| **Countdown / list** | Numbered titles, quick cuts | Titles, templates |
| **Clip from a long video / podcast** | Find the best 30–60 s, reframe the speaker, captions | Import a long file, find moments (transcript search), auto reframe |
| **POV / non-verbal / aesthetic** | Music-driven, text on screen, beat cuts | Beat markers, cut to beat, titles, filters |
| **Your own Short (draft 1107)** | Horizontal walking footage on a blurred background, hook text in a serif font, CTA text, music from 24 s into the song | Blurred background, custom fonts, two free-positioned texts, images |

## 5. What Shorts Editor has today vs. CapCut

✅ done · 🟡 partial · ❌ missing. "Shorts value" is how much the feature affects a Short's result, from §2–§4.

| Area | Feature | Us | Shorts value |
|---|---|---|---|
| Timeline | Split, delete with gap closing, multi-select, undo, J/K/L, frame step | ✅ | — |
| | Drag clips to reorder, trim edges by dragging | ❌ (right-click Move only) | **High** (basic expectation) |
| | Delete left/right of playhead (Q/W), select range I/O | ❌ | High (fast trimming) |
| | Snapping, markers, beat markers | ❌ | Medium |
| | Several tracks: B-roll/overlay video above the main clips | ❌ | **High** |
| | Copy/paste clips and their settings | ❌ | Medium |
| | Filmstrip thumbnails, waveforms on clips | 🟡 (one thumbnail) | Medium |
| Framing | Fill / Show all | ✅ | — |
| | **Blurred background** behind "Show all" | ❌ | **High** (used in your own CapCut Short) |
| | Position / scale / rotation by dragging in the viewer | ❌ | **High** |
| | **Punch-in zoom** (e.g. 120%) per clip, alternating on cuts | ❌ | **High** |
| | Keyframes for zoom/position (Ken Burns, zoom on a word) | ❌ | High |
| | **Auto reframe** (follow the face/subject) | ❌ | High (horizontal sources, podcasts) |
| | Crop, flip, opacity | ❌ | Low–medium |
| | Layouts: top/bottom split, picture-in-picture | ❌ | Medium–high (reaction, gameplay, comparison) |
| Media | Images as clips (JPEG/PNG/HEIC/AVIF), with slow zoom | ❌ | **High** (you imported an AVIF in CapCut) |
| | Freeze frame, reverse | ❌ | Low–medium |
| Speed | Constant speed with pitch kept | ❌ | **High** |
| | Speed ramps / curves, smooth slow-mo | ❌ | Medium |
| Captions | Auto captions, word timing, 5 styles, positions, editing | ✅ | — |
| | **Keyword highlight**, colour/font choice per style | ❌ | High |
| | Emojis on captions | ❌ | Medium |
| | Caption animations (pop/bounce per word), size, drag position | 🟡 (pop only, 3 positions) | Medium–high |
| | Edit video by deleting words in the transcript, **remove filler words** | ❌ | **High** (talking heads) |
| | Import/export SRT | ❌ | Low–medium |
| | Translate captions | ❌ | Low (4 languages chosen) |
| Text | Titles: 5 styles, pop/fade, drag vertically | ✅ | — |
| | **Your own fonts**, colours, outline/shadow/background settings, size | ❌ | **High** (EB Garamond in your Short) |
| | Several texts at once on separate rows, drag anywhere (X and Y), rotate | 🟡 (one lane, Y only) | High (hook + CTA) |
| | More text animations (typewriter, slide, zoom), keyframes | ❌ | Medium |
| | Saved text styles ("brand kit") | ❌ | Medium |
| | Stickers / shapes / arrows / emoji | ❌ | Medium |
| Audio | Clip volume, music, ducking, fades, −14 LUFS | ✅ | — |
| | **Sound effects lane** (several sounds anywhere, each with volume) | ❌ | **High** |
| | Voice-over recording | ❌ | Medium–high (faceless) |
| | Noise reduction / voice clean-up (Apple Voice Isolation) | ❌ | High (cheap mics) |
| | Fades on clip sound, extract audio from video as its own item | ❌ | Medium |
| | Beat detection, cut to beat | ❌ | Medium |
| | Text to speech (system voices) | ❌ | Medium (faceless) |
| | Voice changer, AI music | ❌ | Low |
| Look | Filters (a few presets) and basic adjustments (exposure, contrast, saturation, temperature) | ❌ | Medium |
| | LUTs, curves, HSL, colour match | ❌ | Low |
| | Transitions (a few quick ones: cross dissolve, zoom, whip, flash) | ❌ | Low–medium |
| | Effects (shake, flash, blur, glitch) | ❌ | Low–medium |
| | Remove background (person cut-out), green screen | ❌ | Medium (reaction/tutorial formats) |
| | Stabilize | ❌ | Low–medium |
| | Retouch, relight, eye contact | ❌ | Low |
| AI | **Long video → Shorts** (find best moments) | ❌ | High for podcast/long-form channels |
| | AI avatars, script to video, generative backgrounds | ❌ | Skip |
| Export | YouTube-ready MP4, checks, loudness | ✅ | — |
| | Cover/thumbnail frame picker | ❌ | Medium (Shorts thumbnails are selectable on upload) |
| | Export still frame, export audio only, captions file | ❌ | Low |
| | 60 fps, 4K | ❌ | Low (decided: fixed 1080×1920 30 fps) |
| Project | Save, autosave, missing media | ✅ | — |
| | Templates (save a Short's structure and reuse it) | ❌ | Medium |

## 6. Suggested order (for when building starts)

Ranked by Shorts value ÷ effort, CapCut's usage data, the retention techniques above and **what you did in your own CapCut Short**. Grouped into stages of roughly the size we've been doing.

**P1: the gaps a CapCut user notices in the first five minutes**
1. **Timeline basics:** drag clips to reorder, drag edges to trim, snapping, delete left/right of playhead (Q/W), filmstrip + waveform on clips.
2. **Framing that looks good:** blurred background for "Show all"; move/zoom/rotate the clip by dragging in the viewer; one-click **punch-in** (e.g. 115–125%) with an "alternate on every cut" option.
3. **Images as clips** (JPEG/PNG/HEIC/AVIF), default 3 s, optional slow zoom.
4. **Speed** per clip (0.25×–4×, pitch kept, presets 0.5/1.5/2×).
5. **Text styling:** your own fonts (system + imported), colour, outline, shadow, background, size; X/Y dragging; several titles on separate rows; save a style.
6. **Captions upgrades:** keyword highlight (pick words, or automatic with on-device Foundation Models), colour/font per style, size, drag position.
7. **Edit by text:** delete words in the transcript to cut the video; one-click remove filler words ("um", "eh", "ehm", "allora"…) using the existing word timings.
8. **Sound effects lane** + voice-over recording; voice clean-up with Apple's Voice Isolation.

**P2: what makes Shorts feel produced**
9. **Overlay track** for B-roll / picture-in-picture, plus **layouts** (top/bottom split).
10. **Keyframes** for position/scale/opacity/volume, with ease presets; zoom presets ("zoom in on word").
11. **Auto reframe** of horizontal footage (Vision saliency + face tracking, smoothed).
12. **Markers and beats:** M to mark, beat detection on the music, snap cuts to beats.
13. **Filters and basic adjustments** (Core Image), a handful of **quick transitions** and **effects** (shake, flash, zoom blur).
14. **Loop preview**, cover frame picker, more text animations, emoji/stickers.

**P3: nice to have / later**
15. Long video → Shorts (transcript + on-device LLM to suggest moments), remove background (Vision person segmentation), text to speech, templates/brand kit, stabilize, speed ramps, LUTs, SRT import/export, colour match.

**Skip** (CapCut breadth with little Shorts value, or needing cloud AI): AI avatars, lip sync/translate dubbing, generative video/backgrounds/music, retouch/beauty, relight, eye contact, multi-timeline docking, cloud spaces/teams, 8K/ProRes export, 3D effects.

## 7. Where we can beat CapCut (not just copy it)

From creator complaints in reviews (paywall friction, laggy playback, desktop weaker than mobile, absolute media paths) and from the bundle analysis:
- **Free and on device**: captions, pause/filler removal, voice clean-up, reframe, background removal all run locally with Apple frameworks, with no credits and no uploads.
- **Shorts-only**: no ratio menu, no export matrix, checks for YouTube's rules (3:00, music over 1:00, covered areas). CapCut has loudness presets but no Shorts-specific warnings.
- **A real Mac app**: native menus, every command in a menu with its shortcut, undo that always works, media that survives moved files (bookmarks; CapCut stores absolute paths).
- **Plain language** instead of CapCut's jargon ("Linkage", "Adsorb", "Compound clip").

---

## Sources

Usage and market:
- [Revealing the Creative Trends on CapCut in 2025 (Advertising Week)](https://advertisingweek.com/revealing-the-creative-trends-on-capcut-in-2025/)
- [How CapCut is challenging Adobe Premiere Pro's dominance (MIDiA Research)](https://www.midiaresearch.com/blog/how-capcut-is-challenging-adobe-premiere-pros-dominance-of-the-video-editing-market)
- [What editor do TikTok creators use (Splice)](https://spliceapp.com/blog/what-editor-do-tiktok-creators-use-1)
- [Short-form video editing statistics 2026 (Voxbooster)](https://voxbooster.com/blog/short-form-video-editing-statistics-2026)
- [Best apps for editing short-form video content](https://affiliatemarketingforsuccess.com/affiliate-marketing/best-apps-for-editing-short-form-video-content/)
- [CapCut sees surge in everyday creator use (Net Influencer)](https://www.netinfluencer.com/capcut-sees-surge-in-everyday-creator-use-in-2025-as-ai-tools-drive-editing-adoption/)

Editing techniques and formats:
- [Mastering YouTube Shorts editing (Splice)](https://spliceapp.com/blog/mastering-youtube-shorts-editing-guide/)
- [Ideal YouTube Shorts length & format for retention (Opus)](https://www.opus.pro/blog/ideal-youtube-shorts-length-format-retention)
- [YouTube Shorts hook formulas (Opus)](https://www.opus.pro/blog/youtube-shorts-hook-formulas)
- [Quick editing tips for Shorts (Subscribr)](https://subscribr.ai/youtube-strategy/editing-youtube-shorts-more-engagement)
- [YouTube Shorts editing tips (Schedulala)](https://schedulala.com/blog/youtube-shorts-editing-tips-pro-techniques)
- [YouTube Shorts editing tips (NoteLM)](https://www.notelm.ai/blog/youtube-shorts-editing-tips)
- [Video editing tips (Flowshorts)](https://flowshorts.app/blog/video-editing-tips)
- [YouTube trends 2026 (Epidemic Sound)](https://www.epidemicsound.com/blog/youtube-trends-2026/)
- [Best YouTube Shorts video ideas (Flowshorts)](https://flowshorts.app/blog/best-video-ideas)
- [Best niches for faceless YouTube Shorts 2026 (GhostShorts)](https://ghostshorts.com/blog/best-niches-for-faceless-youtube-shorts-2026)
- [Viral Shorts structures for faceless channels (Virvid)](https://virvid.ai/blog/viral-shorts-structures-faceless-2026)

Tools and competitors:
- [CapCut PC version (CapCut)](https://capcut.com/resource/pc-professional-video-editor)
- [Keyframe animations (CapCut)](https://www.capcut.com/tools/keyframe-animation)
- [CapCut PC review 2026 (Atomi Systems)](https://atomisystems.com/screencasting/capcut-pc-review-2026-is-free-video-editing-really-worth-your-time/)
- [CapCut Pro vs Free 2026 (Vidpros)](https://vidpros.com/capcut-pro-vs-free/)
- [CapCut pricing 2026 (eesel)](https://www.eesel.ai/en/blog/capcut-pricing)
- [CapCut review (Toksta)](https://toksta.com/products/capcut)
- [CapCut review 2025 (quso.ai)](https://quso.ai/blog/capcut-review.html)
- [OpusClip vs Submagic vs Bytecap 2026](https://www.bytecap.io/blog/opusclip-vs-submagic-vs-bytecap-2026)
- [Submagic (Creator Economy Tools)](https://creatoreconomytools.com/tool/submagic)
- [Captions.ai vs Submagic vs Opus Clip](https://filmfont.pages.dev/articles/captions-ai-vs-submagic-vs-opus-clip)

YouTube's own editor and rules:
- [YouTube is updating the Shorts video editor (Engadget)](https://www.engadget.com/apps/youtube-is-updating-the-shorts-video-editor-to-make-it-a-better-alternative-to-tiktok-182932945.html)
- [Made on YouTube 2026 (Uppbeat)](https://uppbeat.io/blog/creator-news/made-on-youtube-2026-brings-new-youtube-tools-for-editing-earning-and-more)
- [YouTube will let creators edit Shorts by chatting with Gemini (PPC Land)](https://ppc.land/youtube-will-let-creators-edit-shorts-by-chatting-with-gemini-in-early-2027/)
- [How long can YouTube Shorts be (Riverside)](https://riverside.com/blog/how-long-can-youtube-shorts-be)
- Official platform rules: see `shorts-editor-research.md` §2.
