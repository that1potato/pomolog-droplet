# Pomolog

A log of every session you run in [Droppy](https://getdroppy.app)'s own
Pomodoro. Use Droppy's Pomodoro as you always do. This droplet watches it,
writes each session to a file on your Mac, and shows the log in Droppy's
Settings. Your focus also climbs a mountain you pick, on Droppy's shelf.
Built with [DroppyKit](https://getdroppy.app/docs/droppykit).

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

## The climb

Pick a mountain in the expedition log, and every focus takes you further up it.

- **Seven peaks, in any order:** Ben Nevis (1,345 m), Mount Fuji (3,776 m),
  Mont Blanc (4,808 m), Kilimanjaro (5,895 m), Aconcagua (6,961 m), Everest
  (8,849 m), and Olympus Mons on Mars (21,900 m). Each is drawn from a
  photograph of its best-known view; [docs/summit](docs/summit/README.md) has
  the drawings beside the photographs.
- **10 m a minute.** A 25-minute focus climbs 250 m. A countdown climbs up to
  the length you set, and time past zero doesn't count. A stopwatch run climbs
  at most 60 minutes. Breaks don't climb on their own.
- **The break bonus.** A focus that starts from a finished break climbs 20%
  further: 300 m instead of 250. The break has to follow a focus, run to zero
  and end no more than 5 minutes past it, and the next focus has to start
  within 2 minutes, as pressing Next does.
- **Tomatoes and jars.** A focus that runs to zero leaves a tomato on the
  trail, and every fourth tomato of a day fills a jar.
- **One climb at a time.** Focus climbs only while a mountain is picked. A
  climb ends at the top, and anything past it is dropped; then you pick the
  next peak, or the same one again. Switching to another peak part of the way
  up clears the climb you leave, and the log asks first.

Where it shows:

- **The Summit widget** on Droppy's shelf: the peak you're climbing, with your
  trail and the tomatoes along it, today's tomatoes and jars, and the sessions
  to the top. The climber moves while a focus runs. With no climb under way,
  it points you to the expedition log.
- **The expedition log**, from the widget's expand button: a field journal
  with every peak and a Climb button to pick one, today's climb split into
  focus and break bonus, the week's tomatoes and jars, and the latest
  stickers.
- **Stickers:** 23 for how you work, like Early bird for a tomato finished
  between 5:00 and 8:00, and one for each peak's top, which counts every time
  you reach it. The sticker book in Settings shows what earns each one when
  you point at it.
- **Notch moments:** reaching a top, finding a sticker and filling a jar show
  in the notch. They wait while the shelf is open.

The climb is worked out from the log each time. Only the peaks you pick are
stored, so a change to the log changes the climb with it.

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
sessions.json            { "schemaVersion": 2, "sessions": [ … ] }
sessions.backup.json     the copy from before the last write
active.json              the session running right now
expeditions.json         { "schemaVersion": 1, "picks": [ … ] }
expeditions.backup.json  the copy from before the last pick
diagnostics.log          what the droplet found, and every session it logged
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

Each pick is a peak's id, like `ben-nevis`, and the time you picked it. A focus
counts toward the peak picked when the focus ends.

A file that cannot be read is moved aside under a dated name, never
overwritten. Export CSV writes a copy to `Exports/` beside the log.

## Installing

1. Download `Pomodorolog.droplet.zip` from the
   [latest release](https://github.com/that1potato/pomolog-droplet/releases/latest)
   and unzip it.
2. In Droppy, go to Settings, Store, Local droplets, drop
   `Pomodorolog.droplet` there and approve it.

Built and tested on Droppy 16.0.1. Droppy hasn't signed it, so Droppy asks
again each time it opens unless "Don't ask again for local droplets" is on.
Droppy Playground has no built-in Pomodoro, so Pomolog only works in Droppy
itself.

To update, install a newer release the same way and restart Droppy, because
the old build keeps running until then.

## Building from source

Needs Xcode 26 or later and a clone of the DroppyKit SDK at the version this
droplet pins: 1.20.1, the one Droppy 16.0.1 carries.

```bash
git clone --branch v1.20.1 https://gitlab.com/droppyformac1/droppykit.git   # once, anywhere
export PATH="/path/to/droppykit/Scripts:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # when xcode-select points at the Command Line Tools
swift test                 # the log, the tracker (with a recorded run), the reader, the climb
droppykit build            # writes .build/Pomodorolog.droplet
droppykit validate
```

Install the build the same way as a release, from `.build/Pomodorolog.droplet`.
After a rebuild, drop it in again and restart Droppy.

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
  Rewards/                   the climb, peaks, tomatoes, jars and stickers, worked out from the log (Foundation only)
  Store/                     the log and the picks on disk
  Surfaces/                  the Summit widget, expedition log, notch moments and settings page
  Support/                   formatting and SVG path parsing
Tests/PomodorologTests/      the log, the tracker, the reader, a recorded run, and the climb
docs/summit/                 how the peaks are drawn, and the generator that writes PeakScenes.swift
Scripts/                     dump-builtin-pomodoro.py
TODO.md                      ideas built on the log
LIMITATIONS.md               what Droppy and DroppyKit do not allow, and the update routine
```

## License

MIT. See [LICENSE](LICENSE).
