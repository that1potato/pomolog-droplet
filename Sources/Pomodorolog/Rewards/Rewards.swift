//
//  Rewards.swift
//  Pomodorolog
//
//  Everything the summit shows, worked out from the log and the picks in one
//  go, and what changed when a session was added: a summit, a sticker, a jar.
//  Foundation only.
//

import Foundation

struct RewardsSnapshot: Equatable, Sendable {
    /// The day "today" means, as `YYYY-MM-DD`.
    let today: String
    let climb: Climb
    let pantry: Pantry
    /// Earned stickers, oldest first.
    let stickers: [EarnedSticker]
    /// When the first focus of `today` started, or nil before it.
    let todayStartedAt: Date?

    init(records: [SessionRecord], picks: [ClimbPick], today: String) {
        let climb = Climb(records: records, picks: picks)
        let pantry = Pantry(records: records)
        self.today = today
        self.climb = climb
        self.pantry = pantry
        stickers = StickerBook.earned(records: records, climb: climb, pantry: pantry)
        todayStartedAt = records
            .filter { $0.kind == .focus && $0.localDay == today }
            .map(\.startedAt)
            .min()
    }

    static let empty = RewardsSnapshot(records: [], picks: [], today: "")

    var todayClimb: DayClimb { climb.day(today) }
    var todayPantry: Pantry.Day { pantry.day(today) }
    var sessionsFromBreak: Int { climb.steps.filter(\.startedFromBreak).count }
    var bonusMetres: Double { climb.steps.reduce(0) { $0 + $1.bonusMetres } }
}

enum RewardEvent: Equatable, Sendable {
    case summit(Summit)
    case sticker(EarnedSticker)
    /// A day's tomatoes filled another jar.
    case jarFilled(day: String, jarsThatDay: Int, jarsThatWeek: Int)
}

enum RewardEvents {
    /// What a newly logged session earned: summits first, then stickers, then
    /// jars. A peak's own sticker comes with its summit, so it isn't a sticker
    /// event of its own.
    static func between(old: RewardsSnapshot, new: RewardsSnapshot) -> [RewardEvent] {
        var events: [RewardEvent] = []
        let reached = Set(old.climb.summits.map { "\($0.peakIndex)-\($0.number)" })
        for summit in new.climb.summits where !reached.contains("\(summit.peakIndex)-\(summit.number)") {
            events.append(.summit(summit))
        }
        let held = Set(old.stickers.map(\.sticker.id))
        for earned in new.stickers where !held.contains(earned.sticker.id) && earned.sticker.peak == nil {
            events.append(.sticker(earned))
        }
        for day in new.pantry.days.keys.sorted() {
            let jars = new.pantry.day(day).jars
            if jars > old.pantry.day(day).jars {
                events.append(.jarFilled(day: day, jarsThatDay: jars, jarsThatWeek: new.pantry.jars(inWeekOf: day)))
            }
        }
        return events
    }
}
