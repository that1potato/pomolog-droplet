//
//  Climb.swift
//  Pomodorolog
//
//  Focus climbs the peaks at 10 m for every counted minute, and a focus that
//  starts from a finished break climbs 20% further. That bonus covers that one
//  focus and never grows or stacks. Breaks never climb on their own.
//
//  It is worked out from the log alone, so every session ever logged counts.
//  Foundation only.
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
    let baseMetres: Double
    let bonusMetres: Double
    let startedFromBreak: Bool
    /// The total climb before and after this session.
    let before: Double
    let after: Double

    var metres: Double { baseMetres + bonusMetres }
}

/// The top of a peak, reached.
struct Summit: Equatable, Sendable {
    let peakIndex: Int
    let ascent: Int
    /// The session that crossed the top, and when it ended.
    let recordID: UUID
    let date: Date
    /// The focus sessions that climbed this peak, and the days they fell on.
    let sessions: Int
    let days: Int

    var peak: Peak { Peaks.all[peakIndex] }
}

/// One day's share of the climb.
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
    let summits: [Summit]

    var total: Double { steps.last?.after ?? 0 }
    var position: PeakPosition { Peaks.position(at: total) }

    init(records: [SessionRecord]) {
        let timeline = Self.timeline(records)
        var steps: [ClimbStep] = []
        var total: Double = 0
        for index in timeline.indices where timeline[index].kind == .focus {
            let record = timeline[index]
            let fromBreak = Self.startsFromBreak(timeline, at: index)
            let base = ClimbRules.metres(seconds: ClimbRules.countedSeconds(record))
            let bonus = fromBreak ? base * ClimbRules.breakBonus : 0
            steps.append(ClimbStep(
                recordID: record.id,
                day: record.localDay,
                endedAt: record.endedAt,
                baseMetres: base,
                bonusMetres: bonus,
                startedFromBreak: fromBreak,
                before: total,
                after: total + base + bonus
            ))
            total += base + bonus
        }
        self.steps = steps
        summits = Self.summits(in: steps)
    }

    /// One day's share.
    func day(_ key: String) -> DayClimb {
        var result = DayClimb()
        for step in steps where step.day == key {
            result.focusMetres += step.baseMetres
            result.bonusMetres += step.bonusMetres
            result.sessions += 1
            if step.startedFromBreak { result.startedFromBreak += 1 }
        }
        return result
    }

    /// The climb so far of a focus still running, so the climber can move
    /// while it runs. `records` is the log, which the running session isn't in
    /// yet. Nil for anything but a focus.
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
        return ClimbStep(
            recordID: active.id,
            day: LocalDay.key(for: active.startedAt, utcOffsetSeconds: active.utcOffsetSeconds),
            endedAt: now,
            baseMetres: base,
            bonusMetres: bonus,
            startedFromBreak: fromBreak,
            before: total,
            after: total + base + bonus
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

    /// Each top crossed, dated by the session that crossed it. A session that
    /// carries on past a top counts toward both peaks.
    private static func summits(in steps: [ClimbStep]) -> [Summit] {
        var summits: [Summit] = []
        var ascent = 1
        var index = 0
        var top = Peaks.top(ofPeak: 0, ascent: 1)
        var first = 0
        for (position, step) in steps.enumerated() {
            while step.after >= top {
                let climbed = steps[first...position]
                summits.append(Summit(
                    peakIndex: index,
                    ascent: ascent,
                    recordID: step.recordID,
                    date: step.endedAt,
                    sessions: climbed.count,
                    days: Set(climbed.map(\.day)).count
                ))
                first = step.after > top ? position : position + 1
                index += 1
                if index == Peaks.all.count {
                    index = 0
                    ascent += 1
                }
                top = Peaks.top(ofPeak: index, ascent: ascent)
            }
        }
        return summits
    }
}
