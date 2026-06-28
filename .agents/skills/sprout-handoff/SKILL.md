---
name: sprout-handoff
description: Orient an agent to the real Sprout repo, source-of-truth paths, branch law, product surfaces, stale-copy risk, and high-risk workflows. Use at the start of a Sprout task, when preparing a handoff, or when a session needs to rebuild the project's operating rules before editing.
---

# Sprout Handoff

Use this skill to rebuild the minimum correct context for Sprout before coding, reviewing, or handing work to another session.

## Workflow

1. Confirm the source-of-truth repo is `C:\Dev\Sprout`.
2. Confirm the active branch is `main`, tracking `origin/main`.
3. Run `git fetch --all --prune`; if the tree is clean and `main` is checked out, run `git pull --ff-only`.
4. Confirm the two product surfaces:
   - iOS app: `Sprout-iOS/SproutApp/Sprout/Sprout.xcodeproj`
   - web prototype: `Sprout-html/index.html`
5. Read the smallest relevant instruction file:
   - `AGENTS.md` for shared operating rules and risk priorities
   - `CLAUDE.md` for Claude-specific assumptions
   - `docs/project-handoff.md` for repo handoff and stale-copy notes
6. Explicitly call out stale copies if they appear in the task context:
   - `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Sprout`
7. Identify the touched surface before editing: iOS, web, or both.
8. Choose the focused skill for the highest-risk area, rather than broad generic review.

## Product Risk Order

1. Budget math
2. Month rollover behavior
3. Persistence and restore
4. Quick-entry routing
5. Cross-surface drift between web and iOS
6. Maintainability

## Rules

- Work from `C:\Dev\Sprout`, not the OneDrive/Desktop copy, unless Patrick explicitly asks to inspect that copy.
- Work only on `main`; do not create, switch to, preserve, push, or suggest side branches or pull requests unless Patrick explicitly asks in the current task.
- Commit and push completed code, docs, or workflow changes to `origin/main` unless Patrick says not to.
- Treat `Sprout-html/sprout-firebase-config.js` and `Sprout-html/sprout-firebase-config.local.js` as ignored local config.
- Do not claim SwiftUI/Xcode runtime validation from Windows.
- When shared behavior changes, compare the iOS logic against the web prototype before declaring the work done.

## Good Handoff Shape

Include:

1. repo root
2. touched surface
3. branch and sync state
4. stale-copy warning, if relevant
5. selected focused skill or reason none was needed
6. validation performed and validation limits
