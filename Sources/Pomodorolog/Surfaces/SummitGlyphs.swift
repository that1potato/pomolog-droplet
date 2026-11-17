//
//  SummitGlyphs.swift
//  Pomodorolog
//
//  Each peak's own sticker: its silhouette drawn as a symbol, on a disc 100
//  units across. The snow line and the gap around a nearer peak are cut out of
//  the ink, so the disc shows through them whatever its colour. The path data
//  is the approved design's (shots/climb-picker-design/stickericons.py),
//  number for number.
//

import SwiftUI

/// One peak's symbol as SVG path data, in a 100 × 100 disc with the ground at
/// y 70.
struct SummitGlyphArt: Sendable {
    let body: String
    /// Cut out of the body as a line.
    var snow: String?
    /// A nearer peak, set apart from the body by a gap.
    var front: String?
    /// Mars's moons.
    var moons: [CGRect] = []

    /// In the order of `Peaks.all`.
    static let all: [SummitGlyphArt] = [benNevis, mountFuji, montBlanc, kilimanjaro, aconcagua, everest, olympusMons]

    /// The great hump, its foothill in front.
    static let benNevis = SummitGlyphArt(
        body: "M12,70 C14.5,58 20,47.5 28.5,40.5 C33.5,36.4 38.5,34 43.5,33.6 C49.5,33.2 55.5,35.6 60.5,40.5 C66.5,46.4 71,55 73,70 Z",
        snow: "M31.5,44.5 L37,48.5 L42,43.5 L47,48.5 L52.5,44",
        front: "M47,70 C51,64.5 57,60 65,58.2 C73,56.4 81,58 86.5,62.5 C88.5,64.3 89.6,66.8 90.5,70 Z"
    )

    /// The concave cone and its flat crater rim.
    static let mountFuji = SummitGlyphArt(
        body: "M12,70 C26,67 35,59 41,47 L45.5,35 Q46.6,32.6 49,32.6 L51,32.6 Q53.4,32.6 54.5,35 L59,47 C65,59 74,67 88,70 Z",
        snow: "M40,49.5 L44,45.5 L47,51.5 L50,45.5 L53,51.5 L56,45.5 L60,49.5"
    )

    /// The snow dome, the Aiguille de Bionnassay's needle in front.
    static let montBlanc = SummitGlyphArt(
        body: "M14,70 C17,58 25,47 35,41 C43,36.5 52,34.5 60,35.5 C68,36.5 75,42 79,50 C81,54 82,60 82.5,70 Z",
        snow: "M29,51.5 L35.5,46 L41,51.5 L47,45 L53,50.5",
        front: "M59,70 L69,44 Q71,39.5 73,44 L83,70 Z"
    )

    /// Kibo's long flat top under its glaciers, Mawenzi's crags in front.
    static let kilimanjaro = SummitGlyphArt(
        body: "M30,70 C35,62 40,54 45,47 C48,43 51,41 55,40.5 L71,40 C74.5,40 77,41.5 79,44.5 C83,50.5 86,59 89,70 Z",
        snow: "M51,47.5 L56.5,43.5 L62,48.5 L67.5,43.5 L73,48",
        front: "M11,70 L16,59 L19.5,52 Q20.6,50 21.8,52 L23.4,55 L25.6,49.5 Q26.7,47.5 27.9,49.5 L31,56.5 L36,70 Z"
    )

    /// The great massif and its two summits.
    static let aconcagua = SummitGlyphArt(
        body: "M12,70 C18,61 24,52 31,44 L38.5,35.5 Q41,33 43.6,34.6 L48.6,37.8 L53.6,35 Q56.2,33.6 58.6,35.8 L64,41 C71,48 79,58 88,70 Z",
        snow: "M32,47.5 L38.5,42.5 L44.5,48.5 L50.5,41.5 L56.5,48 L62.5,43.5"
    )

    /// The pyramid and its north-east shoulder, Changtse in front.
    static let everest = SummitGlyphArt(
        body: "M24,70 L38.5,49.5 L47.4,34.4 Q50,30 52.6,34.4 L60.4,47.6 Q62.2,50.4 65.4,50.4 L71,50.4 Q73.8,50.4 75.4,52.6 L88,70 Z",
        snow: "M42.5,47.5 L46.5,43 L50,49 L53.5,43 L57.5,47.5",
        front: "M9,70 L23.4,54.2 Q26,51.4 28.6,54.2 L43,70 Z"
    )

    /// The vast shield ringed by its cliffs, the caldera at its top, and
    /// Mars's two moons.
    static let olympusMons = SummitGlyphArt(
        body: "M10,70 L13,62 Q14,59.5 16.5,59 C26,57 36,53.5 44,50.5 Q46.5,49.6 47.6,51.6 Q50,54.6 52.4,51.6 Q53.5,49.6 56,50.5 C64,53.5 74,57 83.5,59 Q86,59.5 87,62 L90,70 Z",
        moons: [
            CGRect(x: 24.6, y: 30.6, width: 10.8, height: 10.8),
            CGRect(x: 42.2, y: 24.7, width: 5.6, height: 5.6),
        ]
    )
}

/// A peak's symbol as paths, parsed once.
struct SummitGlyphShapes: Sendable {
    let body: Path
    let snow: Path?
    let front: Path?
    let moons: [CGRect]

    init(_ art: SummitGlyphArt) {
        body = SVGPath.path(art.body)
        snow = art.snow.map(SVGPath.path)
        front = art.front.map(SVGPath.path)
        moons = art.moons
    }

    static let all: [SummitGlyphShapes] = SummitGlyphArt.all.map(SummitGlyphShapes.init)
}

/// A peak's symbol, filling a disc the size of its frame. The cut-outs are
/// transparent, so the disc behind shows through them.
struct SummitGlyph: View {
    let peak: Int
    var ink: Color = Color.black.opacity(0.78)

    /// The width of the snow line and of the gap around a nearer peak, in disc
    /// units.
    static let gap: CGFloat = 3.8
    /// A hair of stroke in the ink itself rounds every corner, as a symbol's are.
    static let softening: CGFloat = 1.2

    var body: some View {
        Canvas { context, size in
            guard SummitGlyphShapes.all.indices.contains(peak) else { return }
            let shapes = SummitGlyphShapes.all[peak]
            let scale = min(size.width, size.height) / 100
            context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let ink = ink
            context.drawLayer { layer in
                let soft = StrokeStyle(lineWidth: Self.softening, lineJoin: .round)
                layer.fill(shapes.body, with: .color(ink))
                layer.stroke(shapes.body, with: .color(ink), style: soft)
                var cut = layer
                cut.blendMode = .clear
                if let snow = shapes.snow {
                    cut.stroke(snow, with: .color(.black), style: StrokeStyle(lineWidth: Self.gap, lineCap: .round, lineJoin: .round))
                }
                if let front = shapes.front {
                    cut.stroke(front, with: .color(.black), style: StrokeStyle(lineWidth: Self.gap * 2, lineJoin: .round))
                    layer.fill(front, with: .color(ink))
                    layer.stroke(front, with: .color(ink), style: soft)
                }
                for moon in shapes.moons {
                    layer.fill(Path(ellipseIn: moon), with: .color(ink))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// `×2`: how many times a peak's sticker has been earned, at its disc's
/// lower right.
struct StickerCount: View {
    let count: Int
    /// The ring that sets it apart from the disc: the colour behind the
    /// sticker, or none.
    var ring: Color?

    var body: some View {
        Text(verbatim: "×\(count)")
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background {
                Capsule().fill(Color(hex: "#1C1C1E"))
                if let ring {
                    Capsule().stroke(ring, lineWidth: 1.5)
                }
            }
            .accessibilityLabel("Earned \(count) times")
    }
}
