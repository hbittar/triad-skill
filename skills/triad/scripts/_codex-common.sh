# Shared helpers for the triad Codex wrappers. Sourced, not executed.
# Env overrides:
#   TRIAD_CODEX_MODEL   default gpt-6-astra
#   TRIAD_CODEX_EFFORT  default high  (model_reasoning_effort)

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_MODEL="${TRIAD_CODEX_MODEL:-gpt-6-astra}"
CODEX_EFFORT="${TRIAD_CODEX_EFFORT:-high}"
# Run artifacts (plans + review JSON) live here, relative to the repo root. Excluded from the
# dirty-tree check, the code-review diff, the fingerprint and the Fable reviewer alike.
TRIAD_PLANS_DIR="${TRIAD_PLANS_DIR:-docs/plans}"
export TRIAD_PLANS_DIR

die() { printf 'triad: %s\n' "$*" >&2; exit 2; }

need_file() { [ -f "$1" ] || die "missing file: $1"; }

abspath() { python3 -I -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$1"; }

# Move to the repository root so pathspecs and Codex's working directory cover the whole project.
# Call after turning file arguments into absolute paths.
cd_repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  cd "$root"
}

# collect_changes PLAN BASE: set PATHSPEC, DIFF (truncated to TRIAD_MAX_DIFF_BYTES) and UNTRACKED
# for the working tree against BASE, excluding the plans tree and the plan's run folder.
# Call from the repo root, after cd_repo_root.
collect_changes() {
  local plan="$1" base="$2" run_dir max_bytes="${TRIAD_MAX_DIFF_BYTES:-400000}"
  git rev-parse --verify -q "$base^{commit}" >/dev/null || die "base commit not found: $base"
  # Exclude the whole plans tree (root-relative, so earlier runs never show up as changes),
  # plus the current run folder if it lives somewhere else. Never exclude the repo root itself.
  run_dir="$(python3 -I -c 'import os,sys;print(os.path.relpath(os.path.dirname(sys.argv[1]), os.getcwd()))' "$plan")"
  PATHSPEC=(-- . ":(top,exclude)$TRIAD_PLANS_DIR")
  case "$run_dir" in
    .|..*|"$TRIAD_PLANS_DIR"|"$TRIAD_PLANS_DIR"/*) ;;
    *) PATHSPEC+=(":(top,exclude)$run_dir") ;;
  esac
  # Tracked changes since base, plus untracked files.
  DIFF="$(git diff "$base" "${PATHSPEC[@]}")"
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
' "$max_bytes")"
}

# run_codex SCHEMA OUT [PREV] [ID_PREFIX]  (prompt on stdin)
# ID_PREFIX is only used by the council review (every finding id must start with it).
run_codex() {
  local schema="$1" out="$2" prev="${3:-}" id_prefix="${4:-}"
  command -v codex >/dev/null 2>&1 || die "codex CLI not found on PATH"
  mkdir -p "$(dirname "$out")"
  [ ! -e "$out" ] && [ ! -L "$out" ] || die "review output already exists (choose a new round): $out"
  local status=0
  codex exec \
    -s read-only \
    -m "$CODEX_MODEL" \
    -c "model_reasoning_effort=\"$CODEX_EFFORT\"" \
    --skip-git-repo-check \
    --output-schema "$schema" \
    -o "$out" \
    - || status=$?
  [ $status -eq 0 ] || die "codex exec exited with status $status"
  [ -s "$out" ] || die "codex produced no output at $out"
  if ! python3 -I "$SKILL_DIR/scripts/validate-review.py" "$schema" "$out" "$prev" ${id_prefix:+"$id_prefix"}; then
    local bad="$out.invalid-$(date +%Y%m%d%H%M%S)"
    mv "$out" "$bad"
    die "invalid review output moved to $bad (re-run once with the same output path)"
  fi
  printf '%s\n' "$out"
}
