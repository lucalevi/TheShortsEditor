import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

// Text, stickers and voice (Stage H) in the window: the sticker and template picker, the parts
// of the title inspector for stickers, motion and following, and the text-to-speech sheet.

/// Ready-made texts, emoji and symbols, added at the playhead with one click.
struct StickerPicker: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ready-made texts").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(TextTemplate.allCases) { template in
                        Button {
                            model.addTextTemplate(template)
                            dismiss()
                        } label: {
                            Text(template.displayName)
                                .font(.callout.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.15)) }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(template.hint)
                    }
                }

                Text("Emoji").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(StickerCatalog.emoji, id: \.self) { emoji in
                        tile(Sticker(.emoji(emoji))) { Text(emoji).font(.system(size: 26)) }
                    }
                }

                ForEach(StickerCatalog.groups) { group in
                    Text(group.name).font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(group.symbols) { symbol in
                            tile(Sticker(.symbol(symbol.name), color: symbol.name == "bell.fill" ? .yellow : .white)) {
                                Image(systemName: symbol.name).font(.system(size: 22, weight: .bold))
                            }
                            .help(symbol.displayName)
                        }
                    }
                }
                Text("Added at the playhead for two seconds. Drag it in the viewer; change it on the right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 360, height: 520)
    }

    private func tile<Icon: View>(_ sticker: Sticker, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            model.addSticker(sticker)
            dismiss()
        } label: {
            icon()
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sticker.name)
    }
}

/// A sticker's own settings: how big, what colour (symbols), and which one.
struct StickerSection: View {
    let model: EditorModel
    let title: TextOverlay
    let sticker: Sticker
    @State private var dragging: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Group {
                    if let image = TitlePreview.image(for: sticker) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                    }
                }
                .frame(width: 64, height: 64)
                .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sticker.name).font(.headline)
                    Text(sticker.isEmoji ? "Emoji sticker" : "Symbol sticker").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Size").frame(width: 34, alignment: .leading)
                Slider(value: Binding(get: { dragging ?? sticker.size }, set: { dragging = $0 }), in: Sticker.sizeRange) { editing in
                    if !editing, let value = dragging {
                        dragging = nil
                        model.editTitle(title.id, "Change Sticker Size") { $0.sticker?.size = value.rounded() }
                    }
                }
                .controlSize(.small)
                Text("\(Int((dragging ?? sticker.size).rounded()))").monospacedDigit().frame(width: 36, alignment: .trailing)
            }
            if !sticker.isEmoji {
                ColorRow(title: "Colour", selection: sticker.color) { color in
                    if let color { model.editTitle(title.id, "Change Sticker Colour") { $0.sticker?.color = color } }
                }
            }
        }
    }
}

/// How a title or sticker comes in, moves while on screen, leaves, and how it is turned.
struct TitleMotionSection: View {
    let model: EditorModel
    let title: TextOverlay
    @State private var turning: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animation").font(.subheadline.weight(.semibold))
            row("Comes in") {
                Picker("Comes in", selection: Binding(get: { title.entrance }, set: { entrance in
                    model.editTitle(title.id, "Change Animation") { $0.entrance = entrance }
                })) {
                    ForEach(TitleEntrance.allCases.filter { !title.isSticker || $0 != .typewriter }) { Text($0.displayName).tag($0) }
                }
            }
            row("While on") {
                Picker("While on", selection: Binding(get: { title.loop }, set: { loop in
                    model.editTitle(title.id, loop == nil ? "Hold Still" : "Loop Animation") { $0.loop = loop }
                    if loop != nil { model.playTitle(title.id) }
                })) {
                    Text("Still").tag(TitleLoop?.none)
                    Divider()
                    ForEach(TitleLoop.allCases) { Text($0.displayName).tag(TitleLoop?.some($0)) }
                }
            }
            row("Goes out") {
                Picker("Goes out", selection: Binding(get: { title.exit?.kind }, set: { kind in
                    model.editTitle(title.id, kind == nil ? "No Animation Out" : "Animation Out") {
                        $0.exit = kind.map { ClipAnimation($0, duration: TextOverlay.exitDuration) }
                    }
                    if kind != nil { model.playTitle(title.id, end: true) }
                })) {
                    Text("Just goes").tag(MotionAnimation?.none)
                    Divider()
                    ForEach(MotionAnimation.allCases) { Label($0.displayName, systemImage: $0.systemImage).tag(MotionAnimation?.some($0)) }
                }
            }
            row("Turn") {
                HStack {
                    Slider(value: Binding(get: { turning ?? title.rotation }, set: { turning = $0 }), in: -180...180) { editing in
                        if !editing, let value = turning {
                            turning = nil
                            // Sticks to straight.
                            let degrees = abs(value) < 3 ? 0 : value.rounded()
                            model.editTitle(title.id, "Turn") { $0.rotation = degrees }
                        }
                    }
                    .controlSize(.small)
                    Text("\(Int((turning ?? title.rotation).rounded()))°").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    private func row<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(name).frame(width: 64, alignment: .leading)
            content()
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

/// Makes a title or sticker follow something in the video.
struct FollowSubjectSection: View {
    let model: EditorModel
    let title: TextOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Follow something in the video").font(.subheadline.weight(.semibold))
            if let tracking = model.tracking, tracking.id == title.id {
                ProgressView(value: tracking.progress) { Text("Following…").font(.caption) }
            } else if title.track != nil {
                HStack {
                    Label("Follows what was under it", systemImage: "scope")
                    Spacer()
                    Button("Stop Following") { model.stopFollowing(title.id) }
                        .controlSize(.small)
                }
                Button("Follow Again from Here") { model.followInVideo(title.id) }
                    .controlSize(.small)
                    .help("Follow what is under it now, at its first moment (after you moved it)")
            } else {
                Button("Follow", systemImage: "scope") { model.followInVideo(title.id) }
                    .disabled(model.tracking != nil || title.visibleRange(in: model.project) == nil)
                Text("Put it on a face or an object at its first moment, then click Follow: it moves with that for as long as it is on screen. Done on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Turns text into a voice-over with one of the Mac's voices.
struct SpeechSheet: View {
    let model: EditorModel
    @State var request: SpeechRequest
    @State private var language: CaptionLanguage
    @State private var voiceID: String?
    @State private var rate = 1.0
    @State private var personalAllowed = SpeechMaker.personalVoiceAllowed

    init(model: EditorModel, request: SpeechRequest) {
        self.model = model
        _request = State(initialValue: request)
        // The language the Short's captions are in.
        _language = State(initialValue: model.captionLanguage)
    }

    private var voices: [SpeechMaker.Voice] {
        SpeechMaker.voices(for: language.rawValue).filter { !$0.isPersonal || personalAllowed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Speak Text").font(.title2.weight(.semibold))
            Text("A voice reads your words and they go in as a voice-over at \(TimeFormat.string(request.start)). Made on this Mac with its own voices.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $request.text)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            Form {
                Picker("Language", selection: $language) {
                    ForEach(CaptionLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Voice", selection: $voiceID) {
                    ForEach(voices) { voice in
                        Text(voice.isPersonal ? "\(voice.name) (your Personal Voice)" : voice.isBetter && !voice.name.contains("(") ? "\(voice.name) (better quality)" : voice.name)
                            .tag(Optional(voice.id))
                    }
                }
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $rate, in: 0.6...1.5)
                        Text("\(rate.formatted(.number.precision(.fractionLength(1))))×").monospacedDigit().frame(width: 36)
                    }
                }
            }
            .formStyle(.columns)
            if !personalAllowed {
                Button("Use My Personal Voice…") {
                    Task { personalAllowed = await SpeechMaker.allowPersonalVoice() }
                }
                .buttonStyle(.link)
                .help("If you made a Personal Voice in System Settings ▸ Accessibility, it can read your text")
            }
            Text("More and better voices: System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voice ▸ Manage Voices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Listen", systemImage: "speaker.wave.2") { SpeechMaker.preview(request.text, voice: voiceID, rate: rate) }
                    .disabled(request.text.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if model.makingSpeech { ProgressView().controlSize(.small) }
                Button("Cancel") {
                    SpeechMaker.stopPreview()
                    model.speechRequest = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Add Voice-Over") {
                    SpeechMaker.stopPreview()
                    model.makeSpeech(request, voice: voiceID, rate: rate)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(request.text.trimmingCharacters(in: .whitespaces).isEmpty || model.makingSpeech)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: pickVoice)
        .onChange(of: language) { pickVoice() }
        .onChange(of: personalAllowed) { pickVoice() }
    }

    private func pickVoice() {
        if !voices.contains(where: { $0.id == voiceID }) { voiceID = voices.first?.id }
    }
}
