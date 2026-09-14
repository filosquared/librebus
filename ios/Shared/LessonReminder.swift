import Foundation

struct LessonReminder: Codable, Equatable, Identifiable {
    static let category = "LIBREBUS_LESSON_ENDING"
    static let identifierPrefix = "librebus.lesson-ending."
    static let payloadKey = "lessonReminder"

    var id: String
    var fireDate: Date
    var lessonEndsAt: Date
    var currentSubject: String
    var nextLesson: WatchLesson?

    var title: String { "Lesson ending in 5 mins" }
    var body: String {
        guard let nextLesson else { return "No more lessons today." }
        let room = Self.available(nextLesson.classroom) ?? "unavailable"
        let teacher = Self.available(nextLesson.teacher) ?? "teacher unavailable"
        return "Next lesson is \(nextLesson.subject) in room \(room) with \(teacher)."
    }

    static func available(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "—" || trimmed == "-" ? nil : trimmed
    }
}

enum LessonReminderPlanner {
    // Leave space for other notification categories; never schedule an unbounded week.
    static let maximumReminders = 48

    static func reminders(for snapshot: WatchSnapshot?, now: Date = Date()) -> [LessonReminder] {
        guard let snapshot, snapshot.signedIn, snapshot.lessonAlertsEnabled == true,
              snapshot.timetableUpdatedAt != nil, snapshot.timetableIsComplete != false else { return [] }
        let lessons = snapshot.lessons.filter {
            !$0.isCancelled && snapshot.covers($0.start) && snapshot.covers($0.end.addingTimeInterval(-1))
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var seen = Set<String>()
        return Array(lessons.compactMap { current -> LessonReminder? in
            let fire = current.end.addingTimeInterval(-5 * 60)
            guard fire > now, fire > current.start else { return nil }
            let next = lessons.first {
                $0.start >= current.end && WatchSnapshot.schoolCalendar.isDate($0.start, inSameDayAs: current.start)
            }
            // Date-based, stable identifiers let a new timetable replace existing alerts.
            let id = LessonReminder.identifierPrefix + snapshot.accountID + "." + String(Int(current.end.timeIntervalSince1970))
            guard seen.insert(id).inserted else { return nil }
            return LessonReminder(id: id, fireDate: fire, lessonEndsAt: current.end,
                                  currentSubject: current.subject, nextLesson: next)
        }.sorted { $0.fireDate < $1.fireDate }.prefix(maximumReminders))
    }
}
