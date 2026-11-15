import Foundation
import Testing
@testable import Pomodorolog

// Droppy 16.0.1's PomodoroManager, as far as the reader looks: the same field
// names and types, with the underscored storage `@Observable` gives them.

private enum FakeSessionKind: String { case focus, `break` }
/// No raw value: read by its case name.
private enum FakeRunMode { case countdown, stopwatch }
private enum FakeProvenance: String { case local, appleClock }
private struct FakeSelection { var sectionID: String; var minutes: Int }
private struct FakeSection { var id: String; var name: String; var colorHex: String; var timers: [Int]; var order: Int }

private final class FakePomodoroManager {
    var _isInstalled = true
    var _isEnabled = true
    var _isActive = true
    var _remainingSeconds = 42
    var _sections = [
        FakeSection(id: "focus", name: "Focus", colorHex: "#FF9500", timers: [5, 10, 15, 25, 50], order: 0),
        FakeSection(id: "break", name: "Break", colorHex: "#0A84FF", timers: [5, 10, 15], order: 1),
    ]
    var _activeSelection: FakeSelection? = FakeSelection(sectionID: "focus", minutes: 25)
    var _sessionKind = FakeSessionKind.focus
    var _focusTitle: String? = "Write the plan"
    var _runMode = FakeRunMode.countdown
    var _isPaused = false
    var _isOvertime = false
    var _completedSessions = 2
    var _timerProvenance = FakeProvenance.local
    var _totalDurationSeconds: Double = 1500
    var _nativeTimerID: String?
    var _nativeTimerTitle: String?
    var _nativeTimerDeadline: Date?
    var _selectedSectionID = "focus"
    var _selectedMinutes = 25
    var _timer: Timer?
    var _endTime: Date? = Date(timeIntervalSince1970: 1_780_001_500)
    var _pausedRemainingSeconds: Int?
    var _pausedOvertimeSeconds: Int?
    var _stopwatchStartTime: Date?
    var _stopwatchPausedElapsedSeconds: Int?
    var _lastUsedSectionMinutes = ["focus": 25, "break": 5]
}

/// A Droppy that renamed one field and changed the type of another.
private final class ChangedPomodoroManager {
    var _isActive = true
    var _isPaused = "no"
    var _inOvertime = false
}

@MainActor
@Suite struct BuiltInPomodoroReaderTests {
    @Test func readsEveryFieldTheHookNeeds() throws {
        let reader = BuiltInPomodoroReader()
        let fake = FakePomodoroManager()
        reader.attach(fake)

        let snapshot = try reader.read().get()

        #expect(snapshot == BuiltInSnapshot(
            isActive: true,
            isPaused: false,
            isOvertime: false,
            runMode: "countdown",
            sessionKind: "focus",
            provenance: "local",
            activeSelection: .init(sectionID: "focus", minutes: 25),
            selectedSectionID: "focus",
            selectedMinutes: 25,
            remainingSeconds: 42,
            totalDurationSeconds: 1500,
            endTime: Date(timeIntervalSince1970: 1_780_001_500),
            pausedRemainingSeconds: nil,
            pausedOvertimeSeconds: nil,
            stopwatchStartTime: nil,
            stopwatchPausedElapsedSeconds: nil,
            completedSessions: 2,
            focusTitle: "Write the plan",
            nativeTimerID: nil,
            nativeTimerTitle: nil,
            nativeTimerDeadline: nil,
            sections: [
                .init(id: "focus", name: "Focus", colorHex: "#FF9500"),
                .init(id: "break", name: "Break", colorHex: "#0A84FF"),
            ]
        ))
    }

    @Test func emptyAndFilledOptionalsBothRead() throws {
        let reader = BuiltInPomodoroReader()
        let fake = FakePomodoroManager()
        fake._activeSelection = nil
        fake._runMode = .stopwatch
        fake._timerProvenance = .appleClock
        fake._nativeTimerTitle = "Pasta"
        fake._nativeTimerDeadline = Date(timeIntervalSince1970: 1_780_000_600)
        fake._pausedRemainingSeconds = 30
        fake._focusTitle = nil
        reader.attach(fake)

        let snapshot = try reader.read().get()

        #expect(snapshot.activeSelection == nil)
        #expect(snapshot.runMode == "stopwatch")
        #expect(snapshot.provenance == "appleClock")
        #expect(snapshot.nativeTimerTitle == "Pasta")
        #expect(snapshot.nativeTimerDeadline == Date(timeIntervalSince1970: 1_780_000_600))
        #expect(snapshot.pausedRemainingSeconds == 30)
        #expect(snapshot.focusTitle == nil)
    }

    @Test func aRenamedOrRetypedFieldIsNamedNotGuessed() {
        let reader = BuiltInPomodoroReader()
        let changed = ChangedPomodoroManager()
        reader.attach(changed)

        guard case .failure(.fields(let problems)) = reader.read() else {
            Issue.record("a changed object was read as if nothing had changed")
            return
        }
        #expect(problems.contains("_isOvertime is missing"))
        #expect(problems.contains("_isPaused is Swift.String, not Bool"))
        #expect(!problems.contains { $0.hasPrefix("_isActive") })
    }

    @Test func onlyTheCountdownTickIsNotAChange() throws {
        let reader = BuiltInPomodoroReader()
        let fake = FakePomodoroManager()
        reader.attach(fake)

        let first = try reader.read().get()
        fake._remainingSeconds -= 1
        let ticked = try reader.read().get()
        fake._isPaused = true
        let paused = try reader.read().get()

        #expect(!ticked.differsMeaningfully(from: first))
        #expect(paused.differsMeaningfully(from: ticked))
    }

    @Test func theReaderNeverKeepsTheObjectAlive() {
        let reader = BuiltInPomodoroReader()
        do {
            let fake = FakePomodoroManager()
            reader.attach(fake)
            withExtendedLifetime(fake) {
                #expect(reader.object != nil)
            }
        }
        #expect(reader.object == nil)
        #expect(reader.read() == .failure(.noObject))
    }

    @Test func theInventoryListsEveryFieldWithItsType() {
        let reader = BuiltInPomodoroReader()
        let fake = FakePomodoroManager()
        reader.attach(fake)

        let inventory = reader.inventory()

        #expect(inventory.contains("_isActive: Swift.Bool"))
        #expect(inventory.contains("_endTime: Swift.Optional<Foundation.Date>"))
        #expect(inventory.count == Mirror(reflecting: fake).children.count)
    }
}
