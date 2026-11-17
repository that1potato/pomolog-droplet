//
//  Peaks.swift
//  Pomodorolog
//
//  The mountains there are to climb. Any of them can be picked, in any
//  order, and climbed again; Climb.swift works out each climb. Foundation
//  only.
//

import Foundation

struct Peak: Equatable, Sendable {
    /// Saved with a pick, so a pick keeps its peak whatever the list's order.
    let id: String
    let name: String
    /// Where it stands, as the expedition log writes it.
    let region: String
    /// Its height in metres, from foot to top.
    let height: Double
}

enum Peaks {
    /// In the order the expedition log lists them.
    static let all: [Peak] = [
        Peak(id: "ben-nevis", name: "Ben Nevis", region: "Scotland", height: 1345),
        Peak(id: "mount-fuji", name: "Mount Fuji", region: "Japan", height: 3776),
        Peak(id: "mont-blanc", name: "Mont Blanc", region: "France and Italy", height: 4808),
        Peak(id: "kilimanjaro", name: "Kilimanjaro", region: "Tanzania", height: 5895),
        Peak(id: "aconcagua", name: "Aconcagua", region: "Argentina", height: 6961),
        Peak(id: "everest", name: "Everest", region: "Nepal and China", height: 8849),
        Peak(id: "olympus-mons", name: "Olympus Mons", region: "Mars", height: 21900),
    ]

    /// Where the peak with this id is in `all`, or nil for an id this version
    /// doesn't know.
    static func index(of id: String) -> Int? {
        all.firstIndex { $0.id == id }
    }
}
