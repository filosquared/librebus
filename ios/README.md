# Librebus iOS app

This Xcode project also builds the native [macOS app](../macos/README.md).
Both platforms share the SwiftUI screens and Librus client.

The iPhone app also embeds an [Apple Watch companion](../watchOS/README.md).
Use the `LibrebusWatch` scheme to run it on your paired Watch. Both targets need
the same signing team; the Watch receives cached data from iPhone, not from Mac.
Optional **More → Apple Watch → Lesson-ending alerts** sends the Watch a setting
to notify five minutes before each lesson ends, with the next lesson, room and
teacher. Allow notifications in the Watch app once. This uses Watch notifications,
not automatic app launches; see the [Watch guide](../watchOS/README.md).

The iOS target is a native, local-first app. It connects directly to Librus, presents grades, schedule, attendance, homework, and messages in SwiftUI, stores the Librus password in the iPhone Keychain, and caches school data in the app's private storage.

No Librebus server is required. The app needs an internet connection when it signs in or synchronizes with Librus; cached data remains available between syncs.

## Build and run

1. Open `ios/Librebus.xcodeproj` in Xcode.
2. Select the `Librebus` target and choose your Apple Developer Team under **Signing & Capabilities**.
3. Connect an iPhone running iOS 16 or later, or choose an iOS Simulator.
4. Press **Run**.

The repository helper builds an iOS Simulator app:

```bash
./tools/build-ios.sh
```

For a physical device, let Xcode manage signing and provisioning. The project uses the bundle identifier `com.filiplopes.Librebus`; change it if that identifier is already in use.

## Data and privacy

Sign in with the **school-issued Synergia login** (often digits with a suffix),
not the email used for Konto LIBRUS. Email-based Konto LIBRUS sign-in and
interactive verification are not implemented. A successful web login to Konto
LIBRUS does not validate the Synergia adapter. Never paste real credentials into
test fixtures.

The iOS adapter starts at Synergia's `loguj/portalRodzina` endpoint, requires the
redirected OAuth URL, checks the login JSON, and resolves `goTo` against
`https://api.librus.pl/`. URLSession manages cookies using their original domains
and paths. An HTTP 200 alone is not proof of a successful login.

Offline authentication checks (macOS with Xcode):

```bash
swiftc -module-cache-path /tmp/librebus-swift-cache ios/Librebus/Models.swift ios/Librebus/LibrusClient.swift tests/ios_auth_checks.swift -o /tmp/librebus-auth-checks
/tmp/librebus-auth-checks
```

Credentials are stored in the Keychain with device-only protection. Non-secret synchronized data is stored in the app's Application Support directory. Signing out deletes both the saved credentials and local cache.

The app talks to Librus over HTTPS. Its OAuth bootstrap differs from the legacy
Python implementation. Librus can change that flow or its response formats, so
the provider adapter may need maintenance as the upstream service evolves.
