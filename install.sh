#!/usr/bin/env bash
# Installer: copies the tracker scripts into ~/.claude and prints the settings to merge.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
mkdir -p "$DEST"

install -m 0755 "$SRC/statusline-usage.sh"     "$DEST/statusline-usage.sh"
install -m 0755 "$SRC/usage-threshold-hook.sh" "$DEST/usage-threshold-hook.sh"

if [ -f "$DEST/usage-actions.json" ]; then
  echo "note: $DEST/usage-actions.json already exists - leaving your version in place."
else
  install -m 0644 "$SRC/usage-actions.json" "$DEST/usage-actions.json"
fi

cat <<'EOF'

Scripts installed to ~/.claude.

Next:
  1. Merge the "statusLine" and "hooks" blocks from settings.example.json into
     ~/.claude/settings.json (add them alongside your existing settings; do not
     overwrite the file).
  2. Restart Claude Code, or open /hooks once so it reloads the config.

Requirements: bash, jq, python3, and a Claude.ai Pro/Max subscription
(rate-limit numbers only appear in the statusline for subscription auth).
EOF
