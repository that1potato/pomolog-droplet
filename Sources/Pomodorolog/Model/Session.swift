//
//  Session.swift
//  Pomodorolog
//
//  The session log's record types. Foundation only: nothing here knows about
//  Droppy, so the log can be read, tested and built on without it.
//

import Foundation

/// Whether a session was work or rest, or a plain timer.
enum SessionKind: String, Codable, Sendable, CaseIterable {
    case focus
    case `break`
    /// A timer from Apple's Clock app or Siri that Droppy's Pomodoro shows.
    /// Neither focus nor break, so it counts toward no total.
    case clock
}

/// One thing that happened to a session, with the moment it happened.
///
/// The events are the source of truth. Every number on a ``SessionRecord``
/// (active, paused, overtime) is derived from them and can be recomputed.
struct SessionEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The timer was started.
        case start
        /// The user paused it.
        case pause
        /// The user resumed it.
        case resume
        /// The countdown hit zero; the session carried on into overtime.
        case reachedZero
        /// Ended by moving on to the next section.
        case next
        /// Ended with the stop button.
        case stop
        /// Ended because Droppy quit or the droplet was switched off.
        case interrupt
    }

    var type: Kind
    var at: Date
}

/// How a session turned out.
enum SessionOutcome: String, Codable, Sendable {
    /// The countdown reached zero.
    case completed
    /// The user ended it before zero.
    case endedEarly
    /// Droppy quit, or the droplet was switched off, before zero.
    case interrupted
}

/// What closed a session.
enum SessionEndReason: String, Codable, Sendable {
    case next
    case stop
    case interrupt
}

/// Where a record came from.
enum SessionSource: String, Codable, Sendable {
    case timer
    case manual
    case stopwatch
}

/// A session that is still running. This is what `active.json` holds, so a
/// session survives Droppy quitting underneath it.
struct ActiveSession: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var kind: SessionKind
    var sectionID: String
    var sectionName: String
    var sectionColorHex: String
    var plannedSeconds: Int
    var startedAt: Date
    var timeZoneID: String
    var utcOffsetSeconds: Int
    var events: [SessionEvent]
    var cycleIndex: Int?
    var title: String?
    /// The last moment the session was known to be alive. Rewritten while it
    /// runs, so an interrupted session can be closed at roughly the right time.
    var lastSeenAt: Date
    /// How the time is measured. `nil` is a countdown, which is all an
    /// `active.json` written before stopwatch runs could hold.
    var source: SessionSource? = nil

    // MARK: Derived state

    /// True when the last pause has not been resumed.
    var isPaused: Bool {
        for event in events.reversed() {
            switch event.type {
            case .pause: return true
            case .resume, .start: return false
            default: continue
            }
        }
        return false
    }

    /// True once the countdown has hit zero.
    var hasReachedZero: Bool {
        events.contains { $0.type == .reachedZero }
    }

    /// Seconds the timer has actually been running up to `date`, pauses left out.
    func activeSeconds(at date: Date) -> TimeInterval {
        var total: TimeInterval = 0
        var runningSince: Date?
        for event in events {
            switch event.type {
            case .start, .resume:
                if runningSince == nil { runningSince = event.at }
            case .pause:
                if let since = runningSince {
                    total += event.at.timeIntervalSince(since)
                    runningSince = nil
                }
            default:
                continue
            }
        }
        if let since = runningSince {
            total += date.timeIntervalSince(since)
        }
        return max(0, total)
    }

    /// Seconds spent paused up to `date`.
    func pausedSeconds(at date: Date) -> TimeInterval {
        var total: TimeInterval = 0
        var pausedSince: Date?
        for event in events {
            switch event.type {
            case .pause:
                if pausedSince == nil { pausedSince = event.at }
            case .resume:
                if let since = pausedSince {
                    total += event.at.timeIntervalSince(since)
                    pausedSince = nil
                }
            default:
                continue
            }
        }
        if let since = pausedSince {
            total += date.timeIntervalSince(since)
        }
        return max(0, total)
    }

    /// Seconds left on the countdown at `date`. Negative in overtime.
    func remainingSeconds(at date: Date) -> TimeInterval {
        TimeInterval(plannedSeconds) - activeSeconds(at: date)
    }

    // MARK: Closing

    /// Turns the running session into a finished record.
    func finished(at end: Date, reason: SessionEndReason, dropletVersion: String) -> SessionRecord {
        let source = self.source ?? .timer
        // A stopwatch has no countdown: nothing to reach, nothing over.
        let countsDown = source != .stopwatch && plannedSeconds > 0
        var closedEvents = events
        // A session that crossed zero unnoticed (Droppy quit before the timer
        // fired) still gets its marker, at the moment it actually happened.
        if countsDown, !hasReachedZero, let crossed = zeroCrossing(before: end) {
            let index = closedEvents.firstIndex { $0.at > crossed } ?? closedEvents.endIndex
            closedEvents.insert(SessionEvent(type: .reachedZero, at: crossed), at: index)
        }
        let endKind: SessionEvent.Kind
        switch reason {
        case .next: endKind = .next
        case .stop: endKind = .stop
        case .interrupt: endKind = .interrupt
        }
        closedEvents.append(SessionEvent(type: endKind, at: end))

        let active = activeSeconds(at: end)
        let reachedZero = countsDown && active >= TimeInterval(plannedSeconds)
        let outcome: SessionOutcome
        if reachedZero || (!countsDown && reason != .interrupt) {
            outcome = .completed
        } else if reason == .interrupt {
            outcome = .interrupted
        } else {
            outcome = .endedEarly
        }

        return SessionRecord(
            id: id,
            kind: kind,
            sectionID: sectionID,
            sectionName: sectionName,
            sectionColorHex: sectionColorHex,
            plannedSeconds: plannedSeconds,
            startedAt: startedAt,
            endedAt: end,
            timeZoneID: timeZoneID,
            utcOffsetSeconds: utcOffsetSeconds,
            events: closedEvents,
            activeSeconds: Int(active.rounded()),
            pausedSeconds: Int(pausedSeconds(at: end).rounded()),
            overtimeSeconds: countsDown ? Int(max(0, active - TimeInterval(plannedSeconds)).rounded()) : 0,
            outcome: outcome,
            endedBy: reason,
            cycleIndex: cycleIndex,
            title: title,
            note: nil,
            tags: [],
            source: source,
            dropletVersion: dropletVersion
        )
    }

    /// The moment the countdown hit zero, if it did so before `end`, worked
    /// out from the running stretches so it lands exactly on the planned time.
    func zeroCrossing(before end: Date) -> Date? {
        let planned = TimeInterval(plannedSeconds)
        guard activeSeconds(at: end) >= planned else { return nil }
        // Walk the running stretches until the planned time is used up.
        var used: TimeInterval = 0
        var runningSince: Date?
        for event in events {
            switch event.type {
            case .start, .resume:
                if runningSince == nil { runningSince = event.at }
            case .pause:
                if let since = runningSince {
                    let stretch = event.at.timeIntervalSince(since)
                    if used + stretch >= planned {
                        return since.addingTimeInterval(planned - used)
                    }
                    used += stretch
                    runningSince = nil
                }
            default:
                continue
            }
        }
        if let since = runningSince {
            return since.addingTimeInterval(planned - used)
        }
        return nil
    }
}

/// One finished session, as it is written to the log.
struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var kind: SessionKind
    /// The section it ran in, snapshotted so history stays right after the
    /// section is renamed, recoloured or deleted.
    var sectionID: String
    var sectionName: String
    var sectionColorHex: String
    var plannedSeconds: Int
    var startedAt: Date
    var endedAt: Date
    /// The time zone the session started in, so "which day was this" has one
    /// answer wherever the log is read later.
    var timeZoneID: String
    var utcOffsetSeconds: Int
    var events: [SessionEvent]
    var activeSeconds: Int
    var pausedSeconds: Int
    var overtimeSeconds: Int
    var outcome: SessionOutcome
    var endedBy: SessionEndReason
    /// For a focus session, its position among that day's focus sessions,
    /// starting at 1. `nil` for a break.
    var cycleIndex: Int?
    var title: String?
    var note: String?
    var tags: [String]
    var source: SessionSource
    var dropletVersion: String

    /// The calendar day the session started on, in the time zone it started
    /// in, as `YYYY-MM-DD`.
    var localDay: String {
        LocalDay.key(for: startedAt, utcOffsetSeconds: utcOffsetSeconds)
    }

    /// Seconds counted toward the countdown, overtime left out.
    var countedSeconds: Int {
        min(activeSeconds, plannedSeconds)
    }

    /// A focus session whose countdown reached zero. A stopwatch run adds to
    /// the focus time but is not a completed session; a Clock timer is
    /// neither.
    var countsAsCompletedFocus: Bool {
        kind == .focus && outcome == .completed && source != .stopwatch
    }
}

/// Calendar days as `YYYY-MM-DD` keys, computed from a fixed UTC offset so
/// they never depend on the Mac's current time zone.
enum LocalDay {
    static func key(for date: Date, utcOffsetSeconds: Int) -> String {
        let components = calendar(utcOffsetSeconds: utcOffsetSeconds)
            .dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }

    /// The key of the day before `key`, or `nil` when `key` is malformed.
    static func previous(_ key: String) -> String? {
        let utc = calendar(utcOffsetSeconds: 0)
        guard let date = date(for: key),
              let previous = utc.date(byAdding: .day, value: -1, to: date) else { return nil }
        return self.key(for: previous, utcOffsetSeconds: 0)
    }

    /// Noon UTC on the day `key` names, for formatting and day arithmetic.
    static func date(for key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar(utcOffsetSeconds: 0).date(from: components)
    }

    private static func calendar(utcOffsetSeconds: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt
        return calendar
    }
}
