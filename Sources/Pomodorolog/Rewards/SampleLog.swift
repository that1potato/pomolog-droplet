//
//  SampleLog.swift
//  Pomodorolog
//
//  The design's sample week, and the builder that writes sessions the way
//  Droppy's Pomodoro would. The tests use both. The harness, which has no
//  Droppy Pomodoro to log, shows the sample week. Foundation only.
//

import Foundation

enum SampleLog {
    /// Six days ending on `lastDay`. In all: 27 tomatoes, 18 of them started
    /// from a break, 5 jars and 7,650 m: Ben Nevis and Mount Fuji climbed and
    /// 2,529 m up Mont Blanc. The last day has 6 tomatoes, 1 jar and 1,650 m,
    /// 150 of them from breaks. Ending on a Sunday, it earns 12 stickers.
    static func week(endingOn lastDay: String, utcOffsetSeconds: Int = 0) -> [SessionRecord] {
        func daysBack(_ count: Int) -> String { LocalDay.offset(lastDay, by: -count) ?? lastDay }

        // Five tomatoes with a break before each but the first.
        var log = SessionLogBuilder(day: daysBack(5), at: 9, utcOffsetSeconds: utcOffsetSeconds)
        log.focus(); log.rest(); log.focus(); log.rest(); log.focus(); log.rest(); log.focus(); log.rest()
        log.focus(then: .stop)

        // Eight, the best day: a titled first focus and one break skipped.
        log.move(to: daysBack(4), at: 9)
        log.focus(title: "Thesis"); log.rest(); log.focus(); log.rest(); log.focus(); log.rest(); log.focus(); log.rest()
        log.focus(then: .stop)
        log.wait(minutes: 0.5)
        log.focus(); log.rest(); log.focus(); log.rest()
        log.focus(then: .stop)

        // Four, the last one left running 12 minutes past zero.
        log.move(to: daysBack(3), at: 9)
        log.focus(); log.rest(); log.focus(); log.rest(); log.focus(); log.rest()
        log.focus(overtime: 12, then: .stop)

        // Two and two.
        log.move(to: daysBack(2), at: 9)
        log.focus(); log.rest()
        log.focus(then: .stop)
        log.move(to: daysBack(1), at: 10)
        log.focus(); log.rest()
        log.focus(then: .stop)

        // Six from an early start, with lunch after the fourth break and the
        // last break skipped.
        log.move(to: daysBack(0), at: 7, 30)
        log.focus(); log.rest(); log.focus(); log.rest(); log.focus(); log.rest(); log.focus()
        log.rest(then: .stop)
        log.wait(minutes: 45)
        log.focus(then: .stop)
        log.wait(minutes: 0.5)
        log.focus()
        log.rest(then: .stop)

        return log.records
    }
}

/// Writes sessions the way Droppy's Pomodoro would log them, one after
/// another from a running clock in the session's own time zone.
struct SessionLogBuilder {
    private(set) var records: [SessionRecord] = []
    private(set) var clock: Date
    let utcOffsetSeconds: Int

    init(day: String, at hour: Int, _ minute: Int = 0, utcOffsetSeconds: Int = 0) {
        self.utcOffsetSeconds = utcOffsetSeconds
        clock = Self.localTime(day: day, hour: hour, minute: minute, utcOffsetSeconds: utcOffsetSeconds)
    }

    /// `hour:minute` on `day`, in a time zone `utcOffsetSeconds` from UTC.
    static func localTime(day: String, hour: Int, minute: Int, utcOffsetSeconds: Int) -> Date {
        let noonUTC = LocalDay.date(for: day) ?? Date(timeIntervalSince1970: 0)
        return noonUTC.addingTimeInterval(TimeInterval(-12 * 3600 - utcOffsetSeconds + hour * 3600 + minute * 60))
    }

    mutating func move(to day: String, at hour: Int, _ minute: Int = 0) {
        clock = Self.localTime(day: day, hour: hour, minute: minute, utcOffsetSeconds: utcOffsetSeconds)
    }

    mutating func wait(minutes: Double) {
        clock = clock.addingTimeInterval(minutes * 60)
    }

    /// A focus of `minutes`, run for `ran` of them (all, unless it was ended
    /// early), then `overtime` minutes past zero, with `pausedMinutes` paused.
    @discardableResult
    mutating func focus(
        _ minutes: Int = 25, ran: Int? = nil, overtime: Int = 0, title: String? = nil,
        pausedMinutes: Int = 0, stopwatch: Bool = false, then end: SessionEndReason = .next
    ) -> SessionRecord {
        append(.focus, planned: stopwatch ? 0 : minutes, ran: ran ?? minutes, overtime: overtime,
               title: title, pausedMinutes: pausedMinutes, stopwatch: stopwatch, end: end)
    }

    @discardableResult
    mutating func rest(_ minutes: Int = 5, ran: Int? = nil, overtime: Int = 0, then end: SessionEndReason = .next) -> SessionRecord {
        append(.break, planned: minutes, ran: ran ?? minutes, overtime: overtime,
               title: nil, pausedMinutes: 0, stopwatch: false, end: end)
    }

    @discardableResult
    mutating func clockTimer(_ minutes: Int) -> SessionRecord {
        append(.clock, planned: minutes, ran: minutes, overtime: 0, title: nil, pausedMinutes: 0, stopwatch: false, end: .stop)
    }

    private mutating func append(
        _ kind: SessionKind, planned: Int, ran: Int, overtime: Int, title: String?,
        pausedMinutes: Int, stopwatch: Bool, end: SessionEndReason
    ) -> SessionRecord {
        let start = clock
        let plannedSeconds = planned * 60
        let active = (ran + overtime) * 60
        let paused = pausedMinutes * 60
        let countsDown = !stopwatch && plannedSeconds > 0
        let reachedZero = countsDown && active >= plannedSeconds
        let ended = start.addingTimeInterval(TimeInterval(active + paused))

        var events = [SessionEvent(type: .start, at: start)]
        if paused > 0 {
            events.append(SessionEvent(type: .pause, at: start.addingTimeInterval(60)))
            events.append(SessionEvent(type: .resume, at: start.addingTimeInterval(TimeInterval(60 + paused))))
        }
        if reachedZero {
            events.append(SessionEvent(type: .reachedZero, at: start.addingTimeInterval(TimeInterval(plannedSeconds + paused))))
        }
        let endType: SessionEvent.Kind = switch end {
        case .next: .next
        case .stop: .stop
        case .interrupt: .interrupt
        }
        events.append(SessionEvent(type: endType, at: ended))

        let outcome: SessionOutcome
        if reachedZero || (!countsDown && end != .interrupt) {
            outcome = .completed
        } else {
            outcome = end == .interrupt ? .interrupted : .endedEarly
        }
        let day = LocalDay.key(for: start, utcOffsetSeconds: utcOffsetSeconds)
        let cycle = kind == .focus ? records.filter { $0.kind == .focus && $0.localDay == day }.count + 1 : nil
        let record = SessionRecord(
            id: UUID(),
            kind: kind,
            sectionID: kind.rawValue,
            sectionName: kind == .focus ? "Focus" : kind == .break ? "Break" : "Clock timer",
            sectionColorHex: kind == .focus ? "#FF9500" : kind == .break ? "#0A84FF" : "#8E8E93",
            plannedSeconds: plannedSeconds,
            startedAt: start,
            endedAt: ended,
            timeZoneID: "GMT",
            utcOffsetSeconds: utcOffsetSeconds,
            events: events,
            activeSeconds: active,
            pausedSeconds: paused,
            overtimeSeconds: countsDown ? max(0, active - plannedSeconds) : 0,
            outcome: outcome,
            endedBy: end,
            cycleIndex: cycle,
            title: title,
            note: nil,
            tags: [],
            source: stopwatch ? .stopwatch : .timer,
            dropletVersion: "sample"
        )
        records.append(record)
        clock = ended
        return record
    }
}
