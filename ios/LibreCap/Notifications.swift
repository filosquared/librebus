import Foundation

#if os(iOS)
import UserNotifications
#endif

enum SchoolNotificationKind: String, Hashable {
    case grade
    case homework
    case absence
    case message
}

enum SchoolNotificationLanguage: String {
    case english = "en"
    case polish = "pl"
}

struct SchoolNotification: Hashable, Identifiable {
    let id: String
    let kind: SchoolNotificationKind
    let title: String
    let body: String
}

enum NotificationPermission: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
protocol LocalNotificationClient: AnyObject {
    func permission() async -> NotificationPermission
    func requestAuthorization() async -> Bool
    func schedule(_ notifications: [SchoolNotification]) async
    func clearLibreCapNotifications() async
}

enum SchoolNotificationPlanner {
    private static let maximumNotifications = 12

    static func newNotifications(
        from previous: CachedSchoolData,
        to current: CachedSchoolData,
        baselineEstablished: Bool,
        language: SchoolNotificationLanguage = .english
    ) -> [SchoolNotification] {
        guard baselineEstablished else { return [] }

        var result: [SchoolNotification] = []
        var seenIDs = Set<String>()

        for grade in current.grades where !previous.grades.contains(where: { $0.id == grade.id }) {
            let id = "grade-\(grade.id)"
            guard seenIDs.insert(id).inserted else { continue }
            result.append(SchoolNotification(
                id: id,
                kind: .grade,
                title: language == .polish ? "Nowa ocena" : "New grade",
                body: grade.subject.isEmpty ? grade.value : "\(grade.subject): \(grade.value)"
            ))
        }

        for homework in current.homeworks where !previous.homeworks.contains(where: { $0.id == homework.id }) {
            let id = "homework-\(homework.id)"
            guard seenIDs.insert(id).inserted else { continue }
            result.append(SchoolNotification(
                id: id,
                kind: .homework,
                title: language == .polish ? "Nowa praca domowa" : "New homework",
                body: homework.subject.isEmpty ? (language == .polish ? "Otwórz LibreCap, aby zobaczyć szczegóły." : "Open LibreCap to see the details.") : homework.subject
            ))
        }

        for attendance in current.attendances where !attendance.isPresence && !previous.attendances.contains(where: { $0.id == attendance.id }) {
            let id = "absence-\(attendance.id)"
            guard seenIDs.insert(id).inserted else { continue }
            result.append(SchoolNotification(
                id: id,
                kind: .absence,
                title: language == .polish ? "Nowa nieobecność" : "New absence",
                body: attendance.subject.isEmpty ? (language == .polish ? "Otwórz LibreCap, aby zobaczyć szczegóły." : "Open LibreCap to see the details.") : attendance.subject
            ))
        }

        for message in current.messages where !previous.messages.contains(where: { $0.id == message.id }) {
            let id = "message-\(message.id)"
            guard seenIDs.insert(id).inserted else { continue }
            let fallback = language == .polish ? "Nowa wiadomość w LibreCap." : "A new message is available in LibreCap."
            let body = message.subject.isEmpty ? fallback : message.subject
            result.append(SchoolNotification(
                id: id,
                kind: .message,
                title: language == .polish ? "Nowa wiadomość" : "New message",
                body: body
            ))
        }

        return Array(result.prefix(maximumNotifications))
    }
}

#if os(iOS)
@MainActor
final class SystemLocalNotificationClient: NSObject, LocalNotificationClient, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "librecap.school."

    override init() {
        super.init()
        center.delegate = self
    }

    func permission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional: return .authorized
        default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(_ notifications: [SchoolNotification]) async {
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.userInfo = [
                "kind": notification.kind.rawValue,
                "notificationID": notification.id,
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + notification.id,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func clearLibreCapNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.map(\.request.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
#else
@MainActor
final class SystemLocalNotificationClient: LocalNotificationClient {
    func permission() async -> NotificationPermission { .restricted }
    func requestAuthorization() async -> Bool { false }
    func schedule(_ notifications: [SchoolNotification]) async {}
    func clearLibreCapNotifications() async {}
}
#endif
