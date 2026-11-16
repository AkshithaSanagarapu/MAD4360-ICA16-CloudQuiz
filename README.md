# ICA 16 — Class A Cloud Quiz (Graduate)

Student: Akshitha Sainath Sanagarapu | ID: 003027780

This project adapts the user's Activity 15 Flutter quiz to a 10-question Firebase-backed Class A quiz. **This ZIP is source code, not a tested APK or proof of deployed cloud tests.**

## Required local setup

1. Install Flutter, Android SDK, Firebase CLI and FlutterFire CLI.
2. Create a **separate** Firebase project; enable Email/Password and create two test users through the console.
3. Create Cloud Firestore (Standard, Native mode), then publish `firestore.rules` to the correct project (`firebase deploy --only firestore:rules --project YOUR_PROJECT_ID`). Never deploy permissive rules.
4. From this folder run `flutter pub get`, then `flutterfire configure` and select this Android application and your project. This generates the real `lib/firebase_options.dart` (the ZIP includes only a placeholder).
5. Run `flutter run` to test, then `flutter build apk --release`. Copy `build/app/outputs/flutter-apk/app-release.apk` to `ICA16_A_Sanagarapu_Akshitha.apk`.
6. Complete T01–T12 and G01–G03 with real deployed-cloud evidence; fill the DOCX and add screenshots.
7. Push source, deployed rules, README and commit hash to GitHub. Submit APK, repository URL and completed DOCX.

## API
`https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple`

## Cloud path and schema
`users/{authenticatedUid}/attempts/{roundId}`. Exactly six fields: `schemaVersion=1`, `variant=A`, `categoryId=9`, `questionCount=10`, `correctCount=0..10`, and server `submittedAt`. Create-once transaction; server-only verification.

## Important current limitations
- Firebase configuration, compilation, deployment, device testing and cloud test evidence have **not** been performed in this environment.
- The development fault toggles implement acknowledgement loss, unavailable and resource-exhausted simulations; other required invalid-input, two-client and stale-response test harnesses are not supplied.
- A process restart does not currently restore the prior round ID automatically; T07 needs an implementation extension or an authorized server-read test harness.
- Transaction timeout is not cancellation; a pending transaction must be allowed to settle before retrying. Additional hardening is needed for rigorous T08–T12/G01–G03 compliance.
- `pubspec.lock` originated from Activity 15 and must be refreshed by `flutter pub get`.

## Security
Never commit passwords, private keys, tokens or service-account files. Firebase client configuration is not a secret; access is enforced by authentication and Firestore rules.
