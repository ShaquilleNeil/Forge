# Live Activity — iOS widget extension setup (Xcode, on your Mac)

The Dart side is done (`LiveActivityService` + the `live_activities`
plugin). What is left is the native target — a Widget Extension — which
only Xcode can create. The Swift source is already written:
`ios/ForgeLiveActivity/ForgeLiveActivity.swift` (+ its `Info.plist`).
Until this target exists, the Dart calls fail silently and iOS falls
back to the local notification + the in-app timer — nothing crashes.

## Steps

1. Open `ios/Runner.xcworkspace` in Xcode.
2. File → New → Target… → **Widget Extension** → Next.
   - Product Name: `ForgeLiveActivity`
   - "Embed in Application": **Runner**
   - Finish → **Activate** when Xcode asks.
3. Xcode creates template files inside the new `ForgeLiveActivity`
   folder. Delete its generated `.swift` file (and the template
   `Assets.xcassets` if you don't want it), then drag in the two files
   from `ios/ForgeLiveActivity/` — `ForgeLiveActivity.swift` and
   `Info.plist` — making sure **both are added to the
   `ForgeLiveActivity` target** (not Runner).
   - If Xcode asks about the Info.plist, choose Replace.
4. Set the extension target's deployment target to **iOS 16.1**:
   select the `ForgeLiveActivity` target → General → Minimum
   Deployments → iOS 16.1. (Live Activities need 16.1+; the main app
   can stay where it is.)
5. App Group — both targets, same id:
   - Select the **Runner** target → Signing & Capabilities → **+
     Capability** → **App Groups** → check (or create)
     `group.com.forge.app.forge`.
   - Select the **ForgeLiveActivity** target → do the same, checking
     the **same** `group.com.forge.app.forge`.
   - Xcode creates the entitlements files; nothing to edit by hand.
6. Push Notifications capability — **Runner target only**:
   Signing & Capabilities → + Capability → **Push Notifications**.
   (The extension does not get it.)
7. Confirm `NSSupportsLiveActivities` is `true` in both Info.plists —
   it is already in `ios/Runner/Info.plist` and in the extension's
   `Info.plist` provided here.
8. Build and run on a **real iPhone** (Live Activities do not reliably
   appear in the simulator below iOS 17; a real device is the test).

## Test

1. Start a workout, log a set — a rest starts.
2. Lock the phone: the Live Activity shows on the lock screen —
   exercise, next set, orange countdown.
3. On a Dynamic Island iPhone, long-press the island to expand it.
4. Press **+15s** in the app: the countdown jumps by 15 seconds.
5. Press **Skip rest** or finish the workout: the Live Activity ends.

If the Live Activity never appears: check that the App Group id is
identical in both targets, that the extension target built (Product →
Build, look for `ForgeLiveActivity.appex`), and that the phone is on
iOS 16.1+. The Dart side logs nothing — it fails silently by design,
so a missing activity always means the native target, not the Dart.
