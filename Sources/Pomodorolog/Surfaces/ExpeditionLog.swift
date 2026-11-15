//
//  ExpeditionLog.swift
//  Pomodorolog
//
//  The expedition log: a takeover on the shelf, opened from the summit
//  widget. The range of peaks to scale, today's climb split into focus and
//  break bonus, the week's pantry, and the stickers found.
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
    /// around this, so the view draws edge to edge.
    static let expeditionLogSize = CGSize(width: 624, height: 384)

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

    let position: PeakPosition
    /// Today's climb, with a running focus's share so far.
    let today: DayClimb
    let since: Date?
    let week: [WeekDay]
    let weekTomatoes: Int
    let weekJars: Int
    let weekFromBreak: Int
    let stickers: [EarnedSticker]

    init(rewards: RewardsSnapshot, today: String, live: ClimbStep?, since: Date?) {
        position = Peaks.position(at: live?.after ?? rewards.climb.total)
        var day = rewards.climb.day(today)
        if let live, live.day == today {
            day.focusMetres += live.baseMetres
            day.bonusMetres += live.bonusMetres
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

    /// `Peak 3 of 7`, and the ascent after the first time up.
    var peakText: String {
        let peak = "Peak \(position.index + 1) of \(Peaks.all.count)"
        return position.ascent > 1 ? "\(peak), ascent \(position.ascent)" : peak
    }

    /// The line under the range, which draws only the six on Earth.
    var finaleText: String {
        let mars = Peaks.all[Peaks.all.count - 1]
        if position.index == Peaks.all.count - 1 {
            return "On \(mars.name), Mars: \(SummitWidgetModel.metres(position.metres)) of \(SummitWidgetModel.metres(mars.height)) m"
        }
        return "Then \(mars.name) on Mars, \((mars.height / 1000).formatted(.number.precision(.fractionLength(1)))) km"
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

    /// The stickers drawn in the strip: the latest found, then a few still to
    /// find, at most 16 discs in all.
    var shownStickers: [EarnedSticker] { Array(stickers.suffix(16)) }
    var shownLocked: Int { max(0, min(4, 16 - shownStickers.count, Stickers.all.count - stickers.count)) }
}

private struct ExpeditionLogView: View {
    @ObservedObject var droplet: PomodorologDroplet

    var body: some View {
        // Every so often, so a running focus moves the marker as on the widget.
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let model = ExpeditionLogModel(
                rewards: droplet.rewards,
                today: droplet.today,
                live: droplet.liveStep(at: timeline.date),
                since: droplet.todayStartedAt
            )
            VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                header(model)
                RangeProfileView(position: model.position)
                Text(verbatim: model.finaleText)
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                HStack(alignment: .top, spacing: 28) {
                    TodayClimbBlock(model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PantryWeekBlock(model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, DroppySpacing.xs)
                StickerStrip(model: model) { droplet.openStickerBook() }
                    .padding(.top, DroppySpacing.sm)
            }
            .font(.system(size: 12))
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func header(_ model: ExpeditionLogModel) -> some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 12, weight: .medium))
            Text("Expedition log")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: DroppySpacing.sm)
            Text(verbatim: model.peakText)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            Button {
                droplet.closeExpeditionLog()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 24))
            .accessibilityLabel("Close the expedition log")
        }
        .frame(height: 24)
    }
}

/// The six peaks on Earth to scale, climbed ones flagged, the current one
/// filled to where you are. Olympus Mons is too tall to draw beside them, so
/// the line under the range names it.
private struct RangeProfileView: View {
    let position: PeakPosition

    private static let size = CGSize(width: 624, height: 120)
    private static let baseline: CGFloat = 100
    /// Everest is 80 high; the rest to the same scale.
    private static let everestHeight: CGFloat = 80
    private static let centres: [CGFloat] = [50, 140, 235, 335, 435, 552]

    private struct Outline {
        let centre: CGFloat
        let height: CGFloat
        let half: CGFloat
        let apex: CGPoint
    }

    private static func outline(_ index: Int) -> Outline {
        let height = CGFloat(Peaks.all[index].height / Peaks.all[5].height) * everestHeight
        return Outline(
            centre: centres[index],
            height: height,
            half: 18 + height * 0.55,
            apex: CGPoint(x: centres[index], y: baseline - height)
        )
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.size.width, size.height / Self.size.height)
            let dx = (size.width - Self.size.width * scale) / 2
            func map(_ point: CGPoint) -> CGPoint { CGPoint(x: dx + point.x * scale, y: point.y * scale) }
            func polygon(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points.map(map))
                path.closeSubpath()
                return path
            }

            var ground = Path()
            ground.move(to: map(CGPoint(x: 0, y: Self.baseline)))
            ground.addLine(to: map(CGPoint(x: Self.size.width, y: Self.baseline)))
            context.stroke(ground, with: .color(.white.opacity(0.12)), lineWidth: 1)

            let onMars = position.index == Peaks.all.count - 1
            for index in 0..<6 {
                let outline = Self.outline(index)
                let left = CGPoint(x: outline.centre - outline.half, y: Self.baseline)
                let right = CGPoint(x: outline.centre + outline.half, y: Self.baseline)
                let climbed = index < position.index || onMars
                let current = index == position.index
                let fill = climbed ? "#3A3A3C" : current ? "#2C2C2E" : "#202022"
                context.fill(polygon([left, outline.apex, right]), with: .color(Color(hex: fill)))

                if current {
                    let fraction = CGFloat(min(max(position.fraction, 0), 1))
                    let level = Self.baseline - outline.height * fraction
                    let inset = outline.half * fraction
                    let climbedLeft = CGPoint(x: left.x + inset, y: level)
                    let climbedRight = CGPoint(x: right.x - inset, y: level)
                    context.fill(polygon([left, climbedLeft, climbedRight, right]), with: .color(Color(hex: "#4A4A4E")))
                    let marker = map(climbedLeft)
                    let radius = 4.4 * scale
                    let disc = Path(ellipseIn: CGRect(x: marker.x - radius, y: marker.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(disc, with: .color(.white))
                    context.stroke(disc, with: .color(SummitInk.tomato), lineWidth: 2.4 * scale)
                } else if climbed {
                    let top = outline.apex
                    var pole = Path()
                    pole.move(to: map(top))
                    pole.addLine(to: map(CGPoint(x: top.x, y: top.y - 8.8)))
                    context.stroke(pole, with: .color(SummitInk.pole), lineWidth: 1.3 * scale)
                    context.fill(polygon([
                        CGPoint(x: top.x, y: top.y - 8.8),
                        CGPoint(x: top.x + 7, y: top.y - 6.8),
                        CGPoint(x: top.x, y: top.y - 4.8),
                    ]), with: .color(SummitInk.flag))
                }

                let name = index == 1 ? "Fuji" : Peaks.all[index].name
                let label = Text(verbatim: name)
                    .font(.system(size: 11 * scale, weight: current ? .semibold : .regular))
                    .foregroundColor(current ? .white : .white.opacity(climbed ? 0.62 : 0.4))
                context.draw(label, at: map(CGPoint(x: outline.centre, y: 112)), anchor: .center)
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Self.spoken(position))
    }

    static func spoken(_ position: PeakPosition) -> String {
        let percent = Int((position.fraction * 100).rounded(.down))
        return "Peak \(position.index + 1) of \(Peaks.all.count): \(position.peak.name), \(percent) percent climbed"
    }
}

private struct TodayClimbBlock: View {
    let model: ExpeditionLogModel

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            Text("Today's climb")
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.sm) {
                Text(verbatim: model.todayText)
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                if let since = model.sinceText {
                    Text(verbatim: since)
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
            }
            ClimbBar(focus: model.today.focusMetres, bonus: model.today.bonusMetres)
                .frame(height: 8)
            HStack(spacing: DroppySpacing.mdl) {
                key(SummitInk.tomato, model.focusText)
                key(SummitInk.bonus, model.bonusText)
            }
            Text(verbatim: model.fromBreakText)
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
        }
        .lineLimit(1)
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 4)
            Text(verbatim: text)
                .monospacedDigit()
        }
    }
}

/// Today's climb as one bar: focus, then the bonus the breaks earned.
private struct ClimbBar: View {
    let focus: Double
    let bonus: Double

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
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .accessibilityElement()
        .accessibilityLabel("\(SummitWidgetModel.metres(focus)) metres from focus and \(SummitWidgetModel.metres(bonus)) from break bonuses")
    }
}

private struct PantryWeekBlock: View {
    let model: ExpeditionLogModel

    /// Three glyphs and the day's letter, the tallest a column gets.
    private static let weekHeight: CGFloat = 3 * 16 + 3 * 6 + 10

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.smd) {
            Text("Pantry this week")
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            HStack(alignment: .bottom, spacing: DroppySpacing.xs) {
                ForEach(model.week, id: \.day) { day in
                    VStack(spacing: DroppySpacing.xsm) {
                        ForEach(0..<day.shownLoose, id: \.self) { _ in TomatoGlyph(size: 12) }
                        ForEach(0..<day.shownJars, id: \.self) { _ in JarGlyph(size: 16) }
                        Text(verbatim: day.letter)
                            .font(.system(size: 10, weight: day.isToday ? .semibold : .regular))
                            .foregroundStyle(day.isToday ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceTertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.letter): \(TimerFormat.count(day.tomatoes, "tomato", "tomatoes"))")
                }
            }
            .frame(height: Self.weekHeight, alignment: .bottom)
            Text(verbatim: model.weekText)
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .lineLimit(1)
        }
    }
}

/// The stickers found, as discs, and the way to the whole book.
private struct StickerStrip: View {
    let model: ExpeditionLogModel
    let openBook: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.smd) {
            Text(verbatim: model.stickersText)
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            HStack(spacing: DroppySpacing.xsm) {
                ForEach(model.shownStickers, id: \.sticker.id) { earned in
                    StickerDisc(sticker: earned.sticker, size: 24)
                        .help(earned.sticker.name)
                }
                ForEach(0..<model.shownLocked, id: \.self) { _ in
                    StickerDisc(sticker: nil, size: 24)
                }
                Spacer(minLength: DroppySpacing.sm)
                Button("Sticker book", action: openBook)
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
            .frame(height: 24)
        }
    }
}

/// A sticker as a disc in its colour with its symbol, or a question mark for
/// one not found yet.
struct StickerDisc: View {
    let sticker: Sticker?
    var size: CGFloat = 24
    /// On the shelf's black, or in Settings, which follows the Mac's
    /// appearance: decides how a sticker not found yet is drawn.
    var onShelf = true

    var body: some View {
        ZStack {
            Circle()
                .fill(sticker.map { Color(hex: $0.colorHex) } ?? lockedFill)
            Image(systemName: sticker?.symbol ?? "questionmark")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(sticker == nil ? lockedInk : Color.black.opacity(0.78))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(sticker?.name ?? "A sticker not found yet")
    }

    private var lockedFill: Color { onShelf ? Color.white.opacity(0.07) : Color.primary.opacity(0.07) }
    private var lockedInk: Color { onShelf ? Color.white.opacity(0.34) : Color.primary.opacity(0.34) }
}
