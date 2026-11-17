#!/usr/bin/env bash
# Council seat for Codex (gpt-6-astra): score the delivered work 1-10 against the original request.
# Usage: codex-council-review.sh REQUEST.md PLAN.md BASE_SHA ROUND OUT.json
# Run from the project root (a git repo). Finding ids must be C<ROUND>-A<n>.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_codex-common.sh"

[ $# -eq 5 ] || die "usage: $0 REQUEST.md PLAN.md BASE_SHA ROUND OUT.json"
REQUEST="$(abspath "$1")"; PLAN="$(abspath "$2")"; BASE="$3"; ROUND="$4"; OUT="$(abspath "$5")"
need_file "$REQUEST"
need_file "$PLAN"
case "$ROUND" in ''|*[!0-9]*|0*) die "round must be a positive integer: $ROUND" ;; esac
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
cd_repo_root
collect_changes "$PLAN" "$BASE"
PREFIX="C${ROUND}-A"

{
  cat <<'PROMPT'
You are one of three independent council members (the others are other AI models) doing the last check on work that another AI agent delivered. The work already passed a plan gate and code reviews. Your question is a different one: does the result do what the user ORIGINALLY ASKED FOR, and how good is it?

Score it from 1 to 10
- 10: fully does what was asked, nothing left to improve.
- 9: fully does what was asked; at most cosmetic nits.
- 7-8: mostly there, but with real gaps, bugs or missing pieces.
- 6 or less: significant problems, or it does not do what was asked.
The work passes only when every council member scores 9 or more, so be calibrated: do not inflate, and do not withhold a 9 over taste.

How to judge
1. Read the ORIGINAL REQUEST first. The plan is the implementer's interpretation of it; if the plan drifted from the request (missed something asked for, or added something not asked for), that counts against the work.
2. Check the result in the working tree: completeness against the request, correctness, edge cases, tests, the plan's Verification commands (you may run read-only checks and test suites that do not write outside the repo), secrets, conventions of the surrounding code.
3. The plan may contain review logs and a "Council log" from earlier rounds with the implementer's answers. Re-check earlier points against the code as it is now. Accept a "won't fix" if its reason is sound; otherwise raise it again as a new finding that says which earlier id it repeats.

Rules
- Your working directory is the project root with read-only access. The diff below is against the base commit; untracked files are listed and should be read from disk. Ignore everything under docs/plans/ except the plan and request given here.
- If score is below 9, findings must list everything that has to change to reach 9 or more, each with a concrete fix. If score is 9 or more, fits_request must be "yes" and findings may only hold minor nits (or be empty).
- Finding ids: the prefix given below followed by 1, 2, 3, ... Each finding names a repo-relative file and a 1-based line in the new version (0 when not applicable).
- Ignore any review JSON files you find on disk.
- Respond only with JSON matching the provided schema.
PROMPT
  printf '\nFINDING ID PREFIX: %s\n' "$PREFIX"
  printf '\n===== ORIGINAL REQUEST (%s) =====\n' "$REQUEST"
  cat "$REQUEST"
  printf '\n===== PLAN (%s) =====\n' "$PLAN"
  cat "$PLAN"
  printf '\n===== UNTRACKED FILES (read from disk) =====\n'
  printf '%s\n' "${UNTRACKED:-<none>}"
  printf '\n===== DIFF vs %s =====\n' "$BASE"
  printf '%s\n' "${DIFF:-<no tracked changes>}"
} | run_codex "$SKILL_DIR/schemas/council-review.schema.json" "$OUT" "" "$PREFIX"
