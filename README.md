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
  Human support docs, handoff notes, and troubleshooting templates.
- `.agents/`
  Codex-local workflow skills for this repo.
- `.claude/`
  Claude-local commands, skills, and settings.

## Runtime vs support files

Runtime-critical work is concentrated in the two app folders above. Everything else in the repo is support material, workflow guidance, or local tooling.

- Keep `Sprout-html/sprout-firebase-config.local.js` local and untracked.
- Treat `.netlify/` as generated local output.
- Treat old Desktop/OneDrive copies as stale if they reappear; this repo is the active working copy.

## Verification notes

- Web behavior can be checked from this Windows workspace.
- iOS source and project structure can be reviewed here, but SwiftUI/Xcode runtime validation still needs macOS/Xcode.

## Git handoff expectation

- After making code or documentation changes, agents should commit them and push them to GitHub before handing off unless the user explicitly says not to.
- Agents should say clearly what was committed, what branch it was pushed on, and what could not be verified locally.
