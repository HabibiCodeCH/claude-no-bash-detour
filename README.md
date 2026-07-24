# claude-no-bash-detour

A set of Claude Code `PreToolUse` hooks that deny specific Bash command
patterns which duplicate a built-in Claude Code tool, and tell Claude to use
that tool instead. Each hook is a standalone script; install one, some, or
all of them.

## Why

Telling Claude in a `CLAUDE.md` file "don't use `find -exec`, use Grep/Glob"
doesn't reliably stick — instructions are a suggestion, not an enforcement
mechanism, and a model will still reach for a familiar shell one-liner under
the right prompt. It also means every Bash call built out of one of these
patterns shows up as a permission prompt for the user to approve, when the
native tool call wouldn't have needed approval at all.

A `PreToolUse` hook enforces it at the harness level instead: the hook runs
before the Bash tool call reaches you, denies it if it matches, and hands
Claude a reason it can act on — so it retries with the right tool rather than
just getting stuck. Configured once in `settings.json`, it applies to every
session and every subagent, so you're not approving (or fixing) the same
pattern repeatedly across parallel agents.

## Hooks included

### `deny-find-chains.sh` — use Grep/Glob

Blocks:
- `find . -name '*.log' -exec rm {} \;`
- `find . -name '*.ts' | grep -v node_modules`
- `find . -type f | xargs grep -l TODO`

Doesn't touch: plain `find` with no `-exec`/piped `grep`, plain `grep`, or
"find"/"grep" appearing as substrings of another word or inside quoted
arguments (e.g. `grep -rn "findUser" src`, a path like `my-find-exec-project/`).

### `deny-sed-inplace.sh` — use Edit

Blocks:
- `sed -i 's/foo/bar/' file.txt`
- `sed -i.bak 's/foo/bar/' file.txt`
- `sed -i '' 's/foo/bar/' file.txt` (BSD/macOS)
- `gsed -i ...` / `sed --in-place ...`

Doesn't touch: `sed` without `-i` (printing to stdout), or `sed` used to
transform piped text (`git diff | sed 's/^/  /'`).

### `deny-cat-head-tail.sh` — use Read

Blocks:
- `cat notes.txt`
- `head -n 20 notes.txt`
- `tail -c 100 notes.txt`
- `sudo cat /etc/hosts`

Doesn't touch: `tail -f`/`--follow` (streaming), `cat file1 file2`
(concatenating multiple files — Read handles one file at a time), anything
piped elsewhere (`cat notes.txt | grep TODO`, `head -n 5 file | wc -l`), and
anything redirected to a new file (`cat notes.txt > copy.txt`).

## Limitations

These are text-pattern heuristics on the raw Bash command string, not a
shell parser — deliberately simple. They won't catch every possible
obfuscation (e.g. combined short-option clusters like `sed -ni` where `-i`
isn't the first letter after the dash, or a quoted file path containing a
space in `deny-cat-head-tail.sh`'s naive whitespace tokenizer), and
`deny-find-chains.sh`/`deny-sed-inplace.sh` can't distinguish a real
invocation from a command that merely *mentions* the pattern in a comment or
string — both get denied. If you need airtight enforcement, that's a
different, heavier tool.

## Install

```bash
git clone https://github.com/<you>/claude-no-bash-detour.git
cd claude-no-bash-detour
./install.sh                       # installs all hooks into ~/.claude/settings.json
./install.sh --project             # installs all hooks into ./.claude/settings.json (this repo only)
./install.sh deny-sed-inplace      # installs only the named hook(s)
```

Requires [`jq`](https://jqlang.org/). The installer copies each hook script
into `<config-dir>/hooks/` and adds a `Bash`-matched `PreToolUse` entry per
hook to `settings.json`, without touching any of your existing hooks or
permissions. It's idempotent — running it again only installs what's
missing. A timestamped backup of your prior `settings.json` is written
before the first change.

After installing, restart Claude Code (or open `/hooks` once) to pick up the
change.

## Uninstall

For each hook you want removed: delete the `PreToolUse` entry whose
`matcher` is `"Bash"` and whose command points at that hook's script from
`settings.json`, and delete the script from `~/.claude/hooks/`.

## How it works

Each hook script reads the hook's stdin JSON, pulls out
`tool_input.command`, and checks it against the patterns described above. On
a match it prints a `hookSpecificOutput` JSON blob with
`permissionDecision: "deny"` and a `permissionDecisionReason` pointing Claude
at the right tool; otherwise it exits silently and the command proceeds as
normal.

## License

MIT
