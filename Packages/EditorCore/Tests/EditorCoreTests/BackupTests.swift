import Foundation
import Testing

@testable import EditorCore

struct BackupTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15, mid-morning in Rome
    private func ago(minutes: Double = 0, days: Double = 0) -> Date { now.addingTimeInterval(-(minutes * 60 + days * 86_400)) }

    @Test func aBackupIsDueAtFirstAndThenEveryQuarterHour() {
        #expect(BackupPolicy.isDue(newest: nil, now: now))
        #expect(!BackupPolicy.isDue(newest: ago(minutes: 14), now: now))
        #expect(BackupPolicy.isDue(newest: ago(minutes: 15), now: now))
    }

    @Test func theNewestTenAreAllKept() {
        let dates = (0..<12).map { ago(minutes: Double($0) * 20) }
        let kept = BackupPolicy.kept(dates, now: now, calendar: calendar)
        // The newest ten, plus the newest of yesterday (if the last two fall on another day, it is kept too).
        #expect(Set(dates.prefix(10)).isSubset(of: kept))
        #expect(kept.count <= 12)
    }

    @Test func olderBackupsKeepOnePerDayForAWeek() {
        // Twelve today, then three a day for ten days before.
        let today = (0..<12).map { ago(minutes: Double($0)) }
        let earlier = (1...10).flatMap { day in [0.0, 60, 120].map { ago(minutes: $0, days: Double(day)) } }
        let kept = BackupPolicy.kept(today + earlier, now: now, calendar: calendar)
        #expect(Set(today.prefix(10)).isSubset(of: kept))
        #expect(!kept.contains(today[11]))
        for day in 1...10 {
            let newestOfDay = ago(days: Double(day))
            #expect(kept.contains(newestOfDay) == (day <= 7), "day \(day)")
            #expect(!kept.contains(ago(minutes: 60, days: Double(day))))
        }
        #expect(kept.count == 10 + 7)
    }

    @Test func fileNamesSortByDateAndReadBack() {
        let date = Date(timeIntervalSince1970: 1_800_000_000.25)
        let name = BackupPolicy.fileName(for: date)
        #expect(name == "2027-01-15T08-00-00.250Z.shortsproject")
        #expect(BackupPolicy.date(fromFileName: name) == date)
        #expect(BackupPolicy.fileName(for: date) < BackupPolicy.fileName(for: date.addingTimeInterval(1)))
        #expect(BackupPolicy.date(fromFileName: "notes.txt") == nil)
        #expect(BackupPolicy.date(fromFileName: "x.shortsproject") == nil)
    }
}
