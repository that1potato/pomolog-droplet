//
//  Formatting.swift
//  Pomodorolog
//
//  How times, durations and days are written out, in one place.
//

import Foundation
import SwiftUI

enum TimerFormat {
    /// A length of time in words: `45s`, `25m`, `1h 15m`.
    static func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(max(0, seconds))s" }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// `1 session`, `3 sessions`.
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// A day key as a heading: Today, Yesterday, or `Mon 9 Nov 2026`.
    static func dayTitle(_ day: String, today: String) -> String {
        if day == today { return "Today" }
        if LocalDay.previous(today) == day { return "Yesterday" }
        guard let date = LocalDay.date(for: day) else { return day }
        return date.formatted(
            Date.FormatStyle(timeZone: .gmt)
                .weekday(.abbreviated).day().month(.abbreviated).year()
        )
    }

    /// A session's clock times, in the time zone it happened in: `09:12 – 09:37`.
    static func timeRange(_ session: SessionRecord) -> String {
        let zone = TimeZone(secondsFromGMT: session.utcOffsetSeconds) ?? .gmt
        let style = Date.FormatStyle(timeZone: zone).hour().minute()
        return "\(session.startedAt.formatted(style)) – \(session.endedAt.formatted(style))"
    }
}

extension Color {
    /// A colour from `#RRGGBB`. Falls back to white for anything else.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .white
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
