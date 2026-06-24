#!/usr/bin/env bash
# Idempotent launcher for tuicr-diff, invoked by the four actions:
#
#   launch.sh <spec> <placement>
#     spec       working | branch    (which diff; encoded in the pane title)
#     placement  split | tab         (where the pane goes)
#
# "Launch-or-focus, toggle on repeat", scoped per comparison type (the pane title
# encodes the spec, so `working` and `branch` toggle independently and coexist):
#
#   split  no matching pane in the current tab     -> open a split (focused)
#          matching pane exists but isn't focused   -> focus it
#          matching pane IS the focused pane        -> close it (toggle off)
#   tab    matching pane in the current tab         -> focus / close as above
#          else matching pane in another tab        -> switch to that tab
#          else                                     -> open in a new tab
#
# herdr runs this from the plugin root. The repo to diff is the focused pane's
# cwd, handed to the new pane via `--env HERDR_DIFF_REPO` (NOT `--cwd`: the pane
# command is a path relative to the plugin root). Pane/tab ids pulled from the
# host JSON are validated flag-safe before reaching an argv (option-injection
# guard), mirroring the herdr-file-viewer launcher.
set -uo pipefail

spec="${1:?spec required (working|branch)}"
placement="${2:?placement required (split|tab)}"
herdr_bin="${HERDR_BIN_PATH:-herdr}"

case "$spec" in
  working) entrypoint="diff-working"; title="Diff: working" ;;
  branch)  entrypoint="diff-branch";  title="Diff: branch"  ;;
  *) printf 'tuicr-diff: unknown spec %q\n' "$spec" >&2; exit 2 ;;
esac

# Safe to place in an argv iff non-empty, not starting with '-', and only
# [A-Za-z0-9_:.-] (herdr ids look like wE:pD).
is_flag_safe() {
  case "$1" in
    "" | -*) return 1 ;;
    *[!A-Za-z0-9_:.-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# --- gather state -----------------------------------------------------------
cur="$("$herdr_bin" pane current 2>/dev/null || true)"
focused_pane="$(printf '%s' "$cur" | jq -r '.result.pane.pane_id // empty' 2>/dev/null || true)"
focused_tab="$(printf '%s' "$cur" | jq -r '.result.pane.tab_id // empty' 2>/dev/null || true)"
repo="$(printf '%s' "$cur" | jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' 2>/dev/null || true)"

panes="$("$herdr_bin" pane list 2>/dev/null || true)"

# pane_id of a matching diff pane in the focused tab, if any.
here_id=""
if [ -n "$focused_tab" ] && [ -n "$panes" ]; then
  here_id="$(printf '%s' "$panes" \
    | jq -r --arg t "$title" --arg tab "$focused_tab" \
      'first(.result.panes[] | select(.label == $t and .tab_id == $tab) | .pane_id) // empty' \
    2>/dev/null || true)"
fi

# --- open helpers -----------------------------------------------------------
open_pane() {
  local -a cmd=(
    "$herdr_bin" plugin pane open
    --plugin tuicr-diff
    --entrypoint "$entrypoint"
    --placement "$placement"
    --focus
    --env "HERDR_DIFF_REPO=$repo"
  )
  [ "$placement" = "split" ] && cmd+=(--direction right)
  # Forward an explicit base override into the fresh pane env, if set.
  [ -n "${HERDR_DIFF_BASE:-}" ] && cmd+=(--env "HERDR_DIFF_BASE=$HERDR_DIFF_BASE")
  exec "${cmd[@]}"
}

focus_pane() { # $1 = pane id (validated)
  "$herdr_bin" pane zoom "$1" --on >/dev/null 2>&1 || true
  exec "$herdr_bin" pane zoom "$1" --off
}

# --- decide -----------------------------------------------------------------
# A matching pane in the current tab: toggle off if it's focused, else focus it.
if [ -n "$here_id" ] && is_flag_safe "$here_id"; then
  if [ "$here_id" = "$focused_pane" ]; then
    exec "$herdr_bin" pane close "$here_id"
  fi
  focus_pane "$here_id"
fi

# Tab variant only: a matching pane living in another tab -> switch to it.
if [ "$placement" = "tab" ] && [ -n "$panes" ]; then
  other_tab="$(printf '%s' "$panes" \
    | jq -r --arg t "$title" \
      'first(.result.panes[] | select(.label == $t) | .tab_id) // empty' \
    2>/dev/null || true)"
  if [ -n "$other_tab" ] && is_flag_safe "$other_tab"; then
    exec "$herdr_bin" tab focus "$other_tab"
  fi
fi

# Nothing matching -> open fresh.
open_pane
