# Forge — Mac setup checklist

Run each command on its own line, in order. Nothing here needs a Firebase
project created on the VM — that happens on the Mac.

## 1. Install / update tooling

- `flutter --version`
- Confirm Flutter 3.47.7 / Dart 3.13.5 (or newer stable that still resolves
  this pubspec).

## 2. Firebase project (create once in the Firebase console)

- Create a Firebase project (name it `forge`, or as preferred).
- Enable Authentication: Email/Password provider ON.
- Enable Authentication: Google provider ON.
- Enable Firestore Database (production mode; rules are deployed in step 5).
- Enable Storage (default bucket).

## 3. Generate the real Firebase options (replaces the VM placeholder)

- `dart pub global activate flutterfire_cli`
- `flutterfire configure`
- Select the Firebase project created in step 2.
- Select platforms: android, ios (web optional).
- Confirm `lib/firebase_options.dart` is now real (no `REPLACE-ME` values).
- `lib/firebase_options.dart` stays in `.gitignore` and out of the zip.

## 4. Google sign-in — Android SHA-1

- `cd android`
- `./gradlew signingReport`
- Copy the debug SHA-1 (and release SHA-1 when a release keystore exists).
- In the Firebase console, open Project settings > Your apps > Android app.
- Add each SHA-1 fingerprint.
- Download the updated `google-services.json`.
- Place it at `android/app/google-services.json`.

## 5. Google sign-in — iOS

- In the Firebase console, open Project settings > Your apps > iOS app.
- Bundle ID must be `com.forge.app`.
- Download `GoogleService-Info.plist`.
- Place it at `ios/Runner/GoogleService-Info.plist`.
- Open `ios/Runner.xcworkspace` in Xcode at least once and confirm the
  file is in the Runner target.

## 6. Deploy rules

- `firebase deploy --only firestore:rules,storage`
- Verify in the console that the deployed rules match `firestore.rules`
  and `storage.rules` (owner-only under `users/{uid}/`).

## 7. App icon — nothing to do

- The launcher icons are already generated and committed:
  `android/app/src/main/res/mipmap-*/ic_launcher.png` and
  `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.
- They were built from `assets/icon/app_icon.png` (1024x1024, orange
  hammer striking anvil on black) with `dart run flutter_launcher_icons`.
- Re-run `dart run flutter_launcher_icons` only if the master icon changes.

## 8. First run

- `flutter clean`
- `flutter pub get`
- `flutter analyze`
- `flutter run`
- Sign in, complete profile setup, and confirm the 5 bottom-nav tabs
  (Today, Program, +, History, Progress) all open.

## 9. Distribute (later, after Alex tests the build himself)

- Do NOT distribute to any tester until Alex has tested the build
  himself and said it is good.
