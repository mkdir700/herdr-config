#!/usr/bin/env bash
# Link every local (in-repo) Herdr plugin in one shot.
#
# Herdr's link registry (plugins.json) is machine-specific and gitignored, so a
# fresh `git clone` — or any reset of that registry — leaves the local plugins
# unlinked even though their source is in the repo. Symptom: a keybinding fires
# `herdr plugin action invoke ...` and gets `plugin_not_found`, so nothing
# happens. Run this once after cloning instead of linking each plugin by hand.
#
# It links every plugins/<name>/ that has a herdr-plugin.toml. The gitignored
# plugins/github/ (marketplace downloads) and plugins/config/ (runtime copies)
# are skipped automatically: they hold no *top-level* plugins/*/herdr-plugin.toml.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

herdr="${HERDR_BIN_PATH:-herdr}"
command -v "$herdr" >/dev/null 2>&1 || { echo "herdr not found on PATH" >&2; exit 1; }

shopt -s nullglob
linked=0
for manifest in plugins/*/herdr-plugin.toml; do
  dir="$(dirname "$manifest")"
  printf '→ linking %s\n' "$dir"
  "$herdr" plugin link "$dir" >/dev/null
  linked=$((linked + 1))
done

if [ "$linked" -eq 0 ]; then
  echo "No local plugins found under plugins/*/herdr-plugin.toml" >&2
  exit 1
fi

echo
echo "Linked $linked local plugin(s). Currently linked:"
"$herdr" plugin list 2>/dev/null | grep -i "local:" || true
