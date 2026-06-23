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

## Setup on a new machine

```bash
git clone https://github.com/mkdir700/herdr-config ~/.config/herdr
cd ~/.config/herdr
herdr plugin link plugins/superset-bootstrap
```

That re-enables the plugin (the `plugins.json` registry is machine-specific and
not tracked, so `plugin link` rebuilds it).

## What's ignored

`*.sock`, `*.log`, `session.json`, `plugins.json`, and `plugins/config/` — all
Herdr-managed runtime state, regenerated automatically.
