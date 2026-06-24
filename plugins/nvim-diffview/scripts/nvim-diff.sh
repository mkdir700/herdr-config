#!/usr/bin/env bash
# Pane wrapper for nvim-diffview — runs AS the herdr pane process.
#
#   $1                    comparison spec: "working" | "branch"
#   $HERDR_DIFF_REPO      repo dir to diff (passed by launch.sh via `--env`)
#   $HERDR_DIFFVIEW_BASE  (optional) override base ref for the "branch" spec
#
# Resolves the diffview argument, then execs Neovim with the user's full config
# (diffview.nvim is loaded there). Transient viewer: an autocmd quits nvim when
# the diffview view is closed, so the herdr split/tab disappears with it.
set -uo pipefail

spec="${1:-working}"
repo="${HERDR_DIFF_REPO:-$PWD}"

# Show a message in the pane for a couple of seconds, then leave (pane closes).
die() { printf 'nvim-diffview: %s\n' "$1" >&2; sleep 2; exit 1; }

cd "$repo" 2>/dev/null || die "cannot cd into '$repo'"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "'$repo' is not a git repository"

# Base ref for "branch": explicit override wins, else origin/HEAD's default
# branch, else the first of main/master/develop that exists (local or remote).
detect_base() {
  if [ -n "${HERDR_DIFFVIEW_BASE:-}" ]; then
    printf '%s' "$HERDR_DIFFVIEW_BASE"
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
    base="$(detect_base)" || die "no base branch found (set \$HERDR_DIFFVIEW_BASE)"
    diff_cmd="DiffviewOpen ${base}...HEAD"
    ;;
  working | *)
    diff_cmd="DiffviewOpen"
    ;;
esac

# -c commands run in order: register the transient-close autocmd BEFORE opening
# the view. :qa (not :qa!) so any edits made in the diff prompt to save rather
# than being silently dropped.
exec nvim \
  -c "autocmd User DiffviewViewClosed ++once qa" \
  -c "$diff_cmd"
