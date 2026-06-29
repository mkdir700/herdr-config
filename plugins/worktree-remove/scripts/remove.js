#!/usr/bin/env node
"use strict";

// Action entrypoint (bound to prefix+alt+d). Resolves the focused worktree:
//   - not a removable worktree -> notify and stop
//   - clean                    -> remove immediately (headless) + notify
//   - dirty                    -> open the confirmation overlay (confirm.js),
//                                 which force-removes only after you confirm
//
// Runs headless, so the clean path never flashes an overlay.

const path = require("node:path");
const { spawnSync } = require("node:child_process");
const lib = require(path.join(__dirname, "lib.js"));

try {
  const wt = lib.resolveWorktree();
  if (wt.error) {
    lib.notify("Remove worktree", wt.error);
    process.exit(0);
  }

  if (lib.dirtyFiles(wt.path).length === 0) {
    lib.removeWorktree(wt.workspaceId, false);
    lib.notify("Worktree removed", `${wt.branch || wt.label} (clean)`);
    process.exit(0);
  }

  // Dirty: hand off to the overlay so the user can confirm discarding the work.
  const result = spawnSync(
    lib.herdr,
    [
      "plugin",
      "pane",
      "open",
      "--plugin",
      "worktree-remove",
      "--entrypoint",
      "confirm",
      "--placement",
      "overlay",
      "--focus",
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  );
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  process.exit(result.status ?? (result.error ? 1 : 0));
} catch (error) {
  lib.notify("Remove worktree failed", error.message);
  process.exit(1);
}
