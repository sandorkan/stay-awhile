# Upgrading from an earlier version

[Back to the README](../README.md)

The plugin used to have a different name. If you still have the old one
installed (its plugin id starts with `waiting-room`), disable it before
enabling this one, so hooks do not run twice.

Run `/stay-awhile:init` after installing. Its setup plan carries over any
options saved under the old name, keeping choices you have already made here,
and updates an old viewer status-line path rather than chaining it twice. The
previous settings entry is left in place for rollback.

Turn history, the data directory, browser scene and turn-strip preferences,
and the old `*_PORT` / `*_SIMULATION` environment variables all keep working;
the compatibility code is documented in CLAUDE.md.
