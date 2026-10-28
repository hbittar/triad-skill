---
name: triad
description: Three-model delivery loop for a task — Fable writes the plan, Codex (gpt-6-astra) gates it until every gap is closed, an Opus subagent implements it, Codex reviews the diff until no finding is unresolved, and a final Fable review must also pass on the same code. Use when the user runs /triad <task> or asks for the plan→cross-check→execute→verify flow.
user-invocable: true
---

# Triad: plan (Fable) → gate (Codex Astra) → build (Opus) → verify (Codex Astra) → final check (Fable)

You are the orchestrator. You stay in this session as the planner and the
dispatcher; you never implement the plan yourself. The task is `$ARGUMENTS`.
If it is empty, ask the user for the task and stop.

Paths below are relative to this skill directory (`~/.claude/skills/triad`).
Helper scripts: `scripts/codex-plan-review.sh`, `scripts/codex-code-review.sh`.
Always run them from the project root with Bash. Run every loop round in the
foreground; each Codex call takes several minutes.

## Operating rules

- **One approval, then silence.** The user reviews the plan once (end of
  Phase 2) and from that point on is not asked anything until Phase 5 unless
  the flow is stuck: a helper script fails, a round cap is hit, Opus reports a
  step blocked after one follow-up, or Codex and Opus disagree on the same
  item two rounds in a row. Progress goes out as short one-line status
  messages, never as questions. Every question that can be asked before
  approval (dirty tree, open questions, missing git repo) is asked before it.
- **One exclusion rule.** Everything under `docs/plans/` (all runs, not just
  this one) is invisible to the dirty-tree check, the Codex code gate, the
  fingerprint helper and the Fable reviewer. The wrappers and the helper apply
  it themselves (`TRIAD_PLANS_DIR`); the setup check and the Fable prompt must
  use the same path.
- Codex runs in a read-only sandbox. It never edits files; Opus does.
- Never put secrets (`.env` values, tokens, keys) in a plan or a prompt.
- A non-zero exit from a helper script means stop and show the user the error,
  except for the one explicit retry below. Do not retry silently.
- Track logical review rounds separately from helper-call attempts. Initialize
  PLAN_ATTEMPTS=0 and CODE_ATTEMPTS=0 once per run. Immediately before each
  respective review-wrapper invocation, check that PLAN_ATTEMPTS is below 10
  or CODE_ATTEMPTS is below 8, respectively, then increment that counter. All invocations count, including invalid-output retries
  and failed calls. Never reset these counts on edits or phase re-entry.
- If the wrapper reports invalid review output (bad JSON, schema or cross-round
  violation; it moves the bad file to `*.invalid-<timestamp>`), announce the
  failure and retry that logical round once, only if its attempt budget remains.
  Keep the same round number, output path and previous valid review input.
  Do not use the invalid file as PREV. For a code-gate retry, capture a fresh
  CODE_BEFORE fingerprint. If the retry fails, stop and show the error.
  The wrappers validate field types, verdict consistency, unique IDs, and
  complete coverage of previous open findings with `scripts/validate-review.py`.
- Hard caps: 10 plan-review calls, 8 code-review calls, 3 final-check launches
  per run. A passing result on the last permitted call can proceed normally;
  if another call is needed, stop and show the remaining items. Never make a
  eleventh plan-review call, ninth code-review call, or fourth final-check launch
  without new user direction.
- Do not commit, push, or deploy. The user does that.
- If your CLAUDE.md has a session-log or hand-off rule, it still applies at the end.

## Phase 0: setup

1. `git rev-parse --is-inside-work-tree` must succeed. If not, ask the user
   whether to `git init` (the code gate diffs against a base commit). Stop if
   they decline.
2. If `git status --porcelain -- . ':(exclude)docs/plans'` is non-empty, tell
   the user the tree is dirty and that the code gate would review unrelated
   changes. Ask: proceed anyway, or stop so they can commit/stash first.
   Earlier run folders under `docs/plans/` are expected and do not count.
3. Derive a short kebab-case SLUG from the task, then allocate a new run
   directory atomically from the project root:
   ```bash
   mkdir -p docs/plans
   RUN=$(mktemp -d "docs/plans/$(date +%F)-${SLUG}.XXXXXX") || exit 1
   ```
   Keep this exact RUN for the whole invocation. Never reuse a directory from
   an earlier invocation, even for the same task on the same day. If allocation
   fails, stop before writing any artifacts.
4. If the repo has no commits, make an empty one first only with the user's
   consent (`git commit --allow-empty -m "triad base"`). Then record
   `git rev-parse HEAD > "$RUN/base.sha"`; stop if it fails.

## Phase 1: plan (you, Fable)

Explore the codebase first (Explore agents, in parallel, as you would for any
planning task). Then write `$RUN/plan.md` with exactly these sections:

1. **Context**: the need, what prompted it, the intended outcome.
2. **Scope / Non-goals**.
3. **Steps**: numbered. Each step names the files it touches, references the
   existing functions or patterns to reuse (with paths), and ends with an
   **Acceptance** line that a reviewer can check mechanically.
4. **Verification**: the exact commands or checks that prove the whole change
   works (tests, lint, running the app).
5. **Risks and mitigations**.
6. **Open questions**: things only the user can answer. If any exist, ask them
   with AskUserQuestion now and fold the answers into the plan before the gate.

Keep it concise enough to read in a few minutes, detailed enough that Opus can
execute it without guessing.

## Phase 2: plan gate (Codex Astra ↔ you), max 10 calls

Use logical round N = 1, 2, ... and the separate PLAN_ATTEMPTS counter.
Advance N only after a valid review when another review is needed. An
invalid-output retry keeps N unchanged and consumes another attempt.

1. Run, from the project root:
   ```
   ~/.claude/skills/triad/scripts/codex-plan-review.sh "$RUN/plan.md" "$RUN/plan-review-N.json" ["$RUN/plan-review-(N-1).json"]
   ```
   Pass the previous round's file from round 2 on.
2. Read the JSON. Fields: `verdict` (`approved` | `gaps`), `summary`,
   `gaps[] {id, severity, area, description, suggested_fix}`,
   `resolved_previous[] {id, resolved, note}`.
3. Tell the user in one or two lines: round N, verdict, how many gaps by severity.
4. For every gap: verify its claim against the code yourself, then edit
   `plan.md` to close it. If you disagree after checking, add a one-paragraph
   **Reviewer disagreement (Gx)** note right under the affected step with your
   reason; Codex must accept it or re-raise it next round.
5. Maintain a **Review log** section at the end of `plan.md`: one line per gap
   id per round saying `closed: <how>` or `disputed: <why>`.
6. Done when `verdict == "approved"` **and** every entry of `resolved_previous`
   has `resolved: true`. Otherwise go to round N+1.

After Codex approves, show the user the final plan (a 5-10 line summary plus
the path of `plan.md`) and ask with AskUserQuestion: **Execute now** /
**Let me edit the plan first** / **Abort**. This is the only approval in the
flow. If they edit, re-run the gate loop on the edited plan, continuing the
round numbering N and PLAN_ATTEMPTS (new logical rounds use new output paths), and, once Codex approves again,
execute without asking a second time.

## Phase 3: execute (Opus subagent)

Launch one agent and keep its handle; you will message it again in Phase 4.

```
Agent(subagent_type: "general-purpose", model: "opus", description: "Implement triad plan", prompt: <below>)
```

Prompt contents:
- The absolute path of `$RUN/plan.md` and the instruction to read it fully first.
- Implement every step, in order, completely. Do not skip or narrow a step.
- Run the plan's Verification section and fix what it reveals.
- Do not commit, push, or deploy. Do not edit anything under `$RUN/`.
- Report back per step: done / partially done / blocked, with the reason for
  anything not done, plus the verification output summary.

If the report lists partial or blocked steps, send one follow-up via
`SendMessage` to the same agent asking it to finish them. If it is still blocked,
that is a stuck condition: stop and ask the user.

## Phase 4: code gate (Codex Astra ↔ Opus), max 8 calls

Use logical round C, starting at 1, and the separate CODE_ATTEMPTS counter.
Advance C after each valid review when another review is needed, including
stale reviews and re-entry from Phase 4b. An invalid-output retry keeps C
unchanged and consumes another attempt. Never reset either counter. Keep
the latest valid review path as PREV; omit it only before the first valid
review. Each new logical round uses a new output path. Only the permitted
invalid-output retry reuses its now-vacant output path.

1. Before the call, record a fingerprint from the project root:
   ```
   python3 -I ~/.claude/skills/triad/scripts/worktree-fingerprint.py
   ```
   Keep it as CODE_BEFORE. Then run:
   ```
   ~/.claude/skills/triad/scripts/codex-code-review.sh "$RUN/plan.md" "$(cat "$RUN/base.sha")" "$RUN/code-review-C.json" ["$RUN/code-review-(C-1).json"]
   ```
2. Read the JSON. Fields: `verdict` (`clean` | `findings`), `summary`,
   `findings[] {id, severity, category, file, line, description, suggested_fix}`,
   `resolved_previous[] {id, resolved, note}`.
3. After Codex returns, run the fingerprint helper again, before dispatching
   any fixes. If it differs from CODE_BEFORE, the review is stale: discard its
   approval and repeat Phase 4 using the next C (this still counts toward the
   cap). If a helper fails, stop and show the error. When the fingerprints
   match, retain that value as CODE_APPROVED only if the gate passes.
4. Tell the user in one or two lines: round C, verdict, count by severity.
5. If there are findings, send them to the Opus agent with `SendMessage` (same agent, context
   intact; if it is gone, launch a new Opus agent with the plan path and the
   findings). Ask it to fix each one or answer `won't fix: <reason>` per id, and
   to re-run verification afterwards.
6. Write a short **Code review log** section in `plan.md`: per finding id per
   round, `fixed` or `won't fix: <reason>`. The next Codex round reads this from
   the plan and must accept or re-raise each won't-fix.
7. Done when `verdict == "clean"` **and** every `resolved_previous` entry is
   `resolved: true`. Otherwise go to round C+1. If the same finding id is
   re-raised by Codex and answered won't-fix by Opus in two consecutive
   rounds, that is a stuck condition: stop and ask the user to rule on it.

## Phase 4b: final check (Fable), max 3 rounds

Use a separate cumulative final-check counter F, starting at 1; stop before
launching reviewer 4. Codex re-entry never resets C, F, or CODE_ATTEMPTS.

Runs only after Phase 4 ended with `clean` and a recorded CODE_APPROVED.
Immediately before launching Fable, run the fingerprint helper again. If it
differs from CODE_APPROVED, return to Phase 4 before launching Fable.
The point is an independent read that is not anchored on Codex's findings, so use a fresh reviewer, not your own
context:

```
Agent(subagent_type: "general-purpose", model: "fable", description: "Triad final review", prompt: <below>)
```

Prompt contents:
- Read-only. Do not edit any file.
- The absolute path of `$RUN/plan.md`, the base SHA, and the instruction to
  run `git diff <base> -- . ':(top,exclude)docs/plans'` plus read the untracked
  files (`git ls-files --others --exclude-standard -- . ':(top,exclude)docs/plans'`),
  ignoring everything under `docs/plans/` (earlier runs included).
- Check, in order: every plan step implemented and its Acceptance line holds;
  correctness (bugs, edge cases, error handling); tests present and meaningful;
  the plan's Verification commands actually pass (run them if they are
  read-only or test commands); secrets; conventions of the surrounding code.
  Honour the won't-fix entries in the plan's "Code review log" unless they are
  wrong.
- Report as a list of findings with `id` (R1, R2, ...), `severity`
  (blocker|major|minor), `file:line`, description, concrete fix; or the single
  word CLEAN when there is nothing that must change. No padding.

Then:
1. Tell the user in one line: final check round F, clean or how many findings.
2. Run the fingerprint helper after Fable returns, even if it reports CLEAN.
   If it differs from CODE_APPROVED, that approval is stale. Preserve any
   findings, handle them as in step 3, then return to Phase 4 using the next C.
   If CLEAN and the fingerprint matches, advance to Phase 5.
   The helper covers tracked and non-ignored untracked content, modes,
   symlinks, and initialized submodules; it excludes `docs/plans/` and ignored
   build artifacts. Do not run concurrent implementation while reviews are active.
3. If there are findings, send them to the Opus agent with `SendMessage` (fix or
   `won't fix: <reason>` per id, re-run verification), log them in the plan's
   **Code review log** as `R<n>: fixed` / `won't fix: <reason>`, then re-enter
   **Phase 4** on the new state (the Codex gate must be clean again on the code
   as it now stands; pass the latest completed `code-review-C.json` as the previous
   round). When Codex is clean again, run Phase 4b round F+1 with a new Fable
   reviewer agent. Done when a Fable round is CLEAN immediately after a Codex
   clean, i.e. both reviewers passed the same code. A won't-fix that the next
   Fable reviewer rejects twice is a stuck condition: ask the user.

## Phase 5: wrap-up

Report to the user, standing on its own:
- plan path and the number of rounds each gate took (plan gate, Codex code gate, Fable final check)
- files changed (`git status --short`), verification that was run and its result
- any won't-fix items Codex or the Fable reviewer accepted (so the user can overrule)
- that nothing was committed

If your CLAUDE.md asks for a session log or hand-off note, write it now.
