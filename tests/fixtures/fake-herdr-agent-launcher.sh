#!/usr/bin/env bash
set -eu

case "${1:-} ${2:-}" in
"pane current")
	printf '%s\n' '{"result":{"pane":{"foreground_cwd":"/tmp"}}}'
	;;
"plugin pane")
	printf '%s\n' "$*" >>"$TEST_COMMAND_LOG"
	;;
*)
	printf 'unexpected fake herdr command: %s\n' "$*" >&2
	exit 64
	;;
esac
