---
description: Run a targeted pre-ship quality pass for a feature, file, or surface.
argument-hint: [feature-or-path]
---

Run a lean pre-ship review for `$ARGUMENTS`.

Workflow:

1. Identify whether the work is in `Sprout-html`, `Sprout-iOS`, or both.
2. Use only the relevant project skills:
   - `budget-invariants`
   - `month-rollover-check`
   - `backup-persistence-check`
   - `quick-entry-path-check`
   - `surface-drift-check`
3. Review for:
   - user-visible regressions
   - data-loss risk
   - wrong totals or wrong carryover
   - routing/presentation mistakes
   - verification gaps caused by the current environment
4. Return findings first, ordered by severity, with exact file references.
5. Keep the summary brief. Do not pad with stylistic suggestions.
