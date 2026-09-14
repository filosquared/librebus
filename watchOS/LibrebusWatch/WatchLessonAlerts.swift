import SwiftUI
import UserNotifications

enum LessonNotificationPermission { case notDetermined, denied, allowed }
struct PendingLessonAlert { var id: String; var reminder: LessonReminder? }

@MainActor
protocol LessonNotificationClient: AnyObject {
    var onOpen: ((LessonReminder) -> Void)? { get set }
    func permission() async -> LessonNotificationPermission
    func requestPermission() async throws -> Bool
    func pending() async -> [PendingLessonAlert]
    func removePending(_ ids: [String])
    func clearDelivered() async
    func add(_ reminder: LessonReminder) async throws
}

@MainActor
final class WatchLessonAlerts: ObservableObject {
    @Published private(set) var status = "Lesson alerts are off."
    @Published private(set) var needsPermission = false
    @Published private(set) var isRequestingPermission = false
    @Published var presentedReminder: LessonReminder?
    private let client: LessonNotificationClient?
    private let now: () -> Date
    private var snapshot: WatchSnapshot?
    private var generation = 0
    private var worker: Task<Void, Never>?
    private var clearDelivered = false

    init(client: LessonNotificationClient?, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
        client?.onOpen = { [weak self] reminder in
            guard let self, let snapshot = self.snapshot, snapshot.signedIn,
                  snapshot.lessonAlertsEnabled == true,
                  reminder.id.hasPrefix(LessonReminder.identifierPrefix + snapshot.accountID + ".") else { return }
            self.presentedReminder = reminder
        }
    }

    func update(_ snapshot: WatchSnapshot?) {
        if snapshot?.signedIn != true || snapshot?.lessonAlertsEnabled != true || self.snapshot?.accountID != snapshot?.accountID {
            clearDelivered = true
            presentedReminder = nil
        }
        self.snapshot = snapshot
        generation += 1
        guard worker == nil, client != nil else { return }
        // One worker serializes OS operations. An in-flight old add is removed by
        // the next pass if an off/sign-out/update arrives while awaiting it.
        worker = Task { await reconcile() }
    }

    func allowNotifications() async {
        guard let client, snapshot?.lessonAlertsEnabled == true, !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        do {
            _ = try await client.requestPermission()
            update(snapshot)
            await finishPendingUpdates()
        } catch { status = "Could not request permission. Try again on your Watch." }
    }

    func finishPendingUpdates() async { await worker?.value }

    private func reconcile() async {
        guard let client else { worker = nil; return }
        while true {
            let currentGeneration = generation
            let enabled = snapshot?.signedIn == true && snapshot?.lessonAlertsEnabled == true
            let permission = await client.permission()
            let pending = await client.pending()
            guard currentGeneration == generation else { continue }
            needsPermission = enabled && permission == .notDetermined
            let plan = enabled && permission == .allowed ? LessonReminderPlanner.reminders(for: snapshot, now: now()) : []
            let desiredIDs = Set(plan.map(\.id))
            client.removePending(pending.filter { !desiredIDs.contains($0.id) }.map(\.id))
            if clearDelivered {
                clearDelivered = false
                await client.clearDelivered()
            }
            guard currentGeneration == generation else { continue }
            var failed = false
            for reminder in plan {
                guard currentGeneration == generation else { break }
                if pending.contains(where: { $0.id == reminder.id && $0.reminder == reminder }) { continue }
                client.removePending([reminder.id])
                do { try await client.add(reminder) }
                catch { failed = true }
            }
            guard currentGeneration == generation else { continue }
            if !enabled { status = "Lesson alerts are off." }
            else if permission == .denied { status = "Notifications are blocked. Enable Librebus notifications in Watch settings." }
            else if needsPermission { status = "Allow notifications on this Watch to get lesson alerts." }
            else if failed { status = "Some alerts could not be scheduled. Open the Watch app to retry." }
            else if snapshot?.timetableIsComplete == false { status = "Timetable is incomplete. Refresh on iPhone before scheduling alerts." }
            else if plan.isEmpty { status = "No upcoming lesson alerts. Refresh the timetable on iPhone." }
            else { status = "\(plan.count) lesson alerts scheduled on this Watch. Focus may silence them." }
            worker = nil
            return
        }
    }
}

@MainActor
final class SystemLessonNotifications: NSObject, LessonNotificationClient, UNUserNotificationCenterDelegate {
    var onOpen: ((LessonReminder) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(identifier: LessonReminder.category, actions: [], intentIdentifiers: [])])
    }

    func permission() async -> LessonNotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional: return .allowed
        default: return .denied
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pending() async -> [PendingLessonAlert] {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(LessonReminder.identifierPrefix) }.map {
            PendingLessonAlert(id: $0.identifier, reminder: Self.reminder(from: $0.content))
        }
    }

    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }

    func clearDelivered() async {
        let ids = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(LessonReminder.identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func add(_ reminder: LessonReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = LessonReminder.category
        content.userInfo = [LessonReminder.payloadKey: try JSONEncoder().encode(reminder)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    nonisolated static func reminder(from content: UNNotificationContent) -> LessonReminder? {
        guard let data = content.userInfo[LessonReminder.payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(LessonReminder.self, from: data)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let reminder = Self.reminder(from: response.notification.request.content)
        Task { @MainActor in
            if let reminder { self.onOpen?(reminder) }
            completionHandler()
        }
    }
}
