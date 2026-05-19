# Sprout iOS Migration Scaffold

This folder is a native SwiftUI rewrite scaffold for Sprout that preserves the current web app's core behavior:

- Personal and grocery budget tabs
- Budget editing
- Expenses and payments
- Quick-add from recent items
- Calendar drill-down for the current month
- Editable personal categories with emoji
- Monthly reset prompt
- On-device persistence

## Important honesty

This is the native Swift source tree, not a complete `.xcodeproj`.

That is intentional. Generating Xcode project files by hand is brittle, and it is much safer for you to create the app shell in Xcode on your Mac and then drop these source files in.

## What changed from the web app

- Firebase/Auth is removed.
- Data is saved locally to a JSON file in the app's Application Support directory.
- The structure is set up so you can later add App Intents, Control Center controls, Action Button hooks, and deep links.

## Xcode setup on your Mac

1. Open Xcode.
2. Create a new iOS app project named `Sprout`.
3. Choose:
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Minimum target: `iOS 17` or newer
4. Close Xcode's generated `ContentView.swift` and `SproutApp.swift`.
5. Copy everything from `Sprout-iOS/Sprout/` into your Xcode project's `Sprout/` folder.
6. In Xcode, add the copied files to the app target if prompted.
7. Add `icon-180.png` as the starting point for your app icon set.
8. Build and run on the simulator or your iPhone.

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
