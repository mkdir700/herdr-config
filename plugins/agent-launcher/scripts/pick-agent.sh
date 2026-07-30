#!/usr/bin/env bash
# Choose an agent, then open its tab from the directory captured before the overlay.
set -euo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
cwd="${HERDR_AGENT_LAUNCHER_CWD:-}"

if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
	printf 'invalid agent launch directory: %s\n' "$cwd" >&2
	exit 1
fi

if ! agent="$(printf '%s\n' codex claude pi | fzf --prompt='Start agent > ' --height=8 --layout=reverse --border=rounded)"; then
	exit 0
fi

case "$agent" in
codex | claude | pi) ;;
*) exit 0 ;;
esac

exec "$herdr_bin" plugin pane open \
	--plugin agent-launcher \
	--entrypoint "agent-$agent" \
	--placement tab \
	--focus \
	--env "HERDR_AGENT_LAUNCHER_CWD=$cwd"
