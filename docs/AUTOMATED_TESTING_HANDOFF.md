# Automated Testing Handoff

This repository is configured by `.swift-automation.json` using schema version 1.

## Repository Contract

- App: Sprout
- Project type: xcode
- Platform: ios
- Workflow mode: generate
- Default branch: main
- Physical device required for final product validation: True

## Workflows

- `.github/workflows/automation-xcode.yml`

## Live AI Surfaces

- Live AI validation is disabled.

## Commands And Secrets

- Xcode: `xcodebuild -project Sprout.xcodeproj -scheme Sprout test`

- Required provider secret: No provider secret is configured.

## Evidence Checkpoint

- Repository commit when this handoff was rendered: `0da5aeac9ddfa6ffa77de84835047b59b89ba77c`
- Local profile validation: passed.
- Latest GitHub Actions result, observed HTTP-call count, and physical-device result: not recorded by the installer; verify and update after execution.

Live jobs are manual, require the exact confirmation phrase, and depend on the deterministic prerequisite. `maxHttpCalls` is a declared budget and is only enforced when the feature harness reads `SWIFT_AUTOMATION_MAX_HTTP_CALLS` or independently caps attempts. Artifacts must be redacted and must never contain API keys or private user media.

## Agent Instructions

1. Read `.swift-automation.json` before changing workflows.
2. Run deterministic tests before any paid API workflow.
3. Keep each paid feature in its own `run_live_<surface>` job.
4. Never print or persist secret values.
5. Report what CI proves separately from what still needs Xcode on a physical Apple device.

## Verified Execution Evidence

Appended manually after real runs (the installer regenerates the sections above; keep this section when regenerating).

- **Latest green run:** GitHub Actions run `29887254452` on commit `1ce070f`, workflow `Xcode Test`, `macos-latest`.
- **Toolchain observed on runner:** Xcode 26.5, iPhoneSimulator 26.5 SDK, simulator `iPhone 17`.
- **Result:** `** TEST SUCCEEDED **`. Swift Testing reported `Test run with 64 tests in 1 suite passed`. The zero-test guard matched that line; the lone `Executed 0 tests` entry is the empty XCTest suite (this target has no XCTest cases) and correctly does not satisfy the `[1-9]` guard.
- **Money is stored as integer cents (`MoneyAmount`), schema v2.** Legacy v1/unversioned files (Double dollars) migrate to cents on load and are re-persisted at v2. Migration is covered by tests (`legacyV1DollarsMigrateToExactCents`, `v2FileRoundTripsExactCents`).

### What this CI proves
- The full app (SwiftUI + models + store) compiles for the iOS Simulator on real Xcode, and the `SproutTests` Swift Testing suite executes and passes on a booted simulator. Every push to `main` and every PR re-verifies this, and the job fails if zero tests are discovered.

### What it does NOT prove (still needs a physical Apple device)
- On-device persistence/Keychain/file-protection behavior, App Intents / `sprout://` quick-add from Shortcuts and the widget, haptics, and real UI. `physicalDeviceRequired` is `true` for a reason: green CI is necessary, not sufficient, for release.

### Known limitations / follow-ups
- **Simulator device name is pinned** (`iPhone 17`). When GitHub bumps the `macos-latest` image to a newer device lineup, update `xcode.destination` in `.swift-automation.json` and regenerate. A runtime "newest available iPhone" resolver in the kit would remove this maintenance step and is the recommended next hardening.
- **Failure-only diagnostics upload** (`xcode.log`, `xcode-result.xcresult`) was corrected in the kit (paths are no longer literal-quoted inside the block list) but has only been exercised on green runs here; confirm the artifact appears on the next genuinely failing run.
