#!/usr/bin/env python3
"""Check Droppy's built-in Pomodoro against what Pomolog reads.

Pomolog reads Droppy's PomodoroManager by field name (see
Sources/Pomodorolog/BuiltIn/BuiltInPomodoroReader.swift). This script lists
that class's fields as the installed Droppy declares them, from the Swift
reflection metadata in its binary, and marks every field the droplet reads
that is missing or has changed type. Run it after a Droppy update when the
droplet's settings page says "Not logging". It only reads the app's files.

    python3 Scripts/dump-builtin-pomodoro.py [/Applications/Droppy.app]

Exit status: 0 when everything the droplet reads is there as expected, 1 when
something is missing or changed, 2 when the app cannot be read.
"""

import plistlib
import re
import struct
import sys
from pathlib import Path

# What BuiltInPomodoroReader reads, with the types Droppy 16.0.1 declares.
# Keep in step with BuiltInPomodoroReader.read(). The binary names a type from
# another framework (Foundation's Date) only by reference, so it shows as
# "external".
CLASS_NAME = "_TtC6Droppy15PomodoroManager"
MANAGER = "PomodoroManager"
FIELDS = {
    "_isActive": "Bool",
    "_isPaused": "Bool",
    "_isOvertime": "Bool",
    "_runMode": "PomodoroRunMode",
    "_sessionKind": "PomodoroSessionKind",
    "_timerProvenance": "PomodoroTimerProvenance",
    "_activeSelection": "Optional<PomodoroActiveSelection>",
    "_selectedSectionID": "String",
    "_selectedMinutes": "Int",
    "_remainingSeconds": "Int",
    "_totalDurationSeconds": "Double",
    "_endTime": "Optional<external>",
    "_pausedRemainingSeconds": "Optional<Int>",
    "_pausedOvertimeSeconds": "Optional<Int>",
    "_stopwatchStartTime": "Optional<external>",
    "_stopwatchPausedElapsedSeconds": "Optional<Int>",
    "_completedSessions": "Int",
    "_focusTitle": "Optional<String>",
    "_nativeTimerID": "Optional<String>",
    "_nativeTimerTitle": "Optional<String>",
    "_nativeTimerDeadline": "Optional<external>",
    "_sections": "Array<PomodoroSection>",
}
NESTED = {
    "PomodoroActiveSelection": {"sectionID": "String", "minutes": "Int"},
    "PomodoroSection": {"id": "String", "name": "String", "colorHex": "String"},
}
CASES = {
    "PomodoroRunMode": ["countdown", "stopwatch"],
    "PomodoroSessionKind": ["focus", "break"],
    "PomodoroTimerProvenance": ["local", "appleClock"],
}

KINDS = {0: "struct", 1: "class", 2: "enum", 3: "enum"}
BASIC = {"Sb": "Bool", "Si": "Int", "Sd": "Double", "Sf": "Float", "SS": "String",
         "Su": "UInt", "Sa": "Array", "SD": "Dictionary", "Sh": "Set"}


class Binary:
    """The arm64 (or x86_64) slice of a Mach-O file, and its Swift metadata."""

    def __init__(self, path):
        data = Path(path).read_bytes()
        if struct.unpack_from(">I", data, 0)[0] == 0xCAFEBABE:
            slices = {}
            for index in range(struct.unpack_from(">I", data, 4)[0]):
                cputype, _, offset, size, _ = struct.unpack_from(">iiIII", data, 8 + index * 20)
                slices[cputype] = data[offset:offset + size]
            data = slices.get(0x0100000C) or slices.get(0x01000007)
            if data is None:
                raise ValueError("no arm64 or x86_64 slice")
        if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
            raise ValueError("not a 64-bit Mach-O file")
        self.data = data
        self.sections = {}
        self.base = 0
        offset = 32
        for _ in range(struct.unpack_from("<I", data, 16)[0]):
            command, size = struct.unpack_from("<II", data, offset)
            if command == 0x19:  # LC_SEGMENT_64
                segment = data[offset + 8:offset + 24].rstrip(b"\0").decode()
                vmaddr, _, fileoff = struct.unpack_from("<QQQ", data, offset + 24)
                if segment == "__TEXT":
                    self.base = vmaddr - fileoff
                at = offset + 72
                for _ in range(struct.unpack_from("<I", data, offset + 64)[0]):
                    name = data[at:at + 16].rstrip(b"\0").decode()
                    _, length, fileoffset = struct.unpack_from("<QQI", data, at + 32)
                    self.sections[(segment, name)] = (fileoffset, length)
                    at += 80
            offset += size

    def relative(self, at):
        return at + struct.unpack_from("<i", self.data, at)[0]

    def cstring(self, at):
        return self.data[at:self.data.index(b"\0", at)].decode("utf-8", "replace")

    def context_name(self, at):
        """The name of the type context descriptor at `at`."""
        try:
            return self.cstring(self.relative(at + 8))
        except (ValueError, IndexError, struct.error):
            return None

    def mangled(self, at):
        """A mangled type name, with symbolic references written as {Name}."""
        text = []
        index = at
        while self.data[index] != 0:
            byte = self.data[index]
            if 1 <= byte <= 0x17:
                target = index + 1 + struct.unpack_from("<i", self.data, index + 1)[0]
                name = None
                if byte == 1:
                    name = self.context_name(target)
                elif byte == 2:
                    raw = struct.unpack_from("<Q", self.data, target)[0]
                    if not raw >> 63:  # a rebase within this binary, not a bind to another
                        pointer = raw & 0xFFFFFFFFF
                        name = self.context_name(pointer - self.base if pointer >= self.base else pointer)
                text.append("{" + (name if name and name.isascii() else "external") + "}")
                index += 5
            elif 0x18 <= byte <= 0x1F:
                text.append("{external}")
                index += 9
            else:
                text.append(chr(byte))
                index += 1
        return "".join(text)

    def descriptors(self):
        """Every field descriptor: (type name, kind, [(field, type)])."""
        start, length = self.sections[("__TEXT", "__swift5_fieldmd")]
        at, end = start, start + length
        while at < end:
            name_offset = struct.unpack_from("<i", self.data, at)[0]
            kind, record_size, count = struct.unpack_from("<HHI", self.data, at + 8)
            name = readable(self.mangled(at + name_offset)) if name_offset else ""
            fields = []
            for index in range(count):
                record = at + 16 + index * record_size
                _, type_offset, field_offset = struct.unpack_from("<Iii", self.data, record)
                field = self.cstring(record + 8 + field_offset) if field_offset else ""
                field_type = readable(self.mangled(record + 4 + type_offset)) if type_offset else ""
                fields.append((field, field_type))
            yield name, KINDS.get(kind, str(kind)), fields
            at += 16 + count * record_size


def readable(mangled):
    """The common cases of a mangled type, written the way Swift prints them."""
    def parse(index):
        if index >= len(mangled):
            return "?", index
        if mangled[index] == "{":
            end = mangled.index("}", index)
            name, index = mangled[index + 1:end], end + 1
        elif mangled[index:index + 2] in BASIC:
            name, index = BASIC[mangled[index:index + 2]], index + 2
        elif match := re.match(r"So(\d+)", mangled[index:]):
            # An imported Objective-C type: its name, then C, V or _p.
            start = index + len(match.group(0))
            length = int(match.group(1))
            name, index = mangled[start:start + length], start + length
            if mangled.startswith("_p", index):
                name, index = f"any {name}", index + 2
            elif index < len(mangled) and mangled[index] in "CVO":
                index += 1
        else:
            return mangled[index:], len(mangled)
        if mangled.startswith("y", index):
            arguments, index = [], index + 1
            while index < len(mangled) and mangled[index] != "G":
                argument, index = parse(index)
                arguments.append(argument)
            name, index = f"{name}<{', '.join(arguments)}>", index + 1
        while mangled.startswith("Sg", index):
            name, index = f"Optional<{name}>", index + 2
        return name, index

    name, index = parse(0)
    return name + mangled[index:]


def main():
    app = Path(sys.argv[1] if len(sys.argv) > 1 else "/Applications/Droppy.app")
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        binary = Binary(app / "Contents/MacOS" / info["CFBundleExecutable"])
    except (OSError, KeyError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Cannot read {app}: {error}")
        return 2

    print(f"Droppy {info.get('CFBundleShortVersionString', '?')} ({info.get('CFBundleVersion', '?')}) at {app}")
    types = {}
    for name, kind, fields in binary.descriptors():
        types.setdefault(name, (kind, fields))
    has_class_name = CLASS_NAME.encode() in binary.data
    print(f"Objective-C name {CLASS_NAME}: {'present' if has_class_name else 'MISSING'}")

    problems = 0 if has_class_name else 1
    if MANAGER not in types:
        print(f"\n{MANAGER}: MISSING. Droppy renamed or removed it; the droplet cannot find it.")
        return 1
    kind, fields = types[MANAGER]
    declared = dict(fields)
    print(f"{MANAGER}: {kind}, {len(fields)} stored fields\n")

    print("Fields the droplet reads:")
    for field, expected in FIELDS.items():
        found = declared.get(field)
        if found is None:
            status, problems = "MISSING", problems + 1
        elif found != expected:
            status, problems = "CHANGED", problems + 1
        else:
            status = "ok"
        detail = "" if status == "ok" else f"  (expected {expected})"
        print(f"  {status:8} {field:32} {found or '-'}{detail}")

    print("\nInside the fields:")
    for name, expected_fields in NESTED.items():
        nested = dict(types.get(name, ("", []))[1])
        for field, expected in expected_fields.items():
            found = nested.get(field)
            ok = found == expected
            problems += 0 if ok else 1
            detail = "" if ok else f"  (expected {expected})"
            print(f"  {'ok' if ok else 'MISSING' if found is None else 'CHANGED':8} {name}.{field:16} {found or '-'}{detail}")
    for name, expected_cases in CASES.items():
        cases = [case for case, _ in types.get(name, ("", []))[1]]
        missing = [case for case in expected_cases if case not in cases]
        problems += len(missing)
        status = "ok" if not missing else "MISSING " + ", ".join(missing)
        print(f"  {'ok' if not missing else 'CHANGED':8} {name}: {', '.join(cases) or '-'}"
              + ("" if not missing else f"  ({status})"))

    print(f"\nEvery stored field of {MANAGER}:")
    for field, field_type in fields:
        print(f"  {field:34} {field_type}")

    print()
    if problems:
        print(f"{problems} problem(s): update the names in BuiltInPomodoroReader.swift "
              "(and BuiltInPomodoroLocator.swift for the class), then check the rules "
              "in BuiltInSessionTracker.swift against a probe run.")
        return 1
    print("Everything the droplet reads is there, with the types it expects.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
