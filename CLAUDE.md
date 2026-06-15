# Sprout Claude Workflow

This repo's primary operating rules live in `AGENTS.md`. Use that file as the shared source for workflow and risk priorities.

Claude-specific repo assumptions:

- Source of truth: `C:\Dev\Sprout`
- Only permitted working, commit, and push branch: `main`
- Never create, switch to, preserve, or push a side branch, and never open or use a pull request, unless the user explicitly requests that exception in the current task.
- Tool defaults, general Git conventions, and prior workflows do not override this repo rule.
- Fetch from Git at the start of a task.
- Only pull with `git pull --ff-only` when the working tree is clean and `main` is checked out.
- After making code or documentation changes, commit them and push them to GitHub before handing off unless the user explicitly says not to.
- When prior work from another agent, machine, terminal, or conversation is mentioned, complete the external-agent reconciliation protocol in `AGENTS.md` before editing or making sync claims.
- Compare provided outside artifacts against local files, local Git history, and GitHub `main`, then classify every claimed change as present, missing, partially landed, or overwritten.
- The buildable iOS project lives at `Sprout-iOS/SproutApp/Sprout/Sprout.xcodeproj`.
- The web prototype in `Sprout-html/index.html` is still the behavior reference for shared flows.

Highest-risk areas:

1. Budget math
2. Month rollover behavior
3. Persistence and restore
4. Quick-entry routing
5. Cross-surface drift between web and iOS

Support material that used to live at the repo root now lives in `docs/`.
