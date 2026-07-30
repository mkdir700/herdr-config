#!/usr/bin/env node

const lib = require("./lib.js");

try {
	const target = lib.resolvePaneTarget();
	const closesWorkspace =
		target.tabs.length === 1 && target.tabPanes.length === 1;
	if (!closesWorkspace) {
		lib.closePane(target.pane.pane_id);
		process.exit(0);
	}

	lib.openConfirmation({
		kind: "pane",
		workspaceId: target.workspace.workspace_id,
		tabId: target.pane.tab_id,
		paneId: target.pane.pane_id,
	});
} catch (error) {
	lib.notify("Close pane failed", error.message);
	process.stderr.write(`tab-close-guard: ${error.message}\n`);
	process.exitCode = 1;
}
