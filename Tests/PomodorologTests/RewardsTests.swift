import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct RewardsTests {
    let records = SampleLog.week(endingOn: "2026-11-15")

    private var rewards: RewardsSnapshot {
        RewardsSnapshot(records: records, today: "2026-11-15")
    }

    /// The `number`th focus on `day`.
    private func focus(_ day: String, _ number: Int) -> SessionRecord {
        records.filter { $0.kind == .focus && $0.localDay == day }[number - 1]
    }

    /// The rewards up to just before `record`, and up to and including it.
    private func around(_ record: SessionRecord, today: String) throws -> (RewardsSnapshot, RewardsSnapshot) {
        let index = try #require(records.firstIndex { $0.id == record.id })
        return (
            RewardsSnapshot(records: Array(records[..<index]), today: today),
            RewardsSnapshot(records: Array(records[...index]), today: today)
        )
    }

    @Test func theSampleWeekClimbsAsTheDesignSays() {
        let rewards = rewards
        #expect(rewards.climb.total == 7650)
        #expect(rewards.pantry.totalTomatoes == 27)
        #expect(rewards.pantry.totalJars == 5)
        #expect(rewards.sessionsFromBreak == 18)
        #expect(rewards.bonusMetres == 900)
        #expect(rewards.climb.position.peak.name == "Mont Blanc")
        #expect(rewards.climb.position.metres == 2529)
        #expect(rewards.todayClimb == DayClimb(focusMetres: 1500, bonusMetres: 150, sessions: 6, startedFromBreak: 3))
        #expect(rewards.todayPantry.tomatoes == 6)
        #expect(rewards.todayPantry.jars == 1)
        #expect(rewards.pantry.jars(inWeekOf: "2026-11-15") == 5)
    }

    @Test func theSampleWeekReachesTwoTops() {
        let summits = rewards.climb.summits
        #expect(summits.map(\.peak.name) == ["Ben Nevis", "Mount Fuji"])
        #expect(summits.first?.recordID == focus("2026-11-10", 5).id)
        #expect(summits.last?.recordID == focus("2026-11-13", 1).id)
        #expect(summits.last?.sessions == 14)
        #expect(summits.last?.days == 4)
    }

    @Test func theSampleWeekEarnsTwelveStickers() {
        #expect(Set(rewards.stickers.map(\.sticker.id)) == [
            "first-tomato", "unbroken", "hat-trick", "well-rested", "first-jar", "base-camp",
            "named-it", "fresh-legs", "clockwork", "extra-mile", "early-bird", "weekend-warrior",
        ])
        let dates = rewards.stickers.map(\.date)
        #expect(dates == dates.sorted())
    }

    @Test func fillingAJarIsAnEvent() throws {
        let (before, after) = try around(focus("2026-11-15", 4), today: "2026-11-15")
        #expect(RewardEvents.between(old: before, new: after) == [
            .jarFilled(day: "2026-11-15", jarsThatDay: 1, jarsThatWeek: 5),
        ])
    }

    @Test func reachingATopIsAnEvent() throws {
        let (before, after) = try around(focus("2026-11-13", 1), today: "2026-11-13")
        let events = RewardEvents.between(old: before, new: after)
        #expect(events.count == 1)
        guard case .summit(let summit) = events.first else {
            Issue.record("Expected a summit, got \(events)")
            return
        }
        #expect(summit.peak.name == "Mount Fuji")
    }

    @Test func newStickersAreEventsInTheBooksOrder() throws {
        let (before, after) = try around(focus("2026-11-15", 1), today: "2026-11-15")
        let ids = RewardEvents.between(old: before, new: after).compactMap { event -> String? in
            if case .sticker(let earned) = event { return earned.sticker.id }
            return nil
        }
        #expect(ids == ["early-bird", "weekend-warrior"])
    }

    @Test func nothingNewIsNoEvent() {
        #expect(RewardEvents.between(old: rewards, new: rewards).isEmpty)
    }
}
