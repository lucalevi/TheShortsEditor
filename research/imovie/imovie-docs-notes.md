# iMovie User Guide for Mac: chapter notes

_Read 2026-11-09: all 87 topic pages of https://support.apple.com/en-gb/guide/imovie/welcome/mac (iMovie 10.4.4 on macOS 13.5, pages dated 2026), except four with nothing for us (tape cameras, memory cards, iMovie Theater, copyright). Also https://support.apple.com/en-us/docs/software/pl147, which only lists the three user guides (Mac 10.4, iPhone/iPad 3.0.2) and old downloads (iMovie 9.0.x, Plug-in Pack 2.1.1); and the iPhone guide's Magic Movie, Storyboard, timeline, audio and sharing chapters (notes in `imovie-reference.md` §8). Paraphrased; UI labels exact._

---

## Get started
- **Main window**: browser top left, viewer top right, timeline bottom. Projects view lists movies; Media shows libraries.
- **First run**: Projects view → Create New → Movie. Photos library is in the sidebar and available with no import ("All the photos and video clips in your Photos library are automatically available").
- **Import window** (⌘I, toolbar ↓): Cameras / Devices / Favorites sidebar; preview by moving the pointer across a thumbnail; "Import to" an event or **Project Media**; Import All / Import Selected (button label follows the selection); import continues in the background with a progress indicator, you keep editing. Record from the FaceTime camera straight into the project (a clip per take). Drag files or folders from Finder onto an event.
- **Play/skim**: move the pointer over any clip to preview it (no click); Space plays from under the pointer; Play Full Screen; Loop Playback; Audio Skimming toggle.
- **Sort/search/rate**: filter All Clips / Hide Rejected / Favorites / Rejected; search by name or by type ("photo", "video"). F marks a favourite (hold F during playback to mark a range), ⌫ in the browser **rejects** (doesn't delete), U clears. Green/red lines on the frames.

## Create movies
- **New movie**: resolution and frame rate come from the **first clip added**. Autosave, no Save command; the name is asked when you go back to Projects.
- **Projects**: search, library filter, double-click to open, ‹ Projects to go back; menu per project: Play, Open, Share, Copy/Move to Library, Rename, Duplicate, Delete (its media become an event, never lost).
- **Themes**: a theme is opening/ending titles + transitions (+ music); "Automatic content" inserts them as you build; can be changed or removed any time.
- **Select**: click = yellow border, playhead jumps to the click; ⌘-click / rectangle for several; Select in Movie ▸ by kind. Hover shows the length on the clip.
- **Select part**: hold **R** and drag = range (can't cross a clip boundary); drag the yellow handles to adjust; ranges feed speed, trim, volume and adding.
- **Add**: drag to the timeline; drop **onto** a clip → menu Insert / Replace / Replace from Start / Replace from End; **E** adds to the end (or the **+** on the browser clip); **W** inserts at the playhead (splitting the clip there); browser clips show an **orange stripe** where already used. 4:3 into 16:9 is cropped to fill automatically.
- **Trim**: drag an edge (extending needs unused media); **Clip Trimmer** (⌘\: the whole source with the used part bright, drag edges or slide the used part); **Precision Editor** (⌘/ or double-click an edit point: outgoing above, incoming below, drag the edit line, unused parts dimmed and skimmable, transition handles, audio edit point for split edits); R-range + **Trim Selection**.
- **Move/split**: drag clips (blue outlines show the landing spot); Split Clip ⌘B at the playhead.
- **Transitions**: automatic with a theme + Automatic content; or drag from the Transitions browser between clips, or double-click one to put it on both ends of the selected clip; ⌘T cross dissolve (on both sides of a whole clip); duration 0.5 s default (2 s theme) set in Settings; too long → the longest possible; double-click a transition → Duration + **Apply to all**; drag a new one onto an old one to replace.
- **Titles**: double-click a style = added at the playhead; or drag above / onto a clip (first or last third → that third, middle → whole clip); edit the text in the viewer (double-click, Tab between fields); font, size, alignment, B/I/Outline, colour; Apply. Change style by double-clicking a new one with the playhead on the title (keeps its duration). Duration by dragging the bar's edge or in Clip Information. Snapping (View ▸ Snapping): yellow line when ends align.
- **Maps and backgrounds**: double-click to add at the playhead; travel maps with route, style, name, swap; solid/gradient/pattern backgrounds with one or two colours.

## Audio
- **Music and sound effects**: Audio & Video browser (Music, Apple TV, Sound Effects; pick a range in the waveform). Drag to the **background music well** (not tied to clips; "Trim background music" fits it to the movie) or to the timeline (**attached** to the clip under it, moves with it).
- **Voiceover** (V or the 🎤 under the viewer): set the playhead, Record, stop with Record or Space, Done. Options: input, volume, **Mute Project**. The meter should stay green. Becomes a clip attached to the clip under the playhead.
- **Detach audio** (⌥⌘B): the sound becomes a green audio-only clip under the video; move, trim, effects, or move it to the music well.
- **Volume**: drag the volume line on the clip's waveform (percentage shown, waveform reshapes live); R-range then drag = volume for part, **with fades added at both edges**; ⌥-click the line = keyframe, ⌃-click = delete; waveform green/yellow/red; Mute.
- **Fades**: handles appear when hovering the clip's sound; drag to set the fade.
- **Enhance audio**: Volume ▸ **Auto** raises the average level; Reduce background noise 0–100 %; Equalizer presets.
- **Audio effects**: chooser; **Lower volume of other clips** (manual ducking with a slider), example: voiceover over music.

## Video effects
- **Enhance**: one click fixes colour and sound; the buttons it used light up. A range applies to the whole clip.
- **Colour**: Auto (removes casts, maximises contrast), Match Color (skim to a frame, click it), White Balance and Skin Tone Balance (click a white/grey area or skin in the viewer), manual multislider, saturation, temperature; Apply / Cancel / Reset; a slider above the viewer compares before/after.
- **Crop**: Crop to Fill (adjustable frame, locked to the movie's shape), Fit (whole picture, black bars), rotate ±90°, Reset clears crop and rotation. **Ken Burns**: Start and End frames, swap, Fit removes it. Aspect mismatch → black bars.
- **Stabilize**: per clip, analysed in the background (spinner), amount slider; Fix Rolling Shutter with an amount.
- **Filters**: grid of looks with strength; None removes. **Fade to** B&W / Sepia / Dream from the playhead or over a range. **Flash and Freeze Frame**: flash to white, freeze with a slow zoom out, then play on.
- **Freeze frame** (⌥F): 3 s, no sound, attached at both ends to the clip; hand icon to edit; Remove Freeze Frame.
- **Connected clips**: drag a clip or range above a clip, release on the green **+**; one control for Cutaway (opacity, fade handles on the clip), Green/Blue Screen (key colour taken from the frame under the playhead; Softness, Crop, Clean-up), Split Screen (Left/Right/Top/Bottom, Slide-in), Picture in Picture (drag to move, corners to resize, **yellow guides**, Dissolve/Zoom/Swap, border, shadow, keyframes for position with Add/Delete Keyframe and ◀ ▶ that dim at the ends). Change the type any time.
- **Speed**: Slow (50 %) / Fast (2×) / Custom; on a range with three handles and optional **Smooth** ramp; Reverse; Preserve Pitch; clip shows turtle/rabbit and lengthens/shortens live; high-frame-rate clips slowed automatically; Auto ramps.
- **Instant Replay** (plays again slower, adds an "Instant Replay" title) and **Rewind** (plays forward, backwards, forward again).
- **Copy effects**: Copy a clip, then Paste Adjustments ▸ All / Color / Crop / Volume (incl. ducking and fades) / Filter / Audio Effect / Speed / Overlay / Map to one or many clips.

## Share
- Email (warns over 10 MB), Social Platforms (writes a file, you upload it yourself), **Image** (JPEG of the frame under the playhead), **File** (Format: video and audio or audio only; Resolution; Quality incl. Custom bit rate with **live size estimate**; Compress faster/better quality; optional "export segmentation" on Max/Ultra chips). One share at a time; progress in the toolbar; "Share Successful" notification; the file opens in QuickTime Player.

## Trailers and app previews
- **Trailer**: pick a genre template (length and cast count shown); Outline (names, dates, credits; no field may stay empty) / Storyboard (wells that say how long and what kind of shot: "Wide", "Action", a person…) / Shot List; drop clips on wells; template music. Convert to Movie keeps the pacing as clips of the same lengths.
- **App preview**: screen recordings with restricted titles (Scale, Bar) and solid backgrounds, exported to App Store specs.

## Work smarter
- **Settings**: slow motion automatically, Photo Placement (Fit / Crop to Fill / Ken Burns), Photo Duration, Transition duration, Delete render files.
- **Project settings** (Settings button in the timeline): resolution shown, Theme, Automatic content, Filter for the whole movie, Trim background music, Fade in from / out to black, Clip Size, Show Waveforms.
- **Layout**: drag the viewer/timeline border; hide the browser; Revert to Original Layout.
- **Clip appearance**: clip size, waveforms, zoom (time per thumbnail); Clip Information (name, date, how much is used, total length; browser: sharing history).
- **Organise**: events grouped by date automatically; new/merge/rename events; moving vs copying (⌥) clips; deleting clips frees no space until the event goes.
- **Lines**: green favourite, red rejected, orange used (View ▸ Used Media Ranges); click a line to select that range.
- **Find the source**: Reveal in Project Media / Finder / Photos.
- **Send to Final Cut Pro**: the project and media copied into a new FCP library; "Lower volume of other clips" becomes a Gain filter.
- **Shortcuts and gestures**: see `imovie-reference.md` §3.
