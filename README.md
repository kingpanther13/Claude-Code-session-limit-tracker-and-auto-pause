# Claude Code Session Limit Tracker

A Claude Code status line that shows your usage limits: the **5-hour session
window** and the **7-day weekly window**, each with the time until it resets.

```
S:8%(r2h01m) W:41%(r3d4h) | Opus 4.8
```

## How it works

Claude Code passes the status line command a JSON payload on stdin that
includes `rate_limits.five_hour` and `rate_limits.seven_day` (each with
`used_percentage` and `resets_at`). `statusline-usage.sh` reads them and
prints the bar above. Each refresh runs a single `jq`.

## Requirements

- A recent Claude Code with `rate_limits` in the statusline payload.
- A **Claude.ai Pro/Max subscription**. The rate-limit fields only appear for
  subscription auth, and only after the first API response of a session.
- `bash` (4+) and `jq` on `PATH`.

## Install

```bash
git clone https://github.com/kingpanther13/Claude-Code-session-limit-tracker-and-auto-pause.git
cd Claude-Code-session-limit-tracker-and-auto-pause
./install.sh
```

Then merge the `statusLine` block from
[`settings.example.json`](settings.example.json) into your
`~/.claude/settings.json` (add it alongside your existing settings, don't
overwrite the file) and restart Claude Code.

Manual install: copy `statusline-usage.sh` into `~/.claude/`, `chmod +x` it,
and add the settings block.

### Upgrading from the auto-pause version

Earlier versions also shipped a threshold hook that paused and resumed work.
It has been removed. Delete the `hooks` entries that run
`usage-threshold-hook.sh` from `~/.claude/settings.json`, then delete
`~/.claude/usage-threshold-hook.sh`, `usage-actions.json`, `usage-state.json`
and `usage-fired.json`.

## Testing

```bash
printf '%s' '{"model":{"display_name":"Test"},"rate_limits":{"five_hour":{"used_percentage":98.5,"resets_at":'"$(( $(date +%s)+3600 ))"'},"seven_day":{"used_percentage":40,"resets_at":'"$(( $(date +%s)+200000 ))"'}}}' \
  | bash statusline-usage.sh; echo
```

Set `CLAUDE_USAGE_DEBUG` to a path to have the script log the raw statusline
payloads (rolling last 20), handy for confirming your Claude Code build
includes the `rate_limits` fields. It's off unless the variable is set.

## Files

| File | Role |
|------|------|
| `statusline-usage.sh` | Prints the status bar |
| `settings.example.json` | The `statusLine` block to merge |
| `install.sh` | Copies the script into `~/.claude` |

## License

MIT — see [LICENSE](LICENSE).
