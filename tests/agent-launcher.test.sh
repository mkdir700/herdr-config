#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for agent in codex claude pi; do
	command_log="$tmp_dir/$agent.log"
	HERDR_BIN_PATH="$repo_root/tests/fixtures/fake-herdr-agent-launcher.sh" \
		TEST_COMMAND_LOG="$command_log" \
		bash "$repo_root/plugins/agent-launcher/scripts/open-tab.sh" "$agent"

	expected="plugin pane open --plugin agent-launcher --entrypoint agent-$agent --placement tab --focus --env HERDR_AGENT_LAUNCHER_CWD=/tmp"
	actual="$(<"$command_log")"
	if [ "$actual" != "$expected" ]; then
		printf 'FAIL: unexpected %s launch command:\n%s\n' "$agent" "$actual" >&2
		exit 1
	fi
done

if bash "$repo_root/plugins/agent-launcher/scripts/open-tab.sh" unsupported >/dev/null 2>&1; then
	printf 'FAIL: unsupported agent was accepted\n' >&2
	exit 1
fi

printf 'PASS: agent launcher opens Codex, Claude, and Pi tabs\n'
