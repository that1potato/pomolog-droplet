//
//  PeakIcons.swift
//  Pomodorolog
//
//  An icon for each peak, drawn from its real outline: Ben Nevis's broad
//  hump with snow in its gullies, Fuji's cone, Mont Blanc's snow dome behind
//  the Chamonix needles, Kibo's flat top with Mawenzi beside it, Aconcagua's
//  two summits, Everest beside Lhotse with its plume, and Olympus Mons, a
//  shield far wider than it is tall, under Mars's two moons. Flat tones: a
//  lit side, a shaded side and snow.
//

import SwiftUI

/// One peak's artwork as SVG path data, in a 100 × 60 box with the ground at
/// y 58. The data is the approved design's, number for number.
struct PeakArt: Sendable {
    let silhouette: String
    /// The side in shadow, drawn inside the silhouette.
    let shade: String
    /// Drawn inside the silhouette.
    var snow: String?
    /// A nearer ridge drawn over the peak: Mont Blanc's needles, Mawenzi.
    var front: String?
    /// Everest's.
    var plume: String?
    /// Phobos and Deimos.
    var moons: [CGRect] = []
    /// Painted in Mars's colours.
    var isMars = false

    static let box = CGSize(width: 100, height: 60)
    static let ground: CGFloat = 58

    /// In the order of `Peaks.all`.
    static let all: [PeakArt] = [benNevis, fuji, montBlanc, kilimanjaro, aconcagua, everest, olympusMons]

    static let benNevis = PeakArt(
        silhouette: "M2,58 C16,55 26,46 36,35 C44,27 51,22 59,20.8 C64,20.2 68,21.2 71,23.6 C75,27.4 78,34 82,40.5 C86.5,47.5 92,53.5 98,58 Z",
        shade: "M61,0 L61,19 C66,30 70,44 70,60 L100,60 L100,0 Z",
        snow: "M42,29 C49,22.5 56,20.2 63,20.2 C67.5,20.4 71,22.4 73.6,25.4 C71.6,26 70.2,27.4 69.4,30.4 C68.2,27.6 66.4,26.4 63.8,26.6 C61,26.8 59.8,28.8 58.8,31 C57.4,28 55,27 51.6,27.6 C48.4,28.2 45.4,29.6 42,29 Z M74.5,28 C76.4,31.6 77.8,35 78.6,38.6 C77.8,39 77.1,38.8 76.7,38.2 C76,34.8 75,31.8 73.4,28.6 Z"
    )

    static let fuji = PeakArt(
        silhouette: "M2,58 C24,54 34,40 42,18 C43,15.6 44.6,14 46.6,14 L53.4,14 C55.4,14 57,15.6 58,18 C66,40 76,54 98,58 Z",
        shade: "M52,0 L52,13 C55,30 60,46 66,60 L100,60 L100,0 Z",
        snow: "M20,0 L80,0 L80,31 Q66.5,29.5 64.6,31.6 Q61.6,26 59.6,33.2 Q56.6,26 54,34.2 Q51,26.4 48,33.6 Q45,26.4 42.4,32.2 Q39.4,26.4 36.6,31.2 Q34,29.4 20,31 Z"
    )

    static let montBlanc = PeakArt(
        silhouette: "M2,58 C10,51 18,43 28,37 C38,30.5 46,18 58,15.6 C68,14 78,20 85,30 C90,38 94,48 98,58 Z",
        shade: "M60,0 L60,15 C64,28 67,44 67,60 L100,60 L100,0 Z",
        snow: "M0,0 L100,0 L100,47 Q93,41.5 89,47 Q85,39.5 79,45 Q73,37.5 67,43 Q61,35.5 55,41 Q49,34.5 43,40 Q37,35.5 31,40.5 Q24,37.5 0,42.5 Z",
        front: "M7,58 L14.5,42 C15,41 15.6,41 16,42 L17.4,45 L21,31.5 C21.3,30.6 21.9,30.6 22.2,31.5 L24.6,39 L26.4,35.6 C26.7,35 27.2,35 27.5,35.6 L31,46 L33.2,42.6 C33.5,42.1 34,42.1 34.3,42.6 L39,58 Z"
    )

    static let kilimanjaro = PeakArt(
        silhouette: "M2,58 C14,54.5 22,45 30,35 C34,30 38,26 44,24.8 C50,23.8 60,23.8 66,24.8 C71,25.6 74,27.4 76.5,31 C80.5,37 84.5,44.5 90,50.5 C93,53.5 95.5,56 98,58 Z",
        shade: "M64,0 L64,23 C68,34 71,46 72,60 L100,60 L100,0 Z",
        snow: "M36,0 L74,0 L74,27.4 Q70.5,27 69.5,30 Q68.2,27.4 64,27.8 Q61.6,28 60.6,31 Q59.4,28.2 55.5,28.4 Q52.4,28.6 51.4,30.6 Q50.2,28 46.4,28 Q44,28.2 43,30.2 Q41.8,27.6 36,27.8 Z",
        front: "M64,58 C69,52 72.5,46.5 75.5,41.5 L77.6,37.4 C77.9,36.8 78.4,36.8 78.7,37.4 L79.8,39.6 L81.6,34.4 C81.9,33.7 82.5,33.7 82.8,34.4 L84.4,38.6 L85.6,36.8 C85.9,36.4 86.4,36.4 86.7,36.8 L88.6,41.6 C91.5,47 94.8,53 98,58 Z"
    )

    static let aconcagua = PeakArt(
        silhouette: "M2,58 C12,52 20,44 27,35.5 C31,30 35,22 39,17 C40.4,15.2 42.4,14.6 44,15.6 C46,16.9 47.6,19.6 49.6,20.1 C51.6,20.6 53.6,18.6 55.6,18.3 C57.6,18 59.2,19.6 61.2,22.2 C68,31 78,42 88,50 C92,53 95,56 98,58 Z",
        shade: "M43,0 L43,14 C47,28 50,44 50,60 L100,60 L100,0 Z",
        snow: "M28,0 L70,0 L70,25 Q66,23.6 64,27 Q61,22.8 58,26 Q55,22.6 52,26.4 Q49,22.4 46,25.6 Q43,21.8 40,25 Q36,21.6 33,24.6 Q30,23 28,24 Z M60,21 C66,28 72,36 78,44 C76.6,44.8 75,44.6 74,43.6 C68.6,36.6 63.6,30.4 58,24 Z"
    )

    static let everest = PeakArt(
        silhouette: "M2,58 C12,53 20,46.5 28,40.5 C33,36.5 36,33 39,28 C42.2,22.4 45.2,14.6 48.2,8.2 C48.9,6.8 50.1,6.8 50.8,8.2 C53.8,14.4 57,20.2 61,25.2 C63,27.6 65,28.6 67,28.1 C69,27.6 70.8,24.4 72.8,21.8 C73.6,20.8 74.6,20.8 75.4,21.8 C79.6,28 85.6,39.6 91.6,49.6 C93.6,52.8 95.8,55.6 98,58 Z",
        shade: "M50,0 L50,7 C53,24 55,42 54,60 L100,60 L100,0 Z",
        snow: "M36,0 L64,0 L64,24 Q60.6,21.4 58.6,25.4 Q56.4,19.4 54,24.6 Q51.8,17.4 49.6,22.6 Q47.4,18 45.2,23.4 Q42.8,20.4 40.4,24.6 Q38,22.8 36,24 Z M69,0 L82,0 L82,27.5 Q79,25 77.4,28.6 Q75.8,24.2 73.8,27.6 Q72.2,25.4 69,27 Z",
        plume: "M51,8.2 C57,5.6 66,4.8 78,6.4 C70,7.6 61,9 52.4,10.4 Z"
    )

    static let olympusMons = PeakArt(
        silhouette: "M2,58 L3.6,52.4 C4.1,50.8 5.6,49.6 8.2,49.1 C22,46.4 34,38.6 42,33 C44,31.6 45.6,31 47.2,31.2 L48.6,32.4 L51.4,32.4 L52.8,31.2 C54.4,31 56,31.6 58,33 C66,38.6 78,46.4 91.8,49.1 C94.4,49.6 95.9,50.8 96.4,52.4 L98,58 Z",
        shade: "M51,0 L51,31 C55,40 57,50 58,60 L100,60 L100,0 Z",
        moons: [
            CGRect(x: 77.8, y: 15.8, width: 4.4, height: 4.4),
            CGRect(x: 87.6, y: 9.6, width: 2.8, height: 2.8),
        ],
        isMars: true
    )
}

/// A peak's art as paths, parsed once.
struct PeakShapes: Sendable {
    let silhouette: Path
    let shade: Path
    let snow: Path?
    let front: Path?
    let plume: Path?
    let moons: [CGRect]
    let isMars: Bool
    /// The top of the silhouette, where the climb's fill ends.
    let summitY: CGFloat

    init(_ art: PeakArt) {
        silhouette = SVGPath.path(art.silhouette)
        shade = SVGPath.path(art.shade)
        snow = art.snow.map(SVGPath.path)
        front = art.front.map(SVGPath.path)
        plume = art.plume.map(SVGPath.path)
        moons = art.moons
        isMars = art.isMars
        summitY = silhouette.cgPath.boundingBoxOfPath.minY
    }

    static let all: [PeakShapes] = PeakArt.all.map(PeakShapes.init)

    /// Where the fill stops for `fraction` of the way up.
    func fillLine(at fraction: Double) -> CGFloat {
        let clamped = CGFloat(min(max(fraction, 0), 1))
        return summitY + (1 - clamped) * (PeakArt.ground - summitY)
    }
}

/// The inks an icon is drawn in.
struct PeakPalette: Sendable {
    let rock: Color
    let rockShade: Color
    let snow: Color
    let snowShade: Color
    let plume: Color
    let marsRock: Color
    let marsShade: Color
    /// Around an inked peak.
    let outline: Color
    /// A peak not reached yet, in outline only.
    let pencil: Color

    /// Inks on the journal's cream paper.
    static let journal = PeakPalette(
        rock: Color(hex: "#5F6F7D"),
        rockShade: Color(hex: "#46535F"),
        snow: .white,
        snowShade: Color(hex: "#D8E0E8"),
        plume: Color(hex: "#C5CFD9"),
        marsRock: Color(hex: "#C4683E"),
        marsShade: Color(hex: "#9C4B2B"),
        outline: Color(hex: "#3F4A55"),
        pencil: Color(hex: "#B3A992")
    )
}

/// A peak's icon, scaled to fit the frame it is given.
struct PeakIcon: View {
    enum Style: Equatable {
        /// Reached: inked in.
        case inked
        /// Not reached yet: a pencil outline.
        case pencil
        /// Being climbed: inked up to this fraction of its height, pencil above.
        case climbing(Double)
    }

    let index: Int
    let style: Style
    var palette: PeakPalette = .journal

    /// Outline width in points, whatever the icon's size.
    private static let line: CGFloat = 1.2

    var body: some View {
        Canvas { context, size in
            let shapes = PeakShapes.all[index]
            let scale = min(size.width / PeakArt.box.width, size.height / PeakArt.box.height)
            var context = context
            context.translateBy(
                x: (size.width - PeakArt.box.width * scale) / 2,
                y: (size.height - PeakArt.box.height * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)
            switch style {
            case .inked:
                ink(shapes, scale: scale, in: context)
            case .pencil:
                pencil(shapes, scale: scale, in: context)
            case .climbing(let fraction):
                pencil(shapes, scale: scale, in: context)
                var lower = context
                let line = shapes.fillLine(at: fraction)
                lower.clip(to: Path(CGRect(x: -10, y: line, width: PeakArt.box.width + 20, height: PeakArt.box.height)))
                ink(shapes, scale: scale, in: lower)
            }
        }
        .accessibilityHidden(true)
    }

    private func ink(_ shapes: PeakShapes, scale: CGFloat, in context: GraphicsContext) {
        let rock = shapes.isMars ? palette.marsRock : palette.rock
        let shade = shapes.isMars ? palette.marsShade : palette.rockShade
        let outline = StrokeStyle(lineWidth: Self.line / scale, lineJoin: .round)

        context.fill(shapes.silhouette, with: .color(rock))
        var inside = context
        inside.clip(to: shapes.silhouette)
        inside.fill(shapes.shade, with: .color(shade))
        if let snow = shapes.snow {
            inside.fill(snow, with: .color(palette.snow))
            var shaded = inside
            shaded.clip(to: shapes.shade)
            shaded.fill(snow, with: .color(palette.snowShade))
        }
        context.stroke(shapes.silhouette, with: .color(palette.outline), style: outline)
        if let front = shapes.front {
            context.fill(front, with: .color(rock))
            context.stroke(front, with: .color(palette.outline), style: outline)
        }
        if let plume = shapes.plume {
            context.fill(plume, with: .color(palette.plume.opacity(0.85)))
        }
        for moon in shapes.moons {
            let disc = Path(ellipseIn: moon)
            context.fill(disc, with: .color(shade))
            context.stroke(disc, with: .color(palette.outline), style: StrokeStyle(lineWidth: 1 / scale))
        }
    }

    private func pencil(_ shapes: PeakShapes, scale: CGFloat, in context: GraphicsContext) {
        let line = StrokeStyle(lineWidth: Self.line / scale, lineJoin: .round)
        context.stroke(shapes.silhouette, with: .color(palette.pencil), style: line)
        if let front = shapes.front {
            context.stroke(front, with: .color(palette.pencil), style: line)
        }
        for moon in shapes.moons {
            context.stroke(Path(ellipseIn: moon), with: .color(palette.pencil), style: StrokeStyle(lineWidth: 1 / scale))
        }
    }
}
