//
//  Pantry.swift
//  Pomodorolog
//
//  Tomatoes and jars. A tomato is a focus countdown that reached zero, the
//  same count as the Today row and the streak. Every fourth tomato of a day
//  fills a jar, and jars don't carry across days. Foundation only.
//

import Foundation

struct Pantry: Equatable, Sendable {
    static let tomatoesPerJar = 4

    struct Tomato: Equatable, Sendable {
        let recordID: UUID
        let day: String
        let endedAt: Date
        /// Its place among the day's tomatoes, from 1.
        let number: Int

        /// The fourth, eighth, twelfth tomato of a day is a jar.
        var isJar: Bool { number % Pantry.tomatoesPerJar == 0 }
    }

    struct Day: Equatable, Sendable {
        var tomatoes = 0

        var jars: Int { tomatoes / Pantry.tomatoesPerJar }
        /// Tomatoes not in a jar yet.
        var loose: Int { tomatoes % Pantry.tomatoesPerJar }
    }

    /// Every tomato, in the order the sessions started.
    let tomatoes: [Tomato]
    let days: [String: Day]

    init(records: [SessionRecord]) {
        var counts: [String: Int] = [:]
        var tomatoes: [Tomato] = []
        let ordered = records
            .filter(\.countsAsCompletedFocus)
            .sorted { ($0.startedAt, $0.endedAt) < ($1.startedAt, $1.endedAt) }
        for record in ordered {
            let day = record.localDay
            let number = counts[day, default: 0] + 1
            counts[day] = number
            tomatoes.append(Tomato(recordID: record.id, day: day, endedAt: record.endedAt, number: number))
        }
        self.tomatoes = tomatoes
        days = counts.mapValues { Day(tomatoes: $0) }
    }

    var totalTomatoes: Int { tomatoes.count }
    var totalJars: Int { days.values.reduce(0) { $0 + $1.jars } }

    func day(_ key: String) -> Day {
        days[key] ?? Day()
    }

    /// Jars in the Monday-to-Sunday week that holds `key`.
    func jars(inWeekOf key: String) -> Int {
        LocalDay.week(of: key).reduce(0) { $0 + day($1).jars }
    }
}

// MARK: - Day arithmetic

extension LocalDay {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// The key `days` days after `key`, or before it when negative.
    static func offset(_ key: String, by days: Int) -> String? {
        guard let date = date(for: key),
              let moved = utc.date(byAdding: .day, value: days, to: date) else { return nil }
        return self.key(for: moved, utcOffsetSeconds: 0)
    }

    /// 1 for Monday through 7 for Sunday.
    static func isoWeekday(_ key: String) -> Int? {
        guard let date = date(for: key) else { return nil }
        let weekday = utc.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    /// The Monday of the week that holds `key`.
    static func monday(of key: String) -> String? {
        guard let weekday = isoWeekday(key) else { return nil }
        return offset(key, by: 1 - weekday)
    }

    /// Monday to Sunday of the week that holds `key`.
    static func week(of key: String) -> [String] {
        guard let monday = monday(of: key) else { return [] }
        return (0..<7).compactMap { offset(monday, by: $0) }
    }

    /// Whole days from `start` to `end`.
    static func distance(from start: String, to end: String) -> Int? {
        guard let first = date(for: start), let last = date(for: end) else { return nil }
        return utc.dateComponents([.day], from: first, to: last).day
    }
}
