import Foundation

enum WatchSnapshotBuilder {
    static func make(from data: CachedSchoolData, signedIn: Bool, now: Date = Date(), lessonAlertsEnabled: Bool = false) -> WatchSnapshot {
        var snapshot = WatchSnapshot(generatedAt: now, signedIn: signedIn)
        snapshot.lessonAlertsEnabled = signedIn && lessonAlertsEnabled
        guard signedIn else { return snapshot }
        snapshot.firstName = clipped(data.profile?.firstName ?? "", to: 40)
        snapshot.timetableUpdatedAt = data.timetableUpdatedAt
        snapshot.gradesUpdatedAt = data.gradesUpdatedAt
        snapshot.homeworksUpdatedAt = data.homeworksUpdatedAt

        // Do not guess the week for legacy caches: wait for one successful phone refresh.
        if let timetable = data.timetable, let week = timetable.weekStart.flatMap(SchoolDate.parse) {
            snapshot.weekStart = week
            snapshot.timetableIsComplete = true
            let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            for (offset, name) in names.enumerated() {
                guard let day = WatchSnapshot.schoolCalendar.date(byAdding: .day, value: offset, to: week) else { continue }
                for (index, lesson) in (timetable.days[name] ?? []).prefix(20).enumerated() {
                    guard let start = SchoolDate.time(lesson.hourFrom, on: day),
                          let end = SchoolDate.time(lesson.hourTo, on: day), end > start else {
                        snapshot.timetableIsComplete = false
                        continue
                    }
                    snapshot.lessons.append(WatchLesson(
                        id: "\(offset)-\(index)", subject: clipped(lesson.subject, to: 80),
                        start: start, end: end, classroom: clipped(lesson.classroom, to: 30),
                        isCancelled: lesson.isCancelled, isSubstitution: lesson.isSubstitution,
                        teacher: lessonAlertsEnabled ? clipped(lesson.teacher, to: 80) : nil
                    ))
                }
                if (timetable.days[name]?.count ?? 0) > 20 {
                    snapshot.isTruncated = true
                    snapshot.timetableIsComplete = false
                }
            }
        }

        snapshot.grades = data.grades.sorted {
            if $0.addedDate != $1.addedDate { return $0.addedDate > $1.addedDate }
            return $0.id < $1.id
        }.prefix(20).enumerated().map { index, grade in
            WatchGrade(id: "grade-\(index)", subject: clipped(grade.subject, to: 80),
                       value: clipped(grade.value, to: 12), category: clipped(grade.category, to: 80),
                       date: clipped(grade.addedDate, to: 20))
        }
        let today = WatchSnapshot.schoolCalendar.startOfDay(for: now)
        let upcoming = data.homeworks.filter { (SchoolDate.parse($0.date) ?? .distantFuture) >= today }.sorted {
            let left = SchoolDate.parse($0.date) ?? .distantFuture
            let right = SchoolDate.parse($1.date) ?? .distantFuture
            return left == right ? $0.id < $1.id : left < right
        }
        snapshot.homeworks = upcoming.prefix(12).enumerated().map { index, homework in
            WatchHomework(id: "homework-\(index)", subject: clipped(homework.subject, to: 80),
                          type: clipped(homework.type, to: 60), dueDate: SchoolDate.parse(homework.date),
                          content: clipped(homework.content, to: 600))
        }
        snapshot.isTruncated = snapshot.isTruncated || data.grades.count > 20 || upcoming.count > 12

        // The actual UTF-8 byte size matters (including emoji and JSON escaping).
        // Keep a margin for WatchConnectivity's property-list envelope.
        while ((try? snapshot.encoded().count) ?? Int.max) > WatchSnapshot.maxPayloadBytes - 512 {
            snapshot.isTruncated = true
            if !snapshot.homeworks.isEmpty { snapshot.homeworks.removeLast() }
            else if !snapshot.grades.isEmpty { snapshot.grades.removeLast() }
            else if !snapshot.lessons.isEmpty {
                snapshot.lessons.removeLast()
                snapshot.timetableIsComplete = false
            }
            else { break }
        }
        return snapshot
    }

    private static func clipped(_ value: String, to limit: Int) -> String {
        let scalars = value.unicodeScalars
        return scalars.count > limit ? String(String.UnicodeScalarView(scalars.prefix(limit))) + "…" : value
    }
}
