//
//  SummitScene.swift
//  Pomodorolog
//
//  The mountain on the summit widget. Each peak has its own picture and its
//  own trail (PeakScenes.swift); where the climber stands and what is drawn
//  on the trail are plain values worked out from the rewards, so they can be
//  tested. The Canvas only paints them.
//

import DroppyKit
import SwiftUI

/// The line a trail follows up its peak, in the scene's space. How high the
/// climber stands in the picture is how far up the peak they are.
struct Trail: Equatable {
    let points: [CGPoint]

    var foot: CGPoint { points[0] }
    var top: CGPoint { points[points.count - 1] }

    /// The point `fraction` of the way up, by height: the first place the
    /// line reaches that height.
    func point(at fraction: Double) -> CGPoint {
        locate(fraction).point
    }

    /// The line from one fraction of the way up to another, its bends
    /// included.
    func points(from start: Double, to end: Double) -> [CGPoint] {
        let first = locate(start)
        let last = locate(end)
        guard last.index > first.index else { return [first.point, last.point] }
        return [first.point] + points[first.index..<last.index] + [last.point]
    }

    /// The point at `fraction`, and the index of the first sample after it.
    private func locate(_ fraction: Double) -> (index: Int, point: CGPoint) {
        let clamped = min(max(fraction, 0), 1)
        if clamped <= 0 { return (1, foot) }
        if clamped >= 1 { return (points.count - 1, top) }
        let y = foot.y - CGFloat(clamped) * (foot.y - top.y)
        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            if a.y >= y, y >= b.y {
                let t = a.y == b.y ? 0 : (a.y - y) / (a.y - b.y)
                return (index, CGPoint(x: a.x + (b.x - a.x) * t, y: y))
            }
        }
        return (points.count - 1, top)
    }
}

/// A peak's picture: flat planes from the back to the front, its trail and
/// the huts along it, all in `PeakScenes.size`.
struct PeakSceneArt {
    struct Plane {
        let color: Color
        let points: [CGPoint]
    }

    let planes: [Plane]
    let trail: Trail
    let huts: [CGPoint]
    /// Where the height is written, from the top of the trail.
    let labelOffset: CGSize

    /// Planes as a colour, an opacity and `x,y x,y` corners; the trail and
    /// the huts as `x,y x,y` too.
    init(planes: [(String, Double, String)], trail: String, huts: String, labelOffset: CGSize) {
        self.planes = planes.map { Plane(color: Color(hex: $0.0).opacity($0.1), points: PeakScenes.points($0.2)) }
        self.trail = Trail(points: PeakScenes.points(trail))
        self.huts = PeakScenes.points(huts)
        self.labelOffset = labelOffset
    }
}

enum PeakScenes {
    /// The space every scene is drawn in: the full widget, less its edges.
    static let size = CGSize(width: 464, height: 216)
    /// How much of that width the half-width widget shows.
    static let compactWidth: CGFloat = 232

    static func points(_ text: String) -> [CGPoint] {
        text.split(separator: " ").compactMap { pair in
            let parts = pair.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
        }
    }
}

/// What the scene shows of the climb: the peak, how far up it the climber
/// is, the trail climbed so far and a tomato or a jar for each tomato on it.
struct SummitScene: Equatable {
    enum Ink: Equatable, Sendable {
        case today, todayBonus, earlier, earlierBonus
    }

    /// A stretch of trail, as fractions of the way up.
    struct Stretch: Equatable, Sendable {
        let from: Double
        let to: Double
        let ink: Ink
    }

    /// A tomato in the middle of its session's stretch, or a jar for every
    /// fourth of a day.
    struct Marker: Equatable, Sendable {
        let at: Double
        let isJar: Bool
        let isToday: Bool
    }

    /// Where the climb stands.
    enum Status: Equatable, Sendable {
        /// Nothing picked yet: the first peak, with nothing climbed.
        case noClimb
        /// Under way.
        case climbing
        /// At the top, when the session that reached it ended. The next climb
        /// isn't picked yet.
        case summited(Date)
    }

    let peakIndex: Int
    let status: Status
    /// Metres climbed on this peak.
    let climbed: Double
    let stretches: [Stretch]
    let markers: [Marker]

    var peak: Peak { Peaks.all[peakIndex] }
    var art: PeakSceneArt { PeakScenes.all[peakIndex] }
    var fraction: Double { min(max(climbed / peak.height, 0), 1) }

    /// A scene set by hand, for previews and tests.
    init(peakIndex: Int, status: Status = .climbing, climbed: Double, stretches: [Stretch] = [], markers: [Marker] = []) {
        self.peakIndex = peakIndex
        self.status = status
        self.climbed = climbed
        self.stretches = stretches
        self.markers = markers
    }

    /// The latest climb: the one under way, or the one whose top was reached
    /// last. `live` is the running focus's share so far, drawn like today's.
    init(rewards: RewardsSnapshot, today: String, live: ClimbStep? = nil) {
        let climb = rewards.climb
        guard let index = climb.expeditions.indices.last else {
            self.init(peakIndex: 0, status: .noClimb, climbed: 0)
            return
        }
        let expedition = climb.expeditions[index]
        let live = live?.expedition == index ? live : nil
        let height = expedition.peak.height
        let tomatoes = Dictionary(
            rewards.pantry.tomatoes.map { ($0.recordID, $0.isJar) },
            uniquingKeysWith: { first, _ in first }
        )
        var steps = climb.steps.filter { $0.expedition == index }
        if let live { steps.append(live) }

        var stretches: [Stretch] = []
        var markers: [Marker] = []
        for step in steps where step.climbed > 0 {
            let isToday = step.day == today
            // The bonus comes from the break before, so it leads the stretch.
            let bonusEnd = step.before + step.climbedBonus
            if bonusEnd > step.before {
                stretches.append(Stretch(from: step.before / height, to: bonusEnd / height, ink: isToday ? .todayBonus : .earlierBonus))
            }
            if step.after > bonusEnd {
                stretches.append(Stretch(from: bonusEnd / height, to: step.after / height, ink: isToday ? .today : .earlier))
            }
            if let isJar = tomatoes[step.recordID] {
                markers.append(Marker(at: (step.before + step.after) / 2 / height, isJar: isJar, isToday: isToday))
            }
        }

        let climbed = live?.after ?? expedition.metres
        // A focus still running that reaches the top stays a climb at its top
        // until it's logged.
        self.init(
            peakIndex: expedition.peakIndex,
            status: expedition.summitedAt.map { .summited($0) } ?? .climbing,
            climbed: climbed,
            stretches: stretches,
            markers: markers
        )
    }
}

/// The scene's colours. Droppy's shelf is black in both appearances; each
/// peak's own greys are in PeakScenes.swift.
enum SummitInk {
    static let tomato = Color(hex: "#FF4F45")
    static let leaf = Color(hex: "#34C759")
    static let lid = Color(hex: "#8E8E93")
    static let bonus = Color(hex: "#FFB340")
    static let flag = Color(hex: "#64D2FF")
    static let pole = Color(hex: "#D1D1D6")
    static let ring = Color(hex: "#1C1C1E")
    static let hut = Color(hex: "#E5E5EA")
}

/// Paints a `SummitScene` across the whole widget, its foot on the bottom
/// edge. The half-width version closes in on the peak and leaves out the
/// tomatoes and the height.
struct MountainSceneView: View {
    let scene: SummitScene
    var isCompact = false

    /// The part of the scene shown, across its full height. At half width it
    /// frames the climber and the summit together, so it closes in on the
    /// peak as the climb goes on.
    private var viewport: (minX: CGFloat, width: CGFloat) {
        let full = PeakScenes.size.width
        guard isCompact else { return (0, full) }
        let trail = scene.art.trail
        let you = trail.point(at: scene.fraction).x
        let low = min(you, trail.top.x) - 28
        let high = max(you, trail.top.x) + 28
        let width = min(max(high - low, PeakScenes.compactWidth), full)
        let minX = min(max((low + high) / 2 - width / 2, 0), full - width)
        return (minX, width)
    }

    var body: some View {
        let art = scene.art
        let trail = art.trail
        let viewport = viewport
        let isCompact = isCompact
        Canvas { context, size in
            let scale = size.width / viewport.width
            let offset = CGPoint(x: -viewport.minX * scale, y: size.height - PeakScenes.size.height * scale)
            func map(_ point: CGPoint) -> CGPoint {
                CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
            }
            func shape(_ points: [CGPoint], closed: Bool) -> Path {
                var path = Path()
                path.addLines(points.map(map))
                if closed { path.closeSubpath() }
                return path
            }
            func line(_ width: CGFloat, dash: [CGFloat] = []) -> StrokeStyle {
                StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
            }

            for plane in art.planes {
                context.fill(shape(plane.points, closed: true), with: .color(plane.color))
            }

            // A dark edge under the whole trail keeps it readable on snow.
            context.stroke(shape(trail.points, closed: false), with: .color(SummitInk.ring), style: line(4))
            if scene.fraction < 1 {
                context.stroke(
                    shape(trail.points(from: scene.fraction, to: 1), closed: false),
                    with: .color(.white.opacity(0.65)),
                    style: line(2, dash: [2, 4])
                )
            }
            for stretch in scene.stretches {
                context.stroke(
                    shape(trail.points(from: stretch.from, to: stretch.to), closed: false),
                    with: .color(color(stretch.ink)),
                    style: StrokeStyle(lineWidth: width(stretch.ink), lineCap: .butt, lineJoin: .round)
                )
            }

            for hut in art.huts {
                let at = map(hut)
                let box = Path(CGRect(x: at.x - 1.6, y: at.y - 1.6, width: 3.2, height: 3.2))
                context.fill(box, with: .color(SummitInk.hut))
                context.stroke(box, with: .color(SummitInk.ring), lineWidth: 0.8)
            }

            // The flag on the top, and its height.
            let top = map(trail.top)
            let flagTop = CGPoint(x: top.x, y: top.y - 11)
            var pole = Path()
            pole.move(to: top)
            pole.addLine(to: flagTop)
            context.stroke(pole, with: .color(SummitInk.pole), lineWidth: 1.2)
            var flag = Path()
            flag.move(to: flagTop)
            flag.addLine(to: CGPoint(x: top.x + 10, y: top.y - 8.5))
            flag.addLine(to: CGPoint(x: top.x, y: top.y - 6))
            flag.closeSubpath()
            context.fill(flag, with: .color(SummitInk.flag))

            if !isCompact {
                let height = Text(verbatim: "\(Int(scene.peak.height).formatted()) m")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                let y = top.y + art.labelOffset.height - 4
                // Beside the flag, or before the pole where the edge is near.
                let label = context.resolve(height)
                let fits = top.x + art.labelOffset.width + label.measure(in: size).width <= size.width - DroppySpacing.sm
                if fits {
                    context.draw(label, at: CGPoint(x: top.x + art.labelOffset.width, y: y), anchor: .leading)
                } else {
                    context.draw(label, at: CGPoint(x: top.x - DroppySpacing.xsm, y: y), anchor: .trailing)
                }

                for marker in scene.markers {
                    draw(marker, at: map(trail.point(at: marker.at)), in: &context)
                }
            }

            // The climber.
            let you = map(trail.point(at: scene.fraction))
            let radius: CGFloat = isCompact ? 4 : 5
            let disc = Path(ellipseIn: CGRect(x: you.x - radius, y: you.y - radius, width: radius * 2, height: radius * 2))
            context.fill(disc, with: .color(.white))
            context.stroke(disc, with: .color(SummitInk.tomato), lineWidth: isCompact ? 2.2 : 2.6)
        }
        .accessibilityElement()
        .accessibilityLabel("\(scene.peak.name), \(Int((scene.fraction * 100).rounded())) percent of the way up")
    }

    private func color(_ ink: SummitScene.Ink) -> Color {
        switch ink {
        case .today: SummitInk.tomato
        case .todayBonus: SummitInk.bonus
        case .earlier: .white.opacity(0.78)
        case .earlierBonus: SummitInk.bonus.opacity(0.62)
        }
    }

    private func width(_ ink: SummitScene.Ink) -> CGFloat {
        switch ink {
        case .today, .todayBonus: isCompact ? 2.2 : 2.6
        case .earlier, .earlierBonus: 2
        }
    }

    private func draw(_ marker: SummitScene.Marker, at point: CGPoint, in context: inout GraphicsContext) {
        if marker.isJar {
            let body = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 11)
            let jar = Path(roundedRect: body, cornerRadius: 2.2, style: .continuous)
            context.fill(jar, with: .color(SummitInk.tomato))
            context.stroke(jar, with: .color(SummitInk.ring), lineWidth: 1.4)
            let lid = Path(roundedRect: CGRect(x: body.minX + 0.5, y: body.minY - 2.6, width: 8, height: 2.6), cornerRadius: 1.2)
            context.fill(lid, with: .color(SummitInk.lid))
        } else {
            let radius: CGFloat = marker.isToday ? 4.4 : 3.3
            let tomato = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(tomato, with: .color(SummitInk.tomato))
            context.stroke(tomato, with: .color(SummitInk.ring), lineWidth: 1.4)
            let leaf = Path(ellipseIn: CGRect(x: point.x - radius * 0.42, y: point.y - radius - radius * 0.06, width: radius * 0.84, height: radius * 0.52))
            context.fill(leaf, with: .color(SummitInk.leaf))
        }
    }
}
