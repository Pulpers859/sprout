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
