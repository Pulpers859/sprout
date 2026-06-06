# Sprout iOS App

This folder contains the native SwiftUI migration for Sprout. The live buildable project is:

- `SproutApp/Sprout/Sprout.xcodeproj`

The app is meant to preserve the web prototype's core behavior while moving persistence and platform integration into native iOS:

- Personal and grocery budget tabs
- Budget editing
- Expenses and payments
- Quick-add from recent items
- Calendar drill-down for the current month
- Editable personal categories with emoji
- Monthly reset prompt
- On-device persistence

## What changed from the web app

- Firebase/Auth is removed.
- Data is saved locally to a JSON file in the app's Application Support directory.
- The structure is set up so you can later add App Intents, Control Center controls, Action Button hooks, and deep links.

## Project layout

- `SproutApp/Sprout/Sprout/`
  SwiftUI source, models, persistence, quick-entry routing, and assets.
- `SproutApp/Sprout/Sprout.xcodeproj`
  Buildable Xcode project checked into this repo.

## Xcode validation on your Mac

1. Open `SproutApp/Sprout/Sprout.xcodeproj` in Xcode.
2. Choose an iOS simulator or device.
3. Build and run.

The asset catalog already contains the current app icon set, so there is no separate icon import step anymore.

## Future native quick actions

The app already includes a custom URL route parser:

- `sprout://quick-add?tab=personal&mode=expense`
- `sprout://quick-add?tab=grocery&mode=payment`

That gives you a clean bridge for:

- App Intents
- Action Button launching
- Shortcuts
- Control Center or Lock Screen entry points later

It also now includes native `App Intents` scaffolding for:

- `Personal Expense`
- `Grocery Expense`
- `Personal Payment`
- `Grocery Payment`

These are the shortcuts you can expose to:

- the Shortcuts app
- Siri
- Spotlight
- the Action Button
- iPhone Back Tap, through a Shortcut the user assigns in Settings

Back Tap and other shortcut-driven launches now route into a dedicated compact quick-capture sheet instead of the standard full add form.

## Back Tap setup on iPhone

Once this is built in Xcode and installed on your phone:

1. Open the `Shortcuts` app.
2. Confirm Sprout shows the four quick-add actions above.
3. Create a Shortcut that runs the Sprout action you want.
4. Go to `Settings` > `Accessibility` > `Touch` > `Back Tap`.
5. Choose `Double Tap` or `Triple Tap`.
6. Assign the Shortcut you made.

That will let a back tap open Sprout straight into the matching quick-add sheet.

## Suggested next phase

After this compiles in Xcode, the next best move is:

1. Add an app URL scheme named `sprout`.
2. Test quick-add deep links.
3. Add an `AppIntents` target for `Add Expense` and `Add Payment`.
4. Add Control Center / Action Button support on top of those intents.

If you prefer, you can also keep the current App Intents in the main app target first and only split them into a dedicated target later.

## Verification note

This Windows workspace can review the source tree and project structure, but SwiftUI runtime behavior and Xcode-specific build validation still need to happen on macOS/Xcode.
