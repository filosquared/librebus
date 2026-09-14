# Native Librebus for macOS

The native Mac app shares the iOS SwiftUI screens, pastel dashboard cards, tabs,
Librus client, Keychain storage, and local cache. It requires macOS 13 or later.
No Python installation or Librebus server is needed to run it.

## Build

With full Xcode installed, run from the repository:

```sh
./tools/build-macos-native.sh
open dist/native/Librebus.app
```

Alternatively, open `ios/Librebus.xcodeproj`, choose the Librebus scheme and
**My Mac**, and run. Local command-line builds use ad-hoc signing; public
distribution requires your own Developer ID signing and notarization.

Drag `dist/native/Librebus.app` into Applications to install it. The older Python
Mac app and its build helper remain available, and the native build has its own
output directory so building it does not overwrite that app.

## Use

Sign in with the school-issued Synergia login, as on iOS. Email-based Konto
LIBRUS sign-in is not supported. The Mac has its own session and does not import
credentials from the iPhone or the older Python application.

Home, Grades, Schedule, Messages, and More use the same views as iOS. Homework
and Attendance are under More, while Messages is a main category. The Home
screen shows today's remaining lessons, the Schedule day dropdown opens lesson
details, and the gear button exposes language, app-name, and automatic-sync
settings. Resize the window as needed; press Command-R to sync. The window
opens at 680 × 820 points, with a 520 × 620 minimum.
Appearance can be set independently to System, Light, or Dark from Settings.

Credentials are saved in macOS Keychain. The cache is stored at
`~/Library/Application Support/Librebus/school-data.json`. Signing out clears
the native app's credentials and school-data cache.
