//
//  Expeditions.swift
//  Pomodorolog
//
//  The climbs you pick. A pick is a peak and the moment you chose it. The
//  picks are saved beside the session log (ExpeditionStore), because the log
//  alone can't say which peak a focus climbed. Each pick starts a climb from
//  the peak's foot. Foundation only.
//

import Foundation

/// A peak picked to climb, and when.
struct ClimbPick: Codable, Equatable, Sendable {
    /// The peak's `Peak.id`.
    let peak: String
    let at: Date

    init(peak: String, at: Date) {
        self.peak = peak
        self.at = at
    }

    init(_ peak: Peak, at: Date) {
        self.init(peak: peak.id, at: at)
    }
}

/// The picks file's shape.
///
/// - 1: the picks, oldest first.
struct ExpeditionsDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var picks: [ClimbPick]
}

/// One climb: a pick, and how far up its peak the focus since has gone.
struct Expedition: Equatable, Sendable {
    let peakIndex: Int
    /// When it was picked.
    let pickedAt: Date
    /// Metres up the peak, at most its height.
    var metres: Double = 0
    /// When the session that reached the top ended. Nil while it's under way.
    var summitedAt: Date?

    var peak: Peak { Peaks.all[peakIndex] }
    var fraction: Double { min(max(metres / peak.height, 0), 1) }
    var metresToGo: Double { max(peak.height - metres, 0) }
    var isSummited: Bool { summitedAt != nil }
}
