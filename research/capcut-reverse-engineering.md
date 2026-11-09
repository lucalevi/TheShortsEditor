# CapCut for Mac: what's inside

_Analysed 2026-11-09 from `/Applications/CapCut.app` (version 9.7.1, build 297, bundle `com.lemon.lvoverseas`, Mac App Store build) and the CapCut data in `~/Movies/CapCut/User Data`. Nothing was run or decompiled. Everything here comes from the bundle's file layout, its localisation file, strings in its libraries, its config files and the project files it saved on this Mac._

**Purpose:** know which tools, settings and behaviours CapCut has, so we can decide what Shorts Editor should have. We copy *features*, never CapCut's assets, effects, models, fonts, names or look.

How the evidence was collected (repeatable):

| Source | What it gave |
|---|---|
| `Contents/Resources/po/en.po` (17,769 English UI strings) | Every label, button, tooltip and error message, so effectively the full feature list |
| `strings libVECreator.dylib` (651k strings) | 857 QML file names, which show the UI screen by screen (every inspector panel) |
| `Contents/Resources/*`, `models/` | Built-in effects, colour tools, on-device AI models |
| `~/Movies/CapCut/User Data/Config/Shortcut/*.json` | The complete default keyboard map, plus the "Final Cut Pro X" and "Premiere Pro" maps |
| `~/Movies/CapCut/User Data/Config/globalSetting` | Preferences and their defaults |
| `~/Movies/CapCut/User Data/Projects/com.lveditor.draft/1107/draft_info.json` | The project file format, from **a Short you made in CapCut on 2026-11-07** |

Labels below are quoted exactly as CapCut shows them in English.

---

## 1. How CapCut is built

| Layer | What it is | Evidence |
|---|---|---|
| UI | **Qt 6 + QML** (Qt Quick, Controls 2, Shapes, Particles), not AppKit/SwiftUI. Web panels in **Chromium Embedded Framework**, some screens in **Lynx** (ByteDance's cross-platform UI) | `Frameworks/Qt*.framework`, `Chromium Embedded Framework.framework`, `libLynx.dylib`, 857 `.qml` files compiled into `libVECreator.dylib` |
| App logic | `libVECreator.dylib` (744 MB), `libcccreator.dylib` (139 MB) | Size, QML names |
| Video engine | ByteDance "VE" SDK: `libvideoeditor.dylib` (185 MB), effects engine "Amazing" (`libEffectPlatform`, `xshader` folders, Lua scripts), own GPU layer (`libAGFX`, Metal shaders in `VEMetalBinary_Mac.bundle`, plus ANGLE `libEGL`/`libGLESv2`) | Frameworks; `Chroma/amazingfeature/xshader`, `Curves/.../LuaRTTI.MarkGen.lua` |
| Codecs | **FFmpeg** (`libavcodec`, `libavformat`, …, `ffmpeg`/`ffprobe` binaries), dav1d (AV1), ByteVC1 (ByteDance's HEVC decoder), LAME (MP3) | Frameworks, `Resources/ffmpeg` |
| AI on device | ByteNN runtime (`libbytenn`), ~186 MB of models (§9) | `Resources/models` |
| Audio | `libsamicore` (ByteDance audio DSP), RNNoise model, a U-Net music denoiser, audio time-alignment models | `Resources/rnnoise`, `Resources/audiosami` |
| Speech | `libspeechsdk.dylib` (ASR client; transcription itself is mostly cloud, see §9) | Frameworks |
| Agent | An AI chat agent ("Omni mode", "AI Storyboard", "Edit Pilot") with built-in "skills" written as `SKILL.md` files: find highlights, write script, align music with video, identify speakers, understand footage | `Resources/builtin_skills/*/SKILL.md`, `libDeepAgentsService` |
| Other | Content credentials (`libtt_c2pa_sdk`, C2PA), invisible watermark model, in-app purchases (`PIPOIAP`), crash/telemetry, cloud drafts and team spaces | Frameworks |

Takeaways for us:
- CapCut's video, effect and AI stack is entirely its own. We use AVFoundation + Core Image + Vision + Speech instead, and that's enough for everything in the "must have" list.
- The UI is Qt, which is why CapCut on Mac doesn't feel like a Mac app (no native menus for most commands, no native text fields, custom scroll behaviour). A native SwiftUI app is a real advantage we should keep.
- Much of the AI is cloud and paid (credits, "In line to isolate voice… Estimated 1h+ wait"). We can do the most useful parts on device for free.

---

## 2. Screen layout

From `mainwindowLayoutConfig.json`, `timeline_layout.json` and the QML module names (`MaterialPanel`, `Player`, `FunctionPanel`/`DraftInspector*`, `TimeLine`):

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Top bar: Media · Audio · Text · Stickers · Effects · Transitions ·        │
│          Captions · Filters · Adjustment · Templates · AI avatars · …     │
├───────────────────────┬───────────────────────────┬──────────────────────┤
│ Library (left)        │ Player (centre)           │ Inspector (right)    │
│ local media, stock,   │ ratio menu, zoom, guides, │ tabs per selected    │
│ effects, templates    │ rulers, full screen       │ item (see §4)        │
├───────────────────────┴───────────────────────────┴──────────────────────┤
│ Toolbar: select/cut tool, split, delete, freeze, reverse, mirror, rotate, │
│ crop, auto reframe, … · main-track magnet · snapping · linkage · preview  │
│ axis · zoom                                                              │
│ Timeline: text/sticker/effect tracks ▲ main video track ▼ audio tracks   │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Several timelines per project** ("Timeline 01", docked side by side, "Detach timeline"), and **subprojects / compound clips** ("Create compound clip", "Can't nest more subprojects").
- **Home screen** before the editor: project list with covers, "Long video to shorts", AI tools, templates, cloud space, trash (projects go to `.recycle_bin`).

---

## 3. Timeline and editing tools

| Tool | CapCut label / behaviour | Default key |
|---|---|---|
| Split at playhead | "Split" | ⌘K (FCP map: ⌘B) |
| Split all tracks | "batchCut" | ⌘⇧K |
| Delete left / right of playhead (trim to playhead) | "Delete left" / "Delete right" | Q / W |
| Blade tool / select tool | "switchToCut" / "switchToSelect" | C / V |
| Delete | ripple when the main-track magnet is on | ⌫ / Del |
| **Main track magnet** | gaps on the main track close automatically; other tracks are free | ⇧⌫ |
| **Snapping** ("adsorb", "Auto snapping") | clip edges snap to playhead, other edges, markers | S |
| **Linkage** | overlays/text/music move with the main clip they sit on (`linkageEnableTypes=text, effect, sticker, filter, adjust, vice, music, sound, tts`) | ⌘L |
| **Preview axis** (hover scrubbing) | the player follows the mouse over the timeline | ⇧P |
| Select everything after / before the playhead | "forwardSelect" / "backwardSelect" | ⇧A / A |
| Range (in/out) selection | "selectRangeStart/End", "Select range by segment", "Cancel range select" | I / O / ⇧X / ⌥X |
| Group / ungroup | "Group", "Clips ungrouped" | ⌘G / ⌘⇧G |
| Compound clip / undo it | "segmentCombination" | ⌥G / ⌥⇧G |
| Copy / paste **attributes** | paste a clip's look (adjustments, animation, speed…) onto others | ⌘⌥C / ⌘⌥V |
| Markers | add, add with another colour, next/prev, edit, delete all | M / ⌥M / ⇧M / ⌥⇧M |
| Beat markers | "Add beat", "Auto beat"/"Auto mark beats", "Beats 1/2", "Beat frequency"; clips can be aligned to beats | ⌘J |
| Previous / next cut point | | ↑ / ↓ |
| Frame step / 10 frames | | ← → / ⇧← ⇧→ |
| Play / J K L shuttle | | Space / J K L |
| Hide clip, mute track, hide track, lock track | "toggleSegmentVisibe", "Hide track" | ⇧E |
| Separate / extract audio | "Extract audio", "Separate audio" | ⌘⇧L |
| Freeze frame | "Freeze" (inserts a still) | — |
| Reverse | "Reverse" | — |
| Replace clip | keeps length and attributes | — |
| Timeline zoom / fit | | + − / ⇧Z |
| Player zoom / fit | | ⌥⇧+ / ⌥⇧− / ⌥⇧Z |
| Guides, rulers, grid in the player | "Show/hide guides", "Show/hide rulers", "Grid" | ⌘; / ⌘⌥R |
| Pre-render the selection | "prerenderSelectArea" | ⇧↩ |
| Record voice-over | "videoRecord", "Voiceover" | ⌘⌥P |
| Volume up / down | | ⌘. / ⌘, |
| Export | | ⌘M (FCP map: ⌘E) |
| Full screen player | | ` |
| Captions: split line / new line | "subtitleSplit" / "subtitleNewLine" | ↩ / ⌘↩ |
| Keyframes | add with ⇧-click, keyframe panel ⌥K, basic keyframe ⌥⇧K | |
| Speed: split a speed curve point | "divideSpeedSegment" | ⇧B |
| Customisable shortcuts | three custom slots + presets "Final Cut Pro X" and "Premiere Pro" | |

(`Ctrl` in CapCut's maps is ⌘ on Mac.)

---

## 4. Inspector: what you can set on each kind of item

Panel names are the QML files (`DraftInspectorVideo*`, `DraftInspectorText*`, …). Options are the English labels found in the strings.

### 4.1 Video / image clip
| Tab | Settings |
|---|---|
| **Basic** (`VideoScreen`) | Position X/Y, **Scale** (with "Uniform scale"), Rotation, Flip, **Opacity**, **Blend** mode (Multiply, Screen, Overlay, Darken, Color burn, Color dodge, …; 91 files in `MixMode`), **Canvas** (colour / **blur** / image background behind footage that doesn't fill the frame), "Fit to canvas", **Crop** (free or ratio), **Auto reframe**, **Stabilize** (levels), **Remove background** ("Auto removal", "Custom" brush, "Chroma key" with colour picker, intensity, shadow), **Mask** (Line, Mirror/Parallel lines, Circle, Rectangle, Heart, Star, Text, Pen; feather, invert, rotate, size; mask tracking), **Retouch** (Face, Body, Makeup, "Clear blemishes", face/body presets), **Relight** (presets, add light sources), **Eye contact**, **Enhance quality**/"Super resolution", **Remove flickers**, shadow, stroke, "Rounded corner" (`video_shadows`, `video_strokes`, `video_radius`) |
| **Audio** | Volume (dB), fade in/out, **Normalize loudness** (targets: Default −23 LUFS, **YouTube −14 LUFS**, TikTok −12 LUFS), **Enhance voice**, **Reduce noise**, **Isolate voice** / "Vocals & instruments separation", **Voice changer** (filters, characters, "Change voice"), pitch, audio balance/pan, channel mapping |
| **Speed** | **Normal**: 0.1×–100×, duration field, "Change audio pitch" on/off, **Smooth slow-mo** (frame interpolation / "Optical flow"). **Curve**: presets (Montage, Hero, Bullet, Jump cut, Flash in, Flash out, Custom), editable curve with beat points |
| **Animation** | In / Out / **Combo** (loop) presets with duration slider |
| **Adjust** | Auto adjust, **Color match** (match another clip), **Color correction**; Basic: Temp, Tint, Saturation, Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Brilliance, Brightness, Sharpen, Clarity, Fade, Vignette, Grain, Dehaze; **HSL** (8 colours × H/S/L); **Curves** (RGB + per channel); **Color wheels** (primary + log); **LUT** import (CUBE, 3DL); "Adjustment mask"; save as **Adjustment preset**; HDR / colour space conversion; "Color oscilloscope" (scopes) |
| **Tracking** | Camera tracking, object tracking (stickers/text follow a subject) |
| **AI** (`VideoAIGC`) | AI movement, AI backgrounds, generative expand/inpaint ("outpainting", "inpainting") |

### 4.2 Text and captions
| Tab | Settings |
|---|---|
| **Basic** (`TextBase`) | Text box, **Font** (built-in + user fonts + brand fonts), size, **Bold**, case, **Character spacing**, **Line spacing**, **Alignment**, colour (solid/gradient), **Stroke** (several), **Background** (colour, opacity, roundness, padding), **Shadow** (colour, opacity, angle, distance, blur), **Glow**, **Curve** (curved text), position/scale/rotation, "Save as preset" |
| **Templates / Effects** | Text templates (multi-layer designed titles), **Text effects** ("flowers": preset looks), **Bubble** (speech-bubble shapes) |
| **Animation** | In / Out / Loop, per type; captions have their own "Caption animations" |
| **Highlight** (`TextHighlight`) | **"Auto highlight keywords"** in captions with their own style (`HighlightEditStyleDialog`) |
| **Text-to-speech** (`TextTts`) | Voice library, custom voice from a sample (`AICloneTone*` dialogs, "Creating your custom voice..."), speed |
| **Tracking** | Text follows a moving subject |
| **Caption-only** | Captions are text clips with `caption_info`; "Apply to all captions" for any style change; split/merge lines with ↩; "Captions line wrap"; lines per screen; **Bilingual captions**; **AI emojis** (auto emojis on auto-generated captions); **caption templates** (styled packs, can create your own); **Lyrics** ("Auto lyrics") with lyric templates |

### 4.3 Audio clip (music, sound effects, voice-over)
Volume, fade in/out, normalize loudness, enhance voice, reduce noise, isolate voice, voice changer (`DraftInspectorAudioVC`), **speed** with pitch (`AudioSpeed`), **audio effects** (`AudioEffect`, voice filters), beats, "Change sound" (the draft also stores `similiar_music_info`). Music library categories, **sound effects** library, **AI music** ("aimusic": generate music), **AI sound effects** (generate from the video).

### 4.4 Stickers, effects, filters, transitions, shapes
- **Stickers**: library + AI stickers + your own images; animation in/out/loop; tracking; "Face cover stickers" that follow faces.
- **Effects**: **Video effects** (whole frame) and **Body effects** (follow people), each with parameters (`effectParamNames.json`: background animation, blur, colour, … 21 names) and a duration on the timeline; "Effect mask".
- **Filters**: preset looks with strength slider, applied to a clip or as their own timeline item over several clips.
- **Transitions**: between two clips on the main track; duration slider; "Apply to all".
- **Shapes** (`FundamentalShape`): rectangles, circles, lines with fill/stroke, animatable.
- **Adjustment layer**: an "Adjustment" item on the timeline that colours everything under it.

### 4.5 Keyframes (anything animatable)
◆ button next to each property; ease presets ("Linear", "Ease in", "Ease out", and a library of **keyframe graphs**, `SegmentKeyframePresetPanel`); a keyframe panel (⌥K); "Previous/Next keyframe"; on video, text, stickers, effects, filters, adjustments, volume, masks. Solid/gradient colours can be keyframed.

### 4.6 Project settings (`DraftInspectorProjectConfig`)
Name, **ratio** (9:16, 16:9, 1:1, 4:3, 3:4, 21:9, 2:1, original, custom), resolution, frame rate, colour space (SDR/HDR), proxy, where media is stored, the project **cover** (choose a frame or upload, then edit it with text in a cover editor).

---

## 5. AI and "one click" features

| Feature | What it does | On device or cloud* |
|---|---|---|
| **Auto captions** | Speech → timed captions; languages list ~30; "Auto detect"; "Bilingual"; **"Remove filler words"** right in the captions panel | Cloud (upload consent strings) |
| **Transcript-based editing** | "Edit your video as easily as you edit text": delete words → parts of the video are deleted; "Hide deleted text"; detects **Filler words, Pauses, Repetition, Hesitation** ("Repetitions, pauses, and hesitations will be automatically detected. You can delete them in one click.") | Cloud ASR, local edit |
| **Long video to shorts / AI clipper** | Upload one long video (spoken, English only) → several 9:16 Shorts with captions; choose length (<60 s, 60–90 s, 90 s–3 m, Auto), "Caption style", editing style (Commentary, Interview, Montage, Educational…) | Cloud |
| **Smart Cut / AutoCut** | Arrange clips, cut to music, "Auto arrange clips" chronologically | Cloud + local shot detection (`jy_compressShotDetect*`) |
| **Auto reframe** | Turn horizontal into vertical "keeping the main character in the best position"; with "Camera moving speed" | Local (`lvop_intelligent_crop`, saliency + tracking models) |
| **Remove background** | Person cutout without green screen; custom brush; chroma key | Local (`mattingmodel`, `tt_interactive_matting`, `tt_mobilevos`) |
| **Stabilize** | | Local |
| **Smooth slow-mo** | Frame interpolation | Local (`interpolation`, `umvfi`) |
| **Remove flickers** | | Local (`deflicker`) |
| **Enhance quality / Super resolution** | Upscale and sharpen | Local + cloud ("AI ultra HD") |
| **Retouch, Relight, Eye contact** | Face beauty, add light, redirect gaze to camera | Local face models; relight needs a recent GPU |
| **Auto adjust / Color match / Color correction** | | Local |
| **Normalize loudness** | −23 / −14 (YouTube) / −12 (TikTok) LUFS | Local |
| **Reduce noise / Enhance voice / Isolate voice** | Isolate voice is queued on a server | Noise: local (RNNoise); isolate: cloud |
| **Voice changer, Text to speech, Clone tone** | | Cloud |
| **Beat detection** | Auto beat on music, including local music | Local (`audiomodel`) |
| **Auto highlight keywords, AI emojis** | Styles important words in captions; adds emojis | Cloud (LLM) |
| **Translate / Overdub / Lip sync** | Translate a video's speech into another language with the speaker's voice and moving lips; fix spoken mistakes by editing text | Cloud, paid |
| **AI avatars / digital humans** | Talking presenter from a script | Cloud, paid, watermarked "AI generated" |
| **Script to video, AI writer, AI music, AI sound effects, AI stickers, AI backgrounds, Expand image, Inpainting** | Generative tools | Cloud, credits |
| **Agent ("Omni")** | Chat that edits: find highlights, write script, align music, speaker detection | Cloud |

*On device = a model ships in `Resources/models` or the strings show local progress; cloud = strings about uploading, queues, credits or network. This is inferred, not tested.

---

## 6. Export

From the strings and `ExportCompileRightPanel.qml`:
- **Video**: name, location, resolution (720P, 1080P, 2K, 4K, **8K**), "Bit rate" (Lower / Recommended / Higher, CBR or ABR), "Codec" (H.264 / HEVC / AV1 per CapCut's docs; codec names aren't localised strings, so they weren't confirmed in the bundle), **Apple ProRes 4444 (Alpha)**, **HEVC (Alpha)**, "Format", frame rate (24, 25, 29.97, 30, 50, 59.94, 60), **10-bit**, colour space, "Faster exporting, but may have color differences" (hardware), "Motion blur", "Enhance quality" on export ("AI ultra HD").
- **Audio only** ("Export audio"): AAC and PCM found in strings, 192/256/320 kbps.
- **Captions** ("Captions exported", "Caption format"; formats not confirmed in strings, SRT per CapCut's docs). Caption files can also be imported.
- **GIF**, **still frame(s)**, "Export selected clips", "Export clips", "Export timeline".
- Copyright check of music before export ("Duration of copyright issue: %s"), "Share to TikTok", "Link YouTube account".
- Watermark "Made with CapCut" on some Pro content; export blocked by Pro features unless you pay ("Join Pro and export").

---

## 7. Preferences (`globalSetting`, `SettingsView.qml`)

- Draft location, cache location and auto-clean (90/60/30/15 days), custom material and preset folders.
- **Hardware decode / encode / render** switches; performance mode; **proxy** ("Proxy", `autoPrerenderEnable`, `autoRemuxEnable`).
- Default **frame rate** (30), drop-frame timecode, **default image duration** (5 s or 150 frames).
- Language, notifications, export-finished notice, auto update.
- Keyboard map choice (`keymapSettings`: CapCut / Final Cut Pro X / Premiere Pro / Custom 1–3).
- Linkage types (which items follow the main clip), main-track magnet on by default.
- Auto backup of drafts (`Config/AutoBackUp`).

---

## 8. Project file format (`draft_info.json`)

One JSON per timeline; time in **microseconds** (integers), 30 fps stored as a float.

```text
Draft
├─ canvas_config {ratio:"9:16", width:1080, height:1920}
├─ fps, duration, color_space, config {maintrack_adsorb:true, subtitle_sync, …}
├─ tracks[]  type = video | audio | text | sticker | effect | filter | adjustment
│   └─ segments[]
│       ├─ material_id → materials.<kind>[id]
│       ├─ source_timerange {start, duration}   (in the file)
│       ├─ target_timerange {start, duration}   (on the timeline)
│       ├─ speed, volume, reverse, is_loop, is_tone_modify, visible
│       ├─ clip {scale{x,y}, rotation, transform{x,y in −1…1}, flip, alpha}
│       ├─ uniform_scale, render_index, track_render_index
│       ├─ extra_material_refs[] → speeds, canvases, animations, audio_fades,
│       │                          beats, masks, vocal_separations, …
│       ├─ common_keyframes[], keyframe_refs[], lyric_keyframes[]
│       └─ enable_adjust / enable_lut / enable_color_curves / … switches
├─ materials (≈60 kinds): videos, audios, images, texts, stickers, effects,
│   video_effects, transitions, canvases, speeds, audio_fades, beats,
│   material_animations, common_mask, chromas, hsl, color_curves,
│   primary_color_wheels, loudnesses, realtime_denoises, vocal_separations,
│   smart_crops, smart_relights, manual_beautys, text_templates, shapes, …
├─ keyframes, keyframe_graph_list, time_marks (markers), group_container
└─ cover, relationships, platform
```

Notable design choices:
- **Segment + shared "materials"** (like our `Clip` → `MediaAsset`), but *every* effect is also a material referenced by id. Attributes are therefore easy to copy between clips ("Paste attributes").
- Text styling is stored as rich text: `content` is JSON with `styles[]` per character range (fill, strokes, font, size), so one caption can mix colours (that's how word highlighting works).
- Position is normalised to −1…1 of the canvas, scale is relative to "fit".
- Media is referenced by **absolute path** (no bookmarks), which is why CapCut loses media when files move ("Media files not found", "Link media").

### 8.1 Your own CapCut Short, read from the draft

Draft `1107` (2026-11-07), 34.6 s, 9:16 1080×1920, 30 fps:

| Track | Content |
|---|---|
| Video | 4 clips from `WALKING-001.mp4` and others: **1920×1080 horizontal footage** placed on the vertical canvas with **"canvas_blur" (blurred copy of the clip behind it, blur 0.0625)**. Clip lengths 1.6 s, 3.0 s, 4.0 s, 26 s |
| Audio | One song ("Fortuna", a downloaded MP3) **starting 24.07 s into the song**, running for the full 34.6 s at 100% |
| Text 1 | **"Think, / together."**, font **EB Garamond Bold** (your own font), white with a **black outline** (stroke 0.06), size 35, from 1.6 s to the end |
| Text 2 | **"Link in descrizione"** (Italian call to action), moved down (y = −0.45), from 4.6 s to the end |
| Also | An **AVIF image** (`watson-crick.avif`) imported into the media list |

What it tells us about your real needs, beyond what Shorts Editor already does:
1. **Blurred background** for horizontal footage instead of black bars (our "Show all" leaves bars).
2. **Images** as clips (AVIF/HEIC/PNG/JPEG).
3. **Your own fonts** (EB Garamond) for titles.
4. Two text items on screen at once: a **hook** and a **call to action**, each placed freely.
5. Picking **where in the song** the music starts (we have this: "Start the song at").

---

## 9. On-device AI models (for reference)

`Resources/models` (186 MB): face detection/landmarks/3D fitting, face clustering ("who is this person" across clips), face beauty, hair/head/skin/body/human parsing segmentation, skeleton (pose), hand detection, pet face, **saliency** (what's important in the frame → auto reframe), **object tracking** and single-object tracking, **video matting** (background removal; `tt_mobilevos` = video object segmentation, interactive matting), **shot detection** (scene cuts), **frame interpolation** (slow-mo), **deflicker**, depth, scene classification, QR codes, audio models (beats), noise reduction, AEC, invisible watermark. Plus RNNoise and a U-Net music denoiser in `rnnoise/`, `audiosami/`.

Apple equivalents we can use without shipping models: **Vision** (saliency, face/body/hand pose, person segmentation `VNGeneratePersonSegmentationRequest` / `VNGenerateForegroundInstanceMaskRequest`, object tracking `VNTrackObjectRequest`, optical flow), **Core Image** (filters, chroma key via colour cube, blur), **VideoToolbox** frame interpolation (`VTFrameProcessor`, macOS 15.4+, also super resolution), **AVAudioUnit** voice processing / Sound Isolation (macOS 15+ `AUSoundIsolation`), **SpeechAnalyzer** (already used), **Foundation Models** for on-device text tasks (keyword highlighting, titles).

---

## 10. What's free vs Pro (from the strings; plans change often)

Strings say "Join Pro to…" for: remove background (heavy use), isolate voice, export without watermark, 4K/8K and "AI ultra HD", premium templates/effects/fonts, most AI generation (credits), voice changer/TTS voices, translate/lip sync, and more auto-caption minutes. Third-party 2026 reviews disagree on the exact free limits (see the companion research file). This is CapCut's main weakness among creators and a reason a free native Mac tool is attractive.
