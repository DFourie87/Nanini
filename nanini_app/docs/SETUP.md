# Running the app

## Prerequisites (already installed on this machine)
- Flutter SDK 3.47.4 (stable channel), installed at `C:\src\flutter`, added to the user PATH.
- Git 2.55, installed at `C:\Program Files\Git`, added to the user PATH.
- **New terminal windows** need to be opened for PATH changes to take effect (this session added it to the persistent user PATH via `setx`-equivalent, but the current shell needed it added manually).

Run `flutter doctor -v` to check status. As of this build: Chrome (web) and Windows (desktop, needs Visual Studio "Desktop development with C++" workload to actually build/run) are available as targets; Android is not (no Android SDK — install Android Studio to add it).

## First run
```bash
cd nanini_app
flutter pub get
flutter run -d chrome
```

This project has a `.claude/launch.json` entry (`nanini_app_web`) that runs the same command on port 8765 for use with the Claude Code browser preview.

To build an installable Android APK later: install Android Studio (adds the Android SDK), run `flutter doctor` to confirm, then `flutter build apk`.

## Verified working (this build)
- `flutter analyze`: 0 issues across the whole app.
- `flutter run -d chrome`: compiles and runs; Supabase connects successfully; hub screen renders all 7 module tiles with correct branding; navigated into the Hours module and confirmed the log form renders and is interactive.
- `flutter build apk --debug`: succeeds, produces `build/app/outputs/flutter-apk/app-debug.apk` (~165MB — debug builds are much larger than release; a release APK is typically 20-30MB).

## Android toolchain (installed this session)
- JDK 17 (Eclipse Temurin) at `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot`
- Android SDK at `C:\Android\sdk` (command-line tools, platform-tools, platforms 34/35/36, build-tools 28.0.3/35.0.0/36.0.0)
- `ANDROID_HOME`, `JAVA_HOME`, and PATH entries were set at the **user** environment level, so a fresh terminal picks them up automatically — no per-session setup needed going forward.
- Android Studio itself was not installed (not required for command-line builds) — install it later only if you want an emulator or the IDE.

## Installing the APK on a phone
Copy `build/app/outputs/flutter-apk/app-debug.apk` to an Android phone and open it (enable "Install unknown apps" for whatever app you use to open it, e.g. Files or a chat app). Or with a phone connected via USB with USB debugging on: `flutter install`.

## Building a release APK
```bash
cd nanini_app
flutter build apk --release
```
This produces a smaller, optimized APK at the same path. Without a configured signing key it falls back to Flutter's debug signing config (fine for installing on your own device; a real Play Store release needs a proper keystore — see the [Flutter signing docs](https://docs.flutter.dev/deployment/android#signing-the-app)).

## Configuration
The Supabase URL and publishable key are in `lib/core/supabase_client.dart` — they're the same ones the existing web app (`Nanini App/`) uses, so both clients read/write the same data. No `.env` file or secrets setup needed; the publishable key is meant to be client-side (Postgres Row Level Security is what actually protects the data).

## Manager mode
On first use, tapping "Manager" in any module prompts you to set a password (stored locally, hashed, via `shared_preferences`). This is a device-local setting — see `ARCHITECTURE.md` for why it differs from the original web app's per-module passwords.
