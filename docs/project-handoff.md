## Project Identity
- Project name: `Sprout`
- Project type: `mixed workspace`
- Source-of-truth repo path: `C:\Dev\Sprout`
- Historical stale copy path: `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Sprout`
- GitHub remote: `https://github.com/Pulpers859/sprout.git`

## Repo State
- Stable branch: `main`
- Working branch: `main`
- Only permitted branch for normal work, commits, and pushes: `main`
- Side branches and pull requests are prohibited unless the user explicitly requests an exception in the current task.

## Agent workflow
- Inspect before assuming.
- Work in the source-of-truth repo only.
- Work directly on `main`; do not create, use, preserve, or push side branches.
- Do not open or use pull requests unless the user explicitly requests one in the current task.
- Start each new work session with `git fetch`.
- If the working tree is clean and `main` is checked out, pull with `git pull --ff-only` before editing.
- If the repo is dirty, inspect before deciding whether a pull is safe.
- Fix root causes, not surface symptoms.
- Run the checks that are realistically available in the current environment.
- After making code or documentation changes, commit them and push them to GitHub before handing off unless the user explicitly says not to.
- Report clearly what was committed and pushed to `main`, and any verification limits.

## PowerShell / terminal standard
- Do not globally pin every PowerShell session to this project.
- A dedicated desktop shortcut should exist:
  - `Sprout Claude Code`
- That shortcut should open directly in `C:\Dev\Sprout`.
- The shortcut should call `tools/Launch-Sprout-Claude.ps1` through PowerShell 7 when available, matching the Transform, Procedures, Recipes, and MeadEvil desktop launch pattern.
- Keep the launcher project-local and explicit; do not add hidden global startup behavior.

## Skill-first workflow
- Use `sprout-handoff` for fresh orientation.
- Use `sprout-context-compact` when reviving prior work or preparing a short handoff.
- Use `sprout-parallel-audit` for broad investigations that span multiple fragile areas.
- Use the focused skills for normal bug work: `budget-invariants`, `month-rollover-check`, `backup-persistence-check`, `quick-entry-path-check`, and `surface-drift-check`.
- Prefer the smallest skill set that fits the task.

## External-agent reconciliation
- Trigger this workflow whenever the user mentions prior work from another AI agent, machine, terminal, or conversation.
- Inspect every supplied transcript, export, screenshot, commit list, or claimed-fix summary.
- Compare each claim against current local files, local Git history, and GitHub `main`.
- Classify every claimed change as present, missing, partially landed, or overwritten.
- Complete that comparison before editing, rebasing, resetting, merging, or claiming the repo is synchronized.
- Decide whether to pull, rebase, merge, patch missing work, or preserve newer work only after reconciliation.

## Architecture notes
- Native app source: `Sprout-iOS/SproutApp/Sprout/Sprout/`
- Buildable iOS project: `Sprout-iOS/SproutApp/Sprout/Sprout.xcodeproj`
- Web prototype: `Sprout-html/index.html`
- Claude repo workflows: `.claude/commands/` and `.claude/skills/`
- Codex repo workflows: `.agents/skills/`

## Known fragile areas
- Budget math
- Month rollover behavior
- Persistence and restore
- Quick-entry routing and pending request flow
- Cross-surface drift between web and iOS

## Verification limits
- Windows can verify repo structure and web behavior.
- Windows cannot prove SwiftUI runtime behavior or Xcode-only build behavior.
