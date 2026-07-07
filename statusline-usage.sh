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

input="$(cat)"

# Optional raw capture (opt-in) to verify the real payload schema.
if [ -n "$DEBUG" ]; then
  { printf '%s\n' "$input" >> "$DEBUG"; tail -n 20 "$DEBUG" > "$DEBUG.tmp" 2>/dev/null && mv "$DEBUG.tmp" "$DEBUG"; } 2>/dev/null
fi

# Extract fields, one per line so empty values keep their position.
mapfile -t V < <(printf '%s' "$input" | jq -r '
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // ""),
  (.model.display_name // .model.id // "")' 2>/dev/null)

S_PCT="${V[0]-}"; S_RESET="${V[1]-}"; W_PCT="${V[2]-}"; W_RESET="${V[3]-}"; MODEL="${V[4]-}"
now="$(date +%s)"

# Persist state atomically. Each field is coerced to a number or null (never the
# empty stream) so the object always constructs and we never write a blank file.
if jq -n \
     --arg s "$S_PCT" --arg sr "$S_RESET" --arg w "$W_PCT" --arg wr "$W_RESET" --arg t "$now" \
     '{
        five_hour_pct:   (($s|tonumber?)  // null),
        five_hour_reset: (($sr|tonumber?) // null),
        seven_day_pct:   (($w|tonumber?)  // null),
        seven_day_reset: (($wr|tonumber?) // null),
        updated:         (($t|tonumber?)  // null)
      }' > "$STATE.tmp" 2>/dev/null && [ -s "$STATE.tmp" ]; then
  mv "$STATE.tmp" "$STATE" 2>/dev/null
else
  rm -f "$STATE.tmp" 2>/dev/null
fi

# Display: percent + when each window resets (relative).
fmt() { if [ -n "${1:-}" ] && [ "$1" != "null" ]; then printf '%.0f%%' "$1"; else printf -- '--'; fi; }
rel() {
  local e="${1:-}"; case "$e" in ""|"null"|"0") printf '?'; return;; esac
  local d=$(( e - now )); [ "$d" -le 0 ] && { printf 'now'; return; }
  local days=$(( d/86400 )) h=$(( (d%86400)/3600 )) m=$(( (d%3600)/60 ))
  if [ "$days" -gt 0 ]; then printf '%dd%dh' "$days" "$h"; else printf '%dh%02dm' "$h" "$m"; fi
}
printf 'S:%s(r%s) W:%s(r%s) | %s' \
  "$(fmt "$S_PCT")" "$(rel "$S_RESET")" "$(fmt "$W_PCT")" "$(rel "$W_RESET")" "${MODEL:-claude}"
