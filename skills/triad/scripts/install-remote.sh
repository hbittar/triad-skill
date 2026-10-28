#!/usr/bin/env bash
# Copy the triad skill and launcher to remote hosts over SSH and check prerequisites there.
# Usage: install-remote.sh host [host ...]
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -gt 0 ] || { echo "usage: $0 host [host ...]" >&2; exit 2; }

for h in "$@"; do
  echo "=== $h ==="
  ssh -o ConnectTimeout=8 "$h" 'mkdir -p ~/.claude/skills ~/.local/bin'
  rsync -a --delete --exclude __pycache__ --exclude "*.pyc" "$SKILL_DIR/" "$h:~/.claude/skills/triad/"
  [ -f "$HOME/.local/bin/triad" ] && rsync -a "$HOME/.local/bin/triad" "$h:~/.local/bin/triad"
  ssh "$h" 'bash -lc "
    chmod +x ~/.local/bin/triad ~/.claude/skills/triad/scripts/*.sh 2>/dev/null || true
    for b in claude codex git python3; do printf \"  %-8s \" \$b; command -v \$b || echo MISSING; done
    [ -f ~/.codex/auth.json ] && echo \"  codex login: ok\" || echo \"  codex login: MISSING (run: codex login)\"
    echo \"  triad: \$(command -v triad || echo not on PATH)\""'
done
