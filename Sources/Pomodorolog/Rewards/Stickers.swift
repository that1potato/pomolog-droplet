//
//  Stickers.swift
//  Pomodorolog
//
//  Twenty-four stickers, each earned by something in the log. A sticker is
//  dated by the session that first met its rule, so the log's past earns them
//  too. Locked ones show a hint instead of their name. Times are the session's
//  own local time. Foundation only.
//

import Foundation

struct Sticker: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// SF Symbol.
    let symbol: String
    let colorHex: String
    /// What earns it, in a sentence.
    let rule: String
    /// What a locked sticker shows instead of its name.
    let hint: String
}

struct EarnedSticker: Equatable, Sendable {
    let sticker: Sticker
    /// The session that earned it, and when it ended.
    let recordID: UUID
    let date: Date
}

enum Stickers {
    static let firstTomato = Sticker(id: "first-tomato", name: "First tomato", symbol: "leaf.fill", colorHex: "#FF6B5E", rule: "Your first tomato.", hint: "Where it starts")
    static let century = Sticker(id: "century", name: "Century", symbol: "rosette", colorHex: "#FFD60A", rule: "100 tomatoes.", hint: "Three digits")
    static let earlyBird = Sticker(id: "early-bird", name: "Early bird", symbol: "sunrise.fill", colorHex: "#FFD60A", rule: "A tomato finished between 5:00 and 8:00.", hint: "Up with the sun")
    static let nightOwl = Sticker(id: "night-owl", name: "Night owl", symbol: "moon.stars.fill", colorHex: "#A5A3FF", rule: "A tomato finished between 23:00 and 5:00.", hint: "A late one")
    static let hatTrick = Sticker(id: "hat-trick", name: "Hat trick", symbol: "3.circle.fill", colorHex: "#FF9F0A", rule: "3 tomatoes before noon in one day.", hint: "Before lunch")
    static let dozen = Sticker(id: "dozen", name: "Dozen", symbol: "12.circle.fill", colorHex: "#FF6B5E", rule: "12 tomatoes in one day.", hint: "By the dozen")
    static let marathon = Sticker(id: "marathon", name: "Marathon", symbol: "figure.run", colorHex: "#FF7AA2", rule: "4 hours of focus in one day.", hint: "A long day")
    static let weekendWarrior = Sticker(id: "weekend-warrior", name: "Weekend warrior", symbol: "sofa.fill", colorHex: "#DA8FFF", rule: "Tomatoes on a Saturday and the Sunday after.", hint: "No days off")
    static let perfectWeek = Sticker(id: "perfect-week", name: "Perfect week", symbol: "calendar", colorHex: "#64D2FF", rule: "A tomato every day from Monday to Sunday.", hint: "Seven out of seven")
    static let clockwork = Sticker(id: "clockwork", name: "Clockwork", symbol: "clock.fill", colorHex: "#66D4CF", rule: "Tomatoes started in the same hour on 3 days in a row.", hint: "Same time again")
    static let comeback = Sticker(id: "comeback", name: "Comeback", symbol: "arrow.uturn.backward.circle.fill", colorHex: "#30D158", rule: "A tomato after 7 days or more without one.", hint: "Welcome back")
    static let weekStreak = Sticker(id: "week-streak", name: "Week streak", symbol: "flame.fill", colorHex: "#FF9F0A", rule: "7 days in a row with a tomato.", hint: "A week running")
    static let monthStreak = Sticker(id: "month-streak", name: "Month streak", symbol: "flame.circle.fill", colorHex: "#FF453A", rule: "30 days in a row with a tomato.", hint: "A month running")
    static let unbroken = Sticker(id: "unbroken", name: "Unbroken", symbol: "bolt.fill", colorHex: "#66D4CF", rule: "A tomato of 25 minutes or more with no pause.", hint: "No pauses")
    static let extraMile = Sticker(id: "extra-mile", name: "Extra mile", symbol: "forward.fill", colorHex: "#FF7AA2", rule: "A focus that ran 10 minutes past zero.", hint: "Past zero")
    static let longHaul = Sticker(id: "long-haul", name: "Long haul", symbol: "hourglass", colorHex: "#BF5AF2", rule: "A tomato planned for 50 minutes or more.", hint: "One long sitting")
    static let namedIt = Sticker(id: "named-it", name: "Named it", symbol: "pencil", colorHex: "#A5A3FF", rule: "A tomato with a focus title.", hint: "Give it a name")
    static let freshLegs = Sticker(id: "fresh-legs", name: "Fresh legs", symbol: "wind", colorHex: "#FFB340", rule: "10 focus sessions started from a break.", hint: "Rest pays")
    static let wellRested = Sticker(id: "well-rested", name: "Well rested", symbol: "bed.double.fill", colorHex: "#64D2FF", rule: "A day of 4 tomatoes or more where every focus after the first started from a break.", hint: "Every break, all day")
    static let firstJar = Sticker(id: "first-jar", name: "First jar", symbol: "archivebox.fill", colorHex: "#FF6B5E", rule: "Your first jar.", hint: "Four of a kind")
    static let pantry = Sticker(id: "pantry", name: "Pantry", symbol: "shippingbox.fill", colorHex: "#FF9F0A", rule: "25 jars.", hint: "A full pantry")
    static let baseCamp = Sticker(id: "base-camp", name: "Base camp", symbol: "flag.fill", colorHex: "#64D2FF", rule: "Your first summit.", hint: "The first top")
    static let thinAir = Sticker(id: "thin-air", name: "Thin air", symbol: "mountain.2.fill", colorHex: "#E5E5EA", rule: "8,000 m up Everest.", hint: "Very high up")
    static let redPlanet = Sticker(id: "red-planet", name: "Red planet", symbol: "sparkles", colorHex: "#FF453A", rule: "The top of Olympus Mons.", hint: "Another planet")

    /// In the order the sticker book shows them.
    static let all: [Sticker] = [
        firstTomato, century, earlyBird, nightOwl, hatTrick, dozen, marathon, weekendWarrior,
        perfectWeek, clockwork, comeback, weekStreak, monthStreak, unbroken, extraMile, longHaul,
        namedIt, freshLegs, wellRested, firstJar, pantry, baseCamp, thinAir, redPlanet,
    ]
}

/// Works out which stickers a log has earned, and when.
enum StickerBook {
    static func earned(records: [SessionRecord], climb: Climb, pantry: Pantry) -> [EarnedSticker] {
        let context = Context(records: records, climb: climb, pantry: pantry)
        let rules: [(Sticker, (Context) -> Earn?)] = [
            (Stickers.firstTomato, firstTomato), (Stickers.century, century),
            (Stickers.earlyBird, earlyBird), (Stickers.nightOwl, nightOwl),
            (Stickers.hatTrick, hatTrick), (Stickers.dozen, dozen),
            (Stickers.marathon, marathon), (Stickers.weekendWarrior, weekendWarrior),
            (Stickers.perfectWeek, perfectWeek), (Stickers.clockwork, clockwork),
            (Stickers.comeback, comeback), (Stickers.weekStreak, { streak(7, $0) }),
            (Stickers.monthStreak, { streak(30, $0) }), (Stickers.unbroken, unbroken),
            (Stickers.extraMile, extraMile), (Stickers.longHaul, longHaul),
            (Stickers.namedIt, namedIt), (Stickers.freshLegs, freshLegs),
            (Stickers.wellRested, wellRested), (Stickers.firstJar, firstJar),
            (Stickers.pantry, pantryOfJars), (Stickers.baseCamp, baseCamp),
            (Stickers.thinAir, thinAir), (Stickers.redPlanet, redPlanet),
        ]
        let earned = rules.enumerated().compactMap { order, rule -> (Int, EarnedSticker)? in
            guard let earn = rule.1(context) else { return nil }
            return (order, EarnedSticker(sticker: rule.0, recordID: earn.recordID, date: earn.date))
        }
        // Oldest first; two earned by one session keep the book's order.
        return earned
            .sorted { ($0.1.date, $0.0) < ($1.1.date, $1.0) }
            .map(\.1)
    }

    // MARK: What the rules read

    struct Earn {
        let recordID: UUID
        let date: Date
    }

    struct Context {
        /// Focus and break sessions in the order they started.
        let timeline: [SessionRecord]
        /// Tomatoes in the order they started.
        let tomatoes: [SessionRecord]
        let climb: Climb
        let pantry: Pantry
        let steps: [UUID: ClimbStep]

        init(records: [SessionRecord], climb: Climb, pantry: Pantry) {
            timeline = Climb.timeline(records)
            tomatoes = timeline.filter(\.countsAsCompletedFocus)
            self.climb = climb
            self.pantry = pantry
            steps = Dictionary(climb.steps.map { ($0.recordID, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private static func earn(_ record: SessionRecord?) -> Earn? {
        record.map { Earn(recordID: $0.id, date: $0.endedAt) }
    }

    /// The hour on the clock where the session happened.
    private static func hour(_ date: Date, of record: SessionRecord) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: record.utcOffsetSeconds) ?? .gmt
        return calendar.component(.hour, from: date)
    }

    // MARK: The rules

    private static func firstTomato(_ c: Context) -> Earn? {
        earn(c.tomatoes.first)
    }

    private static func century(_ c: Context) -> Earn? {
        c.tomatoes.count >= 100 ? earn(c.tomatoes[99]) : nil
    }

    private static func earlyBird(_ c: Context) -> Earn? {
        earn(c.tomatoes.first { (5..<8).contains(hour($0.endedAt, of: $0)) })
    }

    private static func nightOwl(_ c: Context) -> Earn? {
        earn(c.tomatoes.first {
            let finished = hour($0.endedAt, of: $0)
            return finished >= 23 || finished < 5
        })
    }

    /// The third tomato of a day, finished before noon that same day.
    private static func hatTrick(_ c: Context) -> Earn? {
        var counts: [String: Int] = [:]
        for tomato in c.tomatoes {
            let day = tomato.localDay
            counts[day, default: 0] += 1
            if counts[day] == 3,
               LocalDay.key(for: tomato.endedAt, utcOffsetSeconds: tomato.utcOffsetSeconds) == day,
               hour(tomato.endedAt, of: tomato) < 12 {
                return earn(tomato)
            }
        }
        return nil
    }

    private static func dozen(_ c: Context) -> Earn? {
        var counts: [String: Int] = [:]
        for tomato in c.tomatoes {
            counts[tomato.localDay, default: 0] += 1
            if counts[tomato.localDay] == 12 { return earn(tomato) }
        }
        return nil
    }

    /// Four hours of focus that climbs, in one day.
    private static func marathon(_ c: Context) -> Earn? {
        var seconds: [String: Int] = [:]
        for record in c.timeline where record.kind == .focus {
            seconds[record.localDay, default: 0] += ClimbRules.countedSeconds(record)
            if seconds[record.localDay, default: 0] >= 4 * 3600 { return earn(record) }
        }
        return nil
    }

    private static func weekendWarrior(_ c: Context) -> Earn? {
        var days = Set<String>()
        for tomato in c.tomatoes {
            let day = tomato.localDay
            if LocalDay.isoWeekday(day) == 7, let saturday = LocalDay.offset(day, by: -1), days.contains(saturday) {
                return earn(tomato)
            }
            days.insert(day)
        }
        return nil
    }

    private static func perfectWeek(_ c: Context) -> Earn? {
        var weeks: [String: Set<String>] = [:]
        for tomato in c.tomatoes {
            let day = tomato.localDay
            guard let monday = LocalDay.monday(of: day) else { continue }
            weeks[monday, default: []].insert(day)
            if weeks[monday]?.count == 7 { return earn(tomato) }
        }
        return nil
    }

    /// Tomatoes started in the same clock hour on three days in a row.
    private static func clockwork(_ c: Context) -> Earn? {
        var hours: [String: Set<Int>] = [:]
        for tomato in c.tomatoes {
            let day = tomato.localDay
            let started = hour(tomato.startedAt, of: tomato)
            if let yesterday = LocalDay.offset(day, by: -1),
               let dayBefore = LocalDay.offset(day, by: -2),
               hours[yesterday]?.contains(started) == true,
               hours[dayBefore]?.contains(started) == true {
                return earn(tomato)
            }
            hours[day, default: []].insert(started)
        }
        return nil
    }

    /// A tomato with at least 7 empty days since the one before.
    private static func comeback(_ c: Context) -> Earn? {
        var previous: String?
        for tomato in c.tomatoes {
            let day = tomato.localDay
            if let previous, let gap = LocalDay.distance(from: previous, to: day), gap >= 8 {
                return earn(tomato)
            }
            previous = day
        }
        return nil
    }

    /// The tomato that makes `length` days in a row with a tomato.
    private static func streak(_ length: Int, _ c: Context) -> Earn? {
        var lastDay: String?
        var run = 0
        for tomato in c.tomatoes {
            let day = tomato.localDay
            if day == lastDay { continue }
            if let lastDay, LocalDay.offset(lastDay, by: 1) == day {
                run += 1
            } else {
                run = 1
            }
            lastDay = day
            if run >= length { return earn(tomato) }
        }
        return nil
    }

    private static func unbroken(_ c: Context) -> Earn? {
        earn(c.tomatoes.first { tomato in
            tomato.plannedSeconds >= 25 * 60
                && tomato.pausedSeconds == 0
                && !tomato.events.contains { $0.type == .pause }
        })
    }

    private static func extraMile(_ c: Context) -> Earn? {
        earn(c.timeline.first { $0.kind == .focus && $0.overtimeSeconds >= 10 * 60 })
    }

    private static func longHaul(_ c: Context) -> Earn? {
        earn(c.tomatoes.first { $0.plannedSeconds >= 50 * 60 })
    }

    private static func namedIt(_ c: Context) -> Earn? {
        earn(c.tomatoes.first { !($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private static func freshLegs(_ c: Context) -> Earn? {
        let fromBreak = c.climb.steps.filter(\.startedFromBreak)
        guard fromBreak.count >= 10 else { return nil }
        return Earn(recordID: fromBreak[9].recordID, date: fromBreak[9].endedAt)
    }

    /// The first moment a day had 4 tomatoes and every focus after its first
    /// had started from a break.
    private static func wellRested(_ c: Context) -> Earn? {
        struct DayState {
            var focus = 0
            var tomatoes = 0
            var allFromBreak = true
        }
        var days: [String: DayState] = [:]
        for record in c.timeline where record.kind == .focus {
            let day = record.localDay
            var state = days[day] ?? DayState()
            if state.focus > 0, c.steps[record.id]?.startedFromBreak != true {
                state.allFromBreak = false
            }
            state.focus += 1
            if record.countsAsCompletedFocus { state.tomatoes += 1 }
            days[day] = state
            if state.tomatoes >= 4, state.allFromBreak { return earn(record) }
        }
        return nil
    }

    private static func firstJar(_ c: Context) -> Earn? {
        c.pantry.tomatoes.first(where: \.isJar).map { Earn(recordID: $0.recordID, date: $0.endedAt) }
    }

    private static func pantryOfJars(_ c: Context) -> Earn? {
        let jars = c.pantry.tomatoes.filter(\.isJar)
        guard jars.count >= 25 else { return nil }
        return Earn(recordID: jars[24].recordID, date: jars[24].endedAt)
    }

    private static func baseCamp(_ c: Context) -> Earn? {
        c.climb.summits.first.map { Earn(recordID: $0.recordID, date: $0.date) }
    }

    /// 8,000 m up Everest, the first time up the range.
    private static func thinAir(_ c: Context) -> Earn? {
        let everest = Peaks.all.firstIndex { $0.name == "Everest" } ?? 5
        let mark = Peaks.foot(ofPeak: everest, ascent: 1) + 8000
        return c.climb.steps.first { $0.after >= mark }.map { Earn(recordID: $0.recordID, date: $0.endedAt) }
    }

    private static func redPlanet(_ c: Context) -> Earn? {
        c.climb.summits.first { $0.peakIndex == Peaks.all.count - 1 }.map { Earn(recordID: $0.recordID, date: $0.date) }
    }
}
