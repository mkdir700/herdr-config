# herdr-config

Personal configuration for [Herdr](https://herdr.dev) — a mouse-friendly terminal
multiplexer with first-class support for running AI coding agents in parallel.

This repo tracks the hand-written config and a local plugin. Herdr's runtime
state (sockets, logs, session, plugin runtime copies) is intentionally
`.gitignore`d so the repo stays portable across machines.

## Contents

```
config.toml                         # Herdr settings (UI, worktrees, keybindings)
plugins/superset-bootstrap/         # Local plugin: reuse .superset/config.json for worktrees
  herdr-plugin.toml
  hook.sh
plugins/nvim-diffview/              # Local plugin: review git diffs via Neovim's diffview.nvim
  herdr-plugin.toml
  scripts/launch.sh                 #   idempotent open/focus/close launcher
  scripts/nvim-diff.sh              #   pane wrapper: detect base, run nvim +DiffviewOpen
```

## config.toml

```toml
[ui]
agent_panel_scope = "all"

# Root for git worktree checkouts created from the sidebar/CLI.
# Layout: <directory>/<repo>/<branch-slug>
[worktrees]
directory = "~/.herdr/worktrees"

# Worktree keybindings (prefix defaults to ctrl+b; unset by default in Herdr).
[keys]
new_worktree    = "prefix+shift+g"
open_worktree   = "prefix+shift+o"
remove_worktree = "prefix+alt+d"
```

## Plugin: superset-bootstrap

A local Herdr plugin that bootstraps and tears down git worktrees by **reusing a
repository's existing `.superset/config.json`** — no separate Herdr-specific
config file is needed.

### `.superset/config.json`

Place this at the **main repo root** of any project you want bootstrapped:

```json
{
  "setup": ["git submodule update --init --recursive", "bun install"],
  "teardown": ["docker compose down"]
}
```

- `setup` — commands run **inside the new worktree checkout** when it is created.
- `teardown` — commands run when the worktree is removed.

### How it works

| Herdr event        | Action                                                            |
| ------------------ | ----------------------------------------------------------------- |
| `worktree.created` | Run `setup` in the new checkout (CLI/API path).                   |
| `workspace.focused`| Backstop for worktrees created via the UI (which does not emit `worktree.created`). Idempotent via a state marker, so `setup` runs only once per checkout. |
| `worktree.removed` | Run `teardown`.                                                   |

The plugin reads the repo's `.superset/config.json`, resolves the main repo root
from the event/context payload, and runs each command in order. Failures are
logged and do not abort the remaining commands. Inspect runs with:

```bash
herdr plugin log list --plugin superset-bootstrap
```

### Caveats

- **`teardown` runs *after* the checkout folder is deleted.** Herdr fires
  `worktree.removed` once `git worktree remove` has already removed the
  directory, and that event carries no repo root. The plugin stashes the main
  repo root in its setup marker to locate the config later, and runs `teardown`
  from the main repo root. So `teardown` is for cleaning up **external** resources
  (containers, volumes, caches) — not files inside the (now gone) worktree. The
  command receives `$SUPERSET_WORKTREE_PATH` and `$SUPERSET_WORKTREE_BRANCH` to
  identify the removed checkout.
- Removing a worktree that contains git submodules requires `--force`:
  `herdr worktree remove --workspace <id> --force`.
- Requires `jq`. Built for Herdr **0.7.0+**.

## Plugin: nvim-diffview

A local Herdr plugin that opens **Neovim's [diffview.nvim](https://github.com/sindrets/diffview.nvim)**
in a split or tab to review git diffs, then gets out of the way.

### Two comparisons

| Comparison | What it shows | diffview command |
| ---------- | ------------- | ---------------- |
| **working** | Uncommitted changes — working tree + index vs `HEAD` | `:DiffviewOpen` |
| **branch**  | The whole branch — `base...HEAD` (every commit since the fork point) | `:DiffviewOpen <base>...HEAD` |

The **base** for the branch comparison is auto-detected: `origin/HEAD`'s default
branch, else the first of `main` / `master` / `develop` that exists. Override it
per repo with the `HERDR_DIFFVIEW_BASE` environment variable.

### Behaviour

- Runs Neovim with **your full config** — `diffview.nvim` must be installed there
  (it is, via `lua/plugins/diffview.lua`).
- **Transient viewer:** closing the diffview view (`:DiffviewClose` / `q`) quits
  Neovim, so the split/tab disappears with it. Uses `:qa` (not `:qa!`), so edits
  made in the diff prompt to save rather than being dropped.
- **Idempotent toggle**, per comparison: pressing the key opens the diff; pressing
  it again focuses it; once more closes it. `working` and `branch` have separate
  identities and can be open at once. The tab variant switches to an existing diff
  tab rather than duplicating it.

### Keybindings (tracked in `config.toml`)

| Key | Action |
| --- | ------ |
| `prefix+u`       | uncommitted (working tree) diff, split |
| `prefix+shift+u` | uncommitted (working tree) diff, own tab |
| `prefix+a`       | branch vs base diff, split |
| `prefix+shift+a` | branch vs base diff, own tab |

These are chosen to be conflict-free with Herdr's default keybindings
(`prefix+b` is `toggle_sidebar`, `prefix+shift+d` is `close_workspace`).

Requires `jq` and `nvim` (with `diffview.nvim`). Built for Herdr **0.7.0+**.

## Installed marketplace plugins

These are installed from GitHub (not tracked in this repo — `herdr plugin
install` downloads them into the ignored `plugins/github/`). Reinstall on a new
machine with the commands below.

| Plugin | What it does | Deps |
| ------ | ------------ | ---- |
| [`wyattjoh/herdr-plugin-gh-pr`](https://github.com/wyattjoh/herdr-plugin-gh-pr) | Shows the focused worktree branch's GitHub PR status in the sidebar | `bun`, `gh` |
| [`smarzban/herdr-file-viewer`](https://github.com/smarzban/herdr-file-viewer) | Git-aware read-only file viewer TUI (tree + diff/markdown/syntax in a split pane) | `cargo` (builds on install) |
| [`paulbkim-dev/vim-herdr-navigation`](https://github.com/paulbkim-dev/vim-herdr-navigation) | Seamless `Ctrl+h/j/k/l` navigation across Herdr panes and Vim/Neovim splits | `bash` |
| [`ogulcancelik/herdr-plugin-github-start`](https://github.com/ogulcancelik/herdr-plugin-github-start) | Start Claude/Codex from a GitHub issue, PR, or discussion | `node` |

```bash
herdr plugin install wyattjoh/herdr-plugin-gh-pr --yes
herdr plugin install smarzban/herdr-file-viewer --yes
herdr plugin install paulbkim-dev/vim-herdr-navigation --yes
herdr plugin install ogulcancelik/herdr-plugin-github-start --yes
```

> **`vim-herdr-navigation` needs two more steps** beyond `plugin install`:
> 1. The `[[keys.command]]` bindings for `Ctrl+h/j/k/l` in `config.toml` — already
>    tracked in this repo.
> 2. The Neovim side, copied to `~/.config/nvim/after/plugin/herdr_nav.lua` from
>    the plugin's `editor/nvim.lua`. This lives in the Neovim config, not this repo.

## Setup on a new machine

```bash
git clone https://github.com/mkdir700/herdr-config ~/.config/herdr
cd ~/.config/herdr
herdr plugin link plugins/superset-bootstrap   # local plugin
herdr plugin link plugins/nvim-diffview        # local plugin
# then reinstall the marketplace plugins listed above
```

`plugin link` re-enables the local plugin (the `plugins.json` registry is
machine-specific and not tracked, so it is rebuilt).

## What's ignored

`*.sock`, `*.log`, `session.json`, `plugins.json`, `plugins/config/`, and
`plugins/github/` — all Herdr-managed runtime state and plugin downloads,
regenerated automatically.
