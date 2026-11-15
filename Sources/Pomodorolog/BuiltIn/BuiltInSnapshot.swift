//
//  BuiltInSnapshot.swift
//  Pomodorolog
//
//  One reading of Droppy's own Pomodoro: a plain copy of the fields of its
//  `PomodoroManager`, taken by `BuiltInPomodoroReader`. Foundation only, so
//  everything built on it can be tested without Droppy.
//

import Foundation

struct BuiltInSnapshot: Equatable, Sendable {
    /// One of the built-in's sections: Focus, Break, or one the user added.
    struct Section: Equatable, Sendable {
        var id: String
        var name: String
        var colorHex: String
    }

    /// The section and length a countdown was started with.
    struct Selection: Equatable, Sendable {
        var sectionID: String
        var minutes: Int
    }

    /// A session is running; a paused one counts.
    var isActive: Bool
    var isPaused: Bool
    /// The countdown has passed zero and is counting up.
    var isOvertime: Bool
    /// `countdown` or `stopwatch`.
    var runMode: String
    /// `focus` or `break`.
    var sessionKind: String
    /// `local` for the built-in's own timer, `appleClock` for one started in
    /// the Clock app or with Siri that the built-in mirrors.
    var provenance: String
    var activeSelection: Selection?
    /// What the widget has picked for the next start.
    var selectedSectionID: String
    var selectedMinutes: Int
    /// Ticks every second while a countdown runs.
    var remainingSeconds: Int
    var totalDurationSeconds: Double
    var endTime: Date?
    var pausedRemainingSeconds: Int?
    var pausedOvertimeSeconds: Int?
    var stopwatchStartTime: Date?
    var stopwatchPausedElapsedSeconds: Int?
    var completedSessions: Int
    var focusTitle: String?
    var nativeTimerID: String?
    var nativeTimerTitle: String?
    var nativeTimerDeadline: Date?
    var sections: [Section]

    /// Whether anything changed apart from the once-a-second countdown.
    func differsMeaningfully(from other: BuiltInSnapshot) -> Bool {
        var mine = self
        mine.remainingSeconds = other.remainingSeconds
        return mine != other
    }
}
