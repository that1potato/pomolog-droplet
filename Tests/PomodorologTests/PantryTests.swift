import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct PantryTests {
    @Test func everyFourthTomatoOfADayFillsAJar() {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        for _ in 0..<9 { log.focus(); log.rest() }
        let pantry = Pantry(records: log.records)
        let day = pantry.day("2026-11-10")
        #expect(day.tomatoes == 9)
        #expect(day.jars == 2)
        #expect(day.loose == 1)
        #expect(pantry.tomatoes.map(\.isJar) == [false, false, false, true, false, false, false, true, false])
    }

    @Test func jarsDoNotCarryAcrossDays() {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        for _ in 0..<3 { log.focus(); log.rest() }
        log.move(to: "2026-11-11", at: 9)
        log.focus(then: .stop)
        let pantry = Pantry(records: log.records)
        #expect(pantry.totalTomatoes == 4)
        #expect(pantry.totalJars == 0)
    }

    @Test func onlyAFocusThatReachedZeroIsATomato() {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        log.focus(ran: 10, then: .stop)
        log.focus(30, stopwatch: true, then: .stop)
        log.rest(then: .stop)
        log.clockTimer(5)
        log.focus(then: .stop)
        #expect(Pantry(records: log.records).totalTomatoes == 1)
    }

    @Test func jarsAreCountedByWeek() {
        var log = SessionLogBuilder(day: "2026-11-09", at: 9)
        for _ in 0..<4 { log.focus(); log.rest() }
        log.move(to: "2026-11-15", at: 9)
        for _ in 0..<8 { log.focus(); log.rest() }
        log.move(to: "2026-11-16", at: 9)
        for _ in 0..<4 { log.focus(); log.rest() }
        let pantry = Pantry(records: log.records)
        #expect(pantry.jars(inWeekOf: "2026-11-12") == 3)
        #expect(pantry.jars(inWeekOf: "2026-11-16") == 1)
    }

    @Test func daysAddUpAndWeeksRunMondayToSunday() {
        #expect(LocalDay.isoWeekday("2026-11-09") == 1)
        #expect(LocalDay.isoWeekday("2026-11-15") == 7)
        #expect(LocalDay.monday(of: "2026-11-15") == "2026-11-09")
        #expect(LocalDay.week(of: "2026-11-12") == [
            "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15",
        ])
        #expect(LocalDay.offset("2026-12-31", by: 1) == "2027-01-01")
        #expect(LocalDay.offset("2026-03-01", by: -1) == "2026-02-28")
        #expect(LocalDay.distance(from: "2026-11-01", to: "2026-11-09") == 8)
    }
}
