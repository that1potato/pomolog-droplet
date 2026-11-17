import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct ExpeditionLogTests {
    let records = SampleLog.week(endingOn: "2026-11-15")

    private var rewards: RewardsSnapshot {
        RewardsSnapshot(records: records, picks: SampleLog.picks(for: records), today: "2026-11-15")
    }

    @Test func theSampleWeekReadsAsTheDesignDoes() {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        #expect(model.climbedText == "2 of 7 climbed")
        #expect(model.todayText == "\(1650.formatted()) m")
        #expect(model.focusText == "Focus \(1500.formatted()) m")
        #expect(model.bonusText == "Break bonus 150 m")
        #expect(model.fromBreakText == "3 of 6 sessions started from a break")
        #expect(model.weekText == "27 tomatoes, 5 jars, 18 started from a break")
        #expect(model.stickersText == "Stickers found · 14 of 30")
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
        #expect(RewardsSnapshot(records: records, picks: [], today: "2026-11-16").todayStartedAt == nil)
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
        #expect(model.today.metres == 1770)
        #expect(model.current?.metres == 2320)
        // The running focus fills Mont Blanc's icon further.
        #expect(model.rows[2].state == .current(metres: 2320, fraction: 2320.0 / 4808.0))
    }

    @Test func theRouteInksTheClimbedPeaksAndFillsTheCurrentOne() throws {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        let summits = rewards.climb.summits
        #expect(summits.count == 2)
        #expect(model.rows.map(\.index) == Array(0..<7))
        #expect(model.rows[0].state == .climbed(summits[0].date, times: 1))
        #expect(model.rows[1].state == .climbed(summits[1].date, times: 1))
        #expect(model.current?.metres == 2200)
        #expect(model.rows[2].state == .current(metres: 2200, fraction: 2200.0 / 4808.0))
        #expect(model.rows[3...].allSatisfy { $0.state == .ahead })
        #expect(model.rows[0].detailText == "Scotland · \(1345.formatted()) m")
        #expect(model.rows[6].detailText == "Mars · \(21900.formatted()) m")
        #expect(model.rows[2].spokenText == "Mont Blanc, \(4808.formatted()) metres, \(2200.formatted()) climbed, 45 percent")
        #expect(model.rows[3].spokenText == "Kilimanjaro, \(5895.formatted()) metres, still ahead")
        let day = try #require(LocalDay.date(for: "2026-11-15"))
        #expect(model.dateText == day.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide).day().month(.wide)))
        #expect(model.dateText.contains("15"))
    }

    @Test func aPeakClimbedAgainShowsItsLatestTopAndHowOften() {
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        let summits = [
            Summit(peakIndex: 0, number: 1, recordID: UUID(), date: first, sessions: 3, days: 1),
            Summit(peakIndex: 3, number: 1, recordID: UUID(), date: first, sessions: 9, days: 2),
            Summit(peakIndex: 0, number: 2, recordID: UUID(), date: second, sessions: 3, days: 1),
        ]
        let rows = ExpeditionLogModel.rows(current: nil, summits: summits)
        #expect(rows[0].state == .climbed(second, times: 2))
        #expect(rows[3].state == .climbed(first, times: 1))
        #expect(rows[0].spokenText.hasPrefix("Ben Nevis, \(1345.formatted()) metres, climbed 2 times, last on "))
        #expect(rows.filter { $0.state == .ahead }.count == 5)
    }

    @Test func thePeakBeingClimbedIsItsOwnRowEvenAfterItsTop() {
        let summits = [Summit(peakIndex: 0, number: 1, recordID: UUID(), date: Date(timeIntervalSince1970: 1_000), sessions: 3, days: 1)]
        let again = Expedition(peakIndex: 0, pickedAt: Date(timeIntervalSince1970: 2_000), metres: 100)
        let rows = ExpeditionLogModel.rows(current: again, summits: summits)
        #expect(rows[0].state == .current(metres: 100, fraction: 100.0 / 1345.0))
    }

    @Test func theStickerRowShowsTheLatestEightAndCountsTheRest() {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        #expect(model.shownStickers.count == 8)
        #expect(model.shownStickers.last == model.stickers.last)
        #expect(model.shownLocked == 0)
        #expect(model.moreStickersText == "+6")
        let empty = ExpeditionLogModel(rewards: RewardsSnapshot(records: [], picks: [], today: "2026-11-15"), today: "2026-11-15", live: nil, since: nil)
        #expect(empty.shownStickers.isEmpty)
        #expect(empty.shownLocked == 4)
        #expect(empty.moreStickersText == nil)
        #expect(empty.fromBreakText == "No focus yet today")
        #expect(empty.weekText == "No tomatoes yet this week")
        #expect(empty.climbedText == "0 of 7 climbed")
        #expect(empty.current == nil)
        #expect(empty.rows.allSatisfy { $0.state == .ahead })
    }

    @Test func theRouteAsksForAClimbWhenNoneIsUnderWay() throws {
        let climbing = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        #expect(!climbing.isPicking)
        #expect(climbing.headingText == "The route")
        let none = ExpeditionLogModel(rewards: RewardsSnapshot(records: records, picks: [], today: "2026-11-15"), today: "2026-11-15", live: nil, since: nil)
        #expect(none.isPicking)
        #expect(none.headingText == "Pick your first climb")
        // Ben Nevis picked at the start of the week, its top reached on
        // Tuesday and nothing picked since.
        let first = try #require(records.first?.startedAt)
        let topped = RewardsSnapshot(records: records, picks: [ClimbPick(Peaks.all[0], at: first)], today: "2026-11-15")
        let model = ExpeditionLogModel(rewards: topped, today: "2026-11-15", live: nil, since: nil)
        #expect(model.isPicking)
        #expect(model.headingText == "Pick your next climb")
        #expect(model.climbedText == "1 of 7 climbed")
    }

    @Test func leavingAClimbWithMetresOnItAsksFirst() {
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: nil, since: nil)
        let warning = ExpeditionLogModel.SwitchWarning(title: "Leave Mont Blanc?", detail: "Your progress will be lost")
        #expect(model.switchWarning(to: 0) == warning)
        #expect(model.switchWarning(to: 6) == warning)
        // Picking the climb under way again changes nothing, so asks nothing.
        #expect(model.switchWarning(to: 2) == nil)
    }

    @Test func aSwitchThatLosesNothingGoesStraightThrough() throws {
        // Picked, nothing climbed yet.
        let picked = RewardsSnapshot(records: [], picks: [ClimbPick(Peaks.all[1], at: .now)], today: "2026-11-15")
        #expect(ExpeditionLogModel(rewards: picked, today: "2026-11-15", live: nil, since: nil).switchWarning(to: 0) == nil)
        // Nothing picked.
        let none = RewardsSnapshot(records: records, picks: [], today: "2026-11-15")
        #expect(ExpeditionLogModel(rewards: none, today: "2026-11-15", live: nil, since: nil).switchWarning(to: 0) == nil)
        // The top reached: that climb is over.
        let first = try #require(records.first?.startedAt)
        let topped = RewardsSnapshot(records: records, picks: [ClimbPick(Peaks.all[0], at: first)], today: "2026-11-15")
        #expect(ExpeditionLogModel(rewards: topped, today: "2026-11-15", live: nil, since: nil).switchWarning(to: 1) == nil)
    }

    @Test func aRunningFocusIsNotProgressASwitchLoses() throws {
        // Mount Fuji picked again as the last session ended, then a focus: it
        // counts toward whichever climb is picked when it ends, so a switch
        // takes it along.
        let end = try #require(records.last?.endedAt)
        let picks = SampleLog.picks(for: records) + [ClimbPick(Peaks.all[1], at: end)]
        let rewards = RewardsSnapshot(records: records, picks: picks, today: "2026-11-15")
        let active = ActiveSession(
            id: UUID(), kind: .focus, sectionID: "focus", sectionName: "Focus", sectionColorHex: "#FF9500",
            plannedSeconds: 1500, startedAt: end, timeZoneID: "GMT", utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: end)], cycleIndex: 7, title: nil, lastSeenAt: end
        )
        let live = rewards.climb.provisionalStep(for: active, after: records, at: end.addingTimeInterval(600))
        let model = ExpeditionLogModel(rewards: rewards, today: "2026-11-15", live: live, since: nil)
        #expect(model.current?.peakIndex == 1)
        #expect(model.current?.metres == 120)
        #expect(model.switchWarning(to: 2) == nil)
    }
}

@MainActor
@Suite struct NotchMomentsTests {
    let records = SampleLog.week(endingOn: "2026-11-15")

    private var rewards: RewardsSnapshot {
        RewardsSnapshot(records: records, picks: SampleLog.picks(for: records), today: "2026-11-15")
    }

    private func card(_ moment: NotchMoment?) -> NotchCard? {
        if case .card(let card) = moment { card } else { nil }
    }

    @Test func aSummitCardSaysWhatItTookAndLeavesTheNextClimbToYou() throws {
        let fuji = try #require(rewards.climb.summits.last)
        let card = NotchMoments.summitCard(fuji)
        #expect(card.title == "Summit: Mount Fuji")
        #expect(card.detail == "\(3776.formatted())\u{00A0}m in 14 sessions over 3 days. Pick your next climb.")
        // On the peak's own sticker, its symbol on the tile.
        #expect(card.tileHex == Stickers.mountFuji.colorHex)
        #expect(card.peak == 1)
        #expect(card.hudID == "pomolog.summit")
    }

    @Test func aPeakClimbedAgainSaysHowOften() {
        func title(_ number: Int) -> String {
            NotchMoments.summitCard(Summit(peakIndex: 0, number: number, recordID: UUID(), date: Date(), sessions: 3, days: 1)).title
        }
        #expect(title(1) == "Summit: Ben Nevis")
        #expect(title(2) == "Summit: Ben Nevis, twice")
        #expect(title(3) == "Summit: Ben Nevis, 3 times")
    }

    @Test func aStickerCardSaysWhereItWasFound() throws {
        let earlyBird = try #require(rewards.stickers.first { $0.sticker.id == "early-bird" })
        let card = try #require(NotchMoments.stickerCard([earlyBird], rewards: rewards))
        #expect(card.title == "Found on the way: Early bird")
        // Sunday's first focus, from 550 m to 800 m up Mont Blanc.
        #expect(card.detail == "A tomato finished between 5:00 and 8:00, at 800\u{00A0}m on Mont Blanc. 14 of 30 found.")
        #expect(card.tileHex == Stickers.earlyBird.colorHex)
        #expect(card.peak == nil)
    }

    @Test func aStickerFoundWithNothingPickedSaysNoPlace() throws {
        var log = SessionLogBuilder(day: "2026-11-10", at: 9)
        log.focus(then: .stop)
        let rewards = RewardsSnapshot(records: log.records, picks: [], today: "2026-11-10")
        let first = try #require(rewards.stickers.first { $0.sticker.id == "first-tomato" })
        let card = try #require(NotchMoments.stickerCard([first], rewards: rewards))
        #expect(card.detail == "Your first tomato. \(rewards.stickers.count) of 30 found.")
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
        #expect(card.title == "14 stickers from your log so far")
        #expect(card.detail == "Found in the sessions you'd already logged. 16 more to find on the way up.")
        #expect(NotchMoments.welcomeCard(rewards: RewardsSnapshot(records: [], picks: [], today: "2026-11-15")) == nil)
    }

    @Test func theSamplesAreASummitAStickerAndAJar() {
        let samples = NotchMoments.samples(today: "2026-11-15", utcOffsetSeconds: 0)
        #expect(samples.map(\.hudID) == ["pomolog.summit", "pomolog.sticker", "pomolog.jar"])
        #expect(card(samples[0])?.title == "Summit: Mount Fuji")
        #expect(card(samples[1])?.title == "Found on the way: Early bird")
        #expect(samples[2] == .jar(today: 1, week: 5))
    }

    @Test func aCardIsAsTallAsItsWordsOnTheShapeItShowsOn() throws {
        let fuji = NotchMoments.summitCard(try #require(rewards.climb.summits.last))
        let earlyBird = try #require(rewards.stickers.first { $0.sticker.id == "early-bird" })
        let sticker = try #require(NotchMoments.stickerCard([earlyBird], rewards: rewards))
        // A line of title and two of description: as tall as Droppy's own
        // cards, on either shape.
        #expect(MomentCard.height(for: fuji, onNotch: true) == MomentCard.shortestHeight)
        #expect(MomentCard.height(for: fuji, onNotch: false) == MomentCard.shortestHeight)
        #expect(MomentCard.height(for: sticker, onNotch: true) == MomentCard.shortestHeight)
        // The island's narrower words take a third line.
        #expect(MomentCard.height(for: sticker, onNotch: false) > MomentCard.shortestHeight)
    }

    @Test func aTitleShrinksToTwelvePointsToStayOnOneLineAndWrapsPastThat() {
        let island = MomentCard.Layout.island.wordsWidth
        #expect(MomentCard.titleLines("Found on the way: Early bird", width: island) == 1)
        #expect(MomentCard.titleLines("Found on the way: Weekend warrior", width: island) == 2)
        #expect(MomentCard.titleLines("Found on the way: Weekend warrior", width: MomentCard.Layout.notch.wordsWidth) == 1)
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
        #expect(ClimbGuide.peaksValue == "7 peaks, any order")
        #expect(ClimbGuide.peaksTip.hasPrefix("Ben Nevis \(1345.formatted()) m, Mount Fuji \(3776.formatted()) m, Mont Blanc \(4808.formatted()) m"))
        #expect(ClimbGuide.peaksTip.contains("Everest \(8849.formatted()) m and Olympus Mons \(21900.formatted()) m on Mars."))
        #expect(ClimbGuide.peaksTip.contains("Focus climbs only while a climb is picked."))
        #expect(ClimbGuide.peaksTip.hasSuffix("clears the climb you leave."))
    }

    @Test func theJournalsTypefacesAreOnThisMac() {
        // Both ship with macOS; the journal falls back to the system serif
        // where one is missing, so this only says the names are spelled right.
        #expect(JournalType.isInstalled(JournalType.hand))
        #expect(JournalType.isInstalled(JournalType.print))
        #expect(!JournalType.isInstalled("No Such Typeface"))
    }
}
