//
//  ExpeditionStore.swift
//  Pomodorolog
//
//  The climbs picked, on disk beside the session log:
//
//      expeditions.json          { "schemaVersion": 1, "picks": [ … ] }
//      expeditions.backup.json   the copy from before the last write
//
//  As with the session log, nothing is deleted: a file that cannot be read is
//  moved aside under a dated name, and the picks carry on in a fresh one.
//

import Combine
import Foundation

@MainActor
final class ExpeditionStore: ObservableObject {
    /// Every pick, oldest first.
    @Published private(set) var picks: [ClimbPick] = []

    /// Set when the last write failed.
    @Published private(set) var lastError: String?

    let directory: URL
    private let fileManager: FileManager

    var fileURL: URL { directory.appendingPathComponent("expeditions.json") }
    var backupURL: URL { directory.appendingPathComponent("expeditions.backup.json") }

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Reads the picks. Falls back to the backup when the main file is
    /// damaged, and moves anything unreadable aside rather than overwriting
    /// it. No file means nothing has been picked.
    func load() {
        if let document = readDocument(at: fileURL) {
            picks = document.picks
            return
        }
        let mainExists = fileManager.fileExists(atPath: fileURL.path)
        if let document = readDocument(at: backupURL) {
            if mainExists { moveAside(fileURL, label: "unreadable") }
            picks = document.picks
            save()
            return
        }
        if mainExists { moveAside(fileURL, label: "unreadable") }
        if fileManager.fileExists(atPath: backupURL.path) { moveAside(backupURL, label: "unreadable") }
        picks = []
    }

    /// Saves a pick of `peak`, made at `date`.
    func pick(_ peak: Peak, at date: Date) {
        picks.append(ClimbPick(peak, at: date))
        save()
    }

    private func readDocument(at url: URL) -> ExpeditionsDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let document = try? SessionStore.decoder.decode(ExpeditionsDocument.self, from: data) else { return nil }
        // Picks written by a newer version are not ours to rewrite.
        guard document.schemaVersion <= ExpeditionsDocument.currentSchemaVersion else { return nil }
        return document
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let document = ExpeditionsDocument(schemaVersion: ExpeditionsDocument.currentSchemaVersion, picks: picks)
            let data = try SessionStore.encoder.encode(document)
            // Keep the last good copy before replacing it.
            if readDocument(at: fileURL) != nil {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func moveAside(_ url: URL, label: String) {
        let stamp = SessionStore.fileStamp(Date())
        let name = url.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent("\(name).\(label)-\(stamp).json")
        var attempt = 1
        while fileManager.fileExists(atPath: destination.path) {
            attempt += 1
            destination = directory.appendingPathComponent("\(name).\(label)-\(stamp)-\(attempt).json")
        }
        try? fileManager.moveItem(at: url, to: destination)
    }
}
