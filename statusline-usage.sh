#!/usr/bin/env bash
# Claude Code usage status line (statusLine command).
# Reads the statusLine JSON on stdin and prints the 5-hour and 7-day usage with
# the time to each reset. One jq per refresh: every process start costs (slow on
# Windows Git Bash, and some Windows drivers leak kernel memory per process).
#
# Env override:
#   CLAUDE_USAGE_DEBUG  - if set, append raw payloads here (rolling last 20)
set -u

DEBUG="${CLAUDE_USAGE_DEBUG:-}"
IFS= read -r -d '' input || true

# Optional raw capture (opt-in) to verify the real payload schema.
if [ -n "$DEBUG" ]; then
  { printf '%s\n' "$input" >> "$DEBUG"; tail -n 20 "$DEBUG" > "$DEBUG.tmp" 2>/dev/null && mv "$DEBUG.tmp" "$DEBUG"; } 2>/dev/null
fi

jq -nj '
  def num: if type == "number" then . elif type == "string" then (tonumber? // null) else null end;
  def fmt: if . == null then "--" else "\(round)%" end;
  def rel($now): if . == null or . == 0 then "?" else (. - $now | floor) as $d
    | if $d <= 0 then "now" else ($d / 86400 | floor) as $D | ($d % 86400 / 3600 | floor) as $h | ($d % 3600 / 60 | floor) as $m
      | if $D > 0 then "\($D)d\($h)h" else "\($h)h\(if $m < 10 then "0" else "" end)\($m)m" end end end;
  (now | floor) as $now
  | (try input catch null) | (if type == "object" then . else {} end)
  | "S:\(.rate_limits.five_hour.used_percentage | num | fmt)(r\(.rate_limits.five_hour.resets_at | num | rel($now)))"
    + " W:\(.rate_limits.seven_day.used_percentage | num | fmt)(r\(.rate_limits.seven_day.resets_at | num | rel($now)))"
    + " | \(.model.display_name // .model.id // "" | if . == "" then "claude" else . end)"
' <<<"$input" 2>/dev/null
