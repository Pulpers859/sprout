## Project Identity
- Project name: `Sprout`
- Project type: `mixed workspace`
- Source-of-truth repo path: `C:\Dev\Sprout`
- Historical stale copy path: `C:\Users\Patrick's Computer\OneDrive - WV School of Osteopathic Medicine\Desktop\Sprout`
- GitHub remote: `https://github.com/Pulpers859/sprout.git`

## Repo State
- Stable branch: `main`
- Working branch: `main`
- Expected default branch for normal work: `main`

## Agent workflow
- Inspect before assuming.
- Work in the source-of-truth repo only.
- Start each new work session with `git fetch`.
- If the working tree is clean and the branch is correct, pull with `git pull --ff-only` before editing.
- If the repo is dirty, inspect before deciding whether a pull is safe.
- Fix root causes, not surface symptoms.
- Run the checks that are realistically available in the current environment.
- After making code or documentation changes, commit them and push them to GitHub before handing off unless the user explicitly says not to.
- Report clearly what was committed, what branch was pushed, and any verification limits.

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
