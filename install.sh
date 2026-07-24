#!/usr/bin/env bash
# Installs every hook in hooks/ as a PreToolUse Bash hook in Claude Code settings.
#
# Usage:
#   ./install.sh              installs all hooks into ~/.claude/settings.json (all projects)
#   ./install.sh --project    installs all hooks into ./.claude/settings.json (this repo only)
#   ./install.sh <name>...    installs only the named hook(s), e.g. ./install.sh deny-sed-inplace
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (https://jqlang.org/download/)" >&2
  exit 1
fi

CONFIG_DIR="$HOME/.claude"
names=()
for arg in "$@"; do
  if [ "$arg" = "--project" ]; then
    CONFIG_DIR="./.claude"
  else
    names+=("$arg")
  fi
done

HOOKS_DIR="$CONFIG_DIR/hooks"
SETTINGS_FILE="$CONFIG_DIR/settings.json"

if [ "${#names[@]}" -eq 0 ]; then
  for f in "$SCRIPT_DIR"/hooks/*.sh; do
    names+=("$(basename "$f" .sh)")
  done
fi

mkdir -p "$HOOKS_DIR"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

backed_up=0

for name in "${names[@]}"; do
  SRC="$SCRIPT_DIR/hooks/$name.sh"
  if [ ! -f "$SRC" ]; then
    echo "error: no such hook '$name' (looked for $SRC)" >&2
    exit 1
  fi

  HOOK_DEST="$HOOKS_DIR/$name.sh"
  cp "$SRC" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"

  if jq -e --arg cmd "$HOOK_DEST" \
    '(.hooks.PreToolUse // [])[] | select(.matcher == "Bash") | .hooks[]? | select(.command == $cmd)' \
    "$SETTINGS_FILE" >/dev/null 2>&1; then
    echo "Hook '$name' already present in $SETTINGS_FILE — skipping."
    continue
  fi

  if [ "$backed_up" -eq 0 ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak-$(date +%s)"
    backed_up=1
  fi

  jq --arg cmd "$HOOK_DEST" '
    .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{
      matcher: "Bash",
      hooks: [{ type: "command", command: $cmd }]
    }])
  ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
  mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

  echo "Installed '$name' -> $HOOK_DEST"
done

echo "Settings file: $SETTINGS_FILE"
echo "Restart Claude Code, or open /hooks once, to pick up any change."
