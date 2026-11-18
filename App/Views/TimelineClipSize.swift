import SwiftUI

/// How tall the clips are on the timeline: bigger clips show bigger pictures and sound waves
/// (iMovie's Clip Size). Remembered for every Short.
enum TimelineClipSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The height of a main clip.
    var trackHeight: CGFloat {
        switch self {
        case .small: 56
        case .medium: 76
        case .large: 112
        }
    }

    /// The height of the sound wave at the bottom of a main clip.
    var waveHeight: CGFloat {
        switch self {
        case .small: 20
        case .medium: 30
        case .large: 48
        }
    }
}

/// View ▸ Clip Size.
struct TimelineViewCommands: Commands {
    @AppStorage(SettingsKey.clipSize, store: AppEnvironment.defaults) private var clipSize = TimelineClipSize.medium

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Picker("Clip Size", selection: $clipSize) {
                ForEach(TimelineClipSize.allCases) { Text($0.displayName).tag($0) }
            }
            Divider()
        }
    }
}

/// The Clip Size menu in the timeline's header.
struct ClipSizeMenu: View {
    @AppStorage(SettingsKey.clipSize, store: AppEnvironment.defaults) private var clipSize = TimelineClipSize.medium

    var body: some View {
        Picker("Clip Size", selection: $clipSize) {
            ForEach(TimelineClipSize.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .controlSize(.small)
        .help("How tall the clips are: bigger clips show bigger pictures and sound waves (View ▸ Clip Size)")
    }
}
