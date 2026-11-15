import Foundation
import Testing
@testable import Pomodorolog

// MARK: Reading the probe's log back

private let probeTime = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

private func date(_ text: String) -> Date {
    try! probeTime.parse(text)
}

/// The "change" and "tick" lines of builtin-probe.log, back as snapshots.
private func probeReadings(_ log: String) -> [(at: Date, snapshot: BuiltInSnapshot)] {
    var sections: [BuiltInSnapshot.Section] = []
    var readings: [(at: Date, snapshot: BuiltInSnapshot)] = []
    for line in log.split(separator: "\n").map(String.init) {
        guard let match = line.wholeMatch(of: /(\S+) (?:change|tick)\s+(.*)/) else { continue }
        var fields: [String: String] = [:]
        for field in String(match.2).matches(of: /(\w+)=(\[[^\]]*\]|\S+)/) {
            fields[String(field.1)] = String(field.2)
        }
        if let list = fields["sections"] {
            sections = list.matches(of: /(\w[\w-]*) "([^"]*)" (#\w+)/).map {
                BuiltInSnapshot.Section(id: String($0.1), name: String($0.2), colorHex: String($0.3))
            }
        }
        func value(_ key: String) -> String? { fields[key] == "-" ? nil : fields[key] }
        func pair(_ text: String?) -> (String, Int)? {
            guard let parts = text?.split(separator: "/"), parts.count == 2, let minutes = Int(parts[1]) else { return nil }
            return (String(parts[0]), minutes)
        }
        func unquoted(_ text: Substring) -> String? {
            text == "-" ? nil : text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        let clock = (fields["clock"] ?? "-/-/-").split(separator: "/", omittingEmptySubsequences: false)
        let selected = pair(fields["selected"])!

        readings.append((date(String(match.1)), BuiltInSnapshot(
            isActive: fields["active"] == "1",
            isPaused: fields["paused"] == "1",
            isOvertime: fields["overtime"] == "1",
            runMode: fields["mode"]!,
            sessionKind: fields["kind"]!,
            provenance: fields["from"]!,
            activeSelection: pair(value("selection")).map { .init(sectionID: $0.0, minutes: $0.1) },
            selectedSectionID: selected.0,
            selectedMinutes: selected.1,
            remainingSeconds: Int(fields["remaining"]!)!,
            totalDurationSeconds: Double(fields["total"]!)!,
            endTime: value("end").map(date),
            pausedRemainingSeconds: value("pausedRemaining").flatMap { Int($0) },
            pausedOvertimeSeconds: value("pausedOvertime").flatMap { Int($0) },
            stopwatchStartTime: value("stopwatchStart").map(date),
            stopwatchPausedElapsedSeconds: value("stopwatchPaused").flatMap { Int($0) },
            completedSessions: Int(fields["completed"]!)!,
            focusTitle: value("title").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) },
            nativeTimerID: unquoted(clock[0]),
            nativeTimerTitle: unquoted(clock[1]),
            nativeTimerDeadline: clock[2] == "-" ? nil : date(String(clock[2])),
            sections: sections
        )))
    }
    return readings
}

// MARK: A log to number cycles against

@MainActor
private final class LogStub {
    var records: [SessionRecord] = []
    var checkpoint: ActiveSession?
    var checkpointCount = 0

    func focusCount(onDay day: String) -> Int {
        records.filter { $0.kind == .focus && $0.localDay == day }.count
    }

    func apply(_ outputs: [BuiltInSessionTracker.Output]) {
        for output in outputs {
            switch output {
            case .finished(let record):
                records.append(record)
            case .checkpoint(let session):
                checkpoint = session
                checkpointCount += 1
            }
        }
    }
}

// MARK: Readings made by hand

private let t0 = date("2026-11-15T06:00:00.250Z")

private func at(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

private let defaultSections = [
    BuiltInSnapshot.Section(id: "focus", name: "Focus", colorHex: "#FF9500"),
    BuiltInSnapshot.Section(id: "break", name: "Break", colorHex: "#0A84FF"),
]

private func idle(selected: String = "focus", minutes: Int = 25) -> BuiltInSnapshot {
    BuiltInSnapshot(
        isActive: false, isPaused: false, isOvertime: false,
        runMode: "countdown", sessionKind: selected == "break" ? "break" : "focus", provenance: "local",
        activeSelection: nil, selectedSectionID: selected, selectedMinutes: minutes,
        remainingSeconds: 0, totalDurationSeconds: 0, endTime: nil,
        pausedRemainingSeconds: nil, pausedOvertimeSeconds: nil,
        stopwatchStartTime: nil, stopwatchPausedElapsedSeconds: nil,
        completedSessions: 0, focusTitle: nil,
        nativeTimerID: nil, nativeTimerTitle: nil, nativeTimerDeadline: nil,
        sections: defaultSections
    )
}

/// A countdown that started at `startedAt` and has run without a pause, as
/// read at `now`; or, with `pausedRemaining`, one paused with that much left.
private func countdown(
    section: String = "focus",
    minutes: Int = 25,
    startedAt: Date,
    now: Date,
    pausedRemaining: Int? = nil
) -> BuiltInSnapshot {
    var snapshot = idle(selected: section, minutes: minutes)
    let total = TimeInterval(minutes * 60)
    snapshot.isActive = true
    snapshot.activeSelection = .init(sectionID: section, minutes: minutes)
    snapshot.totalDurationSeconds = total
    if let pausedRemaining {
        snapshot.isPaused = true
        snapshot.pausedRemainingSeconds = pausedRemaining
        snapshot.remainingSeconds = pausedRemaining
    } else {
        let end = startedAt.addingTimeInterval(total)
        snapshot.endTime = end
        snapshot.remainingSeconds = Int(end.timeIntervalSince(now).rounded(.up))
    }
    return snapshot
}

/// A Clock app timer that started at `startedAt`, as read at `now`.
private func clockTimer(seconds: Int, startedAt: Date, now: Date, title: String? = nil) -> BuiltInSnapshot {
    var snapshot = idle()
    let deadline = startedAt.addingTimeInterval(TimeInterval(seconds))
    snapshot.isActive = true
    snapshot.provenance = "appleClock"
    snapshot.totalDurationSeconds = TimeInterval(seconds)
    snapshot.endTime = deadline
    snapshot.nativeTimerDeadline = deadline
    snapshot.nativeTimerID = "CLOCK-1"
    snapshot.nativeTimerTitle = title
    snapshot.remainingSeconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    return snapshot
}

private func expectClose(_ actual: Date, _ expected: Date, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual.timeIntervalSince(expected)) < 0.001, "\(actual) is not \(expected)", sourceLocation: sourceLocation)
}

@MainActor
@Suite struct BuiltInSessionTrackerTests {
    private let log = LogStub()

    private func makeTracker() -> BuiltInSessionTracker {
        let log = log
        return BuiltInSessionTracker(
            dropletVersion: "test",
            timeZone: { TimeZone(identifier: "GMT")! },
            focusSessionCount: { day in log.focusCount(onDay: day) }
        )
    }

    /// One reading, its outputs applied to the log as the droplet will.
    @discardableResult
    private func feed(_ tracker: inout BuiltInSessionTracker, _ snapshot: BuiltInSnapshot, at moment: Date) -> [BuiltInSessionTracker.Output] {
        let outputs = tracker.observe(snapshot, at: moment)
        log.apply(outputs)
        return outputs
    }

    /// Feeds readings the way the droplet will: one every half second, each
    /// held until the next. The probe only wrote down the changes.
    private func replay(_ readings: [(at: Date, snapshot: BuiltInSnapshot)], into tracker: inout BuiltInSessionTracker) {
        for (index, reading) in readings.enumerated() {
            let next = index + 1 < readings.count ? readings[index + 1].at : reading.at
            var moment = reading.at
            repeat {
                feed(&tracker, reading.snapshot, at: moment)
                moment = moment.addingTimeInterval(0.5)
            } while moment < next
        }
    }

    // MARK: The real run

    @Test func theProbeRunLogsItsFiveSessions() throws {
        let readings = probeReadings(probeRun20261115)
        #expect(readings.count == 32)
        var tracker = makeTracker()
        replay(readings, into: &tracker)

        #expect(tracker.active == nil)
        #expect(log.checkpoint == nil)
        try #require(log.records.count == 5)
        let focus = log.records[0], rest = log.records[1], early = log.records[2]
        let stopwatch = log.records[3], clock = log.records[4]

        // A 1-minute Focus, paused once, past zero for 17 seconds, then Next.
        #expect(focus.kind == .focus)
        #expect(focus.sectionName == "Focus" && focus.sectionColorHex == "#FF9500")
        #expect(focus.plannedSeconds == 60)
        expectClose(focus.startedAt, date("2026-11-15T06:15:27.188Z"))
        expectClose(focus.endedAt, date("2026-11-15T06:16:50.610Z"))
        #expect(focus.events.map(\.type) == [.start, .pause, .resume, .reachedZero, .next])
        expectClose(focus.events[3].at, date("2026-11-15T06:16:33.983Z"))
        #expect(focus.activeSeconds == 77 && focus.pausedSeconds == 6 && focus.overtimeSeconds == 17)
        #expect(focus.outcome == .completed && focus.endedBy == .next)
        #expect(focus.cycleIndex == 1 && focus.source == .timer)

        // The Break that Next started, at the same moment, paused and stopped.
        #expect(rest.kind == .break)
        #expect(rest.sectionName == "Break" && rest.sectionColorHex == "#0A84FF")
        #expect(rest.plannedSeconds == 300)
        expectClose(rest.startedAt, focus.endedAt)
        expectClose(rest.endedAt, date("2026-11-15T06:17:02.017Z"))
        #expect(rest.activeSeconds == 7 && rest.pausedSeconds == 4)
        #expect(rest.outcome == .endedEarly && rest.endedBy == .stop)
        #expect(rest.cycleIndex == nil)

        // A Focus stopped after 12 seconds: the second of the day.
        expectClose(early.startedAt, date("2026-11-15T06:17:11.066Z"))
        #expect(early.activeSeconds == 12)
        #expect(early.outcome == .endedEarly && early.cycleIndex == 2)

        // A stopwatch, paused and resumed: no countdown, so no zero, no overtime.
        #expect(stopwatch.kind == .focus && stopwatch.source == .stopwatch)
        #expect(stopwatch.plannedSeconds == 0)
        expectClose(stopwatch.startedAt, date("2026-11-15T06:17:27.073Z"))
        expectClose(stopwatch.endedAt, date("2026-11-15T06:17:41.513Z"))
        #expect(stopwatch.events.map(\.type) == [.start, .pause, .resume, .stop])
        #expect(stopwatch.activeSeconds == 11 && stopwatch.pausedSeconds == 3 && stopwatch.overtimeSeconds == 0)
        #expect(stopwatch.outcome == .completed && stopwatch.cycleIndex == 3)
        #expect(!stopwatch.countsAsCompletedFocus)

        // A Clock timer that rang: it ends at zero, not when the alarm stopped.
        #expect(clock.kind == .clock && clock.source == .timer)
        #expect(clock.sectionName == "Clock timer" && clock.sectionColorHex == BuiltInSessionTracker.clockColorHex)
        #expect(clock.plannedSeconds == 60)
        expectClose(clock.startedAt, date("2026-11-15T06:18:05.270Z"))
        expectClose(clock.endedAt, date("2026-11-15T06:19:05.270Z"))
        #expect(clock.events.map(\.type) == [.start, .reachedZero, .stop])
        #expect(clock.activeSeconds == 60 && clock.overtimeSeconds == 0)
        #expect(clock.outcome == .completed && clock.cycleIndex == nil)
    }

    // MARK: Cases the run did not cover

    @Test func aClockTimerCancelledEarlyEndsEarly() throws {
        var tracker = makeTracker()
        feed(&tracker, clockTimer(seconds: 60, startedAt: at(0), now: at(0.3), title: "Pasta"), at: at(0.3))
        feed(&tracker, clockTimer(seconds: 60, startedAt: at(0), now: at(20), title: "Pasta"), at: at(20))
        feed(&tracker, idle(), at: at(20.5))

        let record = try #require(log.records.first)
        #expect(record.kind == .clock && record.sectionName == "Pasta")
        expectClose(record.startedAt, at(0))
        expectClose(record.endedAt, at(20.5))
        #expect(record.events.map(\.type) == [.start, .stop])
        #expect(record.outcome == .endedEarly)
    }

    @Test func switchingTheDropletOffEndsTheSessionAsInterrupted() throws {
        var tracker = makeTracker()
        var moment = at(0.4)
        while moment < at(100) {
            feed(&tracker, countdown(startedAt: at(0), now: moment), at: moment)
            moment = moment.addingTimeInterval(0.5)
        }
        let outputs = tracker.end(.interrupt, at: at(100))
        log.apply(outputs)

        let record = try #require(log.records.first)
        #expect(outputs.last == .checkpoint(nil))
        #expect(record.outcome == .interrupted && record.endedBy == .interrupt)
        #expect(record.activeSeconds == 100)
        #expect(tracker.end(.interrupt, at: at(101)).isEmpty)
    }

    @Test func switchingOffAfterAGapEndsWhereItWasLastSeen() throws {
        var tracker = makeTracker()
        feed(&tracker, countdown(startedAt: at(0), now: at(0.4)), at: at(0.4))
        // Reading stopped working; the droplet is switched off an hour later.
        log.apply(tracker.end(.interrupt, at: at(3600)))

        let record = try #require(log.records.first)
        expectClose(record.endedAt, at(0.4))
        #expect(record.outcome == .interrupted)
    }

    @Test func aSessionCutOffByAQuitIsRecoveredFromItsCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pomodorolog-tracker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        store.load()

        // Droppy quits 75 seconds in; the last checkpoint was the heartbeat at 60.
        var tracker = makeTracker()
        var moment = at(0.4)
        while moment <= at(75) {
            for output in tracker.observe(countdown(startedAt: at(0), now: moment), at: moment) {
                if case .checkpoint(let session) = output { store.checkpoint(session) }
            }
            moment = moment.addingTimeInterval(0.5)
        }

        let reopened = SessionStore(directory: directory)
        reopened.load()
        let record = try #require(reopened.recoverInterruptedSession(dropletVersion: "test"))
        expectClose(record.startedAt, at(0))
        #expect(abs(record.endedAt.timeIntervalSince(at(60.4))) < 0.001)
        #expect(record.outcome == .interrupted)
    }

    @Test func aSessionAlreadyRunningWhenTheDropletStartsIsPickedUpFromItsStart() throws {
        var tracker = makeTracker()
        // First reading: 20 seconds into a 1-minute Focus.
        feed(&tracker, countdown(minutes: 1, startedAt: at(0), now: at(20)), at: at(20))
        let session = try #require(tracker.active)
        expectClose(session.startedAt, at(0))
        #expect(session.events.map(\.type) == [.start])
    }

    @Test func aSessionFirstSeenPausedCountsWhatHasRun() throws {
        var tracker = makeTracker()
        feed(&tracker, countdown(minutes: 1, startedAt: at(0), now: at(50), pausedRemaining: 30), at: at(50))
        let session = try #require(tracker.active)
        expectClose(session.startedAt, at(20))
        #expect(session.events.map(\.type) == [.start, .pause])

        var moment = at(50.5)
        while moment < at(60) {
            feed(&tracker, countdown(minutes: 1, startedAt: at(0), now: moment, pausedRemaining: 30), at: moment)
            moment = moment.addingTimeInterval(0.5)
        }
        feed(&tracker, idle(), at: at(60))
        let record = try #require(log.records.first)
        #expect(record.activeSeconds == 30 && record.pausedSeconds == 10)
    }

    @Test func aStopFoundAfterAGapEndsWhereItWasLastSeen() throws {
        var tracker = makeTracker()
        feed(&tracker, countdown(startedAt: at(0), now: at(0.4)), at: at(0.4))
        feed(&tracker, countdown(startedAt: at(0), now: at(0.9)), at: at(0.9))
        // No readings for a minute (a read that failed), then it has stopped.
        feed(&tracker, idle(), at: at(60.9))

        let record = try #require(log.records.first)
        expectClose(record.endedAt, at(0.9))
    }

    @Test func aRunningSessionReachesTheDiskEveryThirtySeconds() throws {
        var tracker = makeTracker()
        var moment = at(0.4)
        while moment <= at(65) {
            feed(&tracker, countdown(startedAt: at(0), now: moment), at: moment)
            moment = moment.addingTimeInterval(0.5)
        }
        // The start, then a heartbeat at 30.4 and at 60.4.
        #expect(log.checkpointCount == 3)
        expectClose(try #require(log.checkpoint).lastSeenAt, at(60.4))

        // A paused session has nothing new to say.
        let before = log.checkpointCount
        moment = at(65.4)
        feed(&tracker, countdown(startedAt: at(0), now: moment, pausedRemaining: 1435), at: moment)
        while moment <= at(130) {
            moment = moment.addingTimeInterval(0.5)
            feed(&tracker, countdown(startedAt: at(0), now: moment, pausedRemaining: 1435), at: moment)
        }
        #expect(log.checkpointCount == before + 1)
    }

    @Test func startingAnotherLengthStopsTheOldSession() throws {
        var tracker = makeTracker()
        feed(&tracker, countdown(minutes: 25, startedAt: at(0), now: at(0.4)), at: at(0.4))
        feed(&tracker, countdown(minutes: 50, startedAt: at(10), now: at(10.4)), at: at(10.4))

        let record = try #require(log.records.first)
        #expect(record.endedBy == .stop && record.outcome == .endedEarly)
        expectClose(record.endedAt, at(10))
        let next = try #require(tracker.active)
        #expect(next.plannedSeconds == 3000)
        expectClose(next.startedAt, at(10))
        #expect(next.cycleIndex == 2)
    }

    @Test func aStopwatchStartedWithBreakSelectedIsFocus() throws {
        // What Droppy 16.0.1 showed in 2.0.0's first run: Break still
        // selected from the session before, the stopwatch a focus session.
        var tracker = makeTracker()
        var stopwatch = idle(selected: "break", minutes: 5)
        stopwatch.isActive = true
        stopwatch.runMode = "stopwatch"
        stopwatch.sessionKind = "focus"
        stopwatch.stopwatchStartTime = at(0)
        feed(&tracker, stopwatch, at: at(0.4))
        feed(&tracker, idle(selected: "break", minutes: 5), at: at(10.4))

        let record = try #require(log.records.first)
        #expect(record.kind == .focus && record.source == .stopwatch)
        #expect(record.sectionID == "focus" && record.sectionName == "Focus" && record.sectionColorHex == "#FF9500")
    }

    @Test func choosingWhatToStartNextLogsNothing() {
        var tracker = makeTracker()
        var outputs: [BuiltInSessionTracker.Output] = []
        outputs += feed(&tracker, idle(selected: "focus", minutes: 25), at: at(0))
        outputs += feed(&tracker, idle(selected: "focus", minutes: 1), at: at(1))
        outputs += feed(&tracker, idle(selected: "break", minutes: 5), at: at(2))
        #expect(outputs.isEmpty)
        #expect(log.records.isEmpty)
    }
}
