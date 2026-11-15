//
//  BuiltInPomodoroReader.swift
//  Pomodorolog
//
//  Reads Droppy's `PomodoroManager` into a `BuiltInSnapshot` with Swift's
//  `Mirror`, field by field, by name. Unofficial and read-only: Droppy's
//  binary carries the names of the object's fields, and `Mirror` copies their
//  values out without calling any of Droppy's code. The names below are
//  Droppy 16.0.1's (`@Observable` keeps each property in `_name`). A Droppy
//  that renames one makes `read()` fail and say which, and nothing is guessed.
//

import Foundation

@MainActor
final class BuiltInPomodoroReader {
    enum Failure: Error, Equatable, CustomStringConvertible {
        /// Nothing attached, or the object went away.
        case noObject
        /// Fields that are missing or hold something unexpected.
        case fields([String])

        var description: String {
            switch self {
            case .noObject: "no PomodoroManager attached"
            case .fields(let problems): problems.joined(separator: "; ")
            }
        }
    }

    /// Droppy's object. Weak, so the reader never keeps it alive.
    private(set) weak var object: AnyObject?

    func attach(_ object: AnyObject) {
        self.object = object
    }

    /// Every stored field of the object with its type, for the probe log.
    func inventory() -> [String] {
        guard let object else { return [] }
        return Mirror(reflecting: object).children.map { child in
            "\(child.label ?? "(no label)"): \(MirrorFields.typeName(child.value))"
        }
    }

    func read() -> Result<BuiltInSnapshot, Failure> {
        guard let object else { return .failure(.noObject) }
        var fields = MirrorFields(Mirror(reflecting: object))

        let snapshot = BuiltInSnapshot(
            isActive: fields.value("_isActive", false),
            isPaused: fields.value("_isPaused", false),
            isOvertime: fields.value("_isOvertime", false),
            runMode: fields.caseName("_runMode"),
            sessionKind: fields.caseName("_sessionKind"),
            provenance: fields.caseName("_timerProvenance"),
            activeSelection: fields.record("_activeSelection") { selection in
                BuiltInSnapshot.Selection(
                    sectionID: selection.value("sectionID", ""),
                    minutes: selection.value("minutes", 0)
                )
            },
            selectedSectionID: fields.value("_selectedSectionID", ""),
            selectedMinutes: fields.value("_selectedMinutes", 0),
            remainingSeconds: fields.value("_remainingSeconds", 0),
            totalDurationSeconds: fields.value("_totalDurationSeconds", 0),
            endTime: fields.optional("_endTime", as: Date.self),
            pausedRemainingSeconds: fields.optional("_pausedRemainingSeconds", as: Int.self),
            pausedOvertimeSeconds: fields.optional("_pausedOvertimeSeconds", as: Int.self),
            stopwatchStartTime: fields.optional("_stopwatchStartTime", as: Date.self),
            stopwatchPausedElapsedSeconds: fields.optional("_stopwatchPausedElapsedSeconds", as: Int.self),
            completedSessions: fields.value("_completedSessions", 0),
            focusTitle: fields.optional("_focusTitle", as: String.self),
            nativeTimerID: fields.optional("_nativeTimerID", as: String.self),
            nativeTimerTitle: fields.optional("_nativeTimerTitle", as: String.self),
            nativeTimerDeadline: fields.optional("_nativeTimerDeadline", as: Date.self),
            sections: fields.records("_sections") { section in
                BuiltInSnapshot.Section(
                    id: section.value("id", ""),
                    name: section.value("name", ""),
                    colorHex: section.value("colorHex", "")
                )
            }
        )
        return fields.problems.isEmpty ? .success(snapshot) : .failure(.fields(fields.problems))
    }
}

/// The children of a `Mirror` by label. Every read that fails adds a line to
/// `problems` and returns a placeholder, so one pass reports everything.
struct MirrorFields {
    private let values: [String: Any]
    private let path: String
    private(set) var problems: [String] = []

    init(_ mirror: Mirror, path: String = "") {
        var values: [String: Any] = [:]
        for child in mirror.children {
            if let label = child.label { values[label] = child.value }
        }
        self.values = values
        self.path = path
    }

    /// A field that always holds a value of type `T`.
    mutating func value<T>(_ label: String, _ placeholder: T) -> T {
        guard let raw = raw(label) else { return placeholder }
        guard let value = raw as? T else {
            problems.append("\(path)\(label) is \(Self.typeName(raw)), not \(T.self)")
            return placeholder
        }
        return value
    }

    /// An optional field: nil when it is empty.
    mutating func optional<T>(_ label: String, as type: T.Type) -> T? {
        guard let raw = raw(label), let inner = Self.unwrapped(raw) else { return nil }
        guard let value = inner as? T else {
            problems.append("\(path)\(label) is \(Self.typeName(raw)), not \(T.self)?")
            return nil
        }
        return value
    }

    /// An enum field, as its raw value when that is a string, otherwise as
    /// its case name.
    mutating func caseName(_ label: String) -> String {
        guard let raw = raw(label) else { return "" }
        guard Mirror(reflecting: raw).displayStyle == .enum else {
            problems.append("\(path)\(label) is \(Self.typeName(raw)), not an enum")
            return ""
        }
        if let representable = raw as? any RawRepresentable, let text = representable.rawValue as? String {
            return text
        }
        return String(describing: raw)
    }

    /// A struct field, or an optional one (nil when empty), read by `build`.
    mutating func record<T>(_ label: String, _ build: (inout MirrorFields) -> T) -> T? {
        guard let raw = raw(label), let inner = Self.unwrapped(raw) else { return nil }
        var nested = MirrorFields(Mirror(reflecting: inner), path: "\(path)\(label).")
        let result = build(&nested)
        problems += nested.problems
        return result
    }

    /// An array field, each element read by `build`.
    mutating func records<T>(_ label: String, _ build: (inout MirrorFields) -> T) -> [T] {
        guard let raw = raw(label) else { return [] }
        let mirror = Mirror(reflecting: raw)
        guard mirror.displayStyle == .collection else {
            problems.append("\(path)\(label) is \(Self.typeName(raw)), not an array")
            return []
        }
        var results: [T] = []
        for child in mirror.children {
            var nested = MirrorFields(Mirror(reflecting: child.value), path: "\(path)\(label)[].")
            results.append(build(&nested))
            problems += nested.problems
        }
        return results
    }

    private mutating func raw(_ label: String) -> Any? {
        guard let raw = values[label] else {
            problems.append("\(path)\(label) is missing")
            return nil
        }
        return raw
    }

    /// The value inside an optional, nil when it is empty; any other value
    /// as it is.
    static func unwrapped(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    static func typeName(_ value: Any) -> String {
        String(reflecting: type(of: value))
    }
}
