import SwiftUI

/// The editor window: media on the left, the vertical viewer in the middle, details on the right,
/// and the timeline across the bottom.
struct ContentView: View {
    @Bindable var model: EditorModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VSplitView {
            HSplitView {
                MediaBrowserView(model: model)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 400)
                ViewerView(model: model)
                    .frame(minWidth: 320, maxWidth: .infinity)
                InspectorView(model: model)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            }
            .frame(minHeight: 380)
            TimelineView(model: model)
                .frame(minHeight: 170, idealHeight: 220)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Import", systemImage: "square.and.arrow.down") {
                    MediaImportPanel.run(model: model, addToTimeline: false)
                }
                .help("Import videos into Media (⌘I)")
                Button("Split", systemImage: "scissors") { model.splitAtPlayhead() }
                    .help("Cut the clip at the playhead (B)")
                    .disabled(model.project.timeline.clips.isEmpty)
                Button("Delete", systemImage: "trash") { model.deleteSelectedClip() }
                    .help("Remove the selected clip and close the gap (⌫)")
                    .disabled(model.selectedClipID == nil)
            }
            ToolbarItem {
                Toggle("Overlay Areas", systemImage: "rectangle.dashed", isOn: $model.showsSafeZone)
                    .help("Show where YouTube's buttons and captions cover your video (⌘')")
            }
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }
}
