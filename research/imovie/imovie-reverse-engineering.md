# iMovie, reverse engineered for Shorts Editor

_Written 2026-11-09. Step 1 of "bring Shorts Editor to iMovie's level and beyond"; step 2 (building) starts when the user asks._

**Sources**
1. **iMovie 10.4.5 on this Mac.** Live menu bar read through Accessibility (every item and shortcut), the bundle's 449 command names and 137 default shortcuts, its catalogues (titles, transitions, filters, themes, sound effects, audio presets), and a hands-on session: a scratch library in `~/Movies/ShortsEditorResearch` (the user's own library and project were not touched; the scratch library was closed afterwards) with a vertical 1080×1920 clip, a horizontal 1920×1080 clip and a photo. Screens are in `screens/`.
2. **Apple's iMovie User Guide for Mac**: 83 of its 87 pages read in full (notes: `imovie-docs-notes.md`). The PL147 page only lists the three user guides and old downloads.
3. **iMovie for iPhone guide** (3.0.x): Magic Movie, Storyboards, timeline, audio and sharing chapters, because that's where Apple's ideas for quick, phone-shaped videos live.

Lookup tables (menus, shortcuts, every control and default, catalogues, colour language) are in `imovie-reference.md`.

**About the percentages.** "20 % that gives 80 %" and "30 % that covers 90 %" are judgements, not measurements: Apple publishes no usage data. The ranking comes from how prominent each feature is in iMovie's own interface (toolbar, single-key shortcuts, defaults), how much of the guide it takes, and what a Short needs. §2 and §4 explain the reasoning.

---

## 1. iMovie in one paragraph

One window, three panes: a **browser** (your media, plus tabs of ready-made titles, backgrounds, transitions, music and sound effects), a **viewer** with one **adjustments bar** above it, and a **magnetic timeline** (a main row of clips that never has gaps, with titles, cutaways and sounds pinned above or below it, and a separate music well). A separate **Projects** grid holds every movie. You never save, you rarely open a dialog, and almost everything is: _select something, then click a button in the bar above the viewer._

---

## 2. The 20 % that does 80 % of the work (hands-on)

What a typical iMovie user actually does, in order of how often. This is the core loop iMovie is designed around: every item has a toolbar control, a single-key shortcut or both.

| # | Action | How iMovie makes it fast | Shorts Editor today |
|---|---|---|---|
| 1 | **Look through footage** | **Skimming**: hovering over any clip shows that frame in the viewer, no click; Space plays from under the pointer; J/K/L; audio skimming toggle (⇧S) | Scrub on the ruler and click to place the playhead. **No skimming.** |
| 2 | **Pick the good part** | Click selects a few seconds from the click point; hold **R** and drag for any range; **X** whole clip; orange stripe shows what's already used | Whole files only. **No ranges in Media.** |
| 3 | **Put it in the movie** | **E** add to end, **W** insert at playhead (splits), **Q** connect above; drag-and-drop with a blue landing marker; drop **on** a clip → Replace / Replace from Start / End / Insert | Drag or Import adds whole files in order; B-roll via button/menu. |
| 4 | **Cut** | ⌘B split; drag edges with a live length tooltip ("01:19") and a length badge; R-range then Trim to Selection; Trim to Playhead (⌥−); Clip Trimmer; Precision Editor | ✅ B split, edge drag, Q/W trim to playhead, snapping. No length tooltip while dragging, no range trim, no trimmer. |
| 5 | **Rearrange** | Drag clips; magnetic, no gaps; everything pinned to a clip moves with it | ✅ Drag to reorder. B-roll, titles and sounds stay at their time instead of following. |
| 6 | **Add a title** | Double-click a style = added at the playhead, 4 s; dropping on a clip's first/last third fits that third, the middle fits the whole clip; type in the viewer | ✅ ⌘T at the playhead, 5 styles, design, drag in viewer. |
| 7 | **Add music and sound** | Music well under the timeline (Trim background music to the movie); sound effects pinned to a clip; volume line on every clip; fade handles on hover; voiceover (V) | ✅ Music with automatic ducking and fades, sounds row, voice-over, clip volume. No volume line or fade handles on clips. |
| 8 | **Smooth the joins** | ⌘T cross dissolve; drag a transition between clips; one default length; Apply to all | ❌ No transitions. |
| 9 | **Fix the picture** | ✨ Enhance (one click); Color Balance Auto / White Balance / Skin Tone / Match; Crop to Fill / Fit / Ken Burns; rotate; stabilize | Fill/Show all, move/resize/turn, motion. ❌ No colour, no stabilize. |
| 10 | **Layer two videos** | Drag above a clip → cutaway; one menu turns it into Picture in Picture / Split Screen / Green Screen; opacity and fades | ✅ B-roll, PiP corners, top/bottom split. ❌ Opacity, fades, green screen. |
| 11 | **Change speed** | Slow / Fast presets, Freeze Frame, Instant Replay, Rewind, Reverse, Smooth ramps, Preserve Pitch | ✅ 0.25–4× with pitch kept. ❌ Freeze, reverse, replay, ramps. |
| 12 | **Share** | One sheet: preview, title, resolution, quality, **length and size estimate**; Image exports the current frame | ✅ YouTube-ready export with checks. ❌ Size estimate, still frame export. |

The **one-click whole-movie paths** sit on top of this loop: Themes + Automatic content (titles and transitions inserted as you add clips), project-wide Filter, Fade in/out from black, Trim background music; on iPhone, **Magic Movie** (pick clips, get a finished movie) and **Storyboards** (a shot list that tells you what to film).

---

## 3. The rules iMovie follows everywhere

These consistent behaviours matter more than any single feature: they are why iMovie feels easy, and they let a user who learned one tool guess how the next one works. Each rule below was seen in the app or is stated by the guide on several pages.

### 3.1 Selection and editing
1. **Select, then adjust.** The viewer's bar is the only place adjustments live. It changes with what's selected: a **T** button appears for titles, a **Video Overlay** button appears first (and opens by itself) for connected clips, **Cinematic** for Cinematic-mode clips. No floating panels, no separate inspector windows.
2. **Every tool has Reset, and the bar has Reset All.** Settings never get stuck; the way back is always in the same place.
3. **Selected = yellow border with handles**, in the browser and the timeline alike. Clicking a clip also moves the playhead to the click.
4. **One range tool for everything.** Hold R and drag: the range then works for adding, trimming, speed, volume and colour (with sensible rules: colour/enhance apply to the whole clip; volume applies to the range with automatic fades at its edges).
5. **The pointer is a second playhead.** The white skimmer line follows the mouse; Space plays from it; choosers preview at it.
6. **Things are pinned to clips.** Titles, cutaways, sound effects, voiceovers and freeze frames hang from a clip by a pin line; move or trim the clip and they come along. Only the background music lives apart, on purpose.
7. **Magnetic and non-destructive.** No gaps, inserting splits, deleting closes up; the source is never changed; trims can be extended again into unused media.
8. **Drop target decides the action.** Between clips = insert (blue marker), on a clip = menu (Replace / Replace from Start / End / Insert / Cutaway / Split / PiP / Green Screen), above a clip = connect (green +).
9. **Copy, then Paste Adjustments by kind** (all, colour, crop, volume, filter, audio effect, speed, overlay) onto one or many clips.

### 3.2 Feedback
10. **Preview on your own footage.** The filter grid shows 35 thumbnails of the selected clip's frame; skimming a title, transition, map or background previews it in the viewer over your movie; themes play on hover; Match Color shows source and result side by side.
11. **Numbers appear while you drag**: "01:19" (new length, seconds:frames) at the edge being trimmed, percentages on the volume line, a length badge on hover ("2.0s", "4.0s – Title Text Here").
12. **One colour language**: yellow = selected / aligned, blue = landing spot, green + = connect, orange = used, green/red = favourite/rejected, purple = title, turtle/rabbit = speed, green/yellow/red waveform = level/distortion/clipping.
13. **Teach in place.** Empty states say what to do ("Drag and drop video clips and photos from the browser above…"); hints appear at the right moment ("Press the R key while dragging to select a range"); every tooltip names the action.
14. **Haptics at snap points** (Force Touch): crop box hits a guide, a drag passes a clip's edge, a title lands on a clip.

### 3.3 Defaults and forgiveness
15. **Good-looking defaults.** Titles 4 s; transitions 0.5 s; photos get Ken Burns (face-aware on iPhone); high-frame-rate clips become slow motion; 4:3 is cropped to fill 16:9; PiP starts in the top-right quarter; stabilise 33 %, noise reduction 50 %.
16. **Clamp, don't refuse.** A transition longer than the media allows becomes the longest possible; Fast on a too-short clip falls back to Custom.
17. **Whole-movie switches** for the common finishing touches: Theme, Filter, Fade in/out from black, Trim background music.
18. **No saving, no losing.** Autosave; deleting a project turns its media into an event; Reset/Undo everywhere; long jobs (import, stabilise, share) run in the background with a progress indicator while you keep working.

### 3.4 Keyboard and menus
19. **Single letters for the frequent things** (E Q W R X F U M N V, Space J K L, / \ ; '), ⌘ for commands, ⌥⌘ for the paste-adjustments family, ⇧ for "ten times" (⇧, ⇧.).
20. **Every action is in a menu** (Edit, Mark, Modify, View, Window), and the right-click menu repeats the clip's common actions with their shortcuts.

---

## 4. The 30 % that covers 90 % (full inventory, ranked)

The guide and menus describe roughly 150 distinct capabilities. Below are the ~45 that cover nearly everything people make with iMovie; the rest (libraries and events management, tape import, trailers, app previews, travel maps, Cinematic focus editing, Send to Final Cut Pro, Theater, ratings, render files) serve niches or bookkeeping. Each row is marked for Shorts (★★★ essential for a Short … ★ rarely) and for Shorts Editor (✅ have, ◐ partly, ❌ missing, ➖ not needed).

### Media and project
| Capability | Shorts | Us |
|---|---|---|
| Projects grid: create, open, rename, duplicate, delete, search | ★★★ | ✅ Home window |
| Autosave, no Save command | ★★★ | ✅ |
| Import from files and Finder drag | ★★★ | ✅ |
| **Photos library in the sidebar, no import needed** | ★★★ (phone footage lives there) | ❌ |
| Import window with preview by hovering, Import Selected | ★★ | ◐ Open panel |
| Record from the Mac's camera into the project | ★ | ❌ |
| Browser: thumbnails in the clip's own shape, length on hover, **orange "used" stripe**, search, sort | ★★ | ◐ list, no used marks |
| Favourite / reject ranges | ★ | ➖ |

### Viewing
| Capability | Shorts | Us |
|---|---|---|
| **Skimming** timeline and media; audio skimming toggle | ★★★ | ❌ |
| Space / J K L / frame step / Home End | ★★★ | ✅ |
| Play selection (/), play from beginning (\), play around (⇧?) | ★★ | ❌ |
| **Loop playback** (⌘L) | ★★★ (Shorts loop) | ❌ |
| **Play full screen** (⇧⌘F) | ★★ | ❌ |
| Next/previous edit (; '), markers (M) | ★★ | ❌ |

### Editing
| Capability | Shorts | Us |
|---|---|---|
| Magnetic storyline, drag to reorder | ★★★ | ✅ |
| Split (⌘B), drag-trim with snapping | ★★★ | ✅ |
| **Range selection (R)** in media and timeline | ★★★ | ❌ |
| **E / W / Q** add, insert, connect from the browser | ★★★ | ◐ (Q/W used for trim to playhead) |
| **Drop on a clip → Replace / Insert / overlay types** | ★★ | ❌ |
| Trim to Selection / Trim to Playhead | ★★★ | ◐ to playhead only |
| Live length tooltip and badges while trimming | ★★ | ❌ |
| Clip Trimmer (source with used part, slide) | ★★ | ❌ |
| Precision Editor / split edits (J- and L-cuts) | ★★ | ❌ |
| Detach audio | ★★ | ◐ ("use video's sound as music") |
| **Connected items follow their clip** | ★★★ | ❌ (B-roll, titles, sounds stay at their time) |
| Copy / **Paste Adjustments** by kind | ★★ | ❌ |
| Select in Movie by kind; Select All; rectangle | ★ | ✅ |
| Undo everything | ★★★ | ✅ |

### Titles and graphics
| Capability | Shorts | Us |
|---|---|---|
| Title styles with live preview, double-click to add | ★★★ | ◐ 5 styles, no preview grid |
| Text edited in the viewer; font, size, colour, outline | ★★★ | ✅ (better: box, shadow, saved styles) |
| Title placement rules (thirds, whole clip), snapping | ★★ | ◐ snapping only |
| Backgrounds (solid/gradient) as clips | ★★ (text-only intro cards) | ❌ |
| Captions | ★★★ | ✅ (iMovie has none) |

### Transitions
| Capability | Shorts | Us |
|---|---|---|
| **Cross dissolve ⌘T**, a small set of others | ★★ | ❌ |
| Default length, Apply to all, clamp to media | ★★ | ❌ |
| Automatic content from a theme | ★ | ❌ |

### Picture
| Capability | Shorts | Us |
|---|---|---|
| Fit / Crop to Fill | ★★★ | ✅ Show all / Fill screen |
| **Ken Burns start/end** | ★★★ | ✅ (motion presets + keyframes, more flexible) |
| Rotate | ★★ | ✅ |
| **Enhance (one click)** | ★★★ | ❌ |
| Colour balance: Auto, White Balance, Skin Tone, Match Color | ★★ | ❌ |
| Colour correction: shadows, brightness, contrast, highlights, saturation, temperature | ★★ | ❌ |
| **Filters with strength**, whole-movie filter | ★★ | ❌ |
| **Stabilize**, rolling shutter | ★★ (handheld phone footage) | ❌ |
| Fade to B&W/sepia/dream; Flash and Freeze | ★ | ❌ |

### Layers
| Capability | Shorts | Us |
|---|---|---|
| Cutaway / B-roll | ★★★ | ✅ |
| Picture in picture (drag, resize, border, shadow, keyframed position) | ★★★ | ✅ (no border/shadow) |
| Split screen | ★★★ | ✅ top/bottom (iMovie adds left/right, slide-in) |
| **Opacity and fade in/out of the overlay** | ★★ | ❌ |
| **Green/blue screen** | ★★ | ❌ (roadmap: background removal) |

### Time
| Capability | Shorts | Us |
|---|---|---|
| Slow / fast presets, custom, preserve pitch | ★★★ | ✅ |
| **Freeze frame** (3 s) | ★★ | ❌ |
| **Speed on a range with smooth ramps** | ★★ | ❌ |
| Reverse, instant replay, rewind | ★★ | ❌ |
| Automatic slow motion for 60/120/240 fps clips | ★★ | ❌ |

### Sound
| Capability | Shorts | Us |
|---|---|---|
| Background music, fitted to the movie | ★★★ | ✅ |
| Sound effects library | ★★★ | ✅ (7 built in; iMovie ~95) |
| Voiceover with mute-project option | ★★★ | ✅ |
| **Volume line on clips, range volume, keyframes** | ★★ | ❌ (one level per clip) |
| **Fade handles on clip sound** | ★★ | ❌ |
| Ducking ("Lower volume of other clips") | ★★★ | ✅ automatic (better) |
| Auto volume, noise reduction, EQ presets | ★★ | ◐ Clean up voice + loudness on export |
| Voice effects (robot, chipmunk, telephone, radio…) | ★★ (meme Shorts) | ❌ |
| Waveform level colours (yellow/red) | ★ | ❌ |

### Finishing
| Capability | Shorts | Us |
|---|---|---|
| Export file with presets and size estimate | ★★★ | ✅ (no estimate) |
| **Export current frame as an image** | ★★ (thumbnail/cover) | ❌ |
| Themes (titles + transitions + music bundle) | ★★ as "Shorts styles" | ❌ |
| Magic Movie / Storyboards (iPhone) | ★★★ as "Shorts templates" | ❌ |

---

## 5. Where iMovie falls short for Shorts (and where we're already ahead)

Verified in the hands-on session: **iMovie for Mac has no vertical movies.** The project takes its format from the first clip, but a vertical 1080×1920 clip added first still produced a **16:9 1080p project with the clip pillarboxed** (screen `02`); Crop to Fill then shows only a thin horizontal slice. The browser preview looked vertical, which is misleading. The iPhone guide never mentions portrait either. Every iMovie default (16:9 crop frame, lower thirds, PiP size, 4:3 → 16:9 auto-crop) assumes a landscape movie.

Other gaps for a Shorts creator:
- No captions, transcription, edit-by-text or pause removal.
- No awareness of YouTube's covered areas, the 3:00 limit, loudness targets or the first second.
- Titles: no saved styles, few fonts per style, no word-by-word animation.
- Keyframes only for PiP position and volume; Ken Burns is just start and end.
- **Apply buttons** (✓) for crop, titles, overlays: a step that our live edits don't need.
- Music is manual: ducking is a per-clip checkbox and a slider.

Shorts Editor already beats iMovie on: vertical canvas, captions, Remove Pauses, edit by text, automatic ducking, −14 LUFS, voice clean-up, follow the subject, keyframes with presets, saved text styles, export checks.

**So the target is: iMovie's grammar and breadth (§3, §4) on top of our Shorts-specific strengths.**

---

## 6. What to take from iMovie, ranked

Recommendations for the build step, grouped so each group can be one stage like the earlier ones. "Better than iMovie" notes say how to adapt each idea to Shorts.

### Stage A: iMovie's grammar (feel, not features). Highest value per hour.
1. **Skimming** on the timeline and in Media: hover shows the frame in the viewer, a white skimmer line, Space plays from the skimmer, ⇧S audio skimming. _Better:_ also skim title/caption/motion style pickers on the real frame.
2. **Live numbers while dragging**: length tooltip at a trimmed edge (seconds and frames), length badge on hover, time at the drop point when moving.
3. **Range selection (R)** on timeline clips and in Media, used by: add part of a file, trim to range (⌥/), speed for a range, volume for a range (with automatic fades), delete range.
4. **Connected items follow their clip**: B-roll, titles, sounds and voice-overs pinned to the main clip under their start (a pin line in the timeline), so moving, trimming, speed changes and Remove Pauses carry them along. Keep "stay at this time" as an option for music-timed items. (Model change: an anchor clip ID + offset, like captions already follow their file.)
5. **Drop-on-clip menu**: dropping media on a clip offers Replace, Replace from Start, Replace from End, Insert, As B-roll, Split Screen, Picture in Picture. Blue landing marker between clips, green + above.
6. **Reset per inspector section + Reset All**, and **Copy / Paste Settings ▸ All, Picture, Motion, Speed, Sound, Look, Text** for one or many clips (⌥⌘V family).
7. **E / W keys from Media** (add to end / insert at playhead), with a **+** button on media items; an **orange "used" mark** on Media items.
8. **Loop playback (⌘L), Play full screen (⇧⌘F)** shown in a phone frame with YouTube's interface drawn over it, play selection (/), play from start (\), previous/next edit (; ').
9. **Teach in place**: empty-state hints in every lane, one-line tips the first time a gesture would help (as iMovie does for R).

### Stage B: Look
10. **Enhance** (one click: auto colour + auto level) and **Auto** in the Look section.
11. **Colour**: white balance by clicking the viewer, skin tone, exposure/contrast/highlights/shadows, saturation, temperature (Core Image), with a before/after toggle. **Match Color** between clips of the same Short.
12. **Filters**: 10–12 looks that suit Shorts (Vivid, Warm, Cool, B&W, Noir, Film, Fade, Vintage, Dreamy, Teal & Orange…), a grid previewed on the selected clip's frame, strength slider, "Apply to all clips" and a whole-Short filter.
13. **Stabilize** with an amount (Vision image registration, analysed in the background).

### Stage C: Transitions and time
14. **Transitions**: Cross Dissolve (⌘T), Fade through black/white, Slide, Zoom, Whip/blur, Wipe: 6–8, previewed by skimming; one default length (0.5 s) in Settings, Apply to All, clamp to available media.
15. **Freeze frame** (⌥F, 3 s, silent), **Reverse**, **Instant Replay** (repeat a moment slower), **speed on a range with Smooth ramps**, **automatic slow motion** for 60/120/240 fps clips.
16. **Opacity and fade in/out** for B-roll (and keyframed opacity).

### Stage D: Sound like iMovie, smarter
17. **Volume line on clips**: drag up/down with a percentage, range volume with automatic fades, keyframes with ⌥-click; **fade handles** on every clip's sound.
18. **Detach Audio** (⌥⌘B) and **J/L cuts** (sound starting before / continuing after the picture).
19. **Voice effects** (Robot, Chipmunk, Deep, Telephone, Radio, Echo, Megaphone, Underwater) with AVAudioUnit effects; EQ presets (Voice, Music, Less bass); waveform turning yellow/red when clipping.
20. A bigger **sound effects library** (still synthesized or royalty-free), grouped like iMovie's (Whooshes, Hits, Risers, UI, Cartoon, Ambience).

### Stage E: Media and finishing
21. **Photos library in Media** (PhotoKit, with the user's permission): iPhone footage without exporting files first; iCloud downloads with progress.
22. **Clip trimmer**: the whole source with the used part bright; drag edges or slide the used part (⌘\).
23. **Export current frame** as JPEG/PNG (for the Short's thumbnail), and a **size estimate** in the export sheet.
24. **Markers** (M) with names, snapping to markers; groundwork for beats.
25. **Settings** like iMovie's: picture length, picture placement (Fill / Show all / slow zoom), transition length, automatic slow motion.

### Stage F: One-click Shorts (iMovie's Themes, Magic Movie and Storyboards, made for Shorts)
26. **Shorts styles** (like Themes): a bundle of title look, caption style, transition, motion and music mood, switchable any time, applied to the whole Short.
27. **Magic Short**: pick clips (or one long video) → a first cut with pauses removed, captions, a hook title, punch-ins, music and a loop-friendly ending, then edited normally.
28. **Shorts storyboards**: templates with a shot list that says what to film and for how long (Hook 0–2 s, Problem, Steps 1–3, Payoff, Call to action), for tutorials, reviews, before/after, top 3, day-in-the-life.

### Not taking
Libraries, events and ratings (the home window is enough), trailers (their storyboard idea lives on in Stage F), app previews, travel maps, tape and camera import, Send to Final Cut Pro, Theater, Cinematic focus editing, Apply buttons (we keep live edits with undo), 16:9 anything.

---

## 7. Suggested order

| Order | Stage | Why first |
|---|---|---|
| 1 | **A. Grammar** | Makes every existing feature feel like iMovie; mostly UI on top of the current model, except item 4 (anchoring), which also fixes a known limitation (B-roll doesn't follow its clip). |
| 2 | **D. Sound** | Volume lines and fades on clips are basics people miss within minutes. |
| 3 | **C. Transitions and time** | Cross dissolve, freeze frame and ramps are among the most-used iMovie features after cutting. |
| 4 | **B. Look** | Enhance + filters lift every Short; needs a colour pipeline in `ShortsCompositor`. |
| 5 | **E. Media and finishing** | Photos library, trimmer, frame export, markers. |
| 6 | **F. One-click Shorts** | Builds on everything above (styles need transitions, looks and captions in place). |

Each stage follows the project's usual shape: model and tests in `EditorCore`, rendering in `RenderEngine`, UI and an `EditorModel` method, then an on-screen check.
