import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct ExpeditionLogTests {
    let records = SampleLog.week(endingOn: "2026-11-15")

    private var rewards: RewardsSnapshot {
        RewardsSnapshot(records: records, today: "2026-11-15")
    }

    @Test func theSampleWeekReadsAsTheDesignDoes() {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        #expect(model.peakText == "Peak 3 of 7")
        #expect(model.finaleText == "Then Olympus Mons on Mars, 21.9 km")
        #expect(model.todayText == "\(1650.formatted()) m")
        #expect(model.focusText == "Focus \(1500.formatted()) m")
        #expect(model.bonusText == "Break bonus 150 m")
        #expect(model.fromBreakText == "3 of 6 sessions started from a break")
        #expect(model.weekText == "27 tomatoes, 5 jars, 18 started from a break")
        #expect(model.stickersText == "Stickers found · 12 of 24")
    }

    @Test func theWeekRunsMondayToSundayWithJarsAtTheBottom() {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        #expect(model.week.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(model.week.first?.day == "2026-11-09")
        #expect(model.week.map(\.isToday) == [false, false, false, false, false, false, true])
        #expect(model.week.reduce(0) { $0 + $1.tomatoes } == 27)
        // Sunday's six: one jar and two loose.
        let sunday = model.week[6]
        #expect(sunday.shownJars == 1)
        #expect(sunday.shownLoose == 2)
    }

    @Test func aLongDayDrawsAtMostThreeGlyphs() {
        let day = ExpeditionLogModel.WeekDay(day: "2026-11-12", letter: "T", tomatoes: 15, isToday: false)
        #expect(day.jars == 3)
        #expect(day.loose == 3)
        #expect(day.shownJars == 3)
        #expect(day.shownLoose == 0)
    }

    @Test func todayStartsWithItsFirstFocus() throws {
        let first = try #require(records.filter { $0.kind == .focus && $0.localDay == "2026-11-15" }.map(\.startedAt).min())
        #expect(rewards.todayStartedAt == first)
        #expect(RewardsSnapshot(records: records, today: "2026-11-16").todayStartedAt == nil)
    }

    @Test func aRunningFocusCountsTowardToday() throws {
        let end = try #require(records.last?.endedAt)
        let active = ActiveSession(
            id: UUID(), kind: .focus, sectionID: "focus", sectionName: "Focus", sectionColorHex: "#FF9500",
            plannedSeconds: 1500, startedAt: end, timeZoneID: "GMT", utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: end)], cycleIndex: 7, title: nil, lastSeenAt: end
        )
        let live = rewards.climb.provisionalStep(for: active, after: records, at: end.addingTimeInterval(600))
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: live, since: nil)
        #expect(model.today.sessions == 7)
        #expect(model.today.metres > 1650)
        #expect(model.position.metres == 2649)
    }

    @Test func theStripShowsTheLatestStickersAndAFewToFind() {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        #expect(model.shownStickers.count == 12)
        #expect(model.shownLocked == 4)
        let empty = ExpeditionLogModel(rewards: RewardsSnapshot(records: [], today: "2026-11-15"), today: "2026-11-15", live: nil, since: nil)
        #expect(empty.shownStickers.isEmpty)
        #expect(empty.shownLocked == 4)
        #expect(empty.fromBreakText == "No focus yet today")
        #expect(empty.weekText == "No tomatoes yet this week")
        #expect(empty.peakText == "Peak 1 of 7")
    }
}

@MainActor
@Suite struct NotchMomentsTests {
    let records = SampleLog.week(endingOn: "2026-11-15")

    private var rewards: RewardsSnapshot {
        RewardsSnapshot(records: records, today: "2026-11-15")
    }

    private func card(_ moment: NotchMoment?) -> NotchCard? {
        if case .card(let card) = moment { card } else { nil }
    }

    @Test func aSummitCardSaysWhatItTookAndWhatIsNext() throws {
        let fuji = try #require(rewards.climb.summits.last)
        let card = NotchMoments.summitCard(fuji)
        #expect(card.title == "Summit: Mount Fuji")
        #expect(card.detail == "\(3776.formatted()) m in 14 sessions over 4 days. Next up: Mont Blanc.")
        #expect(card.action == .seeTheClimb)
        #expect(card.hudID == "pomolog.summit")
    }

    @Test func theLastSummitSendsYouRoundAgain() {
        let mars = Summit(peakIndex: 6, ascent: 1, recordID: UUID(), date: Date(), sessions: 1, days: 1)
        #expect(NotchMoments.summitCard(mars).detail.hasSuffix("Next up: the range again, from Ben Nevis."))
    }

    @Test func aStickerCardSaysWhereItWasFound() throws {
        let earlyBird = try #require(rewards.stickers.first { $0.sticker.id == "early-bird" })
        let step = try #require(rewards.climb.steps.first { $0.recordID == earlyBird.recordID })
        let place = Peaks.position(at: step.after)
        let card = try #require(NotchMoments.stickerCard([earlyBird], rewards: rewards))
        #expect(card.title == "Found on the way: Early bird")
        #expect(card.detail == "A tomato finished between 5:00 and 8:00, at \(Int(place.metres.rounded(.down)).formatted()) m on \(place.peak.name). 12 of 24 found.")
        #expect(card.action == .expeditionLog)
        #expect(card.tileHex == Stickers.earlyBird.colorHex)
    }

    @Test func stickersFoundTogetherShareOneCard() throws {
        let three = Array(rewards.stickers.prefix(3))
        let card = try #require(NotchMoments.stickerCard(three, rewards: rewards))
        #expect(card.title == "Found on the way: 3 stickers")
        #expect(card.detail.hasPrefix(NotchMoments.list(three.map(\.sticker.name)) + ", at "))
        #expect(NotchMoments.stickerCard([], rewards: rewards) == nil)
    }

    @Test func namesAreListedInPlainEnglish() {
        #expect(NotchMoments.list(["Early bird"]) == "Early bird")
        #expect(NotchMoments.list(["Early bird", "Unbroken"]) == "Early bird and Unbroken")
        #expect(NotchMoments.list(["Early bird", "Unbroken", "Named it"]) == "Early bird, Unbroken and Named it")
    }

    @Test func momentsComeSummitFirstThenStickersThenTheJar() throws {
        let fuji = try #require(rewards.climb.summits.last)
        let stickers = Array(rewards.stickers.prefix(2))
        let events: [RewardEvent] = [
            .summit(fuji),
            .sticker(stickers[0]),
            .sticker(stickers[1]),
            .jarFilled(day: "2026-11-15", jarsThatDay: 1, jarsThatWeek: 5),
        ]
        let moments = NotchMoments.make(from: events, rewards: rewards, announced: [])
        #expect(moments.map(\.hudID) == ["pomolog.summit", "pomolog.sticker", "pomolog.jar"])
        #expect(card(moments[1])?.title == "Found on the way: 2 stickers")
        #expect(moments[2] == .jar(today: 1, week: 5))
    }

    @Test func aStickerAlreadyAnnouncedIsNotAnnouncedAgain() {
        let sticker = rewards.stickers[0]
        let moments = NotchMoments.make(from: [.sticker(sticker)], rewards: rewards, announced: [sticker.sticker.id])
        #expect(moments.isEmpty)
    }

    @Test func theFirstRunSumsUpTheLogsStickers() throws {
        let card = try #require(NotchMoments.welcomeCard(rewards: rewards))
        #expect(card.title == "12 stickers from your log so far")
        #expect(card.detail == "Found in the sessions you'd already logged. 12 more to find on the way up.")
        #expect(NotchMoments.welcomeCard(rewards: RewardsSnapshot(records: [], today: "2026-11-15")) == nil)
    }

    @Test func theSamplesAreASummitAStickerAndAJar() {
        let samples = NotchMoments.samples(today: "2026-11-15", utcOffsetSeconds: 0)
        #expect(samples.map(\.hudID) == ["pomolog.summit", "pomolog.sticker", "pomolog.jar"])
        #expect(card(samples[0])?.title == "Summit: Mount Fuji")
        #expect(card(samples[1])?.title == "Found on the way: Early bird")
        #expect(samples[2] == .jar(today: 1, week: 5))
    }

    @Test func aCardIsTallEnoughForItsWords() throws {
        let earlyBird = try #require(rewards.stickers.first { $0.sticker.id == "early-bird" })
        let card = try #require(NotchMoments.stickerCard([earlyBird], rewards: rewards))
        let height = MomentCard.height(for: card)
        // Room for the island's layout, and for every line on a notch.
        #expect(height >= MomentCard.narrowHeight)
        #expect(height <= 140)
        let fuji = NotchMoments.summitCard(try #require(rewards.climb.summits.last))
        #expect(MomentCard.height(for: fuji) <= height)
    }
}

@MainActor
@Suite struct ClimbGuideTests {
    @Test func theDefinitionsSayWhatTheClimbDoes() {
        #expect(ClimbGuide.focusValue == "10 m a minute")
        #expect(ClimbGuide.focusTip.contains("a 25-minute focus climbs 250 m"))
        #expect(ClimbGuide.focusTip.contains("at most 60 minutes"))
        #expect(ClimbGuide.bonusValue == "+20%")
        #expect(ClimbGuide.bonusTip.contains("300 m instead of 250"))
        #expect(ClimbGuide.bonusTip.contains("no more than 5 minutes past it"))
        #expect(ClimbGuide.bonusTip.contains("within 2 minutes"))
        #expect(ClimbGuide.jarValue == "4 tomatoes")
        #expect(ClimbGuide.jarTip.hasPrefix("Every 4th tomato of a day fills a jar: the 4th, 8th, 12th and so on."))
        #expect(ClimbGuide.peaksValue == "Ben Nevis to Olympus Mons")
        #expect(ClimbGuide.peaksTip.hasPrefix("Ben Nevis \(1345.formatted()) m, Mount Fuji \(3776.formatted()) m, Mont Blanc \(4808.formatted()) m"))
        #expect(ClimbGuide.peaksTip.contains("and Everest \(8849.formatted()) m, then Olympus Mons on Mars, \(21900.formatted()) m."))
    }
}
