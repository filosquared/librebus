import SwiftUI
import WatchKit
import UserNotifications

struct LessonReminderView: View {
    let reminder: LessonReminder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Lesson ending", systemImage: "bell.badge.fill")
                .font(.caption).foregroundStyle(.orange)
            Text(Date() < reminder.lessonEndsAt ? "Lesson ending in 5 mins" : "Lesson ended")
                .font(.headline)
            if let lesson = reminder.nextLesson {
                Text("Next lesson").font(.caption2).foregroundStyle(.secondary)
                Text(lesson.subject).font(.title3.bold())
                Label("Room \(LessonReminder.available(lesson.classroom) ?? "unavailable")", systemImage: "door.left.hand.open")
                Label(LessonReminder.available(lesson.teacher) ?? "Teacher unavailable", systemImage: "person.fill")
                Text(lesson.start, style: .time).font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No more lessons today.")
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.timeZone, WatchSnapshot.schoolCalendar.timeZone)
    }
}

final class LessonNotificationController: WKUserNotificationHostingController<LessonNotificationView> {
    private var reminder: LessonReminder?

    override var body: LessonNotificationView { LessonNotificationView(reminder: reminder) }

    override func didReceive(_ notification: UNNotification) {
        reminder = SystemLessonNotifications.reminder(from: notification.request.content)
    }
}

struct LessonNotificationView: View {
    let reminder: LessonReminder?
    var body: some View {
        if let reminder { LessonReminderView(reminder: reminder) }
        else { Text("Open LibreCap for your next lesson.") }
    }
}

struct WatchLessonAlertsSection: View {
    @ObservedObject var alerts: WatchLessonAlerts

    var body: some View {
        Section("Lesson alerts") {
            Text(alerts.status).font(.footnote).foregroundStyle(.secondary)
            if alerts.needsPermission {
                Button(alerts.isRequestingPermission ? "Requesting…" : "Allow notifications") {
                    Task { await alerts.allowNotifications() }
                }
                .disabled(alerts.isRequestingPermission)
            }
        }
        .sheet(item: $alerts.presentedReminder) { reminder in
            ScrollView { LessonReminderView(reminder: reminder).padding(.horizontal) }
        }
    }
}

#Preview("Lesson ending — synthetic") {
    LessonReminderView(reminder: LessonReminder(id: "fixture", fireDate: .now, lessonEndsAt: .now.addingTimeInterval(300),
        currentSubject: "Science", nextLesson: WatchLesson(id: "fixture-next", subject: "Mathematics",
        start: .now.addingTimeInterval(900), end: .now.addingTimeInterval(3600), classroom: "12",
        isCancelled: false, isSubstitution: false, teacher: "Alex Example")))
}
