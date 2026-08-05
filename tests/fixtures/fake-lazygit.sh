#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "lazygit $*" >>"$TEST_COMMAND_LOG"
exit "${FAKE_LAZYGIT_EXIT_CODE:-0}"
