//
//  BuiltInSessionTracker.swift
//  Pomodorolog
//
//  Turns readings of Droppy's own Pomodoro into the session log's records.
//  Fed one `BuiltInSnapshot` at a time, it keeps the running session as an
//  `ActiveSession` and says when to checkpoint it and when one has finished.
//  `ActiveSession.finished` does the arithmetic, as it did for the replica.
//
//  The rules are what a probe run showed in Droppy 16.0.1 on 15 November
//  2026, and the tests replay that run:
//
//  - A countdown starts when `isActive` turns on. Its start is the built-in's
//    own `endTime − totalDurationSeconds`, which is exact.
//  - Pauses and resumes are stamped when seen, at most one reading late. The
//    built-in itself keeps only whole seconds while paused. A stopwatch never
//    sets `isPaused`; its pause clears `stopwatchStartTime` instead.
//  - Zero is `isOvertime` turning on, at `endTime`.
//  - Next keeps `isActive` on and changes the section. The old session ends,
//    and the new one starts, at the new session's exact start.
//  - A Clock app or Siri timer never goes into overtime. It sits at zero while
//    the alarm rings, so one that rang ends at the moment it reached zero.
//

import Foundation

@MainActor
struct BuiltInSessionTracker {
    enum Output: Equatable, Sendable {
        /// Write the running session to active.json, or remove the file (nil).
        case checkpoint(ActiveSession?)
        /// A session ended: add it to the log.
        case finished(SessionRecord)
    }

    /// How often a running session's `lastSeenAt` reaches the disk, so one
    /// cut off by Droppy quitting is closed about where it stopped.
    static let heartbeatInterval: TimeInterval = 30
    /// A start the built-in's own dates give is used when it agrees with its
    /// whole-second counters to within this; otherwise the counters win.
    static let startTolerance: TimeInterval = 3
    /// Readings further apart than this mean nobody was watching (a read that
    /// failed, a Mac asleep). A session found ended after such a gap ends
    /// where it was last seen, never later.
    static let maximumReadingGap: TimeInterval = 5
    /// The colour of a Clock timer, which no section names: system grey.
    nonisolated static let clockColorHex = "#8E8E93"
    /// The name of a Clock timer the user gave no label.
    nonisolated static let clockTimerName = "Clock timer"

    let dropletVersion: String
    /// How many focus sessions the log already holds for a day
    /// (`YYYY-MM-DD`), for the cycle index of the next one.
    private let focusSessionCount: (String) -> Int
    private let timeZone: () -> TimeZone

    /// The session running in the built-in, as it will be logged.
    private(set) var active: ActiveSession?
    private var identity: Identity?
    private var previous: BuiltInSnapshot?
    private var lastReadingAt: Date?
    private var lastCheckpointAt: Date?
    /// Focus sessions finished during the current call, by day: not in the
    /// log yet when the next one is numbered.
    private var focusFinishedThisCall: [String: Int] = [:]

    init(
        dropletVersion: String,
        timeZone: @escaping () -> TimeZone = { .current },
        focusSessionCount: @escaping (String) -> Int
    ) {
        self.dropletVersion = dropletVersion
        self.timeZone = timeZone
        self.focusSessionCount = focusSessionCount
    }

    // MARK: Feeding it

    /// Takes one reading, made at `now`, and says what to write.
    mutating func observe(_ snapshot: BuiltInSnapshot, at now: Date) -> [Output] {
        defer {
            previous = snapshot
            lastReadingAt = now
        }
        focusFinishedThisCall = [:]
        var outputs: [Output] = []
        var changed = false
        let next = Identity(snapshot)

        if active != nil, let current = identity {
            if next == nil {
                // Stopped, or a Clock timer dismissed.
                outputs.append(.finished(finish(.stop, at: lastSeen(before: now))))
                changed = true
            } else if let next, next != current {
                // Moved on to the next section, or another timer took over:
                // the old session ends where the new one starts.
                let reason: SessionEndReason = current.isLocal && next.isLocal && current.sectionID != next.sectionID
                    ? .next : .stop
                let start = Self.startMoment(of: snapshot, at: now)
                let ended = finish(reason, at: start)
                outputs.append(.finished(ended))
                begin(snapshot, as: next, at: now, startingAt: max(ended.endedAt, start))
                changed = true
            } else {
                changed = advance(with: snapshot, at: now)
            }
        } else if let next {
            begin(snapshot, as: next, at: now, startingAt: Self.startMoment(of: snapshot, at: now))
            changed = true
        }

        // Running and quiet: refresh lastSeenAt on disk every so often.
        if !changed, var session = active, !Self.isPaused(snapshot),
           now.timeIntervalSince(lastCheckpointAt ?? .distantPast) >= Self.heartbeatInterval {
            session.lastSeenAt = now
            active = session
            changed = true
        }
        if changed {
            outputs.append(.checkpoint(active))
            lastCheckpointAt = now
        }
        return outputs
    }

    /// Ends the running session, when the droplet is switched off.
    mutating func end(_ reason: SessionEndReason, at now: Date) -> [Output] {
        guard active != nil else { return [] }
        focusFinishedThisCall = [:]
        let record = finish(reason, at: lastSeen(before: now))
        lastCheckpointAt = now
        return [.finished(record), .checkpoint(nil)]
    }

    /// When a session found ended at `now` ended: `now`, unless the readings
    /// stopped a while ago (one failed, the Mac slept), in which case where it
    /// was last seen. Never later than that.
    private func lastSeen(before now: Date) -> Date {
        guard let lastReadingAt, now.timeIntervalSince(lastReadingAt) > Self.maximumReadingGap else { return now }
        return lastReadingAt
    }

    // MARK: Sessions

    private mutating func begin(_ snapshot: BuiltInSnapshot, as identity: Identity, at now: Date, startingAt start: Date) {
        let details = Details(snapshot)
        var events = [SessionEvent(type: .start, at: start)]
        // A session first seen past zero or paused (the droplet started in the
        // middle of it) picks those up as well as it can.
        if snapshot.isOvertime, let zero = Self.zeroMoment(of: snapshot, at: now), zero >= start, zero <= now {
            events.append(SessionEvent(type: .reachedZero, at: zero))
        }
        if Self.isPaused(snapshot) {
            events.append(SessionEvent(type: .pause, at: max(now, events[events.count - 1].at)))
        }

        let zone = timeZone()
        let offset = zone.secondsFromGMT(for: start)
        let day = LocalDay.key(for: start, utcOffsetSeconds: offset)
        active = ActiveSession(
            id: UUID(),
            kind: details.kind,
            sectionID: details.sectionID,
            sectionName: details.name,
            sectionColorHex: details.colorHex,
            plannedSeconds: details.plannedSeconds,
            startedAt: start,
            timeZoneID: zone.identifier,
            utcOffsetSeconds: offset,
            events: events,
            cycleIndex: details.kind == .focus
                ? focusSessionCount(day) + focusFinishedThisCall[day, default: 0] + 1
                : nil,
            title: details.title,
            lastSeenAt: now,
            source: details.source
        )
        self.identity = identity
    }

    /// Records what changed in a session that is still the same one. Returns
    /// whether anything did.
    private mutating func advance(with snapshot: BuiltInSnapshot, at now: Date) -> Bool {
        guard var session = active, let previous else { return false }
        var changed = false
        // Zero first, so a pause in the same reading lands after it.
        if snapshot.isOvertime, !previous.isOvertime, !session.hasReachedZero {
            let floor = session.events.last?.at ?? session.startedAt
            let zero = min(max(Self.zeroMoment(of: snapshot, at: now) ?? now, floor), now)
            session.events.append(SessionEvent(type: .reachedZero, at: zero))
            changed = true
        }
        let wasPaused = Self.isPaused(previous)
        let isPaused = Self.isPaused(snapshot)
        if isPaused != wasPaused {
            let at = max(now, session.events.last?.at ?? now)
            session.events.append(SessionEvent(type: isPaused ? .pause : .resume, at: at))
            changed = true
        }
        guard changed else { return false }
        session.lastSeenAt = now
        active = session
        return true
    }

    private mutating func finish(_ reason: SessionEndReason, at moment: Date) -> SessionRecord {
        guard let session = active else {
            preconditionFailure("finish called with no session running")
        }
        var end = max(moment, session.events.last?.at ?? session.startedAt)
        // A Clock timer that rang sat at zero until the alarm was dismissed,
        // so it ended when it reached zero.
        if session.kind == .clock, let zero = session.zeroCrossing(before: end) {
            end = zero
        }
        let record = session.finished(at: end, reason: reason, dropletVersion: dropletVersion)
        if record.kind == .focus {
            focusFinishedThisCall[record.localDay, default: 0] += 1
        }
        active = nil
        identity = nil
        return record
    }

    // MARK: Reading the built-in

    /// What tells one of the built-in's sessions from the next. Pausing,
    /// resuming and passing zero leave it alone.
    private struct Identity: Equatable {
        var provenance: String
        var runMode: String
        var sectionID: String?
        var minutes: Int?
        var clockTimerID: String?

        var isLocal: Bool { provenance != "appleClock" }

        init?(_ snapshot: BuiltInSnapshot) {
            guard snapshot.isActive else { return nil }
            provenance = snapshot.provenance
            runMode = snapshot.runMode
            if snapshot.provenance == "appleClock" {
                clockTimerID = snapshot.nativeTimerID
            } else if snapshot.runMode == "stopwatch" {
                sectionID = snapshot.sessionKind
            } else {
                sectionID = snapshot.activeSelection?.sectionID ?? snapshot.selectedSectionID
                minutes = snapshot.activeSelection?.minutes ?? snapshot.selectedMinutes
            }
        }
    }

    /// How a session from the built-in is logged.
    private struct Details {
        var kind: SessionKind
        var sectionID: String
        var name: String
        var colorHex: String
        var plannedSeconds: Int
        var source: SessionSource
        var title: String?

        init(_ snapshot: BuiltInSnapshot) {
            if snapshot.provenance == "appleClock" {
                kind = .clock
                sectionID = "clock"
                name = Self.trimmed(snapshot.nativeTimerTitle) ?? BuiltInSessionTracker.clockTimerName
                colorHex = BuiltInSessionTracker.clockColorHex
                plannedSeconds = Int(snapshot.totalDurationSeconds.rounded(.down))
                source = .timer
                title = nil
                return
            }
            let isStopwatch = snapshot.runMode == "stopwatch"
            let kind: SessionKind = snapshot.sessionKind.lowercased().contains("break") ? .break : .focus
            let id = isStopwatch
                ? Self.stopwatchSectionID(snapshot, kind: kind)
                : (snapshot.activeSelection?.sectionID ?? snapshot.selectedSectionID)
            let section = snapshot.sections.first { $0.id == id }
            let minutes = snapshot.activeSelection?.minutes ?? snapshot.selectedMinutes
            self.kind = kind
            sectionID = id
            name = section?.name ?? (id.prefix(1).uppercased() + id.dropFirst())
            colorHex = section?.colorHex ?? (kind == .break ? "#0A84FF" : "#FF9500")
            plannedSeconds = isStopwatch
                ? 0
                : (snapshot.totalDurationSeconds > 0 ? Int(snapshot.totalDurationSeconds.rounded(.down)) : minutes * 60)
            source = isStopwatch ? .stopwatch : .timer
            title = Self.trimmed(snapshot.focusTitle)
        }

        /// The section a stopwatch run belongs to. The built-in runs a
        /// stopwatch as a focus session whatever pill is selected: on
        /// 15 November 2026 `sessionKind` went to focus while
        /// `selectedSectionID` stayed on break. So the section follows the
        /// kind, and the selected pill only when no section has that id.
        static func stopwatchSectionID(_ snapshot: BuiltInSnapshot, kind: SessionKind) -> String {
            snapshot.sections.contains { $0.id == kind.rawValue } ? kind.rawValue : snapshot.selectedSectionID
        }

        private static func trimmed(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
    }

    /// Whether the built-in's session is paused. A stopwatch keeps
    /// `isPaused` off and clears its start time instead.
    static func isPaused(_ snapshot: BuiltInSnapshot) -> Bool {
        if snapshot.runMode == "stopwatch" {
            return snapshot.stopwatchStartTime == nil && snapshot.stopwatchPausedElapsedSeconds != nil
        }
        return snapshot.isPaused
    }

    /// When the session in `snapshot` started: the built-in's own date when it
    /// agrees with its whole-second counters, otherwise worked out from them.
    static func startMoment(of snapshot: BuiltInSnapshot, at now: Date) -> Date {
        let estimate = now.addingTimeInterval(-elapsedSeconds(of: snapshot))
        var exact: Date?
        if !isPaused(snapshot) {
            if snapshot.runMode == "stopwatch" {
                exact = snapshot.stopwatchStartTime
            } else if let end = snapshot.endTime ?? snapshot.nativeTimerDeadline, snapshot.totalDurationSeconds > 0 {
                exact = end.addingTimeInterval(-snapshot.totalDurationSeconds)
            }
        }
        guard let exact,
              exact <= now.addingTimeInterval(1),
              abs(exact.timeIntervalSince(estimate)) <= startTolerance else {
            return estimate
        }
        return exact
    }

    /// How long the session has run by the built-in's own counters, in whole
    /// seconds: a countdown counts down and then counts its overtime up, and a
    /// stopwatch counts up.
    static func elapsedSeconds(of snapshot: BuiltInSnapshot) -> TimeInterval {
        if snapshot.runMode == "stopwatch" {
            return TimeInterval(snapshot.stopwatchPausedElapsedSeconds ?? snapshot.remainingSeconds)
        }
        if snapshot.isOvertime {
            return snapshot.totalDurationSeconds + TimeInterval(snapshot.pausedOvertimeSeconds ?? snapshot.remainingSeconds)
        }
        let remaining = snapshot.pausedRemainingSeconds ?? snapshot.remainingSeconds
        return max(0, snapshot.totalDurationSeconds - TimeInterval(remaining))
    }

    /// When the countdown reached zero, by the built-in's own end time when it
    /// has one.
    private static func zeroMoment(of snapshot: BuiltInSnapshot, at now: Date) -> Date? {
        if let end = snapshot.endTime { return end }
        if let overtime = snapshot.pausedOvertimeSeconds { return now.addingTimeInterval(-TimeInterval(overtime)) }
        return nil
    }
}
