import Foundation
import Testing
@testable import Pomodorolog

/// How a running session becomes a record, apart from the timer that runs it.
@MainActor
@Suite struct SessionTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000.25)

    private func session(planned: Int, source: SessionSource?, kind: SessionKind = .focus) -> ActiveSession {
        ActiveSession(
            id: UUID(),
            kind: kind,
            sectionID: kind.rawValue,
            sectionName: kind == .focus ? "Focus" : "Break",
            sectionColorHex: kind == .focus ? "#FF9500" : "#0A84FF",
            plannedSeconds: planned,
            startedAt: start,
            timeZoneID: "GMT",
            utcOffsetSeconds: 0,
            events: [SessionEvent(type: .start, at: start)],
            cycleIndex: 1,
            title: nil,
            lastSeenAt: start,
            source: source
        )
    }

    // MARK: Countdowns

    @Test func pausedTimeDoesNotCount() {
        var running = session(planned: 1500, source: nil)
        running.events.append(SessionEvent(type: .pause, at: start.addingTimeInterval(60)))
        // Still paused: the countdown has not moved.
        #expect(running.remainingSeconds(at: start.addingTimeInterval(180)) == 1440)
        #expect(running.isPaused)

        running.events.append(SessionEvent(type: .resume, at: start.addingTimeInterval(180)))
        let now = start.addingTimeInterval(240)
        #expect(running.activeSeconds(at: now) == 120)
        #expect(running.pausedSeconds(at: now) == 120)
        #expect(running.remainingSeconds(at: now) == 1380)
        #expect(!running.isPaused)
    }

    @Test func stoppingBeforeZeroIsEndedEarly() {
        let record = session(planned: 1500, source: nil)
            .finished(at: start.addingTimeInterval(600), reason: .stop, dropletVersion: "test")

        #expect(record.outcome == .endedEarly && record.endedBy == .stop)
        #expect(record.activeSeconds == 600 && record.overtimeSeconds == 0)
        #expect(record.events.map(\.type) == [.start, .stop])
    }

    @Test func zeroCrossedWhileNobodyWasLookingLandsOnTheRightMoment() throws {
        // The Mac slept for two hours through a 1-minute countdown.
        let record = session(planned: 60, source: nil)
            .finished(at: start.addingTimeInterval(7200), reason: .stop, dropletVersion: "test")

        let marker = try #require(record.events.first { $0.type == .reachedZero })
        #expect(marker.at == start.addingTimeInterval(60))
        #expect(record.outcome == .completed)
        #expect(record.activeSeconds == 7200 && record.overtimeSeconds == 7140)
    }

    @Test func zeroFallsAfterThePausesBeforeIt() throws {
        var running = session(planned: 300, source: nil, kind: .break)
        running.events.append(SessionEvent(type: .pause, at: start.addingTimeInterval(120)))
        running.events.append(SessionEvent(type: .resume, at: start.addingTimeInterval(170)))
        // 360 s active of a 300 s break, and nothing marked zero.
        let record = running.finished(at: start.addingTimeInterval(410), reason: .next, dropletVersion: "test")

        #expect(record.events.map(\.type) == [.start, .pause, .resume, .reachedZero, .next])
        let marker = try #require(record.events.first { $0.type == .reachedZero })
        // 120 s ran before the 50 s pause, so zero falls 180 s after the resume.
        #expect(marker.at == start.addingTimeInterval(120 + 50 + 180))
        #expect(record.activeSeconds == 360 && record.pausedSeconds == 50 && record.overtimeSeconds == 60)
        #expect(record.outcome == .completed && record.endedBy == .next && record.kind == .break)
    }

    // MARK: Stopwatch runs

    @Test func aStopwatchRunHasNoZeroAndNoOvertime() {
        let record = session(planned: 0, source: .stopwatch)
            .finished(at: start.addingTimeInterval(600), reason: .stop, dropletVersion: "test")

        #expect(record.events.map(\.type) == [.start, .stop])
        #expect(record.activeSeconds == 600 && record.overtimeSeconds == 0)
        #expect(record.outcome == .completed && record.source == .stopwatch)
        #expect(!record.countsAsCompletedFocus)
    }

    @Test func aStopwatchCutOffIsInterrupted() {
        let record = session(planned: 0, source: .stopwatch)
            .finished(at: start.addingTimeInterval(60), reason: .interrupt, dropletVersion: "test")
        #expect(record.outcome == .interrupted)
    }

    @Test func aCountdownWithoutASourceIsATimer() {
        let record = session(planned: 60, source: nil)
            .finished(at: start.addingTimeInterval(90), reason: .stop, dropletVersion: "test")

        #expect(record.source == .timer)
        #expect(record.events.map(\.type) == [.start, .reachedZero, .stop])
        #expect(record.overtimeSeconds == 30 && record.outcome == .completed)
        #expect(record.countsAsCompletedFocus)
    }

    @Test func endingExactlyAtZeroCompletes() throws {
        let running = session(planned: 60, source: nil)
        let zero = try #require(running.zeroCrossing(before: start.addingTimeInterval(68.273)))
        let record = running.finished(at: zero, reason: .stop, dropletVersion: "test")
        #expect(record.activeSeconds == 60 && record.outcome == .completed)
    }

    @Test func anActiveFileWrittenBeforeStopwatchesStillReads() throws {
        var old = session(planned: 60, source: nil)
        old.source = nil
        let data = try SessionStore.encoder.encode(old)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("\"source\""))

        let decoded = try SessionStore.decoder.decode(ActiveSession.self, from: data)
        #expect(decoded.source == nil)
        #expect(decoded == old)
    }
}
