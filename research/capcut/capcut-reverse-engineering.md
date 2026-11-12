# CapCut, reverse engineered for Shorts Editor

_Written 2026-11-12. Step 1 of "give Shorts Editor CapCut's best features"; step 2 (building) starts when the user asks._

**The brief (user, 2026-11-12):** Shorts Editor keeps **iMovie's look and feel** (native Mac, quiet dark interface, one adjustments area, magnetic timeline, plain words) and gains **CapCut's features**. We copy what CapCut *does*, never how it looks, its names, assets, effects, fonts or models.

**Sources**
1. **CapCut 9.7.1 (build 297) for Mac, hands-on (2026-11-12).** A scratch project with two stock clips and a text: every clip-inspector tab, every library tab, the text inspector, speed, animation, adjust, captions, templates and the export window, read and screenshotted (`screens/`, Italian UI; labels are translated below with the Italian in brackets where it helps). Only clicks were used; nothing was exported or bought. The scratch project "1112" was moved to be deleted (see README).
2. **The CapCut bundle and its data** (`capcut-bundle-analysis.md`, from 2026-11-09): 17,769 UI strings, 857 screen names, the project file format, on-device models, preferences. Still valid: the version hasn't changed.
3. **Your two CapCut Shorts**, read from their project files: `1107` (2026-11-07) and `1111` "Studiare per la vita" (2026-11-11). See §2.
4. **capcut.com**: home, Tools index, Desktop pages, pricing, 32 help-centre articles and ~20 desktop how-to guides (notes: `capcut-web-notes.md`).
5. The default keyboard map with the Final Cut Pro and Premiere presets (`capcut-shortcuts-raw.txt`).

Lookup tables (every panel, preset list, free vs Pro, export, shortcuts) are in `capcut-reference.md`.

**About the ranking.** CapCut publishes no usage data. "Most used" below comes from where CapCut puts a feature (home screen, first tab, toolbar, single key), how much of its help centre it takes, what your own two Shorts used, and what a Short needs. The ranking is a judgement.

---

## 1. CapCut in one paragraph

A home screen pushes AI first (an "Omni agent" chat box, AI video/image generation, "Long video to shorts") above a **Create project** button and a grid of projects. The editor is one window in four parts: a **library** on the left with tabs (Media, Audio, Text, Stickers, Effects, Transitions, Captions, Filters, Adjustment, Templates, AI avatar), each a store of downloadable presets; an **inspector** that changes with the selection (Video / Speed / Animation / Adjust / AI style for a clip; Text / Animation / Tracking / Text to speech for a text); a **player**; and a **multi-track timeline** with a magnetic main track and free tracks above it for text, stickers, effects, filters and B-roll, and below it for sound. Almost every look is a tile you drag onto a clip or onto its own track. Most AI and many tiles are **Pro** (diamond badge), and the paywall only shows when you try to **export**.

---

## 2. What your own CapCut Shorts say you need

| | Short `1107` (7 Nov, 34.6 s) | Short `1111` "Studiare per la vita" (11 Nov, 14 s) |
|---|---|---|
| Footage | 4 horizontal 1920×1080 clips, **blurred background** | 2 vertical iPhone videos (MOV), 3 **pictures** (HEIC, WebP), some **zoomed 110 %** |
| Sound | One song, started 24 s into it | **A voice-over recorded in CapCut** ("Doppiaggio1", at 42 %) + a song kept **very low (3 %)** under it |
| Text | 2 titles: a hook and "Link in descrizione", your own font **EB Garamond Bold**, white with black outline | **14 short text items typed by hand**, one phrase each (0.2–2.8 s), timed to the voice-over, EB Garamond Bold, **emoji in the text** (😘 😉 🤑), ends with "LINK IN DESCRIZIONE!!!" |
| Canvas | 9:16 | **1188 × 1920, "Original" ratio**: CapCut took the shape from the first picture (360×582), so this "Short" isn't 9:16 |
| Not used | | Auto captions, animations, transitions, filters, effects (all present in CapCut) |

What this tells us:
1. **Your captions come from a voice-over, and you typed them by hand.** In CapCut 9.7.1 the auto-captions **Generate** button carries a **Pro** badge (screen 22), so you wrote 14 timed texts yourself. Shorts Editor makes captions for free, but **it doesn't transcribe voice-overs yet** (STATUS: "Voice-overs … aren't transcribed"). That is the single most valuable gap: record a voice-over, get punchy one-phrase captions in your font, timed automatically.
2. **Short phrases, one at a time, big, in your own font, with emoji.** We nearly have this: caption font, size and colours, One Word style, suggested emoji. Missing: a 2–4-word "phrase" page, splitting a caption where *you* want, and emoji typed into a caption.
3. **The voice-over is the main sound and the music is a bed.** Our ducking does this automatically; CapCut made you set 3 % by hand.
4. **Pictures and a little zoom.** We have pictures, Ken-Burns-like motion and Fill. ✅
5. **CapCut's "Original" ratio is a trap.** One small picture first and the Short isn't 9:16 any more. Our fixed 1080×1920 canvas is a feature to keep.

---

## 3. The 20 % that does 80 % of the work (hands-on)

What a CapCut user making a Short does most, in order. Every item is on the first screen of a panel, on the toolbar or on a single key.

| # | Action | How CapCut does it | Shorts Editor today |
|---|---|---|---|
| 1 | **Captions** | Captions tab ▸ Auto captions: spoken language, bilingual (Pro), "Identify filler words" (Pro), **Generate (Pro)**, "Delete current captions". Caption **templates** (animated presets: Trending, Classic, Word, Glow, Basic, Aesthetic…). Each caption is a text item: split a line with ↩, new line ⌘↩, style change "Apply to all" | ✅ On device, free, EN/IT/DE/FR, 5 styles, font/size/colours, key words + emoji, edit lines, drag up/down, Script panel. ❌ Voice-overs and B-roll not transcribed, no split/merge, no animated presets, no translation, no SRT |
| 2 | **Text on screen** | Text ▸ Default text (drag to a track) or text templates / text effects; inspector: font, size, B/U/I, case, colour, letter & line spacing, alignment, **28 preset looks** (outline, box, glow…), stroke, background, shadow, curve, opacity; Bubble; Effects; Animation In/Out/Loop; **Tracking** (Pro); **Text to speech** | ✅ Titles: 5 styles, 6 entrances, fonts (Add Fonts…), colours, saved styles, drag in viewer. ❌ No exits/loops, no presets grid, no bubbles, no tracking, no text to speech |
| 3 | **Cut and arrange** | Split ⌘K, Delete left/right Q/W, ripple delete, magnet, snapping S, linkage ⌘L | ✅ (iMovie grammar, stage A) |
| 4 | **Music and sound** | Audio tab: music library by mood (Phonk, Vlog, Fun, Fitness…), sound effects, your files, extract audio from a video, **record voice-over**; per clip volume, fades, normalize loudness, enhance voice, reduce noise, isolate voice (Pro), voice changer; **beats** | ✅ Mood music made by the app, 7 effects, voice-over, ducking, −14 LUFS, clean voice, voice effects, volume line. ❌ **Beats**, more effects |
| 5 | **Speed** | Standard 0.1–100×, duration field, "Change audio pitch"; **Curve**: Montage, Hero, Bullet, Jump cut, Flash in, Flash out, Custom (free: 2 uses); **Speed effects** (Flash, Shake & blur, Blur…, Retro zoom, Rainbow); Smooth slow-mo (Pro) | ✅ 0.25–4×, pitch kept, freeze, reverse, replay, gradual changes. ❌ Speed **curves/presets**, speed effects, smooth slow-mo |
| 6 | **Animate a clip** | Animation tab: **In / Out / Combo** presets in families (Trending, Basic, Light, Glitch, Mask, 3D, Shake), one duration slider | ◐ Motion presets (slow zoom, glide, zoom in at playhead), keyframes, styles' punch-ins. ❌ In/Out presets on clips |
| 7 | **Transitions** | Transitions tab, families (Overlay, Light, Camera, 3D, Blur…); drag between clips; duration; Apply to all | ✅ 8 kinds, length, Use on Every Cut. ❌ Glitch, spin, blur, shake families |
| 8 | **Effects** | Effects tab: **Video effects** (whole frame) and **Body effects** (follow a person); dropped on a clip or as their own timeline item with a length | ❌ No effects layer (only filters and transitions) |
| 9 | **Fix and frame the picture** | Transform (scale, position, rotation, align), Blend + opacity, **Canvas** (colour/blur/image), Crop, Stabilize (Pro), Auto reframe (Pro), Enhance quality (Pro, 3/day), Remove flickers (Pro) | ✅ Fill/Show all + blurred background, move/scale/turn, opacity, Stabilize, Follow the Subject, Enhance (colour). ❌ Blend modes, canvas colour/picture |
| 10 | **Colour** | Adjust: Auto adjust, Color match, Color correction (Pro); LUT; skin-tone protection; HSL, Curves, Color wheels, Mask; Filters tab (Featured, Life, Landscape, Portrait, Mono, Film, Retro…) with strength | ✅ Enhance, Match Color, Pick Skin, sliders, 12 filters with strength, look for the whole Short. ❌ LUT import |
| 11 | **Cut someone out** | Remove background: Auto (Pro), Custom (brush), **Chroma key** (picker, strength, shadow, edge feathering) | ❌ |
| 12 | **Templates** | Templates tab: filter by orientation, number of clips, length; each card shows uses and clip count; replace the placeholders | ◐ Storyboards (shot lists) and Styles (one-click look). ❌ Ready-made timed templates with placeholders |
| 13 | **Export** | Export window (resolution 480p–8K, bit rate, codec, format, fps, audio only, captions file, GIF, copyright check, share to TikTok/YouTube). **Blocked by Pro items** with a "Pro materials" list (screen 31) | ✅ One YouTube-ready preset, checks, size estimate, loudness, frame as picture. ❌ Captions file (SRT), audio only |

---

## 4. The rules CapCut follows everywhere, and which ones we take

CapCut is consistent about a few things. Some fit iMovie's feel; some fight it.

**Take (they fit iMovie's grammar):**
1. **One "None" tile first in every preset grid**, the current choice outlined. Undoing a look is one click. (We do this for filters; do it everywhere.)
2. **"Apply to all"** next to every per-clip setting (canvas, adjust, captions style, transitions). iMovie only has it for transitions. A single button beside the setting is clearer than a menu.
3. **Reset ↺ and keyframe ◇ beside every setting group.** Each group header has a reset arrow; animatable values have ◇ with ‹ › to jump between keyframes. We have keyframes for placement/opacity; add the same ◇ to volume and colour later.
4. **Presets drawn from your own footage** where possible (filter tiles). We already do it; CapCut doesn't (it uses stock pictures), which is worse.
5. **A text is a timeline item with its own length**, captions included; captions stay editable as text (split with ↩). Fits our lanes.
6. **Save as preset** at the bottom of text, adjust and retouch. We have "My Styles" for titles; extend to looks and captions.
7. **Every speed change keeps the timeline honest**: the duration field updates with the speed; curves show their shape as an icon.

**Don't take (they fight the iMovie feel or the user's needs):**
1. A store of hundreds of downloadable tiles per tab (stock pictures, trending, "Black Friday", "Halloween"). We ship a short, curated, offline set made by the app.
2. Four nested levels of tabs (library tab ▸ category ▸ sub-tab ▸ section). iMovie's single adjustments bar plus inspector sections is calmer.
3. A free "Original" canvas ratio (trap, §2).
4. Paywall at export, cloud uploads, credits, an AI chat box on the home screen.
5. Effects and filters as separate timeline tracks the user must stretch over clips. Prefer iMovie's way: a look belongs to a clip (or the whole Short); an effect is attached to a clip and follows it, like our B-roll/titles do.

---

## 5. The full inventory, ranked (what to take)

`Have` = Shorts Editor today: ✅ done, ◐ partly, ❌ missing. `Take` = **Yes** (worth building), **Later**, **No**. Pro = needs CapCut Pro in 9.7.1 on this account.

### Captions (CapCut's most visible tool; your #1 need)
| Feature | CapCut | Have | Take |
|---|---|---|---|
| Auto captions | Captions ▸ Auto captions ▸ language ▸ Generate (**Pro**) | ✅ free, on device | — |
| Captions from a **voice-over** and from **B-roll** sound | Any audio source | ❌ | **Yes, first** |
| **Split / merge** a caption line; new line | ↩ / ⌘↩ in the caption text; merge in the list | ❌ | **Yes** |
| Move captions anywhere in the viewer | Drag | ✅ up/down (kept clear of YouTube's areas) | — |
| **Caption templates** (animated looks: word pop, karaoke fill, glow, bounce, typewriter) | Captions ▸ Templates, ~10 families | ◐ 5 styles | **Yes** (8–12 made by the app) |
| Highlight key words in their own style | "Auto highlight keywords" (cloud LLM) | ✅ rules | Better picking with **Foundation Models** (on device) |
| AI emojis | Auto emojis | ✅ small dictionary | Bigger with Foundation Models |
| Filler-word detection | "Identify filler words" (**Pro**) | ✅ sounds ("um") | Real words ("like", "allora", "tipo") via Foundation Models |
| Bilingual / translated captions | "Bilingual captions" (**Pro**) | ❌ | **Later** (Apple **Translation** framework, on device) |
| Spoken language auto-detect, many languages | ~30 languages | ◐ 4 | Later: more `SpeechTranscriber` locales |
| Import/export captions file | SRT | ❌ | **Yes** (small) |
| Lyrics captions | "Auto lyrics" | ❌ | No (our music has no words) |
| Speaker colours | "identify speakers" (agent) | ❌ | Later |

### Text and graphics
| Feature | CapCut | Have | Take |
|---|---|---|---|
| Preset looks grid | 28 looks (outline, box, glow, colours) | ◐ 5 styles + design | **Yes**: a grid of ~12 looks drawn live |
| In / Out / **Loop** animations for text | Animation tab | ◐ 6 entrances | **Yes**: exits and loops (pulse, wiggle, float) |
| Text templates (designed multi-line titles: hook, subscribe, "Part 2") | Text ▸ Text templates | ❌ | **Yes**, a few made by the app |
| Bubbles / callouts | Text ▸ Bubble | ❌ | Later |
| Stickers, arrows, emoji, shapes | Stickers tab (store + AI), Shapes | ❌ | **Yes**: emoji + SF-Symbol arrows/shapes, animated |
| Text/sticker **follows a subject** | Tracking (**Pro**) | ❌ | **Yes** (Vision `VNTrackObjectRequest`; we already track faces for Follow the Subject) |
| **Text to speech** | Text ▸ Text to speech, hundreds of voices, "Generate speech" | ❌ | **Yes** (`AVSpeechSynthesizer`, system and Personal Voice, on device) |
| Curved text, per-letter styling | Curve; rich text per range | ❌ | Later |
| Text opacity, blend | Blend section | ❌ | Later |

### Rhythm: beats, speed curves, effects
| Feature | CapCut | Have | Take |
|---|---|---|---|
| **Beat markers** on music | Auto beat (on device model), add beat by hand | ❌ | **Yes** (our own music knows its beats; any file: onset detection with Accelerate) |
| Snap cuts to beats / **Beat cut** (auto cut clips to the music) | Auto Cut, "Beat Cut" | ❌ | **Yes** |
| **Speed curve presets** | Montage, Hero, Bullet, Jump cut, Flash in, Flash out, Custom | ◐ gradual changes | **Yes** (named ramps as `speedSegments`) |
| Speed effects (flash, shake & blur on the ramp) | Speed ▸ Speed effects | ❌ | Later |
| Smooth slow motion | Optical flow (**Pro**) | ❌ | **Yes** (`VTFrameProcessor` frame interpolation, macOS 15.4+) |
| Video effects layer (shake, flash, zoom lens, glitch, VHS, grain, light leak, blur) | Effects tab, hundreds | ❌ | **Yes**: ~12 Core Image effects attached to a clip |
| Body effects (follow a person) | Effects ▸ Body effects | ❌ | Later (Vision person mask) |
| Clip In/Out/Combo animations | Animation tab | ◐ motion | **Yes** (reuse text animations on clips) |

### Picture
| Feature | CapCut | Have | Take |
|---|---|---|---|
| **Remove background** (person) | Auto removal (**Pro**), Custom brush | ❌ | **Yes** (Vision `VNGenerateForegroundInstanceMaskRequest`/person segmentation, on device) |
| **Chroma key** | Colour picker, strength, shadow, edge feathering | ❌ | **Yes** (Core Image colour cube) |
| Masks (line, mirror, circle, rectangle, star, heart, text, brush) with feather/invert | Mask tab | ❌ | Later (circle/rectangle/line first, for split looks) |
| Blend modes | Blend | ❌ | Later (Screen/Multiply/Overlay for light leaks) |
| Canvas: colour / blur / picture behind | Canvas, Apply to all | ◐ blur | Small: add colour |
| Auto adjust, colour match | **Pro** | ✅ | — |
| LUT import | LUT | ❌ | Later |
| Stabilize, auto reframe, flicker | **Pro** | ✅ / ✅ / ❌ | — |
| Enhance quality (upscale) | **Pro**, 3 a day | ❌ | Later (`VTFrameProcessor` super resolution) |
| AI expand, AI remove object, AI remix, eye contact, lip sync, relight, retouch | AI, many Pro | ❌ | **No** |

### Sound
| Feature | CapCut | Have | Take |
|---|---|---|---|
| Music library by mood | Store, genres | ✅ app-made moods | More moods later |
| Sound effects | Store | ✅ 7 | **Yes**: ~20 (riser, whoosh family, camera shutter, notification, swoosh, record scratch, laugh-free) |
| Voice changer | Voice filters | ✅ | — |
| Normalize, enhance, reduce noise, isolate voice | some Pro | ✅ | — |
| Extract audio from a video | Extract audio | ◐ detach sound | — |
| Music that starts later / loops | free placement | ❌ (one song from the start) | **Yes** |

### Templates and one-click
| Feature | CapCut | Have | Take |
|---|---|---|---|
| Templates with placeholders, timed to music | Templates tab, filters by clips/length | ◐ Storyboards + Styles | **Yes**: "Fill a template" = a storyboard with fixed timings, transitions and text, cuts on the beat |
| Long video to Shorts (AI clipper: <60 s, 60–90 s, 90 s–3 min, caption style) | Home tile, cloud | ◐ Magic Short (keeps the start) | **Yes**: find the best moments with Foundation Models on the transcript |
| Script to video, AI avatar, AI video/image | Cloud, credits | ❌ | **No** |
| Agent / EditPilot (edit by chat) | Cloud | ❌ | No (maybe much later with Foundation Models) |

### Finishing
| Feature | CapCut | Have | Take |
|---|---|---|---|
| Export range (I/O) | ⇧X / I, O | ◐ | Later |
| Captions file, audio only | Export window | ❌ | **Yes** (SRT), later (audio) |
| **Cover** (pick a frame, add text) | Cover editor | ◐ frame as picture | **Yes**: cover picker = frame + title, 1080×1920 JPEG |
| Resolutions, codecs, fps, 8K, ProRes | Export window | Fixed by design | **No** |
| Share to YouTube | Upload | ❌ | Later (needs an account) |

---

## 6. Where CapCut falls short for a Short (and where we're already ahead)

1. **Paywall at the end.** You can spend an hour using Pro tiles and only learn at Export ("Get Pro and save 21.6 € to unlock these features", screen 31). Even stock clips from its own library are Pro. Auto captions are Pro.
2. **Cloud and credits.** Captions, filler words, isolate voice, translation and most AI run on servers with queues. We do captions, voice clean-up, filler sounds and reframe on device, free and private.
3. **Not 9:16 by default.** "Original" ratio from the first clip (your Short `1111` is 1188×1920).
4. **Not a Mac app.** Qt windows: no native menus for editing, own text fields, popups as separate windows, an always-on "EditPilot" bubble over the player's ratio button. iMovie-style native SwiftUI is a real advantage.
5. **Breadth over clarity.** Hundreds of trending tiles, 4 levels of tabs, Italian labels truncated ("Flash in ingre…"). A Shorts editor needs 10 good choices, each previewed live.
6. **No YouTube-specific checks.** No safe-zone overlay, no 3-minute limit, no Content ID warning for music over 1 minute, loudness only as an option. We have all of them.
7. **Media by absolute path**: moved files break projects. We use bookmarks and keep playing with black.

---

## 7. What to take, as build stages (iMovie feel, CapCut features)

Each stage follows the project's rules: model and logic in `EditorCore` with tests, drawing in `ShortsCompositor`, plain-language UI in the existing inspector/menus, every shortcut in a menu, on device only.

### Stage G: Captions, the CapCut way (asked for on 2026-11-12). Highest value.
1. **Captions from every voice**: transcribe voice-overs and B-roll sound too (stored per file like now, so they follow edits). Your `1111` Short becomes: record → captions appear.
2. **Phrase captions**: a "Phrase" style (2–4 words a page, big, centred, your caption font, e.g. EB Garamond) next to One Word; emoji typed in a caption drawn in colour.
3. **Edit like text**: ↩ splits a caption at the cursor, ⌘↩ adds a line break, ⌫ at the start merges with the one before; a caption's timing can be nudged on the captions lane (drag its edges).
4. **Caption looks grid** (8–12, drawn live from the Short's own frame): Bold Pop, Karaoke fill, Glow, Box, Outline, Typewriter, Bounce, Subtitles… each with its word animation.
5. **Smarter words** with Apple **Foundation Models** (on device): key words, emoji, and real filler words ("like", "tipo", "allora"), falling back to today's rules when the model isn't available.
6. **SRT** import/export (File menu).
7. Later in G: translated second line (Translation framework), more languages with auto-detect.

### Stage H: Text, stickers and voice
Title look grid (~12 presets), exits and loops, 4–6 text templates (Hook, Subscribe, Part 2, Top 3 number, Question, "Link in description"), emoji/arrow/shape stickers with the same animations, **follow a subject** for titles and stickers (Vision tracking), **text to speech** from a title or a script line (system voices, placed as a voice-over, captioned by stage G).

### Stage I: Rhythm
Beat markers (app music knows them; files by onset detection), snap to beats, **Cut to the Beat** (clips trimmed so cuts land on beats), **speed curve presets** (Montage, Hero, Bullet, Jump Cut, Flash In, Flash Out) as named shapes of our gradual speed, smooth slow motion (frame interpolation), clip In/Out animations, music placed later or looped.

### Stage J: Effects
~12 effects attached to a clip (and following it): Shake, Flash, Zoom Pulse, Glitch, RGB Split, VHS, Film Grain, Light Leak, Blur In/Out, Vignette Pulse, Mirror, Black & White Pop; strength + length; "None" first; previews from your own frame. Plus ~12 more sound effects.

### Stage K: Cut-outs
Remove background (Vision, offline per file, cached like Stabilize), chroma key (picker, strength, edge softness, spill), a few masks (line, circle, rectangle with feather/invert), canvas colour, blend modes for overlays.

### Stage L: Templates and finding moments
Templates = storyboards with fixed timings, text and transitions, cut on the beat ("Fill a template"); Magic Short picks the best 30/60 s by reading the transcript with Foundation Models; cover picker (frame + title) on export.

### Not taking
Generative AI (video, images, avatars, lip sync, eye contact, relight, retouch, AI expand/remove), cloud agent, store of trending assets, accounts and cloud spaces, extra ratios/resolutions/codecs, several timelines and compound clips, copyright check service.

---

## 8. Suggested order

**G → I → H → J → K → L.** G answers your request and your real workflow (voice-over Shorts with hand-typed captions). I (beats and speed ramps) is what makes CapCut edits feel "CapCut". H and J add the graphic punch. K and L are bigger and can wait. Each stage ends with tests, an on-screen check and your OK before committing.
