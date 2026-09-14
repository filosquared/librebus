#if os(iOS)
import SwiftUI
import WatchConnectivity

@MainActor
final class PhoneWatchSync: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "Checking Apple Watch…"
    @Published private(set) var lessonAlertsEnabled = UserDefaults.standard.bool(forKey: "watchLessonAlertsEnabled")
    private var schoolData = CachedSchoolData.empty
    private var signedIn = false
    private var accountID = ""
    private var latest: Data?
    private var revision: UInt64
    private let streamID: String
    private let revisionKey = "watchSnapshotRevision"

    override init() {
        streamID = UserDefaults.standard.string(forKey: "watchSnapshotStream") ?? UUID().uuidString
        revision = UInt64(UserDefaults.standard.string(forKey: "watchSnapshotRevision") ?? "0") ?? 0
        super.init()
        UserDefaults.standard.set(streamID, forKey: "watchSnapshotStream")
        guard WCSession.isSupported() else {
            status = "Apple Watch is not supported on this device."
            return
        }
        let session = WCSession.default
        if let previous = session.applicationContext[WatchSnapshot.contextKey] as? Data,
           let snapshot = try? WatchSnapshot.decode(previous) {
            revision = max(revision, snapshot.revision)
        }
        session.delegate = self
        session.activate()
    }

    func publish(_ data: CachedSchoolData, signedIn: Bool, accountID: String) {
        schoolData = signedIn ? data : .empty
        self.signedIn = signedIn
        self.accountID = accountID
        var snapshot = WatchSnapshotBuilder.make(from: schoolData, signedIn: signedIn, lessonAlertsEnabled: lessonAlertsEnabled)
        revision += 1
        UserDefaults.standard.set(String(revision), forKey: revisionKey)
        snapshot.revision = revision
        snapshot.streamID = streamID
        snapshot.accountID = signedIn ? accountID : ""
        do {
            latest = try snapshot.encoded()
            sendLatest()
        } catch {
            // Never log the payload: it contains school data.
            latest = nil
            status = "Could not prepare Watch data. Try syncing again."
        }
    }

    func setLessonAlertsEnabled(_ enabled: Bool) {
        guard enabled != lessonAlertsEnabled else { return }
        lessonAlertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "watchLessonAlertsEnabled")
        publish(schoolData, signedIn: signedIn, accountID: accountID)
    }

    func sendLatest() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired else { status = "Pair an Apple Watch with this iPhone."; return }
        guard session.isWatchAppInstalled else { status = "Install Librebus using the iPhone’s Watch app."; return }
        guard let latest else { return }
        do {
            // Latest-state transport works while the counterpart is unreachable.
            try session.updateApplicationContext([WatchSnapshot.contextKey: latest])
            status = "Latest snapshot queued for Apple Watch. Delivery is managed by watchOS."
        } catch {
            status = "Watch sync could not be queued. Open both apps and try again."
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if error != nil { self.status = "Watch connection unavailable. Open both apps and try again." }
            else { self.sendLatest() }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendLatest() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let wantsSnapshot = message[WatchSnapshot.requestKey] as? Bool == true
        Task { @MainActor in
            // Reply from memory; never make a Watch request wait for a Librus login.
            if wantsSnapshot, let latest = self.latest {
                replyHandler([WatchSnapshot.contextKey: latest])
            } else { replyHandler([:]) }
        }
    }
}

struct PhoneWatchStatusView: View {
    @ObservedObject var sync: PhoneWatchSync

    var body: some View {
        Section("Apple Watch") {
            Toggle("Lesson-ending alerts", isOn: Binding(
                get: { sync.lessonAlertsEnabled }, set: sync.setLessonAlertsEnabled
            ))
            .accessibilityIdentifier("watchLessonAlertsToggle")
            Text("Notify your Watch 5 minutes before each lesson ends, with the next lesson, room and teacher. Open Librebus on Watch once to allow notifications. Focus and Watch notification settings control how alerts appear; the app cannot open itself.")
                .font(.footnote).foregroundStyle(.secondary)
            if sync.lessonAlertsEnabled {
                Text("Teacher names are included while alerts are enabled. Disabling takes effect when the Watch receives the update.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Label(sync.status, systemImage: "applewatch")
                .font(.subheadline)
            Button("Send latest data to Watch") { sync.sendLatest() }
            Text("Refresh school data on this iPhone first. Your Watch receives the timetable, recent grades and upcoming homework—not your password.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
#endif
