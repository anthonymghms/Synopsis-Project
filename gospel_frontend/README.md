# Gospel Topics

The website, Android app, and iOS app use the same Flutter routes, Firebase authentication and accounts, Flask API, and reader preferences.

## Routes and presentation

The public homepage is at `/`. Its collection cards open `/topics`, `/topics?dataset=miracles`, and `/topics?dataset=parables` through the existing sign-in and membership checks. Browser bookmarks use Flutter hash routes, for example `/#/topics?dataset=parables`. Historic table bookmarks with query parameters on `/` still work. The homepage comparison preview loads up to three real rows from the shared Harmony cache after reading access is verified.

The shared visual definitions and responsive photograph are in `lib/study_theme.dart`. The homepage is in `lib/study_home.dart`. `TopicListScreen`, `HarmonyTable`, `TopicDetailScreen`, and `ReferenceViewerPage` retain their existing controllers and API cache. Compact layouts stack the homepage cards, keep table columns horizontally scrollable, and provide expandable reading controls.

The table language follows the Bible by default. Selecting a specific table language adds `tableLocale` to study links and saves the choice in the account's optional `tableLanguageOverride` preference. Publish the checked-in Firestore rules alongside the release to enable cross-device saving of that preference. Existing profiles need no migration.

## Run locally

Use Flutter 3.47.2, the SDK used for this redesign. Run the following commands from `gospel_frontend`.

```sh
flutter pub get
flutter doctor -v
```

To use the local Flask backend, start `python3 app.py` from the repository root in another terminal with the existing Python dependencies and backend Firebase credentials. Then start the website.

```sh
flutter run -d chrome --web-port 8760 --dart-define=API_BASE_URL=http://127.0.0.1:8010
```

To use the hosted API, run the same command with `--dart-define=API_BASE_URL=https://paragospels.com/api` if your web development origin is allowed by the backend. The production website uses the same-origin `/api` proxy.

## Run on Android or iOS

Start an Android emulator, start an iOS simulator, or connect a device. List the connected targets, then run the shared app and choose the target when prompted.

```sh
flutter devices
flutter run --dart-define=API_BASE_URL=https://paragospels.com/api
```

To select a particular device, pass `-d` followed by its ID from `flutter devices`. Android development requires a JDK 17 or later and an Android SDK compatible with Flutter 3.47.2. On a Mac, iOS development requires Xcode with the iOS platform installed and CocoaPods for the existing Firebase plugins. The iOS deployment target is 15.0. To install on a physical iPhone, select the development team in `ios/Runner.xcworkspace`.

The native API URL must be absolute. Use an accessible HTTPS staging backend when testing local changes on a phone. Debug builds default to the development machine's loopback address, which points back to the device when run on a physical phone.

## Build releases

```sh
flutter build web --release --dart-define=API_BASE_URL=/api --pwa-strategy=none
flutter build appbundle --release --dart-define=API_BASE_URL=https://paragospels.com/api
flutter build ios --release --no-codesign --dart-define=API_BASE_URL=https://paragospels.com/api
```

The website is written to `build/web`. Store distribution requires the publisher's signing credentials. Provide `android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` to sign the Android bundle with an upload key. Use an absolute keystore path. Without this file, Android uses the debug key for local testing. After configuring Apple distribution signing, run `flutter build ipa --release --dart-define=API_BASE_URL=https://paragospels.com/api` to archive the iOS app.

The checked-in Firebase client options target project `synopsis-224b0` on all three platforms. Its registered Android ID is `com.example.gospel_frontend` and iOS bundle ID is `com.example.gospelFrontend`. A new store identifier requires a corresponding client registration in that same project and matching client options. Firebase Admin credentials belong only on the Flask host.

## Verification

```sh
flutter analyze
flutter test
flutter test --platform chrome test/browser/topics_table_browser.dart test/browser/dataset_history_browser.dart
```

The release passed static analysis, 343 Flutter tests, four Chrome history/printing/link tests, and 243 backend and rules tests with a local Firestore emulator. A separate Chrome run against local Firebase Authentication, Firestore, and Flask verified email sign-in, loading protected Harmony content, denial of a direct admin link for a subscribed reader, and sign-out followed by refreshing a protected bookmark.

On the redesign host (Flutter 3.47.2, Xcode 26.2), the shared Dart application compiled to ARM64 release code for Android and iOS. The Android print bridge compiled with Kotlin 2.2.20 and JDK 17. The iOS bridge passed the Swift compiler's UIKit type check, and Xcode compiled the Firebase Authentication and Cloud Firestore pods for release. APK and App Bundle packaging still require an Android SDK installation with accepted licenses. Xcode requires its matching iOS platform component for an installable app. The asset compiler reported no installed iOS simulator runtime. Install the platform in **Xcode → Settings → Components**, then rerun the native build commands above. Physical-device behavior still needs verification.

CSV uses the browser download flow or the native file saver. Print/PDF uses the browser print dialog, Android Print, or the iOS print sheet. Each renders all matching rows with the selected Gospel columns. CSV retains its administrator-only check.
