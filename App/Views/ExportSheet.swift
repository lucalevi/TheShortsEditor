import EditorCore
import RenderEngine
import SwiftUI

/// Checks, then saves the Short as an MP4 with YouTube's recommended settings.
struct ExportSheet: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Your Short").font(.title2.weight(.semibold))
            summary
            Divider()
            switch model.exportPhase {
            case .checking, nil:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking your Short…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                buttons { Button("Cancel", role: .cancel) { model.endExport() } }
            case .review(let issues):
                IssueList(issues: issues)
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Even out the loudness", isOn: $model.evensOutLoudness)
                    Text("Brings the sound to the level YouTube plays Shorts at, so yours isn't quieter than the next one. Recommended.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 20)
                }
                .toggleStyle(.checkbox)
                buttons {
                    Button("Cancel", role: .cancel) { model.endExport() }
                    Button("Export…") { chooseFile() }
                        .keyboardShortcut(.defaultAction)
                }
            case .exporting(let fraction):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: fraction)
                    Text("Exporting… \(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(minHeight: 80)
                buttons { Button("Stop", role: .cancel) { model.endExport() } }
            case .finished(let url):
                Label("Your Short is ready: \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(minHeight: 80)
                buttons {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Done") { model.endExport() }
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 80)
                buttons { Button("Close") { model.endExport() }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            let captions = model.project.hasCaptions && model.project.captions.isVisible
                ? "captions: \(model.project.captions.style.displayName)" : "no captions"
            let music = model.project.musicRange != nil ? " · music" : ""
            Text("\(TimeFormat.string(model.duration)) · vertical 1080 × 1920 · \(captions)\(music)")
            Text("File size: \(model.exportSizeEstimate)")
                .foregroundStyle(.secondary)
            Text("MP4 file with YouTube's recommended settings (H.264, 30 fps, AAC sound).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
        }
    }

    private func chooseFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = model.suggestedExportName
        panel.canCreateDirectories = true
        panel.message = "Where should your Short be saved?"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(to: url)
    }
}

private struct IssueList: View {
    let issues: [ExportIssue]

    var body: some View {
        if issues.isEmpty {
            Label("Everything looks good.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .frame(minHeight: 40)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(issues) { issue in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.headline)
                            Text(issue.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: issue.severity == .warning ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                            .foregroundStyle(issue.severity == .warning ? .orange : .yellow)
                    }
                }
            }
        }
    }
}
