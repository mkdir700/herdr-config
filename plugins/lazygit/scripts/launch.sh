#!/usr/bin/env bash
# Idempotent launcher for the lazygit plugin, invoked by the "toggle" action.
#
# Single instance in its own tab — "open-or-focus, toggle off when already on it":
#
#   no lazygit pane anywhere        -> open it in a new tab (focused)
#   lazygit pane in another tab     -> switch to that tab
#   lazygit pane IS the focused pane -> close it (toggle off)
#
# herdr runs this from the plugin root. The repo to open is the focused pane's
# cwd, handed to the new pane via `--env HERDR_LAZYGIT_REPO` (NOT `--cwd`: the
# pane command is a path relative to the plugin root). Pane/tab ids pulled from
# the host JSON are validated flag-safe before reaching an argv (option-injection
# guard), mirroring the tuicr-diff launcher.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
entrypoint="lazygit"
title="lazygit"

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

# pane_id of the lazygit pane in the focused tab, if any.
here_id=""
if [ -n "$focused_tab" ] && [ -n "$panes" ]; then
  here_id="$(printf '%s' "$panes" \
    | jq -r --arg t "$title" --arg tab "$focused_tab" \
      'first(.result.panes[] | select(.label == $t and .tab_id == $tab) | .pane_id) // empty' \
    2>/dev/null || true)"
fi

# --- open helper ------------------------------------------------------------
open_pane() {
  exec "$herdr_bin" plugin pane open \
    --plugin lazygit \
    --entrypoint "$entrypoint" \
    --placement tab \
    --focus \
    --env "HERDR_LAZYGIT_REPO=$repo"
}

focus_pane() { # $1 = pane id (validated)
  "$herdr_bin" pane zoom "$1" --on >/dev/null 2>&1 || true
  exec "$herdr_bin" pane zoom "$1" --off
}

# --- decide -----------------------------------------------------------------
# The lazygit pane is in the current tab: toggle off if focused, else focus it.
if [ -n "$here_id" ] && is_flag_safe "$here_id"; then
  if [ "$here_id" = "$focused_pane" ]; then
    exec "$herdr_bin" pane close "$here_id"
  fi
  focus_pane "$here_id"
fi

# A lazygit pane living in another tab -> switch to it.
if [ -n "$panes" ]; then
  other_tab="$(printf '%s' "$panes" \
    | jq -r --arg t "$title" \
      'first(.result.panes[] | select(.label == $t) | .tab_id) // empty' \
    2>/dev/null || true)"
  if [ -n "$other_tab" ] && is_flag_safe "$other_tab"; then
    exec "$herdr_bin" tab focus "$other_tab"
  fi
fi

# Nothing matching -> open fresh in a new tab.
open_pane
