import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// Following the subject: makes a horizontal clip vertical by gliding with the face or subject.
struct FollowSubjectButton: View {
    let model: EditorModel
    let clip: Clip

    var body: some View {
        let isWide = model.project.asset(id: clip.assetID).map { $0.displaySize.width > $0.displaySize.height * 0.75 } ?? false
        if isWide {
            VStack(alignment: .leading, spacing: 4) {
                if let progress = model.tasks.progress(.reframe(clip.id)) {
                    ProgressView(value: progress) { Text("Finding the subject…").font(.caption) }
                } else {
                    Button("Follow the Subject", systemImage: "person.crop.rectangle") { model.followSubject(clip.id) }
                        .disabled(model.tasks.isRunning(kind: .reframe))
                        .help("Fill the screen and glide to keep the face (or what stands out) in the middle")
                }
            }
            .controlSize(.small)
        }
    }
}

/// How B-roll shares the screen: over the clip, split screen, or small in a corner.
struct LayoutSection: View {
    let model: EditorModel
    let overlay: Overlay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layout").font(.subheadline.weight(.semibold))
            Picker(
                "Layout",
                selection: Binding(
                    get: { overlay.layout.isSplit },
                    set: { split in
                        model.setLayout(split ? .top : .free, for: overlay.id)
                    })
            ) {
                Text("Over").tag(false)
                Text("Split Screen").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(
                overlay.layout == .free
                    ? "Over the clip below it. Or put it small in a corner:"
                    : "This clip fills the part chosen below, the clip under it the rest. "
                        + "Two split clips at once can share the screen in three, like a top and a bottom third."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if overlay.layout.isSplit {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(OverlayLayout.splits) { layout in
                        let isChosen = overlay.layout == layout
                        Button {
                            model.setLayout(layout, for: overlay.id)
                        } label: {
                            Label(layout.displayName, systemImage: isChosen ? "checkmark" : layout.symbolName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .help("This clip in the \(layout.displayName.lowercased()) of the screen")
                        .accessibilityAddTraits(isChosen ? .isSelected : [])
                    }
                }
                .controlSize(.small)
            }
            if overlay.layout == .free {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(PictureCorner.allCases) { corner in
                        Button(corner.displayName) { model.putInCorner(corner, overlayID: overlay.id) }
                            .help("Small, in the corner, clear of YouTube's buttons")
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

extension OverlayLayout {
    /// A small picture of where the clip goes.
    var symbolName: String {
        switch self {
        case .free: "rectangle"
        case .top, .topThird: "rectangle.tophalf.filled"
        case .bottom, .bottomThird: "rectangle.bottomhalf.filled"
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        }
    }
}
