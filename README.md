# herdr-config

Personal configuration for [Herdr](https://herdr.dev) — a mouse-friendly terminal
multiplexer with first-class support for running AI coding agents in parallel.

This repo tracks the hand-written config and a local plugin. Herdr's runtime
state (sockets, logs, session, plugin runtime copies) is intentionally
`.gitignore`d so the repo stays portable across machines.

## Contents

```
config.toml                         # Herdr settings (UI, worktrees, keybindings)
scripts/link-local-plugins.sh       # Re-link all local plugins (run after cloning)
plugins/superset-bootstrap/         # Local plugin: reuse .superset/config.json for worktrees
  herdr-plugin.toml
  hook.sh
plugins/tuicr-diff/                 # Local plugin: review git diffs via tuicr (terminal code-review TUI)
  herdr-plugin.toml
  scripts/launch.sh                 #   idempotent open/focus/close launcher
  scripts/tuicr-diff.sh             #   pane wrapper: detect base, run tuicr -w / -r base...HEAD
plugins/copy-workspace-path/        # Local plugin: "Copy path" (prefix+y) — copy focused workspace/tab/pane cwd
  herdr-plugin.toml
  scripts/copy-path.sh              #   resolve the focused item's cwd, copy to clipboard
plugins/github-issue-worktree/      # Local plugin: issue → worktree (prefix+shift+i), names drafted by claude
  herdr-plugin.toml
  config.example.json               #   default agent, base ref, prompt template
  scripts/open.js                   #   action entrypoint: open the overlay prompt
  scripts/prompt.js                 #   read issue, draft names, create worktree, launch agent
```

## config.toml

```toml
[ui]
agent_panel_scope = "all"

# Root for git worktree checkouts created from the sidebar/CLI.
# Layout: <directory>/<repo>/<branch-slug>
[worktrees]
directory = "~/.herdr/worktrees"
```

### Keybindings — aligned to LazyVim

The full `[keys]` block is remapped to **LazyVim** conventions for Vim muscle
memory. Herdr uses a tmux-style **prefix** model (press the prefix, then a key),
so the prefix (`ctrl+b`) plays the role of LazyVim's `<leader>` — Vim's `Space`
leader can't be a multiplexer prefix without eating every space you type.

Concept mapping: herdr **pane** → nvim window (split), herdr **tab** → nvim tab,
herdr **workspace** → project/session.

**Window navigation is direct (no prefix):** `Ctrl+h/j/k/l` moves across Vim
splits *and* herdr panes seamlessly (via `vim-herdr-navigation`), exactly like
LazyVim's `<C-hjkl>`.

| Scope | Key (after `ctrl+b`) | Action | LazyVim analog |
| ----- | -------------------- | ------ | -------------- |
| Pane  | `h` / `j` / `k` / `l` | focus left/down/up/right | `<C-hjkl>` |
| Pane  | `-`                   | split below (stacked)    | `<leader>-` |
| Pane  | `+`                   | split right (side by side) | `<leader>+` |
| Pane  | `x` / `z` / `r`       | close / maximize / resize mode | `<leader>wd` / `wm` |
| Pane  | `Tab` / `Shift+Tab`   | cycle next / previous panes | — |
| Pane  | `Shift+p`             | rename pane | — |
| Tab   | `[` / `]`             | previous / next tab | `<leader><tab>[` / `]` |
| Tab   | `t` / `Shift+t` / `Shift+x` | new / rename / close tab | `<leader><tab><tab>` |
| Tab   | `1`..`9`              | switch to tab N | — |
| Wksp  | `w`                   | workspace picker | — |
| Wksp  | `Shift+n` / `Shift+w` / `Shift+d` | new / rename / close workspace | — |
| Wksp  | `Shift+1`..`Shift+9`  | switch to workspace N | — |
| Wksp  | `{` / `}`             | previous / next workspace | — |
| Agent | `,` / `.`             | previous / next agent (any workspace/tab) | — |
| Misc  | `?` `s` `q` `g` `o` `e` `c` `b` | help / settings / detach / goto / notification / edit-scrollback / copy-mode / sidebar | — |

Notes:

- `copy_mode` is moved off its hidden default (`prefix+[`) to `prefix+c`, freeing
  `[` / `]` for LazyVim-style tab navigation.
- **Split direction** follows Vim's convention (`-` stacks, `+` is side by side).
  If it feels swapped on your terminal, swap the `split_horizontal` /
  `split_vertical` values in `config.toml`.
- **Workspace `{` / `}`** mirror the tab `[` / `]` bindings — outer brackets for
  the outer container. **Agent `,` / `.`** cycle focus across agent panes
  regardless of layout; `Shift+hjkl` is left to herdr's built-in `swap_pane`.

```toml
# Worktree keybindings (prefix defaults to ctrl+b).
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

## Plugin: tuicr-diff

A local Herdr plugin that opens **[tuicr](https://tuicr.dev)** — a terminal
code-review TUI with vim keybindings — in a split or tab to review git diffs,
then gets out of the way. No nvim involved.

### Two comparisons

| Comparison | What it shows | tuicr command |
| ---------- | ------------- | ------------- |
| **working** | Uncommitted changes — working tree + index vs `HEAD` | `tuicr -w` |
| **branch**  | The whole branch — `base...HEAD` (every commit since the fork point) | `tuicr -r <base>...HEAD` |

The **base** for the branch comparison is auto-detected: `origin/HEAD`'s default
branch, else the first of `main` / `master` / `develop` that exists. Override it
per repo with the `HERDR_DIFF_BASE` environment variable.

### Behaviour

- Runs **tuicr** directly in the pane — a single static binary, no editor and no
  runtime deps. Reviewing a local diff needs **no GitHub auth** (that's only for
  `:submit`, which pushes a PR review).
- **Transient viewer:** quitting tuicr (`q`) exits the process, so the split/tab
  disappears with it.
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

Requires `jq` and [`tuicr`](https://tuicr.dev) on `PATH`
(`curl -fsSL tuicr.dev/install.sh | sh`, or `brew install agavra/tap/tuicr`,
`cargo install tuicr`). Built for Herdr **0.7.0+**.

## Plugin: copy-workspace-path

A local Herdr plugin that copies the focused workspace/tab/pane's working
directory to the system clipboard.

> **Why a keybinding, not a right-click menu item.** The original goal was a
> "Copy path" entry in the sidebar right-click menu. **Herdr 0.7.0's right-click
> menu is built-in and does not render plugin actions** (the `contexts` field is
> accepted but unused by the menu in this version — even the official
> `github-start` plugin's `contexts`-tagged action does not appear there). So
> the action is surfaced as a **keybinding** instead — the documented way to
> trigger a plugin action, same as `github-start`. Revisit the menu approach if
> a future Herdr release makes the context menu plugin-extensible.

### How it works

Three actions (`copy-path-workspace` / `-tab` / `-pane`), all titled **Copy
path**, sharing `scripts/copy-path.sh` which takes the level as its argument.
Each is invoked by a keybinding (or `herdr plugin action invoke
copy-workspace-path.copy-path-<level>`). The `contexts` values are kept as
forward-looking metadata for if/when the menu becomes extensible.

On invocation Herdr injects the focused item's id (`HERDR_WORKSPACE_ID` /
`HERDR_TAB_ID` / `HERDR_PANE_ID`) plus a flat `HERDR_PLUGIN_CONTEXT_JSON`. The
script resolves the cwd from that id against `pane list` (authoritative),
falling back to the context JSON or the focused pane when an id is missing:

| Level | What gets copied |
| ----- | ---------------- |
| **workspace** | cwd of the workspace's active pane |
| **tab**       | cwd of the tab's active pane |
| **pane**      | cwd of that pane |

A workspace/tab has no path of its own — its "path" is the cwd Herdr tracks for
its active pane, so that is what gets copied.

### Keybinding (tracked in `config.toml`)

| Key | Action |
| --- | ------ |
| `prefix+y` | copy the focused **workspace**'s path (yank) |

Bind the tab/pane variants the same way with `command =
"copy-workspace-path.copy-path-tab"` / `"...copy-path-pane"`.

### Clipboard

Portable, first available wins: `pbcopy` (macOS), `clip.exe` (WSL — sets the
Windows clipboard), `wl-copy` (Wayland), `xclip` / `xsel` (X11). On success it
fires a best-effort top-right toast (visible only when `ui.toast.delivery =
"herdr"`); the copy itself works regardless.

Requires `jq` on `PATH`. Menu-only — no keybinding. Built for Herdr **0.7.0+**.

## Plugin: github-issue-worktree

A local Herdr plugin that starts work **from a GitHub issue** — but instead of
just naming a tab after the issue number (what the marketplace `github-start`
plugin does), it reads the issue's **content** and uses it to name a real **git
worktree + branch**, then launches an agent inside that checkout.

### Why not `github-start`

`github-start` creates a *tab* with a mechanical `gh-issue-614` label, never
reads the issue body, and never touches git worktrees. This plugin reads the
issue, drafts meaningful names from it, and creates an isolated worktree — so
each issue gets its own branch and checkout, ready for parallel agent work.

### Flow (`prefix+shift+i`)

1. Paste an issue URL / `#614` / `issue 614` in the overlay, pick an agent.
2. `gh issue view` pulls the title, body, and labels.
3. `claude -p` drafts `{ branch, workspace }` from that content — e.g.
   `614-fix-login-redirect` + a short workspace label. Falls back to a
   deterministic `issue-<n>-<title-slug>` if `claude` is missing or the output
   can't be parsed (naming never blocks the flow).
4. `herdr worktree create --branch <branch> --label <workspace>` makes the
   worktree, **branched off the repo's default branch** (auto-detected — not
   whatever branch you happened to trigger from). This fires `worktree.created`,
   so the **superset-bootstrap** plugin auto-runs the repo's `setup` in the
   fresh checkout.
5. The chosen agent starts in the worktree's root pane, seeded with a prompt
   pointing at the issue.

### Naming

The "agent drafts the names" step is a single non-interactive `claude -p` call,
not a full interactive agent — names must be decided *before* the worktree (the
agent's working dir) exists. Tune or disable it in `config.json`:

| Key | Effect |
| --- | ------ |
| `defaultAgent`    | `claude` or `codex` (the interactive agent started in the worktree) |
| `baseRef`         | branch off this ref; empty = auto-detect the repo default (`origin/HEAD`, else `main`/`master`/`develop`) |
| `namingModel`     | model for the naming call (empty = your `claude` default) |
| `promptTemplate`  | seed prompt; `{url}` `{title}` `{number}` `{branch}` `{workspace}` |

Config seeds from `config.example.json` on first run. Find it with:

```bash
herdr plugin config-dir github-issue-worktree
```

### Keybinding (tracked in `config.toml`)

| Key | Action |
| --- | ------ |
| `prefix+shift+i` | start a worktree from a GitHub issue (`i` = issue) |

Pairs with the built-in `new_worktree` (`prefix+shift+g`) — same "g/i" worktree
family, but this one seeds the checkout from an issue. Requires `gh`
(authenticated) and `node` 18+ on `PATH`; `claude` is optional (naming only).
Built for Herdr **0.7.0+**.

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
./scripts/link-local-plugins.sh   # links every plugins/<name>/ with a herdr-plugin.toml
# then reinstall the marketplace plugins listed above
```

`scripts/link-local-plugins.sh` links all the local plugins in one shot
(`superset-bootstrap`, `tuicr-diff`, `copy-workspace-path`,
`github-issue-worktree`). The `plugins.json` link registry is machine-specific
and not tracked, so it has to be rebuilt on every new machine — run this script
after cloning. If a plugin keybinding ever does nothing and
`herdr plugin action invoke ...` returns `plugin_not_found`, the registry was
reset; just run the script again. It's idempotent. You can still link an
individual plugin by hand with `herdr plugin link plugins/<name>`.

## What's ignored

`*.sock`, `*.log`, `session.json`, `plugins.json`, `plugins/config/`, and
`plugins/github/` — all Herdr-managed runtime state and plugin downloads,
regenerated automatically.
