//
//  Settings.swift
//  Pomodorolog
//
//  The droplet's page in Droppy's Settings: whether Droppy's Pomodoro is being
//  logged, the log's totals, and a History page listing every session by day.
//

import DroppyKit
import SwiftUI

extension PomodorologDroplet: SettingsPagesProviding {
    static let historyPageID = "history"

    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(PomodoroSettings(droplet: self))
    }

    public func makeSettingsPage(id: String, context: SettingsPaneContext) -> AnyView? {
        id == Self.historyPageID ? AnyView(HistoryPage(droplet: self)) : nil
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Droppy's Pomodoro", keywords: ["pomodoro", "timer", "logging", "status"]),
            SettingsSearchEntry(title: "History", keywords: ["log", "sessions", "streak", "export", "csv"]),
        ]
    }
}

/// The droplet's settings page. It starts with its first setting: Droppy
/// already draws the icon, name and summary above it.
private struct PomodoroSettings: View {
    @ObservedObject var droplet: PomodorologDroplet

    var body: some View {
        DropletSettingsPane {
            DropletSettingsCard {
                DropletControlRow(
                    title: "Droppy's Pomodoro",
                    icon: "timer",
                    infoTip: "Pomolog reads Droppy's own Pomodoro while it runs and writes every session to the log: countdowns, stopwatch runs and timers from the Clock app. There is no official way to do this, so a Droppy update can stop it until Pomolog is updated."
                ) {
                    DropletValuePill(text: Self.statusText(droplet.hookStatus, session: droplet.session))
                }
                if case .stopped(let reason, let detail) = droplet.hookStatus {
                    DropletStackedRow(title: "Nothing is being logged") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: reason)
                            Text(verbatim: detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Session log")
            } content: {
                DropletSettingsCard {
                    let today = droplet.store?.summary(forDay: droplet.today)
                    let totals = droplet.store?.totals()

                    DropletControlRow(title: "Today") {
                        DropletValuePill(text: Self.focusLine(
                            count: today?.completedFocusCount ?? 0,
                            seconds: today?.focusSeconds ?? 0
                        ))
                    }
                    DropletControlRow(
                        title: "Streak",
                        infoTip: "Days in a row with at least one completed focus session."
                    ) {
                        DropletValuePill(text: TimerFormat.count(
                            droplet.store?.streak(today: droplet.today) ?? 0, "day", "days"
                        ))
                    }
                    DropletControlRow(title: "All time") {
                        DropletValuePill(text: Self.focusLine(
                            count: totals?.completedFocusCount ?? 0,
                            seconds: totals?.focusSeconds ?? 0
                        ))
                    }
                    DropletSettingsPageLink(
                        "History",
                        subtitle: "Every session, by day.",
                        page: PomodorologDroplet.historyPageID,
                        icon: nil
                    )
                    DropletControlRow(
                        title: "Log file",
                        infoTip: "Every session is written to sessions.json. Export makes a CSV copy beside it."
                    ) {
                        HStack(spacing: DroppySpacing.sm) {
                            Button("Reveal in Finder") { droplet.revealLog() }
                                .buttonStyle(DroppyQuietButtonStyle(size: .small))
                            Button("Export CSV") { droplet.exportCSV() }
                                .buttonStyle(DroppyQuietButtonStyle(size: .small))
                        }
                    }
                    if let error = droplet.store?.lastError {
                        DropletControlRow(title: "The log could not be saved") {
                            Text(verbatim: error)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            // Stage 2 of the summit work: the numbers before the widget
            // shows them. Removed once the widget and the log are in.
            DropletSettingsSection {
                settingsSectionHeader("Summit preview")
            } content: {
                SummitPreview(rewards: droplet.rewards)
            }
        }
    }

    /// `Logging`, `Recording Focus`, `Starting`, `Not logging`.
    static func statusText(_ status: PomodorologDroplet.HookStatus, session: ActiveSession?) -> String {
        switch status {
        case .starting: "Starting"
        case .logging: session.map { "Recording \($0.sectionName)" } ?? "Logging"
        case .stopped: "Not logging"
        }
    }

    /// `3 sessions · 1h 15m`.
    static func focusLine(count: Int, seconds: Int) -> String {
        let sessions = TimerFormat.count(count, "session", "sessions")
        return seconds > 0 ? "\(sessions) · \(TimerFormat.duration(seconds: seconds))" : sessions
    }
}

/// The summit numbers for the log, as plain rows. Temporary.
private struct SummitPreview: View {
    let rewards: RewardsSnapshot

    var body: some View {
        let position = rewards.climb.position
        let today = rewards.todayClimb
        let todayPantry = rewards.todayPantry
        DropletSettingsCard {
            DropletControlRow(
                title: "Climbing",
                infoTip: "Focus climbs 10 m for every counted minute, and 20% further when it starts from a finished break."
            ) {
                DropletValuePill(text: Self.climbing(position))
            }
            DropletControlRow(title: "Summits") {
                DropletValuePill(text: Self.summits(rewards.climb.summits))
            }
            DropletControlRow(title: "Today") {
                DropletValuePill(text: "\(TimerFormat.count(todayPantry.tomatoes, "tomato", "tomatoes")) · \(TimerFormat.count(todayPantry.jars, "jar", "jars")) · \(Self.metres(today.metres)) m")
            }
            DropletControlRow(title: "All time") {
                DropletValuePill(text: "\(TimerFormat.count(rewards.pantry.totalTomatoes, "tomato", "tomatoes")) · \(TimerFormat.count(rewards.pantry.totalJars, "jar", "jars")) · \(Self.metres(rewards.climb.total)) m")
            }
            DropletControlRow(title: "From a break") {
                DropletValuePill(text: "\(TimerFormat.count(rewards.sessionsFromBreak, "session", "sessions")) · \(Self.metres(rewards.bonusMetres)) m extra")
            }
            DropletStackedRow(title: "Stickers, \(rewards.stickers.count) of \(Stickers.all.count)") {
                Text(verbatim: rewards.stickers.isEmpty ? "None yet." : rewards.stickers.map(\.sticker.name).joined(separator: ", "))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// `Mont Blanc, 2,529 of 4,808 m`, with the ascent after the first.
    static func climbing(_ position: PeakPosition) -> String {
        let ascent = position.ascent > 1 ? ", ascent \(position.ascent)" : ""
        return "\(position.peak.name), \(metres(position.metres)) of \(metres(position.peak.height)) m\(ascent)"
    }

    /// `2: Ben Nevis, Mount Fuji`, or `None yet`.
    static func summits(_ summits: [Summit]) -> String {
        guard !summits.isEmpty else { return "None yet" }
        let names = summits.suffix(3).map(\.peak.name).joined(separator: ", ")
        return "\(summits.count): \(summits.count > 3 ? "… " : "")\(names)"
    }

    /// Whole metres climbed, grouped: `7,650`. Rounded down, as the widget does.
    static func metres(_ value: Double) -> String {
        Int(value.rounded(.down)).formatted()
    }
}

/// Every session in the log, grouped by day, newest first.
private struct HistoryPage: View {
    @ObservedObject var droplet: PomodorologDroplet

    /// Enough to scroll back through without building thousands of rows.
    private static let dayLimit = 120

    var body: some View {
        let days = droplet.store?.daySummaries() ?? []
        let today = droplet.today

        DropletSettingsPage {
            if days.isEmpty {
                DropletSettingsCard {
                    DropletControlRow(title: "No sessions yet") {
                        Text("Start a timer in Droppy's Pomodoro.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(days.prefix(Self.dayLimit)) { day in
                DropletSettingsSection {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: TimerFormat.dayTitle(day.day, today: today))
                            .font(.headline)
                        Text(verbatim: Self.daySubtitle(day))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                } content: {
                    DropletSettingsCard {
                        ForEach(day.sessions) { session in
                            DropletControlRow(
                                title: "\(TimerFormat.timeRange(session))  \(session.sectionName)",
                                icon: Self.symbol(for: session),
                                iconColor: Color(hex: session.sectionColorHex)
                            ) {
                                DropletValuePill(text: Self.detail(for: session))
                            }
                        }
                    }
                }
            }
            if days.count > Self.dayLimit {
                DropletSettingsCard {
                    DropletControlRow(title: "Older sessions are in the log file") {
                        Button("Reveal in Finder") { droplet.revealLog() }
                            .buttonStyle(DroppyQuietButtonStyle(size: .small))
                    }
                }
            }
        }
    }

    /// `3 focus sessions · 1h 15m focus · 10m break`.
    static func daySubtitle(_ day: DaySummary) -> String {
        var parts = [TimerFormat.count(day.completedFocusCount, "focus session", "focus sessions")]
        if day.focusSeconds > 0 {
            parts.append("\(TimerFormat.duration(seconds: day.focusSeconds)) focus")
        }
        if day.breakSeconds > 0 {
            parts.append("\(TimerFormat.duration(seconds: day.breakSeconds)) break")
        }
        return parts.joined(separator: " · ")
    }

    static func symbol(for session: SessionRecord) -> String {
        if session.kind == .clock { return "timer" }
        switch session.outcome {
        case .completed: return "checkmark.circle.fill"
        case .endedEarly: return "stop.circle"
        case .interrupted: return "exclamationmark.circle"
        }
    }

    /// `25m`, `25m +3m`, `10m of 25m`, `8m, interrupted`, `12m, stopwatch`,
    /// and `10m, Clock timer` for a Clock timer that has a name of its own.
    static func detail(for session: SessionRecord) -> String {
        let active = TimerFormat.duration(seconds: session.activeSeconds)
        if session.source == .stopwatch {
            return session.outcome == .interrupted ? "\(active), stopwatch, interrupted" : "\(active), stopwatch"
        }
        let planned = TimerFormat.duration(seconds: session.plannedSeconds)
        var text: String
        switch session.outcome {
        case .completed:
            text = session.overtimeSeconds >= 60
                ? "\(planned) +\(TimerFormat.duration(seconds: session.overtimeSeconds))"
                : planned
        case .endedEarly:
            text = "\(active) of \(planned)"
        case .interrupted:
            text = "\(active), interrupted"
        }
        if session.kind == .clock, session.sectionName != BuiltInSessionTracker.clockTimerName {
            text += ", Clock timer"
        }
        return text
    }
}
