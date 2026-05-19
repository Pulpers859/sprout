---
name: budget-invariants
description: Check budget arithmetic and spending invariants when work touches totals, refunds, carryover, progress, or daily allowance.
when_to_use: Use for changes involving BudgetStore, transaction math, dashboard totals, summary cards, calendar net totals, or mirrored web logic in index.html.
---

Focus on correctness, not style.

Steps:

1. Identify the touched surface:
   - Web prototype: `Sprout-html/index.html`
   - iOS app: `Sprout-iOS/Sprout/*.swift`
2. Trace the numbers all the way through:
   - base budget
   - carryover
   - refund handling
   - net spent
   - remaining
   - progress
   - daily allowance
3. Check these invariants explicitly:
   - `budget = base budget + carryover`
   - refunds reduce net spending, not increase it
   - `remaining = budget - net spent`
   - progress is clamped to a safe range
   - carryover never becomes negative during reset/carry-over logic unless that is an explicit product rule
   - zero-budget cases do not divide by zero or show misleading output
4. If the same behavior exists in both web and iOS, compare semantics across both surfaces.
5. Report concrete findings first, with file references and the user-visible consequence.

Do not spend time on visual polish unless it directly hides a logic bug.
