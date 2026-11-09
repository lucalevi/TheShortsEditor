import Foundation

/// Naming and grouping for the home window, where every Short is listed (like iMovie's Projects).
public enum ShortsLibrary {
    public static let defaultName = "My Short"

    /// A name no other Short has: "My Short", then "My Short 2", "My Short 3"…
    public static func newName(base: String = defaultName, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let base = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultName : base
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    /// The name for a copy of a Short: "Hook test copy", "Hook test copy 2"…
    public static func copyName(of name: String, existing: [String]) -> String {
        newName(base: "\(name) copy", existing: existing)
    }

    /// A name typed by the user, tidied: spaces at the ends removed, line breaks made spaces,
    /// and nil when nothing is left (the old name stays).
    public static func cleanedName(_ typed: String) -> String? {
        let single = typed.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = single.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(100))
    }

    /// Whether a Short matches the search field (any word of the search, in any order).
    public static func matches(_ name: String, search: String) -> Bool {
        let words = search.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { name.localizedCaseInsensitiveContains($0) }
    }

    /// The heading a Short last changed at `date` goes under, as in iMovie: Today, Yesterday,
    /// Previous 7 Days, then the month ("October", or "October 2025" in another year).
    public enum Section: Hashable, Sendable, Comparable {
        case today
        case yesterday
        case previousWeek
        /// The first day of the month.
        case month(Date)

        public static func < (a: Section, b: Section) -> Bool {
            switch (a, b) {
            case let (.month(x), .month(y)): x > y   // newer months first
            default: a.order < b.order
            }
        }

        private var order: Int {
            switch self {
            case .today: 0
            case .yesterday: 1
            case .previousWeek: 2
            case .month: 3
            }
        }

        public func title(now: Date = .now, calendar: Calendar = .current) -> String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .previousWeek: return "Previous 7 Days"
            case .month(let start):
                let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: now)
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.locale = calendar.locale ?? .current
                formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMM" : "MMMMyyyy")
                return formatter.string(from: start)
            }
        }
    }

    public static func section(for date: Date, now: Date = .now, calendar: Calendar = .current) -> Section {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if days <= 0 { return .today }
        if days == 1 { return .yesterday }
        if days < 8 { return .previousWeek }
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? day
        return .month(start)
    }

    /// Items grouped under their headings, newest first in each.
    public static func grouped<Item>(_ items: [Item], date: (Item) -> Date, now: Date = .now, calendar: Calendar = .current) -> [(Section, [Item])] {
        let sorted = items.sorted { date($0) > date($1) }
        var groups: [Section: [Item]] = [:]
        for item in sorted { groups[section(for: date(item), now: now, calendar: calendar), default: []].append(item) }
        return groups.keys.sorted().map { ($0, groups[$0]!) }
    }
}
