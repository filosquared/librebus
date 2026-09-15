import Foundation

@main struct NotificationChecks {
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    static func grade(_ id: String) -> GradeRecord {
        GradeRecord(id: id, subject: "Mathematics", value: "5", weight: "1", comment: "", category: "", isFinal: false, isSemester: false, semester: "", addedDate: "", teacher: "")
    }

    static func homework(_ id: String) -> HomeworkRecord {
        HomeworkRecord(id: id, subject: "English", addedBy: "", type: "Homework", startTime: "", endTime: "", date: "", addedDate: "", content: "")
    }

    static func attendance(_ id: String, isPresence: Bool) -> AttendanceRecord {
        AttendanceRecord(id: id, subject: "Physics", type: "Absent", shortType: "a", isPresence: isPresence, addedDate: "", date: "", teacher: "")
    }

    static func message(_ id: String) -> MessageSummary {
        MessageSummary(id: id, sender: "Teacher", subject: "Project", date: "")
    }

    static func main() {
        var previous = CachedSchoolData.empty
        previous.grades = [grade("existing-grade")]
        previous.homeworks = [homework("existing-homework")]
        previous.attendances = [attendance("existing-presence", isPresence: true)]
        previous.messages = [message("existing-message")]

        var current = previous
        current.grades.append(grade("new-grade"))
        current.homeworks.append(homework("new-homework"))
        current.attendances.append(attendance("new-presence", isPresence: true))
        current.attendances.append(attendance("new-absence", isPresence: false))
        current.messages.append(message("new-message"))

        check(SchoolNotificationPlanner.newNotifications(from: previous, to: current, baselineEstablished: false).isEmpty, "First sync establishes a baseline")
        let notifications = SchoolNotificationPlanner.newNotifications(from: previous, to: current, baselineEstablished: true)
        check(notifications.map(\.id) == ["grade-new-grade", "homework-new-homework", "absence-new-absence", "message-new-message"], "Only new meaningful records notify")
        check(notifications.first?.title == "New grade", "English notification copy")

        let polish = SchoolNotificationPlanner.newNotifications(from: previous, to: current, baselineEstablished: true, language: .polish)
        check(polish.first?.title == "Nowa ocena", "Polish notification copy")

        var many = current
        many.grades.append(contentsOf: (0..<20).map { grade("grade-\($0)") })
        check(SchoolNotificationPlanner.newNotifications(from: current, to: many, baselineEstablished: true).count == 12, "Notification queue is bounded")
        print("Notification planner checks passed (offline, synthetic data only).")
    }
}
