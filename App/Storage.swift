import AppKit
import EditorCore
import RenderEngine
import SwiftUI

/// Keeping the app's own files from piling up: made copies no Short uses go by themselves at
/// launch; media the app made for Shorts (recordings, spoken text, backwards copies, copies from
/// Photos) can only be moved to the Trash by the user, from Settings ▸ Storage.
extension ProjectStore {
    /// Folders of media the app made or copied for Shorts. Shorts point at these files like at
    /// any other media, and some (recordings) can't be made again.
    static var madeMediaFolders: [URL] {
        ["Voice-overs", "Voices", "Backwards", "From Photos"].map { appFolder.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// Calls `body` with every Short in the library, its media reachable through the saved
    /// bookmarks for as long as `body` runs (so copies named after a file's size and date match).
    static func withLibraryProjects<T>(_ body: ([Project]) -> T) -> T {
        withLibraryShorts { shorts in body(shorts.map(\.project)) }
    }

    /// `withLibraryProjects` with each Short's id (its file's name).
    static func withLibraryShorts<T>(_ body: ([(id: UUID, project: Project)]) -> T) -> T {
        let files = (try? FileManager.default.contentsOfDirectory(at: libraryFolder, includingPropertiesForKeys: nil)) ?? []
        let media = MediaAccess()
        defer { media.close() }
        let shorts = files.filter { $0.pathExtension == ProjectFile.fileExtension }.compactMap { url -> (id: UUID, project: Project)? in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                let file = Log.file.attempt("Reading a Short for clean-up", { try ProjectFile.decode(Data(contentsOf: url)) })
            else { return nil }
            return (id, media.resolve(file).project)
        }
        return body(shorts)
    }

    /// For every Short in the library that has some: the copies the app made for it alone
    /// (Delete Generated Files removes them; they are made again when the Short is opened).
    static func generatedFilesByShort() -> [UUID: [URL]] {
        finishSaving()
        return withLibraryShorts { shorts in
            let files = StorageCleaner.generatedFiles(of: shorts.map(\.project))
            return Dictionary(uniqueKeysWithValues: zip(shorts.map(\.id), files).filter { !$0.1.isEmpty })
        }
    }

    /// At launch, before a Short is open: removes made copies no Short has used for a week.
    static func removeUnusedCopies() {
        let freed = withLibraryProjects { StorageCleaner.removeUnusedCopies(keepingFor: $0) }
        if freed > 0 { Log.storage.info("Removed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file), privacy: .public) of unused copies") }
    }

    /// Media the app made that no Short in the library uses.
    static func unusedMadeMedia() -> [URL] {
        withLibraryProjects { projects in
            StorageCleaner.unusedFiles(in: madeMediaFolders, inUse: StorageCleaner.filesInUse(by: projects), before: .distantFuture)
        }
    }
}

/// Settings ▸ Storage: how much room the app's own files take, and moving unused media to the Trash.
struct StorageSettings: View {
    let model: EditorModel
    @State private var copies: Int64 = 0
    @State private var media: Int64 = 0
    @State private var unused: [URL] = []
    @State private var result: String?
    /// The copies the app made for each Short alone, largest first.
    @State private var perShort: [(id: UUID, bytes: Int64)] = []

    var body: some View {
        Section {
            LabeledContent("Copies the app made", value: format(copies))
            Text(
                "Cleaned-up voices, slowed-down and cut-out copies of your videos. They are made again when needed; ones no Short has used for a week "
                    + "are removed by themselves. Below, what each Short's own copies take."
            )
            .font(.caption).foregroundStyle(.secondary)
            ForEach(perShort, id: \.id) { short in
                LabeledContent {
                    HStack {
                        Text(format(short.bytes)).monospacedDigit()
                        Button("Delete…") {
                            if model.library.deleteGeneratedFiles(of: short.id) > 0 { measure() }
                        }
                        .help("Delete Generated Files: they are made again the next time you open this Short")
                        .accessibilityLabel("Delete generated files of \(name(of: short.id))")
                    }
                } label: {
                    Text(name(of: short.id)).lineLimit(1).truncationMode(.middle).padding(.leading, 12)
                }
            }
            LabeledContent("Recordings and copied media", value: format(media))
            LabeledContent(
                "Not used by any Short",
                value: unused.isEmpty ? "None" : "\(format(StorageCleaner.size(of: unused))) in \(unused.count) \(unused.count == 1 ? "file" : "files")")
            HStack {
                Button("Move Unused to Trash…") { moveToTrash() }
                    .disabled(unused.isEmpty || model.screen != .home)
                if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
            }
            Text(
                model.screen == .home
                    ? "Voice-overs, spoken text, backwards copies and videos copied from Photos that none of your Shorts use."
                    : "Go back to All Shorts first: the Short you are editing may still need them to undo."
            )
            .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Storage")
        }
        .onAppear(perform: measure)
        .onChange(of: model.screen) { measure() }
    }

    private func measure() {
        copies = StorageCleaner.size(of: StorageCleaner.cacheFolders)
        media = StorageCleaner.size(of: ProjectStore.madeMediaFolders)
        unused = ProjectStore.unusedMadeMedia()
        perShort = ProjectStore.generatedFilesByShort()
            .map { (id: $0.key, bytes: StorageCleaner.size(of: $0.value)) }
            .sorted { $0.bytes > $1.bytes }
    }

    private func name(of id: UUID) -> String {
        model.library.shorts.first { $0.id == id }?.name ?? "A Short"
    }

    private func moveToTrash() {
        let alert = NSAlert()
        alert.messageText = unused.count == 1 ? "Move 1 unused file to the Trash?" : "Move \(unused.count) unused files to the Trash?"
        alert.informativeText =
            "None of your Shorts use them. A copy of a Short saved elsewhere with Save a Copy… may; you can take them back out of the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var moved = 0
        for url in unused where (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { moved += 1 }
        result = moved == unused.count ? "Moved to the Trash." : "\(unused.count - moved) couldn't be moved."
        measure()
    }

    private func format(_ bytes: Int64) -> String {
        bytes == 0 ? "None" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
