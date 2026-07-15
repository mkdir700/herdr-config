#!/usr/bin/env bash
set -eu

case "${1:-} ${2:-}" in
  "pane current")
    printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","foreground_cwd":"/repo/current"}}}'
    ;;
  "pane list")
    case "${TEST_SCENARIO:-foreign}" in
      foreign)
        printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"},{"pane_id":"w2:p9","tab_id":"w2:t9","workspace_id":"w2","label":"lazygit"}]}}'
        ;;
      local)
        printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"},{"pane_id":"w1:p9","tab_id":"w1:t9","workspace_id":"w1","label":"lazygit"},{"pane_id":"w2:p9","tab_id":"w2:t9","workspace_id":"w2","label":"lazygit"}]}}'
        ;;
      focused)
        printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","label":"lazygit"}]}}'
        ;;
      *)
        printf 'unknown test scenario: %s\n' "$TEST_SCENARIO" >&2
        exit 64
        ;;
    esac
    ;;
  "plugin pane" | "tab focus" | "pane close" | "pane zoom")
    printf '%s\n' "$*" >>"$TEST_COMMAND_LOG"
    ;;
  *)
    printf 'unexpected fake herdr command: %s\n' "$*" >&2
    exit 64
    ;;
esac
