# Sprout

`C:\Dev\Sprout` is the live source-of-truth repo for this project.

## Product surfaces

- `Sprout-iOS/`
  Native SwiftUI app. The buildable project lives at `Sprout-iOS/SproutApp/Sprout/Sprout.xcodeproj`.
- `Sprout-html/`
  Legacy single-file web prototype. Runtime entry point is `Sprout-html/index.html`.

The iOS app is the higher-value surface. The web app still matters as a behavior reference during the migration.

## Workspace layout

- `AGENTS.md`
  Shared working rules for AI agents in this repo.
- `CLAUDE.md`
  Claude-specific handoff entrypoint that mirrors the same source-of-truth assumptions.
- `docs/`
  Human support docs, including the repo handoff note and reusable templates.
- `.agents/`
  Codex-local workflow skills for this repo.
- `.claude/`
  Claude-local commands, skills, and settings.
- `tools/Launch-Sprout-Claude.ps1`
  PowerShell 7 launcher used by the desktop `Sprout Claude Code` shortcut.

## Runtime vs support files

Runtime-critical work is concentrated in the two app folders above. Everything else in the repo is support material, workflow guidance, or local tooling.

- Keep `Sprout-html/sprout-firebase-config.local.js` local and untracked.
- Treat `.netlify/` as generated local output.
- Treat old Desktop/OneDrive copies as stale if they reappear; this repo is the active working copy.

## Verification notes

- Web behavior can be checked from this Windows workspace.
- iOS source and project structure can be reviewed here, but SwiftUI/Xcode runtime validation still needs macOS/Xcode.

## Git handoff expectation

- All normal work happens directly on `main`. `main` is the only branch agents may use for editing, committing, and pushing.
- Agents must not create or use side branches and must not open or use pull requests unless the user explicitly requests an exception in the current task.
- Risky AI-agent experiments can use detached sandboxes via `docs/agent-sandbox-workflow.md`; final integration still happens on `main`.
- After making code or documentation changes, agents should commit them and push them to GitHub before handing off unless the user explicitly says not to.
- Agents should say clearly what was committed and pushed to `main`, and what could not be verified locally.

## Claude Code shortcut

The intended desktop shortcut is `Sprout Claude Code`. It should open PowerShell 7 in `C:\Dev\Sprout` and run:

```powershell
C:\Dev\Sprout\tools\Launch-Sprout-Claude.ps1
```

The launcher does not add global shell behavior. It only sets the working directory, checks for repo-local Claude memory, skills, and commands, then launches `claude`.

## External-agent reconciliation

When work from another agent, machine, terminal, or conversation is part of the context, agents must reconcile the supplied artifacts against local files, local Git history, and GitHub `main` before editing or claiming the repo is synchronized. Each claimed change must be reported as present, missing, partially landed, or overwritten. The full protocol is defined in `AGENTS.md`.
