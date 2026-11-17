# Changelog

## [Unreleased]

Your focus sessions now climb mountains. Nothing changes in how sessions are
logged.

- The climb: pick a mountain in the expedition log, and each focus climbs it,
  10 m a minute. A focus started soon after a finished break climbs 20%
  further. There are seven peaks, from Ben Nevis to Olympus Mons on Mars, to
  climb in any order and as often as you like. A climb ends at its top. Picking
  another mountain mid-climb clears the one you leave, and the log asks first
  when that would lose metres.
- Tomatoes and jars: a tomato is a focus countdown that reached zero, and every
  fourth tomato of a day fills a jar.
- The Summit widget on the shelf: the peak you're climbing, drawn from its real
  view, with your trail, today's tomatoes and the sessions to the top. With no
  climb under way, it points to the expedition log.
- The expedition log, from the widget's expand button: every peak with a Climb
  button, today's climb split into focus and break bonus, the week's pantry and
  the latest stickers.
- Stickers: 23 for how you work and one for each peak's top, which counts every
  time you reach it. Settings has a sticker book.
- Notch moments: a summit, a new sticker and a filled jar show in the notch.
  They wait while the shelf is open.
- Settings has a Summit section and explains how the climb works.
- Picks are saved in `expeditions.json` beside the session log.
- The droplet now asks for the hud, expanded-surface, shelf-read and
  shelf-write capabilities.

## [2.0.0] - 2026-11-15

Pomolog is now a log for Droppy's own Pomodoro instead of a timer of its own.

- Renamed from Pomodoro Log to Pomolog.
- Logs every session of Droppy's built-in Pomodoro: Focus and Break
  countdowns, stopwatch runs, and timers from the Clock app or Siri that the
  built-in shows. It reads the built-in through Droppy's private internals,
  from inside Droppy, so a Droppy update can stop it. The settings page says
  when that happens.
- Removed the droplet's own timer, shelf widget, notch countdown and time-up
  message, with their settings. Their stored values are cleared.
- The settings page starts with whether Droppy's Pomodoro is being logged.
- History marks stopwatch runs and Clock timers. Stopwatch runs add to focus
  time but don't count as completed sessions; Clock timers count toward no
  total.
- The log is schema version 2: `kind` can be `clock` and `source` can be
  `stopwatch`. Logs from 1.0 read as they are. 1.0 can't read a version 2 log
  and moves it aside, intact.
- The droplet no longer needs any capabilities.

## [1.0.1] - 2026-11-15

- Probe for Droppy's own Pomodoro: finds its state inside Droppy and writes
  what it reads to `builtin-probe.log` beside the session log. Read-only; it
  records no sessions yet.

## [1.0.0] - 2026-11-10

- First release.
