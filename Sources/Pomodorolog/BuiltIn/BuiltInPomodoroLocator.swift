//
//  BuiltInPomodoroLocator.swift
//  Pomodorolog
//
//  Finds Droppy's own Pomodoro, its live `PomodoroManager` object, from
//  inside Droppy's process. Unofficial: DroppyKit has no API for the built-in
//  timer, so this reads Droppy's memory, and only reads it.
//
//  Droppy keeps one `PomodoroManager` for the whole run, held in a global
//  (only SwiftUI views store it, and no class does). So the object is found
//  by looking through Droppy's own global variables for a pointer to a live
//  object of that class. Nothing of Droppy's is called or written.
//

import Darwin
import Foundation
import MachO
import ObjectiveC

@MainActor
enum BuiltInPomodoroLocator {
    /// The Objective-C runtime name of Droppy's `PomodoroManager` class, as
    /// Droppy 16.0.1 names it.
    nonisolated static let className = "_TtC6Droppy15PomodoroManager"

    /// The sections searched, in order. Swift keeps a `static let` in
    /// zero-filled storage until first use, so `__bss` comes first.
    static let sections = ["__bss", "__common", "__data"]

    struct Found {
        let object: AnyObject
        /// Where the pointer was, for example `__DATA,__bss`.
        let location: String
        let milliseconds: Double
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        /// No such class in this process: not Droppy (the harness, the
        /// Playground), or a Droppy that renamed it.
        case classMissing
        /// The class exists but the image that defines it could not be read.
        case imageMissing(String)
        /// The class exists but no global points to an object of it yet.
        case notInGlobals(scannedBytes: Int, milliseconds: Double)

        var description: String {
            switch self {
            case .classMissing:
                return "no class named \(BuiltInPomodoroLocator.className) in this process"
            case .imageMissing(let detail):
                return "the image that defines \(BuiltInPomodoroLocator.className) could not be read: \(detail)"
            case .notInGlobals(let bytes, let milliseconds):
                return "no global points to a \(BuiltInPomodoroLocator.className) yet (searched \(bytes / 1024) KB in \(Self.format(milliseconds)) ms)"
            }
        }

        static func format(_ milliseconds: Double) -> String {
            String(format: "%.1f", milliseconds)
        }
    }

    /// Searches for the one object of `className` that a global holds. The
    /// name is only ever changed by the tests, which run the same search on
    /// a class of their own.
    static func locate(className name: String = BuiltInPomodoroLocator.className) -> Result<Found, Failure> {
        let clock = ContinuousClock()
        let started = clock.now
        func elapsed() -> Double {
            let duration = started.duration(to: clock.now)
            return Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        }

        guard let found = objc_getClass(name), let managerClass = found as? AnyClass else {
            return .failure(.classMissing)
        }
        let classAddress = UInt(bitPattern: ObjectIdentifier(managerClass))
        guard let image = Image(defining: managerClass) else {
            return .failure(.imageMissing(class_getImageName(managerClass).map { String(cString: $0) } ?? "no image name"))
        }

        var scanned = 0
        for section in sections {
            var size: UInt = 0
            guard let start = getsectiondata(image.header, "__DATA", section, &size) else { continue }
            // A pointer-sized global sits on an 8-byte boundary.
            let first = (UInt(bitPattern: start) + 7) & ~7
            let end = UInt(bitPattern: start) + size
            guard end > first, let words = UnsafeRawPointer(bitPattern: first) else { continue }
            scanned += Int(size)
            for index in 0..<(Int(end - first) / 8) {
                let value = words.load(fromByteOffset: index * 8, as: UInt.self)
                guard let object = objectOfClass(at: value, classAddress: classAddress, image: image) else { continue }
                return .success(Found(object: object, location: "__DATA,\(section)", milliseconds: elapsed()))
            }
        }
        return .failure(.notInGlobals(scannedBytes: scanned, milliseconds: elapsed()))
    }

    /// The object at `value` when it is a live heap object whose class is
    /// `classAddress`, or nil for anything else.
    ///
    /// Every check before the read is one that cannot fault: malloc answers
    /// for any address whether it is the start of a block it handed out, and
    /// only a live block's first word is read.
    private static func objectOfClass(at value: UInt, classAddress: UInt, image: Image) -> AnyObject? {
        // Heap blocks are 16-byte aligned and sit above the 4 GB zero page,
        // and a pointer into Droppy's own binary is static data, not the heap.
        guard value & 0xF == 0, value >= 0x1_0000_0000, value < (1 << 47) else { return nil }
        guard !image.contains(value), let pointer = UnsafeRawPointer(bitPattern: value) else { return nil }
        guard malloc_zone_from_ptr(pointer) != nil, malloc_size(pointer) >= 16 else { return nil }

        let isa = pointer.load(as: UInt.self)
        // A Swift object's first word is its class. An Objective-C object may
        // pack flags around it (bit 0 set), so compare that one masked.
        let matches = isa == classAddress || (isa & 1 == 1 && isa & 0x0000_000F_FFFF_FFF8 == classAddress)
        guard matches else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// The loaded image (Droppy's executable) that defines a class, with the
    /// address range its segments occupy in memory.
    private struct Image {
        let header: UnsafePointer<mach_header_64>
        let range: Range<UInt>

        init?(defining cls: AnyClass) {
            guard let namePointer = class_getImageName(cls) else { return nil }
            let name = String(cString: namePointer)
            var match: UnsafePointer<mach_header>?
            for index in 0..<_dyld_image_count() {
                guard let imageName = _dyld_get_image_name(index), String(cString: imageName) == name else { continue }
                match = _dyld_get_image_header(index)
                break
            }
            guard let match else { return nil }
            let header = UnsafeRawPointer(match).assumingMemoryBound(to: mach_header_64.self)
            guard header.pointee.magic == MH_MAGIC_64 else { return nil }

            // The segments' addresses as linked, then moved by the slide: the
            // distance between the header and the start of __TEXT.
            var low = UInt.max
            var high: UInt = 0
            var textAddress: UInt?
            var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0..<header.pointee.ncmds {
                let load = command.load(as: load_command.self)
                if load.cmd == UInt32(LC_SEGMENT_64) {
                    let segment = command.load(as: segment_command_64.self)
                    // __PAGEZERO maps nothing.
                    if segment.initprot != 0, segment.vmsize > 0 {
                        low = min(low, UInt(segment.vmaddr))
                        high = max(high, UInt(segment.vmaddr + segment.vmsize))
                        if segment.fileoff == 0, segment.filesize > 0 { textAddress = UInt(segment.vmaddr) }
                    }
                }
                command = command.advanced(by: Int(load.cmdsize))
            }
            guard let textAddress, low < high else { return nil }
            let slide = UInt(bitPattern: UnsafeRawPointer(header)) &- textAddress
            self.header = header
            self.range = (low &+ slide)..<(high &+ slide)
        }

        func contains(_ address: UInt) -> Bool { range.contains(address) }
    }
}
