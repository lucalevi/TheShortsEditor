# iMovie reference: menus, shortcuts, controls, catalogues

_Collected 2026-11-09 from iMovie **10.4.5** on this Mac (live menus read through Accessibility, resource files in the app bundle, a hands-on session in a scratch library) and Apple's iMovie User Guide for Mac (10.4.4). Raw dumps next to this file: `imovie-menus-raw.txt` (live menu bar, modifier codes: 0 = ⌘, 1 = ⇧⌘, 2 = ⌥⌘, 8 = no modifier, 9 = ⇧, 10 = ⌥, 11 = ⌥⇧, 12 = ⌃, 13 = ⌃⇧), `imovie-commandset-raw.txt` (the default key set, shared with Final Cut Pro, so it lists commands iMovie doesn't show)._

The analysis is in `imovie-reverse-engineering.md`. This file is the lookup table.

---

## 1. Window anatomy

```
┌ toolbar: ‹ Projects │ Media/Audio toggle │ Import ↓ │ project name ……………………… Share ⤴ ┐
├ browser (top left) ─────────────────────────┬ viewer (top right) ────────────────────┤
│ tabs: My Media · Audio & Video · Titles ·   │ adjustments bar: ✨Enhance │ [overlay] │
│       Backgrounds · Transitions             │  Color Balance · Color Correction ·   │
│ sidebar: Project Media · Photos · All Events│  Crop · Stabilization · Volume ·      │
│          · libraries › events               │  Noise Reduction & EQ · Speed ·       │
│ header: event name · All Clips ▾ · Search ⚙ │  Filter & Audio Effects · Info · Reset All
│ thumbnails at the clip's own shape,         │ tool row (changes with the tool)      │
│ duration badge on hover, orange = used,     │ picture                               │
│ green = favourite, red = rejected, + to add │ 🎤 voiceover · ◀◀ ▶ ▶▶ · full screen   │
├ timeline ─────────────────────────────────────────────────────────────────────────┤
│ 00:04 / 00:09                                            zoom slider · Settings   │
│ titles (purple bars) and connected clips above the storyline, pinned to a clip     │
│ storyline: clips with filmstrip + waveform, transitions between them              │
│ ♫ background music well                                                          │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Empty states: the browser shows a big **Import Media** button; the empty timeline says "Drag and drop video clips and photos from the browser above to start creating your movie." Projects view: **Create New** tile (popover: Movie / Trailer, each with a one-line description), one tile per project, "All Projects ▾" and Search above.

## 2. Menu bar (iMovie 10.4.5, English)

| Menu | Items (shortcut) |
|---|---|
| **iMovie** | About, Settings… ⌘, · Provide Feedback… · Hide ⌘H · Hide Others ⌥⌘H · Quit ⌘Q |
| **File** | New Movie ⌘N · New Trailer… ⇧⌘N · New App Preview · New Event ⌥N · Import Media… ⌘I · Import iMovie iOS Projects… · Open Library ▸ (libraries, New…, Other…, Clear Recents) · Close Library · Copy to Library ▸ · Move to Library ▸ · Merge Events · Consolidate Library Files… · **Share ▸ Email… / Social Platforms… / Image… / File…** · Convert Trailer to Movie · Reveal in Event ⇧F · Reveal in Finder ⇧⌘R · Update Projects and Events… · Delete ⌘⌫ |
| **Edit** | Undo ⌘Z · Redo ⇧⌘Z · Cut ⌘X · Copy ⌘C · Paste ⌘V · **Paste Adjustments ▸ All ⌥⌘V, Color Correction ⌥⌘C, Crop ⌥⌘R, Volume ⌥⌘A, Clip Filter ⌥⌘L, Audio Effect ⌥⌘O, Speed ⌥⌘S, Video Overlay Settings ⌥⌘U, Map Style ⌥⌘M** · Delete ⌫ · Delete Keyframes ⌥⇧⌫ · Duplicate Project ⌘D · Select All ⌘A · **Select Entire Clip X** · Select in Movie ▸ Video Clips / Transitions / Photos / Maps / Backgrounds · Deselect All ⇧⌘A · **Add to Movie E · Add Connected Media Q · Insert W** · Add Cross Dissolve ⌘T · Find… ⌘F · Writing Tools ▸ · Emoji & Symbols |
| **Mark** | Favorite F · Reject ⌫ · Unrate U · Add Marker M · Delete Marker ⌃⇧M |
| **Modify** | **Enhance ⇧⌘E** · Fade to ▸ Black and White / Sepia / Dream · **Flash and Freeze Frame** · Mute Audio ⇧⌘M · **Trim to Selection ⌥/** · Trim Clip Edge ▸ Nudge Left , / Right . / Left Many ⇧, / Right Many ⇧. · **Split Clip ⌘B** · Join Clips ⇧⌘B · **Detach Audio ⌥⌘B** · Slow Motion ▸ 50% / 25% / 10% · Fast Forward ▸ 2× / 4× / 8× / 20× · **Instant Replay ▸ 100% / 50% / 25% / 10%** · **Rewind ▸ 1× / 2× / 4×** · **Add Freeze Frame ⌥F** · Reset Speed ⌥⇧R · Adjust Clip Date and Time… |
| **View** | Play Space · Play Selection / · Play from Beginning \ · Play Full Screen ⇧⌘F · Loop Playback ⌘L · Sort Events By ▸ · Sort By ▸ Date/Name/Duration, Ascending/Descending · Show Separate Days in Events · Show Audio Waveforms · Show Used Media Ranges · Show Skimmer Info ⌃Y · Zoom In ⌘+ · Zoom Out ⌘− · Zoom All Clips ⇧Z · **Snapping N** · **Audio Skimming ⇧S** |
| **Window** | (system items) · Go to Media 1 · Go to Projects 2 · Show Libraries ⇧⌘1 · Content Library ▸ My Media ⌘1, Audio & Video ⌘2, Titles ⌘3, Backgrounds ⌘4, Transitions ⌘5 · Theme Chooser… ⌘6 · Clip Trimmer ⌘\ · Precision Editor ⌘/ · **Record Voiceover V** · Revert to Original Layout |
| **Help** | iMovie Help · What's New in iMovie · Keyboard Shortcuts · Supported Cameras |

Timeline clip **right-click menu** (seen): Play (Space) · Cut ⌘X · Copy ⌘C · Delete ⌫ · Split Clip ⌘B · Add Freeze Frame · Detach Audio ⌥⌘B · **Trim to Playhead ⌥−** · Show Clip Trimmer ⌘\ · Adjust · Show Speed Editor ⌘R · Show Cinematic Editor ⌃⌥F · Add Cross Dissolve ⌘T · Reveal in Project Media ⇧F.

## 3. Keyboard shortcuts (Apple's table, complete, plus ones only seen in the app)

| Area | Keys |
|---|---|
| Play | Space play/pause from the playhead **or the skimmer** · / play selection · \ play from beginning · ← → one frame · ↓ (browser, playing) next clip · ↑ (timeline) start of clip / previous clip · ⇧⌘F full screen · Esc exit · ⌘L loop · ⌃Y skimmer info · J / K / L (reverse / stop / forward, repeat for faster) · ⇧? play around · ; ' previous / next edit · ⌃; ⌃' previous / next marker · Home / End |
| Projects | ⌘N new movie · ⌘⌫ move to Trash · ⌘, settings |
| Select & edit | ⌘A select all · **X select entire clip** · **hold R + drag = range** · ⇧⌘A deselect · **E add to end** · **Q connect at playhead** · **W insert at playhead** · ⇧⌘E enhance · ⌘X ⌘C ⌘V · ⌥/ trim to selection · ⌥− trim to playhead · ⌘B split · ⇧⌘B join · ⌥⇧R reset speed · ⌥⌘V/C/R/A/L/O/S/U/M paste adjustments (all / colour / crop / volume / filter / audio effect / speed / overlay / map) · F favourite · U unrate · ⌫ reject (browser) or delete (timeline) · ⌘\ clip trimmer · ⌘/ precision editor · ⌥⌘F cinematic editor · , . nudge edge (⇧ = 10) · M marker · N snapping · ⌘T cross dissolve · ⌥F freeze frame |
| Audio | V voiceover · ⇧S audio skimming · ⇧⌘M mute clip · ⌥⌘B detach audio · ⌃= / ⌃− volume ±1 dB |
| Window | 1 media · 2 projects · ⇧⌘1 libraries list · ⌘1–⌘5 browser tabs · ⌘6 themes · ⌘= ⌘− zoom · ⇧Z zoom to fit |
| Gestures | pinch on the timeline = zoom · Force Touch: harder press on Next/Previous = faster; haptic tick when the crop box snaps to a guide, when dragging past a clip's start/end, when a title lands on a clip |

Pattern: **single letters for the things done hundreds of times per movie** (E Q W R X F U M N V, Space J K L, / \ ; '), ⌘ for commands, ⌥⌘ for the "paste adjustments" family, ⇧ for "more" (⇧, ⇧. move 10).

## 4. The adjustments bar, tool by tool (seen in the app; defaults on this Mac)

| Button | Row that appears | Defaults / values |
|---|---|---|
| ✨ Enhance (wand, far left) | one click; lights up Color Balance, Color Correction and (if useful) Volume | applies to the whole clip even if a range is selected |
| [Video Overlay] (only for connected clips, appears first and opens by itself) | type ▾ **Cutaway / Green/Blue Screen / Split Screen / Picture in Picture**, then per type: Cutaway: Opacity, Fade (s). Split: Position ▾ (Left/Right/Top/Bottom), Slide (s). PiP: transition ▾ (Dissolve/Zoom/Swap) + seconds (0,5), Border (none/thin/thick), colour, Shadow; keyframe strip ◀ ◆ ▶ and Reset inside the viewer. Green: Softness, Crop, Clean-up | Reset · ✓ Apply |
| T (only for titles) | Font ▾ (… Show Fonts) · Size (Auto ▾) · align left/centre/right/justify · B I O (outline) · colour · Reset · ✓ | text edited in place in the viewer, Tab to the next field |
| Color Balance | Auto · Match Color · White Balance · Skin Tone Balance · Reset | eyedropper + instruction above the viewer; Match Color shows source left / result right |
| Color Correction | multislider (shadows ● brightness ● contrast ◐◑ highlights ●) · Saturation · Color Temperature · Reset | |
| Crop | Style: **Fit / Crop to Fill / Ken Burns** · rotate ⟲ ⟳ · (Ken Burns: swap start/end ⇄) · Reset · ✓ | Ken Burns proposes **Start** and **End** boxes at once with an arrow; outside dimmed; the whole source shown while cropping; titles hidden |
| Stabilization | ☐ Stabilize Shaky Video [slider] **33 %** · ☐ Fix Rolling Shutter [Medium ▾] · Reset | checkbox becomes a spinner while analysing |
| Volume | **Auto** · mute · [slider] **100 %** · ☐ Lower volume of other clips [slider] · Reset | |
| Noise Reduction & EQ | ☐ Reduce background noise [slider] **50 %** · Equalizer [**Flat** ▾] · Reset | presets include Voice Enhance, Music Enhance, Loudness, Hum Reduction, Bass Boost/Reduce, Treble Boost/Reduce |
| Speed | Speed [Normal ▾ = **Normal / Slow / Fast / Freeze Frame / Custom**] · Slow: 50 % 25 % 10 % · Fast: **2× 4× 8× 20×** · Custom: % · ☐ Smooth · ☐ Reverse · ☐ Preserve Pitch · Reset | clip shows a turtle/rabbit and a speed handle at its top; drag it to set any speed |
| Filter & Audio Effects | Clip Filter [None] + strength **100** · Audio Effect [None] · Reset | both open a grid chooser (see §6), previewed on the clip's own frame |
| Info (i) | clip name and date · Duration [2,0] s of 8.0s | |
| Cinematic (only for Cinematic-mode clips) | Depth of Field + focus points | |
| **Reset All** (far right) | clears every adjustment of the selection | |

Project **Settings** (timeline header): resolution (here "1080p", from the first clip) · Theme [No Theme] · ☐ Automatic content · Filter [None] (whole movie) · ☐ Trim background music · ☐ Fade in from black · ☐ Fade out to black · Clip Size slider · Audio: ☑ Show Waveforms.

App **Settings** (⌘,): ☑ Apply slow motion automatically (clips over 30 fps) · Photo Placement [Ken Burns ▾ / Fit / Crop to Fill] · Photo Duration 2,0 s (on this Mac) · Transitions 1,0 s (on this Mac; the guide says 0.5 s standard, 2 s for theme transitions) · Render Files: Delete.

## 5. Numbers worth copying

| What | Value |
|---|---|
| New title | 4.0 s; dropped on a clip's first or last third → that third; dropped in the middle → whole clip |
| Transition | 0.5 s standard (setting), 2 s theme transitions; too long → longest the media allows |
| Freeze frame | 3 s, no sound, selected after adding |
| Photo | Ken Burns by default; duration from settings (iOS: Ken Burns with face detection) |
| Slow / fast | Slow 50 % (25 %, 10 %), Fast 2× (4×, 8×, 20×); clip under 0.1 s → Custom |
| High-frame-rate clip | slowed automatically to the movie's rate; Auto over 3 s ramps speed at both ends |
| PiP | starts top-right, about a quarter of the frame; Dissolve 0.5 s |
| Stabilize 33 %, noise reduction 50 %, filter strength 100, volume 100 % | defaults |
| Volume range | changing part of a clip adds fades at both edges automatically |
| Waveform colours | green fine, yellow distortion, red clipping |
| Export | 9 s → "23 MB est." shown before saving; Resolution 1080p, Quality High, Compress Faster; e-mail warns above 10 MB |
| iOS sharing | Mail/Messages copies are 360p 30 fps; 60 fps offered only when over half the media is 60 fps |

## 6. Catalogues

**Clip filters (35, grid chooser):** None, Flipped, Black & White, Noir, Silent Era, Comic Basic, Comic Cool, Comic Ink, Comic Mono, Comic Vintage, Camo, Heat Wave, Blockbuster, Vintage, Western, Film Grain, Aged Film, Sepia, Vignette, Romantic, Cartoon, Blue, Blast, Hard Light, Bleach Bypass, Glow, Old World, Flashback, Dreamy, Raster, Day into Night, X-Ray, Negative, Sci-Fi, Duotone.

**Colour presets in the bundle (20):** Alien Lab, Artificial Light, Ash, Brighten, Cold CCD, Contrast, Cool, Dew, Dim, Dry, Dust, Fall Sun, Frost, Moonlight, Night, Sewer, Spring Sun, Summer Sun, Warm, Winter Sun.

**Transitions (24 + theme ones):** Cross Dissolve, Cross Blur, Fade to Black, Fade to White, Spin In, Spin Out, Circle Open, Circle Close, Doorway, Swap, Cube, Mosaic, Wipe Left/Right/Up/Down, Slide Left/Right, Puzzle Left/Right, Page Curl Left/Right, Cross Zoom, Ripple. Each theme adds 4 (e.g. "Comic Book 1–4").

**Titles (≈50, grouped Simple / Build In-Out / Bumper-Opener / Lower Thirds / Credits):** pairs of a full-frame and a "Lower Third" version: Slide, Split, Chromatic, Standard, Expand, Reveal, Focus, Line, Pop-up, Gravity, Prism (each + Lower Third); Centered, Lower Third, Upper Third, Organic Main/Lower, Gradient White/Black, Torn Edge Tan/Black, Clouds, Overlap, Four Corners, Ticker, Sideways Drift, Zoom, Far Far Away, Boogie Lights, Lens Flare, Scrolling Credits, Credits 1–3; plus theme titles (Opening, Middle, Ending). Titles show the style's placeholder text in the user's language ("Testo del titolo" on this Mac).

**Themes (15):** No Theme, Bright, Bulletin Board, Comic Book, Filmstrip, Kids, Modern, Neon, News, Newscast, Photo Album, Scrapbook, Simple, Sports, Travel. A theme = opening/middle/ending titles + 4 transitions + theme music (7 tracks in the bundle: Bright, Modern, Neon, News, Playful, Simple, Travel).

**Overlay types (4):** Cutaway, Green/Blue Screen, Split Screen, Picture in Picture.

**Sound effects:** ~95 in "iMovie Sound Effects" (Whoosh-like: Sweep Motion, Sci-Fi Sweep, Title Flange Sweep Hit, Bell Transition, Cartoon Boing, Heartbeat, Clock Tick, Typewriter, crowd, weather, sports, animals, doors…) plus folders Ambience, Animals, Booms, Foley, Jingles, Machines, People, Sci-Fi, Sports, Stingers. Audio browser sidebar: Music (the Music app's library), Apple TV, Sound Effects; list with Name / Time / Genre / Artist / Album, waveform at the top to pick a range.

**Audio effects / EQ presets (≈150 names in the bundle):** voice: Robot, Alternate/Average Robot, Android, Alien, Martian, Monster, Chipmunk, Squirrel, Mouse, Helium, Cartoon Animals, Disguised (Male/Female), Telephone, Cellphone Earpiece, Walkie Talkie, Shortwave Radio, Car Radio, Television, Vintage Radios (1931, 1945, 1957, 1967 Pocket Transistor), Cheap Speakers, Underwater, Muffled, Next Door, Cosmic, Spaceship; rooms: Small/Medium/Large Room, Lecture Room, Cathedral, Modest Church, Big Cave Echo, Canyon Echo, Metallic PA Echo; tools: Voice Enhance, Voice Over Enhancement, Punchy/Smooth Male/Female VO, Dialogue, Music Enhance, Loudness, Hum Reduction, Rumble Reducer, Mud Removal, Bass/Treble Boost/Reduce, Low/High Cut, Limiter, Brickwall, Chorus, Doubler, Echo Delay, Tremolo, Pitch, Multi-Tune.

## 7. Colour and shape language

| Mark | Meaning |
|---|---|
| Yellow border with handles | selected clip or range (browser and timeline) |
| Yellow vertical line | snapping alignment |
| Yellow guides in the viewer | centre / edge alignment while moving a picture |
| Blue box / outline while dragging | where the clip will land |
| White border on drop target | drop will replace (menu on release) |
| Green "+" pointer and a line to the clip | drop will connect (cutaway etc.) |
| Orange stripe on a browser clip | already used in the project |
| Green / red stripe | favourite / rejected range |
| Purple bar | title; a vertical line pins it to a clip |
| Blue waveform band | clip sound; green bar = detached / audio-only clip; background music in its own well |
| Turtle / rabbit badge | slowed / sped up |
| "2.0s" badge (top left of a clip, on hover) | clip length |
| "01:19" tooltip while trimming | new length, seconds:frames |
| Diagonal lines | transition overlap |
| White skimmer line | where the pointer is (follows hover; Space plays from it) |
| Red playhead triangle | the playhead |

## 8. iMovie for iPhone extras (guide 3.0.x)

- **Magic Movie**: pick clips (order = tap order) → movie with soundtrack, transitions and titles made for you; edit as a list of clips (groups, rename, reorder, swipe to delete, duplicate); **Styles** (transitions + music + title font + title colours), Music, Font, Color, Filter, all for the whole movie; Reset.
- **Storyboards**: templates for common video types (cooking, product review, science experiment…), a shot list of placeholders that say what kind of shot goes there; fill each with library media or the camera; styles as above.
- Per clip: trim/split by handles, speed slider 1/8× to 2×, volume with a second "Soundtrack" slider, voiceover with 3-second countdown and Retake/Review/Accept.
- Soundtracks fit the length of the project automatically (and loop by default); music under 1 minute behaves as a sound effect.
- Ducking is automatic while a clip has sound; off when that clip is muted.
- Titles: drag to move, pinch to resize, Lower Third, Uppercase, Text Shadow, Full Clip Duration, optional sound effect.
- Undo/redo history only back to when the app was last opened; shake to undo.
- The guide never mentions portrait, vertical or 9:16.
