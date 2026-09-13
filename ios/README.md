# Librebus iOS app

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

Credentials are stored in the Keychain with device-only protection. Non-secret synchronized data is stored in the app's Application Support directory. Signing out deletes both the saved credentials and local cache.

The app talks to Librus over HTTPS using the same public OAuth/API flow as the Python implementation. Librus can change that flow or its response formats, so the provider adapter may need maintenance as the upstream service evolves.
