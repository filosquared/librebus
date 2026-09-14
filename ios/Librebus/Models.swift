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

enum MessageFolder: String, Codable, CaseIterable, Hashable, Identifiable {
    case inbox
    case sent
    case announcements
    case notes

    var id: String { rawValue }
}

struct TimetableData: Codable, Hashable {
    var nextWeek: Bool
    var days: [String: [TimetableLesson]]
    // Actual requested week; older caches decode this as nil.
    var weekStart: String? = nil
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
    var folder: MessageFolder

    init(id: String, sender: String, subject: String, date: String, folder: MessageFolder = .inbox) {
        self.id = id
        self.sender = sender
        self.subject = subject
        self.date = date
        self.folder = folder
    }

    private enum CodingKeys: String, CodingKey {
        case id, sender, subject, date, folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sender = try container.decode(String.self, forKey: .sender)
        subject = try container.decode(String.self, forKey: .subject)
        date = try container.decode(String.self, forKey: .date)
        folder = try container.decodeIfPresent(MessageFolder.self, forKey: .folder) ?? .inbox
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sender, forKey: .sender)
        try container.encode(subject, forKey: .subject)
        try container.encode(date, forKey: .date)
        try container.encode(folder, forKey: .folder)
    }
}

struct MessageDetail: Codable, Hashable {
    var subject: String
    var sender: String
    var date: String
    var content: String
}

struct SchoolNote: Codable, Hashable, Identifiable {
    var id: String
    var text: String
    var reminds: Bool
    var isNoLongerRelevant: Bool
    var updatedAt: Date
}

struct CachedSchoolData: Codable {
    var profile: StudentProfile?
    var grades: [GradeRecord]
    var timetable: TimetableData?
    var attendances: [AttendanceRecord]
    var homeworks: [HomeworkRecord]
    var messages: [MessageSummary]
    var lastSync: Date?
    var timetableUpdatedAt: Date? = nil
    var gradesUpdatedAt: Date? = nil
    var homeworksUpdatedAt: Date? = nil

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
