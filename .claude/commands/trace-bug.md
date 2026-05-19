---
description: Trace a bug report through the smallest relevant product path and isolate the likely failure point.
argument-hint: [bug-report]
---

Debug `$ARGUMENTS` with a narrow workflow.

Process:

1. Restate the bug in product terms.
2. Identify the likely failure mode:
   - budget math
   - month rollover
   - persistence/restore
   - quick-entry routing
   - surface drift
3. Use the matching project skill instead of doing a broad repo tour.
4. Trace the request or data path end to end.
5. Return:
   - most likely fault location
   - why it causes the reported behavior
   - smallest safe fix
   - what still needs runtime verification

Avoid speculative architecture advice unless the bug cannot be fixed locally.
