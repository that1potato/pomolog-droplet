//
//  PeakIcons.swift
//  Pomodorolog
//
//  An icon for each peak, cut down from the view the summit widget draws:
//  Ben Nevis's dome above its foothill, Fuji's broad cone, Mont Blanc's long
//  ridge behind the Aiguille de Bionnassay, Mawenzi beside flat-topped Kibo,
//  Aconcagua's south face, Everest's north face behind Changtse, and Olympus
//  Mons, a low shield with a scarp and a caldera, under Mars's two moons.
//  Straight edges and flat ink, with a sketched hand: the shaded side is
//  hatched, the outline is gone over twice, and the ground is one loose line.
//

import SwiftUI

/// One peak's artwork as SVG path data, in a 100 × 60 box with the ground at
/// y 56. The data is the approved design's, number for number.
struct PeakArt: Sendable {
    let silhouette: String
    /// The side in shadow, hatched inside the silhouette.
    let shade: String
    /// Drawn inside the silhouette.
    var snow: String?
    /// A nearer hill or peak drawn over this one: Ben Nevis's foothill, the
    /// Aiguille de Bionnassay, Changtse.
    var front: String?
    /// Phobos and Deimos.
    var moons: [CGRect] = []
    /// Painted in Mars's colours.
    var isMars = false

    static let box = CGSize(width: 100, height: 60)
    static let ground: CGFloat = 56

    /// In the order of `Peaks.all`.
    static let all: [PeakArt] = [benNevis, fuji, montBlanc, kilimanjaro, aconcagua, everest, olympusMons]

    static let benNevis = PeakArt(
        silhouette: "M8,56 L20,40 L27,30 L31,24 L34,19 L44,15 L56,13 L68,15 L78,22 L88,32 L96,40 L96,56 Z",
        shade: "M8,56 L20,40 L27,30 L31,24 L34,19 L37,28 L33,42 L28,56 Z M68,15 L78,22 L88,32 L96,40 L96,56 L80,56 L74,34 Z",
        snow: "M34,19 L44,15 L56,13 L68,15 L74,19 L68,19 L62,23 L55,18 L48,23 L41,19 Z",
        front: "M2,56 L18,50 L36,46 L52,45 L68,47 L84,52 L98,56 Z"
    )

    static let fuji = PeakArt(
        silhouette: "M2,56 L16,52 L30,45 L40,36 L47,26 L52,17 L54,14 L57,13 L60,14 L63,13 L66,14 L68,17 L73,26 L80,36 L90,45 L98,50 L98,56 Z",
        shade: "M60,14 L63,13 L66,14 L68,17 L73,26 L80,36 L90,45 L98,50 L98,56 L70,56 L64,36 Z",
        snow: "M47,26 L52,17 L54,14 L57,13 L60,14 L63,13 L66,14 L68,17 L73,26 L70,24 L68,30 L64,23 L60,31 L56,23 L52,29 L50,24 Z"
    )

    static let montBlanc = PeakArt(
        silhouette: "M2,56 L12,50 L24,42 L34,36 L40,28 L44,26 L52,23 L60,21 L66,22 L72,18 L78,15 L82,14 L86,16 L92,22 L98,30 L98,56 Z",
        shade: "M82,14 L86,16 L92,22 L98,30 L98,56 L86,56 L84,34 Z",
        snow: "M40,28 L44,26 L52,23 L60,21 L66,22 L72,18 L78,15 L82,14 L86,16 L92,22 L98,30 L98,40 L90,36 L84,42 L76,34 L68,40 L60,32 L52,36 L46,30 Z",
        front: "M76,56 L83,40 L88,28 L91,22 L94,28 L98,36 L98,56 Z"
    )

    static let kilimanjaro = PeakArt(
        silhouette: "M2,56 L10,53 L18,48 L23,42 L26,38 L28,36 L30,37.5 L32,36.5 L35,40 L40,42 L48,42 L55,39 L62,32 L67,25 L70,21 L74,20 L78,19 L82,20 L86,21 L90,27 L95,35 L98,40 L98,56 Z",
        shade: "M78,19 L82,20 L86,21 L90,27 L95,35 L98,40 L98,56 L84,56 L80,36 Z M28,36 L30,37.5 L32,36.5 L35,40 L40,42 L40,56 L30,56 Z",
        snow: "M67,25 L70,21 L74,20 L78,19 L82,20 L86,21 L89,25 L86,24 L84,28 L81,23 L78,29 L75,23 L72,27 L70,24 Z"
    )

    static let aconcagua = PeakArt(
        silhouette: "M4,56 L14,44 L22,36 L30,28 L38,22 L44,19 L47,18 L52,20 L58,21 L64,20 L72,19 L78,18.5 L82,20 L87,26 L93,34 L98,40 L98,56 Z",
        shade: "M78,18.5 L82,20 L87,26 L93,34 L98,40 L98,56 L80,56 L78,36 Z",
        snow: "M38,22 L44,19 L47,18 L52,20 L58,21 L64,20 L72,19 L78,18.5 L82,20 L87,26 L84,31 L79,29 L74,35 L68,31 L62,37 L56,32 L50,38 L45,31 L41,29 Z"
    )

    static let everest = PeakArt(
        silhouette: "M2,56 L14,50 L24,44 L32,38 L40,32 L48,28 L56,25 L62,22 L66,18 L69,15 L71,11 L74,16 L78,22 L84,29 L90,33 L98,33 L98,56 Z",
        shade: "M71,11 L74,16 L78,22 L84,29 L90,33 L98,33 L98,56 L78,56 L74,34 Z",
        snow: "M40,32 L48,28 L56,25 L62,22 L66,18 L69,15 L71,11 L74,16 L78,22 L84,29 L80,31 L76,26 L72,32 L68,24 L62,30 L54,29 L46,34 Z",
        front: "M30,56 L38,46 L52,40 L68,31 L80,40 L92,50 L96,56 Z"
    )

    static let olympusMons = PeakArt(
        silhouette: "M2,56 L3,51 L6,47 L14,45 L28,40 L40,35.5 L46,33.5 L48,35.5 L56,35.5 L58,33.5 L64,35.5 L76,40 L90,45 L96,47 L98,51 L99,56 Z",
        shade: "M52,35.5 L56,35.5 L58,33.5 L64,35.5 L76,40 L90,45 L96,47 L98,51 L99,56 L56,56 Z",
        moons: [CGRect(x: 20.4, y: 20.4, width: 3.2, height: 3.2), CGRect(x: 28.9, y: 15.9, width: 2.2, height: 2.2)],
        isMars: true
    )
}

/// A peak's art as paths, parsed once.
struct PeakShapes: Sendable {
    let silhouette: Path
    let shade: Path
    let snow: Path?
    let front: Path?
    let moons: [CGRect]
    let isMars: Bool
    /// The top of the silhouette, where the climb's fill ends.
    let summitY: CGFloat

    init(_ art: PeakArt) {
        silhouette = SVGPath.path(art.silhouette)
        shade = SVGPath.path(art.shade)
        snow = art.snow.map(SVGPath.path)
        front = art.front.map(SVGPath.path)
        moons = art.moons
        isMars = art.isMars
        summitY = silhouette.cgPath.boundingBoxOfPath.minY
    }

    static let all: [PeakShapes] = PeakArt.all.map(PeakShapes.init)

    /// The hatching of a shaded side: loose strokes leaning the same way,
    /// none quite the length of the next. Clipped to each peak's shade.
    static let hatch: Path = {
        var path = Path()
        for x in stride(from: -30, to: 100, by: 4) {
            // Swift's remainder keeps the sign, so fold it back to 0 and up.
            let a = CGFloat(((x % 3) + 3) % 3)
            let b = CGFloat(((x % 5) + 5) % 5)
            let c = CGFloat(((x % 4) + 4) % 4)
            path.move(to: CGPoint(x: CGFloat(x), y: 58 - a))
            path.addLine(to: CGPoint(x: CGFloat(x) + 30 + b, y: 4 + c))
        }
        return path
    }()

    /// The ground under every peak, drawn in one stroke.
    static let groundLine: Path = {
        var path = Path()
        path.addLines([CGPoint(x: 0, y: 56.5), CGPoint(x: 24, y: 55.9), CGPoint(x: 62, y: 56.4), CGPoint(x: 100, y: 55.8)])
        return path
    }()

    /// How far the second pass of the pen lands from the first.
    static let secondPass = CGSize(width: 0.9, height: 0.7)

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
    let marsRock: Color
    let marsShade: Color
    /// Around Olympus Mons, and its hatching.
    let marsOutline: Color
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
        marsRock: Color(hex: "#C4683E"),
        marsShade: Color(hex: "#9C4B2B"),
        marsOutline: Color(hex: "#7E3A20"),
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
        let pen = shapes.isMars ? palette.marsOutline : palette.outline
        let outline = StrokeStyle(lineWidth: Self.line / scale, lineJoin: .round)

        context.fill(shapes.silhouette, with: .color(rock))
        var inside = context
        inside.clip(to: shapes.silhouette)
        // The shaded side is hatched, not filled.
        var shaded = inside
        shaded.clip(to: shapes.shade)
        shaded.stroke(PeakShapes.hatch, with: .color(pen), style: StrokeStyle(lineWidth: 1 / scale, lineCap: .round))
        if let snow = shapes.snow {
            inside.fill(snow, with: .color(palette.snow))
            shaded.fill(snow, with: .color(palette.snowShade))
            inside.stroke(snow, with: .color(pen.opacity(0.7)), style: StrokeStyle(lineWidth: 0.7 / scale, lineJoin: .round))
        }
        context.stroke(shapes.silhouette, with: .color(pen), style: outline)
        secondPass(shapes.silhouette, in: context, color: pen, scale: scale)
        if let front = shapes.front {
            context.fill(front, with: .color(rock))
            context.stroke(front, with: .color(pen), style: outline)
        }
        context.stroke(PeakShapes.groundLine, with: .color(pen), style: StrokeStyle(lineWidth: 0.9 / scale, lineCap: .round))
        for moon in shapes.moons {
            let disc = Path(ellipseIn: moon)
            context.fill(disc, with: .color(shade))
            context.stroke(disc, with: .color(pen), style: StrokeStyle(lineWidth: 1 / scale))
        }
    }

    private func pencil(_ shapes: PeakShapes, scale: CGFloat, in context: GraphicsContext) {
        let line = StrokeStyle(lineWidth: Self.line / scale, lineJoin: .round)
        context.stroke(PeakShapes.groundLine, with: .color(palette.pencil), style: StrokeStyle(lineWidth: 0.9 / scale, lineCap: .round))
        // The peak stops where a nearer one stands in front of it.
        var behind = context
        if let front = shapes.front {
            behind.clip(to: front, options: .inverse)
        }
        secondPass(shapes.silhouette, in: behind, color: palette.pencil, scale: scale)
        behind.stroke(shapes.silhouette, with: .color(palette.pencil), style: line)
        if let snow = shapes.snow {
            var inside = behind
            inside.clip(to: shapes.silhouette)
            inside.stroke(snow, with: .color(palette.pencil), style: line)
        }
        if let front = shapes.front {
            context.stroke(front, with: .color(palette.pencil), style: line)
        }
        for moon in shapes.moons {
            context.stroke(Path(ellipseIn: moon), with: .color(palette.pencil), style: StrokeStyle(lineWidth: 1 / scale))
        }
    }

    /// The outline gone over again, a little off the first line and fainter.
    private func secondPass(_ path: Path, in context: GraphicsContext, color: Color, scale: CGFloat) {
        var second = context
        second.translateBy(x: PeakShapes.secondPass.width, y: PeakShapes.secondPass.height)
        second.stroke(path, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8 / scale, lineJoin: .round))
    }
}
