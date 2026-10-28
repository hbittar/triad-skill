# triad — a three-model delivery loop for Claude Code

`/triad <task>` runs one task through five gated phases, each handled by a
different model so no single model reviews its own work:

| Phase | Who | What |
|---|---|---|
| 1. Plan | Claude Fable (your session) | Explores the repo, writes `docs/plans/<date>-<slug>.<id>/plan.md` |
| 2. Plan gate | Codex (`gpt-6-astra`, read-only) | Finds every gap; loops until `approved` and every previous gap is resolved. **You approve the plan once here.** |
| 3. Build | Claude Opus subagent | Implements every step, runs the plan's Verification |
| 4. Code gate | Codex (read-only) | Reviews the diff against the base commit; findings go back to the same Opus agent until `clean` |
| 4b. Final check | Fresh Claude Fable subagent | Independent read of the same code; must also be CLEAN, otherwise back to phase 4 |
| 5. Wrap-up | Fable | Report: rounds per gate, files changed, verification, won't-fix items. Nothing is committed. |

Guard rails built in: hard caps per gate (10 plan reviews, 8 code reviews,
3 final checks), JSON-schema validation of every Codex answer, cross-round
checks (every open finding must be re-raised or marked resolved), a
working-tree fingerprint so a review is discarded as stale if anything
changed while it ran, and a "stuck" rule that stops and asks you when the
reviewer and implementer disagree twice on the same item.

## Prerequisites

- [Claude Code](https://docs.claude.com/en/docs/claude-code) with access to the
  `fable` and `opus` models.
- [Codex CLI](https://github.com/openai/codex) on your PATH and logged in
  (`codex login`), with access to `gpt-6-astra`. Tested with codex-cli 0.164.0.
- `git`, `bash`, `python3` (stdlib only).

## Install

```bash
git clone <this repo> triad-skill
cd triad-skill && ./install.sh
```

This copies `skills/triad/` to `~/.claude/skills/triad/` and the `triad`
launcher to `~/.local/bin/`. To push the same thing to other machines you
reach over SSH:

```bash
~/.claude/skills/triad/scripts/install-remote.sh host1 host2
```

## Use

Inside any Claude Code session running as Fable, in a git repository:

```
/triad add rate limiting to the /api/login endpoint
```

Or from a shell, in the project directory:

```bash
triad "add rate limiting to the /api/login endpoint"
```

The run leaves its artifacts in `docs/plans/<date>-<slug>.<random>/`:
`plan.md` (with a Review log and Code review log appended), `base.sha`, and
one `plan-review-N.json` / `code-review-C.json` per round. Commit or ignore
that folder as you prefer; the skill never commits anything.

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `TRIAD_CODEX_MODEL` | `gpt-6-astra` | Codex model for both gates |
| `TRIAD_CODEX_EFFORT` | `high` | `model_reasoning_effort` passed to Codex |
| `TRIAD_PLANS_DIR` | `docs/plans` | Where runs live; excluded from the dirty-tree check, the diff, the fingerprint and the final reviewer |
| `TRIAD_MAX_DIFF_BYTES` | `400000` | Diff size cap sent to the code gate (the rest is read from disk) |

## Layout

```
skills/triad/
  SKILL.md                      the orchestration instructions Claude follows
  schemas/plan-review.schema.json
  schemas/code-review.schema.json
  scripts/_codex-common.sh      shared: codex exec wrapper + validation
  scripts/codex-plan-review.sh  phase 2 wrapper
  scripts/codex-code-review.sh  phase 4 wrapper
  scripts/validate-review.py    schema + cross-round invariants
  scripts/worktree-fingerprint.py  stale-review detection
  scripts/install-remote.sh     rsync the skill to SSH hosts
bin/triad                       shell launcher: claude --model fable "/triad ..."
install.sh                      local installer
```

## Adapting it

- Swap the gate model by setting `TRIAD_CODEX_MODEL`, or edit
  `_codex-common.sh` to call a different CLI; the wrappers only need a program
  that reads the prompt on stdin and writes JSON matching the schema.
- Swap the implementer or final reviewer by changing the `model:` in the two
  `Agent(...)` calls in `SKILL.md`.
- The prompts Codex sees are the heredocs in the two wrapper scripts.

## License

MIT
