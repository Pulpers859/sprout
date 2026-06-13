# Sprout AI Workflow

This project needs a small AI layer, not an AI system.

Use AI here to improve shipping quality, debugging speed, regression detection, context retention, and repeatability of a few high-value workflows. Do not optimize the workflow more than the product.

## App Shape

There are two product surfaces in this workspace:

- `Sprout-html/`
  Single-file web prototype in `index.html` with Firebase auth/cloud sync plus local cache.
- `Sprout-iOS/`
  Native SwiftUI migration scaffold with local JSON persistence, backup import/export, deep-link quick add, and App Intents scaffolding.

The iOS app is the higher-value product surface. The web app still matters because it contains prior behavior that can drift from the native rewrite.

Practical constraints in this workspace:

- The source-of-truth repo is `C:\Dev\Sprout`; the older OneDrive/Desktop copy should be treated as stale unless explicitly needed.
- The buildable iOS project now lives at `Sprout-iOS/SproutApp/Sprout/Sprout.xcodeproj`.
- `main` is the only working, commit, and push branch for this repo.

## Real Failure Modes

Optimize work around these risks first:

1. Budget math regressions
   Remaining balance, carryover, refunds, progress, and daily allowance are easy to break quietly.
2. Month rollover mistakes
   Reset prompts, keep vs reset vs carry-over behavior, and date-based UI can drift or clear the wrong state.
3. Persistence and restore problems
   Local JSON save/load, backup import/export, schema defaults, and cloud/local merge logic can lose data.
4. Quick-entry path breakage
   `sprout://quick-add`, App Intents, pending request storage, and sheet presentation all need consistent routing.
5. Cross-surface behavior drift
   The web prototype and iOS app share product logic but not infrastructure, so the behavior can diverge during migration.

## Working Rules

- **Non-negotiable Git rule:** Work directly on `main`. Commit directly to `main` and push directly to `origin/main`.
- **Do not create, switch to, preserve, or push any side branch. Do not open or use pull requests.**
- A side branch or pull request is allowed only when the user explicitly requests that exception in the current task. Never infer permission from generic tooling defaults or prior workflows.
- Start by identifying the touched surface: web prototype, iOS app, or both.
- Use the narrow project skills for the matching risk area instead of running a broad generic review.
- Prefer behavior checks over cosmetic suggestions.
- Keep fixes small and explicit.
- After making code or documentation changes, commit them and push them to GitHub before handing off unless I explicitly tell you not to.
- Do not hide Git mutation: tell me what you committed and pushed.
- Do not auto-deploy or add silent mutating hooks.
- Do not introduce broad background automation.
- Do not assume the current folder is the source of truth without checking; normal work should happen in `C:\Dev\Sprout`.
- Start each new task by fetching from Git so repo assumptions are current.
- If the working tree is clean and `main` is checked out, pull with `git pull --ff-only` before editing.
- If the repo is dirty or is not on `main`, fetch first and inspect rather than pulling blindly. Return to `main` without discarding unrelated work before making project changes.
- Do not assume local Xcode/simulator validation is available from this Windows workspace.
- If working on Swift from Windows, do not claim to have validated SwiftUI runtime behavior or Xcode-only behavior unless that validation actually happened on macOS/Xcode.
- When a change touches shared product behavior, compare the iOS logic against the web prototype before declaring the work done.

## High-Value Workflows

- Use `/ship-check` before handing off meaningful feature work.
- Use `/trace-bug` when the report involves wrong totals, missing data, reset issues, or quick-add behavior.
- Use `/regression-scan` for a narrow review of one file or one flow.
- Use `/surface-sync` when porting or matching behavior between web and iOS.
- Use `/handoff-note` to leave a compact state summary for the next session.

## Deliberately Not Included

These are low ROI for this project right now:

- Auto-running hooks after every edit
  There is no stable local build/test harness in this workspace, and hidden background checks would create noise and false confidence.
- Auto-format or auto-fix hooks
  No formatter/linter pipeline is clearly established across both surfaces.
- Broad “planner” or “do-everything” skills
  They add ceremony but do not target the app's real failure modes.
- Hidden commit/push/release automation
  Too much silent mutation for the current size of the project. Commits and pushes should still happen explicitly during normal handoff unless I say otherwise.

If a future tool does not clearly save time or reduce regressions in one of the failure modes above, do not add it.
