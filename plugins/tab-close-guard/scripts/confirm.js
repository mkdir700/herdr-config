#!/usr/bin/env node

const readline = require("node:readline/promises");
const { stdin: input, stdout: output } = require("node:process");
const lib = require("./lib.js");

function requiredId(name) {
	const value = process.env[name];
	if (!lib.isSafeId(value)) throw new Error(`missing or invalid ${name}`);
	return value;
}

function confirmationKind() {
	const kind = process.env.HERDR_TAB_CLOSE_GUARD_KIND;
	if (kind !== "tab" && kind !== "pane") {
		throw new Error("missing or invalid HERDR_TAB_CLOSE_GUARD_KIND");
	}
	return kind;
}

async function main() {
	const workspaceId = requiredId("HERDR_TAB_CLOSE_GUARD_WORKSPACE_ID");
	const tabId = requiredId("HERDR_TAB_CLOSE_GUARD_TAB_ID");
	const kind = confirmationKind();
	const paneId =
		kind === "pane" ? requiredId("HERDR_TAB_CLOSE_GUARD_PANE_ID") : "";
	const workspace = lib
		.workspaceList()
		.find((item) => item.workspace_id === workspaceId);
	const tabs = lib.tabsInWorkspace(workspaceId);
	const tab = tabs.find((item) => item.tab_id === tabId);
	const pane =
		kind === "pane"
			? lib.paneList().find((item) => item.pane_id === paneId)
			: null;

	output.write("\x1b[2J\x1b[H");
	if (!tab || (kind === "pane" && !pane)) {
		output.write("The target was already closed. Nothing to do.\n");
		return;
	}

	output.write(`Close final ${kind}?\n\n`);
	output.write(`Tab       : ${tab.label || tab.tab_id}\n`);
	output.write(`Workspace : ${workspace?.label || workspaceId}\n\n`);
	output.write(
		`This is the workspace's only tab${kind === "pane" ? " and pane" : ""}. Closing it also removes the workspace.\n\n`,
	);

	const terminal = readline.createInterface({ input, output });
	const response = await terminal.question(
		"Type 'y' to close it, anything else to cancel: ",
	);
	const answer = response.trim().toLowerCase();
	terminal.close();

	if (answer !== "y" && answer !== "yes") {
		output.write(
			`\nCancelled. ${kind[0].toUpperCase()}${kind.slice(1)} kept.\n`,
		);
		return;
	}

	const currentTabs = lib.tabsInWorkspace(workspaceId);
	if (kind === "tab") {
		if (currentTabs.length === 1) {
			lib.closeWorkspace(workspaceId);
		} else {
			lib.closeTab(tabId);
		}
	} else {
		const currentPanes = lib.paneList();
		const currentTabPanes = currentPanes.filter(
			(item) => item.tab_id === tabId,
		);
		if (currentTabs.length === 1 && currentTabPanes.length === 1) {
			lib.closeWorkspace(workspaceId);
		} else {
			lib.closePane(paneId);
		}
	}
	output.write("\nClosed requested target.\n");
}

main().catch((error) => {
	output.write(`\nError: ${error.message}\n`);
	process.exitCode = 1;
});
