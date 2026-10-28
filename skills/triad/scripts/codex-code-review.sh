#!/usr/bin/env bash
# Review the working-tree diff against a base commit with Codex (gpt-6-astra).
# Usage: codex-code-review.sh PLAN.md BASE_SHA OUT.json [PREV.json]
# Run from the project root (a git repo).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_codex-common.sh"

[ $# -ge 3 ] || die "usage: $0 PLAN.md BASE_SHA OUT.json [PREV.json]"
PLAN="$(abspath "$1")"; BASE="$2"; OUT="$(abspath "$3")"; PREV="${4:+$(abspath "$4")}"
need_file "$PLAN"
[ -z "$PREV" ] || need_file "$PREV"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
cd_repo_root
git rev-parse --verify -q "$BASE^{commit}" >/dev/null || die "base commit not found: $BASE"

MAX_DIFF_BYTES="${TRIAD_MAX_DIFF_BYTES:-400000}"
# Exclude the whole plans tree (root-relative, so earlier runs never show up as changes),
# plus the current run folder if it lives somewhere else. Never exclude the repo root itself.
RUN_DIR="$(python3 -I -c 'import os,sys;print(os.path.relpath(os.path.dirname(sys.argv[1]), os.getcwd()))' "$PLAN")"
PATHSPEC=(-- . ":(top,exclude)$TRIAD_PLANS_DIR")
case "$RUN_DIR" in
  .|..*|"$TRIAD_PLANS_DIR"|"$TRIAD_PLANS_DIR"/*) ;;
  *) PATHSPEC+=(":(top,exclude)$RUN_DIR") ;;
esac

# Tracked changes since base, plus untracked files.
DIFF="$(git diff "$BASE" "${PATHSPEC[@]}")"
UNTRACKED="$(git ls-files --others --exclude-standard "${PATHSPEC[@]}")"
# Consume the entire input before slicing, avoiding SIGPIPE under pipefail.
DIFF="$(printf '%s' "$DIFF" | python3 -I -c '
import sys
limit = int(sys.argv[1])
if limit <= 0:
    sys.exit("TRIAD_MAX_DIFF_BYTES must be positive")
data = sys.stdin.buffer.read()
if len(data) > limit:
    sys.stdout.write(data[:limit].decode("utf-8", errors="ignore"))
    sys.stdout.write(f"\n[diff truncated at {limit} bytes; inspect the working tree directly for the rest]")
else:
    sys.stdout.buffer.write(data)
' "$MAX_DIFF_BYTES")"

{
  cat <<'PROMPT'
You are the final reviewer for a code change implemented by another AI agent from a written plan. Nothing ships until you report verdict "clean".

Check, in this order
1. Every step of the plan is implemented, and its acceptance criteria hold. A step that is missing or half-done is a finding with category "missing-step".
2. Correctness: bugs, regressions, broken edge cases, wrong error handling, concurrency or data-integrity issues.
3. Tests: new behaviour has tests; existing tests still make sense. You may run read-only checks (linters, type checkers, test suites that do not write outside the repo) if they help.
4. Security and secrets.
5. Style only when it violates a convention visible in the surrounding code.

Rules
- Your working directory is the project root with read-only access. The diff below is against the base commit; untracked files are listed and should be read from disk.
- Each finding must name a repo-relative file and a 1-based line in the new version (0 when not applicable), and a concrete fix.
- Do not pad: if the change is complete and correct, verdict "clean" with an empty findings list.
- Severity: blocker = wrong behaviour or plan step not done; major = likely bug or missing test; minor = polish.
- If a previous round is included, evaluate each previous finding and report it in resolved_previous. A finding marked "won't fix" by the implementer with a reason: mark resolved=true if you accept the reason, otherwise re-raise it with the same id.
- verdict must be "clean" only when findings is empty and every previous finding is resolved.
- The only previous round is the PREVIOUS REVIEW ROUND section below, if present. Ignore any review JSON files you find on disk. When that section is absent this is round 1 and resolved_previous must be an empty array.
- Respond only with JSON matching the provided schema.
PROMPT
  printf '\n===== PLAN (%s) =====\n' "$PLAN"
  cat "$PLAN"
  printf '\n===== UNTRACKED FILES (read from disk) =====\n'
  printf '%s\n' "${UNTRACKED:-<none>}"
  printf '\n===== DIFF vs %s =====\n' "$BASE"
  printf '%s\n' "${DIFF:-<no tracked changes>}"
  if [ -n "$PREV" ]; then
    printf '\n===== PREVIOUS REVIEW ROUND (%s) =====\n' "$PREV"
    cat "$PREV"
  fi
} | run_codex "$SKILL_DIR/schemas/code-review.schema.json" "$OUT" "$PREV"
