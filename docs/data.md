# Local data and turn history

[Back to the README](../README.md)

Completed turns append tab-separated rows to `waits.log` in the plugin's data
directory; permission prompts append intermediate checkpoints too.
Claude Code normally assigns this directory through `CLAUDE_PLUGIN_DATA`.
`~/.claude/waiting-room/data-dir` points to it, and
`python3 scripts/setup.py status` prints the resolved path. Without an assigned
directory, the fallback is `~/.claude/waiting-room`.
`waits.log` contains counts, timings, session IDs, and the project's folder
name; it does not store prompt text or file contents. To compute the counts,
the metrics helper reads the local transcript's last user message.

Separately, the status-line integration saves the full payload received from
Claude Code to `status.json` and rate-limit cache files. These are not limited
to the log's columns and may include paths and other session metadata. The
viewer reads them through a local loopback server. These plugin data files
stay on your machine; the plugin does not send them to an external service.

| # | Column | |
|---|--------|---|
| 1 | `ended` | when the turn ended |
| 2 | `seconds` | how long it ran |
| 3 | `outcome` | `done`, `failed`, `needs-you`, `silent` |
| 4 | `session` | Claude Code's session id |
| 5–6 | `words`, `chars` | how long the prompt was |
| 7 | `images` | images attached to it |
| 8–13 | `paths`, `code_blocks`, `urls`, `bullets`, `questions`, `is_slash` | how the prompt was shaped |
| 14–15 | `tools`, `permissions` | tool calls, and permission prompts during the turn |
| 16 | `think_secs` | gap between the last turn ending and this prompt |
| 17 | `switched_away` | 1 if you prompted another session while this one ran |
| 18 | `concurrent` | other turns already running when this one started |
| 19 | `project` | folder name of the working directory |

Columns 5–13 are measured from the transcript's last user message. Zeros there
mean "couldn't measure" (no `python3`, no transcript), not "none".

A turn stopped by a permission prompt logs a `needs-you` line and keeps
counting, so you see both the stretch before the prompt and the whole turn.

```bash
# Use the data directory printed by: python3 scripts/setup.py status
cd /path/to/plugin-data

# the shape of your day
awk -F'\t' '$3 != "needs-you" {n++; s+=$2; if ($2>m) m=$2; if ($2>120) long++}
  END {printf "%d turns, %.0f min waiting, mean %.0fs, longest %ds, %d over 2 min\n",
       n, s/60, (n ? s/n : 0), m, long}' waits.log

# mid-task switching: how often, and what you were leaving
awk -F'\t' '$3 != "needs-you" && $17==1 {n++; s+=$2} END {printf "%d switches, average turn %.0fs\n", n, (n ? s/n : 0)}' waits.log

# do longer prompts mean fewer corrections? (a turn re-prompted within 20s)
awk -F'\t' '$3 == "needs-you" {next} NR>1 && $16<20 && $16>=0 {short[bucket]++} {bucket = ($5<25 ? "under 25 words" : "25+ words"); all[bucket]++}
  END {for (b in all) printf "%-15s %d turns, %d quick re-prompts\n", b, all[b], short[b]}' waits.log
```
