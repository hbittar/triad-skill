#!/usr/bin/env bash
# Gate an implementation plan with Codex (gpt-6-astra).
# Usage: codex-plan-review.sh PLAN.md OUT.json [PREV.json]
# Run from the project root so Codex can read the repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_codex-common.sh"

[ $# -ge 2 ] || die "usage: $0 PLAN.md OUT.json [PREV.json]"
PLAN="$(abspath "$1")"; OUT="$(abspath "$2")"; PREV="${3:+$(abspath "$3")}"
need_file "$PLAN"
[ -z "$PREV" ] || need_file "$PREV"
cd_repo_root

{
  cat <<'PROMPT'
You are the gate reviewer for an implementation plan written by another AI agent. The plan will be executed verbatim by a third agent, so anything missing, wrong, or vague here becomes a defect later.

Your job: find every gap. Look for
- steps that are missing, out of order, or depend on something the plan never establishes
- assumptions about this repository that are false (verify by reading the code; your working directory is the project root and you have read-only access)
- acceptance criteria that cannot be checked, or steps with no acceptance criteria
- verification that would not catch the likely failure modes
- risks without a mitigation, and scope that silently drifts beyond the stated goal
- missing tests, migrations, config, docs, or rollout steps the codebase convention requires

Rules
- Cite evidence (file paths, existing functions) for every gap about the repo.
- Do not pad: a plan that is genuinely ready gets verdict "approved" and an empty gaps list.
- Severity: blocker = execution would fail or produce wrong behaviour; major = likely rework; minor = polish.
- If a previous round is included, evaluate each previous gap and report it in resolved_previous. A "Reviewer disagreement" note in the plan is the author's counter-argument: mark resolved=true if you accept it, otherwise re-raise the gap with the same id.
- verdict must be "approved" only when gaps is empty and every previous gap is resolved.
- The only previous round is the PREVIOUS REVIEW ROUND section below, if present. Ignore any review JSON files you find on disk. When that section is absent this is round 1 and resolved_previous must be an empty array.
- Respond only with JSON matching the provided schema.
PROMPT
  printf '\n===== PLAN (%s) =====\n' "$PLAN"
  cat "$PLAN"
  if [ -n "$PREV" ]; then
    printf '\n===== PREVIOUS REVIEW ROUND (%s) =====\n' "$PREV"
    cat "$PREV"
  fi
} | run_codex "$SKILL_DIR/schemas/plan-review.schema.json" "$OUT" "$PREV"
