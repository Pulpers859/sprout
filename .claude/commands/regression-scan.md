---
description: Scan one file or one flow for high-risk regressions without turning it into a full audit.
argument-hint: [path-or-flow]
---

Review `$ARGUMENTS` for regressions with a tight scope.

Rules:

1. Limit the scan to the named file or flow plus direct dependencies.
2. Choose only the relevant project skill checks.
3. Prioritize:
   - incorrect totals
   - broken reset behavior
   - lost or stale persisted state
   - quick-action misrouting
   - drift from the other surface if this behavior is shared
4. Return findings first, then residual risks, then a short “looks safe” note if nothing serious is found.

Do not widen the review unless the evidence points outside the requested scope.
