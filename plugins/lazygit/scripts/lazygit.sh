#!/usr/bin/env bash
# Pane wrapper for the lazygit plugin. herdr runs this from the plugin root, so
# the repo to open is handed in via $HERDR_LAZYGIT_REPO (the focused pane's cwd
# at launch time) rather than the pane cwd. cd there and hand off to lazygit,
# which walks up to the enclosing git repo on its own. Quitting lazygit exits
# this process, so the transient tab disappears with it.
set -uo pipefail

repo="${HERDR_LAZYGIT_REPO:-$PWD}"
cd "$repo" 2>/dev/null || true

exec lazygit
