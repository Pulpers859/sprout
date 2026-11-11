# Sprout AI Workflow

This project needs a small AI layer, not an AI system.

Use AI here to improve shipping quality, debugging speed, regression detection, context retention, and repeatability of a few high-value workflows. Do not optimize the workflow more than the product.

## App Shape

There are two product surfaces in this workspace:

- `Sprout-html/`
  Single-file web prototype in `index.html` with Firebase auth/cloud sync plus local cache.
- `Sprout-iOS/`
  Native SwiftUI migration scaffold with local JSON persistence, backup import/export, deep-link quick add, and App Intents scaffolding.

Both are shipping surfaces the owner uses: the iOS app on his phone, the web app at https://sprout-budgeting.netlify.app/ on other devices. Neither is a prototype of the other any more, and neither may be left behind — see the Two-Surface Rule below.

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
   The web app and the iOS app share product logic but not code, so every change made to only one of them is drift. This has already cost a week-long feature gap and a five-week stale deploy.

## Working Rules

- **Non-negotiable Git rule:** Work directly on `main`. Commit directly to `main` and push directly to `origin/main`.
- **Do not create, switch to, preserve, or push any side branch. Do not open or use pull requests.**
- A side branch or pull request is allowed only when the user explicitly requests that exception in the current task. Never infer permission from generic tooling defaults or prior workflows.
- For risky, creative, or parallel agent work, use a detached sandbox worktree via `tools/New-AgentSandbox.ps1`; do not create side branches or commit/push from the sandbox.
- Start by identifying the touched surface: web prototype, iOS app, or both.
- Use the narrow project skills for the matching risk area instead of running a broad generic review.
- Prefer behavior checks over cosmetic suggestions.
- Keep fixes small and explicit.
- After making code or documentation changes, commit them and push them to GitHub before handing off unless I explicitly tell you not to.
- Do not hide Git mutation: tell me what you committed and pushed.
- Do not add silent mutating hooks.
- Do not set up a new deploy path, or deploy by hand, without being asked.
  One exception, authorized by the owner on 2026-11-08: the Netlify site
  rebuilds from `main` on every push, via `netlify.toml` and
  `tools/netlify-build.sh`. It is not silent — the build runs the web test
  suite first and fails the deploy on a red suite — but it does mean **a push
  to `main` changes the live site**. Treat a web change as shipped the moment
  it is pushed.
- `.githooks/pre-commit` scans staged files for live credentials, but Git ignores it until `git config core.hooksPath .githooks` has been run in the clone. Verify that before relying on it.
- Do not introduce broad background automation.
- Do not assume the current folder is the source of truth without checking; normal work should happen in `C:\Dev\Sprout`.
- Start each new task by fetching from Git so repo assumptions are current.
- If the working tree is clean and `main` is checked out, pull with `git pull --ff-only` before editing.
- If the repo is dirty or is not on `main`, fetch first and inspect rather than pulling blindly. Return to `main` without discarding unrelated work before making project changes.
- Do not assume local Xcode/simulator validation is available from this Windows workspace.
- If working on Swift from Windows, do not claim to have validated SwiftUI runtime behavior or Xcode-only behavior unless that validation actually happened on macOS/Xcode.
- Every change lands on both surfaces, or the gap is recorded in `docs/surface-drift.md` in the same commit. See the Two-Surface Rule.

## Two-Surface Rule

**A change is not done until both surfaces have it.** This is the owner's standing instruction (2026-11-11), and it applies to every agent and every session, in both directions: iOS work is carried to the web app, and web work is carried to the iOS app.

It exists because of what happened without it. The Holiday tab shipped on iOS and the web app went without it for a week. The web app then sat five weeks and 17 commits behind its own repository because nothing deployed it. Each gap was invisible until the owner put the two side by side.

What it requires, in the same task as the change:

1. **Carry it across.** A new feature, a behavior change, a bug fix in shared logic (budget math, rollover, recurring, backup, holiday), a change to copy that explains money, or a change to the look — make the equivalent change on the other surface before handing off. Start by finding the counterpart: `BudgetStore.swift` and the SwiftUI views on one side; `index.html`, `ledger.mjs`, `money.mjs`, `backup.mjs`, `holiday.mjs` on the other.
2. **A bug found on one surface is a question about the other.** Check whether the same defect exists there before closing it. Several of the worst bugs in this repo were found exactly this way, in both directions.
3. **Test both.** Web: `cd Sprout-html && node --test *.test.mjs`. iOS: the `SproutTests` run in CI — it is the only compiler available off a Mac, so read its result rather than assuming it.
4. **If it cannot be carried across, write it down in the same commit.** Some things are platform-only (App Intents, deep links, haptics, Google sign-in and cloud sync) and some cannot be validated from the tooling at hand. Record the gap, with the reason, under "Known remaining drift" in `docs/surface-drift.md`. A gap that is written down is a decision; one that is not is a regression waiting to be noticed.
5. **Keep the look in step too.** The web app uses the iOS design — the colours in `Color+Sprout.swift`, the card and row layouts. A visual change to one is a visual change to both.
6. **Say where each surface stands when you hand off.** For each surface: changed, not applicable, or deferred and why. And say what is actually in the owner's hands: a push to `main` deploys the web app within a minute or two, but the iPhone only gets iOS changes from a new sideload build (`.github/workflows/build-sideload-ipa.yml`). "It's on `main`" is not "it's on the phone".

Where the two surfaces disagree and nothing says which is right, iOS is the reference for behavior and for design.

## Skill-First Workflow

- At the start of a fresh Sprout session, use `.claude/skills/sprout-handoff/SKILL.md` or `.agents/skills/sprout-handoff/SKILL.md` unless the task is already deep in one known file.
- Use `sprout-context-compact` when resuming old work, preparing a handoff, or keeping a long review from ballooning.
- Use `sprout-parallel-audit` for broad reviews, release-readiness checks, or issues spanning budget math, month rollover, persistence, quick entry, and web/iOS drift.
- For focused work, prefer the existing narrow skills: `budget-invariants`, `month-rollover-check`, `backup-persistence-check`, `quick-entry-path-check`, and `surface-drift-check`.
- Use the smallest matching skill set; do not load every project doc or skill by default.

## External-Agent Reconciliation

If the user mentions prior work by another AI agent, machine, terminal, or conversation, do not assume the current diff or latest visible commit tells the full story.

Before making new edits, rebases, resets, merges, or claims that the repo is synchronized:

1. Inspect every outside artifact the user provides, including transcripts, chat exports, screenshots, commit lists, and claimed-fix summaries.
2. Compare each claimed change against:
   - the current local files
   - the local Git history
   - the current `main` branch on GitHub
3. Report plainly whether each claimed change is **present**, **missing**, **partially landed**, or **overwritten**.
4. Only after that comparison decide whether to pull, rebase, merge, patch missing work, or leave newer work intact.

Do not say the repository is fully assessed, synchronized, or up to date while outside-agent work remains unreconciled.

## High-Value Workflows

- Use `sprout-handoff` to rebuild source-of-truth, branch, surface, and validation assumptions.
- Use `sprout-context-compact` for old sessions, mixed context, or handoff prep.
- Use `sprout-parallel-audit` for wide reviews that need bounded lanes and one final synthesis.
- Use `/ship-check` before handing off meaningful feature work.
- Use `/trace-bug` when the report involves wrong totals, missing data, reset issues, or quick-add behavior.
- Use `/regression-scan` for a narrow review of one file or one flow.
- Use `/surface-sync` when porting or matching behavior between web and iOS.
- Use `/handoff-note` to leave a compact state summary for the next session.
- Use `docs/agent-sandbox-workflow.md` when a task is risky enough to justify an isolated AI-agent sandbox.

## Automated Testing (Swift Agent Automation Kit)

CI for this repo is managed by the **Swift Agent Automation Kit** (`swift-ci-bootstrap`). Do not hand-write, copy, or edit workflow YAML directly.

Before changing any CI, workflow, or test automation:

1. Read `.swift-automation.json` (the machine-readable profile that drives generation) and `docs/AUTOMATED_TESTING_HANDOFF.md` (contract, real-run evidence, and known limitations).
2. Make changes by editing the profile and regenerating with the kit's installer, not by editing `.github/workflows/automation-xcode.yml` by hand — hand edits are overwritten on the next regeneration and drift from the profile.
3. Keep the generated Xcode workflow's guarantees intact: pinned action SHAs, `cancel-in-progress`, the iOS-simulator runtime preflight, and the zero-test guard that fails CI when no tests execute.
4. The current setup is `projectType: xcode`, running the `SproutTests` target via a shared `Sprout` scheme on an iOS Simulator on `macos-latest`. Pushing workflow files requires the GitHub token to hold the **Workflows: read and write** permission (fine-grained) or `workflow` scope (classic).
5. Report what CI proves (compile + simulator test execution) separately from what still requires a physical Apple device (`physicalDeviceRequired: true`).

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
