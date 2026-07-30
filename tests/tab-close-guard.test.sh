#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bin_dir="$tmp_dir/bin"
mkdir -p "$bin_dir"

cat >"$bin_dir/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${TEST_COMMAND_LOG:?}"
scenario="${TEST_SCENARIO:?}"

case "$*" in
  "workspace list")
    printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"Demo","active_tab_id":"w1:t1","focused":true}]}}'
    ;;
  "tab list --workspace w1")
    case "$scenario" in
      multi) printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","label":"One"},{"tab_id":"w1:t2","label":"Two"}]}}' ;;
      single) printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","label":"One"}]}}' ;;
      *) printf 'unknown scenario: %s\n' "$scenario" >&2; exit 64 ;;
    esac
    ;;
  "pane list")
    printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","focused":true}]}}'
    ;;
  "tab close "* | "pane close "* | "workspace close "*)
    printf '%s\n' "$*" >>"$log"
    printf '%s\n' '{"result":{}}'
    ;;
  "plugin pane open "*)
    printf '%s\n' "$*" >>"$log"
    ;;
  "notification show "*)
    :
    ;;
  *)
    printf 'unexpected fake herdr command: %s\n' "$*" >&2
    exit 64
    ;;
esac
EOF
chmod +x "$bin_dir/herdr"

run_action() {
	TEST_COMMAND_LOG="$1" TEST_SCENARIO="$2" HERDR_BIN_PATH="$bin_dir/herdr" \
		env -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_PANE_ID -u HERDR_PLUGIN_CONTEXT_JSON \
		node "$repo_root/plugins/tab-close-guard/scripts/close-tab.js"
}

run_pane_action() {
	TEST_COMMAND_LOG="$1" TEST_SCENARIO="$2" HERDR_BIN_PATH="$bin_dir/herdr" \
		env -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_PANE_ID -u HERDR_PLUGIN_CONTEXT_JSON \
		node "$repo_root/plugins/tab-close-guard/scripts/close-pane.js"
}

multi_log="$tmp_dir/multi.log"
run_action "$multi_log" multi
[ "$(<"$multi_log")" = "tab close w1:t1" ] || {
	printf 'FAIL: multiple-tab close did not immediately close the active tab\n' >&2
	exit 1
}

single_log="$tmp_dir/single.log"
run_action "$single_log" single
expected_overlay='plugin pane open --plugin tab-close-guard --entrypoint confirm --placement overlay --focus --env HERDR_TAB_CLOSE_GUARD_WORKSPACE_ID=w1 --env HERDR_TAB_CLOSE_GUARD_KIND=tab --env HERDR_TAB_CLOSE_GUARD_TAB_ID=w1:t1'
[ "$(<"$single_log")" = "$expected_overlay" ] || {
	printf 'FAIL: final-tab close did not open the confirmation overlay\n' >&2
	exit 1
}

cancel_log="$tmp_dir/cancel.log"
cancel_output="$(printf 'n\n' | TEST_COMMAND_LOG="$cancel_log" TEST_SCENARIO=single HERDR_BIN_PATH="$bin_dir/herdr" HERDR_TAB_CLOSE_GUARD_WORKSPACE_ID=w1 HERDR_TAB_CLOSE_GUARD_KIND=tab HERDR_TAB_CLOSE_GUARD_TAB_ID=w1:t1 node "$repo_root/plugins/tab-close-guard/scripts/confirm.js")"
[ ! -e "$cancel_log" ] || {
	printf 'FAIL: cancel still closed the tab\n' >&2
	exit 1
}
printf '%s' "$cancel_output" | grep -Fq 'Cancelled. Tab kept.' || {
	printf 'FAIL: cancel feedback missing\n' >&2
	exit 1
}

confirm_log="$tmp_dir/confirm.log"
printf 'yes\n' | TEST_COMMAND_LOG="$confirm_log" TEST_SCENARIO=single HERDR_BIN_PATH="$bin_dir/herdr" HERDR_TAB_CLOSE_GUARD_WORKSPACE_ID=w1 HERDR_TAB_CLOSE_GUARD_KIND=tab HERDR_TAB_CLOSE_GUARD_TAB_ID=w1:t1 node "$repo_root/plugins/tab-close-guard/scripts/confirm.js" >/dev/null
[ "$(<"$confirm_log")" = "workspace close w1" ] || {
	printf 'FAIL: confirmed final-tab close did not close its workspace\n' >&2
	exit 1
}

pane_multi_log="$tmp_dir/pane-multi.log"
run_pane_action "$pane_multi_log" multi
[ "$(<"$pane_multi_log")" = "pane close w1:p1" ] || {
	printf 'FAIL: non-final pane did not close immediately\n' >&2
	exit 1
}

pane_single_log="$tmp_dir/pane-single.log"
run_pane_action "$pane_single_log" single
expected_pane_overlay='plugin pane open --plugin tab-close-guard --entrypoint confirm --placement overlay --focus --env HERDR_TAB_CLOSE_GUARD_WORKSPACE_ID=w1 --env HERDR_TAB_CLOSE_GUARD_KIND=pane --env HERDR_TAB_CLOSE_GUARD_TAB_ID=w1:t1 --env HERDR_TAB_CLOSE_GUARD_PANE_ID=w1:p1'
[ "$(<"$pane_single_log")" = "$expected_pane_overlay" ] || {
	printf 'FAIL: final pane did not open the confirmation overlay\n' >&2
	exit 1
}

printf 'PASS: final tabs and panes require confirmation; other targets close immediately\n'
