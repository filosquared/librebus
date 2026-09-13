import Foundation

struct StudentProfile: Codable, Hashable {
    var firstName: String
    var lastName: String
    var tutorFirstName: String
    var tutorLastName: String
    var schoolYearStarts: String
    var schoolYearMiddles: String
    var schoolYearEnds: String
    var type: String
    var className: String

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var tutorName: String {
        "\(tutorFirstName) \(tutorLastName)"
    }
}

struct GradeRecord: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var value: String
    var weight: String
    var comment: String
    var category: String
    var isFinal: Bool
    var isSemester: Bool
    var semester: String
    var addedDate: String
    var teacher: String
}

struct TimetableLesson: Codable, Hashable, Identifiable {
    var id: String
    var lessonNumber: String
    var subject: String
    var isSubstitution: Bool
    var isCancelled: Bool
    var teacher: String
    var hourFrom: String
    var hourTo: String
    var classroom: String
}

struct TimetableData: Codable, Hashable {
    var nextWeek: Bool
    var days: [String: [TimetableLesson]]
}

struct AttendanceRecord: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var type: String
    var shortType: String
    var isPresence: Bool
    var addedDate: String
    var date: String
    var teacher: String
}

struct HomeworkRecord: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var addedBy: String
    var type: String
    var startTime: String
    var endTime: String
    var date: String
    var addedDate: String
    var content: String
}

struct MessageSummary: Codable, Hashable, Identifiable {
    var id: String
    var sender: String
    var subject: String
    var date: String
}

struct MessageDetail: Codable, Hashable {
    var subject: String
    var sender: String
    var date: String
    var content: String
}

struct CachedSchoolData: Codable {
    var profile: StudentProfile?
    var grades: [GradeRecord]
    var timetable: TimetableData?
    var attendances: [AttendanceRecord]
    var homeworks: [HomeworkRecord]
    var messages: [MessageSummary]
    var lastSync: Date?

    static let empty = CachedSchoolData(
        profile: nil,
        grades: [],
        timetable: nil,
        attendances: [],
        homeworks: [],
        messages: [],
        lastSync: nil
    )
}
