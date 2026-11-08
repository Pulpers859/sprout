# Sprout

`C:\Dev\Sprout` is the live source-of-truth repo for this project.

## Product surfaces

- `Sprout-iOS/`
  Native SwiftUI app. The buildable project lives at `Sprout-iOS/SproutApp/Sprout/Sprout.xcodeproj`.
- `Sprout-html/`
  Web app. Runtime entry point is `Sprout-html/index.html`, with small modules for money, ledger/recurrence, and portable backups.

The iOS app is the higher-value surface. The web app follows the applicable iOS budget behavior; intentional differences are tracked in `docs/surface-drift.md`.

Both surfaces have three tabs: Personal and Grocery are monthly budgets, and
Holiday is a separate seasonal budget for tracking gifts per person. Holiday
spending is stored outside the monthly ledger and is never counted against
either monthly budget — structurally, not by filtering. Shared holiday logic
lives in `Sprout-html/holiday.mjs`, mirroring the Swift; holiday amounts are
integer cents on both sides, which `holiday.mjs` explains. Remaining
differences, and the places web is ahead of iOS, are listed in
`docs/surface-drift.md`.

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

## Deploying the web app

`.github/workflows/deploy-web.yml` publishes `Sprout-html/` to
https://sprout-budgeting.netlify.app/ on every push to `main` that touches the
web app. It runs `tools/netlify-build.sh` first, which runs the web test suite
and then writes `Sprout-html/sprout-firebase-config.js` from the environment.
A red suite fails the job before the deploy step, so it cannot reach the live
site.

**A push to `main` is a deploy.** There is no separate publish step.

Required repository secrets (Settings -> Secrets and variables -> Actions):

| Secret | What |
| --- | --- |
| `NETLIFY_AUTH_TOKEN` | Netlify personal access token (User settings -> Applications) |
| `NETLIFY_SITE_ID` | the site's API ID (Site configuration -> General) |
| `SPROUT_FIREBASE_CONFIG_JSON` | the whole Firebase web config as one JSON object |

`SPROUT_FIREBASE_CONFIG_JSON` is the contents of
`sprout-firebase-config.local.js` as JSON — the six keys from
`sprout-firebase-config.example.js`, no `window.SPROUT_FIREBASE =` wrapper and
no trailing semicolon:

```json
{"apiKey":"...","authDomain":"...","projectId":"...","storageBucket":"...","messagingSenderId":"...","appId":"..."}
```

The six `SPROUT_FIREBASE_*` variables are accepted individually instead, and
win if both are set. Either way the build fails and names what is missing
rather than publishing a site that loads and then cannot sign in.

The config file stays untracked and is generated at deploy time, so live
values never enter git and the secret-scanning hook still applies. Local
development is unchanged: keep using `sprout-firebase-config.local.js`.

`netlify.toml` covers the other direction — if the site is ever linked to the
repo in the Netlify UI, Netlify's own build uses the same script, and the six
values go in Netlify's environment variables instead.

Note for whoever wires this up: **Firebase console -> Authentication ->
Settings -> Authorized domains** must list the Netlify domain, or Google
sign-in is rejected there rather than here. This is already in place.

To run the same build locally before pushing:

```
SPROUT_FIREBASE_API_KEY=... SPROUT_FIREBASE_AUTH_DOMAIN=... \
SPROUT_FIREBASE_PROJECT_ID=... SPROUT_FIREBASE_STORAGE_BUCKET=... \
SPROUT_FIREBASE_MESSAGING_SENDER_ID=... SPROUT_FIREBASE_APP_ID=... \
bash tools/netlify-build.sh
```

## Secret scanning

`.githooks/pre-commit` blocks a commit that would introduce a live API key or
private key. **Git does not use it until the clone is pointed at that
directory**, which has to be done once per clone:

```
git config core.hooksPath .githooks
```

Until that runs, the hook file is inert. Live Firebase values belong in
`Sprout-html/sprout-firebase-config.local.js`, which is ignored; commit only
`sprout-firebase-config.example.js`.

## Verification notes

- Web behavior can be checked from this Windows workspace.
- iOS source and project structure can be reviewed here, but SwiftUI/Xcode runtime validation still needs macOS/Xcode.

## Web checks and hosting

Run the dependency-free regression suite with Node.js 20 or newer:

```powershell
node --test Sprout-html/money.test.mjs Sprout-html/ledger.test.mjs Sprout-html/holiday.test.mjs Sprout-html/backup.test.mjs Sprout-html/app.test.mjs
```

These tests cover money, rollover, recurrence, backups, and app integration with
fake Firebase/storage. They do not test live Google authentication or Firestore.
The existing generated Xcode CI remains unchanged; the web suite is run locally.

Serve the whole `Sprout-html/` directory over HTTP(S), including `money.mjs`,
`ledger.mjs`, and `backup.mjs` with a JavaScript MIME type. Opening `index.html`
directly as a file is not supported. Preserve your ignored Firebase configuration.
No deployment is performed by the test command.

Settings offers portable iOS-compatible backups. Web cache/cloud documents retain
dollar amounts (schema 1); exported backups use integer cents (schema 2). Import
previews and confirms replacement of the signed-in web account, saves an undo
copy on that device, and refuses malformed backups. The iOS app does not share
Firebase accounts: moving data between surfaces requires export/import.

## Installing on the iPhone

The owner has no Mac and no Apple Developer account. They install by
re-signing an unsigned `.ipa` with **Signulous**, on the phone. Xcode, a
cable, TestFlight and CI artifacts are all useless for this.

1. Push to `main`.
2. Run `.github/workflows/build-sideload-ipa.yml` (manual, no inputs).
3. Hand over the release link it prints:
   `https://github.com/Pulpers859/sprout/releases/download/sideload-<N>/Sprout.ipa`
   (`<N>` is the run number).
4. Open it in Safari on the phone, give it to Signulous, install.

Each Signulous install is signed under a different team, so anything tied to
the team (App Groups, iCloud, push) would not work; the app uses none of them
today. CI cannot see the phone: ask the owner how it behaves on device.

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
