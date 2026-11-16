//
//  SummitScene.swift
//  Pomodorolog
//
//  The mountain on the summit widget. Where the trail runs and what is drawn
//  on it are plain values worked out from the rewards, so they can be tested;
//  the Canvas only paints them.
//

import SwiftUI

/// The trail up the mountain, in the scene's own 424 × 140 space. It zigzags
/// at an even slope with a short hairpin at each turn, so how high the climber
/// stands in the picture is how far up the peak they are.
enum TrailGeometry {
    static let size = CGSize(width: 424, height: 140)
    static let waypoints: [CGPoint] = [
        CGPoint(x: 130, y: 134), CGPoint(x: 330, y: 90), CGPoint(x: 330, y: 84),
        CGPoint(x: 190.5, y: 53.3), CGPoint(x: 190.5, y: 47.3), CGPoint(x: 240, y: 14),
    ]
    static var foot: CGPoint { waypoints[0] }
    static var top: CGPoint { waypoints[waypoints.count - 1] }

    /// The point `fraction` of the way up, by height.
    static func point(at fraction: Double) -> CGPoint {
        let clamped = min(max(fraction, 0), 1)
        let y = foot.y - CGFloat(clamped) * (foot.y - top.y)
        for (a, b) in zip(waypoints, waypoints.dropFirst()) where a.y >= y && y >= b.y {
            let t = a.y == b.y ? 0 : (a.y - y) / (a.y - b.y)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: y)
        }
        return top
    }

    /// The trail from one fraction of the way up to another, its corners
    /// included.
    static func points(from start: Double, to end: Double) -> [CGPoint] {
        let first = point(at: start)
        let last = point(at: end)
        return [first] + waypoints.filter { $0.y < first.y && $0.y > last.y } + [last]
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

    let peakIndex: Int
    let ascent: Int
    /// Metres climbed on this peak.
    let climbed: Double
    let stretches: [Stretch]
    let markers: [Marker]

    var peak: Peak { Peaks.all[peakIndex] }
    var fraction: Double { min(max(climbed / peak.height, 0), 1) }

    /// `live` is the running focus's share so far, drawn like today's.
    init(rewards: RewardsSnapshot, today: String, live: ClimbStep? = nil) {
        let total = live?.after ?? rewards.climb.total
        let position = Peaks.position(at: total)
        let foot = Peaks.foot(ofPeak: position.index, ascent: position.ascent)
        let top = foot + position.peak.height
        func fraction(_ altitude: Double) -> Double {
            min(max((altitude - foot) / position.peak.height, 0), 1)
        }

        let tomatoes = Dictionary(
            rewards.pantry.tomatoes.map { ($0.recordID, $0.isJar) },
            uniquingKeysWith: { first, _ in first }
        )
        var steps = rewards.climb.steps
        if let live { steps.append(live) }

        var stretches: [Stretch] = []
        var markers: [Marker] = []
        for step in steps where step.after > foot && step.before < top {
            let isToday = step.day == today
            // The bonus comes from the break before, so it leads the stretch.
            let bonusEnd = step.before + step.bonusMetres
            if step.bonusMetres > 0, bonusEnd > foot {
                stretches.append(Stretch(from: fraction(step.before), to: fraction(bonusEnd), ink: isToday ? .todayBonus : .earlierBonus))
            }
            if step.after > max(bonusEnd, foot) {
                stretches.append(Stretch(from: fraction(bonusEnd), to: fraction(step.after), ink: isToday ? .today : .earlier))
            }
            let middle = (step.before + step.after) / 2
            if let isJar = tomatoes[step.recordID], middle >= foot, middle < top {
                markers.append(Marker(at: fraction(middle), isJar: isJar, isToday: isToday))
            }
        }

        peakIndex = position.index
        ascent = position.ascent
        climbed = position.metres
        self.stretches = stretches
        self.markers = markers
    }
}

/// The scene's colours. Droppy's shelf is black in both appearances.
enum SummitInk {
    static let tomato = Color(hex: "#FF4F45")
    static let leaf = Color(hex: "#34C759")
    static let lid = Color(hex: "#8E8E93")
    static let bonus = Color(hex: "#FFB340")
    static let rock = Color(hex: "#2C2C2E")
    static let rockBack = Color(hex: "#1A1A1C")
    static let snow = Color(hex: "#5E5E63")
    static let flag = Color(hex: "#64D2FF")
    static let pole = Color(hex: "#D1D1D6")
    static let ring = Color(hex: "#1C1C1E")
}

/// The mountain in silhouette, in the trail's 424 × 140 space.
private enum MountainArt {
    static let back = polygon("0,140 0,96 40,80 70,92 110,60 140,74 170,66 200,84 236,58 262,70 300,52 330,66 370,58 400,74 424,68 424,140")
    static let main = polygon("0,140 20,128 60,118 96,100 130,84 160,62 190,44 214,30 240,14 266,30 292,46 318,56 350,80 390,98 424,110 424,140")
    static let snow = polygon("226,22.6 240,14 254,22.6 250,24.2 246,22.4 242,26 238,22.6 234,25 230,23.2")

    private static func polygon(_ text: String) -> [CGPoint] {
        text.split(separator: " ").compactMap { pair in
            let parts = pair.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
        }
    }
}

/// Paints a `SummitScene`. Without markers it is the half-width version: the
/// trail and the climber, which stay readable when the widget shares a row.
struct MountainSceneView: View {
    let scene: SummitScene
    var showsMarkers = true

    /// The part of the 424 × 140 scene shown. At half width it closes in on
    /// the mountain, so the trail draws larger.
    private var viewport: CGRect {
        showsMarkers
            ? CGRect(origin: .zero, size: TrailGeometry.size)
            : CGRect(x: 96, y: 0, width: 288, height: TrailGeometry.size.height)
    }

    var body: some View {
        let viewport = viewport
        Canvas { context, size in
            let scale = min(size.width / viewport.width, size.height / viewport.height)
            let offset = CGPoint(
                x: (size.width - viewport.width * scale) / 2 - viewport.minX * scale,
                y: size.height - viewport.height * scale - viewport.minY * scale
            )
            func map(_ point: CGPoint) -> CGPoint {
                CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
            }
            func shape(_ points: [CGPoint], closed: Bool) -> Path {
                var path = Path()
                path.addLines(points.map(map))
                if closed { path.closeSubpath() }
                return path
            }

            context.fill(shape(MountainArt.back, closed: true), with: .color(SummitInk.rockBack))
            context.fill(shape(MountainArt.main, closed: true), with: .color(SummitInk.rock))
            context.fill(shape(MountainArt.snow, closed: true), with: .color(SummitInk.snow))

            for stretch in scene.stretches {
                context.stroke(
                    shape(TrailGeometry.points(from: stretch.from, to: stretch.to), closed: false),
                    with: .color(color(stretch.ink)),
                    style: StrokeStyle(lineWidth: width(stretch.ink), lineCap: .butt, lineJoin: .round)
                )
            }
            if scene.fraction < 1 {
                context.stroke(
                    shape(TrailGeometry.points(from: scene.fraction, to: 1), closed: false),
                    with: .color(.white.opacity(0.36)),
                    style: StrokeStyle(lineWidth: showsMarkers ? 2 : 1.6, lineCap: .round, lineJoin: .round, dash: [2, 4])
                )
            }

            // The flag on the top, and its height.
            let top = map(TrailGeometry.top)
            let flagTop = CGPoint(x: top.x, y: top.y - 11 * scale)
            var pole = Path()
            pole.move(to: top)
            pole.addLine(to: flagTop)
            context.stroke(pole, with: .color(SummitInk.pole), lineWidth: 1.2)
            var flag = Path()
            flag.move(to: flagTop)
            flag.addLine(to: CGPoint(x: top.x + 10 * scale, y: top.y - 8.5 * scale))
            flag.addLine(to: CGPoint(x: top.x, y: top.y - 6 * scale))
            flag.closeSubpath()
            context.fill(flag, with: .color(SummitInk.flag))

            if showsMarkers {
                let height = Text(verbatim: "\(Int(scene.peak.height).formatted()) m")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                context.draw(height, at: CGPoint(x: top.x + 15 * scale, y: top.y - 8 * scale), anchor: .leading)

                for marker in scene.markers {
                    draw(marker, at: map(TrailGeometry.point(at: marker.at)), scale: scale, in: &context)
                }
            }

            // The climber.
            let you = map(TrailGeometry.point(at: scene.fraction))
            let radius: CGFloat = showsMarkers ? 5 : 4
            let disc = Path(ellipseIn: CGRect(x: you.x - radius, y: you.y - radius, width: radius * 2, height: radius * 2))
            context.fill(disc, with: .color(.white))
            context.stroke(disc, with: .color(SummitInk.tomato), lineWidth: showsMarkers ? 2.6 : 2.2)
        }
        .aspectRatio(viewport.width / viewport.height, contentMode: .fit)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("\(scene.peak.name), \(Int((scene.fraction * 100).rounded())) percent of the way up")
    }

    private func color(_ ink: SummitScene.Ink) -> Color {
        switch ink {
        case .today: SummitInk.tomato
        case .todayBonus: SummitInk.bonus
        case .earlier: .white.opacity(0.72)
        case .earlierBonus: SummitInk.bonus.opacity(0.62)
        }
    }

    private func width(_ ink: SummitScene.Ink) -> CGFloat {
        guard showsMarkers else { return 2 }
        switch ink {
        case .today, .todayBonus: return 2.6
        case .earlier, .earlierBonus: return 2
        }
    }

    private func draw(_ marker: SummitScene.Marker, at point: CGPoint, scale: CGFloat, in context: inout GraphicsContext) {
        let size = max(scale, 0.75)
        if marker.isJar {
            let body = CGRect(x: point.x - 4.5 * size, y: point.y - 4.5 * size, width: 9 * size, height: 11 * size)
            let jar = Path(roundedRect: body, cornerRadius: 2.2 * size, style: .continuous)
            context.fill(jar, with: .color(SummitInk.tomato))
            context.stroke(jar, with: .color(SummitInk.ring), lineWidth: 1.4)
            let lid = Path(roundedRect: CGRect(x: body.minX + 0.5 * size, y: body.minY - 2.6 * size, width: 8 * size, height: 2.6 * size), cornerRadius: 1.2 * size)
            context.fill(lid, with: .color(SummitInk.lid))
        } else {
            let radius = (marker.isToday ? 4.4 : 3.3) * size
            let tomato = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(tomato, with: .color(SummitInk.tomato))
            context.stroke(tomato, with: .color(SummitInk.ring), lineWidth: 1.4)
            let leaf = Path(ellipseIn: CGRect(x: point.x - radius * 0.42, y: point.y - radius - radius * 0.06, width: radius * 0.84, height: radius * 0.52))
            context.fill(leaf, with: .color(SummitInk.leaf))
        }
    }
}
