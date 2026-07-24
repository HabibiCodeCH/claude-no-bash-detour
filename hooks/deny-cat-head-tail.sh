#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): deny a bare `cat file` / `head file` / `tail file`
# (viewing one whole file, nothing piped/redirected/concatenated), and tell
# Claude to use the Read tool instead.
set -euo pipefail

cmd_json=$(jq -r '.tool_input.command // empty')

[ -z "$cmd_json" ] && exit 0

# Returns 0 (true) if $1 is a clause that ONLY views a single file with cat/head/tail:
# no pipe anywhere in the clause, no second file (concatenation), no -f/--follow (streaming).
is_bare_view() {
  local clause="$1"
  [[ "$clause" == *"|"* ]] && return 1 # piped somewhere else — real processing, not a bare view

  local -a tokens
  read -ra tokens <<< "$clause"
  local n=${#tokens[@]}
  (( n < 2 )) && return 1

  local idx=0
  if [[ "${tokens[0]}" == "sudo" || "${tokens[0]}" == "env" ]]; then
    idx=1
  fi
  (( n - idx < 2 )) && return 1

  local base="${tokens[$idx]##*/}"
  case "$base" in
    cat|head|tail) ;;
    *) return 1 ;;
  esac

  local path="${tokens[$((n-1))]}"
  [[ "$path" == -* ]] && return 1

  local i=$((idx+1))
  while (( i < n-1 )); do
    local tok="${tokens[$i]}"
    case "$tok" in
      -f|-F|--follow|--follow=*)
        return 1 ;; # streaming, not a one-shot view
      -n|-c)
        # only head/tail take a numeric argument here; cat's -n/-c-like flags don't
        if [[ "$base" != "cat" ]]; then
          local next="${tokens[$((i+1))]:-}"
          if [[ "$next" =~ ^[0-9]+$ ]]; then
            i=$((i+2)); continue
          else
            return 1
          fi
        fi
        i=$((i+1)); continue
        ;;
      -*)
        i=$((i+1)); continue ;;
      *)
        return 1 ;; # a non-flag token before the last one (e.g. a 2nd file): not a bare view
    esac
  done
  return 0
}

while IFS= read -r clause; do
  [ -z "$clause" ] && continue
  if is_bare_view "$clause"; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Bare cat/head/tail on a single file is blocked. Use the Read tool instead."
      }
    }'
    exit 0
  fi
done <<< "$(printf '%s' "$cmd_json" | tr ';&' '\n\n')"

exit 0
