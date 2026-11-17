import Foundation
import Testing
@testable import Pomodorolog

@MainActor
@Suite struct ExpeditionStoreTests {
    /// A folder of its own for each test.
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pomolog-expeditions-\(UUID().uuidString)")
    }

    private let noon = Date(timeIntervalSince1970: 1_794_916_800)

    @Test func noFileMeansNothingPicked() {
        let store = ExpeditionStore(directory: folder())
        store.load()
        #expect(store.picks.isEmpty)
    }

    @Test func picksSurviveARoundTrip() {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ExpeditionStore(directory: folder)
        store.load()
        store.pick(Peaks.all[0], at: noon)
        store.pick(Peaks.all[2], at: noon.addingTimeInterval(60))

        let reread = ExpeditionStore(directory: folder)
        reread.load()
        #expect(reread.picks == store.picks)
        #expect(reread.picks.map(\.peak) == ["ben-nevis", "mont-blanc"])
        #expect(reread.picks.first?.at == noon)
    }

    @Test func aDamagedFileFallsBackToTheBackupAndIsKept() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ExpeditionStore(directory: folder)
        store.load()
        store.pick(Peaks.all[0], at: noon)
        // The second write keeps the first in the backup.
        store.pick(Peaks.all[1], at: noon.addingTimeInterval(60))
        try Data("not json".utf8).write(to: store.fileURL)

        let reread = ExpeditionStore(directory: folder)
        reread.load()
        #expect(reread.picks.map(\.peak) == ["ben-nevis"])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("expeditions.unreadable-") })
    }

    @Test func picksFromANewerVersionAreMovedAsideNotOverwritten() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let newer = #"{ "schemaVersion": 99, "picks": [] }"#
        try Data(newer.utf8).write(to: folder.appendingPathComponent("expeditions.json"))

        let store = ExpeditionStore(directory: folder)
        store.load()
        #expect(store.picks.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let aside = try #require(names.first { $0.hasPrefix("expeditions.unreadable-") })
        let kept = try String(contentsOf: folder.appendingPathComponent(aside), encoding: .utf8)
        #expect(kept == newer)
    }
}
