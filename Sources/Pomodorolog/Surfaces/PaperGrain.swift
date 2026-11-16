//
//  PaperGrain.swift
//  Pomodorolog
//
//  The journal's paper: a fine, even speckle over the page colour, so the
//  cream reads as paper rather than a flat fill. The speckle lightens and
//  darkens the page alike (soft light), which keeps it clean. It is noise
//  made once from a fixed seed, so it looks the same on every launch and
//  needs no image in the bundle.
//

import CoreGraphics
import SwiftUI

enum PaperGrain {
    /// Samples a side. The tile repeats every 128pt.
    static let side = 160
    /// Points per sample: each speckle about 0.8pt across, the "Fine" grain.
    static let pointsPerSample: CGFloat = 0.8
    /// How far a sample strays from mid-grey, as a standard deviation.
    static let spread = 0.16
    /// How strongly the speckle shows: the "Medium" strength.
    static let opacity = 0.6

    /// Grey samples around mid-grey, the same every time.
    static let tile: CGImage? = makeTile()

    /// The tile as a fill, repeated across whatever shape it paints.
    static var paint: ImagePaint? {
        tile.map {
            ImagePaint(image: Image(decorative: $0, scale: 1).interpolation(.medium), scale: pointsPerSample)
        }
    }

    /// The samples, row by row. Split out so the spread can be tested.
    static func samples(seed: UInt64 = 0x5EED_9A9E_2026_1116) -> [UInt8] {
        var state = seed
        func next() -> Double {
            // SplitMix64.
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
        // The mean of two uniforms is a soft bell around the middle, with a
        // standard deviation of 0.204; scale it to the spread.
        let stretch = spread / 0.204
        return (0..<(side * side)).map { _ in
            let noise = (next() + next()) / 2
            let grey = min(max(0.5 + (noise - 0.5) * stretch, 0), 1)
            return UInt8((grey * 255).rounded())
        }
    }

    private static func makeTile() -> CGImage? {
        let data = Data(samples()) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

/// A page of the journal: the paper colour with its grain, in `shape`.
struct PaperPage<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            shape.fill(JournalInk.paper)
            if let grain = PaperGrain.paint {
                shape.fill(grain)
                    .blendMode(.softLight)
                    .opacity(PaperGrain.opacity)
            }
        }
        // Blends the grain with the paper alone, not with the shelf behind.
        .compositingGroup()
        .accessibilityHidden(true)
    }
}
