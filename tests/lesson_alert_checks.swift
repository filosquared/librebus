// Offline reminder and scheduler checks. No real notification center or credentials.
import Foundation

@MainActor final class FakeLessonNotifications: LessonNotificationClient {
    var onOpen: ((LessonReminder) -> Void)?
    var authorization = LessonNotificationPermission.allowed
    var queued: [String: LessonReminder] = [:]
    var addCount = 0
    var permissionRequests = 0
    var deliveredClearCount = 0
    var failAdd = false
    var pauseNextAdd = false
    var pausedAdd: CheckedContinuation<Void, Never>?

    func permission() async -> LessonNotificationPermission { authorization }
    func requestPermission() async throws -> Bool {
        permissionRequests += 1
        authorization = .allowed
        return true
    }
    func pending() async -> [PendingLessonAlert] { queued.map { PendingLessonAlert(id: $0.key, reminder: $0.value) } }
    func removePending(_ ids: [String]) { ids.forEach { queued.removeValue(forKey: $0) } }
    func clearDelivered() async { deliveredClearCount += 1 }
    func add(_ reminder: LessonReminder) async throws {
        if pauseNextAdd {
            pauseNextAdd = false
            await withCheckedContinuation { pausedAdd = $0 }
        }
        if failAdd { throw NSError(domain: "Fixture", code: 1) }
        addCount += 1
        queued[reminder.id] = reminder
    }
}

@main @MainActor struct LessonAlertChecks {
    static var count = 0
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        count += 1
    }

    static func lesson(_ id: String, day: Date, start: String, end: String, cancelled: Bool = false) -> WatchLesson {
        WatchLesson(id: id, subject: id, start: SchoolDate.time(start, on: day)!, end: SchoolDate.time(end, on: day)!,
                    classroom: "12", isCancelled: cancelled, isSubstitution: false, teacher: "Taylor Example")
    }

    static func main() async throws {
        let monday = SchoolDate.parse("2026-09-14")!
        let now = SchoolDate.time("08:00", on: monday)!
        var snapshot = WatchSnapshot(generatedAt: now, signedIn: true, accountID: "fixture-account",
                                     timetableUpdatedAt: now, weekStart: monday)
        snapshot.lessonAlertsEnabled = true
        snapshot.timetableIsComplete = true
        snapshot.lessons = [
            lesson("Science", day: monday, start: "08:15", end: "09:00"),
            lesson("Cancelled", day: monday, start: "09:10", end: "09:55", cancelled: true),
            lesson("Mathematics", day: monday, start: "10:05", end: "10:50"),
            lesson("Tomorrow", day: SchoolDate.parse("2026-09-15")!, start: "08:15", end: "09:00")
        ]
        let plan = LessonReminderPlanner.reminders(for: snapshot, now: now)
        check(plan.count == 3, "Cancelled lessons must not schedule alerts")
        check(plan[0].fireDate == SchoolDate.time("08:55", on: monday), "Alert exactly five minutes before lesson end")
        check(plan[0].nextLesson?.subject == "Mathematics", "Skip cancelled next lesson")
        check(plan[0].body == "Next lesson is Mathematics in room 12 with Taylor Example.", "Requested next lesson, room and teacher")
        check(plan[1].nextLesson == nil && plan[1].body == "No more lessons today.", "Do not call tomorrow's lesson the next lesson today")
        check(LessonReminderPlanner.reminders(for: snapshot, now: plan[0].fireDate).count == 2, "Never fire an old alert immediately on sync")
        check(LessonReminderPlanner.reminders(for: snapshot, now: SchoolDate.parse("2026-09-21")!).isEmpty, "No repeating stale week")
        check(try JSONDecoder().decode(LessonReminder.self, from: JSONEncoder().encode(plan[0])) == plan[0], "Notification payload round-trip")

        var changed = snapshot
        changed.lessons[2].teacher = nil
        changed.lessons[2].classroom = "—"
        let unknown = LessonReminderPlanner.reminders(for: changed, now: now)[0]
        check(unknown.body.contains("room unavailable") && unknown.body.contains("teacher unavailable"), "Never invent missing room or teacher")
        changed.lessons[2].teacher = "Replacement Teacher"
        changed.lessons[2].isSubstitution = true
        check(LessonReminderPlanner.reminders(for: changed, now: now)[0].nextLesson?.teacher == "Replacement Teacher", "Use updated substitution details")

        var disabled = snapshot
        disabled.lessonAlertsEnabled = false
        check(LessonReminderPlanner.reminders(for: disabled, now: now).isEmpty, "Disabled means no reminders")
        var signedOut = snapshot
        signedOut.signedIn = false
        check(LessonReminderPlanner.reminders(for: signedOut, now: now).isEmpty, "Signed out means no reminders")
        var incomplete = snapshot
        incomplete.timetableIsComplete = false
        check(LessonReminderPlanner.reminders(for: incomplete, now: now).isEmpty, "Don't infer a next lesson from a truncated timetable")
        incomplete = snapshot
        incomplete.timetableUpdatedAt = nil
        check(LessonReminderPlanner.reminders(for: incomplete, now: now).isEmpty, "Need a successfully synced timetable")
        incomplete = snapshot
        incomplete.weekStart = nil
        check(LessonReminderPlanner.reminders(for: incomplete, now: now).isEmpty, "Never guess which week")

        var short = snapshot
        short.lessons = [lesson("Short", day: monday, start: "08:15", end: "08:20")]
        check(LessonReminderPlanner.reminders(for: short, now: now).isEmpty, "Don't notify before/at start of a five-minute activity")
        var duplicates = snapshot
        duplicates.lessons += snapshot.lessons
        check(LessonReminderPlanner.reminders(for: duplicates, now: now).count == plan.count, "No duplicate alerts for duplicate lessons")
        var many = snapshot
        many.lessons = (0..<60).map { index in
            let start = now.addingTimeInterval(Double(index * 900 + 60))
            return WatchLesson(id: "\(index)", subject: "Fixture", start: start, end: start.addingTimeInterval(600),
                               classroom: "12", isCancelled: false, isSubstitution: false)
        }
        check(LessonReminderPlanner.reminders(for: many, now: now).count == 48, "Bound the OS notification queue")

        // Compatibility and opt-in teacher projection.
        var legacyJSON = try JSONSerialization.jsonObject(with: snapshot.encoded()) as! [String: Any]
        legacyJSON.removeValue(forKey: "lessonAlertsEnabled")
        legacyJSON.removeValue(forKey: "timetableIsComplete")
        var legacyLessons = legacyJSON["lessons"] as! [[String: Any]]
        for index in legacyLessons.indices { legacyLessons[index].removeValue(forKey: "teacher") }
        legacyJSON["lessons"] = legacyLessons
        let legacy = try WatchSnapshot.decode(JSONSerialization.data(withJSONObject: legacyJSON))
        check(legacy.lessons.count == 4 && legacy.lessons[0].teacher == nil, "Old Watch snapshots remain readable")
        check(LessonReminderPlanner.reminders(for: legacy, now: now).isEmpty, "Old snapshots default to alerts off")
        var school = CachedSchoolData.empty
        school.timetable = TimetableData(nextWeek: false, days: ["Monday": [TimetableLesson(id: "fixture", lessonNumber: "1",
            subject: "Science", isSubstitution: false, isCancelled: false, teacher: "Taylor Example", hourFrom: "08:15", hourTo: "09:00", classroom: "12")]], weekStart: "2026-09-14")
        school.timetableUpdatedAt = now
        check(WatchSnapshotBuilder.make(from: school, signedIn: true).lessons.first?.teacher == nil, "No teacher data when opt-in is off")
        check(WatchSnapshotBuilder.make(from: school, signedIn: true, lessonAlertsEnabled: true).lessons.first?.teacher == "Taylor Example", "Teacher data transferred with opt-in")
        check(WatchSnapshotBuilder.make(from: school, signedIn: false, lessonAlertsEnabled: true).lessonAlertsEnabled == false, "Sign-out tombstone disables alerts")

        let client = FakeLessonNotifications()
        let scheduler = WatchLessonAlerts(client: client, now: { now })
        scheduler.update(snapshot)
        await scheduler.finishPendingUpdates()
        check(client.queued.count == 3, "Schedules saved week locally")
        let adds = client.addCount
        scheduler.update(snapshot)
        await scheduler.finishPendingUpdates()
        check(client.addCount == adds, "Repeated sync must not reschedule identical alerts")
        scheduler.update(changed)
        await scheduler.finishPendingUpdates()
        check(client.queued[plan[0].id]?.nextLesson?.teacher == "Replacement Teacher", "Replace old notification body on changes")
        scheduler.update(disabled)
        await scheduler.finishPendingUpdates()
        check(client.queued.isEmpty && client.deliveredClearCount > 0, "Disabling clears pending and delivered alerts")
        scheduler.update(snapshot)
        await scheduler.finishPendingUpdates()
        scheduler.update(signedOut)
        await scheduler.finishPendingUpdates()
        check(client.queued.isEmpty, "Sign-out clears notifications")

        client.authorization = .denied
        scheduler.update(snapshot)
        await scheduler.finishPendingUpdates()
        check(client.queued.isEmpty && scheduler.status.contains("blocked"), "Denied permission is visible, not claimed as scheduled")
        client.authorization = .notDetermined
        scheduler.update(snapshot)
        await scheduler.finishPendingUpdates()
        check(scheduler.needsPermission && client.permissionRequests == 0, "No background permission prompts")
        await scheduler.allowNotifications()
        check(!scheduler.needsPermission && client.permissionRequests == 1 && client.queued.count == 3, "Explicit permission action schedules saved lessons")
        client.onOpen?(plan[0])
        check(scheduler.presentedReminder == plan[0], "Tapping opens the lesson card")
        scheduler.update(signedOut)
        await scheduler.finishPendingUpdates()
        client.onOpen?(plan[0])
        check(scheduler.presentedReminder == nil, "Don't reopen old account details after logout")

        // An old add is in flight when the setting is turned off.
        client.pauseNextAdd = true
        scheduler.update(snapshot)
        for _ in 0..<1000 {
            if client.pausedAdd != nil { break }
            await Task.yield()
        }
        check(client.pausedAdd != nil, "Race fixture suspended")
        scheduler.update(disabled)
        client.pausedAdd?.resume()
        client.pausedAdd = nil
        await scheduler.finishPendingUpdates()
        check(client.queued.isEmpty, "An old async add cannot undo disable")

        client.failAdd = true
        scheduler.update(snapshot)
        await scheduler.finishPendingUpdates()
        check(scheduler.status.contains("could not") && client.queued.isEmpty, "Surface scheduling failures")
        client.failAdd = false
        scheduler.update(snapshot)
        await scheduler.finishPendingUpdates()
        check(client.queued.count == 3, "Retry scheduling on next refresh")
        print("\(count) lesson reminder/scheduler checks passed (offline; fake notification center).")
    }
}
