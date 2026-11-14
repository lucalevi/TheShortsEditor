import Foundation
import Testing

@testable import EditorCore

/// Every Short in a real library opens with today's code. Only with `SHORTS_LIBRARY` set to a folder of
/// `.shortsproject` files (`make check-library` uses the app's own library on this Mac). Read-only.
/// Run it before changing how files are read: it covers files saved by every build in between the
/// golden versions.
struct LibraryCompatibilityTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHORTS_LIBRARY"] != nil))
    func everyShortInTheLibraryOpens() throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SHORTS_LIBRARY"]))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ProjectFile.fileExtension }
        #expect(!files.isEmpty)
        for url in files {
            do {
                let file = try ProjectFile.decode(Data(contentsOf: url))
                // Saving it again and reading it back changes nothing.
                #expect(try ProjectFile.decode(file.encoded()) == file, "\(url.lastPathComponent)")
            } catch {
                Issue.record("\(url.lastPathComponent): \(error)")
            }
        }
    }
}
