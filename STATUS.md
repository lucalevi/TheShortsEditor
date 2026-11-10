# Project status

_Last updated: 2026-11-10 (Stage C). Read this first when picking the project back up, then update it at the end of each session._

## Where we are

Stages 1–7 are done, tested on screen, committed and pushed to https://github.com/lucalevi/TheShortsEditor (public, branch `main`):

| Stage | What | Session |
|---|---|---|
| 1 | Foundation: import, viewer, magnetic timeline, framing, playback, undo | 2026-11-07 |
| 2 | Auto-captions | 2026-11-08 |
| 3 | Export to a YouTube-ready MP4, with pre-export checks | 2026-11-08 |
| 4 | Remove Pauses (silence removal) | 2026-11-08 |
| 5 | Titles (text overlay for the hook) | 2026-11-09 |
| 6 | Audio: clip volume, music with ducking, loudness on export | 2026-11-09 |
| 7 | Save/open projects, autosave, missing media | 2026-11-09 |

**Pick up here (2026-11-10, latest):** Stage C of the iMovie list ("Transitions and time", `research/imovie/imovie-reverse-engineering.md`) is built, tested and checked on screen, **not committed yet** (the user commits each stage). Stages A (d46eb5e) and D (99a303b) are committed. Next in the suggested order: B (look), E (media and finishing), F (one-click Shorts). Ask the user which one. Test footage and a closed scratch iMovie library are in `~/Movies/ShortsEditorResearch` (safe to delete). The on-screen checks left test Shorts "My Short 5"–"My Short 12" in the library (safe to delete from the home window).

### Stage C: transitions and time (2026-11-10): done, not committed yet

Model in `EditorCore/Transitions.swift` and `EditorCore/TimeEffects.swift` (`TransitionsAndTimeTests`, 28 tests); `RenderEngine/TransitionMixer.swift`, `FrameStills.swift`, `Reverser.swift` and the builder/compositor (`TransitionsAndTimeRenderTests`, 14); app in `App/EditorModel+Time.swift` and `App/Views/TimeViews.swift`. Project files are now version 4.
1. **Transitions** between main clips: Dissolve, Through Black, Flash (through white), Slide, Slide Up, Zoom, Whip, Wipe. Kept on the clip before the cut (`Clip.transitionOut`, a `ClipTransition`: SwiftUI already has a `Transition`), so a split keeps it at the cut. **The Short keeps its length**: the transition plays over the half before the cut and the half after (`Timeline.transitionSpans`); it takes at most half of each neighbouring clip, so a short clip makes it shorter. In its first half the next clip shows early, in its second the old clip runs on: more of their files where there is more (on a second video track), else held on their first/last picture. Default 0.5 s (14 frames, always an even number), 0.2–2 s.
   - Add: toolbar **Transition** button (adds on the cut nearest the playhead and opens the picker), **⌥T** (Clip ▸ Transition ▸ Add … at Nearest Cut, the last kind used), the clip inspector's **Into the next clip** grid, or the clip's right-click menu. With one clip selected, the nearer of its two cuts is used.
   - A white square on the cut marks it; click it for the picker (kinds, None, Length, Play It, Use on Every Cut, Remove All Transitions). Choosing a kind plays it once. Skimming over the cut shows it too.
2. **Freeze frame** (⌥F, Clip menu, clip inspector, right-click): the clip is cut at the playhead and a 3 s silent clip of that one picture goes in between (`Clip.isFrozen`), with the same framing; motion stops at that moment. Any length (drag its edges, or 1/2/3/5 s in the inspector). At the very end it holds the last picture. Read with `FrameStills` the way the player reads frames, so the held picture looks exactly like the moving one.
3. **Instant Replay** (Clip menu, clip and range inspectors, right-click): the range, the selected clips or the clip under the playhead plays once more straight after itself at half speed.
4. **Play backwards** (Speed section toggle, Clip menu, right-click; main clips and B-roll): `Reverser` writes a backwards copy of the file (picture and sound; whole files up to 1 minute, else the clip's part ± 3 s) into `Application Support/Shorts Editor/Backwards`, with progress on the clip; the copy is an ordinary media file marked `MediaAsset.reversedFrom`, and the clip points at it (`Project.flipDirection`), so trim, split, speed and motion just work. Turning back is instant.
5. **Speed changes gradually** (`Clip.smoothSpeed`, on by default; "Change speed gradually" in the Speed section): where a clip carries on from the same recording at another speed (e.g. speed set on a range), the picture goes through up to 5 steps of speed on each side of the cut over half a second (`Timeline.speedSegments`). Both clips together still show exactly the same footage in the same time, so nothing else moves.
6. **Slow-motion footage**: `MediaProbe` reads the frame rate (`MediaAsset.frameRate`); files at 100 fps or more start at ¼ speed when added (`MediaAsset.defaultSpeed`), and the Speed section says how far slow motion stays smooth for 60 fps and up.
7. **See-through B-roll**: `Placement.opacity` ("Solid" slider, 0–100%; it is part of the placement, so keyframes animate it) and picture fades in/out up to 2 s (`Clip.pictureFadeIn/Out`), in a "See-through and fades" section for clips over the others. Copy/Paste Settings ▸ Picture and Reset include them.

Tests: 254 model + 76 render + 3 transcription = 333, all pass.
Verified on screen: toolbar Transition → picker pop-up, choosing Slide (plays it; the frame on the cut shows both clips), the marker staying on its cut through later edits, ⌥F at 0:02 (2.0 / 3.0 freeze / 4.0, "Freeze frame" on the clip), Instant Replay of the last clip (8.0 s at 0.5×), Play Backwards on the horizontal clip (copy made in a few seconds, "(backwards)" file in Media, badge on the clip), B-roll at 45% solid with a 0.8 s fade in (blend in the viewer, badge on the block), speed 0.5× on half of a split clip → "Change speed gradually" on, playing 14 s straight through freeze, speed change, transition and backwards clip, quit + relaunch keeps everything, ⌥F and ⌥T from the keyboard.
Not yet verified on screen: the other transition kinds by eye (render-tested), the Length slider, Use on Every Cut / Remove All, the right-click menus, the freeze length buttons, the Fade out slider, opacity keyframes, Play Forwards again, a real 120/240 fps clip, the backwards sound by ear, an export of such a Short from the app (transitions in an export are render-tested).

### Stage D: sound like iMovie (2026-11-09): done, committed (99a303b)

Model in `EditorCore/SoundShaping.swift` (`SoundShapingTests`, 14 tests); `RenderEngine/SoundProcessor.swift` and the volume ramps in `CompositionBuilder` (`SoundShapingRenderTests`, 6); app in `App/EditorModel+Sound.swift`, `App/Views/VolumeLineEditor.swift`, `App/Views/SoundShapingViews.swift`.
1. **Volume line** on every main clip and every sound on the sound row (yellow, over the waveform; 100% is halfway up). Drag it up or down: 1% per point, in 5% steps, with a "Volume 80%" label. **⌥-click** adds a point (`Clip.volumeKeys`, in source time, so points survive split/trim; a point's level multiplies the clip's volume). The first point also pins the line at the clip's start and end, so dragging a point makes a dip or bump. ⌥-click a point to remove it; Remove Points in the inspector and the clip's right-click menu; Sound ▸ Add Volume Point at Playhead.
2. **Fades** (`Clip.fadeIn/fadeOut`, up to 5 s): white handles at the top corners of the selected clip's waveform (13 pt in from the edges, clear of the trim grips), or the Fades sliders in the inspector. Split, Remove Pauses and ranges keep the fade in on the first piece and the fade out on the last. A range's volume still fades over 0.2 s where it continues the same recording (`AudioMix.storylineEnvelope`).
3. **Too loud**: where the file's loudness × the clip's volume line goes over −6 dBFS (RMS per frame), the waveform bars are red and full height, the clip shows a warning triangle, and the inspector says how many seconds may crackle.
4. **Detach Sound** (⌥⌘B, Sound menu, inspector, clip right-click): the clip's sound becomes a "Sound of …" item on the sound row (`SoundClip.detachedFrom`) with its volume, fades, points and effect; the clip shows "Sound detached" and plays silent (`Clip.soundDetached`). Trim or move the item for **J/L cuts** (sound starting before the picture or carrying on after). Its sound still lowers the music. "Bring Sound Back" removes the item and unmutes the clip.
5. **Voice effects** (Robot, Chipmunk, Deep, Telephone, Radio, Echo, Megaphone, Underwater) and **Tone** presets (Clearer voice, Fuller music, Less bass), in the inspector and Sound ▸ Voice Effect. Made offline like voice clean-up: `SoundProcessor` renders a processed copy (AVAudioEngine: time-pitch, EQ, delay, reverb, plus ring modulation and overdrive by hand) into Caches, keyed by file + recipe, from the cleaned-up copy if the clip uses one. The change is applied once the copy is made (progress in the inspector). Missing copies (another Mac, cleared cache, voice clean-up switched later) are remade after each rebuild (`prepareMissingProcessedSounds`).
6. **Sound effects library**: 34 synthesized effects in six groups (Whooshes, Hits, Risers, Taps and alerts, Cartoon, Ambience), grouped in the Sounds panel and Sound ▸ Add Sound Effect. Ambience sounds are 12 s and quieter.
7. Copy/Paste Settings ▸ Sound and Reset include fades, points, effect and tone.

Tests: 226 model + 62 render + 3 transcription = 291, all pass. `Tools/uitest/ui.sh optclick X Y` added (⌥-click; `keydrag 58` didn't reliably hold ⌥).
Verified on screen: dragging the volume line (label, 150%, the warning disappearing below the limit, red bars at 200%), the fade-in handle (1.1 s, the clip's length unchanged), ⌥-click a point and dragging it into a dip, the inspector's sound section, Robot (copy made in Caches, icon on the clip), ⌥⌘B detach (sound row item with fade, points and effect; "Sound detached" on the clip; survives reopening), grouped Sounds panel, Rain added from the menu.
Not yet verified on screen: the effects and tone **by ear** (render-tested for length, level and bass removal only), trimming a detached sound beyond the picture (J/L cut, unit tested), the Tone picker, volume lines on B-roll (inspector fades only; no line drawn on B-roll blocks), fade-out handle, Bring Sound Back.

### Stage A: iMovie's grammar (2026-11-09): done, committed (d46eb5e)

Model in `EditorCore/Grammar.swift` (`GrammarTests`, 28 tests), app in `App/EditorModel+Grammar.swift`; the volume fade is in `CompositionBuilder`.
1. **Skimming**: hovering over the timeline shows that moment in the viewer under a white line; the playhead stays put (seeks are "chased", so it stays smooth). Space while skimming plays from the pointer. Hovering over a file in Media shows its frames in the viewer (`MediaProbe.frame`), with a mark on the file's bar. View ▸ Skimming turns it off; View ▸ Audio Skimming (⇧S) plays a tenth of a second of sound at each stop (rough: it briefly runs the player).
2. **Live numbers while dragging**: a label under the ruler: "Length 0:05.0 −0:01.0" at a trimmed edge (clips, B-roll, titles, sounds), "Starts at …" when moving an item, "Goes at …" when reordering, "Range …". While a main clip's edge is dragged, the viewer shows the frame at that edge.
3. **Ranges**: hold **R** and drag across clips (or empty space in the clip row), or press **X** for the clip under the pointer/playhead. Yellow frame with its length; the inspector becomes **Range**: Delete This Part (⌫), Keep Only This Part (Clip ▸ Trim to Range, ⌥/), Play It (/), speed of the part, volume of the part (sound fades over 0.2 s at its edges where it continues the same recording: `Clip.continues`), Mute This Part. Escape clears. Also in the clip right-click menu. In **Media**, drag across the bar under a file to pick a part (yellow frame); E, W and drops use that part.
4. **Items follow their clip**: titles, B-roll and sounds are pinned to the main clip under their start (thin line from the item to the clip, yellow when selected). `Project.followClips(from:)` runs inside `EditorModel.apply` after every edit: each item keeps the same moment of the same recording (move, trim, speed, delete earlier clips, Remove Pauses, insert, split). Items the edit itself moved and items whose clip was deleted keep their time. Inspector switch "Move with the clip under it" (`followsClip`, saved; older files read as on).
5. **Drop on a clip**: files dragged over the clip row show a "Put in here" bar near a cut (drop inserts there) or a dashed frame around a clip ("Drop for options"); dropping on a clip opens a menu: Replace, Replace from Start, Replace from End, Insert, Over the Clip (B-roll), Split Screen, Picture in Picture. Songs and Short files dropped there do what they did before. One undo step with the import.
6. **Settings**: Edit ▸ Copy Settings (⌥⌘C), Paste Settings ▸ All (⌥⌘V) / Picture / Motion / Speed / Sound / Title Design, onto every selected clip (motion lands at the same offset from the clip's start). Also in clip and title right-click menus and a Settings row in the clip and B-roll inspectors. **Reset All** (inspector, Clip ▸ Reset All Settings) and Reset per section (Picture now resets framing and background too; Speed got a Reset; Sound had one).
7. **E / W from Media**: with a file selected in Media, **E** adds it (or the chosen part) to the end, **W** puts it in at the playhead (cutting the clip there; playhead goes after it). Without a Media selection W still trims the end. A **+** button appears on hover. Files used in the Short say **Used** and their bar marks the used parts in orange (`Project.usedParts`).
8. **Playback**: **Loop** (⌘L, button in the transport bar, remembered), **Play Selection** (/: the range or the selected item, looping when Loop is on), **Play from Start** (\), **Previous/Next Edit** (; and ': cuts and item edges, `Project.editPoints`), **Play Full Screen** (⇧⌘F, button in the transport bar): the window goes full screen and shows the Short in a phone with a sketch of YouTube's buttons (like column, channel, description, progress line); Space plays/pauses, Escape or Done leaves. Punctuation keys are matched by character, so they work on Italian and other layouts.
9. **Teach in place**: one-time tips at the bottom of the timeline (skimming, R ranges, E/W in Media, items follow their clip, drop on a clip), kept in UserDefaults `shownTips` (delete it to see them again); "Titles go here" hint in the empty titles lane.

Tests: 212 model + 56 render + 3 transcription = 271, all pass. `Tools/uitest/ui.sh` gained `move` (hover), `hold`/`release` (screenshot a drag under way), `keydrag 15 …` (drag with R held) and `rawkey` (a key press that works while a pop-up menu is open).
Verified on screen: skimming (viewer frame, white line, playhead unmoved), Space from the skimmer, R-drag range + 2× on it (clip split into 4.8 / 1.7 at 2× / 3.5), title following when the first clip was deleted (0:12.1 → 0:07.3, pin line), live length label at a trimmed edge with the edge frame in the viewer, drop from Media on a clip → menu → Insert, W at 0:03.2 and E, a part chosen on the Media bar added with E (+1.5 s), Punch In → Copy Settings → Paste onto the next clip, Reset All, Next Edit, Loop + / (still looping inside the clip after 13 s), full screen in and out, X + ⌫ + undo, Media hover skimming, tips.
Not yet verified on screen: audio skimming by ear, Replace / Replace from Start/End, Split Screen and Picture in Picture from the drop menu, the "Put in here" bar (drop on a cut), dropping files from Finder on a clip, Paste Motion, the follow switch turned off, Remove Pauses carrying a title (unit tested), the volume fade by ear (render-tested), ; and \ on screen.

Earlier: the P0 list from the research is complete. On 2026-11-09 CapCut was analysed (`research/capcut-reverse-engineering.md`) and creator tool usage researched (`research/shorts-creator-tools-research.md`, with a gap table in §5), then distilled into the build list `research/feature-roadmap.md` (12 features, stages 8–16).

### Delete media from the media panel (2026-11-09): done
Select a file in the Media panel and press ⌫, or right-click ▸ Delete. It also removes the file's clips, B-roll, sounds, music and captions; one undo restores everything (`Project.removeAsset`, `EditorModel.removeAssets`). Checked on screen (key, right-click, undo). Not checked: deleting several files at once.

### Home window with every Short (2026-11-09): done, committed (44c6838)

Like iMovie's Projects browser. The app opens on **Shorts**, a grid of every Short (9:16 poster = a frame 1 s in, rendered by `ProjectPoster` through the compositor; length badge; name; last change), grouped Today / Yesterday / Previous 7 Days / month, newest first, with a **New Short** tile, a + button and **Search Shorts**. Click a Short to edit it. "…" button or right-click: Edit, Rename (inline, also by double-clicking the name), Duplicate ("… copy"), Delete… (asks; moves the file to the Trash, media untouched). Dropping videos on the home window starts a new Short with them.
- Editor toolbar: **‹ All Shorts** (⇧⌘0, File ▸ All Shorts) saves and goes back; next to it the Short's name, click to rename (Return keeps, Escape cancels). New Shorts are "My Short", "My Short 2"…; a Short left with no media isn't kept.
- Every Short lives in the library: `Application Support/Shorts Editor/Shorts/<UUID>.shortsproject` (+ `<UUID>.jpg` poster, remade when older than the file). `ProjectFile` gained optional `name` and `created` (still version 3; old files read fine). Autosave a second after each change, as before.
- File menu: New Short ⌘N, Open… ⌘O (a `.shortsproject` file from anywhere is **copied into the library** and opened; same when opened from Finder), All Shorts ⇧⌘0, Save ⌘S (saves now), **Save a Copy…** ⇧⌘S (writes a file anywhere, e.g. a backup). Open Recent, Save As… and the "Do you want to save" prompt are gone.
- First launch after the update moves the old unnamed Short (`Untitled.shortsproject`) and the projects in Open Recent into the library (once; `MovedIntoLibrary` default). On this Mac that gave "Untitled", which has 8 media files but no clips on its timeline. The move reads and rewrites the same data, so it shouldn't drop clips, but the original file was removed after the move and can't be checked.
- Tests: `ShortsLibraryTests` (names, copies, tidying typed names, search, date sections, name/date saved) and `ProjectPosterTests`. 182 model + 55 render + 3 transcription, all pass.
- Verified on screen: launch on home, New Short tile, videos opened from Finder go into it, rename in the toolbar, split then All Shorts (home shows the new name and time, poster), empty New Short (⌘N then back) not kept, Duplicate from the "…" menu, rename by double-click, search, Delete… with the confirmation, a Short opened from Finder on the home window, ⌘Q in the editor then relaunch (Short kept with poster).
- Not yet verified on screen: Open… with a `.shortsproject` from elsewhere, Save a Copy…, dropping videos on the home window, a library with Shorts from earlier months, many Shorts (no lazy poster loading limit beyond one at a time).

### Batch "features 6–12" (2026-11-09): done, committed (ca0fc32)

Features 1–5 are committed (`b764acb`). The user then asked for 6–12 in one go; a usage limit interrupted it once, then it was finished. All seven are built, tested and checked on screen. **Not committed yet** (the user commits each batch).

| # | Feature | Model + tests | Rendering + tests | UI | On screen |
|---|---|---|---|---|---|
| 6 | Speed | ✅ | ✅ | ✅ | ✅ |
| 7 | Text design | ✅ | ✅ | ✅ | ✅ |
| 8 | Captions that pop | ✅ | ✅ | ✅ | ✅ |
| 9 | Edit by text | ✅ | — | ✅ | ✅ |
| 10 | Sound layer | ✅ | ✅ | ✅ | ✅ |
| 11 | Auto reframe | ✅ | ✅ | ✅ | ✅ |
| 12 | Layouts | ✅ | ✅ | ✅ | ✅ |

Tests: 175 model + 54 render + 3 transcription = 232, all pass (`make test`).

What 6–12 added:
- **Speed** (Clip ▸ Speed, inspector Speed section with 0.5/1/1.25/1.5/2× and a slider 0.25–4×; also for B-roll and several selected clips): `Clip.speed`, `duration` stays the timeline length and the source covers `duration × speed`; voices keep their pitch (spectral pitch algorithm in the player, export and loudness meter). Captions, pauses, keyframes, trimming and splitting all follow the speed. Clips show "2×".
- **Text design** (title inspector Design section): font (installed families, plus Add Fonts… which copies font files into the app's folder and registers them for the app at each launch), Bold, all capitals, size 40–220, colours for letters / outline / box (a palette of 11 named colours plus None), a box per line, shadow, Reset to the style. Titles can be dragged anywhere in the viewer (sticks to the centre across; "Centre Across" button). New entrances: Type (typewriter), Slide Up, Zoom. **My Styles**: Save Style… keeps the look and entrance for every Short (UserDefaults), apply or delete from the menu. Choosing a style replaces the look but keeps the font.
- **Captions that pop** (Captions panel ▸ Design, key words & emoji, which scrolls inside the settings area): font, size 60–160%, letters and accent colours ("None" = the style's), Pick Key Words (numbers, names, long words, about one in seven; heuristic, 4 languages), Suggest Emoji (a dictionary of ~45 concepts in EN/IT/DE/FR, at most one per caption, drawn above it), show/hide toggles. The spoken word is a little bigger in Bold/Highlight. Captions can be dragged up/down in the viewer (kept clear of YouTube's areas).
- **Script panel** (new sidebar tab): the transcript as words, one paragraph per clip; click goes there, ⇧-click selects a range, ⌘-click toggles; ⌫ or Cut removes the words and the pause after each from the video (as a `SilencePlan`, like Remove Pauses); Highlight marks key words; an emoji menu for a single word; Remove N Filler Words cuts "um/eh/äh/euh…" and words said twice (dotted underline). Needs captions to exist.
- **Sounds** (new sidebar tab, sounds row under the captions, Sound menu): 7 built-in effects (Whoosh, Swipe, Pop, Click, Ding, Riser, Boom) synthesized by the app the first time (`SoundEffect`, no licensing), listen/add at playhead; sound files from Media (right-click ▸ Add as Sound Effect) or dropped on the sounds row. Drag, trim, split, delete like B-roll; overlapping ones stack. **Record Voice-Over** (⌥⌘R or the panel): microphone permission, 3-2-1 countdown, the Short plays silently from the playhead, stop with Space/Escape/the button or at the end; becomes a voice-over sound (pink, mic icon), and the music is lowered under voice-overs. Recordings go to Application Support/Shorts Editor/Voice-overs.
- **Clean up voice** (clip/B-roll/voice-over inspector toggle, Sound ▸ Clean Up Voice): Apple's voice isolation (AUSoundIsolation) renders a lossless cleaned copy of the file once (Caches/Shorts Editor/Clean Voice, keyed by path+size+date), used in playback and export. Progress shown in the inspector.
- **Follow the Subject** (Picture section on horizontal clips, Clip menu): Vision faces (biggest) or attention saliency, every 0.25 s, smoothed over ±0.8 s, keyframes every 0.5 s with redundant ones dropped; sets Fill screen. A still subject gives one fixed crop.
- **Layouts** (B-roll inspector Layout): Over / Top Half / Bottom Half (split screen: each clip fills its half, `Project.regions(at:)`), and Top Left/Top Right/Bottom Left/Bottom Right picture-in-picture placed clear of YouTube's covered areas. Viewer handles work inside the halves.

Verified on screen (2026-11-09, test Short): Whoosh added from the Sounds tab at the playhead (sounds row with waveform, inspector); 2× speed from the Clip menu (3.5 → 1.8 s, badge); Top Half split screen; Top Right corner; title added, letters made yellow, dragged left/down, Reset appears; captions made from the Script tab; caption settings scroll (fixed a layout bug where they pushed the window); cutting "Hey everyone," from the Script (talking clip 11.8 → 11.0 s, captions follow); Pick Key Words + Suggest Emoji (bold/underlined key words and 👀 in the Script); Follow the Subject on the horizontal clip; Clean Up Voice (cleaned in seconds, badge on clip); voice-over: countdown, recording, auto-stop at the end, voice-over on the sounds row; relaunch keeps everything (file version 3).
Not yet verified on screen (6–12): the font menu and Add Fonts… (NSMenu pop-ups block `ui.sh`; press Escape after), My Styles, Type/Slide Up/Zoom entrances watched during playback, dragging captions in the viewer, key-word colour on a caption that isn't being spoken (render test checks it), emoji above a caption in the viewer (render test), Remove Filler Words on real speech (the synthetic voices have none), split screen in an export, a voice-over with real speech and ducking heard.

### Batch "features 1–5" (2026-11-09): done and committed

The user asked for the first five of the twelve roadmap features in one go, then to **stop and ask** before going on (next would be 6 speed, 7 text design, 8 captions that pop, 9 edit by text, 10 sound layer, 11 auto reframe, 12 layouts). All five are built, tested and checked on screen; **not committed yet** (the user commits each stage).

| # | Feature | Model + tests | Rendering + tests | UI | On screen |
|---|---|---|---|---|---|
| 1 | Hands-on timeline: drag to reorder, drag edges to trim, snapping, Q/W, filmstrip + waveform | ✅ | ✅ | ✅ | ✅ |
| 2 | Second video track (B-roll / picture-in-picture) | ✅ | ✅ | ✅ | ✅ |
| 3 | Pictures as clips | ✅ | ✅ | ✅ | ✅ |
| 4 | Framing in the viewer: move/resize/turn, blurred background, punch-in, punch-in on alternate cuts | ✅ | ✅ | ✅ | ✅ |
| 5 | Zoom and move over time: keyframes + one-click motions | ✅ | ✅ | ✅ | ✅ |

Design: every clip (main or B-roll) has a `Placement` (offset, scale, rotation) on top of its framing, plus optional keyframes stored in the source file's own time, so motion follows splits, trims and Remove Pauses like captions do. B-roll is `Project.overlays` (timed on the timeline like titles). The compositor draws layers: main clip (over a blurred copy of itself or black) → overlays → titles → captions. Project files are now version 2 (version 1 files still open; old clips keep black backgrounds).

What works today:
- **Dark look** like Final Cut Pro / iMovie: the app always runs in Dark Mode (`AppDelegate`), with flat greys from `App/Views/Theme.swift` (near-black viewer, dark timeline, mid-grey panels, lighter header strips). Not yet seen on screen: Captions panel with captions, Export sheet, Remove Pauses panel.
- Import videos, **pictures** (JPEG, PNG, HEIC, AVIF, WebP… anything ImageIO reads) and sound files (music) by drag-and-drop (Media list, viewer, timeline), with **Import…** / **Choose Videos…**, or from Finder (Open With / Dock icon). Files go onto the timeline in order, and the same file is never imported twice.
- **Pictures** are clips of 3 s (any length up to an hour by trimming), shown "Picture" in Media. Decoded once at up to 2600 px, the right way up (`StillImages`). Horizontal pictures default to Show all with the blurred background.
- **Hands-on timeline** (stage 8 of the roadmap):
  - Drag a clip to move it in the storyline (a yellow bar shows where it lands). Drag either edge to trim it; the clips after it close up on release. Q / W trim the clip under the playhead to the playhead (start / end); on selected B-roll under the playhead they trim that instead. Also in Clip menu and the clip's right-click menu.
  - **Snapping** (S, View ▸ Snapping, button in the timeline header; remembered): dragged edges of clips, titles and B-roll stick within 8 points to cuts, other items' edges, the start/end and the playhead; a yellow line shows where.
  - Clips show a **filmstrip** (a still per second, up to 120 per file) and a **waveform** (from the per-frame levels already measured for Remove Pauses), plus icons for zoom and motion, and keyframe diamonds.
  - Titles that overlap get their own rows now (`LanePacking`), and titles snap when moved or lengthened.
- **B-roll / picture-in-picture** (`Project.overlays`): videos or pictures over the main clips, on rows above them (overlapping ones on separate rows, each its own composition track). Add with the toolbar **B-roll** button or Clip ▸ Add Over Clips at Playhead… (both start at the playhead), Media right-click ▸ Add Over Clips at Playhead, or by dropping files on the B-roll row (at the drop time). Starts full screen, 4 s (pictures 3 s), **without its own sound** (switch "Play its own sound" in its inspector). Drag to move, drag edges to trim, B splits it when selected, ⌫ deletes. Its inspector has Picture, Motion, Sound. Not tied to the clips under it: it stays at its time when they change.
- **Placing the picture** (selected clip or B-roll, when it is under the playhead):
  - In the viewer: a yellow box with corner squares and a round knob. Drag inside to move (sticks to the middle, with yellow guides), drag a corner or pinch to resize, drag the knob to turn (sticks to straight angles). Clicking the video selects the picture under the pointer (B-roll first). The frame updates live while dragging (`LivePreview`, no rebuild), then becomes one undoable edit.
  - Inspector **Picture** section: Fill screen / Show all, **Around it: Blurred / Black** (main clips; new clips default to Blurred), Size 25–300%, Angle, **Punch In** (120%, toggles) and Reset.
  - **Punch In on Every Other Cut** (Clip menu; multiple-selection inspector): every other clip of the same recording is zoomed 120%, so jump cuts look like a camera change. Applies to the selected clips (2+) or all; clips that move are left alone.
- **Motion** (inspector Motion section, Clip ▸ Motion): one click for Slow Zoom In / Slow Zoom Out (to 115%), Glide Left / Right, Zoom In at Playhead (to 130% in 8 frames, then stays). **Add Keyframe** remembers the picture at the playhead; once a clip moves, any change at another time (viewer or sliders) adds a keyframe there. Keyframes list (go to, delete), Remove Motion. Easing: smooth by default, linear for slow zooms/glides.
- 9:16 viewer (1080×1920, 30 fps) with a toggle for the dimmed areas YouTube's interface covers (`SafeZone`).
- **Playhead follows any click** on the timeline (2026-11-09): a plain click anywhere (ruler, empty space in any lane, clips, B-roll, titles, sounds, music) moves the playhead there; ⌘/⇧-clicks only change the selection; dragging empty space still draws the selection rectangle; clicking a caption line still jumps to that caption. The B-roll and sound lanes' drop targets used to swallow clicks. Checked on screen at 8 spots.
- Magnetic timeline: click a clip to select it and move the playhead there, drag the ruler to scrub, split (**B**), delete with the gap closing (**⌫**), move earlier/later (right-click), zoom.
- **Selecting several items** on the timeline (`TimelineSelection` in EditorCore): ⌘-click adds/removes, ⇧-click adds the clips in between, drag across empty space draws a selection rectangle (⌘/⇧ adds), click empty space or ⇧⌘A deselects, ⌘A selects all (outside text fields, in `EditorKeys`). Delete removes them all in one undo step; the inspector shows "N Selected" with framing and mute for all selected clips. Not yet seen on screen: music in a group, the right-click "Delete N Selected Items", the group framing/mute buttons, Deselect All. Dragging a title moves only that title; the rectangle doesn't auto-scroll.
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
- **Sound** (Sound menu, toolbar **Music**, the clip inspector):
  - Clip volume 0–200% with a mute switch (inspector), shown on the clip ("160%", or a crossed-out speaker). Kept through split and Remove Pauses.
  - **Music**: one song per Short. Add it with the toolbar button, Sound ▸ Add Music…, "Add Music…" in the empty music lane, by dropping a sound file on the timeline/viewer, or by opening one from Finder. Sound files show in Media as Music (double-click uses it). A video's sound can also be used as music (right-click in Media).
  - The music starts with the Short and stops with it (or when the song ends: the inspector says so). Settings: volume (default 50%), "Start the song at" (skip an intro), fade in (1 s) / fade out (2 s).
  - **Lower while people talk** (on by default): the music drops to 20% of its volume (about −14 dB) wherever the clips have speech, found from the per-frame loudness of the files (gaps under 0.5 s are bridged; muted clips don't count). It goes down 0.25 s before speech and comes back up over 0.6 s. The music lane draws the volume line, so the dips are visible.
  - **Even out the loudness** (Export sheet, on by default): the mixed sound is measured with an EBU R128 / BS.1770 meter and brought to −14 LUFS, keeping peaks at −1 dBFS or lower and boosting by 20 dB at most. Checked with ffmpeg's `ebur128` on an export: −14.0 LUFS, peak −1.1 dBFS.
  - Export check: **music on a Short over 1:00** (warning: Content ID claims block those Shorts).
- **Saving** (superseded by the home window above; kept for history): every change is saved about a second later, so quitting never loses work.
  - An unnamed Short ("Untitled Short", subtitle "Kept on this Mac · ⌘S to name it") lives in the app's container (`Application Support/Shorts Editor/Untitled.shortsproject`) and comes back at the next launch.
  - ⌘S names it the first time (save panel); after that it saves in place. Save As… ⌘⇧S switches to a new file. The window shows the name and the file's proxy icon.
  - New Short ⌘N, Open… ⌘O, Open Recent (8, with Clear Menu). Leaving an unnamed Short with something in it asks Save… / Don't Save / Cancel. The last open Short reopens at launch. `.shortsproject` files open from Finder; dropping one on the window opens it.
  - Format: JSON (`ProjectFile`, version 1; a newer version is refused with a clear message). Each media file is saved with a security-scoped (app-scope) bookmark, so the sandboxed app can open it again after a restart, and follows files moved or renamed on the same disk.
  - **Missing media**: clips whose file can't be found play black and silent for their full length (a black placeholder video is stretched over them); missing music is left out. An orange bar over the viewer, "Can't be found" in Media, and an export warning. **Find Missing Files…** (bar, File menu, Media right-click) takes the file or its folder; files with the same names are checked for kind and length (±0.5 s) before being used. Undoable.
- 186 automated tests (`make test`, about a minute; 41 added for features 1–5 in `EditingTests.swift`, `LayerTests.swift` and an export test with a picture and B-roll with sound): timeline, caption, pause and export-check logic; framing math; rendering checked pixel by pixel (orientation, every caption style); export checked for codec, size, AAC and fast start; per-frame sound levels; and a real transcription of speech made with `say`.

Verified on screen: import, Finder open (launch and while running), select, framing switch, split, delete, undo (fixed 2026-11-08, see below), Space play/pause, ruler scrub, closing the window quits. Captions: make, style and position switches, editing a line, jumping from the timeline lane, split/delete with captions following, undo of all of these. Export: checks sheet, save panel, progress, finished state, output checked with ffprobe. Remove Pauses: detection on a sample with known pauses, sliders, preview playback, apply, undo. Saving: unnamed Short survives ⌘Q and relaunch (media readable through bookmarks, also after a rebuild), ⌘S into a folder, autosave in place after a split, file moved + original deleted → missing bar/black frames/Media marker, Find Missing Files… with the folder → relinked and still relinked after relaunch, New Short, Open Recent, Don't Save prompt (autosave removed), opening a project file through Launch Services. Sound: song opened from Finder becomes the music, ducking curve on a clip with pauses, lowering off/on (inspector and Sound menu), mute (music stays up under the muted clip), volume slider to 160%, export with loudness evened out (ffmpeg: −14.0 LUFS). Titles: add (⌘T) with text ready to type, typing + Return, style switch, undo/redo, drag in the viewer into the covered area (warning in inspector and export sheet), Top preset, move and lengthen on the timeline, ⌫ delete.
Features 1–5 (2026-11-09, on the test Short): picture opened from Finder (3 s clip, blurred background), B-roll added through Clip ▸ Add Over Clips at Playhead…, resized into picture-in-picture by a corner, moved by dragging, undo, clip reordered by dragging, background switched to Blurred, Slow Zoom In (107% halfway, 115% at the end, keyframe list), edge trim (6.0 → 5.0 s, rest closed up), Q, W, B-roll moved and snapped to a cut at exactly 0:05.0, B-roll start trimmed, splits + Punch In on Every Other Cut (only the middle piece zoomed), turning with the knob on a moving clip (adds a keyframe), S toggles snapping, quit + relaunch keeps everything (file version 2).
**Not yet verified on screen (features 1–5):** dropping files from Finder onto the B-roll row, Media right-click ▸ Add Over Clips, a picture as B-roll, pinch to resize, Glide and Zoom In at Playhead watched during playback, B-roll with its own sound turned on (checked in the export test), the Size/Angle sliders' live preview, export of a Short with B-roll from the app (checked in tests).
**Not yet verified on screen:** Save As…, Open… panel, the "Save…" branch of the leave-unnamed prompt, a project whose media is on another disk, a newer-version file. The music volume and "Start the song at" sliders, Change Song…, dropping a sound file on the timeline, listening to the result (checks so far are visual and measured, not by ear). J/K/L reverse and fast playback, the clip right-click menu, the title right-click menu, the title length stepper, timeline zoom, drag-and-drop from Finder. The Pop and Fade animations are checked by render tests, not by eye during playback.

## Decisions already made (don't re-ask)

- macOS 26+, Apple Silicon. SwiftUI app with AppKit where needed. XcodeGen project.
- Personal tool first; a shareable **.dmg** later. Opening it without warnings on other Macs needs a paid Apple Developer ID (99 USD/yr), which is still to be decided when sharing starts.
- Caption languages: **English, Italian, German, French**. All four are available in Apple's on-device `SpeechTranscriber` (checked on this Mac).
- Support all kinds of footage, with **very friendly, intuitive UX** as the top requirement.
- Repo is public on GitHub.

## What's next, in order

The P0 list from `research/shorts-editor-research.md` §5. Each stage ends with tests and an on-screen check.

1. ~~Auto-captions~~ (done)
2. ~~Export~~ (done), with all the checks from the research except "low-volume audio" (made unnecessary by evening out the loudness).
3. ~~Remove silences~~ (done, as "Remove Pauses").
4. ~~Text overlay~~ (done, as "Titles", stage 5), with the "text where YouTube covers it" export check.
5. ~~Audio~~ (done, stage 6): clip volume, music with fades and ducking, loudness on export.
6. ~~Save/open projects~~ (done, stage 7).
7. **Roadmap features 1–5 done** (2026-11-09, `research/feature-roadmap.md`): timeline you can touch, B-roll, pictures, framing in the viewer, motion.
8. **Roadmap features 6–12 done** (2026-11-09): speed, text design, captions that pop, edit by text, sound layer, auto reframe, layouts.
9. **Next (ask the user first):** the "next 20%" in `research/feature-roadmap.md` §4: markers and beats, filters/adjustments, a few transitions and effects, loop preview and cover frame, long video → Shorts, background removal, text to speech, stickers, templates, copy/paste clip settings.

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
- Saving: one window, one Short at a time (no DocumentGroup: the single-window model, shared `EditorModel` and Finder media import made a custom store simpler). No versions browser and no "Revert". Media bookmarks are app-scoped, so a project copied to another Mac (or user) needs Find Missing Files… there. Writing tries an atomic write first and falls back to a plain one if the sandbox refuses the temporary file. In an Open panel a folder has to be *selected* (not just opened) for "Use" to work, as everywhere in macOS. `screencapture` of the app window misses separate windows (Open panel, alerts): capture their region (`System Events … get {position, size} of windows`).
- Sound files can only be the music, not clips. Animated GIFs show their first frame only.
- B-roll sound isn't counted as speech for ducking, and B-roll isn't transcribed for captions. Voice-overs count as speech for their whole length (not by loudness) and aren't transcribed either.
- Key words and emoji are picked by simple rules (no language model); "welcome"/"showing" can be picked. Emoji dictionary is small. Filler words are sounds only ("um", "eh"…), not real words used as fillers ("like", "allora").
- Voice clean-up copies are kept in Caches and remade if missing; a project opened on another Mac re-cleans when the toggle is switched off and on.
- Speed has no ramps/curves and no smooth slow motion (frame blending). Reversed clips don't exist.
- Split screen is top/bottom halves only, and only the topmost split B-roll at a time decides it. Overlays are timeline-timed (like titles), not attached to the clip under them, so moving a main clip doesn't move its B-roll.
- Live preview while dragging a picture redraws the frame by seeking to the same time; during playback it isn't shown (dragging pauses).
- Keyframes animate placement only (not opacity or volume). The handles' corner squares are kept inside the viewer, so on a picture bigger than the screen they sit at the edge, not at the true corner.
- Filmstrip and waveform are drawn per clip with Canvas; very long clips at high zoom draw many stills (no tiling yet).
- Synthetic clicks (`ui.sh`) can leave a SwiftUI pop-up menu open, which blocks Apple events to the app (osascript times out after 2 minutes). Press Escape (`ui.sh code 53`) after using a pop-up.
- Audio: one song only; it always starts with the Short (no placing it later, no looping a short song).
- Volume line: points move up/down only (not sideways). B-roll has fades and effects in the inspector but no line on its timeline block. "Too loud" uses per-frame RMS (−6 dBFS), not true peaks, so it's a hint. Voice effects are synthesized by me and were never judged by ear; Robot is ring modulation + a short comb, not a vocoder. Processed copies are stereo, play from file time 0 (a video whose sound starts later than its picture would drift slightly, same as voice clean-up), and the echo/reverb tail is cut at the end of the file. Speech for ducking is found by loudness, so a clip with constant loud sound (e.g. its own music) counts as speech throughout. Volume sliders apply when released (no live preview while dragging). AVFoundation's audio mix does boost above 100% (checked: linear in float).
- Transitions: the sound still cuts at the cut (no crossfade). Only between main clips (not at the start or end of the Short, not on B-roll). Without spare footage a clip is held on its first/last picture during its half. The white band over a transition on the timeline is faint.
- Backwards copies are H.264 at up to 1920 px on the long side; they are listed in Media, stay in Application Support when no longer used, and for files over a minute hold only the clip's part ± 3 s (the clip can't be trimmed out further). Backwards speech has no captions.
- Gradual speed changes move the picture only: the sound changes speed at the cut, so it is up to a few frames out of step with the picture inside the half-second change, and in step again after it. Captions and keyframes there are timed as if the change were at the cut.
- Slow-motion footage always starts at ¼ speed (no setting yet; press 1× to undo). Instant Replay adds no "Replay" label; there is no Rewind.
- `MusicTrack` is a type in Apple's AudioToolbox, hence the model's name `BackgroundMusic`.
- `SafeZone` margins are approximate (no official YouTube overlay found).


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
