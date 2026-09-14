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

- **Latest green run:** GitHub Actions run `34847120980` (run number 16) on commit `17ff900`, workflow `Xcode Test`, `macos-latest`.
- **Toolchain observed on runner:** `macos-latest` image with the pinned `iPhone 17` simulator; the runtime preflight found an available iOS runtime and did not need to download one.
- **Result:** `** TEST SUCCEEDED **`. Swift Testing reported `Test run with 85 tests in 1 suite passed after 14.034 seconds`. The zero-test guard matched that line.
- **Previous green run for reference:** run `29887254452` on commit `1ce070f`, 64 tests.
- **The `sprout://` URL scheme is now declared in the built bundle.** Before commit `f39c2ac` no `CFBundleURLTypes` entry existed, so iOS never routed `sprout://quick-add` to the app and `ContentView.onOpenURL` could not fire — the deep-link half of the quick-entry path was inert. `Sprout-Info.plist` (kept outside the `Sprout/` synchronized group so Xcode cannot also copy it in as a resource) declares it, and `theQuickAddSchemeIsDeclaredInTheBundle` reads `CFBundleURLTypes` back out of `Bundle.main` on the simulator. That test passing is what proves the plist actually merged, not just that the diff looked right.
- **Amount text round-trips in non-`.` decimal locales.** `SproutMoneyText` takes an injectable locale and is asserted across en_US, de_DE, fr_FR, pt_BR, ja_JP and en_IN, because the runner's own locale (en_US) is the one place the original corruption never reproduced.
- **Money is stored as integer cents (`MoneyAmount`), schema v2.** Legacy v1/unversioned files (Double dollars) migrate to cents on load and are re-persisted at v2. Migration is covered by tests (`legacyV1DollarsMigrateToExactCents`, `v2FileRoundTripsExactCents`).

### What this CI proves
- The full app (SwiftUI + models + store) compiles for the iOS Simulator on real Xcode, and the `SproutTests` Swift Testing suite executes and passes on a booted simulator. Every push to `main` and every PR re-verifies this, and the job fails if zero tests are discovered.

### What it does NOT prove (still needs a physical Apple device)
- On-device persistence and file-protection behavior (`.completeFileProtectionUnlessOpen` is a no-op on the simulator), App Intents invoked from Shortcuts or Siri, actually *opening* a `sprout://quick-add` link from another app, haptics, and real UI including Dynamic Type and VoiceOver. CI proves the scheme is **declared**; it does not prove a launch through it. There is no widget target in this project, despite an earlier version of this note implying one. `physicalDeviceRequired` is `true` for a reason: green CI is necessary, not sufficient, for release.

### Known limitations / follow-ups
- **Simulator device name is pinned** (`iPhone 17`). When GitHub bumps the `macos-latest` image to a newer device lineup, update `xcode.destination` in `.swift-automation.json` and regenerate. A runtime "newest available iPhone" resolver in the kit would remove this maintenance step and is the recommended next hardening.
- ~~**Failure-only diagnostics upload** has only been exercised on green runs; confirm the artifact appears on the next genuinely failing run.~~ **Closed.** Run `34846056675` failed genuinely (three assertion failures, exit code 65) and the upload behaved correctly: `xcode-diagnostics` uploaded with 1542 files, 56,022,830 bytes, artifact ID `10347498764`. The complementary case is also confirmed — on green run `34847120980` the "Upload Xcode diagnostics" step reports `skipped`, so it really is failure-only rather than always-on.
- **Test-host coupling is a live hazard for tests touching `UserDefaults.standard`.** The suite runs with `TEST_HOST` set to the real app, whose `ContentView` observes `UserDefaults.didChangeNotification` and consumes the pending quick-entry key the moment anything writes it. A test using the shared suite therefore races the app it runs inside; `QuickEntryRequestStore` takes an injectable suite for this reason. Any future test writing app-observed defaults must do the same.
