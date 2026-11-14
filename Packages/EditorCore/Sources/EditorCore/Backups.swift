import Foundation

/// When a Short is backed up and which backups are kept (like Final Cut Pro's library backups).
///
/// Before a Short's file is saved over, the version on disk is copied into its backups folder when
/// the newest backup is older than `interval`, and when the Short is opened (if it changed since
/// its newest backup), so File ▸ Revert To can always go back to how it was before this session.
/// Backups are small: the project file only, never media.
public enum BackupPolicy {
    /// A Short being edited is backed up at most this often.
    public static let interval: TimeInterval = 15 * 60
    /// The newest backups are all kept…
    public static let recentCount = 10
    /// …and, before them, the newest backup of each of the last days.
    public static let dailyDays = 7
    /// Backups of a Short that is no longer in the library are removed after this long.
    public static let orphanLifetime: TimeInterval = 30 * 24 * 3600

    /// Whether to back up before saving: when there is no backup yet, or the newest is old enough.
    public static func isDue(newest: Date?, now: Date) -> Bool {
        guard let newest else { return true }
        return now.timeIntervalSince(newest) >= interval
    }

    /// The backups to keep, out of `dates` (any order): the newest `recentCount`, then the newest
    /// of each calendar day within `dailyDays` days of `now`. Everything else can be removed.
    public static func kept(_ dates: [Date], now: Date, calendar: Calendar = .current) -> Set<Date> {
        let newestFirst = dates.sorted(by: >)
        var keep = Set(newestFirst.prefix(recentCount))
        let oldestDay = calendar.date(byAdding: .day, value: -dailyDays, to: calendar.startOfDay(for: now)) ?? now
        var daysSeen = Set<Date>()
        for date in newestFirst where date >= oldestDay {
            let day = calendar.startOfDay(for: date)
            if daysSeen.insert(day).inserted { keep.insert(date) }
        }
        return keep
    }

    /// The file name of a backup made at `date`: sortable, and readable back with `date(fromFileName:)`.
    public static func fileName(for date: Date) -> String {
        "\(formatter.string(from: date)).\(ProjectFile.fileExtension)"
    }

    /// When the backup in a file named by `fileName(for:)` was made, or nil for other files.
    public static func date(fromFileName name: String) -> Date? {
        guard name.hasSuffix(".\(ProjectFile.fileExtension)") else { return nil }
        return formatter.date(from: String(name.dropLast(ProjectFile.fileExtension.count + 1)))
    }

    // ISO 8601 in UTC with milliseconds, with "-" for ":" (not allowed in Finder names).
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        return formatter
    }()
}
