#!/usr/bin/env bash
# Install the triad skill into ~/.claude/skills and the launcher into ~/.local/bin.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p ~/.claude/skills ~/.local/bin
rsync -a --delete --exclude __pycache__ --exclude '*.pyc' "$HERE/skills/triad/" ~/.claude/skills/triad/
cp "$HERE/bin/triad" ~/.local/bin/triad
chmod +x ~/.local/bin/triad ~/.claude/skills/triad/scripts/*.sh
echo "installed: ~/.claude/skills/triad and ~/.local/bin/triad"
echo "prerequisites:"
for b in claude codex git python3; do printf "  %-8s " "$b"; command -v "$b" || echo MISSING; done
[ -f ~/.codex/auth.json ] && echo "  codex login: ok" || echo "  codex login: MISSING (run: codex login)"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "  note: add ~/.local/bin to PATH to use the 'triad' launcher";; esac
