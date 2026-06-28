---
name: sprout-parallel-audit
description: Break broad Sprout investigations into bounded lanes, gather evidence without context sprawl, and finish with one integrated judgment. Use for app reviews, multi-flow regressions, release checks, or investigations spanning budget math, rollover, persistence, quick entry, and web/iOS surface drift.
---

# Sprout Parallel Audit

Use this skill when one careful pass is not enough, but a repo-wide sweep would waste context.

## Workflow

1. Confirm the source-of-truth repo is `C:\Dev\Sprout`.
2. Restate the real decision or risk in one sentence.
3. Split the work into 2-4 bounded lanes. Good lane types include:
   - budget arithmetic and dashboard totals
   - month rollover and calendar behavior
   - persistence, backup, restore, and local/cloud sync
   - quick-entry routing and App Intents
   - cross-surface behavior drift
   - build, project structure, or release readiness
4. For each lane, define:
   - the narrow question
   - exact files or artifacts to inspect
   - evidence needed
   - stop condition
5. After each lane or wave, write a compact recap:
   - checked
   - found
   - uncertain
   - next best move
6. Synthesize only after the evidence passes are done.

## Review Priority

Findings should be ordered by:

1. wrong totals, spending, refund, carryover, or remaining-balance behavior
2. month-reset data loss or stale state
3. persistence, restore, backup, or sync failure
4. quick-entry misrouting or duplicate presentation
5. accidental drift between web and iOS behavior
6. maintainability issues likely to compound

## Rules

- Keep one primary session responsible for synthesis and final judgment.
- Prefer small waves over broad file sweeps.
- Separate evidence-backed findings from informed inferences.
- Do not let visual polish distract from budget correctness, data safety, or routing behavior.
- If one focused skill is enough, keep the task simple.

## Common Uses

- "Do a broad review of Sprout."
- "Check whether the iOS migration drifted from the web prototype."
- "Audit budget, reset, persistence, and quick-add flows before release."
- "Prepare a compact handoff after a wide investigation."
