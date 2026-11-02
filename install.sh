#!/usr/bin/env bash
# Installer: copies the status line script into ~/.claude and prints the settings to merge.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
mkdir -p "$DEST"

install -m 0755 "$SRC/statusline-usage.sh" "$DEST/statusline-usage.sh"

cat <<'EOF'

Status line installed to ~/.claude/statusline-usage.sh.

Next:
  1. Merge the "statusLine" block from settings.example.json into
     ~/.claude/settings.json (add it alongside your existing settings; do not
     overwrite the file).
  2. Restart Claude Code.

Requirements: bash 4+, jq, and a Claude.ai Pro/Max subscription
(rate-limit numbers only appear in the statusline for subscription auth).
EOF
