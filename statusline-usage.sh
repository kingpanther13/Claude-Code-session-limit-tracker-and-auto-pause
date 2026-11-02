#!/usr/bin/env bash
# Claude Code usage sensor (statusLine command).
# Reads the statusLine JSON on stdin, persists rate-limit state to a file that
# the usage-threshold hook reads, and prints a compact status line.
#
# Env overrides (for testing without touching your live files):
#   CLAUDE_USAGE_STATE  - state file path   (default: ~/.claude/usage-state.json)
#   CLAUDE_USAGE_DEBUG  - if set, append raw payloads here (rolling last 20)
set -u

DIR="$HOME/.claude"
STATE="${CLAUDE_USAGE_STATE:-$DIR/usage-state.json}"
DEBUG="${CLAUDE_USAGE_DEBUG:-}"

IFS= read -r -d '' input || true
printf -v now '%(%s)T' -1

# Optional raw capture (opt-in) to verify the real payload schema.
if [ -n "$DEBUG" ]; then
  { printf '%s\n' "$input" >> "$DEBUG"; tail -n 20 "$DEBUG" > "$DEBUG.tmp" 2>/dev/null && mv "$DEBUG.tmp" "$DEBUG"; } 2>/dev/null
fi

# One jq per refresh: every process start costs (slow on Windows Git Bash, and
# some Windows drivers leak kernel memory per process). Line 1 is the state
# object, each field a number or null; line 2 is the status line.
jq -r --argjson now "$now" '
  def num: if type == "number" then . elif type == "string" then (tonumber? // null) else null end;
  def fmt: if . == null then "--" else "\(round)%" end;
  def rel: if . == null or . == 0 then "?" else (. - $now | floor) as $d
    | if $d <= 0 then "now" else ($d / 86400 | floor) as $D | ($d % 86400 / 3600 | floor) as $h | ($d % 3600 / 60 | floor) as $m
      | if $D > 0 then "\($D)d\($h)h" else "\($h)h\(if $m < 10 then "0" else "" end)\($m)m" end end end;
  (.rate_limits.five_hour.used_percentage | num) as $s | (.rate_limits.five_hour.resets_at | num) as $sr
  | (.rate_limits.seven_day.used_percentage | num) as $w | (.rate_limits.seven_day.resets_at | num) as $wr
  | ({five_hour_pct: $s, five_hour_reset: $sr, seven_day_pct: $w, seven_day_reset: $wr, updated: $now} | tojson),
    "S:\($s | fmt)(r\($sr | rel)) W:\($w | fmt)(r\($wr | rel)) | \(.model.display_name // .model.id // "" | if . == "" then "claude" else . end)"
' <<<"$input" > "$STATE.tmp" 2>/dev/null

if { IFS= read -r state && IFS= read -r line; } < "$STATE.tmp" 2>/dev/null; then
  state="${state%$'\r'}"; line="${line%$'\r'}"
else
  state="{\"five_hour_pct\":null,\"five_hour_reset\":null,\"seven_day_pct\":null,\"seven_day_reset\":null,\"updated\":$now}"
  line="S:--(r?) W:--(r?) | claude"
fi

# Persist state atomically.
printf '%s\n' "$state" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
printf '%s' "$line"
