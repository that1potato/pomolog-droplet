//
//  Peaks.swift
//  Pomodorolog
//
//  The mountains the climb goes up, in order, and where a total climb puts
//  you. Each peak is climbed from its foot, and what's left over carries on to
//  the next. After the last, the range starts again as a second ascent.
//  Foundation only.
//

import Foundation

struct Peak: Equatable, Sendable {
    let name: String
    /// Its height in metres, from foot to top.
    let height: Double
}

enum Peaks {
    static let all: [Peak] = [
        Peak(name: "Ben Nevis", height: 1345),
        Peak(name: "Mount Fuji", height: 3776),
        Peak(name: "Mont Blanc", height: 4808),
        Peak(name: "Kilimanjaro", height: 5895),
        Peak(name: "Aconcagua", height: 6961),
        Peak(name: "Everest", height: 8849),
        Peak(name: "Olympus Mons", height: 21900),
    ]

    /// Metres from the foot of the first peak to the top of the last: 53,534.
    static let rangeHeight: Double = all.reduce(0) { $0 + $1.height }

    /// Where a total climb of `altitude` metres puts you.
    static func position(at altitude: Double) -> PeakPosition {
        let total = max(0, altitude)
        let laps = Int(total / rangeHeight)
        var rest = total - Double(laps) * rangeHeight
        for (index, peak) in all.enumerated() {
            if rest < peak.height {
                return PeakPosition(ascent: laps + 1, index: index, metres: rest)
            }
            rest -= peak.height
        }
        // Rounding put it exactly at the top of the range: the next ascent.
        return PeakPosition(ascent: laps + 2, index: 0, metres: 0)
    }

    /// The total climb at the top of peak `index` on ascent `ascent` (from 1).
    static func top(ofPeak index: Int, ascent: Int) -> Double {
        Double(ascent - 1) * rangeHeight + all[...index].reduce(0) { $0 + $1.height }
    }

    /// The total climb at the foot of peak `index` on ascent `ascent`.
    static func foot(ofPeak index: Int, ascent: Int) -> Double {
        top(ofPeak: index, ascent: ascent) - all[index].height
    }
}

/// A place on the range.
struct PeakPosition: Equatable, Sendable {
    /// 1 the first time up the range, 2 for the second ascent, and so on.
    let ascent: Int
    let index: Int
    /// Metres climbed on this peak so far.
    let metres: Double

    var peak: Peak { Peaks.all[index] }
    var fraction: Double { metres / peak.height }
    var metresToGo: Double { peak.height - metres }
}
