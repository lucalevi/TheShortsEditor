import SwiftUI

/// Window ▸ Background Tasks (⌘9): everything the app is making in the background, with how far
/// it has got and a button to stop it, and what failed or was stopped recently.
struct BackgroundTasksView: View {
    static let windowID = "background-tasks"
    @Environment(BackgroundTasks.self) private var tasks

    var body: some View {
        Group {
            if tasks.jobs.isEmpty && tasks.ended.isEmpty {
                ContentUnavailableView(
                    "Nothing in the background", systemImage: "checkmark.circle",
                    description: Text("Long jobs, like cleaning up a voice, turning a clip round or exporting, show here while they run."))
            } else {
                List {
                    if !tasks.jobs.isEmpty {
                        Section("Running") {
                            ForEach(tasks.jobs) { job in
                                RunningJobRow(job: job) { tasks.cancel(job.id) }
                            }
                        }
                    }
                    if !tasks.ended.isEmpty {
                        Section {
                            ForEach(tasks.ended) { job in
                                EndedJobRow(job: job)
                            }
                        } header: {
                            HStack {
                                Text("Stopped or failed")
                                Spacer()
                                Button("Clear") { tasks.clearEnded() }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 220)
    }
}

private struct RunningJobRow: View {
    let job: BackgroundTasks.Job
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.key.kind.symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                if let fraction = job.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                if let detail = job.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Button("Stop", systemImage: "xmark.circle.fill", action: stop)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Stop “\(job.title)”")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(job.fraction.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Working")
        .accessibilityAction(named: "Stop", stop)
    }
}

private struct EndedJobRow: View {
    let job: BackgroundTasks.Ended

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: job.error == nil ? "stop.circle" : "exclamationmark.triangle")
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                Text(job.error.map { "Failed: \($0)" } ?? "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(job.date, style: .time).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
