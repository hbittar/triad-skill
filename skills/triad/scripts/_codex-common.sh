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

# run_codex SCHEMA OUT [PREV]  (prompt on stdin)
run_codex() {
  local schema="$1" out="$2" prev="${3:-}"
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
  if ! python3 -I "$SKILL_DIR/scripts/validate-review.py" "$schema" "$out" "$prev"; then
    local bad="$out.invalid-$(date +%Y%m%d%H%M%S)"
    mv "$out" "$bad"
    die "invalid review output moved to $bad (re-run once with the same output path)"
  fi
  printf '%s\n' "$out"
}
