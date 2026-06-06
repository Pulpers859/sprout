---
name: surface-drift-check
description: Compare web and iOS behavior for the same product flow and flag semantic drift that matters to users.
when_to_use: Use during migration work, when porting a feature, or when the same budgeting behavior exists in both Sprout-html and Sprout-iOS.
---

The purpose is not visual parity. The purpose is product-behavior parity where it still matters.

Steps:

1. Name the flow being compared:
   - budget editing
   - transaction add/delete
   - refunds/payments
   - month reset
   - recent-item quick add
   - calendar details
   - persistence/restore
2. Read the matching logic in both surfaces.
3. Compare semantics, not implementation style:
   - state shape
   - default values
   - validation rules
   - reset behavior
   - sort order
   - carryover handling
   - empty states
4. Separate findings into:
   - intentional platform differences
   - accidental drift likely to confuse users
5. Recommend the smaller change set unless there is a strong reason one surface should become the new source of truth.

Do not ask for full parity when the iOS app intentionally removed Firebase/auth or other web-only infrastructure.
