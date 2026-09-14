#if os(iOS)
import SwiftUI
import WatchConnectivity

enum WatchSyncStatus: Equatable {
    case checking
    case unsupported
    case unavailable
    case notPaired
    case appMissing
    case prepareFailed
    case queued
    case queueFailed

    func text(using settings: AppSettings) -> String {
        switch self {
        case .checking: return settings.text(.watchChecking)
        case .unsupported: return settings.text(.watchUnsupported)
        case .unavailable: return settings.text(.watchUnavailable)
        case .notPaired: return settings.text(.watchNotPaired)
        case .appMissing: return settings.text(.watchAppMissing)
        case .prepareFailed: return settings.text(.watchPrepareFailed)
        case .queued: return settings.text(.watchQueued)
        case .queueFailed: return settings.text(.watchQueueFailed)
        }
    }
}

@MainActor
final class PhoneWatchSync: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status: WatchSyncStatus = .checking
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
            status = .unsupported
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
            status = .prepareFailed
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
        guard session.isPaired else { status = .notPaired; return }
        guard session.isWatchAppInstalled else { status = .appMissing; return }
        guard let latest else { return }
        do {
            // Latest-state transport works while the counterpart is unreachable.
            try session.updateApplicationContext([WatchSnapshot.contextKey: latest])
            status = .queued
        } catch {
            status = .queueFailed
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if error != nil { self.status = .unavailable }
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
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Section(settings.text(.appleWatch)) {
            Toggle(settings.text(.lessonAlerts), isOn: Binding(
                get: { sync.lessonAlertsEnabled }, set: sync.setLessonAlertsEnabled
            ))
            .accessibilityIdentifier("watchLessonAlertsToggle")
            Text(settings.text(.watchAlertDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if sync.lessonAlertsEnabled {
                Text(settings.text(.teacherNames))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Label(sync.status.text(using: settings), systemImage: "applewatch")
                .font(.subheadline)
                .lineLimit(2)
            Button(settings.text(.sendLatestToWatch)) { sync.sendLatest() }
                .buttonStyle(.borderless)
            Text(settings.text(.watchDataDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
#endif
