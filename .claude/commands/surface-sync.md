---
description: Compare a feature across the web prototype and iOS app and summarize meaningful behavioral drift.
argument-hint: [feature]
---

Compare `$ARGUMENTS` across `Sprout-html` and `Sprout-iOS`.

Workflow:

1. Use `surface-drift-check`.
2. Read only the code needed for the named feature.
3. List:
   - matching behavior
   - intentional differences
   - accidental drift
   - recommended smaller fix direction
4. Prefer product semantics over UI styling notes.

Do not demand infrastructure parity where the iOS rewrite intentionally differs from the web prototype.
