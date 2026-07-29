#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bin_dir="$tmp_dir/bin"
workspace="$tmp_dir/workspace"
mkdir -p "$bin_dir" "$workspace"

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

cat >"$bin_dir/agent-recorder" <<'EOF'
#!/usr/bin/env bash
{
	printf '%s' "$(basename "$0")"
	if [ "$#" -gt 0 ]; then
		printf ' %s' "$@"
	fi
	printf '\n%s\n' "$PWD"
} >"$TEST_AGENT_LOG"
EOF
chmod +x "$bin_dir/agent-recorder"
for agent in codex claude pi; do
	ln -s agent-recorder "$bin_dir/$agent"
done

for test_case in \
	"codex|codex --dangerously-bypass-approvals-and-sandbox" \
	"claude|claude --dangerously-skip-permissions" \
	"pi|pi"; do
	agent="${test_case%%|*}"
	expected_command="${test_case#*|}"
	agent_log="$tmp_dir/$agent-agent.log"
	PATH="$bin_dir:$PATH" \
		TEST_AGENT_LOG="$agent_log" \
		HERDR_AGENT_LAUNCHER_CWD="$workspace" \
		bash "$repo_root/plugins/agent-launcher/scripts/run-agent.sh" "$agent"

	actual_command="$(sed -n '1p' "$agent_log")"
	actual_cwd="$(sed -n '2p' "$agent_log")"
	if [ "$actual_command" != "$expected_command" ] || [ "$actual_cwd" != "$workspace" ]; then
		printf 'FAIL: unexpected %s process launch:\n%s\n' "$agent" "$(cat "$agent_log")" >&2
		exit 1
	fi
done

printf 'PASS: agent launcher opens danger-mode Codex/Claude and default Pi tabs\n'
