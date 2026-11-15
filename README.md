# Pomolog

A log of every session you run in [Droppy](https://getdroppy.app)'s own
Pomodoro. Use Droppy's Pomodoro as you always do. This droplet watches it,
writes each session to a file on your Mac, and shows the log in Droppy's
Settings. Built with [DroppyKit](https://getdroppy.app/docs/droppykit).

> [!WARNING]
> **Uses private API.** Droppy has no API for its built-in Pomodoro, so
> Pomolog reads Droppy's private internals: it finds Droppy's
> `PomodoroManager` object in memory and copies its fields by name. It never
> calls or changes anything of Droppy's, but any Droppy update can stop it
> logging. The Droppy Store doesn't accept droplets that do this, so Pomolog
> isn't there. It is unofficial, and not affiliated with or endorsed by
> Droppy.

Version 1 was a timer of its own, modelled on Droppy's Pomodoro. Version 2
drops it: the built-in timer is better than a copy, and all the log needed was
a way to see it. The droplet's id and code keep the name it started with,
`pomodorolog`.

## What it does

- **Logs Droppy's Pomodoro.** For every Focus and Break: when it started and
  ended, every pause, when it reached zero, any overtime, and how it ended.
  It ends completed, stopped early, by Next, or cut off by Droppy quitting.
- **Stopwatch runs and Clock timers too.** A stopwatch run is logged as focus
  time with no countdown. A timer from Apple's Clock app or Siri, which
  Droppy's Pomodoro shows in the notch, is logged as a Clock timer and counts
  toward no total.
- **History.** The droplet's page in Settings shows:
  - whether Droppy's Pomodoro is being logged
  - today's focus
  - the streak
  - all-time totals
  - every session by day

  Export CSV makes a copy for a spreadsheet.

## How it works

Droppy has no API for its built-in Pomodoro, so the droplet reads it through
Droppy's internals. A droplet runs inside Droppy's process, and the built-in
keeps its whole state in one object, `PomodoroManager`.

1. The droplet finds that object once, by looking through Droppy's global
   variables.
2. It reads the object's fields by name with Swift's `Mirror`: every half
   second while a session runs, every two seconds while idle. It never calls
   or changes anything of Droppy's.
3. `BuiltInSessionTracker` turns what it reads into the log's records.

This is fragile by nature: a Droppy update can rename the object or its
fields. When that happens the droplet logs nothing rather than guessing, and
its settings page says "Not logging" with the reason.
[LIMITATIONS.md](LIMITATIONS.md) has the routine to run after a Droppy update.

## The log

The log lives in the droplet's private folder (Settings, Pomolog, Log file,
Reveal in Finder):

```
sessions.json          { "schemaVersion": 2, "sessions": [ … ] }
sessions.backup.json   the copy from before the last write
active.json            the session running right now
diagnostics.log        what the droplet found, and every session it logged
```

Each session records:

- its kind: `focus`, `break` or `clock`
- its section, with the name and colour snapshotted
- its planned length
- its start and end in UTC, with the time zone it happened in
- every event, with its timestamp: `start`, `pause`, `resume`, `reachedZero`,
  `next`, `stop`, `interrupt`
- the active, paused and overtime seconds worked out from those events
- how it turned out: `completed`, `endedEarly` or `interrupted`
- what ended it
- its source: `timer` for a countdown, or `stopwatch`

`title`, `note` and `tags` are there for later features. Schema 2 added
`clock` and `stopwatch`, and a version 1 log reads as it is.

Start and zero times come from the built-in's own end time, so they're
exact. Pauses and stops are stamped within half a second of happening.

A file that cannot be read is moved aside under a dated name, never
overwritten. Export CSV writes a copy to `Exports/` beside the log.

## Building and installing

Needs Xcode 26 or later and a clone of the DroppyKit SDK at the version this
droplet pins: 1.20.1, the one Droppy 16.0.1 carries.

```bash
git clone --branch v1.20.1 https://gitlab.com/droppyformac1/droppykit.git   # once, anywhere
export PATH="/path/to/droppykit/Scripts:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # when xcode-select points at the Command Line Tools
swift test                 # the log, the tracker (with a recorded run), the reader
droppykit build            # writes .build/Pomodorolog.droplet
droppykit validate
```

To install:

1. In Droppy, go to Settings, Store, Local droplets.
2. Drop `.build/Pomodorolog.droplet` there and approve it.

After a rebuild, drop it again and restart Droppy, because the old build keeps
running until then. Droppy Playground has no built-in Pomodoro, so the droplet
can only be tried in Droppy itself.

After a Droppy update, `python3 Scripts/dump-builtin-pomodoro.py` lists the
built-in's fields in the installed Droppy. It flags any field the droplet
reads that has gone or changed type.

`droppykit agent` writes the files coding agents read (`AGENTS.md`,
`CLAUDE.md` and the DroppyKit MCP server's config), pointing at your SDK
clone. They're gitignored.

## Layout

```
Sources/Pomodorolog/
  PomodorologDroplet.swift   wiring: finds and reads the built-in, writes the log
  BuiltIn/                   locator, reader, snapshot, session tracker
  Model/Session.swift        the log's record types (Foundation only)
  Store/SessionStore.swift   the log on disk and its queries
  Surfaces/Settings.swift    the settings page and History
Tests/PomodorologTests/      the log, the tracker, the reader, and a recorded run
Scripts/                     dump-builtin-pomodoro.py
TODO.md                      ideas built on the log
LIMITATIONS.md               what Droppy and DroppyKit do not allow, and the update routine
```

## License

MIT. See [LICENSE](LICENSE).
