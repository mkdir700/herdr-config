const { spawnSync } = require("node:child_process");

const herdr = process.env.HERDR_BIN_PATH || "herdr";
const SAFE_ID = /^[A-Za-z0-9:._-]+$/;

function isSafeId(value) {
	return (
		typeof value === "string" && SAFE_ID.test(value) && !value.startsWith("-")
	);
}

function run(args) {
	const result = spawnSync(herdr, args, {
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	});
	if (result.error) {
		throw new Error(
			`${herdr} ${args.join(" ")} failed to start: ${result.error.message}`,
		);
	}
	if (result.status !== 0) {
		throw new Error(
			`${herdr} ${args.join(" ")} failed: ${(result.stderr || result.stdout || `exit ${result.status}`).trim()}`,
		);
	}
	return result.stdout;
}

function runJson(args) {
	const output = run(args);
	try {
		return JSON.parse(output);
	} catch {
		throw new Error(
			`${herdr} ${args.join(" ")} returned non-JSON: ${output.trim()}`,
		);
	}
}

function readJson(value) {
	if (!value) return null;
	try {
		return JSON.parse(value);
	} catch {
		return null;
	}
}

function notify(title, body) {
	try {
		run([
			"notification",
			"show",
			title,
			"--body",
			body,
			"--position",
			"top-right",
		]);
	} catch {
		// Feedback must not obscure the primary error.
	}
}

function workspaceList() {
	return runJson(["workspace", "list"]).result?.workspaces || [];
}

function paneList() {
	return runJson(["pane", "list"]).result?.panes || [];
}

function tabsInWorkspace(workspaceId) {
	if (!isSafeId(workspaceId)) throw new Error("invalid workspace id");
	return (
		runJson(["tab", "list", "--workspace", workspaceId]).result?.tabs || []
	);
}

function targetFromEnvironment() {
	const context = readJson(process.env.HERDR_PLUGIN_CONTEXT_JSON) || {};
	const tabId = process.env.HERDR_TAB_ID || context.tab_id;
	const paneId =
		process.env.HERDR_PANE_ID || context.focused_pane_id || context.pane_id;
	const workspaceId = process.env.HERDR_WORKSPACE_ID || context.workspace_id;
	return {
		tabId: isSafeId(tabId) ? tabId : "",
		paneId: isSafeId(paneId) ? paneId : "",
		workspaceId: isSafeId(workspaceId) ? workspaceId : "",
	};
}

function resolveTarget() {
	const requested = targetFromEnvironment();
	const workspaces = workspaceList();
	let workspace = requested.workspaceId
		? workspaces.find((item) => item.workspace_id === requested.workspaceId)
		: null;

	if (!workspace && requested.tabId) {
		workspace =
			workspaces.find((item) => item.active_tab_id === requested.tabId) || null;
	}
	if (!workspace) workspace = workspaces.find((item) => item.focused) || null;
	if (!workspace) throw new Error("no focused workspace to close a tab from");

	const tabs = tabsInWorkspace(workspace.workspace_id);
	const tab = requested.tabId
		? tabs.find((item) => item.tab_id === requested.tabId)
		: tabs.find((item) => item.tab_id === workspace.active_tab_id);
	if (!tab) throw new Error("the target tab no longer exists in its workspace");

	return { workspace, tab, tabs };
}

function resolvePaneTarget() {
	const requested = targetFromEnvironment();
	const panes = paneList();
	const pane = requested.paneId
		? panes.find((item) => item.pane_id === requested.paneId)
		: panes.find((item) => item.focused);
	if (!pane) throw new Error("no focused pane to close");

	const workspace = workspaceList().find(
		(item) => item.workspace_id === pane.workspace_id,
	);
	if (!workspace) throw new Error("the pane's workspace no longer exists");

	const tabs = tabsInWorkspace(workspace.workspace_id);
	return {
		pane,
		workspace,
		tabs,
		tabPanes: panes.filter((item) => item.tab_id === pane.tab_id),
	};
}

function closeTab(tabId) {
	if (!isSafeId(tabId)) throw new Error("invalid tab id");
	runJson(["tab", "close", tabId]);
}

function closePane(paneId) {
	if (!isSafeId(paneId)) throw new Error("invalid pane id");
	runJson(["pane", "close", paneId]);
}

function closeWorkspace(workspaceId) {
	if (!isSafeId(workspaceId)) throw new Error("invalid workspace id");
	runJson(["workspace", "close", workspaceId]);
}

function openConfirmation({ workspaceId, tabId, paneId, kind }) {
	if (!isSafeId(workspaceId) || !["tab", "pane"].includes(kind)) {
		throw new Error("invalid confirmation target");
	}
	if (kind === "tab" && !isSafeId(tabId)) {
		throw new Error("invalid tab confirmation target");
	}
	if (kind === "pane" && (!isSafeId(tabId) || !isSafeId(paneId))) {
		throw new Error("invalid pane confirmation target");
	}

	const args = [
		"plugin",
		"pane",
		"open",
		"--plugin",
		"tab-close-guard",
		"--entrypoint",
		"confirm",
		"--placement",
		"overlay",
		"--focus",
		"--env",
		`HERDR_TAB_CLOSE_GUARD_WORKSPACE_ID=${workspaceId}`,
		"--env",
		`HERDR_TAB_CLOSE_GUARD_KIND=${kind}`,
		"--env",
		`HERDR_TAB_CLOSE_GUARD_TAB_ID=${tabId}`,
	];
	if (kind === "pane") {
		args.push("--env", `HERDR_TAB_CLOSE_GUARD_PANE_ID=${paneId}`);
	}
	run(args);
}

module.exports = {
	closePane,
	closeTab,
	closeWorkspace,
	isSafeId,
	notify,
	openConfirmation,
	paneList,
	resolvePaneTarget,
	resolveTarget,
	tabsInWorkspace,
	workspaceList,
};
