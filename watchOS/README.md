# Librebus for Apple Watch

A native SwiftUI companion for **watchOS 9 or later**, fed by Librebus on its
paired iPhone (iOS 16 or later). No Librebus server, Watch login or iCloud setup.

## Install from Xcode

1. Open `ios/Librebus.xcodeproj` in full Xcode with watchOS platform support installed.
2. Under Signing & Capabilities, choose the **same development team** for
   `Librebus` and `LibrebusWatch`. If you customize identifiers, keep the Watch
   identifier prefixed by the phone identifier and update
   `WKCompanionAppBundleIdentifier` in `watchOS/LibrebusWatch/Info.plist` to match.
3. Select the **Librebus** scheme and your iPhone, then Run to install the updated
   phone app. Sign in on the phone and refresh school data.
4. Select the **LibrebusWatch** scheme and the Apple Watch paired with that
   iPhone, then Run. Enable Developer Mode if Xcode requests it.
5. Open both apps. On the phone, **More → Apple Watch → Send latest data to Watch**
   queues its saved snapshot. On Watch, **Get iPhone data** requests the latest
   saved phone data; it does not trigger a new Librus login or server refresh.

The iPhone build embeds `LibrebusWatch.app`. It can also appear under Available
Apps in Apple's Watch app; install it there if automatic installation is off.
The Mac target does not embed or directly feed the Watch app.
Sharing an Apple Account alone does not add Mac/iCloud syncing.

## What is included

- Current/next non-cancelled lesson, room and substitution indicators.
- Dated weekly timetable, including cancelled lessons.
- Up to 20 recent grades and 12 upcoming homework items, with short details.
- Per-section last-successful-refresh times and an older-data warning.
- An offline snapshot retained between launches.
- Waiting, unreachable-iPhone, signed-out and update-required states.
- Optional lesson-ending notifications with a custom next-lesson card.

School lesson times use Europe/Warsaw, including daylight saving changes.
Lessons are anchored to the requested calendar week: an old Monday never rolls
into a later Monday. Older phone caches without that date need one successful
timetable refresh before they can be sent to Watch.

## Five-minute lesson alerts

Install the updated **iPhone and Watch apps**, then enable **More → Apple Watch →
Lesson-ending alerts** on iPhone. Open Librebus on Watch and tap **Allow
notifications** if prompted by the Lesson alerts section. The setting is off by
default and is saved on the iPhone.

The alert fires **five minutes before the current lesson ends**, not five minutes
before the next lesson starts. It says “Lesson ending in 5 mins” and shows the
next non-cancelled lesson that day, its room and teacher. The last lesson says
“No more lessons today.” Missing room/teacher information is marked unavailable.
Cancelled lessons and activities lasting five minutes or less do not produce
alerts. The next lesson's card also shows its start time.

watchOS presents a notification, **not a forced app launch**. The custom Watch
notification interface contains the lesson card; tapping it opens the card in
Librebus. Notification settings, Focus, wrist/lock state and the OS control
whether you see/hear an alert immediately. No critical-alert bypass is used.

After sync and permission, reminders are scheduled locally on Watch, so the
iPhone need not remain nearby. The nearest 48 upcoming reminders from the saved
week are scheduled, with no repeating stale-week alerts. A refresh replaces
changed reminders. An incomplete/truncated timetable is not used for reminders.
Open the phone and refresh regularly to pick up timetable changes and new weeks.

Turning the toggle off or signing out clears this feature's pending and delivered
Watch notifications **after the Watch receives that update**. An offline Watch
can still show previously scheduled alerts until it reconnects.

## Sync and privacy

The phone uses WatchConnectivity application context for **latest state**, not
a growing transfer queue. Delivery is scheduled by the OS and is not guaranteed
to be immediate. A reachable Watch can request the phone's in-memory snapshot.
Open the phone and refresh there to fetch newly published school data.

The wire format contains only a first name, lesson summaries, grade summaries,
short homework text, timestamps and opaque sync identifiers. **Lesson teacher
names are also included only while lesson alerts are enabled**, including in
notification content. It contains no passwords, usernames, cookies, provider
tokens, messages or API responses. Payloads are bounded to 48 KB, with trimming
reported on the Watch.
The Watch cache is atomically written, protected until first device unlock, and
excluded from backup. There is no direct Watch network client.

Signing out on iPhone queues a data-free snapshot. The Watch replaces its cache
when that update arrives; **an offline Watch cannot be remotely erased until it
reconnects**. Revision watermarks prevent delayed messages from undoing sign-out.
Different account sessions reset Watch navigation, and late phone refreshes
cannot restore a signed-out account.

This version has no complications, widgets, remote push alerts, background
Librus polling, standalone Watch sign-in, or Mac/iCloud synchronization.

## Build and offline checks

```sh
./tools/build-watch.sh       # Watch simulator build
./tools/build-ios.sh         # iPhone build, including the Watch companion
./tools/test-native.sh       # synthetic snapshot/cache, auth and lifecycle tests
```

Override `DESTINATION`/`CONFIGURATION` for a specific simulator or device. Device
installation requires valid signing for both targets. An unsigned build is a
compile/bundle check, not an installable release.

Xcode Canvas previews in `WatchHomeView.swift` cover waiting and synthetic loaded
states without accessing credentials or making network calls. Verify on a
small Watch and with larger text before distribution.

## Device acceptance checks

Apple recommends [physical iPhone/Watch testing for WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity).
Simulator builds and offline tests alone do not prove paired-device delivery.

1. Refresh on iPhone; verify the Watch's timetable, grades, homework and dates.
2. Make the phone unavailable, reopen Watch, and verify saved data stays readable
   with its original timestamps and a clear connection status.
3. Reconnect, refresh on iPhone and request data on Watch; verify new values arrive.
4. Sign out on iPhone; verify the Watch clears after delivery and stays cleared
   after relaunch. Repeat with the Watch offline, then reconnect.
5. Check a cancelled lesson, a substitution, an empty timetable, expired homework,
   week rollover and an account change.
6. Enable lesson-ending alerts, allow Watch notifications, and verify delivery
   five minutes before a real lesson ends. Check the next lesson, room and teacher.
7. Disable the setting, sync to Watch, and confirm that pending alerts are removed.
   Repeat with notification permission denied and after an account sign-out.

## Code map

- `ios/Shared/WatchSnapshot.swift`: versioned provider-neutral wire data and dates.
- `ios/Shared/WatchSnapshotBuilder.swift`: privacy projection and payload limits.
- `ios/Shared/LessonReminder.swift`: deterministic lesson-ending reminder plan.
- `watchOS/LibrebusWatch/WatchLessonAlerts.swift`: local notification scheduling.
- `watchOS/LibrebusWatch/LessonReminderView.swift`: Watch notification/card UI.
- `ios/Librebus/PhoneWatchSync.swift`: iPhone transport and status section.
- `watchOS/LibrebusWatch/WatchSchoolStore.swift`: Watch delivery and request state.
- `watchOS/LibrebusWatch/WatchSnapshotCache.swift`: protected offline persistence.
- `watchOS/LibrebusWatch/WatchHomeView.swift`, `WatchDetailViews.swift`: watchOS UI.
