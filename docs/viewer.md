# Viewer setup and internals

[Back to the README](../README.md)

Commands below run from a source checkout. Where `python3` is not available,
use `python` with Python 3 installed.

## Status line and usage data

`scripts/statusline.sh` prints a compact row and saves the payload Claude Code
hands it to `status.json` in the plugin’s data directory. That payload is the only
local source for the numbers `/usage` shows — the 5-hour and weekly
percentages and their reset times — which is what the visual viewer needs.

```
18% · 1:35 · wk 46%
```

These are percentages **used**, followed by hours and minutes until the
five-hour window resets. The weekly percentage also means used.

**After installing the plugin, run `/stay-awhile:init` once.** It shows what
it would change, asks before touching your settings, and explains the trade.
Then `/stay-awhile:show` opens the window whenever you want it, and
`/stay-awhile:close` puts it away early (it stops by itself when your last
session ends).

Under the hood that's `scripts/setup.py`, which also works on its own:

```bash
python3 scripts/setup.py status     # what's configured, is the server up
python3 scripts/setup.py install    # dry run; add --apply to write it
python3 scripts/setup.py open       # start the server and open the viewer
python3 scripts/setup.py stop
```

Or add it to `settings.json` by hand, substituting the actual installed plugin
path printed by `python3 scripts/setup.py status` (on Windows, write it with
forward slashes, `C:/Users/you/...`, because bash runs the command):

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/stay-awhile/scripts/statusline.sh\"",
    "refreshInterval": 5
  }
}
```

`refreshInterval` matters: status-line updates are event-driven and go quiet
while a session is idle, which is exactly when you'd be watching the number.

Two things worth knowing before you add it:

- **A configured status line replaces some of Claude Code's footer hints**
  (`esc to interrupt`, `? for shortcuts`, the voice-dictation hint). That's
  the trade for a permanent usage readout.
- **`rate_limits` only appears for Pro and Max subscribers, and only after the
  session's first API response.** An empty row before then is correct, not a
  failure. Each window also disappears from the payload once it resets.

**Already have a status line?** `/stay-awhile:init` offers to chain to it. By
hand, set `CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN` to it and its output is printed first, with the
usage segments appended:

```json
"command": "CLAUDE_PLUGIN_OPTION_STATUSLINE_CHAIN='~/.claude/my-statusline.sh' \"/absolute/path/to/stay-awhile/scripts/statusline.sh\""
```

## Server and rendering

`scripts/viewer-server.py` serves `viewer/` on `127.0.0.1:8787` and streams
state to the page as it changes. It reads hook/status data, maintains its own
server identity file, and saves music selections through the setup helper.

The moon advances locally even while no new server events arrive. When a
cached usage window expires, the viewer clears its percentage to a dash until
fresh numbers arrive; it doesn't keep showing an expired “spent” window.
Partial status updates preserve the last known values for each window until
that window resets; a weekly-only update does not clear the five-hour display.

The server stays available while another session is open, including between
prompts. Session hooks register leases and the status line refreshes them.
Leases older than two hours are ignored; after 30 minutes with no viewers or
fresh session/activity leases, an abandoned server retires. A deliberate
`/stay-awhile:close` stops it earlier. Server ownership is checked before any
process is signalled.
