---
name: quick-entry-path-check
description: Validate quick-add entry routing across deep links, App Intents, pending request storage, and sheet presentation.
when_to_use: Use for changes involving QuickEntryRoute, QuickEntryRequestStore, QuickEntryCoordinator, App Intents, onOpenURL, or quick-capture presentation.
---

This skill is for the "how does a quick action become the right sheet?" path.

Steps:

1. Trace the request from entry point to UI:
   - URL scheme or App Intent
   - pending request persistence if used
   - coordinator consumption
   - tab selection
   - transaction sheet presentation
2. Verify these invariants:
   - `tab` and `mode` stay aligned end to end
   - invalid or missing route values fall back safely
   - pending requests are consumed once, not replayed forever
   - foreground re-entry paths do not duplicate presentation
   - quick-capture and standard entry use the expected presentation style
3. Check for stale request state after dismiss or app activation.
4. If the change is in iOS only, compare against the documented web behavior or migration intent when helpful.
5. Report the smallest fix that restores reliable routing.

Do not broaden this into a full navigation audit unless the bug clearly escapes the quick-entry path.
