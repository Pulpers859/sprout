---
name: sprout-context-compact
description: Keep agent context lean in Sprout by rebuilding only the project state needed for the current task, choosing the right local skill, and producing compact handoffs. Use when starting a fresh session, resuming older work, preparing a handoff, or when docs, logs, or diffs may balloon context.
---

# Sprout Context Compact

Use this skill when the session needs enough context to be safe without rereading the whole repository.

## Workflow

1. Start with the current user request and root `AGENTS.md`.
2. Use `sprout-handoff` for fresh repo orientation.
3. Choose one deeper skill first:
   - `budget-invariants` for totals, refunds, carryover, progress, or daily allowance
   - `month-rollover-check` for reset prompts, keep/reset/carry-over behavior, month keys, or calendar state
   - `backup-persistence-check` for JSON persistence, backup import/export, local cache, or cloud/local merge behavior
   - `quick-entry-path-check` for URL routes, App Intents, pending requests, or quick-capture presentation
   - `surface-drift-check` when behavior exists in both `Sprout-html` and `Sprout-iOS`
   - `sprout-parallel-audit` for broad reviews across multiple risk areas
4. Open only the files directly needed for the task.
5. Before editing or ending, summarize state in 5-8 bullets:
   - what was checked
   - what was found
   - what is evidence-backed
   - what is inferred
   - what remains unverified
   - next best move

## Rules

- Do not load all docs or skills by default.
- Do not paste giant logs when a short issue summary will do.
- Prefer targeted searches, line-level reads, and compact recaps.
- Reuse prior conclusions only if branch state and relevant files have not changed.
- Keep Sprout's actual product risks ahead of AI-workflow ceremony.

## Common Uses

- "Refresh yourself on Sprout before continuing."
- "Pick up where another session left off."
- "Summarize this work for the next agent."
- "Keep this review light on context."
