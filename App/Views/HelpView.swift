import SwiftUI

/// Help ▸ Shorts Editor Help (⌘?, F27): how to make a Short, topic by topic, in plain words.
struct HelpView: View {
    static let windowID = "help"

    @State private var topic: HelpTopic? = .start

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $topic) { topic in
                Label(topic.title, systemImage: topic.systemImage).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            if let topic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(topic.title).font(.largeTitle.weight(.semibold))
                        ForEach(topic.sections, id: \.heading) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                if !section.heading.isEmpty { Text(section.heading).font(.title3.weight(.semibold)) }
                                ForEach(section.lines, id: \.self) { line in
                                    Text(line).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if topic == .shortcuts { ShortcutTable() }
                    }
                    .textSelection(.enabled)
                    .padding(24)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

/// The topics of Help, in the order a Short is made.
enum HelpTopic: String, CaseIterable, Identifiable {
    case start, media, timeline, text, captions, sound, looks, oneClick, export, library, shortcuts, problems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: "Your first Short"
        case .media: "Adding videos, pictures and sound"
        case .timeline: "Editing on the timeline"
        case .text: "Titles and stickers"
        case .captions: "Captions"
        case .sound: "Sound and music"
        case .looks: "Looks, effects and motion"
        case .oneClick: "Magic Short, styles and templates"
        case .export: "Exporting for YouTube"
        case .library: "Your Shorts and backups"
        case .shortcuts: "Keyboard shortcuts"
        case .problems: "When something goes wrong"
        }
    }

    var systemImage: String {
        switch self {
        case .start: "star"
        case .media: "photo.on.rectangle"
        case .timeline: "scissors"
        case .text: "textformat"
        case .captions: "captions.bubble"
        case .sound: "music.note"
        case .looks: "camera.filters"
        case .oneClick: "wand.and.stars"
        case .export: "square.and.arrow.up"
        case .library: "square.grid.2x2"
        case .shortcuts: "keyboard"
        case .problems: "lifepreserver"
        }
    }

    struct Section {
        var heading = ""
        var lines: [String]
    }

    var sections: [Section] {
        switch self {
        case .start:
            [
                Section(lines: [
                    "A Short is a vertical video up to 3 minutes long. Shorts Editor makes exactly that: "
                        + "1080 × 1920 pictures, 30 a second, ready for YouTube."
                ]),
                Section(
                    heading: "In five steps",
                    lines: [
                        "1. Click New Short in All Shorts (⌘N).",
                        "2. Drag your videos onto the timeline at the bottom, or into Media on the left.",
                        "3. Cut what you don't need: put the playhead where a cut should be and press B to split, "
                            + "then select the part you don't want and press Delete.",
                        "4. Add a title for the first seconds (⌘T) and captions (Text ▸ Make Captions).",
                        "5. Export (⌘E). The file is ready to upload.",
                    ]),
                Section(
                    heading: "Saving",
                    lines: [
                        "Your Short is saved by itself a second after every change. There is nothing to remember to do. "
                            + "Quit whenever you like: the app opens again where you left it."
                    ]),
            ]
        case .media:
            [
                Section(lines: [
                    "Drag files from Finder onto the timeline or into Media, use File ▸ Import Media… (⌘I), "
                        + "or pick from your Photos library in the Photos tab.",
                    "Videos, pictures and sound files all work. Wide videos are shown whole over a blurred copy of themselves; "
                        + "choose Fill Screen in the clip's details to fill the screen instead.",
                    "Double-click something in Media to add it to the end, or drag it onto a clip to put it in "
                        + "between, replace it, or lay it over the clips as B-roll.",
                ]),
                Section(
                    heading: "Files that moved",
                    lines: [
                        "If a file was moved or renamed, its clips show black and a bar says so. Click Find Missing "
                            + "Files… and choose the file again: your cuts stay as they were."
                    ]),
            ]
        case .timeline:
            [
                Section(lines: [
                    "The main clips play one after another. Everything else (B-roll, titles, sounds, music) sits "
                        + "above or below and follows the clip it starts on when you edit.",
                    "Click to select and move the playhead; drag a clip to move it; drag an edge to trim it. ⌘-click selects several items.",
                ]),
                Section(
                    heading: "Cutting",
                    lines: [
                        "B splits at the playhead. Q trims the start of a clip to the playhead and W trims its end.",
                        "Hold R and drag across the timeline to pick a range, then press Delete to take it out.",
                        "Clip ▸ Remove Pauses… takes out the silent parts between sentences for you.",
                    ]),
                Section(
                    heading: "Playing",
                    lines: [
                        "Space plays and stops. J, K and L play backwards, stop and play forwards; press J or L again to go faster.",
                        "Move the pointer over the timeline to skim through it without moving the playhead.",
                    ]),
            ]
        case .text:
            [
                Section(lines: [
                    "⌘T adds a title at the playhead. Type the words in the details on the right, choose a "
                        + "look, and drag the title in the viewer to place it.",
                    "Keep titles inside the dotted lines in the viewer: outside them, YouTube's buttons cover them.",
                    "Stickers (emoji and symbols) and ready-made texts such as Subscribe are in the Text menu. A "
                        + "title or sticker can follow something that moves in the video.",
                ])
            ]
        case .captions:
            [
                Section(lines: [
                    "Text ▸ Make Captions listens to your Short on this Mac and writes what is said, word by word. Nothing is sent anywhere.",
                    "Correct a word by clicking it in the Captions list. Press Return in a caption to split it, "
                        + "and Delete at its start to join it to the one before.",
                    "Choose how captions look in the Captions panel. Key words can be highlighted and emoji added after a word.",
                    "File ▸ Export Subtitle File (.srt)… writes them as a file for YouTube, if you prefer YouTube's own captions.",
                ])
            ]
        case .sound:
            [
                Section(lines: [
                    "Drag the yellow line on a clip's waveform up or down to change its volume; drag the dots at its top corners to fade in and out.",
                    "Sound ▸ Add Music adds a song under the whole Short. It is lowered by itself while people talk.",
                    "Record a voice-over with Sound ▸ Record Voice-Over (or in the Sounds panel): a "
                        + "countdown starts, then speak while the Short plays.",
                    "Voice clean-up takes away background noise and music from what people say.",
                    "When you export, the sound is brought to the loudness YouTube plays Shorts at, so yours is neither too quiet nor turned down.",
                ])
            ]
        case .looks:
            [
                Section(lines: [
                    "Select a clip to see its details on the right: filters and colour, speed, effects, steadying, "
                        + "removing the background, and how the picture is placed and moves.",
                    "Drag the picture in the viewer to move it, drag a corner to resize it, and drag the round knob to turn it.",
                    "Transitions go on the cuts between clips (⌥T adds one at the nearest cut). They never change how long your Short is.",
                ])
            ]
        case .oneClick:
            [
                Section(lines: [
                    "New Magic Short (⌥⌘N) makes a Short from your videos by itself: it takes out fillers and pauses, "
                        + "fits it to a length, adds captions, a hook title and music.",
                    "A style gives your whole Short one look in one click: titles, captions, transitions, motion, filter "
                        + "and music. Your own changes are kept when you choose another style.",
                    "Templates are made to music: each shot is a number of beats long. Drop your clips on the shots.",
                ])
            ]
        case .export:
            [
                Section(lines: [
                    "File ▸ Export Short… (⌘E) checks your Short first: things YouTube would cut off, sound that is too loud, "
                        + "text under YouTube's buttons, missing files. Fix them or go on anyway.",
                    "The file is an MP4 with YouTube's recommended settings. Upload it in YouTube Studio or the YouTube app as a Short.",
                    "If some clips were filmed in HDR, you can keep HDR; on YouTube it looks brighter on screens that can show it.",
                    "Make a cover with File ▸ Cover… (⇧⌘S) to use as the Short's thumbnail.",
                ])
            ]
        case .library:
            [
                Section(lines: [
                    "All Shorts (⇧⌘0) shows every Short you have made, newest first. Double-click one to open it; right-click to "
                        + "rename, copy or delete it (Edit ▸ Undo brings a deleted Short back).",
                    "Backups are kept as you work. File ▸ Revert To lets you go back to how a Short was earlier today, yesterday or before.",
                    "File ▸ Save a Copy… writes a Short as a file, to keep or to open on another Mac.",
                    "Settings ▸ Storage shows the space the app's own copies take (steadied clips, cut-outs, slow motion) and frees it.",
                ])
            ]
        case .shortcuts:
            [Section(lines: ["Every shortcut is also in a menu. Single keys work when the timeline or the viewer is in front."])]
        case .problems:
            [
                Section(lines: [
                    "When something can't be done, the message says why and offers what can help: Try Again, Find Missing Files…, Free Up Space…, "
                        + "or a button to System Settings when the microphone or Photos is switched off for the app.",
                    "Long jobs (making captions, removing a background, steadying, exporting) are listed in Window ▸ "
                        + "Background Tasks (⌘9), where you can see their progress and stop them.",
                    "If a Short won't open, File ▸ Revert To can open one of its backups.",
                ])
            ]
        }
    }
}

/// Help's list of keyboard shortcuts (each is also in a menu).
private struct ShortcutTable: View {
    private let rows: [(keys: String, action: String)] = [
        ("Space", "Play or stop"),
        ("J  K  L", "Play backwards, stop, play forwards (again: faster)"),
        ("←  →", "One frame back, one frame on"),
        ("Home  End", "Go to the start, go to the end"),
        (";  '", "Previous cut, next cut"),
        ("B", "Split at the playhead"),
        ("Q  W", "Trim the start, the end to the playhead"),
        ("Delete", "Delete what is selected"),
        ("M", "Add a marker"),
        ("S", "Snapping on or off"),
        ("⌘T", "Add a title"),
        ("⌥T", "Add a transition at the nearest cut"),
        ("⌥F", "Add a freeze frame"),
        ("⌘I", "Import media"),
        ("⌘E", "Export your Short"),
        ("⇧⌘S", "Make a cover"),
        ("⌘N  ⌥⌘N", "New Short, new Magic Short"),
        ("⇧⌘0", "All Shorts"),
        ("⇧⌘F", "Full-screen preview, as on a phone"),
        ("⌘+  ⌘−", "Zoom the timeline in, out"),
        ("⌘9", "Background Tasks"),
        ("⌘Z  ⇧⌘Z", "Undo, redo"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            ForEach(rows, id: \.keys) { row in
                GridRow {
                    Text(row.keys).font(.body.monospaced().weight(.semibold))
                    Text(row.action)
                }
            }
        }
    }
}
