#!/usr/bin/env bash
# Pane wrapper for tuicr-diff — runs AS the herdr pane process.
#
#   $1                 comparison spec: "working" | "branch"
#   $HERDR_DIFF_REPO   repo dir to diff (passed by launch.sh via `--env`)
#   $HERDR_DIFF_BASE   (optional) override base ref for the "branch" spec
#
# Resolves the diff to review, then execs tuicr (https://tuicr.dev) — a terminal
# code-review TUI with vim keybindings. Reviewing a local diff needs no GitHub
# auth (that's only for `:submit`). Transient viewer: quitting tuicr exits this
# process, so the herdr split/tab disappears with it. No nvim involved.
set -uo pipefail

spec="${1:-working}"
repo="${HERDR_DIFF_REPO:-$PWD}"

# Show a message in the pane for a couple of seconds, then leave (pane closes).
die() { printf 'tuicr-diff: %s\n' "$1" >&2; sleep 2; exit 1; }

command -v tuicr >/dev/null 2>&1 \
  || die "tuicr not found on PATH — install it from https://tuicr.dev (e.g. curl -fsSL tuicr.dev/install.sh | sh)"

cd "$repo" 2>/dev/null || die "cannot cd into '$repo'"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "'$repo' is not a git repository"

# Base ref for "branch": explicit override wins, else origin/HEAD's default
# branch, else the first of main/master/develop that exists (local or remote).
detect_base() {
  if [ -n "${HERDR_DIFF_BASE:-}" ]; then
    printf '%s' "$HERDR_DIFF_BASE"
    return 0
  fi
  local ref
  ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$ref" ]; then
    printf '%s' "${ref#refs/remotes/}" # e.g. refs/remotes/origin/main -> origin/main
    return 0
  fi
  local b
  for b in main master develop; do
    if git rev-parse --verify --quiet "refs/heads/$b" >/dev/null 2>&1 \
      || git rev-parse --verify --quiet "refs/remotes/origin/$b" >/dev/null 2>&1; then
      printf '%s' "$b"
      return 0
    fi
  done
  return 1
}

case "$spec" in
  branch)
    base="$(detect_base)" || die "no base branch found (set \$HERDR_DIFF_BASE)"
    # Three-dot range: changes introduced on the branch since its fork point
    # from base (merge-base...HEAD) — every commit since the branch diverged.
    exec tuicr -r "${base}...HEAD"
    ;;
  working | *)
    # Uncommitted changes: working tree + index vs HEAD.
    exec tuicr -w
    ;;
esac
