# Claude Code Session Limit Tracker & Auto-Pause

Surfaces your Claude Code usage limits — the **5-hour session window** and the
**7-day weekly window** — into Claude's own context while it works, and can
automatically **pause all work when you're about to hit a limit and resume it
after the window resets**.

```
S:8%(r2h1m) W:41%(r3d4h) | Opus 4.8
```

## Why this exists

Claude Code shows your rate-limit usage in `/usage`, but that number isn't
available to Claude itself, and it isn't available to hooks either. So the model
has no idea when you're about to be cut off mid-task.

It turns out the numbers *are* exposed in exactly one place a script can reach:
the **statusline command's stdin JSON**, under `rate_limits.five_hour` and
`rate_limits.seven_day` (each with `used_percentage` and `resets_at`). This tool
bridges that single gap.

## How it works

- **Sensor — `statusline-usage.sh`** runs as your `statusLine` command. On every
  render it reads the rate-limit percentages and reset times from stdin, writes
  them to `~/.claude/usage-state.json`, and prints a compact bar showing both
  windows and their countdowns.
- **Trigger — `usage-threshold-hook.sh`** runs on `PostToolUse` (after every
  tool call) and `UserPromptSubmit`. It reads the state file and, when a window
  first crosses a threshold band, injects a message straight into Claude's
  context via `hookSpecificOutput.additionalContext`. It de-dupes per band per
  reset window, so each crossing fires once — not on every tool call.

Because it fires on every tool call, you get near-continuous checks *while Claude
is actively working* — which is exactly when limits get consumed. It does not
(and cannot) wake Claude between turns; nothing in Claude Code can. It only
speaks up during an active turn.

## Requirements

- A recent Claude Code with `rate_limits` in the statusline payload.
- A **Claude.ai Pro/Max subscription** — the rate-limit fields only appear for
  subscription auth, and only after the first API response of a session.
- `bash` (4+), `jq`, and `python3` on `PATH`.

## Install

```bash
git clone https://github.com/kingpanther13/Claude-Code-session-limit-tracker-and-auto-pause.git
cd Claude-Code-session-limit-tracker-and-auto-pause
./install.sh
```

Then merge the `statusLine` and `hooks` blocks from
[`settings.example.json`](settings.example.json) into your
`~/.claude/settings.json` (add them alongside your existing settings — don't
overwrite the file), and restart Claude Code or open `/hooks` once so it reloads.

Manual install is just as easy: copy the three files into `~/.claude/`, `chmod
+x` the two scripts, and add the settings blocks.

## Configuration — `usage-actions.json`

```jsonc
{
  "bands": [50, 75, 90, 95, 98, 99],
  "session_directives": { "98": "...stop + @@AUTORESUME@@" },
  "weekly_directives":  { "99": "...stop + @@AUTORESUME@@" }
}
```

- **`bands`** — the usage percentages that trigger an injection. A window only
  fires when it *first* crosses a band within its current reset window.
- **`session_directives` / `weekly_directives`** — keyed by band string. The
  text is injected as an instruction to Claude when that band is crossed. Bands
  with no directive are **report-only** (Claude is told the level and the reset
  time, nothing more).
- **`@@AUTORESUME@@`** — put this token anywhere in a directive and the hook
  appends a `RESUME TARGET` = that window's reset **+ 1 minute**, formatted as a
  ready-to-run `CronCreate(recurring:false, ...)` call.

Every injected alert also reports **both** windows' reset times (absolute local
time + countdown), so Claude always knows when relief arrives.

### Default behavior

| Band | Session (5h) | Weekly (7d) |
|-----:|--------------|-------------|
| 50 / 75 / 90 / 95 | report only | report only |
| 98 | **stop + auto-resume** | report only |
| 99 | (stop, via ≥98 rule) | **stop + auto-resume** |

Edit `usage-actions.json` to taste — change the bands, wire your own directives
into other levels, or remove the auto-resume token to make it alert-only. The
hook re-reads the file on every fire; no restart needed.

## Auto-pause & resume

When a window crosses a band whose directive carries `@@AUTORESUME@@`, Claude
receives an instruction to:

1. immediately **stop all work** (`TaskStop` any running agents/workflows) and
   start nothing new,
2. write a one-line handoff of what was in progress, and
3. schedule the provided one-time `CronCreate` for ~1 minute after the window
   reopens, whose prompt tells it to resume from the handoff.

**Honest caveats:**

- It is **model-driven**. The hook injects the instruction and a ready-made
  command; Claude carries it out. It's a strong nudge with the exact command
  pre-computed, not a hard kernel-level kill switch.
- `CronCreate` jobs are **in-session / in-memory**. The resume only fires if the
  Claude Code REPL stays open through the cooldown. Close the terminal and the
  scheduled resume is gone.
- Resume continuity is only as good as the one-line handoff — it's continuity of
  intent, not a perfect snapshot of in-flight state.

## Testing

The live hook reads `~/.claude/usage-state.json` on every tool call, so **never
write synthetic data into your live state file to test** — you'll fire real
alerts. Both scripts honor env overrides so you can test against throwaway files:

```bash
TD=$(mktemp -d)
export CLAUDE_USAGE_STATE="$TD/state.json" \
       CLAUDE_USAGE_FIRED="$TD/fired.json" \
       CLAUDE_USAGE_DEBUG="$TD/dbg.jsonl" \
       CLAUDE_USAGE_ACTIONS="$PWD/usage-actions.json"

# feed a fake payload to the sensor, then run the hook against the temp state
printf '%s' '{"model":{"display_name":"Test"},"rate_limits":{"five_hour":{"used_percentage":98.5,"resets_at":'"$(( $(date +%s)+3600 ))"'},"seven_day":{"used_percentage":40,"resets_at":'"$(( $(date +%s)+200000 ))"'}}}' \
  | bash statusline-usage.sh; echo
echo '{}' | bash usage-threshold-hook.sh PostToolUse | jq -r '.hookSpecificOutput.additionalContext'
rm -rf "$TD"
```

Set `CLAUDE_USAGE_DEBUG` to a path to have the sensor log the raw statusline
payloads (rolling last 20) — handy for confirming your Claude Code build
actually includes the `rate_limits` fields. It's off unless the var is set.

## Files

| File | Role |
|------|------|
| `statusline-usage.sh` | Sensor: writes `usage-state.json`, prints the status bar |
| `usage-threshold-hook.sh` | Trigger: injects alerts + resume commands at thresholds |
| `usage-actions.json` | Config: bands + per-band directives |
| `settings.example.json` | The `statusLine` + `hooks` blocks to merge |
| `install.sh` | Copies scripts into `~/.claude` |

Runtime files the tool writes into `~/.claude/`: `usage-state.json` (current
levels) and `usage-fired.json` (dedup bookkeeping).

## License

MIT — see [LICENSE](LICENSE).
