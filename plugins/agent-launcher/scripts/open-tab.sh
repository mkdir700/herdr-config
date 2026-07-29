#!/usr/bin/env bash
# Open the requested agent in a tab rooted at the focused pane's directory.
set -euo pipefail

agent="${1:-}"
case "$agent" in
codex | claude | pi) ;;
*)
	printf 'unsupported agent: %s\n' "$agent" >&2
	exit 64
	;;
esac

herdr_bin="${HERDR_BIN_PATH:-herdr}"
cwd="${HERDR_ACTIVE_PANE_CWD:-}"

# Plugin actions normally receive HERDR_ACTIVE_PANE_CWD. Query the live pane as
# a fallback for direct `herdr plugin action invoke` calls.
if [ -z "$cwd" ]; then
	current="$($herdr_bin pane current 2>/dev/null || true)"
	cwd="$(printf '%s' "$current" | jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' 2>/dev/null || true)"
fi

if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
	printf 'could not determine the focused pane working directory\n' >&2
	exit 1
fi

exec "$herdr_bin" plugin pane open \
	--plugin agent-launcher \
	--entrypoint "agent-$agent" \
	--placement tab \
	--focus \
	--env "HERDR_AGENT_LAUNCHER_CWD=$cwd"
