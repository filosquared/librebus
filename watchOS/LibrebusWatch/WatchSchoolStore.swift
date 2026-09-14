import SwiftUI
import WatchConnectivity

@MainActor
final class WatchSchoolStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var status = "Open Librebus on your iPhone to sync."
    @Published private(set) var isRequesting = false
    private let cache: WatchSnapshotCache
    let lessonAlerts: WatchLessonAlerts
    private var timeoutTask: Task<Void, Never>?
    private var requestID: UUID?
    private let connectsToPhone: Bool
    private let positionKey = "acceptedWatchSnapshotPosition"

    private var acceptedPosition: WatchSnapshotPosition? {
        guard let data = UserDefaults.standard.data(forKey: positionKey) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshotPosition.self, from: data)
    }

    init(preview: WatchSnapshot? = nil, connectsToPhone: Bool = true) {
        self.connectsToPhone = connectsToPhone
        self.cache = WatchSnapshotCache()
        self.lessonAlerts = WatchLessonAlerts(client: connectsToPhone ? SystemLessonNotifications() : nil)
        super.init()
        guard connectsToPhone else { snapshot = preview; return }
        do {
            let saved = try cache.load()
            // If a previous disk write failed, do not resurrect older account data.
            let mayLoad = acceptedPosition.map { accepted in
                saved?.position == accepted || saved?.position.isNewer(than: accepted) == true
            } ?? true
            if let saved, mayLoad {
                snapshot = saved
            }
        } catch { status = "Saved data unavailable. Open the iPhone app to sync again." }
        lessonAlerts.update(snapshot)
        guard WCSession.isSupported() else { status = "iPhone connection unavailable."; return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func requestLatest() {
        if connectsToPhone { lessonAlerts.update(snapshot) }
        guard connectsToPhone, WCSession.isSupported(), !isRequesting else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { status = "Connecting to iPhone…"; return }
        accept(session.receivedApplicationContext)
        guard session.isReachable else {
            status = snapshot?.signedIn == true
                ? "iPhone unavailable. Showing saved data. Open both apps to sync."
                : "Open Librebus on your iPhone to send school data."
            return
        }
        let id = UUID()
        requestID = id
        isRequesting = true
        status = "Asking iPhone for its latest saved data…"
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finishRequest(id, status: "No reply yet. Open Librebus on your iPhone and sync there.")
        }
        session.sendMessage([WatchSnapshot.requestKey: true], replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self else { return }
                if reply[WatchSnapshot.contextKey] == nil {
                    self.finishRequest(id, status: "Open Librebus on iPhone and refresh school data.")
                } else {
                    self.accept(reply)
                    self.finishRequest(id)
                }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.finishRequest(id, status: "iPhone unavailable. Open both apps and try again.") }
        })
    }

    private func finishRequest(_ id: UUID, status: String? = nil) {
        guard requestID == id else { return }
        requestID = nil
        isRequesting = false
        timeoutTask?.cancel()
        if let status { self.status = status }
    }

    @discardableResult
    private func accept(_ context: [String: Any]) -> Bool {
        guard let data = context[WatchSnapshot.contextKey] as? Data else { return false }
        do {
            let incoming = try WatchSnapshot.decode(data)
            if let accepted = acceptedPosition, incoming.position != accepted && !incoming.position.isNewer(than: accepted) {
                status = "Keeping the newer saved snapshot."
                return false
            }
            if let snapshot, incoming.position != snapshot.position && !incoming.isNewer(than: snapshot) {
                status = "Keeping the newer saved snapshot."
                return false
            }
            UserDefaults.standard.set(try JSONEncoder().encode(incoming.position), forKey: positionKey)
            // A sign-out snapshot replaces the cache with a data-free tombstone.
            snapshot = incoming
            lessonAlerts.update(incoming)
            try cache.save(incoming)
            requestID = nil
            isRequesting = false
            timeoutTask?.cancel()
            status = incoming.signedIn ? "Saved for offline use." : "Signed out on iPhone. Sign in there to reconnect."
            return true
        } catch WatchSnapshot.SnapshotError.unsupportedVersion {
            status = "Update Librebus on both your iPhone and Watch."
        } catch {
            status = "Could not save this update. Open the iPhone app and try again."
        }
        return false
    }

    // Keep the background task alive while WatchConnectivity drains its delivery queue.
    // Also read receivedApplicationContext so cold launches recover the last delivery.
    func handleBackgroundDelivery() async {
        guard connectsToPhone, WCSession.isSupported() else { return }
        let session = WCSession.default
        for _ in 0..<100 {
            guard !Task.isCancelled else { return }
            if session.activationState == .activated && !session.hasContentPending { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        accept(session.receivedApplicationContext)
        await lessonAlerts.finishPendingUpdates()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if error != nil { self.status = "Connection unavailable. Open both apps and try again." }
            else {
                self.accept(session.receivedApplicationContext)
                self.requestLatest()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.accept(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable { self.requestLatest() }
        }
    }
}
