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
        #expect(model.climbedText == "2 of 7 climbed")
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
        // The running focus fills Mont Blanc's icon further.
        #expect(model.rows[2].state == .current(metres: 2649, fraction: model.position.fraction))
    }

    @Test func theRouteInksTheClimbedPeaksAndFillsTheCurrentOne() throws {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        let summits = rewards.climb.summits
        #expect(summits.count == 2)
        #expect(model.rows.map(\.index) == Array(0..<7))
        #expect(model.rows[0].state == .climbed(summits[0].date))
        #expect(model.rows[1].state == .climbed(summits[1].date))
        #expect(model.position.metres == 2529)
        #expect(model.rows[2].state == .current(metres: 2529, fraction: model.position.fraction))
        #expect(model.rows[3...].allSatisfy { $0.state == .ahead })
        #expect(model.rows[0].detailText == "Scotland · \(1345.formatted()) m")
        #expect(model.rows[6].detailText == "Mars · \(21900.formatted()) m")
        #expect(model.rows[2].spokenText == "Mont Blanc, \(4808.formatted()) metres, \(2529.formatted()) climbed, 52 percent")
        #expect(model.rows[3].spokenText == "Kilimanjaro, \(5895.formatted()) metres, still ahead")
        let day = try #require(LocalDay.date(for: "2026-11-15"))
        #expect(model.dateText == day.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide).day().month(.wide)))
        #expect(model.dateText.contains("15"))
    }

    @Test func aSecondAscentDatesOnlyItsOwnSummits() {
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        let summits = (0..<7).map { Summit(peakIndex: $0, ascent: 1, recordID: UUID(), date: first, sessions: 1, days: 1) }
            + [Summit(peakIndex: 0, ascent: 2, recordID: UUID(), date: second, sessions: 1, days: 1)]
        let position = PeakPosition(ascent: 2, index: 1, metres: 100)
        let rows = ExpeditionLogModel.rows(at: position, summits: summits, now: .distantFuture)
        #expect(rows[0].state == .climbed(second))
        #expect(rows[1].state == .current(metres: 100, fraction: position.fraction))
        #expect(rows[2...].allSatisfy { $0.state == .ahead })
        #expect(ExpeditionLogModel.climbedText(at: position) == "Ascent 2 · 1 of 7 climbed")
    }

    @Test func aTopTheRunningFocusCrossedIsDatedNow() {
        let now = Date(timeIntervalSince1970: 3_000)
        let rows = ExpeditionLogModel.rows(at: PeakPosition(ascent: 1, index: 1, metres: 10), summits: [], now: now)
        #expect(rows[0].state == .climbed(now))
    }

    @Test func theStickerRowShowsTheLatestEightAndCountsTheRest() {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        #expect(model.shownStickers.count == 8)
        #expect(model.shownStickers.last == model.stickers.last)
        #expect(model.shownLocked == 0)
        #expect(model.moreStickersText == "+4")
        let empty = ExpeditionLogModel(rewards: RewardsSnapshot(records: [], today: "2026-11-15"), today: "2026-11-15", live: nil, since: nil)
        #expect(empty.shownStickers.isEmpty)
        #expect(empty.shownLocked == 4)
        #expect(empty.moreStickersText == nil)
        #expect(empty.fromBreakText == "No focus yet today")
        #expect(empty.weekText == "No tomatoes yet this week")
        #expect(empty.climbedText == "0 of 7 climbed")
        #expect(empty.rows[0].state == .current(metres: 0, fraction: 0))
        #expect(empty.rows.dropFirst().allSatisfy { $0.state == .ahead })
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
