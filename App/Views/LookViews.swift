import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// A clip's look: Enhance, filters, colour sliders, picking white or skin, Match Color.
struct LookSection: View {
    let model: EditorModel
    let clip: Clip
    /// The sliders being dragged: the look shown until they are let go.
    @State private var dragging: ColorAdjustments?
    @State private var draggingStrength: Double?
    @State private var showsColor = false

    private var color: ColorAdjustments { dragging ?? clip.look.color }
    private var isBusy: Bool { model.analysingLook.contains(clip.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Look").font(.subheadline.weight(.semibold))
                Spacer()
                OriginalToggle(model: model)
            }

            HStack {
                Button("Enhance", systemImage: "wand.and.stars") { model.enhance([clip.id]) }
                    .help("Fix colour, brightness and contrast in one click (⌥E)")
                    .disabled(isBusy)
                if isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Reset") { model.resetLook(of: [clip.id]) }
                    .disabled(clip.look.isNeutral)
                    .help("Back to the colours as filmed, with no filter")
            }
            .controlSize(.small)

            FilterGrid(model: model, clip: clip, selected: clip.look.filter?.filter) { filter in
                model.setFilter(filter, for: [clip.id])
            }

            if let choice = clip.look.filter {
                HStack {
                    Text("Strength").frame(width: 64, alignment: .leading)
                    Slider(value: Binding(get: { draggingStrength ?? choice.strength }, set: { value in
                        draggingStrength = value
                        var look = clip.look
                        look.filter?.strength = value
                        model.previewLook(look, for: clip.id)
                    }), in: 0...1) { editing in
                        if !editing, let value = draggingStrength {
                            draggingStrength = nil
                            model.setFilterStrength(value, for: [clip.id])
                        }
                    }
                    Text("\(Int(((draggingStrength ?? choice.strength) * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                Button("Use \(choice.filter.displayName) on Every Clip") { model.setFilterOnEveryClip(choice) }
                    .controlSize(.small)
                    .help("Give every clip of the Short this filter, at this strength")
            }

            DisclosureGroup(isExpanded: $showsColor) {
                VStack(alignment: .leading, spacing: 6) {
                    slider("Light", \.exposure, help: "Brighter or darker overall")
                    slider("Contrast", \.contrast, help: "More or less difference between light and dark")
                    slider("Brights", \.highlights, help: "Bring back bright parts (left) or make them brighter (right)")
                    slider("Darks", \.shadows, help: "Deepen dark parts (left) or lift them to show detail (right)")
                    slider("Colour", \.saturation, help: "Less colour, down to black and white (left), or more (right)")
                    slider("Warmth", \.warmth, help: "Cooler and bluer (left) or warmer and more orange (right)")
                    slider("Tint", \.tint, help: "Greener (left) or more magenta (right)")

                    HStack {
                        pickButton("Pick White", systemImage: "eyedropper", target: .white,
                                   help: "Then click something white or grey in the viewer: its colour becomes neutral")
                        pickButton("Pick Skin", systemImage: "face.smiling", target: .skin,
                                   help: "Then click someone's skin in the viewer: it gets a natural skin colour")
                    }
                    .controlSize(.small)

                    let candidates = model.matchCandidates(for: clip.id)
                    Menu("Match Color of…") {
                        ForEach(candidates, id: \.id) { candidate in
                            Button(candidate.label) { model.matchColor(of: clip.id, to: candidate.id) }
                        }
                    }
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(candidates.isEmpty || isBusy)
                    .help("Give this clip the colours of another clip, so they look filmed together")
                }
                .padding(.top, 4)
            } label: {
                Text(clip.look.color.isNeutral ? "Colour" : "Colour (changed)")
                    .font(.callout)
            }

            Text(model.colorPick?.clipID == clip.id ? model.colorPick!.prompt + ". Press Escape to stop."
                 : "Filters change the mood. Enhance fixes dull or dark clips. Press ⌥C to compare with the original.")
                .font(.caption)
                .foregroundStyle(model.colorPick?.clipID == clip.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { showsColor = !clip.look.color.isNeutral }
    }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<ColorAdjustments, Double>, help: String) -> some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { color[keyPath: keyPath] }, set: { value in
                // Sticks to the middle.
                var adjusted = dragging ?? clip.look.color
                adjusted[keyPath: keyPath] = abs(value) < 0.04 ? 0 : value
                dragging = adjusted
                var look = clip.look
                look.color = adjusted
                model.previewLook(look, for: clip.id)
            }), in: ColorAdjustments.range) { editing in
                if !editing, let value = dragging {
                    dragging = nil
                    model.editColor(of: [clip.id], title) { $0 = value }
                }
            }
            Text(label(color[keyPath: keyPath]))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .help(help)
    }

    private func label(_ value: Double) -> String {
        let v = Int((value * 100).rounded())
        return v == 0 ? "0" : v > 0 ? "+\(v)" : "\(v)"
    }

    private func pickButton(_ title: String, systemImage: String, target: ColorAdjustments.BalanceTarget, help: String) -> some View {
        let active = model.colorPick == ColorPick(clipID: clip.id, target: target)
        return Button(title, systemImage: systemImage) { model.beginColorPick(target, for: clip.id) }
            .buttonStyle(.bordered)
            .tint(active ? .accentColor : nil)
            .help(help)
    }
}

/// The before/after switch: every picture without its colour and filters while it is on.
struct OriginalToggle: View {
    let model: EditorModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.showsOriginalLook }, set: { model.showsOriginalLook = $0 })) {
            Label("Original", systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal")
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help("Compare with the original: show the clips without colour changes and filters (⌥C)")
    }
}

/// Every filter shown on the clip's own picture, plus None. `selected` is outlined.
struct FilterGrid: View {
    let model: EditorModel
    let clip: Clip?
    let selected: LookFilter?
    let choose: (LookFilter?) -> Void
    /// The picture each tile shows (nil: still being made).
    @State private var previews: [LookFilter?: CGImage] = [:]

    private let columns = [GridItem(.adaptive(minimum: 70), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            tile(nil, name: "None")
            ForEach(LookFilter.allCases) { filter in
                tile(filter, name: filter.displayName)
            }
        }
        .task(id: previewKey) { await makePreviews() }
    }

    /// What the tiles depend on: the clip, where the playhead is in it, and its sliders.
    private var previewKey: String {
        guard let clip else { return "none" }
        let time = model.project.sourceTime(ofClip: clip.id, at: model.currentTime)?.seconds ?? 0
        return "\(clip.id)|\(clip.assetID)|\((time * 2).rounded())|\(clip.look.color.hashValue)"
    }

    private func tile(_ filter: LookFilter?, name: String) -> some View {
        Button { choose(filter) } label: {
            VStack(spacing: 2) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let image = previews[filter] {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(selected == filter ? Color.accentColor : .clear, lineWidth: 2.5)
                }
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(selected == filter ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(filter == nil ? "No filter" : "\(name) filter")
    }

    private func makePreviews() async {
        guard let clip, let frame = await model.lookFrame(of: clip, maxSize: CGSize(width: 160, height: 160)) else {
            previews = [:]
            return
        }
        let color = clip.look.color
        let made = await Task.detached(priority: .userInitiated) {
            var made: [LookFilter?: CGImage] = [:]
            made[nil] = LookRenderer.preview(frame, look: ClipLook(color: color))
            for filter in LookFilter.allCases {
                made[filter] = LookRenderer.preview(frame, look: ClipLook(color: color, filter: FilterChoice(filter)))
            }
            return made
        }.value
        guard !Task.isCancelled else { return }
        previews = made
    }
}

/// Stabilize: smooths out camera shake, zooming in a little to hide the moving edges.
struct SteadySection: View {
    let model: EditorModel
    let clip: Clip
    @State private var dragging: Double?

    private var progress: Double? { model.steadying[clip.assetID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Steady shaky video", isOn: Binding(get: { clip.steadiness > 0 }, set: { on in
                model.setSteadiness(on ? Clip.defaultSteadiness : 0, for: [clip.id])
            }))
            .font(.subheadline.weight(.semibold))
            if clip.steadiness > 0 {
                HStack {
                    Text("Amount").frame(width: 64, alignment: .leading)
                    Slider(value: Binding(get: { dragging ?? clip.steadiness }, set: { dragging = $0 }), in: 0.05...1) { editing in
                        if !editing, let value = dragging {
                            dragging = nil
                            model.setSteadiness(value, for: [clip.id])
                        }
                    }
                    Text("\(Int(((dragging ?? clip.steadiness) * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                if let progress {
                    ProgressView(value: progress) { Text("Looking at how the camera moves…").font(.caption) }
                }
            }
            Text(clip.steadiness > 0
                 ? "More steadies more, but zooms in a little more to hide the moving edges. Planned camera moves are kept."
                 : "Smooths out a shaky hand. The picture zooms in a little to hide the edges.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The filter over the whole Short (on top of each clip's look).
struct ShortLookSection: View {
    let model: EditorModel
    @State private var dragging: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Look of the whole Short").font(.subheadline.weight(.semibold))
                Spacer()
                OriginalToggle(model: model)
            }
            FilterGrid(model: model, clip: model.clipAtPlayhead, selected: model.project.look?.filter) { model.setShortFilter($0) }
            if let choice = model.project.look {
                HStack {
                    Text("Strength").frame(width: 64, alignment: .leading)
                    Slider(value: Binding(get: { dragging ?? choice.strength }, set: { value in
                        dragging = value
                        model.previewShortFilterStrength(value)
                    }), in: 0...1) { editing in
                        if !editing, let value = dragging {
                            dragging = nil
                            model.setShortFilterStrength(value)
                        }
                    }
                    Text("\(Int(((dragging ?? choice.strength) * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Text("Goes over every clip, on top of their own colour and filters. Titles and captions keep their colours.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Enhance and a filter for several selected clips at once.
struct MultipleLookSection: View {
    let model: EditorModel
    let clips: [Clip]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Look").font(.subheadline.weight(.semibold))
            HStack {
                Button("Enhance All", systemImage: "wand.and.stars") { model.enhance(clips.map(\.id)) }
                    .disabled(!model.analysingLook.isDisjoint(with: clips.map(\.id)))
                Menu("Filter") {
                    Button("None") { model.setFilter(nil, for: clips.map(\.id)) }
                    Divider()
                    ForEach(LookFilter.allCases) { filter in
                        Button(filter.displayName) { model.setFilter(filter, for: clips.map(\.id)) }
                    }
                }
                .fixedSize()
            }
            .controlSize(.small)
            let steadiable = clips.filter(model.canStabilize)
            if !steadiable.isEmpty {
                let allSteady = steadiable.allSatisfy { $0.steadiness > 0 }
                Button(allSteady ? "Stop Steadying" : "Steady Shaky Video") {
                    model.setSteadiness(allSteady ? 0 : Clip.defaultSteadiness, for: steadiable.map(\.id))
                }
                .controlSize(.small)
            }
        }
    }
}

/// Over the viewer while picking white or skin: a crosshair, and a click reads the spot.
struct ColorPickOverlay: View {
    let model: EditorModel

    var body: some View {
        if let pick = model.colorPick {
            GeometryReader { geometry in
                let scale = geometry.size.width / Project.canvasSize.width
                Color.white.opacity(0.001)
                    .onTapGesture { location in
                        model.pickColor(at: CGPoint(x: location.x / scale, y: location.y / scale))
                    }
                    .onHover { inside in
                        if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                    }
                    .onDisappear { NSCursor.arrow.set() }
                    .overlay(alignment: .top) {
                        HStack(spacing: 8) {
                            Image(systemName: pick.target == .white ? "eyedropper" : "face.smiling")
                            Text(pick.prompt)
                            Button("Cancel") { model.colorPick = nil }
                                .controlSize(.small)
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 10)
                    }
            }
        } else if model.showsOriginalLook {
            Text("Original")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .allowsHitTesting(false)
        }
    }
}
