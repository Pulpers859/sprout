---
name: month-rollover-check
description: Audit month reset, carry-over, and date-based behavior when work touches current month state, reset prompts, or calendar flows.
when_to_use: Use for changes involving currentMonth, resetMonth, keepCurrentTransactions, selected calendar state, month grids, or date helpers.
---

Treat this as a regression-prevention checklist for the turn of the month.

Steps:

1. Locate the date boundary logic in the touched surface.
2. Walk through three scenarios:
   - same-month normal launch
   - first launch after month changes
   - user chooses Keep vs Reset Fresh vs Carry Over
3. Verify these behaviors:
   - reset prompt appears only when month keys differ
   - Keep updates the stored month without destroying transactions
   - Reset Fresh clears transactions and clears carryover
   - Carry Over clears transactions and keeps only positive remainder
   - selected calendar detail is cleared when month reset makes prior selection invalid
   - date helpers produce current-month views and safe day counts at month edges
4. Call out any ambiguity in product behavior instead of guessing.
5. If both surfaces implement month logic, compare them and highlight drift.

Prefer simple scenario-based reasoning over generalized date abstractions.
