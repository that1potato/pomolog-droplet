import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite final class SessionStoreTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pomodorolog-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> SessionStore {
        let store = SessionStore(directory: directory)
        store.load()
        return store
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    /// A finished focus session starting at `start`.
    private func record(
        start: Date,
        minutes: Int = 25,
        kind: SessionKind = .focus,
        outcome: SessionOutcome = .completed,
        utcOffset: Int = 0
    ) -> SessionRecord {
        let planned = minutes * 60
        let end = start.addingTimeInterval(TimeInterval(planned))
        return SessionRecord(
            id: UUID(),
            kind: kind,
            sectionID: kind == .focus ? "focus" : "break",
            sectionName: kind == .focus ? "Focus" : "Break",
            sectionColorHex: kind == .focus ? "#FF9500" : "#0A84FF",
            plannedSeconds: planned,
            startedAt: start,
            endedAt: end,
            timeZoneID: "GMT",
            utcOffsetSeconds: utcOffset,
            events: [
                SessionEvent(type: .start, at: start),
                SessionEvent(type: .reachedZero, at: end),
                SessionEvent(type: .stop, at: end),
            ],
            activeSeconds: planned,
            pausedSeconds: 0,
            overtimeSeconds: 0,
            outcome: outcome,
            endedBy: .stop,
            cycleIndex: kind == .focus ? 1 : nil,
            title: nil,
            note: nil,
            tags: [],
            source: .timer,
            dropletVersion: "test"
        )
    }

    /// 2026-03-01 12:00:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_772_366_400)

    private func running(start: Date, minutes: Int = 25) -> ActiveSession {
        ActiveSession(
            id: UUID(),
            kind: .focus,
            sectionID: "focus",
            sectionName: "Focus",
            sectionColorHex: "#FF9500",
            plannedSeconds: minutes * 60,
            startedAt: start,
            timeZoneID: "GMT",
            utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: start)],
            cycleIndex: 1,
            title: nil,
            lastSeenAt: start
        )
    }

    // MARK: Reading and writing

    @Test func theLogSurvivesARoundTrip() throws {
        let store = makeStore()
        #expect(store.sessions.isEmpty)
        let first = record(start: noon.addingTimeInterval(0.25))
        let second = record(start: noon.addingTimeInterval(3600), kind: .break)
        store.append(first)
        store.append(second)

        let reloaded = makeStore()
        #expect(reloaded.sessions == [first, second])
        #expect(reloaded.lastError == nil)

        // The file is the documented shape, with millisecond timestamps.
        let text = try String(contentsOf: store.logURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(text.contains("2026-03-01T12:00:00.250Z"))
    }

    @Test func appendingTheSameSessionTwiceKeepsOneCopy() throws {
        let store = makeStore()
        var session = record(start: noon)
        store.append(session)
        session.title = "Write the report"
        store.append(session)
        #expect(store.sessions.count == 1)
        #expect(makeStore().sessions.first?.title == "Write the report")
    }

    @Test func aDamagedLogFallsBackToTheBackup() throws {
        let store = makeStore()
        let first = record(start: noon)
        store.append(first)
        store.append(record(start: noon.addingTimeInterval(3600)))
        // The backup now holds the log as it was after the first append.
        try Data("not json".utf8).write(to: store.logURL)

        let reloaded = makeStore()
        #expect(reloaded.sessions == [first])
        // The damaged file was kept, not overwritten.
        #expect(files().contains { $0.hasPrefix("sessions.unreadable-") })
        // And the log is readable again.
        #expect(makeStore().sessions == [first])
    }

    @Test func nothingIsDeletedWhenBothFilesAreDamaged() throws {
        let store = makeStore()
        store.append(record(start: noon))
        store.append(record(start: noon.addingTimeInterval(3600)))
        try Data("broken".utf8).write(to: store.logURL)
        try Data("also broken".utf8).write(to: store.backupURL)

        let reloaded = makeStore()
        #expect(reloaded.sessions.isEmpty)
        let kept = files().filter { $0.contains("unreadable") }
        #expect(kept.count == 2)

        // New sessions go into a fresh log beside the kept files.
        reloaded.append(record(start: noon.addingTimeInterval(7200)))
        #expect(makeStore().sessions.count == 1)
        #expect(files().filter { $0.contains("unreadable") }.count == 2)
    }

    @Test func aLogFromANewerVersionIsLeftAlone() throws {
        let newer = #"{"schemaVersion": 99, "sessions": []}"#
        try Data(newer.utf8).write(to: directory.appendingPathComponent("sessions.json"))

        let store = makeStore()
        #expect(store.sessions.isEmpty)
        let kept = try #require(files().first { $0.hasPrefix("sessions.unreadable-") })
        let text = try String(contentsOf: directory.appendingPathComponent(kept), encoding: .utf8)
        #expect(text == newer)
    }

    @Test func aVersionOneLogReadsAndIsRewrittenAsVersionTwo() throws {
        let first = record(start: noon)
        let old = SessionLogDocument(schemaVersion: 1, sessions: [first])
        try SessionStore.encoder.encode(old).write(to: directory.appendingPathComponent("sessions.json"))

        let store = makeStore()
        #expect(store.sessions == [first])
        store.append(record(start: noon.addingTimeInterval(3600)))
        let text = try String(contentsOf: store.logURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(makeStore().sessions.count == 2)
    }

    // MARK: Droppy's own Pomodoro

    @Test func stopwatchRunsAndClockTimersCountOnlyWhereTheyShould() throws {
        let store = makeStore()
        let countdown = record(start: noon, minutes: 25)
        var stopwatch = record(start: noon.addingTimeInterval(3600), minutes: 10)
        stopwatch.source = .stopwatch
        stopwatch.overtimeSeconds = 0
        let clock = record(start: noon.addingTimeInterval(7200), minutes: 5, kind: .clock)
        let rest = record(start: noon.addingTimeInterval(9000), minutes: 5, kind: .break)
        for session in [countdown, stopwatch, clock, rest] { store.append(session) }

        let day = store.summary(forDay: "2026-03-01")
        #expect(day.completedFocusCount == 1)
        #expect(day.focusSeconds == 35 * 60)
        #expect(day.breakSeconds == 5 * 60)
        #expect(store.totals().completedFocusCount == 1)
        #expect(store.totals().focusSeconds == 35 * 60)
        #expect(store.streak(today: "2026-03-01") == 1)
    }

    @Test func aDayWithOnlyAStopwatchRunKeepsNoStreak() throws {
        let store = makeStore()
        var stopwatch = record(start: noon, minutes: 10)
        stopwatch.source = .stopwatch
        store.append(stopwatch)
        store.append(record(start: noon.addingTimeInterval(3600), minutes: 5, kind: .clock))

        #expect(store.streak(today: "2026-03-01") == 0)
        #expect(store.summary(forDay: "2026-03-01").completedFocusCount == 0)
    }

    // MARK: Interrupted sessions

    @Test func aSessionLeftRunningIsClosedWhereItWasLastSeen() throws {
        let store = makeStore()
        var session = running(start: noon)
        session.lastSeenAt = noon.addingTimeInterval(300)
        store.checkpoint(session)
        #expect(FileManager.default.fileExists(atPath: store.activeURL.path))

        // Droppy quit; the next launch finds the checkpoint.
        let next = makeStore()
        let record = try #require(next.recoverInterruptedSession(dropletVersion: "test"))
        #expect(record.id == session.id)
        #expect(record.outcome == .interrupted)
        #expect(record.endedBy == .interrupt)
        #expect(record.activeSeconds == 300)
        #expect(record.endedAt == noon.addingTimeInterval(300))
        #expect(record.events.map(\.type) == [.start, .interrupt])
        #expect(!FileManager.default.fileExists(atPath: next.activeURL.path))
        #expect(makeStore().sessions == [record])
        // Nothing left to recover the second time.
        #expect(next.recoverInterruptedSession(dropletVersion: "test") == nil)
    }

    @Test func aSessionLeftPausedEndsAtItsPause() throws {
        let store = makeStore()
        var session = running(start: noon)
        session.events.append(SessionEvent(type: .pause, at: noon.addingTimeInterval(120)))
        session.lastSeenAt = noon.addingTimeInterval(120)
        store.checkpoint(session)

        let record = try #require(store.recoverInterruptedSession(dropletVersion: "test"))
        #expect(record.endedAt == noon.addingTimeInterval(120))
        #expect(record.activeSeconds == 120)
        #expect(record.pausedSeconds == 0)
        #expect(record.outcome == .interrupted)
    }

    @Test func aSessionInterruptedInOvertimeCountsAsCompleted() throws {
        let store = makeStore()
        var session = running(start: noon, minutes: 1)
        session.lastSeenAt = noon.addingTimeInterval(200)
        store.checkpoint(session)

        let record = try #require(store.recoverInterruptedSession(dropletVersion: "test"))
        #expect(record.outcome == .completed)
        #expect(record.endedBy == .interrupt)
        #expect(record.overtimeSeconds == 140)
        #expect(record.events.map(\.type) == [.start, .reachedZero, .interrupt])
    }

    @Test func clearingTheCheckpointRemovesTheFile() throws {
        let store = makeStore()
        store.checkpoint(running(start: noon))
        store.checkpoint(nil)
        #expect(!FileManager.default.fileExists(atPath: store.activeURL.path))
        #expect(store.recoverInterruptedSession(dropletVersion: "test") == nil)
    }

    // MARK: Days

    @Test func aSessionBelongsToTheDayItStartedWhereItStarted() throws {
        // 23:30 UTC on 1 March.
        let late = noon.addingTimeInterval(11.5 * 3600)
        #expect(record(start: late, utcOffset: 0).localDay == "2026-03-01")
        // Tokyo is already on the 2nd; Los Angeles is still on the 1st.
        #expect(record(start: late, utcOffset: 9 * 3600).localDay == "2026-03-02")
        #expect(record(start: late, utcOffset: -8 * 3600).localDay == "2026-03-01")
        // 00:30 UTC on 2 March is still the 1st in Los Angeles.
        let early = late.addingTimeInterval(3600)
        #expect(record(start: early, utcOffset: 0).localDay == "2026-03-02")
        #expect(record(start: early, utcOffset: -8 * 3600).localDay == "2026-03-01")
    }

    @Test func summariesGroupByDayNewestFirst() throws {
        let store = makeStore()
        let day = 86_400.0
        store.append(record(start: noon))
        store.append(record(start: noon.addingTimeInterval(1800), kind: .break))
        store.append(record(start: noon.addingTimeInterval(3600), outcome: .endedEarly))
        store.append(record(start: noon.addingTimeInterval(day)))

        let summaries = store.daySummaries()
        #expect(summaries.map(\.day) == ["2026-03-02", "2026-03-01"])
        let first = try #require(summaries.last)
        #expect(first.sessions.count == 3)
        #expect(first.completedFocusCount == 1)
        #expect(first.focusSeconds == 3000)
        #expect(first.breakSeconds == 1500)
        #expect(first.sessions.first?.startedAt == noon.addingTimeInterval(3600))

        #expect(store.focusSessionCount(onDay: "2026-03-01") == 2)
        #expect(store.summary(forDay: "2026-02-27").sessions.isEmpty)

        let totals = store.totals()
        #expect(totals.sessionCount == 4)
        #expect(totals.completedFocusCount == 2)
        #expect(totals.focusSeconds == 4500)
        #expect(totals.dayCount == 2)
    }

    @Test func theStreakCountsBackThroughConsecutiveDays() throws {
        let store = makeStore()
        let day = 86_400.0
        #expect(store.streak(today: "2026-03-05") == 0)

        // 1, 2 and 3 March; a break and an unfinished session do not count.
        store.append(record(start: noon))
        store.append(record(start: noon.addingTimeInterval(day)))
        store.append(record(start: noon.addingTimeInterval(2 * day)))
        store.append(record(start: noon.addingTimeInterval(3 * day), kind: .break))
        store.append(record(start: noon.addingTimeInterval(3 * day), outcome: .endedEarly))

        #expect(store.streak(today: "2026-03-03") == 3)
        // Nothing completed yet on the 4th: yesterday's streak still stands.
        #expect(store.streak(today: "2026-03-04") == 3)
        // A whole day missed breaks it.
        #expect(store.streak(today: "2026-03-05") == 0)

        // Across a month boundary.
        #expect(LocalDay.previous("2026-03-01") == "2026-02-28")
        #expect(LocalDay.previous("2026-01-01") == "2025-12-31")
    }

    // MARK: Export

    @Test func csvQuotesWhatNeedsQuoting() throws {
        let store = makeStore()
        var session = record(start: noon)
        session.title = "Draft, then \"review\""
        session.tags = ["writing", "q1"]
        store.append(session)

        let lines = store.csv().split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("id,day,kind,section,planned_seconds"))
        #expect(lines[1].contains("2026-03-01,focus,Focus,1500,2026-03-01T12:00:00.000Z"))
        #expect(lines[1].contains("\"Draft, then \"\"review\"\"\""))
        #expect(lines[1].contains("writing;q1"))

        let url = try store.writeCSVExport(now: noon)
        #expect(url.pathExtension == "csv")
        #expect(try String(contentsOf: url, encoding: .utf8) == store.csv())
    }
}
