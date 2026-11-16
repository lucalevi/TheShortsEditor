import CoreText
import EditorCore
import SwiftUI

/// Title looks, saved styles (the "brand kit") and fonts the user added.
extension EditorModel {
    // MARK: Title looks and fonts

    func editTitleLook(_ id: TextOverlay.ID, _ actionName: String, _ change: @escaping (inout TextLook) -> Void) {
        editTitle(id, actionName) { change(&$0.look) }
    }

    func saveTextStyle(from title: TextOverlay, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        savedTextStyles.removeAll { $0.name == name }
        savedTextStyles.append(SavedTextStyle(name: name, look: title.look, entrance: title.entrance, exit: title.exit, loop: title.loop))
    }

    func applySavedStyle(_ style: SavedTextStyle, to titleID: TextOverlay.ID) {
        editTitle(titleID, "Use Saved Style") { title in
            title.look = style.look
            title.entrance = style.entrance
            title.exit = style.exit
            title.loop = style.loop
        }
    }

    func deleteSavedStyle(_ id: SavedTextStyle.ID) {
        savedTextStyles.removeAll { $0.id == id }
    }

    /// Lets the user pick font files to use in titles and captions.
    func importFonts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Fonts"
        panel.message = "Choose font files (.ttf, .otf) to use in your titles and captions"
        guard panel.runModal() == .OK else { return }
        let added = FontLibrary.importFonts(panel.urls)
        if added.isEmpty {
            alert = AlertMessage(title: "No fonts were added", message: "These files couldn't be read as fonts.")
        }
    }
}

/// Saved title looks, kept for every Short in the app's preferences.
enum TextStyleStore {
    private static let key = "savedTextStyles"

    static func load() -> [SavedTextStyle] {
        guard let data = AppEnvironment.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedTextStyle].self, from: data)) ?? []
    }

    static func save(_ styles: [SavedTextStyle]) {
        AppEnvironment.defaults.set(try? JSONEncoder().encode(styles), forKey: key)
    }
}

/// Fonts the user added: copied into the app's own folder and made available to it (only to
/// it, not to the rest of the Mac) at every launch.
enum FontLibrary {
    static var folder: URL {
        AppEnvironment.appFolder.appending(path: "Fonts", directoryHint: .isDirectory)
    }

    static func registerImportedFonts() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        guard !files.isEmpty else { return }
        CTFontManagerRegisterFontURLs(files as CFArray, .process, true, nil)
    }

    /// Copies and registers the fonts; returns the family names that were added.
    @discardableResult
    static func importFonts(_ urls: [URL]) -> [String] {
        Log.file.attempt("Making the fonts folder") { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var families: [String] = []
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else { continue }
            let destination = folder.appending(path: url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            guard Log.file.attempt("Copying a font", { try FileManager.default.copyItem(at: url, to: destination) }) != nil else { continue }
            CTFontManagerRegisterFontURLs([destination] as CFArray, .process, true, nil)
            families += descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        }
        return families
    }

    /// Every font family the app can use, by name.
    static var families: [String] {
        NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
    }
}
