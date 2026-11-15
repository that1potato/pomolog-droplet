# Limitations

What Droppy and DroppyKit do not let this droplet do, as of **15 November
2026** on **Droppy 16.0.1**, which carries **DroppyKit 1.20.1**. Each entry
says where the limit comes from, what the droplet does about it, and what to
look for in a later release.

Ideas are in [TODO.md](TODO.md); this file is only for things the host or the
SDK stands in the way of.

## After a Droppy update

The droplet reads Droppy's Pomodoro without an API (see below), so an update
can stop the logging. After every update:

1. Open Droppy's Settings, Pomolog. The card at the top should say
   **Logging**, or **Recording** and a section name while a session runs.
2. Run a 1-minute Focus in Droppy's Pomodoro, and check that History shows it
   with the right times.
3. If the card says **Not logging**, or the session is missing or wrong, run:

   ```bash
   python3 Scripts/dump-builtin-pomodoro.py
   ```

   It lists the fields of `PomodoroManager` in the installed Droppy and marks
   every one the droplet reads that is missing or has changed type. These are
   the files to fix:
   - the field names the droplet reads: `Sources/Pomodorolog/BuiltIn/BuiltInPomodoroReader.swift`
   - the class name: `BuiltInPomodoroLocator.swift`
   - the rules that turn readings into sessions: `BuiltInSessionTracker.swift`

   If only names moved, fixing them is enough. If the built-in behaves
   differently, record a run first: a probe that reads the built-in every half
   second and writes each change to a log, like the run replayed in
   `Tests/PomodorologTests/ProbeRun20261115.swift` (see "How the rules were
   found").
4. Check whether DroppyKit has grown a real API for the built-in timer:

   ```bash
   git -C /path/to/droppykit fetch --tags
   ```

   Then read `COMPATIBILITY.md` and
   `Sources/DroppyKit/Documentation.docc/HostSupport.md` at the newest tag.
5. Raise the pin in `Package.swift` and `kit.minAPI` in `droplet.json` only to
   what the installed Droppy carries. A droplet that asks for more is refused.

Versions known when this was written:

| Droppy | DroppyKit |
| --- | --- |
| 16.0.1 (stable) | 1.20.1 |
| 16.1.2-beta.1 to 16.2.0-beta.4 | 1.21.0 |
| nightlies since 3 November 2026 | 1.22.0, up to 1.27.0 |

## Droppy's built-in Pomodoro

### There is no API for it

- **Why:** it is compiled into Droppy, and DroppyKit has no service for its
  state, up to 1.27.0. The launcher can start a Pomodoro but reports nothing.
  From 1.23, a live activity of the `timer` kind only learns that one of
  Droppy's timers holds the notch, which can't tell Pomodoro from Stay Awake.
- **What the droplet does:** reads it unofficially, from inside Droppy's
  process:
  - `BuiltInPomodoroLocator` finds the one `PomodoroManager`
    (`_TtC6Droppy15PomodoroManager`). It looks through Droppy's global
    variables for a pointer to a live object of that class. On 16.0.1 that
    pointer sits in `__DATA,__common`, and the search takes 0.3 ms.
  - `BuiltInPomodoroReader` copies the object's fields out by name with
    `Mirror`. That works because Droppy's binary carries Swift's reflection
    metadata.
  - Nothing of Droppy's is called or written.
- **What can break it:** a Droppy update that does any of these:
  - renames `PomodoroManager`
  - renames or retypes a field the droplet reads
  - keeps the object somewhere other than a global
  - changes what the fields mean

  Droppy's nightlies are already well past 16.0.1.
- **What you see then:** the settings card says **Not logging**, with the
  reason and the technical detail underneath, and `diagnostics.log` has the
  same line. Nothing is logged and nothing is guessed. A session that was
  running when reading stopped is closed no later than where it was last
  seen.
- **The Store:** the Store's rules forbid reaching into Droppy's internals
  (private API, and looking classes up by name), as set out in `Rules.md` in
  newer DroppyKit releases (1.27.0 has it; 1.20.1 doesn't). So this droplet
  isn't in the Store, and can't be submitted as it is.
- **Lifted by:** a host service for the built-in timer's sessions. None is
  announced. Those rules say to ask for a missing API by opening an issue in
  the Store repository ("Asking for an exception" in `Rules.md`).

### How the rules were found

The rules in `BuiltInSessionTracker.swift` come from two runs in Droppy 16.0.1
on 15 November 2026:
- A probe in 1.0.1 wrote every reading to `builtin-probe.log`. That log is
  replayed in
  `Tests/PomodorologTests/ProbeRun20261115.swift`.
- 2.0.0's first run showed how a stopwatch picks its section.

| The built-in | How it is logged |
| --- | --- |
| A countdown starts: `isActive` on, `activeSelection` set | Starts at `endTime − totalDurationSeconds`, exact |
| Pause and resume: `isPaused` flips, and `endTime` is cleared while paused | Stamped when seen, within half a second |
| Zero: `isOvertime` on | `reachedZero` at `endTime`, exact |
| Next: still active, and the section changes | The old session ends, and the new one starts, at the new one's start |
| Stop: `isActive` off | Stamped when seen |
| A stopwatch: always a focus session, even with Break selected; a pause clears `stopwatchStartTime` | Focus, with no countdown |
| A Clock or Siri timer: `timerProvenance` appleClock, never in overtime | Kind `clock`; one that rang ends when it reached zero |

### Not seen yet

Each of these is handled the way the rules suggest, but hasn't been watched in
Droppy:

- A Clock timer cancelled early. Expected: inactive before its deadline, so
  ended early.
- A Clock timer paused in the Clock app.
- Droppy quitting during a session. Expected: closed as interrupted from
  `active.json` at the next launch, at the last heartbeat, which can be up to
  30 seconds early.
- Sections beyond Focus and Break.

### A session that runs through sleep

- **Seen:** not yet tested. The built-in counts from the wall clock, so a
  session left running while the Mac sleeps most likely counts the time asleep
  as active, or as overtime.
- **What the droplet does:** follows the built-in. Whether the log should
  leave sleep out is an open question in [TODO.md](TODO.md).

## Notch moments and the takeover

On 15 November 2026, a throwaway probe (stage 1 of the summit work) tested in
Droppy 16.0.1 what a droplet may show while Droppy's own Pomodoro runs.

- **Capabilities:** Droppy grants a local build every capability its manifest
  declares (`hud`, `expanded-surface`, `shelf-read` and `shelf-write` were all
  granted). The settings page lists them under "What it can do".
- **HUDs are refused while the shelf is open.** That includes the moment a
  session ends because the user pressed Next inside the shelf. With the shelf
  closed, a card shows, even while Droppy's Pomodoro holds the notch: it
  covers the timer briefly, and a strip sent as a countdown reached zero was
  accepted both times.
  - **What the droplet does:** holds a moment until the shelf closes. It
    watches the shelf through `shelf-read`.
- **A takeover needs `ExpandedSurfaceHosting`.** Droppy finds a droplet's
  takeover by casting it to `ExpandedSurfaceHosting` and reading
  `expandedSurfaceProvider`. Conforming to `ExpandedSurfaceProviding` alone
  renders in the harness, but Droppy refuses every presentation without asking
  for a size. Neither the 1.20.1 guides nor the World Clock example mention
  this; the protocol's own documentation does, and the AI Stats droplet
  (`droplets/ai-receipt` in the Store repository) does it. With the
  conformance, a click on the widget opened a 640 × 330 takeover. Droppy
  proposed 369 × 93 standard and 1089 × 620 at most on the display it ran on.
- **Feedback:** `host.feedback.play(.success)` needs no capability. Whether
  the cue was audible wasn't checked.

## Waiting on a newer Droppy

- **Tools for AI apps:** `MCPToolProviding` needs DroppyKit 1.21.0, so a stable
  Droppy that carries it.

## Building, installing and debugging

- **A full Xcode is required.** The Command Line Tools cannot compile
  SwiftUI's macros. When `xcode-select` points at the Command Line Tools, set
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for builds.
- **The DroppyKit MCP server's build and shots tools fail when `xcode-select`
  points at the Command Line Tools.** They pick those up and stop inside
  DroppyKit's SwiftUI sources, with
  "cannot assign to property: 'self' is immutable". Run `droppykit build` and
  `droppykit run -- --shots …` from a terminal with `DEVELOPER_DIR` set.
  `droppykit_validate` works, because it compiles nothing.
- **The SDK clone must match the installed Droppy.** For Droppy 16.0.1 that is
  `v1.20.1`. The newest scaffold and guides describe APIs that Droppy 16.0.1
  doesn't have.
- **A rebuilt droplet needs Droppy restarted.** macOS can't unload code, so the
  old build keeps running until then. A session running at that moment is
  logged as interrupted.
- **Unsigned builds are approved on every launch,** unless "Don't ask again
  for local droplets" is on (Settings, Store, Local droplets).
- **Droppy Playground can't test it.** The Playground has no built-in
  Pomodoro. Every test that matters runs in Droppy itself, by hand, since
  automation can't drive the notch. The recorded run in the tests stands in
  for that.
- **The droplet's log lines don't show up in `log show`.** Queries for
  Droppy's `droplets` category returned nothing on 16.0.1. `diagnostics.log`
  in the droplet's folder is the fallback.
- **It isn't documented whether the droplet's folder survives removing it.**
  Preferences are documented to survive removal, but the folder is only
  documented to persist "across updates". Export the log before removing the
  droplet.
