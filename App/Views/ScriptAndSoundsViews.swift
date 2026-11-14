import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

// MARK: - Script (edit by text)

/// The words of the Short as text. Select words and cut them, and the video is cut with them.
struct ScriptView: View {
    @Bindable var model: EditorModel
    /// The last word clicked without ⇧, where a ⇧-click range starts.
    @State private var anchor: WordRef?

    var body: some View {
        let words = model.project.script
        if words.isEmpty {
            ContentUnavailableView {
                Label("No Script Yet", systemImage: "text.alignleft")
            } description: {
                Text("The script is what is said in your clips. Make captions first, and it appears here: cut words to cut the video.")
            } actions: {
                Button("Make Captions") { model.makeCaptions() }
                    .disabled(model.project.timeline.clips.isEmpty || model.captionJob != nil)
            }
        } else {
            VStack(spacing: 0) {
                toolbar(words)
                Divider()
                ScrollView {
                    paragraphs(words)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func toolbar(_ words: [TimedWord]) -> some View {
        let fillers = model.fillerWords
        let selected = model.scriptSelection
        let selectedWords = words.filter { selected.contains($0.ref) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(
                    fillers.isEmpty ? "No Filler Words" : "Remove \(fillers.count) Filler Word\(fillers.count == 1 ? "" : "s")",
                    systemImage: "wand.and.stars"
                ) { model.removeFillerWords() }
                .disabled(fillers.isEmpty)
                .help("Cuts “um”, “eh”, words said twice in a row, and fillers Apple Intelligence found. Underlined with dots below.")
                if model.canUseWordModel, words.contains(where: { $0.source == .clip }) {
                    if model.wordModelJob == .fillers {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Find More", systemImage: "apple.intelligence") { model.findMoreFillers() }
                            .disabled(model.wordModelJob != nil)
                            .help("Apple Intelligence looks for words like “like”, “tipo” or “allora” said only as fillers, on this Mac")
                    }
                }
            }
            if selectedWords.isEmpty {
                Text("Click a word to go there. ⇧-click to select several, then cut them (⌫) and the video is cut too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    let cuttable = selectedWords.filter { $0.source == .clip }.count
                    Button("Cut \(cuttable)", systemImage: "scissors") { model.cutWords(selected) }
                        .disabled(cuttable == 0)
                        .help(
                            cuttable == 0
                                ? "Words in voice-overs and B-roll can't be cut here: trim the sound on the timeline instead"
                                : "Cut these words (and the pause after each) out of the video (⌫)")
                    let allKey = selectedWords.allSatisfy(\.isKeyword)
                    Button(allKey ? "Unhighlight" : "Highlight", systemImage: "highlighter") {
                        model.setKeyword(!allKey, words: Set(selectedWords.map(\.wordID)))
                    }
                    .help("Key words are shown in the accent colour in the captions")
                    if selectedWords.count == 1, let word = selectedWords.first {
                        Menu {
                            ForEach(["🔥", "💰", "😂", "😱", "💡", "✅", "❌", "🚀", "❤️", "👀", "🎯", "💯"], id: \.self) { emoji in
                                Button(emoji) { model.setEmoji(emoji, word: word.wordID) }
                            }
                            if word.emoji != nil {
                                Divider()
                                Button("No Emoji") { model.setEmoji(nil, word: word.wordID) }
                            }
                        } label: {
                            Text(word.emoji ?? "Emoji")
                        }
                        .fixedSize()
                        .help("Shown above the caption this word is in")
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The words, one paragraph per clip, voice-over or B-roll clip, in the order they are heard.
    private func paragraphs(_ words: [TimedWord]) -> some View {
        let groups = Dictionary(grouping: words.enumerated(), by: \.element.clipID)
        var order: [Clip.ID] = []
        for word in words where !order.contains(word.clipID) { order.append(word.clipID) }
        let fillers = Set(model.fillerWords)
        let current = words.last { $0.range.start <= model.currentTime && model.currentTime < $0.range.end + CMTime(value: 1, timescale: 5) }?.ref
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(order, id: \.self) { clipID in
                VStack(alignment: .leading, spacing: 4) {
                    switch groups[clipID]?.first?.element.source {
                    case .sound?:
                        Label("Voice-over or sound", systemImage: "mic").font(.caption).foregroundStyle(.secondary)
                    case .broll?:
                        Label("B-roll", systemImage: "rectangle.on.rectangle").font(.caption).foregroundStyle(.secondary)
                    default:
                        EmptyView()
                    }
                    FlowLayout(spacing: 3, lineSpacing: 4) {
                        ForEach(groups[clipID] ?? [], id: \.element.ref) { index, word in
                            WordChip(
                                word: word, isSelected: model.scriptSelection.contains(word.ref),
                                isCurrent: current == word.ref, isFiller: fillers.contains(word.ref)
                            )
                            .onTapGesture { click(word, index: index, in: words) }
                        }
                    }
                }
            }
        }
    }

    private func click(_ word: TimedWord, index: Int, in words: [TimedWord]) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor, let from = words.firstIndex(where: { $0.ref == anchor }) {
            model.scriptSelection = Set(words[min(from, index)...max(from, index)].map(\.ref))
        } else if modifiers.contains(.command) {
            if model.scriptSelection.remove(word.ref) == nil { model.scriptSelection.insert(word.ref) }
            anchor = word.ref
        } else {
            model.scriptSelection = [word.ref]
            anchor = word.ref
            model.pause()
            model.seek(to: word.range.start)
        }
    }
}

private struct WordChip: View {
    let word: TimedWord
    let isSelected: Bool
    let isCurrent: Bool
    let isFiller: Bool

    var body: some View {
        HStack(spacing: 1) {
            if let emoji = word.emoji { Text(emoji).font(.caption2) }
            Text(word.text)
                .fontWeight(word.isKeyword ? .bold : .regular)
                .underline(word.isKeyword)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(isSelected ? Color.accentColor.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            if isCurrent { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.8), lineWidth: 1) }
        }
        .overlay(alignment: .bottom) {
            if isFiller {
                Rectangle().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])).frame(height: 1.5).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isFiller ? .secondary : .primary)
        .contentShape(Rectangle())
        .help(isFiller ? "A filler word or a repeat" : word.isKeyword ? "Key word" : "")
    }
}

/// Puts views in rows, wrapping to the next row when one is full (like words in a paragraph).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in row.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var items: [(Int, CGFloat)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].items.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + lineSpacing))
            }
            var row = rows[rows.count - 1]
            row.items.append((index, row.width))
            row.width += size.width + spacing
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Sounds

/// Voice-over recording and the sound effects that come with the app.
struct SoundsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        List {
            Section("Voice-over") {
                VStack(alignment: .leading, spacing: 6) {
                    if model.isRecordingVoiceOver {
                        Button("Stop Recording", systemImage: "stop.circle.fill") { model.stopVoiceOver() }
                            .controlSize(.large)
                    } else {
                        Button("Record Voice-Over", systemImage: "mic.circle.fill") { model.startVoiceOver() }
                            .controlSize(.large)
                            .disabled(model.project.timeline.clips.isEmpty)
                    }
                    Text(
                        "Starts at the playhead after 3-2-1. Your Short plays silently while you talk. Stop with the button or Space. The music is lowered under your voice."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            ForEach(SoundEffectGroup.allCases) { group in
                Section(group.displayName) {
                    ForEach(group.effects) { effect in
                        HStack(spacing: 8) {
                            Image(systemName: effect.systemImage).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(effect.displayName)
                                Text(effect.hint).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Listen", systemImage: "play.circle") { model.previewSoundEffect(effect) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                            Button("Add") { model.addSoundEffect(effect) }
                                .controlSize(.small)
                                .disabled(model.project.timeline.clips.isEmpty)
                                .help("Put it on the timeline at the playhead")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.addSoundEffect(effect) }
                    }
                }
            }
            let files = model.project.assets.filter { !$0.hasVideo && $0.hasAudio }
            if !files.isEmpty {
                Section("Your sounds") {
                    ForEach(files) { asset in
                        HStack {
                            Image(systemName: "waveform")
                            Text(asset.name).lineLimit(1)
                            Spacer()
                            Button("Add") { model.addSound(asset.id) }
                                .controlSize(.small)
                                .disabled(model.project.timeline.clips.isEmpty)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}
