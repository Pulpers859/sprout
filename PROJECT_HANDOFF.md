## Project Identity
- Project name: `Sprout`
- Project type: `mixed workspace`
- Source-of-truth repo path: `C:\Dev\Sprout`
- Stale/old copies to ignore if applicable: `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Sprout`
- GitHub remote: `None`

## Repo State
- Stable branch: `main`
- Working branch: `dev`
- Expected default branch for normal work: `dev`
- If Git is not set up yet for this project, the agent should bootstrap it before doing major feature work.

## If No Git Exists Yet
If `git rev-parse --is-inside-work-tree` fails in the real project root, the agent should help set up the repo using this standard:
1. confirm the real project root
2. migrate the project to `C:\Dev\Sprout` if the current location is a weak source of truth
3. initialize local Git
4. create a focused `.gitignore`
5. create `.gitattributes` enforcing LF for code files
6. set repo-local config:
   - `core.autocrlf=false`
   - `core.eol=lf`
   - `pull.ff=only`
   - `fetch.prune=true`
7. add repo-local aliases:
   - `git st`
   - `git lg`
8. create the initial commit
9. connect the GitHub remote if I want one
10. push `main`
11. create and push `dev`
12. add a local hook blocking direct commits to `main`
13. create a dedicated PowerShell shortcut for this project

## PowerShell / Terminal Standard
- Do not globally pin every PowerShell session to this project.
- A dedicated shortcut should exist:
  - `Sprout PowerShell`
- That shortcut should open directly in the source-of-truth repo path.
- Avoid fragile startup command strings if the path contains apostrophes or quoting hazards.

## How The Agent Should Operate
- Inspect before assuming.
- Work in the source-of-truth repo only.
- Fix root causes, not surface symptoms.
- Be honest and direct.
- Prefer architecture/data-flow fixes over hacks.
- Do not use brittle hardcoded special cases or band-aid fixes unless you explicitly explain why a deeper fix is not practical.
- Be proactive: inspect, diagnose, edit code directly, verify, and then audit nearby weaknesses.
- Do not stop at the first fix if adjacent code is obviously fragile.
- Tell me clearly what is evidence-backed, proven, inferred, or heuristic.
- If validation, linting, or review logic is too rigid and rejects good output, improve the rule when appropriate instead of dumbing down the product.
- Do not silently tolerate poor architecture if it is now a maintenance risk.
- Handle Git operations when appropriate.
- Keep normal work on `dev`, not `main`.
- Audit adjacent risks after making fixes.
- Run the checks that are realistically available in the current environment.
- Clearly distinguish evidence-backed logic from heuristics.

## Communication Style
- Warm, collaborative, calm, disciplined
- High-effort and thoughtful
- Short progress updates while working
- Clear reasoning, no fluff, no fake certainty
- If the agent misses something, it should own it directly

## Post-Fix Audit Standard
After making changes, the agent should do another harsh pass focused on:
- root-cause completeness
- adjacent fragility
- architecture quality
- validation or rule correctness
- progression / flow coherence where relevant
- silent failure risk
- wasted retries / wasted cost / wasted work
- maintainability

## What The User Wants By Default
- The user describes the problem in chat.
- The agent investigates directly.
- The agent makes code changes directly.
- The agent audits adjacent risks.
- The agent runs local checks where possible.
- The agent handles Git steps when appropriate.
- The user should not need to babysit PowerShell, Git, or GitHub for normal work.

## Before Starting Any New Task
The agent should confirm:
1. current repo path
2. current branch
3. repo status cleanliness
4. remote configuration
5. whether stale copies exist elsewhere
6. whether the active folder is truly the source of truth

## Architecture / Product Notes
- Main product purpose: personal and grocery budgeting app being migrated from a web prototype to a native SwiftUI app while preserving core behavior.
- Key modules or directories: `Sprout-iOS/Sprout/` for native app source, `Sprout-html/index.html` for the legacy single-file web prototype, `.claude/commands/` and `.claude/skills/` for narrow project workflows.
- Known fragile areas: budget math, month rollover behavior, persistence and restore, quick-entry routing and pending request flow, and cross-surface drift between web and iOS behavior.
- Important evidence/product constraints: `Sprout-iOS/` is source-only here and not a complete Xcode project, the iOS app is the higher-value surface, the web app remains the behavior reference, and Windows cannot validate SwiftUI runtime behavior.
- Runtime environments that matter: iOS simulator, iPhone device, and the web prototype in a browser.

## Git / Release Notes
- Preferred everyday flow:
  - `git st`
  - `git diff`
  - `git add .`
  - `git commit -m "..."`
  - `git push`
- Preferred promotion flow from `dev` to `main`:
  - `git checkout main`
  - `git pull --ff-only`
  - `git merge --ff-only dev`
  - `git push`
  - `git checkout dev`

## Project-Specific Instructions For The Next Agent
```text
Project: Sprout
Active repo path: C:\Dev\Sprout
GitHub remote: None
Stable branch: main
Working branch: dev

Important:
- Treat C:\Dev\Sprout as the source of truth.
- Do not work in stale copies unless explicitly asked.
- If Git is not already set up, bootstrap it using the repo standard in this file before major feature work.
- Use the standard workflow: investigate directly, fix root causes, audit adjacent risks, run checks, and handle Git when appropriate.
- Treat Sprout-iOS as the higher-value surface, but compare shared behavior against Sprout-html before declaring cross-surface work complete.
- Do not claim Xcode or SwiftUI runtime validation unless it actually happened on macOS/Xcode.
```
