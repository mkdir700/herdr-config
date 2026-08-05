#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
ln -s "$repo_root/tests/fixtures/fake-lazygit.sh" "$fake_bin/lazygit"

run_lazygit() {
	local return_tab="$1"
	local command_log="$2"

	TEST_COMMAND_LOG="$command_log" \
		HERDR_BIN_PATH="$repo_root/tests/fixtures/fake-herdr-return.sh" \
		HERDR_LAZYGIT_RETURN_TAB="$return_tab" \
		PATH="$fake_bin:$PATH" \
		bash "$repo_root/plugins/lazygit/scripts/lazygit.sh"
}

valid_log="$tmp_dir/valid.log"
run_lazygit "w1:t1" "$valid_log"
grep -Fxq 'tab focus w1:t1' "$valid_log" || {
	printf 'FAIL: quitting lazygit did not restore the invoking tab:\n' >&2
	cat "$valid_log" >&2
	exit 1
}

invalid_log="$tmp_dir/invalid.log"
run_lazygit '-unsafe-id' "$invalid_log"
if grep -q '^tab focus ' "$invalid_log"; then
	printf 'FAIL: invalid return tab reached herdr:\n' >&2
	cat "$invalid_log" >&2
	exit 1
fi

printf 'PASS: lazygit restores its invoking tab when it exits\n'
