# Usability audit: what stops the editor from "just flowing"

_2026-11-18. First pass: a Short made by hand in the real app (pointer and keyboard, a separate test library), the code read where the screen raised a question, and web research on what makes iMovie and CapCut easy to learn. Screens from the session: `Tools/uitest/.shots/a01…a12` (not committed)._

**The goal (user, 2026-11-18):** someone who has used iMovie can make a Short without learning anything. Every step should be guessable, and the usual Mac habits (⌘C/⌘V, double-click to edit, Escape to let go) should just work.

---

## 1. The yardstick: eight rules from the research

| # | Rule | Where it comes from |
|---|---|---|
| R1 | **Mac habits work everywhere.** ⌘X/⌘C/⌘V/⌘D, Delete, Escape, double-click to edit, drag to move, ⌥-drag to copy, pinch to zoom. People don't read menus to find these: they try them. | Nielsen heuristic 4, "Consistency and standards: follow platform conventions" ([WPI](https://web.cs.wpi.edu/~kal/courses/hci/module6/neilsen10heuristics.htm)); iMovie copies/pastes clips with ⌘C/⌘V ([Apple Community](https://discussions.apple.com/thread/253313857)); CapCut users copy styled text layers with ⌘C/⌘V instead of remaking them ([tutorial](https://pexo.ai/blog/capcut-tips-and-tricks-9869)) |
| R2 | **Recognition, not recall.** What you can do is visible where you are looking. | Nielsen heuristic 6 ([WPI](https://web.cs.wpi.edu/~kal/courses/hci/module6/neilsen10heuristics.htm)) |
| R3 | **Icons get words.** Icon-only toolbars are guessed right about 60% of the time, 88% with labels; Outlook's toolbar only got better when labels were added. Apple: give every toolbar item a label and prefer verbs. | [NN/g, Icon Usability](https://www.nngroup.com/articles/icon-usability/); [UserTesting](https://www.usertesting.com/blog/user-friendly-ui-icons/); [Apple HIG, Toolbars](https://developer-mdn.apple.com/design/human-interface-guidelines/components/menus-and-actions/toolbars) |
| R4 | **Edit the thing itself.** Text is typed on the picture, sound is seen as a wave, a clip is trimmed by its edge. | iMovie edits titles in place in the viewer and shows waveforms on every clip and in the music well (`imovie/imovie-reference.md` §1, §7) |
| R5 | **One place per kind of thing.** iMovie's browser has a tab for each thing you can add (Media, Audio, Titles, Backgrounds, Transitions); the adjustments bar shows one tool at a time. | `imovie/imovie-reference.md` §1, §4; CapCut's library tabs (`capcut/capcut-reference.md` §1) |
| R6 | **Few things at a time.** Beginners need "a convenient timeline, tooltips or built-in training, and few unnecessary functions at startup". | [tonfotos.com](https://tonfotos.com/articles/video-editing-software-for-beginners/) |
| R7 | **Help doesn't get in the way.** CapCut's critique: people stop not knowing what to do next; tie hints to what they are doing. | [Pratt IxD, Design Critique: CapCut](https://ixd.prattsi.org/2025/09/design-critique-capcut/) |
| R8 | **Simple wins over complete.** iMovie's reviews praise the straightforward interface, drag and drop and the small feature set; its complaints are about missing power, never about being hard. | [G2](https://www.g2.com/products/imovie/reviews), [Capterra](https://www.capterra.com/p/207187/iMovie/reviews/?page=8), [Tom's Guide](https://www.tomsguide.com/reviews/apple-imovie) |

The Shorts Editor has far more features than iMovie (stages A–L). The friction comes less from missing features than from the basics around them: the Mac habits (R1), where things are (R2, R5) and how much is shown at once (R6).

---

## 2. What I did

New Short → opened five files (two talking videos, B-roll, a song, a photo) → added a title with ⌘T, typed it → tried ⌘C/⌘V on the title → trimmed a clip by its edge → dragged the title along the timeline → double-clicked the title in the viewer → scrolled the clip inspector → opened Export.

**Worked well, keep it:** plain-language labels and tooltips everywhere; "Saved as you work"; trimming by dragging an edge; dragging a title; undo names ("Undo Edit Title"); the export sheet (length, size estimate, "No captions" hint, loudness checkbox); the empty states ("Drop your videos or pictures here to start").

---

## 3. Findings

Severity: **A** = breaks the flow for everyone, on every Short. **B** = slows people down or confuses them often. **C** = polish.

### Editing basics (R1)

| # | Sev | What happens | What people expect | Fix |
|---|---|---|---|---|
| U1 | **A** | **No Cut, Copy, Paste or Duplicate for anything on the timeline.** With a title selected, ⌘C then ⌘V does nothing; Edit ▸ Cut/Copy/Paste are disabled. Only "Copy Settings" (⌥⌘C) exists. To make five similar titles you add five and style each one. | iMovie: ⌘C/⌘V clips and titles. CapCut: ⌘C/⌘V and ⌘D on every item. | A clipboard of timeline items (clips, titles, stickers, B-roll, sounds, with all their settings): ⌘X/⌘C/⌘V (paste at the playhead, main clips inserted there), **⌘D Duplicate** (right after the original), **⌥-drag to copy**. The same items in every right-click menu. |
| U2 | **A** | Right-click menus lack the basics. A title's menu: Start at Playhead, Copy/Paste Title Design, Delete. A clip's: no Cut/Copy/Duplicate. | Cut · Copy · Paste · Duplicate · Delete at the top of every menu. | Shared top block for every timeline item's menu. |
| U3 | B | **Escape doesn't let go of a selection** (it only ends ranges, colour picking, the trimmer and full screen). | Escape deselects (Finder, Photos, Final Cut). | Escape → deselect; ⇧⌘A stays. |
| U4 | B | **No pinch to zoom the timeline** (pinch only resizes pictures in the viewer); only the slider and View ▸ Zoom. | Pinch and ⌘+/⌘− on the timeline (iMovie); ⇧Z fit (iMovie). | MagnifyGesture on the timeline, zooming around the pointer; ⌘+/⌘− shortcuts; ⇧Z "Zoom to Fit". |
| U5 | C | Single-key shortcuts (J K L B Q W S R X M) are matched by **key code**, i.e. the key's position on a US keyboard. Right on Italian QWERTY; wrong on French AZERTY and German QWERTZ, two of the caption languages. | The key with that letter. | Match these by character too, as the punctuation already is. |
| U6 | C | ⌫ in the Media panel removes the file from the Short; easy to hit when you think a timeline clip is selected. | Needs checking: does selecting a clip clear the Media selection? | Check; if not, Delete acts only on what has the visible yellow frame. |

### Sound (R4)

| # | Sev | What happens | What people expect | Fix |
|---|---|---|---|---|
| U7 | **A** | **The music has no sound wave**: a green bar with a volume line (`TimelineLanes.musicLane`). You can't see where it gets loud, where the drop is, where to cut. | iMovie draws the wave in the music well; CapCut on every audio track. | Draw `WaveformView` in the music lane (levels from `MediaAnalysis`, like sounds), beats over it when shown. |
| U8 | B | The clips' waves are a thin 24 pt grey strip under the filmstrip, the same for every clip, and the timeline's heights are fixed. | iMovie: View ▸ Show Audio Waveforms and a Clip Size slider. | A "Clip size" control (filmstrip and wave grow), loud parts drawn brighter, and green/yellow/red for fine/loud/clipping as in iMovie. |
| U9 | C | The clip trimmer has no wave (known, `STATUS.md`). | — | Add it. |

### Text and titles (R4)

| # | Sev | What happens | What people expect | Fix |
|---|---|---|---|---|
| U10 | **A** | **Text can only be typed in the inspector field**, not on the picture. Double-clicking the title in the viewer did nothing. | iMovie and CapCut: double-click the text on the picture and type there. | Double-click a title in the viewer → edit it in place (a text field over the picture, same font size), Return or click away to finish. Keep the inspector field. |
| U11 | **A (bug)** | **After dragging the title along the timeline, its box in the viewer disappeared** and clicking it in the viewer no longer selected it (screens a09, a10). Before the drag the yellow box was there (a05). | The selected title always has its box. | Find out why `TitleHandles` stops drawing (likely the frame or time used after `moveTitle`); add a UI test. |
| U12 | C | The style tiles show your own text, cut off ("Hello worl"). | A short sample or the whole word scaled down. | Scale the sample to fit, or use "Title" when the text is long. |
| U13 | C | Typed text is saved only on Return or clicking away; quitting while typing loses it (known). | Saved as you type. | Commit on every pause (debounced), one undo step per typing session. |

### Finding things (R2, R3, R5, R6)

| # | Sev | What happens | What people expect | Fix |
|---|---|---|---|---|
| U14 | **A** | **The toolbar is 12 icons with no words.** Several are hard to guess: a half-filled circle is Transition, a wave with a minus is Remove Pauses, two rectangles is B-roll, a dashed square is the YouTube safe zones, a smiley is Stickers. | Labels under the icons (Pages, Keynote, iMovie's Import/Share are words). | Show labels (`.labelStyle(.titleAndIcon)` / toolbar "Icon and Text"), fewer items: group by what they add. |
| U15 | **A** | **Things to add live in four different kinds of place.** Media, Photos, Captions, Script, Sounds are tabs on the left; Titles, Stickers, Transitions, B-roll and Music are toolbar buttons, menus or pop-overs; Captions is both a tab and a toolbar button; Styles are in the right-hand panel. | iMovie: one browser with a tab for each kind of thing you can add, and you drag it onto the timeline. CapCut: the same (Media, Audio, Text, Stickers, Effects, Transitions, Captions, Filters). | One browser on the left: **Media · Audio (music + sound effects) · Text (titles, stickers, text templates) · Transitions · Effects · Captions**. Every tile can be dragged onto the timeline or double-clicked to add at the playhead. Script moves next to Captions (both are about words). The toolbar keeps only the few actions that aren't "things": Split, Delete, Undo/Redo, Export. |
| U16 | **A** | **The clip inspector is one long scroll of about 11 sections** (Picture, Look, Steady, Motion, Animation, Effects, Cut-out, Freeze, Speed, Sound, Transition). The filter grid alone fills the panel; Speed or Sound are far below and found only by scrolling. | iMovie: an adjustments bar, one tool at a time. CapCut: tabs (Video, Audio, Speed, Animation, Adjust). | Tabs at the top of the inspector: **Picture · Colour · Speed · Sound · Animation · Effects** (only those that apply), remembering the last tab per kind. Grids of filter tiles smaller (3 per row, tiny pictures) or in the left browser (U15). |
| U17 | B | **The time ruler scrolls away** when the timeline is scrolled down to reach the music (screen a04). | The ruler stays at the top. | Pin the ruler (and the playhead's head) outside the vertical scroll. |
| U18 | B | **The timeline is cramped.** On a 770 pt window the music lane sits at the very bottom, half-hidden; empty lanes ("Titles go here…", "Drop B-roll…", "Sound effects… go here") take full height even when empty. | iMovie: a draggable divider between viewer and timeline. | Draggable divider (remembered); empty lanes thin (a single line with the hint on hover); "Clip size" (U8). |
| U19 | B | **Tips cover the timeline**, one after another (three in the first two minutes), at the bottom where the music lane is. | Hints near what they explain, rarely. | At most one tip per session, shown next to the thing it explains, never over the timeline; Help ▸ Tips lists them all. |
| U20 | C | The home screen's four big tiles: **Storyboard** and **Template** sound alike; nothing says what each makes. There is also a "+" that does the same as New Short. | iMovie's Create New pop-over: each choice with one line of explanation. | One line under each tile ("Follow a shot list", "Clips cut to the music's beat"…); drop the duplicate "+" or make it the same menu. |
| U21 | C | Three import entries behave differently: Media's **Import…** (to Media only), the viewer's **Choose Videos…** (straight onto the timeline) and the toolbar's Import. | One rule. | Same rule everywhere: imports go to Media *and*, while the timeline is empty, onto it; say so in the button ("Add Videos…"). |

### Inconsistencies I noticed but did not finish checking

- Opening five files put all of them on the timeline, the song as music and the photo as a 3 s clip at the end. That fits an empty Short; when the Short already has clips, check what happens (iMovie imports into the browser only).
- The selection after an import is the last file (the music inspector opened), not the first clip.
- Two vertical lines on the timeline (the red playhead and a white skimmer line) look alike in a black and white view; the hand-made title started at the white one, not the red one.

---

## 4. Not yet audited (next pass)

Captions from start to finish (make, edit a word, style, move), voice-over recording, B-roll by dragging from Media, transitions on the timeline, Magic Short, Storyboard and Template from the home screen, Sounds panel, speed and freeze frame, reordering clips by drag, multiple selection (⌘-click, ⇧-click, ⌘A) and acting on it, keyframes in the viewer, the Script panel, Settings, Find Missing Files, and the whole thing in a small (13") window. Also: a session with someone who has never seen the app (5 tasks, no help, note where they stop), which is the real test of R2.

---

## 5. Suggested order of work

**Done (2026-11-18):** step 1: U1, U2, U3, U4 (pinch; ⌘+/⌘− were already there) and U11. Step 5: U5, U6 (already safe: selecting on the timeline clears the Media selection), U19, U20, U21, ⇧Z. Step 4: U14, U15, U16, U17 (pinned ruler), U18. Step 3: U10, U12, U13 (2026-11-18). Step 2: U7, U8 (Clip Size; the green/yellow/red colours were left out: red already marks sound that may crackle), U9.

1. **Mac habits (U1–U4, U11):** clipboard, Duplicate, ⌥-drag, Escape, pinch zoom, the title-box bug. Small, everywhere, the user asked for it first.
2. **See the sound (U7–U9):** waves on the music, bigger waves, clip size.
3. **Text on the picture (U10, U12, U13).**
4. **One place per thing (U14–U16, U18):** labelled toolbar, the browser with a tab per kind of thing, tabs in the inspector, the divider. This is the largest change and should be sketched (ASCII or screens) and agreed before building.
5. **Polish (U5, U6, U17, U19–U21)**, then the second audit pass (§4).
