export type CheckBucket = "pass" | "fail" | "pending" | "skipping" | "cancel";

export interface Check {
  bucket: CheckBucket;
}

export type CiRollup = "pass" | "fail" | "pending" | "none";

/**
 * GitHub pull request lifecycle state used for sidebar label composition.
 */
export type PullRequestState = "OPEN" | "CLOSED" | "MERGED";

// Collapse per-check buckets into one rollup, worst-status-wins.
// gh's buckets are: pass, fail, pending, skipping, cancel.
export function rollupChecks(checks: Check[]): CiRollup {
  if (checks.length === 0) return "none";
  const buckets = new Set(checks.map((c) => c.bucket));
  if (buckets.has("fail") || buckets.has("cancel")) return "fail";
  if (buckets.has("pending")) return "pending";
  return "pass";
}

// herdr renders custom_status as PLAIN TEXT: normalization strips control
// characters (so ANSI color escapes do not survive) and there is no markup or
// per-source color directive. The only way to convey color in the sidebar label
// is a glyph that carries its own color, so status is encoded with emoji dots,
// which pass normalization and render the same color regardless of the theme:
//
//   🟢 open, CI green (passing, or no checks gating the branch)
//   🟡 open, CI not green yet (failing OR still pending)
//   🟣 merged
//   🔴 closed
const OPEN_DOT: Record<CiRollup, string> = {
  pass: "🟢",
  none: "🟢",
  pending: "🟡",
  fail: "🟡",
};

const TERMINAL_PR_DOT: Record<Exclude<PullRequestState, "OPEN">, string> = {
  MERGED: "🟣",
  CLOSED: "🔴",
};

// Glyph shown in place of the status dot while the status is being recomputed.
export const REFRESHING = "⟳";

// Extract the PR number from an existing label like "#123 🟢" or "#123 ⟳".
// Used to keep the number on screen while a refresh is in flight.
export function parsePrNumber(label: string | null | undefined): number | null {
  const match = label?.match(/^#(\d+)\b/);
  return match ? Number(match[1]) : null;
}

// Label shown during a refresh: keep the number, swap the status dot for the
// refreshing glyph.
export function refreshingLabel(prNumber: number): string {
  return `#${prNumber} ${REFRESHING}`;
}

/**
 * Compose the concise PR sidebar label from a PR number, CI rollup, and PR
 * state. The trailing glyph is a colored dot that encodes the status (see
 * OPEN_DOT / TERMINAL_PR_DOT).
 */
export function composeLabel(
  prNumber: number,
  ci: CiRollup,
  prState: PullRequestState = "OPEN",
): string {
  if (prState !== "OPEN") {
    return `#${prNumber} ${TERMINAL_PR_DOT[prState]}`;
  }

  return `#${prNumber} ${OPEN_DOT[ci]}`;
}
