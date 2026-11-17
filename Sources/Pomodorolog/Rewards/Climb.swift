//
//  Climb.swift
//  Pomodorolog
//
//  Focus climbs the peak you picked, at 10 m for every counted minute, and a
//  focus that starts from a finished break climbs 20% further. That bonus
//  covers that one focus and never grows or stacks. Breaks never climb on
//  their own.
//
//  A focus counts toward the climb that's picked when it ends, so with
//  nothing picked it climbs nothing. A climb stops at the top, and the rest of
//  the focus that reached it is dropped. Picking another peak starts a new
//  climb from its foot and leaves the old one behind; picking the peak
//  already being climbed changes nothing.
//
//  It is worked out from the log and the picks alone, so every session ever
//  logged counts. Foundation only.
//

import Foundation

enum ClimbRules {
    /// Metres for each counted minute of focus.
    static let metresPerMinute: Double = 10
    /// How much further a focus started from a finished break climbs.
    static let breakBonus: Double = 0.2
    /// One session follows on from another when it starts within this many
    /// seconds of the other ending. Next hands over at once; Stop and then
    /// Start takes a moment.
    static let handoverSeconds: TimeInterval = 120
    /// A break that ran longer than this past zero was more than a break.
    static let breakOvertimeAllowance = 300
    /// A stopwatch run has no planned length, so it counts up to an hour.
    static let stopwatchCapSeconds = 3600

    /// The seconds of a session that climb. A countdown counts up to its
    /// planned length, so overtime doesn't climb and a forgotten timer can't
    /// carry anyone up a mountain. A stopwatch run counts up to an hour. Only
    /// focus climbs.
    static func countedSeconds(_ record: SessionRecord) -> Int {
        guard record.kind == .focus else { return 0 }
        if record.source == .stopwatch {
            return min(max(0, record.activeSeconds), stopwatchCapSeconds)
        }
        return max(0, record.countedSeconds)
    }

    static func metres(seconds: Int) -> Double {
        Double(seconds) / 60 * metresPerMinute
    }
}

/// One focus session's share of the climb.
struct ClimbStep: Equatable, Sendable {
    let recordID: UUID
    let day: String
    let endedAt: Date
    /// What the focus earned: its counted minutes, and the bonus from the
    /// break before it.
    let baseMetres: Double
    let bonusMetres: Double
    let startedFromBreak: Bool
    /// The climb it counted toward, as an index into `Climb.expeditions`.
    /// Nil when nothing was being climbed as it ended.
    let expedition: Int?
    /// The peak it climbed, and metres up it before and after. A session
    /// that climbed nothing has `before` equal to `after`.
    let peakIndex: Int?
    let before: Double
    let after: Double

    /// What it earned.
    var metres: Double { baseMetres + bonusMetres }
    /// What it climbed: what it earned, less anything past the top.
    var climbed: Double { after - before }
    /// The bonus leads, as the trail draws it, so a session cut short at the
    /// top keeps its bonus first.
    var climbedBonus: Double { min(bonusMetres, climbed) }
    var climbedFocus: Double { climbed - climbedBonus }
}

/// The top of a peak, reached.
struct Summit: Equatable, Sendable {
    let peakIndex: Int
    /// 1 the first time this peak's top is reached, 2 the next, and so on.
    let number: Int
    /// The session that reached the top, and when it ended.
    let recordID: UUID
    let date: Date
    /// The focus sessions of that climb, and the days they fell on.
    let sessions: Int
    let days: Int

    var peak: Peak { Peaks.all[peakIndex] }
}

/// One day's share of the climb: the metres climbed, and every focus that day
/// whether it climbed or not.
struct DayClimb: Equatable, Sendable {
    var focusMetres: Double = 0
    var bonusMetres: Double = 0
    var sessions = 0
    var startedFromBreak = 0

    var metres: Double { focusMetres + bonusMetres }
}

struct Climb: Equatable, Sendable {
    /// Every focus session's step, in the order they started.
    let steps: [ClimbStep]
    /// A climb for every pick that started one, oldest first.
    let expeditions: [Expedition]
    /// Every top reached, in order.
    let summits: [Summit]

    /// The latest climb, under way or at its top. Nil before the first pick.
    var latest: Expedition? { expeditions.last }
    /// The climb under way: the latest, until it reaches the top.
    var current: Expedition? { latest.flatMap { $0.isSummited ? nil : $0 } }

    init(records: [SessionRecord], picks: [ClimbPick]) {
        let timeline = Self.timeline(records)
        // Oldest first; two at the same moment keep the order they were saved in.
        let picks = picks.enumerated()
            .compactMap { offset, pick in Peaks.index(of: pick.peak).map { (index: $0, at: pick.at, offset: offset) } }
            .sorted { ($0.at, $0.offset) < ($1.at, $1.offset) }
        var expeditions: [Expedition] = []
        var steps: [ClimbStep] = []
        var next = 0
        for index in timeline.indices where timeline[index].kind == .focus {
            let record = timeline[index]
            // A focus counts toward the climb picked when it ends.
            while next < picks.count, picks[next].at <= record.endedAt {
                Self.take(picks[next].index, at: picks[next].at, into: &expeditions)
                next += 1
            }
            let fromBreak = Self.startsFromBreak(timeline, at: index)
            let base = ClimbRules.metres(seconds: ClimbRules.countedSeconds(record))
            let bonus = fromBreak ? base * ClimbRules.breakBonus : 0
            let advance = Self.advance(&expeditions, by: base + bonus, endedAt: record.endedAt)
            steps.append(ClimbStep(
                recordID: record.id,
                day: record.localDay,
                endedAt: record.endedAt,
                baseMetres: base,
                bonusMetres: bonus,
                startedFromBreak: fromBreak,
                expedition: advance.expedition,
                peakIndex: advance.peakIndex,
                before: advance.before,
                after: advance.after
            ))
        }
        while next < picks.count {
            Self.take(picks[next].index, at: picks[next].at, into: &expeditions)
            next += 1
        }
        self.steps = steps
        self.expeditions = expeditions
        summits = Self.summits(of: expeditions, steps: steps)
    }

    /// One day's share.
    func day(_ key: String) -> DayClimb {
        var result = DayClimb()
        for step in steps where step.day == key {
            result.focusMetres += step.climbedFocus
            result.bonusMetres += step.climbedBonus
            result.sessions += 1
            if step.startedFromBreak { result.startedFromBreak += 1 }
        }
        return result
    }

    /// The climb so far of a focus still running, so the climber can move
    /// while it runs. It counts toward whatever is being climbed now, as it
    /// will once it ends. `records` is the log, which the running session
    /// isn't in yet. Nil for anything but a focus.
    func provisionalStep(for active: ActiveSession, after records: [SessionRecord], at now: Date) -> ClimbStep? {
        guard active.kind == .focus else { return nil }
        let seconds = Int(active.activeSeconds(at: now))
        let counted = active.source == .stopwatch
            ? min(seconds, ClimbRules.stopwatchCapSeconds)
            : min(seconds, active.plannedSeconds)
        let timeline = Self.timeline(records)
        let fromBreak = timeline.count >= 2 && Self.isBonusHandover(
            from: timeline[timeline.count - 2],
            through: timeline[timeline.count - 1],
            to: active.startedAt
        )
        let base = ClimbRules.metres(seconds: max(0, counted))
        let bonus = fromBreak ? base * ClimbRules.breakBonus : 0
        var expeditions = expeditions
        let advance = Self.advance(&expeditions, by: base + bonus, endedAt: now)
        return ClimbStep(
            recordID: active.id,
            day: LocalDay.key(for: active.startedAt, utcOffsetSeconds: active.utcOffsetSeconds),
            endedAt: now,
            baseMetres: base,
            bonusMetres: bonus,
            startedFromBreak: fromBreak,
            expedition: advance.expedition,
            peakIndex: advance.peakIndex,
            before: advance.before,
            after: advance.after
        )
    }

    // MARK: Rules

    /// Focus and break sessions in the order they started. A Clock timer is
    /// no part of a Pomodoro, so it neither climbs nor stands between a break
    /// and the focus after it.
    static func timeline(_ records: [SessionRecord]) -> [SessionRecord] {
        records
            .filter { $0.kind != .clock }
            .sorted { ($0.startedAt, $0.endedAt) < ($1.startedAt, $1.endedAt) }
    }

    /// Whether the focus at `index` started from a finished break that itself
    /// followed a focus.
    static func startsFromBreak(_ timeline: [SessionRecord], at index: Int) -> Bool {
        guard index >= 2 else { return false }
        return isBonusHandover(from: timeline[index - 2], through: timeline[index - 1], to: timeline[index].startedAt)
    }

    /// Focus, then its break, then a focus starting at `start`: the break ran
    /// to zero and no more than 5 minutes past it, and each session followed
    /// on from the one before.
    static func isBonusHandover(from focus: SessionRecord, through rest: SessionRecord, to start: Date) -> Bool {
        focus.kind == .focus
            && rest.kind == .break
            && rest.outcome == .completed
            && rest.overtimeSeconds <= ClimbRules.breakOvertimeAllowance
            && isHandover(from: focus.endedAt, to: rest.startedAt)
            && isHandover(from: rest.endedAt, to: start)
    }

    static func isHandover(from end: Date, to start: Date) -> Bool {
        let gap = start.timeIntervalSince(end)
        return gap >= -1 && gap <= ClimbRules.handoverSeconds
    }

    /// A pick starts a climb from the peak's foot, unless that peak is the
    /// one being climbed.
    private static func take(_ peakIndex: Int, at date: Date, into expeditions: inout [Expedition]) {
        if let last = expeditions.last, !last.isSummited, last.peakIndex == peakIndex { return }
        expeditions.append(Expedition(peakIndex: peakIndex, pickedAt: date))
    }

    private struct Advance {
        let expedition: Int?
        let peakIndex: Int?
        let before: Double
        let after: Double
    }

    /// Climbs `earned` metres up the climb under way, if there is one, and no
    /// further than its top.
    private static func advance(_ expeditions: inout [Expedition], by earned: Double, endedAt: Date) -> Advance {
        guard let index = expeditions.indices.last, !expeditions[index].isSummited else {
            return Advance(expedition: nil, peakIndex: nil, before: 0, after: 0)
        }
        let before = expeditions[index].metres
        let height = expeditions[index].peak.height
        let reachesTop = before + earned >= height
        let after = reachesTop ? height : before + earned
        expeditions[index].metres = after
        if reachesTop { expeditions[index].summitedAt = endedAt }
        return Advance(expedition: index, peakIndex: expeditions[index].peakIndex, before: before, after: after)
    }

    /// Each top reached, dated by the session that reached it, and numbered
    /// for its peak.
    private static func summits(of expeditions: [Expedition], steps: [ClimbStep]) -> [Summit] {
        var reached: [Int: Int] = [:]
        return expeditions.indices.compactMap { index in
            let expedition = expeditions[index]
            guard expedition.isSummited else { return nil }
            let climbed = steps.filter { $0.expedition == index }
            guard let last = climbed.last else { return nil }
            reached[expedition.peakIndex, default: 0] += 1
            return Summit(
                peakIndex: expedition.peakIndex,
                number: reached[expedition.peakIndex] ?? 1,
                recordID: last.recordID,
                date: last.endedAt,
                sessions: climbed.count,
                days: Set(climbed.map(\.day)).count
            )
        }
    }
}
