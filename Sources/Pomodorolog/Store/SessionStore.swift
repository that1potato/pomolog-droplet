//
//  SessionStore.swift
//  Pomodorolog
//
//  The session log on disk, and the questions the rest of the droplet asks it.
//
//      sessions.json          { "schemaVersion": 1, "sessions": [ … ] }
//      sessions.backup.json   the copy from before the last write
//      active.json            the session that is running right now
//
//  Nothing is ever deleted to make room: a file that cannot be read is moved
//  aside under a dated name, and the log carries on in a fresh one.
//

import Combine
import Foundation

/// The log file's shape.
///
/// - 1: version 1.0, sessions from its own timer.
/// - 2: sessions from Droppy's own Pomodoro as well: `kind` can be `clock`
///   and `source` can be `stopwatch`. A version 1 log reads as it is.
struct SessionLogDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var sessions: [SessionRecord]
}

/// Totals for one calendar day.
struct DaySummary: Equatable, Sendable, Identifiable {
    /// `YYYY-MM-DD`.
    var day: String
    /// Every session that started that day, newest first.
    var sessions: [SessionRecord]

    var id: String { day }

    /// Focus sessions whose countdown reached zero.
    var completedFocusCount: Int {
        sessions.filter(\.countsAsCompletedFocus).count
    }

    /// Seconds of focus that day, overtime included, unfinished sessions and
    /// stopwatch runs too.
    var focusSeconds: Int {
        sessions.filter { $0.kind == .focus }.reduce(0) { $0 + $1.activeSeconds }
    }

    var breakSeconds: Int {
        sessions.filter { $0.kind == .break }.reduce(0) { $0 + $1.activeSeconds }
    }
}

/// Totals over the whole log.
struct LogTotals: Equatable, Sendable {
    var sessionCount: Int
    var completedFocusCount: Int
    var focusSeconds: Int
    var dayCount: Int
}

@MainActor
final class SessionStore: ObservableObject {
    /// Every finished session, oldest first.
    @Published private(set) var sessions: [SessionRecord] = []

    /// Set when the last write failed, so the settings pane can say so.
    @Published private(set) var lastError: String?

    let directory: URL
    private let fileManager: FileManager

    var logURL: URL { directory.appendingPathComponent("sessions.json") }
    var backupURL: URL { directory.appendingPathComponent("sessions.backup.json") }
    var activeURL: URL { directory.appendingPathComponent("active.json") }

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    // MARK: Loading

    /// Reads the log. Falls back to the backup when the main file is damaged,
    /// and moves anything unreadable aside rather than overwriting it.
    func load() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if let document = readDocument(at: logURL) {
            sessions = document.sessions
            return
        }
        let mainExists = fileManager.fileExists(atPath: logURL.path)
        if let document = readDocument(at: backupURL) {
            if mainExists { moveAside(logURL, label: "unreadable") }
            sessions = document.sessions
            save()
            return
        }
        if mainExists { moveAside(logURL, label: "unreadable") }
        if fileManager.fileExists(atPath: backupURL.path) { moveAside(backupURL, label: "unreadable") }
        sessions = []
    }

    private func readDocument(at url: URL) -> SessionLogDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let document = try? Self.decoder.decode(SessionLogDocument.self, from: data) else { return nil }
        // A log written by a newer version is not ours to rewrite.
        guard document.schemaVersion <= SessionLogDocument.currentSchemaVersion else { return nil }
        return document
    }

    private func moveAside(_ url: URL, label: String) {
        let stamp = Self.fileStamp(Date())
        let name = url.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent("\(name).\(label)-\(stamp).json")
        var attempt = 1
        while fileManager.fileExists(atPath: destination.path) {
            attempt += 1
            destination = directory.appendingPathComponent("\(name).\(label)-\(stamp)-\(attempt).json")
        }
        try? fileManager.moveItem(at: url, to: destination)
    }

    // MARK: Writing

    /// Adds a finished session and writes the log.
    func append(_ record: SessionRecord) {
        if let index = sessions.firstIndex(where: { $0.id == record.id }) {
            sessions[index] = record
        } else {
            sessions.append(record)
        }
        save()
    }

    /// Replaces a session already in the log, for later edits (title, note, tags).
    func update(_ record: SessionRecord) {
        guard let index = sessions.firstIndex(where: { $0.id == record.id }) else { return }
        sessions[index] = record
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let document = SessionLogDocument(
                schemaVersion: SessionLogDocument.currentSchemaVersion,
                sessions: sessions
            )
            let data = try Self.encoder.encode(document)
            // Keep the last good copy before replacing it.
            if readDocument(at: logURL) != nil {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: logURL, to: backupURL)
            }
            try data.write(to: logURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: The running session

    /// Writes the running session to `active.json`, or removes the file when
    /// there is none.
    func checkpoint(_ active: ActiveSession?) {
        guard let active else {
            try? fileManager.removeItem(at: activeURL)
            return
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(active).write(to: activeURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Closes a session a previous run left behind and adds it to the log.
    ///
    /// It ends where it was last seen alive: at its pause if it was paused,
    /// otherwise at its last checkpoint.
    @discardableResult
    func recoverInterruptedSession(dropletVersion: String) -> SessionRecord? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        defer { try? fileManager.removeItem(at: activeURL) }
        guard let active = try? Self.decoder.decode(ActiveSession.self, from: data) else {
            moveAside(activeURL, label: "unreadable")
            return nil
        }
        let lastEvent = active.events.last?.at ?? active.startedAt
        let end = active.isPaused ? lastEvent : max(active.lastSeenAt, lastEvent)
        let record = active.finished(at: end, reason: .interrupt, dropletVersion: dropletVersion)
        append(record)
        return record
    }

    // MARK: Questions

    /// The log grouped by the day each session started, newest day first.
    func daySummaries() -> [DaySummary] {
        Dictionary(grouping: sessions, by: \.localDay)
            .map { day, sessions in
                DaySummary(day: day, sessions: sessions.sorted { $0.startedAt > $1.startedAt })
            }
            .sorted { $0.day > $1.day }
    }

    /// One day's totals. An empty summary when nothing was logged that day.
    func summary(forDay day: String) -> DaySummary {
        DaySummary(
            day: day,
            sessions: sessions.filter { $0.localDay == day }.sorted { $0.startedAt > $1.startedAt }
        )
    }

    /// How many focus sessions have started on `day`, whatever became of them.
    func focusSessionCount(onDay day: String) -> Int {
        sessions.filter { $0.kind == .focus && $0.localDay == day }.count
    }

    /// Consecutive days with at least one completed focus session, counting
    /// back from `today`. A day that has none yet does not break the streak
    /// until it is over, so the count starts from yesterday in that case.
    func streak(today: String) -> Int {
        let days = Set(sessions.filter(\.countsAsCompletedFocus).map(\.localDay))
        var cursor = today
        if !days.contains(cursor) {
            guard let yesterday = LocalDay.previous(cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = LocalDay.previous(cursor) else { break }
            cursor = previous
        }
        return count
    }

    func totals() -> LogTotals {
        LogTotals(
            sessionCount: sessions.count,
            completedFocusCount: sessions.filter(\.countsAsCompletedFocus).count,
            focusSeconds: sessions.filter { $0.kind == .focus }.reduce(0) { $0 + $1.activeSeconds },
            dayCount: Set(sessions.map(\.localDay)).count
        )
    }

    // MARK: Export

    /// The log as CSV, one row per session, oldest first.
    func csv() -> String {
        let header = [
            "id", "day", "kind", "section", "planned_seconds", "started_at", "ended_at",
            "time_zone", "utc_offset_seconds", "active_seconds", "paused_seconds",
            "overtime_seconds", "outcome", "ended_by", "cycle_index", "title", "note", "tags",
            "source",
        ]
        var lines = [header.joined(separator: ",")]
        for session in sessions {
            let fields: [String] = [
                session.id.uuidString,
                session.localDay,
                session.kind.rawValue,
                session.sectionName,
                String(session.plannedSeconds),
                Self.dateStyle.format(session.startedAt),
                Self.dateStyle.format(session.endedAt),
                session.timeZoneID,
                String(session.utcOffsetSeconds),
                String(session.activeSeconds),
                String(session.pausedSeconds),
                String(session.overtimeSeconds),
                session.outcome.rawValue,
                session.endedBy.rawValue,
                session.cycleIndex.map(String.init) ?? "",
                session.title ?? "",
                session.note ?? "",
                session.tags.joined(separator: ";"),
                session.source.rawValue,
            ]
            lines.append(fields.map(Self.csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the CSV beside the log and returns where it went.
    func writeCSVExport(now: Date = Date()) throws -> URL {
        let folder = directory.appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("pomodoro-log-\(Self.fileStamp(now)).csv")
        try csv().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Coding

    /// ISO 8601 in UTC with milliseconds, so events keep their order.
    nonisolated private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateStyle.format(date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? dateStyle.parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not an ISO 8601 date: \(string)"
            )
        }
        return decoder
    }()

    private static func fileStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d-%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }
}
