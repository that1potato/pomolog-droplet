//
//  ExpeditionLog.swift
//  Pomodorolog
//
//  The expedition log: a takeover on the shelf, opened from the summit
//  widget, drawn as an open field journal. The left page is the route, a
//  peak to a row, its icon inked in once climbed and filling as you climb
//  it. The right page is today: the climb split into focus and break bonus,
//  the week's pantry, and the stickers found.
//

import DroppyKit
import SwiftUI

/// How Droppy finds the takeover: it casts the droplet to
/// `ExpandedSurfaceHosting` and reads the provider. Conforming to
/// `ExpandedSurfaceProviding` alone renders in the harness, but Droppy refuses
/// every presentation (LIMITATIONS.md).
extension PomodorologDroplet: ExpandedSurfaceHosting {
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }
}

extension PomodorologDroplet: ExpandedSurfaceProviding {
    static let expeditionLogID: ExpandedSurfaceID = "log"

    /// The content area. The host insets a takeover itself and adds its chrome
    /// around this, so the view draws edge to edge. The header, the notebook
    /// and the ribbon hanging below it.
    static let expeditionLogSize = CGSize(width: 680, height: 418)

    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [
            ExpandedSurfaceDescriptor(
                id: Self.expeditionLogID,
                title: "Expedition log",
                systemImage: "mountain.2.fill",
                suppresses: [.shelfWidgets]
            )
        ]
    }

    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        AnyView(ExpeditionLogView(droplet: self))
    }

    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? {
        CGSize(
            width: min(Self.expeditionLogSize.width, proposal.maximumSize.width),
            height: min(Self.expeditionLogSize.height, proposal.maximumSize.height)
        )
    }

    func openExpeditionLog() {
        guard let host else { return }
        let shown = host.notchSurface.presentExpandedSurface(
            ExpandedSurfacePresentationRequest(surfaceID: Self.expeditionLogID, opensShelf: true)
        ) != nil
        if !shown { diagnose("the expedition log was refused") }
    }

    func closeExpeditionLog() {
        host?.notchSurface.dismissExpandedSurface(Self.expeditionLogID)
    }

    /// Droppy's Settings, on the sticker book.
    func openStickerBook() {
        closeExpeditionLog()
        if host?.workspace.openSettingsPage(Self.stickerBookPageID, title: "Sticker book") == false {
            diagnose("the sticker book page was refused")
        }
    }

    /// When today's first focus started: the log's, or the running focus's.
    var todayStartedAt: Date? {
        let today = today
        if rewards.today == today, let first = rewards.todayStartedAt { return first }
        if let session, session.kind == .focus,
           LocalDay.key(for: session.startedAt, utcOffsetSeconds: session.utcOffsetSeconds) == today {
            return session.startedAt
        }
        return nil
    }
}

/// What the expedition log shows, worked out from the rewards. A plain value,
/// so the wording can be tested.
struct ExpeditionLogModel: Equatable {
    struct WeekDay: Equatable {
        let day: String
        /// M, T, W and so on.
        let letter: String
        let tomatoes: Int
        let isToday: Bool

        var jars: Int { tomatoes / Pantry.tomatoesPerJar }
        var loose: Int { tomatoes % Pantry.tomatoesPerJar }

        /// What the day's column draws, jars at the bottom, at most three so a
        /// long day still fits.
        var shownJars: Int { min(jars, 3) }
        var shownLoose: Int { min(loose, 3 - shownJars) }
    }

    /// A peak on the route page.
    struct RouteRow: Equatable {
        enum State: Equatable {
            /// Its top reached: when the session that reached it last ended,
            /// and how many times.
            case climbed(Date, times: Int)
            /// Being climbed: metres up it so far, and that as a fraction of
            /// its height.
            case current(metres: Double, fraction: Double)
            /// Not climbed to the top yet.
            case ahead
        }

        let index: Int
        let state: State

        var peak: Peak { Peaks.all[index] }

        /// `Scotland · 1,345 m`.
        var detailText: String {
            "\(peak.region) · \(SummitWidgetModel.metres(peak.height)) m"
        }

        /// What a screen reader says for the row.
        var spokenText: String {
            let title = "\(peak.name), \(SummitWidgetModel.metres(peak.height)) metres"
            switch state {
            case .climbed(let date, let times):
                let again = times > 1 ? " \(times) times, last" : ""
                return "\(title), climbed\(again) on \(date.formatted(.dateTime.day().month(.wide)))"
            case .current(let metres, let fraction):
                return "\(title), \(SummitWidgetModel.metres(metres)) climbed, \(Int((fraction * 100).rounded(.down))) percent"
            case .ahead:
                return "\(title), still ahead"
            }
        }
    }

    /// The climb under way, with a running focus's share so far. Nil when
    /// nothing is being climbed.
    let current: Expedition?
    let rows: [RouteRow]
    /// How many peaks' tops have been reached.
    let summitedPeaks: Int
    /// Whether any climb has ever been picked.
    let hasClimbed: Bool
    /// The metres logged on the climb under way: what a switch would clear. A
    /// running focus isn't among them, it counts toward whichever climb is
    /// picked when it ends.
    let loggedMetres: Double
    /// Today's key, for the right page's heading.
    let day: String
    /// Today's climb, with a running focus's share so far.
    let today: DayClimb
    let since: Date?
    let week: [WeekDay]
    let weekTomatoes: Int
    let weekJars: Int
    let weekFromBreak: Int
    let stickers: [EarnedSticker]

    init(rewards: RewardsSnapshot, today: String, live: ClimbStep?, since: Date?) {
        var current = rewards.climb.current
        loggedMetres = current?.metres ?? 0
        if let live, live.expedition != nil, live.expedition == rewards.climb.expeditions.indices.last {
            current?.metres = live.after
        }
        self.current = current
        rows = Self.rows(current: current, summits: rewards.climb.summits)
        summitedPeaks = Set(rewards.climb.summits.map(\.peakIndex)).count
        hasClimbed = !rewards.climb.expeditions.isEmpty
        self.day = today
        var day = rewards.climb.day(today)
        if let live, live.day == today {
            day.focusMetres += live.climbedFocus
            day.bonusMetres += live.climbedBonus
            day.sessions += 1
            if live.startedFromBreak { day.startedFromBreak += 1 }
        }
        self.today = day
        self.since = since
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let days = LocalDay.week(of: today)
        week = days.enumerated().map { index, day in
            WeekDay(day: day, letter: letters[index], tomatoes: rewards.pantry.day(day).tomatoes, isToday: day == today)
        }
        weekTomatoes = week.reduce(0) { $0 + $1.tomatoes }
        weekJars = week.reduce(0) { $0 + $1.jars }
        let inWeek = Set(days)
        weekFromBreak = rewards.climb.steps.filter { $0.startedFromBreak && inWeek.contains($0.day) }.count
        stickers = rewards.stickers
    }

    /// Every peak: the one being climbed, those whose tops were reached
    /// dated by the latest, the rest still to climb.
    static func rows(current: Expedition?, summits: [Summit]) -> [RouteRow] {
        Peaks.all.indices.map { index in
            if let current, current.peakIndex == index {
                return RouteRow(index: index, state: .current(metres: current.metres, fraction: current.fraction))
            }
            let reached = summits.filter { $0.peakIndex == index }
            if let latest = reached.last {
                return RouteRow(index: index, state: .climbed(latest.date, times: reached.count))
            }
            return RouteRow(index: index, state: .ahead)
        }
    }

    /// `2 of 7 climbed`: the peaks whose tops have been reached.
    var climbedText: String { "\(summitedPeaks) of \(Peaks.all.count) climbed" }

    /// Nothing is being climbed, so every peak offers its Climb button.
    var isPicking: Bool { current == nil }

    /// `The route` while a climb is under way, or a nudge to pick one.
    var headingText: String {
        if current != nil { return "The route" }
        return hasClimbed ? "Pick your next climb" : "Pick your first climb"
    }

    /// The question a row asks before leaving the climb under way.
    struct SwitchWarning: Equatable {
        let title: String
        let detail: String
    }

    /// Whether to ask before leaving the climb under way for the peak at
    /// `index`: only when logged metres there would be lost.
    func switchWarning(to index: Int) -> SwitchWarning? {
        guard let current, current.peakIndex != index, loggedMetres > 0 else { return nil }
        return SwitchWarning(title: "Leave \(current.peak.name)?", detail: "Your progress will be lost")
    }

    /// `Sunday, 15 November`, in the Mac's own date style. The key's noon UTC,
    /// formatted in UTC, so no time zone can move it to another day.
    var dateText: String {
        guard let date = LocalDay.date(for: day) else { return "" }
        return date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide).day().month(.wide))
    }

    /// `1,650 m`.
    var todayText: String { "\(SummitWidgetModel.metres(today.metres)) m" }

    /// `since 7:30 AM`, in the Mac's own clock style.
    var sinceText: String? {
        since.map { "since \($0.formatted(date: .omitted, time: .shortened))" }
    }

    var focusText: String { "Focus \(SummitWidgetModel.metres(today.focusMetres)) m" }
    var bonusText: String { "Break bonus \(SummitWidgetModel.metres(today.bonusMetres)) m" }

    /// `3 of 6 sessions started from a break`.
    var fromBreakText: String {
        today.sessions == 0
            ? "No focus yet today"
            : "\(today.startedFromBreak) of \(TimerFormat.count(today.sessions, "session", "sessions")) started from a break"
    }

    /// `27 tomatoes, 5 jars, 18 started from a break`.
    var weekText: String {
        weekTomatoes == 0
            ? "No tomatoes yet this week"
            : "\(TimerFormat.count(weekTomatoes, "tomato", "tomatoes")), \(TimerFormat.count(weekJars, "jar", "jars")), \(weekFromBreak) started from a break"
    }

    /// `Stickers found · 8 of 24`.
    var stickersText: String { "Stickers found · \(stickers.count) of \(Stickers.all.count)" }

    /// Stickers the page has room for.
    static let stickerSlots = 8

    /// The latest found, at most eight.
    var shownStickers: [EarnedSticker] { Array(stickers.suffix(Self.stickerSlots)) }

    /// Places for stickers still to find, in the room the found ones leave,
    /// at most four.
    var shownLocked: Int {
        max(0, min(4, Self.stickerSlots - shownStickers.count, Stickers.all.count - stickers.count))
    }

    /// `+4`: the found stickers the page has no room for.
    var moreStickersText: String? {
        stickers.count > Self.stickerSlots ? "+\(stickers.count - Self.stickerSlots)" : nil
    }
}

/// The journal's colours: paper, ink and binding. The shelf around it stays
/// Droppy's black.
enum JournalInk {
    static let paper = Color(hex: "#F4EEE1")
    static let rule = Color(hex: "#E3D9C5")
    static let text = Color(hex: "#2E2A24")
    static let secondary = Color(hex: "#6E665A")
    static let tertiary = Color(hex: "#9C9383")
    static let gutter = Color(hex: "#D8CCB4")
    static let stitch = Color(hex: "#B5A586")
    static let cover = Color(hex: "#8E2F27")
    static let highlight = Color(hex: "#D6483A").opacity(0.12)
    /// Behind a row asking whether to leave the climb under way.
    static let warning = Color(hex: "#E9B44C").opacity(0.16)
    static let climbed = Color(hex: "#3F7A4C")
    static let current = Color(hex: "#C2463A")
    static let stickerRing = Color(hex: "#FFFDF8")
}

/// The journal's type and sizes: handwritten headings over printed names. Its smallest type is 12pt, the size of the
/// Focus and Break labels on Droppy's own Pomodoro, so nothing in it reads
/// smaller than Droppy does; the rest is the approved design scaled to match.
private enum Journal {
    static let small: CGFloat = 12
    static let name: CGFloat = 14.5
    static let heading: CGFloat = 16
    static let figure: CGFloat = 33
    static let rowHeight: CGFloat = 44
    static let icon = CGSize(width: 55, height: 33)
    static let sticker: CGFloat = 25

    /// The keeper's handwriting, for the headings and the day's figure:
    /// Bradley Hand, which every Mac has. Should one not, the system's serif
    /// in italic, as the journal was first set.
    static func hand(_ size: CGFloat) -> Font {
        JournalType.isInstalled(JournalType.hand)
            ? .custom(JournalType.hand, fixedSize: size)
            : .system(size: size, weight: size > heading ? .bold : .regular, design: .serif).italic()
    }

    /// The printed names of the peaks: Baskerville, semibold. Should a Mac
    /// not have it, the system's serif.
    static func print(_ size: CGFloat) -> Font {
        JournalType.isInstalled(JournalType.print)
            ? .custom(JournalType.print, fixedSize: size)
            : .system(size: size, weight: .semibold, design: .serif)
    }
}

/// The journal's two typefaces, by the names macOS knows them by.
enum JournalType {
    static let hand = "BradleyHandITCTT-Bold"
    static let print = "Baskerville-SemiBold"

    static func isInstalled(_ name: String) -> Bool {
        NSFont(name: name, size: 12) != nil
    }
}

private struct ExpeditionLogView: View {
    @ObservedObject var droplet: PomodorologDroplet

    var body: some View {
        // Every so often, so a running focus fills the icon as on the widget.
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let model = ExpeditionLogModel(
                rewards: droplet.rewards,
                today: droplet.today,
                live: droplet.liveStep(at: timeline.date),
                since: droplet.todayStartedAt
            )
            VStack(alignment: .leading, spacing: DroppySpacing.smd) {
                header
                JournalNotebook(model: model) { droplet.pickClimb($0) }
                    // Room for the ribbon to hang below the pages.
                    .padding(.bottom, DroppySpacing.mdl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 12, weight: .medium))
            Text("Expedition log")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: DroppySpacing.sm)
            Button("Sticker book") { droplet.openStickerBook() }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
            Button {
                droplet.closeExpeditionLog()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 24))
            .accessibilityLabel("Close the expedition log")
        }
        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        .frame(height: 24)
    }
}

/// The open journal: a cloth cover, the route on the left page, today on the
/// right, the gutter stitched between them and a ribbon hanging out.
private struct JournalNotebook: View {
    let model: ExpeditionLogModel
    /// Picks the peak at an index in `Peaks.all` to climb.
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            RoutePage(model: model, onPick: onPick)
                .background(PaperPage(shape: UnevenRoundedRectangle(
                    topLeadingRadius: 8, bottomLeadingRadius: 8,
                    bottomTrailingRadius: 2, topTrailingRadius: 2, style: .continuous
                )))
            Rectangle()
                .fill(JournalInk.gutter)
                .overlay {
                    StitchLine()
                        .stroke(JournalInk.stitch, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                .frame(width: 12)
                .accessibilityHidden(true)
            TodayPage(model: model)
                .background(PaperPage(shape: UnevenRoundedRectangle(
                    topLeadingRadius: 2, bottomLeadingRadius: 2,
                    bottomTrailingRadius: 8, topTrailingRadius: 8, style: .continuous
                )))
        }
        .padding(DroppySpacing.xsm)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                .fill(JournalInk.cover)
        )
        .overlay(alignment: .bottomLeading) {
            RibbonShape()
                .fill(SummitInk.tomato)
                .frame(width: 11, height: 30)
                .offset(x: 275, y: 13)
                .accessibilityHidden(true)
        }
        // The pages are paper, a light surface: Droppy's controls on them take
        // their dark ink and light backing. The journal's own inks are fixed.
        .environment(\.colorScheme, .light)
    }
}

/// The left page: every peak, a Climb button on each that can be picked.
/// While a climb is under way a row shows its button when pointed at; with
/// nothing picked, every row shows it.
private struct RoutePage: View {
    let model: ExpeditionLogModel
    let onPick: (Int) -> Void

    /// The row pointed at.
    @State private var hovered: Int?
    /// The row asking whether to leave the climb under way.
    @State private var confirming: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: model.headingText)
                    .font(Journal.hand(Journal.heading))
                Spacer(minLength: DroppySpacing.sm)
                Text(verbatim: model.climbedText)
                    .font(.system(size: Journal.small))
                    .monospacedDigit()
                    .foregroundStyle(JournalInk.secondary)
            }
            .frame(height: 24, alignment: .top)
            ForEach(model.rows, id: \.index) { row in
                let isLast = row.index == Peaks.all.count - 1
                if confirming == row.index, let warning = model.switchWarning(to: row.index) {
                    SwitchWarningRow(
                        warning: warning,
                        onCancel: { confirming = nil },
                        onSwitch: {
                            confirming = nil
                            onPick(row.index)
                        }
                    )
                } else {
                    RouteRowView(
                        row: row,
                        isLast: isLast,
                        showsClimb: model.current?.peakIndex != row.index && (model.isPicking || hovered == row.index),
                        onClimb: { climb(row.index) }
                    )
                    .onHover { inside in
                        if inside {
                            hovered = row.index
                        } else if hovered == row.index {
                            hovered = nil
                        }
                    }
                }
            }
        }
        .foregroundStyle(JournalInk.text)
        .lineLimit(1)
        // A Climb button on every row while picking: Droppy's flat wash, no
        // glass pass per row.
        .droppyFlatGlassControls()
        .padding(.horizontal, DroppySpacing.lg)
        .padding(.vertical, DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Picks at once, unless metres on the climb under way would be lost.
    private func climb(_ index: Int) {
        if model.switchWarning(to: index) != nil {
            confirming = index
        } else {
            confirming = nil
            onPick(index)
        }
    }
}

private struct RouteRowView: View {
    let row: ExpeditionLogModel.RouteRow
    let isLast: Bool
    /// The Climb button in place of the row's status.
    var showsClimb = false
    var onClimb: () -> Void = {}

    private var isCurrent: Bool {
        if case .current = row.state { true } else { false }
    }

    private var isClimbed: Bool {
        if case .climbed = row.state { true } else { false }
    }

    private var isAhead: Bool { row.state == .ahead }

    private var iconStyle: PeakIcon.Style {
        switch row.state {
        case .climbed: .inked
        case .current(_, let fraction): .climbing(fraction)
        case .ahead: .pencil
        }
    }

    var body: some View {
        HStack(spacing: DroppySpacing.md) {
            HStack(spacing: DroppySpacing.md) {
                PeakIcon(index: row.index, style: iconStyle)
                    .frame(width: Journal.icon.width, height: Journal.icon.height)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: DroppySpacing.xs) {
                        Text(verbatim: row.peak.name)
                            .font(Journal.print(Journal.name))
                            .foregroundStyle(isAhead ? JournalInk.secondary : JournalInk.text)
                        // The status gives way to the button, so the tick
                        // moves beside the name.
                        if showsClimb && isClimbed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(JournalInk.climbed)
                        }
                    }
                    Text(verbatim: row.detailText)
                        .font(.system(size: Journal.small))
                        .foregroundStyle(isAhead ? JournalInk.tertiary : JournalInk.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !showsClimb {
                    status
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.spokenText)
            if showsClimb {
                Button("Climb", action: onClimb)
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                    .accessibilityLabel("Climb \(row.peak.name)")
            }
        }
        .frame(height: Journal.rowHeight)
        .contentShape(Rectangle())
        .background {
            // Past the row's edges, so the highlight takes no width from it.
            if isCurrent {
                RoundedRectangle(cornerRadius: DroppyRadius.xs, style: .continuous)
                    .fill(JournalInk.highlight)
                    .padding(.horizontal, -DroppySpacing.xsm)
            }
        }
        .overlay(alignment: .bottom) {
            // The page's ruling, under every row but the last.
            if !isLast && !isCurrent {
                Rectangle().fill(JournalInk.rule).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch row.state {
        case .climbed(let date, _):
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text(verbatim: date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: Journal.small))
            }
            .foregroundStyle(JournalInk.climbed)
        case .current(let metres, let fraction):
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(SummitWidgetModel.metres(metres)) m")
                    .font(.system(size: Journal.small, weight: .semibold))
                Text(verbatim: "\(Int((fraction * 100).rounded(.down)))% up")
                    .font(.system(size: Journal.small))
            }
            .monospacedDigit()
            .foregroundStyle(JournalInk.current)
        case .ahead:
            EmptyView()
        }
    }
}

/// A row asking whether to leave the climb under way: two short lines, then
/// Cancel and Switch. Nothing changes until Switch.
private struct SwitchWarningRow: View {
    let warning: ExpeditionLogModel.SwitchWarning
    let onCancel: () -> Void
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: warning.title)
                    .font(Journal.print(Journal.name))
                    .foregroundStyle(JournalInk.text)
                    // The longest name only just fits; it may give a little.
                    .minimumScaleFactor(0.85)
                Text(verbatim: warning.detail)
                    .font(.system(size: Journal.small))
                    .foregroundStyle(JournalInk.current)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DroppySpacing.xsm) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                Button("Switch", action: onSwitch)
                    .buttonStyle(DroppyQuietButtonStyle(size: .small, destructive: true))
            }
        }
        .frame(height: Journal.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: DroppyRadius.xs, style: .continuous)
                .fill(JournalInk.warning)
                .padding(.horizontal, -DroppySpacing.xsm)
                .padding(.vertical, 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(warning.title) \(warning.detail)")
    }
}

/// The right page: today's climb, the week's pantry and the stickers found.
private struct TodayPage: View {
    let model: ExpeditionLogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.dateText)
                .font(Journal.hand(Journal.heading))
                .frame(height: 24, alignment: .top)

            Text("Today's climb")
                .foregroundStyle(JournalInk.secondary)
                .padding(.top, DroppySpacing.sm)
            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.sm) {
                Text(verbatim: model.todayText)
                    .font(Journal.hand(Journal.figure))
                if let since = model.sinceText {
                    Text(verbatim: since)
                        .foregroundStyle(JournalInk.secondary)
                }
            }
            .padding(.top, 1)
            ClimbBar(focus: model.today.focusMetres, bonus: model.today.bonusMetres, track: JournalInk.rule)
                .frame(height: 8)
                .padding(.top, DroppySpacing.xsm)
            HStack(spacing: DroppySpacing.lg) {
                key(SummitInk.tomato, model.focusText)
                key(SummitInk.bonus, model.bonusText)
            }
            .padding(.top, DroppySpacing.sm)
            Text(verbatim: model.fromBreakText)
                .foregroundStyle(JournalInk.tertiary)
                .padding(.top, 5)

            Text("Pantry this week")
                .foregroundStyle(JournalInk.secondary)
                .padding(.top, DroppySpacing.mdl)
            WeekColumns(model: model)
                .frame(height: 63)
                .padding(.top, DroppySpacing.xs)
            Text(verbatim: model.weekText)
                .foregroundStyle(JournalInk.tertiary)
                .padding(.top, DroppySpacing.xs)

            Text(verbatim: model.stickersText)
                .foregroundStyle(JournalInk.secondary)
                .padding(.top, DroppySpacing.md)
            StickerRow(model: model)
                .padding(.top, DroppySpacing.sm)
        }
        .font(.system(size: Journal.small))
        .foregroundStyle(JournalInk.text)
        .lineLimit(1)
        .padding(.horizontal, DroppySpacing.lg)
        .padding(.vertical, DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 11, height: 4)
            Text(verbatim: text)
                .monospacedDigit()
        }
    }
}

/// The week as columns of tomatoes, jars at the bottom.
private struct WeekColumns: View {
    let model: ExpeditionLogModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(model.week, id: \.day) { day in
                VStack(spacing: 2) {
                    ForEach(0..<day.shownLoose, id: \.self) { _ in TomatoGlyph(size: 12) }
                    ForEach(0..<day.shownJars, id: \.self) { _ in JarGlyph(size: 14) }
                    Text(verbatim: day.letter)
                        .font(.system(size: Journal.small, weight: day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? JournalInk.text : JournalInk.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.letter): \(TimerFormat.count(day.tomatoes, "tomato", "tomatoes"))")
            }
        }
    }
}

/// The stickers found, stuck on the page, and places for ones still to find.
private struct StickerRow: View {
    let model: ExpeditionLogModel

    var body: some View {
        HStack(spacing: DroppySpacing.xs) {
            ForEach(model.shownStickers, id: \.sticker.id) { earned in
                StickerDisc(sticker: earned.sticker, size: Journal.sticker)
                    .padding(2)
                    .background(Circle().fill(JournalInk.stickerRing))
                    .rotationEffect(.degrees(Self.tilt(earned.sticker.id)))
                    .overlay(alignment: .bottomTrailing) {
                        if earned.count > 1 {
                            StickerCount(count: earned.count, ring: JournalInk.stickerRing)
                                .offset(x: 9, y: 4)
                        }
                    }
                    .help(earned.sticker.name)
            }
            ForEach(0..<model.shownLocked, id: \.self) { _ in
                ZStack {
                    Circle()
                        .strokeBorder(PeakPalette.journal.pencil, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                    Image(systemName: "questionmark")
                        .font(.system(size: Journal.small, weight: .semibold))
                        .foregroundStyle(PeakPalette.journal.pencil)
                }
                .frame(width: Journal.sticker, height: Journal.sticker)
                .padding(2)
                .accessibilityElement()
                .accessibilityLabel("A sticker not found yet")
            }
            if let more = model.moreStickersText {
                Text(verbatim: more)
                    .foregroundStyle(JournalInk.tertiary)
                    .padding(.leading, DroppySpacing.xs)
            }
        }
        .frame(height: Journal.sticker + 4)
    }

    /// A small tilt of its own for each sticker, as if stuck on by hand.
    static func tilt(_ id: String) -> Double {
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 19) - 9
    }
}

/// Today's climb as one bar: focus, then the bonus the breaks earned.
private struct ClimbBar: View {
    let focus: Double
    let bonus: Double
    var track: Color = .white.opacity(0.1)

    var body: some View {
        GeometryReader { proxy in
            let total = focus + bonus
            HStack(spacing: 0) {
                if total > 0 {
                    Rectangle().fill(SummitInk.tomato)
                        .frame(width: proxy.size.width * CGFloat(focus / total))
                    Rectangle().fill(SummitInk.bonus)
                        .frame(width: proxy.size.width * CGFloat(bonus / total))
                }
                Spacer(minLength: 0)
            }
            .background(track)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .accessibilityElement()
        .accessibilityLabel("\(SummitWidgetModel.metres(focus)) metres from focus and \(SummitWidgetModel.metres(bonus)) from break bonuses")
    }
}

/// The gutter's stitching, short of the page ends.
private struct StitchLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 12))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 12))
        return path
    }
}

/// The bookmark ribbon: a strip with a V cut into its end.
private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A sticker as a disc in its colour with its symbol, or a question mark for
/// one not found yet. A peak's sticker draws the peak's own symbol, and one
/// not reached yet draws it greyed, since every peak is known from the start.
struct StickerDisc: View {
    let sticker: Sticker?
    var size: CGFloat = 24
    /// On the shelf's black, or in Settings, which follows the Mac's
    /// appearance: decides how a sticker not found yet is drawn.
    var onShelf = true
    /// The peak whose sticker this is, when it hasn't been found yet.
    var lockedPeak: Int? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(sticker.map { Color(hex: $0.colorHex) } ?? lockedFill)
            if let peak = sticker?.peak ?? lockedPeak {
                SummitGlyph(peak: peak, ink: sticker == nil ? lockedInk : Color.black.opacity(0.78))
            } else {
                Image(systemName: sticker?.symbol ?? "questionmark")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(sticker == nil ? lockedInk : Color.black.opacity(0.78))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var label: String {
        if let sticker { return sticker.name }
        if let lockedPeak, Peaks.all.indices.contains(lockedPeak) { return "\(Peaks.all[lockedPeak].name), not climbed yet" }
        return "A sticker not found yet"
    }

    private var lockedFill: Color { onShelf ? Color.white.opacity(0.07) : Color.primary.opacity(0.07) }
    private var lockedInk: Color { onShelf ? Color.white.opacity(0.34) : Color.primary.opacity(0.34) }
}
