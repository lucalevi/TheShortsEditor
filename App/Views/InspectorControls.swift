import CoreMedia
import EditorCore
import RenderEngine
import SwiftUI

/// A row of colour swatches, optionally with "None". Each swatch says its colour when pointed at.
struct ColorRow: View {
    let title: String
    let selection: RGBA?
    var allowsNone = false
    let onChange: (RGBA?) -> Void

    private static let names = ["White", "Black", "Yellow", "Orange", "Red", "Pink", "Purple", "Blue", "Cyan", "Green", "Lime"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if allowsNone {
                    swatch(nil, name: "None")
                }
                ForEach(Array(RGBA.palette.enumerated()), id: \.offset) { index, color in
                    swatch(color, name: Self.names[index])
                }
            }
        }
    }

    private func swatch(_ color: RGBA?, name: String) -> some View {
        let isSelected = color == selection
        return Button {
            onChange(color)
        } label: {
            ZStack {
                if let color {
                    Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                } else {
                    Circle().strokeBorder(Color.secondary, lineWidth: 1)
                    Image(systemName: "line.diagonal").font(.system(size: 10))
                }
            }
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 1 : 0.25), lineWidth: isSelected ? 2.5 : 1).padding(-2))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A menu of font families, with the system font and adding font files.
struct FontMenu: View {
    let model: EditorModel
    let selection: String?
    let onChange: (String?) -> Void

    var body: some View {
        Menu {
            Button("System Font") { onChange(nil) }
            Divider()
            ForEach(FontLibrary.families, id: \.self) { family in
                Button(family) { onChange(family) }
            }
            Divider()
            Button("Add Fonts…") { model.importFonts() }
        } label: {
            Text(selection ?? "System Font").lineLimit(1)
        }
        .help("The font. Add your own with Add Fonts… at the bottom.")
    }
}

/// Whether a title, B-roll clip or sound moves with the main clip under its start.
struct FollowClipToggle: View {
    let model: EditorModel
    let item: TimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Move with the clip under it", isOn: Binding(get: { model.project.followsClip(item) }, set: { model.setFollowsClip($0, for: item) }))
            Text(
                model.project.followsClip(item)
                    ? "Pinned to the clip below its start (the thin line on the timeline): moving, trimming or speeding up that clip carries it along."
                    : "Stays at its time on the timeline whatever happens to the clips, e.g. to land on a beat of the music."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Reset All for a clip, and copying its settings to others.
struct ClipSettingsButtons: View {
    let model: EditorModel
    let clipID: Clip.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings").font(.subheadline.weight(.semibold))
            HStack {
                Button("Copy", systemImage: "doc.on.doc") { model.copySettings() }
                    .help("Copy this clip's picture, motion, speed and sound settings (⌥⌘C), to paste on other clips (⌥⌘V)")
                Menu("Paste") {
                    Button("All") { model.pasteSettings(Set(SettingsKind.allCases)) }
                    Divider()
                    ForEach(SettingsKind.allCases) { kind in
                        Button(kind.displayName) { model.pasteSettings([kind]) }
                    }
                }
                .fixedSize()
                .disabled(model.copiedClip == nil || model.copiedClip?.id == clipID)
                Button("Reset All") { model.resetSettings(Set(SettingsKind.allCases), of: [clipID]) }
                    .disabled(model.project.changedSettings(of: clipID).isEmpty)
                    .help("Back to how the clip was when added: picture, motion, speed and sound")
            }
            .controlSize(.small)
        }
    }
}
