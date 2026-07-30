#!/usr/bin/env node

const lib = require("./lib.js");

try {
	const target = lib.resolveTarget();
	if (target.tabs.length !== 1) {
		lib.closeTab(target.tab.tab_id);
		process.exit(0);
	}

	lib.openConfirmation({
		kind: "tab",
		workspaceId: target.workspace.workspace_id,
		tabId: target.tab.tab_id,
	});
} catch (error) {
	lib.notify("Close tab failed", error.message);
	process.stderr.write(`tab-close-guard: ${error.message}\n`);
	process.exitCode = 1;
}
