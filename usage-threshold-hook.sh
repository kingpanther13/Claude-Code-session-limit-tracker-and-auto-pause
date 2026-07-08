#!/usr/bin/env bash
# Claude Code usage threshold hook.
# Usage: usage-threshold-hook.sh <EventName>
# Reads ~/.claude/usage-state.json (written by the statusline sensor). When the
# 5-hour (session) or 7-day (weekly) window first crosses a threshold band for
# its current reset window, injects a report into Claude's context via
# additionalContext. De-duped per band per reset window (fires once per crossing).
#
# Directives come from ~/.claude/usage-actions.json (session_directives /
# weekly_directives, keyed by band string). Any directive containing the token
# @@AUTORESUME@@ also emits a RESUME TARGET (that window's reset + 1 min) as a
# background `sleep <secs>` (Bash run_in_background) that re-invokes the model when
# the window reopens. Bands with no directive report only.
#
# Env overrides (for testing without touching your live files):
#   CLAUDE_USAGE_STATE / CLAUDE_USAGE_ACTIONS / CLAUDE_USAGE_FIRED
set -u

EVENT="${1:-UserPromptSubmit}"
DIR="$HOME/.claude"
STATE="${CLAUDE_USAGE_STATE:-$DIR/usage-state.json}"
ACTIONS="${CLAUDE_USAGE_ACTIONS:-$DIR/usage-actions.json}"
FIRED="${CLAUDE_USAGE_FIRED:-$DIR/usage-fired.json}"
TOKEN="@@AUTORESUME@@"

cat >/dev/null 2>&1 || true   # drain stdin so we never block on the pipe

[ -f "$STATE" ]   || exit 0
[ -f "$ACTIONS" ] || exit 0
# Self-heal a missing/empty/corrupt dedup file so it can't cause re-fire storms.
jq -e . "$FIRED" >/dev/null 2>&1 || echo '{}' > "$FIRED"

now="$(date +%s)"
BANDS_JSON="$(jq -c '.bands' "$ACTIONS" 2>/dev/null)"
[ -n "$BANDS_JSON" ] && [ "$BANDS_JSON" != "null" ] || exit 0

band_for()   { jq -n --argjson pct "$1" --argjson b "$BANDS_JSON" '[ $b[] | select(. <= $pct) ] | (max // 0)'; }
prev_band()  { jq -r --arg w "$1" --argjson r "$2" '(.[$w] // {}) | if (.reset == $r) then (.band // 0) else 0 end' "$FIRED"; }
# Directive for a crossed band = the one defined at the HIGHEST directive-band <= it.
# So the stop threshold is set purely by which band you put the directive on in
# usage-actions.json - no need to edit this script. Also covers a window that
# jumps straight past the critical band in a single poll (it still inherits the directive).
dir_for()    { jq -r --arg b "$1" --arg k "$2" '(.[$k] // {}) as $d | ([ $d | keys[] | tonumber | select(. <= ($b|tonumber)) ] | max) as $m | if $m == null then "" else ($d[($m|tostring)] // "") end' "$ACTIONS"; }
sess_dir()   { dir_for "$1" session_directives; }
week_dir()   { dir_for "$1" weekly_directives; }

fmt_rel() {
  local e="${1:-}"; case "$e" in ""|"null"|"0") echo "unknown"; return;; esac
  local d=$(( e - now )); [ "$d" -le 0 ] && { echo "now"; return; }
  local days=$(( d/86400 )) h=$(( (d%86400)/3600 )) m=$(( (d%3600)/60 ))
  if [ "$days" -gt 0 ]; then printf '%dd %dh' "$days" "$h"; else printf '%dh %02dm' "$h" "$m"; fi
}
fmt_abs() {
  local e="${1:-}"; case "$e" in ""|"null"|"0") echo "unknown"; return;; esac
  python3 -c 'import time,sys; print(time.strftime("%a %Y-%m-%d %H:%M %Z", time.localtime(int(sys.argv[1]))))' "$e" 2>/dev/null || echo "unknown"
}
compute_resume() {        # reset-epoch  label
  local reset="$1" label="$2"
  if [ "$reset" != "0" ] && [ -n "$reset" ]; then
    local re=$(( reset + 60 )) secs ra
    secs=$(( re - now )); [ "$secs" -lt 1 ] && secs=1
    ra="$(fmt_abs "$re")"
    printf 'RESUME TARGET (%s): %s (window reopen + 1 min), in %ss. Arm it NOW: start ONE background command `sleep %s` (Bash tool, run_in_background:true). It re-invokes you when it exits - then resume the paused work from the handoff note. Do NOT foreground-sleep and do NOT use CronCreate. Keep this session open (and the machine awake) until it fires.' \
      "$label" "$ra" "$secs" "$secs"
    return
  fi
  printf 'RESUME TARGET (%s): reset time unknown, cannot auto-schedule - pause only and resume manually after the window reopens.' "$label"
}

# Read persisted state (numeric; -1/0 defaults keep positions non-empty).
mapfile -t ST < <(jq -r '
  (.five_hour_pct // -1),
  (.five_hour_reset // 0),
  (.seven_day_pct // -1),
  (.seven_day_reset // 0)' "$STATE" 2>/dev/null)
S_PCT="${ST[0]:--1}"; S_RESET="${ST[1]:-0}"; W_PCT="${ST[2]:--1}"; W_RESET="${ST[3]:-0}"

msgs=""
RESUMES=""

check_window() {          # label pct reset fired-key kind
  local label="$1" pct="$2" reset="$3" key="$4" kind="$5"
  case "$pct" in ""|"-1"|"null") return;; esac
  local cur prev; cur="$(band_for "$pct")"; prev="$(prev_band "$key" "$reset")"
  if [ "${cur:-0}" -gt "${prev:-0}" ]; then
    local dir=""
    if [ "$kind" = "session" ]; then dir="$(sess_dir "$cur")"; else dir="$(week_dir "$cur")"; fi
    msgs+="- ${label} crossed ${cur}% (now ${pct}%; window resets in $(fmt_rel "$reset") at $(fmt_abs "$reset"))."$'\n'
    if [ -n "$dir" ]; then
      case "$dir" in
        *"$TOKEN"*)
          dir="${dir//$TOKEN/}"
          RESUMES+="$(compute_resume "$reset" "$label")"$'\n'
          ;;
      esac
      msgs+="  ACTION: ${dir}"$'\n'
    fi
  fi
  local keep="${cur:-0}"; [ "${prev:-0}" -gt "$keep" ] && keep="$prev"
  local upd; upd="$(jq --arg w "$key" --argjson r "$reset" --argjson b "$keep" '.[$w] = {reset:$r, band:$b}' "$FIRED")"
  printf '%s' "$upd" > "$FIRED"
}

check_window "Session (5h)" "$S_PCT" "$S_RESET" "five_hour" "session"
check_window "Weekly (7d)"  "$W_PCT" "$W_RESET" "seven_day" "weekly"

[ -n "$msgs" ] || exit 0

SUMMARY="Reset times -> Session (5h): $(fmt_abs "$S_RESET") (in $(fmt_rel "$S_RESET")); Weekly (7d): $(fmt_abs "$W_RESET") (in $(fmt_rel "$W_RESET"))."

CONTEXT="USAGE THRESHOLD ALERT (auto-injected from /usage rate limits):
${msgs}${SUMMARY}"
[ -n "$RESUMES" ] && CONTEXT="${CONTEXT}
${RESUMES}"

jq -n --arg e "$EVENT" --arg c "$CONTEXT" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
exit 0
