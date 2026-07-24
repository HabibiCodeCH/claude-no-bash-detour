#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): deny `find -exec` and `find | grep` style chains,
# and tell Claude to use the Grep/Glob tools instead.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')

[ -z "$cmd" ] && exit 0

bound_l='(^|[[:space:];&|()])'
bound_r='([[:space:];&|()]|$)'
exec_pattern="${bound_l}find${bound_r}[^|;&]*${bound_l}-exec(dir)?${bound_r}"
piped_grep_pattern="${bound_l}find${bound_r}[^|;&]*\\|[[:space:]]*(xargs[[:space:]]+)?grep${bound_r}"

if echo "$cmd" | grep -Eiq "$exec_pattern" || echo "$cmd" | grep -Eiq "$piped_grep_pattern"; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "find -exec and find|grep chains are blocked. Use the Grep tool for content search or the Glob tool for filename search instead."
    }
  }'
fi

exit 0
