# To do

Things Droppy or DroppyKit do not allow yet are in
[LIMITATIONS.md](LIMITATIONS.md), with the routine to run after a Droppy
update.

The timer is Droppy's own now, so everything here builds on the log.

## Building on the log

- **A daily goal**, and how close today is to it, on the settings page.
- **Weekly and monthly charts** on the History page.
- **Notes and tags** on a session, edited from History. `note` and `tags`
  exist, and `SessionStore.update` writes the change.
- **Focus titles in History.** Droppy's Pomodoro can give a session a title,
  and the log keeps it in `title`, but History doesn't show it yet.
- **A small shelf widget** with today's focus and the streak. It would bring
  back the `shelf-widget` surface, read-only this time.
- **Tools for AI apps** (`MCPToolProviding`) once Droppy ships DroppyKit 1.21
  or later, to answer "how much did I focus this week".

## Open questions

- **Sleep.** The built-in counts from the wall clock, so a session left
  running while the Mac sleeps most likely logs the time asleep as active.
  Decide whether the log should leave it out: the droplet could watch for
  sleep and wake and record them as a pause and a resume.
- **Clock timers.** They're logged and count toward no total. Decide whether
  they belong in this log at all, or behind a switch.

## Housekeeping

- The log is one JSON file, rewritten every time a session ends. That's fine
  for years of use; split it by year if it ever gets slow.
- When Droppy updates, run the routine in LIMITATIONS.md. Then raise the
  DroppyKit pin in `Package.swift` and `kit.minAPI` in `droplet.json` to what
  the new Droppy carries.
