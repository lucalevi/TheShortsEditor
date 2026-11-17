import CoreMedia
import EditorCore
import Foundation

/// Reopening the app as it was left (F27): the Short that was open, with its playhead, timeline
/// zoom and side panel. Remembered whenever the Short is saved (and so at quit), forgotten on going
/// back to All Shorts, so the app opens where the user last was.
struct EditingSession: Codable, Equatable {
    var shortID: UUID
    var playheadValue: Int64
    var playheadTimescale: Int32
    var zoom: Double
    var sidebar: String

    var playhead: CMTime { CMTime(value: playheadValue, timescale: max(playheadTimescale, 1)) }

    static let key = "lastSession"

    static var saved: EditingSession? {
        guard let data = AppEnvironment.defaults.data(forKey: key) else { return nil }
        return Log.file.attempt("Reading where the user was") { try JSONDecoder().decode(EditingSession.self, from: data) }
    }
}

extension EditorModel {
    /// Remembers the open Short and where the user is in it; nil forgets it (the home window).
    func rememberSession() {
        guard screen == .editor, let id = openShortID, isWorthKeeping else {
            AppEnvironment.defaults.removeObject(forKey: EditingSession.key)
            return
        }
        let time = playback.currentTime
        let session = EditingSession(
            shortID: id, playheadValue: time.value, playheadTimescale: time.timescale, zoom: Double(timelineZoom), sidebar: sidebar.rawValue)
        if let data = Log.file.attempt("Remembering where the user was", { try JSONEncoder().encode(session) }) {
            AppEnvironment.defaults.set(data, forKey: EditingSession.key)
        }
    }

    /// At launch: opens the Short that was open when the app was quit, as it was. False when it is
    /// gone, and the home window stays.
    @discardableResult
    func reopen(_ session: EditingSession) -> Bool {
        guard FileManager.default.fileExists(atPath: ProjectStore.fileURL(for: session.shortID).path) else { return false }
        openShort(session.shortID)
        guard screen == .editor, openShortID == session.shortID else { return false }
        timelineZoom = min(max(CGFloat(session.zoom), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        if let sidebar = Sidebar(rawValue: session.sidebar), sidebar != .storyboard || project.storyboard != nil { self.sidebar = sidebar }
        playback.seek(to: session.playhead)
        return true
    }
}
