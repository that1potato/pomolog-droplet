import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct SummitSceneTests {
    let sample = SampleLog.week(endingOn: "2026-11-15")

    private var rewards: RewardsSnapshot {
        RewardsSnapshot(records: sample, picks: SampleLog.picks(for: sample), today: "2026-11-15")
    }

    @Test func everyPeakHasAPictureAndATrailInsideIt() {
        #expect(PeakScenes.all.count == Peaks.all.count)
        for art in PeakScenes.all {
            #expect(!art.planes.isEmpty)
            #expect(art.planes.allSatisfy { $0.points.count >= 3 })
            let inside = CGRect(origin: .zero, size: PeakScenes.size).insetBy(dx: -1, dy: -1)
            #expect(art.trail.points.allSatisfy(inside.contains))
            #expect(art.huts.allSatisfy(inside.contains))
        }
    }

    @Test func everyTrailRunsFromItsFootToItsTopAndOnlyClimbs() {
        for art in PeakScenes.all {
            let trail = art.trail
            #expect(trail.point(at: 0) == trail.foot)
            #expect(trail.point(at: 1) == trail.top)
            #expect(trail.foot.y > trail.top.y)
            let heights = stride(from: 0.0, through: 1.0, by: 0.05).map { trail.point(at: $0).y }
            #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 > $1 })
        }
    }

    @Test func aStretchOfTrailKeepsItsBendsAndItsEnds() {
        // Mount Fuji's switchbacks are between the fifth station and the rim.
        let trail = PeakScenes.all[1].trail
        let stretch = trail.points(from: 0.6, to: 0.9)
        #expect(stretch.first == trail.point(at: 0.6))
        #expect(stretch.last == trail.point(at: 0.9))
        #expect(stretch.count > 10)
        #expect(trail.points(from: 0.5, to: 0.5).count == 2)
    }

    @Test func theSceneDrawsThePeakItStandsOn() {
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        #expect(scene.art.trail == PeakScenes.all[2].trail)
    }

    @Test func theSampleWeekStandsNearlyHalfwayUpMontBlanc() {
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        #expect(scene.peak.name == "Mont Blanc")
        #expect(scene.status == .climbing)
        #expect(scene.climbed == 2200)
        #expect(abs(scene.fraction - 2200.0 / 4808.0) < 1e-9)
    }

    @Test func eachTomatoOnThisPeakIsAMarkerAndTheFourthOfADayIsAJar() {
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        // Saturday's two and Sunday's six: Mont Blanc was picked on Friday,
        // after both of that day's tomatoes.
        #expect(scene.markers.count == 8)
        #expect(scene.markers.filter(\.isJar).count == 1)
        #expect(scene.markers.filter(\.isToday).count == 6)
        let places = scene.markers.map(\.at)
        #expect(places == places.sorted())
    }

    @Test func theBonusLeadsItsStretchInItsOwnInk() {
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        #expect(scene.stretches.count == 12)
        #expect(scene.stretches.filter { $0.ink == .todayBonus }.count == 3)
        #expect(scene.stretches.filter { $0.ink == .earlierBonus }.count == 1)
        let todayInks = scene.stretches.filter { $0.ink == .today || $0.ink == .todayBonus }
        #expect(todayInks.first?.from == 550.0 / 4808.0)
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
        #expect(scene.climbed == 2320)
        #expect(scene.stretches.count == 14)
        #expect(scene.markers.count == 8)
    }

    @Test func nothingPickedStandsAtTheFootOfBenNevis() {
        let scene = SummitScene(rewards: RewardsSnapshot(records: sample, picks: [], today: "2026-11-15"), today: "2026-11-15")
        #expect(scene.status == .noClimb)
        #expect(scene.peak.name == "Ben Nevis")
        #expect(scene.climbed == 0)
        #expect(scene.stretches.isEmpty)
        #expect(scene.markers.isEmpty)
    }

    @Test func aSummitStaysOnItsPeakUntilTheNextPick() throws {
        // Ben Nevis picked at the start of the week and never again.
        let first = try #require(sample.first?.startedAt)
        let rewards = RewardsSnapshot(records: sample, picks: [ClimbPick(Peaks.all[0], at: first)], today: "2026-11-15")
        let scene = SummitScene(rewards: rewards, today: "2026-11-15")
        let summit = try #require(rewards.climb.summits.first)
        #expect(scene.status == .summited(summit.date))
        #expect(scene.climbed == 1345)
        #expect(scene.fraction == 1)
        let model = SummitWidgetModel(rewards: rewards, today: "2026-11-15", live: nil, logging: true)
        #expect(model.state == .summited)
        // The widget's empty sky, until the next pick.
        #expect(model.showsEmptyView)
        #expect(model.peakTitle == "Summit")
        #expect(model.lastSummitText == "Ben Nevis climbed on \(summit.date.formatted(.dateTime.day().month(.abbreviated)))")
        #expect(model.emptyHint == "Pick a mountain in the expedition log when you're ready.")
        #expect(model.statusText == model.emptyHint)
    }

    @Test func aRunningFocusThatReachesTheTopStaysOnThePeakUntilItIsLogged() throws {
        // Five tomatoes up Ben Nevis, 1,250 m, then a focus 20 minutes in.
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        log.focus(then: .stop)
        for _ in 0..<4 {
            log.wait(minutes: 30)
            log.focus(then: .stop)
        }
        let rewards = RewardsSnapshot(records: log.records, picks: [ClimbPick(Peaks.all[0], at: log.records[0].startedAt)], today: "2026-11-10")
        #expect(rewards.climb.current?.metres == 1250)
        let start = try #require(log.records.last?.endedAt).addingTimeInterval(1800)
        let active = ActiveSession(
            id: UUID(), kind: .focus, sectionID: "focus", sectionName: "Focus", sectionColorHex: "#FF9500",
            plannedSeconds: 1500, startedAt: start, timeZoneID: "GMT", utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: start)], cycleIndex: 5, title: nil, lastSeenAt: start
        )
        let live = rewards.climb.provisionalStep(for: active, after: log.records, at: start.addingTimeInterval(1200))
        let model = SummitWidgetModel(rewards: rewards, today: "2026-11-10", live: live, logging: true)
        #expect(model.scene.climbed == 1345)
        #expect(model.scene.status == .climbing)
        #expect(!model.showsEmptyView)
        #expect(model.peakTitle == "Ben Nevis")
        #expect(model.statusText == "Summit reached")
    }

    @Test func theWidgetSaysWhereYouAreAndHowFarToGo() {
        let model = SummitWidgetModel(rewards: rewards, today: "2026-11-15", live: nil, logging: true)
        #expect(model.state == .climbing)
        #expect(!model.showsEmptyView)
        #expect(model.peakTitle == "Mont Blanc")
        #expect(model.altitudeText == "\(2200.formatted()) of \(4808.formatted()) m")
        #expect(model.percentText == "45%")
        #expect(model.todayTomatoes == 6)
        #expect(model.todayJars == 1)
        #expect(model.climbedText == 2200.formatted())
        #expect(model.ofText == "of \(4808.formatted()) m · 45% up")
        // Six today: one jar and two loose.
        #expect(model.todayGlyphs.jars == 1)
        #expect(model.todayGlyphs.loose == 2)
        // 2,608 m to go at 275 m a session, the pace of the last ten.
        #expect(model.statusText == "Summit in about 9 sessions")
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
        let rewards = RewardsSnapshot(records: log.records, picks: [ClimbPick(Peaks.all[0], at: log.records[0].startedAt)], today: "2026-11-10")
        let model = SummitWidgetModel(rewards: rewards, today: "2026-11-10", live: nil, logging: true)
        #expect(model.statusText == "Summit in about 4 sessions")
    }

    @Test func theWidgetAsksForAClimbThenAFirstFocusAndSaysWhenItCannotLog() {
        let nothing = RewardsSnapshot(records: [], picks: [], today: "2026-11-15")
        let model = SummitWidgetModel(rewards: nothing, today: "2026-11-15", live: nil, logging: true)
        #expect(model.state == .noClimb)
        #expect(model.showsEmptyView)
        #expect(model.peakTitle == "Summit")
        #expect(model.lastSummitText == "No peaks climbed yet")
        #expect(model.emptyHint == "Pick a mountain in the expedition log when you're ready.")
        let picked = RewardsSnapshot(records: [], picks: [ClimbPick(Peaks.all[1], at: .now)], today: "2026-11-15")
        let started = SummitWidgetModel(rewards: picked, today: "2026-11-15", live: nil, logging: true)
        #expect(!started.showsEmptyView)
        #expect(started.peakTitle == "Mount Fuji")
        #expect(started.statusText == "Start a focus to begin the climb")
        #expect(SummitWidgetModel(rewards: rewards, today: "2026-11-15", live: nil, logging: false).statusText
            == "Not logging, see Settings")
        #expect(SummitWidgetModel(rewards: nothing, today: "2026-11-15", live: nil, logging: false).emptyHint
            == "Not logging, see Settings")
    }
}
