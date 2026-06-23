#!/usr/bin/env bash
#
# Herdr plugin: superset-bootstrap
#
# Reuses an existing `.superset/config.json` (the Superset worktree convention)
# to bootstrap / tear down Herdr worktrees. Config lives at the MAIN repo root:
#
#   .superset/config.json
#   { "setup":    ["git submodule update --init --recursive", "bun install"],
#     "teardown": ["docker compose down"] }
#
#   setup    -> runs INSIDE the new worktree checkout on create / first focus.
#   teardown -> runs when the worktree is removed. NOTE: by the time
#               worktree.removed fires, Herdr has already deleted the checkout
#               folder, so teardown runs from the MAIN repo root and is meant
#               for cleaning up external resources (containers, volumes, caches).
#               $SUPERSET_WORKTREE_PATH / _BRANCH identify the gone checkout.
#
# Mode is $1 (setup|teardown).
#
# Payload shape (discovered empirically, Herdr 0.7.0):
#   HERDR_PLUGIN_EVENT_JSON   = { event, data:{ worktree:{path,branch,is_linked_worktree,...},
#                                               workspace:{worktree:{repo_root,...}} } }
#   HERDR_PLUGIN_CONTEXT_JSON = { workspace_cwd, worktree:{repo_root,checkout_path,is_linked_worktree} }
#   worktree.removed carries data.worktree but NO repo_root and an empty context,
#   so we stash repo_root in the idempotency marker during setup and read it back.
set -uo pipefail

MODE="${1:-}"

log()  { printf '[superset-bootstrap] %s\n' "$*"; }
warn() { printf '[superset-bootstrap] WARN: %s\n' "$*" >&2; }

command -v jq >/dev/null 2>&1 || { warn "jq is required"; exit 0; }

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"; [ -n "$ctx" ] || ctx='{}'
evt="${HERDR_PLUGIN_EVENT_JSON:-}";   [ -n "$evt" ] || evt='{}'

# Normalize the two payloads into one flat object.
norm=$(jq -n --argjson c "$ctx" --argjson e "$evt" '
  ($e.data // {}) as $d | {
    wt_path:   ($d.worktree.path // $c.worktree.checkout_path // $c.workspace_cwd // ""),
    branch:    ($d.worktree.branch // $c.worktree.branch // ""),
    is_linked: (($d.worktree.is_linked_worktree // $c.worktree.is_linked_worktree // false) | tostring),
    repo_root: ($c.worktree.repo_root // $d.workspace.worktree.repo_root // $d.worktree.repo_root // "")
  }' 2>/dev/null || echo '{}')
nget() { jq -r "$1 // empty" 2>/dev/null <<<"$norm"; }

wt_path=$(nget '.wt_path')
branch=$(nget '.branch')
is_linked=$(nget '.is_linked')
repo_root=$(nget '.repo_root')

marker_path() {
    [ -n "${HERDR_PLUGIN_STATE_DIR:-}" ] || { printf ''; return; }
    printf '%s/done/%s' "$HERDR_PLUGIN_STATE_DIR" \
        "$(printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1)"
}

run_array() {
    # $1 = jq key (.setup/.teardown), $2 = run dir, $3 = config file
    local key="$1" rundir="$2" cfg="$3" n i cmd
    n=$(jq -r "(${key} // []) | length" "$cfg" 2>/dev/null || echo 0)
    if [ "$n" -eq 0 ]; then log "no ${key#.} commands in config"; return 0; fi
    for ((i=0; i<n; i++)); do
        cmd=$(jq -r "${key}[$i]" "$cfg")
        [ -n "$cmd" ] && [ "$cmd" != "null" ] || continue
        log "${key#.}[$i] (cwd=$rundir): $cmd"
        ( cd "$rundir" 2>/dev/null && /bin/sh -c "$cmd" ) \
            || warn "command failed (continuing): $cmd"
    done
}

case "$MODE" in
  setup)
    [ "$is_linked" = "true" ] || { log "not a linked worktree — skip"; exit 0; }
    [ -n "$wt_path" ] && [ -d "$wt_path" ] || { log "worktree path not present ($wt_path) — skip"; exit 0; }
    wt_path=$(cd "$wt_path" && pwd -P)

    # repo_root from context; fall back to `git worktree list` if absent.
    if [ -z "$repo_root" ]; then
        repo_root=$(git -C "$wt_path" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
    fi
    [ -n "$repo_root" ] && [ -d "$repo_root" ] || { warn "cannot resolve main repo root"; exit 0; }
    repo_root=$(cd "$repo_root" && pwd -P)
    [ "$repo_root" = "$wt_path" ] && { log "this is the main checkout — skip"; exit 0; }

    cfg="$repo_root/.superset/config.json"
    [ -f "$cfg" ] || { log "no .superset/config.json in $repo_root — skip"; exit 0; }

    marker=$(marker_path "$wt_path")
    if [ -n "$marker" ] && [ -f "$marker" ]; then log "already bootstrapped $wt_path — skip"; exit 0; fi

    export SUPERSET_WORKTREE_PATH="$wt_path" SUPERSET_MAIN_ROOT="$repo_root" SUPERSET_WORKTREE_BRANCH="$branch"
    run_array '.setup' "$wt_path" "$cfg"

    # Stash repo_root in the marker so teardown can find the config later.
    if [ -n "$marker" ]; then mkdir -p "$(dirname "$marker")"; printf '%s\n' "$repo_root" > "$marker"; fi
    log "setup complete: $wt_path"
    ;;

  teardown)
    [ -n "$wt_path" ] || { warn "no worktree path in event — skip"; exit 0; }
    marker=$(marker_path "$wt_path")

    # repo_root was stashed at setup time (checkout is already deleted now).
    if [ -z "$repo_root" ] && [ -n "$marker" ] && [ -f "$marker" ]; then
        repo_root=$(head -n1 "$marker" 2>/dev/null)
    fi
    [ -n "$repo_root" ] && [ -d "$repo_root" ] || {
        warn "cannot locate main repo root for teardown (wt=$wt_path); was it bootstrapped by this plugin?"
        [ -n "$marker" ] && rm -f "$marker" 2>/dev/null || true
        exit 0
    }
    repo_root=$(cd "$repo_root" && pwd -P)

    cfg="$repo_root/.superset/config.json"
    [ -f "$cfg" ] || { log "no .superset/config.json in $repo_root — skip"; [ -n "$marker" ] && rm -f "$marker"; exit 0; }

    export SUPERSET_WORKTREE_PATH="$wt_path" SUPERSET_MAIN_ROOT="$repo_root" SUPERSET_WORKTREE_BRANCH="$branch"
    # The checkout is normally gone by now; run from main root (or the checkout if it still exists).
    rundir="$repo_root"; [ -d "$wt_path" ] && rundir="$wt_path"
    run_array '.teardown' "$rundir" "$cfg"

    [ -n "$marker" ] && rm -f "$marker" 2>/dev/null || true
    log "teardown complete: $wt_path"
    ;;

  *) warn "unknown mode: $MODE"; exit 0 ;;
esac
