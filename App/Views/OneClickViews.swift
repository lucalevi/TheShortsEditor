import CoreMedia
import EditorCore
import SwiftUI
import UniformTypeIdentifiers

// Stage F (one-click Shorts): the style picker, the Magic Short sheet, the storyboard chooser and
// the storyboard's shot list.

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

// MARK: - Styles

/// A small picture of how a style's titles look, on a dark frame.
struct StyleSample: View {
    let style: ShortStyle?
    var height: CGFloat = 46

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            if let style {
                let look = style.titleLook
                Text(look.uppercase ? "HOOK" : "Hook")
                    .font(.system(size: 15, weight: look.isBold ? .heavy : .regular))
                    .foregroundStyle(Color(look.textColor))
                    .padding(.horizontal, look.boxColor == nil ? 0 : 5)
                    .padding(.vertical, look.boxColor == nil ? 0 : 1)
                    .background(look.boxColor.map { Color($0) } ?? .clear, in: RoundedRectangle(cornerRadius: 3))
                    .shadow(color: look.outlineColor == nil && !look.shadow ? .clear : .black, radius: look.outlineColor != nil ? 0.8 : 2)
            } else {
                Image(systemName: "nosign").foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The styles as cards, None first. The chosen one has a checkmark and a thick border.
struct StylePicker: View {
    let selected: ShortStyle?
    var busy: ShortStyle?
    var offersNone = true
    var columns = 2
    let choose: (ShortStyle?) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            if offersNone { card(nil) }
            ForEach(ShortStyle.allCases) { card($0) }
        }
    }

    private func card(_ style: ShortStyle?) -> some View {
        let isSelected = style == selected
        return Button {
            choose(style)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                StyleSample(style: style)
                    .overlay(alignment: .topTrailing) {
                        if busy != nil, busy == style {
                            ProgressView().controlSize(.mini).padding(4)
                        } else if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(3)
                        }
                    }
                HStack(spacing: 4) {
                    Image(systemName: style?.systemImage ?? "circle.slash").font(.caption)
                    Text(style?.displayName ?? "None").font(.callout.weight(isSelected ? .bold : .medium))
                }
                if let style {
                    Text(style.hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Keep everything as it is")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(isSelected ? 0.1 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.08), lineWidth: isSelected ? 2.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(style.map { "\($0.displayName): \($0.hint)" } ?? "No style")
        .accessibilityLabel(style?.displayName ?? "No style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Style" in the inspector when nothing is selected.
struct ShortStyleSection: View {
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Style").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Magic…", systemImage: "wand.and.stars") { model.beginMagic() }
                    .controlSize(.small)
                    .help("Make a first cut for you: pauses and filler words out, captions, a hook title and music")
            }
            StylePicker(selected: model.project.style, busy: model.styleBeingMade) { model.setStyle($0) }
            Text(
                "Changes the titles, captions, transitions, motion, filter and music of the whole Short. Your own song, and anything you moved by hand, stay as they are."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Magic Short

struct MagicShortSheet: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Magic Short").font(.title2.weight(.semibold))
                    Text("A first cut, made for you. Then edit it like any other Short.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            if let session = model.magic {
                switch session.phase {
                case .choosing: choosing(session)
                case .working(let text, let fraction): working(text, fraction)
                case .done(let report): done(report)
                }
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    // MARK: Choosing

    private var clipSummary: String {
        let count = model.project.timeline.clips.count
        return "\(count == 1 ? "1 clip" : "\(count) clips") · \(TimeFormat.string(model.duration).dropLast(2))"
    }

    @ViewBuilder
    private func choosing(_ session: MagicSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "film.stack")
                if model.isImporting {
                    Text("Adding your clips…")
                    ProgressView().controlSize(.small)
                } else if model.project.timeline.clips.isEmpty {
                    Text("Your Short has no clips yet.")
                    Button("Choose Clips…") { model.addClipsForMagic() }
                } else {
                    Text(clipSummary).monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Style").font(.headline)
                StylePicker(selected: session.options.style, offersNone: false, columns: 3) { style in
                    if let style { model.updateMagic { $0.options.style = style } }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Length").font(.headline).fixedSize()
                    Picker("Length", selection: Binding(get: { session.options.length }, set: { value in model.updateMagic { $0.options.length = value } })) {
                        ForEach(MagicLength.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("Language").font(.headline).fixedSize()
                    Picker("Language", selection: Binding(get: { session.language }, set: { value in model.updateMagic { $0.language = value } })) {
                        ForEach(CaptionLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("The language spoken in the clips, for captions and for finding filler words")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("What it does").font(.headline)
                toggle("Cut filler words (um, eh) and repeats", \.removesFillers)
                toggle("Cut the pauses between sentences", \.removesPauses)
                toggle("Captions of what is said", \.showsCaptions)
                if session.options.length != .keepAll {
                    toggle("Keep the best moments, not just the start", \.findsBestMoments)
                }
                toggle("A hook title from the first sentence", \.addsHookTitle)
                toggle("\(session.options.style.music.displayName) music, made by the app (free to use)", \.addsMusic)
                Text(
                    "Clips with nobody talking are cut to their middle 4 seconds. The end comes right after the last word, so the Short loops back to the start cleanly."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }

            HStack {
                Text("Edit ▸ Undo puts everything back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelMagic() }
                    .keyboardShortcut(.cancelAction)
                Button("Make My Short") { model.runMagic() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isImporting || model.project.timeline.clips.isEmpty)
            }
        }
    }

    private func toggle(_ title: String, _ key: WritableKeyPath<MagicOptions, Bool>) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { model.magic?.options[keyPath: key] ?? false },
                set: { value in model.updateMagic { $0.options[keyPath: key] = value } }))
    }

    // MARK: Working

    private func working(_ text: String, _ fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text).font(.headline)
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text("Listening takes about a quarter of the clips' length. Everything stays on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Stop", role: .cancel) { model.cancelMagic() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: Done

    private func done(_ report: MagicReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Short is ready: \(TimeFormat.string(model.duration).dropLast(2))")
                .font(.headline)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines(report), id: \.self) { line in
                    Label(line, systemImage: "checkmark")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if report.hookNeedsText {
                    Label(
                        "Nobody talks in these clips, so the hook title says “\(MagicShort.placeholderHook)”. Type your own when this closes.",
                        systemImage: "pencil"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Text("Edit ▸ Undo Magic Short puts everything back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.finishMagic(play: false) }
                    .keyboardShortcut(.cancelAction)
                Button(report.hookNeedsText ? "Write the Hook" : "Play It") { model.finishMagic(play: true) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
    }

    private func lines(_ report: MagicReport) -> [String] {
        var lines: [String] = []
        var cuts: [String] = []
        if report.removedFillers > 0 { cuts.append(report.removedFillers == 1 ? "1 filler word" : "\(report.removedFillers) filler words") }
        if report.removedPauses > 0 { cuts.append(report.removedPauses == 1 ? "1 pause" : "\(report.removedPauses) pauses") }
        if !cuts.isEmpty {
            lines.append("Cut \(cuts.joined(separator: " and ")), \(String(format: "%.1f", report.removedTime.seconds)) s in all")
        } else if report.removedTime > .zero {
            lines.append("Made \(String(format: "%.1f", report.removedTime.seconds)) s shorter")
        }
        if let kept = report.keptSentences, let said = report.sentencesSaid {
            lines.append("Kept the best \(kept) of \(said) sentences, \(report.momentsByModel ? "picked by Apple Intelligence" : "the liveliest run")")
        }
        if model.project.captions.isVisible, report.hasSpeech { lines.append("Captions in the \(model.project.style?.displayName ?? "") style") }
        if let id = report.hookTitleID, !report.hookNeedsText, let title = model.project.title(id: id) { lines.append("Hook title: “\(title.text)”") }
        if let music = model.project.music, let mood = music.mood { lines.append("\(mood.displayName) music, lowered while someone talks") }
        if model.project.style?.motion == .punchIns { lines.append("Punch-ins on every other cut") }
        lines.append("Ends right after the last word, ready to loop")
        return lines
    }
}

// MARK: - Storyboards

/// The storyboard chooser: every template with its shot list.
struct StoryboardChooser: View {
    @Bindable var model: EditorModel
    @State private var chosen: StoryboardKind = .tutorial

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start from a Storyboard").font(.title2.weight(.semibold))
                Text("A shot list that tells you what to film and for how long. Fill each shot with a clip; they go in order.")
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    ForEach(StoryboardKind.allCases) { kind in
                        Button {
                            chosen = kind
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: kind.systemImage).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(kind.displayName).font(.body.weight(chosen == kind ? .bold : .regular))
                                    Text(kind.hint).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if chosen == kind { Image(systemName: "checkmark") }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(chosen == kind ? 0.12 : 0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen == kind ? Color.accentColor : .clear, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen == kind ? .isSelected : [])
                    }
                }
                .frame(width: 250)

                VStack(alignment: .leading, spacing: 8) {
                    let board = Storyboard(kind: chosen)
                    HStack {
                        Text("\(board.slots.count) shots · about \(Int(board.plannedLength.seconds.rounded())) s")
                            .font(.headline)
                        Spacer()
                        Label(chosen.suggestedStyle.displayName, systemImage: chosen.suggestedStyle.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("The style it starts in. You can change it any time.")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(board.slots.enumerated()), id: \.offset) { index, slot in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(Color.white.opacity(0.12)))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(slot.shot.name) · \(Int(slot.shot.length.seconds)) s").font(.callout.weight(.semibold))
                                        Text(slot.shot.direction).font(.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 300, height: 300)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.choosesStoryboard = false }
                    .keyboardShortcut(.cancelAction)
                Button("Start \(chosen.displayName)") { model.newShort(from: chosen) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
    }
}

/// The left panel's "Shots" tab: the storyboard's shot list, filled or waiting for a clip.
struct StoryboardView: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let board = model.project.storyboard {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    let filled = board.slots.filter { model.project.clip(filling: $0) != nil }.count
                    Text("\(filled) of \(board.slots.count) shots filled · planned \(Int(board.plannedLength.seconds.rounded())) s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(board.slots.enumerated()), id: \.element.id) { index, slot in
                            ShotRow(model: model, number: index + 1, slot: slot)
                        }
                    }
                    .padding(10)
                }
                Divider()
                HStack {
                    Text("Drop a clip on a shot, or select one in Media and click Use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Done") { model.closeStoryboard() }
                        .help("Stop showing the shot list. Your clips stay")
                }
                .padding(10)
            }
        } else {
            VStack(spacing: 10) {
                Text("This Short has no storyboard.").foregroundStyle(.secondary)
                Button("Choose a Storyboard…") { model.choosesStoryboard = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ShotRow: View {
    let model: EditorModel
    let number: Int
    let slot: Storyboard.Slot
    @State private var isTargeted = false

    private var clip: Clip? { model.project.clip(filling: slot) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                if let clip, let image = model.thumbnails[clip.assetID] {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.05)
                    Image(systemName: clip == nil ? "video.badge.plus" : "film").foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(clip == nil ? 0.6 : 0), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(number). \(slot.shot.name)").font(.callout.weight(.semibold))
                    if clip != nil { Image(systemName: "checkmark.circle.fill").font(.caption).accessibilityLabel("Filled") }
                    Spacer(minLength: 0)
                    Text(lengthText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(slot.shot.direction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if clip != nil {
                        Button("Show") { model.showShot(slot) }
                        Button("Replace…") { model.chooseFile(for: slot.id) }
                        Button("Remove") { model.emptyShot(slot.id) }
                    } else {
                        Button("Choose…") { model.chooseFile(for: slot.id) }
                        Button("Use Selected") { if let id = model.selectedAssetID { model.fill(slot.id, with: id) } }
                            .disabled(model.selectedAssetID.flatMap { model.project.asset(id: $0) }?.hasVideo != true)
                            .help("Use the file selected in Media")
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(isTargeted ? 0.14 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2))
        .dropDestination(for: URL.self) { urls, _ in
            model.fill(slot.id, withFiles: urls)
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot \(number), \(slot.shot.name)")
    }

    private var lengthText: String {
        let planned = "\(Int(slot.shot.length.seconds)) s"
        guard let clip else { return planned }
        return String(format: "%.1f s", clip.duration.seconds)
    }
}

// MARK: - Home tiles

/// A home-window tile for a way to start a Short (Magic Short, Storyboard).
struct StartTile: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color(white: isHovered ? 0.26 : 0.21)
                    VStack(spacing: 10) {
                        Image(systemName: systemImage)
                            .font(.system(size: 34, weight: .light))
                        Text(title)
                            .font(.headline)
                    }
                    .foregroundStyle(.primary)
                }
                .frame(width: HomeView.tileWidth, height: HomeView.tileWidth * 16 / 9)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.5), lineWidth: 1.5))
                Text(" ").font(.callout)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(title)
    }
}
