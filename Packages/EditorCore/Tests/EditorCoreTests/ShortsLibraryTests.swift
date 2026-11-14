import Foundation
import Testing

@testable import EditorCore

struct ShortsLibraryTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        c.locale = Locale(identifier: "en_US")
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func newShortsGetNumberedNames() {
        #expect(ShortsLibrary.newName(existing: []) == "My Short")
        #expect(ShortsLibrary.newName(existing: ["My Short"]) == "My Short 2")
        #expect(ShortsLibrary.newName(existing: ["my short", "My Short 2", "My Short 3"]) == "My Short 4")
        #expect(ShortsLibrary.newName(base: "  ", existing: []) == "My Short")
    }

    @Test func copiesSayCopy() {
        #expect(ShortsLibrary.copyName(of: "Hook test", existing: ["Hook test"]) == "Hook test copy")
        #expect(ShortsLibrary.copyName(of: "Hook test", existing: ["Hook test", "Hook test copy"]) == "Hook test copy 2")
    }

    @Test func typedNamesAreTidied() {
        #expect(ShortsLibrary.cleanedName("  Day 1  ") == "Day 1")
        #expect(ShortsLibrary.cleanedName("two\nlines") == "two lines")
        #expect(ShortsLibrary.cleanedName("   ") == nil)
        #expect(ShortsLibrary.cleanedName(String(repeating: "a", count: 300))?.count == 100)
    }

    @Test func searchMatchesWordsInAnyOrder() {
        #expect(ShortsLibrary.matches("Pasta recipe part 2", search: "part pasta"))
        #expect(ShortsLibrary.matches("Pasta recipe", search: ""))
        #expect(!ShortsLibrary.matches("Pasta recipe", search: "pizza"))
    }

    @Test func shortsAreGroupedLikeIMovie() {
        let now = date(2026, 11, 9, 16)
        #expect(ShortsLibrary.section(for: date(2026, 11, 9, 1), now: now, calendar: calendar) == .today)
        #expect(ShortsLibrary.section(for: date(2026, 11, 8, 23), now: now, calendar: calendar) == .yesterday)
        #expect(ShortsLibrary.section(for: date(2026, 11, 2), now: now, calendar: calendar) == .previousWeek)
        let october = ShortsLibrary.section(for: date(2026, 10, 20), now: now, calendar: calendar)
        #expect(october == .month(date(2026, 10, 1, 0)))
        #expect(october.title(now: now, calendar: calendar) == "October")
        #expect(ShortsLibrary.section(for: date(2025, 3, 3), now: now, calendar: calendar).title(now: now, calendar: calendar) == "March 2025")
    }

    @Test func groupsComeNewestFirst() {
        let now = date(2026, 11, 9, 16)
        let items = [date(2026, 9, 1), date(2026, 11, 9, 10), date(2026, 10, 5), date(2026, 11, 9, 15), date(2026, 11, 8)]
        let groups = ShortsLibrary.grouped(items, date: { $0 }, now: now, calendar: calendar)
        #expect(groups.map(\.0.self) == [.today, .yesterday, .month(date(2026, 10, 1, 0)), .month(date(2026, 9, 1, 0))])
        #expect(groups[0].1 == [date(2026, 11, 9, 15), date(2026, 11, 9, 10)])
    }

    @Test func theNameAndDateAreSavedWithTheShort() throws {
        let made = Date(timeIntervalSince1970: 1_700_000_000)
        let file = ProjectFile(project: Project(), name: "Hook test", created: made)
        let read = try ProjectFile.decode(file.encoded())
        #expect(read.name == "Hook test")
        #expect(read.created == made)
        // Files from before the home window have neither.
        let old = try ProjectFile.decode(ProjectFile(project: Project()).encoded())
        #expect(old.name == nil)
    }
}
