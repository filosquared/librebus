# Librebus Android app

The Android app is a native Kotlin/Jetpack Compose port of the local-first
Apple app. It connects directly to Librus Synergia and does not require a
Librebus server.

It includes:

- school-issued Synergia sign-in with an Android Keystore-protected password;
- local cached profile, grades, timetable, attendance, homework, and messages;
- a Home dashboard with today's remaining lessons and quick actions;
- grade filtering by first/second semester, tappable timetable lessons, and
  private notes/reminders;
- received/sent/announcements/notes message categories;
- Polish and English UI, System/Light/Dark appearance, and 45-minute sync.

## Build

Install Android Studio or the Android SDK, then set `ANDROID_HOME` (or
`ANDROID_SDK_ROOT`) to the SDK directory. Gradle also accepts a local,
machine-specific `local.properties` file; it is ignored by Git.

```bash
cd android
./gradlew :app:assembleDebug
```

The debug APK is written to
`app/build/outputs/apk/debug/app-debug.apk`. For a release build:

```bash
cd ..
./tools/build-android.sh
```

The release APK is intentionally unsigned in this repository. Sign it with
your own Android keystore before distributing it through Google Play or to
other devices.

## Data and privacy

The app uses the school-issued Synergia login, not the email login for Konto
LIBRUS. The password is encrypted with Android Keystore; cached school data
and private notes remain in the app's private storage. Sign out removes both.
Never commit real credentials, student data, or API responses.
