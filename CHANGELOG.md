# Changelog

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
