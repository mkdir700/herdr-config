#!/usr/bin/env bash
# Pane wrapper for the lazygit plugin. herdr runs this from the plugin root, so
# the repo to open is handed in via $HERDR_LAZYGIT_REPO (the focused pane's cwd
# at launch time) rather than the pane cwd. When the tab instance exits, restore
# the tab that launched it before herdr removes this transient tab.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
repo="${HERDR_LAZYGIT_REPO:-$PWD}"
return_tab="${HERDR_LAZYGIT_RETURN_TAB:-}"

is_flag_safe() {
	case "$1" in
	"" | -*) return 1 ;;
	*[!A-Za-z0-9_:.-]*) return 1 ;;
	*) return 0 ;;
	esac
}

restore_invoking_tab() {
	local status=$?
	if is_flag_safe "$return_tab"; then
		"$herdr_bin" tab focus "$return_tab" >/dev/null 2>&1 || true
	fi
	exit "$status"
}

trap restore_invoking_tab EXIT

cd "$repo" 2>/dev/null || true
lazygit
