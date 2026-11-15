import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct ClimbTests {
    /// A log starting at 09:00 on a Tuesday, and its climb.
    private func climb(_ build: (inout SessionLogBuilder) -> Void) -> (Climb, [SessionRecord]) {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        build(&log)
        return (Climb(records: log.records), log.records)
    }

    @Test func focusClimbsTenMetresAMinute() {
        let (climb, _) = climb { $0.focus(then: .stop) }
        #expect(climb.total == 250)
        #expect(climb.steps.first?.startedFromBreak == false)
    }

    @Test func aFocusStartedFromAFinishedBreakClimbsAFifthFurther() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(); log.focus(then: .stop)
        }
        #expect(climb.steps.map(\.metres) == [250, 300])
        #expect(climb.steps.map(\.startedFromBreak) == [false, true])
        #expect(climb.total == 550)
    }

    @Test func theBonusNeverGrowsOrStacks() {
        let (climb, _) = climb { log in
            for _ in 0..<5 { log.focus(); log.rest() }
            log.focus(then: .stop)
        }
        #expect(climb.steps.dropFirst().allSatisfy { $0.bonusMetres == 50 })
    }

    @Test func aBreakEndedEarlyGivesNoBonus() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(ran: 2); log.focus(then: .stop)
        }
        #expect(climb.steps.last?.startedFromBreak == false)
    }

    @Test func aBreakMoreThanFiveMinutesPastZeroGivesNoBonus() {
        let (long, _) = climb { log in
            log.focus(); log.rest(overtime: 6); log.focus(then: .stop)
        }
        let (short, _) = climb { log in
            log.focus(); log.rest(overtime: 5); log.focus(then: .stop)
        }
        #expect(long.steps.last?.startedFromBreak == false)
        #expect(short.steps.last?.startedFromBreak == true)
    }

    @Test func theFocusStartsWithinTwoMinutesOfTheBreak() {
        let (late, _) = climb { log in
            log.focus(); log.rest(then: .stop); log.wait(minutes: 3); log.focus(then: .stop)
        }
        let (soon, _) = climb { log in
            log.focus(); log.rest(then: .stop); log.wait(minutes: 2); log.focus(then: .stop)
        }
        #expect(late.steps.last?.startedFromBreak == false)
        #expect(soon.steps.last?.startedFromBreak == true)
    }

    @Test func theBreakFollowsAFocus() {
        let (firstThing, _) = climb { log in
            log.rest(); log.focus(then: .stop)
        }
        let (afterAWhile, _) = climb { log in
            log.focus(then: .stop); log.wait(minutes: 10); log.rest(); log.focus(then: .stop)
        }
        #expect(firstThing.steps.last?.startedFromBreak == false)
        #expect(afterAWhile.steps.last?.startedFromBreak == false)
    }

    @Test func aSkippedBreakGivesNoBonus() {
        let (climb, _) = climb { log in
            log.focus(then: .stop); log.wait(minutes: 0.5); log.focus(then: .stop)
        }
        #expect(climb.steps.last?.startedFromBreak == false)
    }

    @Test func aClockTimerNeitherClimbsNorGetsInTheWay() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(); log.clockTimer(1); log.focus(then: .stop)
        }
        #expect(climb.steps.count == 2)
        #expect(climb.steps.last?.startedFromBreak == true)
        #expect(climb.total == 550)
    }

    @Test func overtimeDoesNotClimb() {
        let (climb, _) = climb { $0.focus(overtime: 15, then: .stop) }
        #expect(climb.total == 250)
    }

    @Test func aFocusEndedEarlyClimbsWhatItRanButLeavesNoTomato() {
        let (climb, records) = climb { $0.focus(ran: 10, then: .stop) }
        #expect(climb.total == 100)
        #expect(Pantry(records: records).totalTomatoes == 0)
    }

    @Test func aStopwatchRunCountsUpToAnHour() {
        let (climb, records) = climb { $0.focus(90, stopwatch: true, then: .stop) }
        #expect(climb.total == 600)
        #expect(Pantry(records: records).totalTomatoes == 0)
    }

    @Test func aStopwatchRunStartedFromABreakGetsTheBonus() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(); log.focus(30, stopwatch: true, then: .stop)
        }
        #expect(climb.steps.last?.metres == 360)
    }

    @Test func aSummitIsDatedByTheSessionThatCrossedTheTop() throws {
        // 250 m, then five of 300 m: the fifth focus crosses Ben Nevis at 1,450 m.
        let (climb, records) = climb { log in
            for _ in 0..<5 { log.focus(); log.rest() }
            log.focus(then: .stop)
        }
        let summit = try #require(climb.summits.first)
        #expect(climb.summits.count == 1)
        #expect(summit.peak.name == "Ben Nevis")
        #expect(summit.recordID == records[8].id)
        #expect(summit.sessions == 5)
        #expect(summit.days == 1)
        #expect(climb.total == 1750)
        #expect(climb.position.peak.name == "Mount Fuji")
        #expect(climb.position.metres == 405)
    }

    @Test func theRangeStartsAgainAfterOlympusMons() {
        #expect(Peaks.rangeHeight == 53534)
        #expect(Peaks.position(at: 1344).peak.name == "Ben Nevis")
        #expect(Peaks.position(at: 1345).peak.name == "Mount Fuji")
        let second = Peaks.position(at: Peaks.rangeHeight + 100)
        #expect(second.ascent == 2)
        #expect(second.peak.name == "Ben Nevis")
        #expect(second.metres == 100)
    }

    @Test func aSecondAscentReachesItsOwnTops() {
        // 92 one-hour stopwatch runs of 600 m: 55,200 m, past Ben Nevis again.
        var log = SessionLogBuilder(day: "2026-11-01", at: 0)
        for _ in 0..<92 {
            log.focus(60, stopwatch: true, then: .stop)
            log.wait(minutes: 10)
        }
        let climb = Climb(records: log.records)
        #expect(climb.total == 55200)
        #expect(climb.summits.count == 8)
        #expect(climb.summits.last?.ascent == 2)
        #expect(climb.summits.last?.peak.name == "Ben Nevis")
    }

    @Test func aDaysShareSplitsFocusFromTheBreakBonus() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(); log.focus(); log.rest(then: .stop)
        }
        #expect(climb.day("2026-11-10") == DayClimb(focusMetres: 500, bonusMetres: 50, sessions: 2, startedFromBreak: 1))
        #expect(climb.day("2026-11-11") == DayClimb())
    }

    @Test func aRunningFocusClimbsAsItGoes() throws {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        log.focus(); log.rest()
        let climb = Climb(records: log.records)
        let start = log.clock
        let active = ActiveSession(
            id: UUID(), kind: .focus, sectionID: "focus", sectionName: "Focus", sectionColorHex: "#FF9500",
            plannedSeconds: 1500, startedAt: start, timeZoneID: "GMT", utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: start)], cycleIndex: 2, title: nil, lastSeenAt: start
        )
        let tenMinutesIn = try #require(climb.provisionalStep(for: active, after: log.records, at: start.addingTimeInterval(600)))
        #expect(tenMinutesIn.startedFromBreak)
        #expect(tenMinutesIn.metres == 120)
        #expect(tenMinutesIn.after == 370)
        let inOvertime = try #require(climb.provisionalStep(for: active, after: log.records, at: start.addingTimeInterval(1800)))
        #expect(inOvertime.metres == 300)
    }
}
