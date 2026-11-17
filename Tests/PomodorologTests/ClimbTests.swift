import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct ClimbTests {
    /// When the logs below start: 09:00 on a Tuesday.
    private let start = SessionLogBuilder(day: "2026-11-10", at: 9).clock

    /// A log starting at 09:00 on a Tuesday, and its climb: Ben Nevis picked
    /// from the start, unless `picks` says otherwise.
    private func climb(picks: [ClimbPick]? = nil, _ build: (inout SessionLogBuilder) -> Void) -> (Climb, [SessionRecord]) {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        build(&log)
        return (Climb(records: log.records, picks: picks ?? [ClimbPick(Peaks.all[0], at: start)]), log.records)
    }

    private func pick(_ index: Int, minutes: Double) -> ClimbPick {
        ClimbPick(Peaks.all[index], at: start.addingTimeInterval(minutes * 60))
    }

    // MARK: What a focus earns

    @Test func focusClimbsTenMetresAMinute() {
        let (climb, _) = climb { $0.focus(then: .stop) }
        #expect(climb.steps.first?.climbed == 250)
        #expect(climb.current?.metres == 250)
        #expect(climb.steps.first?.startedFromBreak == false)
    }

    @Test func aFocusStartedFromAFinishedBreakClimbsAFifthFurther() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(); log.focus(then: .stop)
        }
        #expect(climb.steps.map(\.metres) == [250, 300])
        #expect(climb.steps.map(\.startedFromBreak) == [false, true])
        #expect(climb.current?.metres == 550)
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
        #expect(climb.current?.metres == 550)
    }

    @Test func overtimeDoesNotClimb() {
        let (climb, _) = climb { $0.focus(overtime: 15, then: .stop) }
        #expect(climb.current?.metres == 250)
    }

    @Test func aFocusEndedEarlyClimbsWhatItRanButLeavesNoTomato() {
        let (climb, records) = climb { $0.focus(ran: 10, then: .stop) }
        #expect(climb.current?.metres == 100)
        #expect(Pantry(records: records).totalTomatoes == 0)
    }

    @Test func aStopwatchRunCountsUpToAnHour() {
        let (climb, records) = climb { $0.focus(90, stopwatch: true, then: .stop) }
        #expect(climb.current?.metres == 600)
        #expect(Pantry(records: records).totalTomatoes == 0)
    }

    @Test func aStopwatchRunStartedFromABreakGetsTheBonus() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(); log.focus(30, stopwatch: true, then: .stop)
        }
        #expect(climb.steps.last?.metres == 360)
    }

    // MARK: Picking a climb

    @Test func nothingPickedClimbsNothing() {
        let (climb, _) = climb(picks: []) { log in
            log.focus(); log.rest(); log.focus(then: .stop)
        }
        #expect(climb.expeditions.isEmpty)
        #expect(climb.current == nil)
        // Each focus still earns, and still counts as a session of the day.
        #expect(climb.steps.map(\.metres) == [250, 300])
        #expect(climb.steps.allSatisfy { $0.expedition == nil && $0.peakIndex == nil && $0.climbed == 0 })
        #expect(climb.day("2026-11-10") == DayClimb(focusMetres: 0, bonusMetres: 0, sessions: 2, startedFromBreak: 1))
    }

    @Test func aFocusCountsTowardTheClimbPickedWhenItEnds() {
        // The first focus runs 09:00 to 09:25, the second 09:30 to 09:55.
        let (during, _) = climb(picks: [pick(1, minutes: 40)]) { log in
            log.focus(); log.rest(); log.focus(then: .stop)
        }
        #expect(during.steps.map(\.climbed) == [0, 300])
        #expect(during.current?.peak.name == "Mount Fuji")
        #expect(during.current?.metres == 300)

        let (after, _) = climb(picks: [pick(1, minutes: 60)]) { log in
            log.focus(); log.rest(); log.focus(then: .stop)
        }
        #expect(after.steps.map(\.climbed) == [0, 0])
        #expect(after.current?.peak.name == "Mount Fuji")
        #expect(after.current?.metres == 0)
    }

    @Test func aClimbStopsAtTheTopAndDropsTheRest() throws {
        // 250 m, then five of 300 m: the fifth reaches Ben Nevis's top at
        // 1,345 m, 105 m short of what it earned, and the sixth climbs
        // nothing until another climb is picked.
        let (climb, records) = climb { log in
            for _ in 0..<5 { log.focus(); log.rest() }
            log.focus(then: .stop)
        }
        let summit = try #require(climb.summits.first)
        #expect(climb.summits.count == 1)
        #expect(summit.peak.name == "Ben Nevis")
        #expect(summit.number == 1)
        #expect(summit.recordID == records[8].id)
        #expect(summit.date == records[8].endedAt)
        #expect(summit.sessions == 5)
        #expect(summit.days == 1)
        #expect(climb.steps[4].before == 1150)
        #expect(climb.steps[4].after == 1345)
        #expect(climb.steps[5].climbed == 0)
        #expect(climb.steps[5].expedition == nil)
        #expect(climb.current == nil)
        #expect(climb.latest?.isSummited == true)
        #expect(climb.latest?.metres == 1345)
    }

    @Test func theBonusLeadsWhenTheTopCutsASessionShort() {
        // The fifth focus earned 250 m and a 50 m bonus, and climbed 195 m:
        // the bonus, then 145 m of focus.
        let (climb, _) = climb { log in
            for _ in 0..<5 { log.focus(); log.rest() }
            log.focus(then: .stop)
        }
        #expect(climb.steps[4].climbedBonus == 50)
        #expect(climb.steps[4].climbedFocus == 145)
        #expect(climb.day("2026-11-10") == DayClimb(focusMetres: 1145, bonusMetres: 200, sessions: 6, startedFromBreak: 5))
    }

    @Test func switchingPeaksLeavesTheOldClimbBehind() {
        // Four focus sessions of 25 minutes with breaks between, from 09:00 to
        // 10:55; Mount Fuji picked at 10:00, as the third begins.
        let (climb, _) = climb(picks: [pick(0, minutes: 0), pick(1, minutes: 60)]) { log in
            log.focus(); log.rest(); log.focus(); log.rest()
            log.focus(); log.rest(); log.focus(then: .stop)
        }
        #expect(climb.expeditions.map(\.peak.name) == ["Ben Nevis", "Mount Fuji"])
        #expect(climb.expeditions.map(\.metres) == [550, 600])
        #expect(climb.expeditions[0].isSummited == false)
        #expect(climb.current?.peak.name == "Mount Fuji")
        #expect(climb.summits.isEmpty)
    }

    @Test func pickingThePeakBeingClimbedChangesNothing() {
        let (climb, _) = climb(picks: [pick(0, minutes: 0), pick(0, minutes: 40)]) { log in
            log.focus(); log.rest(); log.focus(then: .stop)
        }
        #expect(climb.expeditions.count == 1)
        #expect(climb.current?.metres == 550)
    }

    @Test func aPeakClimbedAgainNumbersItsSummits() {
        // One-hour stopwatch runs of 600 m: Ben Nevis takes three.
        var log = SessionLogBuilder(day: "2026-11-01", at: 0)
        let start = log.clock
        for _ in 0..<6 {
            log.focus(60, stopwatch: true, then: .stop)
            log.wait(minutes: 10)
        }
        let again = log.records[2].endedAt.addingTimeInterval(60)
        let climb = Climb(records: log.records, picks: [ClimbPick(Peaks.all[0], at: start), ClimbPick(Peaks.all[0], at: again)])
        #expect(climb.expeditions.count == 2)
        #expect(climb.summits.map(\.number) == [1, 2])
        #expect(climb.summits.map(\.recordID) == [log.records[2].id, log.records[5].id])
        #expect(climb.summits.allSatisfy { $0.sessions == 3 })
    }

    @Test func picksOfPeaksThisVersionDoesNotKnowAreLeftOut() {
        let (climb, _) = climb(picks: [ClimbPick(peak: "k2", at: start)]) { $0.focus(then: .stop) }
        #expect(climb.expeditions.isEmpty)
        #expect(climb.steps.first?.climbed == 0)
    }

    @Test func aDaysShareSplitsFocusFromTheBreakBonus() {
        let (climb, _) = climb { log in
            log.focus(); log.rest(); log.focus(); log.rest(then: .stop)
        }
        #expect(climb.day("2026-11-10") == DayClimb(focusMetres: 500, bonusMetres: 50, sessions: 2, startedFromBreak: 1))
        #expect(climb.day("2026-11-11") == DayClimb())
    }

    // MARK: A focus still running

    private func runningFocus(from start: Date) -> ActiveSession {
        ActiveSession(
            id: UUID(), kind: .focus, sectionID: "focus", sectionName: "Focus", sectionColorHex: "#FF9500",
            plannedSeconds: 1500, startedAt: start, timeZoneID: "GMT", utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: start)], cycleIndex: 2, title: nil, lastSeenAt: start
        )
    }

    @Test func aRunningFocusClimbsAsItGoes() throws {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        log.focus(); log.rest()
        let climb = Climb(records: log.records, picks: [ClimbPick(Peaks.all[0], at: start)])
        let active = runningFocus(from: log.clock)
        let tenMinutesIn = try #require(climb.provisionalStep(for: active, after: log.records, at: log.clock.addingTimeInterval(600)))
        #expect(tenMinutesIn.startedFromBreak)
        #expect(tenMinutesIn.metres == 120)
        #expect(tenMinutesIn.after == 370)
        #expect(tenMinutesIn.expedition == 0)
        let inOvertime = try #require(climb.provisionalStep(for: active, after: log.records, at: log.clock.addingTimeInterval(1800)))
        #expect(inOvertime.metres == 300)
    }

    @Test func aRunningFocusWithNothingPickedClimbsNothing() throws {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        log.focus(); log.rest()
        let climb = Climb(records: log.records, picks: [])
        let step = try #require(climb.provisionalStep(for: runningFocus(from: log.clock), after: log.records, at: log.clock.addingTimeInterval(600)))
        #expect(step.metres == 120)
        #expect(step.climbed == 0)
        #expect(step.expedition == nil)
    }

    @Test func aRunningFocusStopsAtTheTop() throws {
        // 1,150 m up Ben Nevis; a 25-minute focus from a break earns 300.
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        for _ in 0..<4 { log.focus(); log.rest() }
        let climb = Climb(records: log.records, picks: [ClimbPick(Peaks.all[0], at: start)])
        let step = try #require(climb.provisionalStep(for: runningFocus(from: log.clock), after: log.records, at: log.clock.addingTimeInterval(1500)))
        #expect(step.before == 1150)
        #expect(step.after == 1345)
        #expect(step.climbed == 195)
    }
}
