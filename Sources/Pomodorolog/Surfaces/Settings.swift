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
    static let stickerBookPageID = "stickers"

    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(PomodoroSettings(droplet: self))
    }

    public func makeSettingsPage(id: String, context: SettingsPaneContext) -> AnyView? {
        switch id {
        case Self.historyPageID: AnyView(HistoryPage(droplet: self))
        case Self.stickerBookPageID: AnyView(StickerBookPage(droplet: self))
        default: nil
        }
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Droppy's Pomodoro", keywords: ["pomodoro", "timer", "logging", "status"]),
            SettingsSearchEntry(title: "Summit", keywords: ["climb", "mountain", "peak", "tomato", "jar", "break bonus"]),
            SettingsSearchEntry(title: "How the climb works", keywords: ["rules", "metres", "meters", "minute", "break bonus", "tomato", "jar", "peaks"]),
            SettingsSearchEntry(title: "Sticker book", keywords: ["stickers", "badges", "achievements"]),
            SettingsSearchEntry(title: "Notch moments", keywords: ["notification", "hud", "summit", "sticker", "jar", "preview"]),
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
                settingsSectionHeader("Summit")
            } content: {
                SummitSettings(droplet: droplet)
            }

            DropletSettingsSection {
                settingsSectionHeader("How the climb works")
            } content: {
                ClimbRulesSettings()
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
                        icon: SettingsTiles.history
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

/// The climb, the sticker book and the notch moments.
private struct SummitSettings: View {
    @ObservedObject var droplet: PomodorologDroplet

    var body: some View {
        let rewards = droplet.rewards
        DropletSettingsCard {
            DropletControlRow(
                title: "Climbing",
                infoTip: "The peak you're climbing now, and how far up it you are. Pick a climb in the expedition log."
            ) {
                DropletValuePill(text: Self.climbing(rewards.climb))
            }
            DropletSettingsPageLink(
                "Sticker book",
                subtitle: "\(rewards.stickers.count) of \(Stickers.all.count) found.",
                page: PomodorologDroplet.stickerBookPageID,
                icon: SettingsTiles.stickerBook
            )
            DropletControlRow(
                title: "Notch moments",
                infoTip: "A filled jar, a summit and a new sticker show in the notch when the session that earned them is logged, once the shelf is closed."
            ) {
                Button("Preview") { droplet.previewMoments() }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
        }
    }

    /// `Mont Blanc · 52%`, `Mont Blanc · summit` once its top is reached, or
    /// `No climb picked`.
    static func climbing(_ climb: Climb) -> String {
        guard let latest = climb.latest else { return "No climb picked" }
        guard !latest.isSummited else { return "\(latest.peak.name) · summit" }
        return "\(latest.peak.name) · \(Int((latest.fraction * 100).rounded(.down)))%"
    }
}

/// The rules of the climb, a row each: the number at a glance, the whole
/// definition behind the row's (i).
private struct ClimbRulesSettings: View {
    var body: some View {
        DropletSettingsCard {
            DropletControlRow(title: "Focus", infoTip: ClimbGuide.focusTip) {
                DropletValuePill(text: ClimbGuide.focusValue)
            }
            DropletControlRow(title: "Break bonus", infoTip: ClimbGuide.bonusTip) {
                DropletValuePill(text: ClimbGuide.bonusValue)
            }
            DropletControlRow(title: "Tomato", infoTip: ClimbGuide.tomatoTip) {
                DropletValuePill(text: ClimbGuide.tomatoValue)
            }
            DropletControlRow(title: "Jar", infoTip: ClimbGuide.jarTip) {
                DropletValuePill(text: ClimbGuide.jarValue)
            }
            DropletControlRow(title: "Peaks", infoTip: ClimbGuide.peaksTip) {
                DropletValuePill(text: ClimbGuide.peaksValue)
            }
        }
    }
}

/// The climb's rules in words, built from the numbers the climb is worked out
/// with, so the two can't drift apart.
enum ClimbGuide {
    private static var perMinute: Int { Int(ClimbRules.metresPerMinute) }
    private static var bonusPercent: Int { Int((ClimbRules.breakBonus * 100).rounded()) }
    /// A 25-minute focus, without and with the break bonus.
    private static var example: Int { 25 * perMinute }
    private static var boosted: Int { Int((Double(example) * (1 + ClimbRules.breakBonus)).rounded()) }

    static var focusValue: String { "\(perMinute) m a minute" }
    static var focusTip: String {
        "Every minute of focus climbs \(perMinute) m, so a 25-minute focus climbs \(example) m. "
            + "A countdown climbs up to the length you set; time past zero doesn't count. "
            + "A stopwatch run climbs at most \(ClimbRules.stopwatchCapSeconds / 60) minutes. "
            + "Breaks don't climb on their own."
    }

    static var bonusValue: String { "+\(bonusPercent)%" }
    static var bonusTip: String {
        "A focus that starts from a finished break climbs \(bonusPercent)% further: \(boosted) m instead of \(example). "
            + "The break has to follow a focus, run to zero and end no more than "
            + "\(ClimbRules.breakOvertimeAllowance / 60) minutes past it, and the next focus has to start within "
            + "\(Int(ClimbRules.handoverSeconds / 60)) minutes, as pressing Next does. "
            + "The bonus is for that one focus and never stacks."
    }

    static let tomatoValue = "A focus run to zero"
    static let tomatoTip = "Each focus that runs to zero leaves a tomato on the trail. "
        + "A focus stopped early, or a stopwatch run, still climbs but leaves no tomato."

    static var jarValue: String { "\(Pantry.tomatoesPerJar) tomatoes" }
    static var jarTip: String {
        let n = Pantry.tomatoesPerJar
        return "Every \(n)th tomato of a day fills a jar: the \(n)th, \(2 * n)th, \(3 * n)th and so on. "
            + "Tomatoes don't carry over to the next day."
    }

    static var peaksValue: String { "\(Peaks.all.count) peaks, any order" }
    static var peaksTip: String {
        let peaks = Peaks.all.map { peak in
            let height = "\(peak.name) \(SummitWidgetModel.metres(peak.height)) m"
            return peak.region == "Mars" ? "\(height) on Mars" : height
        }
        return "\(NotchMoments.list(peaks)). "
            + "Pick one in the expedition log to start climbing it from its foot. Focus climbs only while a climb is picked. "
            + "A climb ends at the top, and anything past it is dropped; then pick the next, or the same peak again. "
            + "Switching to another peak part of the way up clears the climb you leave."
    }
}

/// Every sticker. Each peak's sticker first, in a group of their own, since
/// they count every time a top is reached; then the stickers earned once: the
/// ones found and when, then the rest as a question mark and a hint.
private struct StickerBookPage: View {
    @ObservedObject var droplet: PomodorologDroplet

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: DroppySpacing.xsm, alignment: .top)]

    var body: some View {
        let rewards = droplet.rewards
        let held = Dictionary(rewards.stickers.map { ($0.sticker.id, $0) }, uniquingKeysWith: { first, _ in first })
        let summits = Stickers.all.filter { $0.peak != nil }
        let earned = rewards.stickers.filter { $0.sticker.peak == nil }
        let found = Set(earned.map(\.sticker.id))
        let onceOnly = Stickers.all.filter { $0.peak == nil }
        let locked = onceOnly.filter { !found.contains($0.id) }

        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Summits, \(summits.filter { held[$0.id] != nil }.count) of \(summits.count)")
            } content: {
                DropletSettingsCard {
                    VStack(alignment: .leading, spacing: DroppySpacing.md) {
                        LazyVGrid(columns: columns, alignment: .center, spacing: DroppySpacing.mdl) {
                            ForEach(summits) { sticker in
                                SummitCell(
                                    sticker: sticker,
                                    count: held[sticker.id]?.count ?? 0,
                                    latest: rewards.climb.summits.last { $0.peakIndex == sticker.peak }?.date
                                )
                            }
                        }
                        Text("Each top's sticker counts every time you reach it.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DroppySpacing.mdl)
                    .padding(.horizontal, DroppySpacing.smd)
                }
            }
            DropletSettingsSection {
                settingsSectionHeader("Stickers, \(earned.count) of \(onceOnly.count)")
            } content: {
                DropletSettingsCard {
                    LazyVGrid(columns: columns, alignment: .center, spacing: DroppySpacing.mdl) {
                        ForEach(earned, id: \.sticker.id) { item in
                            StickerCell(sticker: item.sticker, foundOn: item.date)
                        }
                        ForEach(locked) { sticker in
                            StickerCell(sticker: sticker, foundOn: nil)
                        }
                    }
                    .padding(.vertical, DroppySpacing.mdl)
                    .padding(.horizontal, DroppySpacing.smd)
                }
            }
        }
    }
}

/// One sticker in the book: its disc and name and when it was found, or a
/// question mark and its hint until then. Hovering shows what earns it, in a
/// popover like the one behind a row's (i).
private struct StickerCell: View {
    let sticker: Sticker
    /// Nil while it hasn't been found.
    let foundOn: Date?

    @State private var showsRule = false

    var body: some View {
        let isFound = foundOn != nil
        VStack(spacing: DroppySpacing.xsm) {
            StickerDisc(sticker: isFound ? sticker : nil, size: 42, onShelf: false)
            Text(verbatim: isFound ? sticker.name : sticker.hint)
                .font(.system(size: 12, weight: isFound ? .medium : .regular))
                .foregroundStyle(isFound ? .primary : .tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let foundOn {
                Text(verbatim: foundOn.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { showsRule = $0 }
        .popover(isPresented: $showsRule, arrowEdge: .top) {
            Text(verbatim: sticker.rule)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 220, alignment: .leading)
                .padding(DroppySpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(sticker.rule)
    }
}

/// A peak's sticker in the book: its symbol, coloured once its top has been
/// reached and greyed until then, with how many times and when last.
private struct SummitCell: View {
    let sticker: Sticker
    /// How many times its top has been reached.
    let count: Int
    /// When last.
    let latest: Date?

    @State private var showsRule = false

    var body: some View {
        let isFound = count > 0
        VStack(spacing: DroppySpacing.xsm) {
            StickerDisc(sticker: isFound ? sticker : nil, size: 42, onShelf: false, lockedPeak: sticker.peak)
                .overlay(alignment: .bottomTrailing) {
                    if count > 1 {
                        StickerCount(count: count, ring: nil)
                            .offset(x: 9, y: 3)
                    }
                }
            Text(verbatim: sticker.name)
                .font(.system(size: 12, weight: isFound ? .medium : .regular))
                .foregroundStyle(isFound ? .primary : .tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if isFound, let latest {
                Text(verbatim: latest.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { showsRule = $0 }
        .popover(isPresented: $showsRule, arrowEdge: .top) {
            Text(verbatim: ruleText)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 220, alignment: .leading)
                .padding(DroppySpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(ruleText)
    }

    /// `The top of Ben Nevis. Reached twice.`
    private var ruleText: String {
        switch count {
        case 0: sticker.rule
        case 1: "\(sticker.rule) Reached once."
        case 2: "\(sticker.rule) Reached twice."
        default: "\(sticker.rule) Reached \(count) times."
        }
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
