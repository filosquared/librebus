# Librebus iOS client

This directory contains a small native SwiftUI client for Librebus. It embeds the existing Librebus web interface in `WKWebView`, so the Python server remains the source of truth for authentication and school data.

It is intentionally a client, not a Python server bundled into iOS. iOS does not provide the same background-server model as the macOS launcher, and a fully standalone iOS app would require porting the backend to a native service/API.

## Build with Xcode

1. Install the full Xcode application from the Mac App Store. Command Line Tools alone cannot compile or sign an iOS app.
2. Open `ios/Librebus.xcodeproj` in Xcode.
3. Select the `Librebus` target, choose your Apple Developer Team under **Signing & Capabilities**, and change the bundle identifier if needed.
4. The project already includes the three Swift source files and `Info.plist`.
5. Set the app's deployment target to iOS 16 or later if Xcode asks.
6. Choose an iPhone Simulator or a connected iPhone and press **Run**.

Once Xcode is installed and configured, a simulator build can also be started from the repository root with:

```bash
./tools/build-ios.sh
```

If you prefer to create a project manually, add the three files in `ios/Librebus/` to a new **iOS App** using **SwiftUI** and **Swift**:
   - `LibrebusApp.swift`
   - `ContentView.swift`
   - `LibrebusWebView.swift`
   Add this privacy description to the target's `Info.plist` if you connect to a server on your local network:

   `Privacy - Local Network Usage Description` — `Librebus connects to your school server on the local network.`


## Connect to a development server

The server normally listens only on the Mac itself. For testing from an iPhone on the same Wi-Fi network, start Librebus with a LAN listen address:

```bash
LIBREBUS_LISTEN_ADDRESS=0.0.0.0 python3 librusik.py --skip-wizard
```

Then enter the Mac's LAN address in the app, for example `http://192.168.1.20:7777`.

Plain HTTP is suitable only for temporary local testing. Use HTTPS for any server reachable outside your private network, because the app sends login credentials to the server.

## App Store readiness

Before distribution, configure an HTTPS deployment, a real bundle identifier, Apple signing, an app icon, privacy disclosures, and a production server URL. A signed `.ipa` cannot be generated from this checkout until full Xcode and an Apple signing identity are available. The helper defaults to an unsigned iOS Simulator build; device and archive builds require selecting a signing team in Xcode.
