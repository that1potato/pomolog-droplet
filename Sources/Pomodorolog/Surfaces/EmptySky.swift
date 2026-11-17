//
//  EmptySky.swift
//  Pomodorolog
//
//  The summit widget with no climb under way: one generic mountain in the
//  scenes' flat greys, low in the corner, and a few gulls in the sky. The
//  shapes are the approved design's (shots/climb-picker-design/emptyview.py).
//

import SwiftUI

struct EmptySkyView: View {
    /// Half width: the same mountain, smaller, under the text.
    var isCompact = false

    /// The full widget's 480 × 232, where the shapes are drawn.
    private enum Art {
        static let height: CGFloat = 232
        static let farHills = PeakScenes.points("0,232 0,196 34,186 70,192 112,178 150,188 186,232")
        static let body = PeakScenes.points("232,232 262,206 300,180 336,152 360,130 384,112 404,100 424,114 448,134 476,158 500,176 500,232")
        static let litFace = PeakScenes.points("232,232 262,206 300,180 336,152 360,130 384,112 404,100 398,136 386,170 370,204 360,232")
        static let shadeFace = PeakScenes.points("404,100 424,114 448,134 476,158 500,176 500,232 448,232 432,190 418,142")
        static let cap = PeakScenes.points("374,117 384,112 404,100 424,114 434,122 428,125 422,134 416,126 410,139 404,128 398,136 392,126 386,130 378,124")
        static let nearHills = PeakScenes.points("0,232 0,218 60,210 128,216 196,208 262,217 330,210 398,217 466,211 496,214 496,232")
    }

    /// The scenes' greys.
    private enum Ink {
        static let far = Color(hex: "#151517")
        static let mid = Color(hex: "#29292B")
        static let lit = Color(hex: "#333335")
        static let shade = Color(hex: "#1C1C1E")
        static let snow = Color(hex: "#7A7A80")
        static let snowShade = Color(hex: "#5C5C62")
        static let near = Color(hex: "#2E2E30")
    }

    /// A gull: where it flies in the art's space, its size, and how bright.
    private struct Gull {
        let at: CGPoint
        let size: CGFloat
        let opacity: Double
    }

    private static let gulls = [
        Gull(at: CGPoint(x: 300, y: 98), size: 1.2, opacity: 0.7),
        Gull(at: CGPoint(x: 330, y: 114), size: 0.9, opacity: 0.55),
        Gull(at: CGPoint(x: 348, y: 92), size: 0.72, opacity: 0.5),
        Gull(at: CGPoint(x: 270, y: 116), size: 0.6, opacity: 0.42),
    ]

    private static let compactGulls = [
        Gull(at: CGPoint(x: 279, y: 83), size: 0.95, opacity: 0.68),
        Gull(at: CGPoint(x: 324, y: 107), size: 0.72, opacity: 0.52),
        Gull(at: CGPoint(x: 348, y: 69), size: 0.58, opacity: 0.45),
    ]

    var body: some View {
        let isCompact = isCompact
        Canvas { context, size in
            // Anchored to the lower right, so a narrower widget keeps the
            // mountain and loses only the empty sky at the left.
            let scale = (isCompact ? 0.58 : 1) * size.height / Art.height
            let right: CGFloat = isCompact ? 500 : 480
            let offset = CGPoint(x: size.width - right * scale, y: size.height - Art.height * scale)
            func map(_ point: CGPoint) -> CGPoint {
                CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
            }
            func shape(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points.map(map))
                path.closeSubpath()
                return path
            }

            context.fill(shape(Art.farHills), with: .color(Ink.far))
            let body = shape(Art.body)
            let shade = shape(Art.shadeFace)
            context.fill(body, with: .color(Ink.mid))
            context.fill(shape(Art.litFace), with: .color(Ink.lit))
            context.fill(shade, with: .color(Ink.shade))
            var onPeak = context
            onPeak.clip(to: body)
            onPeak.fill(shape(Art.cap), with: .color(Ink.snow))
            var inShade = onPeak
            inShade.clip(to: shade)
            inShade.fill(shape(Art.cap), with: .color(Ink.snowShade))
            context.fill(shape(Art.nearHills), with: .color(Ink.near))

            for gull in isCompact ? Self.compactGulls : Self.gulls {
                context.stroke(
                    Self.gull(at: map(gull.at), size: gull.size),
                    with: .color(.white.opacity(gull.opacity)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// A gull in flight, 20 points across at size 1: two arched wings and a
    /// small dip where they meet.
    static func gull(at origin: CGPoint, size k: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * k, y: origin.y + y * k) }
        var path = Path()
        path.move(to: p(0, 0))
        path.addCurve(to: p(9, -2.4), control1: p(3, -4.5), control2: p(6.5, -5.2))
        path.addQuadCurve(to: p(11, -2.4), control: p(10, -1.3))
        path.addCurve(to: p(20, 0), control1: p(13.5, -5.2), control2: p(17, -4.5))
        return path
    }
}
