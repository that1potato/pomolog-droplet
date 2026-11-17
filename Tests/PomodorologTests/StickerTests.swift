import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct StickerTests {
    /// The stickers a log earns with these picks, by id.
    private func earned(_ records: [SessionRecord], picks: [ClimbPick] = []) -> [String: EarnedSticker] {
        let rewards = RewardsSnapshot(records: records, picks: picks, today: "2026-11-15")
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

    @Test func theCatalogHasThirtyStickersWithUniqueIDs() {
        #expect(Stickers.all.count == 30)
        #expect(Set(Stickers.all.map(\.id)).count == 30)
    }

    @Test func everyPeakHasASummitStickerOfItsOwn() {
        let summitStickers = Peaks.all.indices.compactMap { Stickers.summit(of: $0) }
        #expect(summitStickers.count == Peaks.all.count)
        #expect(Set(summitStickers.map(\.id)).count == Peaks.all.count)
        #expect(Stickers.summit(of: 6) == Stickers.redPlanet)
        #expect(Stickers.redPlanet.name == "Olympus Mons")
        #expect(Peaks.all.indices.allSatisfy { Stickers.summit(of: $0)?.peak == $0 })
        #expect(Stickers.all.filter { $0.peak != nil }.count == Peaks.all.count)
    }

    @Test func everySummitSymbolStandsOnTheGroundInsideItsDisc() {
        #expect(SummitGlyphShapes.all.count == Peaks.all.count)
        for shapes in SummitGlyphShapes.all {
            let body = shapes.body.boundingRect
            #expect(body.minX >= 0 && body.maxX <= 100 && body.minY >= 20)
            #expect(abs(body.maxY - 70) < 0.01)
            if let front = shapes.front {
                #expect(abs(front.boundingRect.maxY - 70) < 0.01)
            }
            if let snow = shapes.snow {
                #expect(body.contains(snow.boundingRect))
            }
        }
        // Mars's two moons, and nothing else has any.
        #expect(SummitGlyphShapes.all.map(\.moons.count) == [0, 0, 0, 0, 0, 0, 2])
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

    /// One-hour stopwatch runs of 600 m each, which leave no tomatoes.
    private func hourlyRuns(_ count: Int) -> SessionLogBuilder {
        var log = SessionLogBuilder(day: "2026-11-01", at: 0)
        for _ in 0..<count {
            log.focus(60, stopwatch: true, then: .stop)
            log.wait(minutes: 10)
        }
        return log
    }

    @Test func baseCampThinAirAndRedPlanetComeFromTheClimb() {
        // Everest first: 8,000 m is the 14th run and its top the 15th. Then
        // Olympus Mons, picked a minute later: 21,900 m is 37 runs more.
        let log = hourlyRuns(60)
        let picks = [
            ClimbPick(Peaks.all[5], at: log.records[0].startedAt),
            ClimbPick(Peaks.all[6], at: log.records[14].endedAt.addingTimeInterval(60)),
        ]
        let stickers = earned(log.records, picks: picks)
        #expect(stickers["thin-air"]?.recordID == log.records[13].id)
        #expect(stickers["base-camp"]?.recordID == log.records[14].id)
        #expect(stickers["summit-everest"]?.recordID == log.records[14].id)
        #expect(stickers["red-planet"]?.recordID == log.records[51].id)
        #expect(stickers["summit-ben-nevis"] == nil)
        #expect(stickers["first-tomato"] == nil)
    }

    @Test func aPeaksStickerCountsEveryTimeItsTopIsReached() {
        // Ben Nevis takes three runs; picked again after its top, it takes three more.
        let log = hourlyRuns(6)
        let picks = [
            ClimbPick(Peaks.all[0], at: log.records[0].startedAt),
            ClimbPick(Peaks.all[0], at: log.records[2].endedAt.addingTimeInterval(60)),
        ]
        let sticker = earned(log.records, picks: picks)["summit-ben-nevis"]
        #expect(sticker?.count == 2)
        #expect(sticker?.recordID == log.records[2].id)
        #expect(earned(log.records, picks: picks)["base-camp"]?.count == 1)
    }

    @Test func nothingPickedEarnsNoClimbingStickers() {
        let stickers = earned(hourlyRuns(30).records)
        #expect(stickers.values.allSatisfy { $0.sticker.peak == nil })
        #expect(stickers["base-camp"] == nil)
        #expect(stickers["thin-air"] == nil)
    }
}
