# herdr-plugin-gh-pr (local fork)

Shows the GitHub PR status of the focused **agent** pane's current git branch as a label on that pane's row in the herdr sidebar. The label reads like `#123 🟢` (the PR number plus a **colored status dot**):

| Dot | Meaning |
| --- | ------- |
| 🟢 | open, CI green (passing, or no checks gating the branch) |
| 🟡 | open, CI not green yet (failing or still pending) |
| 🟣 | merged |
| 🔴 | closed |

While the status is being recomputed, the dot is replaced with `⟳`.

> **Local fork** of [`wyattjoh/herdr-plugin-gh-pr`](https://github.com/wyattjoh/herdr-plugin-gh-pr). Upstream uses monochrome symbols (`✓ ✗ ● ◆ ⊘`); this fork swaps them for colored emoji dots, because herdr renders `custom_status` as plain text (ANSI escapes are stripped on normalization), so a self-colored glyph is the only way to convey status by color in the sidebar.

## Requirements

- herdr >= 0.7.0
- `bun`, `git`, and `gh` (authenticated: `gh auth status`) on your PATH

## Install

This fork is tracked in the herdr config repo and linked as a local plugin (it replaces the marketplace install of the same id). From the repo root:

```bash
herdr plugin link plugins/gh-pr
# or, to (re)link every local plugin at once:
./scripts/link-local-plugins.sh
```

That is the entire install. No daemon, no config. herdr runs the hooks with `bun`, so `bun` must be on your PATH.

### Optional keybindings

herdr has no plugin-extensible right-click menu, and a plugin cannot ship its own keybinding (the manifest has no `key` field and keybindings live only in the user's config). To trigger the actions with a keystroke, add them to `~/.config/herdr/config.toml` and run `herdr server reload-config`:

```toml
[[keys.command]]
key = "prefix+u"
type = "plugin_action"
command = "gh-pr.open-pr"
description = "open PR in browser"

[[keys.command]]
key = "prefix+i"
type = "plugin_action"
command = "gh-pr.refresh"
description = "refresh PR status"
```

Then press your prefix (default `ctrl+b`) followed by `u` (open PR) or `i` (refresh status). Avoid `alt+` chords (they emit characters in the terminal), and pick a key that does not collide with a built-in: `o` (notifications), `g` (goto), `r` (resize), `v` (split), and `e` (edit scrollback) are taken by default. `herdr server reload-config` reports any conflict as a `partial` status.

## Use

Focus an agent pane sitting in a git repo whose branch has a PR. The label appears and refreshes when you switch panes or open/create worktrees. To avoid hammering the GitHub API, the automatic path checks at most once per pane every 30 seconds; a manual refresh always updates immediately.

Refresh the focused pane's PR status on demand:

```bash
herdr plugin action invoke gh-pr.refresh
```

Open the focused pane's branch PR in the browser:

```bash
herdr plugin action invoke gh-pr.open-pr
```

The qualified action id uses a dot (`gh-pr.open-pr`), not a slash.

## Develop

- `bun test` runs the unit tests.
- `herdr plugin log list gh-pr` shows hook output.
