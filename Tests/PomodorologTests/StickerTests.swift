import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct StickerTests {
    /// The stickers a log earns, by id.
    private func earned(_ records: [SessionRecord]) -> [String: EarnedSticker] {
        let rewards = RewardsSnapshot(records: records, today: "2026-11-15")
        return Dictionary(rewards.stickers.map { ($0.sticker.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// `perDay` tomatoes, each with a break after it, on `count` days in a row
    /// from `start`, starting at `hour:minute`.
    private func days(
        from start: String, count: Int, at hour: Int = 9, _ minute: Int = 0, perDay: Int = 1
    ) -> [SessionRecord] {
        var log = SessionLogBuilder(day: start, at: hour, minute)
        for offset in 0..<count {
            log.move(to: LocalDay.offset(start, by: offset) ?? start, at: hour, minute)
            for _ in 0..<perDay { log.focus(); log.rest() }
        }
        return log.records
    }

    private func tomatoes(_ records: [SessionRecord]) -> [SessionRecord] {
        records.filter(\.countsAsCompletedFocus)
    }

    @Test func theCatalogHasTwentyFourStickersWithUniqueIDs() {
        #expect(Stickers.all.count == 24)
        #expect(Set(Stickers.all.map(\.id)).count == 24)
    }

    @Test func nothingLoggedEarnsNothing() {
        #expect(earned([]).isEmpty)
    }

    @Test func firstTomatoCenturyFirstJarAndPantry() {
        let records = days(from: "2026-10-01", count: 25, perDay: 4)
        let stickers = earned(records)
        let all = tomatoes(records)
        #expect(stickers["first-tomato"]?.recordID == all[0].id)
        #expect(stickers["first-jar"]?.recordID == all[3].id)
        #expect(stickers["century"]?.recordID == all[99].id)
        #expect(stickers["pantry"]?.recordID == all[99].id)
        #expect(stickers["century"]?.date == all[99].endedAt)
    }

    @Test func earlyBirdIsBeforeEightAndNightOwlAfterEleven() {
        var dawn = SessionLogBuilder(day: "2026-11-10", at: 7, 30)
        dawn.focus(then: .stop)
        var eight = SessionLogBuilder(day: "2026-11-10", at: 7, 35)
        eight.focus(then: .stop)
        var night = SessionLogBuilder(day: "2026-11-10", at: 22, 50)
        night.focus(then: .stop)
        var smallHours = SessionLogBuilder(day: "2026-11-10", at: 4, 0)
        smallHours.focus(then: .stop)

        #expect(earned(dawn.records)["early-bird"] != nil)
        #expect(earned(eight.records)["early-bird"] == nil)
        #expect(earned(night.records)["night-owl"] != nil)
        #expect(earned(smallHours.records)["night-owl"] != nil)
        #expect(earned(smallHours.records)["early-bird"] == nil)
    }

    @Test func timesAreTheSessionsOwnLocalTime() {
        var sydney = SessionLogBuilder(day: "2026-11-10", at: 7, 30, utcOffsetSeconds: 11 * 3600)
        sydney.focus(then: .stop)
        #expect(earned(sydney.records)["early-bird"] != nil)
    }

    @Test func hatTrickIsThreeBeforeNoon() {
        var morning = SessionLogBuilder(day: "2026-11-10", at: 9)
        morning.focus(); morning.rest(); morning.focus(); morning.rest(); morning.focus(then: .stop)
        var lunchtime = SessionLogBuilder(day: "2026-11-10", at: 11)
        lunchtime.focus(); lunchtime.rest(); lunchtime.focus(); lunchtime.rest(); lunchtime.focus(then: .stop)

        #expect(earned(morning.records)["hat-trick"]?.recordID == morning.records[4].id)
        #expect(earned(lunchtime.records)["hat-trick"] == nil)
    }

    @Test func dozenAndMarathonInOneDay() {
        var log = SessionLogBuilder(day: "2026-11-10", at: 6)
        for _ in 0..<12 { log.focus(); log.rest() }
        let all = tomatoes(log.records)
        let stickers = earned(log.records)
        #expect(stickers["dozen"]?.recordID == all[11].id)
        // 4 hours is 240 minutes: the tenth 25-minute focus gets there.
        #expect(stickers["marathon"]?.recordID == all[9].id)
    }

    @Test func weekendWarriorIsASaturdayAndTheSundayAfter() {
        let weekend = days(from: "2026-11-14", count: 2)
        let sundayMonday = days(from: "2026-11-15", count: 2)
        #expect(earned(weekend)["weekend-warrior"]?.recordID == tomatoes(weekend)[1].id)
        #expect(earned(sundayMonday)["weekend-warrior"] == nil)
    }

    @Test func perfectWeekIsMondayToSunday() {
        let week = days(from: "2026-11-09", count: 7)
        var gap = SessionLogBuilder(day: "2026-11-09", at: 9)
        for offset in [0, 1, 3, 4, 5, 6] {
            gap.move(to: LocalDay.offset("2026-11-09", by: offset) ?? "", at: 9)
            gap.focus(then: .stop)
        }
        #expect(earned(week)["perfect-week"]?.recordID == tomatoes(week)[6].id)
        #expect(earned(gap.records)["perfect-week"] == nil)
    }

    @Test func clockworkIsTheSameHourThreeDaysRunning() {
        let steady = days(from: "2026-11-10", count: 3, at: 9, 10)
        var drifting = SessionLogBuilder(day: "2026-11-10", at: 9, 10)
        drifting.focus(then: .stop)
        drifting.move(to: "2026-11-11", at: 10, 10)
        drifting.focus(then: .stop)
        drifting.move(to: "2026-11-12", at: 9, 10)
        drifting.focus(then: .stop)

        #expect(earned(steady)["clockwork"]?.recordID == tomatoes(steady)[2].id)
        #expect(earned(drifting.records)["clockwork"] == nil)
    }

    @Test func comebackIsAfterSevenEmptyDays() {
        var back = SessionLogBuilder(day: "2026-11-01", at: 9)
        back.focus(then: .stop)
        back.move(to: "2026-11-09", at: 9)
        back.focus(then: .stop)
        var soon = SessionLogBuilder(day: "2026-11-01", at: 9)
        soon.focus(then: .stop)
        soon.move(to: "2026-11-08", at: 9)
        soon.focus(then: .stop)

        #expect(earned(back.records)["comeback"]?.recordID == back.records[1].id)
        #expect(earned(soon.records)["comeback"] == nil)
    }

    @Test func streaksAreDaysInARow() {
        let week = days(from: "2026-10-01", count: 7)
        let month = days(from: "2026-10-01", count: 30)
        #expect(earned(days(from: "2026-10-01", count: 6))["week-streak"] == nil)
        #expect(earned(week)["week-streak"]?.recordID == tomatoes(week)[6].id)
        #expect(earned(week)["month-streak"] == nil)
        #expect(earned(month)["month-streak"]?.recordID == tomatoes(month)[29].id)
    }

    @Test func unbrokenIsAQuarterHourOrMoreWithNoPause() {
        var clean = SessionLogBuilder(day: "2026-11-10", at: 9)
        clean.focus(then: .stop)
        var paused = SessionLogBuilder(day: "2026-11-10", at: 9)
        paused.focus(pausedMinutes: 2, then: .stop)
        var short = SessionLogBuilder(day: "2026-11-10", at: 9)
        short.focus(20, then: .stop)

        #expect(earned(clean.records)["unbroken"] != nil)
        #expect(earned(paused.records)["unbroken"] == nil)
        #expect(earned(short.records)["unbroken"] == nil)
    }

    @Test func extraMileIsTenMinutesPastZero() {
        var ten = SessionLogBuilder(day: "2026-11-10", at: 9)
        ten.focus(overtime: 10, then: .stop)
        var nine = SessionLogBuilder(day: "2026-11-10", at: 9)
        nine.focus(overtime: 9, then: .stop)
        #expect(earned(ten.records)["extra-mile"] != nil)
        #expect(earned(nine.records)["extra-mile"] == nil)
    }

    @Test func longHaulIsPlannedForFiftyMinutes() {
        var fifty = SessionLogBuilder(day: "2026-11-10", at: 9)
        fifty.focus(50, then: .stop)
        var fortyFive = SessionLogBuilder(day: "2026-11-10", at: 9)
        fortyFive.focus(45, then: .stop)
        #expect(earned(fifty.records)["long-haul"] != nil)
        #expect(earned(fortyFive.records)["long-haul"] == nil)
    }

    @Test func namedItNeedsARealTitle() {
        var titled = SessionLogBuilder(day: "2026-11-10", at: 9)
        titled.focus(title: "Essay", then: .stop)
        var blank = SessionLogBuilder(day: "2026-11-10", at: 9)
        blank.focus(title: "   ", then: .stop)
        #expect(earned(titled.records)["named-it"] != nil)
        #expect(earned(blank.records)["named-it"] == nil)
    }

    @Test func freshLegsIsTenFocusSessionsFromABreak() {
        var log = SessionLogBuilder(day: "2026-11-10", at: 8)
        for _ in 0..<11 { log.focus(); log.rest() }
        let all = tomatoes(log.records)
        #expect(earned(log.records)["fresh-legs"]?.recordID == all[10].id)
        #expect(earned(Array(log.records.dropLast(2)))["fresh-legs"] == nil)
    }

    @Test func wellRestedIsADayWhereEveryFocusAfterTheFirstStartedFromABreak() {
        var rested = SessionLogBuilder(day: "2026-11-10", at: 9)
        for _ in 0..<4 { rested.focus(); rested.rest() }
        var skipped = SessionLogBuilder(day: "2026-11-10", at: 9)
        skipped.focus(); skipped.rest(); skipped.focus(then: .stop)
        skipped.wait(minutes: 0.5)
        for _ in 0..<3 { skipped.focus(); skipped.rest() }

        #expect(earned(rested.records)["well-rested"]?.recordID == tomatoes(rested.records)[3].id)
        #expect(earned(skipped.records)["well-rested"] == nil)
    }

    @Test func baseCampThinAirAndRedPlanetComeFromTheClimb() {
        // One-hour stopwatch runs of 600 m each, which leave no tomatoes.
        var log = SessionLogBuilder(day: "2026-11-01", at: 0)
        for _ in 0..<92 {
            log.focus(60, stopwatch: true, then: .stop)
            log.wait(minutes: 10)
        }
        let stickers = earned(log.records)
        // Ben Nevis is 1,345 m: the third run. 8,000 m up Everest is 30,785 m
        // in all: the 52nd. Olympus Mons tops the range at 53,534 m: the 90th.
        #expect(stickers["base-camp"]?.recordID == log.records[2].id)
        #expect(stickers["thin-air"]?.recordID == log.records[51].id)
        #expect(stickers["red-planet"]?.recordID == log.records[89].id)
        #expect(stickers["first-tomato"] == nil)
    }
}
