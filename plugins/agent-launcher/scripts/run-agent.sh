#!/usr/bin/env bash
# Plugin pane commands start in the plugin directory, so restore the caller's cwd.
set -euo pipefail

agent="${1:-}"
case "$agent" in
codex | claude | pi) ;;
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
exec "$agent"
