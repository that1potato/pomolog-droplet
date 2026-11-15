//
//  PomodorologDroplet.swift
//  Pomodorolog
//
//  The droplet: it watches Droppy's own Pomodoro and writes every session
//  that runs there to the log. BuiltIn/ reads Droppy's timer (unofficially,
//  and only ever reads it) and turns what it sees into sessions; the settings
//  pane in Surfaces/ shows the log.
//

import AppKit
import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(PomodorologPrincipal)
public final class PomodorologPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { PomodorologDroplet() }
}

/// Pomolog.
@MainActor
public final class PomodorologDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal `DroppyDropletID` in the bundle's Info.plist and `id` in
    /// droplet.json. The loader refuses the bundle if the three disagree.
    public nonisolated static let id: DropletID = "pomodorolog"

    /// Written into every log record. Keep in step with droplet.json.
    static let version = "2.0.0"

    /// How often Droppy's Pomodoro is read: often while a session runs, so a
    /// pause or a stop lands within half a second, and less often while idle,
    /// since a start's moment comes from the built-in itself.
    static let activeReadInterval: TimeInterval = 0.5
    static let idleReadInterval: TimeInterval = 2
    /// While Droppy's Pomodoro cannot be found yet: how often to look again,
    /// and for how many attempts (two minutes).
    static let locateRetryInterval: TimeInterval = 5
    static let locateAttempts = 24

    /// Whether sessions from Droppy's Pomodoro are reaching the log.
    enum HookStatus: Equatable {
        /// Looking for Droppy's Pomodoro.
        case starting
        /// Reading it: every session is logged.
        case logging
        /// Not logging: why, in a sentence, and the technical detail.
        case stopped(String, detail: String)
    }

    private(set) var host: DropletHost?
    private(set) var store: SessionStore?
    @Published private(set) var hookStatus: HookStatus = .starting
    /// The session running in Droppy's Pomodoro, as it will be logged.
    @Published private(set) var session: ActiveSession?
    /// The climb, the pantry and the stickers, worked out from the log.
    @Published private(set) var rewards = RewardsSnapshot.empty
    /// True when the rewards come from the sample week, in the harness.
    private(set) var isShowingSample = false

    private let reader = BuiltInPomodoroReader()
    private var tracker: BuiltInSessionTracker?
    private var timer: Timer?
    private var locateAttempts = 0
    private var cancellables = Set<AnyCancellable>()

    /// Notch moments waiting their turn, the wait before the next, and a card
    /// button's delayed action (NotchMoments.swift).
    var pendingMoments: [PendingMoment] = []
    var momentTask: Task<Void, Never>?
    var actionTask: Task<Void, Never>?

    // MARK: Lifecycle

    public func activate(host: DropletHost) throws {
        self.host = host

        let store = SessionStore(directory: host.environment.containerDirectory)
        store.load()
        if let recovered = store.recoverInterruptedSession(dropletVersion: Self.version) {
            host.log.notice("Closed a session left running: \(recovered.sectionName), \(recovered.activeSeconds)s, \(recovered.outcome.rawValue)")
        }
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.$sessions
            .sink { [weak self] sessions in self?.refreshRewards(with: sessions) }
            .store(in: &cancellables)
        clearReplicaPreferences()

        tracker = BuiltInSessionTracker(dropletVersion: Self.version) { [weak store] day in
            store?.focusSessionCount(onDay: day) ?? 0
        }

        host.log.info("Pomolog activated, \(store.sessions.count) sessions in \(store.logURL.path)")
        diagnose("activated \(Self.version) in Droppy \(host.environment.appVersion), granted \(host.grantedCapabilities.map(\.rawValue).sorted().joined(separator: ", "))")
        if host.environment.isHarness {
            presentHarnessMoment()
        } else {
            welcomeIfFirstRun()
        }
        // On a later turn of the run loop: Droppy runs activate(host:) under a
        // watchdog, and the search should not count against it.
        schedule(.locate, after: 0)
    }

    public func deactivate() {
        // Everything activate() started is torn down here. Swift cannot unload
        // code, so anything left running keeps running until Droppy relaunches.
        timer?.invalidate()
        timer = nil
        stopMoments()
        // Logged, but not celebrated: the notch is no place for it now.
        apply(tracker?.end(.interrupt, at: Date()) ?? [], celebrates: false)
        tracker = nil
        cancellables.removeAll()
        session = nil
        store = nil
        host = nil
    }

    // MARK: State the views read

    /// Today as a day key, in the Mac's current time zone.
    var today: String {
        LocalDay.key(for: Date(), utcOffsetSeconds: TimeZone.current.secondsFromGMT())
    }

    /// Works the rewards out again from the log. The harness has no Droppy
    /// Pomodoro to log, so it shows the design's sample week instead.
    private func refreshRewards(with sessions: [SessionRecord]) {
        var records = sessions
        isShowingSample = records.isEmpty && host?.environment.isHarness == true
        if isShowingSample {
            records = SampleLog.week(endingOn: today, utcOffsetSeconds: TimeZone.current.secondsFromGMT())
        }
        rewards = RewardsSnapshot(records: records, today: today)
    }

    /// The running focus's share of the climb so far, so the climber moves
    /// while it runs. Nil when no focus is running.
    func liveStep(at date: Date) -> ClimbStep? {
        guard let session, session.kind == .focus, let store else { return nil }
        return rewards.climb.provisionalStep(for: session, after: store.sessions, at: date)
    }

    // MARK: Commands

    func revealLog() {
        guard let store, let host else { return }
        let target = FileManager.default.fileExists(atPath: store.logURL.path) ? store.logURL : store.directory
        host.workspace.revealInFinder(target)
    }

    func exportCSV() {
        guard let store, let host else { return }
        do {
            host.workspace.revealInFinder(try store.writeCSVExport())
        } catch {
            host.log.error("CSV export failed: \(error.localizedDescription)")
        }
    }

    // MARK: Watching Droppy's Pomodoro

    private enum Step {
        case locate
        case read
    }

    private func schedule(_ step: Step, after delay: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.run(step) }
        }
        timer.tolerance = delay / 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func run(_ step: Step) {
        timer = nil
        switch step {
        case .locate: locate()
        case .read: read()
        }
    }

    private func locate() {
        guard tracker != nil, let host else { return }
        locateAttempts += 1
        switch BuiltInPomodoroLocator.locate() {
        case .success(let found):
            reader.attach(found.object)
            locateAttempts = 0
            diagnose("found Droppy's Pomodoro via \(found.location) in \(BuiltInPomodoroLocator.Failure.format(found.milliseconds)) ms")
            read()
        case .failure(.classMissing):
            let reason = host.environment.isHarness
                ? "The harness has no Droppy Pomodoro to read."
                : "This version of Droppy (\(host.environment.appVersion)) has no Pomodoro that Pomolog can find."
            setStatus(.stopped(reason, detail: BuiltInPomodoroLocator.Failure.classMissing.description))
        case .failure(let failure):
            if locateAttempts < Self.locateAttempts {
                schedule(.locate, after: Self.locateRetryInterval)
            } else {
                setStatus(.stopped(
                    "Pomolog could not find Droppy's Pomodoro in this version of Droppy (\(host.environment.appVersion)).",
                    detail: failure.description
                ))
            }
        }
    }

    private func read() {
        guard tracker != nil, let host else { return }
        switch reader.read() {
        case .success(let snapshot):
            setStatus(.logging)
            apply(tracker?.observe(snapshot, at: Date()) ?? [])
            schedule(.read, after: session == nil ? Self.idleReadInterval : Self.activeReadInterval)
        case .failure(.noObject):
            diagnose("Droppy's Pomodoro went away; looking for it again")
            setStatus(.starting)
            locateAttempts = 0
            schedule(.locate, after: Self.locateRetryInterval)
        case .failure(let failure):
            // Nothing is guessed while it cannot be read. Reading goes on, so
            // a passing state picks logging up again by itself.
            setStatus(.stopped(
                "Droppy's Pomodoro changed in this version of Droppy (\(host.environment.appVersion)), so nothing is logged.",
                detail: failure.description
            ))
            schedule(.read, after: Self.idleReadInterval)
        }
    }

    private func apply(_ outputs: [BuiltInSessionTracker.Output], celebrates: Bool = true) {
        for output in outputs {
            switch output {
            case .finished(let record):
                let before = rewards
                store?.append(record)
                diagnose("logged \(record.sectionName), \(record.activeSeconds)s, \(record.outcome.rawValue)")
                if celebrates { celebrate(since: before) }
            case .checkpoint(let active):
                store?.checkpoint(active)
                session = active
            }
        }
    }

    private func setStatus(_ status: HookStatus) {
        guard status != hookStatus else { return }
        hookStatus = status
        switch status {
        case .starting:
            break
        case .logging:
            diagnose("logging Droppy's Pomodoro")
        case .stopped(let reason, let detail):
            diagnose("not logging: \(reason) (\(detail))")
        }
    }

    // MARK: Housekeeping

    /// The replica timer's settings from 1.0. Nothing reads them
    /// now, so they are cleared.
    private func clearReplicaPreferences() {
        guard let preferences = host?.preferences else { return }
        for key in ["sections", "selectedSection", "keepsTimerVisible", "playsSound", "revealsTimerFromCountdown"]
        where preferences.hasValue(forKey: key) {
            preferences.setValue(nil as Bool?, forKey: key)
        }
    }

    /// Writes a line to Droppy's log and to `diagnostics.log` beside the
    /// session log, where it can be read without Droppy's private log.
    func diagnose(_ message: String) {
        host?.log.notice(message)
        guard let store else { return }
        let url = store.directory.appendingPathComponent("diagnostics.log")
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Keep the tail only; this is a debugging aid, not a record.
        let kept = existing.count > 20_000 ? String(existing.suffix(10_000)) : existing
        try? (kept + line).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Notch moments: a jar, a summit, a sticker (NotchMoments.swift). The
/// conformance agrees with `hud` in droplet.json.
extension PomodorologDroplet: HUDPresenting {}
