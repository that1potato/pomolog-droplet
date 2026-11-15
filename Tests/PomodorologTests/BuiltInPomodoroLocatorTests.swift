import Foundation
import ObjectiveC
import Testing
@testable import Pomodorolog

/// Stands in for Droppy's PomodoroManager: one instance, held by a global.
final class LocatorTarget {
    var value = 7
}

nonisolated(unsafe) private var heldTarget: LocatorTarget?

/// The same search the probe runs inside Droppy, run against this test binary.
@MainActor
@Suite(.serialized) struct BuiltInPomodoroLocatorTests {
    private var runtimeName: String { String(cString: class_getName(LocatorTarget.self)) }

    @Test func findsTheObjectAGlobalHolds() {
        let target = LocatorTarget()
        heldTarget = target
        defer { heldTarget = nil }

        guard case .success(let found) = BuiltInPomodoroLocator.locate(className: runtimeName) else {
            Issue.record("the object a global holds was not found")
            return
        }
        #expect(found.object === target)
        #expect(found.location.hasPrefix("__DATA,"))
    }

    @Test func aClassNoGlobalHoldsIsNotFound() {
        heldTarget = nil
        guard case .failure(.notInGlobals) = BuiltInPomodoroLocator.locate(className: runtimeName) else {
            Issue.record("found an object no global holds")
            return
        }
    }

    @Test func outsideDroppyThereIsNoPomodoroManager() {
        guard case .failure(.classMissing) = BuiltInPomodoroLocator.locate() else {
            Issue.record("found Droppy's PomodoroManager in the test process")
            return
        }
    }
}
