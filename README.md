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
plugins/tuicr-diff/                 # Local plugin: review git diffs via tuicr (terminal code-review TUI)
  herdr-plugin.toml
  scripts/launch.sh                 #   idempotent open/focus/close launcher
  scripts/tuicr-diff.sh             #   pane wrapper: detect base, run tuicr -w / -r base...HEAD
plugins/copy-workspace-path/        # Local plugin: "Copy path" (prefix+y) — copy focused workspace/tab/pane cwd
  herdr-plugin.toml
  scripts/copy-path.sh              #   resolve the focused item's cwd, copy to clipboard
plugins/lazygit/                    # Local plugin: lazygit in a tab (prefix+v) — idempotent open/focus/close
  herdr-plugin.toml
  scripts/launch.sh                 #   idempotent open/focus/close launcher (single tab instance)
  scripts/lazygit.sh                #   pane wrapper: cd to repo, exec lazygit
plugins/gh-pr/                      # Local fork: branch PR status in the sidebar, as a colored dot
  herdr-plugin.toml
  bin/                              #   update-pr-status.ts (labeler) / open-pr.ts (open in browser)
  src/                              #   label.ts (colored-dot composition) / main.ts / throttle.ts
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

## Plugin: lazygit

A local Herdr plugin that opens **[lazygit](https://github.com/jesseduffield/lazygit)**
— a terminal UI for git — in its own tab, then gets out of the way.

### Behaviour

A single lazygit instance lives in its own tab. The bound key (`prefix+v`) is an
**idempotent toggle**, exactly like `tuicr-diff`'s tab variant:

| State when you press the key | What happens |
| ---------------------------- | ------------ |
| No lazygit tab               | open lazygit in a new tab (focused) |
| lazygit tab exists, elsewhere | switch to that tab |
| Already on the lazygit tab   | close it (toggle off) |

The viewer is **transient**: quitting lazygit (`q`) exits the process, so the tab
disappears with it. lazygit runs in the focused pane's repo — the launcher hands
the focused pane's cwd to the new pane via `--env HERDR_LAZYGIT_REPO`, and lazygit
walks up to the enclosing git repo from there.

### How it works

One pane entrypoint (`lazygit`, title `lazygit`) and one action (`toggle`). The
launcher (`scripts/launch.sh`) keys its decision off the pane **label** in
`herdr pane list` (so the single instance is found regardless of tab), and
ids pulled from the host JSON are validated flag-safe before reaching an argv
(option-injection guard), mirroring the `tuicr-diff` launcher.

### Keybinding (tracked in `config.toml`)

| Key | Action |
| --- | ------ |
| `prefix+v` | toggle lazygit in a tab (open / focus / close) |

`v` is the slot freed when `split_vertical` moved to `prefix+plus`; a loose
mnemonic for version-control. The obvious `g`/`shift+g` were already taken by
`goto` / `new_worktree`. Requires [`lazygit`](https://github.com/jesseduffield/lazygit)
and `jq` on `PATH`. Built for Herdr **0.7.0+**.

## Plugin: gh-pr (local fork)

A local fork of [`wyattjoh/herdr-plugin-gh-pr`](https://github.com/wyattjoh/herdr-plugin-gh-pr)
that labels the focused **agent** pane's sidebar row with its git branch's GitHub
PR status. The label reads like `#1157 🟣` — the PR number plus a **colored status
dot** so the state reads at a glance:

| Dot | Meaning |
| --- | ------- |
| 🟢 | open, CI green (passing, or no checks gating the branch) |
| 🟡 | open, CI not green yet (failing or still pending) |
| 🟣 | merged |
| 🔴 | closed |

While a refresh is in flight the dot is `⟳`.

### Why a fork (and why a dot, not colored text)

Herdr renders the sidebar `custom_status` as **plain text**: on normalization it
strips control characters (so ANSI color escapes do not survive) and caps the
string at 32 chars — there is no markup or per-source color directive. So the PR
number itself cannot be colored. The only way to convey status by color in the
sidebar is a glyph that carries its own color, hence the emoji dots. Upstream
ships monochrome symbols (`✓ ✗ ● ◆ ⊘`); this fork swaps `composeLabel`
(`src/label.ts`) for the colored dots above. Everything else is unchanged.

Because the change lives in plugin code, the marketplace install is replaced by
this tracked local plugin. It is picked up automatically by
`scripts/link-local-plugins.sh`. Requires `bun`, `gh` (authenticated), and `git`
on `PATH`. Built for Herdr **0.7.0+**.

## Installed marketplace plugins

These are installed from GitHub (not tracked in this repo — `herdr plugin
install` downloads them into the ignored `plugins/github/`). Reinstall on a new
machine with the commands below.

| Plugin | What it does | Deps |
| ------ | ------------ | ---- |
| [`smarzban/herdr-file-viewer`](https://github.com/smarzban/herdr-file-viewer) | Git-aware read-only file viewer TUI (tree + diff/markdown/syntax in a split pane) | `cargo` (builds on install) |
| [`paulbkim-dev/vim-herdr-navigation`](https://github.com/paulbkim-dev/vim-herdr-navigation) | Seamless `Ctrl+h/j/k/l` navigation across Herdr panes and Vim/Neovim splits | `bash` |
| [`ogulcancelik/herdr-plugin-github-start`](https://github.com/ogulcancelik/herdr-plugin-github-start) | Start Claude/Codex from a GitHub issue, PR, or discussion | `node` |
| [`mkdir700/herdr-plugin-superset-bootstrap`](https://github.com/mkdir700/herdr-plugin-superset-bootstrap) | Run a repo's `.superset/config.json` setup/teardown commands when a worktree is created or removed | `jq` |
| [`mkdir700/herdr-plugin-worktree`](https://github.com/mkdir700/herdr-plugin-worktree) | Full worktree lifecycle: `create` from a GitHub issue/PR/branch (claude-named), force-aware `remove` of the focused worktree | `gh`, `git`, `node` |

```bash
herdr plugin install smarzban/herdr-file-viewer --yes
herdr plugin install paulbkim-dev/vim-herdr-navigation --yes
herdr plugin install ogulcancelik/herdr-plugin-github-start --yes
herdr plugin install mkdir700/herdr-plugin-superset-bootstrap --yes
herdr plugin install mkdir700/herdr-plugin-worktree --yes
```

> `gh-pr` used to be installed from `wyattjoh/herdr-plugin-gh-pr`; it is now a
> tracked local fork (`plugins/gh-pr/`, colored status dots) linked by
> `link-local-plugins.sh`, so it is no longer a marketplace install.

> `superset-bootstrap` used to be a tracked local plugin (`plugins/superset-bootstrap/`)
> linked by `link-local-plugins.sh`; it is now split out into its own repo,
> [`mkdir700/herdr-plugin-superset-bootstrap`](https://github.com/mkdir700/herdr-plugin-superset-bootstrap),
> and installed like the other marketplace plugins above.

> `github-issue-worktree` and `worktree-remove` used to be two separate
> tracked local plugins (`plugins/github-issue-worktree/`,
> `plugins/worktree-remove/`) linked by `link-local-plugins.sh`; they've since
> been merged into one plugin — two actions covering the full worktree
> lifecycle — split out into its own repo,
> [`mkdir700/herdr-plugin-worktree`](https://github.com/mkdir700/herdr-plugin-worktree),
> and installed like the other marketplace plugins above. The `prefix+shift+i`
> / `prefix+shift+d` keybindings in `config.toml` now call `worktree.create` /
> `worktree.remove`.

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
(`tuicr-diff`, `copy-workspace-path`, `lazygit`, `gh-pr`).
The `plugins.json` link registry is machine-specific
and not tracked, so it has to be rebuilt on every new machine — run this script
after cloning. If a plugin keybinding ever does nothing and
`herdr plugin action invoke ...` returns `plugin_not_found`, the registry was
reset; just run the script again. It's idempotent. You can still link an
individual plugin by hand with `herdr plugin link plugins/<name>`.

## What's ignored

`*.sock`, `*.log`, `session.json`, `plugins.json`, `plugins/config/`, and
`plugins/github/` — all Herdr-managed runtime state and plugin downloads,
regenerated automatically.
