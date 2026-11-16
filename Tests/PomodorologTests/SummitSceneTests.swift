import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct SummitSceneTests {
    let sample = SampleLog.week(endingOn: "2026-11-15")

    private var rewards: RewardsSnapshot {
        RewardsSnapshot(records: sample, today: "2026-11-15")
    }

    @Test func theTrailRunsFromTheFootToTheTopAndOnlyClimbs() {
        #expect(TrailGeometry.point(at: 0) == TrailGeometry.foot)
        #expect(TrailGeometry.point(at: 1) == TrailGeometry.top)
        let heights = stride(from: 0.0, through: 1.0, by: 0.05).map { TrailGeometry.point(at: $0).y }
        #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 > $1 })
        // A stretch across the first hairpin keeps its corners.
        #expect(TrailGeometry.points(from: 0.3, to: 0.5).count == 4)
    }

    @Test func theSampleWeekStandsHalfwayUpMontBlanc() {
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        #expect(scene.peak.name == "Mont Blanc")
        #expect(scene.climbed == 2529)
        #expect(abs(scene.fraction - 2529.0 / 4808.0) < 1e-9)
    }

    @Test func eachTomatoOnThisPeakIsAMarkerAndTheFourthOfADayIsAJar() {
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        // Friday's second, Saturday's two and Sunday's six: Friday's first
        // ended mostly on Mount Fuji.
        #expect(scene.markers.count == 9)
        #expect(scene.markers.filter(\.isJar).count == 1)
        #expect(scene.markers.filter(\.isToday).count == 6)
        let places = scene.markers.map(\.at)
        #expect(places == places.sorted())
    }

    @Test func theBonusLeadsItsStretchInItsOwnInk() {
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        #expect(scene.stretches.count == 15)
        #expect(scene.stretches.filter { $0.ink == .todayBonus }.count == 3)
        #expect(scene.stretches.filter { $0.ink == .earlierBonus }.count == 2)
        let todayInks = scene.stretches.filter { $0.ink == .today || $0.ink == .todayBonus }
        #expect(todayInks.first?.from == 879.0 / 4808.0)
    }

    @Test func aRunningFocusMovesTheClimber() throws {
        let end = try #require(sample.last?.endedAt)
        let active = ActiveSession(
            id: UUID(), kind: .focus, sectionID: "focus", sectionName: "Focus", sectionColorHex: "#FF9500",
            plannedSeconds: 1500, startedAt: end, timeZoneID: "GMT", utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: end)], cycleIndex: 7, title: nil, lastSeenAt: end
        )
        let live = rewards.climb.provisionalStep(for: active, after: sample, at: end.addingTimeInterval(600))
        let scene = SummitScene(rewards: rewards, today: "2026-11-15", live: live)
        #expect(scene.climbed == 2649)
        #expect(scene.stretches.count == 17)
        #expect(scene.markers.count == 9)
    }

    @Test func nothingLoggedStandsAtTheFootOfBenNevis() {
        let scene = SummitScene(rewards: RewardsSnapshot(records: [], today: "2026-11-15"), today: "2026-11-15")
        #expect(scene.peak.name == "Ben Nevis")
        #expect(scene.climbed == 0)
        #expect(scene.stretches.isEmpty)
        #expect(scene.markers.isEmpty)
    }

    @Test func theWidgetSaysWhereYouAreAndHowFarToGo() {
        let model = SummitWidgetModel(rewards: rewards, today: "2026-11-15", live: nil, logging: true)
        #expect(model.state == .climbing)
        #expect(model.peakTitle == "Mont Blanc")
        #expect(model.altitudeText == "\(2529.formatted()) of \(4808.formatted()) m")
        #expect(model.percentText == "52%")
        #expect(model.todayTomatoes == 6)
        #expect(model.todayJars == 1)
        #expect(model.climbedText == 2529.formatted())
        #expect(model.ofText == "of \(4808.formatted()) m · 52% up")
        // Six today: one jar and two loose.
        #expect(model.todayGlyphs.jars == 1)
        #expect(model.todayGlyphs.loose == 2)
        // 2,279 m to go at 275 m a session, the pace of the last ten.
        #expect(model.statusText == "Summit in about 8 sessions")
    }

    @Test func quickSessionsDoNotSetThePace() {
        // One 25-minute tomato, then four 1-minute ones: 290 m in all, so
        // 1,055 m to the top of Ben Nevis at 250 m a session.
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        log.focus(then: .stop)
        for _ in 0..<4 {
            log.wait(minutes: 30)
            log.focus(1, then: .stop)
        }
        let rewards = RewardsSnapshot(records: log.records, today: "2026-11-10")
        let model = SummitWidgetModel(rewards: rewards, today: "2026-11-10", live: nil, logging: true)
        #expect(model.statusText == "Summit in about 4 sessions")
    }

    @Test func theWidgetInvitesAFirstFocusAndSaysWhenItCannotLog() {
        let empty = RewardsSnapshot(records: [], today: "2026-11-15")
        #expect(SummitWidgetModel(rewards: empty, today: "2026-11-15", live: nil, logging: true).statusText
            == "Start a focus to begin the climb")
        #expect(SummitWidgetModel(rewards: rewards, today: "2026-11-15", live: nil, logging: false).statusText
            == "Not logging, see Settings")
    }
}
