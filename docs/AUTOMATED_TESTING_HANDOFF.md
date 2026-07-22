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
