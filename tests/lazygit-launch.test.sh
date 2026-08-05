#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_scenario() {
	local scenario="$1"
	local command_log="$tmp_dir/$scenario.log"

	TEST_SCENARIO="$scenario" \
		TEST_COMMAND_LOG="$command_log" \
		HERDR_BIN_PATH="$repo_root/tests/fixtures/fake-herdr.sh" \
		bash "$repo_root/plugins/lazygit/scripts/launch.sh"
}

run_scenario foreign
if grep -q '^tab focus ' "$tmp_dir/foreign.log"; then
	printf 'FAIL: lazygit toggle switched to another workspace:\n' >&2
	cat "$tmp_dir/foreign.log" >&2
	exit 1
fi

grep -q '^plugin pane open ' "$tmp_dir/foreign.log" || {
	printf 'FAIL: lazygit toggle did not open in the current workspace:\n' >&2
	cat "$tmp_dir/foreign.log" >&2
	exit 1
}

grep -Fq -- '--env HERDR_LAZYGIT_RETURN_TAB=w1:t1' "$tmp_dir/foreign.log" || {
	printf 'FAIL: lazygit toggle did not preserve its invoking tab:\n' >&2
	cat "$tmp_dir/foreign.log" >&2
	exit 1
}

run_scenario local
grep -q '^tab focus w1:t9$' "$tmp_dir/local.log" || {
	printf 'FAIL: lazygit toggle did not focus its existing local tab:\n' >&2
	cat "$tmp_dir/local.log" >&2
	exit 1
}

run_scenario focused
grep -q '^pane close w1:p1$' "$tmp_dir/focused.log" || {
	printf 'FAIL: lazygit toggle did not close the focused local pane:\n' >&2
	cat "$tmp_dir/focused.log" >&2
	exit 1
}

printf 'PASS: lazygit toggle is scoped to the current workspace\n'
