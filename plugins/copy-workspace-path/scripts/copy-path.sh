#!/usr/bin/env bash
# Copy the right-clicked sidebar item's working directory to the system clipboard.
#
#   copy-path.sh <kind>     kind = workspace | tab | pane
#
# Invoked by the three "Copy path" actions. herdr injects the clicked item's id
# as HERDR_WORKSPACE_ID / HERDR_TAB_ID / HERDR_PANE_ID (whichever applies), plus
# HERDR_PLUGIN_CONTEXT_JSON and HERDR_BIN_PATH.
#
# A workspace/tab has no cwd of its own — its path is the cwd of its active pane;
# a pane's path is its own cwd. We resolve everything from the clicked item's id
# against `pane list` (authoritative), falling back to the context JSON or the
# focused pane only when an id is missing. Clipboard write is portable (clip.exe
# on WSL, pbcopy on macOS, wl-copy/xclip on Linux).
set -uo pipefail

kind="${1:-workspace}"
herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

note() { # title, body (best-effort; only visible if ui.toast.delivery="herdr")
  "$herdr_bin" notification show "$1" --body "$2" --position top-right >/dev/null 2>&1 || true
}

fail() {
  printf 'copy-workspace-path: %s\n' "$1" >&2
  note "Copy path failed" "$1"
  exit 1
}

# Try one of the available system clipboard tools, in order of reliability for
# the host. printf '%s' avoids a trailing newline.
copy_to_clipboard() {
  local text="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy && return 0
  fi
  # On WSL, clip.exe sets the Windows clipboard immediately and exits (no
  # daemon to outlive this short-lived action), so prefer it there.
  if grep -qi microsoft /proc/version 2>/dev/null && command -v clip.exe >/dev/null 2>&1; then
    printf '%s' "$text" | clip.exe && return 0
  fi
  if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy && return 0
  fi
  if [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard && return 0
  fi
  if [ -n "${DISPLAY:-}" ] && command -v xsel >/dev/null 2>&1; then
    printf '%s' "$text" | xsel --clipboard --input && return 0
  fi
  if command -v clip.exe >/dev/null 2>&1; then
    printf '%s' "$text" | clip.exe && return 0
  fi
  return 1
}

panes="$("$herdr_bin" pane list 2>/dev/null || true)"

ctx_field() { # $1 = jq path expr (e.g. .workspace_id)
  [ -n "$ctx" ] || return 0
  printf '%s' "$ctx" | jq -r "($1) // empty" 2>/dev/null || true
}
focused_field() { # $1 = field on the focused PaneInfo (e.g. .workspace_id)
  printf '%s' "$panes" | jq -r "(first(.result.panes[] | select(.focused == true) | $1)) // empty" 2>/dev/null || true
}

# --- resolve the clicked item's id and its path ------------------------------
case "$kind" in
  workspace)
    id="${HERDR_WORKSPACE_ID:-}"
    [ -n "$id" ] || id="$(ctx_field .workspace_id)"
    [ -n "$id" ] || id="$(focused_field .workspace_id)"
    [ -n "$id" ] || fail "could not determine which workspace was clicked"
    active_tab="$("$herdr_bin" workspace get "$id" 2>/dev/null \
      | jq -r '.result.workspace.active_tab_id // empty' 2>/dev/null || true)"
    path="$(printf '%s' "$panes" | jq -r --arg w "$id" --arg t "$active_tab" '
      [.result.panes[] | select(.workspace_id == $w)] as $wp
      | ( first($wp[] | select(.tab_id == $t and .focused == true))
          // first($wp[] | select(.tab_id == $t))
          // first($wp[]) )
      | (.foreground_cwd // .cwd) // empty
    ' 2>/dev/null || true)"
    label="Workspace path copied"
    ;;
  tab)
    id="${HERDR_TAB_ID:-}"
    [ -n "$id" ] || id="$(ctx_field .tab_id)"
    [ -n "$id" ] || id="$(focused_field .tab_id)"
    [ -n "$id" ] || fail "could not determine which tab was clicked"
    path="$(printf '%s' "$panes" | jq -r --arg t "$id" '
      [.result.panes[] | select(.tab_id == $t)] as $tp
      | ( first($tp[] | select(.focused == true)) // first($tp[]) )
      | (.foreground_cwd // .cwd) // empty
    ' 2>/dev/null || true)"
    label="Tab path copied"
    ;;
  pane)
    id="${HERDR_PANE_ID:-}"
    [ -n "$id" ] || id="$(ctx_field .focused_pane_id)"
    [ -n "$id" ] || id="$(focused_field .pane_id)"
    [ -n "$id" ] || fail "could not determine which pane was clicked"
    path="$(printf '%s' "$panes" | jq -r --arg p "$id" '
      first(.result.panes[] | select(.pane_id == $p)) | (.foreground_cwd // .cwd) // empty
    ' 2>/dev/null || true)"
    label="Pane path copied"
    ;;
  *)
    fail "unknown kind $kind (expected workspace|tab|pane)"
    ;;
esac

[ -n "$path" ] || fail "could not resolve a path for $kind $id"

# --- copy -------------------------------------------------------------------
if copy_to_clipboard "$path"; then
  note "$label" "$path"
else
  fail "no clipboard tool available (tried pbcopy, clip.exe, wl-copy, xclip, xsel)"
fi
