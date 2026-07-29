#!/usr/bin/env bash
# Plugin pane commands start in the plugin directory, so restore the caller's cwd.
set -euo pipefail

agent="${1:-}"
case "$agent" in
codex)
	command=(codex --dangerously-bypass-approvals-and-sandbox)
	;;
claude)
	command=(claude --dangerously-skip-permissions)
	;;
pi)
	command=(pi)
	;;
*)
	printf 'unsupported agent: %s\n' "$agent" >&2
	exit 64
	;;
esac

cwd="${HERDR_AGENT_LAUNCHER_CWD:-}"
if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
	printf 'invalid agent launch directory: %s\n' "$cwd" >&2
	exit 1
fi

cd "$cwd"
exec "${command[@]}"
