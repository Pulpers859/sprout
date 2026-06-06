# AI Project Handoff Template

Use this as a reusable handoff template for local app repos on this Windows machine.

## Source of truth
- Keep the active repo outside OneDrive.
- Preferred location: `C:\Dev\<ProjectName>`
- Treat Desktop/OneDrive copies as archival or stale unless explicitly promoted.

## Git baseline
- Local Git repo in the real project folder
- Focused `.gitignore`
- `.gitattributes` with LF rules for code files
- Repo-local config:
  - `core.autocrlf=false`
  - `core.eol=lf`
  - `pull.ff=only`
  - `fetch.prune=true`

## Agent baseline
- Confirm repo path, branch, cleanliness, remote, and fetch state before work.
- Pull with `git pull --ff-only` only when the working tree is clean and the intended branch is checked out.
- Prefer direct code fixes and adjacent-risk audits over surface patches.
- Handle normal Git work from chat when appropriate.
- After making code or documentation changes, commit them and push them before handoff unless the user explicitly says not to.

## Migration baseline
If a project still lives in OneDrive/Desktop:

1. Confirm the real project root.
2. Move or copy the repo to `C:\Dev\<ProjectName>`.
3. Verify Git state, remote, hooks, and repo-local config in the new location.
4. Retire the old copy only after the new one is confirmed good.
