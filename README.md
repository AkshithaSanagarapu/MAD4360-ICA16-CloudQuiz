# ICA 16 — Class A Cloud Quiz (Graduate)

**Student Name:** Akshitha Sainath Sanagarapu  
**Student ID:** 003027780  
**Course:** MAD 4360 — Mobile App Development  
**Assignment:** In-Class Activity 16 — Class A (Graduate)

## Overview

I developed **Cloud Quiz**, a Flutter Android application that combines a general knowledge quiz with Firebase Authentication and Cloud Firestore. I built on the quiz flow I had developed for Activity 15 and extended it to support authenticated users, persistent cloud submissions, and verification of saved results.

The app loads 10 easy multiple-choice questions from the Open Trivia Database. After I answer the questions, it shows my final score and an answer review. I can then submit the completed round to Firestore and check that the result was actually saved on the server.

## Features I implemented

- **Firebase sign-in:** I connected the app to a separate Firebase project and enabled Email/Password authentication. I created test accounts for the activity.
- **10-question quiz:** I request exactly 10 easy General Knowledge multiple-choice questions from Open Trivia DB, using category 9.
- **Answer feedback and review:** The app shows whether an answer is correct, tracks the score, and displays a review when the round is finished.
- **Cloud score submission:** I save each completed round under the authenticated user's Firestore path, using a round-specific document ID.
- **Create-once behavior:** I use a transaction-based submission flow so retries target the same round document rather than intentionally creating a new result each time.
- **Server verification:** After submission, the app checks the stored document and shows a **Cloud verified** state when it confirms the saved result.
- **Recovery controls:** I included development controls for simulated acknowledgement loss and service errors to explore how the app handles uncertain submission outcomes.

## Technologies used

I used Flutter and Dart for the Android application, Firebase Authentication for sign-in, Cloud Firestore for storing results, and Open Trivia DB for the quiz questions. I tested the app on the Pixel 10 Android emulator.

**API endpoint:**

`https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple`

## Firebase and Firestore

I configured the application with my separate Firebase project, `mad4360-ica16-cloudquiz`, using FlutterFire. Each quiz attempt is stored at:

`users/{uid}/attempts/{roundId}`

The saved attempt contains these six fields:

- `schemaVersion`: `1`
- `variant`: `A`
- `categoryId`: `9`
- `questionCount`: `10`
- `correctCount`: the number of correct answers, from `0` to `10`
- `submittedAt`: a server-generated timestamp

I also configured Firestore security rules to restrict reads and creates to the authenticated owner, validate the allowed fields and values, and deny updates and deletes.

## What I tested

I ran the application on the Pixel 10 emulator, signed in with a Firebase test account, completed a full 10-question round, and submitted the result. My observed score was **3/10**. The app displayed **Cloud verified**, and I checked the corresponding Firestore document in the Firebase console. The saved document contained the expected six fields, including `correctCount: 3` and the server timestamp.

I also ran `flutter analyze`, which completed with **No issues found**, and built the release APK successfully using `flutter build apk --release`.

The graduate test plan also includes duplicate submissions, restart recovery, offline and simulated service errors, user ownership, concurrent same-ID writes, collision handling, and stale authentication responses. The successful cloud submission above is the result I directly verified; it should not be taken as evidence that every graduate fault scenario was executed.

## How to run the project

This project uses my Firebase configuration. To run it with a different Firebase project, enable Email/Password authentication and Firestore, configure the Android application with FlutterFire, and apply the Firestore rules in `firestore.rules`.

```bash
flutter pub get
flutter analyze
flutter run
```

To create the Android release APK:

```bash
flutter build apk --release
```

The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.

## Project files

- `lib/main.dart` — Flutter quiz, authentication, and cloud-submission flow
- `lib/firebase_options.dart` — Firebase app configuration
- `firestore.rules` — Firestore access and validation rules
- `pubspec.yaml` — Flutter dependencies
- `screenshots/` — application screenshots
- `ICA16_A_Sanagarapu_Akshitha.docx` — graduate report

## Reflection

This activity helped me understand why saving a score and confirming that it was saved are two different steps. A network interruption can leave the app uncertain even when a cloud write has succeeded. Using a stable round ID, validating the stored data, and checking Firestore after submission made the result more reliable than simply displaying a success message after a write request. It also showed me the importance of Firebase security rules for separating each user's data.
