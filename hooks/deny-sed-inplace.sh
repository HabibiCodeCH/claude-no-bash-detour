#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): deny in-place `sed -i` / `gsed -i` / `--in-place`
# edits, and tell Claude to use the Edit tool instead.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')

[ -z "$cmd" ] && exit 0

sed_token='(^|[[:space:]])(sed|gsed)([[:space:]]|$)'
inplace_flag="(^|[[:space:]])-i([[:space:].\"'\`]|\$)|--in-place"

matched=0
while IFS= read -r segment; do
  if echo "$segment" | grep -Eiq "$sed_token" && echo "$segment" | grep -Eq "$inplace_flag"; then
    matched=1
    break
  fi
done <<< "$(printf '%s' "$cmd" | tr ';&|' '\n\n\n')"

if [ "$matched" -eq 1 ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "sed -i / --in-place edits are blocked. Use the Edit tool to modify files instead."
    }
  }'
fi

exit 0
